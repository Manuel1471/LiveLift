import assert from "node:assert/strict";
import test from "node:test";
import {createClientHook} from "./client_hook.js";

function element(initialState) {
  const countNode = {dataset: {liveLiftText: "count"}, textContent: ""};
  const stepNode = {dataset: {liveLiftText: "step"}, textContent: ""};
  const controls = {
    advance: {dataset: {liveLiftAction: "advance"}},
    retreat: {dataset: {liveLiftAction: "retreat"}},
    save: {dataset: {liveLiftServer: "save_score"}},
  };
  const listeners = new Map();

  return {
    dataset: {liveLiftState: JSON.stringify(initialState), liveLiftModule: "App.Score"},
    innerHTML: "",
    controls,
    hasChildNodes: () => false,
    countNode,
    stepNode,
    listeners,
    contains: (node) => Object.values(controls).includes(node),
    querySelectorAll: (selector) => selector === "[data-live-lift-text]" ? [countNode, stepNode] : [],
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: (name) => listeners.delete(name),
    click(actionName) {
      listeners.get("click")({target: {closest: () => controls[actionName]}});
    },
  };
}

test("runs app actions and renders app-selected fields", () => {
  const el = element({count: 10, step: 3});
  const actions = {
    advance: (state) => ({count: state.count + state.step, step: state.step}),
    retreat: (state) => ({count: state.count - state.step, step: state.step}),
  };
  const template = "<button data-live-lift-action=\"advance\">Add</button>";
  const hook = {...createClientHook({"App.Score": {actions, template}}), el};

  hook.mounted();
  assert.equal(el.innerHTML, template);
  assert.equal(el.countNode.textContent, "10");
  assert.equal(el.stepNode.textContent, "3");
  el.click("advance");
  assert.equal(el.countNode.textContent, "13");
  el.click("retreat");
  assert.equal(el.countNode.textContent, "10");
  hook.destroyed();
  assert.equal(el.listeners.size, 0);
});

test("passes input values and typed element parameters to two-argument actions", () => {
  const el = element({count: 0, step: 1, items: [{id: 1, name: "Old"}]});
  el.controls.edit = {
    dataset: {liveLiftInput: "edit", liveLiftParams: '{"id":1}'},
    value: "New",
    checked: false,
  };
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {edit: (state, event) => ({
        ...state,
        items: state.items.map((item) => item.id === event.params.id ? {...item, name: event.value} : item),
      })},
      template: "<input>",
    }}),
    el,
  };

  hook.mounted();
  el.listeners.get("input")({target: {closest: () => el.controls.edit}});
  assert.deepEqual(hook.state.items, [{id: 1, name: "New"}]);
});

test("keeps server-rendered DOM when mounting", () => {
  const el = element({count: 10, step: 2});
  el.innerHTML = '<output><span data-live-lift-text="count">10</span></output>';
  el.hasChildNodes = () => true;
  el.countNode.textContent = "10";
  const initialMarkup = el.innerHTML;
  const hook = {
    ...createClientHook({"App.Score": {actions: {}, template: "<output></output>"}}),
    el,
  };

  hook.mounted();
  assert.equal(el.innerHTML, initialMarkup);
  assert.equal(el.countNode.textContent, "10");
});

test("rejects unsafe action results", () => {
  const el = element({count: 1, step: 1});
  const hook = {
    ...createClientHook({
      "App.Score": {
        actions: {advance: () => ({count: Number.MAX_SAFE_INTEGER + 1, step: 1})},
        template: "<output></output>",
      },
    }),
    el,
  };

  hook.mounted();
  assert.throws(() => el.click("advance"), /Unsupported LiveLift state value/);
  assert.equal(el.countNode.textContent, "1");
});

test("does not commit state when rendering a client action fails", () => {
  const el = element({count: 1, step: 1});
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: () => ({count: 2})},
      template: "<output></output>",
    }}), el,
  };
  hook.mounted();
  assert.throws(() => el.click("advance"), /Unknown LiveLift state field: step/);
  assert.deepEqual(hook.state, {count: 1, step: 1});
  assert.equal(el.countNode.textContent, "1");
});

test("accepts nested state and rejects dangerous keys", () => {
  const el = element({count: 1, step: 1, items: [{id: "a", done: false}]});
  const hook = {
    ...createClientHook({"App.Score": {actions: {}, template: []}}),
    el,
  };
  hook.mounted();

  const unsafe = element(JSON.parse('{"count":1,"step":1,"__proto__":1}'));
  const unsafeHook = {...createClientHook({"App.Score": {actions: {}, template: []}}), el: unsafe};
  assert.throws(() => unsafeHook.mounted(), /Unsafe LiveLift state key/);
});

