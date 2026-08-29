import { EditorView, basicSetup } from "codemirror";
import { hoverTooltip, tooltips } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { linter, lintGutter, setDiagnostics } from "@codemirror/lint";
import { nuppLanguage } from "./nupp-lang.js";
import { nuppEditorTheme, updateLineNumberVisibility } from "./cm-theme.js";
import { EXAMPLES } from "./examples.js";
import { renderLuaOutput } from "./lua-output.js";

const FILENAME = "playground.nupp";
const OPTIONS = { strict: true, optimize: true, dialect: "lua51" };
// Documentation frequently introduces a declaration before showing its use.
// Keep that teaching shape without turning every first step into yellow chrome.
const IGNORED_DOC_DIAGNOSTICS = new Set(["NUPP2507"]);
const toCmPos = (offset) => offset - 1;
const toNuppOffset = (position) => position + 1;

function visibleDiagnostics(diagnostics) {
  return diagnostics.filter((diagnostic) => !IGNORED_DOC_DIAGNOSTICS.has(diagnostic.code));
}

// One compiler serves every editor on a documentation page. Worker calls are
// serialized because hover reads the parse produced by the most recent check;
// keeping check+hover in one queued operation prevents another editor from
// replacing that parse between the two calls.
class CompilerClient {
  constructor() {
    this.worker = null;
    this.ready = null;
    this.nextId = 1;
    this.pending = new Map();
    this.queue = Promise.resolve();
    this.lastSource = null;
  }

  start() {
    if (this.ready) return this.ready;
    this.ready = new Promise((resolve, reject) => {
      this.resolveReady = resolve;
      this.rejectReady = reject;
    });
    this.worker = new Worker(new URL("./worker.js", import.meta.url), { type: "module" });
    this.worker.addEventListener("message", (event) => {
      const message = event.data;
      if (message.type === "ready") {
        this.resolveReady?.();
        this.resolveReady = null;
        this.rejectReady = null;
        return;
      }
      if (message.type === "boot-error") {
        this.rejectReady?.(new Error(message.message));
        this.resolveReady = null;
        this.rejectReady = null;
        return;
      }
      if (message.type === "status") return;
      const resolve = this.pending.get(message.id);
      if (!resolve) return;
      this.pending.delete(message.id);
      resolve(message);
    });
    this.worker.addEventListener("error", (event) => {
      this.rejectReady?.(new Error(event.message || "the compiler worker failed to start"));
      this.resolveReady = null;
      this.rejectReady = null;
    });
    return this.ready;
  }

  async raw(kind, payload) {
    await this.start();
    const id = this.nextId++;
    return new Promise((resolve) => {
      this.pending.set(id, resolve);
      this.worker.postMessage({ id, kind, filename: FILENAME, options: OPTIONS, ...payload });
    });
  }

  run(operation) {
    const result = this.queue.then(operation, operation);
    this.queue = result.catch(() => {});
    return result;
  }

  check(source) {
    return this.run(async () => {
      const result = await this.raw("check", { source });
      if (result.ok) this.lastSource = source;
      return result;
    });
  }

  compile(source) {
    return this.run(() => this.raw("compile", { source }));
  }

  hover(source, offset) {
    return this.run(async () => {
      if (this.lastSource !== source) {
        const checked = await this.raw("check", { source });
        if (!checked.ok) return checked;
        this.lastSource = source;
      }
      return this.raw("hover", { offset });
    });
  }
}

const compiler = new CompilerClient();

// Runs compiled Lua 5.1 in an isolated Worker to produce the computed result
// the Run button shows. Mirrors app.js's runGenerated: a fresh Worker per run,
// terminated on completion or on the same 10 second hard deadline.
function runGenerated(code) {
  return new Promise((resolve, reject) => {
    const application = new Worker(new URL("./app-worker.js", import.meta.url), { type: "module" });
    let settled = false;
    const timeout = setTimeout(() => {
      application.terminate();
      reject(new Error("the program exceeded the playground's 10 second hard deadline"));
    }, 10000);
    const finish = (body) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      application.terminate();
      body();
    };
    application.addEventListener("message", (event) => finish(() => {
      if (event.data?.ok) resolve(event.data.result);
      else reject(new Error(event.data?.error || "the application Worker failed"));
    }), { once: true });
    application.addEventListener("error", (event) => finish(() => {
      reject(event.error || new Error(event.message || "the application Worker failed"));
    }), { once: true });
    application.postMessage({ type: "run", code });
  });
}

