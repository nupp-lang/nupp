_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
















local ansi = require ( "nupp.cli" )

local cli = { }

local root = require ( "nupp.tools.cli.root" )

local APPLICATION = nil



local function application ( ) 
if APPLICATION ~= nil then
return APPLICATION
end
APPLICATION = ansi . application ( _G.nupp.__reflect.ensure( root . Root ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="nupp"},{["kind"]="value",["name"]="group",["value"]=true}},["name"]="cli"}},["fields"]={{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=2,["writable"]=true}},["fingerprint"]="58757989116aabe4b0a82325c69bddc10c9a10fd4d73b8eb95ed37dc9d4c6909",["kind"]="record",["name"]="Root",["qualifiedName"]="Root",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="nupp"},{["kind"]="value",["name"]="group",["value"]=true}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.root:Root:1",["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=2,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=2}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.root",["name"]="Root",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=6,["write"]=6},{["name"]="cliName",["read"]=11,["write"]=11},{["name"]="cliSummary",["read"]=11,["write"]=11},{["name"]="fromCLI",["read"]=13,["write"]=13},{["name"]="subcommands",["read"]=21,["write"]=21}},["supertypes"]={24},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=4,["parameters"]={{["mode"]="plain",["name"]="",["type"]=1}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=3}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=9,["parameters"]={},["returnPack"]=10,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=8,["kind"]="array"},{["kind"]="string"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=9,["parameters"]={},["returnPack"]=12,["returns"]={8},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=8}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=10,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=7}},["returnPack"]=20,["returns"]={14,16},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={15,1}},{["kind"]="nil"},{["kind"]="union",["members"]={15,17}},{["fields"]={{["name"]="destination",["read"]=18,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=18,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=19,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=8,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=8,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=18,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=18,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={15,8}},{["kind"]="union",["members"]={3,15}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=14},{["mode"]="plain",["type"]=16}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=9,["parameters"]={},["returnPack"]=28,["returns"]={22},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=23,["kind"]="array"},{["kind"]="typeobject",["of"]=24},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=25,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=25}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=27,["parameters"]={{["mode"]="plain",["name"]="",["type"]=26}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=24,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=26}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=22}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.root\0runtime\0001",["24"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) , {
name = "nupp" ,
version = require ( "nupp.tools.version" ) . line ( ) ,
width = 79 ,
indent = "  " ,
labelLimit = 20 ,
} )

return APPLICATION
end

