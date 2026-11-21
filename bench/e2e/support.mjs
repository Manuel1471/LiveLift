export async function gotoLiveLift(page, path) {
  await page.goto(path);
  await page.waitForFunction(() => window.liveSocket?.isConnected() &&
    [...document.querySelectorAll('[phx-hook="LiveLift"]')].every(
      (island) => island.dataset.liveLiftLoad === "ready"
    ));
}

export async function measureCounterClick(page, optimistic) {
  return page.evaluate((optimistic) => {
    const root = document.querySelector(optimistic
      ? "#native-counter"
      : 'section[aria-label="Native LiveComponent counter"]');
    const button = root?.querySelector('button[phx-click="inc"]');
    const output = root?.querySelector("output");
    if (!button || !output) throw new Error("Native counter is unavailable");

    const expectedCount = String(Number(output.textContent) + 1);
    const expectedAck = Number(root.dataset.liveLiftAckSeq) + 1;
    if (optimistic && !Number.isSafeInteger(expectedAck)) {
      throw new Error("Native counter acknowledgment is unavailable");
    }

    return new Promise((resolve, reject) => {
      let started;
      let visibleMs;
      const observer = new MutationObserver(sample);
      const deadline = setTimeout(() => {
        observer.disconnect();
        reject(new Error("Counter update and acknowledgment did not arrive"));
      }, 5_000);

      function sample() {
        const elapsed = performance.now() - started;
        if (root.querySelector("output")?.textContent === expectedCount) visibleMs ??= elapsed;
        if (visibleMs === undefined || (optimistic && Number(root.dataset.liveLiftAckSeq) < expectedAck)) return;
        observer.disconnect();
        clearTimeout(deadline);
        resolve({visibleMs, confirmedMs: elapsed});
      }

      observer.observe(root, {
        subtree: true,
        childList: true,
        characterData: true,
        attributes: true,
        attributeFilter: ["data-live-lift-ack-seq"],
      });
      started = performance.now();
      button.click();
      sample();
    });
  }, optimistic);
}
