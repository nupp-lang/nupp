import { highlightCode, tagHighlighter, tags } from "@lezer/highlight";
import { nuppLanguage } from "./nupp-lang.js";

const luaHighlighter = tagHighlighter([
  { tag: tags.keyword, class: "lua-keyword" },
  { tag: tags.bool, class: "lua-boolean" },
  { tag: tags.string, class: "lua-string" },
  { tag: tags.comment, class: "lua-comment" },
  { tag: tags.number, class: "lua-number" },
  { tag: tags.typeName, class: "lua-type" },
  { tag: tags.operator, class: "lua-operator" },
  { tag: tags.propertyName, class: "lua-property" },
  { tag: tags.punctuation, class: "lua-punctuation" },
  { tag: tags.variableName, class: "lua-variable" },
  { tag: tags.standard(tags.variableName), class: "lua-builtin" },
  { tag: tags.meta, class: "lua-meta" },
]);

export function luaHighlightSegments(source) {
  const segments = [];
  highlightCode(
    source,
    nuppLanguage.parser.parse(source),
    luaHighlighter,
    (text, classes) => segments.push({ text, classes }),
    () => segments.push({ text: "\n", classes: "" }),
  );
  return segments;
}

export function luaHighlightLines(source) {
  const lines = [[]];
  for (const { text, classes } of luaHighlightSegments(source)) {
    const parts = text.split("\n");
    for (let index = 0; index < parts.length; index++) {
      if (parts[index]) lines.at(-1).push({ text: parts[index], classes });
      if (index < parts.length - 1) lines.push([]);
    }
  }
  return lines;
}

export function renderLuaOutput(target, source) {
  const fragment = document.createDocumentFragment();
  for (const [index, segments] of luaHighlightLines(source).entries()) {
    const line = document.createElement("span");
    line.className = "lua-line";

    const number = document.createElement("span");
    number.className = "lua-line-number";
    number.setAttribute("aria-hidden", "true");
    number.textContent = String(index + 1);
    line.append(number);

    const code = document.createElement("span");
    code.className = "lua-line-code";
    for (const { text, classes } of segments) {
      if (!classes) {
        code.append(document.createTextNode(text));
        continue;
      }
      const span = document.createElement("span");
      span.className = classes;
      span.textContent = text;
      code.append(span);
    }
    line.append(code);
    fragment.append(line);
  }
  target.replaceChildren(fragment);
}
