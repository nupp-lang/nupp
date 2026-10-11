_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.exportc\0runtime\0001") };



local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "export-c" )
local cliModule = require ( "nupp.cli" )
local report = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = report . OK ,
output = { type = "string" } ,
target = { type = "string" } ,
declarations = { type = "array" , items = { type = "string" } } ,
diagnostics = report . DIAGNOSTICS ,
} ,
required = { "ok" , "target" , "declarations" , "diagnostics" } ,
}




local function walk ( node , visit , context ) 
if not node or require ( "nupp.compiler.syntax.cst" ) . isToken ( node ) then
return
end
visit ( node , context )
for _ , child in ipairs ( node ) do
walk ( child , visit , context )
end
end

local function diagnostic ( path , node , code , message , help ) 
local token = node and ( node . name or node [ 1 ] ) or nil
return {
filename = path ,
line = token and token . line or 1 ,
col = token and token . col or 1 ,
offset = token and token . offset or 0 ,
length = token and # ( token . text or "" ) or 1 ,
severity = "error" ,
code = code ,
msg = message ,
help = help ,
}
end

local function run ( options ) 
local positional = options . inputs
local fs = require ( "nupp.compiler.fs" )
local paths , selections = { } , { }
for _ , value in ipairs ( positional ) do
if fs . exists ( value ) then
paths [ # paths + 1 ] = value
else
selections [ # selections + 1 ] = value
end
end
if # paths == 0 or # selections == 0 then
return usageError ( "at least one source file and one selected declaration are required" )
end
local output = options . output
if not output then
return usageError ( "-o FILE is required" )
end



local function refuse ( code , message ) 
if options . format == "json" then
return report . failure ( REPORT_SCHEMA , { report . runDiagnostic ( code , message , nil , "nupp.lua" ) } , {
declarations = selections
} )
end
io . stderr : write ( require ( "nupp.tools.cli.error" ) . message ( message ) .. "\n" )

return 1
end

local manifest = require ( "nupp.tools.build.manifest" )
local config , configErr = manifest . load ( "." )
if not config then
return refuse ( report . MANIFEST , tostring ( configErr ) )
end
local target , targetErr = require ( "nupp.tools.build.tasks" ) . targetConfig ( config , options . target )
if not target then
return refuse ( report . UNKNOWN_NAME , tostring ( targetErr ) )
end
config . _target = target
local targetLayout = require ( "nupp.compiler.targetlayout" )
local layoutKey = target . layoutTarget or targetLayout . hostKey ( )
if not layoutKey then
return refuse ( report . MANIFEST , "the compiler host has no modeled C layout; configure build.layoutTarget" )
end

local envMod = require ( "nupp.compiler.project.env" )
local env = envMod . new ( "." , { config = config } )
local parser = require ( "nupp.compiler.syntax.parser" )
local checker = require ( "nupp.compiler.check" )
local allDiagnostics = { }
local types , functions , sites = { } , { } , { }



local bitfields = { }
local bitfieldFiles = { }

local function collectCdefFunction ( node , context ) 
local moduleName = context . moduleName
if node . kind == "cdefFunc" and node . name and node . cAbiSignature then
local qualified = ( moduleName and moduleName .. "." or "" ) .. node . name . text
functions [ qualified ] , sites [ qualified ] = node . cAbiSignature , node
elseif node . kind == "fieldDecl" and node . name and node . bitWidth then
bitfields [ node . name ] = node . bitWidth
bitfieldFiles [ node . name ] = context . path
end
end

for _ , path in ipairs ( paths ) do
local source , readErr = fs . readFile ( path )
if not source then
allDiagnostics [
# allDiagnostics + 1
] = report . fileDiagnostic ( path , tostring ( readErr ) , "check that the path exists and is readable" )
else
local result = parser . parse ( source , path )
for _ , one in ipairs ( result . errors ) do
allDiagnostics [ # allDiagnostics + 1 ] = one
end
if # result . errors == 0 then
local moduleName = envMod . moduleNameForPath ( env , path )
local diagnostics , _ , exports = checker . check ( result , path , env , {
moduleName = moduleName
} )
for _ , one in ipairs ( diagnostics ) do
allDiagnostics [ # allDiagnostics + 1 ] = one
end
for name , t in pairs ( exports and exports . types or { } ) do
local qualified = ( moduleName and moduleName .. "." or "" ) .. name
types [ qualified ] , sites [ qualified ] = t , exports . typeDefs [ name ]
end
walk ( result . root , collectCdefFunction , { moduleName = moduleName , path = path } )
end
end
end

local reportMod = require ( "nupp.tools.cli.report" )
local failed = false
for _ , one in ipairs ( allDiagnostics ) do
if require ( "nupp.compiler.diagnostics" ) . isFatal ( one ) then
failed = true
end
end
local cabi = require ( "nupp.compiler.cinterop.cabi" )
local aggregateDescriptions , functionSignatures = { } , { }
local described = { }

local function describe ( t , selection ) 
if described [ t ] then
return true
end
for _ , name in ipairs ( t . fieldOrder or { } ) do
local definition = t . fieldDefs and t . fieldDefs [ name ] or nil
local width = definition and bitfields [ definition . token ] or nil
if width then
allDiagnostics [
# allDiagnostics + 1
] = diagnostic (
bitfieldFiles [ definition . token ] or paths [ 1 ] ,
{ width } ,
"NUPP2203" ,
("cannot export %s to C: field %q is a bitfield, which the C layout target does not model")

: format ( selection , name ) ,
"drop the width, or keep this struct out of the exported header"
)
failed = true
return false
end
end
local description , why = cabi . aggregate ( t , layoutKey )
if not description then
local site = sites [ selection ]
allDiagnostics [
# allDiagnostics + 1
] = diagnostic (
site and site . filename or paths [ 1 ] ,
site and site . token or site ,
"NUPP2203" ,
("cannot export %s to C: %s") : format ( selection , tostring ( why ) ) ,
"select a reified struct representable by the configured layout target"
)
failed = true
return false
end
described [ t ] = true
for _ , dependency in ipairs ( description . dependencies or { } ) do
if not describe ( dependency , cabi . identity ( dependency ) ) then
return false
end
end
for _ , dependency in ipairs ( description . pointerDependencies or { } ) do
if not describe ( dependency , cabi . identity ( dependency ) ) then
return false
end
end
aggregateDescriptions [ # aggregateDescriptions + 1 ] = description

return true
end






local function pointedAt ( t ) 
while t do
if t . tag == "ptr" or t . tag == "const" or t . tag == "carray" then
t = t . elem or t . inner
elseif t . tag == "union" and t . hasNil and # ( t . members or { } ) == 2 then
local first , second = t . members [ 1 ] , t . members [ 2 ]
t = first and first . tag == "nil" and second or first
else
do break end
end
end

return t
end

for _ , selection in ipairs ( selections ) do
if types [ selection ] then
describe ( types [ selection ] , selection )
elseif functions [ selection ] then
functionSignatures [ # functionSignatures + 1 ] = functions [ selection ]
for _ , parameter in ipairs ( functions [ selection ] . params or { } ) do
local t = pointedAt ( parameter . type )
if t and t . tag == "nominal" and t . declKind == "struct" and not t . cdefName then
describe ( t , cabi . identity ( t ) )
end
end
local t = pointedAt ( functions [ selection ] . result )
if t and t . tag == "nominal" and t . declKind == "struct" and not t . cdefName then
describe ( t , cabi . identity ( t ) )
end
else
allDiagnostics [
# allDiagnostics + 1
] = diagnostic (
paths [ 1 ] ,
nil ,
"NUPP2101" ,
"selected C export does not exist: " .. selection ,
"select a module-qualified exported struct or cdef function from the named sources"
)
failed = true
end
end

local text = nil
if not failed then
local rendered , why = cabi . header ( aggregateDescriptions , functionSignatures , output )
if not rendered then
allDiagnostics [
# allDiagnostics + 1
] = diagnostic ( paths [ 1 ] , nil , "NUPP2203" , "cannot export C header: " .. tostring ( why ) )
failed = true
else
text = rendered
end
end
if text then
local written , writeErr = fs . writeFileIfChanged ( output , text )
if not written then
allDiagnostics [
# allDiagnostics + 1
] = report . fileDiagnostic ( output , tostring ( writeErr ) , "check that the output path is writable" )
failed = true
end
end

if options . format == "json" then
reportMod . write ( {
ok = not failed ,
output = not failed and output or nil ,
target = layoutKey ,
declarations = selections ,
diagnostics = reportMod . diagnosticValues ( allDiagnostics ) ,
} )
else
require ( "nupp.compiler.diagnostics" ) . report ( allDiagnostics )
if not failed then
io . write ( output .. "\n" )
end
end

return failed and 1 or 0
end










local ExportC = {} ExportC.__index = ExportC



















function ExportC:run() 
return run ( self )
end ;ExportC.__nuppInit1=function(__nuppT10, a1, a2, a3, a4, a5) __nuppT10.output = a1 __nuppT10.target = a2 if a3 == nil then __nuppT10.format = "text" else __nuppT10.format = a3 end if a4 == nil then __nuppT10.schema = false else __nuppT10.schema = a4 end __nuppT10.inputs = a5 return __nuppT10 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Export canonical C declarations for Nupp structs.\n\nExamples:\n\n    nupp export-c -o include/game.h src/game.nupp game.Position\n    nupp export-c --target library -o include/library.h src/library.nupp library.Widget\n    nupp export-c --json -o include/game.h src/game.nupp game.Position",["group"]=false,["hidden"]=false,["name"]="export-c",["summary"]="Export canonical C declarations for Nupp structs."},["fieldCount"]=5,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--output",["documentation"]="Write the generated header to this file.",["field"]="output",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"output","o"},["required"]=true,["role"]="option",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--target",["documentation"]="Use a named manifest build target.",["field"]="target",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"target"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="INPUT",["documentation"]="Source files and declarations to export.",["field"]="inputs",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=true,["role"]="positional",["value"]="INPUT"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="INPUT",["documentation"]="Source files and declarations to export.",["field"]="inputs",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=true,["role"]="positional",["value"]="INPUT"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="439940e110c2ca8f4d17314cb21d4914c52ece15dc5f816f1b928d79ac6e5b28",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.exportc:ExportC:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="export-c"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Export canonical C declarations for Nupp structs."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (ExportC?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="ExportC",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.exportc:ExportC:1",ExportC,__nuppDerived) ;ExportC["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;ExportC["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("export-c")end ;ExportC["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Export canonical C declarations for Nupp structs.")end ;ExportC["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(ExportC,__nuppT1[1],{ })


function ExportC . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = ExportC } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.exportc"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.exportc"]=__nuppExports;return __nuppExports