const styles = `
:host {
  --pg-accent: var(--nuppdoc-accent, #768d93);
  --pg-accent-hover: var(--nuppdoc-accent-hover, color-mix(in srgb, #768d93 80%, black));
  --pg-accent-soft: var(--nuppdoc-accent-soft, #f1e1df);
  --pg-background: var(--nuppdoc-code-background, #e6eaec);
  --pg-code-background: var(--nuppdoc-code-background, #e6eaec);
  --pg-background-alt: var(--nuppdoc-background-alt, #f0ebe7);
  --pg-border: var(--nuppdoc-border, color-mix(in srgb, #50676c 70%, white));
  --pg-code-block-radius: var(--nuppdoc-code-block-radius, 4px);
  --pg-text: var(--nuppdoc-text, #2e2f2a);
  --pg-muted: var(--nuppdoc-text-muted, #594a4f);
  --pg-faint: var(--nuppdoc-text-faint, color-mix(in srgb, var(--pg-muted) 72%, transparent));
  --pg-error: #cf222e;
  --pg-warning: #836620;
  --pg-info: var(--nuppdoc-accent, #768d93);
  --pg-syntax-keyword: var(--nuppdoc-syntax-keyword, #9a1600);
  --pg-syntax-boolean: var(--nuppdoc-syntax-boolean, #836620);
  --pg-syntax-string: var(--nuppdoc-syntax-string, #364c31);
  --pg-syntax-comment: var(--nuppdoc-syntax-comment, #474c44);
  --pg-syntax-number: var(--nuppdoc-syntax-number, #836620);
  --pg-syntax-function: var(--nuppdoc-syntax-function, #376076);
  --pg-syntax-meta: var(--nuppdoc-syntax-meta, #2e595c);
  --pg-syntax-type: var(--nuppdoc-syntax-type, #2e595c);
  --pg-syntax-operator: var(--nuppdoc-syntax-operator, #2e595c);
  --pg-syntax-property: var(--nuppdoc-syntax-property, #425f3c);
  --pg-syntax-punctuation: var(--nuppdoc-syntax-punctuation, #3c5156);
  --pg-syntax-variable: var(--nuppdoc-syntax-variable, #6e5032);
  --pg-font: var(--nuppdoc-font, Inter, ui-sans-serif, system-ui, sans-serif);
  --pg-font-mono: var(--nuppdoc-font-mono, ui-monospace, monospace);
  position: relative;
  display: block;
  overflow: visible;
  margin: 2rem 0 1rem;
  color: var(--pg-text);
  font-family: var(--pg-font);
}
* { box-sizing: border-box; }
.toolbar {
  position: absolute;
  z-index: 2;
  top: -2rem;
  right: 0;
  left: 0;
  display: flex;
  height: 1.625rem;
  align-items: center;
  justify-content: flex-end;
  gap: .5rem;
  padding: 0;
}
:host([data-grouped]) { margin: 0; }
:host([data-grouped]) .toolbar {
  position: static;
  height: 2rem;
  padding: 0 0 .4rem;
}
:host([data-grouped]) .editor {
  border: 0;
  border-top: 1px solid var(--pg-border);
  border-radius: 0;
}
:host([data-grouped]) .lua-panel {
  margin-top: 0;
  border: 0;
  border-top: 1px solid var(--pg-border);
  border-radius: 0;
}
:host([data-grouped]) .output {
  margin-top: 0;
  border: 0;
  border-top: 1px solid var(--pg-border);
  border-radius: 0;
}
.example-picker {
  display: flex;
  align-items: center;
  gap: .4rem;
  color: var(--pg-muted);
}
select {
  max-width: 15rem;
  padding: .14rem 1.35rem .14rem .35rem;
  color: var(--pg-text);
  border: 1px solid var(--pg-border);
  border-radius: 2px;
  background: var(--pg-background);
  font: inherit;
}
@media (max-width: 600px) {
  select { max-width: 7.5rem; }
}
.tabs {
  display: flex;
  align-items: center;
  height: 100%;
  margin-right: auto;
}
.tab {
  height: 100%;
  padding: 0 .55rem;
  color: var(--pg-muted);
  border: 0;
  border-bottom: 2px solid transparent;
  background: transparent;
  cursor: pointer;
  font: inherit;
  font-size: .72rem;
}
.tab:hover { color: var(--pg-text); }
.tab[aria-selected="true"] {
  color: var(--pg-text);
  border-bottom-color: var(--pg-accent);
  font-weight: 600;
}
.actions { display: flex; align-items: center; gap: .1rem; margin-left: auto; }
.icon-button {
  display: grid;
  width: 26px;
  height: 26px;
  padding: 0;
  place-items: center;
  color: var(--pg-muted);
  border: 0;
  border-radius: 4px;
  background: transparent;
  cursor: pointer;
  text-decoration: none;
}
.icon-button:hover { color: var(--pg-text); background: var(--pg-background-alt); }
.icon-button:disabled { opacity: .5; cursor: wait; }
.icon-button svg { width: 16px; height: 16px; fill: none; stroke: currentColor; stroke-width: 1.45; }
.icon-button .play { fill: currentColor; stroke: none; }
.editor {
  position: relative;
  overflow: hidden;
  margin-top: .25rem;
  border: 1px solid var(--pg-border);
  border-radius: var(--pg-code-block-radius);
  background: var(--pg-background);
}
.editor .cm-scroller {
  max-height: 28rem;
  overflow: auto;
  font-family: var(--pg-font-mono);
  font-size: 13px;
}
.editor .cm-content { padding: .75rem 0 !important; }
.tooltip-layer {
  position: absolute;
  z-index: 3;
  inset: 0;
  pointer-events: none;
}
.tooltip-layer .cm-tooltip { pointer-events: auto; }
.reader-source {
  position: absolute;
  inset: 0;
  overflow: hidden;
  opacity: 0;
  pointer-events: none;
  user-select: none;
}
.output {
  margin-top: .35rem;
  border: 1px solid var(--pg-border);
  border-radius: var(--pg-code-block-radius);
  background: var(--pg-background);
}
.output[hidden] { display: none; }
.output-head {
  display: flex;
  min-height: 1.9rem;
  align-items: center;
  gap: .5rem;
  padding: .2rem .3rem .2rem .65rem;
  color: var(--pg-muted);
  border-bottom: 1px solid var(--pg-border);
  font-size: .72rem;
}
.output-summary { margin-left: auto; }
.output-close { font-size: 1rem; line-height: 1; }
.output-main {
  overflow: auto;
  max-height: 18rem;
  margin: 0;
  padding: .65rem .75rem;
  color: var(--pg-text);
  background: transparent;
  font-family: var(--pg-font-mono);
  font-size: 12.5px;
  line-height: 1.45;
  white-space: pre-wrap;
}
.lua-panel {
  overflow: auto;
  max-height: 28rem;
  margin-top: .25rem;
  padding: .75rem 0;
  border: 1px solid var(--pg-border);
  border-radius: var(--pg-code-block-radius);
  background: var(--pg-background);
  color: var(--pg-text);
  font-family: var(--pg-font-mono);
  font-size: 13px;
  line-height: 1.45;
  white-space: pre;
}
.lua-panel[hidden] { display: none; }
.lua-panel .lua-line {
  display: grid;
  grid-template-columns: max-content minmax(0, 1fr);
}
.lua-panel .lua-line-number {
  min-width: 2.75rem;
  padding: 0 .65rem;
  color: var(--pg-faint);
  text-align: right;
  user-select: none;
}
.lua-panel .lua-line-code {
  min-width: 0;
  padding-right: .75rem;
}
.lua-panel .lua-keyword { color: var(--pg-syntax-keyword); }
.lua-panel .lua-boolean { color: var(--pg-syntax-boolean); }
.lua-panel .lua-string { color: var(--pg-syntax-string); }
.lua-panel .lua-comment { color: var(--pg-syntax-comment); font-style: italic; }
.lua-panel .lua-number { color: var(--pg-syntax-number); }
.lua-panel .lua-type { color: var(--pg-syntax-type); }
.lua-panel .lua-operator { color: var(--pg-syntax-operator); }
.lua-panel .lua-property { color: var(--pg-syntax-property); }
.lua-panel .lua-punctuation { color: var(--pg-syntax-punctuation); }
.lua-panel .lua-variable { color: var(--pg-syntax-variable); }
.lua-panel .lua-builtin { color: var(--pg-syntax-function); }
.lua-panel .lua-meta { color: var(--pg-syntax-meta); }
`;

