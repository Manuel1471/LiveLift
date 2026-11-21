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

  await root.locator('button[phx-click="label"]').evaluate((button) => button.click());
  await expect(label).toHaveText("ready");
  await expect(label).not.toHaveClass("spike-active");
  await expect(increment).toBeFocused();
});
