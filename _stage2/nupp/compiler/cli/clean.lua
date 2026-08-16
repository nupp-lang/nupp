_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local spec = require ( "nupp.compiler.cli.spec" )

local command = spec . command {
name = "clean" ,
summary = "Remove build outputs configured in nupp.lua" ,
usage = { "nupp clean [--target NAME] [--platform NAME|all] [--dry-run] [--format text|json]" } ,
options = require (
"nupp.compiler.cli.options"
) . join (
{ name = "--target" , value = "NAME" , help = "Clean only the named build target" } ,
{ name = "--platform" , value = "NAME" , help = "Clean one configured binary platform, or all" } ,
{ name = "--dry-run" , help = "Print output paths without removing them" } ,
require ( "nupp.compiler.cli.options" ) . format ( )
) ,
schema = {
type = "object" ,
properties = {
removed = {
type = "array" ,
items = { type = "string" } ,
description = "The output paths, removed unless dryRun is set, "
.. "in which case these are the paths that would be."
} ,
dryRun = { type = "boolean" } ,
ok = { type = "boolean" } ,
} ,
required = { "ok" , "removed" , "dryRun" } ,
} ,
detail = [[With no target, cleans every configured target output. Paths outside the
project and paths that resolve to the project root are always rejected.]] ,
}

local function run ( parsed )
local positional = parsed . positional
if # positional > 0 then
return command : usageError ( "unexpected argument " .. positional [ 1 ] )
end
local values = parsed . values
local asJson = values . format == "json"
local dryRun = values . dryRun and true or false
if values . platform and not values . target then
return command : usageError ( "--platform requires --target" )
end
local project = require ( "nupp.compiler.build.project" )
local removed = { }
local code = project . clean ( "." , {
target = values . target ,
platform = values . platform ,
dryRun = values . dryRun ,
removed = asJson and removed or nil
} )
if asJson then
require ( "nupp.compiler.cli.report" ) . write ( { ok = code == 0 , removed = removed , dryRun = dryRun } )
end

return code
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
