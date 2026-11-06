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
  assert.throws(() => el.click("advance"), /safe integers/);
  assert.equal(el.countNode.textContent, "1");
});

test("renders browser-safe primitives and dynamic attributes", () => {
  const el = element({count: null, step: true, style: "active", title: "<ready>"});
  const attributes = new Map();
  const node = {
    getAttribute: (name) => name === "data-live-lift-bind-class" ? "style" : "title",
    setAttribute: (name, value) => attributes.set(name, value),
  };
  const originalQuery = el.querySelectorAll;
  el.querySelectorAll = (selector) => selector === "[data-live-lift-bind-class]" ||
    selector === "[data-live-lift-bind-title]" ? [node] : originalQuery(selector);
  const hook = {
    ...createClientHook({"App.Score": {actions: {}, template: "<p></p>"}}),
    el,
  };

  hook.mounted();
  assert.equal(el.countNode.textContent, "");
  assert.equal(el.stepNode.textContent, "true");
  assert.equal(attributes.get("class"), "active");
  assert.equal(attributes.get("title"), "<ready>");
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

  assert.deepEqual(sent, [{name: "save_score", payload: {state: {count: 13, step: 3}}}]);
});
