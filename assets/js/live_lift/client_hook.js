function validateState(state) {
  if (
    state === null ||
    typeof state !== "object" ||
    Array.isArray(state) ||
    !Object.values(state).every(Number.isSafeInteger)
  ) {
    throw new Error("LiveLift state must be a map of safe integers");
  }
}

/**
 * Runs user-defined client actions in a LiveView-owned page.
 * The app supplies its own HEEx and marks only the locally owned DOM subtree.
 */
export function createClientHook(views) {
  return {
    mounted() {
      this.view = views[this.el.dataset.liveLiftModule];
      if (!this.view) {
        throw new Error(`Unknown LiveLift view: ${this.el.dataset.liveLiftModule}`);
      }

      this.state = JSON.parse(this.el.dataset.liveLiftState);
      validateState(this.state);
      this.el.innerHTML = this.view.template;

      this.onClick = (event) => {
        const control = event.target.closest(
          "[data-live-lift-action], [data-live-lift-server]",
        );
        if (!control || !this.el.contains(control)) return;

        const serverEvent = control.dataset.liveLiftServer;
        if (serverEvent) {
          this.pushEvent(serverEvent, {state: this.state});
          return;
        }

        const actionName = control.dataset.liveLiftAction;
        const actions = this.view.actions;
        const action = Object.hasOwn(actions, actionName) ? actions[actionName] : undefined;
        if (typeof action !== "function") {
          throw new Error(`Unknown LiveLift action: ${actionName}`);
        }

        const nextState = action(this.state);
        validateState(nextState);
        this.state = nextState;
        this.render();
      };

      this.el.addEventListener("click", this.onClick);
      this.render();
    },

    destroyed() {
      this.el.removeEventListener("click", this.onClick);
    },

    render() {
      for (const node of this.el.querySelectorAll("[data-live-lift-text]")) {
        const field = node.dataset.liveLiftText;
        if (!Object.hasOwn(this.state, field)) {
          throw new Error(`Unknown LiveLift state field: ${field}`);
        }
        node.textContent = String(this.state[field]);
      }
    },
  };
}
