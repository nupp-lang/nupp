local ffi = require("ffi")

ffi.cdef([[
typedef struct nuppSimdjsonParser nuppSimdjsonParser;
nuppSimdjsonParser *nuppSimdjsonNew(void);
void nuppSimdjsonFree(nuppSimdjsonParser *parser);
int nuppSimdjsonPrepare(nuppSimdjsonParser *parser,
   const char *source, size_t length);
int nuppSimdjsonStage1(nuppSimdjsonParser *parser);
int nuppSimdjsonDom(nuppSimdjsonParser *parser);
const char *nuppSimdjsonError(int code);
const char *nuppSimdjsonVersion(void);
const char *nuppSimdjsonImplementation(void);
]])

local suffix = ffi.os == "Windows" and ".dll"
   or ffi.os == "OSX" and ".dylib"
   or ".so"
local prefix = ffi.os == "Windows" and "" or "lib"
local libraryPath = "build/lib/" .. prefix .. "simdjson_bench_native" .. suffix
local native = ffi.load(libraryPath)
local openNative, loadError = package.loadlib(libraryPath, "luaopen_simdjson_bench_native")
assert(openNative, loadError)
local luaNative = openNative()
package.loaded.simdjson_bench_native = luaNative

local M = {}
local Parser = {}
Parser.__index = Parser

local function checked(code)
   if code ~= 0 then
      error(ffi.string(native.nuppSimdjsonError(code)), 3)
   end
end

function M.new(source)
   local pointer = native.nuppSimdjsonNew()
   if pointer == nil then
      error("could not allocate simdjson parser", 2)
   end
   pointer = ffi.gc(pointer, native.nuppSimdjsonFree)
   checked(native.nuppSimdjsonPrepare(pointer, source, #source))
   return setmetatable({pointer = pointer}, Parser)
end

function Parser:stage1()
   return native.nuppSimdjsonStage1(self.pointer)
end

function Parser:dom()
   return native.nuppSimdjsonDom(self.pointer)
end

function M.version()
   return ffi.string(native.nuppSimdjsonVersion())
end

function M.implementation()
   return ffi.string(native.nuppSimdjsonImplementation())
end

function M.error(code)
   return ffi.string(native.nuppSimdjsonError(code))
end

--- Parses and constructs an ordinary Lua DOM in one native call.
--- JSON null is dropped unless nullValue is supplied.
function M.decode(source, nullValue)
   return luaNative.decode(source, nullValue)
end

--- Selectively materializes a document with simdjson On-Demand.
--- `true` selects a complete value, object tables select named fields, and
--- `array(shape)` applies one shape to every array item.
function M.pull(source, shape, nullValue)
   return luaNative.pull(source, shape == nil and true or shape, nullValue)
end

--- Constructs the shape used to pull every item from a JSON array.
function M.arrayOf(shape)
   return luaNative.arrayOf(shape == nil and true or shape)
end

M.asArray = luaNative.asArray
M.asObject = luaNative.asObject

--- Serializes one Lua value. A plain empty table is an object; use `asArray`
--- or `EMPTY_ARRAY` for an empty array.
function M.encode(value, nullValue)
   return luaNative.encode(value, nullValue)
end

M.serialize = M.encode
M.encoded = luaNative.encoded
M.encodedString = luaNative.encodedString
M.verified = luaNative.verified
M.verifiedString = luaNative.verifiedString

--- Creates an incremental writer over caller-owned storage.
function M.writer(out, nullValue)
   return luaNative.writer(out, nullValue)
end

M.NULL = luaNative.NULL
M.EMPTY_ARRAY = luaNative.EMPTY_ARRAY
M.EMPTY_OBJECT = luaNative.EMPTY_OBJECT

return M
