_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.importc\0runtime\0001") };









local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "import-c" )
local cliModule = require ( "nupp.cli" )
local report = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = report . OK ,
output = {
type = "string" ,
description = "Where the generated module was written. Absent when nothing was generated."
} ,
diagnostics = {
type = "array" ,
items = report . DIAGNOSTIC ,
description = "Why the import failed, as errors, and what the header contained that the bindings could not represent, as warnings. A warning is not a failure."

,
} ,
bridgeOutput = { type = "string" } ,
direct = { type = "integer" } ,
bridged = { type = "integer" } ,
skipped = { type = "integer" } ,
dispositions = { type = "array" , items = { type = "object" } } ,
} ,
required = { "ok" , "diagnostics" } ,
}



local function warningDiagnostic ( header , warning ) 
local line , message = warning : match ( "^[^:]+:(%d+): (.*)$" )
return { filename = header , line = line and tonumber ( line ) or nil , severity = "warning" , msg = message or warning , }
end



local function headerModuleName ( header ) 
local base = ( header : match ( "([^/\\]+)$" ) or header ) : gsub ( "%.[^.]*$" , "" )
local name = base : lower ( ) : gsub ( "[^a-z0-9]" , "" )
if not name : match ( "^[a-z]" ) then
name = "c" .. name
end

return name
end









