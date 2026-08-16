_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);













local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local narrowing = require ( "nupp.compiler.narrowing" )
local cst = require ( "nupp.compiler.cst" )
local lexer = require ( "nupp.compiler.lexer" )
local state = require ( "nupp.compiler.check.state" )

local narrow = { }

local isA = relations . isA
local subtract = narrowing . subtract
local truthiness = narrowing . truthiness
local withoutMember = narrowing . withoutMember


















































function narrow . install ( c )
local facts = { }

function facts . mergeFacts ( a , b )
local out = { }
for k , v in pairs ( a ) do
out [ k ] = v
end
for k , v in pairs ( b ) do
out [ k ] = v
end

return out
end







function facts . pathKey ( node )
if node . kind == "name" then
return node . token and node . token . text or nil
end
if node . kind == "dotIndex" then
local base = facts . pathKey ( node . obj )
if base and node . name then
return base .. "." .. node . name . text
end
end

return nil
end






c . funcOwner = function ( fname )
local names = { }
for _ , child in ipairs ( fname ) do
if cst . isToken ( child ) and child . kind == "name" then
names [ # names + 1 ] = child
end
end
if fname . method then

table . remove ( names )
if # names == 0 then
return nil , nil
end
local parts = { }
for j , tok in ipairs ( names ) do
parts [ j ] = tok . text
end
return table . concat ( parts , "." ) , fname . method
end
if # names < 2 then
return nil , nil
end
local member = table . remove ( names )
local parts = { }
for j , tok in ipairs ( names ) do
parts [ j ] = tok . text
end

return table . concat ( parts , "." ) , member
end





function facts . lookupNarrowed ( key )
local sc = c . scope
while sc do
local t = sc . narrowed and sc . narrowed [ key ]
if t then
return t
end
sc = sc . parent
end

return nil
end





function facts . clearNarrowed ( key )
local sc = c . scope
while sc do
if sc . narrowed then
for k in pairs ( sc . narrowed ) do
if k == key or k : sub ( 1 , # key + 1 ) == key .. "." then
sc . narrowed [ k ] = nil
end
end
end
sc = sc . parent
end
end

c . refType = function ( node )
if not node then
return nil
end
local key = facts . pathKey ( node )
if key then
local narrowed = facts . lookupNarrowed ( key )
if narrowed then
return narrowed
end
end
if node . kind == "name" then
return c . lookupVar ( node . token . text )
end
if node . kind == "dotIndex" then
local baseT = c . refType ( node . obj )
if baseT then
return c . fieldType ( baseT , node . name . text )
end
end

return nil
end








function facts . clearAliases ( key )
local sc = c . scope
while sc do
for name , entry in pairs ( sc . vars ) do
local from = entry . aliasPath
if name == key or ( from and ( from == key or from : sub ( 1 , # key + 1 ) == key .. "." ) ) then
entry . aliasNode , entry . aliasPath = nil , nil
end
end
sc = sc . parent
end
end









function facts . analyzeCond ( cond )
local none = { t = { } , f = { } }
local kind = cond . kind
if kind == "paren" then
return facts . analyzeCond ( cond . expr )
elseif kind == "name" then
local name = cond . token and cond . token . text or ""
local vt = c . lookupVar ( name )
if vt then
local out = { t = { } , f = { } }
local truthy , falsy = truthiness ( vt )
if truthy then
out . t [ name ] = truthy
end
if falsy then
out . f [ name ] = falsy
end
local entry = c . lookupEntry ( name )
local group = entry and entry . packCorrelation
local at = entry and entry . packCorrelationIndex
if group and at then
local trueArms , falseArms = { } , { }
for _ , arm in ipairs ( group . pack . alternatives or { } ) do
local value = T . packAt ( arm , at ) or T . nil_
local armTrue , armFalse = truthiness ( value )
if armTrue then
trueArms [ # trueArms + 1 ] = arm
end
if armFalse then
falseArms [ # falseArms + 1 ] = arm
end
end
local function correlate ( into , arms )
for index , sibling in pairs ( group . names ) do
local members = { }
for _ , arm in ipairs ( arms ) do
members [ # members + 1 ] = T . packAt ( arm , index ) or T . nil_
end
if # members > 0 then
into [ sibling ] = T . union ( members )
end
end
for _ , copy in ipairs ( group . extraNames or { } ) do
local members = { }
for _ , arm in ipairs ( arms ) do
members [ # members + 1 ] = T . packAt ( arm , copy . index ) or T . nil_
end
if # members > 0 then
into [ copy . name ] = T . union ( members )
end
end
end

correlate ( out . t , trueArms )
correlate ( out . f , falseArms )
end
return out
end
return none
elseif kind == "dotIndex" then


local key = facts . pathKey ( cond )
local vt = key and c . refType ( cond )
if key and vt then
local out = { t = { } , f = { } }
local truthy , falsy = truthiness ( vt )
if truthy then
out . t [ key ] = truthy
end
if falsy then
out . f [ key ] = falsy
end
return out
end
return none
elseif kind == "call" then
local argsNode = cond . args
local args = argsNode and argsNode . kind == "args" and argsNode . exprs or { }

local callee = cond . obj
if callee and callee . kind == "dotIndex" then
local typeArg = callee . ffiTypeArg
local member = callee . name
if typeArg and member and member . text == "istype" then
local first = args [ 1 ]
local key = first and facts . pathKey ( first )
if key and first then
local target = c . resolveType ( typeArg )
local vt = c . refType ( first )
local out = { t = { } , f = { } }
out . t [ key ] = target
if vt then
out . f [ key ] = subtract ( vt , target )
end
return out
end
return none
end
end


c . infer ( cond )
local ft = cond . calleeType
local predicate = ft and ft . tag == "func" and ft . predicate or nil
if predicate then
local arg = args [ predicate . param ]
local key = arg and facts . pathKey ( arg )
if key and arg then
local vt = c . refType ( arg )
local out = { t = { } , f = { } }
out . t [ key ] = predicate . type
if vt then
out . f [ key ] = subtract ( vt , predicate . type )
end
return out
end
end
return none
elseif kind == "isExpr" then
local key = cond . expr and facts . pathKey ( cond . expr )
if key then
local vt = c . refType ( cond . expr )
local target = c . resolveType ( cond . type )
local out = { t = { } , f = { } }
out . t [ key ] = target
if vt then
out . f [ key ] = subtract ( vt , target )
end
return out
end
return none
elseif kind == "unop" and cond . op and cond . op . kind == "not" and cond . operand then
local inner = facts . analyzeCond ( cond . operand )
return { t = inner . f , f = inner . t }
elseif kind == "binop" then
local opTok , lhs , rhs = cond . op , cond . lhs , cond . rhs
if not opTok or not lhs or not rhs then
return none
end
local op = opTok . kind
if op == "==" or op == "~=" then

local nameNode , nilNode
if rhs . kind == "nilExpr" then
nameNode , nilNode = lhs , rhs
elseif lhs . kind == "nilExpr" then
nameNode , nilNode = rhs , lhs
end
if nilNode then
local key = facts . pathKey ( nameNode )
local vt = key and c . refType ( nameNode )
if key and vt then
local eqNil = { [ key ] = T . nil_ }
local neNil = { [ key ] = subtract ( vt , T . nil_ ) }
if op == "==" then
return { t = eqNil , f = neNil }
else
return { t = neNil , f = eqNil }
end
end
return none
end



local refNode , litNode
if rhs . kind == "string"
or rhs . kind == "number"
or rhs . kind == "trueExpr"
or rhs . kind == "falseExpr"
then
refNode , litNode = lhs , rhs
elseif lhs . kind == "string"
or lhs . kind == "number"
or lhs . kind == "trueExpr"
or lhs . kind == "falseExpr"
then
refNode , litNode = rhs , lhs
end


local aliasNode
if refNode and refNode . kind == "name" then
local refTok = refNode . token
local e = refTok and c . lookupEntry ( refTok . text )
aliasNode = e and e . aliasNode or nil
end
local key = refNode and facts . pathKey ( refNode )
if key then
local litT = c . infer ( litNode )
local out = { t = { } , f = { } }
if aliasNode then
local aliasKey = facts . pathKey ( aliasNode )
if aliasKey then
out . t [ aliasKey ] = litT
local aliasT = c . refType ( aliasNode )
local rest = aliasT and withoutMember ( aliasT , litT ) or nil
if rest then
out . f [ aliasKey ] = rest
end
end
end
out . t [ key ] = litT
if refNode . kind == "name" and refNode . token then
local entry = c . lookupEntry ( refNode . token . text )
if entry and entry . coroutineStatusName and litT . tag == "literal" and type (
litT . constant
) == "string" then
out . t [ "@coroutine:" .. entry . coroutineStatusName ] = litT
end
local group = entry and entry . packCorrelation
local slot = entry and entry . packCorrelationIndex
if group and slot then
local selected , rejected = { } , { }
for _ , arm in ipairs ( group . pack . alternatives or { } ) do
local armType = T . packAt ( arm , slot ) or T . nil_
if isA ( litT , armType ) then
selected [ # selected + 1 ] = arm
else
rejected [ # rejected + 1 ] = arm
end
end
local function addCorrelated ( into , arms )
for index , sibling in pairs ( group . names ) do
local members = { }
for _ , arm in ipairs ( arms ) do
members [ # members + 1 ] = T . packAt ( arm , index ) or T . nil_
end
if # members > 0 then
into [ sibling ] = T . union ( members )
end
end
for _ , copy in ipairs ( group . extraNames or { } ) do
local members = { }
for _ , arm in ipairs ( arms ) do
members [ # members + 1 ] = T . packAt ( arm , copy . index ) or T . nil_
end
if # members > 0 then
into [ copy . name ] = T . union ( members )
end
end
end

addCorrelated ( out . t , selected )
addCorrelated ( out . f , rejected )
end
end

local refT = c . refType ( refNode )
local rest , emptied = withoutMember ( refT , litT )
if rest then
out . f [ key ] = rest
elseif emptied then
out . exhausted = key
end
local discNode = refNode . kind == "dotIndex" and refNode or aliasNode
if discNode and discNode . obj then
local baseKey = facts . pathKey ( discNode . obj )
local baseT = c . refType ( discNode . obj )
if baseKey and baseT and baseT . tag == "union" then
local kept , dropped = { } , { }
for _ , m in ipairs ( baseT . members ) do
local ft = c . fieldType ( m , discNode . name . text )
if ft and isA ( litT , ft ) then
kept [ # kept + 1 ] = m
else
dropped [ # dropped + 1 ] = m
end
end
if # kept > 0 and # dropped > 0 then
out . t [ baseKey ] = T . union ( kept )
out . f [ baseKey ] = T . union ( dropped )
end
end
end
if op == "~=" then
return { t = out . f , f = out . t }
end
return out
end
return none
elseif op == "and" then



local l = facts . analyzeCond ( lhs )
c . pushScope ( )
facts . applyFacts ( l . t )
local r = facts . analyzeCond ( rhs )
c . popScope ( )

return { t = facts . mergeFacts ( l . t , r . t ) , f = { } }
elseif op == "or" then


local l = facts . analyzeCond ( lhs )
c . pushScope ( )
facts . applyFacts ( l . f )
local r = facts . analyzeCond ( rhs )
c . popScope ( )




local t = { }
for key , lt in pairs ( l . t ) do
local rt = r . t [ key ]
if rt then
t [ key ] = T . union ( { lt , rt } )
end
end


local fal = facts . mergeFacts ( l . f , r . f )
for key , lf in pairs ( l . f ) do
local rf = r . f [ key ]
if rf then
local keep , seen = { } , { }
for _ , m in ipairs ( lf . tag == "union" and lf . members or { lf } ) do
seen [ m ] = true
end
for _ , m in ipairs ( rf . tag == "union" and rf . members or { rf } ) do
if seen [ m ] then
keep [ # keep + 1 ] = m
end
end
if # keep > 0 then
fal [ key ] = T . union ( keep )
end
end
end
return { t = t , f = fal }
end
return none
end

return none
end



function facts . snapshotNarrowed ( )
local out , blocked = { } , { }
local sc = c . scope
while sc do
if sc . narrowed then
for k , v in pairs ( sc . narrowed ) do
if out [ k ] == nil and not blocked [ k ] then
out [ k ] = v
end
end
end
for k , entry in pairs ( sc . vars ) do
if out [ k ] == nil and not blocked [ k ] then
if entry . narrowing then
out [ k ] = entry . t
else


blocked [ k ] = true
end
end
end
sc = sc . parent
end

return out
end






local function carryFixedWidth ( shadow , entry )
local established = entry and entry . fixedWidthEstablished or nil
if established then
local copied = { }
for fact in pairs ( established ) do
copied [ fact ] = true
end
shadow . fixedWidthEstablished = copied
end
shadow . fixedWidthTrusted = entry and entry . fixedWidthTrusted or nil
shadow . fixedWidthCallableUntrusted = entry and entry . fixedWidthCallableUntrusted or nil

return shadow
end






function facts . applyFacts ( facts )
for name , t in pairs ( facts ) do
local coroutineName = name : match ( "^@coroutine:(.+)$" )
if coroutineName then
local entry = c . lookupEntry ( coroutineName )
if entry then
local phase = t . tag == "literal" and t . constant == "dead" and "dead" or entry . threadPhase
c . scope . vars [
coroutineName
] = carryFixedWidth (
{
t = entry . t ,
narrowing = true ,
ann = entry . ann or false ,
constant = entry . constant or false ,
decl = entry . decl or entry . t ,
definition = entry . definition ,
ownership = entry . ownership ,
moved = c . ownershipState ( entry ) . moved or false ,
ownershipOrigin = c . ownershipState ( entry ) ,
functionDepth = entry . functionDepth or c . functionDepth ,
threadPhase = phase ,
} ,
entry
)
end
elseif name : find ( "." , 1 , true ) then
c . scope . narrowed = c . scope . narrowed or { }
c . scope . narrowed [ name ] = t
else
local entry = c . lookupEntry ( name )
local conditionalOwnership = entry and entry . packCorrelation and c . ownershipKind ( t ) or nil
local moved = entry and c . ownershipState ( entry ) . moved or false
local ownershipOrigin = entry and c . ownershipState ( entry ) or nil
if conditionalOwnership then
moved , ownershipOrigin = false , nil
end
c . scope . vars [ name ] = carryFixedWidth (
{
t = t ,
narrowing = true ,


aliasNode = entry and entry . aliasNode or nil ,
aliasPath = entry and entry . aliasPath or nil ,
ann = entry and entry . ann or false ,
constant = entry and entry . constant or false ,
decl = entry and ( entry . decl or entry . t ) or t ,
definition = entry and entry . definition or nil ,







ownership = conditionalOwnership or entry and entry . ownership or nil ,
moved = moved ,
ownershipOrigin = ownershipOrigin ,
automaticOwner = entry and entry . automaticOwner or nil ,
functionDepth = entry and entry . functionDepth or c . functionDepth ,
threadPhase = entry and entry . threadPhase or nil ,
wrappedProtocol = entry and entry . wrappedProtocol or nil ,
wrappedPhase = entry and entry . wrappedPhase or nil ,
} ,
entry
)
end
end
end



c . pathKey = facts . pathKey
c . applyFacts = facts . applyFacts
c . analyzeCond = facts . analyzeCond
c . lookupNarrowed = facts . lookupNarrowed

return facts
end

return narrow
