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

test("accepts tagged floats and rejects malformed float state", () => {
  const el = element({count: {$live_lift_float: "-0.0"}, step: 1});
  const hook = {...createClientHook({"App.Score": {actions: {}, template: "<output></output>"}}), el};
  hook.mounted();
  assert.equal(el.countNode.textContent, "-0.0");

  for (const malformed of ["NaN", "Infinity", "1", "1.0e+309"]) {
    const bad = element({count: {$live_lift_float: malformed}, step: 1});
    const badHook = {...createClientHook({"App.Score": {actions: {}, template: "<output></output>"}}), el: bad};
    assert.throws(() => badHook.mounted(), /Invalid LiveLift float/);
  }
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

test("skips rendering unchanged local and acknowledged states", () => {
  const el = element({count: 1, step: 1});
  el.dataset.liveLiftMode = "component";
  const replies = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {
        keep: (state) => ({...state}),
        advance: (state) => ({...state, count: state.count + 1}),
      },
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, _payload, reply) => replies.push(reply),
  };
  hook.mounted();
  const render = hook.render;
  let renders = 0;
  hook.render = (...args) => { renders += 1; return render.call(hook, ...args); };
  hook.runAction("keep", el.controls.advance);
  assert.equal(renders, 0);
  hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.equal(renders, 1);
  replies[0]({revision: 1, ack_seq: 1, state: {count: 2, step: 1}});
  assert.equal(renders, 1);
  assert.equal(hook.state.count, 2);
});

test("accepts nested state and rejects dangerous keys", () => {
  const el = element({count: 1, step: 1, items: [{id: "a", done: false}]});
  const hook = {
    ...createClientHook({"App.Score": {actions: {}, template: []}}),
    el,
  };
  hook.mounted();

  for (const key of ["__proto__", "constructor", "prototype"]) {
    const unsafe = element(JSON.parse(`{"count":1,"step":1,"${key}":1}`));
    const unsafeHook = {...createClientHook({"App.Score": {actions: {}, template: []}}), el: unsafe};
    assert.throws(() => unsafeHook.mounted(), /Unsafe LiveLift state key/);
  }
});

test("enforces list and total state size limits before mounting", () => {
  const view = {"App.Score": {actions: {}, template: "<output></output>"}};
  const mount = (state) => {
    const el = element(state);
    el.hasChildNodes = () => true;
    return {...createClientHook(view), el}.mounted();
  };
  assert.doesNotThrow(() => mount({items: Array(10_000).fill(null)}));
  assert.throws(() => mount({items: Array(10_001).fill(null)}), /list length limit exceeded/);
  assert.throws(() => mount({item: Object.fromEntries(Array.from({length: 1_025}, (_, i) => [`field_${i}`, null]))}),
    /map field limit exceeded/);
  assert.throws(() => mount({text: "é".repeat(524_289)}), /state size limit exceeded/);
  assert.throws(() => mount({groups: Array(50).fill({items: Array(1_000).fill(null)})}),
    /state size limit exceeded/);
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
  for (const key of ["__proto__", "constructor", "prototype"]) {
    const params = Object.fromEntries([[key, "x"]]);
    assert.throws(() => hook.sendOptimistic(el.controls.advance, "advance", params), /Unsafe LiveLift event parameter/);
  }
  assert.equal(hook.state.count, 1);
});

test("native component accepts bounded nested event parameters", () => {
  const el = element({count: 1, step: 1});
  el.dataset.liveLiftMode = "component";
  let sent;
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state, event) => ({...state, count: state.count + event.params.profile.note.length})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_target, _name, params) => { sent = params; },
  };
  hook.mounted();
  hook.sendOptimistic(el.controls.advance, "advance", {profile: {note: "é"}});
  assert.equal(hook.state.count, 2);
  assert.deepEqual(sent, {profile: {note: "é"}, _live_lift_seq: 1});
  for (const params of [
    {profile: {}},
    {profile: Object.fromEntries([["__proto__", "x"]])},
    {a: {b: {c: {d: {e: "x"}}}}},
  ]) {
    assert.throws(() => hook.sendOptimistic(el.controls.advance, "advance", params), /LiveLift event parameter/);
  }
  assert.equal(hook.state.count, 2);
});

