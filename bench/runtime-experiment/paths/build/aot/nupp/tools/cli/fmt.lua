_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.fmt\0runtime\0001") };














local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "fmt" )
local cliModule = require ( "nupp.cli" )

local REPORT_SCHEMA = {
type = "object" ,
description = "Which files are not formatted, and what was done about it." ,
properties = {
unformatted = {
type = "array" ,
items = { type = "string" } ,
description = "Files whose formatting differs from the formatter's. Under --write these are the files that were rewritten."


} ,
written = {
type = "boolean" ,
description = "Whether the files listed were rewritten rather than merely reported."
} ,
failed = {
type = "array" ,
description = "Files that could not be formatted at all, which is a different answer from being unformatted."
,
items = {
type = "object" ,
properties = { file = { type = "string" } , diagnostics = require ( "nupp.tools.cli.report" ) . DIAGNOSTICS } ,
required = { "file" , "diagnostics" } ,
} ,
} ,
ok = {
type = "boolean" ,
description = "True when nothing was left unformatted and nothing failed. False always comes with a coded error in `diagnostics`."

} ,
diagnostics = {
type = "array" ,
description = "Every failure's diagnostics, and one NUPP4002 for each file a --check or project run found unformatted."
,
items = require ( "nupp.tools.cli.report" ) . DIAGNOSTIC ,
} ,
} ,
required = { "ok" , "diagnostics" , "unformatted" , "written" , "failed" } ,
}

local function run ( options ) 
local positional = options . files
local values = options
local write , asking = values . write , values . check
if write and asking then
return usageError (
"--write and --check ask for opposite things: one fixes the formatting, the other reports it"
)
end
local width = 120
if values . width then
local given = tonumber ( values . width )
if not given or given < 20 or given ~= math . floor ( given ) then
return usageError ( "--width takes a whole number of columns, at least 20, not " .. values . width )
end
width = math . floor ( given )
end
local fs = require ( "nupp.compiler.fs" )
local fmt = require ( "nupp.tools.fmt" )
local envMod = require ( "nupp.compiler.project.env" )
local diagnosticMod = require ( "nupp.compiler.diagnostics" )
local reportMod = require ( "nupp.tools.cli.report" )
local asJson = values . format == "json"
local env = envMod . new ( "." )



local methodParens = not values . noMethodParens and envMod . fmtMethodParensDefault ( env )



local currentPath = ""
local formatter = fmt . new ( {
environment = env ,
annotations = env . annotations ,
resolveAnnotation = function ( name ) 
return env . resolveProjectAnnotation ( env , currentPath , name )
end ,
methodParens = methodParens ,
width = width ,
} )
local paths = positional
local wholeProject = # paths == 0



local reporting = asking or wholeProject or asJson
local failures = { }
local problems = { }

