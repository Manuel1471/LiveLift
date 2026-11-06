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