test("native component rejects oversized event parameters before prediction", () => {
  const el = element({count: 1, step: 1});
  el.dataset.liveLiftMode = "component";
  const hook = {
    ...createClientHook({"App.Score": {actions: {advance: (state) => ({...state, count: state.count + 1})}, template: "<output></output>"}}),
    el,
    pushEventTo: () => assert.fail("oversized event reached server"),
  };
  hook.mounted();
  const many = Object.fromEntries(Array.from({length: 65}, (_, i) => [`field_${i}`, "x"]));
  assert.throws(() => hook.sendOptimistic(el.controls.advance, "advance", many), /event parameter limit exceeded/);
  assert.throws(() => hook.sendOptimistic(el.controls.advance, "advance", {note: "é".repeat(32_769)}),
    /event parameter size limit exceeded/);
  assert.equal(hook.state.count, 1);
  assert.equal(hook.pending.length, 0);
  assert.equal(hook.nextSequence, 1);
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

test("authoritative replies in one frame render only the newest snapshot", (t) => {
  const frames = new Map();
  let nextFrame = 0;
  const oldRaf = globalThis.requestAnimationFrame;
  const oldCancel = globalThis.cancelAnimationFrame;
  globalThis.requestAnimationFrame = (callback) => {
    frames.set(++nextFrame, callback);
    return nextFrame;
  };
  globalThis.cancelAnimationFrame = (id) => frames.delete(id);
  t.after(() => {
    if (oldRaf) globalThis.requestAnimationFrame = oldRaf;
    else delete globalThis.requestAnimationFrame;
    if (oldCancel) globalThis.cancelAnimationFrame = oldCancel;
    else delete globalThis.cancelAnimationFrame;
  });
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  const replies = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, _payload, reply) => replies.push(reply),
  };
  hook.mounted();
  const rendered = [];
  hook.render = (state) => rendered.push(state.count);
  hook.sendOptimistic(el.controls.advance, "advance", {});
  hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.deepEqual(rendered, [1, 2]);

  replies[1]({revision: 2, ack_seq: 2, state: {count: 20, step: 1}});
  replies[0]({revision: 1, ack_seq: 1, state: {count: 10, step: 1}});
  assert.equal(frames.size, 1);
  assert.deepEqual(rendered, [1, 2]);
  frames.values().next().value();
  assert.deepEqual(rendered, [1, 2, 20]);
  assert.equal(hook.pending.length, 0);
  assert.equal(hook.serverRevision, 2);

  hook.sendOptimistic(el.controls.advance, "advance", {});
  replies[2]({revision: 3, ack_seq: 3, state: {count: 30, step: 1}});
  assert.equal(frames.size, 1);
  hook.disconnected();
  assert.equal(frames.size, 0);
  assert.deepEqual(rendered, [1, 2, 20, 21]);
  hook.destroyed();
});

test("a gap recovers a missing request and drains queued actions in order", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  const requests = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, payload, reply) => requests.push({payload, reply}),
  };
  hook.mounted();
  for (let index = 0; index < 3; index += 1) hook.sendOptimistic(el.controls.advance, "advance", {});
  const sequences = () => requests.map(({payload}) => payload._live_lift_seq);
  const response = (ack_seq) => ({revision: ack_seq, ack_seq, state: {count: ack_seq, step: 1}});

  // Pretend the first request was lost and deliver two gap replies for later actions.
  requests[2].reply({...response(0), expected_seq: 1});
  requests[1].reply({...response(0), expected_seq: 1});
  assert.deepEqual(sequences(), [1, 2, 3, 1]);
  hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.equal(hook.state.count, 4);

  requests[3].reply(response(1));
  requests[3].reply(response(1));
  assert.deepEqual(sequences(), [1, 2, 3, 1, 2]);
  requests[4].reply(response(2));
  requests[5].reply(response(3));
  requests[6].reply(response(4));
  assert.deepEqual(sequences(), [1, 2, 3, 1, 2, 3, 4]);
  assert.equal(hook.pending.length, 0);
  assert.equal(hook.recovery, null);
  assert.equal(hook.state.count, 4);
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
    for (const {index, payload} of replies) {
      callbacks[index](payload);
      if ((seed + index) % 2 === 0) callbacks[index](payload);
    }
    assert.equal(hook.state.count, serverCount, `seed ${seed}`);
    assert.equal(hook.pending.length, 0, `seed ${seed}`);
    assert.equal(hook.serverRevision, count, `seed ${seed}`);
  }
});

