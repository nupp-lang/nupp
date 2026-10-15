_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.fixpoint\0runtime\0001") };











local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "fixpoint" )
local cliModule = require ( "nupp.cli" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = require ( "nupp.tools.cli.report" ) . OK ,
diagnostics = require ( "nupp.tools.cli.report" ) . DIAGNOSTICS ,
kind = {
type = "string" ,
enum = { "compiler" , "binary" } ,
description = "Which claim was checked: the compiler compiling itself from stage zero, or the packaged binary stamping another."

} ,
target = { type = "string" , description = "The manifest target that was verified." } ,
stage0 = { type = "string" , description = "The stage-zero compiler the run started from." } ,
emittedStage0 = { type = "string" , description = "Where the stage-zero bundle was written, if anywhere." } ,
bytes = { type = "integer" , description = "The size of the verified binary, for --binary." } ,
reason = { type = "string" , description = "Why it failed, in one phrase. Absent when ok is true." } ,
} ,
required = { "ok" , "kind" , "diagnostics" } ,
}

local function run ( options ) 
local positional = { }
if # positional > 0 then
return usageError ( "unexpected argument " .. positional [ 1 ] )
end
local values = options
if values . binary and values . emitStage0 then
return usageError ( "--binary verifies the packaged binary and composes no stage zero" )
end
local asJson = values . format == "json"
local project = require ( "nupp.tools.build.project" )


local result = { }
local diagnostics = { }
local collected = asJson and diagnostics or nil
local code
if values . binary then
code = project . binaryFixpoint ( "." , { result = asJson and result or nil , diagnostics = collected } )
else
code = project . fixpoint ( "." , {
emitStage0 = values . emitStage0 ,
result = asJson and result or nil ,
diagnostics = collected
} )
end
if asJson then
local report = require ( "nupp.tools.cli.report" )
result . ok = code == 0
result . kind = values . binary and "binary" or "compiler"
result . diagnostics = report . diagnosticValues ( diagnostics )
report . write ( result )
end

return code
end










local Fixpoint = {} Fixpoint.__index = Fixpoint














function Fixpoint:run() 
return run ( self )
end ;Fixpoint.__nuppInit1=function(__nuppT4, a1, a2, a3, a4) __nuppT4.emitStage0 = a1 if a2 == nil then __nuppT4.binary = false else __nuppT4.binary = a2 end if a3 == nil then __nuppT4.format = "text" else __nuppT4.format = a3 end if a4 == nil then __nuppT4.schema = false else __nuppT4.schema = a4 end return __nuppT4 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Verify a byte-identical self-hosting rebuild.\n\nExamples:\n\n    nupp fixpoint\n    nupp fixpoint --binary\n    nupp fixpoint --emit-stage0 build/stage0/nupp.lua",["group"]=false,["hidden"]=false,["name"]="fixpoint",["summary"]="Verify a byte-identical self-hosting rebuild."},["fieldCount"]=4,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--emit-stage0",["documentation"]="Write the verified stage-zero bundle here.",["field"]="emitStage0",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"emit-stage0"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--binary",["documentation"]="Verify the packaged binary instead of the compiler.",["field"]="binary",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"binary"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"}},["positionals"]={},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="b39fa1c5c07ce19040265564be5757fde889dbf2ddad7f7fb54fbe154614873c",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.fixpoint:Fixpoint:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="fixpoint"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Verify a byte-identical self-hosting rebuild."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Fixpoint?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Fixpoint",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.fixpoint:Fixpoint:1",Fixpoint,__nuppDerived) ;Fixpoint["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Fixpoint["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("fixpoint")end ;Fixpoint["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Verify a byte-identical self-hosting rebuild.")end ;Fixpoint["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Fixpoint,__nuppT1[1],{ })


function Fixpoint . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Fixpoint } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.fixpoint"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.fixpoint"]=__nuppExports;return __nuppExports