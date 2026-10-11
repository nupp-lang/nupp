_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local reducerContracts = require ( "nupp.compiler.aot.reducers" )



































local T = require ( "nupp.compiler.types" )
local cst = require ( "nupp.compiler.syntax.cst" )
local state = require ( "nupp.compiler.check.state" )

local aot = { }










local DECLINED

= {
funcExpr = "a nested function" ,
shortfn = "a nested function" ,
funcStmt = "a nested function" ,
localFuncStmt = "a nested function" ,
vararg = "varargs" ,
gotoStmt = "`goto`" ,
labelStmt = "a label" ,
istring = "an interpolated string" ,
safeCall = "an optional call" ,
safeIndex = "an optional index" ,
safeBracket = "an optional index" ,
newExpr = "a constructor call" ,
withStmt = "an owned scope" ,
unsafe = "an `@unsafe` construct" ,
}




local BECAUSE

= {
funcExpr = "an AOT body has no closure, upvalue, or dynamic call" ,
shortfn = "an AOT body has no closure, upvalue, or dynamic call" ,
funcStmt = "an AOT body has no closure, upvalue, or dynamic call" ,
localFuncStmt = "an AOT body has no closure, upvalue, or dynamic call" ,
vararg = "an AOT function has a fixed admitted signature" ,
gotoStmt = "AOT IR source maps do not yet model arbitrary jumps" ,
labelStmt = "AOT IR source maps do not yet model arbitrary jumps" ,
istring = "interpolated construction is not admitted; use explicit string concatenation" ,
safeCall = "an AOT call must resolve statically" ,
safeIndex = "an AOT body indexes only spans, structs, and fixed arrays" ,
safeBracket = "an AOT body indexes only spans, structs, and fixed arrays" ,
newExpr = "an AOT body creates no owner and allocates nothing" ,
withStmt = "an AOT function creates no owner and has no cleanup region" ,
unsafe = "`@aot` is a checked contract and does not admit unsafe operations" ,
}





function aot . install ( c ) 
local ops = { }


local function decline ( node , kind ) 
local at = cst . firstToken ( node ) or node
c . diag ( "NUPP2903" , at , ("%s has no AOT IR representation; %s") : format ( DECLINED [ kind ] , BECAUSE [ kind ] ) )
end




function ops . body ( node ) 
if node == nil or cst . isToken ( node ) then
return
end
local body = ( node ) . body

local function exactCall ( current ) 
local callee = current . obj
local exact = callee ~= nil and ( callee ) . exactCallExport or nil
if exact == nil and callee ~= nil and callee . kind == "dotIndex" then
local indexed = callee
local base = indexed . obj
local baseExact = base ~= nil and ( base ) . exactCallExport or nil
if baseExact ~= nil and indexed . name ~= nil then
exact = { identity = baseExact . identity .. "." .. indexed . name . text , }
end
local token = base ~= nil and base . kind == "name" and ( base ) . token or nil
local definition = token ~= nil and ( token ) . definition or nil
local moduleName = definition ~= nil and definition . requiredModule or nil
if exact == nil and moduleName ~= nil and indexed . name ~= nil then
exact = { identity = moduleName .. "." .. indexed . name . text , }
end
end
if exact == nil and callee ~= nil and callee . kind == "name" then
local token = ( callee ) . token
local definition = token ~= nil and ( token ) . definition or nil
exact = definition ~= nil and definition . exactCallExport or nil
end

return exact
end


local function localIdentity ( current ) 
if current == nil or current . kind ~= "name" then
return nil
end
local token = ( current ) . token

return token ~= nil and ( ( token ) . definition or token ) or nil
end




local function reducers ( ) 
local states = { }
local ordered = { }
local nextRegion = 0


local doRegions = { }

local function constructor ( current ) 
if current == nil or current . kind ~= "call" then
return nil , nil , nil
end
local exact = exactCall ( current )
local identity = exact ~= nil and exact . identity or nil
local order
local operation
if identity ~= nil then
local contract = reducerContracts . CONSTRUCTORS [ identity ]
if contract ~= nil then
return contract . order , "add" , contract . operation == "dot" and 2 or 1
end
order , operation = identity : match ( "^nupp%.simd%.reducer%.(%a+)(%u%l+)$" )
end
if order ~= "ordered" and order ~= "pairwise" and order ~= "algebraic" and order ~= "compensated" then
return nil , nil , nil
end
if operation ~= "Sum" and operation ~= "Product" and operation ~= "Dot" then
return nil , nil , nil
end

return order , "add" , operation == "Dot" and 2 or 1
end

local function diagnose ( current , message ) 
c . diag ( "NUPP2904" , cst . firstToken ( current ) or current , message )
end

local function use ( call , region ) 
local identity = localIdentity ( call . obj )
local state_ = identity ~= nil and states [ identity ] or nil
if state_ == nil or call . name == nil then
return
end
local method = call . name . text
local arguments = call . args ~= nil and ( ( call . args ) . exprs or { } ) or { }
if method == state_ . contribution and # arguments == state_ . arity + 1 then



