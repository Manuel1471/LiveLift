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

test("native HEEx :for keeps the same focused row across a client reorder", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const first = root.locator('#row-1 input[name="label"]');
  await expect(root.locator("li").first()).toHaveAttribute("id", "row-1");
  await first.fill("Local draft");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await page.evaluate(() => { window.__nativeRowInput = document.querySelector('#row-1 input[name="label"]'); });
  await root.getByRole("button", {name: "Reverse rows"}).evaluate((button) => button.click());
  await expect(root.locator("li").first()).toHaveAttribute("id", "row-2");
  await expect(first).toBeFocused();
  await expect(first).toHaveValue("Local draft");
  expect(await page.evaluate(() => document.querySelector('#row-1 input[name="label"]') === window.__nativeRowInput)).toBe(true);
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native list validates live form changes and saves the edited row", async ({page}) => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  page.on("console", (message) => { if (message.type() === "error") errors.push(message.text()); });
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const row = root.locator("#row-1");
  await row.getByRole("textbox", {name: "Label"}).fill("Édité <&>");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  expect(errors).toEqual([]);
  await expect(root.locator("li")).toHaveCount(2);
  await row.getByRole("button", {name: "Save row"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await expect(row.getByRole("textbox", {name: "Label"})).toHaveValue("Édité <&>");
  await expect(root.locator("#row-2").getByRole("textbox", {name: "Label"})).toHaveValue("Two");
  expect(errors).toEqual([]);
});

test("a server-corrected row reuses its unaffected neighbors", async ({page}) => {
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
  await page.goto("/native-list?rows=1000");
  await page.waitForFunction(() => window.liveSocket.isConnected());
  const root = page.locator("#native-list");
  await expect(root.locator("li")).toHaveCount(1000);
  await root.evaluate((component) => {
    window.__rowProbe = {
      edited: component.querySelector('#row-500 input[name="label"]'),
      neighbor: component.querySelector('#row-501 input[name="label"]'),
      allocated: 0,
    };
    const create = document.createElement;
    document.createElement = function (tag, ...args) {
      if (tag === "li") window.__rowProbe.allocated += 1;
      return create.call(this, tag, ...args);
    };
  });
  const input = root.locator('#row-500 input[name="label"]');
  await input.fill("Client prediction");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(input).toHaveValue("Server correction");
  await expect(input).toBeFocused();
  const probe = await root.evaluate((component) => ({
    sameEdited: component.querySelector('#row-500 input[name="label"]') === window.__rowProbe.edited,
    sameNeighbor: component.querySelector('#row-501 input[name="label"]') === window.__rowProbe.neighbor,
    allocated: window.__rowProbe.allocated,
  }));
  expect(probe.sameEdited).toBe(true);
  expect(probe.sameNeighbor).toBe(true);
  expect(probe.allocated).toBeLessThanOrEqual(2);
});

test("app-owned list reorder keeps the focused keyed input", async ({page}) => {
  await page.goto("/native-list?rows=3");
  const root = page.locator("#native-list");
  const third = root.locator("#row-3 input[name='label']");
  await third.fill("Draft Three");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await page.evaluate(() => { window.__focusedNativeRow = document.querySelector("#row-3 input[name='label']"); });

  await root.locator("#row-2").getByRole("button", {name: "Move to top"}).evaluate((button) => button.click());
  await expect(root.locator("li").first()).toHaveAttribute("id", "row-2");
  await expect(third).toBeFocused();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");

  await root.locator("#row-3").getByRole("button", {name: "Move to top"}).evaluate((button) => button.click());
  await expect(root.locator("li").first()).toHaveAttribute("id", "row-3");
  await expect(third).toBeFocused();
  await expect(third).toHaveValue("Draft Three");
  expect(await page.evaluate(() => document.querySelector("#row-3 input[name='label']") === window.__focusedNativeRow)).toBe(true);
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "3");
});

test("native form handles a change event without a preceding input event", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const input = root.locator('#row-1 input[name="label"]');
  await input.evaluate((field) => {
    field.value = "Change only";
    field.dispatchEvent(new Event("change", {bubbles: true}));
  });
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(input).toHaveValue("Change only");
});

