_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.reference\0runtime\0001") };














local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "reference" )
local cliModule = require ( "nupp.cli" )
local report = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = report . OK ,
diagnostics = report . DIAGNOSTICS ,
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
description = "A complete module using it. Every one is compiled by the compiler's own tests."

} ,
codes = {
type = "array" ,
items = { type = "string" } ,
description = "The codes that report getting it wrong. 'nupp explain <code>' says more."
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
required = { "ok" , "title" , "sections" , "chapters" , "tooling" , "markdown" } ,
}




local function writeOutput ( path , content , asJson ) 
local wrote , err = require ( "nupp.compiler.fs" ) . writeFile ( path , content .. "\n" )
if not wrote then
if asJson then
return report . failure ( REPORT_SCHEMA , {
report . fileDiagnostic ( path , err , "check that the output path is writable" )
} )
end
io . stderr : write ( "nupp: " .. tostring ( err ) .. "\n" )
return 1
end

return 0
end

local function run ( options ) 
local positional = { }
if options . chapter ~= nil then
positional [ 1 ] = options . chapter
end
local reference = require ( "nupp.tools.reference" )
if ( options . skill and options . json ) or ( options . skill or options . json ) and options . format ~= nil then
return usageError ( "output format was specified more than once" )
end
local format = options . skill and "skill" or options . json and "json" or options . format or "markdown"
if # positional > 1 then
return usageError ( "at most one reference chapter is required" )
end
local topic = positional [ 1 ]
local wantedSection = options . section
local wantedCode = options . forCode
if wantedSection and wantedCode then
return usageError ( "--section and --for name the same thing two ways" )
end
if ( wantedSection or wantedCode ) and topic then
return usageError ( "--section and --for already say which part to print" )
end



if wantedSection or wantedCode then
local chosen = { }
if wantedSection then
local section , chapter = reference . findSection ( wantedSection )
if section then
chosen [ 1 ] = { section = section , chapter = chapter }
else



