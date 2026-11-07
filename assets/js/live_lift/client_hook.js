const SAFE_KEY = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
const RESERVED_KEYS = new Set(["__proto__", "constructor", "prototype"]);
const MAX_LIST_LENGTH = 10_000;
const MAX_MAP_FIELDS = 1_024;
const MAX_STATE_NODES = 50_000;
const MAX_STATE_BYTES = 1_048_576;
const MAX_EVENT_FIELDS = 64;
const MAX_EVENT_BYTES = 65_536;
const encoder = new TextEncoder();
const decodedEntities = new Map();

function decodeEntities(value) {
  if (!decodedEntities.has(value)) {
    const decoder = document.createElement("span");
    // Input is a compile-time literal template; dynamic values never use innerHTML.
    decoder.innerHTML = value;
    decodedEntities.set(value, decoder.textContent);
  }
  return decodedEntities.get(value);
}

function charge(budget, nodes, bytes, path) {
  budget.nodes += nodes;
  budget.bytes += bytes;
  if (budget.nodes > MAX_STATE_NODES || budget.bytes > MAX_STATE_BYTES) {
    throw new Error(`LiveLift state size limit exceeded at ${path}`);
  }
}

function validateValue(value, path, depth, budget) {
  if (typeof value === "string") {
    charge(budget, 1, encoder.encode(value).length, path);
    return;
  }
  if (typeof value === "boolean" || value === null || Number.isSafeInteger(value)) {
    charge(budget, 1, 0, path);
    return;
  }
  if (depth >= 16) throw new Error(`Unsupported LiveLift state value at ${path}`);
  if (Array.isArray(value)) {
    if (value.length > MAX_LIST_LENGTH) throw new Error(`LiveLift list length limit exceeded at ${path}`);
    charge(budget, 1, 0, path);
    value.forEach((item, index) => validateValue(item, `${path}[${index}]`, depth + 1, budget));
    return;
  }
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    const entries = Object.entries(value);
    if (entries.length > MAX_MAP_FIELDS) throw new Error(`LiveLift map field limit exceeded at ${path}`);
    charge(budget, 1, 0, path);
    for (const [key, item] of entries) {
      if (!SAFE_KEY.test(key) || RESERVED_KEYS.has(key)) {
        throw new Error(`Unsafe LiveLift state key at ${path}: ${key}`);
      }
      charge(budget, 0, encoder.encode(key).length, path);
      validateValue(item, `${path}.${key}`, depth + 1, budget);
    }
    return;
  }
  throw new Error(`Unsupported LiveLift state value at ${path}`);
}

function validateState(state) {
  if (!state || typeof state !== "object" || Array.isArray(state)) {
    throw new Error("LiveLift state must be a map");
  }
  validateValue(state, "state", 0, {nodes: 0, bytes: 0});
}

function sameValue(left, right) {
  if (Object.is(left, right)) return true;
  if (!left || !right || typeof left !== "object" || typeof right !== "object") return false;
  if (Array.isArray(left) !== Array.isArray(right)) return false;
  if (Array.isArray(left)) {
    return left.length === right.length && left.every((item, index) => sameValue(item, right[index]));
  }
  const keys = Object.keys(left);
  return keys.length === Object.keys(right).length &&
    keys.every((key) => Object.hasOwn(right, key) && sameValue(left[key], right[key]));
}

function evaluate(expr, scope) {
  if (expr.type === "literal") return expr.value;
  if (expr.type === "map") {
    return Object.fromEntries(expr.entries.map(({key, expr: value}) => [key, evaluate(value, scope)]));
  }
  if (expr.type === "path") {
    let value;
    let fields = expr.fields;
    if (expr.root === "state" && fields.length && Object.hasOwn(scope, fields[0])) {
      value = scope[fields[0]];
      fields = fields.slice(1);
    } else {
      if (!Object.hasOwn(scope, expr.root)) throw new Error(`Missing client scope: ${expr.root}`);
      value = scope[expr.root];
    }
    for (const field of fields) {
      if (!value || typeof value !== "object" || !Object.hasOwn(value, field)) {
        throw new Error(`Missing client field: ${field}`);
      }
      value = value[field];
    }
    return value;
  }
  throw new Error(`Unsupported client expression: ${expr.type}`);
}