test("native list adds and removes rows with dynamic phx-value-id", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  await expect(root.locator("li")).toHaveCount(2);
  await page.evaluate(() => window.liveSocket.enableLatencySim(450));
  await root.getByRole("button", {name: "Add row"}).click();
  await expect(root.locator('#row-3 input[name="label"]')).toHaveValue("New", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.locator("#row-2").getByRole("button", {name: "Remove"}).click();
  await expect(root.locator("#row-2")).toHaveCount(0, {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await expect(root.locator("li")).toHaveCount(2);
});

test("native list replaces and deletes its last row by index", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  await root.getByRole("button", {name: "Reset last row"}).click();
  await expect(root.locator("li").last().getByRole("textbox")).toHaveValue("Reset");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Remove last row"}).click();
  await expect(root.locator("li")).toHaveCount(1);
  await expect(root.locator("li").last().getByRole("textbox")).toHaveValue("One");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native Enum.find predicts the first matching row and converges", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const match = root.getByRole("status", {name: "First new row"});
  await expect(match).toHaveText("None");
  await expect(root.locator("#row-1")).toHaveAttribute("title", "None");
  await root.getByRole("button", {name: "Find new row"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(match).toHaveText("None");
  await root.getByRole("button", {name: "Add row"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await root.getByRole("button", {name: "Find new row"}).click();
  await expect(match).toHaveText("New");
  await expect(root.locator("#row-1")).toHaveAttribute("title", "New");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "3");
});

test("native Enum.reduce combines app-owned rows and converges", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const combined = root.getByRole("status", {name: "Combined labels"});
  await expect(combined).toHaveText("");
  await root.getByRole("button", {name: "Combine labels"}).click();
  await expect(combined).toHaveText("OneTwo");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Add row"}).click();
  await root.getByRole("button", {name: "Combine labels"}).click();
  await expect(combined).toHaveText("OneTwoNew");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "3");
});

test("native Enum.sort_by preserves keyed focus and server order", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  await root.getByRole("button", {name: "Add row"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  const focused = root.locator('#row-2 input[name="label"]');
  await focused.focus();
  await root.getByRole("button", {name: "Sort labels"}).evaluate((button) => button.click());
  await expect(root.locator("li").first()).toHaveAttribute("id", "row-3");
  await expect(focused).toBeFocused();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native Enum.count predicts app-owned row counts", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const count = root.getByRole("status", {name: "New row count"});
  await expect(count).toHaveText("0");
  await root.getByRole("button", {name: "Count new rows"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(count).toHaveText("0");
  await root.getByRole("button", {name: "Add row"}).click();
  await root.getByRole("button", {name: "Count new rows"}).click();
  await expect(count).toHaveText("1");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "3");
});

test("native Enum.join renders app-owned labels and converges", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const joined = root.getByRole("status", {name: "Combined labels"});
  await root.getByRole("button", {name: "Join labels"}).click();
  await expect(joined).toHaveText("One · Two");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Add row"}).click();
  await root.getByRole("button", {name: "Join labels"}).click();
  await expect(joined).toHaveText("One · Two · New");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "3");
});

test("native Enum.flat_map expands app-owned labels and converges", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const result = root.getByRole("status", {name: "Combined labels"});
  await root.getByRole("button", {name: "Add row"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Expand labels"}).click();
  await expect(result).toHaveText("One · Two · New · !");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native Enum.with_index numbers app-owned labels and converges", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  const result = root.getByRole("status", {name: "Combined labels"});
  await root.getByRole("button", {name: "Number labels"}).click();
  await expect(result).toHaveText("1: One · 2: Two");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
});

test("native String.downcase follows Elixir's Greek sigma behavior", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  await root.locator('#row-1 input[name="label"]').fill("ΟΣ");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Lower labels"}).click();
  await expect(root.getByRole("status", {name: "Combined labels"})).toHaveText("οσ · two");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native String.split handles app-owned labels and converges", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  await root.locator('#row-1 input[name="label"]').fill("A,B");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Split labels"}).click();
  await expect(root.getByRole("status", {name: "Combined labels"})).toHaveText("A · B · Two");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native String.replace changes only the first comma and converges", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  await root.locator('#row-1 input[name="label"]').fill("A,B");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Replace first comma"}).click();
  await expect(root.getByRole("status", {name: "Combined labels"})).toHaveText("A · B,Two");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native map projections order field names and count values", async ({page}) => {
  await page.goto("/native-list");
  const root = page.locator("#native-list");
  await root.getByRole("button", {name: "Summarize fields"}).click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(root.getByRole("status", {name: "Combined labels"})).toHaveText("next_id · rows (2)");
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

