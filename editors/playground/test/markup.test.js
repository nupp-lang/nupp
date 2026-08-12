import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

test("playground chrome has no synthetic filename", () => {
  const index = readFileSync(new URL("../static/index.html", import.meta.url), "utf8");
  const embed = readFileSync(new URL("../static/embed.html", import.meta.url), "utf8");
  assert.doesNotMatch(index, />playground\.nupp</);
  assert.doesNotMatch(embed, />playground\.nupp</);
});

test("output starts hidden behind the Run control", () => {
  const index = readFileSync(new URL("../static/index.html", import.meta.url), "utf8");
  const embed = readFileSync(new URL("../static/embed.html", import.meta.url), "utf8");
  assert.match(index, /id="compile-button" class="button">Run<\/button>/);
  assert.match(index, /<section class="output" id="output" aria-label="Output" hidden>/);
  assert.match(embed, /id="compile-button"[^>]+title="Run" aria-label="Run"/);
  assert.match(embed, /<section class="output" id="output" aria-label="Output" hidden>/);
});

test("condensed controls sit above the rounded editor border", () => {
  const index = readFileSync(new URL("../static/index.html", import.meta.url), "utf8");
  const embed = readFileSync(new URL("../static/embed.html", import.meta.url), "utf8");
  const theme = readFileSync(new URL("../src/cm-theme.js", import.meta.url), "utf8");
  const style = readFileSync(new URL("../static/style.css", import.meta.url), "utf8");
  assert.match(theme, /"\.cm-gutters": \{[\s\S]*?backgroundColor: "var\(--pg-code-background, var\(--pg-background\)\)"[\s\S]*?borderRight: "0"/);
  assert.match(theme, /"\.cm-lineNumbers \.cm-gutterElement": \{[\s\S]*?paddingLeft: "\.65rem"[\s\S]*?paddingRight: "1px"[\s\S]*?var\(--pg-faint/);
  assert.match(theme, /"\.cm-foldGutter span": \{ padding: "0" \}/);
  assert.match(theme, /"\.cm-gutter-lint": \{ width: "1em" \}/);
  assert.match(theme, /"\.cm-gutter-lint \.cm-gutterElement": \{ padding: "0" \}/);
  assert.match(style, /\.is-embed \.editor-host \.cm-content \{ padding: \.5rem 0; \}/);
  assert.match(style, /\.is-embed #source-editor \{[\s\S]*?border: 1px solid var\(--pg-border\);[\s\S]*?border-radius: var\(--pg-code-block-radius\);/);
  assert.match(style, /\.head-bar \{[\s\S]*?justify-content: flex-end;[\s\S]*?border: 0;[\s\S]*?background: transparent;/);
  assert.match(style, /\.head-actions \{[\s\S]*?margin-left: auto;/);
  assert.match(index, /id="options-button"/);
  assert.doesNotMatch(embed, /id="options-button"/);
});

test("playgrounds hide line numbers for sources shorter than five lines", () => {
  const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
  const docApp = readFileSync(new URL("../src/doc-app.js", import.meta.url), "utf8");
  const theme = readFileSync(new URL("../src/cm-theme.js", import.meta.url), "utf8");
  assert.match(theme, /view\.state\.doc\.lines < 5/);
  assert.match(theme, /"&\.cm-hide-line-numbers \.cm-lineNumbers": \{ display: "none !important" \}/);
  assert.match(app, /updateLineNumberVisibility\(sourceView\)/);
  assert.match(app, /updateLineNumberVisibility\(update\.view\)/);
  assert.match(docApp, /updateLineNumberVisibility\(this\.view\)/);
  assert.match(docApp, /updateLineNumberVisibility\(update\.view\)/);
});

test("documentation playgrounds are inline and have dismissible output", () => {
  const docApp = readFileSync(new URL("../src/doc-app.js", import.meta.url), "utf8");
  assert.match(docApp, /customElements\.define\("nupp-playground"/);
  assert.match(docApp, /:host \{[\s\S]*?position: relative;[\s\S]*?margin: 1\.75rem 0 \.75rem;/);
  assert.match(docApp, /\.toolbar \{[\s\S]*?position: absolute;[\s\S]*?top: -1\.75rem;/);
  assert.match(docApp, /:host\(\[data-grouped\]\) \.toolbar \{[\s\S]*?position: static;/);
  assert.match(docApp, /:host\(\[data-grouped\]\) \.editor \{[\s\S]*?border: 0;[\s\S]*?border-radius: 0;/);
  assert.match(docApp, /\.editor \{[\s\S]*?border: 1px solid var\(--pg-border\);[\s\S]*?border-radius: var\(--pg-code-block-radius\);/);
  assert.match(docApp, /\.editor \.cm-content \{ padding: \.75rem 0 !important; \}/);
  assert.match(docApp, /<div class="editor"><\/div>\s*<div class="tooltip-layer"><\/div>/);
  assert.match(docApp, /\.tooltip-layer \{[\s\S]*?position: absolute;[\s\S]*?z-index: 3;[\s\S]*?pointer-events: none;/);
  assert.match(docApp, /tooltips\(\{ parent: tooltipLayer \}\)/);
  assert.match(docApp, /class="icon-button output-close"[^>]+aria-label="Close output">×<\/button>/);
  assert.match(docApp, /root\.querySelector\("\.output-close"\)\.addEventListener\("click"/);
  assert.match(docApp, /const compiler = new CompilerClient\(\)/);
});

test("documentation playgrounds expose source to Reader Mode", () => {
  const docApp = readFileSync(new URL("../src/doc-app.js", import.meta.url), "utf8");
  assert.match(docApp, /this\.querySelector\("\[data-reader-source\]"\)/);
  assert.match(docApp, /readerSource\.slot = "reader-source"/);
  assert.match(docApp, /class="reader-source" aria-hidden="true"><slot name="reader-source"><\/slot>/);
  assert.match(docApp, /\.reader-source \{[\s\S]*?position: absolute;[\s\S]*?opacity: 0;[\s\S]*?pointer-events: none;/);
  assert.match(docApp, /this\.readerSource\.textContent = source/);
  assert.match(docApp, /this\.readerSource\.textContent = update\.state\.doc\.toString\(\)/);
  assert.match(docApp, /root\.querySelector\("\.cm-gutters"\)\?\.setAttribute\("aria-hidden", "true"\)/);
});

test("documentation playgrounds inherit normal code-block colors", () => {
  const docApp = readFileSync(new URL("../src/doc-app.js", import.meta.url), "utf8");
  assert.match(docApp, /--pg-background: var\(--nuppdoc-code-background/);
  assert.match(docApp, /--pg-border: var\(--nuppdoc-border/);
  assert.doesNotMatch(docApp, /--nuppdoc-playground-border/);
  for (const token of ["keyword", "boolean", "string", "comment", "number", "function", "meta", "type", "operator", "property", "punctuation", "variable"]) {
    assert.match(docApp, new RegExp(`--pg-syntax-${token}: var\\(--nuppdoc-syntax-${token}`));
  }
});

test("generated Lua output has a muted line-number gutter", () => {
  const docApp = readFileSync(new URL("../src/doc-app.js", import.meta.url), "utf8");
  const app = readFileSync(new URL("../src/app.js", import.meta.url), "utf8");
  const style = readFileSync(new URL("../static/style.css", import.meta.url), "utf8");
  assert.match(docApp, /\.output-main \.lua-line-number \{[\s\S]*?color: var\(--pg-faint\);[\s\S]*?user-select: none;/);
  assert.match(style, /\.output-main \.lua-line-number \{[\s\S]*?color: var\(--pg-faint\);[\s\S]*?user-select: none;/);
  assert.match(docApp, /\.output-main\.is-code \{[\s\S]*?white-space: pre;/);
  assert.match(style, /\.output-main\.is-code \{[\s\S]*?white-space: pre;/);
  assert.doesNotMatch(app, /EditorView\.lineWrapping/);
});

test("editor tooltips use compact text and balanced padding", () => {
  const theme = readFileSync(new URL("../src/cm-theme.js", import.meta.url), "utf8");
  assert.match(theme, /"\.cm-tooltip": \{[\s\S]*?fontSize: "\.72rem"[\s\S]*?lineHeight: "1\.35"/);
  assert.match(theme, /"\.cm-diagnostic": \{ padding: "\.2rem \.75rem" \}/);
  assert.match(theme, /"\.cm-nupp-hover pre": \{[\s\S]*?padding: "\.2rem \.75rem"/);
});

test("documentation playgrounds check only after the reader engages", () => {
  const docApp = readFileSync(new URL("../src/doc-app.js", import.meta.url), "utf8");
  assert.doesNotMatch(docApp, /IntersectionObserver/);
  assert.match(docApp, /const IGNORED_DOC_DIAGNOSTICS = new Set\(\["NUPP2507"\]\)/);
  assert.match(docApp, /const diagnostics = visibleDiagnostics\(result\.diagnostics\)/);
});

test("playground codegen drops effects removed by optimization", () => {
  const worker = readFileSync(new URL("../src/worker.js", import.meta.url), "utf8");
  assert.match(worker, /pcall\(optimize\.run, result,/);
  assert.match(worker, /result\.effects = optimize\.liveEffects\(result\)/);
  assert.ok(
    worker.indexOf("optimize.liveEffects(result)") < worker.indexOf("gen.generate, result"),
    "live effects must be recomputed before generation",
  );
});

test("the playground build rejects bootstrap syntax Fengari cannot parse", () => {
  const build = readFileSync(new URL("../build.mjs", import.meta.url), "utf8");
  assert.match(build, /function verifyFengariSyntax\(filename\)/);
  assert.match(build, /lauxlib\.luaL_loadstring\(state, to_luastring\(source\)\)/);
  assert.match(build, /verifyFengariSyntax\(path\.join\(dist, "nupp-bootstrap\.lua"\)\)/);
});
