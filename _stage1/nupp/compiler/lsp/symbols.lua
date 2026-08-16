_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






local wire = require ( "nupp.compiler.lsp.wire" )
local tree = require ( "nupp.compiler.lsp.tree" )
local text = require ( "nupp.compiler.lsp.text" )

local symbols = { }













symbols . SYMBOL_KINDS = {
record = 5 ,
class = 5 ,
struct = 23 ,
interface = 11 ,
type = 5 ,
field = 8 ,
[ "function" ] = 12 ,
method = 6 ,
variable = 13 ,
constant = 14 ,
}


local function declarationChildren ( stat , source )
local children = { }
local function child ( nameTok , kind , node )
if not nameTok then
return
end
local from , to = tree . nodeBounds ( node or nameTok )
if not from then
return
end

children [
# children + 1
] = {
name = nameTok . text ,
kind = symbols . SYMBOL_KINDS [ kind ] or symbols . SYMBOL_KINDS . field ,
range = {
start = text . positionAtOffset ( source , from ) ,
[ "end" ] = text . positionAtOffset ( source , to ) ,
} ,
selectionRange = text . tokenRange ( source , nameTok ) ,
children = wire . array ( { } ) ,
}
end

for _ , entry in ipairs ( stat . entries or { } ) do
if entry . kind == "fieldDecl" then
child ( entry . name , "field" , entry )
elseif entry . kind == "inlineMethod" then
child ( entry . name , "method" , entry )
elseif entry . kind == "metamethodDecl" then
child ( entry . name , "method" , entry )
end
end

local nominal = stat . resolvedType
if nominal and nominal . tag == "nominal" then
local generated = { }
for name , definition in pairs ( nominal . derivedDefinitions or { } ) do
generated [ # generated + 1 ] = { name = name , definition = definition }
end
for name , definition in pairs ( nominal . derivedStaticDefinitions or { } ) do
generated [ # generated + 1 ] = { name = name , definition = definition , static = true }
end
table . sort ( generated , function ( a , b )
if a . name ~= b . name then
return a . name < b . name
end
return not a . static and b . static
end )
for _ , item in ipairs ( generated ) do
local definition = item . definition
local origin = definition and definition . token
if origin then
children [
# children + 1
] = {
name = item . name .. " (generated" .. ( item . static and ", static" or "" ) .. ")" ,
kind = symbols . SYMBOL_KINDS [ definition . kind ] or symbols . SYMBOL_KINDS . method ,
range = text . tokenRange ( source , origin ) ,
selectionRange = text . tokenRange ( source , origin ) ,
children = wire . array ( { } ) ,
}
end
end
end

return wire . array ( children )
end




function symbols . documentSymbols ( result , source )
local found = wire . array ( { } )
local function emit ( stat , nameTok , kind , path )
if not nameTok then
return
end
local from , to = tree . nodeBounds ( stat )
if not from then
return
end

found [
# found + 1
] = {
name = path or nameTok . text ,
kind = symbols . SYMBOL_KINDS [ kind ] or symbols . SYMBOL_KINDS . variable ,
range = {
start = text . positionAtOffset ( source , from ) ,
[ "end" ] = text . positionAtOffset ( source , to ) ,
} ,
selectionRange = text . tokenRange ( source , nameTok ) ,
children = declarationChildren ( stat , source ) ,
}
end

local function qualified ( stat )
local parts = { }
for _ , tok in ipairs ( stat . qualifiers or { } ) do
parts [ # parts + 1 ] = tok . text
end
parts [ # parts + 1 ] = stat . name and stat . name . text or "?"

return table . concat ( parts , "." )
end

for _ , block in ipairs ( result . root . blocks or { } ) do
for _ , raw in ipairs ( block . stats or { } ) do
local stat = raw
while stat and stat . kind == "pragmaStmt" do
stat = stat . stat
end
if not stat then

elseif stat . kind == "recordDecl" then
emit ( stat , stat . name , stat . declKind or "record" , qualified ( stat ) )
elseif stat . kind == "typeAlias" then
emit ( stat , stat . name , "type" , qualified ( stat ) )
elseif stat . kind == "localFuncStmt" then
emit ( stat , stat . name , "function" )
elseif stat . kind == "funcStmt" then
local holder , member = tree . memberHolder ( stat )
local fname = stat . name
local named = fname
local nameTok = member or ( fname and named . base )
local path = nil
if holder and member then
path = holder . text .. ( named . method and ":" or "." ) .. member . text
end
emit ( stat , nameTok , fname and named . method and "method" or "function" , path )
end
end
end

return found
end







function symbols . foldableSpans ( result )
local spans = { }
tree . walkNodes ( result . root , function ( node )
if node . kind == "block" or node . kind == "chunk" then
return
end
local from , to = tree . nodeBounds ( node )
if from and to and to > from then
spans [ # spans + 1 ] = { from , to }
end
end )

return spans
end

return symbols
