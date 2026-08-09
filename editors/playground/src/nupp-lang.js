// A CodeMirror language for Nupp. Nupp is a syntactic superset of LuaJIT's
// Lua dialect, so the existing Lua stream-mode tokenizer already gets most of
// a source file right; this only adds the keywords and annotation sigil Lua
// doesn't have.
import { StreamLanguage } from "@codemirror/language";
import { lua } from "@codemirror/legacy-modes/mode/lua";

const NUPP_KEYWORDS = new Set([
  "as", "borrows", "cdef", "const", "constructor", "continue",
  "exclusive", "from", "global", "interface", "is", "matches",
  "metamethod", "new", "out", "readonly", "record", "releases",
  "resumes", "retains", "struct", "takes", "type", "unsafe",
  "where", "with", "writeonly", "yields",
]);

const NUPP_TYPES = new Set([
  "any", "boolean", "borrowed", "cdata", "cstring", "ctype", "float",
  "int8", "int16", "int32", "int64", "integer", "metatable", "never",
  "number", "owned", "pinned", "string", "table", "thread", "uint8",
  "uint16", "uint32", "uint64", "unknown", "userdata", "voidptr",
]);

const NUPP_OPERATOR = /^(?:~>>=|\.\.\.|<<=|>>=|\/\/=|\.\.=|\?\?=|~>>|<<|>>|==|~=|<=|>=|!=|&&|\|\||\?\?|\?\.|::|\/\/|\.\.|->|\+=|-=|\*=|\/=|%=|&=|\|=|[+\-*/%^#&~|<>=?:!@])/;

const baseToken = lua.token;
const normalTokenizer = lua.startState().cur;
const nuppMode = {
  ...lua,
  token(stream, state) {
    // Let Lua retain control while it is inside a multiline string or
    // comment. At top level it must also see both dashes together: otherwise
    // NUPP_OPERATOR consumes them one at a time and the comment body is
    // highlighted as live code.
    if (state.cur !== normalTokenizer || stream.match(/^--/, false)) {
      return baseToken(stream, state);
    }
    // Annotations: @allow(...), @dispose, etc. Lua's mode has no notion of
    // these, so catch the sigil before falling through to it.
    if (stream.match(/^@!?[A-Za-z_][A-Za-z0-9_]*/)) return "meta";
    if (stream.match(NUPP_OPERATOR)) return "operator";
    const style = baseToken(stream, state);
    if (style === "variable") {
      const word = stream.current();
      if (NUPP_KEYWORDS.has(word)) return "keyword";
      if (NUPP_TYPES.has(word) || /^[A-Z][A-Za-z0-9_]*$/.test(word)) return "type";
    }
    return style;
  },
};

export const nuppLanguage = StreamLanguage.define(nuppMode);