for _ , found in ipairs ( reference . pointerSections ( wantedSection , os . getenv ( "NUPP_COMPILER_ROOT" ) ) ) do
chosen [ # chosen + 1 ] = found
end
end
if # chosen == 0 then
return usageError ( "no reference section named " .. wantedSection .. "; `nupp reference` lists them" )
end
else
for _ , found in ipairs ( reference . sectionsFor ( wantedCode ) ) do
chosen [ # chosen + 1 ] = found
end
if # chosen == 0 then


return usageError (
"no reference section covers " .. wantedCode .. "; try `nupp explain " .. wantedCode .. "`"
)
end
end
local parts = { }
for _ , found in ipairs ( chosen ) do
parts [ # parts + 1 ] = reference . sectionMarkdown ( found . section , found . chapter )
end
local rendered = table . concat ( parts , "\n\n" )
if format == "skill" then
rendered = reference . sectionSkill ( chosen )
elseif format == "json" then
local sections = { }
for _ , found in ipairs ( chosen ) do
sections [
# sections + 1
] = {
title = found . section . title ,
body = found . section . body ,
example = found . section . example ,
codes = found . section . codes ,
}
end
local payload = {
ok = true ,
title = sections [ 1 ] . title ,
sections = sections ,
chapters = { } ,
tooling = reference . tooling ,
markdown = rendered ,
}
if options . output then
return writeOutput ( options . output , report . encode ( payload ) , true )
end
report . write ( payload )
return 0
end
if options . output then
return writeOutput ( options . output , rendered )
end
io . write ( rendered , "\n" )

return 0
end




if not topic and not options . format and not options . json and not options . skill and not options . output then
io . write ( reference . catalog ( ) , "\n" )
return 0
end
local chapter = topic and topic ~= "all" and reference . chapter ( topic ) or nil
if topic and topic ~= "all" and not chapter then
return usageError ( "unknown reference chapter " .. topic )
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




local listed = { }
if chapter then
listed = chapter . sections
else
for _ , one in ipairs ( reference . chapters ) do
for _ , section in ipairs ( one . sections ) do
listed [ # listed + 1 ] = section
end
end
end
local sections = { }
for _ , section in ipairs ( listed ) do
sections [
# sections + 1
] = { title = section . title , body = section . body , example = section . example , codes = section . codes , }
end
local payload

= {
ok = true ,
title = chapter and "Nupp " .. chapter . title .. " reference" or "Nupp reference" ,
sections = sections ,
chapters = chapter and { chapter } or reference . chapters ,
tooling = reference . tooling ,
markdown = text ,
}
if chapter then
payload . chapter = chapter
end
if options . output then
return writeOutput ( options . output , report . encode ( payload ) , true )
end
report . write ( payload )
return 0
end

if options . output then
return writeOutput ( options . output , text )
end
io . write ( text , "\n" )

return 0
end






















local Reference = {} Reference.__index = Reference





























function Reference:run() 
return run ( self )
end ;Reference.__nuppInit1=function(__nuppT5, a1, a2, a3, a4, a5, a6, a7, a8) __nuppT5.format = a1 if a2 == nil then __nuppT5.skill = false else __nuppT5.skill = a2 end if a3 == nil then __nuppT5.json = false else __nuppT5.json = a3 end __nuppT5.section = a4 __nuppT5.forCode = a5 __nuppT5.output = a6 if a7 == nil then __nuppT5.schema = false else __nuppT5.schema = a7 end __nuppT5.chapter = a8 return __nuppT5 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="List or print a focused Nupp reference chapter.\n\nWith no chapter, lists the focused references and their sections. A\nchapter is compiled into the executable and belongs to this compiler.\n`--section` prints one section by heading or documentation pointer, and\n`--for` prints the sections which explain one diagnostic code. Skill output\nputs its short description in the always-loaded frontmatter and the full\nreference in the lazily loaded body.\n\nExamples:\n\n    nupp reference cli\n    nupp reference language\n    nupp reference --section affine-resources\n    nupp reference --section docs/learn/language/modules.md#modules\n    nupp reference --for NUPP2004\n    nupp reference cli --format skill -o .agents/skills/nupp-cli/SKILL.md\n    nupp reference performance --format skill -o .agents/skills/nupp-performance/SKILL.md\n    nupp reference --format skill -o .agents/skills/nupp/SKILL.md",["group"]=false,["hidden"]=false,["name"]="reference",["summary"]="List or print a focused Nupp reference chapter."},["fieldCount"]=8,["fields"]={{["arity"]="required",["choices"]={"markdown","skill","json"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Output format.",["field"]="format",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"format"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--skill",["documentation"]="Shorthand for --format skill.",["field"]="skill",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"skill"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--json",["documentation"]="Shorthand for --format json.",["field"]="json",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"json"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--section",["documentation"]="Print one section, by heading or documentation pointer.",["field"]="section",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"section"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--for",["documentation"]="Print sections which explain a diagnostic code.",["field"]="forCode",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"for"},["optional"]=true,["required"]=false,["role"]="option",["value"]="CODE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--output",["documentation"]="Write to this file instead of standard output.",["field"]="output",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"output","o"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=7,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"language","cli","performance","all"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="CHAPTER",["documentation"]="Reference chapter to print.",["field"]="chapter",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="CHAPTER"}},["positionals"]={{["arity"]="required",["choices"]={"language","cli","performance","all"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="CHAPTER",["documentation"]="Reference chapter to print.",["field"]="chapter",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="CHAPTER"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="62bb21c9fde96d160019aef7ebe11937285f576ca15010669f1b6be7bbdddd62",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.reference:Reference:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="reference"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="List or print a focused Nupp reference chapter."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Reference?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Reference",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.reference:Reference:1",Reference,__nuppDerived) ;Reference["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Reference["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("reference")end ;Reference["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("List or print a focused Nupp reference chapter.")end ;Reference["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Reference,__nuppT1[1],{ })


function Reference . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Reference } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.reference"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.reference"]=__nuppExports;return __nuppExports