test("1,000 seeded request and reply schedules converge in action order", () => {
  for (let seed = 1; seed <= 1_000; seed += 1) {
    const el = element({count: "", step: 1});
    el.dataset.liveLiftMode = "component";
    const requests = [];
    const replies = [];
    const hook = {
      ...createClientHook({"App.Score": {
        actions: {advance: (state, event) => ({...state, count: state.count + event.params.digit})},
        template: "<output></output>",
      }}),
      el,
      pushEventTo: (_control, _event, payload, reply) => requests.push({payload, reply}),
    };
    hook.mounted();
    const actions = Array.from({length: 2 + (seed % 7)}, (_, index) => String(index + 1));
    for (const digit of actions) hook.sendOptimistic(el.controls.advance, "advance", {digit});

    let random = seed;
    function choose(list) {
      random = (Math.imul(random, 1664525) + 1013904223) >>> 0;
      return list.splice(random % list.length, 1)[0];
    }

    // Lose the first request, deliver a later request twice, and shuffle both directions.
    requests.shift();
    requests.push(requests.at(-1));
    let ack = 0;
    let server = "";
    let steps = 0;
    while (requests.length || replies.length) {
      assert.ok(++steps < 100, `bounded recovery for seed ${seed}`);
      if (requests.length && (!replies.length || random % 3 !== 0)) {
        const {payload, reply} = choose(requests);
        const sequence = payload._live_lift_seq;
        if (sequence === ack + 1) {
          ack = sequence;
          server += payload.digit;
        }
        const snapshot = {ack_seq: ack, revision: ack, state: {count: server, step: 1}};
        if (sequence > ack) snapshot.expected_seq = ack + 1;
        replies.push(() => reply(snapshot));
        if (random % 7 === 0) replies.push(() => reply(snapshot));
      } else {
        choose(replies)();
      }
    }
    assert.equal(server, actions.join(""), `server order for seed ${seed}`);
    assert.equal(hook.state.count, server, `convergence for seed ${seed}`);
    assert.equal(hook.pending.length, 0, `empty queue for seed ${seed}`);
  }
});

test("a disconnected component drops pending predictions and stale replies at snapshot", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  const replies = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, _payload, reply) => replies.push(reply),
  };
  hook.mounted();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.equal(hook.state.count, 1);
  hook.disconnected();
  el.dataset.liveLiftState = JSON.stringify({count: 7, step: 1});
  el.dataset.liveLiftServerRevision = "3";
  el.dataset.liveLiftAckSeq = "1";
  hook.updated();
  assert.equal(hook.state.count, 7);
  assert.equal(hook.pending.length, 0);
  replies[0]({revision: 1, ack_seq: 1, state: {count: 1, step: 1}});
  assert.equal(hook.state.count, 7);
  assert.equal(hook.serverRevision, 3);
  assert.equal(hook.nextSequence, 2);
});

test("offline actions replay only after a fresh snapshot and receive new sequences", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  const sent = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, payload, reply) => sent.push({payload, reply}),
  };
  hook.mounted();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  hook.disconnected();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.equal(hook.state.count, 2);
  assert.equal(hook.offlineQueue.length, 1);
  assert.equal(sent.length, 1);

  el.dataset.liveLiftState = JSON.stringify({count: 7, step: 1});
  el.dataset.liveLiftServerRevision = "3";
  el.dataset.liveLiftAckSeq = "1";
  hook.updated();
  assert.equal(hook.state.count, 8);
  assert.equal(hook.offlineQueue.length, 0);
  assert.deepEqual(hook.pending.map(({sequence}) => sequence), [2]);
  assert.equal(sent.length, 2);
  assert.equal(sent[1].payload._live_lift_seq, 2);
  sent[0].reply({revision: 1, ack_seq: 1, state: {count: 1, step: 1}});
  assert.equal(hook.state.count, 8);
  sent[1].reply({revision: 4, ack_seq: 2, state: {count: 8, step: 1}});
  assert.equal(hook.pending.length, 0);
  assert.equal(hook.state.count, 8);
});

