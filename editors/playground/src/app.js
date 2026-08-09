import { EditorView, basicSetup } from "codemirror";
import { hoverTooltip } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { linter, lintGutter, setDiagnostics } from "@codemirror/lint";
import { nuppLanguage } from "./nupp-lang.js";
import { nuppEditorTheme } from "./cm-theme.js";
import { EXAMPLES } from "./examples.js";

// Nupp positions are 1-based byte offsets (AGENTS.md: "Source positions are
// 1-based byte line and column numbers"); CodeMirror positions are 0-based
// character offsets. Byte vs. character only diverges on non-ASCII source,
// which the checker itself doesn't special-case either — good enough here.
const toCmPos = (nuppOffset) => nuppOffset - 1;
const toNuppOffset = (cmPos) => cmPos + 1;

const FILENAME = "playground.nupp";

// Everything below tolerates a page that only has #source-editor: the embed
// page (embed.html) is just the editor, with none of the panel/tab/footer
// chrome index.html has, so every optional element is looked up once here
// and every use of it downstream is guarded.
const el = (id) => document.getElementById(id);
const statusEl = el("status");
const checkTimeEl = el("check-time");
const compileButton = el("compile-button");
const exampleSelect = el("example-select");
const examplePicker = el("example-picker");
const filenameEl = el("filename");
const diagListEl = el("diagnostics");
const outputHost = el("output-editor");
const outputEl = el("output");
const outputToggle = el("output-toggle");
const outputBody = el("output-body");
const outputMain = el("output-main");
const outputSummary = el("output-summary");
const optionsButton = el("options-button");
const optionsPanel = el("options-panel");
const openButton = el("open-button");
const shareButton = el("share-button");

// --- Compiler options ---------------------------------------------------------

// What the Options menu sets and the worker acts on. Strict is on here where
// the command line leaves it off: every example checks clean under it, and a
// playground is where seeing the stricter answer first is the point — the
// switch is right there for anyone who wants the gradual one. Kept as one
// object because it travels as one: into every worker request, into a shared
// link, out of a fragment.
const OPTION_DEFAULTS = { strict: true, optimize: true };

const OPTION_FIELDS = [
  {
    key: "strict",
    label: "Strict",
    hint: "Report an exported signature that leaves any as its type.",
  },
  {
    key: "optimize",
    label: "Optimize",
    hint: "Run the -O1 passes before generating Lua.",
  },
];

const options = { ...OPTION_DEFAULTS };

// --- Worker request/response plumbing -------------------------------------

const worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
let nextId = 1;
const pending = new Map();

worker.onmessage = (event) => {
  const msg = event.data;
  if (msg.type === "status") {
    setStatus(msg.message);
    return;
  }
  if (msg.type === "ready") {
    setStatus("ready");
    setBusy(false);
    checkNow();
    return;
  }
  if (msg.type === "boot-error") {
    setStatus("failed to start: " + msg.message, true);
    // The drawer as well as the status line: the embed has no status line, and
    // a compiler that never started is otherwise a page that silently does
    // nothing. Busy is cleared with it, so the drawer can be opened to read
    // this and Open still works — a dead compiler is not a dead page.
    setBusy(false);
    setOutput("-- the compiler failed to start\n\n" + msg.message);
    if (outputMain) outputMain.classList.remove("is-code");
    if (outputSummary) {
      outputSummary.textContent = "failed to start";
      outputSummary.classList.add("is-error");
    }
    setOutputExpanded(true);
    return;
  }
  const resolver = pending.get(msg.id);
  if (!resolver) return;
  pending.delete(msg.id);
  resolver(msg);
};

function request(kind, extra) {
  const id = nextId++;
  return new Promise((resolve) => {
    pending.set(id, resolve);
    worker.postMessage({ id, kind, filename: FILENAME, options: { ...options }, ...extra });
  });
}

// --- Status line ------------------------------------------------------------

