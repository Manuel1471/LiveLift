import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

function summarize(values) {
  const sorted = [...values].sort((left, right) => left - right);
  const percentile = (p) => sorted[Math.ceil(p * sorted.length) - 1];
  return {
    min: sorted[0], median: percentile(.5), p95: percentile(.95), max: sorted.at(-1),
    iqr: percentile(.75) - percentile(.25),
  };
}

for (const cpu of [1, 4]) {
  test(`profile native row editing at ${cpu}x CPU`, async ({page, browserName}) => {
    test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium",
      "Run with LIVE_LIFT_BENCH=1 in Chromium");
    test.setTimeout(120_000);
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Emulation.setCPUThrottlingRate", {rate: cpu});
    await cdp.send("Profiler.enable");
    await cdp.send("Profiler.setSamplingInterval", {interval: 500});

    for (const rows of [100, 1_000]) {
      await gotoLiveLift(page, `/native-list?rows=${rows}`);
      const root = page.locator("#native-list");
      await expect(root.locator("li")).toHaveCount(rows);

      const collect = (count, offset) => root.evaluate(async (component, {count, offset, rows}) => {
        const row = Math.floor(rows / 2);
        const selector = `#row-${row} input[name="label"]`;
        const input = component.querySelector(selector);
        input.focus();
        const samples = [];

        for (let index = offset; index < offset + count; index++) {
          const label = `Edited ${String(index).padStart(3, "0")}`;
          const sequence = Number(component.dataset.liveLiftAckSeq) + 1;
          const sample = await new Promise((resolve, reject) => {
            const observer = new MutationObserver(() => {
              if (Number(component.dataset.liveLiftAckSeq) !== sequence) return;
              observer.disconnect();
              clearTimeout(deadline);
              resolve({localMs, ackMs: performance.now() - start});
            });
            const deadline = setTimeout(() => {
              observer.disconnect();
              reject(new Error(`No acknowledgment for edit ${sequence}`));
            }, 5_000);
            observer.observe(component, {attributes: true, attributeFilter: ["data-live-lift-ack-seq"]});
            input.value = label;
            const start = performance.now();
            input.dispatchEvent(new Event("input", {bubbles: true}));
            const localMs = performance.now() - start;
            if (input.getAttribute("value") !== label) {
              observer.disconnect();
              clearTimeout(deadline);
              reject(new Error("The edit did not render optimistically"));
            }
          });
          samples.push(sample);
        }

        return {
          samples,
          snapshotBytes: new TextEncoder().encode(component.dataset.liveLiftState).length,
          preservedInput: input === component.querySelector(selector),
          preservedFocus: input === document.activeElement,
        };
      }, {count, offset, rows});

      await collect(10, 0);
      const result = await collect(100, 10);
      expect(result.preservedInput).toBe(true);
      expect(result.preservedFocus).toBe(true);

      // Profile a separate batch to keep sampling overhead out of the durations.
      await cdp.send("Profiler.start");
      await collect(100, 110);
      const {profile} = await cdp.send("Profiler.stop");
      const ticks = new Map();
      for (const {callFrame, hitCount = 0} of profile.nodes) {
        if (hitCount && callFrame.url.includes("/assets/js/")) {
          const name = callFrame.functionName || "(anonymous)";
          ticks.set(name, (ticks.get(name) || 0) + hitCount);
        }
      }

      console.log(JSON.stringify({
        rows, cpu, chromium: page.context().browser().version(), samples: 100,
        snapshotBytes: result.snapshotBytes,
        localMs: summarize(result.samples.map((sample) => sample.localMs)),
        ackMs: summarize(result.samples.map((sample) => sample.ackMs)),
        selfSamples: [...ticks].sort((a, b) => b[1] - a[1]).slice(0, 12),
      }));
    }
  });
}
