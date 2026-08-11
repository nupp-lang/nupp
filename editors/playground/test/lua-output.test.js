import assert from "node:assert/strict";
import test from "node:test";
import { luaHighlightLines, luaHighlightSegments } from "../src/lua-output.js";

test("generated Lua is split into syntax-highlighted segments", () => {
  const segments = luaHighlightSegments([
    "local answer = 42",
    "local message = \"done\" -- result",
    "rawget(_G, message)",
    "local property = result.answer",
    "if true then return property end",
    "return answer, message",
  ].join("\n"));

  assert.ok(segments.some(({ text, classes }) => text === "local" && classes === "lua-keyword"));
  assert.ok(segments.some(({ text, classes }) => text === "42" && classes === "lua-number"));
  assert.ok(segments.some(({ text, classes }) => text === "\"done\"" && classes === "lua-string"));
  assert.ok(segments.some(({ text, classes }) => text === "-- result" && classes === "lua-comment"));
  assert.ok(segments.some(({ text, classes }) => text === "=" && classes === "lua-operator"));
  assert.ok(segments.some(({ text, classes }) => text === "rawget" && classes === "lua-builtin"));
  assert.ok(segments.some(({ text, classes }) => text === "true" && classes === "lua-boolean"));
  assert.ok(segments.some(({ text, classes }) => text === "answer" && classes === "lua-property"));
  assert.ok(segments.some(({ text, classes }) => text === "(" && classes === "lua-punctuation"));
});

test("generated Lua is split into numbered lines without losing highlighting", () => {
  const lines = luaHighlightLines("local answer = 42\n\nreturn answer\n");

  assert.equal(lines.length, 4);
  assert.deepEqual(lines[1], []);
  assert.deepEqual(lines[3], []);
  assert.ok(lines[0].some(({ text, classes }) => text === "local" && classes === "lua-keyword"));
  assert.ok(lines[2].some(({ text, classes }) => text === "return" && classes === "lua-keyword"));
});
