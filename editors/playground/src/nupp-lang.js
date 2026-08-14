// A CodeMirror language for Nupp. Nupp is a syntactic superset of LuaJIT's
// Lua dialect, so the existing Lua stream-mode tokenizer already gets most of
// a source file right; this only adds the keywords and annotation sigil Lua
// doesn't have.
import { StreamLanguage } from "@codemirror/language";
import { lua } from "@codemirror/legacy-modes/mode/lua";

const NUPP_KEYWORDS = new Set([
  "as", "associated", "borrows", "cdef", "const", "constructor", "continue",
  "each", "exclusive", "from", "global", "handle", "infer", "interface", "is",
  "keyof", "match", "matches", "metamethod", "new", "out", "preserves",
  "readonly", "record", "releases", "resumes", "retains", "scoped", "struct",
  "suspension", "takes", "type", "typeerror", "unpackof", "unsafe", "when",
  "where", "with", "writekeyof", "writeof", "writeonly", "yields",
]);

const LUA_KEYWORDS = new Set([
  "and", "break", "do", "else", "elseif", "end", "for", "function", "goto",
  "if", "in", "local", "not", "or", "repeat", "return", "then", "until", "while",
]);

const LITERAL_KEYWORDS = new Set(["false", "nil", "true"]);
const DIRECTIVE_KEYWORDS = new Set(["comptime", "nosuspend"]);
const TYPE_DECLARATIONS = new Set(["interface", "record", "struct", "type"]);
const BUILTIN_FUNCTIONS = new Set([
  "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable", "ipairs",
  "load", "loadfile", "loadstring", "next", "pairs", "pcall", "print", "rawequal",
  "rawget", "rawset", "require", "select", "setfenv", "setmetatable", "tonumber",
  "tostring", "type", "unpack", "xpcall",
]);

const NUPP_TYPES = new Set([
  "any", "boolean", "borrowed", "cdata", "cstring", "ctype", "float",
  "int8", "int16", "int32", "int64", "integer", "metatable", "never",
  "number", "owned", "pinned", "string", "table", "thread", "uint8",
  "uint16", "uint32", "uint64", "unknown", "userdata", "voidptr",
]);

const NUPP_OPERATOR = /^(?:~>>=|\.\.\.|<<=|>>=|\/\/=|\.\.=|\?\?=|~>>|<<|>>|==|~=|<=|>=|!=|&&|\|\||\?\?|\?\.|::|\/\/|\.\.|->|\+=|-=|\*=|\/=|%=|&=|\|=|[+\-*/%^#&~|<>=?:!@])/;
const IDENTIFIER = /^[A-Za-z_][A-Za-z0-9_]*/;
const PUNCTUATION = /^[()[\]{},;.:]/;

function updateIndent(state, token) {
  if (/^(?:function|if|repeat|do|\(|\{)$/.test(token)) state.indentDepth++;
  else if (/^(?:end|until|\)|\})$/.test(token)) state.indentDepth--;
}

function backtickString(stream, state) {
  let escaped = false;
  let ch;
  while ((ch = stream.next()) != null) {
    if (ch === "`" && !escaped) {
      state.cur = normalTokenizer;
      break;
    }
    escaped = !escaped && ch === "\\";
  }
  return "string";
}

const baseToken = lua.token;
const normalTokenizer = lua.startState().cur;
const nuppMode = {
  ...lua,
  token(stream, state) {
    // Let Lua retain control while it is inside a multiline string or
    // comment. At top level it must also see both dashes together: otherwise
    // NUPP_OPERATOR consumes them one at a time and the comment body is
    // highlighted as live code.
    if (state.cur !== normalTokenizer || stream.match(/^--/, false)
        || stream.match(/^\[(?:\[|=)/, false)) {
      return baseToken(stream, state);
    }
    if (stream.peek() === "`") {
      stream.next();
      state.cur = backtickString;
      return backtickString(stream, state);
    }
    // Annotations such as @allow(...). Lua's mode has no notion of
    // these, so catch the sigil before falling through to it.
    if (stream.match(/^@!?[A-Za-z_][A-Za-z0-9_]*/)) {
      state.nuppPrevious = stream.current();
      return "meta";
    }
    const compoundOperator = stream.match(NUPP_OPERATOR, false);
    if (compoundOperator && compoundOperator[0].length > 1) {
      stream.match(NUPP_OPERATOR);
      state.nuppPrevious = stream.current();
      return "operator";
    }
    if (stream.match(PUNCTUATION)) {
      const punctuation = stream.current();
      updateIndent(state, punctuation);
      state.nuppPrevious = punctuation;
      return "punctuation";
    }
    if (stream.match(NUPP_OPERATOR)) {
      state.nuppPrevious = stream.current();
      return "operator";
    }
    if (stream.match(IDENTIFIER)) {
      const word = stream.current();
      const previous = state.nuppPrevious;
      let style = "variable";
      if (LITERAL_KEYWORDS.has(word)) style = "bool";
      else if (DIRECTIVE_KEYWORDS.has(word)) style = "meta";
      else if (LUA_KEYWORDS.has(word) || NUPP_KEYWORDS.has(word)) style = "keyword";
      else if (NUPP_TYPES.has(word) || /^[A-Z][A-Za-z0-9_]*$/.test(word)
          || TYPE_DECLARATIONS.has(previous)) style = "type";
      else if (previous === "function" || previous === "metamethod"
          || BUILTIN_FUNCTIONS.has(word) || stream.match(/^\s*\(/, false)) style = "builtin";
      else if (previous === "." || previous === ":") style = "property";
      updateIndent(state, word);
      state.nuppPrevious = word;
      return style;
    }
    const style = baseToken(stream, state);
    if (style) state.nuppPrevious = stream.current();
    return style;
  },
};

export const nuppLanguage = StreamLanguage.define(nuppMode);
