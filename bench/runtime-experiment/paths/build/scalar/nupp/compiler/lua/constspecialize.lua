_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local cst = require ( "nupp.compiler.syntax.cst" )
local hash = require ( "nupp.compiler.hash" )
local types = require ( "nupp.compiler.types" )

local constspecialize = { }

constspecialize . maxBodiesPerModule = 8

local function walk ( node , visit ) 
if node == nil or cst . isToken ( node ) then
return
end
visit ( node )
for _ , child in ipairs ( node ) do
walk ( child , visit )
end
end

local function scalarLiteral ( t ) 
if t == nil or t . tag ~= "literal" or t . base == nil then
return nil , nil , nil
end
local domain = t . base . tag
if domain == "integer" then



local value = string . format ( "%.0f" , t . constant )
return "integer:" .. value , value , t . constant
elseif domain == "boolean" then
local value = t . constant == true
return "boolean:" .. tostring ( value ) , tostring ( value ) , value
elseif domain == "string" then
local value = tostring ( t . constant )
return "string:" .. tostring ( # value ) .. ":" .. value , string . format ( "%q" , value ) , value
end

return nil , nil , nil
end

local function candidate ( node , filename ) 
if node . kind ~= "localFuncStmt" or node . name == nil or node . body == nil or node . body . generics == nil then
return nil
end
local clause = node . body . generics
if # clause . names == 0 then
return nil
end
local binders = { }
local byName = { }
for position , token in ipairs ( clause . names ) do
if clause . consts [ position ] ~= true then
return nil
end
local domain = clause . domains [ position ] and clause . domains [ position ] . text or ""
if domain ~= "integer" and domain ~= "boolean" and domain ~= "string" then
return nil
end
local binder = { name = token . text , domain = domain , carriers = { } }
binders [ # binders + 1 ] = binder
byName [ token . text ] = binder
end
for position , raw in ipairs ( node . body . params or { } ) do
local param = raw
local annotation = param . type
local binder = annotation ~= nil
and annotation . kind == "tname"
and annotation . typeArgs == nil
and annotation . base ~= nil
and byName [ annotation . base . text ]
or nil
if binder ~= nil and param . name ~= nil then
binder . carriers [
# binder . carriers + 1
] = { position = position , name = param . name . text , definition = param . name . definition , }
end
end
for _ , binder in ipairs ( binders ) do
if # binder . carriers == 0 then
return nil
end
end
walk ( node . body , function ( part ) 
if part . kind == "name" and part . token ~= nil then
for _ , binder in ipairs ( binders ) do
for _ , carrier in ipairs ( binder . carriers ) do
if part . token . definition == carrier . definition then
binder . used = true
end
end
end
end
end )



local definition = node . name . definition
local stableIdentity = filename .. "\0" .. node . name . text

return {
declaration = node ,
definition = definition ,
identity = stableIdentity ,
filename = filename ,
name = node . name . text ,
requiredAot = node . body . aotRequired == true ,
binders = binders ,
specializations = { } ,
byKey = { } ,
}
end

local function definitionKey ( definition ) 
if definition == nil or definition . filename == nil then
return nil
end

return tostring (
definition . filename
) .. "\0" .. tostring (
definition . name or definition . token and definition . token . text or ""
) .. "\0" .. tostring ( definition . kind or "variable" )
end

local function looseDefinitionKey ( definition ) 
if definition == nil or definition . filename == nil then
return nil
end

return tostring (
definition . filename
) .. "\0" .. tostring ( definition . name or definition . token and definition . token . text or "" )
end

local function byKey ( a , b ) 
return a . key < b . key
end

local function byPriority ( a , b ) 
if a . requiredAot ~= b . requiredAot then
return a . requiredAot == true
end

return a . key < b . key
end




function constspecialize . collect ( result , filename ) 
filename = filename or "<source>"
local candidates , plans = { } , { }
constspecialize . collectCandidates ( result , filename , candidates , plans )
constspecialize . collectCalls ( result , filename , candidates )

constspecialize . sort ( plans )

return plans
end

function constspecialize . collectCandidates (
result ,
filename ,
candidates ,
plans ,
moduleName
) 
walk ( result . root , function ( node ) 
local found = candidate ( node , filename )
if found ~= nil and found . definition ~= nil then
candidates [ found . definition ] = found
local stable = definitionKey ( found . definition )
if stable ~= nil then
candidates [ stable ] = found
end
local loose = looseDefinitionKey ( found . definition )
if loose ~= nil then
candidates [ loose ] = found
end
plans [ # plans + 1 ] = found
end
end )


walk ( result . root , function ( node ) 
if node . kind == "localStmt" and node . isConst then
for position , name in ipairs ( node . names or { } ) do
local value = ( node . exprs or { } ) [ position ]
local token = value ~= nil and value . kind == "name" and value . token or nil
local found = token ~= nil and candidates [ token . definition ] or nil
if found ~= nil and name . definition ~= nil then
candidates [ name . definition ] = found
end
end
end
end )
if moduleName ~= nil and result . moduleExports ~= nil then
for member , definition in pairs ( result . moduleExports . valueDefs or { } ) do
local found = candidates [ definition ]
if found ~= nil then
candidates [ "export\0" .. moduleName .. "." .. member ] = found
end
end
end
if moduleName ~= nil then
local assignment = cst . exportAssignment ( result . root )
local returned = assignment ~= nil and assignment . value or nil
if returned == nil then
for _ , block in ipairs ( result . root . blocks or { } ) do
if block . kind == "block" then
for _ , statement in ipairs ( block . stats or { } ) do
if statement . kind == "returnStmt" and # ( statement . exprs or { } ) == 1 then
returned = statement . exprs [ 1 ]
end
end
end
end
end
if returned ~= nil and returned . kind == "tableExpr" then
for _ , field in ipairs ( returned . fields or { } ) do
local value = field . kind == "fieldNamed" and field . value or nil
local token = value ~= nil and value . kind == "name" and value . token or nil
local found = token ~= nil and candidates [ token . definition ] or nil
if found ~= nil and field . name ~= nil then
candidates [ "export\0" .. moduleName .. "." .. field . name . text ] = found
end
end
end
end
end

function constspecialize . collectCalls ( result , filename , candidates ) 
walk ( result . root , function ( node ) 
if node . kind ~= "call" or node . obj == nil then
return
end
local callee = node . obj . kind == "name" and node . obj . token
or node . obj . kind == "dotIndex" and node . obj . name
or nil
if callee == nil then
return
end
local stableDefinition = definitionKey ( callee . definition )
local looseDefinition = looseDefinitionKey ( callee . definition )
local exact = node . obj . exactCallExport or callee . definition and callee . definition . exactCallExport
local exportIdentity = exact ~= nil and exact . identity or nil
local owner = candidates [ callee . definition ]
or stableDefinition ~= nil and candidates [ stableDefinition ]
or looseDefinition ~= nil and candidates [ looseDefinition ]
or exportIdentity ~= nil and candidates [ "export\0" .. exportIdentity ]
or nil
local signature = node . signatureType
if owner == nil or signature == nil or signature . tag ~= "func" then
return
end
local tuple , bodyTuple , substitutions , omitted , values = { } , { } , { } , { } , { }
for _ , binder in ipairs ( owner . binders ) do
local binderKey = nil
for _ , carrier in ipairs ( binder . carriers ) do
local key , emitted , value = scalarLiteral ( signature . params [ carrier . position ] )
if key == nil or emitted == nil or binderKey ~= nil and binderKey ~= key then
return
end
binderKey = key
substitutions [ carrier . definition ] = emitted
omitted [ carrier . position ] = true
values [ carrier . position ] = value
end
tuple [ # tuple + 1 ] = binder . domain .. ":" .. binder . name .. "=" .. ( binderKey )
if binder . used then
bodyTuple [ # bodyTuple + 1 ] = binder . domain .. ":" .. binder . name .. "=" .. ( binderKey )
end
end
local signatureFingerprint = types . tostring ( signature )
local abi = { }
for position , parameter in ipairs ( signature . params ) do
if not omitted [ position ] then
abi [ # abi + 1 ] = tostring ( signature . paramModes [ position ] or "plain" ) .. ":" .. types . tostring ( parameter )
end
end
abi [ # abi + 1 ] = "returns"
for _ , resultType in ipairs ( signature . rets ) do
abi [ # abi + 1 ] = types . tostring ( resultType )
end
local canonical = owner . identity .. "\0" .. signatureFingerprint .. "\0" .. table . concat ( tuple , "\0" )
local key = hash . digest ( canonical )
local specialization = owner . byKey [ key ]
if specialization == nil then
specialization = {
key = key ,
canonical = canonical ,
name = "__nuppConst_" .. owner . name : gsub ( "[^%w_]" , "_" ) .. "_" .. key : sub ( 1 , 16 ) ,
signature = signature ,
tuple = tuple ,
substitutions = substitutions ,
omitted = omitted ,
values = values ,
bodyClass = hash . digest (
owner . identity .. "\0" .. table . concat ( abi , "\0" ) .. "\0" .. table . concat ( bodyTuple , "\0" )
) ,
calls = { } ,
owner = owner ,
requiredAot = owner . requiredAot ,
}
owner . byKey [ key ] = specialization
owner . specializations [ # owner . specializations + 1 ] = specialization
end
specialization . calls [ # specialization . calls + 1 ] = node
specialization . callFiles = specialization . callFiles or { }
specialization . callFiles [ node ] = filename
end )
end

function constspecialize . sort ( plans ) 
for _ , plan in ipairs ( plans ) do
table . sort ( plan . specializations , byKey )
end
table . sort ( plans , function ( a , b ) 
if a . identity ~= b . identity then
return a . identity < b . identity
end
return a . name < b . name
end )
end


function constspecialize . collectGraph ( checked ) 
local candidates , plans = { } , { }
for _ , module in ipairs ( checked ) do
constspecialize . collectCandidates ( module . result , module . filename , candidates , plans , module . module )
end
for _ , module in ipairs ( checked ) do
constspecialize . collectCalls ( module . result , module . filename , candidates )
end
constspecialize . sort ( plans )

return plans
end




local function selectBodies ( bodies , maximum , accepted , declined ) 
table . sort ( bodies , byPriority )
local classes = { }
local classCount = 0
for _ , specialization in ipairs ( bodies ) do
local representative = classes [ specialization . bodyClass ]
if representative ~= nil then
specialization . physical = representative
specialization . selected = true
accepted [ # accepted + 1 ] = specialization
elseif classCount < maximum then
classCount = classCount + 1
classes [ specialization . bodyClass ] = specialization
specialization . physical = specialization
specialization . selected = true
accepted [ # accepted + 1 ] = specialization
else
specialization . selected = false
declined [ # declined + 1 ] = specialization
end
end
end



function constspecialize . select ( plans , maximum ) 
maximum = maximum or constspecialize . maxBodiesPerModule
local all = { }
for _ , plan in ipairs ( plans ) do
for _ , specialization in ipairs ( plan . specializations ) do
all [ # all + 1 ] = specialization
end
end
local accepted , declined = { } , { }
selectBodies ( all , maximum , accepted , declined )

return accepted , declined
end

function constspecialize . selectGraph ( plans , maximum ) 
maximum = maximum or constspecialize . maxBodiesPerModule
local modules = { }
for _ , plan in ipairs ( plans ) do
local bodies = modules [ plan . filename ]
if bodies == nil then
bodies = { }
modules [ plan . filename ] = bodies
end
for _ , specialization in ipairs ( plan . specializations ) do
bodies [ # bodies + 1 ] = specialization
end
end
local accepted , declined = { } , { }
for _ , bodies in pairs ( modules ) do
selectBodies ( bodies , maximum , accepted , declined )
end
table . sort ( accepted , byKey )
table . sort ( declined , byKey )

return accepted , declined
end

local __nuppExportValue= constspecialize ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.lua.constspecialize"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.lua.constspecialize"]=__nuppExports;return __nuppExports