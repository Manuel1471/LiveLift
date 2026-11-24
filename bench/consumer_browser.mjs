import assert from "node:assert/strict";
import {chromium, firefox, webkit} from "playwright";

const url = new URL("/counter", process.argv[2]).href;
const mode = process.argv[3];
const response = await fetch(url);
assert.ok(response.ok);
assert.match(await response.text(), /<output[^>]*id="count"[^>]*>3<\/output>/);

const ack = "data-live-lift-ack-seq";
for (const [name, engine] of Object.entries({chromium, firefox, webkit})) {
  const browser = await engine.launch();
  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(10_000);
    const pageErrors = [];
    page.on("pageerror", (error) => pageErrors.push(error.message));
    await page.goto(url);
    await page.locator(`.phx-connected [${ack}="0"]`).waitFor({state: "attached"});
    if (mode === "npm-split") {
      await page.locator('[data-live-lift-load="ready"]').waitFor({state: "attached"});
    }

    // Sample in the same JavaScript turn as the click, before a server reply can apply.
    const predicted = await page.evaluate((ackAttribute) => {
      document.querySelector("#inc").click();
      return {
        count: document.querySelector("#count").textContent,
        ack: document.querySelector(`[${ackAttribute}]`).getAttribute(ackAttribute),
      };
    }, ack);
    assert.deepEqual(predicted, {count: "4", ack: "0"});
    await page.locator(`[${ack}="1"]`).waitFor({state: "attached"});
    assert.equal(await page.locator("#count").textContent(), "4");
    await page.locator("#save").click();
    await page.getByText("Saved 4", {exact: true}).waitFor();
    assert.equal(await page.locator(`[${ack}]`).getAttribute(ack), "1");
    assert.deepEqual(pageErrors, []);

    console.log(`${mode} ${name} ${browser.version()}: SSR 3, local 4 before ack, ack 1, Saved 4`);
  } finally {
    await browser.close();
  }
}
