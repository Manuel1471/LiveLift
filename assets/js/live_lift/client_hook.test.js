import assert from "node:assert/strict";
import test from "node:test";
import {createClientHook} from "./client_hook.js";

function element(initialState) {
  const countNode = {dataset: {liveLiftText: "count"}, textContent: ""};
  const stepNode = {dataset: {liveLiftText: "step"}, textContent: ""};
  const controls = {
    advance: {dataset: {liveLiftAction: "advance"}},
    retreat: {dataset: {liveLiftAction: "retreat"}},
  };
  const listeners = new Map();

  return {
    dataset: {liveLiftState: JSON.stringify(initialState), liveLiftModule: "App.Score"},
    innerHTML: "",
    countNode,
    stepNode,
    listeners,
    contains: (node) => Object.values(controls).includes(node),
    querySelectorAll: () => [countNode, stepNode],
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
  assert.throws(() => el.click("advance"), /map of safe integers/);
  assert.equal(el.countNode.textContent, "1");
});