if region == nil or not doRegions [ region ] then
diagnose ( call , "a masked reducer contribution belongs inside a do block, which is its region" )
return
end
if state_ . region ~= nil and state_ . region ~= region then
diagnose ( call , "a reducer is scoped to exactly one region" )
else
state_ . region = region
end
elseif method == state_ . contribution then



state_ . contributed = true
elseif method == "value" then
if region ~= nil then
diagnose ( call , "a reducer is finalized after its contribution region" )
elseif state_ . region == nil and not state_ . contributed then
diagnose ( call , "a reducer must receive its contribution before it is finalized" )
elseif state_ . finalized then
diagnose ( call , "a reducer is finalized exactly once" )
else
state_ . finalized = true
end
end
end

local scan
scan = function ( current , region ) 
if current == nil or cst . isToken ( current ) then
return
end
local kind = current . kind
if kind == "localFuncStmt"
or kind == "funcStmt"
or kind == "inlineMethod"
or kind == "constructorDecl"
or kind == "funcExpr"
or kind == "shortfn"
then
return
elseif kind == "doStmt" or kind == "forinStmt" then


nextRegion = nextRegion + 1
local nestedRegion = nextRegion
doRegions [ nestedRegion ] = true
for _ , child in ipairs ( current ) do
scan ( child , nestedRegion )
end
return
end
if kind == "localStmt" then
local local_ = current
local names , expressions = local_ . names or { } , local_ . exprs or { }
if # names == 1 and # expressions == 1 then
local order , contribution , arity = constructor ( expressions [ 1 ] )
if order ~= nil then
local identity = ( names [ 1 ] ) . definition or names [ 1 ]
local state_ = {
identity = identity ,
source = names [ 1 ] ,
contribution = contribution ,
arity = arity ,
contributed = false ,
finalized = false ,
}
states [ identity ] = state_
ordered [ # ordered + 1 ] = state_
else
local copied = localIdentity ( expressions [ 1 ] )
if copied ~= nil and states [ copied ] ~= nil then
diagnose ( current , "a reducer cannot be copied or passed through another value" )
end
end
end
elseif kind == "methodCall" then
use ( current , region )
end
for _ , child in ipairs ( current ) do
scan ( child , region )
end
end

for _ , statement in ipairs ( body and body . stats or { } ) do
scan ( statement , nil )
end

for _ , state_ in ipairs ( ordered ) do
if state_ . region == nil and not state_ . contributed then
diagnose ( state_ . source , "a reducer must receive a contribution before finalization" )
elseif not state_ . finalized then
diagnose ( state_ . source , "a reducer is finalized exactly once after its contribution region" )
end
end
end

local walk
walk = function ( current , inWorkgroup ) 
if current == nil or cst . isToken ( current ) then
return
end
local kind = ( current ) . kind
if current . expressionAnnotations or ( kind == "pragmaStmt" and current . name . text == "unsafe" ) then
decline ( current , "unsafe" )
return
end
if kind == "call" then
local call = current
local callee = call . obj
local exact = exactCall ( call )
if exact ~= nil and exact . identity == "nupp.gpu.workgroups" then
walk ( callee , false )
local args = call . args ~= nil and ( ( call . args ) . exprs or { } ) or { }
walk ( args [ 1 ] , false )
walk ( args [ 2 ] , false )
local callback = args [ 3 ]
if callback ~= nil and callback . kind == "funcExpr" then
walk ( ( callback ) . body , true )
else
walk ( callback , false )
end
return
end
elseif kind == "methodCall" and inWorkgroup == true then
local call = current
if call . name ~= nil and call . name . text == "run" then
walk ( call . obj , true )
local args = call . args ~= nil and ( ( call . args ) . exprs or { } ) or { }
local callback = args [ 1 ]
if callback ~= nil and callback . kind == "funcExpr" then
walk ( ( callback ) . body , true )
else
walk ( callback , true )
end
return
end
end
if kind == "newExpr" then



local call = ( current ) . call
local constructed = call ~= nil and call . inferredType or ( current ) . inferredType
local raw = constructed ~= nil and T . unwrapOwnership ( constructed ) or nil
local origin = raw ~= nil and raw . tag == "nominal" and ( ( raw ) . origin or raw ) or nil
if origin ~= nil and origin . declKind == "struct" and origin . nativeOnly == true then
for _ , child in ipairs ( current ) do
walk ( child , inWorkgroup )
end
return
end
end
if kind and DECLINED [ kind ] then
decline ( current , kind )

return
end
for _ , child in ipairs ( current ) do
walk ( child , inWorkgroup )
end
end

reducers ( )
walk ( node , false )
end

return ops
end

local __nuppExportValue= aot ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.aot"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.aot"]=__nuppExports;return __nuppExports