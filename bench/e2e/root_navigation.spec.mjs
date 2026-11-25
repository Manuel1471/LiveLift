import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

const timerPath = "/native-timer?start=7";
const timerModule = '[data-live-lift-module="LiveLiftDemoWeb.NativeTimerLive"]';

async function controlIncrement(page) {
  let hold = false;
  let forward;

  await page.routeWebSocket(/\/live\/websocket/, (browser) => {
    const server = browser.connectToServer();
    browser.onMessage((message) => {
      const frame = typeof message === "string" ? JSON.parse(message) : null;
      if (hold && frame?.[4]?.event === "inc") {
        hold = false;
        forward = () => server.send(message);
      } else {
        server.send(message);
      }
    });
  });

  return {
    holdNext: () => { hold = true; },
    isHeld: () => forward !== undefined,
    release: () => {
      forward();
      forward = undefined;
    },
  };
}

async function expectSnapshot(island, count, ack, authoritativeCount = count) {
  await expect(island.locator("output")).toHaveText(String(count));
  await expect(island).toHaveAttribute("data-live-lift-ack-seq", String(ack));
  await expect(island).toHaveAttribute(
    "data-live-lift-state",
    new RegExp(`"count":${authoritativeCount}(?=[},])`),
  );
}

async function expectMount(island, count) {
  await expect(island).toHaveAttribute("data-live-lift-load", "ready");
  await expect(island).toHaveAttribute("data-live-lift-instance", /.+/);
  await expectSnapshot(island, count, 0);
}

test("root LiveView history restores URL state and drops pending predictions", async ({page}) => {
  const delivery = await controlIncrement(page);
  await gotoLiveLift(page, timerPath);
  const timer = page.locator(timerModule);
  const counter = page.locator("#native-counter");
  await page.evaluate(() => { window.liveLiftHistoryProbe = true; });
  await expectMount(timer, 7);
  const timerInstance = await timer.getAttribute("data-live-lift-instance");

  await timer.getByRole("button", {name: "Add one"}).click();
  await expectSnapshot(timer, 8, 1);
  delivery.holdNext();
  await timer.getByRole("button", {name: "Add one"}).click();
  await expectSnapshot(timer, 9, 1, 8);
  await expect.poll(delivery.isHeld).toBe(true);

  await timer.getByRole("button", {name: "Open component counter"}).click();
  await expect(page).toHaveURL(/\/native-counter$/);
  await expect(timer).toHaveCount(0);
  await expectMount(counter, 0);
  const counterInstance = await counter.getAttribute("data-live-lift-instance");
  await counter.getByRole("button", {name: "Add one"}).click();
  await expectSnapshot(counter, 1, 1);

  await page.goBack();
  await expect(page).toHaveURL(/\/native-timer\?start=7$/);
  await expectMount(timer, 7);
  await expect(timer).not.toHaveAttribute("data-live-lift-instance", timerInstance);
  await timer.getByRole("button", {name: "Add one"}).click();
  await expectSnapshot(timer, 8, 1);

  await page.goForward();
  await expect(page).toHaveURL(/\/native-counter$/);
  await expectMount(counter, 0);
  await expect(counter).not.toHaveAttribute("data-live-lift-instance", counterInstance);
  await counter.getByRole("button", {name: "Add one"}).click();
  await expectSnapshot(counter, 1, 1);
  expect(await page.evaluate(() => window.liveLiftHistoryProbe)).toBe(true);
});

test("root LiveView tabs keep their predictions and confirmations independent", async ({page, context}) => {
  const delivery = await controlIncrement(page);
  const second = await context.newPage();
  await gotoLiveLift(page, timerPath);
  await gotoLiveLift(second, timerPath);
  const firstIsland = page.locator(timerModule);
  const secondIsland = second.locator(timerModule);
  await expectMount(firstIsland, 7);
  await expectMount(secondIsland, 7);
  const firstInstance = await firstIsland.getAttribute("data-live-lift-instance");
  const secondInstance = await secondIsland.getAttribute("data-live-lift-instance");
  expect(secondInstance).not.toBe(firstInstance);

  delivery.holdNext();
  await firstIsland.getByRole("button", {name: "Add one"}).click();
  await expectSnapshot(firstIsland, 8, 0, 7);
  await expect.poll(delivery.isHeld).toBe(true);
  await expectSnapshot(secondIsland, 7, 0);

  await secondIsland.getByRole("button", {name: "Add one"}).click();
  await secondIsland.getByRole("button", {name: "Add one"}).click();
  await expectSnapshot(secondIsland, 9, 2);
  await expectSnapshot(firstIsland, 8, 0, 7);
  delivery.release();
  await expectSnapshot(firstIsland, 8, 1);
  await expectSnapshot(secondIsland, 9, 2);

  await second.reload();
  await expect(second).toHaveURL(/\/native-timer\?start=7$/);
  await expectMount(secondIsland, 7);
  await expect(secondIsland).not.toHaveAttribute("data-live-lift-instance", secondInstance);
  await secondIsland.getByRole("button", {name: "Add one"}).click();
  await expectSnapshot(secondIsland, 8, 1);
  await expectSnapshot(firstIsland, 8, 1);
  await expect(firstIsland).toHaveAttribute("data-live-lift-instance", firstInstance);
});
