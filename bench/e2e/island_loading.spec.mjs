import {test, expect} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

const viewChunk = /\/assets\/js\/chunks\/LiveLiftDemo[^/]+\.js$/;
const counterChunk = /\/assets\/js\/chunks\/LiveLiftDemoWeb\.NativeCounterComponent-[^/]+\.js$/;

test("native navigation fetches only the mounted island's view", async ({page}) => {
  const views = [];
  page.on("request", (request) => {
    const path = new URL(request.url()).pathname;
    if (viewChunk.test(path)) views.push(path);
  });
  await gotoLiveLift(page, "/native-counter-server");
  expect(views).toEqual([]);
  if (process.env.LIVE_LIFT_TEST_DEPLOY === "1") {
    await expect(page.locator('script[src*="/assets/js/app-"]')).toHaveCount(1);
  }

  await page.getByRole("link", {name: "Optimistic counter"}).click();
  const root = page.locator("#native-counter");
  await expect(root).toHaveAttribute("data-live-lift-load", "ready");
  expect(views).toHaveLength(1);
  expect(views[0]).toMatch(counterChunk);
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(root.locator("output")).toHaveText("1");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
});

test("a click during loading reaches LiveView and initializes the latest snapshot", async ({page}) => {
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  await page.route(counterChunk, async (route) => {
    await held;
    await route.continue();
  });
  try {
    await page.goto("/native-counter", {waitUntil: "domcontentloaded"});
    const root = page.locator("#native-counter");
    await expect(root).toHaveAttribute("data-live-lift-load", "loading");
    const button = root.getByRole("button", {name: "Add one"});
    await button.evaluate((control) => control.click());
    await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
    await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");
    release();
    await expect(root).toHaveAttribute("data-live-lift-load", "ready");
    await expect(root.locator("output")).toHaveText("1");
    await button.click();
    await expect(root.locator("output")).toHaveText("2");
    await expect(root).toHaveAttribute("data-live-lift-ack-seq", "1");
  } finally {
    release();
  }
});

test("an unavailable view signals the error and leaves native events connected", async ({page}) => {
  await page.route(counterChunk, (route) => route.abort());
  await page.goto("/native-counter");
  const root = page.locator("#native-counter");
  await expect(root).toHaveAttribute("data-live-lift-load", "error");
  await expect(root.getByRole("status").filter({hasText: "Local updates could not load"})).toBeVisible();
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");
});