function display(value) {
  if (value === null) return "";
  if (["string", "number", "boolean"].includes(typeof value)) return String(value);
  throw new Error("Cannot display a client collection directly");
}

function pathLabel(expr) {
  if (expr.type !== "path") return "expression";
  return (expr.root === "state" ? expr.fields : [expr.root, ...expr.fields]).join(".");
}

function flatFormParams(form) {
  const params = Object.create(null);
  for (const [key, value] of new FormData(form)) {
    if (Object.hasOwn(params, key)) throw new Error(`Duplicate LiveLift form parameter: ${key}`);
    if (typeof value !== "string") throw new Error(`Unsupported LiveLift form value: ${key}`);
    params[key] = value;
  }
  return params;
}

function renderNodes(nodes, scope, views, stack = [], textOnly = false) {
  return nodes.flatMap((node) => renderNode(node, scope, views, stack, textOnly));
}

function renderNode(node, scope, views, stack, textOnly) {
  if (node.type === "text") {
    return [document.createTextNode(decodeEntities(node.value))];
  }
  if (node.type === "binding") {
    if (textOnly) return [document.createTextNode(display(evaluate(node.expr, scope)))];
    return [document.createComment("live-lift:text"),
      document.createTextNode(display(evaluate(node.expr, scope))),
      document.createComment("live-lift:end")];
  }
  if (node.type === "component") {
    if (stack.includes(node.module)) throw new Error(`Recursive LiveLift client component: ${node.module}`);
    const component = views[node.module];
    if (!component || component.component !== true) throw new Error(`Unknown LiveLift client component: ${node.module}`);
    const props = Object.fromEntries(node.props.map((prop) => [prop.name, evaluate(prop.expr, scope)]));
    validateState(props);
    return renderNodes(component.template, {state: props}, views, [...stack, node.module]);
  }
  if (node.type !== "element") throw new Error(`Unsupported client node: ${node.type}`);

  if (node.for) {
    const items = evaluate(node.for.source, scope);
    if (!Array.isArray(items)) throw new Error(":for expects a list");
    const keys = new Set();
    return items.flatMap((item) => {
      const itemScope = {...scope, [node.for.var]: item};
      const key = evaluate(node.key, itemScope);
      if (typeof key !== "string" && !Number.isSafeInteger(key)) throw new Error(":key must be a string or safe integer");
      const keyString = String(key);
      if (keys.has(keyString)) throw new Error(`Duplicate client list key: ${key}`);
      keys.add(keyString);
      return renderElement(node, itemScope, key, views, stack);
    });
  }
  return renderElement(node, scope, null, views, stack);
}

function renderElement(node, scope, key, views, stack) {
  if (node.if && [false, null].includes(evaluate(node.if, scope))) return [];
  const element = document.createElement(node.tag);
  for (const attr of node.attrs) {
    if (attr.name === "data-live-lift-show") {
      element.setAttribute(attr.name, attr.value);
      const value = evaluate({type: "path", root: "state", fields: [attr.value]}, scope);
      element.hidden = value === false || value === null;
    } else if (attr.type === "dynamic") {
      element.setAttribute(attr.name, display(evaluate(attr.value, scope)));
      element.setAttribute(`data-live-lift-bind-${attr.name}`, pathLabel(attr.value));
    } else if (attr.type === "params") {
      element.setAttribute("data-live-lift-params", JSON.stringify(evaluate(attr.value, scope)));
    } else if (attr.type === "boolean") {
      const value = evaluate(attr.value, scope);
      if (value !== true && value !== false && value !== null) throw new Error(`${attr.name} requires a boolean or null`);
      element.toggleAttribute(attr.name, value === true);
      element[attr.name] = value === true;
    } else {
      element.setAttribute(attr.name, decodeEntities(attr.value));
    }
  }
  if (key !== null) element.setAttribute("data-live-lift-key", String(key));
  if (node.node_id !== null) element.setAttribute("data-live-lift-node-id", node.node_id);
  element.append(...renderNodes(node.children, scope, views, stack, node.tag === "textarea"));
  return [element];
}

