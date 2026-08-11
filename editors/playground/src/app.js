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
const isEmbed = document.body.classList.contains("is-embed");

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
const diagListEl = el("diagnostics");
const outputHost = el("output-editor");
const outputEl = el("output");
const outputToggle = el("output-toggle");
const outputResizer = el("output-resizer");
const diagnosticsResizer = el("diagnostics-resizer");
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
    // One switch rather than a level, because one is all the optimizer
    // currently distinguishes: every pass it registers runs at -O1, and -O2 is
    // reserved for a stronger tier that does not exist yet. See
    // docs/tooling/optimization.md.
    hint: "Run every optimizer pass (-O1). Off is -O0, which rewrites nothing.",
  },
];

const options = { ...OPTION_DEFAULTS };

// --- Worker request/response plumbing -------------------------------------

// A documentation page can carry dozens of playground iframes. The iframe itself is
// lazy-loaded by the browser; within an embed, defer the substantially more expensive
// Fengari VM and self-hosted compiler until the reader actually engages with it. The
// full playground has only one instance and starts eagerly below.
let worker = null;
let workerReady = null;
let resolveWorkerReady = null;
let rejectWorkerReady = null;
let nextId = 1;
const pending = new Map();

function onWorkerMessage(event) {
  const msg = event.data;
  if (msg.type === "status") {
    setStatus(msg.message);
    return;
  }
  if (msg.type === "ready") {
    setStatus("ready");
    setBusy(false);
    resolveWorkerReady?.();
    resolveWorkerReady = null;
    rejectWorkerReady = null;
    return;
  }
  if (msg.type === "boot-error") {
    setStatus("failed to start: " + msg.message, true);
    // The output panel as well as the status line: the embed has no status
    // line, and a compiler that never started is otherwise a page that
    // silently does nothing. Busy is cleared with it, so this can be read and
    // Open still works — a dead compiler is not a dead page.
    setBusy(false);
    setOutput("-- the compiler failed to start\n\n" + msg.message);
    if (outputMain) outputMain.classList.remove("is-code");
    if (outputSummary) {
      outputSummary.textContent = "failed to start";
      outputSummary.classList.add("is-error");
    }
    setOutputExpanded(true);
    rejectWorkerReady?.(new Error(msg.message));
    resolveWorkerReady = null;
    rejectWorkerReady = null;
    return;
  }
  const resolver = pending.get(msg.id);
  if (!resolver) return;
  pending.delete(msg.id);
  resolver(msg);
}

function startWorker() {
  if (workerReady) return workerReady;

  setBusy(true);
  setStatus("starting…");
  workerReady = new Promise((resolve, reject) => {
    resolveWorkerReady = resolve;
    rejectWorkerReady = reject;
  });
  worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
  worker.onmessage = onWorkerMessage;
  worker.onerror = (event) => {
    const message = event.message || "the compiler worker failed to start";
    setBusy(false);
    setStatus("failed to start: " + message, true);
    rejectWorkerReady?.(new Error(message));
    resolveWorkerReady = null;
    rejectWorkerReady = null;
  };
  return workerReady;
}

