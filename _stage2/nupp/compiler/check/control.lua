_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local narrowing = require ( "nupp.compiler.narrowing" )
local cst = require ( "nupp.compiler.cst" )
local state = require ( "nupp.compiler.check.state" )

local isA = relations . isA
local packIsA = relations . packIsA
local rawType = T . unwrapOwnership
local memberSet = narrowing . memberSet

local control = { }

local LITERAL_KINDS

= { string = true , number = true , nilExpr = true , trueExpr = true , falseExpr = true , }




local function literalEquality ( stat )
if stat . elseClause or # ( stat . clauses or { } ) ~= 1 then
return nil , nil
end
local clause = stat . clauses [ 1 ]
local cond = clause and clause . cond
if not cond or cond . kind ~= "binop" or not cond . op or cond . op . kind ~= "==" then
return nil , nil
end
local lhs , rhs = cond . lhs , cond . rhs
local name , literal = nil , nil
if lhs and lhs . kind == "name" and rhs and LITERAL_KINDS [ rhs . kind ] then
name , literal = lhs , rhs
elseif rhs and rhs . kind == "name" and lhs and LITERAL_KINDS [ lhs . kind ] then
name , literal = rhs , lhs
end
local nameTok , literalTok = name and name . token , literal and cst . firstToken ( literal )
if not nameTok or not literalTok then
return nil
end

return { name = nameTok . text , literal = literalTok . text }
end



local function writesName ( body , name )
if not body or cst . isToken ( body ) or body . kind == "funcbody" or body . kind == "shortfn" then
return false
end
local function isName ( node )
if not node or node . kind ~= "name" or not node . token then
return false
end
return node . token . text == name
end

if body . kind == "compoundAssign" and isName ( body . target ) then
return true
end
if body . kind == "assignStmt" then
for _ , target in ipairs ( body . targets or { } ) do
if isName ( target ) then
return true
end
end
end
for _ , child in ipairs ( body ) do
if not cst . isToken ( child ) and writesName ( child , name ) then
return true
end
end

return false
end


local function isLocal ( c , name )
local scope = c . scope
while scope do
if scope . vars and scope . vars [ name ] then
return true
end
scope = scope . parent
end

return false
end





function control . install ( c )



local function returnFits ( got , expected , expr )
if ( c . comptimeFunctionDepth or 0 ) > 0 and got == T . type_ and expected . tag == "typeHandle" then
return true , nil , false
end
return c . fixedWidth . fits ( got , expected , expr )
end

local own , facts = c . own , c . facts
local mergeFacts , snapshotNarrowed = facts . mergeFacts , facts . snapshotNarrowed
local provenanceOwners = own . provenanceOwners
local alwaysExits = c . alwaysExits
local analyzeCond , applyFacts = c . analyzeCond , c . applyFacts
local borrowRoot , moveExpression = c . borrowRoot , c . moveExpression
local ownershipKind , ownershipState = c . ownershipKind , c . ownershipState









