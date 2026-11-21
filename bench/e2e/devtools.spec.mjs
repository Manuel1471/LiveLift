import {test, expect} from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import {gotoLiveLift} from "./support.mjs";

const deployed = process.env.LIVE_LIFT_TEST_DEPLOY === "1";

test("development inspector travels through state without rewinding LiveView", async ({page}) => {
  test.skip(deployed, "The inspector is not built into deployed assets");
  await gotoLiveLift(page, "/native-counter?live_lift_inspect=1");

  const counter = page.locator("#native-counter");
  const count = counter.locator("output").first();
  const inspector = page.getByRole("dialog", {name: "LiveLift state inspector"});
  const snapshot = inspector.locator("pre");
  const open = page.getByRole("button", {name: "Inspect LiveLift state"});

  await expect(count).toHaveText("0");
  await counter.getByRole("button", {name: "Add one"}).click();
  await expect(counter).toHaveAttribute("data-live-lift-ack-seq", "1");

  await open.click();
  await expect(inspector.getByLabel("Island").locator("option:checked")).toHaveText("native-counter");
  await expect(snapshot).toContainText('"count": 1');
  const audit = await new AxeBuilder({page})
    .include("dialog[aria-labelledby=live-lift-state-inspector-heading]")
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  expect(audit.violations).toEqual([]);
  await inspector.getByRole("button", {name: "Previous snapshot"}).click();
  await expect(inspector.getByRole("status")).toContainText("History");
  await expect(snapshot).toContainText('"count": 0');
  await expect(count).toHaveText("1");
  await expect(counter).toHaveAttribute("data-live-lift-ack-seq", "1");

  // LiveView can receive an update while the developer is inspecting history.
  await counter.getByRole("button", {name: "Add one"}).evaluate((button) => button.click());
  await expect(counter).toHaveAttribute("data-live-lift-ack-seq", "2");
  await expect(count).toHaveText("2");
  await expect(snapshot).toContainText('"count": 0');
  await inspector.getByRole("button", {name: "Next snapshot"}).click();
  await expect(snapshot).toContainText('"count": 1');
  await inspector.getByRole("button", {name: "Follow live"}).click();
  await expect(snapshot).toContainText('"count": 2');

  await page.keyboard.press("Escape");
  await expect(inspector).not.toBeVisible();
  await counter.getByRole("button", {name: "Save on server"}).click();
  await expect(counter).toContainText("Saved 2");

  await page.getByRole("link", {name: "Server counter"}).click();
  await expect(counter).toHaveCount(0);
  await open.click();
  await expect(inspector.getByRole("status")).toHaveText("No mounted LiveLift islands.");
  await expect(inspector.getByLabel("Island").locator("option")).toHaveCount(0);
});

test("development inspector captures both a prediction and its server correction", async ({page}) => {
  test.skip(deployed, "The inspector is not built into deployed assets");
  await page.routeWebSocket(/\/live\/websocket/, (browser) => {
    const server = browser.connectToServer();
    browser.onMessage((message) => {
      const frame = typeof message === "string" ? JSON.parse(message) : null;
      const event = frame?.[4];
      if (event?.event === "edit" && event.value?._live_lift_seq === 1) {
        event.value.label = "Server correction";
        server.send(JSON.stringify(frame));
      } else {
        server.send(message);
      }
    });
  });

  await gotoLiveLift(page, "/native-list?live_lift_inspect=1");
  const input = page.locator('#row-1 input[name="label"]');
  await input.fill("Client prediction");
  await expect(input).toHaveValue("Server correction");

  await page.getByRole("button", {name: "Inspect LiveLift state"}).click();
  const inspector = page.getByRole("dialog", {name: "LiveLift state inspector"});
  const snapshot = inspector.locator("pre");
  await expect(snapshot).toContainText("Server correction");
  await inspector.getByRole("button", {name: "Previous snapshot"}).click();
  await expect(snapshot).toContainText("Client prediction");
  await expect(input).toHaveValue("Server correction");
});

test("development inspector bounds history and renders state as text", async ({page}) => {
  test.skip(deployed, "The inspector is not built into deployed assets");
  await gotoLiveLift(page, "/?live_lift_inspect=1");
  const taskLabel = '<img id="inspector-unsafe" src="missing.png">';
  await page.getByRole("textbox", {name: "New task"}).fill(taskLabel);
  await page.getByRole("button", {name: "Add task"}).click();

  await page.getByRole("button", {name: "Inspect LiveLift state"}).click();
  const inspector = page.getByRole("dialog", {name: "LiveLift state inspector"});
  await inspector.getByLabel("Island").selectOption({label: "task-list"});
  const state = JSON.parse(await inspector.locator("pre").textContent());
  expect(state.items.at(-1).name).toBe(taskLabel);
  await expect(page.locator("#inspector-unsafe")).toHaveCount(0);
  await inspector.getByRole("button", {name: "Close inspector"}).click();

  await page.getByRole("button", {name: "+ 2 points"}).evaluate((button) => {
    for (let index = 0; index < 75; index++) button.click();
  });
  await page.getByRole("button", {name: "Inspect LiveLift state"}).click();
  await inspector.getByLabel("Island").selectOption({label: "local-counter"});
  const previous = inspector.getByRole("button", {name: "Previous snapshot"});
  await expect(previous).toBeEnabled();
  const steps = await previous.evaluate((button) => {
    let steps = 0;
    while (!button.disabled && steps < 100) {
      button.click();
      steps++;
    }
    return steps;
  });
  expect(steps).toBe(63);
  await expect(inspector.locator("pre")).toContainText('"count":');
});

test("development inspector omits oversized snapshots without interrupting the island", async ({page}) => {
  test.skip(deployed, "The inspector is not built into deployed assets");
  await gotoLiveLift(page, "/native-list?rows=1000&live_lift_inspect=1");

  const list = page.locator("#native-list");
  await expect(list.locator("li")).toHaveCount(1000);
  await list.locator('#row-1 input[name="label"]').fill("x".repeat(6000));
  await expect(list).toHaveAttribute("data-live-lift-ack-seq", "1");
  await page.getByRole("button", {name: "Inspect LiveLift state"}).click();
  const inspector = page.getByRole("dialog", {name: "LiveLift state inspector"});
  await expect(inspector.locator("pre")).toHaveText("This state exceeds the inspector's snapshot size limit.");
  await inspector.getByRole("button", {name: "Close inspector"}).click();
  await list.getByRole("button", {name: "Reverse rows"}).click();
  await expect(list.locator("li").first()).toHaveAttribute("id", "row-1000");
  await expect(list).toHaveAttribute("data-live-lift-ack-seq", "2");
});

test("default page and deployed assets leave the inspector inactive", async ({page, request}) => {
  await gotoLiveLift(page, deployed ? "/native-counter?live_lift_inspect=1" : "/native-counter");
  await expect(page.getByRole("button", {name: "Inspect LiveLift state"})).toHaveCount(0);

  if (deployed) {
    const app = await page.locator('script[type="module"][src*="/app"]').getAttribute("src");
    expect(new URL(app, page.url()).pathname).toMatch(/app-[\da-f]+\.js$/);
    const response = await request.get(app);
    expect(response.ok()).toBe(true);
    const code = await response.text();
    expect(code).not.toContain("Inspect LiveLift state");
    expect(code).not.toContain("live_lift_inspect");
  }
});