// index.html only. The embed used to carry a glyph pill floating over the
// editor's corner; the output drawer's own summary says the same thing with
// room for the count, in a bar that is already there.
function setStatus(text, isError) {
  if (!statusEl) return;
  statusEl.textContent = text;
  statusEl.classList.toggle("status-error", !!isError);
}
function setBusy(busy) {
  document.body.classList.toggle("is-busy", busy);
}

// --- Hover -------------------------------------------------------------------

// Reuses whatever the last successful check found (see worker.js's
// lastResult) instead of reparsing and rechecking the whole buffer on every
// mouse movement — hovering needs to feel instant, and re-running the
// checker doesn't.
const nuppHover = hoverTooltip(async (view, pos) => {
  const result = await request("hover", { offset: toNuppOffset(pos) });
  if (!result.ok || !result.found) return null;
  const docLength = view.state.doc.length;
  const from = Math.max(0, Math.min(docLength, toCmPos(result.offset)));
  const to = Math.max(from, Math.min(docLength, from + result.length));
  return {
    pos: from,
    end: to,
    above: true,
    create() {
      const dom = document.createElement("div");
      dom.className = "cm-nupp-hover";
      const pre = document.createElement("pre");
      pre.textContent = result.signature;
      dom.appendChild(pre);
      return { dom };
    },
  };
});

// --- Source editor -----------------------------------------------------------

