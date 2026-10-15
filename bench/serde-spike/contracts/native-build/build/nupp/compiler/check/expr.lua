_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()














local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local narrowing = require ( "nupp.compiler.types.narrowing" )
local cst = require ( "nupp.compiler.syntax.cst" )
local mutationSummaries = require ( "nupp.compiler.check.mutation" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local operators = require ( "nupp.compiler.check.operators" )
local index = require ( "nupp.compiler.check.index" )
local state = require ( "nupp.compiler.check.state" )
local callexpr = require ( "nupp.compiler.check.callexpr" )
local comptime = require (
"nupp.compiler.comptime"
)
local materializeProviders = require ( "nupp.compiler.comptime.materialize.providers" )



local materializeIR = require ( "nupp.compiler.comptime.materialize.ir" )



local stable = require ( "nupp.compiler.stable" )
local fixedWidth = require ( "nupp.compiler.types.fixedwidth" )
local runtimeSurface = require ( "nupp.compiler.runtimesurface" )
local predicate = require ( "nupp.compiler.types.predicate" )

local expr = { }

local isA = relations . isA
local rawType = T . unwrapOwnership
local subtract = narrowing . subtract
















local EXPANDS = { call = true , methodCall = true , safeCall = true , vararg = true }

expr . EXPANDS = EXPANDS





function expr . install ( c ) 



local expectedShortfns = { }





local function captureProblem ( captured ) 
local pending = { captured }
local seen = { }
while # pending > 0 do
local present = table . remove ( pending )
if not seen [ present . id ] then
seen [ present . id ] = true
if present . tag == "affine" then
return "an affine owner"
elseif present . tag == "borrowed" or present . tag == "pinned" then
return "a borrow tied to this Lua state"
elseif present . tag == "const" then
pending [ # pending + 1 ] = present . inner
else
local raw = rawType ( present )
if raw . tag == "func" then
return "a function"
elseif raw == T . thread or raw . tag == "protocolThread" then
return "a thread"
elseif raw == T . userdata then
return "userdata"
elseif raw == T . cdata or raw == T . cstring then
return "cdata"
elseif raw == T . voidptr or raw . tag == "ptr" or raw . tag == "carray" then
return "a C pointer"
elseif raw . tag == "array" then
pending [ # pending + 1 ] = raw . elem
elseif raw . tag == "tuple" then
for _ , member in ipairs ( raw . elems ) do
pending [ # pending + 1 ] = member
end
elseif raw . tag == "union" or raw . tag == "intersection" then
for _ , member in ipairs ( raw . members ) do
pending [ # pending + 1 ] = member
end
elseif raw . tag == "shape" then
for _ , field in ipairs ( raw . fields ) do
if field . read ~= nil then
pending [ # pending + 1 ] = field . read
end
end
end
end
end
end

return nil
end






local function inferSendableLiteral ( node , infer ) 
if not node . sendableContext then
return infer ( )
end
if node . sendableCaptures then
return T . withSendable ( infer ( ) )
end
local watch = { depth = ( c . scope . depth or 0 ) + 1 , captured = false , entries = { } }
c . captureWatches [ # c . captureWatches + 1 ] = watch
local inferred = infer ( )
for index = # c . captureWatches , 1 , -1 do
if c . captureWatches [ index ] == watch then
table . remove ( c . captureWatches , index )
do break end
end
end
local captures





= { }
for definition , entry in pairs ( watch . entries ) do
if ( entry . functionDepth or 0 ) > 0 then
captures [
# captures + 1
] = {
name = definition . name or ( definition . token and definition . token . text ) or "?" ,
token = definition . token ,
definition = definition ,
type = entry . t ,
unassigned = entry . unassigned ,
}
end
end
table . sort ( captures , function ( left , right ) 
local a = left . token and left . token . offset or 0
local b = right . token and right . token . offset or 0
return a < b or a == b and left . name < right . name
end )
for _ , capture in ipairs ( captures ) do
if capture . unassigned then
c . diag (
"NUPP2006" ,
capture . token or node ,
("sendable function capture %q is not initialized yet") : format ( capture . name ) ,
nil ,
{ help = "initialize the binding before the sendable function is created" }
)
end
local why = captureProblem ( capture . type )
if why ~= nil then
c . diag (
"NUPP2006" ,
capture . token or node ,
("sendable function capture %q is %s") : format ( capture . name , why ) ,
nil ,
{ help = "capture only values that can be copied into an isolated Lua state" }
)
end
end
node . sendableCaptures = captures
node . sendableModule = c . result . declaredModuleName
local token = cst . firstToken ( node )
node . sendableMember = ("__nuppSendable_%d") : format ( token and token . offset or 0 )
if not node . sendableModule then
c . diag ( "NUPP2006" , node , "a sendable function literal must be written in a declared module" , nil , {
help = "add a module declaration so another Lua state can load the outlined body"
} )
end
c . result . sendableLiterals = c . result . sendableLiterals or { }
c . result . sendableLiterals [ # c . result . sendableLiterals + 1 ] = node

return T . withSendable ( inferred )
end

local function visibleNames ( ) 
local names = { }
local scope = c . scope
while scope do
for name in pairs ( scope . vars or { } ) do
names [ name ] = true
end
scope = scope . parent
end
for name in pairs ( c . env and c . env . globals or { } ) do
names [ name ] = true
end

return names
end





c . numericOperand = function ( t , node , op ) 
if t == T . any or isA ( t , T . number ) then
return true
end


local raw = T . unwrapOwnership ( t )
if ( raw . tag == "int64" or raw . tag == "uint64" ) and op ~= "for" then
return true
end
c . diag ( "NUPP2003" , node , ("cannot apply '%s' to %s") : format ( op , T . tostring ( t ) ) )

return false
end


local function numberLiteralType ( text ) 
local lower = text : gsub ( "_" , "" ) : lower ( )
if lower : find ( "ull" , 1 , true ) then
return T . uint64
end
if lower : find ( "ll" , 1 , true ) then
return T . int64
end
if lower : sub ( -1 ) == "i" then
return T . number
end
if lower : find ( "x" , 1 , true ) then
if lower : find ( "%." ) or lower : find ( "p" ) then
return T . number
end
return T . integer
end
if lower : find ( "%." ) or lower : find ( "e" ) then
return T . number
end

return T . integer
end














local function comptimeType ( untypedNode ) 
local node = untypedNode
c . pushScope ( )
c . retStack [ # c . retStack + 1 ] = false
c . retPackStack [ # c . retPackStack + 1 ] = false
c . comptimeDepth = ( c . comptimeDepth or 0 ) + 1
if node . body then
c . checkBlock ( node . body , true )
end
c . comptimeDepth = c . comptimeDepth - 1
c . retPackStack [ # c . retPackStack ] = nil
c . retStack [ # c . retStack ] = nil
c . popScope ( )

local reflections , layouts = { } , { }

local function collectComptimeFacts ( value ) 
if type ( value ) ~= "table" then
return
end
if value . reflectedTypeKey and value . reflectedType then
reflections [ value . reflectedTypeKey ] = value . reflectedType
end
if value . targetLayoutKey and value . targetLayout then
layouts [ value . targetLayoutKey ] = value . targetLayout
end
for _ , child in ipairs ( value ) do
collectComptimeFacts ( child )
end
end

collectComptimeFacts ( node . body )
local quoted , resultType , failure , envelope = comptime . evaluate (
untypedNode ,
node . body ,
reflections ,
layouts ,
c . comptimeFunctions ,
c . env and c . env . host or nil ,
c . env and c . env . compilerServices or nil
)
if failure then
c . diag (
failure . code ,
failure . node or node ,
failure . message ,
nil ,
failure . help and { help = failure . help } or nil
)
return T . any
end
if envelope then
local lowered , lowerFailure , lowering , inferredTarget = materializeProviders . lower (
envelope ,
node . materializationExpected ,
c . env
)
if lowerFailure then
c . diag (
lowerFailure . code ,
node ,
lowerFailure . message ,
nil ,
lowerFailure . help and { help = lowerFailure . help } or nil
)
return T . any
end
local rendered , renderFailure = materializeIR . render ( lowered )
if renderFailure then
c . diag ( "NUPP2416" , node , renderFailure . message )
return T . any
end
node . materializedIR = lowered
node . materializationEnvelope = envelope
lowering = lowering or { }
node . materializationObservation = {
provider = envelope . provider ,
schema = envelope . schema ,
fingerprint = envelope . fingerprint ,
backend = lowering . backend or "direct" ,
blueprintSize = # stable ( envelope . payload ) ,
generatedSize = # ( rendered or "" ) ,
runtimeFeatures = lowering . runtimeFeatures or { } ,
abis = {
provider = envelope . schema ,
registry = materializeProviders . ABI ,
emitter = lowering . emitterAbi or 1 ,
helper = lowering . helperAbi or 0 ,
runtimeExpression = materializeIR . ABI ,
} ,
blueprint = envelope ,
generated = rendered ,
}

if node . materializationExpected then
node . comptimeResultType = node . materializationExpected
return node . materializationExpected
end
node . comptimeResultType = inferredTarget or T . any
return node . comptimeResultType
end
node . comptimeValue = quoted
node . comptimeResultType = resultType or T . any

return node . comptimeResultType
end




local handlers = { }
for _ , installed in ipairs ( { operators . install ( c ) , index . install ( c ) , callexpr . install ( c ) , } ) do
for kind , handle in pairs ( installed ) do
handlers [ kind ] = handle
end
end





local function staticCaseShape ( node ) 
if not node then
return false
end
local kind = node . kind
if kind == "number"
or kind == "string"
or kind == "nilExpr"
or kind == "trueExpr"
or kind == "falseExpr"
or kind == "name"
then
return true
elseif kind == "paren" then
return staticCaseShape ( node . expr )
elseif kind == "unop" then
return node . op ~= nil and node . op . kind == "-" and node . operand ~= nil and node . operand . kind == "number"
end

return false
end

local function exactScalar ( node ) 
if not staticCaseShape ( node ) then
c . infer ( node )
return nil , "a static switch case is a scalar literal or a name with an exact scalar type"
end
local valueT = c . infer ( node )
local literalNode = node
while literalNode . kind == "paren" and literalNode . expr do
literalNode = literalNode . expr
end
if literalNode . kind == "string" and literalNode . token then
local value = lexer . stringValue ( literalNode . token . text )
if value then
valueT = T . literal ( value , T . string )
end
end
if literalNode . kind == "unop" and literalNode . operand then
local operand = literalNode . operand
local token = operand . token
local value = token and tonumber ( ( token . text : gsub ( "_" , "" ) ) ) or nil
if value then
valueT = T . literal ( - value , T . number )
end
end
if valueT == T . nil_ or valueT . tag == "literal" then
if valueT . tag == "literal"
and type ( valueT . constant ) == "number"
and (
valueT . constant ~= valueT . constant or valueT . constant == math . huge or valueT . constant == - math . huge
)
then
return nil , "numeric switch cases must be finite"
end
return valueT
end

return nil , "a named switch case must have an exact scalar type"
end

local function scalarKey ( t ) 
if t == T . nil_ then
return "nil"
end
local literal = t

return type ( literal . constant ) .. ":" .. tostring ( literal . constant )
end

local function finiteMembers ( t ) 
if not t then
return nil
elseif t == T . nil_ or t . tag == "literal" then
return { t }
elseif t == T . boolean then
return { T . literal ( false , T . boolean ) , T . literal ( true , T . boolean ) }
elseif t . tag == "union" then
local out = { }
for _ , member in ipairs ( t . members ) do
local expanded = finiteMembers ( member )
if not expanded then
return nil
end
for _ , value in ipairs ( expanded ) do
out [ # out + 1 ] = value
end
end
return out
end

return nil
end



local function openMember ( t ) 
if not t then
return false
elseif t == T . open then
return true
elseif t . tag == "union" then
for _ , member in ipairs ( t . members ) do
if member == T . open then
return true
end
end
end

return false
end






local function recordOnly ( t ) 
t = rawType ( t )
if t . tag == "nominal" then
return t . declKind == "record"
elseif t . tag == "union" then
if # t . members == 0 then
return false
end
for _ , member in ipairs ( t . members ) do
if not recordOnly ( member ) then
return false
end
end
return true
end

return false
end

local blockCompletesSwitch

local function statCompletesSwitch ( stat ) 
local kind = stat . kind
if kind == "yieldStmt" or kind == "returnStmt" or kind == "breakStmt" or kind == "continueStmt" then
return true
elseif kind == "ifStmt" then
if stat . elseClause == nil then
return false
end
for _ , clause in ipairs ( stat . clauses or { } ) do
if not blockCompletesSwitch ( clause . body ) then
return false
end
end
local otherwise = stat . elseClause
return blockCompletesSwitch ( otherwise . body )
elseif kind == "doStmt" or kind == "withStmt" then
return blockCompletesSwitch ( stat . body )
elseif kind == "pragmaStmt" and stat . stat then
return statCompletesSwitch ( stat . stat )
end

return false
end

blockCompletesSwitch = function ( block ) 
local stats = block and block . kind == "block" and block . stats or { }
for index , stat in ipairs ( stats ) do
if statCompletesSwitch ( stat ) then
if index < # stats then
c . diag (
"NUPP2141" ,
stats [ index + 1 ] ,
"statements after a completing expression-block path are unreachable"
)
end
return true
end
end

return c . alwaysExits ( block )
end





local FALSE_T = T . literal ( false , T . boolean )







local function truthyPart ( t ) 
if t == T . any or t == T . unknown or t . tag == "typevar" then
return t
end
if isA ( t , T . nil_ ) or isA ( t , FALSE_T ) then
return T . never
end
local rest = subtract ( t , T . nil_ )
if isA ( rest , T . nil_ ) or isA ( rest , FALSE_T ) then
return T . never
end

return subtract ( rest , FALSE_T )
end


local function falsyPart ( t ) 
if t == T . any or t == T . unknown or t . tag == "typevar" then
return T . union ( { T . nil_ , FALSE_T } )
end
local parts = { }
if isA ( T . nil_ , t ) then
parts [ # parts + 1 ] = T . nil_
end
if isA ( FALSE_T , t ) then
parts [ # parts + 1 ] = FALSE_T
end
if # parts == 0 then
return T . never
end

return T . union ( parts )
end






local function protectedBuiltin ( operand ) 
local callee = operand . kind == "call" and ( operand ) . obj or nil
local token = callee and callee . kind == "name" and ( callee ) . token or nil
local text = token and token . text or nil
if text == "pcall" or text == "xpcall" then
return text
end

return nil
end


local function explicitForm ( exitKind ) 
return ("write `local value, reason = ...` and `%s` under `if value == nil then`")

: format ( exitKind == "return" and "return value, reason" or exitKind )
end






local function checkExitReturn ( node , pack , failure ) 
local at = node . exitToken or node
local dynamic = node
if c . result . declaredModuleName and # c . retStack == 0 then
c . diag ( "NUPP1002" , at , "a declared module exports declarations and has no top-level return" )
return
end
if c . constructorFieldStack [ # c . constructorFieldStack ] then
c . diag ( "NUPP2208" , at , "a constructor returns the instance it builds" , nil , {
help = "write the explicit conditional, and return after initializing the required fields"
} )
return
end
local head = { failure }
for index = 2 , # pack . head do
head [ index ] = pack . head [ index ]
end
local forwarded = T . pack ( head )
dynamic . orExitReturnPack = forwarded
local annotated = c . retPackStack [ # c . retPackStack ]
local observed = c . observedReturnStack [ # c . observedReturnStack ]
if observed and not annotated then
observed [ # observed + 1 ] = forwarded
end
if not annotated then
return
end
if annotated . alternatives then
local ok , why = relations . packIsA ( forwarded , annotated )
if not ok then
c . diag (
"NUPP2002" ,
at ,
"the forwarded failure pack does not match a declared alternative: " .. (
why or "incompatible packs"
)
)
end
return
end
for index , expected in ipairs ( annotated . head ) do
local got = T . packAt ( forwarded , index ) or T . nil_
local ok , why , reported = c . fixedWidth . fits ( got , expected , at )
if not ok and not reported then
c . diag ( "NUPP2002" , at , ("forwarded result %d: %s") : format ( index , why ) , nil , {
help = got == T . unknown
and "`unknown` fits nowhere until it is narrowed; declare this result `unknown` too, or supply a handler through `nupp.util.tryWith`"

or explicitForm ( "return" ) ,
} )
end
end
if not annotated . tail and # forwarded . head > # annotated . head then
c . diag (
"NUPP2002" ,
at ,
("too many forwarded results (expected %d, got %d)") : format ( # annotated . head , # forwarded . head ) ,
nil ,
{ help = explicitForm ( "return" ) }
)
elseif annotated . tail and annotated . tail . kind == "homogeneous" then
for index = # annotated . head + 1 , # forwarded . head do
local ok , why , reported = c . fixedWidth . fits ( forwarded . head [ index ] , annotated . tail . type , at )
if not ok and not reported then
c . diag ( "NUPP2002" , at , ("forwarded result %d: %s") : format ( index , why ) )
end
end
end
end







local function inferOrExit ( node ) 
local operand = node . operand
local exitKind = node . exitKind
if not operand then
return T . any
end
local first = c . infer ( operand )
local dynamicOperand = operand
local pack = dynamicOperand . valuePack or T . pack ( { first } )
local at = node . exitToken or node

if exitKind == "break" or exitKind == "continue" then
c . recordLoopExit ( exitKind , at )
end
local dynamic = node
dynamic . orExitPack = pack









if pack . alternatives then
local remaining = nil
local absent = false
for _ , arm in ipairs ( pack . alternatives ) do
if # arm . head == 1 and not arm . tail and arm . head [ 1 ] == T . nil_ then
absent = true
elseif remaining then
remaining = nil
do break end
else
remaining = arm
end
end
if absent and remaining then
pack = remaining
end
end
if pack . alternatives then
local builtin = protectedBuiltin ( operand )
c . diag (
"NUPP2149" ,
at ,
"this operand's results are a correlated pack union, which the suffix cannot read" ,
nil ,
{
help = builtin
and ("`%s` leads with a discriminator rather than a result; use `nupp.util.%sse`, which answers the conventional (value, reason) layout")


: format ( builtin , builtin )
or explicitForm ( exitKind ) ,
}
)
return T . any
end
if # pack . head == 0 and not pack . tail then
c . diag ( "NUPP2149" , at , "this operand produces no value to test" , nil , { help = explicitForm ( exitKind ) } )
return T . any
end
if pack . tail then
c . diag ( "NUPP2149" , at , "this operand's result count is not fixed" , nil , { help = explicitForm ( exitKind ) } )
return T . any
end

local primary = pack . head [ 1 ]
local success = truthyPart ( primary )
local failure = falsyPart ( primary )
if failure == T . never then
c . diag (
"NUPP2149" ,
at ,
("this operand's first result is %s, which is never nil or false") : format ( T . tostring ( primary ) ) ,
nil ,
{ help = "the suffix would never exit; drop it, or return an optional result" }
)
return success
end
if success == T . never then
c . diag (
"NUPP2149" ,
at ,
("this operand's first result is %s, which is never a value") : format ( T . tostring ( primary ) ) ,
nil ,
{ help = "the suffix would always exit; write the exit statement instead" }
)
return T . never
end


c . checkPackDiscard ( pack , 2 , operand )

if exitKind == "return" then
checkExitReturn ( node , pack , failure )
end
dynamic . orExitSuccess = success
dynamic . orExitFailure = failure
dynamic . orExitWidth = # pack . head


local roots = c . own . capabilityFacts ( operand , nil , false ) . roots
if roots and roots [ 1 ] then
c . own . capabilityFacts ( node ) . roots = roots
end

return success
end


local function inferDo ( node ) 
local yielded = {
roots = { } ,
seenRoots = { } ,
visible = { } ,
expressions = { } ,
before = c . ownershipSnapshot ( ) ,
moved = { } ,
join = c . ownershipJoin ( )
}
local scope = c . scope
while scope do
for _ , entry in pairs ( scope . vars or { } ) do
local root = c . own . borrowRoot ( c . ownershipState ( entry ) )
if root then
yielded . visible [ root ] = true
end
end
scope = scope . parent
end
c . blockYieldStack [ # c . blockYieldStack + 1 ] = yielded
c . checkBlock ( node . body )
c . blockYieldStack [ # c . blockYieldStack ] = nil
local completes = blockCompletesSwitch ( node . body )
if not completes then
c . diag ( "NUPP2141" , node , "this do expression can finish without yielding a value" , nil , {
help = "end every completing path with `yield value`, or return from the enclosing function"
} )
end
c . auditOwnershipJoin ( yielded . moved , yielded . join , node )
c . own . capabilityFacts ( node ) . roots = # yielded . roots > 0 and yielded . roots or nil
for index , expression in ipairs ( yielded . expressions ) do
if index == 1 then
c . fixedWidth . copy ( node , expression )
else
c . fixedWidth . intersect ( node , node , expression )
end
end
local result = # yielded > 0 and T . union ( yielded ) or ( completes and T . never or T . any )
node . switchResultType = result
if c . ownershipKind ( result ) == "affine" then
c . own . temporaryProduced ( node )
end

return result
end







local function coveredBy ( residue , case ) 
return residue ~= T . never and residue ~= T . any and isA ( residue , case )
end

local function inferSwitch ( node ) 
local selector = node . selector
local selectorT = selector and c . infer ( selector ) or T . any
node . switchSelectorType = selectorT
local selectorKey = selector and c . pathKey ( selector ) or nil
local residue = selectorT
local seen = { }
local results = { }
local resultExpressions = { }
local resultExpressionTypes = { }
local resultRoots , seenRoots = { } , { }
local expressionResultsOnly = true
local ownershipBefore = c . ownershipSnapshot ( )
local branchMoved = { }
local join = c . ownershipJoin ( )

local function checkResult ( arm ) 
if arm . expr then
local resultType = c . infer ( arm . expr )
arm . switchResultType = resultType
if c . ownershipKind ( resultType ) == "borrowed" then
c . own . provenanceOwners ( arm . expr , resultRoots , seenRoots )
else
for _ , root in ipairs ( c . own . capabilityFacts ( arm . expr , nil , false ) . roots or { } ) do
if not seenRoots [ root ] then
seenRoots [ root ] = true
resultRoots [ # resultRoots + 1 ] = root
end
end
end
results [ # results + 1 ] = resultType
resultExpressions [ # resultExpressions + 1 ] = arm . expr
resultExpressionTypes [ # resultExpressionTypes + 1 ] = resultType
local exact = staticCaseShape ( arm . expr ) and exactScalar ( arm . expr ) or nil
if exact then
arm . switchStaticResult = exact
end



if c . ownershipKind ( resultType ) == "affine" and c . ownershipEntry ( arm . expr ) then
c . moveExpression ( arm . expr , resultType , "switch result" , "affine" )
end
elseif arm . body then
expressionResultsOnly = false
local yielded = { }
c . blockYieldStack [ # c . blockYieldStack + 1 ] = yielded
c . checkBlock ( arm . body , true )
c . blockYieldStack [ # c . blockYieldStack ] = nil
for _ , valueT in ipairs ( yielded ) do
results [ # results + 1 ] = valueT
end
local completes = blockCompletesSwitch ( arm . body )
if # yielded == 0 and completes then
results [ # results + 1 ] = T . never
end
if not completes then
c . diag ( "NUPP2141" , arm . body , "this switch arm can finish without yielding a value" , nil , {
help = "end every completing path with `yield value`, or return from the enclosing function"
} )
end
else
expressionResultsOnly = false
results [ # results + 1 ] = T . any
end
end

for _ , arm in ipairs ( node . cases or { } ) do
c . pushScope ( )
local armReachable = residue ~= T . never



local guarded = arm . guard ~= nil
if arm . patternKind == "static" then
local narrowed = { }
for _ , value in ipairs ( arm . values or { } ) do
local exact , why = exactScalar ( value )
if not exact then
c . diag ( "NUPP2137" , value , why )
else
value . switchStaticValue = exact
local key = scalarKey ( exact )
if seen [ key ] then
c . diag ( "NUPP2138" , value , "duplicate static switch case" , nil , {
related = { c . related ( seen [ key ] , "the same value is handled here" ) }
} )
elseif not guarded then
seen [ key ] = value
end
narrowed [ # narrowed + 1 ] = exact
if selectorT ~= T . any and not isA ( exact , selectorT ) then
c . diag ( "NUPP2139" , value , "this case value is not admitted by the selector type" )
end
if not guarded then
residue = coveredBy ( residue , exact ) and T . never or subtract ( residue , exact )
end
end
end
if selectorKey and # narrowed > 0 then
c . applyFacts ( { [ selectorKey ] = T . union ( narrowed ) } )


local baseKey , kept = c . facts . discriminantBase ( selector , narrowed )
if baseKey and kept then
c . applyFacts ( { [ baseKey ] = kept } )
end
end
else
arm . switchRecordIdentitySafe = recordOnly ( residue )
local target = c . resolveType ( arm . type )
arm . switchType = target
local members = finiteMembers ( residue )
if members then
armReachable = false
for _ , member in ipairs ( members ) do
if isA ( member , target ) then
armReachable = true
do break end
end
end
end
if selectorKey then
c . applyFacts ( { [ selectorKey ] = target } )
end
if arm . binding then
c . bindVar ( arm . binding . text , target , true , arm . binding , "variable" , true )
end
local bound = { }
if arm . binding then
bound [ arm . binding . text ] = true
end
for _ , field in ipairs ( arm . fields or { } ) do
local name = field . name and field . name . text or ""
local binding = field . alias or field . name
local bindingName = binding and binding . text or name
if bound [ bindingName ] then
c . diag ( "NUPP2137" , binding or field , ("duplicate switch binding %q") : format ( bindingName ) )
else
bound [ bindingName ] = true
end
local fieldT , definition = c . fieldType ( rawType ( target ) , name )
if not fieldT then
c . diag ( "NUPP2137" , field . name or field , ("no field %q in %s") : format ( name , T . tostring ( target ) ) )
fieldT = T . any
end
c . markToken ( field . name , definition , fieldT , "property" )
if binding then
c . bindVar ( bindingName , fieldT , true , binding , "variable" , true )
end
end
if not guarded then
residue = coveredBy ( residue , target ) and T . never or subtract ( residue , target )
end
end
if not armReachable then
c . diag ( "NUPP2139" , arm , "this switch case is unreachable" )
end
if arm . guard and arm . guard . expr then
c . infer ( arm . guard . expr )
end
checkResult ( arm )
if not ( arm . expr and arm . switchResultType == T . never or arm . body and c . alwaysExits ( arm . body ) ) then
c . noteArmEnd ( join )
end
c . popScope ( )
c . ownershipRewind (
ownershipBefore ,
branchMoved ,
not ( arm . expr and arm . switchResultType == T . never or arm . body and c . alwaysExits ( arm . body ) ) ,
join
)
end
if node . elseCase then
c . pushScope ( )
if selectorKey then
c . applyFacts ( { [ selectorKey ] = residue } )
end
if residue == T . never then
c . diag ( "NUPP2139" , node . elseCase , "this switch else arm is unreachable" )
end
checkResult ( node . elseCase )
if not (
node . elseCase . expr and node . elseCase . switchResultType == T . never
or node . elseCase . body and c . alwaysExits ( node . elseCase . body )
) then
c . noteArmEnd ( join )
end
c . popScope ( )
c . ownershipRewind (
ownershipBefore ,
branchMoved ,
not (
node . elseCase . expr and node . elseCase . switchResultType == T . never
or node . elseCase . body and c . alwaysExits ( node . elseCase . body )
) ,
join
)
elseif openMember ( residue ) then
c . diag ( "NUPP2140" , node , "switch is not exhaustive: the selector type is open" , nil , {
help = "add an `else` arm, which is what `nupp.types.nonExhaustive()` asks every switch for"
} )
elseif residue ~= T . never then
local missing = finiteMembers ( residue )
local detail = ""
if missing and # missing > 0 then
local names = { }
for index , member in ipairs ( missing ) do
if member == T . nil_ then
names [ index ] = "nil"
else
names [ index ] = tostring ( ( member ) . constant )
end
end
table . sort ( names )
detail = "; missing " .. table . concat ( names , ", " )
end
c . diag ( "NUPP2140" , node , "switch is not exhaustive" .. detail , nil , {
help = "add the missing cases or add an `else` arm"
} )
end
c . auditOwnershipJoin ( branchMoved , join , node )
local result = # results > 0 and T . union ( results ) or T . any
node . switchResultType = result
c . own . capabilityFacts ( node ) . roots = # resultRoots > 0 and resultRoots or nil


if c . ownershipKind ( result ) == "affine" then
for _ , value in ipairs ( resultExpressions ) do
c . markTemporaryConsumed ( value )
end
c . own . temporaryProduced ( node )
end
if expressionResultsOnly then
local copied = false
for index , value in ipairs ( resultExpressions ) do
if resultExpressionTypes [ index ] ~= T . never then
if copied then
c . fixedWidth . intersect ( node , node , value )
else
c . fixedWidth . copy ( node , value )
copied = true
end
end
end
end

return result
end







local function inferExpr ( node ) 
local handle = handlers [ node . kind ]
if handle then
return handle ( node )
end
local kind = node . kind
if kind == "number" then
local literal = node . token
if not literal then
return T . number
end
local base = numberLiteralType ( literal . text )
local value = tonumber ( ( literal . text : gsub ( "_" , "" ) ) )
if value and ( base == T . integer or base == T . number ) then
c . fixedWidth . markLiteral ( node , value )
return T . literal ( value , base )
end
return base
elseif kind == "string" then
local literal = node . token
if not literal then
return T . string
end
local value = lexer . stringValue ( literal . text )
if value then
return T . literal ( value , T . string )
end
return T . string
elseif kind == "dedentString" then
return T . string
elseif kind == "nilExpr" then
return T . nil_
elseif kind == "trueExpr" then
return T . literal ( true , T . boolean )
elseif kind == "falseExpr" then
return T . literal ( false , T . boolean )
elseif kind == "vararg" then
local pack = c . varargPackStack [ # c . varargPackStack ]
if not pack then
return T . any
end
node . valuePack = pack
c . lastCallRets = pack . head
return T . packAt ( pack , 1 ) or T . nil_
elseif kind == "name" then
local nameTok = node . token
if not nameTok then
return T . any
end
local nameText = nameTok . text
local entry = c . lookupEntry ( nameText )
if not entry
and c . result . declaredModuleName
and c . moduleExports
and c . moduleExports . values
and c . moduleExports . values [ nameText ]
then
local exportedType = c . moduleExports . values [ nameText ]
local definition = c . moduleExports . valueDefs and c . moduleExports . valueDefs [ nameText ] or nil
c . markToken ( nameTok , definition , exportedType , definition and definition . kind or "variable" )
node . immutablePath = true
return exportedType
end
if not entry and c . env and c . env . ensureProjectIndex and c . env . resolveModule then
local registry = c . env . ensureProjectIndex ( c . env )
if registry . declaredModules and registry . declaredModules [ nameText ] then
local moduleType = c . env . resolveModule ( c . env , nameText )
if moduleType then
node . qualifiedModule = nameText
node . qualifiedMembers = { }
node . immutablePath = true
c . markToken (
nameTok ,
registry . moduleDefinitions and registry . moduleDefinitions [ nameText ] or nil ,
moduleType ,
"module"
)
return moduleType
end
end
end



if entry and entry . requiredModule then
node . requiredModule = entry . requiredModule
end
local capturedType = nil
if entry
and entry . definition
and entry . definition . comptimeFunction
and ( c . comptimeDepth or 0 ) == 0
and ( c . comptimeFunctionDepth or 0 ) == 0
then
c . diag ( "NUPP2415" , node , ("comptime function %q has no runtime value") : format ( nameText ) , nil , {
help = "call it from a comptime block or another comptime function"
} )
end
node . immutablePath = entry and entry . constant == true or false
local capabilityFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
if entry and c . ownershipState ( entry ) . withBinding then


c . own . capabilityFacts ( node ) . roots = { c . ownershipState ( entry ) }
elseif capabilityFacts and capabilityFacts . roots then
c . own . capabilityFacts ( node ) . roots = capabilityFacts . roots
end
if entry then
local state = c . ownershipState ( entry )
if state . moved then
local related = state . movedAt and c . related ( state . movedAt , "owner was moved here" ) or nil
c . diag ( "NUPP2601" , node , ("owner %q was moved and cannot be used") : format ( nameText ) , nil , {
related = related and { related } or nil ,
help = "use the owner before this transfer, or borrow it instead of moving it"
} )
node . ownershipUseReported = true
elseif c . ownershipKind ( entry . t )
and ( entry . functionDepth or 0 ) < c . functionDepth
and not ( c . ownershipKind ( entry . t ) == "borrowed" and c . scopedCaptureDepth > 0 )
then
local context = c . closureCaptureStack [ # c . closureCaptureStack ]
local capture = context and context . allowed [ nameText ] or nil
if context and not capture and not context . body . captureBorrows then
capture = { name = nameText , token = nameTok , root = c . borrowRoot ( state ) , outer = state , }
context . allowed [ nameText ] = capture
context . body . borrowCaptures [ # context . body . borrowCaptures + 1 ] = capture
end
if capture then
c . own . capabilityFacts ( node ) . roots = { capture . root }
capturedType = T . borrowed ( rawType ( entry . t ) )
elseif not node . ownershipCaptureReported then

local capturedKind = c . ownershipKind ( entry . t )
c . diag (
"NUPP2603" ,
node ,
("%s value %q has no closure borrow contract") : format ( capturedKind , nameText ) ,
nil ,
{ help = "name the source in borrows (...) or let an expression closure infer it" }
)
node . ownershipCaptureReported = true
end
end
end
if entry and entry . globalModule and entry . globalModule ~= c . result . moduleName then
c . result . implicitSideEffects [ entry . globalModule ] = true
end
if not entry and c . env and c . env . resolveProjectValue then
local valueType , valueDef , valueErr , sideEffectModule , conflicts = c . env . resolveProjectValue (
c . env ,
c . filename ,
nameText
)
if valueType then



if sideEffectModule then
c . result . implicitSideEffects [ sideEffectModule ] = true
end
c . markToken ( nameTok , valueDef , valueType , valueDef and valueDef . kind or "variable" )
return valueType
elseif valueErr then
local related , seen = { } , { }
for _ , conflict in ipairs ( conflicts or { } ) do
local definition = conflict . definition
local key = definition
and (
tostring (
definition . filename
) .. ":" .. tostring ( definition . token and definition . token . offset )
)
or tostring ( conflict )
if not seen [ key ] then
seen [ key ] = true
local item = c . related ( definition , "conflicting global value declared here" )
if item then
related [ # related + 1 ] = item
end
end
end
c . diag (
"NUPP2104" ,
node ,
("ambiguous global %q; a project global must be unique") : format ( nameText ) ,
nil ,
{
related = related ,
help = "make all but one declaration local or attach them to their module tables"
}
)
return T . any
end
end
c . markToken (
nameTok ,
entry and entry . definition ,
entry and entry . t or T . any ,
entry and entry . definition and entry . definition . kind or "variable"
)
local runtimeRoot = runtimeSurface . resolvedRoot ( c , nameTok ) or entry and entry . runtimeSurfaceRoot
local runtimeNode = node
runtimeNode . runtimeSurfaceRoot = runtimeRoot
runtimeSurface . requireIdentity ( c , runtimeRoot , nil , nameTok )
if not entry then




local advice , isModule , fixes = c . missingRequire ( nameText )
if advice then
c . diag ( "missing-require" , node , advice , fixes )
elseif not isModule and c . opts and c . opts . strict and not runtimeNode . newTypeOperand then
fixes = c . edits . nameSpellingFix ( nameTok , visibleNames ( ) )
c . diag ( "NUPP2105" , nameTok , ("unknown variable %q") : format ( nameText ) , fixes , {
help = fixes and "use the suggested visible name"
or "declare the value, require its module, or correct the spelling"
} )
end
end


if entry and entry . unassigned and ( entry . functionDepth or 0 ) >= c . functionDepth then
c . diag ( "NUPP2207" , nameTok , ("%s is read before it holds a value") : format ( nameText ) , nil , {
related = entry . unassignedAt
and {
c . related (
{ filename = c . filename , token = entry . unassignedAt , name = nameText } ,
"declared here, with no value"
)
}
or nil ,
help = ("assign it first, or declare it as %s? if it is meant to start empty")

: format ( T . tostring ( entry . t ) )
} )


entry . unassigned = nil
end
c . fixedWidth . copyBinding ( node , entry )
return capturedType or ( entry and entry . t or T . any )
elseif kind == "paren" then
local inner = node . expr
local out = inner and c . infer ( inner ) or T . any
if inner and inner . valuePack then
c . checkPackDiscard ( inner . valuePack , 2 , node )
end
node . immutablePath = inner and inner . immutablePath or false
c . fixedWidth . copy ( node , inner )
return out
elseif kind == "comptimeExpr" then
return comptimeType ( node )
elseif kind == "newExpr" then



local call = node . call
if not call then
return T . any
end
call . isNew = true



local named = call . obj and c . pathKey ( call . obj ) or nil
local declared = named and c . lookupType ( named ) or nil
declared = declared and rawType ( declared ) or nil
local buildable = declared
and declared . tag == "nominal"
and ( declared . declKind == "record" or declared . declKind == "struct" )
if declared and not buildable then
local why = "`new` builds a record or a struct"
if declared . tag == "nominal" and declared . declKind == "interface" then
why = "an interface declares a contract and has no runtime table to stamp; construct a record that declares it with `is`"


elseif declared . tag == "union" then
why = "a union is one of its members, and a value of it is written as one of them"
end
c . diag ( "NUPP2206" , call . obj or node , ("%s cannot be constructed") : format ( named ) , nil , { help = why } )
call . newReported = true



if call . obj then
( call . obj ) . newTypeOperand = true
end
end
local result = c . infer ( call )
node . partitionFields = call . partitionFields
c . fixedWidth . copy ( node , call )
return result
elseif kind == "ternary" then
local cond , ifTrue , ifFalse = node . cond , node . ifTrue , node . ifFalse
if not cond or not ifTrue or not ifFalse then
return T . any
end
c . infer ( cond )
local facts = c . analyzeCond ( cond )
c . pushScope ( )
c . applyFacts ( facts . t )
local tt = c . infer ( ifTrue )
c . popScope ( )
c . pushScope ( )
c . applyFacts ( facts . f )
local ft = c . infer ( ifFalse )
c . popScope ( )
if c . ownershipKind ( tt ) or c . ownershipKind ( ft ) then
c . diag ( "NUPP2602" , node , "an ownership-bearing value cannot be selected by a ternary expression" , nil , {
help = "move or drop the owner explicitly in each control-flow branch"
} )
end
c . fixedWidth . intersect ( node , ifTrue , ifFalse )
return T . union ( { tt , ft } )
elseif kind == "castExpr" then
local cast = node . expr
if not cast then
return c . resolveType ( node . type )
end
local source = c . infer ( cast )
local target = c . resolveType ( node . type )
c . fixedWidth . storageOnly ( node . type , target , "a cast result" )



if T . constraintOf ( target ) and not isA ( source , target ) then
c . diag (
"NUPP2013" ,
node ,
("%s is not established as %s, and `as` does not establish it")

: format ( T . tostring ( source ) , T . tostring ( target ) ) ,
nil ,
{ help = "use nupp.admit(value) to check it, or `value is " .. T . tostring ( target ) .. "` to test it" }
)
end
node . fixedWidthEstablished = nil
node . fixedWidthTrusted = nil
node . fixedWidthCallableUntrusted = target . tag == "func" and true or nil
if c . ownershipKind ( target ) then
if c . ownershipKind ( target ) == "pinned" and c . ownershipKind ( source ) ~= "pinned" then
c . diag ( "NUPP2604" , node , "a pinned(T) value must be constructed with nupp.pin(pointer, anchor)" )
end
return target
end
if source . tag == "affine" then
return T . affine ( target , source . cleanups , source . transferOnly , source . obligation )
elseif c . ownershipKind ( source ) == "borrowed" then
return T . borrowed ( target )
elseif c . ownershipKind ( source ) == "pinned" then
return T . pinned ( target )
end
return target
elseif kind == "isExpr" then
local subject = node . expr
local from = subject and c . infer ( subject ) or nil
local target = c . resolveType ( node . type )
node . typeTestTarget = target











if from
and target
and subject
and c . pathKey ( subject )
and from ~= T . any
and from . tag ~= "typevar"
and from ~= T . never
and target ~= T . any
and target . tag ~= "typevar"
then







local admitsNil = isA ( T . nil_ , from )
local present = admitsNil and subtract ( from , T . nil_ ) or from


if present == T . never then
present = from
end
if present ~= T . never and present . tag ~= "typevar" and isA ( present , target ) then
node . provenStatically = true
node . provenNeedsNil = admitsNil and not isA ( T . nil_ , target ) or nil




elseif ( rawType ( present ) . tag == "metatable" or rawType ( present ) . tag == "typeobject" )
and target . tag == "nominal"
then
node . refutedStatically = true
end
end
local typeNode = node . type
local builtin = typeNode
and typeNode . kind == "tname"
and typeNode . base
and (
typeNode . base . kind == "nil"
or # typeNode == 1
and (
typeNode . base . text == "boolean"
or typeNode . base . text == "string"
or typeNode . base . text == "number"
or typeNode . base . text == "integer"
or typeNode . base . text == "table"
or typeNode . base . text == "thread"
or typeNode . base . text == "userdata"
or typeNode . base . text == "cdata"
)
)




if typeNode and not builtin then
typeNode . primitiveTest = T . luaTypeName ( T . unconstrained ( target ) ) or target == T . nil_ and "nil" or nil
end




local constraint = T . constraintOf ( target )
if typeNode and constraint and typeNode . primitiveTest then
typeNode . wherePredicate = predicate . normalize (
_G.setmetatable({ op =
"and" ,  a =
_G.setmetatable({ op =  "typeis" ,  path =  { } ,  luaType =  typeNode . primitiveTest }, predicate.Node) ,  b =
constraint }, predicate.Node)

)
typeNode . primitiveTest = nil
end










local disjoint = false
if from
and target
and not node . provenStatically
and not node . refutedStatically
and not narrowing . overlaps ( from , target )
then
disjoint = true
c . diag (
"NUPP2147" ,
node ,
("%s and %s share no value, so this test can never hold")

: format ( T . tostring ( from ) , T . tostring ( target ) ) ,
nil ,
{ help = "test a type the subject can hold, or cast with `as` first" }
)
end
local runtimeIdentity = disjoint
or node . provenStatically
or typeNode and typeNode . primitiveTest
or node . refutedStatically
or builtin
or typeNode and typeNode . kind == "tfunc"
or typeNode and typeNode . wherePredicate
or typeNode and typeNode . recordName
or typeNode and typeNode . recordNames
or typeNode and typeNode . reified
if not runtimeIdentity then
c . diag (
"NUPP3001" ,
typeNode or node ,
target and target . tag == "typevar" and "a generic type parameter has no runtime identity to test"
or target
and target . tag == "nominal"
and target . declKind == "interface"
and "an interface without a refinement has no runtime identity to test"
or "this type has no runtime identity to test" ,
nil ,
{ help = "test a runtime-reified type, or give the interface a satisfies refinement" }
)
end
return T . boolean
elseif kind == "orExitExpr" then
return inferOrExit ( node )
elseif kind == "doExpr" then
return inferDo ( node )
elseif kind == "switchExpr" then
return inferSwitch ( node )
elseif kind == "funcExpr" then
local body = node . body
local inferred = inferSendableLiteral ( node , function ( ) 
return body and c . checkFuncbody ( body ) or T . any
end )
local dynamicNode = node
dynamicNode . mutatesParams = body and ( body ) . mutatesParams or nil
dynamicNode . mutatesCapturedEntries = body and ( body ) . mutatesCapturedEntries or nil
dynamicNode . mutatesCapturedPaths = body and ( body ) . mutatesCapturedPaths or nil
dynamicNode . mutatesSelf = body and ( body ) . mutatesSelf or nil
if body and not body . returnPack then
node . fixedWidthCallableUntrusted = true
end
local captures = body and body . borrowCaptures or { }
if # captures > 0 then
local roots = { }
for _ , capture in ipairs ( captures ) do
roots [ # roots + 1 ] = capture . root
end
c . own . capabilityFacts ( node ) . roots = roots
if not c . ownershipKind ( inferred ) then
inferred = T . borrowed ( inferred )
end
end
return inferred
elseif kind == "shortfn" then
local function inferShort ( ) 
local savedUnsafe = c . unsafeDepth
c . unsafeDepth = 0
c . pushScope ( )
c . scope . completionScope = node . body or node
local params , paramNames , paramModes = { } , { } , { }
local vararg = false
local expectedParams = nil
local expectedModes = nil
local expected = expectedShortfns [ node ]
if expected then
local expectedFunc = rawType ( expected )
if expectedFunc . tag == "func" then
local generics = require ( "nupp.compiler.types.generics" )
expectedParams = generics . expectedParameters ( expectedFunc , c . reductionControl )
expectedModes = generics . expectedParameterModes ( expectedFunc , c . reductionControl )
end
end
for _ , p in ipairs ( node . params ) do
if p . kind == "param" then
local pt = p . type and c . resolveType ( p . type )
or ( expectedParams and expectedParams [ # params + 1 ] )
or T . any
local pname = p . name
if p . namedVararg then
vararg = true
if pname then
c . bindVar ( pname . text , T . table_ , false , pname , "parameter" , true )
end
else
params [ # params + 1 ] = pt
paramNames [ # params ] = pname and pname . text or ""





local mode = expectedModes and expectedModes [ # params ] or "plain"
if mode ~= "borrows" and mode ~= "exclusive" then
mode = "plain"
end
paramModes [ # params ] = mode
if pname then
if p . type then
c . fixedWidth . storageOnly ( p . type , pt , "a parameter" )
end
local bound = mode ~= "plain" and T . borrowed ( pt ) or pt
c . bindVar ( pname . text , bound , p . type ~= nil , pname , "parameter" )
c . scope . vars [ pname . text ] . mutationParameter = # params
c . fixedWidth . mark ( c . scope . vars [ pname . text ] , pt )
c . fixedWidth . trust ( c . scope . vars [ pname . text ] , pt )
if mode == "exclusive" then
c . own . capabilityFacts ( c . scope . vars [ pname . text ] ) . exclusive = true
end
end
end
end
end
local rets
local retPack


local loopClosure = c . loops . begin ( c . functionDepth )
local wasReturning = c . loops . setReturning ( false )
if node . expr then
local savedYields = c . blockYieldStack
c . blockYieldStack = { }
local observed = { }
c . retStack [ # c . retStack + 1 ] = false
c . retPackStack [ # c . retPackStack + 1 ] = false
c . observedReturnStack [ # c . observedReturnStack + 1 ] = observed
local first = c . infer ( node . expr )
c . observedReturnStack [ # c . observedReturnStack ] = nil
c . retPackStack [ # c . retPackStack ] = nil
c . retStack [ # c . retStack ] = nil
c . blockYieldStack = savedYields
retPack = node . expr . valuePack or T . pack ( { first } )
if # observed > 0 then
if first ~= T . never then
observed [ # observed + 1 ] = retPack
end
retPack = T . packUnion ( observed )
end
rets = retPack . head
for index , result in ipairs ( rets ) do
node . expr . fixedWidthResultIndex = index
if fixedWidth . isValue ( result ) and not c . fixedWidth . established ( node . expr , result ) then
node . fixedWidthCallableUntrusted = true
end
end
else
c . retStack [ # c . retStack + 1 ] = false
c . retPackStack [ # c . retPackStack + 1 ] = false
c . observedReturnStack [ # c . observedReturnStack + 1 ] = false
c . checkBlock ( node . body , true )
c . retStack [ # c . retStack ] = nil
c . retPackStack [ # c . retPackStack ] = nil
c . observedReturnStack [ # c . observedReturnStack ] = nil
rets = { T . any }
retPack = T . pack ( { } , { kind = "unknown" , type = T . any } )
node . fixedWidthCallableUntrusted = true
end
c . loops . setReturning ( wasReturning )
c . loops . finish ( loopClosure , node )
c . popScope ( )
c . unsafeDepth = savedUnsafe

return T . func (
params ,
rets ,
vararg ,
paramModes ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
T . pack ( params , vararg and { kind = "unknown" , type = T . any } or nil , paramModes ) ,
retPack ,
nil ,
nil ,
nil ,
nil ,
paramNames
)
end

return inferSendableLiteral ( node , inferShort )
elseif kind == "istring" then

for _ , e in ipairs ( node . parts ) do
c . infer ( e )
end
return T . string
elseif kind == "tableExpr" then
local positional , named = { } , { }
local elems = { }
local expanded = false
local aggregateMoves , aggregateRoots = { } , { }
local ownsElements = false
local computedKey = false
local rootSeen = { }
if node . affineAggregateContext then
node . affineAggregate = true
end







local function widened ( t ) 
if t . tag == "literal" then
return t . base or T . string
end
return t
end



local function tableValue ( value , valueT ) 
if not c . ownershipKind ( valueT ) then
return valueT
end
local roots = c . ownershipKind ( valueT ) == "borrowed"
and ( c . own . capabilityFacts ( value , nil , false ) . roots or { } )
or { }
local taskScoped = # roots > 0
for _ , root in ipairs ( roots ) do
local state = c . ownershipState ( root )
local rootType = state and rawType ( state . t ) or nil
local origin = rootType
and rootType . tag == "nominal"
and ( ( rootType . origin or rootType ) )
or nil
taskScoped = taskScoped
and origin ~= nil
and ( origin . moduleName or origin . sealedModule ) == "nupp.tasks"
and origin . name == "Scope"
end




if not node . affineAggregateContext and not taskScoped then
c . markTemporaryConsumed ( value )
c . diag (
"NUPP2603" ,
value ,
( c . ownershipKind ( valueT ) ) .. " value cannot be stored in a table"
)
return rawType ( valueT )
end
node . affineAggregate = true
if c . ownershipKind ( valueT ) == "affine" then
ownsElements = true
c . moveExpression ( value , valueT , "affine aggregate element" , "affine" )
if value . automaticOwnerMove then
aggregateMoves [ # aggregateMoves + 1 ] = value . automaticOwnerMove
end
else
for _ , root in ipairs ( roots ) do
if not rootSeen [ root ] then
rootSeen [ root ] = true
aggregateRoots [ # aggregateRoots + 1 ] = root
end
end
end
node . automaticOwnerMoves = aggregateMoves

return rawType ( valueT )
end

local function aggregateType ( valueT ) 
if ownsElements then
return T . affine ( valueT , { } , true )
elseif # aggregateRoots > 0 then
c . own . capabilityFacts ( node ) . roots = aggregateRoots
return T . borrowed ( valueT )
end

return valueT
end

for fieldIndex , f in ipairs ( node . fields ) do
if f . kind == "fieldItem" then
local value = f . value
if value then
local valueT = c . infer ( value )
local expands = fieldIndex == # node . fields and EXPANDS [ value . kind ] and value . valuePack or nil
if expands then



expanded = true
positional [ # positional + 1 ] = widened ( tableValue ( value , valueT ) )
local width = # expands . head
if expands . alternatives then
for _ , arm in ipairs ( expands . alternatives ) do
width = math . max ( width , # arm . head )
end
end
for resultIndex = 2 , width do
local resultT = T . packAt ( expands , resultIndex )
if resultT then
positional [ # positional + 1 ] = widened ( tableValue ( value , resultT ) )
end
end
if expands . tail then
positional [ # positional + 1 ] = widened ( expands . tail . type or T . any )
end
else
local elem = tableValue ( value , valueT )
positional [ # positional + 1 ] = widened ( elem )
elems [ # elems + 1 ] = elem
end
end
elseif f . kind == "fieldNamed" then
local value , fieldName = f . value , f . name
if value and fieldName then
local valueT = c . infer ( value )
valueT = tableValue ( value , valueT )




local keep = valueT . tag == "literal" and ( f . isConst or valueT . base == T . string )
local fieldT = keep and valueT or widened ( valueT )
local field = { name = fieldName . text , read = fieldT }
if not f . isConst then
field . write = fieldT
end
named [ # named + 1 ] = field
end
elseif f . kind == "fieldBracket" then
local value = f . value
if f . key then
c . infer ( f . key )
end
if value then
tableValue ( value , c . infer ( value ) )
end






computedKey = true
end
end
if computedKey then
return aggregateType ( T . table_ )
end
if # named > 0 and # positional == 0 then
return aggregateType ( T . shape ( named , nil , true ) )
elseif # positional > 0 and # named == 0 then



return aggregateType ( T . array ( T . union ( positional ) , not expanded and elems or nil , true ) )
elseif # positional == 0 and # named == 0 then
return T . table_
end
return aggregateType ( T . table_ )
elseif kind == "errorExpr" then
return T . any
end

return T . any
end











local DECLARED_WRITES = { rawset = { 1 } , setmetatable = { 1 } }


local SUSPENDS = { [ "coroutine.yield" ] = true , [ "coroutine.resume" ] = true , }







local CONSERVATIVE_UNKNOWN = false








local function markCallMutation ( node ) 
local dynamic = node
local callee = dynamic . obj
local isMethod = node . kind == "methodCall" or node . kind == "safeCall" and dynamic . name ~= nil
local entry = not isMethod
and callee
and callee . kind == "name"
and callee . token
and c . lookupEntry ( callee . token . text )
or nil
local definition = isMethod and dynamic . name and dynamic . name . definition
or callee and callee . kind == "dotIndex" and callee . name and callee . name . definition
or nil
local summaries = c . facts . summaries ( )
local syntactic , calleeKnown = mutationSummaries . callEffects ( summaries , node )
local mutation = definition or entry and ( entry . definition or entry ) or { }
local checked = entry and entry . mutationSummaryKnown or mutation . mutationSummaryKnown or false
local key = not isMethod and mutationSummaries . keyOf ( callee ) or nil



local declared = false
if definition then
declared = definition . filename ~= c . filename
and ( definition . kind == "function" or definition . kind == "method" )
elseif entry and not entry . definition then
declared = true
end

local function add ( value , paths ) 
while value and ( value . kind == "paren" or value . kind == "castExpr" ) do
value = value . expr
end
local key = value and c . pathKey ( value ) or nil
if not key then
return
end
c . callMayMutate = true
if not paths then
c . callMutationRoots = c . callMutationRoots or { }
c . callMutationRoots [ key ] = true
return
end


for path in pairs ( paths ) do
if path : sub ( -1 ) == "*" then
c . callMutationRoots = c . callMutationRoots or { }
c . callMutationRoots [ key .. path : sub ( 1 , -2 ) ] = true
else
c . callMutatedNames = c . callMutatedNames or { }
c . callMutatedNames [ key .. path ] = true
end
end
end

local function forgetName ( name ) 
c . callMayMutate = true
c . callMutatedNames = c . callMutatedNames or { }
c . callMutatedNames [ name ] = true
end



local receiverT = isMethod and dynamic . obj and rawType ( dynamic . obj . inferredType or T . any ) or nil
local throughInterface = receiverT ~= nil and receiverT . tag == "nominal" and receiverT . declKind == "interface"
if isMethod and throughInterface then
add ( dynamic . obj )
elseif isMethod and mutation . mutatesSelf then
add ( dynamic . obj , mutation . mutatesSelfPaths )
end
local args = dynamic . args
local mutatesParams = entry and entry . mutatesParams or mutation . mutatesParams
local mutatesParamPaths = entry and entry . mutatesParamPaths or mutation . mutatesParamPaths
local signature = dynamic . signatureType
local paramNames = signature and signature . tag == "func" and signature . paramNames or nil
local declaredWrites = key and DECLARED_WRITES [ key ] or nil
local unknown = not calleeKnown and not checked and not declared and not declaredWrites
local suspends = key ~= nil and SUSPENDS [ key ] == true
if args and args . kind == "args" then
local position = 0
for _ , argument in ipairs ( args . exprs or { } ) do
if not cst . isToken ( argument ) then
position = position + 1
local value = argument
local index = position
if argument . kind == "namedArg" then
value = argument . value
index = 0
local wanted = argument . name and argument . name . text or nil
local names = paramNames or syntactic and syntactic . paramNames or { }
for j , paramName in ipairs ( names ) do
if paramName == wanted then
index = j
do break end
end
end
elseif argument . kind == "pluckArg" then
value = argument . value
end
local written = mutatesParams and mutatesParams [ index ]
for _ , at in ipairs ( declaredWrites or { } ) do
if at == index then
written = true
end
end
if written or unknown and false then
add ( value , mutatesParamPaths and mutatesParamPaths [ index ] or nil )
end
end
end
end


mutationSummaries . eachWrite ( summaries , node , function ( writtenKey , below ) 
c . callMayMutate = true
if below then
c . callMutationRoots = c . callMutationRoots or { }
c . callMutationRoots [ writtenKey ] = true
else
c . callMutatedNames = c . callMutatedNames or { }
c . callMutatedNames [ writtenKey ] = true
end
end )
if suspends or ( unknown or syntactic and syntactic . unknown ) and false then



local sc = c . scope
local seen = { }
while sc do
for name , visible in pairs ( sc . vars ) do
if not seen [ name ] then
seen [ name ] = true
local outer = ( visible . functionDepth or 0 ) < c . functionDepth
if summaries . capturedAnywhere [ name ] or outer and summaries . assignedAnywhere [ name ] then
forgetName ( name )
end
end
end
sc = sc . parent
end
end
local mutatesCapturedEntries = entry and entry . mutatesCapturedEntries or mutation . mutatesCapturedEntries
if mutatesCapturedEntries then
c . callMayMutate = true
c . callMutatedEntries = c . callMutatedEntries or { }
for mutated in pairs ( mutatesCapturedEntries ) do
c . callMutatedEntries [ mutated ] = true
end
end
local mutatesCapturedPaths = entry and entry . mutatesCapturedPaths or mutation . mutatesCapturedPaths
if mutatesCapturedPaths then
local function visibleName ( wanted ) 
local scope = c . scope
while scope do
for name , candidate in pairs ( scope . vars ) do
if candidate == wanted then
return name
end
end
scope = scope . parent
end
end

for mutated in pairs ( mutatesCapturedPaths ) do
local name = visibleName ( mutated )
if name then
c . callMayMutate = true
c . callMutationRoots = c . callMutationRoots or { }
c . callMutationRoots [ name ] = true
end
end
end
end

local function inferValue ( node ) 
if not EXPANDS [ node . kind ] then
local inferred = inferExpr ( node )
if node . kind == "call"
or node . kind == "methodCall"
or node . kind == "safeCall"
or node . kind == "newExpr"
then
markCallMutation ( node )
end
local dynamic = node
dynamic . inferredType = inferred
if c . ownershipKind ( inferred ) == "affine"
and (
node . kind == "call"
or node . kind == "methodCall"
or node . kind == "safeCall"
or node . kind == "newExpr"
)
then
c . own . temporaryProduced ( node )
end
return inferred
end



node . valuePack = nil
node . fixedWidthEstablished = nil
node . fixedWidthTrusted = nil
node . fixedWidthResultEstablished = nil
node . fixedWidthResultTrusted = nil
node . fixedWidthUntrustedResult = nil
local first = inferExpr ( node )
if node . kind == "call" or node . kind == "methodCall" or node . kind == "safeCall" or node . kind == "newExpr" then
markCallMutation ( node )
end
local dynamic = node
dynamic . inferredType = first
if c . ownershipKind ( first ) == "affine"
and ( node . kind == "call" or node . kind == "methodCall" or node . kind == "safeCall" or node . kind == "newExpr" )
then
c . own . temporaryProduced ( node )
end
if fixedWidth . isValue ( first ) and not node . fixedWidthUntrustedResult then
c . fixedWidth . mark ( node , first )
end
if not node . fixedWidthUntrustedResult then
c . fixedWidth . trust ( node , first )
end





node . valuePack = node . valuePack or T . pack ( { first } )
for index , result in ipairs ( node . valuePack . head or { } ) do
if fixedWidth . isValue ( result ) and not node . fixedWidthUntrustedResult then
node . fixedWidthResultEstablished = node . fixedWidthResultEstablished or { }
node . fixedWidthResultEstablished [ index ] = { [ T . unwrapOwnership ( result ) . tag ] = true }
end
if fixedWidth . requiresTrust ( result ) and not node . fixedWidthUntrustedResult then
node . fixedWidthResultTrusted = node . fixedWidthResultTrusted or { }
node . fixedWidthResultTrusted [ index ] = true
end
end

return first
end




local pendingUnsafe = { }
local validatedAnnotations


= { }

local function validateExpressionAnnotation ( application , target ) 
local cached = validatedAnnotations [ application ]
if cached then
return cached . definition , cached . valid
end
local definition , valid = c . marks . validateAnnotation ( application , target )
validatedAnnotations [ application ] = { definition = definition , valid = valid }

return definition , valid
end

c . infer = function ( node ) 
if not node . expressionAnnotations and not pendingUnsafe [ node ] then
return inferValue ( node )
end
local authorized = pendingUnsafe [ node ] == true
for _ , application in ipairs ( node . expressionAnnotations or { } ) do
local definition , valid = validateExpressionAnnotation ( application , node )
authorized = authorized or ( valid and definition and definition . name == "unsafe" )
end
if authorized and node . expressionPermissionOperand then
local operand = node . expressionPermissionOperand
local previous = pendingUnsafe [ operand ]
pendingUnsafe [ operand ] = true
local ok , result = pcall ( inferValue , node )
pendingUnsafe [ operand ] = previous
if not ok then
error ( result , 0 )
end
return result
elseif authorized then
return c . withUnsafe ( true , function ( ) 
return inferValue ( node )
end )
end

return inferValue ( node )
end

c . apply . inferExpected = function ( node , expected ) 
if not expected then
return c . infer ( node )
end
local expectedFunc = rawType ( expected )
local contextualNoSuspend = expectedFunc . tag == "func" and ( expectedFunc ) . noYield == true
if contextualNoSuspend and ( node . kind == "shortfn" or node . kind == "funcExpr" ) then
local body = node . kind == "funcExpr" and node . body and node . body . body or node . body
c . nosuspend . region ( { body = body } )
c . noSuspendDepth = c . noSuspendDepth + 1
end

local function finish ( inferred ) 
if contextualNoSuspend and ( node . kind == "shortfn" or node . kind == "funcExpr" ) then
c . noSuspendDepth = c . noSuspendDepth - 1
return T . withOwnershipPayload ( inferred , T . withYields ( rawType ( inferred ) , false ) )
end

return inferred
end

if node . kind == "shortfn" then
if rawType ( expected ) . tag == "func" and ( rawType ( expected ) ) . sendable then
node . sendableContext = true
end
expectedShortfns [ node ] = expected
local inferred = c . infer ( node )
expectedShortfns [ node ] = nil
return finish ( inferred )
elseif node . kind == "funcExpr" and node . body then


for _ , application in ipairs ( node . expressionAnnotations or { } ) do
validateExpressionAnnotation ( application , node )
end
if rawType ( expected ) . tag == "func" and ( rawType ( expected ) ) . sendable then
node . sendableContext = true
end
local inferred = inferSendableLiteral ( node , function ( ) 
return c . apply . checkFuncbodyExpected ( node . body , expected )
end )
if not node . body . returnPack then
node . fixedWidthCallableUntrusted = true
end
local captures = ( node . body ) . borrowCaptures or { }
if # captures > 0 then
local roots = { }
for _ , capture in ipairs ( captures ) do
roots [ # roots + 1 ] = capture . root
end
c . own . capabilityFacts ( node ) . roots = roots
if not c . ownershipKind ( inferred ) then
inferred = T . borrowed ( inferred )
end
end
return finish ( inferred )
end

return c . infer ( node )
end
end

local __nuppExportValue= expr ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.expr"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.expr"]=__nuppExports;return __nuppExports