/**
 * A LiveView hook for the local counter component.
 * LiveView owns the initial HTML; this hook owns the count after mounting.
 */
export function createCounterHook(actions) {
  return {
    mounted() {
      const initial = Number(this.el.dataset.liveLiftInitial);
      this.count = Number.isSafeInteger(initial) ? initial : 0;

      this.onClick = (event) => {
        const action = event.target.closest("[data-live-lift-action]");
        if (!action || !this.el.contains(action)) return;

        const actionName = action.dataset.liveLiftAction;
        const clientAction = Object.hasOwn(actions, actionName)
          ? actions[actionName]
          : undefined;

        if (typeof clientAction !== "function") return;

        const result = clientAction(this.count);
        if (!Number.isSafeInteger(result)) {
          throw new Error(`LiveLift action ${actionName} must return a safe integer`);
        }

        this.count = result;
        this.render();
      };

      this.el.addEventListener("click", this.onClick);
      this.render();
    },

    destroyed() {
      this.el.removeEventListener("click", this.onClick);
    },

    render() {
      this.el.querySelector("[data-live-lift-value]").textContent = String(this.count);
    },
  };
}
