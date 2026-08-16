_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);










































local T = require ( "nupp.compiler.types" )
local cst = require ( "nupp.compiler.cst" )
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


local candidates = { }




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


inert [
body
] = returnsAValue (
body . body
) and signatureAdmitsAValue (
known . definition and known . definition . type
) and closed ( queries , known . summary ) and not writesOutward ( body . body )
end
if inert [ body ] then
local at = known . definition and known . definition . token
local related = at and c . related ( at , "declared here, and does nothing but return" ) or nil
c . diag (
"discarded-result" ,
candidate . tok ,
(
"%s has no effects, so dropping its result leaves this " .. "statement doing nothing"
) : format ( candidate . tok . text ) ,
nil ,
{ help = "use the result, or delete the call" , related = related and { related } or nil }
)
end
end
end
end

return ops
end

return discard
