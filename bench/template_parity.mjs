import {readFileSync} from "node:fs";
import {parseHTML} from "linkedom";
import {createClientHook} from "../assets/js/live_lift/client_hook.js";

function childrenOf(node, ignoredAttributes) {
  const projected = [];
  for (const child of node.childNodes) {
    const value = project(child, ignoredAttributes);
    if (!value) continue;
    if (value[0] === "text" && projected.at(-1)?.[0] === "text") {
      projected.at(-1)[1] += value[1];
    } else {
      projected.push(value);
    }
  }
  return projected;
}

function project(node, ignoredAttributes) {
  if (node.nodeType === 3) return node.nodeValue ? ["text", node.nodeValue] : null;
  if (node.nodeType === 8) return null;
  if (node.nodeType !== 1) return null;
  const attrs = [...node.attributes]
    .filter((attr) => !ignoredAttributes?.has(attr.name))
    .map((attr) => [attr.name, attr.value])
    .sort(([left], [right]) => left.localeCompare(right));
  return [node.tagName, attrs, childrenOf(node, ignoredAttributes)];
}

function parseServerHTML(html) {
  const {document} = parseHTML(`<html><body><div id="root">${html}</div></body></html>`);
  const root = document.querySelector("#root");
  for (const textarea of root.querySelectorAll("textarea")) {
    // LinkeDOM leaves character references literal in textarea text.
    const text = textarea.textContent.replaceAll("<", "&lt;");
    textarea.textContent = parseHTML(`<span>${text}</span>`).document.firstElementChild.textContent;
  }
  return root;
}

function assertProjection(root, expected, label, ignoredAttributes) {
  const actual = childrenOf(root, ignoredAttributes);
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label}:\n${JSON.stringify({expected, actual})}`);
  }
}

const cases = JSON.parse(readFileSync(process.argv[2], "utf8"));
const clientBookkeeping = new Set([
  "data-live-lift-action", "data-live-lift-change", "data-live-lift-submit",
  "data-live-lift-key", "data-live-lift-node-id",
]);
let updates = 0;
let phoenixRenders = 0;
for (const [index, item] of cases.entries()) {
  const phoenix = item.phoenixHTML !== undefined;
  const root = parseServerHTML(item.phoenixHTML ?? item.html);
  globalThis.document = root.ownerDocument;
  root.dataset.liveLiftModule = "Parity";
  root.dataset.liveLiftState = JSON.stringify(item.state);
  if (phoenix) root.dataset.liveLiftMode = "component";
  const expected = childrenOf(phoenix ? parseServerHTML(item.html) : root);
  const hook = createClientHook({Parity: {template: item.tree, actions: {}}});
  hook.el = root;
  hook.mounted();
  hook.render();
  assertProjection(root, expected, `Template parity failed at case ${index}`);
  if (phoenix) {
    const server = childrenOf(parseServerHTML(item.phoenixHTML), clientBookkeeping);
    assertProjection(root, server, `Phoenix HEEx parity failed at case ${index}`, clientBookkeeping);
    phoenixRenders += 1;
  }
  let previousState = item.state;
  for (const [step, update] of (item.updates ?? []).entries()) {
    const server = parseServerHTML(update.html);
    const expected = childrenOf(server);
    hook.render(update.state, previousState);
    const location = `case ${index}, update ${step}`;
    assertProjection(root, expected, `Template parity failed at ${location}`);
    if (update.phoenixHTML !== undefined) {
      const server = childrenOf(parseServerHTML(update.phoenixHTML), clientBookkeeping);
      assertProjection(root, server, `Phoenix HEEx parity failed at ${location}`, clientBookkeeping);
      phoenixRenders += 1;
    }
    previousState = update.state;
    updates += 1;
  }
  hook.destroyed();
}
console.log(`${cases.length} template cases matched`);
if (updates) console.log(`${updates} template updates matched`);
if (phoenixRenders) console.log(`${phoenixRenders} Phoenix HEEx renders matched`);