test("native actions recover reordered requests and ignore duplicates", async ({page}) => {
  const delivered = [];
  let first;
  await page.routeWebSocket(/\/live\/websocket/, (browser) => {
    const server = browser.connectToServer();
    browser.onMessage((message) => {
      const frame = typeof message === "string" ? JSON.parse(message) : null;
      const sequence = frame?.[4]?.value?._live_lift_seq;
      if (sequence !== 1 && sequence !== 2) {
        server.send(message);
        return;
      }
      if (sequence === 1 && first === undefined) {
        first = message;
        return;
      }
      delivered.push(sequence);
      server.send(message);
      if (sequence === 2 && delivered.length === 1) {
        delivered.push(1);
        server.send(first);
        server.send(first);
      }
    });
  });

  await page.goto("/native-counter");
  await page.waitForFunction(() => window.liveSocket.isConnected());
  const root = page.locator("#native-counter");
  const add = root.getByRole("button", {name: "Add one"});
  await add.click();
  await add.click();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await expect(root.locator("output")).toHaveText("2");
  expect(delivered.slice(0, 2)).toEqual([2, 1]);
  await root.getByRole("button", {name: "Save on server"}).click();
  await expect(root.locator("span")).toHaveText("Saved 2");
});

test("an unmarked save reads authoritative component state", async ({page}) => {
  await page.goto("/native-counter");
  const root = page.locator("#native-counter");
  await page.evaluate(() => window.liveSocket.enableLatencySim(350));
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(root.locator("output")).toHaveText("1", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Save on server"}).click();
  await expect(root.locator("span")).toHaveText("Saved 1");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("server-only component saves the same authoritative count", async ({page}) => {
  await page.goto("/native-counter-server");
  const serverRoot = page.locator('section[aria-label="Native LiveComponent counter"]');
  await expect(serverRoot.locator("output")).toHaveText("0");
  await page.waitForFunction(() => window.liveSocket.isConnected());
  await serverRoot.getByRole("button", {name: "Add one"}).click();
  await expect(serverRoot.locator("output")).toHaveText("1");
  await serverRoot.getByRole("button", {name: "Save on server"}).click();
  await expect(serverRoot.locator("span")).toHaveText("Saved 1");
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
  const instance = await root.getAttribute("data-live-lift-instance");
  expect(instance).toBeTruthy();
  await page.evaluate(() => { window.liveSocket.disconnect(); window.liveSocket.connect(); });
  await page.waitForFunction(() => window.liveSocket.isConnected());
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "0");
  await expect(count).toHaveText("0");
  await expect(root).not.toHaveAttribute("data-live-lift-instance", instance);
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

test("offline clicks replay in order after the fresh LiveView snapshot", async ({page}) => {
  await page.goto("/native-counter");
  const root = page.locator("#native-counter");
  const count = root.locator("output");
  await page.evaluate(() => window.liveSocket.disconnect());
  await page.waitForFunction(() => !window.liveSocket.isConnected());
  await root.getByRole("button", {name: "Add one"}).click();
  await root.getByRole("button", {name: "Add one"}).click();
  await expect(count).toHaveText("2");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "0");
  await page.evaluate(() => window.liveSocket.connect());
  await page.waitForFunction(() => window.liveSocket.isConnected());
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await expect(count).toHaveText("2");
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
  await expect(root.locator("section")).toHaveAttribute("class", "native-form ");
  await expect(root.getByRole("textbox", {name: "Draft", exact: true})).not.toHaveAttribute("value");
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));
  await root.getByRole("textbox", {name: "Draft", exact: true}).fill("Client draft");
  await expect(root.locator("output")).toHaveText("Client draft", {timeout: 200});
  await expect(root.locator("section")).toHaveAttribute("class", "native-form Client draft");
  await expect(root.getByRole("textbox", {name: "Draft", exact: true})).toHaveAttribute("value", "Client draft");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("textbox", {name: "Note"}).fill("Saved locally");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
  await root.getByRole("button", {name: "Save note"}).click();
  await expect(root.locator("p")).toHaveText("Saved: Saved locally", {timeout: 200});
  await expect(root.locator("section")).toHaveAttribute("class", "native-form has-saved Client draft");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "3");
  await expect(root.locator("p")).toHaveText("Saved: Saved locally");
  await expect(root.locator("section")).toHaveAttribute("title", "Saved locally");
});

test("native form validates a nested field locally and on the server", async ({page}) => {
  await page.goto("/native-form");
  const root = page.locator("#native-form");
  const note = root.getByRole("textbox", {name: "Note"});
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));

  await note.fill("é");
  await expect(root.getByRole("alert")).toHaveText("Note must have at least 3 characters.", {timeout: 200});
  await expect(root.locator(".form-feedback")).toContainText("Note must have at least 3 characters.");
  await root.getByRole("button", {name: "Save note"}).click();
  await expect(root.locator("p").last()).toHaveText("Saved: ");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");

  await note.fill("  Validé  ");
  await expect(root.getByRole("alert")).toHaveCount(0, {timeout: 200});
  await expect(note).toHaveValue("  Validé  ");
  await root.getByRole("button", {name: "Save note"}).click();
  await expect(root.locator("p").last()).toHaveText("Saved:   Validé  ");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "4");
});