async function request(kind, extra) {
  try {
    await startWorker();
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
  const id = nextId++;
  return new Promise((resolve) => {
    pending.set(id, resolve);
    worker.postMessage({ id, kind, filename: FILENAME, options: { ...options }, ...extra });
  });
}

// --- Status line ------------------------------------------------------------

// index.html only. The embed used to carry a glyph pill floating over the
// editor's corner; the output panel's own summary says the same thing with
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
// one (see src/nupp/compiler/doc/html.nupp), from the embed's Open, or from a shared
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
        //
        // Wrapped, unlike the source editor. Generated Lua keeps one line per
        // source line so positions still line up, which puts the whole runtime
        // preamble on line 1 and a comptime table on however few lines the
        // program declared it in — thousands of columns wide, and off the right
        // edge of an unwrapped pane. A reader who scrolls past the first screen
        // of that reasonably concludes the output arrived without line breaks.
        extensions: [
          basicSetup,
          nuppEditorTheme,
          nuppLanguage,
          EditorView.lineWrapping,
          EditorView.editable.of(false),
        ],
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

// --- Output panel ------------------------------------------------------------

// The panel answers one question — what did the compiler say — so its main
// pane holds whichever answer there is: the diagnostics as the CLI prints them
// when something is wrong, the generated Lua when nothing is. The list stays
// either way, because a clean compile can still carry warnings. Which side of
// the main pane that list is on is the stylesheet's business: beside it in the
// embed's drawer, under it in the full playground's column.
function setOutputExpanded(expanded) {
  if (!outputEl || !outputToggle || !outputBody) return;
  outputEl.classList.toggle("is-open", expanded);
  outputBody.hidden = !expanded;
  outputToggle.setAttribute("aria-expanded", String(expanded));
  if (outputResizer) outputResizer.hidden = !expanded;
  if (expanded && outputView) outputView.requestMeasure();
  applyPaneSizes();
}

function isOutputExpanded() {
  return outputEl !== null && outputEl.classList.contains("is-open");
}

if (outputToggle) {
  outputToggle.addEventListener("click", () => setOutputExpanded(!isOutputExpanded()));
}

// --- Resizable panes ---------------------------------------------------------

// How much of the window the answer deserves is the reader's call, not the
// stylesheet's: a two-line diagnostic and a thousand lines of generated Lua
// both land here. The stylesheet's share is only where the drag starts from.
//
// One implementation covers every separator on both pages — the embed's drawer
// under the editor, the full playground's panel beside it, and the split
// between the output and the diagnostics inside that panel. They differ only
// in which pane they size and which way the layout runs, and the direction is
// read off the box rather than written down here, so a separator keeps working
// when the narrow-window media query turns that row back into a column.

// Enough of a sized pane to see its own bar and a couple of lines, and enough
// left of the pane it takes from to still be working in rather than peering
// at. Keyed by the axis, because a column of text needs a different amount of
// room than a stack of them. Measured against the box the two panes share, so
// a small window narrows the range instead of letting either be dragged out of
// existence.
const PANE_MIN = {
  x: { pane: 200, rest: 280 },
  y: { pane: 88, rest: 120 },
};

// Up and left grow the pane a separator sizes, down and right shrink it — the
// same direction the pointer moves to do each — and only the pair along the
// axis that separator runs on answers at all.
const KEY_AXIS = { ArrowUp: "y", ArrowDown: "y", ArrowLeft: "x", ArrowRight: "x" };
const KEY_SIGN = { ArrowUp: 1, ArrowLeft: 1, ArrowDown: -1, ArrowRight: -1 };

// "x" when the pane sits beside its neighbour, "y" when it sits below it.
function paneAxis(pane) {
  const flow = getComputedStyle(pane.parentElement).flexDirection;
  return flow === "row" || flow === "row-reverse" ? "x" : "y";
}

function paneSize(node, axis) {
  const rect = node.getBoundingClientRect();
  return axis === "x" ? rect.width : rect.height;
}

// Re-applied together, since a window resize can leave any of them larger than
// what is left to give.
const paneSizers = [];
function applyPaneSizes() {
  for (const apply of paneSizers) apply();
}
addEventListener("resize", applyPaneSizes);

// A separator sizes the pane that follows it — the drawer below the editor,
// the panel right of it, the diagnostics under the output — so the pointer is
// always holding that pane's leading edge, and dragging toward the pane makes
// it smaller. `sizable` is what says the pane is currently showing anything:
// the drawer's is its own expanded state.
function installResizer(resizer, pane, sizable = () => true) {
  if (!resizer || !pane) return;

  // The size is held here rather than on the element because a collapsed
  // drawer must go back to being one bar — an inline size would keep it open
  // with nothing in it — so the element's style is cleared on collapse and put
  // back on expand.
  let size = null;

  function clamp(px, axis) {
    const min = PANE_MIN[axis];
    const available = paneSize(pane.parentElement, axis) - min.rest;
    return Math.max(min.pane, Math.min(px, Math.max(min.pane, available)));
  }

  function apply() {
    const axis = paneAxis(pane);
    // A media query can turn the layout under a pane that is already sized, so
    // what the separator tells a screen reader is settled here rather than in
    // the markup.
    resizer.setAttribute("aria-orientation", axis === "x" ? "vertical" : "horizontal");
    // A pane never dragged, or one whose panel is collapsed, is whatever the
    // stylesheet says.
    if (size === null || !sizable()) {
      pane.style.removeProperty("flex");
      return;
    }
    size = clamp(size, axis);
    // A flex basis runs along whichever axis its container does, so the one
    // declaration sets a width here and a height there.
    pane.style.flex = `0 0 ${size}px`;
  }

  function setSize(px) {
    size = clamp(px, paneAxis(pane));
    apply();
  }

  // Pointer events rather than mouse: one path covers a trackpad and a touch
  // screen, and capture means a fast drag that outruns the 6px strip keeps
  // going instead of stopping the moment the cursor leaves it.
  resizer.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    const axis = paneAxis(pane);
    const start = axis === "x" ? event.clientX : event.clientY;
    const startSize = paneSize(pane, axis);
    resizer.setPointerCapture(event.pointerId);
    resizer.classList.add("is-dragging");
    const onMove = (move) =>
      setSize(startSize - ((axis === "x" ? move.clientX : move.clientY) - start));
    const onUp = () => {
      resizer.removeEventListener("pointermove", onMove);
      resizer.classList.remove("is-dragging");
    };
    resizer.addEventListener("pointermove", onMove);
    resizer.addEventListener("pointerup", onUp, { once: true });
    resizer.addEventListener("pointercancel", onUp, { once: true });
  });

  // A separator that only answers to a drag is one a keyboard cannot reach.
  resizer.addEventListener("keydown", (event) => {
    const axis = paneAxis(pane);
    if (KEY_AXIS[event.key] !== axis) return;
    const step = (event.shiftKey ? 48 : 16) * KEY_SIGN[event.key];
    setSize(paneSize(pane, axis) + step);
    event.preventDefault();
  });

  // Back to the stylesheet's share — the way out of a drag that went somewhere
  // unhelpful, without having to drag it back by eye.
  resizer.addEventListener("dblclick", () => {
    size = null;
    apply();
  });

  paneSizers.push(apply);
  apply();
}

