_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.lints\0runtime\0001") };














local lints = { }


lints.Lint = {} lints.Lint.__index = lints.Lint ;_G.nupp.__reflect.link(lints.Lint,__nuppT1[1],{ })

















lints . all = {
_G.setmetatable({ name =
"missing-require" ,  code =
"NUPP2120" ,  category =
"correctness" ,  level =
"error" ,  summary =
"a project module is used without being required" }, lints.Lint)
,
_G.setmetatable({ name =
"exhaustiveness" ,  code =
"NUPP2107" ,  category =
"correctness" ,  level =
"warning" ,  summary =
"a dispatch leaves members of a closed set unhandled" }, lints.Lint)
,
_G.setmetatable({ name =
"string-pointer" ,  code =
"NUPP2501" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a pointer taken from a Lua string" }, lints.Lint)
,
_G.setmetatable({ name =
"jit-callback" ,  code =
"NUPP2502" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a C callback left on the JIT" }, lints.Lint)
,
_G.setmetatable({ name =
"customary-operator" ,  code =
"NUPP2504" ,  category =
"style" ,  level =
"warning" ,  summary =
"a customary operator where Lua has a word" }, lints.Lint)
,
_G.setmetatable({ name =
"loop-invariant-closure" ,  code =
"NUPP2505" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a loop builds the same function every iteration" }, lints.Lint)
,
_G.setmetatable({ name =
"undocumented-raise" ,  code =
"NUPP2506" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a documented function raises without saying so" }, lints.Lint)
,
_G.setmetatable({ name =
"unused-binding" ,  code =
"NUPP2507" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a local is declared and nothing reads it" }, lints.Lint)
,
_G.setmetatable({ name =
"discarded-result" ,  code =
"NUPP2508" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a call with nothing to do but return has its result dropped" }, lints.Lint)
,
_G.setmetatable({ name =
"reifiable-record" ,  code =
"NUPP2509" ,  category =
"performance" ,  level =
"off" ,  summary =
"a record whose fields would all live in C memory" }, lints.Lint)
,
_G.setmetatable({ name =
"gradual-projection" ,  code =
"NUPP2511" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"an associated type was erased because inference did not reach its head" }, lints.Lint)
,
_G.setmetatable({ name =
"exit-suffix-binding" ,  code =
"NUPP2517" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a binding list takes more than one value from an exit suffix" }, lints.Lint)
,
_G.setmetatable({ name =
"else-if" ,  code =
"NUPP2510" ,  category =
"style" ,  level =
"warning" ,  summary =
"a conditional chain written as separate ifs" }, lints.Lint)
,
_G.setmetatable({ name =
"positional-record-construction" ,  code =
"NUPP2512" ,  category =
"style" ,  level =
"warning" ,  summary =
"a record built by field order rather than by naming its fields" }, lints.Lint)
,
_G.setmetatable({ name =
"deprecated" ,  code =
"NUPP2513" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"use of an API marked deprecated" }, lints.Lint)
,
_G.setmetatable({ name =
"jit-boundary" ,  code =
"NUPP2514" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"an FFI boundary cannot safely run on a compiled trace" }, lints.Lint)
,
_G.setmetatable({ name =
"jit-loop-closure" ,  code =
"NUPP2515" ,  category =
"performance" ,  level =
"off" ,  summary =
"a loop builds a function and so never compiles" }, lints.Lint)
,
_G.setmetatable({ name =
"private-export-type" ,  code =
"NUPP2516" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"an export exposes a private nominal type" }, lints.Lint)
,
_G.setmetatable({ name =
"prefer-comptime" ,  code =
"NUPP2518" ,  category =
"performance" ,  level =
"off" ,  summary =
"a closed no-input function repeats work that comptime can erase" }, lints.Lint)
,
}



local byKey = { }
for _ , lint in ipairs ( lints . all ) do
byKey [ lint . name ] = lint
byKey [ lint . code ] = lint
end




local CATEGORIES

= {
correctness = "the program is very likely wrong" ,
suspicious = "legal, and probably not meant" ,
style = "it works and reads badly" ,
performance = "the code pays for something it did not have to" ,
}



local LEVELS = { off = true , note = true , warning = true , error = true , }




















local OPT_IN = { performance = true }


lints . categories = CATEGORIES


lints . levels = LEVELS


lints . optIn = OPT_IN




function lints . get ( key ) 
return byKey [ key ]
end







function lints . level ( lint , config ) 
local level = lint . level
if config then
local byCategory = config [ lint . category ]
if byCategory and LEVELS [ byCategory ] then
level = byCategory
end
local byName = config [ lint . name ] or config [ lint . code ]
if byName and LEVELS [ byName ] then
level = byName
end
end

return level
end

local __nuppExportValue= lints ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.lints"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.lints"]=__nuppExports;return __nuppExports