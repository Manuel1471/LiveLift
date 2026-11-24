import {chromium, test, expect} from "@playwright/test";
import {gotoLiveLift, measureCounterClick} from "./support.mjs";

function summarize(values) {
  const sorted = values.toSorted((a, b) => a - b);
  const percentile = (p) => sorted[Math.ceil(sorted.length * p) - 1];
  return {
    min: sorted[0],
    median: percentile(0.5),
    p95: percentile(0.95),
    max: sorted.at(-1),
    iqr: percentile(0.75) - percentile(0.25),
  };
}

for (const cpuRate of [1, 4]) {
  test(`benchmark native component click latency (${cpuRate}x CPU)`, async ({browserName, baseURL}) => {
    test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium", "Run with LIVE_LIFT_BENCH=1 in Chromium");
    test.setTimeout(180_000);
    const samples = 100;
    const warmups = 5;
    const simulatedMs = 75;
    const browser = await chromium.launch();

    try {
      const context = await browser.newContext({baseURL});
      const server = await context.newPage();
      const client = await context.newPage();
      for (const page of [server, client]) {
        const cdp = await context.newCDPSession(page);
        await cdp.send("Emulation.setCPUThrottlingRate", {rate: cpuRate});
      }

      await gotoLiveLift(server, "/native-counter-server");
      await gotoLiveLift(client, "/native-counter");
      for (const page of [server, client]) {
        await page.evaluate((ms) => {
          window.liveSocket.enableLatencySim(ms);
          window.liveSocket.disableDebug();
        }, simulatedMs);
      }

      const serverVisible = [];
      const clientVisible = [];
      const clientConfirmed = [];
      const routes = [{page: server, optimistic: false}, {page: client, optimistic: true}];
      for (let index = 0; index < samples + warmups; index += 1) {
        for (const {page, optimistic} of (index % 2 === 0 ? routes : routes.toReversed())) {
          const {visibleMs, confirmedMs} = await measureCounterClick(page, optimistic);
          if (index < warmups) continue;
          if (optimistic) {
            clientVisible.push(visibleMs);
            clientConfirmed.push(confirmedMs);
          } else {
            serverVisible.push(visibleMs);
          }
        }
      }

      await expect(server.locator('section[aria-label="Native LiveComponent counter"] output')).toHaveText(String(samples + warmups));
      await expect(client.locator("#native-counter")).toHaveAttribute("data-live-lift-ack-seq", String(samples + warmups));
      console.log(JSON.stringify({
        browser: browser.version(), cpuRate, samples, warmups,
        liveSocketLatencySimMs: simulatedMs,
        serverVisibleMs: summarize(serverVisible),
        clientVisibleMs: summarize(clientVisible),
        clientConfirmedMs: summarize(clientConfirmed),
      }, null, 2));
    } finally {
      await browser.close();
    }
  });
}

test("benchmark native float action against integer action", async ({page, browserName}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium", "Run with LIVE_LIFT_BENCH=1 in Chromium");
  test.setTimeout(120_000);

  const measure = async (route, selector, event, expected) => {
    const samples = [];
    for (let run = 0; run < 5; run += 1) {
      await gotoLiveLift(page, route);
      await page.waitForFunction(() => window.liveSocket?.isConnected());
      await page.evaluate(() => window.liveSocket.disconnect());
      const result = await page.locator(selector).evaluate((root, eventName) => {
        const button = root.querySelector(`button[phx-click="${eventName}"]`);
        for (let index = 0; index < 10; index += 1) button.click();
        const started = performance.now();
        for (let index = 0; index < 50; index += 1) button.click();
        return {totalMs: performance.now() - started, output: root.querySelector("output").textContent};
      }, event);
      expect(result.output).toBe(expected);
      samples.push(result.totalMs);
    }
    samples.sort((a, b) => a - b);
    return {medianBatchMs: samples[2], medianPerActionUs: samples[2] * 1000 / 50};
  };

  const integer = await measure("/native-counter", "#native-counter", "inc", "60");
  const float = await measure("/native-float", "#native-float", "add_half", "30.0");
  console.log(JSON.stringify({browser: "Chromium", batches: 5, actionsPerBatch: 50, integer, float}, null, 2));
});

