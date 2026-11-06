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
