_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()















local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local narrowing = require ( "nupp.compiler.types.narrowing" )
local mutation = require ( "nupp.compiler.check.mutation" )
local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local state = require ( "nupp.compiler.check.state" )

local narrow = { }

local isA = relations . isA
local subtract = narrowing . subtract
local truthiness = narrowing . truthiness
local withoutMember = narrowing . withoutMember



local LUA_TYPE_NAMES

= {
[ "nil" ] = T . nil_ ,
boolean = T . boolean ,
number = T . number ,
string = T . string ,
table = T . table_ ,
thread = T . thread ,
userdata = T . userdata ,
cdata = T . cdata ,
}





























































































local function correlateGroup ( into , arms , group ) 
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
if node . kind == "dotIndex" or node . kind == "safeIndex" then


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

function facts . clearNarrowedBelow ( key ) 
local sc = c . scope
while sc do
if sc . narrowed then
for k in pairs ( sc . narrowed ) do
if k : sub ( 1 , # key + 1 ) == key .. "." then
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
if node . kind == "safeIndex" and node . name then
local baseT = c . refType ( node . obj )
local ft = baseT and c . fieldType ( subtract ( baseT , T . nil_ ) , node . name . text ) or nil
if ft then
return T . optional ( ft )
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



function facts . clearAliasesBelow ( key ) 
local sc = c . scope
while sc do
for _ , entry in pairs ( sc . vars ) do
local from = entry . aliasPath
if from and from : sub ( 1 , # key + 1 ) == key .. "." then
entry . aliasNode , entry . aliasPath = nil , nil
end
end
sc = sc . parent
end
end

function facts . aliasTarget ( key ) 
local resolved = nil
local seen = { }
local current = key
while true do
local root , suffix = current : match ( "^([^.]+)(.*)$" )
local entry = root and not seen [ root ] and c . lookupEntry ( root ) or nil
if not ( entry and entry . aliasPath ) then
do break end
end
seen [ root ] = true
current = entry . aliasPath .. suffix
resolved = current
end

return resolved
end







local function copiesOf ( key ) 



local out = { }
local canonical = facts . aliasTarget ( key ) or key
local sc = c . scope
local seen = { }
while sc do
for name , entry in pairs ( sc . vars ) do
if entry . aliasPath and not seen [ name ] then
seen [ name ] = true
local origin = facts . aliasTarget ( name ) or entry . aliasPath
if canonical : sub ( 1 , # origin + 1 ) == origin .. "." then
out [ # out + 1 ] = { name = name , path = name .. canonical : sub ( # origin + 1 ) }
end
end
end
sc = sc . parent
end

return out
end



local function clearNameNarrowing ( name ) 
local sc = c . scope
while sc do
local entry = sc . vars [ name ]
if entry and entry . narrowing then
entry . t = entry . decl or entry . t
entry . narrowing = false
end
sc = sc . parent
end
end

function facts . clearWrite ( key , belowOnly ) 
local targets = { key }
local aliased = facts . aliasTarget ( key )
if aliased then
targets [ # targets + 1 ] = aliased
end
for _ , copy in ipairs ( copiesOf ( key ) ) do
targets [ # targets + 1 ] = copy . path
end
for _ , target in ipairs ( targets ) do
if belowOnly then
facts . clearNarrowedBelow ( target )
else
facts . clearNarrowed ( target )
if not target : find ( "." , 1 , true ) then
clearNameNarrowing ( target )
end
end
end
end

local summaries = nil
function facts . summaries ( ) 
if not summaries then
summaries = mutation . prescan ( c . result and c . result . root or nil )
end

return summaries
end

function facts . forgetWritten ( block ) 
if not block then
return
end
local whole , below = mutation . writtenRoots ( facts . summaries ( ) , block )
for key in pairs ( whole ) do
if c . lookupEntry ( key : match ( "^[^.]+" ) or key ) then
facts . clearWrite ( key )
facts . clearAliases ( key )
end
end
for key in pairs ( below ) do
if not whole [ key ] and c . lookupEntry ( key : match ( "^[^.]+" ) or key ) then
facts . clearWrite ( key , true )
facts . clearAliasesBelow ( key )
end
end
end




local function visibleEntry ( name ) 
local sc = c . scope
while sc do
local entry = sc . vars [ name ]
if entry then
return entry
end
sc = sc . parent
end

return nil
end

function facts . hideCapturedNarrowing ( body ) 
local restore




= { }


facts . summaries ( )
local first = cst . firstToken ( body )
local offset = first and first . offset or 0

local function writtenLater ( entry , path ) 
local token = entry and entry . definition and entry . definition . token or nil
return token ~= nil and mutation . writtenAfter ( token , offset , path )
end

local sc = c . scope
while sc do
for name , entry in pairs ( sc . vars ) do
if entry . narrowing and ( entry . functionDepth or 0 ) < c . functionDepth and writtenLater ( entry , name ) then
restore [ # restore + 1 ] = { entry = entry , t = entry . t }
entry . t = entry . decl or entry . t
end
end
for key , t in pairs ( sc . narrowed or { } ) do
local root = key : match ( "^[^.]+" ) or key
local outer = visibleEntry ( root )
if outer and ( outer . functionDepth or 0 ) < c . functionDepth and writtenLater ( outer , key ) then
restore [ # restore + 1 ] = { map = sc . narrowed , key = key , t = t }
sc . narrowed [ key ] = nil
end
end
sc = sc . parent
end

return function ( ) 
for _ , item in ipairs ( restore ) do
if item . entry then
item . entry . t = item . t
else
item . map [ item . key ] = item . t
end
end
end
end

function facts . invalidateForCall ( ) 
local cleared = { whole = { } , below = { } , entries = { } }
for key in pairs ( c . callMutationRoots or { } ) do
cleared . below [ key ] = true
facts . clearWrite ( key , true )


facts . clearAliasesBelow ( key )
for _ , copy in ipairs ( copiesOf ( key ) ) do
facts . clearAliasesBelow ( copy . name )
end
end
c . callMutationRoots = nil
for key in pairs ( c . callMutatedNames or { } ) do
if c . lookupEntry ( key : match ( "^[^.]+" ) or key ) then
cleared . whole [ key ] = true
facts . clearWrite ( key )
facts . clearAliases ( key )
end
end
c . callMutatedNames = nil
for mutated in pairs ( c . callMutatedEntries or { } ) do
cleared . entries [ mutated ] = true
if mutated . definition then
cleared . entries [ mutated . definition ] = true
end
local sc = c . scope
while sc do
for _ , entry in pairs ( sc . vars ) do
if entry == mutated or ( mutated . definition and entry . definition == mutated . definition ) then
if entry . narrowing then
entry . t = entry . decl
entry . narrowing = false
end
end
end
sc = sc . parent
end
end
c . callMutatedEntries = nil

return cleared
end



function facts . withoutCleared ( map , cleared ) 
if not cleared or not next ( cleared . whole ) and not next ( cleared . below ) and not next ( cleared . entries ) then
return map
end
local out = { }
for key , t in pairs ( map ) do
local plain = key : match ( "^@coroutine:(.+)$" ) or key
local keep = true
for whole in pairs ( cleared . whole ) do
if plain == whole or plain : sub ( 1 , # whole + 1 ) == whole .. "." then
keep = false
end
end
for below in pairs ( cleared . below ) do
if plain : sub ( 1 , # below + 1 ) == below .. "." then
keep = false
end
end
local entry = c . lookupEntry ( plain : match ( "^[^.]+" ) or plain )
if entry and ( cleared . entries [ entry ] or entry . definition and cleared . entries [ entry . definition ] ) then
keep = false
end
if keep then
out [ key ] = t
end
end

return out
end










function facts . discriminantBase ( refNode , literals ) 
local discNode = refNode . kind == "dotIndex" and refNode or nil
if refNode . kind == "name" and refNode . token then
local entry = c . lookupEntry ( refNode . token . text )
discNode = entry and entry . aliasNode or nil
end
if not discNode or discNode . kind ~= "dotIndex" or not discNode . obj or not discNode . name then
return nil , nil , nil
end
local baseKey = facts . pathKey ( discNode . obj )
local baseT = c . refType ( discNode . obj )
if not baseKey or not baseT or baseT . tag ~= "union" then
return nil , nil , nil
end
local kept , dropped = { } , { }
for _ , m in ipairs ( baseT . members ) do
local ft = c . fieldType ( m , discNode . name . text )
local admits = false
for _ , litT in ipairs ( literals ) do
if ft and isA ( litT , ft ) then
admits = true
do break end
end
end
if admits then
kept [ # kept + 1 ] = m
else
dropped [ # dropped + 1 ] = m
end
end
if # kept == 0 or # dropped == 0 then
return nil , nil , nil
end

return baseKey , T . union ( kept ) , T . union ( dropped )
end








local function alwaysTruthy ( node ) 
if not node then
return false
end
if node . kind == "paren" then
return alwaysTruthy ( node . expr )
end


local kind = node . kind
if kind == "number"
or kind == "string"
or kind == "dedentString"
or kind == "istring"
or kind == "trueExpr"
or kind == "tableExpr"
or kind == "funcExpr"
or kind == "shortfn"
then
return true
end
local vt = c . refType ( node )
if not vt or vt == T . any or vt == T . unknown or vt == T . never or vt . tag == "typevar" then
return false
end
local _ , falsy = truthiness ( vt )

return falsy == nil
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
correlateGroup ( out . t , trueArms , group )
correlateGroup ( out . f , falseArms , group )
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
local target = cond . typeTestTarget
if key and first and target then
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

local target = cond . typeTestTarget
if key and target then
local vt = c . refType ( cond . expr )
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


local step = nameNode
local safe = false
while step and ( step . kind == "dotIndex" or step . kind == "safeIndex" ) do
if step . kind == "safeIndex" and step . obj then
local baseKey = facts . pathKey ( step . obj )
local baseT = c . refType ( step . obj )
if baseKey and baseT then
neNil [ baseKey ] = subtract ( baseT , T . nil_ )
end
safe = true
end
step = step . obj
end
if safe then
eqNil = { }
end
if op == "==" then
return { t = eqNil , f = neNil }
else
return { t = neNil , f = eqNil }
end
end
return none
end






local typeCall = lhs . kind == "call" and lhs or rhs . kind == "call" and rhs or nil
local typeName = typeCall == lhs and rhs or lhs
if typeCall and typeName and typeName . kind == "string" then
local typeCallee = typeCall . obj
local typeTok = typeCallee and typeCallee . kind == "name" and typeCallee . token or nil
local typeGlobal = c . env and c . env . globals and c . env . globals . type or nil
local typeEntry = typeTok and typeTok . text == "type" and c . lookupEntry ( "type" ) or nil
local typeArgs = typeCall . args
local subjects = typeArgs and typeArgs . kind == "args" and typeArgs . exprs or { }
local subject = # subjects == 1 and subjects [ 1 ] or nil
local subjectKey = subject and facts . pathKey ( subject ) or nil
if subjectKey
and subject
and typeGlobal
and typeEntry
and typeGlobal . definition == typeEntry . definition
then
local named = c . infer ( typeName )
local proves = named . tag == "literal" and LUA_TYPE_NAMES [ tostring ( named . constant ) ] or nil
if proves and c . refType ( subject ) == T . unknown then
local proven = { [ subjectKey ] = proves }
if op == "==" then
return { t = proven , f = { } }
end
return { t = { } , f = proven }
end
end
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
if entry
and entry . coroutineStatusName
and litT . tag == "literal"
and type ( litT . constant ) == "string"
then
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
correlateGroup ( out . t , selected , group )
correlateGroup ( out . f , rejected , group )
end
end

local refT = c . refType ( refNode )
local rest , emptied = withoutMember ( refT , litT )
if rest then
out . f [ key ] = rest
elseif emptied then
out . exhausted = key
end
local baseKey , kept , dropped = facts . discriminantBase ( refNode , { litT } )
if baseKey and kept and dropped then
out . t [ baseKey ] = kept
out . f [ baseKey ] = dropped
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
local rhsAlwaysTrue = alwaysTruthy ( rhs )
c . popScope ( )






return { t = facts . mergeFacts ( l . t , r . t ) , f = rhsAlwaysTrue and l . f or { } }
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
runtimeSurfaceRoot = entry . runtimeSurfaceRoot ,
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
runtimeSurfaceRoot = entry and entry . runtimeSurfaceRoot or nil ,
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

local __nuppExportValue= narrow ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.narrow"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.narrow"]=__nuppExports;return __nuppExports