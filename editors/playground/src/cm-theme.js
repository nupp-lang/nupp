// A CodeMirror theme built from this project's own palette (see style.css)
// instead of basicSetup's default light-mode HighlightStyle, which is what
// was actually on screen before this file existed: a white gutter and
// default (mostly reddish/orange) token colors sitting on top of a dark page
// — nothing here was reading the --pg-* variables, because plain CSS
// overrides of CodeMirror's internal classes lose the specificity fight
// against the stylesheet basicSetup injects. An explicit EditorView.theme
// plus a HighlightStyle of our own, added after basicSetup's, wins instead.
//
// Colors are CSS var() references, not literal hex, so both this and the
// syntax palette in style.css stay in one place and the editor keeps
// tracking light/dark automatically.
import { EditorView } from "codemirror";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";

const chrome = EditorView.theme({
  "&": {
    color: "var(--pg-text)",
    backgroundColor: "var(--pg-background)",
  },
  ".cm-content": { caretColor: "var(--pg-accent)" },
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--pg-accent)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection": {
    backgroundColor: "var(--pg-accent-soft)",
  },
  ".cm-panels": { color: "var(--pg-text)", backgroundColor: "var(--pg-background-alt)" },
  ".cm-gutters": {
    color: "var(--pg-muted)",
    backgroundColor: "var(--pg-background)",
    borderRight: "0",
  },
  ".cm-activeLineGutter": { backgroundColor: "var(--pg-background)" },
  ".cm-activeLine": { backgroundColor: "var(--pg-background-alt)" },
  ".cm-lineNumbers .cm-gutterElement": { color: "var(--pg-muted)" },
  ".cm-matchingBracket, .cm-nonmatchingBracket": {
    backgroundColor: "var(--pg-accent-soft)",
    outline: "1px solid var(--pg-accent)",
  },
  ".cm-tooltip": {
    color: "var(--pg-text)",
    backgroundColor: "var(--pg-background)",
    border: "1px solid var(--pg-border)",
  },
  ".cm-tooltip-lint": { fontFamily: "var(--pg-font)" },
});

// The Lua legacy stream-mode (see nupp-lang.js) only ever emits "keyword",
// "string", "comment", "number", "variable", "builtin", plus this project's
// own "meta", "type", and "operator" tokens — see the tag-name-to-legacy-name table this
// maps through: node_modules/@codemirror/language's default TokenTable.
const highlightStyle = HighlightStyle.define([
  { tag: tags.keyword, color: "var(--pg-syntax-keyword)" },
  { tag: tags.string, color: "var(--pg-syntax-string)" },
  { tag: tags.comment, color: "var(--pg-syntax-comment)", fontStyle: "italic" },
  { tag: tags.number, color: "var(--pg-syntax-number)" },
  { tag: tags.typeName, color: "var(--pg-syntax-type)" },
  { tag: tags.operator, color: "var(--pg-syntax-operator)" },
  { tag: tags.variableName, color: "var(--pg-syntax-variable)" },
  // Lua's legacy mode tags a small set of stdlib names ("print", "pairs", …)
  // as "builtin", which maps to this modifier-tag combination — see
  // node_modules/@codemirror/language's default TokenTable ("builtin" ->
  // "variableName.standard"). `standard` is a modifier *function*, not a
  // property: tags.variableName.standard is undefined, not a tag.
  { tag: tags.standard(tags.variableName), color: "var(--pg-syntax-function)" },
  { tag: tags.meta, color: "var(--pg-syntax-meta)" },
]);

export const nuppEditorTheme = [chrome, syntaxHighlighting(highlightStyle)];
