_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);













local cst = require ( "nupp.compiler.cst" )
local lexer = require ( "nupp.compiler.lexer" )
local T = require ( "nupp.compiler.types" )
local text = require ( "nupp.compiler.lsp.text" )
local tree = require ( "nupp.compiler.lsp.tree" )
local complete = require ( "nupp.compiler.lsp.complete" )
local wire = require ( "nupp.compiler.lsp.wire" )

local uriToPath , pathToUri = text . uriToPath , text . pathToUri
local positionAtOffset , offsetAtPosition = text . positionAtOffset , text . offsetAtPosition
local tokenRange , readFile = text . tokenRange , text . readFile
local findDeclaration , tokenAt = tree . findDeclaration , tree . tokenAt
local symbolKey , memberOccurrences = tree . symbolKey , tree . memberOccurrences
local moduleMemberAt , documentationAt = tree . moduleMemberAt , tree . documentationAt
local fromTrivia , functionSignature = tree . fromTrivia , tree . functionSignature
local documentationOf = tree . documentationOf
local membersOf = complete . membersOf

local json = wire . json

local navigate = { }






































































function navigate . install ( s )

local function fileTokens ( filename , source )
local entry = s . lexed [ filename ]
if entry and entry . source == source then
return entry . tokens
end
local tokens = lexer . lex ( source )
s . lexed [ filename ] = { source = source , tokens = tokens }

return tokens
end



local function sourceForPath ( path )
for uri , doc in pairs ( s . documents ) do
if uriToPath ( uri ) == path then
return doc . text
end
end

return readFile ( path )
end

local function definitionSource ( def )
return sourceForPath ( def . filename )
end



