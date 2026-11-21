const __liveLiftDraftRoots = new WeakSet();
const __liveLiftDraftMarker = "data-live-lift-draft";
const __liveLiftDraftLength = 4096;
const __liveLiftDraftLifetime = 30 * 60 * 1000;

function __liveLiftPrepareDrafts(root) {
  if (__liveLiftDraftRoots.has(root)) return;
  __liveLiftDraftRoots.add(root);
  const window = root.ownerDocument.defaultView;
  let storage;
  try {
    storage = window.sessionStorage;
  } catch {
    return;
  }

  const fields = new Map();
  const patched = new WeakSet();

  function keyFor(field) {
    if (field.tagName !== "TEXTAREA" && (field.tagName !== "INPUT" || field.type !== "text")) return;
    const scope = field.getAttribute(__liveLiftDraftMarker);
    const form = field.form;
    if (!scope || !/^[a-zA-Z0-9_-]{1,128}$/.test(scope) ||
        !form?.id || form.id.length > 128 || !root.contains(form) || !form.contains(field) ||
        !form.getAttribute("phx-submit") ||
        (form.hasAttribute("phx-change") && form.getAttribute("phx-auto-recover") !== "ignore") ||
        !field.name || field.name.length > 128 || form.elements.namedItem(field.name) !== field) return;
    return "live-lift:draft:" + JSON.stringify([
      window.location.pathname, root.dataset.liveLiftModule, root.id, form.id, scope, field.name,
    ]);
  }

  function discard(key) {
    try {
      storage.removeItem(key);
    } catch {
      // Storage is opportunistic. The current form remains usable.
    }
  }

  function read(key) {
    let raw;
    try {
      raw = storage.getItem(key);
    } catch {
      return;
    }
    if (raw === null) return;
    try {
      if (raw.length <= __liveLiftDraftLength * 6 + 64) {
        const record = JSON.parse(raw);
        const now = Date.now();
        if (Array.isArray(record) && record.length === 3 && record[0] === 1 &&
            Number.isSafeInteger(record[1]) && record[1] > now &&
            record[1] <= now + __liveLiftDraftLifetime &&
            typeof record[2] === "string" && record[2].length <= __liveLiftDraftLength) {
          return {expires: record[1], text: record[2]};
        }
      }
    } catch {
      // A malformed record is discarded below.
    }
    discard(key);
  }

  function sync(field) {
    const key = keyFor(field);
    const previous = fields.get(field);
    if (previous?.key === key) return previous;
    if (previous?.record && field.value === previous.record.text) field.value = field.defaultValue;
    fields.delete(field);
    if (!key) return;

    const entry = {key, record: read(key)};
    fields.set(field, entry);
    if (entry.record) field.value = entry.record.text;
    if (!patched.has(field)) {
      patched.add(field);
      const priorPatch = field.__liveLiftPatch;
      field.__liveLiftPatch = (next) => {
        priorPatch?.(next);
        const active = fields.get(field);
        if (!active?.record || active.key !== keyFor(field) ||
            field.getAttribute(__liveLiftDraftMarker) !== next.getAttribute(__liveLiftDraftMarker) ||
            field.name !== next.name || field.type !== next.type) return;
        if (active.record.expires > Date.now()) {
          next.value = active.record.text;
        } else {
          active.record = undefined;
          discard(active.key);
        }
      };
    }
    return entry;
  }

  function scan() {
    for (const field of fields.keys()) if (!root.contains(field)) fields.delete(field);
    for (const field of root.querySelectorAll("input, textarea")) {
      if (!field.hasAttribute(__liveLiftDraftMarker) && !fields.has(field)) continue;
      const entry = sync(field);
      if (entry?.record && entry.record.expires > Date.now() && field.value !== entry.record.text) {
        field.value = entry.record.text;
      }
    }
  }

  root.addEventListener("input", ({target: field}) => {
    if (!field.hasAttribute?.(__liveLiftDraftMarker) || field.matches(":disabled") || field.readOnly) return;
    // Capture the edit before sync can hydrate a newly rendered or re-scoped element.
    const text = field.value;
    const entry = sync(field);
    if (!entry) return;
    if (field.value !== text) field.value = text;
    if (text.length > __liveLiftDraftLength) {
      entry.record = undefined;
      discard(entry.key);
      return;
    }
    const expires = Date.now() + __liveLiftDraftLifetime;
    entry.record = {expires, text};
    try {
      storage.setItem(entry.key, JSON.stringify([1, expires, text]));
    } catch {
      // A failed replacement leaves the preceding persisted record available.
    }
  }, true);

  root.addEventListener("reset", (event) => {
    window.setTimeout(() => {
      if (event.defaultPrevented) return;
      for (const [field, entry] of fields) {
        if (field.form !== event.target || entry.key !== keyFor(field)) continue;
        entry.record = undefined;
        discard(entry.key);
      }
    }, 0);
  });

  new window.MutationObserver(scan).observe(root, {
    subtree: true, childList: true, attributes: true,
    attributeFilter: [__liveLiftDraftMarker, "id", "name", "type", "form", "phx-submit", "phx-change", "phx-auto-recover", "value"],
  });
  scan();
}
