_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local spec = require ( "nupp.compiler.cli.spec" )

local command = spec . command {
name = "reference" ,
summary = "List or print a focused Nupp reference chapter" ,
usage = { "nupp reference [language|cli|all] [--format markdown|skill|json] [-o PATH]" } ,
positionals = { { name = "chapter" , choices = { "language" , "cli" , "all" } } } ,
intro = [[With no chapter, lists the available focused references. `all` is the
complete language reference, around fifteen thousand tokens, meant to be pasted
whole.

  nupp reference cli
  nupp reference cli --format skill -o .claude/skills/nupp-cli/SKILL.md
  nupp reference all > docs/reference.md
  nupp reference --format skill -o .claude/skills/nupp/SKILL.md]] ,
options = {
{
name = "--format" ,
value = "FORMAT" ,
choices = { "markdown" , "skill" , "json" } ,
duplicate = "output format was specified more than once" ,
help = "Output format: markdown (default), skill, or json"
} ,
{
name = "--skill" ,
key = "format" ,
constant = "skill" ,
duplicate = "output format was specified more than once" ,
help = "Shorthand for --format skill"
} ,
{
name = "--json" ,
key = "format" ,
constant = "json" ,
duplicate = "output format was specified more than once" ,
help = "Shorthand for --format json"
} ,
{
names = { "-o" , "--output" } ,
value = "PATH" ,
key = "output" ,
help = "Write to this file rather than to standard output"
} ,
} ,
detail = [[The skill's description is what a harness keeps in context permanently;
the body loads when something is actually being written. See docs/reference.md
for the same document rendered into the site.]] ,
schema = {
type = "object" ,
properties = {
title = { type = "string" } ,
sections = {
type = "array" ,
items = {
type = "object" ,
properties = {
title = { type = "string" , description = "The heading, and its anchor." } ,
body = { type = "string" , description = "What the construct is for, as markdown." } ,
example = {
type = "string" ,
description = "A complete module using it. Every one "
.. "is compiled by the compiler's own tests."
} ,
codes = {
type = "array" ,
items = { type = "string" } ,
description = "The codes that report getting it "
.. "wrong. 'nupp explain <code>' says more."
} ,
} ,
required = { "title" , "body" , "codes" } ,
} ,
} ,
chapters = {
type = "array" ,
description = "Top-level reference chapters, each containing sections." ,
items = { type = "object" } ,
} ,
tooling = { type = "string" , description = "How to drive the toolchain, as markdown." } ,
markdown = { type = "string" , description = "The whole document, as `--format markdown` writes it." } ,
} ,
required = { "title" , "sections" , "chapters" , "tooling" , "markdown" } ,
} ,
}

local function run ( parsed )
local reference = require ( "nupp.compiler.reference" )
local format = parsed . values . format or "markdown"
local positional = parsed . positional
if # positional > 1 then
return command : usageError ( "at most one reference chapter is required" )
end
local topic = positional [ 1 ]
if not topic and not parsed . values . format and not parsed . values . output then
io . write ( reference . catalog ( ) , "\n" )
return 0
end
local chapter = topic and topic ~= "all" and reference . chapter ( topic ) or nil
if topic and topic ~= "all" and not chapter then
return command : usageError ( "unknown reference chapter " .. topic )
end
local text
if format == "skill" then
text = reference . skill ( chapter )
elseif chapter then
text = reference . chapterMarkdown ( chapter )
else
text = reference . markdown ( )
end

if format == "json" then
local sections = { }
for _ , section in ipairs ( chapter and chapter . sections or reference . sections ) do
sections [
# sections + 1
] = { title = section . title , body = section . body , example = section . example , codes = section . codes , }
end
local payload = {
title = chapter and "Nupp " .. chapter . title .. " reference" or "Nupp language reference" ,
sections = sections ,
chapters = chapter and { chapter } or reference . chapters ,
tooling = reference . tooling ,
markdown = text ,
}
if chapter then
payload . chapter = chapter
end
if parsed . values . output then
local file , err = io . open ( parsed . values . output , "w" )
if not file then
io . stderr : write ( tostring ( err ) .. "\n" )
return 1
end
file : write ( require ( "nupp.compiler.cli.report" ) . encode ( payload ) , "\n" )
file : close ( )
return 0
end
require ( "nupp.compiler.cli.report" ) . write ( payload )
return 0
end

if parsed . values . output then
local file , err = io . open ( parsed . values . output , "w" )
if not file then
io . stderr : write ( tostring ( err ) .. "\n" )
return 1
end
file : write ( text , "\n" )
file : close ( )
return 0
end
io . write ( text , "\n" )

return 0
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