if (outputResizer && outputEl) outputResizer.hidden = !isOutputExpanded();
installResizer(outputResizer, outputEl, isOutputExpanded);
// index.html only: the panel's own split, between the answer and the list of
// what is wrong with it. It lives inside the body the collapse hides, so it
// needs no expanded check of its own.
installResizer(diagnosticsResizer, diagListEl);

// Keep the useful position, severity, and code without presenting the
// playground's internal parser filename as if the reader had chosen it.
// Commented, because the pane it lands in is the one that otherwise holds
// generated Lua, and index.html highlights that pane as Lua.
function diagnosticText(d) {
  const parts = [`-- ${d.line}:${d.col}: ${d.severity || "error"}: `];
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
  // line; there's no incremental rechecking here (that's nupp.compiler.lsp's own
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
  // Editing invalidates whatever the last Run produced, so the panel goes
  // back to saying what the checker says rather than showing Lua from a buffer
  // that has since changed.
  setOutput(result.diagnostics.length ? result.diagnostics.map(diagnosticText).join("\n") : "");
  if (outputMain) outputMain.classList.remove("is-code");
  if (checkTimeEl) checkTimeEl.textContent = `${elapsed} ms`;
}

let compilePending = false;
async function compileNow() {
  if (compilePending) return;
  compilePending = true;
  if (compileButton) compileButton.disabled = true;
  if (outputEl) outputEl.hidden = false;
  setOutputExpanded(true);
  setOutput("");
  setOutputSummary([], "compiling…");
  setBusy(true);
  const source = sourceView.state.doc.toString();
  let result;
  try {
    result = await request("compile", { source });
  } finally {
    setBusy(false);
    compilePending = false;
    if (compileButton) compileButton.disabled = false;
  }
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

// An embed with a program supplied by its page has exactly one buffer, so it
// needs neither the example menu nor a synthetic filename. The full playground
// always has the menu because a reader who opened a shared link is still free
// to browse; an empty embed uses it as its initial content picker.
const wantsExampleMenu = !isEmbed || inlined === null;

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

let activated = false;

function activateCompiler() {
  if (activated) return;
  activated = true;
  startWorker().then(checkNow).catch(() => {
    // startWorker already put the useful failure in the status/output UI.
  });
}

if (isEmbed) {
  setBusy(false);
  setStatus("checking starts when you edit");
  // Capture sees the first gesture before CodeMirror consumes it. Keyboard covers a
  // reader who tabs into the editor; focusin covers assistive technology and scripts.
  addEventListener("pointerdown", activateCompiler, { once: true, capture: true });
  addEventListener("keydown", activateCompiler, { once: true, capture: true });
  addEventListener("focusin", activateCompiler, { once: true, capture: true });
} else {
  activateCompiler();
}
