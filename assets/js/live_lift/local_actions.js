function __liveLiftLocalActions(hook, writes, validateState, validateParams) {
  const {render, sendOptimistic, resetOptimisticSnapshot} = hook;
  let overlay = null;
  let resetLocalDOM = false;

  function visibleState(state) {
    return overlay ? {...state, ...overlay} : state;
  }

  hook.render = function (state = this.state, previous = this.state) {
    render.call(this, visibleState(state),
      previous === null || resetLocalDOM ? null : visibleState(previous));
  };

  hook.resetOptimisticSnapshot = function () {
    if (!overlay || this.el.dataset.liveLiftInstance === this.instance) {
      return resetOptimisticSnapshot();
    }

    const previous = overlay;
    overlay = null;
    resetLocalDOM = true;
    try {
      return resetOptimisticSnapshot();
    } catch (error) {
      if (this.el.dataset.liveLiftInstance !== this.instance) overlay = previous;
      throw error;
    } finally {
      resetLocalDOM = false;
    }
  };

  hook.sendOptimistic = function (control, event, params) {
    if (!Object.hasOwn(writes, event)) return sendOptimistic(control, event, params);

    validateParams(params);
    const previous = visibleState(this.state);
    const next = this.view.actions[event](previous, {
      value: "value" in control ? control.value : null,
      checked: "checked" in control ? control.checked : false,
      params
    });
    validateState(next);
    const updated = {...overlay};
    for (const field of writes[event]) updated[field] = next[field];
    render.call(this, {...this.state, ...updated}, previous);
    overlay = updated;
  };
}
