_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






















local cst = require ( "nupp.compiler.cst" )

local analysis = { }









local LISTS = { "reads" , "writes" , "shapes" , "metatables" , "escapes" , "calls" }
local FLAGS = { "allocates" , "yields" , "raises" , "external" }

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
yields = false ,
raises = false ,
external = false ,
top = false ,
}
end

local function unknownSummary ( )
local out = summary ( )
out . top = true
return out
end

local function fromContract ( contract )
local out = summary ( )
for _ , name in ipairs ( LISTS ) do
out [ name ] = setOf ( contract [ name ] )
end
for _ , value in ipairs ( contract . returns or { } ) do
out . returns [ value ] = true
end
for _ , name in ipairs ( FLAGS ) do
out [ name ] = contract [ name ] == true
end

return out
end

local function copy ( value )
local out = summary ( )
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
local selected = call and ( call . constructorEntry or call . methodEntry ) or nil
local declaration = selected and selected . declaration or nil
if declaration and declaration . effectInfo then
return declaration . effectInfo
end
local callee = call and call . obj
local token = callee and ( callee . token or callee . name )

return token and byDefinition [ token . definition ] or nil
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
local function walk ( node )
if not node or cst . isToken ( node ) then
return
end
local target = unwrap ( node )
local kind = target and target . kind




