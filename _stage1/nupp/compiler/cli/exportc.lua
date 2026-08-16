_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);

local spec = require ( "nupp.compiler.cli.spec" )
local optionsMod = require ( "nupp.compiler.cli.options" )

local command = spec . command {
name = "export-c" ,
summary = "Export canonical C declarations for Nupp structs" ,
usage = {
"nupp export-c -o FILE [--target NAME] [--format text|json] " .. "<source.nupp>... <module.Declaration>..."
} ,
options = optionsMod . join (
{ names = { "-o" , "--output" } , value = "FILE" , key = "output" , help = "Write the generated header to FILE" } ,
{ name = "--target" , value = "NAME" , help = "Use a named manifest build target" } ,
optionsMod . format ( )
) ,
schema = {
type = "object" ,
properties = {
ok = { type = "boolean" } ,
output = { type = "string" } ,
target = { type = "string" } ,
declarations = { type = "array" , items = { type = "string" } } ,
diagnostics = require ( "nupp.compiler.cli.report" ) . DIAGNOSTICS ,
} ,
required = { "ok" , "target" , "declarations" , "diagnostics" } ,
} ,
detail = [[The selected build target supplies layoutTarget. When it has none, the
compiler host is used. Header generation itself invokes no C compiler.]] ,
}




local function walk ( node , visit , context )
if not node or require ( "nupp.compiler.cst" ) . isToken ( node ) then
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

local function run ( parsed )
local fs = require ( "nupp.compiler.fs" )
local paths , selections = { } , { }
for _ , value in ipairs ( parsed . positional ) do
if fs . exists ( value ) then
paths [ # paths + 1 ] = value
else
selections [ # selections + 1 ] = value
end
end
if # paths == 0 or # selections == 0 then
return command : usageError ( "at least one source file and one selected declaration are required" )
end
local output = parsed . values . output
if not output then
return command : usageError ( "-o FILE is required" )
end

local manifest = require ( "nupp.compiler.build.manifest" )
local config , configErr = manifest . load ( "." )
if not config then
io . stderr : write ( "nupp: " .. tostring ( configErr ) .. "\n" )
return 1
end
local target , targetErr = require ( "nupp.compiler.build.tasks" ) . targetConfig ( config , parsed . values . target )
if not target then
io . stderr : write ( "nupp: " .. tostring ( targetErr ) .. "\n" )
return 1
end
config . _target = target
local targetLayout = require ( "nupp.compiler.target_layout" )
local layoutKey = target . layoutTarget or targetLayout . hostKey ( )
if not layoutKey then
io . stderr : write ( "nupp: the compiler host has no modeled C layout; configure build.layoutTarget\n" )
return 1
end

local envMod = require ( "nupp.compiler.env" )
local env = envMod . new ( "." , { config = config } )
local parser = require ( "nupp.compiler.parser" )
local checker = require ( "nupp.compiler.check" )
local allDiagnostics , types , functions , sites = { } , { } , { } , { }
local function collectCdefFunction ( node , moduleName )
if node . kind == "cdefFunc" and node . name and node . cAbiSignature then
local qualified = ( moduleName and moduleName .. "." or "" ) .. node . name . text
functions [ qualified ] , sites [ qualified ] = node . cAbiSignature , node
end
end

for _ , path in ipairs ( paths ) do
local source , readErr = fs . readFile ( path )
if not source then
allDiagnostics [ # allDiagnostics + 1 ] = diagnostic ( path , nil , "NUPP0001" , tostring ( readErr ) )
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
walk ( result . root , collectCdefFunction , moduleName )
end
end
end

local reportMod = require ( "nupp.compiler.cli.report" )
local failed = false
for _ , one in ipairs ( allDiagnostics ) do
if reportMod . fatal ( one ) then
failed = true
end
end
local cabi = require ( "nupp.compiler.cabi" )
local aggregateDescriptions , functionSignatures = { } , { }
local described = { }
local function describe ( t , selection )
if described [ t ] then
return true
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
( "cannot export %s to C: %s" ) : format ( selection , tostring ( why ) ) ,
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

for _ , selection in ipairs ( selections ) do
if types [ selection ] then
describe ( types [ selection ] , selection )
elseif functions [ selection ] then
functionSignatures [ # functionSignatures + 1 ] = functions [ selection ]
for _ , parameter in ipairs ( functions [ selection ] . params or { } ) do
local t = parameter . type
while t and ( t . tag == "ptr" or t . tag == "const" or t . tag == "carray" ) do
t = t . elem or t . inner
end
if t and t . tag == "nominal" and t . declKind == "struct" and not t . cdefName then
describe ( t , cabi . identity ( t ) )
end
end
local t = functions [ selection ] . result
while t and ( t . tag == "ptr" or t . tag == "const" or t . tag == "carray" ) do
t = t . elem or t . inner
end
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
allDiagnostics [ # allDiagnostics + 1 ] = diagnostic ( output , nil , "NUPP0001" , tostring ( writeErr ) )
failed = true
end
end

if parsed . values . format == "json" then
reportMod . write ( {
ok = not failed ,
output = not failed and output or nil ,
target = layoutKey ,
declarations = selections ,
diagnostics = allDiagnostics ,
} )
else
require ( "nupp.compiler.diagnostics" ) . report ( allDiagnostics )
if not failed then
io . write ( output .. "\n" )
end
end

return failed and 1 or 0
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
