_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local lints = { }


lints.Lint = {} lints.Lint.__index = lints.Lint

















lints . all = { setmetatable({ name =

"missing-require" ,  code =
"NUPP2120" ,  category =
"correctness" ,  level =
"error" ,  summary =
"a project module is used without being required" }, lints.Lint)
, setmetatable({ name =

"exhaustiveness" ,  code =
"NUPP2107" ,  category =
"correctness" ,  level =
"warning" ,  summary =
"a dispatch leaves members of a closed set unhandled" }, lints.Lint)
, setmetatable({ name =

"string-pointer" ,  code =
"NUPP2501" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a pointer taken from a Lua string" }, lints.Lint)
, setmetatable({ name =

"jit-callback" ,  code =
"NUPP2502" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a C callback left on the JIT" }, lints.Lint)
, setmetatable({ name =

"customary-operator" ,  code =
"NUPP2504" ,  category =
"style" ,  level =
"warning" ,  summary =
"a customary operator where Lua has a word" }, lints.Lint)
, setmetatable({ name =

"loop-invariant-closure" ,  code =
"NUPP2505" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a loop builds the same function every iteration" }, lints.Lint)
, setmetatable({ name =

"undocumented-raise" ,  code =
"NUPP2506" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a documented function raises without saying so" }, lints.Lint)
, setmetatable({ name =

"unused-binding" ,  code =
"NUPP2507" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a local is declared and nothing reads it" }, lints.Lint)
, setmetatable({ name =

"discarded-result" ,  code =
"NUPP2508" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"a call with nothing to do but return has its result dropped" }, lints.Lint)
, setmetatable({ name =

"reifiable-record" ,  code =
"NUPP2509" ,  category =
"performance" ,  level =
"off" ,  summary =
"a record whose fields would all live in C memory" }, lints.Lint)
, setmetatable({ name =

"gradual-projection" ,  code =
"NUPP2511" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"an associated type was erased because inference did not reach its head" }, lints.Lint)
, setmetatable({ name =

"else-if" ,  code =
"NUPP2510" ,  category =
"style" ,  level =
"warning" ,  summary =
"a conditional chain written as separate ifs" }, lints.Lint)
, setmetatable({ name =

"positional-record-construction" ,  code =
"NUPP2512" ,  category =
"style" ,  level =
"warning" ,  summary =
"a record built by field order rather than by naming its fields" }, lints.Lint)
, setmetatable({ name =

"deprecated" ,  code =
"NUPP2513" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"use of an API marked deprecated" }, lints.Lint)
, setmetatable({ name =

"jit-boundary" ,  code =
"NUPP2514" ,  category =
"suspicious" ,  level =
"warning" ,  summary =
"an FFI boundary cannot safely run on a compiled trace" }, lints.Lint)
, setmetatable({ name =

"jit-loop-closure" ,  code =
"NUPP2515" ,  category =
"performance" ,  level =
"off" ,  summary =
"a loop builds a function and so never compiles" }, lints.Lint)
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

return lints