test("benchmark 1,000 keyed row reversals in Chromium", async ({page, browserName}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium", "Run with LIVE_LIFT_BENCH=1 in Chromium");
  test.setTimeout(120_000);
  await gotoLiveLift(page, "/?bench_rows=1000");
  await page.waitForFunction(() => window.liveSocket?.isConnected());
  await expect(page.locator("#task-list [data-live-lift-key]")).toHaveCount(1_000);

  const result = await page.evaluate(() => {
    const root = document.querySelector("#task-list");
    const button = document.querySelector("#task-list .task-reverse");
    const rows = () => document.querySelectorAll("#task-list [data-live-lift-key]");
    button.click();
    const first = rows()[0];
    if (first.getAttribute("data-live-lift-key") !== "1000") throw new Error("Reverse failed");
    const preservedInput = root.querySelector('[data-live-lift-key="1000"] input[name="value"]');
    const values = [];
    for (let index = 0; index < 25; index += 1) {
      const start = performance.now();
      button.click();
      values.push(performance.now() - start);
    }
    values.sort((a, b) => a - b);
    return {
      medianMs: values[12], p95Ms: values[23], rows: rows().length,
      preservedInput: root.querySelector('[data-live-lift-key="1000"] input[name="value"]') === preservedInput,
      preservedValue: preservedInput.value,
    };
  });

  expect(result.rows).toBe(1_000);
  expect(result.preservedInput).toBe(true);
  expect(result.preservedValue).toBe("Task 1000");
  console.log(JSON.stringify({browser: "Chromium", samples: 25, keyedReverse: result}, null, 2));
});

test("benchmark 1,000 native LiveComponent row reversals in Chromium", async ({page, browserName}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium", "Run with LIVE_LIFT_BENCH=1 in Chromium");
  test.setTimeout(120_000);
  await gotoLiveLift(page, "/native-list?rows=1000");
  await page.waitForFunction(() => window.liveSocket?.isConnected());
  const root = page.locator("#native-list");
  await expect(root.locator("li")).toHaveCount(1_000);
  await page.evaluate(() => window.liveSocket.disconnect());

  const result = await root.evaluate((component) => {
    const button = component.querySelector('button[phx-click="reverse"]');
    const input = component.querySelector('#row-1000 input[name="label"]');
    const values = [];
    for (let index = 0; index < 25; index += 1) {
      const start = performance.now();
      button.click();
      values.push(performance.now() - start);
    }
    values.sort((a, b) => a - b);

    // Count allocations in a separate click so instrumentation does not affect the samples.
    const createElement = document.createElement;
    let createdElements = 0;
    document.createElement = function (...args) {
      createdElements += 1;
      return createElement.apply(this, args);
    };
    try {
      button.click();
    } finally {
      document.createElement = createElement;
    }

    return {
      createdElements,
      medianMs: values[12], p95Ms: values[23],
      rows: component.querySelectorAll("li").length,
      preservedInput: component.querySelector('#row-1000 input[name="label"]') === input,
    };
  });
  expect(result.rows).toBe(1_000);
  expect(result.preservedInput).toBe(true);
  console.log(JSON.stringify({browser: "Chromium", samples: 25, nativeKeyedReverse: result}, null, 2));
});

