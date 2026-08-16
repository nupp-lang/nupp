_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local spec = require ( "nupp.compiler.cli.spec" )

local FORMATS

= { site = "site" , markdown = "markdown" , md = "markdown" , json = "json" , both = "both" , }

local command = spec . command {
name = "doc" ,
summary = "Generate API documentation from source comments" ,
usage = {
"nupp doc [site|markdown|json|both] [-o PATH] [--target NAME] [--title TITLE]"
.. " [--all] [--format text|json] [path...]"
} ,
options = require (
"nupp.compiler.cli.options"
) . join (
{ names = { "-o" , "--output" } , value = "PATH" , key = "output" , help = "Output file or directory" } ,
{ name = "--target" , value = "NAME" , help = "Document a named manifest target" } ,
{ name = "--title" , value = "TITLE" , help = "Documentation title" } ,
{ name = "--all" , help = "Include private declarations" } ,
require ( "nupp.compiler.cli.options" ) . format ( )
) ,
schema = {
type = "object" ,
properties = {
ok = { type = "boolean" } ,
format = { type = "string" , description = "The resolved format: site, markdown, json, or both." } ,
output = { type = "string" , description = "The file or directory the run was pointed at." } ,
files = {
type = "array" ,
items = { type = "string" } ,
description = "Every path written. A file whose contents did "
.. "not change is not rewritten and is not listed."
} ,
} ,
required = { "ok" , "format" , "output" , "files" } ,
} ,
detail = [[The first argument may name the format: site, markdown (or md), json, or both.
With none, the manifest's configured format is used, and site if it has none.

--format names the shape of this command's own report and is unrelated to the
documentation format, which is the positional word.]] ,
}

local function run ( parsed )
local positional = parsed . positional
local values = parsed . values
local doc = require ( "nupp.compiler.doc" )
local config , configErr = doc . loadConfig ( "." )
if not config then
io . stderr : write ( "nupp: " .. tostring ( configErr ) .. "\n" )
return 1
end
local settings , settingsErr = doc . manifestSettings ( config , values . target )
if not settings then
io . stderr : write ( "nupp: " .. tostring ( settingsErr ) .. "\n" )
return 1
end



local deps = require ( "nupp.compiler.build.deps" )
local installed , depErr = deps . build (
"." ,
settings . outDir or "build" ,
config ,
{ } ,
settings
)
if not installed then
io . stderr : write ( "nupp: " .. tostring ( depErr ) .. "\n" )
return 1
end
local opts = { output = values . output , title = values . title }


local sources = { }
local first = positional [ 1 ]
local named = first and FORMATS [ first ] or nil
if named then
opts . format = named
end
for index = named and 2 or 1 , # positional do
sources [ # sources + 1 ] = positional [ index ]
end
if # sources > 0 then
opts . sources = sources
end
if values . all then
settings . all = true
end
local asJson = values . format == "json"
local written = { }
if asJson then
opts . written = written
end
local code , output , resolved = doc . build (
"." ,
config ,
settings ,
opts
)
if asJson then
require ( "nupp.compiler.cli.report" ) . write ( {
ok = code == 0 ,
files = written ,
output = output or "" ,
format = resolved or ""
} )
end

return code
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
