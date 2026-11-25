import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

const serverPage = "/native-counter-server";
const listPage = "/native-list?rows=1000";

async function navigate(page, path) {
  await page.evaluate((href) => {
    const link = document.createElement("a");
    link.href = href;
    link.dataset.phxLink = "redirect";
    link.dataset.phxLinkState = "push";
    document.body.append(link);
    link.click();
    link.remove();
  }, path);
  await expect(page).toHaveURL((url) => url.pathname + url.search === path);
  await page.waitForFunction(() => window.liveSocket?.isConnected());
  expect(await page.evaluate(() => window.liveLiftMemoryProbe !== undefined)).toBe(true);
}

async function collect(page, cdp) {
  for (let pass = 0; pass < 2; pass += 1) {
    await page.evaluate(() => new Promise((resolve) => {
      requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
    }));
    await cdp.send("HeapProfiler.collectGarbage");
  }
  const {documents, nodes, jsEventListeners} = await cdp.send("Memory.getDOMCounters");
  const {usedSize} = await cdp.send("Runtime.getHeapUsage");
  const retainedSamples = await page.evaluate(
    () => window.liveLiftMemoryProbe.references.filter((reference) => reference.deref()).length,
  );
  return {documents, nodes, listeners: jsEventListeners, usedHeapBytes: usedSize, retainedSamples};
}

async function islandListenerCount(cdp) {
  const {result} = await cdp.send("Runtime.evaluate", {
    expression: "window.liveLiftMemoryProbe.island",
    objectGroup: "retention-probe",
  });
  try {
    const {listeners} = await cdp.send("DOMDebugger.getEventListeners", {objectId: result.objectId});
    return listeners.length;
  } finally {
    await cdp.send("Runtime.releaseObjectGroup", {objectGroup: "retention-probe"});
  }
}

async function visitList(page, listenerCount) {
  await navigate(page, listPage);
  const root = page.locator("#native-list");
  await expect(root).toHaveAttribute("data-live-lift-load", "ready");
  await expect(root.locator("li")).toHaveCount(1_000);
  await root.evaluate((island) => {
    const probe = window.liveLiftMemoryProbe;
    probe.island = island;
    if (probe.references) {
      const rows = island.querySelectorAll("li");
      for (const node of [island, rows[0], rows[499], rows[999]]) {
        probe.references.push(new WeakRef(node));
      }
    }
    const button = island.querySelector('button[phx-click="reverse"]');
    for (let i = 0; i < 5; i += 1) button.click();
  });
  await expect(root.locator("li").first()).toHaveAttribute("id", "row-1000");
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "5");
  const mountedListeners = await listenerCount();
  expect(mountedListeners, "mounted island listeners").toBeGreaterThan(0);

  await navigate(page, serverPage);
  await expect(root).toHaveCount(0);
  expect(await page.evaluate(() => window.liveLiftMemoryProbe.island.isConnected)).toBe(false);

  try {
    expect(await listenerCount(), "detached island listeners").toBe(0);
  } finally {
    await page.evaluate(() => { delete window.liveLiftMemoryProbe.island; });
  }
  return mountedListeners;
}

test("native lists release listeners after repeated LiveView navigation", async ({page}) => {
  await gotoLiveLift(page, serverPage);
  await page.evaluate(() => {
    const listeners = new WeakMap();
    const capture = (options) => typeof options === "boolean" ? options : Boolean(options?.capture);
    const add = EventTarget.prototype.addEventListener;
    const remove = EventTarget.prototype.removeEventListener;
    EventTarget.prototype.addEventListener = function (type, callback, options) {
      add.call(this, type, callback, options);
      if (this.id !== "native-list" || !callback || options?.once || options?.signal) return;
      const registered = listeners.get(this) ?? [];
      const useCapture = capture(options);
      if (registered.some((entry) => entry.type === type && entry.callback === callback &&
          entry.capture === useCapture)) return;
      registered.push({type, callback, capture: useCapture});
      listeners.set(this, registered);
    };
    EventTarget.prototype.removeEventListener = function (type, callback, options) {
      remove.call(this, type, callback, options);
      const registered = listeners.get(this);
      if (!registered) return;
      const useCapture = capture(options);
      listeners.set(this, registered.filter((entry) => entry.type !== type ||
        entry.callback !== callback || entry.capture !== useCapture));
    };
    window.liveLiftMemoryProbe = {listenerCount: (island) => listeners.get(island)?.length ?? 0};
  });

  const listenerCount = () => page.evaluate(() => {
    const probe = window.liveLiftMemoryProbe;
    return probe.listenerCount(probe.island);
  });
  const connectedElements = () => page.locator("main *").count();
  const mountedBaseline = await visitList(page, listenerCount);
  const connectedBaseline = await connectedElements();
  expect(connectedBaseline).toBeGreaterThan(0);

  for (let visit = 0; visit < 6; visit += 1) {
    expect(await visitList(page, listenerCount), "mounted listener count").toBe(mountedBaseline);
    expect(await connectedElements(), "connected elements after teardown").toBe(connectedBaseline);
  }
});

test("benchmark native list retention after LiveView navigation", async ({page, browserName}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium", "Run with LIVE_LIFT_BENCH=1 in Chromium");
  test.setTimeout(180_000);

  await gotoLiveLift(page, serverPage);
  await page.evaluate(() => { window.liveLiftMemoryProbe = {references: []}; });
  const cdp = await page.context().newCDPSession(page);
  const listenerCount = () => islandListenerCount(cdp);

  const warmup = 3;
  const visits = 12;
  for (let i = 0; i < warmup; i += 1) await visitList(page, listenerCount);
  const baseline = await collect(page, cdp);

  const samples = [];
  for (let i = 1; i <= visits; i += 1) {
    await visitList(page, listenerCount);
    if (i % 4 === 0) samples.push({visit: i, ...(await collect(page, cdp))});
  }

  console.log(JSON.stringify({warmup, visits, baseline, samples}, null, 2));
  expect(baseline.retainedSamples, "detached roots and sampled rows after warmup").toBe(0);

  for (const sample of samples) {
    expect(sample.retainedSamples, "detached roots and sampled rows held after collection").toBe(0);
    expect(sample.documents, "documents after live navigation").toBe(baseline.documents);
    expect(sample.nodes - baseline.nodes, "extra DOM nodes").toBeLessThanOrEqual(250);
    expect(sample.listeners - baseline.listeners, "extra event listeners").toBeLessThanOrEqual(16);
    expect(sample.usedHeapBytes - baseline.usedHeapBytes, "extra used heap").toBeLessThanOrEqual(1_048_576);
  }
});
