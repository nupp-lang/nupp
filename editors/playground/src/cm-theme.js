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
    backgroundColor: "var(--pg-code-background, var(--pg-background))",
  },
  ".cm-content": { caretColor: "var(--pg-accent)" },
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--pg-accent)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection": {
    backgroundColor: "var(--pg-accent-soft)",
  },
  ".cm-panels": { color: "var(--pg-text)", backgroundColor: "var(--pg-background-alt)" },
  ".cm-gutters": {
    color: "var(--pg-muted)",
    backgroundColor: "var(--pg-code-background, var(--pg-background))",
    borderRight: "0",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "var(--pg-code-background, var(--pg-background))",
  },
  ".cm-activeLine": { backgroundColor: "var(--pg-background-alt)" },
  ".cm-lineNumbers .cm-gutterElement": {
    paddingLeft: ".65rem",
    paddingRight: "1px",
    color: "var(--pg-faint, color-mix(in srgb, var(--pg-muted) 72%, transparent))",
  },
  ".cm-matchingBracket, .cm-nonmatchingBracket": {
    backgroundColor: "var(--pg-accent-soft)",
    outline: "1px solid var(--pg-accent)",
  },
  ".cm-tooltip": {
    color: "var(--pg-text)",
    backgroundColor: "var(--pg-background)",
    border: "1px solid var(--pg-border)",
    fontSize: ".72rem",
    lineHeight: "1.35",
  },
  ".cm-tooltip-lint": { fontFamily: "var(--pg-font)" },
  ".cm-diagnostic": { padding: ".2rem .75rem" },
  ".cm-nupp-hover pre": {
    margin: "0",
    padding: ".2rem .75rem",
    fontFamily: "var(--pg-font-mono)",
    fontSize: ".72rem",
    lineHeight: "1.35",
    whiteSpace: "pre-wrap",
  },
});

// Keep these categories and colors aligned with the documentation highlighter
// in src/nupp/compiler/doc/highlight.nupp.
const highlightStyle = HighlightStyle.define([
  { tag: tags.keyword, color: "var(--pg-syntax-keyword)" },
  { tag: tags.bool, color: "var(--pg-syntax-boolean)" },
  { tag: tags.string, color: "var(--pg-syntax-string)" },
  { tag: tags.comment, color: "var(--pg-syntax-comment)", fontStyle: "italic" },
  { tag: tags.number, color: "var(--pg-syntax-number)" },
  { tag: tags.typeName, color: "var(--pg-syntax-type)" },
  { tag: tags.operator, color: "var(--pg-syntax-operator)" },
  { tag: tags.propertyName, color: "var(--pg-syntax-property)" },
  { tag: tags.punctuation, color: "var(--pg-syntax-punctuation)" },
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