local function requestsSchema ( subject , argv ) 
if subject == nil then
return false
end
local schema = ansi . schema ( subject )
if schema == nil then
return false
end
local arity = { }
local fields = { }
local patterns = { }
for _ , field in ipairs ( schema . fields ) do
if field . role == "option" then
for _ , name in ipairs ( field . names ) do
fields [ name ] = field
arity [ name ] = field . constants [ name ] ~= nil and ansi . none or field . arity
end
if field . pattern ~= nil then
patterns [ # patterns + 1 ] = { pattern = field . pattern , key = field . matchKey }
end
end
end
local stream = ansi . optParser ( argv , {
arity = arity ,
patterns = patterns ,
stopAtFirstArgument = schema . stopAtFirstArgument ,
} )
while true do
local kind = stream : next ( )
if kind == nil then
return false
end
local option = kind == ansi . shortOption or kind == ansi . longOption
local field = option and not stream : pattern ( ) and fields [ stream : key ( ) ] or nil
if field ~= nil and field . field == "schema" and stream : value ( ) == nil then
return true
end
end
end

local function child ( parent , name ) 
if name == nil or parent . subcommands == nil then
return nil
end
for _ , subject in ipairs ( parent . subcommands ( ) ) do
if subject . cliName ( ) == name then
return subject
end
for _ , alias in ipairs ( subject . cliAliases ( ) ) do
if alias == name then
return subject
end
end
end

return nil
end

local function selectCommand ( argv ) 
local subject = root . Root
local index = 1
while index <= # argv do
local nextSubject = child ( subject , argv [ index ] )
if nextSubject == nil then
do break end
end
subject = nextSubject
index = index + 1
end

return subject , index
end


local function writeSchema ( argv ) 
local subject , argumentStart = selectCommand ( argv )
if subject . cliName ( ) == "lsp" and argv [ argumentStart ] == "--schema" then
return require (
"nupp.tools.cli.error"
) . forCommand ( "lsp" ) ( "--schema answers for one operation: nupp lsp <operation> --schema" )
end
local schema = subject . reportSchema and subject . reportSchema ( ) or nil
if schema == nil then
return nil
end
local arguments = { }
for index = argumentStart , # argv do
arguments [ # arguments + 1 ] = argv [ index ]
end
if requestsSchema ( subject , arguments ) then
require ( "nupp.tools.cli.report" ) . write ( schema )
return 0
end

return nil
end















local function warnStaleDeclarations ( ) 
local stale = require ( "nupp.compiler.bundled" ) . staleDeclarations ( )
if # stale == 0 then
return
end
local style = ansi . style ( io . stderr )
local lines = {
ansi . severity ( style , "warning" ) ( "nupp:" ) .. " the compiler is using declarations older than this checkout:" ,
}
for _ , relative in ipairs ( stale ) do
lines [ # lines + 1 ] = "  " .. relative
end
lines [ # lines + 1 ] = "A diagnostic above may describe an interface src/ no longer has."
lines [ # lines + 1 ] = "Run the build again; it has already refreshed them."
io . stderr : write ( table . concat ( lines , "\n" ) .. "\n" )
end









const JIT_DEFAULT_COMMANDS = { bench = true , run = true , task = true }






local function residentCommand ( argv ) 
local name = argv [ 1 ]
if JIT_DEFAULT_COMMANDS [ name ] then
return true
end

local operation = argv [ 2 ]

return name == "lsp" and ( operation == nil or operation == "serve" or operation : sub ( 1 , 1 ) == "-" )
end



















local function tuneJitFor ( argv ) 
if residentCommand ( argv ) or os . getenv ( "NUPP_JIT_DEFAULT" ) then
return
end
local override = os . getenv ( "NUPP_JIT_TUNE" )


if not override then
pcall ( jit . opt . start , "hotexit=200" , "hotloop=1000" )

return
end
local flags = { }
for flag in override : gmatch ( "[^,]+" ) do
flags [ # flags + 1 ] = flag
end
pcall ( function ( ) 
jit . opt . start ( unpack ( flags ) )
end )
end

function cli . main ( argv ) 
local name = argv [ 1 ]



if name == "--version" then
local mapped = { "version" }
for index = 2 , # argv do
mapped [ # mapped + 1 ] = argv [ index ]
end
argv = mapped
name = "version"
end
if name == "__comptime-worker" then
local rest = { }
for index = 2 , # argv do
rest [ # rest + 1 ] = argv [ index ]
end

local worker = require ( "nupp.compiler.comptime.worker" )

return worker . main ( rest )
elseif name == "__comptime-worker-service" then
local worker = require ( "nupp.compiler.comptime.worker" )

return worker . serviceMain ( )
elseif name == "__generator-worker" then
local rest = { }
for index = 2 , # argv do
rest [ # rest + 1 ] = argv [ index ]
end
local worker = require ( "nupp.compiler.comptime.generatorworker" )

return worker . main ( rest )
elseif name == "__parallel-check-service" then



tuneJitFor ( { "check" } )
local service = require ( "nupp.tools.build.parallelcheckservice" )

return service . main ( )
elseif name == "__lsp-reader" then
local server = require ( "nupp.tools.lsp" )

return server . readerMain ( )
end
local schemaStatus = writeSchema ( argv )
if schemaStatus ~= nil then
return schemaStatus
end
tuneJitFor ( argv )
local status = application ( ) : main ( argv )
warnStaleDeclarations ( )

return status
end


function cli . names ( ) 
local names = { }
for _ , subject in ipairs ( root . Root . subcommands ( ) ) do
local commandType = subject
names [ # names + 1 ] = commandType . cliName ( )
end

return names
end


function cli . completion ( shell ) 
return application ( ) : completion ( shell )
end

local __nuppExportValue= cli ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli"]=__nuppExports;return __nuppExports