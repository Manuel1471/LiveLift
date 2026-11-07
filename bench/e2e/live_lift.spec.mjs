import {test, expect} from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test("local state and server patches coexist", async ({page}) => {
  await page.goto("/");
  const score = page.locator("#local-counter .score-row output");
  await expect(score).toHaveText("10");
  await page.getByRole("button", {name: "+ 2 points"}).click();
  await expect(score).toHaveText("12");
  await expect(page.locator("#server-count")).toHaveText("0");

  await page.locator("#server-increment").click();
  await expect(page.locator("#server-count")).toHaveText("1");
  await expect(score).toHaveText("12");
  await expect(page.locator("#local-counter")).toContainText("Server events: 1");

  await page.getByRole("button", {name: "Sync score"}).click();
  await expect(page.locator("#saved-score")).toHaveText("12");
  await expect(page.locator("#local-counter")).toContainText("Server saved: 12");
  await expect(score).toHaveText("12");
});

test("keyed task editing preserves focus across reorder", async ({page}) => {
  await page.goto("/");
  const input = page.locator('#task-list [data-live-lift-key="1"] input');
  await input.fill("Edited in browser");
  await expect(input).toBeFocused();
  await page.getByRole("button", {name: "Reverse order"}).evaluate((button) => button.click());
  await expect(input).toBeFocused();
  await expect(input).toHaveValue("Edited in browser");
  await input.fill("Edited after reorder");
  await expect(input).toHaveValue("Edited after reorder");

  await page.getByRole("textbox", {name: "New task"}).fill("Third task");
  await page.getByRole("button", {name: "Add task"}).click();
  await expect(page.locator("#task-list [data-live-lift-key]")).toHaveCount(3);
  await page.locator('#task-list [data-live-lift-key="2"] .task-remove').click();
  await expect(page.locator("#task-list [data-live-lift-key]")).toHaveCount(2);
});

test("demo has no WCAG A or AA violations detected by axe", async ({page}) => {
  await page.goto("/");
  const results = await new AxeBuilder({page}).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
  expect(results.violations).toEqual([]);
});

test("server HTML and client render produce the same island DOM", async ({page}) => {
  await page.goto("/");
  await expect(page.locator("#local-counter [data-live-lift-text]")).toHaveCount(0);
  await expect(page.locator("#local-counter .client-panel")).toHaveAttribute("title", "Score & activity");
  await expect(page.locator("#local-counter progress")).toHaveAttribute("title", 'A & B "<demo>"');
  const snapshot = () => page.locator("#local-counter").evaluate((root) => {
    const project = (node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        return node.nodeValue.trim() ? ["text", node.nodeValue] : null;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return null;
      const attrs = [...node.attributes]
        .filter((attr) => !attr.name.startsWith("data-phx-"))
        .map((attr) => [attr.name, attr.value])
        .sort(([a], [b]) => a.localeCompare(b));
      return [node.tagName, attrs, [...node.childNodes].map(project).filter(Boolean)];
    };
    return [...root.childNodes].map(project).filter(Boolean);
  });
  const before = await snapshot();
  await page.getByRole("button", {name: "Reset"}).click();
  expect(await snapshot()).toEqual(before);
});

test("checkbox, select and textarea retain native form behavior", async ({page}) => {
  await page.goto("/form-parity");
  const root = page.locator("#form-parity");
  const checkbox = root.getByRole("checkbox", {name: "Enabled"});
  const select = root.getByRole("combobox", {name: "Choice"});
  const textarea = root.getByRole("textbox", {name: "Note"});
  await expect(root.locator("section")).toHaveAttribute("title", "Forms & entities");
  await expect(checkbox).toBeChecked();
  await expect(select).toHaveValue("a");
  await expect(textarea).toHaveValue("A & <B>");

  await checkbox.uncheck();
  await expect(checkbox).not.toBeChecked();
  await select.selectOption("b");
  await expect(select).toHaveValue("b");
  await textarea.fill("x & <y>");
  await expect(textarea).toBeFocused();
  await expect(root.locator("output")).toHaveText("x & <y>");

  await root.getByRole("button", {name: "Reset form"}).click();
  await expect(checkbox).toBeChecked();
  await expect(select).toHaveValue("a");
  await expect(textarea).toHaveValue("A & <B>");
});

