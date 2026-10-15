_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.explain\0runtime\0001") };









local cliError = require ( "nupp.tools.cli.error" )
local usageError = cliError . forCommand ( "explain" )
local ansi = require ( "nupp.cli" )
local cliModule = require ( "nupp.cli" )

local report = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
description = "One code's explanation, or with --list every code that has one." ,
oneOf = {
{
type = "object" ,
description = "One code." ,
properties = {
ok = report . OK ,
code = { type = "string" } ,
summary = { type = "string" , description = "One line." } ,
rule = { type = "string" , description = "The general statement the code enforces." } ,
wrong = {
type = "string" ,
description = "A program that reports the code. Absent when only the family is known."
} ,
right = { type = "string" , description = "The same program, corrected." } ,
related = { type = "array" , items = { type = "string" } , description = "Codes worth reading beside it." } ,
docs = {
type = "string" ,
description = "The reference section, as a path and anchor. The same value every diagnostic carries under `docs`."

} ,
family = {
type = "boolean" ,
description = "True when this is what the code's family says rather than what is known about the code itself, which is when the examples are absent."


} ,
aot = {
type = "boolean" ,
description = "True when the rule is only reported for a build target whose aot policy compiles @aot functions: any policy but off."


} ,
class = { type = "string" , description = "Trace reason class for a jit/* identity." } ,
repair = { type = "string" , description = "Specific semantics-preserving repair, when known." } ,
reasonCatalog = { type = "object" } ,
} ,
required = { "ok" , "code" , "summary" , "rule" , "related" , "docs" , "family" } ,
} ,
{
type = "object" ,
description = "Every code with an explanation of its own, for --list." ,
properties = { ok = report . OK , codes = { type = "array" , items = { type = "string" } } } ,
required = { "ok" , "codes" } ,
} ,
} ,
}

local function run ( options ) 
local positional = options . code and { options . code } or { }
local explain = require ( "nupp.tools.explain" )
local values = options
local asJson = values . format == "json"
if values . list then
if # positional > 0 then
return usageError ( "--list lists every code; it does not take one" )
end
local codes = explain . codes ( )
for _ , reason in ipairs ( require ( "nupp.profile.trace" ) . records ( ) ) do
codes [ # codes + 1 ] = reason . id
end
table . sort ( codes )
if asJson then
report . write ( { ok = true , codes = codes } )
else
io . write ( table . concat ( codes , "\n" ) , "\n" )
end
return 0
end
if # positional ~= 1 then
return usageError ( "exactly one diagnostic code is required" )
end


local requested = positional [ 1 ]
local code = requested : upper ( )
local reason = require ( "nupp.profile.trace" ) . reason ( requested : lower ( ) )
local entry = reason
and {
code = reason . id ,
summary = reason . explanation or reason . id ,
rule = reason . class == "blocker"
and "The selected LuaJIT recorder refuses this operation whenever recording reaches it."
or reason . class == "risk"
and "Whether the recorder accepts this operation depends on runtime or target facts."
or "This is ordinary trace formation rather than a recorder failure." ,
related = { } ,
docs = explain . reasonDocs ( reason . id , reason . class ) ,
family = false ,
class = reason . class ,
repair = reason . repair ,
}
or explain . lookup ( code )
if not entry then
return usageError ( "unknown diagnostic code " .. positional [ 1 ] )
end
local display = entry
if asJson then
report . write ( {
ok = true ,
code = display . code ,
summary = display . summary ,
rule = display . rule ,
wrong = display . wrong ,
right = display . right ,
related = display . related ,
docs = display . docs ,
family = display . family ,
aot = display . aot ,
class = display . class ,
repair = display . repair ,
reasonCatalog = reason
and {
id = require ( "nupp.profile.trace" ) . CATALOG_ID ,
version = require ( "nupp.profile.trace" ) . CATALOG_VERSION ,
}
or nil ,
} )
return 0
end
local style = ansi . style ( io . stdout )
local out = { style . strong ( display . code ) .. "  " .. display . summary , "" , }
for _ , line in ipairs ( cliError . wrap ( display . rule , 79 ) ) do
out [ # out + 1 ] = line
end
if display . repair then
out [ # out + 1 ] = ""
out [ # out + 1 ] = ansi . severity ( style , "help" ) ( "Repair: " ) .. display . repair
end



local function quote ( heading , source ) 
out [ # out + 1 ] = ""
out [ # out + 1 ] = heading
out [ # out + 1 ] = ""
for line in ( source : gsub ( "\n$" , "" ) .. "\n" ) : gmatch ( "([^\n]*)\n" ) do
out [ # out + 1 ] = line == "" and "" or ( "    " .. line )
end
end

local wrong , right = display . wrong , display . right
if wrong then
quote ( ansi . severity ( style , "error" ) ( "Reports it:" ) , wrong )
end
if right then
quote ( ansi . severity ( style , "help" ) ( "Does not:" ) , right )
end
if display . aot then
out [ # out + 1 ] = ""
out [ # out + 1 ] = style . faint ( "Reported only for a target whose aot policy compiles @aot functions." )
end
if display . family then
out [ # out + 1 ] = ""
out [
# out + 1
] = style . faint ( "No worked example is recorded for this code; the rule above is its family's." )
end
if # display . related > 0 then
out [ # out + 1 ] = ""
out [ # out + 1 ] = style . faint ( "Related: " ) .. table . concat ( display . related , ", " )
end
out [ # out + 1 ] = ""
out [ # out + 1 ] = style . faint ( "Reference: " ) .. display . docs
io . write ( table . concat ( out , "\n" ) , "\n" )

return 0
end













local Explain = {} Explain.__index = Explain














function Explain:run() 
return run ( self )
end ;Explain.__nuppInit1=function(__nuppT5, a1, a2, a3, a4) if a1 == nil then __nuppT5.list = false else __nuppT5.list = a1 end if a2 == nil then __nuppT5.format = "text" else __nuppT5.format = a2 end if a3 == nil then __nuppT5.schema = false else __nuppT5.schema = a3 end __nuppT5.code = a4 return __nuppT5 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Describe a diagnostic code, with an example either way.\n\nA code with no worked example still resolves through its family rather than\ninventing an example to fit it.\n\nExamples:\n\n    nupp explain NUPP2004\n    nupp explain --list\n    nupp explain NUPP2004 --json",["group"]=false,["hidden"]=false,["name"]="explain",["summary"]="Describe a diagnostic code, with an example either way."},["fieldCount"]=4,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--list",["documentation"]="List the codes with dedicated explanations.",["field"]="list",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"list"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="CODE",["documentation"]="Diagnostic code to explain.",["field"]="code",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="CODE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="CODE",["documentation"]="Diagnostic code to explain.",["field"]="code",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="CODE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="c9dee407ffba600f83636d5a43683769b87c3583f018ad728ef0ec93186c1caf",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.explain:Explain:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="explain"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Describe a diagnostic code, with an example either way."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Explain?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Explain",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.explain:Explain:1",Explain,__nuppDerived) ;Explain["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Explain["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("explain")end ;Explain["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Describe a diagnostic code, with an example either way.")end ;Explain["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Explain,__nuppT1[1],{ })


function Explain . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Explain } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.explain"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.explain"]=__nuppExports;return __nuppExports