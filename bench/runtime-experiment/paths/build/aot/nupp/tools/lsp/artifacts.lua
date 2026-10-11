_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






















local listing = require ( "nupp.tools.bytecodelisting" )
local text = require ( "nupp.tools.lsp.text" )
local tree = require ( "nupp.tools.lsp.tree" )
local wire = require ( "nupp.tools.lsp.wire" )

local uriToPath = text . uriToPath
local offsetAtPosition = text . offsetAtPosition
local spanRange = text . spanRange

local artifacts = { }




















artifacts . KINDS = { "lua" , "bytecode" }

const LABELS = { lua = "Generated Lua" , bytecode = "Bytecode" , }
const LANGUAGES = { lua = "lua" , bytecode = "nupp-bytecode" , }



const SCOPES = { lua = "module" , bytecode = "module" , }







local function unavailable ( kind , reason , detail ) 
return {
kind = kind ,
available = false ,
label = LABELS [ kind ] or kind ,
unavailable = { reason = reason , detail = detail } ,
}
end

function artifacts . install ( s ) 



local inspectCommand = nil


local function documentFor ( params ) 
local uri = params and params . textDocument and params . textDocument . uri
local doc = uri and s . documents [ uri ] or nil
if not doc then
return uri , nil , nil
end
local offset = params . position and offsetAtPosition ( doc . text , params . position ) or nil

return uri , doc , offset
end







local function lower ( doc , path , optLevel , boundary ) 
local collected = { }
local compile = require ( "nupp.tools.cli.compile" )
local env = require ( "nupp.compiler.project.env" ) . new ( s . currentRoot or "." )
local settings = compile . settings ( { optLevel = tostring ( optLevel ) } , collected )
settings . bytecodeBoundary = boundary
local code , _ , generated = compile . module ( path , env , settings , nil , doc . text )

return code , collected , generated
end


local function firstProblem ( collected ) 
for _ , diagnostic in ipairs ( collected ) do


local message = diagnostic . message or diagnostic . msg
if message then
local where = diagnostic . line and ( ":" .. tostring ( diagnostic . line ) ) or ""
return ( diagnostic . code or "error" ) .. where .. ": " .. tostring ( message )
end
end

return nil
end

local function luaArtifact ( doc , path , optLevel ) 
local code , collected , generated = lower ( doc , path , optLevel )



local problem = nil
if not code and generated then
code = generated
problem = { reason = "not-loaded" , detail = firstProblem ( collected ) or "the generated Lua does not load" }
end
if not code then
return unavailable ( "lua" , "not-lowered" , firstProblem ( collected ) or "the file does not compile" )
end

return {
problem = problem ,
kind = "lua" ,
available = true ,
label = LABELS . lua ,
languageId = LANGUAGES . lua ,
text = code ,



mapping = { kind = "line-identity" } ,
metadata = { optLevel = optLevel , } ,
summary = { lines = select ( 2 , code : gsub ( "\n" , "\n" ) ) , } ,
}
end

local function bytecodeArtifact ( doc , path , optLevel ) 
if not pcall ( require , "jit.util" ) or not pcall ( require , "jit.bc" ) then
return ( { kind = "bytecode" , available = false , label = LABELS [ "bytecode" ] or "bytecode" , unavailable = { reason = "unsupported-host" , detail = "bytecode needs LuaJIT's jit.util and jit.bc" } , } )
end



local code , collected = lower ( doc , path , optLevel , listing . BOUNDARY )
if not code then
return unavailable ( "bytecode" , "not-lowered" , firstProblem ( collected ) or "the file does not compile" )
end
local chunk , loadErr = loadstring ( code , "@" .. path )
if not chunk then
return unavailable ( "bytecode" , "not-loaded" , tostring ( loadErr ) )
end
local analysis = require ( "nupp.tools.tracebytecode" ) . analyze ( chunk )
local boundaryFunction , boundaryPc = listing . boundary ( analysis . functions )


