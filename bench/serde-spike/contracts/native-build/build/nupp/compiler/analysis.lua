_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
























local cst = require ( "nupp.compiler.syntax.cst" )
local callfacts = require ( "nupp.compiler.callfacts" )
local inlinefacts = require ( "nupp.compiler.inlinefacts" )
local viewfacts = require ( "nupp.compiler.viewfacts" )


local analysis = { }













local LISTS = { "reads" , "writes" , "shapes" , "metatables" , "escapes" , "calls" }
local FLAGS = { "allocates" , "yields" , "raises" , "external" }








local INFERRED_FLAGS = { "rawYields" , "allocatesBeyondWideArithmetic" , "raisesBeyondBounds" }

local function setOf ( values ) 
local out = { }
for _ , value in ipairs ( values or { } ) do
out [ value ] = true
end

return out
end

local function summary ( ) 
return {
reads = { } ,
writes = { } ,
shapes = { } ,
metatables = { } ,
escapes = { } ,
calls = { } ,
returns = { } ,
allocates = false ,
allocatesBeyondWideArithmetic = false ,
yields = false ,
raises = false ,
raisesBeyondBounds = false ,
external = false ,
rawYields = false ,
top = false ,
}
end

local function unknownSummary ( ) 
local out = ( { reads = { } , writes = { } , shapes = { } , metatables = { } , escapes = { } , calls = { } , returns = { } , allocates = false , allocatesBeyondWideArithmetic = false , yields = false , raises = false , raisesBeyondBounds = false , external = false , rawYields = false , top = false , } )
out . top = true
return out
end

local function fromContract ( contract ) 
local out = ( { reads = { } , writes = { } , shapes = { } , metatables = { } , escapes = { } , calls = { } , returns = { } , allocates = false , allocatesBeyondWideArithmetic = false , yields = false , raises = false , raisesBeyondBounds = false , external = false , rawYields = false , top = false , } )
for _ , name in ipairs ( LISTS ) do
out [ name ] = setOf ( contract [ name ] )
end
for _ , value in ipairs ( contract . returns or { } ) do
out . returns [ value ] = true
end
for _ , name in ipairs ( FLAGS ) do
out [ name ] = contract [ name ] == true
end


out . allocatesBeyondWideArithmetic = out . allocates
out . raisesBeyondBounds = out . raises

return out
end

local function copy ( value ) 
local out = ( { reads = { } , writes = { } , shapes = { } , metatables = { } , escapes = { } , calls = { } , returns = { } , allocates = false , allocatesBeyondWideArithmetic = false , yields = false , raises = false , raisesBeyondBounds = false , external = false , rawYields = false , top = false , } )
out . top = value . top == true
for _ , name in ipairs ( LISTS ) do
for path in pairs ( value [ name ] or { } ) do
out [ name ] [ path ] = true
end
end
for value2 in pairs ( value . returns or { } ) do
out . returns [ value2 ] = true
end
for _ , name in ipairs ( FLAGS ) do
out [ name ] = value [ name ] == true
end
for _ , name in ipairs ( INFERRED_FLAGS ) do
out [ name ] = value [ name ] == true
end

return out
end

local function join ( into , other ) 
local changed = false
if other . top and not into . top then
into . top , changed = true , true
end
for _ , name in ipairs ( LISTS ) do
for path in pairs ( other [ name ] or { } ) do
if not into [ name ] [ path ] then
into [ name ] [ path ] , changed = true , true
end
end
end
for value in pairs ( other . returns or { } ) do
if not into . returns [ value ] then
into . returns [ value ] , changed = true , true
end
end
for _ , name in ipairs ( FLAGS ) do
if other [ name ] and not into [ name ] then
into [ name ] , changed = true , true
end
end
for _ , name in ipairs ( INFERRED_FLAGS ) do
if other [ name ] and not into [ name ] then
into [ name ] , changed = true , true
end
end

