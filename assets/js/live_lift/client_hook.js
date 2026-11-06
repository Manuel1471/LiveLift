const SAFE_KEY = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
const RESERVED_KEYS = new Set(["__proto__", "constructor", "prototype"]);
const decodedText = new Map();

function validateValue(value, path, depth = 0) {
  if (typeof value === "string" || typeof value === "boolean" || value === null ||
      Number.isSafeInteger(value)) return;
  if (depth >= 16) throw new Error(`Unsupported LiveLift state value at ${path}`);
  if (Array.isArray(value)) {
    value.forEach((item, index) => validateValue(item, `${path}[${index}]`, depth + 1));
    return;
  }
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    for (const [key, item] of Object.entries(value)) {
      if (!SAFE_KEY.test(key) || RESERVED_KEYS.has(key)) {
        throw new Error(`Unsafe LiveLift state key at ${path}: ${key}`);
      }
      validateValue(item, `${path}.${key}`, depth + 1);
    }
    return;
  }
  throw new Error(`Unsupported LiveLift state value at ${path}`);
}

function validateState(state) {
  if (!state || typeof state !== "object" || Array.isArray(state)) {
    throw new Error("LiveLift state must be a map");
  }
  validateValue(state, "state");
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

function renderNodes(nodes, scope, views, stack = []) {
  return nodes.flatMap((node) => renderNode(node, scope, views, stack));
}

function renderNode(node, scope, views, stack) {
  if (node.type === "text") {
    if (!decodedText.has(node.value)) {
      const decoder = document.createElement("textarea");
      // Text comes from a compile-time literal template; dynamic values use textContent.
      decoder.innerHTML = node.value;
      decodedText.set(node.value, decoder.value);
    }
    return [document.createTextNode(decodedText.get(node.value))];
  }
  if (node.type === "binding") {
    const span = document.createElement("span");
    span.dataset.liveLiftText = pathLabel(node.expr);
    span.textContent = display(evaluate(node.expr, scope));
    return [span];
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
    } else {
      element.setAttribute(attr.name, attr.value);
    }
  }
  if (key !== null) element.setAttribute("data-live-lift-key", String(key));
  if (node.node_id !== null) element.setAttribute("data-live-lift-node-id", node.node_id);
  element.append(...renderNodes(node.children, scope, views, stack));
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
  if (current.nodeType === 3) {
    if (current.textContent !== next.textContent) current.textContent = next.textContent;
    return;
  }
  for (const attr of [...current.attributes]) {
    if (!next.hasAttribute(attr.name)) current.removeAttribute(attr.name);
  }
  for (const attr of [...next.attributes]) {
    if (current.getAttribute(attr.name) !== attr.value) current.setAttribute(attr.name, attr.value);
  }
  if (current.tagName === "INPUT" && next.hasAttribute("value") && current.value !== next.value) {
    current.value = next.value;
  }
  if (current.hidden !== next.hidden) current.hidden = next.hidden;
  reconcile(current, [...next.childNodes]);
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
      this.applyServerPatch = (revision, patch) => {
        if (!Number.isSafeInteger(revision) || revision <= this.serverRevision) return;
        if (!patch || typeof patch !== "object" || Array.isArray(patch)) throw new Error("Invalid LiveLift server patch");
        for (const field of Object.keys(patch)) {
          if (!this.serverFields.has(field)) throw new Error(`Server cannot patch client-owned field: ${field}`);
        }
        const nextState = {...this.state, ...patch};
        validateState(nextState);
        this.render(nextState);
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

      this.runAction = (actionName, control) => {
        const actions = this.view.actions;
        const action = Object.hasOwn(actions, actionName) ? actions[actionName] : undefined;
        if (typeof action !== "function") {
          throw new Error(`Unknown LiveLift action: ${actionName}`);
        }

        const eventData = {
          value: "value" in control ? control.value : null,
          checked: "checked" in control ? control.checked : false,
          params: control.dataset.liveLiftParams ? JSON.parse(control.dataset.liveLiftParams) : {},
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
        this.render(nextState);
        this.state = nextState;
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

      this.el.addEventListener("click", this.onClick);
      this.el.addEventListener("input", this.onInput);
      this.el.addEventListener("change", this.onChange);
      this.el.addEventListener("submit", this.onSubmit);
      if (!serverRendered) this.render();
    },

    destroyed() {
      if (this.syncRef && typeof this.removeHandleEvent === "function") this.removeHandleEvent(this.syncRef);
      this.el.removeEventListener("click", this.onClick);
      this.el.removeEventListener("input", this.onInput);
      this.el.removeEventListener("change", this.onChange);
      this.el.removeEventListener("submit", this.onSubmit);
    },

    updated() {
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
