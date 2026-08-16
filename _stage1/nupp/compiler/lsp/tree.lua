_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








local cst = require ( "nupp.compiler.cst" )
local lexer = require ( "nupp.compiler.lexer" )

local tree = { }








































































function tree . tokenAt ( result , offset )
if not result then
return nil
end
local previous = nil
for _ , tok in ipairs ( result . tokens or { } ) do
if tok . kind ~= "eof" then
if offset >= tok . offset and offset < tok . offset + # tok . text then
return tok
end
if tok . offset + # tok . text == offset then
previous = tok
end
end
end

return previous
end

function tree . symbolKey ( def )
if not def then
return nil
end
if def . generatedIdentity then
return "generated:" .. def . generatedIdentity
end
if not def . filename or not def . token then
return nil
end

return def . filename .. ":" .. tostring ( def . token . offset )
end

local function documentationFrom (
kindAt ,
textAt ,
count
)
local lines = { }
for index = 1 , count do
local kind = kindAt ( index )
if kind == "comment" then
local text = textAt ( index )
text = text : gsub ( "^%-%-%-?%s?" , "" )
text = text : gsub ( "^%-%-%[=*%[" , "" )
text = text : gsub ( "%]=*%]$" , "" )
lines [ # lines + 1 ] = text
elseif kind == "whitespace" and textAt ( index ) : find ( "\n%s*\n" ) then
lines = { }
end
end

return # lines > 0 and table . concat ( lines , "\n" ) or nil
end


function tree . documentationOf ( tok )
if not tok then
return nil
end

return documentationFrom (
|index| -> ( lexer . triviaKind ( tok , index ) ) ,
|index| -> ( lexer . triviaText ( tok , index ) ) ,
tok . triviaCount
)
end



function tree . fromTrivia ( triviaList )
local list = triviaList or { }

return documentationFrom ( |index| -> ( list [ index ] . kind ) , |index| -> ( list [ index ] . text ) , # list )
end






function tree . documentationAt ( tokens , index )
local tok = tokens [ index ]
if not tok then
return nil
end
local docs = tree . documentationOf ( tok )
if docs then
return docs
end
for cursor = index - 1 , 1 , - 1 do
local candidate = tokens [ cursor ]
if candidate . line ~= tok . line then
break
end
docs = tree . documentationOf ( candidate )
if docs then
return docs
end
end

return nil
end



local DECLARING = {
[ "local" ] = true ,
[ "global" ] = true ,
[ "function" ] = true ,
[ "type" ] = true ,
[ "record" ] = true ,
[ "struct" ] = true ,
[ "interface" ] = true ,
[ "cdef" ] = true ,
}






function tree . findDeclaration ( tokens , name , near )
local best , bestDistance
for index , tok in ipairs ( tokens ) do
if tok . kind == "name" and tok . text == name then
local previous , following = tokens [ index - 1 ] , tokens [ index + 1 ]
local declared = previous ~= nil and DECLARING [ previous . kind ] or false
if not declared and previous and ( previous . kind == "." or previous . kind == ":" ) then
local cursor = index - 1
while tokens [
cursor
] and ( tokens [ cursor ] . kind == "." or tokens [ cursor ] . kind == ":" or tokens [ cursor ] . kind == "name" ) do
cursor = cursor - 1
end
declared = tokens [ cursor ] ~= nil and DECLARING [ tokens [ cursor ] . kind ] or false
end
if not declared and following and following . kind == ":" and ( not previous or previous . line ~= tok . line ) then
declared = true
end
if declared then
local distance = math . abs ( tok . offset - near )
if not bestDistance or distance < bestDistance then
best , bestDistance = tok , distance
end
end
end
end

return best
end









function tree . walkNodes ( node , visit )
if not node or cst . isToken ( node ) then
return
end
visit ( node )
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
tree . walkNodes ( child , visit )
end
end
end

function tree . nodeBounds ( node )
local first , last
local function walk ( value )
if cst . isToken ( value ) then
if value . text ~= "" then
first = first or value . offset
last = value . offset + # value . text
end
else
for _ , child in ipairs ( value ) do
walk ( child )
end
end
end

walk ( node )

return first , last
end




function tree . comptimeAt ( result , offset )
local found = nil
local bodyFrom = nil
local bodyTo = nil
if not result then
return nil
end
tree . walkNodes ( result . root , function ( node )
if node . kind == "comptimeExpr" then
local from , to = tree . nodeBounds ( node )
if from and to and offset >= from and offset <= to then
found = node
local body = ( node ) . body
if body then
bodyFrom , bodyTo = tree . nodeBounds ( body )
end
end
end
end )

return found , bodyFrom , bodyTo
end





















function tree . memberHolder ( node )
if node . kind == "dotIndex" or node . kind == "methodCall" or node . kind == "safeIndex" then
local obj = node . obj
if obj and obj . kind == "name" then
return obj . token , node . name
end
return nil
end
if node . kind == "funcStmt" then
local fname = node . name
if not fname or fname . kind ~= "funcname" then
return nil
end
local names = { }
for _ , child in ipairs ( fname ) do
if cst . isToken ( child ) and child . kind == "name" then
names [ # names + 1 ] = child
end
end


if # names ~= 2 then
return nil
end
return names [ 1 ] , names [ 2 ]
end

return nil
end





function tree . functionSignature ( stat )


local block = stat . body and ( stat . body ) . body
local parts , first , done = { } , true , false
local function walk ( node )
if done then
return
end
if node == block then
done = true
return
end
if cst . isToken ( node ) then
if not first then
for index = 1 , node . triviaCount do
parts [ # parts + 1 ] = lexer . triviaText ( node , index )
end
end
first = false
parts [ # parts + 1 ] = node . text
return
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( stat )

return ( table . concat ( parts ) : gsub ( "%s+$" , "" ) )
end



function tree . moduleHeld ( result , tok )
if not tok then
return nil
end
local def = tok . definition
if def and def . requiredModule then
return def . requiredModule
end
if result . moduleName and result . moduleLocal == tok . text then
return result . moduleName
end

return nil
end




function tree . memberOccurrences ( result , moduleName , memberName )
local found = { }
tree . walkNodes ( result . root , function ( node )
local holder , member = tree . memberHolder ( node )
if not member or member . text ~= memberName then
return
end
if tree . moduleHeld ( result , holder ) ~= moduleName then
return
end
found [ # found + 1 ] = { token = member , stat = node . kind == "funcStmt" and node or nil , }
end )
table . sort ( found , function ( a , b )
return a . token . offset < b . token . offset
end )

return found
end


function tree . moduleMemberDeclarations ( result , moduleName )
local found = { }
tree . walkNodes ( result . root , function ( node )
if node . kind ~= "funcStmt" then
return
end
local holder , member = tree . memberHolder ( node )
if not member or tree . moduleHeld ( result , holder ) ~= moduleName then
return
end
found [ # found + 1 ] = { name = member . text , token = member , stat = node }
end )
table . sort ( found , function ( a , b )
return a . token . offset < b . token . offset
end )

return found
end


function tree . moduleMemberAt ( result , offset )
local best = nil
tree . walkNodes ( result . root , function ( node )
local holder , member = tree . memberHolder ( node )
if not member or not holder then
return
end
if offset < member . offset or offset >= member . offset + # member . text then
return
end
local moduleName = tree . moduleHeld ( result , holder )
if moduleName then
best = { moduleName = moduleName , name = member . text , token = member }
end
end )

return best
end









function tree . enclosingChain ( result , offset )
local chain = { }
local function walk ( node )
if cst . isToken ( node ) then
return
end
local from , to = tree . nodeBounds ( node )
if not from or offset < from or offset > to then
return
end
chain [ # chain + 1 ] = { from = from , to = to }
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( result . root )

return chain
end










return tree
