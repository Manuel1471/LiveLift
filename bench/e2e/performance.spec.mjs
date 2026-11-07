import {test, expect} from "@playwright/test";

test("benchmark native component click latency", async ({page}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1", "Run with LIVE_LIFT_BENCH=1");
  test.setTimeout(120_000);

  const measure = async (route, optimistic) => {
    await page.goto(route);
    await page.waitForFunction(() => window.liveSocket.isConnected());
    await page.waitForTimeout(300);
    await page.evaluate(() => window.liveSocket.enableLatencySim(150));
    const root = optimistic
      ? page.locator("#native-counter")
      : page.locator('section[aria-label="Native LiveComponent counter"]');
    const count = root.locator("output");
    const button = root.getByRole("button", {name: "Add one"});
    const local = [];
    const settled = [];

    for (let index = 0; index < 23; index += 1) {
      const before = Number(await count.textContent());
      const revision = optimistic ? Number(await root.getAttribute("data-live-lift-server-revision")) : null;
      const started = await page.evaluate(() => performance.now());
      await button.click();
      const afterClick = await page.evaluate(() => performance.now());
      if (optimistic) await expect(count).toHaveText(String(before + 1));
      if (optimistic) {
        await expect(root).toHaveAttribute("data-live-lift-server-revision", String(revision + 1));
      } else {
        await expect(count).toHaveText(String(before + 1));
      }
      const afterServer = await page.evaluate(() => performance.now());
      if (index >= 3) {
        if (optimistic) local.push(afterClick - started);
        settled.push(afterServer - started);
      }
    }
    return {local, settled};
  };

  const server = await measure("/native-counter-server", false);
  const client = await measure("/native-counter", true);
  const median = (values) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];
  console.log(JSON.stringify({
    browser: "Chromium",
    samples: 20,
    simulatedNetworkLatencyMs: 150,
    localMedianMs: median(client.local),
    clientSettledMedianMs: median(client.settled),
    serverMedianMs: median(server.settled),
  }, null, 2));
});

test("benchmark 1,000 keyed row reversals in Chromium", async ({page}) => {
  test.skip(process.env.LIVE_LIFT_BENCH !== "1", "Run with LIVE_LIFT_BENCH=1");
  test.setTimeout(120_000);
  await page.goto("/?bench_rows=1000");
  await expect(page.locator("#task-list [data-live-lift-key]")).toHaveCount(1_000);

  const result = await page.evaluate(() => {
    const root = document.querySelector("#task-list");
    const button = document.querySelector("#task-list .task-reverse");
    const rows = () => document.querySelectorAll("#task-list [data-live-lift-key]");
    button.click();
    const first = rows()[0];
    if (first.getAttribute("data-live-lift-key") !== "1000") throw new Error("Reverse failed");
    const preservedInput = root.querySelector('[data-live-lift-key="1000"] input');
    const values = [];
    for (let index = 0; index < 25; index += 1) {
      const start = performance.now();
      button.click();
      values.push(performance.now() - start);
    }
    values.sort((a, b) => a - b);
    return {
      medianMs: values[12], p95Ms: values[23], rows: rows().length,
      preservedInput: root.querySelector('[data-live-lift-key="1000"] input') === preservedInput,
      preservedValue: preservedInput.value,
    };
  });

  expect(result.rows).toBe(1_000);
  expect(result.preservedInput).toBe(true);
  expect(result.preservedValue).toBe("Task 1000");
  console.log(JSON.stringify({browser: "Chromium", samples: 25, keyedReverse: result}, null, 2));
});
