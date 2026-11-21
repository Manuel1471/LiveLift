import {execFileSync} from "node:child_process";
import {fileURLToPath} from "node:url";
import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

const demo = fileURLToPath(new URL("../../examples/demo/", import.meta.url));

test("native dispatch spike reaches an app listener without a LiveView action", async ({page}) => {
  const encoded = execFileSync("mix", ["run", "--no-start", "--no-compile", "-e", `
    alias Phoenix.LiveView.JS
    IO.puts(Jason.encode!(JS.dispatch("workspace:preview", to: {:inner, ".preview-target"}, bubbles: false)))
  `], {cwd: demo, encoding: "utf8"}).trim();

  await gotoLiveLift(page, "/native-counter");
  const island = page.locator("#native-counter");
  await island.evaluate((root, binding) => {
    const source = document.createElement("div");
    source.setAttribute("phx-click", binding);
    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.textContent = "Preview locally";
    const target = document.createElement("output");
    target.className = "preview-target";
    const outside = document.createElement("output");
    outside.className = "preview-target";
    outside.id = "dispatch-outside";
    outside.textContent = "Outside idle";
    outside.addEventListener("workspace:preview", () => { outside.textContent = "Outside changed"; });

    document.addEventListener("workspace:preview", () => {
      root.dataset.dispatchBubbled = "true";
    });
    target.addEventListener("workspace:preview", (event) => {
      target.textContent = event instanceof CustomEvent && event.detail.dispatcher === source
        ? "Preview rendered"
        : "Unexpected event";
    });

    source.append(trigger, target);
    root.append(source);
    root.after(outside);
  }, encoded);

  await island.getByRole("button", {name: "Preview locally"}).click();
  await expect(island.locator(".preview-target")).toHaveText("Preview rendered");
  await expect(page.locator("#dispatch-outside")).toHaveText("Outside idle");
  await expect(island).not.toHaveAttribute("data-dispatch-bubbled", "true");
  await expect(island).toHaveAttribute("data-live-lift-ack-seq", "0");
  await expect(island).toHaveAttribute("data-live-lift-server-revision", "0");
});

test("compiled native dispatch opens the app dialog before and after an island patch", async ({page}) => {
  for (const route of ["/native-counter-server", "/native-counter"]) {
    await gotoLiveLift(page, route);

    const counter = page.getByRole("region", {name: "Native LiveComponent counter"});
    const dialog = page.getByRole("dialog", {name: "Local preview"});
    const preview = counter.getByRole("button", {name: "Open local preview"});
    const encoded = await preview.getAttribute("phx-click");

    await preview.click();
    await expect(dialog).toBeVisible();
    if (route === "/native-counter") {
      await expect(page.locator("#native-counter")).toHaveAttribute("data-live-lift-ack-seq", "0");
    }
    await dialog.getByRole("button", {name: "Close preview"}).click();
    await expect(dialog).toBeHidden();

    await counter.getByRole("button", {name: "Set label"}).click();
    await expect(counter.locator("span")).toHaveText("ready");
    await expect(preview).toHaveAttribute("phx-click", encoded);
    await preview.click();
    await expect(dialog).toBeVisible();
    if (route === "/native-counter") {
      await expect(page.locator("#native-counter")).toHaveAttribute("data-live-lift-ack-seq", "1");
    }
  }
});
