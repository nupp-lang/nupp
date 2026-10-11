_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.ast\0runtime\0001") };














local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "ast" )
local cliModule = require ( "nupp.cli" )
local report = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = report . OK ,
file = { type = "string" } ,
root = {
[ "$ref" ] = "#/definitions/node" ,
description = "The tree, recovered where the parse failed. Absent when the file could not be read." ,
} ,
diagnostics = report . DIAGNOSTICS ,
} ,
required = { "ok" , "file" , "diagnostics" } ,
definitions = {
node = {
description = "A structural node, or a token with the trivia attached to it. The tree is lossless: every byte of the source is in exactly one token or one piece of trivia."

,
type = "object" ,
properties = {
tag = { type = "string" , enum = { "node" , "token" } } ,
kind = { type = "string" } ,
children = { type = "array" , items = { [ "$ref" ] = "#/definitions/node" } } ,
text = { type = "string" } ,
offset = { type = "integer" } ,
line = { type = "integer" } ,
col = { type = "integer" } ,
missing = { type = "boolean" , description = "Inserted by error recovery; not in the source." } ,
trivia = {
type = "array" ,
items = {
type = "object" ,
properties = {
kind = { type = "string" } ,
text = { type = "string" } ,
offset = { type = "integer" } ,
line = { type = "integer" } ,
col = { type = "integer" }
}
} ,
} ,
} ,
required = { "tag" , "kind" } ,
} ,
} ,
}


local function syntaxTreeValue ( cst , value ) 
if cst . isToken ( value ) then
local trivia = { }
for index = 1 , value . triviaCount do
trivia [ # trivia + 1 ] = require ( "nupp.compiler.syntax.lexer" ) . triviaRecord ( value , index )
end
return {
tag = "token" ,
kind = value . kind ,
text = value . text ,
offset = value . offset ,
line = value . line ,
col = value . col ,
missing = value . missing and true or nil ,
trivia = trivia ,
}
end
local children = { }
for _ , child in ipairs ( value ) do
children [ # children + 1 ] = syntaxTreeValue ( cst , child )
end

return { tag = "node" , kind = value . kind , children = children }
end

local function run ( options ) 
local positional = { options . file }
local paths = positional
if # paths ~= 1 then
return usageError ( "exactly one source file is required" )
end
local path = paths [ 1 ]
local fs = require ( "nupp.compiler.fs" )
local source , readErr = fs . readFile ( path )
if not source then
return report . failure (
REPORT_SCHEMA ,
{ report . fileDiagnostic ( path , readErr , "check that the path exists and is readable" ) } ,
{ file = path }
)
end
local parser = require ( "nupp.compiler.syntax.parser" )
local cst = require ( "nupp.compiler.syntax.cst" )
local result = parser . parse ( source , path )


local failed = false
for _ , err in ipairs ( result . errors ) do
if require ( "nupp.compiler.diagnostics" ) . severityOf ( err ) == "error" then
failed = true
end
end
local value = {
ok = not failed ,
file = path ,
root = syntaxTreeValue ( cst , result . root ) ,
diagnostics = report . diagnosticValues ( result . errors ) ,
}
io . write ( ( options . jsonPretty and report . encodePretty ( value ) or report . encode ( value ) ) .. "\n" )

return failed and 1 or 0
end












local Ast = {} Ast.__index = Ast










function Ast:run() 
return run ( self )
end ;Ast.__nuppInit1=function(__nuppT5, a1, a2, a3) if a1 == nil then __nuppT5.jsonPretty = false else __nuppT5.jsonPretty = a1 end if a2 == nil then __nuppT5.schema = false else __nuppT5.schema = a2 end __nuppT5.file = a3 return __nuppT5 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Dump a Nupp file's parsed syntax tree as JSON.\n\nThe lossless tree includes structural children, tokens, trivia, locations,\nand parse errors.\n\nExamples:\n\n    nupp ast src/main.nupp\n    nupp ast --json-pretty src/main.nupp",["group"]=false,["hidden"]=false,["name"]="ast",["summary"]="Dump a Nupp file's parsed syntax tree as JSON."},["fieldCount"]=3,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--json-pretty",["documentation"]="Indent the JSON instead of printing it on one line.",["field"]="jsonPretty",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"json-pretty"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file to parse.",["field"]="file",["hidden"]=false,["index"]=3,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file to parse.",["field"]="file",["hidden"]=false,["index"]=3,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="64da310c018b374c371e73e3aec535cf7145aabb812dcc095c8c86b562c19526",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.ast:Ast:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="ast"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Dump a Nupp file's parsed syntax tree as JSON."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Ast?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Ast",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.ast:Ast:1",Ast,__nuppDerived) ;Ast["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Ast["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("ast")end ;Ast["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Dump a Nupp file's parsed syntax tree as JSON.")end ;Ast["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Ast,__nuppT1[1],{ })


function Ast . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Ast } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.ast"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.ast"]=__nuppExports;return __nuppExports