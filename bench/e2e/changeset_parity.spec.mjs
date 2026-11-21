import {execFileSync} from "node:child_process";
import {mkdtempSync, readFileSync, rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {fileURLToPath} from "node:url";
import {expect, test} from "@playwright/test";

test("changeset form projections match Ecto in the browser", async ({page}) => {
  test.setTimeout(180_000);
  const dir = mkdtempSync(join(tmpdir(), "live-lift-ecto-"));
  let source;
  try {
    const target = join(dir, "cases.mjs");
    execFileSync("elixir", ["bench/changeset_parity.exs", "--browser", target], {
      cwd: fileURLToPath(new URL("../../", import.meta.url)),
      timeout: 150_000,
    });
    source = readFileSync(target, "utf8");
  } finally {
    rmSync(dir, {recursive: true, force: true});
  }
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
