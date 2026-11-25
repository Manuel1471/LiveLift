import {test, expect} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

const liveView = {
  name: "LiveView", url: "/native-timer", island: '[data-live-lift-module="LiveLiftDemoWeb.NativeTimerLive"]',
  event: "predict", value: "output", initial: "0", fired: "10", simultaneous: "20",
  leave: "Open component counter", destination: "/native-counter",
};

const paths = [
  liveView,
  {
    name: "LiveComponent", url: "/native-counter", island: "#native-counter",
    event: "preview_timer", value: "span", initial: "", fired: "Local timer fired",
    simultaneous: "Local timer fired", leave: "Server counter", destination: "/native-counter-server",
  },
];

async function holdTimers(page, event) {
  const held = [];
  let hold = true;
  await page.routeWebSocket(/\/live\/websocket/, (browser) => {
    const server = browser.connectToServer();
    browser.onMessage((message) => {
      const frame = typeof message === "string" ? JSON.parse(message) : null;
      if (hold && frame?.[4]?.event === event) held.push(() => server.send(message));
      else server.send(message);
    });
  });
  return {
    held,
    allow() { hold = false; },
  };
}

test("LiveView timers fast-forward and reconcile exactly once", async ({page}) => {
  const delivery = await holdTimers(page, liveView.event);
  await page.clock.install();
  await gotoLiveLift(page, liveView.url);
  const root = page.locator(liveView.island);
  const output = root.locator(liveView.value);
  const trigger = root.getByRole("button", {name: "Schedule ten locally"});
  const beforeDue = await trigger.evaluate((button) => {
    button.click();
    button.click();
    return document.querySelector("output").textContent;
  });
  expect(beforeDue).toBe(liveView.initial);
  await expect.poll(() => delivery.held.length).toBe(2);

  await page.clock.fastForward(2_000);
  await expect(output).toHaveText(liveView.simultaneous);
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "0");
  await page.clock.fastForward(2_000);
  await expect(output).toHaveText(liveView.simultaneous);

  delivery.held[0]();
  delivery.held[0]();
  delivery.held[1]();
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "2");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "4");
  await expect(root).toHaveAttribute("data-live-lift-timers", "[]");
  await expect(root).toHaveAttribute("data-live-lift-state", /"count":20/);
  await expect(output).toHaveText(liveView.simultaneous);
});

test("LiveView cancels a delayed browser timer after the server commits it", async ({page}) => {
  await page.clock.install();
  await gotoLiveLift(page, liveView.url);
  const root = page.locator(liveView.island);
  await root.getByRole("button", {name: "Schedule ten locally"}).evaluate((button) => {
    const setTimeout = window.setTimeout;
    const delayed = {scheduled: 0, fired: 0};
    window.delayedTimer = delayed;
    window.setTimeout = (callback, delay, ...args) => {
      // The fixture's 250 ms timer subtracts time spent scheduling the callback.
      if (delay <= 250 && delay > 200) {
        delayed.scheduled++;
        return setTimeout(() => {
          delayed.fired++;
          callback(...args);
        }, 10_000);
      }
      return setTimeout(callback, delay, ...args);
    };
    try {
      button.click();
    } finally {
      window.setTimeout = setTimeout;
    }
  });

  const output = root.locator(liveView.value);
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "1");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await expect(root).toHaveAttribute("data-live-lift-timers", "[]");
  await expect(output).toHaveText(liveView.fired);
  await page.clock.fastForward(11_000);
  expect(await page.evaluate(() => window.delayedTimer)).toEqual({scheduled: 1, fired: 0});
  await expect(output).toHaveText(liveView.fired);
  await expect(root).toHaveAttribute("data-live-lift-state", /"count":10/);
});

for (const scenario of paths) {
  test(`${scenario.name} timers resolve independently when scheduled together`, async ({page}) => {
    const delivery = await holdTimers(page, scenario.event);
    await gotoLiveLift(page, scenario.url);
    const root = page.locator(scenario.island);
    await root.locator(`[phx-click="${scenario.event}"]`).evaluate((button) => {
      button.click();
      button.click();
    });
    await expect(root.locator(scenario.value)).toHaveText(scenario.simultaneous);
    await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");
    expect(delivery.held).toHaveLength(2);
    delivery.held.forEach((send) => send());
    await expect(root).toHaveAttribute("data-live-lift-ack-seq", "2");
    await expect(root).toHaveAttribute("data-live-lift-server-revision", "4");
    await expect(root).toHaveAttribute("data-live-lift-timers", "[]");
    await expect(root.locator(scenario.value)).toHaveText(scenario.simultaneous);
  });

  test(`${scenario.name} timers cannot run after navigation destroys the island`, async ({page}) => {
    await holdTimers(page, scenario.event);
    await page.clock.install();
    await gotoLiveLift(page, scenario.url);
    const root = page.locator(scenario.island);
    await root.locator(scenario.value).evaluate((node) => { window.detachedTimerValue = node; });
    await root.locator(`[phx-click="${scenario.event}"]`).evaluate((button, leaveText) => {
      button.click();
      const leave = [...document.querySelectorAll("button, a")].find(
        (candidate) => candidate.textContent.trim() === leaveText,
      );
      leave.click();
    }, scenario.leave);
    await expect(page).toHaveURL(new RegExp(`${scenario.destination}$`));
    await page.clock.runFor(500);
    expect(await page.evaluate(() => ({
      attached: window.detachedTimerValue.isConnected,
      value: window.detachedTimerValue.textContent,
    }))).toEqual({attached: false, value: scenario.initial});
  });

  test(`${scenario.name} timers use the new snapshot after disconnect and reconnect`, async ({page}) => {
    const delivery = await holdTimers(page, scenario.event);
    await page.clock.install();
    await gotoLiveLift(page, scenario.url);
    const root = page.locator(scenario.island);
    const trigger = root.locator(`[phx-click="${scenario.event}"]`);
    const instance = await root.getAttribute("data-live-lift-instance");
    await trigger.evaluate((button) => {
      button.click();
      window.liveSocket.disconnect();
    });
    await page.waitForFunction(() => !window.liveSocket.isConnected());
    await page.clock.runFor(500);
    await expect(root.locator(scenario.value)).toHaveText(scenario.initial);
    delivery.allow();
    await page.evaluate(() => window.liveSocket.connect());
    await page.waitForFunction(() => window.liveSocket.isConnected());
    await expect(root).not.toHaveAttribute("data-live-lift-instance", instance);
    await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");
    await expect(root.locator(scenario.value)).toHaveText(scenario.initial);
    await trigger.click();
    await expect(root.locator(scenario.value)).toHaveText(scenario.fired);
    await expect(root).toHaveAttribute("data-live-lift-ack-seq", "1");
    await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  });
}
