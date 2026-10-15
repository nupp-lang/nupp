_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.doc\0runtime\0001") };











local cliModule = require ( "nupp.cli" )

local report = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = report . OK ,
diagnostics = report . DIAGNOSTICS ,
kind = { type = "string" , description = "What was produced: site, markdown, json, or both." } ,
output = { type = "string" , description = "The file or directory the run was pointed at." } ,
files = {
type = "array" ,
items = { type = "string" } ,
description = "Every path written. A file whose contents did not change is not rewritten and is not listed."

} ,
} ,
required = { "ok" , "diagnostics" , "kind" , "output" , "files" } ,
}

local function run ( options ) 
local values = options
local asJson = values . format == "json"
local settings = nil
local diagnostics = { }



local function fail ( code , problem , file ) 
if asJson then
return report . failure ( REPORT_SCHEMA , { report . runDiagnostic ( code , tostring ( problem ) , nil , file ) } , {
output = values . output or settings and settings . outDir or "" ,
kind = values . kind or settings and settings . format or "" ,
} )
end
io . stderr : write ( require ( "nupp.tools.cli.error" ) . message ( problem ) .. "\n" )

return 1
end

local doc = require ( "nupp.tools.doc" )



local config = { }
if require ( "nupp.compiler.fs" ) . exists ( "nupp.lua" ) then
local loaded , configErr = require ( "nupp.tools.build.manifest" ) . load ( "." )
if not loaded then
return fail ( report . MANIFEST , configErr , "nupp.lua" )
end
config = loaded
end
local settingsErr = nil
settings , settingsErr = doc . manifestSettings ( config , values . target )
if not settings then
return fail ( report . UNKNOWN_NAME , settingsErr , "nupp.lua" )
end



local deps = require ( "nupp.tools.build.deps" )
local installed , depErr = deps . build ( "." , settings . outDir or "build" , config , { } , settings )
if not installed then
return fail ( report . TOOL_FAILED , depErr )
end
local opts = { output = values . output , title = values . title }
opts . format = values . kind
if # values . paths > 0 then


for _ , path in ipairs ( values . paths ) do
if not require ( "nupp.compiler.fs" ) . exists ( path ) then
return fail ( report . UNREADABLE , "no source file or directory named " .. path , path )
end
end
opts . sources = values . paths
end
if values . includePrivate then
settings . includePrivate = true
end
local written = { }
if asJson then
opts . written = written
opts . diagnostics = diagnostics
end
local code , output , resolved = doc . build ( "." , config , settings , opts )
if asJson then
report . write ( {
ok = code == 0 ,
diagnostics = report . diagnosticValues ( diagnostics ) ,
files = written ,
output = output or "" ,
kind = resolved or ""
} )
end

return code
end













local Doc = {} Doc.__index = Doc






























function Doc:run() 
return run ( self )
end ;Doc.__nuppInit1=function(__nuppT5, a1, a2, a3, a4, a5, a6, a7, a8) __nuppT5.kind = a1 __nuppT5.output = a2 __nuppT5.target = a3 __nuppT5.title = a4 if a5 == nil then __nuppT5.includePrivate = false else __nuppT5.includePrivate = a5 end if a6 == nil then __nuppT5.format = "text" else __nuppT5.format = a6 end if a7 == nil then __nuppT5.schema = false else __nuppT5.schema = a7 end if a8 == nil then __nuppT5.paths = {} else __nuppT5.paths = a8 end return __nuppT5 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Generate API documentation from source comments.\n\n`--kind` names what to produce. Arguments are source paths; with none, the\nmanifest's configured sources are used.\n\nExamples:\n\n    nupp doc\n    nupp doc --kind markdown -o docs/api.md\n    nupp doc --kind site --target library --output build/site",["group"]=false,["hidden"]=false,["name"]="doc",["summary"]="Generate API documentation from source comments."},["fieldCount"]=8,["fields"]={{["arity"]="required",["choices"]={"site","markdown","json","both"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--kind",["documentation"]="What to produce: site, markdown, json, or both.",["field"]="kind",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"kind"},["optional"]=true,["required"]=false,["role"]="option",["value"]="KIND"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--output",["documentation"]="Output file or directory.",["field"]="output",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"output","o"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--target",["documentation"]="Document a named manifest target.",["field"]="target",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"target"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--title",["documentation"]="Documentation title.",["field"]="title",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"title"},["optional"]=true,["required"]=false,["role"]="option",["value"]="TITLE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--include-private",["documentation"]="Include unexported, internal and private declarations.",["field"]="includePrivate",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"include-private"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select this command's report representation.",["field"]="format",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=7,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="PATH",["documentation"]="Source paths to document.",["field"]="paths",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="PATH"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="PATH",["documentation"]="Source paths to document.",["field"]="paths",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="PATH"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="0a954be7379738401fa2fa04e686f209cbde0bcd7cedadf4a55507958a98b99a",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.doc:Doc:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="doc"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Generate API documentation from source comments."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Doc?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Doc",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.doc:Doc:1",Doc,__nuppDerived) ;Doc["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Doc["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("doc")end ;Doc["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Generate API documentation from source comments.")end ;Doc["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Doc,__nuppT1[1],{ })


function Doc . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Doc } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.doc"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.doc"]=__nuppExports;return __nuppExports