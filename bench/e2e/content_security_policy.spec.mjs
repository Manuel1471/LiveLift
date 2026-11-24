import {expect, test} from "@playwright/test";
import {gotoLiveLift} from "./support.mjs";

test("local and optimistic actions work under an enforced script CSP", async ({page}) => {
  await page.addInitScript(() => {
    window.cspViolations = [];
    window.addEventListener("securitypolicyviolation", ({blockedURI, effectiveDirective}) => {
      window.cspViolations.push({blockedURI, effectiveDirective});
    });
  });

  await Promise.all([
    page.waitForResponse((response) =>
      response.ok() && /\/chunks\/LiveLiftDemoWeb\.LocalActionsLive-/.test(new URL(response.url()).pathname)
    ),
    gotoLiveLift(page, "/local-actions-csp"),
  ]);

  const root = page.locator('[data-live-lift-module="LiveLiftDemoWeb.LocalActionsLive"]');
  const rows = root.getByRole("list", {name: "Preview order"}).getByRole("button");
  await expect(rows).toHaveText(["One", "Two"]);
  await root.getByRole("button", {name: "Reverse preview"}).click();
  await expect(rows).toHaveText(["Two", "One"]);
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "0");
  await root.getByRole("button", {name: "Increase shared count"}).click();
  await expect(root.locator("#local-shared-count")).toHaveText("1");
  await expect(root).toHaveAttribute("data-live-lift-ack-seq", "1");
  await rows.first().click();
  await expect(root.locator("#local-saved-first")).toHaveText("Two");
  expect(await page.evaluate(() => window.cspViolations)).toEqual([]);

  // Prove that the browser enforces the response header.
  await page.evaluate(() => {
    const inline = document.createElement("script");
    inline.textContent = "window.inlineProbeRan = true";
    document.head.append(inline);
  });
  await expect.poll(() => page.evaluate(() => window.cspViolations)).toEqual([
    {blockedURI: "inline", effectiveDirective: "script-src-elem"},
  ]);
  expect(await page.evaluate(() => window.inlineProbeRan)).toBeUndefined();
});
