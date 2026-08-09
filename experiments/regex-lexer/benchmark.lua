local script = arg[0]:gsub("\\", "/")
local root = script:match("^(.*)/experiments/regex%-lexer/benchmark%.lua$") or "."
package.path = root .. "/build/?.lua;" .. package.path

local ffi = require("ffi")
local lexer = require("nupp.compiler.lexer")

ffi.cdef([[
typedef struct NuppLexerResult NuppLexerResult;
typedef struct {
   size_t start;
   size_t end;
   size_t line;
   size_t col;
   uint32_t kind;
} NuppLexerSpan;
typedef struct {
   size_t start;
   size_t end;
   size_t line;
   size_t col;
   uint32_t kind;
} NuppLexerError;
NuppLexerResult *nuppLexerTokenize(const uint8_t *, size_t);
size_t nuppLexerSpanCount(const NuppLexerResult *);
const NuppLexerSpan *nuppLexerSpans(const NuppLexerResult *);
size_t nuppLexerErrorCount(const NuppLexerResult *);
const NuppLexerError *nuppLexerErrors(const NuppLexerResult *);
void nuppLexerDestroy(NuppLexerResult *);
]])

local extension = ffi.os == "OSX" and "dylib" or ffi.os == "Windows" and "dll" or "so"
local prefix = ffi.os == "Windows" and "" or "lib"
local library = root .. "/build/host/release/" .. prefix
   .. "nupp_regex_lexer_prototype." .. extension
local C = ffi.load(library)

local BOM, HASHBANG, WHITESPACE, COMMENT = 1, 2, 3, 4
local NAME, NUMBER, STRING, ERROR, OPERATOR = 5, 6, 7, 8, 9
local ISTRING_OPEN, ISTRING_MID, ISTRING_CLOSE, EOF = 10, 11, 12, 13

local triviaKinds = {
   [BOM] = "bom",
   [HASHBANG] = "hashbang",
   [WHITESPACE] = "whitespace",
   [COMMENT] = "comment",
}

local tokenKinds = {
   [NUMBER] = "number",
   [STRING] = "string",
   [ERROR] = "error",
   [ISTRING_OPEN] = "istringOpen",
   [ISTRING_MID] = "istringMid",
   [ISTRING_CLOSE] = "istringClose",
   [EOF] = "eof",
}

local errorMessages = {
   [1] = "unterminated long comment",
   [2] = "malformed number",
   [3] = "unterminated string",
   [4] = "unterminated interpolated string",
   [5] = "unterminated long string",
}

local function release(result)
   ffi.gc(result, nil)
   C.nuppLexerDestroy(result)
end

