import assert from "node:assert/strict";
import test from "node:test";
import { StringStream } from "@codemirror/language";
import { nuppLanguage } from "../src/nupp-lang.js";

function tokenize(lines) {
  const parser = nuppLanguage.streamParser;
  const state = parser.startState();
  return lines.map((line) => {
    const stream = new StringStream(line, 4, 2);
    const tokens = [];
    while (!stream.eol()) {
      stream.start = stream.pos;
      const style = parser.token(stream, state);
      tokens.push([stream.current(), style]);
    }
    return tokens;
  });
}

test("line comments remain one comment token", () => {
  assert.deepEqual(tokenize(["-- type Foo @allow 123 + true"]), [
    [["-- type Foo @allow 123 + true", "comment"]],
  ]);
});

test("multiline comments retain comment styling", () => {
  assert.deepEqual(tokenize(["--[[ type Foo", "@allow + 123 ]] local value"]), [
    [["--[[ type Foo", "comment"]],
    [
      ["@allow + 123 ]]", "comment"],
      [" ", null],
      ["local", "keyword"],
      [" ", null],
      ["value", "variable"],
    ],
  ]);
});

test("Nupp-looking text inside multiline strings remains a string", () => {
  assert.deepEqual(tokenize(["[[type Foo", "@allow + 123 ]] local value"]), [
    [["[[type Foo", "string"]],
    [
      ["@allow + 123 ]]", "string"],
      [" ", null],
      ["local", "keyword"],
      [" ", null],
      ["value", "variable"],
    ],
  ]);
});

test("token categories match documentation highlighting", () => {
  assert.deepEqual(tokenize([
    "local function render(value: Result): boolean",
    "  if true then return value.name .. `ok` end",
    "end",
  ]), [
    [
      ["local", "keyword"], [" ", null], ["function", "keyword"], [" ", null],
      ["render", "builtin"], ["(", "punctuation"], ["value", "variable"],
      [":", "punctuation"], [" ", null], ["Result", "type"], [")", "punctuation"],
      [":", "punctuation"], [" ", null], ["boolean", "type"],
    ],
    [
      ["  ", null], ["if", "keyword"], [" ", null], ["true", "bool"], [" ", null],
      ["then", "keyword"], [" ", null], ["return", "keyword"], [" ", null],
      ["value", "variable"], [".", "punctuation"], ["name", "property"], [" ", null],
      ["..", "operator"], [" ", null], ["`ok`", "string"], [" ", null],
      ["end", "keyword"],
    ],
    [["end", "keyword"]],
  ]);
});
