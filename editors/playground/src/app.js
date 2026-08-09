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
const diagListEl = el("diagnostics");
const outputHost = el("output-editor");
const tabs = document.querySelectorAll(".tab");

// --- Worker request/response plumbing -------------------------------------

const worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
let nextId = 1;
const pending = new Map();

worker.onmessage = (event) => {
  const msg = event.data;
  if (msg.type === "status") {
    setStatus(msg.message, false, "⏳");
    return;
  }
  if (msg.type === "ready") {
    setStatus("ready", false, "⏳");
    setBusy(false);
    checkNow();
    return;
  }
  if (msg.type === "boot-error") {
    setStatus("failed to start: " + msg.message, true, "❌");
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
    worker.postMessage({ id, kind, filename: FILENAME, ...extra });
  });
}

// --- Status line ------------------------------------------------------------

// index.html has room to say "2 errors, 1 warning" and a diagnostics list to
// read it against. The embed has neither: it is a corner pill beside somebody
// else's page, where the only question worth answering at a glance is whether
// the program checks. So it gets the glyph, and keeps the words as its title
// rather than dropping them.
const isEmbedStatus = statusEl !== null && statusEl.classList.contains("embed-status");

function setStatus(text, isError, glyph) {
  if (!statusEl) return;
  statusEl.textContent = isEmbedStatus && glyph ? glyph : text;
  if (isEmbedStatus) statusEl.title = text;
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

// A ```playground fence in the docs may inline its own program, which arrives
// in the fragment as `#source=<percent-encoded>` (see src/nupp/doc/html.nupp).
// A page that supplies one has chosen what it wants shown, so the example menu
// steps aside; a fence with no body gets the menu and its first entry.
function inlinedSource() {
  const match = /(?:^|&)source=([^&]*)/.exec(location.hash.replace(/^#/, ""));
  if (!match) return null;
  try {
    return decodeURIComponent(match[1]);
  } catch {
    return null; // a malformed fragment is not worth failing to start over
  }
}

const inlined = inlinedSource();

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
  if (!outputView) return;
  outputView.dispatch({
    changes: { from: 0, to: outputView.state.doc.length, insert: text },
  });
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
  // line; there's no incremental rechecking here (that's nupp.lsp's own
  // incremental query engine, a lot more machinery than this playground
  // drives — see README.md).
  checkTimer = setTimeout(checkNow, 250);
}

let checkGeneration = 0;
async function checkNow() {
  const generation = ++checkGeneration;
  const source = sourceView.state.doc.toString();
  setStatus("checking…", false, "⏳");
  const t0 = performance.now();
  const result = await request("check", { source });
  if (generation !== checkGeneration) return; // a newer check superseded this one
  const elapsed = Math.round(performance.now() - t0);
  if (!result.ok) {
    setStatus("error: " + result.error, true, "❌");
    return;
  }
  applyDiagnostics(result.diagnostics);
  const errors = result.diagnostics.filter((d) => d.severity === "error").length;
  const warnings = result.diagnostics.filter((d) => d.severity === "warning").length;
  setStatus(
    errors ? `${errors} error${errors === 1 ? "" : "s"}` +
      (warnings ? `, ${warnings} warning${warnings === 1 ? "" : "s"}` : "") :
      warnings ? `${warnings} warning${warnings === 1 ? "" : "s"}` : "checked, clean",
    errors > 0,
    errors ? "❌" : warnings ? "⚠️" : "✅"
  );
  if (checkTimeEl) checkTimeEl.textContent = `${elapsed} ms`;
}

async function compileNow() {
  setBusy(true);
  const source = sourceView.state.doc.toString();
  const result = await request("compile", { source });
  setBusy(false);
  if (!result.ok) {
    setOutput(`-- ${result.error}`);
    return;
  }
  applyDiagnostics(result.diagnostics);
  if (result.code) {
    setOutput(result.code);
    switchTab("output");
  } else {
    setOutput(`-- compile failed (${result.reason}); see diagnostics`);
    switchTab("diagnostics");
  }
}

if (compileButton) compileButton.addEventListener("click", compileNow);

// --- Tabs (index.html only) ------------------------------------------------------

const panels = { diagnostics: el("diagnostics-panel"), output: el("output-panel") };
function switchTab(name) {
  for (const tab of tabs) tab.classList.toggle("is-active", tab.dataset.tab === name);
  for (const [key, panel] of Object.entries(panels)) {
    if (panel) panel.classList.toggle("is-active", key === name);
  }
}
for (const tab of tabs) {
  tab.addEventListener("click", () => switchTab(tab.dataset.tab));
}

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
  switchTab("diagnostics");
  sourceView.focus();
}

if (exampleSelect && inlined === null) {
  for (const example of EXAMPLES) {
    const option = document.createElement("option");
    option.value = example.id;
    option.textContent = example.label;
    exampleSelect.appendChild(option);
  }
  exampleSelect.value = EXAMPLES[0].id;
  exampleSelect.addEventListener("change", () => loadExample(exampleSelect.value));
} else if (exampleSelect) {
  // An inlined program is the page's own, and a menu that would replace it is
  // offering to undo what the page came to show. The class takes the strip the
  // menu sat in with it, rather than leaving an empty bar above the editor.
  document.body.classList.add("is-bare");
}

setBusy(true);
setStatus("starting…", false, "⏳");
