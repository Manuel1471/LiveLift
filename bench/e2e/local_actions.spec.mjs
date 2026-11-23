import {test, expect} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

test("local Elixir actions render without sending events and survive LiveView updates", async ({page}) => {
  const events = [];
  page.on("websocket", socket => socket.on("framesent", ({payload}) => {
    if (typeof payload !== "string") return;
    const message = JSON.parse(payload);
    if (message[3] === "event") events.push(message[4].event);
  }));

  await gotoLiveLift(page, "/local-actions");
  const root = page.locator('[data-live-lift-module="LiveLiftDemoWeb.LocalActionsLive"]');
  const rows = root.getByRole("list", {name: "Preview order"}).getByRole("button");
  await expect(rows).toHaveText(["One", "Two"]);
  const revision = await root.getAttribute("data-live-lift-server-revision");

  await root.getByRole("button", {name: "Two"}).focus();
  await root.getByRole("button", {name: "Reverse preview"}).evaluate(button => button.click());
  await expect(rows).toHaveText(["Two", "One"]);
  await expect(rows.first()).toBeFocused();
  await expect(root).toHaveAttribute("data-live-lift-server-revision", revision);
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");

  await root.getByRole("button", {name: "Increase shared count"}).click();
  await expect(root.locator("#local-shared-count")).toHaveText("1");
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "1");
  await expect(rows).toHaveText(["Two", "One"]);

  await rows.first().click();
  await expect(root.locator("#local-saved-first")).toHaveText("Two");
  await expect(rows).toHaveText(["Two", "One"]);
  expect(events).toEqual(["increase_count", "save_first"]);

  await gotoLiveLift(page, "/local-actions");
  await expect(rows).toHaveText(["One", "Two"]);
});
