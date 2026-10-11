_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local cst = require ( "nupp.compiler.syntax.cst" )
local types = require ( "nupp.compiler.types" )

local typewitness = { }



function typewitness . collect ( root , exports ) 
local values , declarations , blocks , wanted = { } , { } , { } , { }
local moduleBlocks = { }
for _ , block in ipairs ( root . blocks or { } ) do
moduleBlocks [ block ] = true
end

local function origin ( t ) 
t = types . unwrapOwnership ( t )
if t . tag == "nominal" then
return t . origin or t
end

return t
end

local function erased ( node ) 
return node . comptimeFunction
or node . comptimeTok
or node . comptimeValue ~= nil
or node . materializedIR ~= nil
or node . folded ~= nil
or node . isAnnotationDefinition
or false
end

local function inventory ( node , block , depth ) 
if not node or cst . isToken ( node ) or erased ( node ) then
return
end
if node . kind == "block" then
block = node
end
if cst . FUNCTION_DECLARATIONS [ node . kind ] then
depth = depth + 1
end
if node . kind == "recordDecl" and ( node . declKind == "record" or node . declKind == "struct" ) then
local t = node . resolvedType or node . hoistedType
if t then
declarations [
origin ( t )
] = { node = node , block = block , top = depth == 0 and moduleBlocks [ block ] == true , type = t }
end
end
for _ , child in ipairs ( node ) do
inventory ( child , block , depth )
end
end

inventory ( root , nil , 0 )

local seen = { }
local mark
mark = function ( t ) 
if not t or seen [ t ] then
return
end
seen [ t ] = true
local tag = t . tag
if tag == "affine" or tag == "borrowed" or tag == "const" or tag == "pinned" then
mark ( t . inner )
elseif tag == "typeobject" or tag == "ctype" then
mark ( t . of )
elseif tag == "nominal" then
local declared = declarations [ origin ( t ) ]
if declared then
wanted [ declared . node ] = declared
end
for _ , name in ipairs ( t . fieldOrder or { } ) do
mark ( t . byname and t . byname [ name ] )
end
for _ , nested in pairs ( t . nestedTypes or { } ) do
mark ( nested )
end
for _ , entry in ipairs ( t . constructorEntries or { } ) do
for _ , parameter in ipairs ( entry . signature . params or { } ) do
mark ( parameter )
end
end
elseif tag == "array" or tag == "carray" or tag == "ptr" then
mark ( t . elem )
elseif tag == "map" then
mark ( t . key )
mark ( t . value )
elseif tag == "tuple" then
for _ , child in ipairs ( t . elems or { } ) do
mark ( child )
end
elseif tag == "union" or tag == "intersection" then
for _ , child in ipairs ( t . members or { } ) do
mark ( child )
end
elseif tag == "shape" then
for _ , field in ipairs ( t . fields or { } ) do
mark ( field . read )
end
end
end

local published = { }

local function exportedTypes ( t ) 
if not t or published [ t ] then
return
end
published [ t ] = true
t = types . unwrapOwnership ( t )
if t . tag == "typeobject" or t . tag == "ctype" then
mark ( t . of )
elseif t . tag == "shape" then
for _ , field in ipairs ( t . fields or { } ) do
exportedTypes ( field . read )
end
elseif t . tag == "union" then
for _ , member in ipairs ( t . members ) do
exportedTypes ( member )
end
end
end

for _ , t in pairs ( exports and exports . values or { } ) do
exportedTypes ( t )
end

local identityOnly = { }

local function identity ( node ) 
if not node then
return
end
identityOnly [ node ] = true
if node . kind == "paren" or node . kind == "castExpr" then
identity ( node . expr )
end
end

local function visit ( node , parent , depth , exported ) 
if not node or cst . isToken ( node ) or erased ( node ) then
return
end
if node . foldedExpression then
visit ( node . foldedExpression , parent , depth , exported )
return
end
local kind = node . kind
if kind == "binop" and node . op and ( node . op . kind == "==" or node . op . kind == "~=" ) then
identity ( node . lhs )
identity ( node . rhs )
elseif kind == "castExpr" and node . inferredType then
local castType = types . unwrapOwnership ( node . inferredType )
if castType . tag ~= "typeobject" and castType . tag ~= "ctype" then
identity ( node . expr )
end
elseif kind == "localStmt" or kind == "assignStmt" then
for index , value in ipairs ( node . exprs or { } ) do
local annotation = kind == "localStmt" and node . types and node . types [ index ]
local target = annotation and annotation . resolvedType
or kind == "assignStmt" and node . targets [ index ] and node . targets [ index ] . inferredType
local actual = value . inferredType and types . unwrapOwnership ( value . inferredType )
target = target and types . unwrapOwnership ( target )
if actual
and ( actual . tag == "typeobject" or actual . tag == "ctype" )
and types . unwrapOwnership ( actual . of ) . tag == "nominal"
then



