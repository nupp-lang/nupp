_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local spec = require ( "nupp.compiler.cli.spec" )
local optionsMod = require ( "nupp.compiler.cli.options" )
local ansi = require ( "nupp.compiler.ansi" )

local command = spec . command {
name = "explain" ,
summary = "Describe a diagnostic code, with an example either way" ,
usage = { "nupp explain <code> [--format text|json]" , "nupp explain --list" } ,
options = optionsMod . join ( { name = "--list" , help = "List the codes with a worked example" } , optionsMod . format ( ) ) ,
schema = {
type = "object" ,
properties = {
code = { type = "string" } ,
summary = { type = "string" , description = "One line." } ,
rule = { type = "string" , description = "The general statement the code enforces." } ,
wrong = {
type = "string" ,
description = "A program that reports the code. Absent when " .. "only the family is known."
} ,
right = { type = "string" , description = "The same program, corrected." } ,
related = { type = "array" , items = { type = "string" } , description = "Codes worth reading beside it." } ,
docs = {
type = "string" ,
description = "The reference section, as a path and anchor. The "
.. "same value every diagnostic carries under `docs`."
} ,
family = {
type = "boolean" ,
description = "True when this is what the code's family says "
.. "rather than what is known about the code itself, which "
.. "is when the examples are absent."
} ,
strict = {
type = "boolean" ,
description = "True when the rule is only reported under "
.. "--strict, or with strict = true in the manifest."
} ,
codes = {
type = "array" ,
items = { type = "string" } ,
description = "Present for --list instead of the fields above."
} ,
} ,
} ,
detail = [[Every diagnostic written by --json carries the same `docs` anchor this
reports, so a reader holding a diagnostic can reach the reference without
being told where it is.

A code with no worked example still resolves through its family, and says so
with `family: true`, rather than an example being invented to fit it.]] ,
}

local function run ( parsed )
local explain = require ( "nupp.compiler.explain" )
local values = parsed . values
local asJson = values . format == "json"
local positional = parsed . positional
if values . list then
local codes = explain . codes ( )
if asJson then
require ( "nupp.compiler.cli.report" ) . write ( { codes = codes } )
else
io . write ( table . concat ( codes , "\n" ) , "\n" )
end
return 0
end
if # positional ~= 1 then
return command : usageError ( "exactly one diagnostic code is required" )
end


local code = positional [ 1 ] : upper ( )
local entry = explain . lookup ( code )
if not entry then
return command : usageError ( "unknown diagnostic code " .. positional [ 1 ] )
end
if asJson then
require ( "nupp.compiler.cli.report" ) . write ( {
code = entry . code ,
summary = entry . summary ,
rule = entry . rule ,
wrong = entry . wrong ,
right = entry . right ,
related = entry . related ,
docs = entry . docs ,
family = entry . family ,
strict = entry . strict ,
} )
return 0
end
local style = ansi . style ( io . stdout )
local out = { style . strong ( entry . code ) .. "  " .. entry . summary , "" , }
for _ , line in ipairs ( spec . wrap ( entry . rule , 79 ) ) do
out [ # out + 1 ] = line
end



local function quote ( heading , source )
out [ # out + 1 ] = ""
out [ # out + 1 ] = heading
out [ # out + 1 ] = ""
for line in ( source : gsub ( "\n$" , "" ) .. "\n" ) : gmatch ( "([^\n]*)\n" ) do
out [ # out + 1 ] = line == "" and "" or ( "    " .. line )
end
end

local wrong , right = entry . wrong , entry . right
if wrong then
quote ( ansi . forSeverity ( style , "error" ) ( "Reports it:" ) , wrong )
end
if right then
quote ( ansi . forSeverity ( style , "help" ) ( "Does not:" ) , right )
end
if entry . strict then
out [ # out + 1 ] = ""
out [ # out + 1 ] = style . faint ( "Reported only under --strict." )
end
if entry . family then
out [ # out + 1 ] = ""
out [
# out + 1
] = style . faint ( "No worked example is recorded for this code; " .. "the rule above is its family's." )
end
if # entry . related > 0 then
out [ # out + 1 ] = ""
out [ # out + 1 ] = style . faint ( "Related: " ) .. table . concat ( entry . related , ", " )
end
out [ # out + 1 ] = ""
out [ # out + 1 ] = style . faint ( "Reference: " ) .. entry . docs
io . write ( table . concat ( out , "\n" ) , "\n" )

return 0
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
