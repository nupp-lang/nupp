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

test("editor gutter and controls share the editor surface", () => {
  const theme = readFileSync(new URL("../src/cm-theme.js", import.meta.url), "utf8");
  const style = readFileSync(new URL("../static/style.css", import.meta.url), "utf8");
  assert.match(theme, /"\.cm-gutters": \{[\s\S]*?backgroundColor: "var\(--pg-background\)"[\s\S]*?borderRight: "0"/);
  assert.match(style, /\.head-bar \{[\s\S]*?border-bottom: 1px solid var\(--pg-border\);[\s\S]*?background: var\(--pg-background\);/);
  assert.match(style, /\.head-actions \{[\s\S]*?margin-left: auto;/);
});