if not target
or target . tag == "any"
or target . tag == "unknown"
or target . tag == actual . tag and target . of == actual . of
then
identity ( value )
end
elseif target and target . tag == "metatable" and value . kind == "tableExpr" then
for _ , field in ipairs ( value . fields or { } ) do
identity ( field . value )
end
end
end
elseif kind == "call" then
if node . carrayElem then
identity ( node . carrayElem )
end
if node . soaOperation and node . soaLayout and node . args then
identity ( node . args . exprs [ 1 ] )
end
end
local inner = depth
if cst . FUNCTION_DECLARATIONS [ kind ] then
inner = depth + 1
end
local publishing = exported or depth == 0 and ( kind == "exportStmt" and not node . stat or kind == "returnStmt" )
if cst . FUNCTION_DECLARATIONS [ kind ] or kind == "args" then
publishing = false
end
local t = node . inferredType and types . unwrapOwnership ( node . inferredType )
if node . exported and node . kind == "recordDecl" then
mark ( node . resolvedType or node . hoistedType )
end
for _ , subject in ipairs ( node . deriveWitnesses or { } ) do
mark ( subject )
end
local static = parent
and parent . obj == node
and (
parent . kind == "dotIndex"
or parent . kind == "bracketIndex"
or parent . kind == "call"
and ( parent . recordConstruct or parent . structConstruct or parent . constructorCall )
)
if publishing and t and not static and not identityOnly [ node ] then
exportedTypes ( t )
end
local namespace = node . requiredModule and not ( parent and parent . kind == "args" )
if t
and ( t . tag == "typeobject" or t . tag == "ctype" )
and not static
and not publishing
and not namespace
and not identityOnly [ node ]
then
local target = types . unwrapOwnership ( t . of )
if target . tag == "nominal" and ( target . declKind == "record" or target . declKind == "struct" ) then
values [ node ] = target
mark ( target )
end
end
for _ , child in ipairs ( node ) do
visit ( child , node , inner , publishing )
end
end

visit ( root , nil , 0 , false )




local ordered = { }

local function arrange ( node ) 
if not node or cst . isToken ( node ) or erased ( node ) then
return
end
local item = wanted [ node ]
if item then
local group = blocks [ item . block ]
if not group then
group = { items = { } }
blocks [ item . block ] = group
end
group . items [ # group . items + 1 ] = item
item . slot = # group . items
item . group = group
ordered [ # ordered + 1 ] = item
end
for _ , child in ipairs ( node ) do
arrange ( child )
end
end

arrange ( root )
for _ , item in ipairs ( ordered ) do
item . targets = { }
local found = { }
local link
link = function ( t ) 
if not t or found [ t ] then
return
end
found [ t ] = true
local tag = t . tag
if tag == "nominal" then
local source = origin ( t )
local declaration = declarations [ source ]
local key = source . runtimeDeclarationKey or source . declarationKey
if key and declaration and wanted [ declaration . node ] then
item . targets [ # item . targets + 1 ] = { key = key , localTarget = declaration }
elseif key and source . moduleName then
item . targets [ # item . targets + 1 ] = { key = key , module = source . moduleName }
end
elseif tag == "affine" or tag == "borrowed" or tag == "const" or tag == "pinned" then
link ( t . inner )
elseif tag == "array" or tag == "carray" or tag == "ptr" then
link ( t . elem )
elseif tag == "map" then
link ( t . key )
link ( t . value )
elseif tag == "tuple" then
for _ , child in ipairs ( t . elems or { } ) do
link ( child )
end
elseif tag == "union" or tag == "intersection" then
for _ , child in ipairs ( t . members or { } ) do
link ( child )
end
elseif tag == "shape" then
for _ , field in ipairs ( t . fields or { } ) do
link ( field . read )
end
end
end
for _ , name in ipairs ( item . type . fieldOrder or { } ) do
link ( item . type . byname and item . type . byname [ name ] )
end
for _ , entry in ipairs ( item . type . constructorEntries or { } ) do
for _ , parameter in ipairs ( entry . signature . params or { } ) do
link ( parameter )
end
end
end

return { values = values , declarations = wanted , blocks = blocks , ordered = ordered }
end

local __nuppExportValue= typewitness ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.lua.typewitness"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.lua.typewitness"]=__nuppExports;return __nuppExports