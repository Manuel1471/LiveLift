import {readFile} from "node:fs/promises";
import {chromium} from "@playwright/test";

const baselinePath = process.argv[2];
if (!baselinePath) throw new Error("Pass the path to the baseline client_hook.js");
const sources = await Promise.all([
  readFile(baselinePath, "utf8"),
  readFile(new URL("../assets/js/live_lift/client_hook.js", import.meta.url), "utf8"),
]);

const browser = await chromium.launch();
try {
  const page = await browser.newPage();
  const results = await page.evaluate(async sources => {
    const hooks = await Promise.all(sources.map(async source => {
      const url = URL.createObjectURL(new Blob([source], {type: "text/javascript"}));
      try {
        return (await import(url)).createClientHook({});
      } finally {
        URL.revokeObjectURL(url);
      }
    }));

    return [100, 1_000].map(rows => {
      const items = Array.from({length: rows}, (_, index) => ({
        id: `row-${index}`, label: `Row ${index}`
      }));
      const dataset = {
        liveLiftState: JSON.stringify({items}),
        liveLiftServerRevision: "1",
        liveLiftAckSeq: "1"
      };
      const island = {
        el: {dataset},
        optimistic: true,
        serverRevision: 1,
        ackSequence: 1,
        authoritativeBatch: {enqueue() { throw new Error("An unchanged snapshot was queued"); }}
      };

      function measure(hook) {
        const started = performance.now();
        for (let i = 0; i < 1000; i++) hook.updated.call(island);
        return performance.now() - started;
      }

      const samples = [[], []];
      for (let i = 0; i < 50; i++) {
        for (const index of i % 2 === 0 ? [0, 1] : [1, 0]) {
          const sample = measure(hooks[index]);
          if (i >= 10) samples[index].push(sample);
        }
      }

      const [baseline, candidate] = samples.map(values => {
        values.sort((a, b) => a - b);
        return {median: values[19], p95: values[37]};
      });
      return {rows, bytes: new TextEncoder().encode(dataset.liveLiftState).length, baseline, candidate};
    });
  }, sources);
  console.log(JSON.stringify(results, null, 2));
} finally {
  await browser.close();
}
