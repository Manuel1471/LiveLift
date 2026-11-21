import {execFile} from "node:child_process";
import {mkdtempSync, readFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {promisify} from "node:util";
import {expect, test} from "@playwright/test";

const run = promisify(execFile);
const repo = fileURLToPath(new URL("../../", import.meta.url));

test("the seeded Elixir compiler corpus matches generated browser actions", async ({page}) => {
  test.setTimeout(120_000);
  const directory = mkdtempSync(join(tmpdir(), "livelift-browser-parity-"));
  let code, corpus;
  try {
    await run("mix", ["test", "test/live_lift/property_parity_test.exs"], {
      cwd: repo,
      env: {...process.env, LIVE_LIFT_BROWSER_CORPUS_DIR: directory},
      timeout: 90_000,
    });
    code = readFileSync(join(directory, "actions.mjs"), "utf8");
    corpus = JSON.parse(readFileSync(join(directory, "cases.json"), "utf8"));
  } finally {
    rmSync(directory, {recursive: true, force: true});
  }

  await page.route("https://livelift.test/", (route) =>
    route.fulfill({contentType: "text/html", body: "<!doctype html><title>Compiler parity</title>"}));
  await page.route("https://livelift.test/actions.mjs", (route) =>
    route.fulfill({contentType: "text/javascript", body: code}));
  await page.goto("https://livelift.test/");
  const actual = await page.evaluate(async (states) => {
    const {actions} = await import("/actions.mjs");
    return states.map((state) => actions.check(state));
  }, corpus.input);

  expect(actual).toHaveLength(corpus.expected.length);
  for (const [index, expected] of corpus.expected.entries()) {
    expect(actual[index], `Elixir parity for corpus case ${index}`).toEqual(expected);
  }
});
