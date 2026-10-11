_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













































local T = require ( "nupp.compiler.types" )
local cst = require ( "nupp.compiler.syntax.cst" )
local state = require ( "nupp.compiler.check.state" )

local discard = { }















local EFFECTFUL = { "yields" , "raises" , "writes" , "shapes" , "metatables" , "escapes" , "calls" }

local INDEXES = { dotIndex = true , bracketIndex = true , safeIndex = true , safeBracket = true , }





local function returnsAValue ( body ) 
if not body or cst . isToken ( body ) then
return false
end
local kind = body . kind
if kind == "funcbody" or kind == "shortfn" then
return false
end
if kind == "returnStmt" and # ( body . exprs or { } ) > 0 then
return true
end
for _ , child in ipairs ( body ) do
if returnsAValue ( child ) then
return true
end
end

return false
end

local function functionReturnsAValue ( body ) 
if body and body . kind == "shortfn" and body . expr then
return true
end

return returnsAValue ( body and body . body )
end

local function bodyContents ( body ) 
if body and body . kind == "shortfn" then
return body . body or body . expr
end

return body and body . body or nil
end





local function signatureAdmitsAValue ( ft ) 
if not ft or ft . tag ~= "func" then
return true
end
for _ , ret in ipairs ( ft . rets or { } ) do
if ret ~= T . nil_ then
return true
end
end

return false
end






local function closed ( queries , summary ) 
return queries . visible ( summary ) and queries . free ( summary , EFFECTFUL )
end



local function ownBindings ( body ) 
local own = { }

local function remember ( tok ) 
if tok and tok . definition then
own [ tok . definition ] = true
end
end

local function walk ( node ) 
if not node or cst . isToken ( node ) then
return
end
local kind = node . kind
if kind == "funcbody" or kind == "shortfn" then
for _ , param in ipairs ( node . params or { } ) do
remember ( param . name )
end
elseif kind == "localStmt" then
for _ , name in ipairs ( node . names or { } ) do
remember ( name )
end
elseif kind == "localFuncStmt" or kind == "fornumStmt" then
remember ( node . name )
elseif kind == "forinStmt" then
for _ , name in ipairs ( node . names or { } ) do
remember ( name )
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( body )

return own
end




local function writesOutward ( body ) 
local own = ownBindings ( body )
local found = false

local function judge ( target ) 
if not target then
return
end
local base = target
while base and INDEXES [ base . kind ] do
base = base . obj
end
if base ~= target then


found = true
return
end
if base . kind ~= "name" then
found = true
return
end
local tok = base . token
if not tok or not tok . definition or not own [ tok . definition ] then
found = true
end
end

local function walk ( node ) 
if found or not node or cst . isToken ( node ) then
return
end
if node . kind == "assignStmt" then
for _ , target in ipairs ( node . targets or { } ) do
judge ( target )
end
elseif node . kind == "compoundAssign" then
judge ( node . target )
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( body )

return found
end





function discard . install ( c ) 
local ops = { }


local candidates



= { }




function ops . statement ( call ) 
local callee = call and call . obj
local tok = callee and ( callee . token or callee . name ) or nil
if not tok or not tok . definition then
return
end
candidates [ # candidates + 1 ] = {
call = call ,
tok = tok ,


allowed = c . suppressed ( "discarded-result" ) ,
}
end





function ops . sweep ( queries ) 
if not queries then
return
end

local inert = { }
for _ , candidate in ipairs ( candidates ) do
local known = queries . callee and queries . callee ( candidate . call ) or queries . known ( candidate . tok )
local body = known and known . body or nil
if not candidate . allowed and body then
if inert [ body ] == nil then


inert [ body ] = functionReturnsAValue ( body )
and signatureAdmitsAValue ( known . definition and known . definition . type )
and closed ( queries , known . summary )
and not writesOutward ( bodyContents ( body ) )
end
if inert [ body ] then
local at = known . definition and known . definition . token
local related = at and c . related ( at , "declared here, and does nothing but return" ) or nil
c . diag (
"discarded-result" ,
candidate . tok ,
("%s has no effects, so dropping its result leaves this statement doing nothing")

: format ( candidate . tok . text ) ,
nil ,
{ help = "use the result, or delete the call" , related = related and { related } or nil }
)
end
end
end
end

return ops
end

local __nuppExportValue= discard ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.discard"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.discard"]=__nuppExports;return __nuppExports