const MAX_FRAMES = 64;
const MAX_FRAME_LENGTH = 65_536;
const TOO_LARGE = "This state exceeds the inspector's snapshot size limit.";

export function withStateInspector(hook, document) {
  const islands = new Map();
  let frames = [];
  let nextFrame = 1;
  let selectedFrame = null;

  const element = (tag, text) => {
    const node = document.createElement(tag);
    if (text) node.textContent = text;
    return node;
  };
  const button = (label, action) => {
    const node = element("button", label);
    node.type = "button";
    node.addEventListener("click", action);
    return node;
  };

  const dialog = element("dialog");
  const heading = element("h2", "LiveLift state inspector");
  heading.id = "live-lift-state-inspector-heading";
  dialog.setAttribute("aria-labelledby", heading.id);
  dialog.style.cssText = "width:min(46rem,92vw);max-height:85vh;padding:1.25rem;border:1px solid;border-radius:.5rem;margin:auto;background:Canvas;color:CanvasText";

  const island = element("select");
  const label = element("label", "Island ");
  label.append(island);
  island.addEventListener("change", () => selectFrame(null));

  const position = element("p");
  position.setAttribute("role", "status");
  const value = element("pre");
  value.setAttribute("aria-label", "State snapshot");
  value.style.cssText = "margin-block:1rem;max-height:52vh;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere";

  const previous = button("Previous snapshot", () => step(-1));
  const next = button("Next snapshot", () => step(1));
  const latest = button("Follow live", () => selectFrame(null));
  const close = button("Close inspector", () => dialog.close());
  const controls = element("div");
  controls.style.cssText = "display:flex;flex-wrap:wrap;gap:1rem;margin-block:1rem";
  controls.append(previous, next, latest, close);
  dialog.append(heading, label, controls, position, value);

  const open = button("Inspect LiveLift state", () => {
    render();
    dialog.showModal();
  });
  open.style.cssText = "position:fixed;right:1rem;bottom:1rem;z-index:1000;border:1px solid;border-radius:.35rem;padding:.4rem .65rem;background:Canvas;color:CanvasText";
  document.body.append(open, dialog);

  function currentFrames() {
    return frames.filter(({id}) => String(id) === island.value);
  }

  function selectFrame(number) {
    selectedFrame = number;
    render();
  }

  function step(offset) {
    const matching = currentFrames();
    const index = selectedFrame === null
      ? matching.length - 1
      : matching.findIndex(({number}) => number === selectedFrame);

    const frame = matching[index + offset];
    if (frame) selectFrame(frame.number);
  }

  function render() {
    const matching = currentFrames();
    let index = selectedFrame === null
      ? matching.length - 1
      : matching.findIndex(({number}) => number === selectedFrame);

    if (index === -1 && selectedFrame !== null && matching.length) {
      index = 0;
      selectedFrame = matching[0].number;
    }

    const frame = matching[index];
    previous.disabled = index <= 0;
    next.disabled = index < 0 || index >= matching.length - 1;
    latest.disabled = selectedFrame === null || !frame;
    island.disabled = islands.size === 0;
    value.textContent = frame?.text ?? "";
    position.textContent = frame
      ? `${selectedFrame === null ? "Live" : "History"} · Snapshot ${frame.number}`
      : islands.size ? "Waiting for a state snapshot." : "No mounted LiveLift islands.";
  }

  function record(entry, state) {
    let text;
    try {
      text = JSON.stringify(state, null, 2);
    } catch {
      return;
    }
    if (!text) return;
    if (text.length > MAX_FRAME_LENGTH) text = TOO_LARGE;

    const preceding = frames.findLast(({id}) => id === entry.id);
    if (preceding?.text === text) return;
    frames.push({id: entry.id, number: nextFrame++, text});
    if (frames.length > MAX_FRAMES) frames.shift();
    if (dialog.open) render();
  }

  let nextIsland = 0;
  return {
    ...hook,
    mountView(...args) {
      const mounted = hook.mountView.apply(this, args);
      const id = nextIsland++;
      const option = element("option", this.el.id || this.el.dataset.liveLiftModule);
      option.value = String(id);
      island.append(option);
      const entry = {id, option};
      islands.set(this, entry);

      this.recordLocalState = (next) => record(entry, next);
      let value = this.state;
      Object.defineProperty(this, "state", {
        configurable: true,
        enumerable: true,
        get: () => value,
        set(next) {
          value = next;
          record(entry, this.visibleLocalState?.() ?? next);
        },
      });
      record(entry, value);
      return mounted;
    },
    destroyed() {
      try {
        return hook.destroyed.call(this);
      } finally {
        const entry = islands.get(this);
        if (entry) {
          const wasSelected = island.value === String(entry.id);
          entry.option.remove();
          islands.delete(this);
          frames = frames.filter(({id}) => id !== entry.id);
          if (wasSelected) selectedFrame = null;
          if (dialog.open) render();
        }
      }
    },
  };
}