function reconcile(parent, desired) {
  const previous = [...parent.childNodes];
  const used = new Set();
  const keyed = new Map();
  const identified = new Map();
  const unmarked = [];
  for (const node of previous) {
    if (node.nodeType !== 1) { unmarked.push(node); continue; }
    const key = node.getAttribute("data-live-lift-key");
    const id = node.getAttribute("data-live-lift-node-id");
    if (key !== null) keyed.set(`${node.tagName}:${id}:${key}`, node);
    else if (id !== null) identified.set(`${node.tagName}:${id}`, node);
    else unmarked.push(node);
  }
  desired.forEach((next, index) => {
    const key = next.nodeType === 1 ? next.getAttribute("data-live-lift-key") : null;
    const nodeId = next.nodeType === 1 ? next.getAttribute("data-live-lift-node-id") : null;
    const indexed = previous[index];
    const matchesUnmarked = (node) => node && !used.has(node) &&
      (node.nodeType !== 1 || (!node.hasAttribute("data-live-lift-key") && !node.hasAttribute("data-live-lift-node-id"))) &&
      node.nodeType === next.nodeType && (node.nodeType !== 1 || node.tagName === next.tagName);
    const current = key !== null
      ? keyed.get(`${next.tagName}:${nodeId}:${key}`)
      : nodeId !== null
        ? identified.get(`${next.tagName}:${nodeId}`)
        : matchesUnmarked(indexed) ? indexed : unmarked.find(matchesUnmarked);
    const chosen = current || next;
    if (current) patchNode(current, next);
    used.add(chosen);
    if (parent.childNodes[index] !== chosen) parent.insertBefore(chosen, parent.childNodes[index] || null);
  });
  previous.forEach((node) => { if (!used.has(node)) node.remove(); });
}

function patchNode(current, next) {
  if (current.nodeType === 3 || current.nodeType === 8) {
    if (current.nodeValue !== next.nodeValue) current.nodeValue = next.nodeValue;
    return;
  }
  for (const attr of [...current.attributes]) {
    // The component CID belongs to LiveView and is supplied by its original ~H render.
    if (attr.name === "phx-target") continue;
    if (!next.hasAttribute(attr.name)) current.removeAttribute(attr.name);
  }
  for (const attr of [...next.attributes]) {
    if (current.getAttribute(attr.name) !== attr.value) current.setAttribute(attr.name, attr.value);
  }
  if (current.tagName === "INPUT" && next.hasAttribute("value") && current.value !== next.value) {
    current.value = next.value;
  }
  if (current.tagName === "INPUT" && current.checked !== next.checked) current.checked = next.checked;
  if (current.tagName === "OPTION" && current.selected !== next.selected) current.selected = next.selected;
  if (current.hidden !== next.hidden) current.hidden = next.hidden;
  reconcile(current, [...next.childNodes]);
  if ((current.tagName === "SELECT" || current.tagName === "TEXTAREA") && current.value !== next.value) {
    current.value = next.value;
  }
}

/**
 * Runs user-defined client actions in a LiveView-owned page.
 * The app supplies its own HEEx and marks only the locally owned DOM subtree.
 */
