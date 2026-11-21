const SAFE_KEY = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
const RESERVED_KEYS = new Set(["__proto__", "constructor", "prototype"]);
const MAX_LIST_LENGTH = 10_000;
const MAX_MAP_FIELDS = 1_024;
const MAX_STATE_NODES = 50_000;
const MAX_STATE_BYTES = 1_048_576;
const MAX_EVENT_FIELDS = 64;
const MAX_EVENT_BYTES = 65_536;
const OFFLINE_ACTION_MAX_AGE_MS = 30_000;
const FLOAT_TAG = "$live_lift_float";
const FLOAT_TEXT = /^-?(?:0|[1-9]\d*)\.(?:\d+)(?:e-?\d+)?$/;
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
  if (isFloat(value)) {
    const text = value[FLOAT_TAG];
    if (typeof text !== "string" || !FLOAT_TEXT.test(text) || !Number.isFinite(Number(text))) {
      throw new Error(`Invalid LiveLift float at ${path}`);
    }
    charge(budget, 1, encoder.encode(text).length + 16, path);
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

function isFloat(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).length === 1 && Object.hasOwn(value, FLOAT_TAG);
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
  if (expr.type === "float") return {[FLOAT_TAG]: expr.value};
  if (expr.type === "map") {
    return Object.fromEntries(expr.entries.map(({key, expr: value}) => [key, evaluate(value, scope)]));
  }
  if (expr.type === "list") return expr.items.map((item) => evaluate(item, scope));
  if (expr.type === "and") {
    const left = evaluate(expr.left, scope);
    return left === false || left === null ? left : evaluate(expr.right, scope);
  }
  if (expr.type === "path") return readPath(expr, scope);
  throw new Error(`Unsupported client expression: ${expr.type}`);
}

const MISSING_PATH = Symbol();

function readPath(expr, scope, allowMissing = false) {
  let value;
  let offset = 0;
  const {root, fields} = expr;
  if (root === "state" && fields.length && Object.hasOwn(scope, fields[0])) {
    value = scope[fields[offset++]];
  } else {
    if (!Object.hasOwn(scope, root)) {
      if (allowMissing) return MISSING_PATH;
      throw new Error(`Missing client scope: ${root}`);
    }
    value = scope[root];
  }
  for (; offset < fields.length; offset += 1) {
    const field = fields[offset];
    if (!value || typeof value !== "object" || !Object.hasOwn(value, field)) {
      if (allowMissing) return MISSING_PATH;
      throw new Error(`Missing client field: ${field}`);
    }
    value = value[field];
  }
  return value;
}

function display(value) {
  if (value === null) return "";
  if (isFloat(value)) return value[FLOAT_TAG];
  if (["string", "number", "boolean"].includes(typeof value)) return String(value);
  throw new Error("Cannot display a client collection directly");
}

function classValue(value) {
  if (Array.isArray(value)) return classTokens(value).join(" ");
  if (value === null || value === false) return null;
  return display(value);
}

function classTokens(value) {
  return value.flatMap((item) => {
    if (item === null || item === false) return [];
    return Array.isArray(item) ? classTokens(item) : [display(item)];
  });
}

function nativeClassValue(expr, value) {
  if (!Array.isArray(value) || expr.type !== "list") return classValue(value);
  const prefixCount = expr.items.findIndex((item) => item.type !== "literal" || typeof item.value !== "string");
  if (prefixCount > 0) {
    // HEEx inlines a literal class prefix and retains its separator even when the dynamic tail is empty.
    return `${classValue(value.slice(0, prefixCount))} ${classValue(value.slice(prefixCount))}`;
  }
  return classValue(value);
}

function pathLabel(expr) {
  if (expr.type !== "path") return "expression";
  return (expr.root === "state" ? expr.fields : [expr.root, ...expr.fields]).join(".");
}

