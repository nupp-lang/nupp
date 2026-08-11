import { highlightCode, tagHighlighter, tags } from "@lezer/highlight";
import { nuppLanguage } from "./nupp-lang.js";

const luaHighlighter = tagHighlighter([
  { tag: tags.keyword, class: "lua-keyword" },
  { tag: tags.string, class: "lua-string" },
  { tag: tags.comment, class: "lua-comment" },
  { tag: tags.number, class: "lua-number" },
  { tag: tags.typeName, class: "lua-type" },
  { tag: tags.operator, class: "lua-operator" },
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

export function renderLuaOutput(target, source) {
  const fragment = document.createDocumentFragment();
  for (const { text, classes } of luaHighlightSegments(source)) {
    if (!classes) {
      fragment.append(document.createTextNode(text));
      continue;
    }
    const span = document.createElement("span");
    span.className = classes;
    span.textContent = text;
    fragment.append(span);
  }
  target.replaceChildren(fragment);
}