test("native phx-debounce delays prediction and flushes on blur", async ({page}) => {
  await page.goto("/native-form");
  const root = page.locator("#native-form");
  const draft = root.getByRole("textbox", {name: "Debounced draft"});
  const output = root.locator("output");
  await expect(draft).toHaveAttribute("phx-debounce", "300");
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));

  await draft.fill("First");
  await page.waitForTimeout(120);
  await expect(output).toHaveText("");
  await draft.fill("Second");
  await page.waitForTimeout(120);
  await expect(output).toHaveText("");
  await expect(output).toHaveText("Second");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");

  await draft.evaluate((input) => input.setAttribute("phx-debounce", "blur"));
  await draft.fill("On blur");
  await page.waitForTimeout(120);
  await expect(output).toHaveText("Second");
  await draft.blur();
  await expect(output).toHaveText("On blur");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native submit cancels a pending debounced form change", async ({page}) => {
  await page.goto("/native-form");
  const root = page.locator("#native-form");
  const note = root.getByRole("textbox", {name: "Note"});
  await note.evaluate((input) => input.setAttribute("phx-debounce", "300"));
  await note.fill("Valid note");
  await root.locator("form").evaluate((form) => form.requestSubmit());

  await expect(root.locator("p").last()).toHaveText("Saved: Valid note");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await page.waitForTimeout(450);
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
});

test("native assign_new reveals an initially absent field and converges", async ({page}) => {
  await page.goto("/native-optional");
  const root = page.locator("#native-optional");
  await expect(root).toHaveAttribute("data-live-lift-state", /"prefix":"Fresh"/);
  await expect(root).not.toHaveAttribute("data-live-lift-state", /"draft":/);
  await expect(root.locator("p")).toHaveCount(0);
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));

  await root.getByRole("button", {name: "Initialize draft"}).click();
  await expect(root.locator("p")).toHaveText("Fresh draft", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(root).toHaveAttribute("data-live-lift-state", /"draft":"Fresh draft"/);
});

test("native floats preserve type and display through optimistic and authoritative updates", async ({page}) => {
  await page.goto("/native-float");
  const root = page.locator("#native-float");
  const output = root.locator("output");
  await expect(output).toHaveText("-0.0");
  await expect(output).toHaveAttribute("title", "-0.0");
  await expect(root).toHaveAttribute("data-live-lift-state", /\$live_lift_float/);
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));

  await root.getByRole("button", {name: "Add half"}).click();
  await expect(output).toHaveText("0.5", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Add half"}).click();
  await expect(output).toHaveText("1.0", {timeout: 200});
  await expect(output).toHaveAttribute("title", "1.0");
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native cond selects a float branch without changing the LiveComponent template", async ({page}) => {
  await page.goto("/native-float");
  const root = page.locator("#native-float");
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));
  await root.getByRole("button", {name: "Minimum one"}).click();
  await expect(root.locator("output")).toHaveText("1.0", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await expect(root.locator("output")).toHaveAttribute("title", "1.0");
});

test("native case matches a typed float and converges after a prior client action", async ({page}) => {
  await page.goto("/native-float");
  const root = page.locator("#native-float");
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));
  await root.getByRole("button", {name: "Minimum one"}).click();
  await expect(root.locator("output")).toHaveText("1.0", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Advance one"}).click();
  await expect(root.locator("output")).toHaveText("2.0", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("native multi-clause helper works after the marked handler", async ({page}) => {
  await page.goto("/native-float");
  const root = page.locator("#native-float");
  const output = root.locator("output");
  await page.evaluate(() => window.liveSocket.enableLatencySim(400));
  await root.getByRole("button", {name: "Helper step"}).click();
  await expect(output).toHaveText("0.5", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "1");
  await root.getByRole("button", {name: "Helper step"}).click();
  await expect(output).toHaveText("1.0", {timeout: 200});
  await expect(root).toHaveAttribute("data-live-lift-server-revision", "2");
});

test("100 opted-in islands keep their state and events isolated", async ({page}) => {
  await page.goto("/many-islands?count=100");
  await expect(page.locator('#many-islands [data-live-lift-mode="component"]')).toHaveCount(100);

  for (const index of [1, 50, 100]) {
    const island = page.locator(`#island-${index}`);
    await island.getByRole("button", {name: "Add one"}).click();
    await expect(island.locator("output")).toHaveText("1");
    await expect(island).toHaveAttribute("data-live-lift-server-revision", "1");
  }

  for (const index of [2, 49, 51, 99]) {
    const island = page.locator(`#island-${index}`);
    await expect(island.locator("output")).toHaveText("0");
    await expect(island).toHaveAttribute("data-live-lift-server-revision", "0");
  }
});