if kind == "funcExpr" or kind == "shortfn" then
local body = target . body
if body then
local info = {
node = target ,
body = body ,
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
if body . body then
walk ( body . body )
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
summary = target . effectContract and fromContract ( target . effectContract ) or summary ( ) ,
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
local out = summary ( )
local parent , localDefinitions = { } , { }
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
elseif kind == "funcStmt"
or kind == "inlineMethod"
or kind == "constructorDecl"
or kind == "funcExpr"
or kind == "shortfn"
then
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

collectBindings ( info . body and info . body . body )
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
break
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

local function applyCall ( call )
if call . scalarIntrinsic then


return
end
if call . spanAccessorNoAllocate then



if not call . rangeProvenNoRaise then
out . raises = true
end
local receiver = rootOf ( call . obj )
if receiver then
local method = call . name and call . name . text or ""
if method == "set" or method == "getMut" then
out . writes [ receiver .. "[*]" ] = true
else
out . reads [ receiver .. "[*]" ] = true
end
end
return
end
local known = knownCall ( call , byDefinition )
local args = callArgs ( call )
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
if effects [ flag ] then
out [ flag ] = true
end
end
return
end
local name = callName ( call )
if PURE_BUILTINS [ name or "" ] then
local root = rootOf ( args [ 1 ] )
if root then
out . reads [ root .. "[*]" ] = true
end
elseif name == "error" or name == "assert" then
out . raises = true
elseif name == "coroutine.yield" then
out . yields = true
else
out . top = true
end
end

local function returnedRoots ( expr )
local direct = rootOf ( expr )
if direct then
return { [ 1 ] = direct }
end
if not expr or ( expr . kind ~= "call" and expr . kind ~= "methodCall" ) then
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
if kind == "localFuncStmt"
or kind == "funcStmt"
or kind == "inlineMethod"
or kind == "constructorDecl"
or kind == "funcExpr"
or kind == "shortfn"
then
out . allocates = true
return
elseif kind == "tableExpr" then
out . allocates = true
elseif kind == "newExpr" then
out . allocates = true
elseif kind == "istring" then
out . allocates = true
if # ( node . parts or { } ) > 0 then

out . top = true
end
elseif kind == "binop" and node . op and node . op . kind == ".." then
out . allocates = true
if not node . plainConcat then
out . top = true
end
elseif node . effectUnknownOperation then
out . top = true
elseif kind == "call" or kind == "methodCall" then
applyCall ( node )
elseif kind == "name" and not targetContext then
local root = node . token and rooted [ find ( node . token . definition ) ]
if root then
out . reads [ root ] = true
end
elseif kind == "assignStmt" then
for _ , target in ipairs ( node . targets or { } ) do
local base = target
while base and (
base . kind == "dotIndex"
or base . kind == "bracketIndex"
or base . kind == "safeIndex"
or base . kind == "safeBracket"
) do
base = base . obj
end
local token = directName ( base )
local root = token and rooted [ find ( token . definition ) ]
if root and target ~= base then
out . writes [ root .. "[*]" ] = true
out . shapes [ root ] = true
elseif target ~= base and token and not localDefinitions [ token . definition ] then
out . writes [ "$capture[*]" ] = true
out . shapes [ "$capture" ] = true
end
walk ( target , true )
end
for j , expr in ipairs ( node . exprs or { } ) do
local escaped = rootOf ( expr )
local target = node . targets and node . targets [ j ]
local targetName = directName ( target )
if escaped and target and (
( targetName and not localDefinitions [ targetName . definition ] ) or not targetName
) then
out . escapes [ escaped ] = true
end
walk ( expr , false )
end
return
elseif kind == "compoundAssign" then
local base = node . target
while base and ( base . kind == "dotIndex" or base . kind == "bracketIndex" ) do
base = base . obj
end
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
walk ( info . body and info . body . body , false )



local function cleanupEffects ( node )
if not node or cst . isToken ( node ) then
return
end
if node ~= info . body and (
node . kind == "localFuncStmt"
or node . kind == "funcStmt"
or node . kind == "inlineMethod"
or node . kind == "constructorDecl"
or node . kind == "funcExpr"
or node . kind == "shortfn"
) then
return
end
for _ , owner in ipairs ( node . automaticOwners or { } ) do
for _ , cleanup in ipairs ( owner . cleanups or { } ) do
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
if known . summary . raises then
out . raises = true
end
if known . summary . yields then
out . yields = true
end
end
end
end
for _ , child in ipairs ( node ) do
cleanupEffects ( child )
end
end

cleanupEffects ( info . body and info . body . body )

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
return false , ( "is missing %s = %q" ) : format ( list , path )
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

local function returnedAlias ( expr , resultIndex )
local direct = directName ( expr )
if direct then
return { direct }
end
if not expr or ( expr . kind ~= "call" and expr . kind ~= "methodCall" ) then
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
if kind == "localFuncStmt"
or kind == "funcStmt"
or kind == "inlineMethod"
or kind == "constructorDecl"
or kind == "funcExpr"
or kind == "shortfn"
then
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



local NESTED_FUNCTION = {
localFuncStmt = true ,
funcStmt = true ,
inlineMethod = true ,
constructorDecl = true ,
funcExpr = true ,
shortfn = true ,
}









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
local base = target
while base and ( base . kind == "dotIndex" or base . kind == "bracketIndex" ) do
base = base . obj
end
local token = directName ( base )
if target ~= base and token and find ( token . definition ) == class then
stable , reason , related = false , "the array may change shape in the loop" , target
return
end
end
elseif kind == "compoundAssign" then
local base = value . target
while base and ( base . kind == "dotIndex" or base . kind == "bracketIndex" ) do
base = base . obj
end
local token = directName ( base )
if value . target ~= base and token and find ( token . definition ) == class then
stable , reason , related = false , "the array may change shape in the loop" , value . target
return
end
elseif kind == "call" or kind == "methodCall" then
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
break
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
local bound = { }
local prepared = { }
bound . visible = queries . visible
bound . free = queries . free




local byName = { }
for _ , info in ipairs ( facts . functions or { } ) do
local token = info . node and ( info . node . name or info . node . token ) or nil
local text = token and ( token . text or token . name and token . name . text ) or nil
if type ( text ) == "string" and byName [ text ] == nil then
byName [ text ] = info
end
end





function bound . named ( name )
return type ( name ) == "string" and byName [ name ] or nil
end








function bound . known ( token )
return token and token . definition and facts . byDefinition [ token . definition ] or nil
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
local functions , byDefinition = collectFunctions ( result . root )
for _ , info in ipairs ( functions ) do
if info . contract then
info . summary = fromContract ( info . contract )
end
end
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
end
end
if not changed then
break
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
if info . body and info . body . body then
bodies [ # bodies + 1 ] = info . body . body
end
end
result . analysis = { functions = functions , byDefinition = byDefinition , bodies = bodies }

return result . analysis
end

analysis . summary = summary
analysis . join = join
analysis . fromContract = fromContract

return analysis
