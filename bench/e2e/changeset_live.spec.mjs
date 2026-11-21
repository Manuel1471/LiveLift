import {spawn} from "node:child_process";
import {fileURLToPath} from "node:url";
import {expect, test} from "@playwright/test";

const root = fileURLToPath(new URL("../../", import.meta.url));

test("native changeset form converges over the LiveView websocket", async ({page}) => {
  test.setTimeout(180_000);
  const fixture = spawn("elixir", ["bench/changeset_live_fixture.exs"], {cwd: root});
  let output = "";
  try {
    const url = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(`Changeset fixture timed out\n${output}`)), 140_000);
      fixture.on("error", reject);
      fixture.once("exit", (code) => reject(new Error(`Changeset fixture exited with ${code}\n${output}`)));
      fixture.stderr.on("data", (chunk) => { output += chunk; });
      fixture.stdout.on("data", (chunk) => {
        output += chunk;
        const ready = output.match(/CHANGESET_FIXTURE_URL=(http:\/\/127\.0\.0\.1:\d+\/)/);
        if (!ready) return;
        clearTimeout(timeout);
        resolve(ready[1]);
      });
      fixture.once("close", () => clearTimeout(timeout));
    });
    let first;
    await page.routeWebSocket(/\/live\/websocket/, (browser) => {
      const server = browser.connectToServer();
      browser.onMessage((message) => {
        const frame = typeof message === "string" ? JSON.parse(message) : null;
        if (!first && frame?.[4]?.event === "validate") {
          first = {body: frame[4].value, send: () => server.send(message)};
        } else {
          server.send(message);
        }
      });
    });
    await page.goto(url);
    const island = page.locator("#profile");
    await expect(island).toHaveAttribute("data-live-lift-load", "ready");
    const name = page.getByRole("textbox", {name: "Name"});
    const code = page.getByRole("textbox", {name: "Code"});
    const zone = page.getByRole("textbox", {name: "Zone"});
    const usedName = page.locator("#name-used");
    const error = page.getByText("has invalid format");
    const ack = "data-live-lift-ack-seq";
    const snapshot = () => island.evaluate((element) => JSON.parse(element.dataset.liveLiftState));

    await expect(error).toHaveCount(0);
    await code.fill("bad");
    await expect(error).toBeVisible();
    await expect(usedName).toHaveCount(0);
    await expect(island).toHaveAttribute(ack, "0");
    await expect.poll(() => first?.body.profile).toEqual({
      name: "", code: "bad", zone: "", static: "fixed", _unused_name: "", _unused_zone: "",
    });
    first.send();
    await expect(island).toHaveAttribute(ack, "1");
    expect(await snapshot()).toMatchObject({
      used: false, raw_code: "bad", valid: false,
      code_errors: [
        {message: "has invalid format", count: null},
        {message: "should be %{count} character(s)", count: 2},
      ],
    });
    await expect(error).toBeVisible();

    await name.fill("  ");
    await expect(island).toHaveAttribute(ack, "2");
    await expect(name).toHaveValue("  ");
    expect(await snapshot()).toMatchObject({used: true, raw: "  ", name: null, valid: false});

    await name.fill("é🙂");
    await code.fill("OK");
    await zone.fill("lab-1");
    await expect(island).toHaveAttribute(ack, "5");
    await expect(error).toHaveCount(0);
    await expect(usedName).toHaveText("é🙂");
    expect(await snapshot()).toMatchObject({used: true, raw: "é🙂", raw_code: "OK", valid: true});
    await page.getByRole("button", {name: "Validate"}).click();
    await expect(island).toHaveAttribute(ack, "6");
    expect(await snapshot()).toMatchObject({valid: true, code_errors: []});
  } finally {
    fixture.kill();
  }
});
