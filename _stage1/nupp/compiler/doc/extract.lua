_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local cst = require ( "nupp.compiler.cst" )
local lexer = require ( "nupp.compiler.lexer" )
local parser = require ( "nupp.compiler.parser" )
local docblock = require ( "nupp.compiler.docblock" )
local formatter = require ( "nupp.compiler.fmt" )
local stringsMod = require ( "nupp.compiler.doc.strings" )
local filesMod = require ( "nupp.compiler.doc.files" )

local trim = stringsMod . trim
local normalize , join = filesMod . normalize , filesMod . join

local extract = { }


























extract.Member = {} extract.Member.__index = extract.Member



































































local function firstToken ( node )
if not node then
return nil
end
if cst . isToken ( node ) then
return node
end
for _ , child in ipairs ( node ) do
local token = firstToken ( child )
if token then
return token
end
end

return nil
end







local function dedent ( text )
if not text : find ( "\n" , 1 , true ) then
return text
end
local margin , found = "" , false
for line in text : gmatch ( "\n([^\n]*)" ) do
if not line : match ( "^[ \t]*$" ) then
local indent = line : match ( "^[ \t]*" ) or ""
if not found or # indent < # margin then
margin , found = indent , true
end
end
end
if margin == "" then
return text
end

return ( text : gsub ( "\n" .. margin , "\n" ) )
end

local function syntax ( node )
return dedent ( trim ( cst . textOf ( node ) ) )
end





local docLines , parseDoc = docblock . linesOf , docblock . parse






local function documentedNode ( entry )
local annotations = entry and entry . annotations
return annotations and annotations [ 1 ] or entry
end

local function entryDoc ( entry )
return parseDoc ( docLines ( documentedNode ( entry ) ) )
end







local function privateName ( name )
local tail = tostring ( name or "" ) : match ( "([^%.:]+)$" ) or ""
tail = tail : gsub ( "^[\"']" , "" )
return tail : sub ( 1 , 1 ) == "_"
end






local function internalModuleName ( name )
return ( "." .. tostring ( name or "" ) .. "." ) : find ( ".internal." , 1 , true ) ~= nil
end






local function hiddenEntry ( entry , includePrivate )
if includePrivate then
return false
end
if entryDoc ( entry ) . tags . internal then
return true
end

return entry . kind ~= "metamethodDecl" and privateName ( entry . name and entry . name . text or "" )
end








local function hiddenNodes ( node , includePrivate )
local dropped = { }
local function mark ( current )
if cst . isToken ( current ) then
return
end
for _ , entry in ipairs ( current . entries or current . fields or { } ) do
if hiddenEntry ( entry , includePrivate ) then
dropped [ entry ] = true
for _ , annotation in ipairs ( entry . annotations or { } ) do
dropped [ annotation ] = true
end
end
end
for _ , child in ipairs ( current ) do
mark ( child )
end
end

mark ( node )

return dropped
end







local function structureSignature ( node , includePrivate )
local parts = { }
local dropped = hiddenNodes ( node , includePrivate )