test("reconnect to the same instance retries only unacknowledged actions with original IDs", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  el.dataset.liveLiftInstance = "same";
  const sent = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, payload, reply) => sent.push({payload, reply}),
  };
  hook.mounted();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  hook.sendOptimistic(el.controls.advance, "advance", {name: "second"});
  hook.disconnected();
  hook.sendOptimistic(el.controls.advance, "advance", {name: "offline"});

  el.dataset.liveLiftState = JSON.stringify({count: 1, step: 1});
  el.dataset.liveLiftServerRevision = "1";
  el.dataset.liveLiftAckSeq = "1";
  hook.updated();

  assert.equal(hook.state.count, 3);
  assert.deepEqual(sent.map(({payload}) => payload._live_lift_seq), [1, 2, 2]);
  assert.deepEqual(sent[2].payload, sent[1].payload);
  sent[1].reply({revision: 2, ack_seq: 2, state: {count: 99, step: 1}});
  assert.equal(hook.state.count, 3);
  sent[2].reply({revision: 2, ack_seq: 2, state: {count: 2, step: 1}});
  assert.deepEqual(sent[3].payload, {name: "offline", _live_lift_seq: 3});
  sent[3].reply({revision: 3, ack_seq: 3, state: {count: 3, step: 1}});
  assert.equal(hook.pending.length, 0);
  assert.equal(hook.state.count, 3);
});

test("an instance change discards offline actions when configured", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  el.dataset.liveLiftInstance = "old";
  el.dataset.liveLiftReconnectConflict = "discard";
  const sent = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, payload) => sent.push(payload),
  };
  hook.mounted();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  hook.disconnected();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  el.dataset.liveLiftInstance = "new";
  hook.updated();
  assert.equal(hook.state.count, 0);
  assert.equal(hook.pending.length, 0);
  assert.equal(hook.offlineQueue.length, 0);
  assert.equal(sent.length, 1);
  hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.equal(sent[1]._live_lift_seq, 1);
});

test("expired offline actions roll back to the new server snapshot", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  const sent = [];
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: (_control, _event, payload) => sent.push(payload),
  };
  hook.mounted();
  hook.disconnected();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  hook.offlineQueue[0].createdAt -= 30_001;
  el.dataset.liveLiftState = JSON.stringify({count: 7, step: 1});
  el.dataset.liveLiftServerRevision = "3";
  hook.updated();
  assert.equal(hook.state.count, 7);
  assert.equal(hook.offlineQueue.length, 0);
  assert.equal(sent.length, 0);
});

test("offline action queue is bounded before changing local state", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => ({...state, count: state.count + 1})},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: () => assert.fail("offline actions must not be sent before a snapshot"),
  };
  hook.mounted();
  hook.disconnected();
  for (let index = 0; index < 100; index += 1) hook.sendOptimistic(el.controls.advance, "advance", {});
  assert.equal(hook.state.count, 100);
  assert.equal(hook.offlineQueue.length, 100);
  assert.throws(() => hook.sendOptimistic(el.controls.advance, "advance", {}), /pending action limit/);
  assert.equal(hook.state.count, 100);
});

test("an offline replay conflict restores the server snapshot and clears the queue", () => {
  const el = element({count: 0, step: 1});
  el.dataset.liveLiftMode = "component";
  const hook = {
    ...createClientHook({"App.Score": {
      actions: {advance: (state) => {
        if (state.count === 7) throw new Error("item changed on server");
        return {...state, count: state.count + 1};
      }},
      template: "<output></output>",
    }}),
    el,
    pushEventTo: () => assert.fail("conflicting action must not reach the server"),
  };
  hook.mounted();
  hook.disconnected();
  hook.sendOptimistic(el.controls.advance, "advance", {});
  el.dataset.liveLiftState = JSON.stringify({count: 7, step: 1});
  el.dataset.liveLiftServerRevision = "3";
  assert.throws(() => hook.updated(), /offline replay conflict/);
  assert.equal(hook.state.count, 7);
  assert.equal(hook.offline, false);
  assert.equal(hook.offlineQueue.length, 0);
  assert.equal(hook.pending.length, 0);
  assert.equal(hook.serverRevision, 3);
});
