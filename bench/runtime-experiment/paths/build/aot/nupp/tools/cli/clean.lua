_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.clean\0runtime\0001") };









local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "clean" )
local cliModule = require ( "nupp.cli" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
removed = {
type = "array" ,
items = { type = "string" } ,
description = "The output paths, removed unless dryRun is set, in which case these are the paths that would be."

} ,
dryRun = { type = "boolean" } ,
ok = require ( "nupp.tools.cli.report" ) . OK ,
diagnostics = require ( "nupp.tools.cli.report" ) . DIAGNOSTICS ,
} ,
required = { "ok" , "removed" , "dryRun" , "diagnostics" } ,
}

local function run ( options ) 
local positional = { }
if # positional > 0 then
return usageError ( "unexpected argument " .. positional [ 1 ] )
end
local values = options
local asJson = values . format == "json"
local dryRun = values . dryRun and true or false
if values . platform and not values . target then
return usageError ( "--platform requires --target" )
end
local project = require ( "nupp.tools.build.project" )
local removed = { }
local diagnostics = { }
local code = project . clean ( "." , {
target = values . target ,
platform = values . platform ,
dryRun = values . dryRun ,
removed = asJson and removed or nil ,
diagnostics = asJson and diagnostics or nil
} )
if asJson then
local report = require ( "nupp.tools.cli.report" )
report . write ( {
ok = code == 0 ,
removed = removed ,
dryRun = dryRun ,
diagnostics = report . diagnosticValues ( diagnostics )
} )
end

return code
end













local Clean = {} Clean.__index = Clean


















function Clean:run() 
return run ( self )
end ;Clean.__nuppInit1=function(__nuppT4, a1, a2, a3, a4, a5) __nuppT4.target = a1 __nuppT4.platform = a2 if a3 == nil then __nuppT4.dryRun = false else __nuppT4.dryRun = a3 end if a4 == nil then __nuppT4.format = "text" else __nuppT4.format = a4 end if a5 == nil then __nuppT4.schema = false else __nuppT4.schema = a5 end return __nuppT4 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Remove build outputs configured in nupp.lua.\n\nWith no target, cleans every configured target output. Paths outside the\nproject and paths that resolve to the project root are always rejected.\n\nExamples:\n\n    nupp clean --dry-run\n    nupp clean\n    nupp clean --target app",["group"]=false,["hidden"]=false,["name"]="clean",["summary"]="Remove build outputs configured in nupp.lua."},["fieldCount"]=5,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--target",["documentation"]="Clean only the named build target.",["field"]="target",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"target"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--platform",["documentation"]="Clean one configured binary platform, or all.",["field"]="platform",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"platform"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--dry-run",["documentation"]="Print output paths without removing them.",["field"]="dryRun",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"dry-run"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"}},["positionals"]={},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="d07c04a35fc320ed57ef86a8ac12a47a5bf4478f343c18d3dc9c29c1ed932282",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.clean:Clean:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="clean"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Remove build outputs configured in nupp.lua."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Clean?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Clean",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.clean:Clean:1",Clean,__nuppDerived) ;Clean["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Clean["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("clean")end ;Clean["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Remove build outputs configured in nupp.lua.")end ;Clean["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Clean,__nuppT1[1],{ })


function Clean . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Clean } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.clean"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.clean"]=__nuppExports;return __nuppExports