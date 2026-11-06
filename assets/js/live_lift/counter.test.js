import assert from "node:assert/strict";
import test from "node:test";
import {createCounterHook} from "./counter.js";

function element(initial) {
  const output = {textContent: ""};
  const actions = {
    increment: {dataset: {liveLiftAction: "increment"}},
    decrement: {dataset: {liveLiftAction: "decrement"}},
  };
  const listeners = new Map();

  return {
    dataset: {liveLiftInitial: String(initial)},
    output,
    actions,
    listeners,
    contains: (node) => Object.values(actions).includes(node),
    querySelector: () => output,
    addEventListener: (name, callback) => listeners.set(name, callback),
    removeEventListener: (name) => listeners.delete(name),
    click(action) {
      listeners.get("click")({target: {closest: () => actions[action]}});
    },
  };
}

test("counter updates locally and releases its listener", () => {
  const el = element(10);
  const hook = {
    ...createCounterHook({increment: (count) => count + 3, decrement: (count) => count - 2}),
    el,
  };

  hook.mounted();
  assert.equal(el.output.textContent, "10");
  el.click("increment");
  assert.equal(el.output.textContent, "13");
  el.click("decrement");
  assert.equal(el.output.textContent, "11");
  hook.destroyed();
  assert.equal(el.listeners.size, 0);
});

test("counter rejects results outside JavaScript's safe integer range", () => {
  const el = element(1);
  const hook = {...createCounterHook({increment: () => Number.MAX_SAFE_INTEGER + 1}), el};

  hook.mounted();
  assert.throws(() => el.click("increment"), /must return a safe integer/);
  assert.equal(el.output.textContent, "1");
});