local function finish ( code , unformatted ) 
if asJson then
local diagnostics = { }
for _ , failure in ipairs ( failures ) do
for _ , value in ipairs ( failure . diagnostics ) do
diagnostics [ # diagnostics + 1 ] = value
end
end


if not write then
for _ , path in ipairs ( unformatted ) do
problems [
# problems + 1
] = {
filename = path ,
code = "NUPP4002" ,
msg = path .. " is not formatted" ,
help = "run nupp fmt --write " .. path ,
}
end
end
for _ , value in ipairs ( reportMod . diagnosticValues ( problems ) ) do
diagnostics [ # diagnostics + 1 ] = value
end
reportMod . write ( {
ok = code == 0 ,
diagnostics = diagnostics ,
written = write and true or false ,
unformatted = unformatted ,
failed = failures
} )
end

return code
end

if wholeProject then
paths = envMod . listSourceFiles ( env )
if # paths == 0 then

if asJson then
problems [ # problems + 1 ] = reportMod . runDiagnostic ( reportMod . MANIFEST , "no source files found under the project's include roots" , nil , "nupp.lua" )
else
io . stderr : write ( "nupp: no source files found under the project's include roots\n" )
end
return finish ( 1 , { } )
end
end


















local settled = reporting and envMod . openStore ( env , "formatStore" , "formatStoreOpened" , "format.buf" , {
"nupp.tools.fmt" ,
"nupp.tools.fmt.imports" ,
"nupp.compiler.check"
} ) or nil
local textNeeded = write and true or false
local hashMod = require ( "nupp.compiler.hash" )
local digest = env . compilerServices and env . compilerServices . hash and env . compilerServices . hash . digest
or hashMod . digest
local optionsKey = nil

local function verdictKey ( path , source ) 
if not optionsKey then
optionsKey = digest (
tostring (
methodParens
) .. "\0" .. tostring ( width ) .. "\0" .. envMod . annotationKey ( env ) .. "\0" .. fmt . importsKey ( env )
)
end

return digest ( optionsKey .. "\0" .. path .. "\0" .. source )
end

local failed = false
local unformatted = { }



local function fileFailure ( path , err , help ) 
local collected = asJson and { } or nil
reportMod . fileFailure ( path , err , help , collected )
if collected then
failures [ # failures + 1 ] = { file = path , diagnostics = reportMod . diagnosticValues ( collected ) }
end
end

for _ , path in ipairs ( paths ) do
local source , err = fs . readFile ( path )


local verdict = source and settled and settled . get ( verdictKey ( path , source ) ) or nil
if not source then
fileFailure ( path , err , "check that the path exists and is readable" )
failed = true
elseif verdict == "same" then



elseif not textNeeded and verdict == "differs" then
unformatted [ # unformatted + 1 ] = path
else
currentPath = path
local formatted , errors = formatter : format ( source , path )



if settled and # errors == 0 then
settled . put ( verdictKey ( path , source ) , formatted == source and "same" or "differs" )
end
if # errors > 0 then


if asJson then
failures [ # failures + 1 ] = { file = path , diagnostics = reportMod . diagnosticValues ( errors ) }
else
diagnosticMod . report ( errors )
end
failed = true
elseif write then
if formatted ~= source then




local wrote , writeErr = fs . writeFile ( path , formatted )
if not wrote then
fileFailure ( path , tostring ( writeErr ) , "check that the path is writable" )
failed = true
else
unformatted [ # unformatted + 1 ] = path
end
end
elseif reporting then
if formatted ~= source then
unformatted [ # unformatted + 1 ] = path
end
else



io . write ( formatted )
end
end
end
envMod . persist ( env )
if reporting then
if # unformatted > 0 and not asJson then
io . write ( table . concat ( unformatted , "\n" ) , "\n" )
end


if not write and # unformatted > 0 then
failed = true
end
end

return finish ( failed and 1 or 0 , unformatted )
end













local Fmt = {} Fmt.__index = Fmt

























function Fmt:run() 
return run ( self )
end ;Fmt.__nuppInit1=function(__nuppT8, a1, a2, a3, a4, a5, a6, a7) if a1 == nil then __nuppT8.write = false else __nuppT8.write = a1 end if a2 == nil then __nuppT8.check = false else __nuppT8.check = a2 end if a3 == nil then __nuppT8.noMethodParens = false else __nuppT8.noMethodParens = a3 end __nuppT8.width = a4 if a5 == nil then __nuppT8.format = "text" else __nuppT8.format = a5 end if a6 == nil then __nuppT8.schema = false else __nuppT8.schema = a6 end if a7 == nil then __nuppT8.files = {} else __nuppT8.files = a7 end return __nuppT8 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Format Nupp source.\n\nWith named files, formats each to stdout or rewrites it. With none, reports\nfiles in the project which are not formatted.\n\nExamples:\n\n    nupp fmt --check\n    nupp fmt --write src/main.nupp\n    nupp fmt --width 100 src/main.nupp",["group"]=false,["hidden"]=false,["name"]="fmt",["summary"]="Format Nupp source."},["fieldCount"]=7,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--write",["documentation"]="Rewrite files in place instead of writing to stdout.",["field"]="write",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"write","w"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--check",["documentation"]="Report files which are not formatted and write nothing.",["field"]="check",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"check"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--no-method-parens",["documentation"]="Preserve method-call sugar without parentheses.",["field"]="noMethodParens",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"no-method-parens"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="integer",["destination"]="integer",["display"]="--width",["documentation"]="Code column after which a line may break.",["field"]="width",["hidden"]=false,["index"]=4,["invalid"]="width must be a whole number",["long"]=true,["names"]={"width"},["optional"]=true,["required"]=false,["role"]="option",["value"]="N"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source files to format.",["field"]="files",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source files to format.",["field"]="files",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="69e2cce4cf33e2609b2e38b732428bf5c015c43cb22cc50000cfea9f66d8ee30",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.fmt:Fmt:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="fmt"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Format Nupp source."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Fmt?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Fmt",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.fmt:Fmt:1",Fmt,__nuppDerived) ;Fmt["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Fmt["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("fmt")end ;Fmt["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Format Nupp source.")end ;Fmt["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Fmt,__nuppT1[1],{ })


function Fmt . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Fmt } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.fmt"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.fmt"]=__nuppExports;return __nuppExports