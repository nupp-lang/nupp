import { EditorView, basicSetup } from "codemirror";
import { hoverTooltip } from "@codemirror/view";
import { EditorState } from "@codemirror/state";
import { linter, lintGutter, setDiagnostics } from "@codemirror/lint";
import { nuppLanguage } from "./nupp-lang.js";
import { nuppEditorTheme } from "./cm-theme.js";
import { EXAMPLES } from "./examples.js";
import { renderLuaOutput } from "./lua-output.js";

const FILENAME = "playground.nupp";
const OPTIONS = { strict: true, optimize: true };
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

const styles = `
:host {
  --pg-accent: var(--nuppdoc-accent, #607331);
  --pg-accent-hover: var(--nuppdoc-accent-hover, #4d5c27);
  --pg-accent-soft: var(--nuppdoc-accent-soft, #e6e9d8);
  --pg-background: var(--nuppdoc-code-background, #ded7b9);
  --pg-code-background: var(--nuppdoc-code-background, #ded7b9);
  --pg-background-alt: var(--nuppdoc-background-alt, #f2eed8);
  --pg-border: var(--nuppdoc-border, #d4cda8);
  --pg-code-block-radius: var(--nuppdoc-code-block-radius, 8px);
  --pg-text: var(--nuppdoc-text, #173333);
  --pg-muted: var(--nuppdoc-text-muted, #626956);
  --pg-faint: var(--nuppdoc-text-faint, color-mix(in srgb, var(--pg-muted) 72%, transparent));
  --pg-error: #cf222e;
  --pg-warning: #8c5f22;
  --pg-info: var(--nuppdoc-accent, #1b5670);
  --pg-syntax-keyword: var(--nuppdoc-syntax-keyword, #765128);
  --pg-syntax-boolean: var(--nuppdoc-syntax-boolean, #8c5f22);
  --pg-syntax-string: var(--nuppdoc-syntax-string, #607331);
  --pg-syntax-comment: var(--nuppdoc-syntax-comment, #7b806a);
  --pg-syntax-number: var(--nuppdoc-syntax-number, #8c5f22);
  --pg-syntax-function: var(--nuppdoc-syntax-function, #1b5670);
  --pg-syntax-meta: var(--nuppdoc-syntax-meta, #315f58);
  --pg-syntax-type: var(--nuppdoc-syntax-type, #315f58);
  --pg-syntax-operator: var(--nuppdoc-syntax-operator, #315f58);
  --pg-syntax-property: var(--nuppdoc-syntax-property, #506942);
  --pg-syntax-punctuation: var(--nuppdoc-syntax-punctuation, #66725d);
  --pg-syntax-variable: var(--nuppdoc-syntax-variable, #173333);
  --pg-font: var(--nuppdoc-font, Inter, ui-sans-serif, system-ui, sans-serif);
  --pg-font-mono: var(--nuppdoc-font-mono, ui-monospace, monospace);
  position: relative;
  display: block;
  overflow: visible;
  margin: 1.75rem 0 .75rem;
  color: var(--pg-text);
  font-family: var(--pg-font);
}
* { box-sizing: border-box; }
.toolbar {
  position: absolute;
  z-index: 2;
  top: -1.75rem;
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
  padding: 0 0 .2rem;
}
:host([data-grouped]) .editor {
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
  margin-right: auto;
  color: var(--pg-muted);
  font-size: .72rem;
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
.output-main.is-code {
  padding-inline: 0;
  white-space: pre;
}
.output-main .lua-line {
  display: grid;
  grid-template-columns: max-content minmax(0, 1fr);
}
.output-main .lua-line-number {
  min-width: 2.75rem;
  padding: 0 .65rem;
  color: var(--pg-faint);
  text-align: right;
  user-select: none;
}
.output-main .lua-line-code {
  min-width: 0;
  padding-right: .75rem;
}
.output-main .lua-keyword { color: var(--pg-syntax-keyword); }
.output-main .lua-boolean { color: var(--pg-syntax-boolean); }
.output-main .lua-string { color: var(--pg-syntax-string); }
.output-main .lua-comment { color: var(--pg-syntax-comment); font-style: italic; }
.output-main .lua-number { color: var(--pg-syntax-number); }
.output-main .lua-type { color: var(--pg-syntax-type); }
.output-main .lua-operator { color: var(--pg-syntax-operator); }
.output-main .lua-property { color: var(--pg-syntax-property); }
.output-main .lua-punctuation { color: var(--pg-syntax-punctuation); }
.output-main .lua-variable { color: var(--pg-syntax-variable); }
.output-main .lua-builtin { color: var(--pg-syntax-function); }
.output-main .lua-meta { color: var(--pg-syntax-meta); }
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
    const encoded = this.getAttribute("data-source");
    let source = encoded === null ? EXAMPLES[0].source : "";
    if (encoded !== null) {
      try { source = decodeURIComponent(encoded); } catch { source = encoded; }
    }

    const root = this.attachShadow({ mode: "open" });
    root.innerHTML = `
      <style>${styles}</style>
      <div class="toolbar">
        ${encoded === null ? '<label class="example-picker">Example <select></select></label>' : ""}
        <div class="actions">
          <button class="icon-button run" type="button" title="Run" aria-label="Run">
            ${icon("M4.5 3.2v9.6l8-4.8z", "play")}
          </button>
          <a class="icon-button open" title="Open in the full playground" aria-label="Open in the full playground"
             href="/playground/" target="_blank" rel="noopener">
            <svg viewBox="0 0 16 16" aria-hidden="true"><path d="M9 2.6h4.4V7M13 3l-6 6"/><path d="M11.6 9.6v3.2a.9.9 0 0 1-.9.9H3.3a.9.9 0 0 1-.9-.9V5.3a.9.9 0 0 1 .9-.9h3.2"/></svg>
          </a>
        </div>
      </div>
      <div class="editor"></div>
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
      parent: root.querySelector(".editor"),
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
          EditorView.updateListener.of((update) => {
            if (update.docChanged) this.scheduleCheck();
          }),
        ],
      }),
    });

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

    this.runButton.addEventListener("click", () => this.compile());
    this.openButton.addEventListener("click", () => {
      this.openButton.href = "/playground/#source=" + encodeURIComponent(this.view.state.doc.toString());
    });
    root.querySelector(".output-close").addEventListener("click", () => {
      this.output.hidden = true;
      this.runButton.focus();
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

  async compile() {
    this.runButton.disabled = true;
    this.output.hidden = false;
    this.outputSummary.textContent = "compiling…";
    this.outputMain.classList.remove("is-code");
    this.outputMain.textContent = "";
    try {
      const result = await compiler.compile(this.view.state.doc.toString());
      if (!result.ok) throw new Error(result.error);
      this.applyDiagnostics(result.diagnostics);
      const diagnostics = visibleDiagnostics(result.diagnostics);
      const errors = diagnostics.filter((diagnostic) => diagnostic.severity === "error").length;
      const warnings = diagnostics.filter((diagnostic) => diagnostic.severity === "warning").length;
      this.outputSummary.textContent = [
        errors && `${errors} error${errors === 1 ? "" : "s"}`,
        warnings && `${warnings} warning${warnings === 1 ? "" : "s"}`,
      ].filter(Boolean).join(", ") || (result.code ? "compiled" : result.reason || "clean");
      if (result.code) {
        this.outputMain.classList.add("is-code");
        renderLuaOutput(this.outputMain, result.code);
      } else {
        this.outputMain.textContent = diagnostics.map(diagnosticText).join("\n\n");
      }
    } catch (error) {
      this.outputSummary.textContent = "failed";
      this.outputMain.classList.remove("is-code");
      this.outputMain.textContent = `-- ${error instanceof Error ? error.message : String(error)}`;
    } finally {
      this.runButton.disabled = false;
    }
  }
}

customElements.define("nupp-playground", NuppDocPlayground);
