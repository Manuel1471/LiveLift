/**
 * A LiveView hook for the local counter component.
 * LiveView owns the initial HTML; this hook owns the count after mounting.
 */
const Counter = {
  mounted() {
    const initial = Number(this.el.dataset.liveLiftInitial);
    this.count = Number.isSafeInteger(initial) ? initial : 0;

    this.onClick = (event) => {
      const action = event.target.closest("[data-live-lift-action]");
      if (!action || !this.el.contains(action)) return;

      if (action.dataset.liveLiftAction === "increment") this.count += 1;
      if (action.dataset.liveLiftAction === "decrement") this.count -= 1;
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

export default Counter;
export const hooks = {"LiveLift.Counter": Counter};