return changed
end

local function same ( a , b ) 
local left , right = copy ( a ) , copy ( b )
return not join ( left , right ) and not join ( right , left )
end





local function unwrap ( stat ) 
while stat and stat . kind == "pragmaStmt" do
stat = stat . stat
end
return stat
end

local function directName ( expr ) 
while expr and ( expr . kind == "paren" or expr . kind == "castExpr" ) do
expr = expr . expr
end
return expr and expr . kind == "name" and expr . token or nil
end



local NESTED_FUNCTION = {
localFuncStmt = true ,
funcStmt = true ,
inlineMethod = true ,
constructorDecl = true ,
funcExpr = true ,
shortfn = true ,
}

local INDEX = { dotIndex = true , bracketIndex = true , safeIndex = true , safeBracket = true }




local function indexBase ( target ) 
local base = target
while base and INDEX [ base . kind ] do
base = base . obj
end

return base
end




local function unionFind ( ) 
local parent = { }

local function find ( value ) 
if not value then
return nil
end
parent [ value ] = parent [ value ] or value
if parent [ value ] ~= value then
parent [ value ] = find ( parent [ value ] )
end

return parent [ value ]
end

local function union ( a , b ) 
a , b = find ( a ) , find ( b )
if a and b and a ~= b then
parent [ b ] = a
end
end

return find , union
end

local function callName ( call ) 
local callee = call and call . obj
if not callee then
return nil
end
if callee . kind == "name" then
return callee . token and callee . token . text
end
if callee . kind == "dotIndex" and callee . obj and callee . obj . kind == "name" then
return callee . obj . token . text .. "." .. callee . name . text
end

return nil
end

local function callArgs ( call ) 
local args = call and call . args
if not args or args . kind ~= "args" then
return { }
end
if args . table then
return { args . table }
end

return args . exprs or { }
end




local function knownCall ( call , byDefinition ) 
if call and call . unstableCall then
return nil
end
local selected = call and ( call . constructorEntry or call . methodEntry ) or nil
local declaration = selected and selected . declaration or nil
if declaration and declaration . effectInfo then
return declaration . effectInfo
end
local callee = call and call . obj
local token = callee and ( callee . token or callee . name )

return token and byDefinition [ token . definition ] or call and call . importedEffects or nil
end

local function definitionOfFunction ( stat ) 
if stat . kind == "localFuncStmt" then
return stat . name and stat . name . definition
elseif stat . kind == "funcStmt" then
local name = stat . name
if not name then
return nil
end
local token = name . method or name . base
for _ , child in ipairs ( name ) do
if cst . isToken ( child ) and child . kind == "name" then
token = child
end
end
return token and token . definition
elseif stat . kind == "inlineMethod" or stat . kind == "cdefFunc" then
return stat . name and stat . name . definition
end

return nil
end

local function collectFunctions ( root ) 
local functions , byDefinition = { } , { }
local literalDefinitions = { }

local function walk ( node ) 
if not node or cst . isToken ( node ) then
return
end
local target = unwrap ( node )
local kind = target and target . kind
if kind == "localStmt" then
for index , initializer in ipairs ( target . exprs or { } ) do
local name = target . names and target . names [ index ] or nil
if name and name . definition and initializer then
literalDefinitions [ initializer ] = name . definition
end
end
end




