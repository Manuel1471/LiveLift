import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

const path = "/native-counter";
const key = "live-lift:storage-spike";
const sample = JSON.stringify({version: 1, draft: "Unsaved local preview"});

test("session storage retains data across reload but a new island starts from Phoenix", async ({page}) => {
  await gotoLiveLift(page, path);
  const island = page.locator("#native-counter");
  const original = await island.getAttribute("data-live-lift-instance");
  const count = island.locator("output");

  await page.evaluate(() => window.liveSocket.disconnect());
  await island.getByRole("button", {name: "Add one"}).click();
  await expect(count).toHaveText("1");
  await expect(island).toHaveAttribute("data-live-lift-ack-seq", "0");
  await page.evaluate(({key, sample}) => sessionStorage.setItem(key, sample), {key, sample});

  await page.reload();
  await page.waitForFunction(() => window.liveSocket?.isConnected());
  await expect(island).toHaveAttribute("data-live-lift-load", "ready");
  await expect(island).not.toHaveAttribute("data-live-lift-instance", original);
  await expect(count).toHaveText("0");
  await expect(island).toHaveAttribute("data-live-lift-ack-seq", "0");
  expect(await page.evaluate((key) => sessionStorage.getItem(key), key)).toBe(sample);
});

test("an opener can copy session storage into another LiveView tab", async ({page, context}) => {
  await gotoLiveLift(page, path);
  await page.evaluate(({key, sample, path}) => {
    sessionStorage.setItem(key, sample);
    const link = document.createElement("a");
    link.href = path;
    link.target = "_blank";
    link.rel = "opener";
    link.textContent = "Open with opener";
    document.body.prepend(link);
  }, {key, sample, path});

  const [opened] = await Promise.all([
    page.waitForEvent("popup"),
    page.getByRole("link", {name: "Open with opener"}).click(),
  ]);
  await opened.waitForFunction(() => window.liveSocket?.isConnected());
  expect(await opened.evaluate(() => Boolean(window.opener))).toBe(true);
  expect(await opened.evaluate((key) => sessionStorage.getItem(key), key)).toBe(sample);

  await opened.evaluate((key) => sessionStorage.removeItem(key), key);
  expect(await page.evaluate((key) => sessionStorage.getItem(key), key)).toBe(sample);

  const independent = await context.newPage();
  await gotoLiveLift(independent, path);
  expect(await independent.evaluate((key) => sessionStorage.getItem(key), key)).toBeNull();
});

test("restoring draft text leaves Phoenix state unchanged until native form submission", async ({page}) => {
  const observedEvents = [];
  let save;
  await page.routeWebSocket(/\/live\/websocket/, (browser) => {
    const server = browser.connectToServer();
    browser.onMessage((message) => {
      const frame = typeof message === "string" ? JSON.parse(message) : null;
      const event = frame?.[4]?.event;
      if (event) observedEvents.push(event);
      if (event === "save") {
        save = {params: frame[4].value, forward: () => server.send(message)};
      } else {
        server.send(message);
      }
    });
  });

  const noteText = "Résumé — ready & unsaved";
  await gotoLiveLift(page, "/native-form");
  await page.evaluate(({key, noteText}) => sessionStorage.setItem(key, noteText), {key, noteText});
  await page.reload();

  const island = page.locator("#native-form");
  const note = island.getByRole("textbox", {name: "Note", exact: true});
  const saved = island.locator("p").last();
  const ack = "data-live-lift-ack-seq";
  await expect(island).toHaveAttribute("data-live-lift-load", "ready");
  const snapshot = await island.getAttribute("data-live-lift-state");
  await note.evaluate((input, key) => { input.value = sessionStorage.getItem(key); }, key);
  await expect(note).toHaveValue(noteText);
  await expect(island).toHaveAttribute("data-live-lift-state", snapshot);
  await expect(island).toHaveAttribute(ack, "0");
  expect(observedEvents).toEqual([]);

  // Force a real island render between restoring the field and submitting it.
  await island.getByRole("textbox", {name: "Draft", exact: true}).fill("Separate update");
  await expect(island).toHaveAttribute(ack, "1");
  await expect(note).toHaveValue(noteText);
  expect(observedEvents).toEqual(["draft"]);

  await island.getByRole("button", {name: "Save note"}).click();
  await expect.poll(() => save?.params.profile.note).toBe(noteText);
  await expect(saved).toHaveText(`Saved: ${noteText}`);
  await expect(island).toHaveAttribute(ack, "1");
  expect(observedEvents).toEqual(["draft", "save"]);

  save.forward();
  await expect(island).toHaveAttribute(ack, "2");
  expect(JSON.parse(await island.getAttribute("data-live-lift-state")).saved).toBe(noteText);
});