function serializeForm(form, _target, entries = new FormData(form)) {
  const params = Object.create(null);
  for (const [name, value] of entries) {
    if (typeof value !== "string") throw new Error(`Unsupported form value: ${name}`);
    if (!/^[a-zA-Z_]\w*(\[[a-zA-Z_]\w*\]){0,3}$/.test(name)) {
      throw new Error(`Unsupported form name: ${name}`);
    }
    const path = name.match(/[a-zA-Z_]\w*/g);
    let current = params;
    path.forEach((key, index) => {
      if (RESERVED_KEYS.has(key) || key === "_live_lift_seq") {
        throw new Error(`Unsafe form name: ${name}`);
      }
      const leaf = index === path.length - 1;
      if (leaf) {
        if (Object.hasOwn(current, key)) throw new Error(`Duplicate form parameter: ${name}`);
        current[key] = value;
      } else {
        current = current[key] ??= Object.create(null);
        if (typeof current !== "object") {
          throw new Error(`Conflicting form parameter: ${name}`);
        }
      }
    });
  }
  return params;
}

function validateEventParams(params, depth = 0, budget = {fields: 0, bytes: 0}) {
  if (!params || typeof params !== "object" || Array.isArray(params)) {
    throw new Error("LiveLift event params must be a map");
  }
  if (depth > 0 && Object.keys(params).length === 0) {
    throw new Error("Unsupported empty LiveLift event parameter map");
  }
  for (const [key, value] of Object.entries(params)) {
    if (!SAFE_KEY.test(key) || RESERVED_KEYS.has(key) || key === "_live_lift_seq") {
      throw new Error(`Unsafe LiveLift event parameter: ${key}`);
    }
    budget.bytes += encoder.encode(key).length;
    if (typeof value === "string") {
      budget.fields += 1;
      budget.bytes += encoder.encode(value).length;
    } else if (value && typeof value === "object" && !Array.isArray(value) && depth < 3) {
      validateEventParams(value, depth + 1, budget);
    } else {
      throw new Error(`Unsupported LiveLift event parameter: ${key}`);
    }
    if (budget.fields > MAX_EVENT_FIELDS) throw new Error("LiveLift event parameter limit exceeded");
    if (budget.bytes > MAX_EVENT_BYTES) throw new Error("LiveLift event parameter size limit exceeded");
  }
}

const dependencyPlans = new WeakMap();
const renderedTemplates = new WeakMap();
const renderTargets = new WeakMap();
const IN_ROW = Symbol();

function dependencyPlan(root) {
  if (dependencyPlans.has(root)) return dependencyPlans.get(root);
  const variable = root.for?.var;
  const state = new Map();
  const item = new Map();

  function expression(expr) {
    if (!expr || expr.type === "literal" || expr.type === "float") return true;
    if (expr.type === "path") {
      const local = variable !== undefined &&
        (expr.root === variable || (expr.root === "state" && expr.fields[0] === variable));
      if (!local && expr.root !== "state") return false;
      (local ? item : state).set(JSON.stringify([expr.root, expr.fields]), expr);
      return true;
    }
    if (expr.type === "map") return expr.entries.every((entry) => expression(entry.expr));
    if (expr.type === "list") return expr.items.every(expression);
    if (expr.type === "and") return expression(expr.left) && expression(expr.right);
    return false;
  }

  function subtree(node) {
    if (node.type === "text") return true;
    if (node.type === "binding") return expression(node.expr);
    if (node.type === "component") return variable !== undefined &&
      node.props.every((prop) => expression(prop.expr));
    if (node.type !== "element" || (node !== root && node.for)) return false;
    // Unkeyed form controls still reconcile their live values and selection.
    if (variable === undefined && ["form", "input", "select", "textarea", "option"].includes(node.tag)) return false;
    return expression(node.if) && expression(node.key) && node.attrs.every((attr) => {
      if (attr.name === "data-live-lift-show") {
        return expression({type: "path", root: "state", fields: [attr.value]});
      }
      return !["dynamic", "native_dynamic", "params", "boolean"].includes(attr.type) ||
        expression(attr.value);
    }) && node.children.every(subtree);
  }

  const plan = subtree(root) ? {state: [...state.values()], item: [...item.values()]} : null;
  dependencyPlans.set(root, plan);
  return plan;
}

function samePaths(paths, previous, current) {
  return paths.every((path) => sameValue(readPath(path, previous, true), readPath(path, current, true)));
}

