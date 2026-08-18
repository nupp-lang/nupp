local ffi = require("ffi")

ffi.cdef([[
typedef struct nupp_simdjson_parser nupp_simdjson_parser;
nupp_simdjson_parser *nupp_simdjson_new(void);
void nupp_simdjson_free(nupp_simdjson_parser *parser);
int nupp_simdjson_prepare(nupp_simdjson_parser *parser,
   const char *source, size_t length);
int nupp_simdjson_stage1(nupp_simdjson_parser *parser);
int nupp_simdjson_dom(nupp_simdjson_parser *parser);
const char *nupp_simdjson_error(int code);
const char *nupp_simdjson_version(void);
const char *nupp_simdjson_implementation(void);
]])

local suffix = ffi.os == "Windows" and ".dll"
   or ffi.os == "OSX" and ".dylib"
   or ".so"
local prefix = ffi.os == "Windows" and "" or "lib"
local libraryPath = "build/lib/" .. prefix .. "simdjson_bench" .. suffix
local native = ffi.load(libraryPath)
local openNative, loadError = package.loadlib(libraryPath, "luaopen_simdjson_bench_native")
assert(openNative, loadError)
local luaNative = openNative()

local M = {}
local Parser = {}
Parser.__index = Parser

local function checked(code)
   if code ~= 0 then
      error(ffi.string(native.nupp_simdjson_error(code)), 3)
   end
end

function M.new(source)
   local pointer = native.nupp_simdjson_new()
   if pointer == nil then
      error("could not allocate simdjson parser", 2)
   end
   pointer = ffi.gc(pointer, native.nupp_simdjson_free)
   checked(native.nupp_simdjson_prepare(pointer, source, #source))
   return setmetatable({pointer = pointer}, Parser)
end

function Parser:stage1()
   return native.nupp_simdjson_stage1(self.pointer)
end

function Parser:dom()
   return native.nupp_simdjson_dom(self.pointer)
end

function M.version()
   return ffi.string(native.nupp_simdjson_version())
end

function M.implementation()
   return ffi.string(native.nupp_simdjson_implementation())
end

function M.error(code)
   return ffi.string(native.nupp_simdjson_error(code))
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
function M.array(shape)
   return luaNative.array(shape == nil and true or shape)
end

--- Serializes one Lua value. Empty containers require the exported sentinels.
function M.encode(value, nullValue)
   return luaNative.encode(value, nullValue)
end

M.serialize = M.encode

--- Creates an incremental writer. flush() returns the next completed chunk.
function M.writer(nullValue)
   return luaNative.writer(nullValue)
end

M.empty_array = luaNative.empty_array
M.empty_object = luaNative.empty_object

return M