test("a normal LiveComponent runs a marked handler locally and converges with the server", async ({page}) => {
  await page.goto("/native-counter");
  const root = page.locator("#native-counter");
  const count = root.locator("output");
  await expect(count).toHaveText("0");
  await page.evaluate(() => window.liveSocket.enableLatencySim(450));
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(count).toHaveText("1", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(count).toHaveText("1");
  await expect(root.getByRole("button", {name: "Add one"})).toHaveAttribute("phx-target", /\d+/);
  await root.getByRole("button", {name: "Set label"}).click();
  await expect(root.locator("span")).toHaveText("ready", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("pending native component clicks converge after server replies", async ({page}) => {
  await page.goto("/native-counter");
  const root = page.locator("#native-counter");
  const count = root.locator("output");
  await page.evaluate(() => window.liveSocket.enableLatencySim(300));
  const button = root.getByRole("button", {name: "Add one"});
  await button.click();
  await button.click();
  await expect(count).toHaveText("2", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await expect(count).toHaveText("2");
  await root.getByRole("button", {name: "Reset on server"}).click();
  await expect(count).toHaveText("0");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "3");
});

test("server reset interleaved with pending predictions converges", async ({page}) => {
  await page.goto("/native-counter");
  const root = page.locator("#native-counter");
  const count = root.locator("output");
  await page.evaluate(() => window.liveSocket.enableLatencySim(250));
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(count).toHaveText("1", {timeout: 200});
  await root.getByRole("button", {name: "Reset on server"}).click();
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "3");
  await expect(root).toHaveAttribute("data-live-lift-state", /"count":1/);
  await expect(count).toHaveText("1");
});

test("native component reconnects from the server snapshot", async ({page}) => {
  await page.goto("/native-counter");
  const root = page.locator("#native-counter");
  const count = root.locator("output");
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await page.evaluate(() => { window.liveSocket.disconnect(); window.liveSocket.connect(); });
  await page.waitForFunction(() => window.liveSocket.isConnected());
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "0");
  await expect(count).toHaveText("0");
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(count).toHaveText("1");
});

test("a pending prediction is discarded after a connection cut", async ({page}) => {
  await page.goto("/native-counter");
  const root = page.locator("#native-counter");
  const count = root.locator("output");
  await page.evaluate(() => window.liveSocket.enableLatencySim(500));
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(count).toHaveText("1", {timeout: 200});
  await page.evaluate(() => { window.liveSocket.disconnect(); window.liveSocket.connect(); });
  await page.waitForFunction(() => window.liveSocket.isConnected());
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "0");
  await expect(count).toHaveText("0");
  await page.waitForTimeout(600);
  await expect(count).toHaveText("0");
});

test("the same LiveComponent without opt-in keeps normal server behavior", async ({page}) => {
  await page.goto("/native-counter-server");
  const root = page.locator('section[aria-label="Native LiveComponent counter"]');
  const count = root.locator("output");
  await expect(root).not.toHaveAttribute("phx-hook", "LiveLift");
  await page.evaluate(() => window.liveSocket.enableLatencySim(450));
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(count).toHaveText("0", {timeout: 200});
  await expect(count).toHaveText("1");
});

test("native phx-change and phx-submit use the same params on client and server", async ({page}) => {
  await page.goto("/native-form");
  const root = page.locator("#native-form");
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));
  await root.getByRole("textbox", {name: "Draft"}).fill("Client draft");
  await expect(root.locator("output")).toHaveText("Client draft", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("textbox", {name: "Note"}).fill("Saved locally");
  await root.getByRole("button", {name: "Save note"}).click();
  await expect(root.locator("p")).toHaveText("Saved: Saved locally", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await expect(root.locator("p")).toHaveText("Saved: Saved locally");
});