test("renders browser-safe primitives and dynamic attributes", () => {
  const el = element({count: null, step: true, style: "active", title: "<ready>", score: 12});
  const attributes = new Map();
  const node = {
    getAttribute: (name) => ({
      "data-live-lift-bind-class": "style",
      "data-live-lift-bind-title": "title",
      "data-live-lift-bind-value": "score",
    })[name],
    setAttribute: (name, value) => attributes.set(name, value),
  };
  const originalQuery = el.querySelectorAll;
  el.querySelectorAll = (selector) => [
    "[data-live-lift-bind-class]", "[data-live-lift-bind-title]",
    "[data-live-lift-bind-value]",
  ].includes(selector) ? [node] : originalQuery(selector);
  const hook = {
    ...createClientHook({"App.Score": {actions: {}, template: "<p></p>"}}),
    el,
  };

  hook.mounted();
  assert.equal(el.countNode.textContent, "");
  assert.equal(el.stepNode.textContent, "true");
  assert.equal(attributes.get("class"), "active");
  assert.equal(attributes.get("title"), "<ready>");
  assert.equal(attributes.get("value"), "12");
});

test("updates conditional visibility using Elixir truthiness", () => {
  const el = element({count: 0, step: 1, visible: false});
  const node = {dataset: {liveLiftShow: "visible"}, hidden: false};
  const originalQuery = el.querySelectorAll;
  el.querySelectorAll = (selector) => selector === "[data-live-lift-show]" ?
    [node] : originalQuery(selector);
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, visible: 0})},
      template: "<p data-live-lift-show=\"visible\">Hi</p>",
    }}),
    el,
  };

  hook.mounted();
  assert.equal(node.hidden, true);
  el.click("advance");
  assert.equal(node.hidden, false);
});

test("sends a deliberate server event with the current local state", () => {
  const el = element({count: 10, step: 3});
  const sent = [];
  const hook = {
    ...createClientHook({
      "App.Score": {
        actions: {advance: (state) => ({...state, count: state.count + state.step})},
        template: "<button data-live-lift-server=\"save_score\">Save</button>",
      },
    }),
    el,
    pushEvent: (name, payload) => sent.push({name, payload}),
  };

  hook.mounted();
  el.click("advance");
  el.click("save");

  assert.deepEqual(sent, [{name: "save_score", payload: {state: {count: 13, step: 3}, revision: 0}}]);
});

test("applies only fresh server-owned patches while local actions remain independent", () => {
  const el = element({count: 10, step: 2, saved_score: null});
  el.id = "local-counter";
  el.dataset.liveLiftServerFields = '["saved_score"]';
  const sent = [];
  let receive;
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({count: state.count + state.step, step: state.step})},
      template: "<p></p>",
    }}),
    el,
    pushEvent: (name, payload) => sent.push({name, payload}),
    handleEvent: (_name, callback) => { receive = callback; return 1; },
    removeHandleEvent: (ref) => assert.equal(ref, 1),
  };

  hook.mounted();
  el.click("advance");
  receive({id: "local-counter", revision: 1, patch: {saved_score: 10}});
  assert.deepEqual(hook.state, {count: 12, step: 2, saved_score: 10});
  receive({id: "local-counter", revision: 1, patch: {saved_score: 0}});
  assert.equal(hook.state.saved_score, 10);
  assert.throws(() => receive({id: "local-counter", revision: 2, patch: {count: 0}}), /client-owned/);
  el.click("save");
  assert.deepEqual(sent[0].payload, {state: {count: 12, step: 2}, revision: 1});
  hook.destroyed();
});

test("starts at the server revision supplied by the initial render", () => {
  const el = element({count: 1, step: 1, saved_score: 4});
  el.id = "score";
  el.dataset.liveLiftServerFields = '["saved_score"]';
  el.dataset.liveLiftServerRevision = "4";
  let receive;
  const hook = {
    ...createClientHook({"App.Score": {actions: {}, template: "<p></p>"}}), el,
    handleEvent: (_name, callback) => { receive = callback; return 1; },
  };
  hook.mounted();
  receive({id: "score", revision: 3, patch: {saved_score: 3}});
  assert.equal(hook.state.saved_score, 4);
  receive({id: "score", revision: 5, patch: {saved_score: 5}});
  assert.equal(hook.state.saved_score, 5);
  el.dataset.liveLiftServerRevision = "6";
  el.dataset.liveLiftState = JSON.stringify({count: 0, step: 1, saved_score: 6});
  hook.updated();
  assert.deepEqual(hook.state, {count: 1, step: 1, saved_score: 6});
});