local function scan(source)
   local result = C.nuppLexerTokenize(source, #source)
   assert(result ~= nil, "native lexer rejected its subject")
   return ffi.gc(result, C.nuppLexerDestroy)
end

local function nativeOnly(source)
   local result = scan(source)
   local count = tonumber(C.nuppLexerSpanCount(result))
   release(result)
   return count
end

local function prototypeLex(source, filename)
   local result = scan(source)
   local spans = C.nuppLexerSpans(result)
   local spanCount = tonumber(C.nuppLexerSpanCount(result))
   local tokens, pending = {}, {}

   for index = 0, spanCount - 1 do
      local span = spans[index]
      local kind = tonumber(span.kind)
      local first = tonumber(span.start) + 1
      local after = tonumber(span["end"])
      local text = kind == EOF and "" or source:sub(first, after)
      local item = {
         text = text,
         offset = first,
         line = tonumber(span.line),
         col = tonumber(span.col),
      }
      local triviaKind = triviaKinds[kind]
      if triviaKind then
         item.kind = triviaKind
         pending[#pending + 1] = item
      else
         if kind == NAME then
            item.kind = lexer.KEYWORDS[text] and text or "name"
         elseif kind == OPERATOR then
            item.kind = lexer.CUSTOMARY[text] or text
         else
            item.kind = assert(tokenKinds[kind], "unknown native token kind " .. kind)
         end
         item.trivia = pending
         pending = {}
         tokens[#tokens + 1] = item
      end
   end

   local errors = {}
   local nativeErrors = C.nuppLexerErrors(result)
   local errorCount = tonumber(C.nuppLexerErrorCount(result))
   for index = 0, errorCount - 1 do
      local native = nativeErrors[index]
      local kind = tonumber(native.kind)
      local first = tonumber(native.start) + 1
      local after = tonumber(native["end"])
      local message = errorMessages[kind]
      if kind == 6 then
         message = ("unexpected character %q"):format(source:sub(first, after))
      end
      errors[#errors + 1] = {
         code = "NUPP1001",
         offset = first,
         length = math.max(1, after - tonumber(native.start)),
         line = tonumber(native.line),
         col = tonumber(native.col),
         msg = assert(message, "unknown native error kind " .. kind),
         filename = filename,
      }
   end
   release(result)
   return tokens, errors
end

local function same(label, expected, actual, fields)
   assert(#expected == #actual,
      ("%s count: expected %d, got %d"):format(label, #expected, #actual))
   for index = 1, #expected do
      for _, field in ipairs(fields) do
         assert(expected[index][field] == actual[index][field],
            ("%s %d %s: expected %q, got %q"):format(
               label, index, field, expected[index][field], actual[index][field]))
      end
   end
end

local tokenFields = {"kind", "text", "offset", "line", "col"}
local errorFields = {"code", "offset", "length", "line", "col", "msg", "filename"}
local triviaFields = {"kind", "text", "offset", "line", "col"}

local function verify(source, filename)
   local expectedTokens, expectedErrors = lexer.lex(source, filename)
   local actualTokens, actualErrors = prototypeLex(source, filename)
   local ok, problem = pcall(function()
      same(filename .. " tokens", expectedTokens, actualTokens, tokenFields)
      same(filename .. " errors", expectedErrors, actualErrors, errorFields)
      for index = 1, #expectedTokens do
         same(filename .. " token " .. index .. " trivia",
            expectedTokens[index].trivia, actualTokens[index].trivia, triviaFields)
      end
   end)
   if not ok then
      error(problem .. "\nsource: " .. ("%q"):format(source), 0)
   end
end

local function read(path)
   local file = assert(io.open(path, "rb"))
   local source = file:read("*a")
   file:close()
   return source
end

local paths = {}
local command = ("find %q/src %q/tests %q/examples -name '*.nupp' -type f | sort")
   :format(root, root, root)
local pipe = assert(io.popen(command))
for path in pipe:lines() do
   paths[#paths + 1] = path
end
assert(pipe:close())

local corpus, bytes = {}, 0
for _, path in ipairs(paths) do
   local source = read(path)
   corpus[#corpus + 1] = {source = source, filename = path}
   bytes = bytes + #source
end

local probes = {
   "", "a && b", "0xffULL", "local a = 0x", "  -- lead\nlocal x",
   "return 1 -- done\n", "local s = [[a\nb]] return 1", "local s = 'oops\nreturn 1",
   "--[[ open", "a $ b", "`plain`", "`open ${x}`", "`a ${ {x = 1} } b`",
   "`outer ${ `inner ${x}` } done`", "[==[long\nbody]==]", "#!/usr/bin/env nupp\nreturn 1",
   "\239\187\191local x = 1", "0_x_F_Fu_l_l", "1e_+_2", "'trailing\\",
}

for index, source in ipairs(probes) do
   verify(source, ("probe-%d"):format(index))
end
for _, item in ipairs(corpus) do
   verify(item.source, item.filename)
end

local random = 0x4E555050
local alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-*/%^#&~|<>=(){}[];:,.?@! '\"`$\\\n\t"
local generated = 500
for case = 1, generated do
   random = (random * 1664525 + 1013904223) % 4294967296
   local length = random % 200
   local parts = {}
   for index = 1, length do
      random = (random * 1664525 + 1013904223) % 4294967296
      local at = random % #alphabet + 1
      parts[index] = alphabet:sub(at, at)
   end
   verify(table.concat(parts), ("fuzz-%d"):format(case))
end

for case = generated + 1, generated + 200 do
   random = (random * 1664525 + 1013904223) % 4294967296
   local length = random % 200
   local parts = {}
   for index = 1, length do
      random = (random * 1664525 + 1013904223) % 4294967296
      parts[index] = string.char(random % 256)
   end
   verify(table.concat(parts), ("byte-fuzz-%d"):format(case - generated))
end
generated = generated + 200

io.write(("verified %d corpus files and %d generated/probe inputs\n")
   :format(#corpus, #probes + generated))

local function benchmark(name, operation, rounds)
   for _, item in ipairs(corpus) do
      operation(item.source, item.filename)
   end
   collectgarbage()
   local started = os.clock()
   local count = 0
   for _ = 1, rounds do
      for _, item in ipairs(corpus) do
         local first = operation(item.source, item.filename)
         count = count + (type(first) == "table" and #first or first)
      end
   end
   local elapsed = os.clock() - started
   local megabytes = bytes * rounds / 1000000
   io.write(("%-22s %6.1f ms/MB  %7.1f MB/s  %.3f s  objects=%d\n")
      :format(name, elapsed * 1000 / megabytes, megabytes / elapsed, elapsed, count))
end

benchmark("current lexer", lexer.lex, 20)
benchmark("native spans only", nativeOnly, 20)
benchmark("native + Lua objects", prototypeLex, 20)
io.write(("corpus                 %.3f MB in %d files\n"):format(bytes / 1000000, #corpus))