function hydrateKeyedRows(nodes, scope, root) {
  for (const node of nodes) {
    if (node.type !== "element") continue;
    if (node.if && [false, null].includes(evaluate(node.if, scope))) continue;
    if (node.for) {
      const items = evaluate(node.for.source, scope);
      if (!Array.isArray(items)) throw new Error(":for expects a list");
      const keys = new Set();
      const rows = new Map();
      for (const element of root.querySelectorAll("[id]")) {
        if (element.tagName !== node.tag.toUpperCase()) continue;
        const id = element.id;
        rows.set(id, rows.has(id) ? null : element);
      }
      for (const item of items) {
        const itemScope = {...scope, [node.for.var]: item};
        const key = evaluate(node.key, itemScope);
        if (typeof key !== "string" && !Number.isSafeInteger(key)) throw new Error(":key must be a string or safe integer");
        const keyString = String(key);
        if (keys.has(keyString)) throw new Error(`Duplicate client list key: ${key}`);
        keys.add(keyString);
        const row = rows.get(keyString);
        if (!row) continue;
        row.setAttribute("data-live-lift-key", keyString);
        row.setAttribute("data-live-lift-node-id", node.node_id);
        hydrateKeyedRows(node.children, itemScope, row);
      }
    } else {
      hydrateKeyedRows(node.children, scope, root);
    }
  }
}

function renderNodes(nodes, scope, views, stack = [], textOnly = false, parent = null) {
  let previous;
  if (parent && scope.__previousState && nodes.some((node) => node.type === "element" && !node.for)) {
    previous = new Map();
    for (const child of parent.children) {
      const template = renderedTemplates.get(child);
      if (template && !template.for) previous.set(template, child);
    }
  }
  return nodes.flatMap((node) => renderNode(node, scope, views, stack, textOnly, previous));
}

function reuseMarker(element) {
  // Keep live children attached until their parent reconciles them.
  const marker = document.createComment("");
  marker.__liveLiftReuse = element;
  return [marker];
}

function renderNode(node, scope, views, stack, textOnly, previousChildren) {
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
    const plan = scope[IN_ROW] ? null : dependencyPlan(node);
    const previousScope = {state: scope.__previousState};
    const previous = new Map();
    const existing = new Map();
    if (plan && scope.__previousState && scope.__root &&
        node.for.source.type === "path" && node.for.source.root === "state" &&
        samePaths(plan.state, previousScope, scope)) {
      const oldItems = readPath(node.for.source, previousScope, true);
      if (Array.isArray(oldItems)) {
        for (const oldItem of oldItems) {
          const oldKey = evaluate(node.key, {...previousScope, [node.for.var]: oldItem});
          previous.set(String(oldKey), oldItem);
        }
      }
      for (const element of scope.__root.querySelectorAll("[data-live-lift-key]")) {
        if (element.tagName === node.tag.toUpperCase() &&
            element.getAttribute("data-live-lift-node-id") === node.node_id) {
          existing.set(element.getAttribute("data-live-lift-key"), element);
        }
      }
    }
    return items.flatMap((item) => {
      const itemScope = {...scope, [node.for.var]: item, [IN_ROW]: true};
      const key = evaluate(node.key, itemScope);
      if (typeof key !== "string" && !Number.isSafeInteger(key)) throw new Error(":key must be a string or safe integer");
      const keyString = String(key);
      if (keys.has(keyString)) throw new Error(`Duplicate client list key: ${key}`);
      keys.add(keyString);
      const priorItem = previous.get(keyString);
      if (existing.has(keyString) && previous.has(keyString) &&
          (Object.is(priorItem, item) || samePaths(plan.item, {...previousScope, [node.for.var]: priorItem}, itemScope))) {
        return reuseMarker(existing.get(keyString));
      }
      return renderElement(node, itemScope, key, views, stack);
    });
  }
  const current = previousChildren?.get(node);
  const plan = current && dependencyPlan(node);
  if (plan && samePaths(plan.state, {state: scope.__previousState}, scope)) return reuseMarker(current);
  return renderElement(node, scope, null, views, stack, current);
}

