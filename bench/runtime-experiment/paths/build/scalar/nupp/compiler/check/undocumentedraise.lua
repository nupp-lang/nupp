_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()








































local cst = require ( "nupp.compiler.syntax.cst" )
local docblock = require ( "nupp.compiler.syntax.docblock" )
local state = require ( "nupp.compiler.check.state" )

local undocumentedraise = { }


















local function raisesAt ( c , node ) 
if not node or cst . isToken ( node ) then
return nil
end
local kind = node . kind
if kind == "funcbody" or kind == "shortfn" then
return nil
end
if kind == "call" then
local callee = node . obj
local tok = callee and callee . kind == "name" and callee . token or nil
local global = c . env and c . env . globals and c . env . globals . error or nil
if tok and tok . text == "error" and global and tok . definition == global . definition then
return tok
end
end
for _ , child in ipairs ( node ) do
local at = raisesAt ( c , child )
if at then
return at
end
end

return nil
end





function undocumentedraise . install ( c ) 
local ops = { }



local written = { }






local function tokenLike ( anchor , kind , text ) 
return {
kind = kind ,
text = text ,
offset = anchor . offset ,
line = anchor . line ,
col = anchor . col ,
trivia = anchor . trivia ,
triviaFirst = anchor . triviaFirst ,
triviaCount = 0 ,
}
end






local function typeNode ( spelling , anchor ) 
local names = { }




for part in ( spelling .. "." ) : gmatch ( "([^%.]*)%." ) do
if not cst . identifier ( part ) and part ~= "nil" then
return nil
end
names [ # names + 1 ] = part
end
if # names == 0 then
return nil
end
local node = _G.setmetatable({ kind =  "tname" }, cst.Tname)
node . base = cst . add ( node , tokenLike ( anchor , names [ 1 ] == "nil" and "nil" or "name" , names [ 1 ] ) )
for index = 2 , # names do
cst . add ( node , tokenLike ( anchor , "." , "." ) )
cst . add ( node , tokenLike ( anchor , "name" , names [ index ] ) )
end

return node
end




local function record ( stat , info ) 
for _ , raise in ipairs ( info . raises ) do
written [ # written + 1 ] = { stat = stat , raise = raise , scope = c . scope }
end
end

function ops . checkParams ( stat , params ) 
local info , documented = docblock . of ( stat )
if not documented then
return
end
record ( stat , info )
local parameters = { }
for _ , param in ipairs ( params or { } ) do
local name = param . name and param . name . text or nil


if not name then
for _ , child in ipairs ( param ) do
if ( child ) . kind == "..." then
name = "..."
end
end
end


if not name
and param . type
and param . type . kind == "tname"
and ( param . type ) . base
and ( param . type ) . base . text == "self"
then
name = "self"
end
if name then
parameters [ name ] = true
end
end
for name in pairs ( info . params ) do
if not parameters [ name ] then
local label = stat . name and ( stat . name . text or cst . textOf ( stat . name ) : gsub ( "%s+" , "" ) )
or "this declaration"
c . diag (
"NUPP1007" ,
stat . name and cst . lastToken ( stat . name ) or stat ,
("@param %s names no parameter of %s") : format ( name , label ) ,
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
local raiseTok = raisesAt ( c , body . body )
if not raiseTok or not documented or # info . raises > 0 then
return
end
local label = stat . name and ( cst . textOf ( stat . name ) : gsub ( "%s+" , "" ) ) or "this function"


local at = stat . name and cst . lastToken ( stat . name ) or stat
c . diag ( "NUPP2506" , at , ("%s raises, but its documentation does not say when") : format ( label ) , nil , {
help = "add an @raises line saying what makes it raise" ,
related = { c . related ( raiseTok , "raises here" ) }
} )
end




function ops . sweep ( ) 
local restore = c . scope
for _ , entry in ipairs ( written ) do
local stat , raise = entry . stat , entry . raise
local at = stat . name and cst . lastToken ( stat . name ) or stat
local label = stat . name and ( cst . textOf ( stat . name ) : gsub ( "%s+" , "" ) ) or "this declaration"
local spelling = raise . type
local node = spelling ~= "" and typeNode ( spelling , at ) or nil
local resolved = nil
if node then
c . scope = entry . scope




local before = # c . diags
resolved = c . resolveType ( node )
for index = # c . diags , before + 1 , -1 do
c . diags [ index ] = nil
end
c . scope = restore




if resolved and resolved . tag == "any" and spelling ~= "any" then
resolved = nil
end
end
if not resolved then
local msg = spelling == "" and ("@raises on %s names no type") : format ( label )
or ("@raises %s on %s names no type here") : format ( spelling , label )
c . diag ( "NUPP1010" , at , msg , nil , {
help = "write `@raises Type the condition`, naming the type `error` is called with" ,
} )
end
end
c . scope = restore
end

return ops
end

local __nuppExportValue= undocumentedraise ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.undocumentedraise"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.undocumentedraise"]=__nuppExports;return __nuppExports