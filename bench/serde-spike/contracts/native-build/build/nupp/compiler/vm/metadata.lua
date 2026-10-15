_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local metadata = { }

local function node ( kind , fields ) 
local result = fields or { }
result . kind = kind
local keys , children = { } , { }
for key in pairs ( fields or { } ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys )
for _ , key in ipairs ( keys ) do
local value = fields [ key ]
if type ( value ) == "table" then
if value . kind then
children [ # children + 1 ] = value
else
for _ , child in ipairs ( value ) do
if type ( child ) == "table" and child . kind then
children [ # children + 1 ] = child
end
end
end
end
end
for _ , child in ipairs ( children ) do
result [ # result + 1 ] = child
end

return result
end

local function name ( text ) 
return node ( "name" , { token = { text = text } } )
end

local function field ( subject , member ) 
return node ( "dotIndex" , { obj = subject , name = { text = member } } )
end

local function call ( subject , arguments ) 
return node ( "call" , { obj = subject , args = node ( "args" , { exprs = arguments } ) } )
end

local function data ( value ) 
local kind = type ( value )
if kind == "nil" then
return node ( "nilExpr" )
elseif kind == "boolean" then
return node ( value and "trueExpr" or "falseExpr" )
elseif kind == "string" then
return node ( "string" , { token = { text = string . format ( "%q" , value ) } } )
elseif kind == "number" then
return node ( "number" , { token = { text = string . format ( "%.17g" , value ) } } )
end
assert ( kind == "table" , "metadata must be plain data" )
local keys = { }
for key in pairs ( value ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys , function ( a , b ) 
if type ( a ) ~= type ( b ) then
return type ( a ) < type ( b )
end
if type ( a ) == "boolean" then
return not a and b
end

return a < b
end )
local fields = { }
for _ , key in ipairs ( keys ) do
fields [ # fields + 1 ] = node ( "fieldBracket" , { key = data ( key ) , value = data ( value [ key ] ) } )
end

return node ( "tableExpr" , { fields = fields } )
end

metadata . literal = data

local function required ( module ) 
return call ( name ( "require" ) , { data ( module ) } )
end

local function invoke ( subject , arguments ) 
return node ( "callStmt" , { expr = call ( subject , arguments ) } )
end

local function assign ( target , value ) 
return node ( "assignStmt" , { targets = { target } , exprs = { value } } )
end

local function body ( parameters , statements ) 
local params = { }
for _ , parameter in ipairs ( parameters ) do
params [ # params + 1 ] = { name = { text = parameter } }
end

return node ( "funcbody" , { params = params , body = node ( "block" , { stats = statements } ) } )
end

local function path ( text ) 
local result
for member in text : gmatch ( "[^.]+" ) do
result = result and field ( result , member ) or name ( member )
end

return assert ( result , "empty metadata path" )
end

local function constructors ( declaration , identity , statements ) 
local nominal = declaration . resolvedType
for _ , entry in ipairs ( declaration . entries or { } ) do
if entry . kind == "constructorDecl" then
local index = tostring ( entry . constructorIndex or 1 )
local initializer = "__nuppInit" .. index

local writes = { node ( "localStmt" , { names = { { text = "\0constructor:self" } } , exprs = { name ( "self" ) } } ) }
for _ , member in ipairs ( nominal . fieldOrder or { } ) do
local default = nominal . fieldDefaults and nominal . fieldDefaults [ member ]
if default then
writes [ # writes + 1 ] = assign ( field ( name ( "self" ) , member ) , data ( default . value ) )
end
end
for _ , statement in ipairs ( entry . body . body . stats or { } ) do
writes [ # writes + 1 ] = statement
end
writes [ # writes + 1 ] = node ( "returnStmt" , { exprs = { name ( "\0constructor:self" ) } } )
local initBody = { }
for key , value in pairs ( entry . body ) do
if type ( key ) ~= "number" then
initBody [ key ] = value
end
end
local initBlock = { }
for key , value in pairs ( entry . body . body ) do
if type ( key ) ~= "number" then
initBlock [ key ] = value
end
end
initBlock . stats = writes
initBody . body = node ( "block" , initBlock )
initBody . vmConstructorSelf = "\0constructor:self"
statements [ # statements + 1 ] = assign (
field ( identity , initializer ) ,
node ( "funcExpr" , {
body = node ( "funcbody" , initBody )
} )
)
local parameters , arguments = { } , {
node ( "newExpr" , {
inferredType = nominal ,
call = { recordFields = { } , args = { exprs = { } } }
} )
}
for position , parameter in ipairs ( entry . body . params or { } ) do
if position > 1 then
assert ( not parameter . vararg and not parameter . namedVararg , "constructor varargs are not supported" )
parameters [ # parameters + 1 ] = parameter . name . text
arguments [ # arguments + 1 ] = name ( parameter . name . text )
end
end
statements [ # statements + 1 ] = assign (
field ( identity , "__nuppCtor" .. index ) ,
node ( "funcExpr" , {
body = body ( parameters , {
node ( "returnStmt" , {
exprs = { call ( field ( identity , initializer ) , arguments ) }
} )
} )
} )
)
end
end
end

function metadata . declaration ( declaration , identity ) 
local statements = { }
local recipe = declaration . deriveRecipe
local nominal = declaration . resolvedType
constructors ( declaration , identity , statements )
local reflect = field ( field ( name ( "_G" ) , "nupp" ) , "__reflect" )
if nominal and ( nominal . runtimeReflectionNeeded or recipe and recipe . data and recipe . data . json ) then
local reflection = require ( "nupp.compiler.reflection" )
statements [ # statements + 1 ] = invoke ( field ( required ( "nupp.compiler.runtime.reflect" ) , "install" ) , {
field ( name ( "_G" ) , "nupp" )
} )
statements [ # statements + 1 ] = invoke ( field ( reflect , "register" ) , {
identity ,
data ( reflection . describe ( nominal , nominal . runtimePath or nominal . name ) ) ,
data ( reflection . runtimeReferences ( nominal ) )
} )
end
if not recipe then
return statements
end
statements [ # statements + 1 ] = invoke ( field ( required ( "nupp.derive" ) , "install" ) , { field ( name ( "_G" ) , "nupp" ) } )
if recipe . initializer and nominal and # ( nominal . constructorEntries or { } ) == 0 then
local parameters , writes = { "self" } , { }
for _ , member in ipairs ( nominal . fieldOrder or { } ) do
local memberType = nominal . byname and nominal . byname [ member ]
if memberType
and memberType . tag ~= "typeobject"
and not ( nominal . nestedTypes and nominal . nestedTypes [ member ] )
and not ( nominal . privateFields and nominal . privateFields [ member ] )
then
local parameter = "a" .. # parameters
parameters [ # parameters + 1 ] = parameter
local value = name ( parameter )
local default = nominal . fieldDefaults and nominal . fieldDefaults [ member ]
if default then
writes [ # writes + 1 ] = node ( "ifStmt" , {
clauses = {
node ( "ifClause" , {
cond = node ( "binop" , {
op = { text = "==" } ,
lhs = value ,
rhs = data ( nil )
} ) ,
body = node ( "block" , { stats = { assign ( value , data ( default . value ) ) } } )
} )
}
} )
end
writes [ # writes + 1 ] = assign ( field ( name ( "self" ) , member ) , value )
end
end
writes [ # writes + 1 ] = node ( "returnStmt" , { exprs = { name ( "self" ) } } )
statements [ # statements + 1 ] = assign (
field ( identity , recipe . initializer ) ,
node ( "funcExpr" , {
body = body ( parameters , writes )
} )
)
end
local entryName = "\0derive:" .. recipe . key
statements [ # statements + 1 ] = node ( "localStmt" , {
names = { { text = entryName } } ,
exprs = {
call ( field ( field ( field ( name ( "_G" ) , "nupp" ) , "__derive" ) , "register" ) , {
data ( recipe . key ) ,
identity ,
data ( recipe )
} )
}
} )

local function argument ( value ) 
if value . kind == "receiver" then
return name ( "self" )
elseif value . kind == "entry" then
return name ( entryName )
elseif value . kind == "argument" then
return name ( value . name )
elseif value . kind == "field" then
return field ( name ( "self" ) , value . name )
elseif value . kind == "constant" then
return data ( value . value )
elseif value . kind == "witness" then
assert (
declaration . deriveWitnesses and declaration . deriveWitnesses [ value . witnessIndex ] ,
"missing derived type witness"
)
return path ( assert ( value . runtimePath ) )
elseif value . kind == "array" then
local fields = { }
for _ , item in ipairs ( value . values or { } ) do
fields [ # fields + 1 ] = node ( "fieldItem" , { value = argument ( item ) } )
end
return node ( "tableExpr" , { fields = fields } )
end
error ( "unknown derived argument " .. tostring ( value . kind ) )
end

for _ , member in ipairs ( recipe . members or { } ) do
assert ( member . operation == "forward.v1" , "unknown derived member operation" )
local parameters = { }
for index , parameter in ipairs ( member . paramNames or { } ) do
parameters [ index ] = member . namespace == "instance" and index == 1 and "self"
or parameter ~= "" and parameter
or ( "a" .. index )
end
local arguments = { }
for _ , item in ipairs ( member . arguments or { } ) do
arguments [ # arguments + 1 ] = argument ( item )
end
local helper = member . helper . localPath and path ( member . helper . localPath )
or field ( required ( member . helper . module ) , member . helper . member )
statements [ # statements + 1 ] = assign (
field ( identity , member . name ) ,
node ( "funcExpr" , {
body = body ( parameters , {
node ( "returnStmt" , { exprs = { call ( helper , arguments ) } } )
} )
} )
)
end

return statements
end

function metadata . expand ( root ) 
local seen = { }
local managed = false

local function replaceCall ( current , replacement ) 
for index = # current , 1 , -1 do
current [ index ] = nil
end
current . kind = replacement . kind
current . obj = replacement . obj
current . args = replacement . args
current . name = replacement . name
current . overloadMember = nil
current . ownershipIntrinsic = nil
current . recoverManagedAlias = nil
current . managedAliasPolicy = nil
for _ , child in ipairs ( replacement ) do
current [ # current + 1 ] = child
end
managed = true
end

local function visit ( current ) 
if type ( current ) ~= "table" or seen [ current ] then
return
end
seen [ current ] = true
managed = managed or current . requiresManagedRuntime == true
if current . kind == "call" and current . ownershipIntrinsic == "manage" then

local cleanup = call ( name ( "nupp" ) , { name ( "\0managed:value" ) } )
cleanup . ownershipIntrinsic = "attemptAll"
cleanup . ownerCleanups = assert ( current . managedCleanups )
local callback = node ( "funcExpr" , { body = body ( { "\0managed:value" } , { node ( "callStmt" , { expr = cleanup } ) } ) } )
replaceCall (
current ,
call ( field ( field ( name ( "_G" ) , "nupp" ) , "__manage" ) , {
assert ( current . args . exprs [ 1 ] ) ,
callback ,
data ( current . managedPolicy or "" )
} )
)
elseif current . kind == "call" and current . recoverManagedAlias then
replaceCall ( current , call ( field ( field ( name ( "_G" ) , "nupp" ) , "__recoverAlias" ) , current . args . exprs ) )
elseif current . kind == "methodCall" and current . managedAliasPolicy then
replaceCall (
current ,
node ( "methodCall" , {
obj = current . obj ,
name = { text = "_downcast" } ,
args = node ( "args" , { exprs = { data ( current . managedAliasPolicy ) } } )
} )
)
end
if current . kind == "recordDecl" and not current . vmMetadata then
local identity
for _ , qualifier in ipairs ( current . qualifiers or { } ) do
identity = identity and field ( identity , qualifier . text ) or name ( qualifier . text )
end
identity = identity and field ( identity , current . name . text ) or name ( current . name . text )
current . vmMetadata = metadata . declaration ( current , identity )
for _ , statement in ipairs ( current . vmMetadata ) do
current [ # current + 1 ] = statement
end
end
for _ , child in ipairs ( current ) do
visit ( child )
end
end

visit ( root )
if managed and not root . vmManagedRuntime then
local namespace = field ( name ( "_G" ) , "nupp" )
local install = invoke ( field ( required ( "nupp.runtime.managed" ) , "install" ) , { namespace , name ( "_G" ) } )
local block = root . blocks [ 1 ]
table . insert ( block . stats , 1 , install )
block [ # block + 1 ] = install
root . vmManagedRuntime = true
end
end

local __nuppExportValue= metadata ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.vm.metadata"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.vm.metadata"]=__nuppExports;return __nuppExports