function renderElement(node, scope, key, views, stack, current) {
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
    } else if (attr.type === "native_dynamic") {
      const value = evaluate(attr.value, scope);
      if (attr.name !== "class" && Array.isArray(value)) throw new Error(`${attr.name} requires a scalar value`);
      const rendered = attr.name === "class" ? nativeClassValue(attr.value, value) : value === null || value === false ? null : display(value);
      if (rendered !== null) element.setAttribute(attr.name, rendered === "true" && value === true ? "" : rendered);
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
  renderedTemplates.set(element, node);
  if (current) renderTargets.set(element, current);
  element.append(...renderNodes(node.children, scope, views, stack, node.tag === "textarea", current));
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
  let cursor = parent.firstChild;
  desired.forEach((next, index) => {
    const reuse = next.__liveLiftReuse;
    if (reuse) {
      if (reuse.parentNode !== parent || used.has(reuse)) {
        throw new Error("LiveLift node changed parent before reconciliation");
      }
      used.add(reuse);
      if (cursor !== reuse) parent.insertBefore(reuse, cursor);
      cursor = reuse.nextSibling;
      return;
    }
    const key = next.nodeType === 1 ? next.getAttribute("data-live-lift-key") : null;
    const nodeId = next.nodeType === 1 ? next.getAttribute("data-live-lift-node-id") : null;
    const indexed = previous[index];
    const template = renderedTemplates.get(next);
    const matchesUnmarked = (node) => node && !used.has(node) &&
      (node.nodeType !== 1 || (!node.hasAttribute("data-live-lift-key") && !node.hasAttribute("data-live-lift-node-id"))) &&
      node.nodeType === next.nodeType &&
      (node.nodeType !== 1 || (node.tagName === next.tagName &&
        (!renderedTemplates.has(node) || renderedTemplates.get(node) === template)));
    const target = renderTargets.get(next);
    if (target && (target.parentNode !== parent || used.has(target))) {
      throw new Error("LiveLift subtree changed parent before reconciliation");
    }
    const current = target || (key !== null
      ? keyed.get(`${next.tagName}:${nodeId}:${key}`)
      : nodeId !== null
        ? identified.get(`${next.tagName}:${nodeId}`)
        : matchesUnmarked(indexed) ? indexed : unmarked.find(matchesUnmarked));
    const chosen = current || next;
    if (current) patchNode(current, next);
    used.add(chosen);
    if (cursor !== chosen) parent.insertBefore(chosen, cursor);
    cursor = chosen.nextSibling;
  });
  previous.forEach((node) => { if (!used.has(node)) node.remove(); });
}

function patchNode(current, next) {
  if (current.nodeType !== 1) {
    if (current.nodeValue !== next.nodeValue) current.nodeValue = next.nodeValue;
    return;
  }
  renderedTemplates.set(current, renderedTemplates.get(next));
  current.__liveLiftPatch?.(next);
  const hadValueAttribute = current.hasAttribute("value");
  for (const attr of [...current.attributes]) {
    // The component CID belongs to LiveView and is supplied by its original ~H render.
    if (attr.name === "phx-target") continue;
    if (!next.hasAttribute(attr.name)) current.removeAttribute(attr.name);
  }
  for (const attr of next.attributes) {
    if (current.getAttribute(attr.name) !== attr.value) current.setAttribute(attr.name, attr.value);
  }
  if (current.tagName === "INPUT") {
    if (next.hasAttribute("value")) {
      if (current.value !== next.value) current.value = next.value;
    } else if (hadValueAttribute) {
      current.value = "";
    }
    if (current.checked !== next.checked) current.checked = next.checked;
  }
  if (current.tagName === "OPTION" && current.selected !== next.selected) current.selected = next.selected;
  if (current.hidden !== next.hidden) current.hidden = next.hidden;
  reconcile(current, [...next.childNodes]);
  if ((current.tagName === "SELECT" || current.tagName === "TEXTAREA") && current.value !== next.value) {
    current.value = next.value;
  }
}

