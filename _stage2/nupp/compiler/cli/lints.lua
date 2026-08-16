_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local spec = require ( "nupp.compiler.cli.spec" )
local ansi = require ( "nupp.compiler.ansi" )

local command = spec . command {
name = "lints" ,
summary = "List the lints and the level each runs at" ,
usage = { "nupp lints [--format text|json]" } ,
intro = [[Levels are off, note, warning and error; only an error stops a build. A
project moves one in nupp.lua by name or by category:

  lints = { ["missing-require"] = "warning", style = "off" }

A statement waves one away with @allow("missing-require"). See docs/lints.md.]] ,
options = require ( "nupp.compiler.cli.options" ) . format ( ) ,
schema = {
type = "object" ,
properties = {
lints = {
type = "array" ,
items = {
type = "object" ,
properties = {
name = { type = "string" , description = "What an @allow suppression writes." } ,
code = {
type = "string" ,
description = "The diagnostic code it reports under, "
.. "which survives the name being reconsidered."
} ,
category = { type = "string" } ,
level = {
type = "string" ,
enum = { "off" , "note" , "warning" , "error" } ,
description = "The level this project runs it at."
} ,
default = {
type = "string" ,
enum = { "off" , "note" , "warning" , "error" } ,
description = "The level it runs at when a project " .. "says nothing."
} ,
moved = {
type = "boolean" ,
description = "Whether this project moved it off " .. "its default."
} ,
summary = { type = "string" } ,
} ,
required = { "name" , "code" , "category" , "level" , "default" , "moved" , "summary" } ,
} ,
} ,
} ,
required = { "lints" } ,
} ,
}



local LEVEL_SEVERITY = { error = "error" , warning = "warning" , note = "note" , }

local function run ( parsed )
local lints = require ( "nupp.compiler.lints" )
local project = require ( "nupp.compiler.build.project" )


local config , err = project . loadManifest ( "." )
if not config and err then
io . stderr : write ( err .. "\n" )
return 1
end
local lintConfig = config and config . lints or nil
local style = ansi . style ( io . stdout )
local rows = { }
local nameWidth , categoryWidth = 4 , 8
for _ , lint in ipairs ( lints . all ) do
local level = lints . level ( lint , lintConfig )
rows [
# rows + 1
] = {
name = lint . name ,
code = lint . code ,
category = lint . category ,
level = level ,
summary = lint . summary ,
default = lint . level ,
moved = level ~= lint . level ,
}
if # lint . name > nameWidth then
nameWidth = # lint . name
end
if # lint . category > categoryWidth then
categoryWidth = # lint . category
end
end
table . sort ( rows , function ( a , b )
return a . name < b . name
end )
if parsed . values . format == "json" then
require ( "nupp.compiler.cli.report" ) . write ( { lints = rows } )
return 0
end


local out = { }
local function pad ( text , width )
return text .. ( " " ) : rep ( width - # text )
end

out [
# out + 1
] = style . faint (
pad ( "lint" , nameWidth ) .. "  " .. pad ( "category" , categoryWidth ) .. "  " .. pad ( "level" , 7 ) .. "  summary"
)
for _ , row in ipairs ( rows ) do
local summary = row . summary
if row . moved then
summary = summary .. style . faint ( ( " (default %s)" ) : format ( row . default ) )
end
local level = pad ( row . level , 7 )
local severity = LEVEL_SEVERITY [ row . level ]
if severity then
level = ansi . forSeverity ( style , severity ) ( level )
end
out [
# out + 1
] = style . strong (
pad ( row . name , nameWidth )
) .. "  " .. style . faint ( pad ( row . category , categoryWidth ) ) .. "  " .. level .. "  " .. summary
end
io . write ( table . concat ( out , "\n" ) , "\n" )

return 0
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
