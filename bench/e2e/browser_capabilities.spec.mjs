import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

if (process.env.LIVE_LIFT_DEMO_SERVER_ONLY === "1") {
  test("server-only LiveView validates and saves without LiveLift browser APIs", async ({page}) => {
    const errors = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.addInitScript(() => {
      Object.hasOwn = undefined;
      Intl.Segmenter = undefined;
    });
    await gotoLiveLift(page, "/native-form?record=bound");
    await expect(page.locator(".phx-connected #native-note")).toBeVisible();
    await expect(page.locator('[phx-hook="LiveLift"]')).toHaveCount(0);

    const note = page.getByRole("textbox", {name: "Note", exact: true});
    await expect(note).toHaveValue("Server note");
    await note.fill("e\u0301🙂");
    await expect(page.getByRole("alert")).toHaveText("Note must have at least 3 characters.");
    await note.fill("e\u0301🙂!");
    await expect(page.getByRole("alert")).toHaveCount(0);
    await page.getByRole("button", {name: "Save note"}).click();
    await expect(page.getByText("Saved: e\u0301🙂!", {exact: true})).toBeVisible();
    expect(errors).toEqual([]);
  });
} else {
  test("native form validation reaches Phoenix before the LiveLift view loads", async ({page}) => {
    let release;
    const held = new Promise((resolve) => { release = resolve; });
    await page.route(/\/assets\/js\/chunks\/LiveLiftDemoWeb\.NativeFormComponent-[^/]+\.js$/, async (route) => {
      await held;
      await route.continue();
    });

    try {
      await page.goto("/native-form?record=bound", {waitUntil: "domcontentloaded"});
      const root = page.locator("#native-form");
      await expect(root).toHaveAttribute("data-live-lift-load", "loading");
      await root.getByRole("textbox", {name: "Note", exact: true}).fill("e\u0301🙂");
      await expect(root).toHaveAttribute("data-live-lift-state", /"invalid":true/);
      await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");
      release();
      await expect(root).toHaveAttribute("data-live-lift-load", "ready");
      await expect(root.getByRole("alert")).toBeVisible();
    } finally {
      release();
    }
  });

  test("a counter with no grapheme operations works without Intl.Segmenter", async ({page}) => {
    await page.addInitScript(() => { Intl.Segmenter = undefined; });
    await gotoLiveLift(page, "/native-counter");
    const root = page.locator("#native-counter");
    await root.getByRole("button", {name: "Add one"}).click();
    await expect(root).toHaveAttribute("data-live-lift-ack-seq", "1");
    await expect(root.locator("output")).toHaveText("1");
  });
}
