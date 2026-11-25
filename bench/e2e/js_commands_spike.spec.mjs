import {execFileSync} from "node:child_process";
import {fileURLToPath} from "node:url";
import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

const demo = fileURLToPath(new URL("../../examples/demo/", import.meta.url));

function encodedCommands() {
  const probe = `
    alias Phoenix.LiveView.JS
    IO.puts(Jason.encode!(%{
      class: JS.toggle_class("spike-active", to: "#native-counter span"),
      focus: JS.focus(to: "#native-counter button[phx-click=inc]")
    }))
  `;
  return JSON.parse(execFileSync("mix", ["run", "--no-start", "--no-compile", "-e", probe], {
    cwd: demo, encoding: "utf8",
  }).trim());
}

test("JS command spike measures sticky classes and focus after an island patch", async ({page}) => {
  const commands = encodedCommands();
  await gotoLiveLift(page, "/native-counter");
  const root = page.locator("#native-counter");
  const label = root.locator("span");
  await root.evaluate((island, commands) => {
    for (const [name, command] of Object.entries(commands)) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = `Run ${name} command`;
      button.setAttribute("phx-click", JSON.stringify(command));
      island.append(button);
    }
  }, commands);
  await root.getByRole("button", {name: "Run class command"}).click();
  await expect(label).toHaveClass("spike-active");
  await root.getByRole("button", {name: "Run focus command"}).click();
  const increment = root.locator("button[phx-click=inc]");
  await expect(increment).toBeFocused();

  await root.getByRole("button", {name: "Set label"}).evaluate((button) => button.click());
  await expect(label).toHaveText("ready");
  await expect(label).not.toHaveClass("spike-active");
  await expect(increment).toBeFocused();
});

test("native focus commands retain their binding across an optimistic render", async ({page}) => {
  await gotoLiveLift(page, "/native-counter");
  const root = page.locator("#native-counter");
  const target = root.getByRole("textbox", {name: "Command focus target"});
  const first = root.getByRole("textbox", {name: "First focusable field"});
  const control = root.getByRole("button", {name: "Focus target", exact: true});
  const binding = control.locator("..");
  const original = await binding.getAttribute("phx-click");

  await control.click();
  await expect(target).toBeFocused();
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");
  await root.getByRole("button", {name: "Set label"}).evaluate((button) => button.click());
  await expect(root.locator("span")).toHaveText("ready");
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "1");
  await expect(target).toBeFocused();
  await expect(binding).toHaveAttribute("phx-click", original);

  await root.getByRole("button", {name: "Focus first field"}).click();
  await expect(first).toBeFocused();
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "1");
});

test("native class commands match LiveView across optimistic and server patches", async ({page}) => {
  for (const route of ["/native-counter-server", "/native-counter"]) {
    await gotoLiveLift(page, route);
    const root = page.getByRole("region", {name: "Native LiveComponent counter"});
    const add = root.locator("#class-add");
    const remove = root.locator("#class-remove");
    const toggle = root.locator("#class-toggle");

    // Cancel after LiveLift sees the click and before Phoenix can execute it.
    await add.evaluate((target) => {
      const island = target.closest("#native-counter") ?? target.closest("section");
      island.parentElement.addEventListener("click", (event) => event.stopPropagation(), {once: true});
    });
    await add.click();
    await add.evaluate((button) => {
      button.disabled = true;
      button.dispatchEvent(new MouseEvent("click", {bubbles: true}));
      button.disabled = false;
    });
    await root.getByRole("button", {name: "Set label"}).click();
    await expect(toggle).toHaveText("ready");
    await expect(add).toHaveClass("class-sample ready");

    await add.click();
    await root.getByRole("button", {name: "Remove initial style"}).click();
    await root.getByRole("button", {name: "Toggle accent"}).click();
    await expect(add).toHaveClass("class-sample ready accent");
    await expect(remove).toHaveClass("class-sample ready");
    await expect(toggle).toHaveClass("class-sample ready accent");

    await root.getByRole("button", {name: "Save on server"}).click();
    await expect(toggle).toHaveText("Saved 0");
    await expect(add).toHaveClass("class-sample Saved 0 accent");
    await expect(remove).toHaveClass("class-sample Saved 0");
    await expect(toggle).toHaveClass("class-sample Saved 0 accent");

    await root.getByRole("button", {name: "Toggle accent"}).click();
    await expect(toggle).toHaveClass("class-sample Saved 0");
    await root.getByRole("button", {name: "Set label"}).click();
    await expect(toggle).toHaveText("ready");
    await expect(add).toHaveClass("class-sample ready accent");
    await expect(remove).toHaveClass("class-sample ready");
    await expect(toggle).toHaveClass("class-sample ready");
  }
});