// A program can arrive in the fragment: from a ```playground fence that inlined
// one (see src/compiler/doc/html.nupp), from the embed's Open, or from a shared
// link. The fragment rather than a query means no server ever sees it.
function fragmentParams() {
  const out = {};
  for (const pair of location.hash.replace(/^#/, "").split("&")) {
    if (!pair) continue;
    const at = pair.indexOf("=");
    const key = at < 0 ? pair : pair.slice(0, at);
    try {
      out[key] = decodeURIComponent(at < 0 ? "" : pair.slice(at + 1));
    } catch {
      // One malformed pair is not worth failing to start over; the rest stand.
    }
  }
  return out;
}

const params = fragmentParams();
const inlined = typeof params.source === "string" ? params.source : null;
for (const field of OPTION_FIELDS) {
  if (params[field.key] !== undefined) options[field.key] = params[field.key] === "1";
}

// Everything needed to reopen this buffer elsewhere. `location.hash = ...` is
// not used to publish it — the page never rewrites its own address, so a reader
// who came from a docs page can still reload back to what that page showed.
function fragmentFor(source) {
  const parts = ["source=" + encodeURIComponent(source)];
  for (const field of OPTION_FIELDS) {
    if (options[field.key] !== OPTION_DEFAULTS[field.key]) {
      parts.push(`${field.key}=${options[field.key] ? "1" : "0"}`);
    }
  }
  return "#" + parts.join("&");
}

const sourceView = new EditorView({
  parent: el("source-editor"),
  state: EditorState.create({
    doc: inlined ?? EXAMPLES[0].source,
    extensions: [
      basicSetup,
      nuppEditorTheme,
      nuppLanguage,
      // The worker drives when diagnostics get recomputed (debounced, off
      // the main thread), so the linter source itself never runs — results
      // arrive instead via the setDiagnostics dispatches in
      // applyDiagnostics(). This just installs the lint UI machinery.
      linter(() => []),
      lintGutter(),
      nuppHover,
      EditorView.updateListener.of((update) => {
        if (update.docChanged) scheduleCheck();
      }),
    ],
  }),
});

// --- Generated-code panel (index.html only) -----------------------------------

const outputView = outputHost
  ? new EditorView({
      parent: outputHost,
      state: EditorState.create({
        doc: "",
        // Generated output is plain LuaJIT, a subset of what nuppLanguage
        // highlights — reusing it here means one language definition covers
        // both panels rather than a second one for a subset of the first.
        extensions: [basicSetup, nuppEditorTheme, nuppLanguage, EditorView.editable.of(false)],
      }),
    })
  : null;

function setOutput(text) {
  if (outputMain) outputMain.textContent = text;
  if (!outputView) return;
  outputView.dispatch({
    changes: { from: 0, to: outputView.state.doc.length, insert: text },
  });
}

// --- Output drawer (embed.html only) -------------------------------------------

// The drawer answers one question — what did the compiler say — so the main
// pane holds whichever answer there is: the diagnostics as the CLI prints them
// when something is wrong, the generated Lua when nothing is. The list beside
// it stays either way, because a clean compile can still carry warnings.
function setOutputExpanded(expanded) {
  if (!outputEl || !outputToggle || !outputBody) return;
  outputEl.classList.toggle("is-open", expanded);
  outputBody.hidden = !expanded;
  outputToggle.setAttribute("aria-expanded", String(expanded));
}

function isOutputExpanded() {
  return outputEl !== null && outputEl.classList.contains("is-open");
}

if (outputToggle) {
  outputToggle.addEventListener("click", () => setOutputExpanded(!isOutputExpanded()));
}

// `file:line:col: severity: CODE: message`, which is what nupp check writes to
// a terminal — the same string a reader would paste into a search or an issue.
// Commented, because the pane it lands in is the one that otherwise holds
// generated Lua, and index.html highlights that pane as Lua.
function diagnosticText(d) {
  const parts = [`-- ${FILENAME}:${d.line}:${d.col}: ${d.severity || "error"}: `];
  if (d.code) parts.push(`${d.code}: `);
  parts.push(d.msg || "");
  if (d.help) parts.push(`\n--   help: ${d.help}`);
  return parts.join("");
}

function summarize(diags) {
  const errors = diags.filter((d) => d.severity === "error").length;
  const warnings = diags.filter((d) => d.severity === "warning").length;
  const parts = [];
  if (errors) parts.push(`${errors} error${errors === 1 ? "" : "s"}`);
  if (warnings) parts.push(`${warnings} warning${warnings === 1 ? "" : "s"}`);
  return { errors, warnings, text: parts.join(", ") };
}

function setOutputSummary(diags, extra) {
  if (!outputSummary) return;
  const { errors, text } = summarize(diags);
  outputSummary.textContent = text || extra || "clean";
  outputSummary.classList.toggle("is-error", errors > 0);
}

// --- Diagnostics list (index.html only) -----------------------------------------

function renderDiagnostics(diags) {
  if (!diagListEl) return;
  diagListEl.innerHTML = "";
  if (diags.length === 0) {
    const li = document.createElement("li");
    li.className = "diagnostic-empty";
    li.textContent = "No diagnostics.";
    diagListEl.appendChild(li);
    return;
  }
  for (const d of diags) {
    const li = document.createElement("li");
    li.className = "diagnostic diagnostic-" + (d.severity || "error");
    const loc = document.createElement("span");
    loc.className = "diagnostic-loc";
    loc.textContent = `${d.line}:${d.col}`;
    const code = document.createElement("span");
    code.className = "diagnostic-code";
    code.textContent = d.code || "";
    const msg = document.createElement("span");
    msg.className = "diagnostic-msg";
    msg.textContent = d.msg || "";
    li.append(loc, code, msg);
    if (d.help) {
      const help = document.createElement("div");
      help.className = "diagnostic-help";
      help.textContent = d.help;
      li.appendChild(help);
    }
    li.addEventListener("click", () => jumpTo(d));
    diagListEl.appendChild(li);
  }
}

function jumpTo(d) {
  if (typeof d.offset !== "number") return;
  const docLength = sourceView.state.doc.length;
  const from = Math.max(0, Math.min(docLength, toCmPos(d.offset)));
  const to = Math.max(from, Math.min(docLength, from + (d.length || 0)));
  sourceView.dispatch({
    selection: { anchor: from, head: to },
    effects: EditorView.scrollIntoView(from, { y: "center" }),
  });
  sourceView.focus();
}

function severityToLint(severity) {
  if (severity === "error") return "error";
  if (severity === "warning") return "warning";
  return "info";
}

function applyDiagnostics(diags) {
  renderDiagnostics(diags);
  const docLength = sourceView.state.doc.length;
  const markers = diags
    .filter((d) => typeof d.offset === "number")
    .map((d) => {
      const from = Math.max(0, Math.min(docLength, toCmPos(d.offset)));
      const to = Math.max(from, Math.min(docLength, from + Math.max(1, d.length || 1)));
      return {
        from,
        to,
        severity: severityToLint(d.severity),
        message: d.help ? `${d.msg}\n${d.help}` : d.msg,
        source: d.code,
      };
    });
  sourceView.dispatch(setDiagnostics(sourceView.state, markers));
}

// --- Check / compile actions ---------------------------------------------------

let checkTimer = null;
function scheduleCheck() {
  clearTimeout(checkTimer);
  // Short enough to feel responsive, long enough that a fast typist doesn't
  // queue up a check per keystroke — each one re-parses and re-checks the
  // whole buffer (see worker.js), the same as `nupp check` on the command
  // line; there's no incremental rechecking here (that's compiler.lsp's own
  // incremental query engine, a lot more machinery than this playground
  // drives — see README.md).
  checkTimer = setTimeout(checkNow, 250);
}

let checkGeneration = 0;
async function checkNow() {
  const generation = ++checkGeneration;
  const source = sourceView.state.doc.toString();
  setStatus("checking…");
  const t0 = performance.now();
  const result = await request("check", { source });
  if (generation !== checkGeneration) return; // a newer check superseded this one
  const elapsed = Math.round(performance.now() - t0);
  if (!result.ok) {
    setStatus("error: " + result.error, true);
    return;
  }
  applyDiagnostics(result.diagnostics);
  const { errors, text } = summarize(result.diagnostics);
  setStatus(text || "checked, clean", errors > 0);
  setOutputSummary(result.diagnostics);
  // Editing invalidates whatever the last Compile produced, so the drawer goes
  // back to saying what the checker says rather than showing Lua from a buffer
  // that has since changed.
  setOutput(result.diagnostics.length ? result.diagnostics.map(diagnosticText).join("\n") : "");
  if (outputMain) outputMain.classList.remove("is-code");
  if (checkTimeEl) checkTimeEl.textContent = `${elapsed} ms`;
}

async function compileNow() {
  setBusy(true);
  const source = sourceView.state.doc.toString();
  const result = await request("compile", { source });
  setBusy(false);
  setOutputExpanded(true);
  if (!result.ok) {
    setOutput(`-- ${result.error}`);
    if (outputMain) outputMain.classList.remove("is-code");
    if (outputSummary) {
      outputSummary.textContent = "failed";
      outputSummary.classList.add("is-error");
    }
    return;
  }
  applyDiagnostics(result.diagnostics);
  const diags = result.diagnostics;
  if (result.code) {
    setOutput(result.code);
    if (outputMain) outputMain.classList.add("is-code");
    setOutputSummary(diags, "compiled");
  } else {
    // The reason is the compiler's own ("syntax errors", "type errors", "code
    // generation errors"); the diagnostics under it are what it means.
    setOutput([`-- ${result.reason}`, "", ...diags.map(diagnosticText)].join("\n"));
    if (outputMain) outputMain.classList.remove("is-code");
    setOutputSummary(diags, result.reason);
  }
}

if (compileButton) compileButton.addEventListener("click", compileNow);

// --- Example picker (index.html only) ---------------------------------------

function loadExample(id) {
  const example = EXAMPLES.find((e) => e.id === id);
  if (!example) return;
  sourceView.dispatch({
    changes: { from: 0, to: sourceView.state.doc.length, insert: example.source },
    selection: { anchor: 0 },
  });
  // The generated Lua on screen belongs to the program that just got
  // replaced, so drop it rather than leave it reading as this example's
  // output. The edit above already schedules the re-check, through the
  // updateListener the source editor is built with.
  setOutput("");
  sourceView.focus();
}

// The menu is what the head bar's leading edge holds when there is more than
// one program to reach. A page that inlined its own has exactly one, so the
// bar names it instead — the menu there would only offer to replace what the
// page came to show. index.html always has the menu, because a reader who
// opened a shared link is still free to go browse.
const wantsExampleMenu = inlined === null || filenameEl === null;

if (exampleSelect && wantsExampleMenu) {
  for (const example of EXAMPLES) {
    const option = document.createElement("option");
    option.value = example.id;
    option.textContent = example.label;
    exampleSelect.appendChild(option);
  }
  exampleSelect.value = EXAMPLES[0].id;
  exampleSelect.addEventListener("change", () => loadExample(exampleSelect.value));
} else {
  if (examplePicker) examplePicker.hidden = true;
  if (filenameEl) {
    filenameEl.hidden = false;
    filenameEl.textContent = FILENAME;
  }
}

// --- Options menu -----------------------------------------------------------

function renderOptionsPanel() {
  if (!optionsPanel) return;
  optionsPanel.replaceChildren();
  for (const field of OPTION_FIELDS) {
    const row = document.createElement("label");
    row.className = "options-row";
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = options[field.key];
    box.addEventListener("change", () => {
      options[field.key] = box.checked;
      // Strict changes what the checker reports, so the buffer on screen is
      // answering the old question until it runs again. Optimize only shows up
      // in generated Lua, which the next Compile produces anyway.
      if (field.key === "strict") checkNow();
    });
    const text = document.createElement("span");
    text.className = "options-text";
    const name = document.createElement("span");
    name.className = "options-name";
    name.textContent = field.label;
    const hint = document.createElement("span");
    hint.className = "options-hint";
    hint.textContent = field.hint;
    text.append(name, hint);
    row.append(box, text);
    optionsPanel.appendChild(row);
  }
}

function setOptionsOpen(open) {
  if (!optionsPanel || !optionsButton) return;
  optionsPanel.hidden = !open;
  optionsButton.setAttribute("aria-expanded", String(open));
  optionsButton.classList.toggle("is-active", open);
}

if (optionsButton && optionsPanel) {
  renderOptionsPanel();
  optionsButton.addEventListener("click", (event) => {
    event.stopPropagation();
    setOptionsOpen(optionsPanel.hidden);
  });
  // A menu that only closes by its own button is a menu a reader has to
  // remember to put away.
  document.addEventListener("click", (event) => {
    if (optionsPanel.hidden) return;
    // The button is excluded here as well as by the stopPropagation above,
    // because a synthetic click can reach this listener anyway and would
    // close the menu the same gesture just opened.
    if (optionsPanel.contains(event.target) || optionsButton.contains(event.target)) return;
    setOptionsOpen(false);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setOptionsOpen(false);
  });
}

// --- Open, and Share ---------------------------------------------------------

// The embed's Open hands the buffer to the full playground rather than opening
// a blank one, so the program a reader has been editing is the one that arrives
// there. Rebuilt on each click because the buffer changes under it.
if (openButton) {
  openButton.addEventListener("click", () => {
    openButton.href = "/playground/" + fragmentFor(sourceView.state.doc.toString());
  });
}

if (shareButton) {
  shareButton.addEventListener("click", async () => {
    const url = location.origin + location.pathname +
      fragmentFor(sourceView.state.doc.toString());
    try {
      await navigator.clipboard.writeText(url);
      setStatus("link copied");
    } catch {
      // Clipboard access is refused on an insecure origin and in some
      // embeddings. Putting the link in the address bar is the fallback every
      // browser has: the reader can copy it from there.
      location.hash = fragmentFor(sourceView.state.doc.toString());
      setStatus("link is in the address bar");
    }
  });
}

setBusy(true);
setStatus("starting…");
