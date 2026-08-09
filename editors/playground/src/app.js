import { EditorView, basicSetup } from "codemirror";
import { EditorState } from "@codemirror/state";
import { linter, lintGutter, setDiagnostics } from "@codemirror/lint";
import { nuppLanguage } from "./nupp-lang.js";
import EXAMPLE from "./example.nupp";

const FILENAME = "playground.nupp";

// Everything below tolerates a page that only has #source-editor: the embed
// page (embed.html) is just the editor, with none of the panel/tab/footer
// chrome index.html has, so every optional element is looked up once here
// and every use of it downstream is guarded.
const el = (id) => document.getElementById(id);
const statusEl = el("status");
const checkTimeEl = el("check-time");
const compileButton = el("compile-button");
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
    return;
  }
  const resolver = pending.get(msg.id);
  if (!resolver) return;
  pending.delete(msg.id);
  resolver(msg);
};

function request(kind, source) {
  const id = nextId++;
  return new Promise((resolve) => {
    pending.set(id, resolve);
    worker.postMessage({ id, kind, source, filename: FILENAME });
  });
}

// --- Status line ------------------------------------------------------------

function setStatus(text, isError) {
  if (!statusEl) return;
  statusEl.textContent = text;
  statusEl.classList.toggle("status-error", !!isError);
}
function setBusy(busy) {
  document.body.classList.toggle("is-busy", busy);
}

// --- Source editor -----------------------------------------------------------

const sourceView = new EditorView({
  parent: el("source-editor"),
  state: EditorState.create({
    doc: EXAMPLE,
    extensions: [
      basicSetup,
      nuppLanguage,
      // The worker drives when diagnostics get recomputed (debounced, off
      // the main thread), so the linter source itself never runs — results
      // arrive instead via the setDiagnostics dispatches in
      // applyDiagnostics(). This just installs the lint UI machinery.
      linter(() => []),
      lintGutter(),
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
        extensions: [basicSetup, EditorView.editable.of(false)],
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
  const from = Math.max(0, Math.min(docLength, d.offset));
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
      const from = Math.max(0, Math.min(docLength, d.offset));
      const to = Math.max(from, Math.min(docLength, d.offset + Math.max(1, d.length || 1)));
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
  checkTimer = setTimeout(checkNow, 400);
}

let checkGeneration = 0;
async function checkNow() {
  const generation = ++checkGeneration;
  const source = sourceView.state.doc.toString();
  const t0 = performance.now();
  const result = await request("check", source);
  if (generation !== checkGeneration) return; // a newer check superseded this one
  const elapsed = Math.round(performance.now() - t0);
  if (!result.ok) {
    setStatus("error: " + result.error, true);
    return;
  }
  applyDiagnostics(result.diagnostics);
  const errors = result.diagnostics.filter((d) => d.severity === "error").length;
  const warnings = result.diagnostics.filter((d) => d.severity === "warning").length;
  setStatus(
    errors ? `${errors} error${errors === 1 ? "" : "s"}` +
      (warnings ? `, ${warnings} warning${warnings === 1 ? "" : "s"}` : "") :
      warnings ? `${warnings} warning${warnings === 1 ? "" : "s"}` : "checked, clean",
    errors > 0
  );
  if (checkTimeEl) checkTimeEl.textContent = `${elapsed} ms`;
}

async function compileNow() {
  setBusy(true);
  const source = sourceView.state.doc.toString();
  const result = await request("compile", source);
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

setBusy(true);
setStatus("starting…");
