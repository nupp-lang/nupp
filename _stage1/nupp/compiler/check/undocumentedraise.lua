_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);































local cst = require ( "nupp.compiler.cst" )
local docblock = require ( "nupp.compiler.docblock" )
local state = require ( "nupp.compiler.check.state" )

local undocumentedraise = { }














local function raisesAt ( node )
if not node or cst . isToken ( node ) then
return nil
end
local kind = node . kind
if kind == "funcbody" or kind == "shortfn" then
return nil
end
if kind == "call" then
local callee = node . obj
if callee and callee . kind == "name" and callee . token and callee . token . text == "error" then
return callee . token
end
end
for _ , child in ipairs ( node ) do
local at = raisesAt ( child )
if at then
return at
end
end

return nil
end





function undocumentedraise . install ( c )
local ops = { }

function ops . checkParams ( stat , params )
local info , documented = docblock . of ( stat )
if not documented then
return
end
local parameters = { }
for _ , param in ipairs ( params or { } ) do
local name = param . name and param . name . text or ( param [ 1 ] and param [ 1 ] . kind == "..." and "..." or nil )


if not name and param . type and param . type . kind == "tname" and (
param . type
) . base and ( param . type ) . base . text == "self" then
name = "self"
end
if name then
parameters [ name ] = true
end
end
for name in pairs ( info . params ) do
if not parameters [ name ] then
local label = stat . name and (
stat . name . text or cst . textOf ( stat . name ) : gsub ( "%s+" , "" )
) or "this declaration"
c . diag (
"NUPP1007" ,
stat . name and cst . lastToken ( stat . name ) or stat ,
( "@param %s names no parameter of %s" ) : format ( name , label ) ,
nil ,
{ help = "remove the @param line or spell a declared parameter's name" }
)
end
end
end








function ops . check ( stat , body )
if not stat or not body then
return
end
ops . checkParams ( stat , body . params or { } )
local info , documented = docblock . of ( stat )
local raiseTok = raisesAt ( body . body )
if not raiseTok or not documented or # info . raises > 0 then
return
end
local label = stat . name and ( cst . textOf ( stat . name ) : gsub ( "%s+" , "" ) ) or "this function"


local at = stat . name and cst . lastToken ( stat . name ) or stat
c . diag ( "NUPP2506" , at , ( "%s raises, but its documentation does not say when" ) : format ( label ) , nil , {
help = "add an @raises line saying what makes it raise" ,
related = { c . related ( raiseTok , "raises here" ) }
} )
end

return ops
end

return undocumentedraise
