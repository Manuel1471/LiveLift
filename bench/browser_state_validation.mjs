import {readFile} from "node:fs/promises";
import {chromium} from "@playwright/test";

const [baselinePath] = process.argv.slice(2);
if (!baselinePath) throw new Error("Pass the baseline client_hook.js path.");

const moduleURL = (source) => `data:text/javascript,${encodeURIComponent(source + "\nexport {validateState};")}`;
const urls = [
  moduleURL(await readFile(baselinePath, "utf8")),
  moduleURL(await readFile(new URL("../assets/js/live_lift/client_hook.js", import.meta.url), "utf8")),
];

for (const cpu of [1, 4]) {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    const session = await page.context().newCDPSession(page);
    await session.send("Emulation.setCPUThrottlingRate", {rate: cpu});

    const results = await page.evaluate(async (urls) => {
      const validators = await Promise.all(urls.map(async (url) => (await import(url)).validateState));
      const repeats = 16;
      const measure = (validate, state) => {
        const start = performance.now();
        for (let index = 0; index < repeats; index++) validate(state);
        return (performance.now() - start) / repeats;
      };
      const summarize = (values) => {
        values.sort((a, b) => a - b);
        const percentile = (fraction) => values[Math.ceil(values.length * fraction) - 1];
        return {min: values[0], median: percentile(.5), p95: percentile(.95),
          max: values.at(-1), iqr: percentile(.75) - percentile(.25)};
      };

      return [100, 1_000].map((rows) => {
        const state = {items: Array.from({length: rows}, (_, index) => ({
          id: `row-${index + 1}`,
          label: `Línea ${index + 1}`,
        }))};

        for (let index = 0; index < 20; index++) {
          validators.forEach((validate) => measure(validate, state));
        }

        const samples = [[], []];
        for (let index = 0; index < 100; index++) {
          for (const variant of (index % 2 ? [0, 1] : [1, 0])) {
            samples[variant].push(measure(validators[variant], state));
          }
        }
        return {rows, samples: 100, validationsPerSample: repeats,
          baselineMs: summarize(samples[0]), candidateMs: summarize(samples[1])};
      });
    }, urls);

    console.log(JSON.stringify({chromium: browser.version(), cpu, results}));
  } finally {
    await browser.close();
  }
}