local function regionSignature ( regions )
local keys = { }
for path , count in pairs ( regions or { } ) do
if count > 0 then
keys [ # keys + 1 ] = path .. "=" .. tostring ( count )
end
end
table . sort ( keys )

return table . concat ( keys , ";" )
end

local function ownershipSnapshot ( )
local seen , snapshot = { } , { }
local scope = c . scope
while scope do
for _ , entry in pairs ( scope . vars or { } ) do
local state = ownershipState ( entry )
if state and state . ownership and not seen [ state ] then
seen [ state ] = true
snapshot [
# snapshot + 1
] = {
state = state ,
moved = state . moved or false ,
movedAt = state . movedAt ,
retained = own . capabilityFacts ( state , nil , false ) . retention ~= nil ,
capability = own . capabilityOf ( state . t , state ) . id ,
activeBorrows = state . activeBorrows or 0 ,
activeExclusiveBorrows = state . activeExclusiveBorrows or 0 ,
activeRegions = regionSignature ( state . activeRegions ) ,
activeExclusiveRegions = regionSignature ( state . activeExclusiveRegions ) ,
}
end
end
scope = scope . parent
end

return snapshot
end



local function ownershipRewind ( snapshot , moved )
for _ , item in ipairs ( snapshot ) do
if item . state . moved and not item . moved then
moved [ item . state ] = true
end
item . state . moved , item . state . movedAt = item . moved , item . movedAt
end
end






local function checkLoopBackEdge ( snapshot , body , at )
if alwaysExits ( body ) then
return
end
for _ , item in ipairs ( snapshot ) do
local state = item . state
local capabilityChanged = own . capabilityOf (
state . t ,
state
) . id ~= item . capability or (
state . activeBorrows or 0
) ~= item . activeBorrows or ( state . activeExclusiveBorrows or 0 ) ~= item . activeExclusiveBorrows
capabilityChanged = capabilityChanged or regionSignature (
state . activeRegions
) ~= item . activeRegions or regionSignature ( state . activeExclusiveRegions ) ~= item . activeExclusiveRegions
if state . moved ~= item . moved or (
own . capabilityFacts ( state , nil , false ) . retention ~= nil
) ~= item . retained or capabilityChanged then
c . diag (
"NUPP2609" ,
state . movedAt or at ,
"loop back edge changes a live capability from the state at the loop header" ,
nil ,
{
help = "finish the capability inside each iteration, move it into an explicit loop-carried place, or make this path leave the loop" ,
related = { c . related ( at , "this repeatable loop creates the back edge" ) } ,
}
)
end
end
end

local handlers = { }

handlers . returnStmt = function ( stat )
local annotated = c . retStack [ # c . retStack ]
local annotatedPack = c . retPackStack [ # c . retPackStack ]
local wasReturning = c . loops . setReturning ( true )
local returnedPack = c . inferListPack ( stat . exprs )
local ts = returnedPack . head
c . loops . setReturning ( wasReturning )
local function returnedExpression ( result )
local exprs = stat . exprs or { }
if result <= # exprs then
return exprs [ result ]
end
local expanded = exprs [ # exprs ]
if expanded and expanded . returnPartitionFields then
return { partitionFields = expanded . returnPartitionFields [ result - # exprs + 1 ] }
end

return nil
end

local function fixedExpression ( result )
local exprs = stat . exprs or { }
if result < # exprs then
return exprs [ result ]
end
local expanded = exprs [ # exprs ]
if expanded then
expanded . fixedWidthResultIndex = result - # exprs + 1
end

return expanded
end

local function partitionFieldsOf ( returned )
while returned and ( returned . kind == "paren" or returned . kind == "castExpr" ) do
returned = returned . expr
end
return returned and returned . partitionFields or nil
end

local functionBody = c . functionBodies [ # c . functionBodies ]
if functionBody then
for result = 1 , # ts do
local returned = returnedExpression ( result )
local fields = partitionFieldsOf ( returned )
local seen = functionBody . partitionReturnSeen or { }
functionBody . partitionReturnSeen = seen
local prior = seen [ result ]
if prior == nil then
seen [ result ] = fields or false
elseif prior and fields then
for name , region in pairs ( prior ) do
if fields [ name ] ~= region then
seen [ result ] = false
break
end
end
if seen [ result ] then
for name , region in pairs ( fields ) do
if prior [ name ] ~= region then
seen [ result ] = false
break
end
end
end
else
seen [ result ] = false
end
functionBody . partitionResults = functionBody . partitionResults or { }
if seen [ result ] then
functionBody . partitionResults [ result ] = seen [ result ]
else
functionBody . partitionResults [ result ] = nil
end
end
end
for j , valueT in ipairs ( ts ) do
local borrowContract = j == 1 and c . borrowReturnStack [ # c . borrowReturnStack ] or nil
if borrowContract then
local expected , missing = { } , nil
for _ , sourceToken in ipairs ( borrowContract . params or { borrowContract . param } ) do
local source = ownershipState ( c . lookupEntry ( sourceToken . text ) )
if source then
expected [ # expected + 1 ] = borrowRoot ( source )
end
end
local actual = provenanceOwners ( stat . exprs [ j ] )
for _ , source in ipairs ( expected ) do
local found = false
for _ , candidate in ipairs ( actual ) do
if candidate == source then
found = true
end
end
if not found then
missing = true
end
end
if missing then
c . diag ( "NUPP2619" , stat . exprs [ j ] or stat , "cannot prove all declared borrowed-result sources" )
end
end
if ownershipKind ( valueT ) == "borrowed" and not ( j == 1 and c . borrowReturnStack [ # c . borrowReturnStack ] ) then
local expr = stat . exprs [ j ] or stat
local root = provenanceOwners ( expr ) [ 1 ]
local related = root and root . definition and c . related (
root . definition ,
"borrowed source is declared here"
) or nil
local ownReturns = c . ownReturnStack [ # c . ownReturnStack ]
local ownCode = ownReturns and ownReturns [ j ] and "NUPP2616" or nil
c . diag (
ownCode or "NUPP2608" ,
expr ,
ownCode and "an owning result cannot retain an input borrow" or "borrowed value cannot be returned" ,
nil ,
{
help = "return a value owned by the caller, or declare the result with `borrows (source)`" ,
related = related and { related } or nil ,
}
)
elseif ownershipKind ( valueT ) == "affine" or ownershipKind ( valueT ) == "pinned" then

local valueKind = ownershipKind ( valueT )
local expected = annotatedPack and T . packAt (
annotatedPack ,
j
) or ( c . retStack [ # c . retStack ] and c . retStack [ # c . retStack ] [ j ] or nil )
local ownReturns = c . ownReturnStack [ # c . ownReturnStack ]
local capabilityResult = expected and ownReturns and ownReturns [
j
] and rawType ( expected ) . id == rawType ( valueT ) . id
if # c . retStack == 0 then
c . diag ( "NUPP2603" , stat . exprs [ j ] or stat , valueKind .. " value cannot be exported as module state" )
elseif not expected or ownershipKind ( expected ) ~= valueKind and not capabilityResult then
c . diag (
expected == T . any and "NUPP2611" or "NUPP2603" ,
stat . exprs [ j ] or stat ,
expected == T . any
and "a live capability cannot be erased into an any result"
or valueKind
.. " return needs a matching annotation"
)
else
local source = ownershipState ( ( c . ownershipEntry ( stat . exprs [ j ] ) ) )
local promoted = ownReturns and ownReturns [ j ] and source and ownershipKind ( source . t ) ~= valueKind
if not promoted then
moveExpression ( stat . exprs [ j ] , valueT , "return" , valueKind )
end
end
end
end
if # c . retStack == 0 and not c . moduleType then
c . moduleType = ts [ 1 ]



c . moduleReturnValue = stat . exprs and stat . exprs [ 1 ] or nil




local returned = stat . exprs and stat . exprs [ 1 ]
local returnedName = returned and returned . kind == "name" and returned . token or nil
if c . moduleType == T . table_
and not c . moduleLocalAnnotated
and returnedName
and returnedName . text == c . moduleLocal
then
local fields = { }
for name , ft in pairs ( c . moduleFields ) do
if c . moduleFieldConst [ name ] then
fields [ # fields + 1 ] = { name = name , read = ft }
else
fields [ # fields + 1 ] = { name = name , type = ft }
end
end
if # fields > 0 then
c . moduleType = T . shape ( fields )



c . moduleTypeFromFields = true
end
end
if c . opts and c . opts . strict and c . moduleType then


local function untyped ( t )
if t == nil then
return false
end
if t == T . any then
return true
end
if t . tag == "func" then
for _ , p in ipairs ( t . params ) do
if p == T . any then
return true
end
end
for _ , r in ipairs ( t . rets ) do
if r == T . any then
return true
end
end
end

return false
end

local shape = c . moduleType
if shape . tag == "shape" then
for _ , field in ipairs ( shape . fields ) do
if untyped ( field . read or field . type ) then
c . diag (
"NUPP2106" ,
c . moduleFieldTokens [ field . name ] or stat ,
( "exported %q needs a type annotation" ) : format ( field . name )
)
end
end
elseif untyped ( shape ) then
c . diag ( "NUPP2106" , stat , "the module's exported value needs a type annotation" )
end
end
end
local ownReturns = c . ownReturnStack [ # c . ownReturnStack ]
if annotated and not annotatedPack then
for j , rt in ipairs ( annotated ) do
local got = ts [ j ] or T . nil_
local expected = rt
local expr = fixedExpression ( j )
local freshConstruction = expr and (
expr . kind == "newExpr" or expr . kind == "call" and expr . recordConstruct ~= nil
)




if ownReturns and ownReturns [ j ] and ( not ownershipKind ( got ) or freshConstruction ) then
expected = ownReturns [ j ]
got = rawType ( got )
end
local ok , why , reported = returnFits ( got , expected , expr or stat )
if not ok and not reported then
c . diag ( "NUPP2002" , stat . exprs and stat . exprs [ j ] or stat , ( "return %d: %s" ) : format ( j , why ) )
end
end
if # ts > # annotated then
c . diag ( "NUPP2002" , stat , ( "too many return values (expected %d, got %d)" ) : format ( # annotated , # ts ) )
end
end



if annotatedPack then
if annotatedPack . alternatives then
local ok , why = packIsA ( returnedPack , annotatedPack )
if not ok then
c . diag (
"NUPP2010" ,
stat ,
"returned pack does not match a declared alternative: " .. ( why or "incompatible packs" )
)
end
return
end
for j , expected in ipairs ( annotatedPack . head ) do
local got = T . packAt ( returnedPack , j ) or T . nil_
local expr = fixedExpression ( j )
local freshConstruction = expr and (
expr . kind == "newExpr" or expr . kind == "call" and expr . recordConstruct ~= nil
)
if ownReturns and ownReturns [ j ] and ( not ownershipKind ( got ) or freshConstruction ) then
expected = ownReturns [ j ]
got = rawType ( got )
end
local ok , why , reported = returnFits ( got , expected , expr or stat )
if not ok and not reported then
c . diag ( "NUPP2002" , stat . exprs and stat . exprs [ j ] or stat , ( "return %d: %s" ) : format ( j , why ) )
end
end
if not annotatedPack . tail and not returnedPack . tail and # returnedPack . head > # annotatedPack . head then
c . diag (
"NUPP2002" ,
stat ,
( "too many return values (expected %d, got %d)" ) : format ( # annotatedPack . head , # returnedPack . head )
)
elseif annotatedPack . tail and annotatedPack . tail . kind == "homogeneous" then
for j = # annotatedPack . head + 1 , # returnedPack . head do
local expr = fixedExpression ( j )
local ok , why , reported = returnFits ( returnedPack . head [ j ] , annotatedPack . tail . type , expr or stat )
if not ok and not reported then
c . diag ( "NUPP2002" , stat , ( "return %d: %s" ) : format ( j , why ) )
end
end
elseif annotatedPack . tail and annotatedPack . tail . kind == "generic" and (
not returnedPack . tail
or returnedPack . tail . kind ~= "generic"
or returnedPack . tail . var ~= annotatedPack . tail . var
) then
c . diag ( "NUPP2010" , stat , "returned values do not preserve the declared generic pack" )
end
end
end

handlers . ifStmt = function ( stat )
local adjacent = c . nextStat
local first = literalEquality ( stat )
local second = adjacent and adjacent . kind == "ifStmt" and literalEquality ( adjacent ) or nil
local firstClause = stat . clauses and stat . clauses [ 1 ] or nil
local firstEnd = cst . lastToken ( stat )
local nextIf = adjacent and cst . firstToken ( adjacent ) or nil
if first and second and first . name == second . name and first . literal ~= second . literal and isLocal (
c ,
first . name
) and not writesName ( firstClause and firstClause . body , first . name ) and firstEnd and nextIf then
c . diag (
"else-if" ,
adjacent ,
"this condition is mutually exclusive with the preceding if; write elseif instead" ,
{
c . edits . fix (
"write `elseif`" ,
c . edits . replaceToken ( firstEnd , "" ) ,
c . edits . replaceToken ( nextIf , "elseif" )
) ,
} ,
{ help = "replace the second if with elseif and remove the preceding end" }
)
end
local otherwise = stat . elseClause
local elseBody = otherwise and otherwise . kind == "elseClause" and otherwise . body or nil
local elseStats = elseBody and elseBody . kind == "block" and elseBody . stats or { }



local nested = # elseStats == 1 and elseStats [ 1 ] . kind == "ifStmt" and elseStats [ 1 ] or nil
local elseTok = otherwise and cst . firstToken ( otherwise ) or nil
local nestedIf = nested and cst . firstToken ( nested ) or nil
local nestedEnd = nested and cst . lastToken ( nested ) or nil
local fixes = nested and elseTok and nestedIf and nestedEnd and {
c . edits . fix (
"write `elseif`" ,
c . edits . replaceToken ( elseTok , "elseif" ) ,
c . edits . replaceToken ( nestedIf , "" ) ,
c . edits . replaceToken ( nestedEnd , "" )
) ,
} or nil
if nested then
c . diag ( "else-if" , otherwise , "this else contains only an if; write elseif instead" , fixes , {
help = "replace else followed by if with elseif"
} )
end
local accumulatedElse = { }
local firstFacts = nil




local dispatchKey , dispatchStart , dispatchTotal = nil , nil , false
local allBranchesLeave = true



local paths = { }
local ownershipBefore = ownershipSnapshot ( )
local branchMoved = { }
for _ , clause in ipairs ( stat . clauses ) do


c . pushScope ( )
applyFacts ( accumulatedElse )
local facts = { t = { } , f = { } }
local cond , body = nil , nil
if clause . kind == "ifClause" or clause . kind == "elseifClause" then
cond , body = clause . cond , clause . body
end
if cond then
c . infer ( cond )
facts = analyzeCond ( cond )
end
firstFacts = firstFacts or facts
applyFacts ( facts . t )
c . checkBlock ( body , true )
if not alwaysExits ( body ) then
paths [ # paths + 1 ] = snapshotNarrowed ( )
end
c . popScope ( )
ownershipRewind ( ownershipBefore , branchMoved )
accumulatedElse = mergeFacts ( accumulatedElse , facts . f )
if cond then
local key , seen = nil , 0
for k in pairs ( facts . t ) do
key = k ;
seen = seen + 1
end
if seen == 1 and ( dispatchKey == nil or dispatchKey == key ) then
if not dispatchKey then
dispatchKey = key
local test = cond
if test . kind == "binop" then
dispatchStart = ( test . lhs and c . refType ( test . lhs ) ) or ( test . rhs and c . refType ( test . rhs ) )
end
end
if facts . exhausted == key then
dispatchTotal = true
end
else
dispatchKey = false
end
end
if not alwaysExits ( body ) then
allBranchesLeave = false
end
end
if dispatchKey
and dispatchKey ~= false
and not stat . elseClause
and allBranchesLeave
and not dispatchTotal
and memberSet (
dispatchStart
) then
local remaining = accumulatedElse [ dispatchKey ]
local missing = remaining and memberSet ( remaining ) or nil
if missing and # missing > 0 then
local names = { }
for j , m in ipairs ( missing ) do
names [ j ] = ( "%q" ) : format ( m . tag == "literal" and m . constant or "?" )
end
table . sort ( names )
c . diag (
"NUPP2107" ,
stat ,
(
"every branch returns, so this handles %s and leaves " .. "%s unhandled"
) : format ( T . tostring ( dispatchStart ) , table . concat ( names , ", " ) ) ,
nil ,
{ help = "add branches for " .. table . concat ( names , ", " ) .. " or add an else clause" }
)
end
end
if otherwise then
c . pushScope ( )
applyFacts ( accumulatedElse )
c . checkBlock ( elseBody , true )
if not alwaysExits ( elseBody ) then
paths [ # paths + 1 ] = snapshotNarrowed ( )
end
c . popScope ( )
ownershipRewind ( ownershipBefore , branchMoved )
else

c . pushScope ( )
applyFacts ( accumulatedElse )
paths [ # paths + 1 ] = snapshotNarrowed ( )
c . popScope ( )
end



for state in pairs ( branchMoved ) do
state . moved = true
end



if # paths > 0 then
local joined = { }
for key , t in pairs ( paths [ 1 ] ) do
local members = { t }
local everywhere = true
for j = 2 , # paths do
local other = paths [ j ] [ key ]
if not other then
everywhere = false
break
end
members [ # members + 1 ] = other
end
if everywhere then
joined [ key ] = T . union ( members )
end
end
applyFacts ( joined )
end
end

handlers . whileStmt = function ( stat )
local cond = stat . cond
if cond then
local ownershipBefore = ownershipSnapshot ( )
for _ , item in ipairs ( ownershipBefore ) do
item . retained = own . capabilityFacts ( item . state , nil , false ) . retention ~= nil
end
c . infer ( cond )
local facts = analyzeCond ( cond )
c . pushScope ( )
applyFacts ( facts . t )
c . loops . push ( stat . body )
c . checkBlock ( stat . body , true )
c . loops . pop ( )
c . popScope ( )
checkLoopBackEdge ( ownershipBefore , stat . body , stat )
end
end

handlers . repeatStmt = function ( stat )

local ownershipBefore = ownershipSnapshot ( )
for _ , item in ipairs ( ownershipBefore ) do
item . retained = own . capabilityFacts ( item . state , nil , false ) . retention ~= nil
end
c . pushScope ( )
c . loops . push ( stat . body )
c . checkBlock ( stat . body , true )
c . loops . pop ( )
if stat . cond then
c . infer ( stat . cond )
end
c . popScope ( )
checkLoopBackEdge ( ownershipBefore , stat . body , stat )
end

handlers . doStmt = function ( stat )
c . pushScope ( ) ;
c . checkBlock ( stat . body , true ) ;
c . popScope ( )
end

handlers . handleStmt = function ( stat )




if stat . handler then
local actual = c . infer ( stat . handler )
local exports = c . env and c . env . resolveModuleExports and c . env . resolveModuleExports (
c . env ,
"nupp.suspension"
) or nil
local expected = exports and exports . types and exports . types . Handler or nil
if expected then
local ok , why = isA ( actual , expected )
if not ok then
c . diag (
"NUPP2001" ,
stat . handler ,
"suspension handler: " .. ( why or ( T . tostring ( actual ) .. " is not " .. T . tostring ( expected ) ) )
)
end
end
end




local inside , labels = { } , { }
local function collect ( node )
if not node or cst . isToken ( node ) then
return
end
inside [ node ] = true
if node ~= stat . body and (
node . kind == "funcExpr"
or node . kind == "shortfn"
or node . kind == "localFuncStmt"
or node . kind == "funcStmt"
) then
return
end
if node . kind == "labelStmt" and node . name then
labels [ node . name . text ] = true
end
for _ , child in ipairs ( node ) do
collect ( child )
end
end

collect ( stat . body )
if next ( labels ) then
local targetFunction = nil
local function locate ( node , currentFunction )
if not node or cst . isToken ( node ) then
return false
end
local nextFunction = currentFunction
if node . kind == "funcExpr"
or node . kind == "shortfn"
or node . kind == "localFuncStmt"
or node . kind == "funcStmt"
then
nextFunction = node
end
if node == stat then
targetFunction = nextFunction
return true
end
for _ , child in ipairs ( node ) do
if locate ( child , nextFunction ) then
return true
end
end

return false
end

locate ( c . result . root , nil )
local function refuse ( node , currentFunction )
if not node or cst . isToken ( node ) then
return
end
local nextFunction = currentFunction
if node . kind == "funcExpr"
or node . kind == "shortfn"
or node . kind == "localFuncStmt"
or node . kind == "funcStmt"
then
nextFunction = node
end
if nextFunction == targetFunction and not inside [
node
] and node . kind == "gotoStmt" and node . name and labels [
node . name . text
] and not node . handledEntryDiagnosed then
node . handledEntryDiagnosed = true
c . diag ( "NUPP2706" , node , "control cannot enter a `handle suspension` region" , nil , {
help = "move the label outside the handled region"
} )
end
for _ , child in ipairs ( node ) do
refuse ( child , nextFunction )
end
end

refuse ( c . result . root , nil )
end



if c . recordEffect then
c . recordEffect ( "runtime.suspension" )
end
stat . compilerFeatureEffects = { "runtime.suspension" }
c . handledDepth = c . handledDepth + 1
c . pushScope ( )
c . checkBlock ( stat . body , true )
c . popScope ( )
c . handledDepth = c . handledDepth - 1
end

handlers . noSuspendStmt = function ( stat )
c . noSuspendDepth = c . noSuspendDepth + 1
c . pushScope ( )
c . checkBlock ( stat . body , true )
c . popScope ( )
c . noSuspendDepth = c . noSuspendDepth - 1
end

handlers . effectRegionStmt = function ( stat )
local effect = stat . effect
c . effectRegionDepths [ effect ] = ( c . effectRegionDepths [ effect ] or 0 ) + 1
c . effectRegions . region ( stat )
c . pushScope ( )
c . checkBlock ( stat . body , true )
c . popScope ( )
c . effectRegionDepths [ effect ] = ( c . effectRegionDepths [ effect ] or 1 ) - 1
end

handlers . unsafeStmt = function ( stat )
c . unsafeDepth = c . unsafeDepth + 1
c . pushScope ( ) ;
c . checkBlock ( stat . body , true ) ;
c . popScope ( )
c . unsafeDepth = c . unsafeDepth - 1
end

handlers . fornumStmt = function ( stat )
local from , to , var = stat . start , stat . stop , stat . var
if not from or not to or not var then
return
end
local st = c . infer ( from )
local et = c . infer ( to )
if stat . step then
c . infer ( stat . step )
end
c . numericOperand ( st , from , "for" )
c . numericOperand ( et , to , "for" )
local ownershipBefore = ownershipSnapshot ( )
for _ , item in ipairs ( ownershipBefore ) do
item . retained = own . capabilityFacts ( item . state , nil , false ) . retention ~= nil
end
c . pushScope ( )
c . scope . completionScope = stat . body
c . bindVar ( var . text , ( isA ( st , T . integer ) and isA ( et , T . integer ) ) and T . integer or T . number , false , var )


local function rangeField ( node , field )
if not node or node . kind ~= "dotIndex" or not node . name or node . name . text ~= field then
return nil
end
local object = node . obj

return object and object . kind == "name" and object . token and object . token . definition or nil
end

local rangeDefinition = not stat . step and rangeField ( from , "first" ) or nil
local witness = rangeDefinition and rangeDefinition == rangeField (
to ,
"last"
) and rangeDefinition . spanRangeWitness or nil
c . loops . push ( stat . body )
c . checkBlock ( stat . body , true )
if witness and stat . body and var . definition then
local function markRangeAccess ( node )
if not node or cst . isToken ( node ) then
return
end
if node . kind == "methodCall" and node . spanAccessorNoAllocate then
local receiver = node . obj
local receiverDefinition = receiver
and receiver . kind == "name"
and receiver . token
and receiver . token . definition
or nil
local args = node . args and node . args . kind == "args" and node . args . exprs or { }
local index = args [ 1 ]
local indexDefinition = index
and index . kind == "name"
and index . token
and index . token . definition
or nil
if witness . spans [ receiverDefinition ] and indexDefinition == var . definition then
node . rangeProvenNoRaise = true
end
end
for _ , child in ipairs ( node ) do
markRangeAccess ( child )
end
end

markRangeAccess ( stat . body )
end
c . loops . pop ( )
c . popScope ( )
checkLoopBackEdge ( ownershipBefore , stat . body , stat )
end

handlers . forinStmt = function ( stat )


local iterT = nil
for j , e in ipairs ( stat . exprs or { } ) do
local t = c . infer ( e )
if j == 1 then
iterT = t
end
end
local iterator = stat . exprs and stat . exprs [ 1 ]
local callee = iterator and iterator . kind == "call" and iterator . obj or nil
local calleeTok = callee and callee . kind == "name" and callee . token or nil
local global = c . env and c . env . globals and c . env . globals . ipairs or nil
local args = nil
if iterator and iterator . kind == "call" then
args = iterator . args
end
local operands = args and args . kind == "args" and args . exprs or { }
local operand = # operands == 1 and operands [ 1 ] or nil
local operandType = operand and c . refType ( operand ) or nil
if calleeTok
and calleeTok . text == "ipairs"
and global
and calleeTok . definition == global . definition
and operand
and global . definition
and global . definition . constant
and operand . kind == "name"
and operandType
and operandType . tag == "array"
then
stat . builtinIpairs = { operand = operand , type = operandType }
end
local ownershipBefore = ownershipSnapshot ( )
for _ , item in ipairs ( ownershipBefore ) do
item . retained = own . capabilityFacts ( item . state , nil , false ) . retention ~= nil
end
c . pushScope ( )
c . scope . completionScope = stat . body
for j , nameTok in ipairs ( stat . names ) do
local vt = T . any
if iterT and iterT . tag == "func" and iterT . rets [ j ] then
vt = iterT . rets [ j ]
end
c . bindVar ( nameTok . text , vt , false , nameTok )
end
c . loops . push ( stat . body )
c . checkBlock ( stat . body , true )
c . loops . pop ( )
c . popScope ( )
checkLoopBackEdge ( ownershipBefore , stat . body , stat )
end

return handlers
end

return control
