_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








local spec = require ( "nupp.compiler.cli.spec" )

local command = spec . command {
name = "fixpoint" ,
summary = "Verify a byte-identical self-hosting rebuild" ,
usage = { "nupp fixpoint [--update-bootstrap] [--format text|json]" , "nupp fixpoint --binary [--format text|json]" } ,
intro = [[By default the compiler compiles itself twice and the two must agree.

--binary makes the same claim about packaging: the target named by
selfHost.binary is stamped, and the binary that comes out stamps another
identical to itself. It is what the payload format's determinism rests on.]] ,
options = require (
"nupp.compiler.cli.options"
) . join (
{ name = "--update-bootstrap" , help = "Refresh the tracked stage-0 bundle after verification" } ,
{ name = "--binary" , help = "Verify the packaged binary instead of the compiler" } ,
require ( "nupp.compiler.cli.options" ) . format ( )
) ,
schema = {
type = "object" ,
properties = {
ok = { type = "boolean" , description = "Whether the rebuild reproduced itself." } ,
kind = {
type = "string" ,
enum = { "compiler" , "binary" } ,
description = "Which claim was checked: the compiler compiling "
.. "itself twice, or the packaged binary stamping another."
} ,
target = { type = "string" , description = "The manifest target that was verified." } ,
bytes = { type = "integer" , description = "The size of the verified binary, for --binary." } ,
updatedBootstrap = { type = "boolean" , description = "Whether the tracked stage-0 bundle was refreshed." } ,
reason = { type = "string" , description = "Why it failed. Absent when ok is true." } ,
} ,
required = { "ok" , "kind" } ,
} ,
}

local function run ( parsed )
local positional = parsed . positional
if # positional > 0 then
return command : usageError ( "unexpected argument " .. positional [ 1 ] )
end
local values = parsed . values
if values . binary and values . updateBootstrap then
return command : usageError ( "--binary verifies the packaged binary and has no bootstrap to refresh" )
end
local asJson = values . format == "json"
local project = require ( "nupp.compiler.build.project" )


local result = { }
local code
if values . binary then
code = project . binaryFixpoint ( "." , { result = asJson and result or nil } )
else
code = project . fixpoint ( "." , { updateBootstrap = values . updateBootstrap , result = asJson and result or nil } )
end
if asJson then
result . ok = code == 0
result . kind = values . binary and "binary" or "compiler"
require ( "nupp.compiler.cli.report" ) . write ( result )
end

return code
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
