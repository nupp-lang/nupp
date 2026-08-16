_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
































local cst = require ( "nupp.compiler.cst" )
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
tableExpr = "a table constructor" ,
istring = "an interpolated string" ,
safeCall = "an optional call" ,
safeIndex = "an optional index" ,
safeBracket = "an optional index" ,
newExpr = "a constructor call" ,
handleStmt = "suspension handling" ,
unsafeStmt = "an `unsafe` region" ,
unsafeOwnershipExpr = "an unsafe memory operation" ,
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
tableExpr = "an AOT body allocates nothing and holds no Lua value" ,
istring = "an AOT body allocates nothing and holds no Lua value" ,
safeCall = "an AOT call must resolve statically" ,
safeIndex = "an AOT body indexes only spans, structs, and fixed arrays" ,
safeBracket = "an AOT body indexes only spans, structs, and fixed arrays" ,
newExpr = "an AOT body creates no owner and allocates nothing" ,
handleStmt = "an AOT function is non-suspending by construction" ,
unsafeStmt = "`@aot` is a checked contract and does not admit unsafe operations" ,
unsafeOwnershipExpr = "`@aot` is a checked contract and does not admit unsafe operations" ,
}





function aot . install ( c )
local ops = { }


local function decline ( node , kind )
local at = cst . firstToken ( node ) or node
c . diag ( "NUPP2903" , at , ( "%s has no AOT IR representation; %s" ) : format ( DECLINED [ kind ] , BECAUSE [ kind ] ) )
end




function ops . body ( node )
if node == nil or cst . isToken ( node ) then
return
end




local body = ( node ) . body
local loops = 0
for _ , statement in ipairs ( body and body . stats or { } ) do
if statement . kind == "fornumStmt" then
loops = loops + 1
end
end
( node ) . aotMapLoop = loops == 1
local function walk ( current )
if current == nil or cst . isToken ( current ) then
return
end
local kind = ( current ) . kind
if kind and DECLINED [ kind ] then
decline ( current , kind )

return
end


if kind == "binop" then
local op = ( current ) . op
if op and op . text == ".." then
c . diag (
"NUPP2903" ,
op ,
"concatenation has no AOT IR representation; "
.. "an AOT body allocates nothing and holds no Lua value"
)

return
end
end
for _ , child in ipairs ( current ) do
walk ( child )
end
end

walk ( node )
end

return ops
end

return aot