test("native component rejects a full pending queue before changing state", () => {
  const el = element({count: 1, step: 1});
  el.dataset.liveLiftMode = "component";
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: () => {},
  };
  hook.mounted();
  hook.pending = Array.from({length: 100}, (_, sequence) => ({sequence}));
  assert.throws(() => hook.sendOptimistic(el.controls.advance, "advance", {}), /pending action limit/);
  assert.equal(hook.state.count, 1);
});

test("native component rejects unsafe event parameters", () => {
  const el = element({count: 1, step: 1});
  el.dataset.liveLiftMode = "component";
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: () => {},
  };
  hook.mounted();
  assert.throws(() => hook.sendOptimistic(el.controls.advance, "advance", {__proto__: 1, constructor: 1}), /Unsafe LiveLift event parameter/);
  assert.equal(hook.state.count, 1);
});

test("a disabled native component reloads into server mode", () => {
  const el = element({count: 1, step: 1});
  el.dataset.liveLiftMode = "component";
  const previousWindow = globalThis.window;
  let reloads = 0;
  globalThis.window = {location: {reload: () => { reloads += 1; }}};
  try {
    const hook = {
      ...createClientHook({"App.Score": {
        actions: {advance: (state) => ({...state, count: state.count + 1})},
        template: "<output></output>",
      }}),
      el,
      pushEventTo: (_control, _event, _payload, reply) => reply({disabled: true}),
    };
    hook.mounted();
    hook.sendOptimistic(el.controls.advance, "advance", {});
    assert.equal(reloads, 1);
  } finally {
    globalThis.window = previousWindow;
  }
});

test("authoritative corrections replay pending actions and ignore late replies", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  const replies = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, payload, reply) => replies.push({payload, reply}),
  };
  hook.mounted();
  for (let index = 0; index < 3; index += 1) hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.equal(hook.state.count, 3);
  assert.equal(hook.pending.length, 3);

  replies[0].reply({revision: 1, ack_seq: 1, state: {count: 2, step: 1}});
  assert.equal(hook.state.count, 4);
  assert.deepEqual(hook.pending.map(({sequence}) => sequence), [2, 3]);
  replies[2].reply({revision: 3, ack_seq: 3, state: {count: 5, step: 1}});
  assert.equal(hook.state.count, 5);
  assert.equal(hook.pending.length, 0);
  replies[1].reply({revision: 2, ack_seq: 2, state: {count: 4, step: 1}});
  assert.equal(hook.state.count, 5);
  assert.equal(hook.serverRevision, 3);
});

test("failed server reconciliation leaves the previous prediction intact", () => {
  const el = element({count: 1, step: 1});
  el.dataset.liveLiftMode = "component";
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: () => {},
  };
  hook.mounted();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.throws(() => hook.applyAuthoritative(1, {count: 3}, 1), /Unknown LiveLift state field: step/);
  assert.deepEqual(hook.state, {count: 2, step: 1});
  assert.deepEqual(hook.authoritativeState, {count: 1, step: 1});
  assert.equal(hook.serverRevision, 0);
  assert.equal(hook.pending.length, 1);
});

test("1,000 seeded reply orders converge to the server state", () => {
  for (let seed = 1; seed <= 1_000; seed += 1) {
    const el = element({count: 0, step: 1});
    el.dataset.liveLiftMode = "component";
    const callbacks = [];
    const hook = {
      ...createClientHook({"App.Score": {
        actions: {advance: (state) => ({...state, count: state.count + 1})},
        template: "<output></output>",
      }}),
      el,
      pushEventTo: (_control, _event, _payload, reply) => callbacks.push(reply),
    };
    hook.mounted();
    const count = 1 + (seed % 6);
    for (let index = 0; index < count; index += 1) {
      hook.sendOptimistic(el.controls.advance, "advance", {});
    }

    let serverCount = 0;
    const replies = callbacks.map((_callback, index) => {
      serverCount += 1 + ((seed + index) % 3 === 0 ? 1 : 0);
      return {index, payload: {revision: index + 1, ack_seq: index + 1,
        state: {count: serverCount, step: 1}}};
    });
    let random = seed;
    for (let index = replies.length - 1; index > 0; index -= 1) {
      random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
      const other = random % (index + 1);
      [replies[index], replies[other]] = [replies[other], replies[index]];
    }
    for (const {index, payload} of replies) callbacks[index](payload);
    assert.equal(hook.state.count, serverCount, `seed ${seed}`);
    assert.equal(hook.pending.length, 0, `seed ${seed}`);
    assert.equal(hook.serverRevision, count, `seed ${seed}`);
  }
});