local rendered , mappings = listing . aligned ( analysis . functions , doc . text , {
check = true ,
boundaryFunction = boundaryFunction ,
boundaryPc = boundaryPc ,
} )
local entries = wire . array ( { } )
for _ , mapping in ipairs ( mappings ) do
entries [ # entries + 1 ] = mapping
end

return {
kind = "bytecode" ,
available = true ,
label = LABELS . bytecode ,
languageId = LANGUAGES . bytecode ,
text = rendered ,



mapping = { kind = "lines-collapsible" , entries = entries } ,
metadata = { optLevel = optLevel , fingerprint = analysis . bytecodeFingerprint , } ,
summary = {
blockers = analysis . blockers ,
mustBlockers = analysis . mustBlockers ,
risks = analysis . risks ,
functions = # analysis . functions ,
} ,
}
end

const BUILDERS = { lua = luaArtifact , bytecode = bytecodeArtifact , }






local function discover ( params ) 
local uri , doc , offset = documentFor ( params )
if not doc then
return { artifacts = wire . array ( { } ) }
end
local analysis = doc . result and doc . result . traceAnalysis or nil
local selected , from , to = tree . functionAt ( analysis and analysis . functions or nil , offset )
local aotSymbol = nil
local aotSource = nil
if selected ~= nil and selected . body ~= nil and selected . body . aotRequired == true then
local fs = require ( "nupp.compiler.fs" )
local path = uriToPath ( uri )
local root = fs . absolute ( s . useRoot ( path ) )
local absolute = fs . absolute ( path )
aotSource = absolute : sub ( 1 , # root + 1 ) == root .. "/" and absolute : sub ( # root + 2 ) or absolute
local name = selected . node and selected . node . name and selected . node . name . text or selected . traceName
local symbol = require ( "nupp.compiler.aot.scalar" ) . privateSymbol ( name )
aotSymbol = symbol
end
local out = wire . array ( { } )
for _ , kind in ipairs ( artifacts . KINDS ) do
out [ # out + 1 ] = { kind = kind , label = LABELS [ kind ] , languageId = LANGUAGES [ kind ] , scope = SCOPES [ kind ] , }
end

return {
artifacts = out ,
[ "function" ] = selected
and {
name = selected . traceName ,
aotSymbol = aotSymbol ,
aotSource = aotSource ,
range = from and to and spanRange ( doc . text , from , to ) or nil ,
}
or nil ,
}
end

local function resolve ( params ) 
local uri , doc = documentFor ( params )
local kind = params and params . kind
if type ( kind ) ~= "string" or not BUILDERS [ kind ] then
return unavailable ( tostring ( kind ) , "unknown-kind" , "this server produces lua and bytecode" )
end
if not doc then
return ( { kind = kind , available = false , label = LABELS [ kind ] or kind , unavailable = { reason = "no-document" , detail = "the document is not open on this server" } , } )
end
local path = uriToPath ( uri )
s . useRoot ( path )
local requested = params and params . optLevel
local optLevel = requested == nil and 0 or type ( requested ) == "number" and requested or nil
if optLevel == nil or optLevel ~= math . floor ( optLevel ) or optLevel < 0 or optLevel > 2 then
return ( { kind = kind , available = false , label = LABELS [ kind ] or kind , unavailable = { reason = "unknown-opt-level" , detail = "optimization levels are 0, 1 and 2" } , } )
end
local built = assert ( BUILDERS [ kind ] ) ( doc , path , optLevel )
built . uri = uri
built . version = doc . version


built . id = ("%s|%s|O%d") : format ( uri , kind , optLevel )

return built
end







local function lenses ( params ) 
local uri , doc = documentFor ( params )
local out = wire . array ( { } )
if not doc or inspectCommand == nil then
return out
end
local analysis = doc . result and doc . result . traceAnalysis or nil
for _ , info in ipairs ( analysis and analysis . functions or { } ) do
local from , to = tree . nodeBounds ( info . node )
if from and to then
local range = spanRange ( doc . text , from , to )
out [
# out + 1
] = {
range = { start = range . start , [ "end" ] = range . start } ,
command = {
title = "Inspect" ,
command = inspectCommand ,
arguments = wire . array ( {
{ uri = uri , name = info . traceName , position = range . start , range = range , } ,
} ) ,
} ,
}
end
end

return out
end

local function useInspectCommand ( command ) 
inspectCommand = command
end

return { discover = discover , resolve = resolve , lenses = lenses , useInspectCommand = useInspectCommand , }
end

local __nuppExportValue= artifacts ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.lsp.artifacts"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.lsp.artifacts"]=__nuppExports;return __nuppExports