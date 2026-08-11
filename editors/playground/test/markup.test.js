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
  assert.match(theme, /"\.cm-gutters": \{[\s\S]*?backgroundColor: "var\(--pg-background\)"[\s\S]*?borderRight: "0"/);
  assert.match(theme, /"\.cm-lineNumbers \.cm-gutterElement": \{[\s\S]*?var\(--pg-muted\) 55%/);
  assert.match(style, /\.is-embed \.editor-host \.cm-content \{ padding: \.5rem 0 \.25rem; \}/);
  assert.match(style, /\.is-embed #source-editor \{[\s\S]*?border: 1px solid var\(--pg-border\);[\s\S]*?border-radius: 2px;/);
  assert.match(style, /\.head-bar \{[\s\S]*?justify-content: flex-end;[\s\S]*?border: 0;[\s\S]*?background: transparent;/);
  assert.match(style, /\.head-actions \{[\s\S]*?margin-left: auto;/);
  assert.match(index, /id="options-button"/);
  assert.doesNotMatch(embed, /id="options-button"/);
});

test("documentation playgrounds are inline and have dismissible output", () => {
  const docApp = readFileSync(new URL("../src/doc-app.js", import.meta.url), "utf8");
  assert.match(docApp, /customElements\.define\("nupp-playground"/);
  assert.match(docApp, /class="icon-button output-close"[^>]+aria-label="Close output">×<\/button>/);
  assert.match(docApp, /root\.querySelector\("\.output-close"\)\.addEventListener\("click"/);
  assert.match(docApp, /const compiler = new CompilerClient\(\)/);
});
