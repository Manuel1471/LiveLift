import {createHash} from "node:crypto";
import {copyFile, mkdir, readFile, writeFile} from "node:fs/promises";

const root = new URL("../", import.meta.url);
const {version} = JSON.parse(await readFile(new URL("package.json", root), "utf8"));
const runtime = await readFile(new URL("js/live_lift/client_hook.js", root));
const digest = createHash("sha256").update(version).update("\0").update(runtime).digest("hex");
const binding = `__liveLiftRuntime_${version.replace(/[^A-Za-z0-9_]/g, "_")}_${digest}`;

await mkdir(new URL("dist/", root), {recursive: true});
await writeFile(new URL("dist/runtime.js", root),
  `export {createClientHook, createClientHook as ${binding}} from "../js/live_lift/client_hook.js";\n`);
await copyFile(new URL("../LICENSE", root), new URL("dist/LICENSE", root));