local leading = true
local function walk ( child )
if cst . isToken ( child ) then
local triviaParts = { }
local removedDocumentation = false
for index = 1 , leading and 0 or child . triviaCount do
local text = lexer . triviaText ( child , index )
if lexer . triviaKind ( child , index ) == "comment" and text : match ( "^%-%-%-" ) then
removedDocumentation = true
else
triviaParts [ # triviaParts + 1 ] = text
end
end
local triviaText = table . concat ( triviaParts )
if removedDocumentation then
if triviaText : match ( "^%s*$" ) then
triviaText = "\n"
else
repeat
local collapsed , count = triviaText : gsub ( "\n[ \t]*\n[ \t]*" , "\n" )
triviaText = collapsed
until count == 0
end
end
parts [ # parts + 1 ] = triviaText
parts [ # parts + 1 ] = child . text
leading = false
else



if dropped [ child ] then
return
end
for _ , nested in ipairs ( child ) do
if child . kind ~= "funcbody" or nested ~= child . body then
walk ( nested )
end
end
end
end

walk ( node )
local source = trim ( table . concat ( parts ) )
local formatted , errors = formatter . format ( source , "documentation-signature.nupp" )
if # errors > 0 then
return source
end

return trim ( formatted )
end




local function annotationTokens ( child , parts )
if cst . isToken ( child ) then
parts [ # parts + 1 ] = child . text
else
for _ , nested in ipairs ( child ) do
annotationTokens ( nested , parts )
end
end
end





local function annotationText ( node )
local name = node and node . name and node . name . text
if not name then
return nil
end
local args = { }
for _ , arg in ipairs ( node . annotationArgs or { } ) do
local parts = { }
annotationTokens ( arg , parts )
args [ # args + 1 ] = trim ( table . concat ( parts ) )
end
if # args == 0 then
return "@" .. name
end

return "@" .. name .. "(" .. table . concat ( args , ", " ) .. ")"
end


local function annotationsOf ( entry )
local applied = entry and entry . annotations
if not applied or # applied == 0 then
return nil
end
local names = { }
for _ , node in ipairs ( applied ) do
local text = annotationText ( node )
if text then
names [ # names + 1 ] = text
end
end

return # names > 0 and names or nil
end



local function declaredName ( stat )
local name = stat . name . text
if not stat . qualifiers then
return name
end
local parts = { }
for j , token in ipairs ( stat . qualifiers ) do
parts [ j ] = token . text
end
parts [ # parts + 1 ] = name

return table . concat ( parts , "." )
end

local function genericText ( node )
return node and node . generics and syntax ( node . generics ) or ""
end






local function documentedResultType ( value )
if value and value . kind == "tborrows" then
return syntax ( value . type )
end

return syntax ( value )
end

local function functionSignature ( stat , name )
local body = stat . body
local params = { }
for _ , param in ipairs ( body and body . params or { } ) do
local piece
if param [ 1 ] and param [ 1 ] . kind == "..." then
piece = "..." .. ( param . name and param . name . text or "" )
else
piece = ( param . modeTok and ( param . modeTok . text .. " " ) or "" ) .. ( param . name and param . name . text or "?" )
end
if param . type then
piece = piece .. ": " .. syntax ( param . type )
end
params [ # params + 1 ] = piece
end
local returns = { }
for _ , value in ipairs ( body and body . rets or { } ) do
returns [ # returns + 1 ] = documentedResultType ( value )
end
local prefix = stat . kind == "localFuncStmt" and "local function " or "function "
local result = prefix .. name .. genericText ( body ) .. "(" .. table . concat ( params , ", " ) .. ")"
if # returns > 0 then
result = result .. ": " .. table . concat ( returns , ", " )
end

return result
end

local function cdefSignature ( stat )
local params = { }
for _ , param in ipairs ( stat . params or { } ) do
if param [ 1 ] and param [ 1 ] . kind == "..." then
params [ # params + 1 ] = "..."
else
local value = (
param . modeTok and ( param . modeTok . text .. " " ) or ""
) .. ( param . name and param . name . text or "?" ) .. ": " .. ( param . type and syntax ( param . type ) or "any" )
params [ # params + 1 ] = value
end
end
local result = "cdef function " .. stat . name . text .. "(" .. table . concat ( params , ", " ) .. ")"
if stat . ret then
result = result .. ": " .. syntax ( stat . ret )
end
if stat . fromLib then
result = result .. " from " .. stat . fromLib . text
end

return result
end

local function functionDetails ( stat , info )
local details = { params = { } , returns = { } }
for _ , param in ipairs ( stat . body and stat . body . params or stat . params or { } ) do
local name = param . name and param . name . text or "..."
details . params [
# details . params + 1
] = {
name = name ,
type = param . type and syntax ( param . type ) or "any" ,
mode = param . modeTok and param . modeTok . text or nil ,
text = info . params [ name ] or "" ,
}
end
local returns = stat . body and stat . body . rets or ( stat . ret and { stat . ret } or { } )
for index , value in ipairs ( returns or { } ) do
details . returns [ # details . returns + 1 ] = { type = documentedResultType ( value ) , text = info . returns [ index ] or "" , }
end

return details
end











local function typeFunction ( node )
if not node then
return nil
end
if node . kind == "tfunc" then
return node
end
if node . kind ~= "tintersection" then
return nil
end
local widest = nil
for _ , member in ipairs ( node . types or { } ) do
if member . kind ~= "tfunc" then
return nil
end
if not widest or # ( member . params or { } ) > # ( widest . params or { } ) then
widest = member
end
end

return widest
end

local function typeFunctionDetails ( node , info )
local details = { params = { } , returns = { } }
for _ , param in ipairs ( node . params or { } ) do
local name = param . name and param . name . text or ( param [ 1 ] and param [ 1 ] . kind == "..." and "..." ) or "?"
details . params [
# details . params + 1
] = {
name = name ,
type = param . type and syntax ( param . type ) or "any" ,
mode = param . modeTok and param . modeTok . text or nil ,
text = info . params [ name ] or "" ,
}
end
for index , value in ipairs ( node . rets or { } ) do
details . returns [ # details . returns + 1 ] = { type = syntax ( value ) , text = info . returns [ index ] or "" , }
end

return details
end







local function fieldItem ( field , childModuleName , includePrivate )
local name = field . name . text
local info = entryDoc ( field )
if hiddenEntry ( field , includePrivate ) then
return nil
end
local item = {
name = name ,
kind = "variable" ,
signature = "local " .. name .. ": " .. syntax ( field . type ) ,
doc = info ,
path = childModuleName .. "." .. name ,
line = firstToken ( field ) and firstToken ( field ) . line or 1 ,
members = { } ,
params = { } ,
returns = { } ,
raises = info . raises ,
typeargs = { } ,
annotations = annotationsOf ( field ) ,
}
local fn = typeFunction ( field . type )
if fn then
item . kind = "function"
local details = typeFunctionDetails ( fn , info )
item . params , item . returns = details . params , details . returns
for _ , generic in ipairs ( fn . generics and fn . generics . names or { } ) do
item . typeargs [ # item . typeargs + 1 ] = { name = generic . text , text = info . typeargs [ generic . text ] or "" , }
end
end

return item
end













local function recordNamed ( blocks , targetName )
local function find ( stat , prefix )
if stat . kind ~= "recordDecl" then
return nil
end
local name = prefix and prefix .. "." .. stat . name . text or declaredName ( stat )
if name == targetName then
return stat
end
if targetName : sub ( 1 , # name + 1 ) == name .. "." then
for _ , entry in ipairs ( stat . entries or { } ) do
local found = find ( entry , name )
if found then
return found
end
end
end

return nil
end

for _ , block in ipairs ( blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
local found = find ( stat , nil )
if found then
return found
end
end
end

local segments = { }
for segment in targetName : gmatch ( "[^.]+" ) do
segments [ # segments + 1 ] = segment
end

local function walk ( stat , index )
if index > # segments then
return stat
end
for _ , entry in ipairs ( stat . entries or { } ) do
if entry . kind == "recordDecl" and entry . name and entry . name . text == segments [ index ] then
local found = walk ( entry , index + 1 )
if found then
return found
end
end
end

return nil
end

local function findRelative ( entries )
for _ , entry in ipairs ( entries or { } ) do
if entry . kind == "recordDecl" then
if entry . name and entry . name . text == segments [ 1 ] then
local found = walk ( entry , 2 )
if found then
return found
end
end
local nested = findRelative ( entry . entries )
if nested then
return nested
end
end
end

return nil
end

for _ , block in ipairs ( blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "recordDecl" then
if stat . name and stat . name . text == segments [ 1 ] then
local found = walk ( stat , 2 )
if found then
return found
end
end
local nested = findRelative ( stat . entries )
if nested then
return nested
end
end
end
end

return nil
end

local function byKindThenName ( left , right )
if left . kind == right . kind then
return left . name < right . name
end
return left . kind < right . kind
end

local declarationItem




local function shapeEntries ( field , blocks )
if field . type and field . type . kind == "tshape" then
return field . type . fields
elseif field . type and field . type . kind == "tname" then
local record = recordNamed ( blocks , syntax ( field . type ) )
return record and record . entries
end

return nil
end




local function shapeModule ( name , entries , text , path , blocks , includePrivate , expanding , modules )
if not entries or expanding [ entries ] then
return
end
if not includePrivate and internalModuleName ( name ) then
return
end
expanding [ entries ] = true
local items = { }
for _ , entry in ipairs ( entries ) do
if entry . kind == "fieldDecl" or entry . kind == "tshapeField" then
local info = entryDoc ( entry )
local nested = shapeEntries ( entry , blocks )
if info . tags . namespace and nested then
shapeModule (
name .. "." .. entry . name . text ,
nested ,
info . text ,
path ,
blocks ,
includePrivate ,
expanding ,
modules
)
else
local item = fieldItem ( entry , name , includePrivate )
if item then
items [ # items + 1 ] = item
end
end
elseif entry . kind == "typeAlias" or entry . kind == "recordDecl" then
local info = entryDoc ( entry )
if entry . kind == "recordDecl" and info . tags . namespace then





shapeModule (
name .. "." .. entry . name . text ,
entry . entries ,
info . text ,
path ,
blocks ,
includePrivate ,
expanding ,
modules
)
else
local item = declarationItem ( entry , name , true , true , includePrivate )
if item then


item . module = nil
item . path = name .. "." .. item . name
for _ , member in ipairs ( item . members ) do
member . path = item . path .. "." .. member . name
end
items [ # items + 1 ] = item
end
end
end
end
table . sort ( items , byKindThenName )
modules [ # modules + 1 ] = { name = name , path = path , text = text , items = items }
expanding [ entries ] = nil
end





local function namespaceChildren ( shape , prefix , path , blocks , includePrivate )
local modules = { }
local expanding = { }
for _ , field in ipairs ( shape . fields or { } ) do
if field . kind == "tshapeField" and not hiddenEntry ( field , includePrivate ) then
shapeModule (
prefix .. "." .. field . name . text ,
shapeEntries ( field , blocks ) ,
entryDoc ( field ) . text ,
path ,
blocks ,
includePrivate ,
expanding ,
modules
)
end
end

return modules
end




local function globalModules ( name , shape , text , path , blocks , includePrivate )
local modules = { }
shapeModule ( name , shape . fields , text , path , blocks , includePrivate , { } , modules )

return modules
end





local function buildMembers (
entries ,
basePath ,
includePrivate ,
fieldTextOverrides
)
local members = { }
for _ , entry in ipairs ( entries or { } ) do
local entryInfo = entryDoc ( entry )
local entryVisible = not hiddenEntry ( entry , includePrivate )
if ( entry . kind == "fieldDecl" or entry . kind == "metamethodDecl" ) and entryVisible then
local fieldInfo = entryInfo
local member = setmetatable({ name =
entry . name . text ,  type =
syntax ( entry . type ) ,  text =
fieldInfo . text ~= "" and fieldInfo . text or (
fieldTextOverrides and fieldTextOverrides [ entry . name . text ]
) or "" ,  path =
basePath .. "." .. entry . name . text ,  params =
{ } ,  returns =
{ } ,  raises =
fieldInfo . raises ,  annotations =
annotationsOf ( entry ) }, extract.Member)

local fieldFunction = typeFunction ( entry . type )
if fieldFunction then
local details = typeFunctionDetails ( fieldFunction , fieldInfo )
member . params , member . returns = details . params , details . returns
member . isFunction = true
end
if entry . kind == "metamethodDecl" then
member . isMetamethod = true
end
members [ # members + 1 ] = member
elseif entry . kind == "inlineMethod" and entryVisible then
local methodInfo = entryInfo
local details = functionDetails ( entry , methodInfo )
members [
# members + 1
] = setmetatable({ name =
entry . name . text ,  type =
functionSignature ( entry , entry . name . text ) ,  text =
methodInfo . text ,  path =
basePath .. "." .. entry . name . text ,  params =
details . params ,  returns =
details . returns ,  raises =
methodInfo . raises ,  isFunction =
true ,  annotations =
annotationsOf ( entry ) }, extract.Member)

elseif entry . kind == "recordDecl" and entryVisible then
local nestedPath = basePath .. "." .. entry . name . text
members [
# members + 1
] = setmetatable({ name =
entry . name . text ,  type =
entry . declKind or "record" ,  text =
entryInfo . text ,  path =
nestedPath ,  params =
{ } ,  returns =
{ } ,  raises =
{ } ,  isType =
true ,  members =
buildMembers ( entry . entries , nestedPath , includePrivate , entryInfo . fields ) ,  annotations =
annotationsOf ( entry ) }, extract.Member)

elseif entry . name and entryVisible then
members [
# members + 1
] = setmetatable({ name =
entry . name . text ,  type =
entry . kind ,  text =
entryInfo . text ,  path =
basePath .. "." .. entry . name . text ,  params =
{ } ,  returns =
{ } ,  raises =
{ } ,  annotations =
annotationsOf ( entry ) }, extract.Member)

end
end

return members
end







local function returnedNames ( root )
local names = { }
local function record ( value )
if value and value . kind == "name" and value . token then
names [ value . token . text ] = true
end
end

for _ , block in ipairs ( root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "returnStmt" then
for _ , expr in ipairs ( stat . exprs or { } ) do
if expr . kind == "tableExpr" then
for _ , field in ipairs ( expr . fields or { } ) do
record ( field . value )
end
end
end
end
end
end

return names
end





declarationItem = function ( stat , moduleName , includeAll , declarationFile , includePrivate , published )
local documented = stat
local applied = { }
while stat . kind == "pragmaStmt" and stat . stat do
local text = annotationText ( stat )
if text then
applied [ # applied + 1 ] = text
end
stat = stat . stat
end
local lines = docLines ( documented )
local info = parseDoc ( lines )
local public = includeAll or declarationFile or info . tags . export or info . tags . public
local kind , name , signature
if stat . kind == "funcStmt" or stat . kind == "localFuncStmt" then
name = stat . kind == "funcStmt" and syntax ( stat . name ) or stat . name . text
public = public or stat . kind == "funcStmt"
kind = stat . name and stat . name . method and "method" or "function"
signature = functionSignature ( stat , name )
elseif stat . kind == "cdefFunc" then




name , kind = stat . name . text , "function"
public = public or ( published or { } ) [ name ] == true
signature = cdefSignature ( stat )
elseif stat . kind == "typeAlias" then
name , kind = stat . name . text , "type"
public = public or stat . visibility == "module" or stat . visibility == "global"
signature = (
stat . visibility == "global" and "global " or stat . visibility == "local" and "local " or ""
) .. "type " .. declaredName ( stat ) .. genericText ( stat ) .. " = " .. syntax ( stat . value )
elseif stat . kind == "recordDecl" then
name , kind = stat . name . text , stat . declKind
public = public or stat . visibility == "module" or stat . visibility == "global"
signature = structureSignature ( stat , includePrivate )
elseif stat . kind == "cdefStruct" then
name , kind = stat . name . text , "struct"
public = public or ( published or { } ) [ name ] == true
signature = "cdef struct " .. name
elseif stat . kind == "localStmt" then
if # ( stat . names or { } ) ~= 1 then
return nil
end
name , kind = stat . names [ 1 ] . text , "variable"
signature = ( stat . isConst and "const " or "local " ) .. name
if stat . types [ 1 ] then
signature = signature .. ": " .. syntax ( stat . types [ 1 ] )
end
if typeFunction ( stat . types [ 1 ] ) then
kind = "function"
end
else
return nil
end
if info . tags [ "local" ] then
public = includeAll
end
if info . tags . internal and not includePrivate then
public = false
end
if kind == "method" and privateName ( name ) and not includePrivate then
public = false
end
if not public then
return nil
end
local itemPath = moduleName .. "." .. name
local itemModule = nil
if stat . kind == "typeAlias" or stat . kind == "recordDecl" then
local qualified = declaredName ( stat )
itemModule = qualified : match ( "^(.*)%.[^.]+$" )
end
local moduleTail = moduleName : match ( "([^.]+)$" ) or moduleName
if not itemModule and name : sub ( 1 , # moduleTail + 1 ) == moduleTail .. "." then
itemPath = moduleName .. name : sub ( # moduleTail + 1 )
end
local item = {
name = name ,
kind = kind ,
signature = signature ,
doc = info ,
path = itemPath ,
module = itemModule ,
line = firstToken ( stat ) and firstToken ( stat ) . line or 1 ,
members = { } ,
params = { } ,
returns = { } ,
raises = info . raises ,
typeargs = { } ,
annotations = # applied > 0 and applied or nil ,
}
local declaredFunction = stat . kind == "localStmt" and typeFunction ( stat . types and stat . types [ 1 ] ) or nil
local generics = stat . generics or (
stat . body and stat . body . generics
) or ( declaredFunction and declaredFunction . generics )
for _ , generic in ipairs ( generics and generics . names or { } ) do
item . typeargs [ # item . typeargs + 1 ] = { name = generic . text , text = info . typeargs [ generic . text ] or "" , }
end
if stat . kind == "funcStmt" or stat . kind == "localFuncStmt" or stat . kind == "cdefFunc" then
local details = functionDetails ( stat , info )
item . params , item . returns = details . params , details . returns
elseif declaredFunction then
local details = typeFunctionDetails ( declaredFunction , info )
item . params , item . returns = details . params , details . returns
elseif stat . kind == "recordDecl" or stat . kind == "cdefStruct" then
item . members = buildMembers ( stat . entries , item . path , includePrivate , info . fields )
end

return item
end




local function declaredTypePath ( stat , moduleName )
while stat . kind == "pragmaStmt" and stat . stat do
stat = stat . stat
end
local declaresType = stat . kind == "recordDecl" or stat . kind == "typeAlias" or stat . kind == "cdefStruct"
if not declaresType or not stat . name then
return nil
end

return moduleName .. "." .. stat . name . text
end










local function memberNamed ( item , name )
for _ , member in ipairs ( item . members ) do
if member . name == name then
return member
end
end

return nil
end

local function foldMethods ( items , declaredTypes )
local types = { }
for _ , item in ipairs ( items ) do
if item . kind ~= "function" and item . kind ~= "method" and item . kind ~= "variable" then
types [ item . path ] = item
end
end
local kept = { }
for _ , item in ipairs ( items ) do
local callable = item . kind == "method" or item . kind == "function"
local ownerPath = callable and item . path : match ( "^(.*)[.:][^.:]+$" ) or nil
local owner = ownerPath and types [ ownerPath ] or nil
if not owner and ownerPath and declaredTypes [ ownerPath ] then

elseif owner then
local name = item . name : match ( "([^.:]+)$" ) or item . name
local declared = memberNamed ( owner , name )
if declared then
if declared . text == "" then
declared . text = item . doc . text
end
if # declared . raises == 0 then
declared . raises = item . raises
end
else
owner . members [
# owner . members + 1
] = setmetatable({ name =
name ,  type =
item . signature ,  text =
item . doc . text ,  path =
owner . path .. "." .. name ,  params =
item . params ,  returns =
item . returns ,  raises =
item . raises ,  isFunction =
true ,  annotations =
item . annotations }, extract.Member)

end
else
kept [ # kept + 1 ] = item
end
end

return kept
end

local function moduleName ( path , root , includes )
path , root = normalize ( path ) , normalize ( root )
local relative = path
if root ~= "." and path : sub ( 1 , # root + 1 ) == root .. "/" then
relative = path : sub ( # root + 2 )
end
local best = relative
for _ , include in ipairs ( includes or { } ) do
local prefix = normalize ( join ( root , include ) )
if path : sub ( 1 , # prefix + 1 ) == prefix .. "/" then
local candidate = path : sub ( # prefix + 2 )
if # candidate < # best then
best = candidate
end
end
end
best = best : gsub ( "%.d%.nupp$" , "" ) : gsub ( "%.g%.nupp$" , "" ) : gsub ( "%.nupp$" , "" )
best = best : gsub ( "/init$" , "" ) : gsub ( "/" , "." )

return best
end





local function headerDoc ( root )
local token = firstToken ( root )
for index = 1 , token and token . triviaCount or 0 do
local text = lexer . triviaText ( token , index )
if lexer . triviaKind ( token , index ) ~= "comment" then

elseif text : match ( "^%-%-%[=*%[" ) then
return trim ( ( text : gsub ( "^%-%-%[=*%[" , "" ) : gsub ( "%]=*%]$" , "" ) ) )
else
return nil
end
end

return nil
end

function extract . extract (
source ,
path ,
name ,
opts
)
opts = opts or { }
local parsed = parser . parse ( source , path )
if # parsed . errors > 0 then
return nil , parsed . errors
end
local result = {
name = name ,
path = path ,
text = "" ,
items = { } ,
documentationInternal = parsed . root . documentationInternal ,
}
result . text = headerDoc ( parsed . root ) or ""
local declarationFile = path ~= nil and path : match ( "%.d%.nupp$" ) ~= nil
local extraModules = { }
local declaredTypes = { }
local published = returnedNames ( parsed . root )
for _ , block in ipairs ( parsed . root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
local typePath = declaredTypePath ( stat , name )
if typePath then
declaredTypes [ typePath ] = true
end
local info = parseDoc ( docLines ( stat ) )
if info . tags . module then
result . text = type ( info . tags . module ) == "string" and info . tags . module or info . text
end






local shape = stat . kind == "localStmt" and # (
stat . names or { }
) == 1 and stat . types [ 1 ] and stat . types [ 1 ] . kind == "tshape" and stat . types [ 1 ] or nil
local shapeName = shape and stat . kind == "localStmt" and stat . names [ 1 ] . text or nil
local shapePublic = opts . includeAll or declarationFile or info . tags . export or info . tags . public
if info . tags [ "local" ] then
shapePublic = opts . includeAll
end
if info . tags . internal and not opts . includePrivate then
shapePublic = false
end
if shape and info . tags . namespace and shapePublic then
if not opts . shapesAsModules then
local prefix = info . tags . namespace == true and name or info . tags . namespace
for _ , module in ipairs (
namespaceChildren ( shape , prefix , path , parsed . root . blocks , opts . includePrivate )
) do
extraModules [ # extraModules + 1 ] = module
end
end
elseif shape and opts . shapesAsModules and shapePublic then
for _ , module in ipairs (
globalModules ( shapeName , shape , info . text , path , parsed . root . blocks , opts . includePrivate )
) do
extraModules [ # extraModules + 1 ] = module
end
else
local item = declarationItem (
stat ,
name ,
opts . includeAll ,
declarationFile ,
opts . includePrivate ,
published
)
if item then
result . items [ # result . items + 1 ] = item
end
end
end
end
result . items = foldMethods ( result . items , declaredTypes )
table . sort ( result . items , byKindThenName )

return result , { } , extraModules
end






local function splitMembers ( members )
local fields , methods , types = { } , { } , { }
for _ , member in ipairs ( members or { } ) do
local into = member . isType and types or member . isFunction and methods or fields
into [ # into + 1 ] = member
end

return fields , methods , types
end














function extract . children ( modules , name )
local documented = { }
for _ , module in ipairs ( modules ) do
documented [ module . name ] = true
end
local prefix , children = name .. "." , { }
for _ , module in ipairs ( modules ) do
if module . name : sub ( 1 , # prefix ) == prefix then
local nearest , walked = name , name
for segment in module . name : sub ( # prefix + 1 ) : gmatch ( "[^.]+" ) do
walked = walked .. "." .. segment
if walked ~= module . name and documented [ walked ] then
nearest = walked
end
end
if nearest == name then
children [ # children + 1 ] = module
end
end
end

return children
end













function extract . namespaces ( modules )
local taken = { }
for _ , module in ipairs ( modules ) do
taken [ module . name ] = true
end
local namespaces = { }
for _ , module in ipairs ( modules ) do
local walked = nil
for segment in module . name : gmatch ( "[^.]+" ) do
walked = walked and walked .. "." .. segment or segment
if walked ~= module . name and not taken [ walked ] then
taken [ walked ] = true
namespaces [ # namespaces + 1 ] = { name = walked , text = "" , items = { } , namespace = true }
end
end
end

return namespaces
end

extract . internalModuleName = internalModuleName
extract . moduleName = moduleName
extract . splitMembers = splitMembers

return extract
