_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local diagnosticMod = require ( "nupp.compiler.diagnostics" )
local fs = require ( "nupp.compiler.fs" )

local compile = { }


compile.Settings = {} compile.Settings.__index = compile.Settings




































local LEVELS = { [ "0" ] = 0 , [ "1" ] = 1 , [ "2" ] = 2 }



function compile . settings ( values , collected )
return setmetatable({ strict =
values . strict ,  optLevel =
LEVELS [ values . optLevel ] or 0 ,  remarks =
values . remarks and true or false ,  disabled =
values . disabled or { } ,  relaxed =
values . relaxed or { } ,  diagnostics =
collected ,  coverage =
values . coverage == true or os . getenv ( "NUPP_COVERAGE" ) == "1" }, compile.Settings)

end



function compile . module ( path , env , settings )
local collected = settings . diagnostics


local function say ( values )
if not collected then
return diagnosticMod . report ( values )
end
local fatal = false
for _ , diagnostic in ipairs ( values ) do
collected [ # collected + 1 ] = diagnostic
if diagnosticMod . isFatal ( diagnostic ) then
fatal = true
end
end

return fatal
end

local source , readErr = fs . readFile ( path )
if not source then
if collected then
collected [
# collected + 1
] = {
filename = path ,
line = 0 ,
col = 0 ,
offset = 0 ,
length = 0 ,
code = "NUPP0001" ,
msg = readErr ,
help = "check that the path exists and is readable"
}
else
io . stderr : write ( "nupp: " .. tostring ( readErr ) .. "\n" )
end
return nil , readErr
end
local parser = require ( "nupp.compiler.parser" )
local result = parser . parse ( source , path )
if # result . errors > 0 then
say ( result . errors )
return nil , "syntax errors"
end
local check = require ( "nupp.compiler.check" )
local diags = check . check ( result , path , env , { strict = settings . strict } )
if settings . materializations then
local observations = require (
"nupp.compiler.materialize.observe"
) . public ( require ( "nupp.compiler.materialize.observe" ) . collect ( result . root , path ) )
for _ , observation in ipairs ( observations ) do
settings . materializations [ # settings . materializations + 1 ] = observation
end
end
if settings . derives then
for _ , observation in ipairs ( result . deriveObservations or { } ) do
settings . derives [ # settings . derives + 1 ] = observation
end
end
if say ( diags ) then
return nil , "type errors"
end
local remarks = require ( "nupp.compiler.optimize" ) . run ( result , {
level = settings . optLevel ,
filename = path ,
disabled = settings . disabled ,
relaxed = settings . relaxed
} )
if settings . remarks then
say ( remarks )
end
local gen = require ( "nupp.compiler.gen" )
local code , genDiags = gen . generate ( result , path , settings . coverage and { path = path } or nil )
if # genDiags > 0 then
say ( genDiags )
return nil , "code generation errors"
end

return code
end

return compile
