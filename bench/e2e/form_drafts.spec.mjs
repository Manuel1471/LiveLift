import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

const path = "/native-form?record=bound";
const prefix = "live-lift:draft:";
const key = prefix + JSON.stringify([
  "/native-form", "LiveLiftDemoWeb.NativeFormComponent", "native-form",
  "native-note", "demo-note", "profile[note]",
]);
const ack = "data-live-lift-ack-seq";

test("opt-in draft persists through reload and patch, and submits through LiveView", async ({page}) => {
  const events = [];
  let hold = false;
  let sendSave;
  await page.routeWebSocket(/\/live\/websocket/, (browser) => {
    const server = browser.connectToServer();
    browser.onMessage((message) => {
      const event = typeof message === "string" ? JSON.parse(message)?.[4] : undefined;
      if (event?.event) events.push(event);
      if (hold && event?.event === "save") {
        sendSave = () => server.send(message);
      } else {
        server.send(message);
      }
    });
  });

  await gotoLiveLift(page, path);
  const island = page.locator("#native-form");
  const note = island.getByRole("textbox", {name: "Note", exact: true});
  const text = "Résumé 🙂 & <draft>";
  await expect(note).toHaveValue("Server note");
  await note.fill(text);
  await expect(island).toHaveAttribute(ack, "1");
  await expect.poll(() => page.evaluate((key) => {
    const raw = sessionStorage.getItem(key);
    return raw && JSON.parse(raw)[2];
  }, key)).toBe(text);

  events.length = 0;
  await gotoLiveLift(page, path);
  await expect(note).toHaveValue(text);
  await expect(note).toHaveAttribute("value", "Server note");
  await expect(island).toHaveAttribute(ack, "0");
  await expect(island.locator("p").last()).toHaveText("Saved:");
  expect(events).toEqual([]);

  await island.getByRole("textbox", {name: "Draft", exact: true}).fill("Separate update");
  await expect(island).toHaveAttribute(ack, "1");
  await expect(note).toHaveValue(text);

  hold = true;
  await island.getByRole("button", {name: "Save note"}).click();
  await expect.poll(() => events.find(({event}) => event === "save")?.value.profile.note).toBe(text);
  await expect(island).toHaveAttribute(ack, "1");
  sendSave();
  await expect(island).toHaveAttribute(ack, "2");
  expect(JSON.parse(await island.getAttribute("data-live-lift-state")).saved).toBe(text);

  await island.getByRole("button", {name: "Discard draft"}).click();
  await expect.poll(() => page.evaluate((key) => sessionStorage.getItem(key), key)).toBeNull();
  await expect(note).toHaveValue("Server note");
  await gotoLiveLift(page, path);
  await expect(note).toHaveValue("Server note");
});

test("opt-in draft isolates scopes, supports empty text and ignores invalid records", async ({page}) => {
  await gotoLiveLift(page, path);
  const note = page.getByRole("textbox", {name: "Note", exact: true});
  await note.fill("");
  await expect(page.locator("#native-form")).toHaveAttribute(ack, "1");
  await gotoLiveLift(page, "/native-form?record=other");
  await expect(note).toHaveValue("");
  expect(await note.getAttribute("data-live-lift-draft")).toBe("demo-other");
  await note.fill("Other draft");
  await gotoLiveLift(page, path);
  await expect(note).toHaveValue("");
  await expect(note).toHaveAttribute("value", "Server note");

  // Keep the node live while exercising a record-scope change.
  await note.evaluate((field) => field.setAttribute("data-live-lift-draft", "demo-other"));
  await expect(note).toHaveValue("Other draft");
  await note.evaluate((field) => field.setAttribute("data-live-lift-draft", "invalid scope"));
  await expect(note).toHaveValue("Server note");
  await note.evaluate((field) => field.setAttribute("data-live-lift-draft", "demo-note"));
  await expect(note).toHaveValue("");

  for (const invalid of ["expired", "json", "size", "version", "future"]) {
    await page.evaluate(({key, invalid}) => {
      const examples = {
        expired: JSON.stringify([1, Date.now() - 1000, "Expired"]),
        json: "[",
        size: JSON.stringify([1, Date.now() + 60_000, "x".repeat(4097)]),
        version: JSON.stringify([2, Date.now() + 60_000, "Wrong version"]),
        future: JSON.stringify([1, Date.now() + 86_400_000, "Too far in the future"]),
      };
      sessionStorage.setItem(key, examples[invalid]);
    }, {key, invalid});
    await gotoLiveLift(page, path);
    await expect(note).toHaveValue("Server note");
    expect(await page.evaluate((key) => sessionStorage.getItem(key), key)).toBeNull();
  }

  await note.fill("x".repeat(4097));
  await expect.poll(() => page.evaluate((key) => sessionStorage.getItem(key), key)).toBeNull();
  await gotoLiveLift(page, path);
  await expect(note).toHaveValue("Server note");
  await gotoLiveLift(page, "/native-form?record=other");
  await expect(note).toHaveValue("Other draft");
});

test("opt-in draft tolerates browser storage write failures and keeps native submit", async ({page}) => {
  await page.addInitScript((prefix) => {
    const original = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key, value) {
      if (key.startsWith(prefix)) throw new DOMException("Blocked draft", "QuotaExceededError");
      return original.call(this, key, value);
    };
  }, prefix);
  await gotoLiveLift(page, path);
  const island = page.locator("#native-form");
  await island.getByRole("textbox", {name: "Note", exact: true}).fill("Works without storage");
  await expect(island).toHaveAttribute(ack, "1");
  await island.getByRole("button", {name: "Save note"}).click();
  await expect(island).toHaveAttribute(ack, "2");
  await expect(island.locator("p").last()).toHaveText("Saved: Works without storage");
});

test("opt-in draft keeps a stored value when reading it is temporarily denied", async ({page}) => {
  await page.addInitScript(({key}) => {
    const read = Storage.prototype.getItem;
    const storage = window.sessionStorage;
    storage.setItem(key, JSON.stringify([1, Date.now() + 60_000, "Stored draft"]));
    window.readStoredDraft = () => read.call(storage, key);
    Storage.prototype.getItem = function (name) {
      if (name === key) throw new DOMException("Blocked draft", "SecurityError");
      return read.call(this, name);
    };
  }, {key});
  await gotoLiveLift(page, path);
  await expect(page.getByRole("textbox", {name: "Note", exact: true})).toHaveValue("Server note");
  expect(await page.evaluate(() => JSON.parse(window.readStoredDraft())[2])).toBe("Stored draft");
});
