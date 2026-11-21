function createComponentTimers(specs, hook, validateState) {
  const acknowledged = new Map();
  const provisional = new Map();

  function install(entry) {
    entry.timeout = setTimeout(() => {
      entry.fired = true;
      hook.authoritativeBatch.flush();
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

  function project(state) {
    const fired = [...acknowledged.values(), ...provisional.values()]
      .filter(({fired}) => fired)
      .sort((a, b) => a.due - b.due || a.seq - b.seq);
    for (const {event} of fired) state = {...state, ...specs[event].patch};
    if (fired.length) validateState(state);
    return state;
  }

  function clear() {
    for (const entry of acknowledged.values()) clearTimeout(entry.timeout);
    for (const entry of provisional.values()) clearTimeout(entry.timeout);
    acknowledged.clear();
    provisional.clear();
  }

  accept(hook.el.dataset.liveLiftTimers, hook.ackSequence);
  return {start, accept, project, clear};
}