function frameBatch(apply) {
  let pending = null;
  let frame = null;
  let timer = null;

  function clear() {
    if (frame !== null) cancelAnimationFrame(frame);
    if (timer !== null) clearTimeout(timer);
    pending = frame = timer = null;
  }

  function flush() {
    const snapshot = pending;
    clear();
    if (snapshot) apply(snapshot);
  }

  function enqueue(snapshot) {
    if (typeof requestAnimationFrame !== "function") {
      apply(snapshot);
      return;
    }
    if (pending && (pending.revision > snapshot.revision ||
        (pending.revision === snapshot.revision && pending.ack_seq > snapshot.ack_seq))) return;
    pending = snapshot;
    if (frame !== null) return;
    frame = requestAnimationFrame(flush);
    // Hidden documents can stop producing animation frames.
    timer = setTimeout(flush, 48);
  }

  return {enqueue, flush, clear};
}

function replay(actions, state, pending, timers) {
  if (timers) return timers.replay(actions, state, pending, replay);
  for (const {action, eventData} of pending) {
    state = actions[action](state, eventData);
    validateState(state);
  }
  return state;
}

/**
 * Runs user-defined client actions in a LiveView-owned page.
 * The app supplies its own HEEx and marks only the locally owned DOM subtree.
 */
export function createClientHook(views) {
  const imports = new WeakMap();

  return {
    mounted() {
      const name = this.el.dataset.liveLiftModule;
      const entry = Object.hasOwn(views, name) ? views[name] : undefined;
      if (!entry) throw new Error(`Unknown LiveLift view: ${name}`);
      if (typeof entry !== "function") {
        this.mountView(entry, views);
        return;
      }

      const loading = {snapshot: this.el.dataset.liveLiftState, disconnected: false};
      this.loading = loading;
      this.el.dataset.liveLiftLoad = "loading";
      if (!imports.has(entry)) {
        imports.set(entry, Promise.resolve().then(entry).catch((error) => {
          imports.delete(entry);
          throw error;
        }));
      }
      return imports.get(entry).then(({views: loaded}) => {
        if (this.loading !== loading) return;
        if (!loaded || !Object.hasOwn(loaded, name)) throw new Error(`Unknown LiveLift view: ${name}`);
        const refresh = loading.snapshot !== this.el.dataset.liveLiftState;
        this.mountView(loaded[name], loaded, refresh);
        this.loading = null;
        if (loading.disconnected) this.disconnected();
        this.el.dataset.liveLiftLoad = "ready";
      }).catch((error) => {
        if (this.loading !== loading) return;
        this.el.dataset.liveLiftLoad = "error";
        const status = this.el.ownerDocument?.createElement("span");
        if (status) {
          status.setAttribute("role", "status");
          status.textContent = "Local updates could not load. Reload the page to try again.";
          this.el.append(status);
        }
        console.error(`Could not load LiveLift view: ${name}`, error);
      });
    },

    mountView(view, views, refresh = false) {
      const formParams = view.prepare?.(this.el, serializeForm) ?? serializeForm;
      this.view = view;
      this.viewRegistry = views;
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
      if (serverRendered && this.optimistic) hydrateKeyedRows(this.view.template, {state: this.state}, this.el);
      if (this.optimistic) {
        this.lastTextValues = new Map();
        this.debouncedChanges = new Map();
        this.authoritativeState = this.state;
        this.pending = [];
        this.recovery = null;
        this.recoveryBlocked = false;
        this.instance = this.el.dataset.liveLiftInstance;
        this.ackSequence = Number(this.el.dataset.liveLiftAckSeq || "0");
        this.nextSequence = this.ackSequence + 1;
        if (!Number.isSafeInteger(this.nextSequence) || this.nextSequence < 1) {
          throw new Error("Invalid LiveLift event sequence");
        }
        this.connectionEpoch = 0;
        this.reconnectPending = false;
        this.offline = false;
        this.offlineQueue = [];
        this.timers = view.timers?.(this, validateState);
        this.authoritativeBatch = frameBatch(({revision, state, ack_seq, timers}) => {
          this.applyAuthoritative(revision, state, ack_seq, timers);
          this.recoverPending();
        });
        this.resetOptimisticSnapshot = () => {
          const instance = this.el.dataset.liveLiftInstance;
          const sameInstance = Boolean(instance) && instance === this.instance;
          const snapshotRevision = Number(this.el.dataset.liveLiftServerRevision || "0");
          const snapshotAck = Number(this.el.dataset.liveLiftAckSeq || "0");
          if (!Number.isSafeInteger(snapshotRevision) || snapshotRevision < 0) {
            throw new Error("Invalid LiveLift server revision");
          }
          if (!Number.isSafeInteger(snapshotAck) || snapshotAck < 0) {
            throw new Error("Invalid LiveLift acknowledged sequence");
          }
          const keepBase = sameInstance && snapshotRevision < this.serverRevision;
          const snapshot = keepBase ? this.authoritativeState : JSON.parse(this.el.dataset.liveLiftState);
          const revision = keepBase ? this.serverRevision : snapshotRevision;
          const ack = sameInstance ? Math.max(this.ackSequence, snapshotAck) : snapshotAck;
          const retry = sameInstance ? this.pending.filter(({sequence}) => sequence > ack) : [];
          const hadUnacknowledged = retry.length > 0;
          const offline = sameInstance || this.el.dataset.liveLiftReconnectConflict !== "discard"
            ? this.offlineQueue.filter(({createdAt}) => performance.now() - createdAt <= OFFLINE_ACTION_MAX_AGE_MS)
            : [];
          let nextSequence = (retry.at(-1)?.sequence ?? ack) + 1;
          for (const {action, params, eventData} of offline) {
            retry.push({sequence: nextSequence++, action, params, eventData});
          }
          if (!Number.isSafeInteger(nextSequence)) throw new Error("LiveLift event sequence overflow");
          validateState(snapshot);

          this.timers?.resume(keepBase, ack);
          let replayed;
          let replayError = null;
          try {
            replayed = replay(view.actions, snapshot, retry, this.timers);
          } catch (error) {
            replayError = error;
            retry.length = 0;
            replayed = snapshot;
            nextSequence = ack + 1;
          }
          this.render(replayed);
          this.pending = retry;
          this.recovery = retry.length ? {sent: null} : null;
          this.recoveryBlocked = sameInstance && (this.recoveryBlocked || Boolean(replayError && hadUnacknowledged));
          this.instance = instance;
          this.ackSequence = ack;
          this.authoritativeState = snapshot;
          this.serverRevision = revision;
          this.nextSequence = nextSequence;
          this.state = replayed;
          this.reconnectPending = false;
          this.offline = false;
          this.offlineQueue = [];
          if (replayError) {
            throw new Error(`LiveLift offline replay conflict; queued actions were dropped: ${replayError.message}`);
          }
          this.recoverPending();
        };
        this.applyAuthoritative = (revision, state, ackSequence, timers) => {
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
          const fresh = reset || revision > this.serverRevision;
          const nextBase = fresh ? state : this.authoritativeState;
          const nextPending = (reset ? [] : this.pending).filter(({sequence}) => sequence > ackSequence);
          if (revision >= this.serverRevision) this.timers?.accept(timers, ackSequence);
          const nextState = replay(view.actions, nextBase, nextPending, this.timers);
          if (!sameValue(nextState, this.state)) this.render(nextState);
          this.authoritativeState = nextBase;
          if (fresh) this.serverRevision = revision;
          this.ackSequence = Math.max(this.ackSequence, ackSequence);
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
        this.authoritativeBatch.flush();
        if (this.recoveryBlocked) throw new Error("LiveLift cannot resume this action sequence; reload the page");
        if (this.offlineQueue.length + this.pending.length >= 100) {
          throw new Error("LiveLift pending action limit reached");
        }
        if (!Number.isSafeInteger(this.nextSequence)) throw new Error("LiveLift event sequence overflow");
        validateEventParams(params);
        const sequence = this.nextSequence;
        const eventData = this.runAction(eventName, control, params);
        if (this.offline) {
          this.offlineQueue.push({action: eventName, params, eventData, createdAt: performance.now()});
          return;
        }
        this.nextSequence += 1;
        const pendingAction = {sequence, action: eventName, eventData, params};
        this.pending.push(pendingAction);
        if (this.recovery) this.timers?.start(eventName, sequence);
        else this.pushOptimistic(pendingAction);
      };

      this.recoverPending = () => {
        if (!this.recovery || this.offline) return;
        const first = this.pending[0];
        if (!first) {
          this.recovery = null;
          return;
        }
        if (this.recovery.sent === first.sequence) return;
        this.recovery.sent = first.sequence;
        this.pushOptimistic(first);
      };

      this.pushOptimistic = ({sequence, action, params}) => {
        this.timers?.start(action, sequence);
        const payload = {...params, _live_lift_seq: sequence};
        const epoch = this.connectionEpoch;
        // The prediction can remove its own control; target the stable component root.
        this.pushEventTo(this.el, action, payload, (reply) => {
          if (epoch !== this.connectionEpoch) return;
          if (reply.disabled) {
            window.location.reload();
            return;
          }
          if (reply.expected_seq !== undefined &&
              (reply.expected_seq !== reply.ack_seq + 1 || reply.expected_seq >= sequence)) {
            throw new Error("Invalid LiveLift action gap");
          }
          if (reply.expected_seq === undefined && !this.recovery) {
            this.authoritativeBatch.enqueue(reply);
            return;
          }
          this.authoritativeBatch.flush();
          this.applyAuthoritative(reply.revision, reply.state, reply.ack_seq, reply.timers);
          if (reply.expected_seq !== undefined && this.pending.some((item) => item.sequence === sequence)) {
            this.recovery ??= {sent: null};
          }
          this.recoverPending();
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
        const eventName = control.getAttribute("phx-change");
        if (!Object.hasOwn(this.view.actions, eventName)) return;
        event.stopImmediatePropagation();
        const textControl = event.target.matches('input:not([type="checkbox"]):not([type="radio"]), textarea');
        const row = event.target.closest("[data-live-lift-key]");
        const scope = row
          ? `${row.getAttribute("data-live-lift-node-id")}:${row.getAttribute("data-live-lift-key")}`
          : String([...this.el.querySelectorAll("[phx-change]")].indexOf(control));
        const changeKey = JSON.stringify([eventName, scope, event.target.name || event.target.id]);
        // Browsers fire change after input; LiveView must not receive a second event.
        if (event.type === "change" && textControl && this.lastTextValues.get(changeKey) === event.target.value) {
          return;
        }
        if (event.type === "input" && event.target.matches('select, input[type="checkbox"], input[type="radio"]')) return;
        const textValue = textControl ? event.target.value : null;
        const previousTextValue = textControl ? this.lastTextValues.get(changeKey) : undefined;
        // Reconciliation can blur an input and fire change before the input render returns.
        if (textControl) this.lastTextValues.set(changeKey, textValue);
        try {
          const target = event.target;
          const send = () => {
            if (!this.el.contains(target)) return;
            const params = control.tagName === "FORM"
              ? formParams(control, target)
              : {value: control.value, ...(control.name ? {[control.name]: control.value} : {})};
            this.sendOptimistic(control, eventName, params);
          };
          const debounce = target.getAttribute("phx-debounce");
          const previous = this.debouncedChanges.get(target);
          if (previous) clearTimeout(previous.timer);
          this.debouncedChanges.delete(target);
          if (debounce === null) {
            send();
          } else {
            const entry = {timer: null, send};
            this.debouncedChanges.set(target, entry);
            if (debounce !== "blur") {
              entry.timer = setTimeout(() => {
                if (this.debouncedChanges.get(target) !== entry) return;
                this.debouncedChanges.delete(target);
                send();
              }, debounce === "" ? 300 : Number(debounce));
            }
          }
        } catch (error) {
          if (textControl) {
            if (previousTextValue === undefined) this.lastTextValues.delete(changeKey);
            else this.lastTextValues.set(changeKey, previousTextValue);
          }
          throw error;
        }
        if (textControl) {
          if (this.lastTextValues.size > 10_000) {
            this.lastTextValues.delete(this.lastTextValues.keys().next().value);
          }
        }
      };

      this.onOptimisticBlur = (event) => {
        const entry = this.debouncedChanges.get(event.target);
        if (!entry) return;
        clearTimeout(entry.timer);
        this.debouncedChanges.delete(event.target);
        entry.send();
      };

      this.onOptimisticSubmit = (event) => {
        if (!this.optimistic) return;
        const form = event.target.closest("form[phx-submit]");
        if (!form || !this.el.contains(form)) return;
        const eventName = form.getAttribute("phx-submit");
        if (!Object.hasOwn(this.view.actions, eventName)) return;
        for (const [control, entry] of this.debouncedChanges) {
          if (!form.contains(control)) continue;
          clearTimeout(entry.timer);
          this.debouncedChanges.delete(control);
        }
        event.preventDefault();
        event.stopImmediatePropagation();
        this.sendOptimistic(form, eventName, formParams(form));
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
        this.el.addEventListener("blur", this.onOptimisticBlur, true);
        this.el.addEventListener("submit", this.onOptimisticSubmit, true);
      } else {
        this.el.addEventListener("click", this.onClick);
      }
      this.el.addEventListener("input", this.onInput);
      this.el.addEventListener("change", this.onChange);
      this.el.addEventListener("submit", this.onSubmit);
      if (!serverRendered || refresh) this.render(this.state, null);
    },

    destroyed() {
      if (this.loading) {
        this.loading = null;
        return;
      }
      if (this.syncRef && typeof this.removeHandleEvent === "function") this.removeHandleEvent(this.syncRef);
      if (this.optimistic) {
        this.authoritativeBatch.clear();
        this.timers?.clear();
        for (const entry of this.debouncedChanges.values()) clearTimeout(entry.timer);
        this.debouncedChanges.clear();
        this.el.removeEventListener("click", this.onOptimisticClick, true);
        this.el.removeEventListener("input", this.onOptimisticChange, true);
        this.el.removeEventListener("change", this.onOptimisticChange, true);
        this.el.removeEventListener("blur", this.onOptimisticBlur, true);
        this.el.removeEventListener("submit", this.onOptimisticSubmit, true);
      }
      this.el.removeEventListener("click", this.onClick);
      this.el.removeEventListener("input", this.onInput);
      this.el.removeEventListener("change", this.onChange);
      this.el.removeEventListener("submit", this.onSubmit);
    },

    disconnected() {
      if (this.loading) {
        this.loading.disconnected = true;
        return;
      }
      if (this.optimistic) {
        this.authoritativeBatch.clear();
        this.timers?.suspend();
        this.connectionEpoch += 1;
        this.reconnectPending = true;
        this.offline = true;
      }
    },

    reconnected() {
      if (this.loading) this.loading.disconnected = false;
    },

    updated() {
      if (this.loading) return;
      if (this.optimistic) {
        if (this.reconnectPending) {
          this.resetOptimisticSnapshot();
          return;
        }
        const revision = Number(this.el.dataset.liveLiftServerRevision);
        if (Number.isSafeInteger(revision) && revision >= this.serverRevision) {
          const state = JSON.parse(this.el.dataset.liveLiftState);
          const ack = Number(this.el.dataset.liveLiftAckSeq || "0");
          const timers = this.el.dataset.liveLiftTimers;
          if (this.recovery) {
            this.authoritativeBatch.flush();
            this.applyAuthoritative(revision, state, ack, timers);
            this.recoverPending();
          } else if (revision > this.serverRevision || ack !== this.ackSequence) {
            this.authoritativeBatch.enqueue({revision, state, ack_seq: ack, timers});
          }
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

    render(state = this.state, previousState = this.state) {
      if (Array.isArray(this.view.template) && typeof document !== "undefined") {
        const focused = this.el.contains(document.activeElement) ? document.activeElement : null;
        const selection = focused && typeof focused.selectionStart === "number"
          ? [focused.selectionStart, focused.selectionEnd] : null;
        reconcile(this.el, renderNodes(this.view.template,
          {state, __previousState: previousState, __root: this.el}, this.viewRegistry, [], false, this.el));
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
