_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.lints\0runtime\0001") };









local ansi = require ( "nupp.cli" )
local cliModule = require ( "nupp.cli" )
local report = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = report . OK ,
diagnostics = report . DIAGNOSTICS ,
lints = {
type = "array" ,
items = {
type = "object" ,
properties = {
name = { type = "string" , description = "What an @allow suppression writes." } ,
code = {
type = "string" ,
description = "The diagnostic code it reports under, which survives the name being reconsidered."

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
description = "The level it runs at when a project says nothing."
} ,
moved = { type = "boolean" , description = "Whether this project moved it off its default." } ,
summary = { type = "string" } ,
} ,
required = { "name" , "code" , "category" , "level" , "default" , "moved" , "summary" } ,
} ,
} ,
} ,
required = { "ok" , "lints" } ,
}



local LEVEL_SEVERITY = { error = "error" , warning = "warning" , note = "note" , }



local function levelPaint ( style , level ) 
local severity = LEVEL_SEVERITY [ level ]

return severity ~= nil and ansi . severity ( style , severity ) or style . faint
end

local function run ( options ) 
local lints = require ( "nupp.compiler.lints" )
local project = require ( "nupp.tools.build.project" )




local config = nil
if require ( "nupp.compiler.fs" ) . exists ( "nupp.lua" ) then
local loaded , err = project . loadManifest ( "." )
if not loaded then
if options . format == "json" then
return report . failure ( REPORT_SCHEMA , {
report . runDiagnostic ( report . MANIFEST , tostring ( err ) , nil , "nupp.lua" )
} )
end
io . stderr : write ( tostring ( err ) .. "\n" )
return 1
end
config = loaded
end
local lintConfig = config and config . lints or nil
local style = ansi . style ( io . stdout )
local rows = { }
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
end
table . sort ( rows , function ( a , b ) 
return a . name < b . name
end )
if options . format == "json" then
report . write ( { ok = true , lints = rows } )
return 0
end
local cells = { }
for _ , row in ipairs ( rows ) do


local note = nil
if row . moved then
note = (" (default %s)") : format ( row . default )
end
cells [
# cells + 1
] = {
cliModule . paintedCell ( row . name , style . strong ) ,
cliModule . paintedCell ( row . category , style . faint ) ,
cliModule . paintedCell ( row . level , levelPaint ( style , row . level ) ) ,
_G.setmetatable({ text =  row . summary ,  note =  note }, cliModule.Cell) ,
}
end
cliModule . writeTable (
io . stdout ,
{
columns = {
{ heading = "lint" } ,
{ heading = "category" } ,
{ heading = "level" , minimumWidth = 7 } ,
{ heading = "summary" } ,
} ,
rows = cells ,
style = style ,
}
)

return 0
end











local Lints = {} Lints.__index = Lints







function Lints:run() 
return run ( self )
end ;Lints.__nuppInit1=function(__nuppT6, a1, a2) if a1 == nil then __nuppT6.format = "text" else __nuppT6.format = a1 end if a2 == nil then __nuppT6.schema = false else __nuppT6.schema = a2 end return __nuppT6 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="List the lints and the level each runs at.\n\nLevels are off, note, warning and error; only an error stops a build.\n\nExamples:\n\n    nupp lints\n    nupp lints --json",["group"]=false,["hidden"]=false,["name"]="lints",["summary"]="List the lints and the level each runs at."},["fieldCount"]=2,["fields"]={{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"}},["positionals"]={},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="58061b7ee6571cd1fc2658d005fccf640a31bc70086270602bd30e6e83e4cbf2",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lints:Lints:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="lints"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="List the lints and the level each runs at."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Lints?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Lints",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lints:Lints:1",Lints,__nuppDerived) ;Lints["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Lints["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("lints")end ;Lints["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("List the lints and the level each runs at.")end ;Lints["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Lints,__nuppT1[1],{ })


function Lints . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Lints } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.lints"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.lints"]=__nuppExports;return __nuppExports