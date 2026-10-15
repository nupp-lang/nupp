_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local narrowing = require ( "nupp.compiler.types.narrowing" )
local generics = require ( "nupp.compiler.types.generics" )
local fixedWidth = require ( "nupp.compiler.types.fixedwidth" )
local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local state = require ( "nupp.compiler.check.state" )

local isA = relations . isA
local packIsA = relations . packIsA
local rawType = T . unwrapOwnership
local memberSet = narrowing . memberSet
local subtract = narrowing . subtract

local control = { }

local LITERAL_KINDS

= { string = true , number = true , nilExpr = true , trueExpr = true , falseExpr = true , }




local RANGE_NESTED_FUNCTION

= { localFuncStmt = true , funcStmt = true , inlineMethod = true , funcExpr = true , shortfn = true , }








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
local movedFields = nil
for field in pairs ( state . movedFields or { } ) do
movedFields = movedFields or { }
movedFields [ field ] = true
end
snapshot [
# snapshot + 1
] = {
state = state ,
moved = state . moved or false ,
movedAt = state . movedAt ,
movedFields = movedFields ,
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






local function ownershipJoin ( ) 
return { arms = 0 , kept = { } , fieldMoved = { } , nilAtEnd = { } , fieldEmpty = { } }
end






local function noteArmEnd ( join ) 
local arm = join . arms + 1
local scope = c . scope
local seen = { }
while scope do
for _ , entry in pairs ( scope . vars or { } ) do
local state = ownershipState ( entry )
if state and state . auditedConsumer and entry . t == T . nil_ then
join . nilAtEnd [ state ] = join . nilAtEnd [ state ] or { }
join . nilAtEnd [ state ] [ arm ] = true
end
if state and state . auditedFields and not seen [ state ] then
seen [ state ] = true
for field in pairs ( state . auditedFields . fields ) do
local narrowed = c . lookupNarrowed ( state . auditedFields . root .. "." .. field )
if narrowed and ownershipKind ( narrowed ) == nil then
local fields = join . fieldEmpty [ state ] or { }
join . fieldEmpty [ state ] = fields
fields [ field ] = fields [ field ] or { }
fields [ field ] [ arm ] = true
end
end
end
end
scope = scope . parent
end
end

c . noteArmEnd = noteArmEnd

local function ownershipRewind ( snapshot , moved , recordMoves , join ) 
if recordMoves and join then
join . arms = join . arms + 1
end
for _ , item in ipairs ( snapshot ) do
local state = item . state
local nilHere = join and join . nilAtEnd [ state ] and join . nilAtEnd [ state ] [ join . arms ] or false
if recordMoves and state . moved and not item . moved then
moved [ state ] = true
elseif recordMoves and join and not state . moved and not nilHere then
join . kept [ state ] = true
end
if recordMoves and join then
for field in pairs ( state . movedFields or { } ) do
if not ( item . movedFields and item . movedFields [ field ] ) then
local fields = join . fieldMoved [ state ] or { }
join . fieldMoved [ state ] = fields
fields [ field ] = fields [ field ] or { }
fields [ field ] [ join . arms ] = true
end
end
end
state . moved , state . movedAt = item . moved , item . movedAt
local movedFields = nil
for field in pairs ( item . movedFields or { } ) do
movedFields = movedFields or { }
movedFields [ field ] = true
end
state . movedFields = movedFields
end
end








local function auditOwnershipJoin ( moved , join , at ) 
for state in pairs ( moved ) do
if state . auditedConsumer and join . kept [ state ] then
local name = state . definition and state . definition . token and state . definition . token . text or "?"
c . diag (
"NUPP2603" ,
at ,
("consuming parameter %q is discharged on only some paths through this statement") : format ( name ) ,
nil ,
{ help = "drop it, move it, or return it on every path, or on none of them" }
)
end
state . moved = true
end
for state , fields in pairs ( join . fieldMoved ) do
for field , movedOn in pairs ( fields ) do
state . movedFields = state . movedFields or { }
state . movedFields [ field ] = true


local empty = join . fieldEmpty [ state ] and join . fieldEmpty [ state ] [ field ] or nil
local held = false
for arm = 1 , join . arms do
if not movedOn [ arm ] and not ( empty and empty [ arm ] ) then
held = true
end
end
if held then
if state . automaticOwner then
state . conditionalMovedFields = state . conditionalMovedFields or { }
state . conditionalMovedFields [ field ] = true
elseif state . auditedFields then
local name = state . definition and state . definition . token and state . definition . token . text or "?"
c . diag (
"NUPP2603" ,
at ,
("owned field %q of %q is moved on only some paths through this statement")

: format ( field , name ) ,
nil ,
{ help = "move the field on every path, or on none of them" }
)
end
end
end
end
end

c . ownershipJoin = ownershipJoin
c . auditOwnershipJoin = auditOwnershipJoin

c . ownershipSnapshot = ownershipSnapshot
c . ownershipRewind = ownershipRewind











local function unassignedSnapshot ( ) 
local snapshot = { }
local scope = c . scope
while scope do
for _ , entry in pairs ( scope . vars or { } ) do
if entry . unassigned then
snapshot [ # snapshot + 1 ] = entry
end
end
scope = scope . parent
end

return snapshot
end


local function unassignedRestore ( snapshot ) 
for _ , entry in ipairs ( snapshot ) do
entry . unassigned = true
end
end


local function unassignedSurvivors ( snapshot , into ) 
for _ , entry in ipairs ( snapshot ) do
if entry . unassigned then
into [ entry ] = true
end
end
end



local function unassignedJoin ( snapshot , survivors ) 
for _ , entry in ipairs ( snapshot ) do
entry . unassigned = survivors [ entry ] or nil
end
end




local function unassignedArrive ( snapshot ) 
for _ , entry in ipairs ( snapshot ) do
entry . unassigned = true
local definition = entry . definition
local scope = definition and c . scope or nil
while scope do
for _ , other in pairs ( scope . vars or { } ) do
if other ~= entry and other . definition == definition then
other . unassigned = true
other . unassignedAt = other . unassignedAt or entry . unassignedAt
end
end
scope = scope . parent
end
end
end






local function compareBackEdge ( snapshot , at , ownershipOnly ) 
for _ , item in ipairs ( snapshot ) do
local state = item . state





local loanIdle = ( state . activeBorrows or 0 ) == 0
and ( state . activeExclusiveBorrows or 0 ) == 0
and item . activeBorrows == 0
and item . activeExclusiveBorrows == 0
and regionSignature ( state . activeRegions ) == ""
and item . activeRegions == ""
and regionSignature ( state . activeExclusiveRegions ) == ""
and item . activeExclusiveRegions == ""
local capabilityChanged = own . capabilityOf ( state . t , state ) . id ~= item . capability and not loanIdle
or ( state . activeBorrows or 0 ) ~= item . activeBorrows
or ( state . activeExclusiveBorrows or 0 ) ~= item . activeExclusiveBorrows
capabilityChanged = not ownershipOnly
and (
capabilityChanged
or regionSignature ( state . activeRegions ) ~= item . activeRegions
or regionSignature ( state . activeExclusiveRegions ) ~= item . activeExclusiveRegions
)
local fieldsChanged = false
for field in pairs ( state . movedFields or { } ) do
if not ( item . movedFields and item . movedFields [ field ] ) then
fieldsChanged = true
end
end
for field in pairs ( item . movedFields or { } ) do
if not ( state . movedFields and state . movedFields [ field ] ) then
fieldsChanged = true
end
end
if state . moved ~= item . moved
or ( own . capabilityFacts ( state , nil , false ) . retention ~= nil ) ~= item . retained
or capabilityChanged
or fieldsChanged
then
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






local function checkLoopBackEdge ( snapshot , body , at ) 
if not alwaysExits ( body ) then
compareBackEdge ( snapshot , at )
end
end

















local function edgeOwnership ( ) 
local notes = ownershipJoin ( )
noteArmEnd ( notes )
return { snapshot = ownershipSnapshot ( ) , nilAtEnd = notes . nilAtEnd , fieldEmpty = notes . fieldEmpty }
end



local function joinOwnershipEdges ( edges , at ) 
local records = { }
local order = { }
for arm , edge in ipairs ( edges ) do
for _ , item in ipairs ( edge . snapshot ) do
local record = records [ item . state ]
if not record then
record = { moved = { } , present = { } , fields = { } }
records [ item . state ] = record
order [ # order + 1 ] = item . state
end
record . present [ arm ] = true
if item . moved then
record . moved [ arm ] = true
record . movedAt = record . movedAt or item . movedAt
end
for field in pairs ( item . movedFields or { } ) do
record . fields [ field ] = record . fields [ field ] or { }
record . fields [ field ] [ arm ] = true
end
end
end
for _ , state in ipairs ( order ) do
local record = records [ state ]
local movedSomewhere , kept = false , false
for arm , edge in ipairs ( edges ) do
local empty = edge . nilAtEnd [ state ] and edge . nilAtEnd [ state ] [ 1 ] or false
if record . moved [ arm ] then
movedSomewhere = true
elseif record . present [ arm ] and not empty then
kept = true
end
end
if movedSomewhere and kept and state . auditedConsumer then
local name = state . definition and state . definition . token and state . definition . token . text or "?"
c . diag (
"NUPP2603" ,
at ,
("consuming parameter %q is discharged on only some paths reaching here") : format ( name ) ,
nil ,
{ help = "drop it, move it, or return it on every path, or on none of them" }
)
end
state . moved = movedSomewhere
state . movedAt = movedSomewhere and ( record . movedAt or state . movedAt ) or nil
local movedFields = nil
for field , movedOn in pairs ( record . fields ) do
movedFields = movedFields or { }
movedFields [ field ] = true
local held = false
for arm , edge in ipairs ( edges ) do
local fields = edge . fieldEmpty [ state ]
local empty = fields and fields [ field ] and fields [ field ] [ 1 ] or false
if record . present [ arm ] and not movedOn [ arm ] and not empty then
held = true
end
end
if held then
if state . automaticOwner then
state . conditionalMovedFields = state . conditionalMovedFields or { }
state . conditionalMovedFields [ field ] = true
elseif state . auditedFields then
local name = state . definition and state . definition . token and state . definition . token . text or "?"
c . diag (
"NUPP2603" ,
at ,
("owned field %q of %q is moved on only some paths reaching here") : format ( field , name ) ,
nil ,
{ help = "move the field on every path, or on none of them" }
)
end
end
end
state . movedFields = movedFields
end
end





local function joinNarrowingEdges ( snapshots ) 
local current = snapshotNarrowed ( )
local joined = { }
local first = snapshots [ 1 ]
for key , t in pairs ( first or { } ) do
local members = { t }
local everywhere = true
for index = 2 , # snapshots do
local other = snapshots [ index ] [ key ]
if not other then
everywhere = false
do break end
end
members [ # members + 1 ] = other
end
if everywhere then
joined [ key ] = T . union ( members )
end
end
for key , t in pairs ( current ) do
if joined [ key ] ~= t then
c . facts . clearWrite ( key )
end
end
applyFacts ( joined )
end



local function reachedFromAbove ( index ) 
local block = c . scope . block
local stats = block and block . kind == "block" and block . stats or { }
local before = { kind = "block" , stats = { } }
for position = 1 , index - 1 do
before . stats [ position ] = stats [ position ]
end

return c . fallsThrough ( before )
end



local loopFrames = { }



local function openLoop ( stat , before ) 
local frame = {
stat = stat ,
functionDepth = c . functionDepth ,
before = before ,
header = edgeOwnership ( ) ,
breaks = { } ,
breakUnassigned = { } ,
continues = { } ,
continueUnassigned = { } ,
}
loopFrames [ # loopFrames + 1 ] = frame

return frame
end

local function closeLoop ( frame ) 
if loopFrames [ # loopFrames ] == frame then
loopFrames [ # loopFrames ] = nil
end
end



local function recordLoopExit ( kind , at ) 
local frame = loopFrames [ # loopFrames ]
if not frame or frame . functionDepth ~= c . functionDepth then
return
end
if kind == "break" then
frame . breaks [ # frame . breaks + 1 ] = edgeOwnership ( )
frame . breakUnassigned [ # frame . breakUnassigned + 1 ] = unassignedSnapshot ( )
elseif kind == "continue" then

compareBackEdge ( frame . before , at , true )
frame . continues [ # frame . continues + 1 ] = edgeOwnership ( )
frame . continueUnassigned [ # frame . continueUnassigned + 1 ] = unassignedSnapshot ( )
end
end

c . recordLoopExit = recordLoopExit



local function settleLoop ( frame , normal , extra ) 
local edges = { }
if normal then
edges [ # edges + 1 ] = normal
end
for _ , edge in ipairs ( extra or { } ) do
edges [ # edges + 1 ] = edge
end
for _ , edge in ipairs ( frame . breaks ) do
edges [ # edges + 1 ] = edge
end
if # edges > 0 then
joinOwnershipEdges ( edges , frame . stat )
end
end

local handlers = __nuppNew(0,13)

handlers . breakStmt = function ( stat ) 
recordLoopExit ( "break" , stat )
end

handlers . continueStmt = function ( stat ) 
recordLoopExit ( "continue" , stat )
end



local function repeatedAfter ( stat ) 
local name = stat . name
local block = c . scope . block
local stats = block and block . kind == "block" and block . stats or { }
local start = nil
for index , candidate in ipairs ( stats ) do
if candidate == stat then
start = index
do break end
end
end
if not name or not start then
return nil
end

local function jumpsBack ( node ) 
if not node or cst . isToken ( node ) then
return false
end
if node . kind == "gotoStmt" then
return node . name ~= nil and node . name . text == name . text
end
if node . kind == "funcbody" or node . kind == "shortfn" then
return false
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) and jumpsBack ( child ) then
return true
end
end

return false
end

local region = { kind = "block" , stats = { } }
for index = start + 1 , # stats do
region . stats [ # region . stats + 1 ] = stats [ index ]
region [ # region + 1 ] = stats [ index ]
end
for _ , candidate in ipairs ( region . stats ) do
if jumpsBack ( candidate ) then
return region
end
end

return nil
end




local checkedLabels = { }
local pendingGotos = { }

local function offsetOf ( node ) 
local token = node and cst . firstToken ( node ) or nil
return token and token . offset or 0
end

handlers . labelStmt = function ( stat ) 
local name = stat . name
local block = c . scope . block
local stats = block and block . kind == "block" and block . stats or { }
local index = nil
for position , candidate in ipairs ( stats ) do
if candidate == stat then
index = position
do break end
end
end
local blockFirst = block and offsetOf ( block ) or 0
local lastToken = block and cst . lastToken ( block ) or nil
local blockLast = lastToken and lastToken . offset or math . huge
local at = offsetOf ( stat )
if name then

local incoming = { }
for position = # pendingGotos , 1 , -1 do
local jump = pendingGotos [ position ]
if jump . name == name . text
and jump . functionDepth == c . functionDepth
and jump . offset >= blockFirst
and jump . offset < at
then
table . insert ( incoming , 1 , jump )
table . remove ( pendingGotos , position )
end
end
if # incoming > 0 then
local reached = index == nil or reachedFromAbove ( index )
local ownershipEdges , narrowed = { } , { }
if reached then
ownershipEdges [ 1 ] = edgeOwnership ( )
narrowed [ 1 ] = snapshotNarrowed ( )
else
for _ , entry in ipairs ( unassignedSnapshot ( ) ) do
entry . unassigned = nil
end
end
for _ , jump in ipairs ( incoming ) do
ownershipEdges [ # ownershipEdges + 1 ] = jump . ownership
narrowed [ # narrowed + 1 ] = jump . narrowed
unassignedArrive ( jump . unassigned )
end
joinOwnershipEdges ( ownershipEdges , stat )
joinNarrowingEdges ( narrowed )
end
checkedLabels [
# checkedLabels + 1
] = {
name = name . text ,
functionDepth = c . functionDepth ,
offset = at ,
blockLast = blockLast ,
snapshot = ownershipSnapshot ( ) ,
}
end


c . facts . forgetWritten ( repeatedAfter ( stat ) )
end

handlers . gotoStmt = function ( stat ) 
local name = stat . name
if not name then
return
end
local at = offsetOf ( stat )
for position = # checkedLabels , 1 , -1 do
local label = checkedLabels [ position ]
if label . name == name . text
and label . functionDepth == c . functionDepth
and label . offset < at
and at <= label . blockLast
then
for _ , item in ipairs ( label . snapshot ) do
if item . state . moved and not item . moved then
c . diag ( "NUPP2609" , stat , "a backward goto repeats after consuming an outer capability" , nil , {
help = "use structured control flow that reacquires or preserves the owner on every iteration"
} )
do break end
end
end
return
end
end
pendingGotos [
# pendingGotos + 1
] = {
name = name . text ,
functionDepth = c . functionDepth ,
offset = at ,
ownership = edgeOwnership ( ) ,
narrowed = snapshotNarrowed ( ) ,
unassigned = unassignedSnapshot ( ) ,
}
end





handlers . yieldStmt = function ( stat ) 
local collector = c . blockYieldStack [ # c . blockYieldStack ]
local valueT = stat . value and c . infer ( stat . value ) or T . any
if not collector then
c . diag ( "NUPP2141" , stat , "'yield' requires an enclosing do expression" )
return
end
collector [ # collector + 1 ] = valueT
stat . switchResultType = valueT
if collector . roots then
collector . expressions [ # collector . expressions + 1 ] = stat . value
local roots = ownershipKind ( valueT ) == "borrowed" and provenanceOwners ( stat . value )
or own . capabilityFacts ( stat . value , nil , false ) . roots
or { }
for _ , root in ipairs ( roots ) do
if not collector . visible [ root ] then
c . diag (
"NUPP2608" ,
stat . value ,
"a yielded borrow cannot outlive its source inside the do expression"
)
end
if not collector . seenRoots [ root ] then
collector . seenRoots [ root ] = true
collector . roots [ # collector . roots + 1 ] = root
end
end
end

if ownershipKind ( valueT ) == "affine" then
c . markTemporaryConsumed ( stat . value )
if c . ownershipEntry ( stat . value ) then
moveExpression ( stat . value , valueT , "do expression result" , "affine" )
end
end
if collector . before then
local current = ownershipSnapshot ( )
noteArmEnd ( collector . join )
ownershipRewind ( collector . before , collector . moved , true , collector . join )
ownershipRewind ( current , { } , false )
end
end

handlers . withStmt = function ( stat ) 

c . pushScope ( )
for _ , binding in ipairs ( stat . bindings or { } ) do
local nameTok = binding . name
local acquired = c . infer ( binding . expr )
local cleanups = acquired . tag == "affine" and acquired . cleanups or { }
binding . acquiredType = acquired
binding . ownerCleanups = cleanups
if ownershipKind ( acquired ) ~= "affine" or own . optionalOwned ( acquired ) then
c . diag ( "NUPP2602" , binding . expr , "a 'with' acquisition must be a non-optional affine value" )
elseif # cleanups == 0 then
c . diag ( "NUPP2615" , binding . expr , "a 'with' acquisition needs an affine terminal" , nil , {
help = "name the cleanup in affine(T, cleanup), or claim nupp.Affine through an interface"
} )
end
if binding . type then
local declared = c . resolveType ( binding . type )
local ok , why = isA ( rawType ( acquired ) , declared )
if not ok then
c . diag (
"NUPP2001" ,
binding . expr ,
("cannot initialize %s: %s") : format ( nameTok and nameTok . text or "acquisition" , why )
)
end
end


local regionRoot , regionPath = own . regionOf ( binding . expr )
local acquiredFacts = own . capabilityFacts ( binding . expr , 1 , false )
local roots = { }
for _ , root in ipairs ( acquiredFacts . roots or { } ) do
roots [ # roots + 1 ] = root
end
local exclusive = acquiredFacts . exclusive
if acquiredFacts . regionRoot then
regionRoot , regionPath = acquiredFacts . regionRoot , acquiredFacts . regionPath
elseif regionPath == "" then
regionRoot , regionPath = nil , nil
end
if ownershipKind ( acquired ) == "affine" then
moveExpression ( binding . expr , acquired , "with acquisition" , "affine" )
end
local visible = ownershipKind ( acquired ) == "affine" and T . borrowed ( rawType ( acquired ) ) or T . any
if nameTok then
c . bindVar ( nameTok . text , visible , binding . type ~= nil , nameTok , nil , true )
local entry = c . scope . vars [ nameTok . text ]
if entry then
entry . withBinding = binding
local facts = own . capabilityFacts ( entry )
facts . roots = # roots > 0 and roots or nil
facts . exclusive = exclusive
facts . regionRoot , facts . regionPath = regionRoot , regionPath
for _ , root in ipairs ( roots ) do
root . activeBorrows = ( root . activeBorrows or 0 ) + 1
root . activeBorrowSites = root . activeBorrowSites or { }
root . activeBorrowSites [ entry ] = nameTok
if exclusive then
root . activeExclusiveBorrows = ( root . activeExclusiveBorrows or 0 ) + 1
end
end
if regionRoot and regionPath then
regionRoot . activeRegions = regionRoot . activeRegions or { }
regionRoot . activeRegions [ regionPath ] = ( regionRoot . activeRegions [ regionPath ] or 0 ) + 1
if exclusive then
regionRoot . activeExclusiveRegions = regionRoot . activeExclusiveRegions or { }
regionRoot . activeExclusiveRegions [
regionPath
] = ( regionRoot . activeExclusiveRegions [ regionPath ] or 0 ) + 1
end
end
end
end
end
c . captureWatches [ # c . captureWatches + 1 ] = { depth = c . scope . depth , captured = false }
c . checkBlock ( stat . body , true )
stat . capturesEnclosing = c . captureWatches [ # c . captureWatches ] . captured
c . captureWatches [ # c . captureWatches ] = nil
c . popScope ( )
end

handlers . returnStmt = function ( stat ) 
if c . result . declaredModuleName and # c . retStack == 0 then
c . diag ( "NUPP1002" , stat , "a declared module exports declarations and has no top-level return" )
return
end
local annotatedPack = c . retPackStack [ # c . retPackStack ]
local constructor = c . constructorFieldStack [ # c . constructorFieldStack ]
if constructor then
local expr = stat . exprs and stat . exprs [ 1 ]
local valid = # ( stat . exprs or { } ) == 0
local token = expr and expr . kind == "name" and expr . token or nil
if expr and token and # stat . exprs == 1 and token . text == "self" then
c . infer ( expr )
local body = c . functionBodies [ # c . functionBodies ]
local receiver = body and body . params and body . params [ 1 ] and body . params [ 1 ] . name
valid = receiver ~= nil and token . definition == receiver . definition
end
if not valid then
c . diag ( "NUPP2208" , stat , "a constructor returns the instance it builds" , nil , {
help = "use a bare return after initializing the required fields"
} )
end
stat . constructorReturn = true


annotatedPack = nil
end
for index , returned in ipairs ( stat . exprs or { } ) do
local expected = annotatedPack and T . packAt ( annotatedPack , index ) or nil
local rawExpected = expected and rawType ( expected ) or nil
if returned and rawExpected and rawExpected . tag == "func" and rawExpected . sendable then
local contextual = returned
contextual . sendableContext = true
end




if returned and ( returned . kind == "call" or returned . kind == "safeCall" ) then
local contextual = returned
contextual . expectedResult = expected
end
end
local wasReturning = c . loops . setReturning ( true )
local returnedPack = constructor and T . pack ( { } ) or c . inferListPack ( stat . exprs )
local ts = returnedPack . head
c . loops . setReturning ( wasReturning )
local observed = c . observedReturnStack [ # c . observedReturnStack ]
if observed and not annotatedPack then
observed [ # observed + 1 ] = returnedPack
end

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
do break end
end
end
if seen [ result ] then
for name , region in pairs ( fields ) do
if prior [ name ] ~= region then
seen [ result ] = false
do break end
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

if ownershipKind ( valueT ) == "affine" and stat . exprs [ j ] then
c . markTemporaryConsumed ( stat . exprs [ j ] )
end
local declaredBorrow = c . borrowReturnStack [ # c . borrowReturnStack ]
local borrowContract = declaredBorrow and declaredBorrow . result == j and declaredBorrow . contract or nil
if borrowContract then
local expected = { }
local missing = nil
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
if ownershipKind ( valueT ) == "borrowed" and not borrowContract then
local expr = stat . exprs [ j ] or stat
local root = provenanceOwners ( expr ) [ 1 ]
local related = root
and root . definition
and c . related ( root . definition , "borrowed source is declared here" )
or nil
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
local expected = annotatedPack and T . packAt ( annotatedPack , j ) or nil
local ownReturns = c . ownReturnStack [ # c . ownReturnStack ]
local capabilityResult = expected
and ownReturns
and ownReturns [ j ]
and rawType ( expected ) . id == rawType ( valueT ) . id
if # c . retStack == 0 then
c . diag ( "NUPP2603" , stat . exprs [ j ] or stat , valueKind .. " value cannot be exported as module state" )
elseif not expected or ownershipKind ( expected ) ~= valueKind and not capabilityResult then
c . diag (
expected == T . any and "NUPP2611" or "NUPP2603" ,
stat . exprs [ j ] or stat ,
expected == T . any and "a live capability cannot be erased into an any result"
or valueKind .. " return needs a matching annotation"
)
else




local declaredSources = { }
for _ , sourceToken in ipairs (
borrowContract and ( borrowContract . params or { borrowContract . param } ) or { }
) do
local source = ownershipState ( c . lookupEntry ( sourceToken . text ) )
if source then
declaredSources [ borrowRoot ( source ) ] = true
end
end




for _ , root in ipairs ( own . rootsOf ( stat . exprs [ j ] ) ) do
if not declaredSources [ root ]
and ( root . functionDepth or 0 ) >= c . functionDepth
and ownershipKind ( root . t ) ~= nil
then
local rootName = root . definition and root . definition . token and root . definition . token . text
or "?"
local parameter = root . definition and root . definition . kind == "parameter"
local related = root . definition and c . related ( root . definition , "the root is declared here" )
or nil
c . diag (
"NUPP2608" ,
stat . exprs [ j ] or stat ,
parameter
and ("an owning result rooted in parameter %q must declare `borrows (%s)`")

: format ( rootName , rootName )
or ("an owning result rooted in %q outlives it") : format ( rootName ) ,
nil ,
{
help = parameter
and "write the relation on the result so the caller keeps the root alive"
or "return an owner that stands on its own, or root it in a parameter the result declares" ,
related = related and { related } or nil ,
}
)
do break end
end
end
local source = ownershipState ( ( c . ownershipEntry ( stat . exprs [ j ] ) ) )
local promoted = ownReturns and ownReturns [ j ] and source and ownershipKind ( source . t ) ~= valueKind
if not promoted then
moveExpression ( stat . exprs [ j ] , valueT , "return" , valueKind )
end
end
end
end


local consumingEntry = functionBody and functionBody . consumingEntry or nil
local consumingState = consumingEntry and ownershipState ( consumingEntry ) or nil
local name = consumingEntry and consumingEntry . definition and consumingEntry . definition . token or nil

local current = name and c . lookupEntry ( name . text ) or nil
if consumingState and not consumingState . moved and not ( current and current . t == T . nil_ ) then
c . diag (
"NUPP2603" ,
stat ,
("consuming parameter %q is still live at this return") : format ( name and name . text or "?" ) ,
nil ,
{
help = "drop it, move it, or return it before leaving" ,
related = name and { c . related ( name , "the parameter is declared here" ) } or nil ,
}
)
end



local consumingFields = c . consumingFieldStack [ # c . consumingFieldStack ]
local fieldState = consumingFields and ownershipState ( c . lookupEntry ( consumingFields . root ) ) or nil
if consumingFields and fieldState and not fieldState . moved then
local declared = fieldState . definition and fieldState . definition . token or nil
for field in pairs ( consumingFields . allowed ) do
local narrowed = c . lookupNarrowed ( consumingFields . root .. "." .. field )
local moved = fieldState . movedFields and fieldState . movedFields [ field ]
if not moved and not ( narrowed and ownershipKind ( narrowed ) == nil ) then
c . diag (
"NUPP2603" ,
stat ,
("owned field %q of consuming parameter %q is still live at this return")

: format ( field , consumingFields . root ) ,
nil ,
{
help = "drop, move, or return the field or its whole parameter before leaving" ,
related = declared and { c . related ( declared , "the parameter is declared here" ) } or nil ,
}
)
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
c . moduleType = T . shape ( fields , nil , nil , true )



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
("exported %q needs a type annotation") : format ( field . name )
)
end
end
elseif untyped ( shape ) then
c . diag ( "NUPP2106" , stat , "the module's exported value needs a type annotation" )
end
end
end
local ownReturns = c . ownReturnStack [ # c . ownReturnStack ]



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



local constructed = expr
while constructed and ( constructed . kind == "paren" or constructed . kind == "castExpr" ) do
constructed = constructed . expr
end
local freshConstruction = constructed
and (
constructed . kind == "newExpr"
or constructed . kind == "call" and constructed . recordConstruct ~= nil
)
if ownReturns and ownReturns [ j ] and ( not ownershipKind ( got ) or freshConstruction ) then
expected = ownReturns [ j ]
got = rawType ( got )
end
local ok , why , reported = returnFits ( got , expected , expr or stat )
if ok and relations . typevarMismatch ( got , expected ) then
ok = false
why = ("%s is not a value of the generic type %s") : format ( T . tostring ( got ) , T . tostring ( expected ) )
end
if not ok and not reported then
c . diag ( "NUPP2002" , stat . exprs and stat . exprs [ j ] or stat , ("return %d: %s") : format ( j , why ) )
end
end
if not annotatedPack . tail and not returnedPack . tail and # returnedPack . head > # annotatedPack . head then
c . diag (
"NUPP2002" ,
stat ,
("too many return values (expected %d, got %d)") : format ( # annotatedPack . head , # returnedPack . head )
)
elseif annotatedPack . tail and annotatedPack . tail . kind == "homogeneous" then
for j = # annotatedPack . head + 1 , # returnedPack . head do
local expr = fixedExpression ( j )
local ok , why , reported = returnFits ( returnedPack . head [ j ] , annotatedPack . tail . type , expr or stat )
if not ok and not reported then
c . diag ( "NUPP2002" , stat , ("return %d: %s") : format ( j , why ) )
end
end
elseif annotatedPack . tail
and annotatedPack . tail . kind == "generic"
and (
not returnedPack . tail
or returnedPack . tail . kind ~= "generic"
or returnedPack . tail . var ~= annotatedPack . tail . var
)
then
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
if first
and second
and first . name == second . name
and first . literal ~= second . literal
and isLocal ( c , first . name )
and not writesName ( firstClause and firstClause . body , first . name )
and firstEnd
and nextIf
then
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
local fixes = nested
and elseTok
and nestedIf
and nestedEnd
and {
c . edits . fix (
"write `elseif`" ,
c . edits . replaceToken ( elseTok , "elseif" ) ,
c . edits . replaceToken ( nestedIf , "" ) ,
c . edits . replaceToken ( nestedEnd , "" )
) ,
}
or nil
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
local join = ownershipJoin ( )
local unassignedBefore = unassignedSnapshot ( )
local unassignedAfter = { }
for _ , clause in ipairs ( stat . clauses ) do


c . pushScope ( )
applyFacts ( accumulatedElse )
unassignedRestore ( unassignedBefore )
local facts = { t = { } , f = { } }
local cond , body , binding = nil , nil , nil
if clause . kind == "ifClause" or clause . kind == "elseifClause" then
cond , body , binding = clause . cond , clause . body , clause . binding
end
if cond and binding then




local valueType = c . infer ( cond )
if c . callMayMutate then
c . facts . invalidateForCall ( )
c . callMayMutate = false
end
local bound = valueType
local rawValue = rawType ( valueType )



local openParameter = rawValue . tag == "typevar"
and ( rawValue . bound == nil or isA ( T . nil_ , rawValue . bound ) )
if valueType == T . any or valueType == T . unknown then
bound = T . any
elseif openParameter and not ownershipKind ( valueType ) then
bound = valueType
elseif ownershipKind ( valueType ) then
c . diag ( "NUPP2603" , cond , "an if binding cannot take an owned or borrowed value" )
bound = T . any
else
bound = narrowing . subtract ( valueType , T . nil_ )
if valueType == T . nil_ then
bound = T . never
end
if bound == valueType then
c . diag (
"NUPP2001" ,
cond ,
("cannot bind %s: %s is never nil") : format ( binding . text , T . tostring ( valueType ) ) ,
nil ,
{
help = "an if binding takes its arm when the value is not nil, so the value must admit nil"
}
)
elseif bound == T . never then
c . diag ( "NUPP2001" , cond , ("cannot bind %s: the value is always nil") : format ( binding . text ) )
bound = T . any
end
if bound . tag == "literal" then
bound = bound . base or T . string
if bound == T . integer then
bound = T . number
end
end
bound = T . settled ( bound )
end
c . bindVar ( binding . text , bound , false , binding , nil , false )
local boundEntry = c . scope . vars [ binding . text ]
if boundEntry then
if boundEntry . definition then
boundEntry . definition . initialized = true
end
c . fixedWidth . setBinding ( boundEntry , cond , nil )
c . unused . declared ( binding , boundEntry , "variable" )
end
elseif cond then
c . infer ( cond )
local cleared = nil
if c . callMayMutate then
cleared = c . facts . invalidateForCall ( )
c . callMayMutate = false
end
facts = analyzeCond ( cond )
facts . t = c . facts . withoutCleared ( facts . t , cleared )
facts . f = c . facts . withoutCleared ( facts . f , cleared )
end
firstFacts = firstFacts or facts
applyFacts ( facts . t )
c . checkBlock ( body , true )
if not alwaysExits ( body ) then
paths [ # paths + 1 ] = snapshotNarrowed ( )
noteArmEnd ( join )
unassignedSurvivors ( unassignedBefore , unassignedAfter )
end
c . popScope ( )
ownershipRewind ( ownershipBefore , branchMoved , not alwaysExits ( body ) , join )
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




if dispatchKey and dispatchKey ~= false and not stat . elseClause and allBranchesLeave and dispatchTotal then
( stat ) . exhaustiveDispatch = true
end
if dispatchKey
and dispatchKey ~= false
and not stat . elseClause
and allBranchesLeave
and not dispatchTotal
and memberSet ( dispatchStart )
then
local remaining = accumulatedElse [ dispatchKey ]
local missing = remaining and memberSet ( remaining ) or nil
if missing and # missing > 0 then
( stat ) . exhaustiveDispatch = true
local names = { }
for j , m in ipairs ( missing ) do
names [ j ] = ("%q") : format ( m . tag == "literal" and m . constant or "?" )
end
table . sort ( names )
c . diag (
"NUPP2107" ,
stat ,
("every branch returns, so this handles %s and leaves %s unhandled")

: format ( T . tostring ( dispatchStart ) , table . concat ( names , ", " ) ) ,
nil ,
{ help = "add branches for " .. table . concat ( names , ", " ) .. " or add an else clause" }
)
end
end
if otherwise then
c . pushScope ( )
applyFacts ( accumulatedElse )
unassignedRestore ( unassignedBefore )
c . checkBlock ( elseBody , true )
if not alwaysExits ( elseBody ) then
paths [ # paths + 1 ] = snapshotNarrowed ( )
noteArmEnd ( join )
unassignedSurvivors ( unassignedBefore , unassignedAfter )
end
c . popScope ( )
ownershipRewind ( ownershipBefore , branchMoved , not alwaysExits ( elseBody ) , join )
else


c . pushScope ( )
applyFacts ( accumulatedElse )
paths [ # paths + 1 ] = snapshotNarrowed ( )
noteArmEnd ( join )
unassignedRestore ( unassignedBefore )
unassignedSurvivors ( unassignedBefore , unassignedAfter )
c . popScope ( )
join . arms = join . arms + 1
for _ , item in ipairs ( ownershipBefore ) do
local nilHere = join . nilAtEnd [ item . state ] and join . nilAtEnd [ item . state ] [ join . arms ] or false
if not item . moved and not nilHere then
join . kept [ item . state ] = true
end
end
end
auditOwnershipJoin ( branchMoved , join , stat )
unassignedJoin ( unassignedBefore , unassignedAfter )



if # paths > 0 then
local joined = { }
for key , t in pairs ( paths [ 1 ] ) do
local members = { t }
local everywhere = true
for j = 2 , # paths do
local other = paths [ j ] [ key ]
if not other then
everywhere = false
do break end
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
c . infer ( cond )
local cleared = nil
if c . callMayMutate then
cleared = c . facts . invalidateForCall ( )
c . callMayMutate = false
end
local facts = analyzeCond ( cond )
facts . t = c . facts . withoutCleared ( facts . t , cleared )
facts . f = c . facts . withoutCleared ( facts . f , cleared )

local unassignedBefore = unassignedSnapshot ( )


c . facts . forgetWritten ( stat . body )
local frame = openLoop ( stat , ownershipBefore )
c . pushScope ( )
applyFacts ( facts . t )
c . loops . push ( stat . body )
c . checkBlock ( stat . body , true )
c . loops . pop ( )
c . popScope ( )
closeLoop ( frame )
unassignedRestore ( unassignedBefore )
checkLoopBackEdge ( ownershipBefore , stat . body , stat )



local normal = nil
if cond . kind ~= "trueExpr" then
normal = alwaysExits ( stat . body ) and frame . header or edgeOwnership ( )
end
settleLoop ( frame , normal )
end
end

handlers . repeatStmt = function ( stat ) 

local ownershipBefore = ownershipSnapshot ( )
c . facts . forgetWritten ( stat . body )
local frame = openLoop ( stat , ownershipBefore )
c . pushScope ( )
c . loops . push ( stat . body )
c . checkBlock ( stat . body , true )
c . loops . pop ( )
closeLoop ( frame )
local falls = not alwaysExits ( stat . body )


if not falls then
for _ , entry in ipairs ( unassignedSnapshot ( ) ) do
entry . unassigned = nil
end
end
for _ , unassigned in ipairs ( frame . continueUnassigned ) do
unassignedArrive ( unassigned )
end
if stat . cond then
c . infer ( stat . cond )
end
c . popScope ( )
checkLoopBackEdge ( ownershipBefore , stat . body , stat )


for _ , unassigned in ipairs ( frame . breakUnassigned ) do
unassignedRestore ( unassigned )
end
local normal = nil
local continues = { }
if not ( stat . cond and stat . cond . kind == "falseExpr" ) then
normal = falls and edgeOwnership ( ) or nil
continues = frame . continues
end
settleLoop ( frame , normal , continues )
end

handlers . doStmt = function ( stat ) 
c . pushScope ( ) ;
c . checkBlock ( stat . body , true ) ;
c . popScope ( )
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
local unassignedBefore = unassignedSnapshot ( )
c . facts . forgetWritten ( stat . body )
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
local witness = rangeDefinition
and rangeDefinition == rangeField ( to , "last" )
and rangeDefinition . indexedRangeWitness
or nil
if not witness and not stat . step and to . kind == "unop" and to . indexedLength then
local firstToken = cst . firstToken ( from )
local receiverDefinition = to . indexedLength . receiverDefinition
if firstToken
and firstToken . kind == "number"
and tonumber ( firstToken . text ) == 1
and receiverDefinition
and receiverDefinition . constant
then
witness = { views = { [ receiverDefinition ] = to . indexedLength . descriptor , } , }
end
end
local frame = openLoop ( stat , ownershipBefore )
c . loops . push ( stat . body )
c . checkBlock ( stat . body , true )
closeLoop ( frame )
if witness and stat . body and var . definition then
local function markRangeAccess ( node ) 
if not node or cst . isToken ( node ) then
return
end
if RANGE_NESTED_FUNCTION [ node . kind ] then
return
end
if node . kind == "bracketIndex" and node . indexedAccess then
local access = node . indexedAccess
local receiverDefinition = access . receiverDefinition
local indexDefinition = access . indexDefinition
local views = witness . views or witness . spans or { }
if views [ receiverDefinition ] and indexDefinition == var . definition then
node . rangeProvenNoRaise = true
node . indexedRangeAccess = {
loop = stat ,
rangeDefinition = rangeDefinition ,
receiverDefinition = receiverDefinition ,
indexDefinition = indexDefinition ,
descriptor = access . descriptor ,
}
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
unassignedRestore ( unassignedBefore )
checkLoopBackEdge ( ownershipBefore , stat . body , stat )
settleLoop ( frame , alwaysExits ( stat . body ) and frame . header or edgeOwnership ( ) )
end

handlers . forinStmt = function ( stat ) 



local header = c . inferListPack ( stat . exprs )
local iterT = T . packAt ( header , 1 )
iterT = iterT and rawType ( iterT ) or nil
local stateT = T . packAt ( header , 2 ) or T . nil_
local controlT = T . packAt ( header , 3 ) or T . nil_
if ownershipKind ( controlT ) == "affine" then
local controlSource = stat . exprs and stat . exprs [ # stat . exprs ] or stat
c . diag ( "NUPP2622" , controlSource , "generic for control cannot be affine: each step replaces it" )
c . markTemporaryConsumed ( controlSource )
end
local callable = iterT and c . metamethodOf ( iterT , "__call" ) or nil
if callable then
callable = generics . dropSelf ( callable )
else
callable = iterT
end
local choices = callable and callable . tag == "intersection" and callable . members
or callable and { callable }
or { }
local selected , resultPack , failures = nil , nil , { }
for _ , candidate in ipairs ( choices ) do
if candidate . tag == "func" then
local expanded , packProblem = generics . expandFunctionPacks ( candidate , c . reductionControl )
if packProblem then
failures [ # failures + 1 ] = packProblem
else
local problem = nil
for position , want in ipairs ( expanded . params ) do
local actual = position == 1 and stateT or position == 2 and controlT or T . nil_
local ok , why = isA ( actual , want )
if not ok then
problem = ("argument %d: %s")

: format ( position , why or ( T . tostring ( actual ) .. " is not " .. T . tostring ( want ) ) )
do break end
end
end
if not problem and expanded . paramPack . tail and expanded . paramPack . tail . kind == "homogeneous" then
local tail = expanded . paramPack . tail
for position = # expanded . params + 1 , 2 do
local actual = position == 1 and stateT or controlT
local ok , why = isA ( actual , tail . type )
if not ok then
problem = ("argument %d: %s")

: format ( position , why or ( T . tostring ( actual ) .. " is not " .. T . tostring ( tail . type ) ) )
do break end
end
end
end
if problem then
failures [ # failures + 1 ] = problem
elseif selected then
c . diag ( "NUPP2006" , stat , "generic for iterator matches more than one callable overload" )
else
selected , resultPack = expanded , expanded . retPack
end
end
end
end
if not selected and # failures > 0 then
c . diag ( "NUPP2006" , stat . exprs and stat . exprs [ 1 ] or stat , "generic for iterator: " .. failures [ 1 ] )
elseif not selected and iterT and iterT ~= T . any then
c . diag ( "NUPP2005" , stat . exprs and stat . exprs [ 1 ] or stat , "generic for iterator is not callable" )
end
iterT = selected or iterT
if selected and resultPack then
local nextControl = T . packAt ( resultPack , 1 )
if nextControl and nextControl ~= T . nil_ then
nextControl = subtract ( nextControl , T . nil_ )
local want = selected . params [ 2 ]
or selected . paramPack . tail
and selected . paramPack . tail . kind == "homogeneous"
and selected . paramPack . tail . type
or nil
if want and nextControl ~= T . nil_ then
local ok , why = isA ( nextControl , want )
if not ok then
c . diag (
"NUPP2006" ,
stat ,
"generic for next control: " .. (
why or ( T . tostring ( nextControl ) .. " is not " .. T . tostring ( want ) )
)
)
end
end
end
end





if resultPack and resultPack . alternatives then
local live = { }
for _ , arm in ipairs ( resultPack . alternatives ) do
if ( T . packAt ( arm , 1 ) or T . nil_ ) ~= T . nil_ then
live [ # live + 1 ] = arm
end
end
if # live > 0 and # live < # resultPack . alternatives then
resultPack = T . packUnion ( live )
end
end


local iteratorCallNode = stat
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

local sourceExprs = stat . exprs or { }

local function sourceForSlot ( slot ) 
return sourceExprs [ slot ] or sourceExprs [ # sourceExprs ]
end



local ownsHeader = false
for slot = 1 , 2 do
local value = T . packAt ( header , slot )
local source = sourceForSlot ( slot )
if value and ownershipKind ( value ) == "affine" and # ( ( value ) . cleanups or { } ) > 0 then
if not ( source and source . kind == "name" and c . ownershipEntry ( source ) ) then
ownsHeader = true
end
end
end
local headerBlock , headerLocal
local hiddenNames = { }
if ownsHeader then
local first = cst . firstToken ( stat )

local function tokenLike ( base , kind , spelling ) 
local tok = { }
for key , value in pairs ( base or { } ) do
tok [ key ] = value
end
tok . kind , tok . text = kind , spelling
tok . definition = nil
tok . triviaFirst , tok . triviaCount = 0 , 0

return tok
end

for slot = 1 , 3 do
c . loopOwnerCount = ( c . loopOwnerCount or 0 ) + 1
hiddenNames [ slot ] = tokenLike ( first , "name" , ("__nuppForHeader%d") : format ( c . loopOwnerCount ) )
end
headerLocal = _G.setmetatable({ kind =  "localStmt" ,  names =  hiddenNames ,  types =  { } ,  exprs =  sourceExprs }, cst.LocalStmt)
headerLocal [ 1 ] = tokenLike ( first , "local" , "local" )
for slot , name in ipairs ( hiddenNames ) do
headerLocal [ # headerLocal + 1 ] = name
if slot < 3 then
headerLocal [ # headerLocal + 1 ] = tokenLike ( first , "," , "," )
end
end
headerLocal [ # headerLocal + 1 ] = tokenLike ( first , "=" , "=" )
for index , expr in ipairs ( sourceExprs ) do
headerLocal [ # headerLocal + 1 ] = expr
if index < # sourceExprs then
headerLocal [ # headerLocal + 1 ] = tokenLike ( first , "," , "," )
end
end
headerBlock = _G.setmetatable({ kind =  "block" ,  stats =  { headerLocal } }, cst.Block)
c . pushScope ( )
c . scope . block = headerBlock
c . scope . completionScope = headerBlock
for slot , name in ipairs ( hiddenNames ) do
local value = T . packAt ( header , slot ) or T . nil_
local source = sourceForSlot ( slot )
local outer = source and source . kind == "name" and c . ownershipEntry ( source ) or nil
local fresh = slot <= 2 and ownershipKind ( value ) == "affine" and not outer
local bound = outer and T . borrowed ( rawType ( value ) ) or value
c . bindVar ( name . text , bound , false , name )
local entry = c . scope . vars [ name . text ]
if fresh and entry and entry . automaticOwner then
c . markTemporaryConsumed ( source )
local owner = entry . automaticOwner
owner . stat , owner . index , owner . expr , owner . type = headerLocal , slot , source , bound
owner . lowerable = true
headerLocal . automaticOwners = headerLocal . automaticOwners or { }
headerLocal . automaticOwners [ slot ] = owner
c . own . validateCleanups ( bound , owner . cleanups , source or stat , "NUPP2615" )
elseif outer and entry then
local facts = own . capabilityFacts ( entry )
facts . roots = { borrowRoot ( outer ) }
end
end
end
local ownershipBefore = ownershipSnapshot ( )
local unassignedBefore = unassignedSnapshot ( )
c . facts . forgetWritten ( stat . body )
c . pushScope ( )
c . scope . completionScope = stat . body
local iteratorRoots = { }
local seenRoots = { }

local function addIteratorRoot ( root ) 
root = root and borrowRoot ( root ) or nil
if root and not seenRoots [ root ] then
seenRoots [ root ] = true
iteratorRoots [ # iteratorRoots + 1 ] = root
end
end

for _ , expression in ipairs ( stat . exprs or { } ) do
provenanceOwners ( expression , iteratorRoots , seenRoots )
local produced = expression . valuePack
for result = 1 , # ( produced and produced . head or { } ) do
local resultFacts = own . capabilityFacts ( expression , result , false )
for _ , root in ipairs ( resultFacts . roots or { } ) do
addIteratorRoot ( root )
end
end
end
if # iteratorRoots == 0 then



iteratorRoots [ 1 ] = { t = iterT or T . any , moved = false , syntheticIteratorRoot = true , }
end
for j , nameTok in ipairs ( stat . names ) do
local vt = T . any
local mode = resultPack
and (
resultPack . modes [ j ]
or resultPack . tail and resultPack . tail . kind == "homogeneous" and resultPack . tail . mode
)
or "plain"
if resultPack and T . packAt ( resultPack , j ) then
vt = T . packAt ( resultPack , j )
elseif iterT and iterT . tag == "func" and iterT . rets [ j ] then
vt = iterT . rets [ j ]
end
if j == 1 and vt ~= T . any and vt ~= T . unknown and isA ( T . nil_ , vt ) then
vt = subtract ( vt , T . nil_ )
end
if ( mode == "borrowed" or mode == "borrows" or mode == "exclusive" ) and ownershipKind ( vt ) == nil then
vt = T . borrowed ( vt )
end





if ownershipKind ( vt ) == "affine" and # ( ( vt ) . cleanups or { } ) > 0 and stat . body then
stat . loopOwnerNames = stat . loopOwnerNames or { }
if not stat . loopOwnerNames [ j ] then
local hidden = { }
for key , value in pairs ( nameTok ) do
hidden [ key ] = value
end
c . loopOwnerCount = ( c . loopOwnerCount or 0 ) + 1
hidden . text = ("__nuppLoopOwner%d") : format ( c . loopOwnerCount )
hidden . definition = nil
stat . loopOwnerNames [ j ] = nameTok
stat . names [ j ] = hidden
for index , child in ipairs ( stat ) do
if child == nameTok then
stat [ index ] = hidden
end
end
local value = { kind = "name" , token = hidden }
value [ 1 ] = hidden
local ownerStat = {
kind = "localStmt" ,
names = { nameTok } ,
types = { } ,
exprs = { value } ,
syntheticLoopOwner = true ,
}
local body = stat . body
table . insert ( body . stats , 1 , ownerStat )
table . insert ( body , 1 , ownerStat )
end
nameTok = stat . names [ j ]
end
c . bindVar ( nameTok . text , vt , false , nameTok )
local entry = c . scope . vars [ nameTok . text ]




if entry and fixedWidth . isValue ( T . unwrapOwnership ( vt ) ) then
c . fixedWidth . mark ( entry , T . unwrapOwnership ( vt ) )
end
if entry and ownershipKind ( vt ) == "borrowed" then
local bindingFacts = own . capabilityFacts ( entry )
bindingFacts . roots = iteratorRoots
bindingFacts . exclusive = mode == "exclusive" or nil
for _ , root in ipairs ( iteratorRoots ) do
root . activeBorrows = ( root . activeBorrows or 0 ) + 1
root . activeBorrowSites = root . activeBorrowSites or { }
root . activeBorrowSites [ entry ] = nameTok
if bindingFacts . exclusive then
root . activeExclusiveBorrows = ( root . activeExclusiveBorrows or 0 ) + 1
end
end
end
end
local frame = openLoop ( stat , ownershipBefore )
c . loops . push ( stat . body )
c . checkBlock ( stat . body , true )
c . loops . pop ( )
closeLoop ( frame )
c . popScope ( )
unassignedRestore ( unassignedBefore )
checkLoopBackEdge ( ownershipBefore , stat . body , stat )
settleLoop ( frame , alwaysExits ( stat . body ) and frame . header or edgeOwnership ( ) )
if headerBlock and headerLocal and hiddenNames then
headerBlock . automaticOwners = c . scope . automaticOwners
for _ , owner in ipairs ( headerBlock . automaticOwners or { } ) do
owner . boundary = cst . lastToken ( stat )
end
c . popScope ( )

local original = { }
for key , value in pairs ( stat ) do
original [ key ] = value
end
local rewritten = { }
local inHeader , afterHeader = false , false
for _ , child in ipairs ( original ) do
if not inHeader then
rewritten [ # rewritten + 1 ] = child
if cst . isToken ( child ) and child . kind == "in" then
inHeader = true
for slot , name in ipairs ( hiddenNames ) do
local use = { kind = "name" , token = name , name }
rewritten [ # rewritten + 1 ] = use
if slot < 3 then
local comma = { }
for key , value in pairs ( name ) do
comma [ key ] = value
end
comma . kind , comma . text = "," , ","
rewritten [ # rewritten + 1 ] = comma
end
end
end
elseif cst . isToken ( child ) and child . kind == "do" then
afterHeader = true
rewritten [ # rewritten + 1 ] = child
elseif afterHeader then
rewritten [ # rewritten + 1 ] = child
end
end
original . exprs = { }
for slot , name in ipairs ( hiddenNames ) do
original . exprs [ slot ] = { kind = "name" , token = name , name }
end
for index , child in ipairs ( rewritten ) do
original [ index ] = child
end
for index = # rewritten + 1 , # original do
original [ index ] = nil
end
headerBlock . stats [ 2 ] , headerBlock [ 1 ] , headerBlock [ 2 ] = original , headerLocal , original
iteratorCallNode = original
local first = cst . firstToken ( original )
local last = cst . lastToken ( original )
local doTok = { }
local endTok = { }
for key , value in pairs ( first or { } ) do
doTok [ key ] = value
end
for key , value in pairs ( last or { } ) do
endTok [ key ] = value
end
doTok . kind , doTok . text , doTok . triviaCount = "do" , "do" , 0
endTok . kind , endTok . text , endTok . triviaCount = "end" , "end" , 0
local wrapper = stat
for key in pairs ( wrapper ) do
wrapper [ key ] = nil
end
wrapper . kind , wrapper . body = "doStmt" , headerBlock
wrapper [ 1 ] , wrapper [ 2 ] , wrapper [ 3 ] = doTok , headerBlock , endTok
end
c . nosuspend . iterator ( iteratorCallNode , iterT )
end

return handlers
end

local __nuppExportValue= control ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.control"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.control"]=__nuppExports;return __nuppExports