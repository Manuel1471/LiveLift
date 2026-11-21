const __liveLiftClassListeners = new WeakMap();

function __liveLiftPrepareClasses(root, bindings) {
  const effects = new WeakMap();
  const empty = {adds: [], removes: []};

  function update(target, adds, removes, reachedWindow) {
    requestAnimationFrame(() => {
      if (!reachedWindow() || !root.contains(target)) return;
      const prior = effects.get(target) ?? empty;
      const nextAdds = prior.adds.filter((name) => !removes.includes(name))
        .concat(adds.filter((name) => !prior.adds.includes(name) && !target.classList.contains(name)));
      const nextRemoves = prior.removes.filter((name) => !adds.includes(name))
        .concat(removes.filter((name) => !prior.removes.includes(name) && target.classList.contains(name)));
      effects.set(target, {adds: nextAdds, removes: nextRemoves});
      target.__liveLiftPatch = (next) => {
        next.classList.remove(...nextRemoves);
        next.classList.add(...nextAdds);
      };
    });
  }

  function track(target, operation, names, reachedWindow) {
    if (operation === "add_class") update(target, names, [], reachedWindow);
    if (operation === "remove_class") update(target, [], names, reachedWindow);
    if (operation === "toggle_class") {
      requestAnimationFrame(() => {
        if (!reachedWindow() || !root.contains(target)) return;
        const prior = effects.get(target) ?? empty;
        update(
          target,
          names.filter((name) => !prior.adds.includes(name) && !target.classList.contains(name)),
          names.filter((name) => !prior.removes.includes(name) && target.classList.contains(name)),
          reachedWindow,
        );
      });
    }
  }

  __liveLiftClassListeners.get(root)?.abort();
  const controller = new AbortController();
  __liveLiftClassListeners.set(root, controller);

  root.addEventListener("click", (event) => {
    const element = event.target.nodeType === 1 ? event.target : event.target.parentElement;
    let source = element?.closest("[phx-click]");
    while (source?.disabled) source = source.parentElement?.closest("[phx-click]");
    if (!source || !root.contains(source)) return;
    const binding = source.getAttribute("phx-click");
    if (!Object.hasOwn(bindings, binding)) return;
    // Phoenix handles the binding at the window. A stopped click must not
    // affect a later reconciliation.
    const view = root.ownerDocument.defaultView;
    let delivered = false;
    const confirm = (click) => { if (click === event) delivered = true; };
    view.addEventListener("click", confirm);
    setTimeout(() => view.removeEventListener("click", confirm), 0);
    const reachedWindow = () => delivered;

    for (const [operation, {to, names}] of bindings[binding]) {
      const targets = to ? source.querySelectorAll(to.inner) : [source];
      for (const target of targets) {
        track(target, operation, names, reachedWindow);
      }
    }
  }, {signal: controller.signal});
}
