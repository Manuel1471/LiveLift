import {parseHTML} from "linkedom";
import {createClientHook} from "../assets/js/live_lift/client_hook.js";
import {views} from "../examples/demo/assets/js/generated_views.js";
import assert from "node:assert/strict";

function stats(values) {
  values.sort((a, b) => a - b);
  return {median_ms: values[Math.floor(values.length / 2)], p95_ms: values[Math.floor(values.length * 0.95)]};
}

// Reuse depends on what a row reads, even after its state was decoded into new objects.
{
  const {document} = parseHTML("<html><body><div id='probe'></div></body></html>");
  globalThis.document = document;
  const el = document.getElementById("probe");
  el.dataset.liveLiftModule = "Probe";
  el.dataset.liveLiftState = JSON.stringify({items: [{id: 1, name: "Row", note: ""}], label: "old", revision: 0});
  const path = (root, fields) => ({type: "path", root, fields});
  const row = {type: "element", tag: "li", attrs: [], children: [
    {type: "binding", expr: path("state", ["label"])},
    {type: "binding", expr: path("item", ["name"])},
  ], for: {var: "item", source: path("state", ["items"])},
  key: path("item", ["id"]), if: null, node_id: "probe:1"};
  const template = [{type: "element", tag: "ul", attrs: [], children: [row],
    for: null, key: null, if: null, node_id: null},
    {type: "binding", expr: path("state", ["revision"])}];
  const hook = {...createClientHook({Probe: {template,
    actions: {
      change: (state) => ({...state, label: "new"}),
      copy: (state) => ({
        ...state, revision: 1, items: [{...state.items[0], note: "not rendered"}],
      }),
      edit: (state) => ({...state, items: [{...state.items[0], name: "Edited"}]}),
    }}}), el};
  hook.mounted();
  const element = el.querySelector("li");
  const createElement = document.createElement.bind(document);
  let rowAllocations = 0;
  document.createElement = (tag, ...args) => {
    if (tag === "li") rowAllocations += 1;
    return createElement(tag, ...args);
  };

  hook.runAction("copy", el);
  assert.equal(rowAllocations, 0);
  assert.equal(el.querySelector("li"), element);
  hook.runAction("change", el);
  assert.equal(el.querySelector("li").textContent, "newRow");
  hook.runAction("edit", el);
  assert.equal(el.querySelector("li").textContent, "newEdited");
  assert.equal(el.querySelector("li"), element);
  hook.destroyed();
}

const results = {};
for (const size of [10, 100, 1000]) {
  const {document} = parseHTML("<html><body><div id='tasks'></div></body></html>");
  globalThis.document = document;
  const el = document.getElementById("tasks");
  el.dataset.liveLiftModule = "LiveLiftDemo.TaskListView";
  el.dataset.liveLiftState = JSON.stringify({
    items: Array.from({length: size}, (_, index) => ({id: index + 1, name: `Task ${index + 1}`})),
    next_id: size + 1, draft: "", has_items: true, empty: false,
  });
  const hook = {...createClientHook(views), el};
  hook.mounted();
  const button = el.querySelector("[data-live-lift-action='reverse']");
  button.click();
  assert.equal(el.querySelectorAll("[data-live-lift-key]").length, size);
  assert.equal(el.querySelector("[data-live-lift-key]").getAttribute("data-live-lift-key"), String(size));
  const samples = [];
  for (let i = 0; i < 50; i++) {
    const start = performance.now();
    button.click();
    samples.push(performance.now() - start);
  }
  hook.view.actions.__benchmark_noop = (state) => ({...state});
  const noChange = [];
  for (let i = 0; i < 50; i++) {
    const start = performance.now();
    hook.runAction("__benchmark_noop", button);
    noChange.push(performance.now() - start);
  }
  delete hook.view.actions.__benchmark_noop;
  results[size] = {reverse: stats(samples), no_change: stats(noChange)};
  hook.destroyed();
}
console.log(JSON.stringify({node: process.version, library: "linkedom", samples_per_size: 50, list_actions: results}, null, 2));
