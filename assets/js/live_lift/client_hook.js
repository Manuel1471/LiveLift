const SAFE_KEY = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
const RESERVED_KEYS = new Set(["__proto__", "constructor", "prototype"]);

function validateValue(value, path, depth = 0) {
  if (typeof value === "string" || typeof value === "boolean" || value === null ||
      Number.isSafeInteger(value)) return;
  if (depth >= 16) throw new Error(`Unsupported LiveLift state value at ${path}`);
  if (Array.isArray(value)) {
    value.forEach((item, index) => validateValue(item, `${path}[${index}]`, depth + 1));
    return;
  }
  if (value && typeof value === "object" && Object.getPrototypeOf(value) === Object.prototype) {
    for (const [key, item] of Object.entries(value)) {
      if (!SAFE_KEY.test(key) || RESERVED_KEYS.has(key)) {
        throw new Error(`Unsafe LiveLift state key at ${path}: ${key}`);
      }
      validateValue(item, `${path}.${key}`, depth + 1);
    }
    return;
  }
  throw new Error(`Unsupported LiveLift state value at ${path}`);
}

function validateState(state) {
  if (!state || typeof state !== "object" || Array.isArray(state)) {
    throw new Error("LiveLift state must be a map");
  }
  validateValue(state, "state");
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
      if (!this.el.hasChildNodes()) {
        this.el.innerHTML = this.view.template;
      }

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
        node.textContent = this.state[field] === null ? "" : String(this.state[field]);
      }

      for (const attribute of ["class", "title", "aria-label", "value"]) {
        for (const node of this.el.querySelectorAll(`[data-live-lift-bind-${attribute}]`)) {
          const field = node.getAttribute(`data-live-lift-bind-${attribute}`);
          if (!Object.hasOwn(this.state, field)) {
            throw new Error(`Unknown LiveLift state field: ${field}`);
          }
          const value = this.state[field];
          node.setAttribute(attribute, value === null ? "" : String(value));
        }
      }

      for (const node of this.el.querySelectorAll("[data-live-lift-show]")) {
        const field = node.dataset.liveLiftShow;
        if (!Object.hasOwn(this.state, field)) {
          throw new Error(`Unknown LiveLift state field: ${field}`);
        }
        node.hidden = this.state[field] === false || this.state[field] === null;
      }
    },
  };
}
