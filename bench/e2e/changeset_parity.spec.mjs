import {execFileSync} from "node:child_process";
import {mkdtempSync, readFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {expect, test} from "@playwright/test";

function fixture(mode) {
  const dir = mkdtempSync(join(tmpdir(), "live-lift-ecto-"));
  try {
    const target = join(dir, "cases.mjs");
    execFileSync("elixir", ["bench/changeset_parity.exs", mode, target], {
      cwd: fileURLToPath(new URL("../../", import.meta.url)),
      timeout: 150_000,
    });
    return readFileSync(target, "utf8");
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
}

test("changeset form projections match Ecto in the browser", async ({page}) => {
  test.setTimeout(180_000);
  const source = fixture("--browser");
  const checked = await page.evaluate(async (source) => {
    const blob = URL.createObjectURL(new Blob([source], {type: "text/javascript"}));
    try {
      const {actions, cases} = await import(blob);
      const sortKeys = (value) => {
        if (Array.isArray(value)) return value.map(sortKeys);
        if (!value || typeof value !== "object") return value;
        return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortKeys(value[key])]));
      };
      for (const {state, params, expected} of cases) {
        const actual = actions.validate(state, {params});
        if (JSON.stringify(sortKeys(actual)) !== JSON.stringify(sortKeys(expected))) {
          throw new Error(JSON.stringify({state, params, expected, actual}));
        }
      }
      return cases.length;
    } finally {
      URL.revokeObjectURL(blob);
    }
  }, source);
  expect(checked).toBe(1440);
});

test("changeset form tracks used fields before Ecto reconciliation", async ({page}) => {
  test.setTimeout(180_000);
  const runtime = readFileSync(new URL("../../assets/js/live_lift/client_hook.js", import.meta.url), "utf8");
  await page.evaluate(async ({runtime, registry}) => {
    const load = async (source) => {
      const url = URL.createObjectURL(new Blob([source], {type: "text/javascript"}));
      try { return await import(url); }
      finally { URL.revokeObjectURL(url); }
    };
    const {createClientHook} = await load(runtime);
    const {views, cases} = await load(registry);
    const root = document.createElement("div");
    root.id = "changeset-form";
    root.dataset.liveLiftMode = "component";
    root.dataset.liveLiftModule = "ChangesetParityComponent";
    root.dataset.liveLiftState = JSON.stringify(cases[0].state);
    document.body.append(root);
    const requests = [];
    window.formRequests = requests;
    window.confirmCode = () => {
      const {expected} = cases.find(({state, params}) => state.data.name === null &&
        params.profile.name === "" && params.profile.code === "bad" && params.profile.zone === "");
      requests[0].reply({revision: 1, ack_seq: 1, state: expected});
    };
    const hook = {
      ...createClientHook(views), el: root,
      pushEventTo: (_, event, payload, reply) => { requests.push({event, payload, reply}); },
    };
    hook.mounted();
  }, {runtime, registry: fixture("--registry")});

  await page.getByRole("textbox", {name: "Code"}).fill("bad");
  await expect(page.getByText("has invalid format")).toBeVisible();
  await expect(page.locator("#name-used")).toHaveCount(0);
  expect(await page.evaluate(() => window.formRequests[0].payload.profile)).toEqual({
    name: "", code: "bad", zone: "", static: "fixed", _unused_name: "", _unused_zone: "",
  });
  await page.evaluate(() => window.confirmCode());
  await expect(page.getByText("has invalid format")).toBeVisible();
  await expect(page.locator("#name-used")).toHaveCount(0);

  await page.getByRole("textbox", {name: "Name"}).fill("é🙂");
  await expect(page.locator("#name-used")).toHaveText("é🙂");
  expect(await page.evaluate(() => window.formRequests.at(-1).payload.profile)).toEqual({
    name: "é🙂", code: "bad", zone: "", static: "fixed", _unused_zone: "",
  });
  await page.getByRole("button", {name: "Validate"}).click();
  expect(await page.evaluate(() => window.formRequests.at(-1).payload.profile)).toEqual({
    name: "é🙂", code: "bad", zone: "", static: "fixed",
  });

  await page.locator("form").evaluate((form) => form.reset());
  await page.getByRole("textbox", {name: "Code"}).fill("OK");
  expect(await page.evaluate(() => window.formRequests.at(-1).payload.profile)).toEqual({
    name: "é🙂", code: "OK", zone: "", static: "fixed", _unused_name: "", _unused_zone: "",
  });

  await page.locator("form").evaluate((form) => form.setAttribute("phx-no-unused-field", ""));
  await page.getByRole("textbox", {name: "Code"}).fill("NO");
  expect(await page.evaluate(() => window.formRequests.at(-1).payload.profile)).toEqual({
    name: "é🙂", code: "NO", zone: "", static: "fixed",
  });
});