test("benchmark 1,000 native LiveComponent row sorts in Chromium", async ({page, browserName}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium", "Run with LIVE_LIFT_BENCH=1 in Chromium");
  test.setTimeout(120_000);
  await gotoLiveLift(page, "/native-list?rows=1000");
  await page.waitForFunction(() => window.liveSocket?.isConnected());
  const root = page.locator("#native-list");
  await expect(root.locator("li")).toHaveCount(1_000);
  await page.evaluate(() => window.liveSocket.disconnect());

  const result = await root.evaluate((component) => {
    const sort = component.querySelector('button[phx-click="sort_labels"]');
    const reverse = component.querySelector('button[phx-click="reverse"]');
    const input = component.querySelector('#row-1000 input[name="label"]');
    const values = [];
    for (let index = 0; index < 25; index += 1) {
      reverse.click();
      const start = performance.now();
      sort.click();
      values.push(performance.now() - start);
    }
    values.sort((a, b) => a - b);
    return {
      medianMs: values[12], p95Ms: values[23],
      rows: component.querySelectorAll("li").length,
      preservedInput: component.querySelector('#row-1000 input[name="label"]') === input,
    };
  });
  expect(result.rows).toBe(1_000);
  expect(result.preservedInput).toBe(true);
  console.log(JSON.stringify({browser: "Chromium", samples: 25, nativeKeyedSort: result}, null, 2));
});

test("benchmark navigation and mount with 100 islands", async ({page, browserName}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium", "Run with LIVE_LIFT_BENCH=1 in Chromium");
  test.setTimeout(120_000);

  const warmups = 5;
  const samples = 25;
  const durations = {server: [], client: []};
  const measure = async (mode) => {
    const started = performance.now();
    await page.goto(`/many-islands?count=100&mode=${mode}`, {waitUntil: "domcontentloaded"});
    await page.waitForFunction((mode) => {
      const list = document.querySelector(".phx-connected #many-islands");
      if (list?.children.length !== 100) return false;
      const islands = list.querySelectorAll('[phx-hook="LiveLift"]');
      return mode === "server"
        ? islands.length === 0
        : islands.length === 100 && [...islands].every((island) => island.dataset.liveLiftLoad === "ready");
    }, mode);
    return performance.now() - started;
  };

  for (let round = 0; round < warmups + samples; round += 1) {
    const order = round % 2 === 0 ? ["server", "client"] : ["client", "server"];
    for (const mode of order) {
      const elapsed = await measure(mode);
      if (round >= warmups) durations[mode].push(elapsed);
    }
  }

  console.log(JSON.stringify({browser: "Chromium", islands: 100, warmups, samples,
    navigationAndMountMs: {server: summarize(durations.server), client: summarize(durations.client)}}, null, 2));
});

test("benchmark editing a row in a 1,000-row native LiveComponent list", async ({page, browserName}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1" || browserName !== "chromium", "Run with LIVE_LIFT_BENCH=1 in Chromium");
  await gotoLiveLift(page, "/native-list?rows=1000");
  await page.waitForFunction(() => window.liveSocket?.isConnected());
  const root = page.locator("#native-list");
  await expect(root.locator("li")).toHaveCount(1_000);
  await page.evaluate(() => window.liveSocket.disconnect());

  const result = await root.evaluate((component) => {
    const input = component.querySelector('#row-500 input[name="label"]');
    const neighbor = component.querySelector('#row-501 input[name="label"]');
    input.focus();
    const values = [];
    for (let index = 0; index < 25; index += 1) {
      input.value = `Edited ${index}`;
      const start = performance.now();
      input.dispatchEvent(new Event("input", {bubbles: true}));
      values.push(performance.now() - start);
    }
    values.sort((a, b) => a - b);
    return {
      medianMs: values[12], p95Ms: values[23],
      rows: component.querySelectorAll("li").length,
      editedValue: input.getAttribute("value"),
      preservedFocus: document.activeElement === input,
      preservedNeighbor: component.querySelector('#row-501 input[name="label"]') === neighbor,
    };
  });
  expect(result.rows).toBe(1_000);
  expect(result.editedValue).toBe("Edited 24");
  expect(result.preservedFocus).toBe(true);
  expect(result.preservedNeighbor).toBe(true);
  console.log(JSON.stringify({browser: "Chromium", samples: 25, nativeRowEdit: result}, null, 2));
});
