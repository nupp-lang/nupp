_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);














local spec = require ( "nupp.compiler.cli.spec" )
local optionsMod = require ( "nupp.compiler.cli.options" )

local command = spec . command {
name = "check" ,
summary = "Type-check source without emitting Lua" ,
usage = { "nupp check [--strict] [--target NAME] [--platform NAME|all] [--format text|json] [file...]" } ,
options = optionsMod . join (
optionsMod . strict ,
{ name = "--target" , value = "NAME" , help = "Check a named manifest target" } ,
{ name = "--platform" , value = "NAME" , help = "Check one configured binary platform, or all" } ,
optionsMod . format ( )
) ,
schema = {
type = "object" ,
properties = {
diagnostics = require ( "nupp.compiler.cli.report" ) . DIAGNOSTICS ,
platform = { type = "string" } ,
platforms = { type = "array" , items = { type = "object" } } ,
} ,
required = { "diagnostics" } ,
} ,
detail = "With no files, checks the default target from nupp.lua." ,
}

local function run ( parsed )
local paths = parsed . positional
local values = parsed . values
local target = values . target
if ( target or values . platform ) and # paths > 0 then
return command : usageError ( "--target and --platform cannot be combined with source files" )
end
local asJson = values . format == "json"
local reportMod = require ( "nupp.compiler.cli.report" )
local diagnostics = { }
if # paths == 0 then
local project = require ( "nupp.compiler.build.project" )
local produced = { }
local code = project . check ( "." , {
strict = values . strict ,
target = target ,
platform = values . platform ,
diagnostics = asJson and diagnostics or nil ,
produced = asJson and produced or nil
} )
if asJson then
reportMod . write ( {
diagnostics = reportMod . diagnosticValues ( diagnostics ) ,
platform = produced . platform ,
platforms = produced . platforms ,
} )
end
return code
end
local fs = require ( "nupp.compiler.fs" )
local parser = require ( "nupp.compiler.parser" )
local check = require ( "nupp.compiler.check" )
local diagnosticMod = require ( "nupp.compiler.diagnostics" )
local failed = false





local readable , sources = { } , { }
for _ , path in ipairs ( paths ) do
local source , err = fs . readFile ( path )
if source then
readable [ # readable + 1 ] = path
sources [ path ] = source
else
if asJson then
diagnostics [
# diagnostics + 1
] = {
filename = path ,
line = 0 ,
col = 0 ,
offset = 0 ,
length = 0 ,
code = "NUPP0001" ,
msg = err ,
help = "check that the path exists and is readable"
}
else
io . stderr : write ( "nupp: " .. tostring ( err ) .. "\n" )
end
failed = true
end
end











local remaining = readable
local config = # readable > 0 and require ( "nupp.compiler.build.manifest" ) . load ( "." ) or nil
if config then
local envMod = require ( "nupp.compiler.env" )
local roots = envMod . projectRoots ( "." , config )
local mine = { }
for _ , path in ipairs ( readable ) do
if envMod . moduleNameInRoots ( roots , path ) then
mine [ # mine + 1 ] = path
end
end



if # mine > 0 then
local project = require ( "nupp.compiler.build.project" )
local unchecked = { }
local code = project . check ( "." , {
strict = values . strict ,
paths = mine ,
unchecked = unchecked ,
diagnostics = asJson and diagnostics or nil ,
} )
if code ~= 0 then
failed = true
end
remaining = { }
local handled = { }
for _ , path in ipairs ( mine ) do
handled [ path ] = true
end
for _ , path in ipairs ( unchecked ) do
handled [ path ] = nil
end
for _ , path in ipairs ( readable ) do
if not handled [ path ] then
remaining [ # remaining + 1 ] = path
end
end
end
end
if # remaining == 0 then
if asJson then
reportMod . json ( diagnostics )
end

return failed and 1 or 0
end

local env = require ( "nupp.compiler.env" ) . new ( "." )
for _ , path in ipairs ( remaining ) do
local result = parser . parse ( sources [ path ] , path )
if # result . errors > 0 then
if asJson then
for _ , diagnostic in ipairs ( result . errors ) do
diagnostics [ # diagnostics + 1 ] = diagnostic
end
else
diagnosticMod . report ( result . errors )
end
failed = true
else
local diags = check . check ( result , path , env , { strict = values . strict } )
if asJson then
for _ , diagnostic in ipairs ( diags ) do
diagnostics [ # diagnostics + 1 ] = diagnostic
if reportMod . fatal ( diagnostic ) then
failed = true
end
end
elseif diagnosticMod . report ( diags ) then
failed = true
end
end
end



require ( "nupp.compiler.env" ) . persist ( env )
if asJson then
reportMod . json ( diagnostics )
end

return failed and 1 or 0
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
