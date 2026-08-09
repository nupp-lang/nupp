// A CodeMirror language for Nupp. Nupp is a syntactic superset of LuaJIT's
// Lua dialect, so the existing Lua stream-mode tokenizer already gets most of
// a source file right; this only adds the keywords and annotation sigil Lua
// doesn't have.
import { StreamLanguage } from "@codemirror/language";
import { lua } from "@codemirror/legacy-modes/mode/lua";

const NUPP_KEYWORDS = new Set([
  "record", "struct", "interface", "enum", "type", "new",
  "with", "owned", "borrowed", "pinned", "unsafe", "takes",
  "retains", "releases", "raise", "raises", "as", "global",
]);

const baseToken = lua.token;
const nuppMode = {
  ...lua,
  token(stream, state) {
    // Annotations: @allow(...), @dispose, etc. Lua's mode has no notion of
    // these, so catch the sigil before falling through to it.
    if (stream.match(/^@[A-Za-z_][A-Za-z0-9_]*/)) return "meta";
    const style = baseToken(stream, state);
    if (style === "variable" && NUPP_KEYWORDS.has(stream.current())) {
      return "keyword";
    }
    return style;
  },
};

export const nuppLanguage = StreamLanguage.define(nuppMode);