export function createClientHook(views) {
  return {
    mounted() {
      this.view = views[this.el.dataset.liveLiftModule];
      if (!this.view) {
        throw new Error(`Unknown LiveLift view: ${this.el.dataset.liveLiftModule}`);
      }

      this.state = JSON.parse(this.el.dataset.liveLiftState);
      validateState(this.state);
      const serverRendered = this.el.hasChildNodes();
      this.serverFields = new Set(JSON.parse(this.el.dataset.liveLiftServerFields || "[]"));
      for (const field of this.serverFields) {
        if (!Object.hasOwn(this.state, field)) throw new Error(`Missing server-owned field: ${field}`);
      }
      this.serverRevision = Number(this.el.dataset.liveLiftServerRevision || "0");
      if (!Number.isSafeInteger(this.serverRevision) || this.serverRevision < 0) {
        throw new Error("Invalid LiveLift server revision");
      }
      this.optimistic = this.el.dataset.liveLiftMode === "component";
      if (this.optimistic) {
        this.authoritativeState = this.state;
        this.pending = [];
        this.nextSequence = Number(this.el.dataset.liveLiftAckSeq || "0") + 1;
        if (!Number.isSafeInteger(this.nextSequence) || this.nextSequence < 1) {
          throw new Error("Invalid LiveLift event sequence");
        }
        this.connectionEpoch = 0;
        this.reconnectPending = false;
        this.resetOptimisticSnapshot = () => {
          const snapshot = JSON.parse(this.el.dataset.liveLiftState);
          const revision = Number(this.el.dataset.liveLiftServerRevision || "0");
          if (!Number.isSafeInteger(revision) || revision < 0) throw new Error("Invalid LiveLift server revision");
          const nextSequence = Math.max(this.nextSequence, Number(this.el.dataset.liveLiftAckSeq || "0") + 1);
          if (!Number.isSafeInteger(nextSequence) || nextSequence < 1) throw new Error("Invalid LiveLift event sequence");
          validateState(snapshot);
          this.render(snapshot);
          this.pending = [];
          this.authoritativeState = snapshot;
          this.serverRevision = revision;
          this.nextSequence = nextSequence;
          this.state = snapshot;
          this.reconnectPending = false;
        };
        this.applyAuthoritative = (revision, state, ackSequence = 0) => {
          if (!Number.isSafeInteger(revision) || revision < 0) {
            throw new Error("Invalid LiveLift server revision");
          }
          if (!Number.isSafeInteger(ackSequence) || ackSequence < 0) {
            throw new Error("Invalid LiveLift acknowledged sequence");
          }
          if (ackSequence >= this.nextSequence) {
            throw new Error("LiveLift acknowledged an unsent action");
          }
          validateState(state);

          const reset = this.reconnectPending;
          const nextRevision = reset || revision > this.serverRevision ? revision : this.serverRevision;
          const nextBase = reset || revision > this.serverRevision ? state : this.authoritativeState;
          const nextPending = (reset ? [] : this.pending).filter(({sequence}) => sequence > ackSequence);
          let nextState = nextBase;
          for (const {action, eventData} of nextPending) {
            nextState = this.view.actions[action](nextState, eventData);
            validateState(nextState);
          }
          if (!sameValue(nextState, this.state)) this.render(nextState);
          this.authoritativeState = nextBase;
          this.serverRevision = nextRevision;
          this.pending = nextPending;
          this.state = nextState;
          this.reconnectPending = false;
        };
      }
      this.applyServerPatch = (revision, patch) => {
        if (!Number.isSafeInteger(revision) || revision <= this.serverRevision) return;
        if (!patch || typeof patch !== "object" || Array.isArray(patch)) throw new Error("Invalid LiveLift server patch");
        for (const field of Object.keys(patch)) {
          if (!this.serverFields.has(field)) throw new Error(`Server cannot patch client-owned field: ${field}`);
        }
        const nextState = {...this.state, ...patch};
        validateState(nextState);
        if (!sameValue(nextState, this.state)) this.render(nextState);
        this.state = nextState;
        this.serverRevision = revision;
      };
      if (this.serverFields.size && typeof this.handleEvent === "function") {
        this.syncRef = this.handleEvent("live_lift:patch", ({id, revision, patch}) => {
          if (id === this.el.id) this.applyServerPatch(revision, patch);
        });
      }
      if (!this.el.hasChildNodes() && typeof this.view.template === "string") {
        // Legacy string templates are generated from app-owned literals, never client state.
        this.el.innerHTML = this.view.template;
      }

      this.onClick = (event) => {
        const control = event.target.closest(
          "[data-live-lift-action], [data-live-lift-server]",
        );
        if (!control || !this.el.contains(control)) return;

        const serverEvent = control.dataset.liveLiftServer;
        if (serverEvent) {
          const state = Object.fromEntries(Object.entries(this.state).filter(([key]) => !this.serverFields.has(key)));
          this.pushEvent(serverEvent, {state, revision: this.serverRevision});
          return;
        }

        this.runAction(control.dataset.liveLiftAction, control);
      };

      this.runAction = (actionName, control, paramsOverride = null) => {
        const actions = this.view.actions;
        const action = Object.hasOwn(actions, actionName) ? actions[actionName] : undefined;
        if (typeof action !== "function") {
          throw new Error(`Unknown LiveLift action: ${actionName}`);
        }

        const eventData = {
          value: "value" in control ? control.value : null,
          checked: "checked" in control ? control.checked : false,
          params: paramsOverride || (control.dataset.liveLiftParams ? JSON.parse(control.dataset.liveLiftParams) : {}),
        };
        const actionState = action(this.state, eventData);
        validateState(actionState);
        for (const field of this.serverFields) {
          if (Object.hasOwn(actionState, field) && !Object.is(actionState[field], this.state[field])) {
            throw new Error(`Client action cannot change server-owned field: ${field}`);
          }
        }
        const nextState = {...actionState};
        for (const field of this.serverFields) nextState[field] = this.state[field];
        if (!sameValue(nextState, this.state)) this.render(nextState);
        this.state = nextState;
        return eventData;
      };

      this.sendOptimistic = (control, eventName, params) => {
        if (this.pending.length >= 100) throw new Error("LiveLift pending action limit reached");
        if (!Number.isSafeInteger(this.nextSequence)) throw new Error("LiveLift event sequence overflow");
        const entries = Object.entries(params);
        if (entries.length > MAX_EVENT_FIELDS) throw new Error("LiveLift event parameter limit exceeded");
        let bytes = 0;
        for (const [key, value] of entries) {
          if (!SAFE_KEY.test(key) || RESERVED_KEYS.has(key) || key === "_live_lift_seq") {
            throw new Error(`Unsafe LiveLift event parameter: ${key}`);
          }
          if (typeof value !== "string") throw new Error(`Unsupported LiveLift event parameter: ${key}`);
          bytes += encoder.encode(key).length + encoder.encode(value).length;
          if (bytes > MAX_EVENT_BYTES) throw new Error("LiveLift event parameter size limit exceeded");
        }
        const sequence = this.nextSequence;
        const eventData = this.runAction(eventName, control, params);
        this.nextSequence += 1;
        this.pending.push({sequence, action: eventName, eventData});
        const payload = {...params, _live_lift_seq: sequence};
        const epoch = this.connectionEpoch;
        this.pushEventTo(control, eventName, payload, (reply) => {
          if (epoch !== this.connectionEpoch) return;
          if (reply.disabled) {
            window.location.reload();
            return;
          }
          this.applyAuthoritative(reply.revision, reply.state, reply.ack_seq);
        });
      };

      this.onOptimisticClick = (event) => {
        if (!this.optimistic) return;
        const control = event.target.closest("[phx-click]");
        if (!control || !this.el.contains(control)) return;
        const eventName = control.getAttribute("phx-click");
        if (!Object.hasOwn(this.view.actions, eventName)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        const params = Object.create(null);
        for (const attr of control.attributes) {
          if (attr.name.startsWith("phx-value-")) {
            const key = attr.name.slice(10);
            if (!SAFE_KEY.test(key) || RESERVED_KEYS.has(key) || key === "_live_lift_seq") {
              throw new Error(`Unsafe LiveLift event parameter: ${key}`);
            }
            params[key] = attr.value;
          }
        }
        this.sendOptimistic(control, eventName, params);
      };

      this.onOptimisticChange = (event) => {
        if (!this.optimistic) return;
        const control = event.target.closest("[phx-change]");
        if (!control || !this.el.contains(control)) return;
        if (event.type === "change" && event.target.matches('input:not([type="checkbox"]):not([type="radio"]), textarea')) return;
        if (event.type === "input" && event.target.matches('select, input[type="checkbox"], input[type="radio"]')) return;
        const eventName = control.getAttribute("phx-change");
        if (!Object.hasOwn(this.view.actions, eventName)) return;
        event.stopImmediatePropagation();
        const params = control.tagName === "FORM"
          ? flatFormParams(control)
          : {value: control.value, ...(control.name ? {[control.name]: control.value} : {})};
        this.sendOptimistic(control, eventName, params);
      };

      this.onOptimisticSubmit = (event) => {
        if (!this.optimistic) return;
        const form = event.target.closest("form[phx-submit]");
        if (!form || !this.el.contains(form)) return;
        const eventName = form.getAttribute("phx-submit");
        if (!Object.hasOwn(this.view.actions, eventName)) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        this.sendOptimistic(form, eventName, flatFormParams(form));
      };

      this.onInput = (event) => {
        const control = event.target.closest("[data-live-lift-input]");
        if (control && this.el.contains(control)) this.runAction(control.dataset.liveLiftInput, control);
      };

      this.onChange = (event) => {
        const control = event.target.closest("[data-live-lift-change]");
        if (control && this.el.contains(control)) this.runAction(control.dataset.liveLiftChange, control);
      };

      this.onSubmit = (event) => {
        const control = event.target.closest("[data-live-lift-submit]");
        if (!control || !this.el.contains(control)) return;
        event.preventDefault();
        this.runAction(control.dataset.liveLiftSubmit, control);
      };

      if (this.optimistic) {
        this.el.addEventListener("click", this.onOptimisticClick, true);
        this.el.addEventListener("input", this.onOptimisticChange, true);
        this.el.addEventListener("change", this.onOptimisticChange, true);
        this.el.addEventListener("submit", this.onOptimisticSubmit, true);
      } else {
        this.el.addEventListener("click", this.onClick);
      }
      this.el.addEventListener("input", this.onInput);
      this.el.addEventListener("change", this.onChange);
      this.el.addEventListener("submit", this.onSubmit);
      if (!serverRendered) this.render();
    },

    destroyed() {
      if (this.syncRef && typeof this.removeHandleEvent === "function") this.removeHandleEvent(this.syncRef);
      if (this.optimistic) {
        this.el.removeEventListener("click", this.onOptimisticClick, true);
        this.el.removeEventListener("input", this.onOptimisticChange, true);
        this.el.removeEventListener("change", this.onOptimisticChange, true);
        this.el.removeEventListener("submit", this.onOptimisticSubmit, true);
      }
      this.el.removeEventListener("click", this.onClick);
      this.el.removeEventListener("input", this.onInput);
      this.el.removeEventListener("change", this.onChange);
      this.el.removeEventListener("submit", this.onSubmit);
    },

    disconnected() {
      if (this.optimistic) {
        this.connectionEpoch += 1;
        this.reconnectPending = true;
      }
    },

    updated() {
      if (this.optimistic) {
        if (this.reconnectPending) {
          this.resetOptimisticSnapshot();
          return;
        }
        const revision = Number(this.el.dataset.liveLiftServerRevision);
        if (Number.isSafeInteger(revision) && revision >= this.serverRevision) {
          this.applyAuthoritative(
            revision,
            JSON.parse(this.el.dataset.liveLiftState),
            Number(this.el.dataset.liveLiftAckSeq || "0"),
          );
        }
        return;
      }
      if (!this.serverFields.size) return;
      const revision = Number(this.el.dataset.liveLiftServerRevision);
      if (!Number.isSafeInteger(revision) || revision <= this.serverRevision) return;
      const serverState = JSON.parse(this.el.dataset.liveLiftState);
      validateState(serverState);
      const patch = {};
      for (const field of this.serverFields) {
        if (!Object.hasOwn(serverState, field)) throw new Error(`Missing server-owned field: ${field}`);
        patch[field] = serverState[field];
      }
      this.applyServerPatch(revision, patch);
    },

    render(state = this.state) {
      if (Array.isArray(this.view.template) && typeof document !== "undefined") {
        const focused = this.el.contains(document.activeElement) ? document.activeElement : null;
        const selection = focused && typeof focused.selectionStart === "number"
          ? [focused.selectionStart, focused.selectionEnd] : null;
        reconcile(this.el, renderNodes(this.view.template, {state}, views));
        if (focused && focused.isConnected && document.activeElement !== focused) {
          focused.focus({preventScroll: true});
          if (selection && typeof focused.setSelectionRange === "function") {
            focused.setSelectionRange(...selection);
          }
        }
        return;
      }

      const updates = [];
      for (const node of this.el.querySelectorAll("[data-live-lift-text]")) {
        const field = node.dataset.liveLiftText;
        if (!Object.hasOwn(state, field)) {
          throw new Error(`Unknown LiveLift state field: ${field}`);
        }
        const value = display(state[field]);
        updates.push(() => { node.textContent = value; });
      }

      for (const attribute of ["class", "title", "aria-label", "value"]) {
        for (const node of this.el.querySelectorAll(`[data-live-lift-bind-${attribute}]`)) {
          const field = node.getAttribute(`data-live-lift-bind-${attribute}`);
          if (!Object.hasOwn(state, field)) {
            throw new Error(`Unknown LiveLift state field: ${field}`);
          }
          const value = display(state[field]);
          updates.push(() => node.setAttribute(attribute, value));
        }
      }

      for (const node of this.el.querySelectorAll("[data-live-lift-show]")) {
        const field = node.dataset.liveLiftShow;
        if (!Object.hasOwn(state, field)) {
          throw new Error(`Unknown LiveLift state field: ${field}`);
        }
        const hidden = state[field] === false || state[field] === null;
        updates.push(() => { node.hidden = hidden; });
      }
      updates.forEach((apply) => apply());
    },
  };
}
