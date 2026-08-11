import assert from "node:assert/strict";
import test from "node:test";
import { luaHighlightSegments } from "../src/lua-output.js";

test("generated Lua is split into syntax-highlighted segments", () => {
  const segments = luaHighlightSegments([
    "local answer = 42",
    "local message = \"done\" -- result",
    "rawget(_G, message)",
    "return answer, message",
  ].join("\n"));

  assert.ok(segments.some(({ text, classes }) => text === "local" && classes === "lua-keyword"));
  assert.ok(segments.some(({ text, classes }) => text === "42" && classes === "lua-number"));
  assert.ok(segments.some(({ text, classes }) => text === "\"done\"" && classes === "lua-string"));
  assert.ok(segments.some(({ text, classes }) => text === "-- result" && classes === "lua-comment"));
  assert.ok(segments.some(({ text, classes }) => text === "=" && classes === "lua-operator"));
  assert.ok(segments.some(({ text, classes }) => text === "rawget" && classes === "lua-builtin"));
});