local function foldOutput ( path ) 
local normalized = ( path : gsub ( "\\" , "/" ) )
if normalized : sub ( 1 , 1 ) == "/" or normalized : match ( "^[A-Za-z]:/" ) then
return path
end
local parts = { }
for part in normalized : gmatch ( "[^/]+" ) do
if part == ".." and # parts > 0 and parts [ # parts ] ~= ".." then
parts [ # parts ] = nil
elseif part ~= "." then
parts [ # parts + 1 ] = part
end
end

return table . concat ( parts , "/" )
end

local function run ( options ) 
local positional = { options . header }
local paths = positional
if # paths ~= 1 then
return usageError ( "exactly one C header is required" )
end
local header = paths [ 1 ]
local asJson = options . format == "json"
local reportMod = require ( "nupp.tools.cli.report" )
local importc = require ( "nupp.compiler.cinterop.importc" )
local out = options . output and foldOutput ( options . output ) or ( headerModuleName ( header ) .. ".nupp" )
local config = require ( "nupp.tools.build.manifest" ) . load ( "." )
local envMod = require ( "nupp.compiler.project.env" )
local moduleName = envMod . moduleNameInRoots ( envMod . projectRoots ( "." , config ) , out )
if not options . inspect and not moduleName then
return usageError ( "output must be a .nupp file beneath the project root or an include root" )
end


if not options . inspect then
for segment in ( moduleName ) : gmatch ( "[^.]+" ) do
if not segment : match ( "^[a-z][a-z0-9]*$" ) then
local escaped = segment : gsub ( "%p" , "%%%0" )
local suggested = out : gsub ( escaped .. "(%.nupp)$" , headerModuleName ( segment ) .. "%1" )
local problem = ("%s names module segment %q; module segments are lowercase luacase")

: format ( out , segment )
return usageError ( suggested ~= out and problem .. ", such as " .. suggested or problem )
end
end
end
local text , warnings , details = importc . import ( header , {
module = moduleName or headerModuleName ( header ) ,
lib = options . lib ,
bridge = options . bridgeOut ~= nil ,
} )

local function diagnosticsOf ( ) 
local values = { }
for _ , warning in ipairs ( warnings ) do
values [ # values + 1 ] = warningDiagnostic ( header , warning )
end

return values
end

if not text then


if asJson then
local reason = tostring ( warnings [ 1 ] or "cannot import " .. header )
local code = reason : find ( "^cannot read " ) and report . UNREADABLE or report . TOOL_FAILED
return report . failure ( REPORT_SCHEMA , { report . runDiagnostic ( code , reason , nil , header ) } )
end
for _ , warning in ipairs ( warnings ) do
io . stderr : write ( "nupp: " .. warning .. "\n" )
end

return 1
end
if not asJson then
for _ , warning in ipairs ( warnings ) do
io . stderr : write ( "nupp: warning: " .. warning .. "\n" )
end
end
if options . inspect then
if asJson then
reportMod . write ( {
ok = true ,
diagnostics = reportMod . diagnosticValues ( diagnosticsOf ( ) ) ,
direct = details and details . direct or 0 ,
bridged = details and details . bridged or 0 ,
skipped = details and details . skipped or 0 ,
dispositions = details and details . dispositions or { } ,
} )
else
io . write (
("direct %d, bridged %d, skipped %d\n")

: format (
details and details . direct or 0 ,
details and details . bridged or 0 ,
details and details . skipped or 0
)
)
end

return 0
end





local fs = require ( "nupp.compiler.fs" )

local function write ( path , content ) 
local wrote , writeErr = fs . writeFile ( path , content )
if wrote then
return nil
end
if asJson then
local values = diagnosticsOf ( )
values [ # values + 1 ] = report . fileDiagnostic ( path , writeErr , "check that the output path is writable" )
return report . failure ( REPORT_SCHEMA , values )
end
io . stderr : write ( "nupp: " .. tostring ( writeErr ) .. "\n" )

return 1
end

local bridgeOut = options . bridgeOut
if bridgeOut and details and details . bridgeSource then
local stopped = write ( bridgeOut , details . bridgeSource )
if stopped then
return stopped
end
end


local fmt = require ( "nupp.tools.fmt" )
local env = envMod . new ( "." , { config = config } )
local formatted , formatErrors = fmt . format ( text , out , {
environment = env ,
annotations = env . annotations ,
methodParens = envMod . fmtMethodParensDefault ( env )
} )
if # formatErrors == 0 then
text = formatted
end
local stopped = write ( out , text )
if stopped then
return stopped
end
if asJson then
reportMod . write ( {
ok = true ,
output = out ,
bridgeOutput = bridgeOut and details and details . bridgeSource and bridgeOut or nil ,
diagnostics = reportMod . diagnosticValues ( diagnosticsOf ( ) ) ,
direct = details and details . direct or 0 ,
bridged = details and details . bridged or 0 ,
skipped = details and details . skipped or 0 ,
dispositions = details and details . dispositions or { } ,
} )
else
io . write ( out .. "\n" )
end

return 0
end










local ImportC = {} ImportC.__index = ImportC


























function ImportC:run() 
return run ( self )
end ;ImportC.__nuppInit1=function(__nuppT9, a1, a2, a3, a4, a5, a6, a7) __nuppT9.output = a1 __nuppT9.lib = a2 __nuppT9.bridgeOut = a3 if a4 == nil then __nuppT9.inspect = false else __nuppT9.inspect = a4 end if a5 == nil then __nuppT9.format = "text" else __nuppT9.format = a5 end if a6 == nil then __nuppT9.schema = false else __nuppT9.schema = a6 end __nuppT9.header = a7 return __nuppT9 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Generate typed Nupp bindings from a C header.\n\nExamples:\n\n    nupp import-c include/widget.h\n    nupp import-c -l widget -o src/widget.nupp include/widget.h\n    nupp import-c --inspect --json include/widget.h",["group"]=false,["hidden"]=false,["name"]="import-c",["summary"]="Generate typed Nupp bindings from a C header."},["fieldCount"]=7,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--output",["documentation"]="Write the generated module to this file.",["field"]="output",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"output","o"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--lib",["documentation"]="Name the native library loaded by the bindings.",["field"]="lib",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"lib","l"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--bridge-out",["documentation"]="Emit C wrappers for eligible static inline functions.",["field"]="bridgeOut",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"bridge-out"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FILE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--inspect",["documentation"]="Report declaration dispositions without writing output.",["field"]="inspect",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"inspect"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="HEADER",["documentation"]="C header to import.",["field"]="header",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="HEADER"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="HEADER",["documentation"]="C header to import.",["field"]="header",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="HEADER"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="0bfc6d5a4c8fdca3536be1a47ee36971cb20e99b87bcaa62c49429a9b72d15f8",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.importc:ImportC:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="import-c"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Generate typed Nupp bindings from a C header."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (ImportC?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="ImportC",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.importc:ImportC:1",ImportC,__nuppDerived) ;ImportC["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;ImportC["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("import-c")end ;ImportC["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Generate typed Nupp bindings from a C header.")end ;ImportC["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(ImportC,__nuppT1[1],{ })


function ImportC . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = ImportC } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.importc"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.importc"]=__nuppExports;return __nuppExports