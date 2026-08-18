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
function M.decode(source, nullValue)
   return luaNative.decode(source, nullValue)
end

--- Parses into a read-only simdjson-backed DOM that defers Lua allocation.
function M.lazy(source, nullValue)
   return luaNative.lazy(source, nullValue)
end

--- Converts a lazy root or nested container into ordinary Lua values.
function M.materialize(value)
   return luaNative.materialize(value)
end

--- Returns the JSON type of a lazy root or nested container.
function M.type(value)
   return luaNative.type(value)
end

return M