local function declarationIndex ( def , source , tokens )
local tok = def . token
if not tok or not tok . text then
return nil
end
local found
if source : sub ( tok . offset , tok . offset + # tok . text - 1 ) == tok . text then
found = tok . offset
else
local relocated = findDeclaration ( tokens , tok . text , tok . offset )
if not relocated then
return nil
end
found = relocated . offset
end
for index , candidate in ipairs ( tokens ) do
if candidate . offset == found then
return index
end
end

return nil
end

local function resolveDefinition ( def )
if not def or not def . token or not def . filename then
return nil
end
if def . generatedBy and def . generatedOrigin then
def = {
token = def . generatedOrigin ,
filename = def . generatedOrigin . filename or def . filename ,
documentationToken = def . documentationToken ,
}
end
local source = definitionSource ( def )
if not source then
return nil
end
local tokens = fileTokens ( def . filename , source )
local index = declarationIndex ( def , source , tokens )
if not index then
return nil
end

return source , tokens , index
end

local function definitionLocation ( def )
local source , tokens , index = resolveDefinition ( def )
if not source then
return json . null
end
local tok = tokens [ index ]

return {
uri = pathToUri ( def . filename ) ,
range = {
start = positionAtOffset ( source , tok . offset ) ,
[ "end" ] = positionAtOffset ( source , tok . offset + # tok . text ) ,
} ,
}
end

local function documentationFor ( def )
local _ , tokens , index = resolveDefinition ( def )
if not tokens then
if not def then
return nil
end
if def . documentationToken then
return documentationOf ( def . documentationToken )
end

return def . token and fromTrivia ( def . token . trivia )
end

return documentationAt ( tokens , index ) or documentationOf ( def . documentationToken )
end

local function documentAt ( params )
local uri = params and params . textDocument and params . textDocument . uri
return uri , uri and s . documents [ uri ] or nil
end

local function symbolAt ( params )
local uri , doc = documentAt ( params )
if not doc or not doc . result or not params . position then
return uri , doc , nil , nil
end
local offset = offsetAtPosition ( doc . text , params . position )

return uri , doc , offset and tokenAt ( doc . result , offset ) or nil , offset
end

local function isOpenDefinition ( def )
if not def or not def . filename then
return false
end
for uri in pairs ( s . documents ) do
if uriToPath ( uri ) == def . filename then
return true
end
end

return false
end





local function isProjectDefinition ( def )
if not def or not def . filename then
return false
end







if def . associated or def . generatedBy then
return false
end
if isOpenDefinition ( def ) then
return true
end
for _ , path in ipairs ( s . inc . projectFiles ( ) ) do
if path == def . filename then
return true
end
end

return false
end









local function documentsMentioning ( name )
local out , seen = { } , { }
for uri , doc in pairs ( s . documents ) do
seen [ uriToPath ( uri ) ] = true
if doc . result and doc . text : find ( name , 1 , true ) then
out [ # out + 1 ] = { uri = uri , source = doc . text , result = doc . result }
end
end
for _ , path in ipairs ( s . inc . projectFiles ( ) ) do
if not seen [ path ] then
local source = s . inc . fileText ( path )
if source and source : find ( name , 1 , true ) then
local checked = s . inc . checkFile ( path )
if checked and checked . result then
out [ # out + 1 ] = { uri = pathToUri ( path ) , source = source , result = checked . result }
end
end
end
end

return out
end

local function referencesFor ( def , includeDeclaration )
local wanted = symbolKey ( def )
local locations = wire . array ( { } )
if not wanted or not def . token then
return locations
end
local seen = { }
local spelling = def . generatedBy and def . name or def . token . text
for _ , entry in ipairs ( documentsMentioning ( spelling ) ) do
local declaring = uriToPath ( entry . uri ) == def . filename
for _ , tok in ipairs ( entry . result . tokens or { } ) do



local isDeclaration = declaring and tok . offset == def . token . offset
if symbolKey ( tok . definition ) == wanted and ( includeDeclaration or not isDeclaration ) then
local key = entry . uri .. ":" .. tostring ( tok . offset )
if not seen [ key ] then
seen [ key ] = true
locations [ # locations + 1 ] = { uri = entry . uri , range = tokenRange ( entry . source , tok ) , }
end
end
end
end
if includeDeclaration then
local location = definitionLocation ( def )
if location ~= json . null then
local key = location . uri .. ":" .. tostring ( def . token . offset )
if not seen [ key ] then
locations [ # locations + 1 ] = location
end
end
end
table . sort ( locations , function ( a , b )
if a . uri ~= b . uri then
return a . uri < b . uri
end
local ap , bp = a . range . start , b . range . start

return ap . line < bp . line or ( ap . line == bp . line and ap . character < bp . character )
end )

return locations
end











local function memberDeclaration ( moduleName , memberName )
local path = s . inc . modulePath ( moduleName )
if not path then
return nil
end
local checked = s . inc . checkFile ( path )
local result = checked and checked . result
if not result then
return nil
end
for _ , hit in ipairs ( memberOccurrences ( result , moduleName , memberName ) ) do
if hit . stat then
return path , hit . token , hit . stat
end
end

return nil
end



local function memberAt ( doc , offset )
if not doc or not doc . result or not offset then
return nil
end
local member = moduleMemberAt ( doc . result , offset )
if not member then
return nil
end
if not memberDeclaration ( member . moduleName , member . name ) then
return nil
end

return member
end

local function memberLocation ( member )
local path , tok = memberDeclaration ( member . moduleName , member . name )
if not path then
return json . null
end
local source = sourceForPath ( path )
if not source then
return json . null
end

return {
uri = pathToUri ( path ) ,
range = {
start = positionAtOffset ( source , tok . offset ) ,
[ "end" ] = positionAtOffset ( source , tok . offset + # tok . text ) ,
} ,
}
end

local function memberReferences ( member , includeDeclaration )
local locations = wire . array ( { } )
local seen = { }
for _ , entry in ipairs ( documentsMentioning ( member . name ) ) do
local hits = memberOccurrences ( entry . result , member . moduleName , member . name )
for _ , hit in ipairs ( hits ) do
local key = entry . uri .. ":" .. tostring ( hit . token . offset )
if ( includeDeclaration or not hit . stat ) and not seen [ key ] then
seen [ key ] = true
locations [ # locations + 1 ] = { uri = entry . uri , range = tokenRange ( entry . source , hit . token ) , }
end
end
end
table . sort ( locations , function ( a , b )
if a . uri ~= b . uri then
return a . uri < b . uri
end
local ap , bp = a . range . start , b . range . start

return ap . line < bp . line or ( ap . line == bp . line and ap . character < bp . character )
end )

return locations
end




local function memberHover ( member )
local path , tok , stat = memberDeclaration ( member . moduleName , member . name )
if not path then
return nil
end
local value = "```nupp\n" .. functionSignature ( stat ) .. "\n```"
local source = sourceForPath ( path )
if source then
local tokens = fileTokens ( path , source )
for index , candidate in ipairs ( tokens ) do
if candidate . offset == tok . offset then
local docs = documentationAt ( tokens , index )
if docs then
value = value .. "\n\n" .. docs
end
break
end
end
end

return value
end





local function resolveReceiver ( checked , path )
if not checked then
return nil
end
if path [ 1 ] == "ffi" and path [ 2 ] == "C" then
local t = checked . cNamespaceType
for index = 3 , # path do
local member = t and membersOf ( t ) [ path [ index ] ]
t = member and member . type or nil
if not t then
return nil
end
end

return t
end
local base = nil
for _ , def in ipairs ( checked . symbols or { } ) do
if def . name == path [ 1 ] and ( def . type or def . requiredModule ) then
base = def
break
end
end
if not base then
return nil
end
local moduleName = base . requiredModule
if not moduleName and checked . moduleLocal == path [ 1 ] then
moduleName = checked . moduleName
end
local t = base . type
for index = 2 , # path do


if moduleName and index == 2 then
return nil , nil
end
local member = t and membersOf ( t ) [ path [ index ] ]
t = member and member . type or nil
if not t then
return nil , nil
end
end
if # path > 1 then
moduleName = nil
end

return t , moduleName
end

return {
fileTokens = fileTokens ,
sourceForPath = sourceForPath ,
definitionSource = definitionSource ,
declarationIndex = declarationIndex ,
resolveDefinition = resolveDefinition ,
definitionLocation = definitionLocation ,
documentationFor = documentationFor ,
documentAt = documentAt ,
symbolAt = symbolAt ,
isOpenDefinition = isOpenDefinition ,
isProjectDefinition = isProjectDefinition ,
documentsMentioning = documentsMentioning ,
referencesFor = referencesFor ,
memberDeclaration = memberDeclaration ,
memberAt = memberAt ,
memberLocation = memberLocation ,
memberReferences = memberReferences ,
memberHover = memberHover ,
resolveReceiver = resolveReceiver ,
}
end

return navigate
