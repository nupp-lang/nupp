_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








local cst = require ( "nupp.compiler.cst" )
local hash = require ( "nupp.compiler.build.hash" )
local T = require ( "nupp.compiler.types" )
local state = require ( "nupp.compiler.check.state" )

local comptimeFunction = { }






local function check ( c , helper , checkOrdinary )
local body = helper . body
if body . generics then
c . diag ( "NUPP2411" , body . generics , "generic comptime functions are not yet available" )
end
for _ , rawParam in ipairs ( body . params or { } ) do
local param = rawParam
if param . namedVararg or not param . name then
c . diag ( "NUPP2411" , rawParam , "comptime functions cannot be variadic" )
end
end

helper . comptimeFunction = true
local owner , member = nil , nil
if helper . kind == "funcStmt" then
owner , member = c . funcOwner ( helper . name )
end
local helperName = helper . kind == "localFuncStmt" and helper . name or member
if not helperName then
c . diag ( "NUPP2411" , helper . name , "comptime functions must be local or direct module members" )
checkOrdinary ( helper )
return
end

local markedName = helperName
markedName . comptimeFunction = true
helper . comptimeName = markedName . text
local helperKey = owner and owner .. "." .. markedName . text or markedName . text
if helper . kind == "funcStmt" and owner ~= c . moduleLocal then
c . diag ( "NUPP2411" , helper . name , "an exported comptime function must be a direct member of this module" )
end

c . comptimeFunctions [ helperKey ] = helper
c . comptimeFunctionDepth = c . comptimeFunctionDepth + 1
checkOrdinary ( helper )
c . comptimeFunctionDepth = c . comptimeFunctionDepth - 1

if helper . kind ~= "funcStmt" or owner ~= c . moduleLocal or not helper . comptimeSignature then
return
end

local sealedProgram = require (
"nupp.compiler.comptime"
) . sealTypeFunction ( helper , c . comptimeFunctions , helper . comptimeSignature , helper . comptimeDefinition )
local deriveNamespace = c . env and c . env . globalTypes and c . env . globalTypes [ "nupp.derive" ]
local infoType = deriveNamespace and deriveNamespace . nestedTypes and deriveNamespace . nestedTypes . Info
local resultType = deriveNamespace and deriveNamespace . nestedTypes and deriveNamespace . nestedTypes . Result
local signature = helper . comptimeSignature
local answer = signature and signature . rets and signature . rets [ 1 ]
local answerBase = answer and ( answer . origin or answer ) or nil
if answerBase == resultType then
local contract = answer . typeArgs and answer . typeArgs [ 1 ] or nil
local hasContract = contract and contract . tag == "nominal" and contract . declKind == "interface"
local isUnconstrained = contract == T . any
if # signature . params ~= 1 or signature . params [
1
] ~= infoType or # signature . rets ~= 1 or signature . vararg or not ( hasContract or isUnconstrained ) then
c . diag (
"NUPP2809" ,
helper . name ,
"a derive provider must have signature function(nupp.derive.Info): nupp.derive.Result<I>" ,
nil ,
{ help = "I must be one existing interface, or any for self-declared members" }
)
else
sealedProgram . bodyFingerprint = sealedProgram . identity
sealedProgram . identity = hash . sha256 (
table . concat (
{
"nupp.derive.provider.v1" ,
c . result . moduleName or "<chunk>" ,
markedName . text ,
sealedProgram . bodyFingerprint ,
} ,
"\0"
)
)
sealedProgram . deriveProvider = true
sealedProgram . deriveInterface = hasContract and contract or nil
sealedProgram . deriveInterfaceIdentity = hasContract and contract . id or nil
sealedProgram . providerModule = c . result . moduleName
sealedProgram . providerModuleLocal = c . moduleLocal
sealedProgram . runtimeHelpers = { }
for runtimeName , runtimeType in pairs ( c . moduleFields or { } ) do
if runtimeType and runtimeType . tag == "func" then
local moduleName = c . result . moduleName or c . moduleLocal or "<chunk>"
local descriptor = { module = moduleName , member = runtimeName , }
sealedProgram . runtimeHelpers [ moduleName .. "." .. runtimeName ] = descriptor
if c . moduleLocal then
sealedProgram . runtimeHelpers [ c . moduleLocal .. "." .. runtimeName ] = descriptor
end
end
end

local function scanRuntimeHelpers ( value )
if type ( value ) ~= "table" or cst . isToken ( value ) then
return
end
if value . kind == "call"
and value . obj
and cst . textOf ( value . obj ) : gsub ( "%s+" , "" ) == "nupp.derive.helper" then
local arguments = value . args and value . args . exprs or { }
local modulePath = arguments [ 1 ] and c . pathKey ( arguments [ 1 ] ) or nil
local memberText = arguments [
2
] and arguments [ 2 ] . kind == "string" and arguments [ 2 ] . token and arguments [ 2 ] . token . text or nil
local memberName = memberText and (
memberText : match ( '^"(.*)"$' ) or memberText : match ( "^'(.*)'$" )
) or nil
local first = modulePath and modulePath : match ( "^[^.]+" ) or nil
local holder = first and c . lookupEntry ( first ) or nil
local moduleName = holder and holder . requiredModule or (
first == c . moduleLocal and c . result . moduleName or nil
)
local helperType
if moduleName == c . result . moduleName then
helperType = c . moduleFields and c . moduleFields [ memberName ]
else
local moduleType = moduleName and c . env and c . env . resolveModule and c . env . resolveModule (
c . env ,
moduleName
) or nil
helperType = moduleType and c . fieldType ( moduleType , memberName ) or nil
end
if modulePath and moduleName and memberName and helperType and helperType . tag == "func" then
local descriptor = { module = moduleName , member = memberName }
sealedProgram . runtimeHelpers [ modulePath .. "." .. memberName ] = descriptor
sealedProgram . runtimeHelpers [ moduleName .. "." .. memberName ] = descriptor
else
c . diag ( "NUPP2809" , value , "nupp.derive.helper must name an exported runtime function" )
end
end
for _ , child in ipairs ( value ) do
scanRuntimeHelpers ( child )
end
end

scanRuntimeHelpers ( helper . body )
end
end
c . moduleExports . comptimeFunctions [ markedName . text ] = sealedProgram
end

function comptimeFunction . checkLocal (
c ,
helper ,
checkOrdinary
)
check ( c , helper , checkOrdinary )
end

function comptimeFunction . checkQualified (
c ,
helper ,
checkOrdinary
)
check ( c , helper , checkOrdinary )
end

return comptimeFunction
