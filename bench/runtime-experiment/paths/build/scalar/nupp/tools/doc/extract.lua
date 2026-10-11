_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.doc.extract\0runtime\0001") };










local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local parser = require ( "nupp.compiler.syntax.parser" )
local docblock = require ( "nupp.compiler.syntax.docblock" )
local stringsMod = require ( "nupp.tools.doc.strings" )
local filesMod = require ( "nupp.tools.doc.files" )
local surfaces = require ( "nupp.compiler.check.surfaces" )

local trim = stringsMod . trim
local normalize , join = filesMod . normalize , filesMod . join

local extract = { }






























extract.Member = {} extract.Member.__index = extract.Member ;_G.nupp.__reflect.link(extract.Member,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.syntax.docblock\0runtime\0001","nupp.compiler.syntax.docblock") , __nuppT1[1] })

































































































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
if not line : match ( "^[ \9]*$" ) then
local indent = line : match ( "^[ \9]*" ) or ""
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











local function quotedAt ( text , limit ) 
local quote = nil
local longClose = nil
local escaped = false
local cursor = 1
while cursor < limit do
local char = text : sub ( cursor , cursor )
if longClose then
if text : sub ( cursor , cursor + # longClose - 1 ) == longClose then
cursor = cursor + # longClose - 1
longClose = nil
end
elseif quote then
if escaped then
escaped = false
elseif char == "\\" then
escaped = true
elseif char == quote then
quote = nil
end
elseif char == "'" or char == "\"" then
quote = char
elseif char == "[" then
local equals = text : sub ( cursor ) : match ( "^%[(=*)%[" )
if equals then
longClose = "]" .. equals .. "]"
cursor = cursor + # equals + 1
end
end
cursor = cursor + 1
end

return quote ~= nil or longClose ~= nil
end

local function withoutHiddenTerminals ( text ) 
local pieces = { }
local index = 1
while true do
local start , open = text : find ( "affine[ \9\n]*%(" , index )
if start == nil or open == nil then
do break end
end


local before = start > 1 and text : sub ( start - 1 , start - 1 ) or ""
if before : match ( "[%w_%.:]" ) ~= nil or quotedAt ( text , start ) then
pieces [ # pieces + 1 ] = text : sub ( index , open )
index = open + 1
else
local depth , cursor , comma = 1 , open + 1 , nil
while cursor <= # text and depth > 0 do
local char = text : sub ( cursor , cursor )
if char == "(" or char == "[" or char == "{" then
depth = depth + 1
elseif char == ")" or char == "]" or char == "}" then
depth = depth - 1
elseif char == "," and depth == 1 and comma == nil then
comma = cursor
end
cursor = cursor + 1
end
local closeAt = cursor - 1
local cleanup = comma ~= nil and depth == 0 and trim ( text : sub ( comma + 1 , closeAt - 1 ) ) or ""
if cleanup ~= "" and cleanup : match ( "^[%w_%.:]+$" ) ~= nil and privateName ( cleanup ) then
pieces [ # pieces + 1 ] = text : sub ( index , comma )
pieces [ # pieces + 1 ] = " _"
index = closeAt
else
pieces [ # pieces + 1 ] = text : sub ( index , open )
index = open + 1
end
end
end
pieces [ # pieces + 1 ] = text : sub ( index )

return table . concat ( pieces )
end

local function syntax ( node ) 
return withoutHiddenTerminals ( dedent ( trim ( cst . textOf ( node ) ) ) )
end






local function internalModuleName ( name ) 
return ( "." .. tostring ( name or "" ) .. "." ) : find ( ".internal." , 1 , true ) ~= nil
end






local function hiddenEntry ( entry , includePrivate ) 
if includePrivate then
return false
end
if entry . privacy or entryDoc ( entry ) . tags . internal then
return true
end

return entry . kind ~= "metamethodDecl" and privateName ( entry . name and entry . name . text or "" )
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







local function structureHeader ( stat ) 
local parts = { }
if stat . modifier then
parts [ # parts + 1 ] = stat . modifier . text
end


if stat . sealedTok then
parts [ # parts + 1 ] = stat . sealedTok . text
end
parts [ # parts + 1 ] = stat . declKind or "record"
parts [ # parts + 1 ] = declaredName ( stat ) .. ( stat and stat . generics and syntax ( stat . generics ) or "" )
local supertypes = { }
for _ , supertype in ipairs ( stat . supertypes or { } ) do
supertypes [ # supertypes + 1 ] = syntax ( supertype )
end
if # supertypes > 0 then
parts [ # parts + 1 ] = "is " .. table . concat ( supertypes , ", " )
end
if stat . whereClause then
parts [ # parts + 1 ] = syntax ( stat . whereClause )
end

return table . concat ( parts , " " )
end






local function documentedResultType ( value ) 
if value and value . kind == "tborrows" then
return syntax ( value . type )
end

return syntax ( value )
end






local function declaredResults ( node ) 
local rets = node and node . rets or { }
if # rets == 0 and node and node . returnPack then
return { node . returnPack }
end

return rets
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
for _ , value in ipairs ( declaredResults ( body ) ) do
returns [ # returns + 1 ] = documentedResultType ( value )
end
local prefix
if stat . kind == "localFuncStmt" then
prefix = ( stat . comptimeTok and "@comptime " or "" ) .. ( stat . isConst and "const " or "local " ) .. "function "
else
prefix = ( stat . comptimeTok and "@comptime " or "" ) .. "function "
end






local shownName = name
local first = body and body . params and body . params [ 1 ]
if first and first . name and first . name . text == "self" and first . type then
local owner , method = name : match ( "^(.*)%.([^.]+)$" )
local receiver = syntax ( first . type )
local ownerTail = owner and ( owner : match ( "([^.]+)$" ) or owner ) or nil
local receiverBase = receiver : gsub ( "^const%s+" , "" ) : match ( "^([%w_.]+)" )
if owner and ( receiverBase == owner or receiverBase == ownerTail ) then
shownName = owner .. ":" .. method
end
end
local result = prefix .. shownName .. ( body and body . generics and syntax ( body . generics ) or "" ) .. "(" .. table . concat ( params , ", " ) .. ")"
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
local returns = stat . body and declaredResults ( stat . body ) or ( stat . ret and { stat . ret } or { } )
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




local function rotatedFunctionText ( fn ) 
local params = fn . params or { }
if # params < 2 then
return trim ( cst . textOf ( fn ) )
end
local text = cst . textOf ( fn )
local pieces = { trim ( cst . textOf ( params [ 1 ] ) ) }
for index = 3 , # params do
pieces [ # pieces + 1 ] = trim ( cst . textOf ( params [ index ] ) )
end
pieces [ # pieces + 1 ] = trim ( cst . textOf ( params [ 2 ] ) )
local first = text : find ( trim ( cst . textOf ( params [ 1 ] ) ) , 1 , true )
local _ , lastEnd = text : find ( trim ( cst . textOf ( params [ # params ] ) ) , first , true )
local close = text : find ( ")" , ( lastEnd ) + 1 , true )
local head = trim ( text : sub ( 1 , first - 1 ) )

return head .. table . concat ( pieces , ", " ) .. text : sub ( close )
end

local function rotatedTypeText ( node ) 
local overloads = node . kind == "tintersection" and node . types or { node }
local rendered = { }
for index , fn in ipairs ( overloads ) do
rendered [ index ] = rotatedFunctionText ( fn )
end

return withoutHiddenTerminals ( table . concat ( rendered , " & " ) )
end

local function rotatedParams ( params ) 
if # params < 2 then
return params
end
local order = { params [ 1 ] }
for index = 3 , # params do
order [ # order + 1 ] = params [ index ]
end
order [ # order + 1 ] = params [ 2 ]

return order
end




local function isComptime ( node ) 
if node and node . comptimeOnly then
return true
end
for _ , application in ipairs ( node and node . typeAnnotations or { } ) do
if application . name and application . name . text == "comptime" then
return true
end
end

return false
end

local function comptimeKind ( node ) 
local fn = typeFunction ( node )
if fn then
for _ , overload in ipairs ( node . kind == "tintersection" and node . types or { node } ) do
if not isComptime ( overload ) then
return nil
end
end
return "function"
end
if isComptime ( node ) then
return "type"
end

return nil
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
for index , value in ipairs ( declaredResults ( node ) ) do
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
comptimeKind = comptimeKind ( field . type ) ,
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
if not includePrivate and ( ( "." .. tostring ( name or "" ) .. "." ) : find ( ".internal." , 1 , true ) ~= nil ) then
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
local member = _G.setmetatable({ name =
entry . name . text ,  type =
syntax ( entry . type ) ,  text =
fieldInfo . text ~= "" and fieldInfo . text
or ( fieldTextOverrides and fieldTextOverrides [ entry . name . text ] )
or "" ,  path =
basePath .. "." .. entry . name . text ,  params =
{ } ,  returns =
{ } ,  raises =
fieldInfo . raises ,  annotations =
annotationsOf ( entry ) ,  comptimeKind =
comptimeKind ( entry . type ) }, extract.Member)

local fieldFunction = typeFunction ( entry . type )
if fieldFunction then
local details = typeFunctionDetails ( fieldFunction , fieldInfo )
member . params , member . returns = details . params , details . returns
member . isFunction = true
local ownerModule , nominal = basePath : match ( "^(.*)%.([^.]+)$" )
if ownerModule and surfaces . rotates ( ownerModule , nominal , entry . name . text ) then
member . type = rotatedTypeText ( entry . type )
member . params = rotatedParams ( member . params )
end
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
] = _G.setmetatable({ name =
entry . name . text ,  type =
functionSignature ( entry , entry . name . text ) ,  text =
methodInfo . text ,  path =
basePath .. "." .. entry . name . text ,  params =
details . params ,  returns =
details . returns ,  raises =
methodInfo . raises ,  isFunction =
true ,  annotations =
annotationsOf ( entry ) }, extract.Member)

elseif entry . kind == "constructorDecl" and entryVisible then



local constructorInfo = entryInfo
local details = functionDetails ( entry , constructorInfo )
members [
# members + 1
] = _G.setmetatable({ name =
"constructor" ,  type =
functionSignature ( entry , "constructor" ) ,  text =
constructorInfo . text ,  path =
basePath .. ".constructor" ,  params =
details . params ,  returns =
details . returns ,  raises =
constructorInfo . raises ,  isFunction =
true ,  annotations =
annotationsOf ( entry ) }, extract.Member)

elseif entry . kind == "recordDecl" and entryVisible then
local nestedPath = basePath .. "." .. entry . name . text
members [
# members + 1
] = _G.setmetatable({ name =
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

elseif entry . kind == "typeAlias" and entryVisible then




members [
# members + 1
] = _G.setmetatable({ name =
entry . name . text ,  type =
syntax ( entry . value ) ,  text =
entryInfo . text ,  path =
basePath .. "." .. entry . name . text ,  params =
{ } ,  returns =
{ } ,  raises =
{ } ,  isAlias =
true ,  generics =
( entry and entry . generics and syntax ( entry . generics ) or "" ) ~= "" and ( entry and entry . generics and syntax ( entry . generics ) or "" ) or nil ,  annotations =
annotationsOf ( entry ) }, extract.Member)

elseif entry . name and entryVisible then
members [
# members + 1
] = _G.setmetatable({ name =
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












local function publishedTables ( root , moduleLocal ) 
local tables = { }
if moduleLocal == nil then
return tables
end
for _ , block in ipairs ( root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "assignStmt" then
for index , target in ipairs ( stat . targets or { } ) do
local value = stat . exprs and stat . exprs [ index ]
if value
and value . kind == "name"
and value . token
and syntax ( target ) : match ( "^" .. moduleLocal .. "%.[%w_]+$" ) then
tables [ value . token . text ] = true
end
end
end
end
end

return tables
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
elseif stat . kind == "exportStmt" and stat . value and stat . value . kind == "tableExpr" then
for _ , field in ipairs ( stat . value . fields or { } ) do
record ( field . value )
end
end
end
end

return names
end





declarationItem = function ( stat , moduleName , everyDeclaration , declarationFile , includePrivate , published ) 
local documented = stat
local applied = { }
while stat . kind == "pragmaStmt" and stat . stat do
local text = annotationText ( stat )
if text then
applied [ # applied + 1 ] = text
end
stat = stat . stat
end
local explicitlyExported = stat . kind == "exportStmt" and stat . stat ~= nil
if explicitlyExported then
stat = stat . stat
end
local lines = docLines ( documented )
local info = parseDoc ( lines )
local public = everyDeclaration or declarationFile or explicitlyExported or info . tags . export or info . tags . public
local kind , name , signature , itemComptimeKind
if stat . kind == "funcStmt" or stat . kind == "localFuncStmt" then
name = stat . kind == "funcStmt" and syntax ( stat . name ) or stat . name . text
public = public or stat . kind == "funcStmt"
kind = stat . name and stat . name . method and "method" or "function"
signature = functionSignature ( stat , name )
itemComptimeKind = stat . comptimeTok and "function" or nil
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
signature = structureHeader ( stat )
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
itemComptimeKind = comptimeKind ( stat . types [ 1 ] )
else
return nil
end
if info . tags [ "local" ] then
public = everyDeclaration
end
if info . tags . internal and not includePrivate then
public = false
end




if privateName ( name ) and not includePrivate then
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
aliasSource = stat . kind == "localStmt" and stat . exprs and stat . exprs [ 1 ] and syntax ( stat . exprs [ 1 ] ) or nil ,
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
comptimeKind = itemComptimeKind ,
}
local declaredFunction = stat . kind == "localStmt" and typeFunction ( stat . types and stat . types [ 1 ] ) or nil
local generics = stat . generics
or ( stat . body and stat . body . generics )
or ( declaredFunction and declaredFunction . generics )
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



if item . path == "nupp.spi.load" and # item . params == 1 and # item . returns == 1 then
item . signature = "load(Interface): function(): Interface?"
item . typeargs = { }
item . params [ 1 ] . name = "Interface"
item . params [ 1 ] . type = "interface declaration"
item . returns [ 1 ] . type = "function(): Interface?"
end

return item
end




local function declaredTypePath ( stat , moduleName ) 
while stat . kind == "pragmaStmt" and stat . stat do
stat = stat . stat
end
if stat . kind == "exportStmt" and stat . stat then
stat = stat . stat
end
local declaresType = stat . kind == "recordDecl" or stat . kind == "typeAlias" or stat . kind == "cdefStruct"
if not declaresType or not stat . name then
return nil
end

return moduleName .. "." .. stat . name . text
end




















local function unreachableOwner (
name ,
moduleName ,
moduleLocal ,
publishedTables
) 
local qualifiers = name : match ( "^(.*)[.:][^.:]+$" )
if qualifiers == nil then
return false
end
local head = qualifiers : match ( "^([^.:]+)" ) or qualifiers

return head ~= moduleLocal and head ~= ( moduleName : match ( "([^.]+)$" ) or moduleName ) and not publishedTables [ head ]
end

local function memberNamed ( item , name ) 
for _ , member in ipairs ( item . members ) do
if member . name == name then
return member
end
end

return nil
end

local function foldMethods (
items ,
declaredTypes ,
hiddenMembers ,
moduleName ,
moduleLocal ,
publishedTables
) 
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
local memberName = item . name : match ( "([^.:]+)$" ) or item . name
if ownerPath and hiddenMembers [ ownerPath .. "." .. memberName ] then

elseif not owner and ownerPath and declaredTypes [ ownerPath ] then

elseif callable and unreachableOwner ( item . name , moduleName , moduleLocal , publishedTables ) then


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
] = _G.setmetatable({ name =
name ,  type =
item . signature ,  text =
item . doc . text ,  path =
owner . path .. "." .. name ,  params =
item . params ,  returns =
item . returns ,  raises =
item . raises ,  isFunction =
true ,  annotations =
item . annotations ,  comptimeKind =
item . comptimeKind }, extract.Member)

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





local function headerDoc ( root , tokens ) 
local token = firstToken ( root )
local _ , moduleNode = cst . declaredModule ( root )
if moduleNode then
local following = nil
local found = false
for _ , block in ipairs ( root . blocks or { } ) do
for index , stat in ipairs ( block . stats or { } ) do
if stat == moduleNode then
following = block . stats [ index + 1 ]
found = true
do break end
end
end
if found then
do break end
end
end
if following then
token = firstToken ( following )
elseif found and tokens and # tokens > 0 then



token = tokens [ # tokens ]
end
end
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
imports = { } ,
moduleLocal = cst . exportedLocal ( parsed . root ) or cst . returnedLocal ( parsed . root ) ,
importedMembers = { } ,
}
for _ , block in ipairs ( parsed . root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "localStmt" and stat . pattern and stat . patternSource then



local source = stat . patternSource
local args = source . kind == "call"
and source . obj
and source . obj . kind == "name"
and source . obj . token
and source . obj . token . text == "require"
and ( source . args )
or nil
local argument = args and args . exprs and args . exprs [ 1 ]
local literal = argument and argument . kind == "string" and argument . token and argument . token . text or nil
local imported = literal and ( literal : match ( "^\"(.*)\"$" ) or literal : match ( "^'(.*)'$" ) ) or nil
for _ , entry in ipairs ( imported and stat . pattern or { } ) do
local from = entry . sourceName and entry . sourceName . text
local bound = entry . alias and entry . alias . text or from
if from and bound then
result . imports [ bound ] = imported
result . importedMembers [ bound ] = from
end
end
elseif stat . kind == "localStmt" then
for index , binding in ipairs ( stat . names or { } ) do
local value = stat . exprs and stat . exprs [ index ]
if value
and value . kind == "call"
and value . obj
and value . obj . kind == "name"
and value . obj . token
and value . obj . token . text == "require"
then
local args = value . args
local argument = args and args . exprs and args . exprs [ 1 ]
if argument and argument . kind == "string" and argument . token then
local literal = argument . token . text
local imported = literal : match ( "^\"(.*)\"$" ) or literal : match ( "^'(.*)'$" )
if imported then
result . imports [ binding . text ] = imported
end
end
end
end
end
end
end
result . text = headerDoc ( parsed . root , parsed . tokens ) or ""
local declarationFile = path ~= nil and path : match ( "%.d%.nupp$" ) ~= nil
local extraModules = { }
local declaredTypes = { }
local hiddenMembers = { }
local published = returnedNames ( parsed . root )
for _ , block in ipairs ( parsed . root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
local typePath = declaredTypePath ( stat , name )
if typePath then
declaredTypes [ typePath ] = true
local declaration = stat
while declaration . kind == "pragmaStmt" or declaration . kind == "exportStmt" do
declaration = declaration . stat
end
for _ , entry in ipairs ( declaration . entries or { } ) do
if entry . name and hiddenEntry ( entry , opts . includePrivate ) then
hiddenMembers [ typePath .. "." .. entry . name . text ] = true
end
end
end
local info = parseDoc ( docLines ( stat ) )
if info . tags . module then
result . text = type ( info . tags . module ) == "string" and info . tags . module or info . text
end






local shape = stat . kind == "localStmt"
and # ( stat . names or { } ) == 1
and stat . types [ 1 ]
and stat . types [ 1 ] . kind == "tshape"
and stat . types [ 1 ]
or nil
local shapeName = shape and stat . kind == "localStmt" and stat . names [ 1 ] . text or nil
local shapePublic = opts . includePrivate or declarationFile or info . tags . export or info . tags . public
if info . tags [ "local" ] then
shapePublic = opts . includePrivate
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
opts . includePrivate ,
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
result . items = foldMethods (
result . items ,
declaredTypes ,
hiddenMembers ,
name ,
result . moduleLocal ,
publishedTables ( parsed . root , result . moduleLocal )
)
table . sort ( result . items , byKindThenName )

return result , { } , extraModules
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

local __nuppExportValue= extract ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.extract"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.extract"]=__nuppExports;return __nuppExports