function icon(path, className = "") {
  return `<svg viewBox="0 0 16 16" aria-hidden="true"><path class="${className}" d="${path}"/></svg>`;
}

function severityToLint(severity) {
  if (severity === "warning") return "warning";
  if (severity === "info") return "info";
  return "error";
}

function diagnosticText(diagnostic) {
  const code = diagnostic.code ? `${diagnostic.code}: ` : "";
  const help = diagnostic.help ? `\n  help: ${diagnostic.help}` : "";
  return `${diagnostic.line}:${diagnostic.col}: ${diagnostic.severity || "error"}: ${code}${diagnostic.msg || ""}${help}`;
}

class NuppDocPlayground extends HTMLElement {
  connectedCallback() {
    if (this.view) return;
    if (this.closest(".nuppdoc-code-group")) this.setAttribute("data-grouped", "");
    const isHomepage = this.closest(".nuppdoc-home-content") !== null;
    const encoded = this.getAttribute("data-source");
    let source = encoded === null ? EXAMPLES[0].source : "";
    if (encoded !== null) {
      try { source = decodeURIComponent(encoded); } catch { source = encoded; }
    }

    // Reader Mode and no-script clients cannot use CodeMirror's shadow tree.
    // Keep the current program in ordinary light DOM: it is the visible static
    // fallback before upgrade and sits in a transparent slot beside the editor.
    let readerSource = this.querySelector("[data-reader-source]");
    if (!readerSource) {
      readerSource = document.createElement("div");
      readerSource.className = "nuppdoc-code-block";
      readerSource.dataset.lang = "nupp";
      readerSource.setAttribute("data-reader-source", "");
      readerSource.slot = "reader-source";
      readerSource.innerHTML = '<pre><code class="language-nupp"></code></pre>';
      this.appendChild(readerSource);
    }
    this.readerSource = readerSource.querySelector("code");
    this.readerSource.textContent = source;

    const root = this.attachShadow({ mode: "open" });
    root.innerHTML = `
      <style>${styles}</style>
      <div class="reader-source" aria-hidden="true"><slot name="reader-source"></slot></div>
      <div class="toolbar">
        ${encoded === null ? '<label class="example-picker"><select aria-label="Choose an example"></select></label>' : ""}
        <div class="tabs" role="tablist" aria-label="View">
          <button class="tab" type="button" role="tab" data-tab="nupp" aria-selected="true">Nupp</button>
          <button class="tab" type="button" role="tab" data-tab="lua" aria-selected="false">Lua</button>
        </div>
        <div class="actions">
          ${isHomepage ? "" : `<button class="icon-button run" type="button" title="Run" aria-label="Run">
            ${icon("M4.5 3.2v9.6l8-4.8z", "play")}
          </button>`}
          <a class="icon-button open" title="Open in the full playground" aria-label="Open in the full playground"
             href="/playground/" target="_blank" rel="noopener">
            <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M9 2.6h4.4V7M13 3l-6 6"/><path d="M11.6 9.6v3.2a.9.9 0 0 1-.9.9H3.3a.9.9 0 0 1-.9-.9V5.3a.9.9 0 0 1 .9-.9h3.2"/></svg>
          </a>
        </div>
      </div>
      <div class="editor"></div>
      <pre class="lua-panel" tabindex="0" hidden></pre>
      <div class="tooltip-layer"></div>
      <section class="output" aria-label="Output" hidden>
        <div class="output-head"><span>Output</span><span class="output-summary"></span>
          <button class="icon-button output-close" type="button" title="Close output" aria-label="Close output">×</button>
        </div>
        <pre class="output-main" tabindex="0"></pre>
      </section>`;

    this.runButton = root.querySelector(".run");
    this.openButton = root.querySelector(".open");
    this.output = root.querySelector(".output");
    this.outputMain = root.querySelector(".output-main");
    this.outputSummary = root.querySelector(".output-summary");
    this.tabButtons = { nupp: root.querySelector('[data-tab="nupp"]'), lua: root.querySelector('[data-tab="lua"]') };
    this.editorEl = root.querySelector(".editor");
    this.luaPanel = root.querySelector(".lua-panel");
    this.activeTab = "nupp";
    this.compiledSource = null;
    this.compiledCode = null;
    const tooltipLayer = root.querySelector(".tooltip-layer");

    const hover = hoverTooltip(async (view, position) => {
      const result = await compiler.hover(view.state.doc.toString(), toNuppOffset(position));
      if (!result.ok || !result.found) return null;
      const length = view.state.doc.length;
      const from = Math.max(0, Math.min(length, toCmPos(result.offset)));
      const to = Math.max(from, Math.min(length, from + result.length));
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

    this.view = new EditorView({
      parent: this.editorEl,
      root,
      state: EditorState.create({
        doc: source,
        extensions: [
          basicSetup,
          nuppEditorTheme,
          nuppLanguage,
          linter(() => []),
          lintGutter(),
          hover,
          tooltips({ parent: tooltipLayer }),
          EditorView.updateListener.of((update) => {
            if (update.docChanged) {
              updateLineNumberVisibility(update.view);
              this.readerSource.textContent = update.state.doc.toString();
              this.scheduleCheck();
              // The Lua tab and any cached compile belong to the program that
              // just changed; drop both and land back on the source that
              // produced them rather than leave stale Lua on screen.
              this.invalidateCompiled();
            }
          }),
        ],
      }),
    });
    updateLineNumberVisibility(this.view);
    root.querySelector(".cm-gutters")?.setAttribute("aria-hidden", "true");

    const select = root.querySelector("select");
    if (select) {
      for (const example of EXAMPLES) {
        const option = document.createElement("option");
        option.value = example.id;
        option.textContent = example.label;
        select.appendChild(option);
      }
      select.addEventListener("change", () => {
        const example = EXAMPLES.find((candidate) => candidate.id === select.value);
        if (!example) return;
        this.view.dispatch({ changes: { from: 0, to: this.view.state.doc.length, insert: example.source } });
      });
    }

    this.tabButtons.nupp.addEventListener("click", () => this.activateTab("nupp"));
    this.tabButtons.lua.addEventListener("click", () => this.showLua());
    this.runButton?.addEventListener("click", () => this.run());
    this.openButton.addEventListener("click", () => {
      this.openButton.href = "/playground/#source=" + encodeURIComponent(this.view.state.doc.toString());
    });
    root.querySelector(".output-close").addEventListener("click", () => {
      this.output.hidden = true;
      this.runButton?.focus();
    });
  }

  disconnectedCallback() {
    clearTimeout(this.checkTimer);
    this.view?.destroy();
    this.view = null;
  }

  scheduleCheck() {
    clearTimeout(this.checkTimer);
    this.checkTimer = setTimeout(() => this.check(), 250);
  }

  applyDiagnostics(diagnostics) {
    const length = this.view.state.doc.length;
    const markers = visibleDiagnostics(diagnostics)
      .filter((diagnostic) => typeof diagnostic.offset === "number")
      .map((diagnostic) => {
        const from = Math.max(0, Math.min(length, toCmPos(diagnostic.offset)));
        const to = Math.max(from, Math.min(length, from + Math.max(1, diagnostic.length || 1)));
        return {
          from,
          to,
          severity: severityToLint(diagnostic.severity),
          message: diagnostic.help ? `${diagnostic.msg}\n${diagnostic.help}` : diagnostic.msg,
          source: diagnostic.code,
        };
      });
    this.view.dispatch(setDiagnostics(this.view.state, markers));
  }

  async check() {
    const generation = (this.checkGeneration || 0) + 1;
    this.checkGeneration = generation;
    const source = this.view.state.doc.toString();
    try {
      const result = await compiler.check(source);
      if (generation !== this.checkGeneration || !result.ok) return;
      this.applyDiagnostics(result.diagnostics);
    } catch {
      // Run exposes startup failures in an output area the reader can close;
      // passive checking should not turn every snippet into an error panel.
    }
  }

  // Switches which panel is visible without touching what either panel holds
  // — showLua() and invalidateCompiled() own that.
  activateTab(name) {
    if (this.activeTab === name) return;
    this.activeTab = name;
    const showLua = name === "lua";
    this.editorEl.hidden = showLua;
    this.luaPanel.hidden = !showLua;
    this.tabButtons.nupp.setAttribute("aria-selected", String(!showLua));
    this.tabButtons.lua.setAttribute("aria-selected", String(showLua));
    // The editor was measured while hidden (or never shown yet); CodeMirror
    // needs a fresh measurement once it is visible again to lay out correctly.
    if (!showLua) this.view.requestMeasure();
  }

  // The Lua tab and any cached compile belong to whatever source produced
  // them. Called whenever that source changes, so a stale compile is never
  // shown, and reused instead of recompiled otherwise.
  invalidateCompiled() {
    this.compiledSource = null;
    this.compiledCode = null;
    this.luaPanel.textContent = "";
    this.activateTab("nupp");
  }

  async showLua() {
    this.activateTab("lua");
    const source = this.view.state.doc.toString();
    if (this.compiledSource === source) return;
    const generation = (this.luaGeneration || 0) + 1;
    this.luaGeneration = generation;
    this.luaPanel.textContent = "compiling…";
    try {
      const result = await compiler.compile(source);
      if (generation !== this.luaGeneration) return;
      if (!result.ok) throw new Error(result.error);
      this.applyDiagnostics(result.diagnostics);
      if (result.code) {
        this.compiledSource = source;
        this.compiledCode = result.code;
        renderLuaOutput(this.luaPanel, result.code);
      } else {
        const diagnostics = visibleDiagnostics(result.diagnostics);
        this.luaPanel.textContent = diagnostics.length
          ? diagnostics.map(diagnosticText).join("\n\n")
          : (result.reason || "no output");
      }
    } catch (error) {
      if (generation !== this.luaGeneration) return;
      this.luaPanel.textContent = `-- ${error instanceof Error ? error.message : String(error)}`;
    }
  }

  // Compiles the current source if needed (or reuses what showLua() already
  // compiled) and actually executes it, showing the computed result — the one
  // thing the Lua tab's static text cannot do.
  async run() {
    this.runButton.disabled = true;
    this.output.hidden = false;
    this.outputSummary.textContent = "compiling…";
    this.outputMain.textContent = "";
    const source = this.view.state.doc.toString();
    try {
      let code = this.compiledSource === source ? this.compiledCode : null;
      if (code === null) {
        const result = await compiler.compile(source);
        if (!result.ok) throw new Error(result.error);
        this.applyDiagnostics(result.diagnostics);
        if (!result.code) {
          const diagnostics = visibleDiagnostics(result.diagnostics);
          this.outputSummary.textContent = result.reason || "failed";
          this.outputMain.textContent = diagnostics.map(diagnosticText).join("\n\n");
          return;
        }
        code = result.code;
        this.compiledSource = source;
        this.compiledCode = code;
      }
      this.outputSummary.textContent = "running…";
      const execution = await runGenerated(code);
      this.outputSummary.textContent = "ran";
      this.outputMain.textContent = execution?.stdout || "";
    } catch (error) {
      this.outputSummary.textContent = "failed";
      this.outputMain.textContent = `-- ${error instanceof Error ? error.message : String(error)}`;
    } finally {
      this.runButton.disabled = false;
    }
  }
}

customElements.define("nupp-playground", NuppDocPlayground);
