_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.version\0runtime\0001") };














local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "version" )
local versionMod = require ( "nupp.tools.version" )
local cliModule = require ( "nupp.cli" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {


ok = { type = "boolean" , description = "Always true: there is no way for this to fail." } ,
version = {
type = "string" ,
description = "The release, without a leading \"v\"; a -dev suffix is a checkout between releases."
} ,
runtime = { type = "string" , description = "The LuaJIT interpreter underneath this compiler." } ,
} ,
required = { "ok" , "version" , "runtime" } ,
}

local function run ( options ) 
local positional = { }
if # positional > 0 then
return usageError ( "unexpected argument " .. positional [ 1 ] )
end
if options . format == "json" then
require ( "nupp.tools.cli.report" ) . write ( {
ok = true ,
version = versionMod . VERSION ,
runtime = versionMod . runtime ( )
} )

return 0
end
io . write ( versionMod . line ( ) .. "\n" )

return 0
end













local Version = {} Version.__index = Version







function Version:run() 
return run ( self )
end ;Version.__nuppInit1=function(__nuppT4, a1, a2) if a1 == nil then __nuppT4.format = "text" else __nuppT4.format = a1 end if a2 == nil then __nuppT4.schema = false else __nuppT4.schema = a2 end return __nuppT4 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Print the compiler version.\n\nThe text form is the single line `nupp VERSION`, which is what an install\nscript should read. `nupp --version` prints the same line.\n\nExamples:\n\n    nupp version\n    nupp --version\n    nupp version --json",["group"]=false,["hidden"]=false,["name"]="version",["summary"]="Print the compiler version."},["fieldCount"]=2,["fields"]={{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"}},["positionals"]={},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="62ed3248fb4064ba0715e19b84caa4f05556d3a09d62c563ff298863724d68bb",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.version:Version:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="version"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Print the compiler version."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Version?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Version",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.version:Version:1",Version,__nuppDerived) ;Version["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Version["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("version")end ;Version["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Print the compiler version.")end ;Version["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Version,__nuppT1[1],{ })


function Version . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Version } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.version"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.version"]=__nuppExports;return __nuppExports