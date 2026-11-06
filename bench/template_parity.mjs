import {readFileSync} from "node:fs";
import {parseHTML} from "linkedom";
import {createClientHook} from "../assets/js/live_lift/client_hook.js";

function childrenOf(node) {
  const projected = [];
  for (const child of node.childNodes) {
    const value = project(child);
    if (!value) continue;
    if (value[0] === "text" && projected.at(-1)?.[0] === "text") {
      projected.at(-1)[1] += value[1];
    } else {
      projected.push(value);
    }
  }
  return projected;
}

function project(node) {
  if (node.nodeType === 3) return node.nodeValue ? ["text", node.nodeValue] : null;
  if (node.nodeType === 8) return null;
  if (node.nodeType !== 1) return null;
  const attrs = [...node.attributes]
    .map((attr) => [attr.name, attr.value])
    .sort(([left], [right]) => left.localeCompare(right));
  return [node.tagName, attrs, childrenOf(node)];
}

const cases = JSON.parse(readFileSync(process.argv[2], "utf8"));
for (const [index, item] of cases.entries()) {
  const {document} = parseHTML(`<html><body><div id="root"></div></body></html>`);
  globalThis.document = document;
  const root = document.querySelector("#root");
  root.dataset.liveLiftModule = "Parity";
  root.dataset.liveLiftState = JSON.stringify(item.state);
  root.innerHTML = item.html;
  const expected = childrenOf(root);
  const hook = createClientHook({Parity: {template: item.tree, actions: {}}});
  hook.el = root;
  hook.mounted();
  hook.render();
  const actual = childrenOf(root);
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Template parity failed at case ${index}:\n${JSON.stringify({expected, actual})}`);
  }
}
console.log(`${cases.length} template cases matched`);
