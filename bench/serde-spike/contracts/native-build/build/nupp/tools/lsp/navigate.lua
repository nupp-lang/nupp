_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()















local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local T = require ( "nupp.compiler.types" )
local text = require ( "nupp.tools.lsp.text" )
local tree = require ( "nupp.tools.lsp.tree" )
local complete = require ( "nupp.tools.lsp.complete" )
local wire = require ( "nupp.tools.lsp.wire" )

local uriToPath , pathToUri = text . uriToPath , text . pathToUri
local offsetAtPosition = text . offsetAtPosition
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
return json . NULL
end
local tok = tokens [ index ]

return { uri = pathToUri ( def . filename ) , range = tokenRange ( source , tok ) , }
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
if location ~= json . NULL then
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
return json . NULL
end
local source = sourceForPath ( path )
if not source then
return json . NULL
end

return { uri = pathToUri ( path ) , range = tokenRange ( source , tok ) , }
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






local function memberDocumentation ( path , tok ) 
if not tok then
return nil
end
local source = sourceForPath ( path )
if not source then
return nil
end
local tokens = fileTokens ( path , source )
for index , candidate in ipairs ( tokens ) do
if candidate . offset == tok . offset then
return documentationAt ( tokens , index )
end
end

return nil
end

local function memberHover ( member ) 
local path , tok , stat = memberDeclaration ( member . moduleName , member . name )
if not path then
return nil
end
local value = "```nupp\n" .. functionSignature ( stat ) .. "\n```"
local docs = memberDocumentation ( path , tok )
if docs then
value = value .. "\n\n" .. docs
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
do break end
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
memberDocumentation = memberDocumentation ,
memberAt = memberAt ,
memberLocation = memberLocation ,
memberReferences = memberReferences ,
memberHover = memberHover ,
resolveReceiver = resolveReceiver ,
}
end

local __nuppExportValue= navigate ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.lsp.navigate"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.lsp.navigate"]=__nuppExports;return __nuppExports