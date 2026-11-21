function createComponentTimers(specs, hook, validateState) {
  const acknowledged = new Map();
  const provisional = new Map();
  let firedOrder = 0;

  function install(entry) {
    entry.timeout = setTimeout(() => {
      hook.authoritativeBatch.flush();
      entry.fired = ++firedOrder;
      entry.afterSequence = hook.nextSequence - 1;
      // Reproject the current base without replacing the accepted timer snapshot.
      hook.applyAuthoritative(hook.serverRevision, hook.authoritativeState, hook.ackSequence, false);
    }, Math.max(0, entry.due - performance.now()));
    return entry;
  }

  function start(event, seq) {
    if (!Object.hasOwn(specs, event) || provisional.has(seq) ||
        acknowledged.size + provisional.size >= 32) return;
    provisional.set(seq, install({event, seq, due: performance.now() + specs[event].delay}));
  }

  function accept(descriptors, ack) {
    if (descriptors === false) return;
    const keep = new Set();
    const now = performance.now();
    if (typeof descriptors === "string") descriptors = JSON.parse(descriptors);
    descriptors ??= [];
    for (const {id, event, seq, remaining} of descriptors) {
      keep.add(id);
      if (acknowledged.has(id)) continue;
      const local = seq > 0 ? provisional.get(seq) : undefined;
      if (local) provisional.delete(seq);
      acknowledged.set(id, local ?? install({event, seq, due: now + remaining}));
    }
    for (const [id, entry] of acknowledged) {
      if (keep.has(id)) continue;
      clearTimeout(entry.timeout);
      acknowledged.delete(id);
    }
    for (const [seq, entry] of provisional) {
      if (seq > ack) continue;
      clearTimeout(entry.timeout);
      provisional.delete(seq);
    }
  }

  function replay(actions, state, pending, replayActions) {
    const fired = [...acknowledged.values(), ...provisional.values()]
      .filter(({fired}) => fired)
      .sort((a, b) => a.fired - b.fired);
    let index = 0;
    for (const {event, afterSequence} of fired) {
      const start = index;
      while (index < pending.length && pending[index].sequence <= afterSequence) index++;
      state = replayActions(actions, state, pending.slice(start, index));
      const spec = specs[event];
      state = spec.run ? spec.run(state) : {...state, ...spec.patch};
      validateState(state);
    }
    return replayActions(actions, state, pending.slice(index));
  }

  function suspend() {
    for (const entry of acknowledged.values()) clearTimeout(entry.timeout);
    for (const entry of provisional.values()) clearTimeout(entry.timeout);
    provisional.clear();
  }

  function clear() {
    suspend();
    acknowledged.clear();
  }

  function resume(keepBase, ack) {
    if (keepBase) {
      for (const entry of acknowledged.values()) {
        entry.fired = 0;
        install(entry);
      }
    } else {
      clear();
      accept(hook.el.dataset.liveLiftTimers, ack);
    }
  }

  accept(hook.el.dataset.liveLiftTimers, hook.ackSequence);
  return {start, accept, replay, suspend, resume, clear};
}
