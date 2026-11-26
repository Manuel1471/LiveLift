import {execFileSync} from "node:child_process";
import {readFileSync} from "node:fs";
import {isDeepStrictEqual} from "node:util";
import {chromium, firefox, webkit} from "@playwright/test";

const root = new URL("../", import.meta.url);
const output = execFileSync("mix", ["run", "--no-compile", "bench/preformatted_text_spike.exs"], {
  cwd: root, encoding: "utf8",
});
const fixtures = JSON.parse(output);
const runtime = readFileSync(new URL("assets/js/live_lift/client_hook.js", root), "utf8");

for (const engine of [chromium, firefox, webkit]) {
  const browser = await engine.launch();
  try {
    const page = await browser.newPage();
    await page.setContent("<!doctype html><main></main>");
    await page.addScriptTag({type: "module", content: `${runtime}\nwindow.createClientHook = createClientHook;`});
    const results = await page.evaluate((fixtures) => {
      const root = document.querySelector("main");
      return fixtures.map(({name, tag, tree, state, html}) => {
        const parsed = new DOMParser().parseFromString(html, "text/html");
        root.replaceChildren(document.importNode(parsed.body.firstElementChild, true));
        const text = () => {
          const element = root.firstElementChild;
          return tag === "textarea"
            ? {defaultValue: element.defaultValue, value: element.value}
            : element.textContent;
        };
        const initial = text();
        root.dataset.liveLiftModule = "Spike";
        root.dataset.liveLiftMode = "component";
        root.dataset.liveLiftState = JSON.stringify(state);
        const hook = window.createClientHook({Spike: {template: tree, actions: {}}});
        hook.el = root;
        hook.mounted();
        try {
          hook.render();
          return {name, initial, rendered: text()};
        } finally {
          hook.destroyed();
        }
      });
    }, fixtures);
    const mismatches = results.filter(({initial, rendered}) => !isDeepStrictEqual(initial, rendered));
    console.log(`${engine.name()} ${browser.version()}: ${mismatches.length}/${results.length} differ`);
    for (const mismatch of mismatches) console.log(JSON.stringify(mismatch));
  } finally {
    await browser.close();
  }
}