if kind == "funcExpr" or kind == "shortfn" then
local body = kind == "shortfn" and target or target . body
if body then
local info = {
node = target ,
body = body ,
definition = literalDefinitions [ target ] ,
params = { } ,
paramNames = { } ,
contract = body . effectContract ,
summary = unknownSummary ( ) ,
}
for _ , param in ipairs ( body . params or { } ) do
if param . name and not param . namedVararg then
local at = # info . paramNames + 1
if param . name . definition then
info . params [ param . name . definition ] = at
end
info . paramNames [ at ] = param . name . text
end
end
functions [ # functions + 1 ] = info
target . effectInfo = info
if info . definition then
byDefinition [ info . definition ] = info
end
local contents = body . body or kind == "shortfn" and body . expr or nil
if contents then
walk ( contents )
end
return
end
end
if kind == "localFuncStmt" or kind == "funcStmt" or kind == "inlineMethod" or kind == "constructorDecl" then
local body = target . body
local info = {
node = target ,
body = body ,
definition = definitionOfFunction ( target ) ,
params = { } ,
paramNames = { } ,
contract = target . effectContract or body and body . effectContract ,
summary = unknownSummary ( ) ,
}
if target . name and target . name . method then
info . paramNames [ 1 ] = "self"
end
for _ , param in ipairs ( body and body . params or { } ) do
if param . name and not param . namedVararg then
local at = # info . paramNames + 1
if param . name . definition then
info . params [ param . name . definition ] = at
end
info . paramNames [ at ] = param . name . text
end
end
functions [ # functions + 1 ] = info
target . effectInfo = info
if info . definition then
byDefinition [ info . definition ] = info
end
if body and body . body then
walk ( body . body )
end
return
elseif kind == "cdefFunc" then
local info = {
node = target ,
definition = definitionOfFunction ( target ) ,
params = { } ,
paramNames = { } ,
contract = target . effectContract ,
summary = target . effectContract and fromContract ( target . effectContract ) or ( { reads = { } , writes = { } , shapes = { } , metatables = { } , escapes = { } , calls = { } , returns = { } , allocates = false , allocatesBeyondWideArithmetic = false , yields = false , raises = false , raisesBeyondBounds = false , external = false , rawYields = false , top = false , } ) ,
external = true ,
}
if not target . effectContract then
info . summary . top = true
end
for _ , param in ipairs ( target . params or { } ) do
if param . name then
local at = # info . paramNames + 1
if param . name . definition then
info . params [ param . name . definition ] = at
end
info . paramNames [ at ] = param . name . text
end
end
functions [ # functions + 1 ] = info
if info . definition then
byDefinition [ info . definition ] = info
end
return
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( root )

return functions , byDefinition
end



local function bodyContents ( body ) 
if body and body . kind == "shortfn" then
return body . body or body . expr
end

return body and body . body or nil
end





local PURE_BUILTINS = {
type = true ,
tonumber = true ,
select = true ,
rawequal = true ,
rawget = true ,
rawlen = true ,
ipairs = true ,
pairs = true ,
next = true ,
}

local function inferFunction ( info , byDefinition ) 
local out = ( { reads = { } , writes = { } , shapes = { } , metatables = { } , escapes = { } , calls = { } , returns = { } , allocates = false , allocatesBeyondWideArithmetic = false , yields = false , raises = false , raisesBeyondBounds = false , external = false , rawYields = false , top = false , } )
local localDefinitions = { }
local find , union = unionFind ( )

for definition , index in pairs ( info . params ) do
localDefinitions [ definition ] = true
end




local function collectBindings ( node ) 
if not node or cst . isToken ( node ) then
return
end
local kind = node . kind
if kind == "localFuncStmt" then
if node . name and node . name . definition then
localDefinitions [ node . name . definition ] = true
end
return
elseif NESTED_FUNCTION [ kind ] then
return
elseif kind == "localStmt" then
for j , name in ipairs ( node . names or { } ) do
if name . definition then
localDefinitions [ name . definition ] = true
end
local source = directName ( node . exprs and node . exprs [ j ] )
if source then
union ( name . definition , source . definition )
end
end
elseif kind == "fornumStmt" then
if node . name and node . name . definition then
localDefinitions [ node . name . definition ] = true
end
elseif kind == "forinStmt" then
for _ , name in ipairs ( node . names or { } ) do
if name . definition then
localDefinitions [ name . definition ] = true
end
end
elseif kind == "assignStmt" then
for j , target in ipairs ( node . targets or { } ) do
local targetName = directName ( target )
local source = directName ( node . exprs and node . exprs [ j ] )
if targetName and source then
union ( targetName . definition , source . definition )
end
end
end
for _ , child in ipairs ( node ) do
collectBindings ( child )
end
end

collectBindings ( bodyContents ( info . body ) )
local rooted = { }
for definition , index in pairs ( info . params ) do
rooted [ find ( definition ) ] = info . paramNames [ index ]
end

local function rootOf ( expr ) 
local token = directName ( expr )
return token and rooted [ find ( token . definition ) ] or nil
end

local function substitute ( path , callee , args ) 
if path : sub ( 1 , 1 ) == "$" then
return path
end
local root , rest = path : match ( "^([%a_][%w_]*)(.*)$" )
if not root then
return "$capture"
end
local index
for j , name in ipairs ( callee . paramNames or { } ) do
if name == root then
index = j ;
do break end
end
end
if not index then
return "$capture"
end
local actual = rootOf ( args [ index ] )
if actual then
return actual .. rest
end
local token = directName ( args [ index ] )
if token and localDefinitions [ token . definition ] then
return nil
end

return "$capture"
end



local function nativeAggregate ( t ) 
local raw = t
while raw ~= nil
and ( raw . tag == "const" or raw . tag == "affine" or raw . tag == "borrowed" or raw . tag == "pinned" ) do
raw = raw . inner
end
if raw == nil or raw . tag ~= "nominal" then
return false
end
local origin = raw . origin or raw

return origin . declKind == "struct" and origin . nativeOnly == true
end

local function applyCall ( call ) 
if call . scalarIntrinsic or call . ownershipIntrinsic == "adopt" or call . ownershipIntrinsic == "release" then



return
end
local known = knownCall ( call , byDefinition )
local args = callArgs ( call )
if not known and call . isNew and not call . constructorEntry then





out . allocates = true
if not nativeAggregate ( call . inferredType ) then
out . allocatesBeyondWideArithmetic = true
end
return
end
if known then
local effects = known . summary
if effects . top then
out . top = true
end
for _ , list in ipairs ( LISTS ) do
for path in pairs ( effects [ list ] or { } ) do
local mapped = substitute ( path , known , args )
if mapped then
out [ list ] [ mapped ] = true
end
end
end
for _ , flag in ipairs ( FLAGS ) do
if effects [ flag ]
and not ( flag == "raises" and call . callBoundsProven and effects . raisesBeyondBounds == false )
then
out [ flag ] = true
end
end
for _ , flag in ipairs ( INFERRED_FLAGS ) do
if effects [ flag ] then
out [ flag ] = true
end
end
return
end
local name = callName ( call )



if call . trustedYield then
out . yields = true
elseif call . rawYield or name == "coroutine.yield" then
out . yields = true
out . rawYields = true
elseif PURE_BUILTINS [ call . resolvedGlobal or "" ] then
local root = rootOf ( args [ 1 ] )
if root then
out . reads [ root .. "[*]" ] = true
end
elseif name == "error" or name == "assert" then
out . raises = true
out . raisesBeyondBounds = true
else
out . top = true
end
end

local function returnedRoots ( expr ) 
local direct = rootOf ( expr )
if direct then
return { [ 1 ] = direct }
end
if not expr or ( expr . kind ~= "call" and expr . kind ~= "safeCall" and expr . kind ~= "methodCall" ) then
return { }
end
local known = knownCall ( expr , byDefinition )
if not known or known . summary . top then
return { }
end
local args , roots = callArgs ( expr ) , { }
for value in pairs ( known . summary . returns or { } ) do
local resultIndex , root = value : match ( "^(%d+)=([%a_][%w_]*)$" )
if resultIndex and root then
for j , name in ipairs ( known . paramNames or { } ) do
if name == root then
local actual = rootOf ( args [ j ] )
if actual then
roots [ tonumber ( resultIndex ) ] = actual
end
end
end
end
end

return roots
end

local walk
walk = function ( node , targetContext ) 
if not node or cst . isToken ( node ) then
return
end
local kind = node . kind
if NESTED_FUNCTION [ kind ] then
out . allocates = true
out . allocatesBeyondWideArithmetic = true
return
elseif kind == "tableExpr" then
out . allocates = true
out . allocatesBeyondWideArithmetic = true
elseif kind == "newExpr" then
out . allocates = true
if not nativeAggregate ( node . call and node . call . inferredType or node . inferredType ) then
out . allocatesBeyondWideArithmetic = true
end
elseif kind == "istring" then
out . allocates = true
out . allocatesBeyondWideArithmetic = true
if # ( node . parts or { } ) > 0 then

out . top = true
end
elseif kind == "binop" and node . op and node . op . kind == ".." then
out . allocates = true
out . allocatesBeyondWideArithmetic = true
if not node . plainConcat then
out . top = true
end
elseif node . effectUnknownOperation then
out . top = true
elseif node . wideArithmetic then

out . allocates = true
elseif node . gradualIndex then


out . raises = true
out . raisesBeyondBounds = true
elseif node . indexedAccess and not node . rangeProvenNoRaise then
out . raises = true
elseif kind == "call" or kind == "safeCall" or kind == "methodCall" then
applyCall ( node )
elseif kind == "name" and not targetContext then
local root = node . token and rooted [ find ( node . token . definition ) ]
if root then
out . reads [ root ] = true
end
elseif kind == "assignStmt" then
for _ , target in ipairs ( node . targets or { } ) do
local base = indexBase ( target )
local token = directName ( base )
local root = token and rooted [ find ( token . definition ) ]
if root and target ~= base then
out . writes [ root .. "[*]" ] = true
out . shapes [ root ] = true
elseif target ~= base and token and not localDefinitions [ token . definition ] then
out . writes [ "$capture[*]" ] = true
out . shapes [ "$capture" ] = true
end


local level = target
while level ~= base do
if level . expr then
walk ( level . expr , false )
end
level = level . obj
end
walk ( base , base and base . kind == "name" )
end
for j , expr in ipairs ( node . exprs or { } ) do
local escaped = rootOf ( expr )
local target = node . targets and node . targets [ j ]
local targetName = directName ( target )
if escaped
and target
and ( ( targetName and not localDefinitions [ targetName . definition ] ) or not targetName )
then
out . escapes [ escaped ] = true
end
walk ( expr , false )
end
return
elseif kind == "compoundAssign" then
local base = indexBase ( node . target )
local token = directName ( base )
local root = token and rooted [ find ( token . definition ) ]
if root and node . target ~= base then
out . writes [ root .. "[*]" ] = true
end
if root and node . target ~= base then
out . shapes [ root ] = true
end
if node . target ~= base and token and not localDefinitions [ token . definition ] then
out . writes [ "$capture[*]" ] = true
out . shapes [ "$capture" ] = true
end
elseif kind == "returnStmt" then
local exprs = node . exprs or { }
for index , expr in ipairs ( exprs ) do
local roots = returnedRoots ( expr )
if index == # exprs then
for resultIndex , root in pairs ( roots ) do
local output = index + resultIndex - 1
out . returns [ tostring ( output ) .. "=" .. root ] = true
end
elseif roots [ 1 ] then
out . returns [ tostring ( index ) .. "=" .. roots [ 1 ] ] = true
end
end
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
walk ( child , targetContext )
end
end
end
walk ( bodyContents ( info . body ) , false )



local function cleanupEffects ( node ) 
if not node or cst . isToken ( node ) then
return
end
if NESTED_FUNCTION [ node . kind ] then
return
end
local cleanupsHere = { }
for _ , owner in ipairs ( node . automaticOwners or { } ) do
for _ , cleanup in ipairs ( owner . cleanups or { } ) do
cleanupsHere [ # cleanupsHere + 1 ] = cleanup
end
end



if node . kind == "withStmt" then
for _ , binding in ipairs ( node . bindings or { } ) do
for _ , cleanup in ipairs ( binding . ownerCleanups or { } ) do
cleanupsHere [ # cleanupsHere + 1 ] = cleanup
end
end
end
for _ , cleanup in ipairs ( cleanupsHere ) do
do
local operation = cleanup
while operation and operation . kind == "field" do
operation = operation . cleanup
end
local token = operation and operation . kind == "function" and operation . token or nil
local known = token and byDefinition [ token . definition ] or nil
if not known or not known . summary or known . summary . top then
out . top = true
else
if known . summary . allocates then
out . allocates = true
end
if known . summary . allocatesBeyondWideArithmetic then
out . allocatesBeyondWideArithmetic = true
end
if known . summary . raises then
out . raises = true
out . raisesBeyondBounds = true
end
if known . summary . yields then
out . yields = true
end
if known . summary . rawYields then
out . rawYields = true
end
end
end
end
for _ , child in ipairs ( node ) do
cleanupEffects ( child )
end
end

cleanupEffects ( bodyContents ( info . body ) )

return out
end





local function contractContains ( contract , inferred ) 
local declared = fromContract ( contract )
if inferred . top then
return false , "calls code with unknown effects"
end
for _ , list in ipairs ( LISTS ) do
for path in pairs ( inferred [ list ] ) do
if not declared [ list ] [ path ] then
return false , ("is missing %s = %q") : format ( list , path )
end
end
end
for _ , flag in ipairs ( FLAGS ) do
if inferred [ flag ] and not declared [ flag ] then
return false , "is missing " .. flag .. " = true"
end
end
for value in pairs ( inferred . returns ) do
if not declared . returns [ value ] then
return false , "is missing returns = " .. string . format ( "%q" , value )
end
end

return true
end




local function aliasClasses ( body , byDefinition ) 
local find , union = unionFind ( )

local function returnedAlias ( expr , resultIndex ) 
local direct = directName ( expr )
if direct then
return { direct }
end
if not expr or ( expr . kind ~= "call" and expr . kind ~= "safeCall" and expr . kind ~= "methodCall" ) then
return { }
end
local known = knownCall ( expr , byDefinition )
local args = callArgs ( expr )
local aliases = { }
if known and not known . summary . top then
local prefix = tostring ( resultIndex or 1 ) .. "="
for value in pairs ( known . summary . returns or { } ) do
if value : sub ( 1 , # prefix ) == prefix then
local root = value : sub ( # prefix + 1 ) : match ( "^([%a_][%w_]*)" )
for j , name in ipairs ( known . paramNames or { } ) do
if name == root then
local actual = directName ( args [ j ] )
if actual then
aliases [ # aliases + 1 ] = actual
end
end
end
end
end
else



for _ , arg in ipairs ( args ) do
local actual = directName ( arg )
if actual then
aliases [ # aliases + 1 ] = actual
end
end
end

return aliases
end

local function walk ( node ) 
if not node or cst . isToken ( node ) then
return
end
local kind = node . kind
if NESTED_FUNCTION [ kind ] then
return
elseif kind == "localStmt" then
for j , name in ipairs ( node . names or { } ) do
local exprs = node . exprs or { }
local expr = exprs [ j ] or ( # exprs == 1 and exprs [ 1 ] or nil )
local resultIndex = # exprs == 1 and j or 1
for _ , source in ipairs ( returnedAlias ( expr , resultIndex ) ) do
union ( name . definition , source . definition )
end
end
elseif kind == "assignStmt" then
for j , target in ipairs ( node . targets or { } ) do
local targetName = directName ( target )
local exprs = node . exprs or { }
local expr = exprs [ j ] or ( # exprs == 1 and exprs [ 1 ] or nil )
local resultIndex = # exprs == 1 and j or 1
for _ , source in ipairs ( returnedAlias ( expr , resultIndex ) ) do
if targetName then
union ( targetName . definition , source . definition )
end
end
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( body )

return find
end
























local queries = { }








function queries . visible ( summary ) 
if not summary then
return false , "the callee is not known here"
end
if summary . top then
return false , "the callee reaches code with unknown effects"
end
if summary . external then
return false , "the callee's body is foreign"
end

return true
end











function queries . free ( summary , kinds ) 
if not summary then
return false , "the callee is not known here"
end
for _ , kind in ipairs ( kinds ) do
local value = summary [ kind ]
if value == true then
return false , "the callee " .. kind
elseif type ( value ) == "table" and next ( value ) then
return false , "the callee " .. kind .. " " .. tostring ( ( next ( value ) ) )
end
end

return true
end












function queries . body ( body , byDefinition ) 
local find = aliasClasses ( body , byDefinition )
local facts = { }



function facts . aliasOf ( token ) 
return token and find ( token . definition ) or nil
end










function facts . uses ( definition , region ) 
local function count ( node ) 
if not node then
return 0
end
if cst . isToken ( node ) then
return node . kind == "name" and node . definition == definition and 1 or 0
end
local total = 0
for _ , child in ipairs ( node ) do
total = total + count ( child )
end

return total
end

return count ( region or body )
end






















function facts . calledOnly ( definition ) 
if not definition then
return false , 0
end
local callees = { }
local declared = { }

local function collect ( node ) 
if not node or cst . isToken ( node ) then
return
end
if node . kind == "call" then
local callee = directName ( node . obj )
if callee then
callees [ callee ] = true
end
elseif node . kind == "localFuncStmt" and node . name then
declared [ node . name ] = true
end
for _ , child in ipairs ( node ) do
collect ( child )
end
end

collect ( body )

local mentions = 0
local only = true

local function walk ( node ) 
if not node then
return
end
if cst . isToken ( node ) then
if node . kind == "name" and node . definition == definition and not declared [ node ] then
mentions = mentions + 1
if not callees [ node ] then
only = false
end
end

return
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( body )

return only and mentions > 0 , mentions
end
















function facts . shapeStable ( region , class , instead ) 
local stable , reason , related = true , nil , nil

local function inspect ( value ) 
if not value or cst . isToken ( value ) or not stable then
return
end
local swap = instead and instead ( value )
if swap then
inspect ( swap )
return
end
local kind = value . kind
if NESTED_FUNCTION [ kind ] then
return
end
if kind == "assignStmt" then
for _ , target in ipairs ( value . targets or { } ) do
local base = indexBase ( target )
local token = directName ( base )
if target ~= base and token and find ( token . definition ) == class then
stable , reason , related = false , "the array may change shape in the loop" , target
return
end
end
elseif kind == "compoundAssign" then
local base = indexBase ( value . target )
local token = directName ( base )
if value . target ~= base and token and find ( token . definition ) == class then
stable , reason , related = false , "the array may change shape in the loop" , value . target
return
end
elseif kind == "call" or kind == "safeCall" or kind == "methodCall" then
local known = knownCall ( value , byDefinition )
local summary = known and known . summary or nil
if not queries . visible ( summary ) or not queries . free ( summary , { "yields" , "metatables" } ) then
stable , reason , related = false , "a call in the loop may mutate or expose the array" , value
return
end
local args = callArgs ( value )
for path in pairs ( summary . shapes ) do
if path : sub ( 1 , 1 ) == "$" then
stable , reason , related = false , "a call may change a captured table's shape" , value
return
end
local root = path : match ( "^([%a_][%w_]*)" )
local index
for j , name in ipairs ( known . paramNames ) do
if name == root then
index = j ;
do break end
end
end
local actual = index and directName ( args [ index ] ) or nil
if not actual then
stable , reason , related = false , "a call may change an unresolved argument's shape" , value
return
elseif find ( actual . definition ) == class then
stable , reason , related = false , "a call may change the array's shape" , value
return
end
end
end
for _ , child in ipairs ( value ) do
inspect ( child )
end
end

inspect ( region )

return stable , reason , related
end

return facts
end








































function analysis . queries ( facts ) 
if not facts or not facts . byDefinition then
return nil
end
local bound = __nuppNew(0,2)
local prepared = { }
bound . visible = queries . visible
bound . free = queries . free








function bound . known ( token ) 
return token
and token . definition
and not token . definition . callFactsUnstable
and facts . byDefinition [ token . definition ]
or nil
end





function bound . callee ( call ) 
return knownCall ( call , facts . byDefinition )
end


function bound . body ( body ) 
if not prepared [ body ] then
prepared [ body ] = queries . body ( body , facts . byDefinition )
end
return prepared [ body ]
end

return bound
end

function analysis . run ( result , checker ) 
callfacts . reset ( result . root )
local functions , byDefinition = collectFunctions ( result . root )
for _ , info in ipairs ( functions ) do
if info . contract then
info . summary = fromContract ( info . contract )
end
end
for phase = 1 , 2 do
callfacts . run ( result . root , functions , byDefinition )
for _ = 1 , # functions + 1 do
local changed = false
for _ , info in ipairs ( functions ) do
if info . body then
local inferred = inferFunction ( info , byDefinition )
local nextSummary = info . contract and fromContract ( info . contract ) or inferred
if not same ( info . summary , nextSummary ) then
info . summary , changed = nextSummary , true
end
info . inferred = inferred
info . body . effectSummary = nextSummary
info . body . callableEffects = { summary = nextSummary , paramNames = info . paramNames }
end
end
if not changed then
do break end
end
end
end
if checker then
for _ , info in ipairs ( functions ) do
if info . body and info . contract then
local ok , why = contractContains ( info . contract , info . inferred )
if not ok then
checker . diag ( "NUPP2112" , info . node , "@effects contract " .. tostring ( why ) )
end
end
end
end



local bodies = { }
for _ , block in ipairs ( result . root . blocks or { } ) do
bodies [ # bodies + 1 ] = block
end
for _ , info in ipairs ( functions ) do
local contents = bodyContents ( info . body )
if contents then
bodies [ # bodies + 1 ] = contents
end
end
for _ , info in ipairs ( functions ) do
if info . body then
local viewBody = viewfacts . infer ( info . body )
info . body . viewBody = viewBody . nodes and viewBody or nil
local parameters = { }
for position , binding in ipairs ( viewBody . params or { } ) do
local descriptor = viewBody . definitions [ binding ]
if descriptor . view then
parameters [
# parameters + 1
] = {
position = position ,
mode = "borrowed" ,
escapes = false ,
stableCount = true ,
element = descriptor . view . element ,
alias = "unknown"
}
end
end
info . body . representation = {
version = 1 ,
parameters = parameters ,
reason = viewBody . reason ,
relationships = "callableRelations" ,
nodes = viewBody . nodes and # viewBody . nodes
}
local artifact = inlinefacts . infer ( info . body )
info . body . inlineBody = artifact . expression and artifact or nil
info . body . inlineEligibility = {
version = artifact . version ,
size = artifact . size ,
parameters = # ( artifact . params or { } ) ,
reason = artifact . reason
}
end
end
result . analysis = { functions = functions , byDefinition = byDefinition , bodies = bodies }

return result . analysis
end

analysis . summary = summary
analysis . join = join
analysis . fromContract = fromContract

local __nuppExportValue= analysis ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.analysis"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.analysis"]=__nuppExports;return __nuppExports