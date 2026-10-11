_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0005") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0006") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0007") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0008") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\0009") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\00010") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\00011") , _G.nupp.__reflect.declaration("nupp.tools.cli.lsp\0runtime\00012") };















local json = require ( "nupp.codec.json" )
local fs = require ( "nupp.compiler.fs" )
local cliModule = require ( "nupp.cli" )














































local function jsonArray ( items ) 
return json . asArray ( items )
end

local normalizePath = fs . normalize

local function absolutePath ( path ) 
return path : match ( "^/" ) or path : match ( "^[A-Za-z]:[/\\]" )
end

local function resolvePath ( root , path ) 
if ( path : match ( "^/" ) or path : match ( "^[A-Za-z]:[/\\]" ) ) or root == "." or root == "" then
return normalizePath ( path )
end
return normalizePath ( root .. "/" .. path )
end

local function displayPath ( root , path ) 
root , path = normalizePath ( root ) , normalizePath ( path )
if root ~= "." and root ~= "" and path : sub ( 1 , # root + 1 ) == root .. "/" then
return path : sub ( # root + 2 )
end

return path
end



local text = require ( "nupp.tools.lsp.text" )
local pathToUri , utf8Char = text . pathToUri , text . utf8Char

local function uriToPath ( uri ) 
local path = text . uriToPath ( uri )

local share = path : match ( "^//[^/]" ) and "/" or ""

return share .. normalizePath ( path )
end

local function lineStart ( source , wanted ) 
local line , offset = 1 , 1
while line < wanted do
local newline = source : find ( "\n" , offset , true )
if not newline then
return nil
end
offset , line = newline + 1 , line + 1
end

return offset
end


local function toLspPosition ( source , line , column ) 
local start = lineStart ( source , line )
if not start then
return nil , "line is past the end of the file"
end
local finish = source : find ( "\n" , start , true ) or ( # source + 1 )
local target = start + column - 1
if target < start or target > finish then
return nil , "column is past the end of the line"
end
local offset , units = start , 0
while offset < target do
local bytes , width = utf8Char ( source , offset )
if offset + bytes > target then
return nil , "column is inside a UTF-8 character"
end
offset , units = offset + bytes , units + width
end

return { line = line - 1 , character = units }
end


local function fromLspPosition ( source , position ) 
local line = ( position . line or 0 ) + 1
local start = lineStart ( source , line ) or ( # source + 1 )
local offset , units = start , 0
local wanted = position . character or 0
while offset <= # source and source : byte ( offset ) ~= 10 and units < wanted do
local bytes , width = utf8Char ( source , offset )
offset , units = offset + bytes , units + width
end

return { line = line , column = offset - start + 1 , offset = offset }
end







local reportMod = require ( "nupp.tools.cli.report" )


local SYMBOL = {
type = "object" ,
properties = {
name = { type = "string" } ,
kind = { type = "string" , description = "The LSP symbol kind, spelled as a word." } ,
type = { type = "string" } ,
associated = {
type = "string" ,
description = "For an associated type projection, what state it is in beside the source form: what it resolves to, the bound it is opaque at, gradual, or cyclic."
,
} ,
detail = { type = "string" } ,
documentation = { type = "string" } ,
container = { type = "string" } ,
definition = reportMod . LOCATION ,
location = reportMod . LOCATION ,
range = reportMod . RANGE ,
children = { type = "array" , items = { [ "$ref" ] = "#/definitions/symbol" } } ,
automaticCleanup = {
type = "object" ,
properties = {
line = { type = "integer" } ,
column = { type = "integer" } ,
cleanups = { type = "array" , items = { type = "string" } } ,
status = { type = "string" } ,
} ,
} ,
} ,
}

local EDIT = {
type = "object" ,
properties = { file = { type = "string" } , range = reportMod . RANGE , newText = { type = "string" } } ,
required = { "file" , "range" , "newText" } ,
}

local OPERATION_SCHEMAS

= {
inspect = {
type = "object" ,
description = "The symbol at the position, or null where there is nothing to describe." ,
properties = { symbol = { [ "$ref" ] = "#/definitions/symbol" } } ,
definitions = { symbol = SYMBOL } ,
} ,
definition = {
type = "object" ,
properties = {
definition = reportMod . LOCATION ,
definitions = {
type = "array" ,
items = reportMod . LOCATION ,
description = "Every declaration that contributes, when more than one does." ,
} ,
} ,
} ,
implementation = {
type = "object" ,
properties = { implementations = { type = "array" , items = reportMod . LOCATION } } ,
required = { "implementations" } ,
} ,
references = {
type = "object" ,
properties = {
declarationIncluded = { type = "boolean" } ,
references = { type = "array" , items = reportMod . LOCATION } ,
} ,
required = { "declarationIncluded" , "references" } ,
} ,
symbols = {
type = "object" ,
properties = { symbols = { type = "array" , items = { [ "$ref" ] = "#/definitions/symbol" } } } ,
required = { "symbols" } ,
definitions = { symbol = SYMBOL } ,
} ,
rename = {
type = "object" ,
properties = {
oldName = { type = "string" } ,
newName = { type = "string" } ,
written = { type = "boolean" , description = "False for a preview, which is the default." } ,
edits = { type = "array" , items = EDIT } ,
} ,
required = { "newName" , "written" , "edits" } ,
} ,
actions = {
type = "object" ,
properties = {
actions = {
type = "array" ,
items = {
type = "object" ,
properties = {
kind = { type = "string" } ,
title = { type = "string" } ,
diagnostic = {
type = "object" ,
properties = { code = { type = "string" } , message = { type = "string" } }
} ,
edits = { type = "array" , items = EDIT } ,
} ,
required = { "title" , "edits" } ,
} ,
} ,
} ,
required = { "actions" } ,
} ,
[
"trace-check"
] = {
type = "object" ,
properties = {
functionName = { type = "string" } ,
contract = { type = "string" } ,
range = reportMod . RANGE ,
findings = {
type = "array" ,
items = {
type = "object" ,
properties = {
reason = { type = "string" } ,
class = { type = "string" } ,
message = { type = "string" } ,
help = { type = "string" } ,
callPath = { type = "array" , items = { type = "string" } } ,
range = reportMod . RANGE ,
} ,
required = { "reason" , "class" } ,
} ,
} ,
traceProfile = { type = "object" } ,
reasonCatalog = { type = "object" } ,
addContract = { type = "object" , properties = { range = reportMod . RANGE , newText = { type = "string" } } , } ,
} ,
required = { "findings" } ,
} ,
artifacts = {
type = "object" ,
description = "What could be resolved here, without resolving any of it." ,
properties = {
artifacts = {
type = "array" ,
items = {
type = "object" ,
properties = {
kind = { type = "string" , enum = { "lua" , "bytecode" } } ,
label = { type = "string" } ,
languageId = { type = "string" } ,
scope = {
type = "string" ,
enum = { "module" , "function" } ,
description = "Whether resolving this kind answers for the file or for one body." ,
} ,
} ,
required = { "kind" , "label" , "scope" } ,
} ,
} ,
[
"function"
] = {
type = "object" ,
description = "The innermost function the position is in, absent outside one." ,
properties = {
name = { type = "string" } ,
aotSymbol = {
type = "string" ,
description = "Logical AOT kernel symbol, before static archive qualification or tier suffixes."
} ,
aotSource = { type = "string" } ,
range = reportMod . RANGE
} ,
} ,
} ,
required = { "artifacts" } ,
} ,
artifact = {
type = "object" ,
description = "One compiled artifact, or why there is not one." ,
properties = {
id = { type = "string" } ,
kind = { type = "string" } ,
available = { type = "boolean" } ,
label = { type = "string" } ,
languageId = { type = "string" } ,
text = { type = "string" } ,
mapping = {
type = "object" ,
description = "How generated positions relate to source positions." ,
properties = {
kind = {
type = "string" ,
enum = { "line-identity" , "lines" , "lines-collapsible" } ,
description = "`line-identity` means generated line N is source line N for every N, which is what the Lua emitter guarantees. `lines` carries one entry per generated line that stands for source. `lines-collapsible` is the same, laid out so that folding every indented run leaves one row per source line."



,
} ,
entries = {
type = "array" ,
items = {
type = "object" ,
properties = {
generatedLine = { type = "integer" } ,
sourceLine = { type = "integer" } ,
role = { type = "string" , enum = { "exact" , "source" , "derived" , "synthetic" } } ,
} ,
required = { "generatedLine" , "sourceLine" , "role" } ,
} ,
} ,
} ,
required = { "kind" } ,
} ,
metadata = { type = "object" } ,
summary = { type = "object" } ,
unavailable = {
type = "object" ,
properties = { reason = { type = "string" } , detail = { type = "string" } } ,
required = { "reason" } ,
} ,
problem = {
type = "object" ,
description = "Set when the artifact is available but is not a working program: generated Lua that does not load, handed over so the reason can be read in it."
,
properties = { reason = { type = "string" } , detail = { type = "string" } } ,
required = { "reason" } ,
} ,
} ,
required = { "kind" , "available" } ,
} ,
}



for _ , schema in pairs ( OPERATION_SCHEMAS ) do
schema . properties . ok = reportMod . OK
schema . properties . diagnostics = reportMod . DIAGNOSTICS
local required = { "ok" }
for _ , name in ipairs ( schema . required or { } ) do
required [ # required + 1 ] = name
end
schema . required = required
end





local function newClient ( root ) 
local emitted = { }
local sources = { }
local session = require ( "nupp.tools.lsp" ) . newSession ( root , function ( message ) 
emitted [ # emitted + 1 ] = message
end )
local nextId = 0

local function request ( method , params ) 
nextId = nextId + 1
local id = nextId
session . dispatch ( { jsonrpc = "2.0" , id = id , method = method , params = params } )
for index = # emitted , 1 , -1 do
local message = emitted [ index ]
if message . id == id then
if message . error then
return nil , message . error . message
end
return message . result
end
end

return nil , "language service did not answer " .. method
end

local function notify ( method , params ) 
session . dispatch ( { jsonrpc = "2.0" , method = method , params = params } )
end

local _ , initErr = request ( "initialize" , { } )
if initErr then
return nil , initErr
end
notify ( "initialized" , { } )

local function source ( path ) 
path = normalizePath ( path )
if sources [ path ] then
return sources [ path ]
end
local text , err = fs . readFile ( path )
if not text then

return nil , { code = "NUPP0001" , message = tostring ( err ) , file = path }
end
sources [ path ] = text

return text
end

local function open ( path ) 
path = normalizePath ( path )
local text , err = source ( path )
if not text then
return nil , err
end
notify ( "textDocument/didOpen" , {
textDocument = { uri = pathToUri ( path ) , languageId = "nupp" , version = 1 , text = text , }
} )

return text
end

return { request = request , notify = notify , open = open , source = source , root = root , sources = sources }
end

local function rangeValue ( client , path , range ) 
local source = client . source ( path ) or ""
return { start = fromLspPosition ( source , range . start ) , [ "end" ] = fromLspPosition ( source , range [ "end" ] ) , }
end

local function locationValue ( client , location ) 
if not location or location == json . NULL then
return nil
end
local path = uriToPath ( location . uri )

return { file = displayPath ( client . root , path ) , range = rangeValue ( client , path , location . range ) }
end

local function positionParams ( path , position ) 
return { textDocument = { uri = pathToUri ( path ) } , position = position }
end

local function locationText ( location ) 
if not location then
return ""
end
local start = location . range . start

return ("%s:%d:%d") : format ( location . file , start . line , start . column )
end

local SYMBOL_KINDS = {
[ 1 ] = "file" ,
[ 2 ] = "module" ,
[ 3 ] = "namespace" ,
[ 4 ] = "package" ,
[ 5 ] = "class" ,
[ 6 ] = "method" ,
[ 7 ] = "property" ,
[ 8 ] = "field" ,
[ 9 ] = "constructor" ,
[ 10 ] = "enum" ,
[ 11 ] = "interface" ,
[ 12 ] = "function" ,
[ 13 ] = "variable" ,
[ 14 ] = "constant" ,
[ 15 ] = "string" ,
[ 16 ] = "number" ,
[ 17 ] = "boolean" ,
[ 18 ] = "array" ,
[ 19 ] = "object" ,
[ 20 ] = "key" ,
[ 21 ] = "null" ,
[ 22 ] = "enum-member" ,
[ 23 ] = "struct" ,
[ 24 ] = "event" ,
[ 25 ] = "operator" ,
[ 26 ] = "type-parameter" ,
}

local function editValues ( client , changes ) 
local edits = jsonArray ( { } )
local uris = { }
local seen = { }
for uri in pairs ( changes or { } ) do
uris [ # uris + 1 ] = uri
end
table . sort ( uris )
for _ , uri in ipairs ( uris ) do
local path = uriToPath ( uri )
for _ , edit in ipairs ( changes [ uri ] ) do
local start , finish = edit . range . start , edit . range [ "end" ]
local key = path
.. ":"
.. start . line
.. ":"
.. start . character
.. ":"
.. finish . line
.. ":"
.. finish . character
.. ":"
.. edit . newText
if not seen [ key ] then
seen [ key ] = true
edits [
# edits + 1
] = {
file = displayPath ( client . root , path ) ,
range = rangeValue ( client , path , edit . range ) ,
newText = edit . newText ,
}
end
end
end
table . sort ( edits , function ( left , right ) 
if left . file ~= right . file then
return left . file < right . file
end
return left . range . start . offset < right . range . start . offset
end )

return edits
end





local function jsonOutput ( value ) 
value . ok = true
io . write ( json . encode ( value ) .. "\n" )
end




local function usage ( message ) 
return { usage = message }
end

local function parsePositive ( value , label ) 
local number = tonumber ( value )
if not number or number < 1 or number ~= math . floor ( number ) then
return nil , usage ( label .. " must be a positive integer" )
end

return number
end

local function target ( client , opts ) 
if # opts . positional ~= 3 then
return nil , nil , nil , ( { usage = "expected FILE LINE COLUMN" } )
end
local path = resolvePath ( opts . root , opts . positional [ 1 ] )
local source , readErr = client . open ( path )
if not source then
return nil , nil , nil , readErr
end
local line , lineErr = parsePositive ( opts . positional [ 2 ] , "line" )
if not line then
return nil , nil , nil , lineErr
end
local column , columnErr = parsePositive ( opts . positional [ 3 ] , "column" )
if not column then
return nil , nil , nil , columnErr
end
local position , positionErr = toLspPosition ( source , line , column )
if not position then
return nil , nil , nil , { code = "NUPP0003" , message = tostring ( positionErr ) , file = path }
end

return path , source , position
end





local function runInspect ( client , opts ) 
local path , _ , position , err = target ( client , opts )
if not path then
return nil , err
end
local result , requestErr = client . request ( "nupp/inspect" , ( { textDocument = { uri = pathToUri ( path ) } , position = position } ) )
if requestErr then
return nil , requestErr
end
if result == json . NULL then
result = nil
end
local value = result and {
name = result . name ,
kind = result . kind ,
type = result . type ,
associated = result . associated ,
detail = result . detail ,
documentation = result . documentation ,
definition = locationValue ( client , result . definition ) ,
range = result . range and rangeValue ( client , path , result . range ) or nil ,


automaticCleanup = result . automaticCleanup ,
} or nil
if opts . format == "json" then
jsonOutput ( { symbol = value or json . NULL } )
elseif value then
io . write ( value . name .. " (" .. value . kind .. ")\n" )
if value . type then
io . write ( value . type .. "\n" )
end
if value . associated then
io . write ( value . associated .. "\n" )
end
if value . detail then
io . write ( value . detail .. "\n" )
end
if value . documentation then
io . write ( "\n" .. value . documentation .. "\n" )
end
if value . definition then
io . write ( "Defined at " .. locationText ( value . definition ) .. "\n" )
end
end

return true
end

local function runDefinition ( client , opts , implementation ) 
local path , _ , position , err = target ( client , opts )
if not path then
return nil , err
end
local result , requestErr = client . request (
implementation and "textDocument/implementation" or "textDocument/definition" ,
( { textDocument = { uri = pathToUri ( path ) } , position = position } )
)
if requestErr then
return nil , requestErr
end



local values = { }
if result and result . uri == nil and result [ 1 ] then
for _ , one in ipairs ( result ) do
local located = locationValue ( client , one )
if located then
values [ # values + 1 ] = located
end
end
else
local located = locationValue ( client , result )
if located then
values [ 1 ] = located
end
end
if opts . format == "json" then
if implementation then
jsonOutput ( { implementations = jsonArray ( values ) } )
elseif # values > 1 then
jsonOutput ( { definition = values [ 1 ] , definitions = jsonArray ( values ) } )
else
jsonOutput ( { definition = values [ 1 ] or json . NULL } )
end
else
for _ , located in ipairs ( values ) do
io . write ( locationText ( located ) .. "\n" )
end
end

return true
end

local function runReferences ( client , opts ) 
local path , _ , position , err = target ( client , opts )
if not path then
return nil , err
end
local params = ( { textDocument = { uri = pathToUri ( path ) } , position = position } )
params . context = { includeDeclaration = opts . includeDeclaration or false }
local result , requestErr = client . request ( "textDocument/references" , params )
if requestErr then
return nil , requestErr
end
local values = jsonArray ( { } )
local seen = { }
if type ( result ) ~= "table" then
result = { }
end
for _ , location in ipairs ( result ) do
local value = locationValue ( client , location )
local start , finish = value . range . start , value . range [ "end" ]
local key = value . file .. ":" .. start . offset .. ":" .. finish . offset
if not seen [ key ] then
seen [ key ] = true
values [ # values + 1 ] = value
end
end
if opts . format == "json" then
jsonOutput ( { declarationIncluded = opts . includeDeclaration or false , references = values } )
else
for _ , value in ipairs ( values ) do
io . write ( locationText ( value ) .. "\n" )
end
end

return true
end

local function documentSymbolValue ( client , path , symbol ) 
local value = {
name = symbol . name ,
kind = SYMBOL_KINDS [ symbol . kind ] or "unknown" ,
location = {
file = displayPath ( client . root , path ) ,
range = rangeValue ( client , path , symbol . selectionRange or symbol . range )
} ,
}
if symbol . children and # symbol . children > 0 then
value . children = jsonArray ( { } )
for _ , child in ipairs ( symbol . children ) do
value . children [ # value . children + 1 ] = documentSymbolValue ( client , path , child )
end
end

return value
end

local function printSymbol ( symbol , indent ) 
io . write ( ("  ") : rep ( indent ) .. symbol . kind .. " " .. symbol . name .. " " .. locationText ( symbol . location ) .. "\n" )
for _ , child in ipairs ( symbol . children or { } ) do
printSymbol ( child , indent + 1 )
end
end

local function runSymbols ( client , opts ) 
if # opts . positional > 1 then
return nil , ( { usage = "symbols accepts at most one pattern" } )
end
local values = jsonArray ( { } )
local seen = { }
if opts . file then
local path = resolvePath ( opts . root , opts . file )
local _ , openErr = client . open ( path )
if openErr then
return nil , openErr
end
local result , requestErr = client . request ( "textDocument/documentSymbol" , {
textDocument = { uri = pathToUri ( path ) }
} )
if requestErr then
return nil , requestErr
end
local pattern = opts . positional [ 1 ] and opts . positional [ 1 ] : lower ( )
if type ( result ) ~= "table" then
result = { }
end
for _ , symbol in ipairs ( result ) do
if not pattern or symbol . name : lower ( ) : find ( pattern , 1 , true ) then
local value = documentSymbolValue ( client , path , symbol )
local key = value . name .. ":" .. value . location . range . start . offset
if not seen [ key ] then
seen [ key ] = true
values [ # values + 1 ] = value
end
end
end
else
local result , requestErr = client . request ( "workspace/symbol" , { query = opts . positional [ 1 ] or "" } )
if requestErr then
return nil , requestErr
end
if type ( result ) ~= "table" then
result = { }
end
for _ , symbol in ipairs ( result ) do
local value = {
name = symbol . name ,
kind = SYMBOL_KINDS [ symbol . kind ] or "unknown" ,
container = symbol . containerName ,
location = locationValue ( client , symbol . location ) ,
}
local key = value . name .. ":" .. value . location . file .. ":" .. value . location . range . start . offset
if not seen [ key ] then
seen [ key ] = true
values [ # values + 1 ] = value
end
end
end
if opts . format == "json" then
jsonOutput ( { symbols = values } )
else
for _ , symbol in ipairs ( values ) do
printSymbol ( symbol , 0 )
end
end

return true
end


local function latestFirst ( left , right ) 
return left . from > right . from
end

local function rewrittenFiles ( client , rawChanges ) 
local rewritten , previews = { } , { }
local grouped = { }
local seen = { }
for uri , rawEdits in pairs ( rawChanges or { } ) do
local path = uriToPath ( uri )
grouped [ path ] = grouped [ path ] or { }
seen [ path ] = seen [ path ] or { }
for _ , edit in ipairs ( rawEdits ) do
local start , finish = edit . range . start , edit . range [ "end" ]
local key = start . line
.. ":"
.. start . character
.. ":"
.. finish . line
.. ":"
.. finish . character
.. ":"
.. edit . newText
if not seen [ path ] [ key ] then
seen [ path ] [ key ] = true
local pathEdits = grouped [ path ]
pathEdits [ # pathEdits + 1 ] = edit
end
end
end
for path , rawEdits in pairs ( grouped ) do
local source , readErr = client . source ( path )
if not source then
return nil , nil , readErr
end
local edits = { }
for _ , edit in ipairs ( rawEdits ) do
local from = fromLspPosition ( source , edit . range . start ) . offset
local to = fromLspPosition ( source , edit . range [ "end" ] ) . offset
edits [
# edits + 1
] = {
from = from ,
to = to ,
newText = edit . newText ,
oldText = source : sub ( from , to - 1 ) ,
range = rangeValue ( client , path , edit . range )
}
end
table . sort ( edits , latestFirst )
local last = # source + 1
local text = source
for _ , edit in ipairs ( edits ) do
if edit . to > last then
return nil , nil , "rename edits overlap"
end
text = text : sub ( 1 , edit . from - 1 ) .. edit . newText .. text : sub ( edit . to )
last = edit . from
end
rewritten [ path ] = text
previews [ path ] = edits
end

return rewritten , previews
end

local function identifierAt ( source , line , column ) 
local start = lineStart ( source , line )
local offset = start and start + column - 1
if not offset then
return nil
end
local left , right = offset , offset
while left > 1 and source : sub ( left - 1 , left - 1 ) : match ( "[A-Za-z0-9_]" ) do
left = left - 1
end
while right <= # source and source : sub ( right , right ) : match ( "[A-Za-z0-9_]" ) do
right = right + 1
end
local name = source : sub ( left , right - 1 )

return name ~= "" and name or nil
end

local function runRename ( client , opts ) 
if # opts . positional ~= 4 then
return nil , ( { usage = "expected FILE LINE COLUMN NEW_NAME" } )
end
local newName = opts . positional [ 4 ]


local keywords = require ( "nupp.compiler.syntax.lexer" ) . KEYWORDS
if not newName : match ( "^[A-Za-z_][A-Za-z0-9_]*$" ) or keywords [ newName ] then
return nil , usage ( ("NEW_NAME must be an identifier that is not a keyword, not %q") : format ( newName ) )
end
local targetOpts = { positional = { opts . positional [ 1 ] , opts . positional [ 2 ] , opts . positional [ 3 ] } , root = opts . root }
local path , source , position , err = target ( client , targetOpts )
if not path then
return nil , err
end
local params = ( { textDocument = { uri = pathToUri ( path ) } , position = position } )
params . newName = newName
local result , requestErr = client . request ( "textDocument/rename" , params )
if requestErr then
return nil , requestErr
end
local changes = result and result . changes or { }
local edits = editValues ( client , changes )
local rewritten , previews , rewriteErr = rewrittenFiles ( client , changes )
if not rewritten then
return nil , rewriteErr
end
local changedFiles = { }
for changedPath in pairs ( rewritten ) do
changedFiles [ # changedFiles + 1 ] = changedPath
end
table . sort ( changedFiles )
if opts . write then
for _ , changedPath in ipairs ( changedFiles ) do
local ok , writeErr = fs . writeFile ( changedPath , rewritten [ changedPath ] )
if not ok then
return nil , { code = "NUPP0001" , message = tostring ( writeErr ) , file = changedPath }
end
end
end
local oldName = identifierAt ( source , tonumber ( opts . positional [ 2 ] ) , tonumber ( opts . positional [ 3 ] ) )
if opts . format == "json" then
jsonOutput ( { oldName = oldName , newName = newName , written = opts . write or false , edits = edits } )
elseif opts . write then
io . write (
("Renamed %s to %s in %d location%s across %d file%s\n")

: format (
oldName or "symbol" ,
newName ,
# edits ,
# edits == 1 and "" or "s" ,
# changedFiles ,
# changedFiles == 1 and "" or "s"
)
)
for _ , changedPath in ipairs ( changedFiles ) do
io . write ( displayPath ( opts . root , changedPath ) .. "\n" )
end
else
for _ , changedPath in ipairs ( changedFiles ) do
io . write ( "--- " .. displayPath ( opts . root , changedPath ) .. "\n" )
io . write ( "+++ " .. displayPath ( opts . root , changedPath ) .. "\n" )
for index = # previews [ changedPath ] , 1 , -1 do
local edit = previews [ changedPath ] [ index ]
io . write ( ("@@ %d:%d @@\n") : format ( edit . range . start . line , edit . range . start . column ) )
io . write ( "-" .. edit . oldText .. "\n" )
io . write ( "+" .. edit . newText .. "\n" )
end
end
end

return true
end

local function runActions ( client , opts ) 
local path , _ , position , err = target ( client , opts )
if not path then
return nil , err
end
local params = ( { textDocument = { uri = pathToUri ( path ) } , position = position } )
params . range = { start = position , [ "end" ] = position }
local context = { diagnostics = jsonArray ( { } ) }
if opts . only then
context . only = jsonArray ( { opts . only } )
end
params . context = context
local result , requestErr = client . request ( "textDocument/codeAction" , params )
if requestErr then
return nil , requestErr
end
local actions = jsonArray ( { } )
if type ( result ) ~= "table" then
result = { }
end
for _ , action in ipairs ( result ) do
local diagnostic = action . diagnostics and action . diagnostics [ 1 ]
actions [
# actions + 1
] = {
kind = action . kind ,
title = action . title ,
diagnostic = diagnostic and { code = diagnostic . code , message = diagnostic . message , } or nil ,
edits = editValues ( client , action . edit and action . edit . changes or { } ) ,
}
end
if opts . format == "json" then
jsonOutput ( { actions = actions } )
else
for _ , action in ipairs ( actions ) do
io . write ( action . kind .. ": " .. action . title .. "\n" )
end
end

return true
end

local function runTraceCheck ( client , opts ) 
local path , _ , position , err = target ( client , opts )
if not path then
return nil , err
end
local result , requestErr = client . request ( "nupp/traceCheck" , ( { textDocument = { uri = pathToUri ( path ) } , position = position } ) )
if requestErr then
return nil , requestErr
end
local value = { findings = jsonArray ( { } ) }
if result and result ~= json . NULL then
value . functionName = result . name
value . contract = result . contract
value . range = result . range and rangeValue ( client , path , result . range ) or nil
value . traceProfile = result . traceProfile
value . reasonCatalog = result . reasonCatalog
value . addContract = result . addContract
and { range = rangeValue ( client , path , result . addContract . range ) , newText = result . addContract . newText , }
or nil
for _ , finding in ipairs ( result . findings or { } ) do
value . findings [
# value . findings + 1
] = {
reason = finding . reason ,
class = finding . class ,
message = finding . message ,
help = finding . help ,
callPath = jsonArray ( finding . callPath or { } ) ,
range = finding . range and rangeValue ( client , path , finding . range ) or nil ,
}
end
end
if opts . format == "json" then
jsonOutput ( value )
elseif not value . functionName then
io . write ( "No checked function at that position\n" )
elseif # value . findings == 0 then
io . write ( value . functionName .. ": no cataloged trace blockers or risks\n" )
else
io . write (
("%s: %d trace finding%s\n") : format ( value . functionName , # value . findings , # value . findings == 1 and "" or "s" )
)
for _ , finding in ipairs ( value . findings ) do
local pathText = # finding . callPath > 1 and " via " .. table . concat ( finding . callPath , " -> " ) or ""
io . write ( ("  %s %s%s: %s\n") : format ( finding . class , finding . reason , pathText , finding . message or "" ) )
if finding . help then
io . write ( "    help: " .. finding . help .. "\n" )
end
end
end

return true
end

local function runArtifacts ( client , opts ) 
local path , _ , position , err = target ( client , opts )
if not path then
return nil , err
end
local result , requestErr = client . request ( "nupp/artifacts" , ( { textDocument = { uri = pathToUri ( path ) } , position = position } ) )
if requestErr then
return nil , requestErr
end
local available = jsonArray ( { } )
for _ , entry in ipairs ( result and result . artifacts or { } ) do
available [
# available + 1
] = { kind = entry . kind , label = entry . label , languageId = entry . languageId , scope = entry . scope , }
end
local enclosing = result and result [ "function" ] or nil
local value = {
artifacts = available ,
[ "function" ] = enclosing
and {
name = enclosing . name ,
aotSymbol = enclosing . aotSymbol ,
aotSource = enclosing . aotSource ,
range = enclosing . range and rangeValue ( client , path , enclosing . range ) or nil ,
}
or nil ,
}
if opts . format == "json" then
jsonOutput ( value )
else
for _ , entry in ipairs ( available ) do
io . write ( ("%s: %s (%s)\n") : format ( entry . kind , entry . label , entry . scope ) )
end
if enclosing and enclosing . name then
io . write (
"in " .. enclosing . name .. ( enclosing . aotSymbol and ( " (" .. enclosing . aotSymbol .. ")" ) or "" ) .. "\n"
)
end
end

return true
end



local function runArtifact ( client , opts ) 
if # opts . positional ~= 1 then
return nil , ( { usage = "expected FILE" } )
end
if not opts . kind then
return nil , ( { usage = "--kind names the artifact to resolve: lua or bytecode" } )
end
local path = resolvePath ( opts . root , opts . positional [ 1 ] )
local _ , readErr = client . open ( path )
if readErr then
return nil , readErr
end
local result , requestErr = client . request ( "nupp/artifact" , {
textDocument = { uri = pathToUri ( path ) } ,
kind = opts . kind ,
optLevel = tonumber ( opts . artifactOptLevel ) or 0 ,
} )
if requestErr then
return nil , requestErr
end
if opts . format == "json" then
jsonOutput ( result )
elseif not result . available then
local reason = result . unavailable or { }

return nil , ( reason . detail or reason . reason or "the artifact is not available" )
else
io . write ( result . text )
if result . problem then
io . stderr : write ( "nupp: warning: " .. tostring ( result . problem . detail or result . problem . reason ) .. "\n" )
end
end

return true
end





local OPERATIONS = {
inspect = runInspect ,
definition = runDefinition ,
implementation = function ( client , opts ) 
return runDefinition ( client , opts , true )
end ,
references = runReferences ,
symbols = runSymbols ,
rename = runRename ,
actions = runActions ,
[ "trace-check" ] = runTraceCheck ,
artifacts = runArtifacts ,
artifact = runArtifact ,
}

local function typedOperation ( name , self , positional ) 
local opts = { root = self . root or "." , format = self . format or "text" , positional = positional }
opts . includeDeclaration = self . includeDeclaration
opts . file = self . file
opts . write = self . write
opts . only = self . only
opts . kind = self . kind
opts . artifactOptLevel = self . optLevel




local function fail ( problem , fallback ) 
local code = type ( problem ) == "table" and problem . code or fallback
local message = type ( problem ) == "table" and problem . message or tostring ( problem )
local file = type ( problem ) == "table" and problem . file or nil
if opts . format == "json" then
return reportMod . failure ( OPERATION_SCHEMAS [ name ] , { reportMod . runDiagnostic ( code , message , nil , file ) } )
end
io . stderr : write ( require ( "nupp.tools.cli.error" ) . message ( message ) .. "\n" )

return 1
end




local manifestPath = fs . join ( opts . root , "nupp.lua" )
if fs . exists ( manifestPath ) then
local loaded , loadErr = require ( "nupp.tools.build.manifest" ) . load ( opts . root )
if not loaded then
return fail (
{ code = reportMod . MANIFEST , message = tostring ( loadErr ) , file = manifestPath } ,
reportMod . MANIFEST
)
end
end
local client , clientErr = newClient ( opts . root )
if not client then
return fail ( clientErr , reportMod . TOOL_FAILED )
end
local run = assert ( OPERATIONS [ name ] )
local ok , runErr = run ( client , opts )
if not ok and type ( runErr ) == "table" and runErr . usage then
return require ( "nupp.tools.cli.error" ) . forCommand ( "lsp " .. name ) ( runErr . usage )
elseif not ok then
return fail ( runErr , reportMod . TOOL_FAILED )
end

return 0
end
























local Lsp = {} Lsp.__index = Lsp ;Lsp.__nuppInit1=function(__nuppT43) return __nuppT43 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Language-server and semantic source operations.\n\n`nupp lsp serve [root]` runs the language server over stdio. Semantic\noperations are `nupp lsp inspect`, `nupp lsp definition`,\n`nupp lsp implementation`, `nupp lsp references`, `nupp lsp symbols`,\n`nupp lsp rename`, `nupp lsp actions`, and `nupp lsp trace-check`.\nArtifact operations are `nupp lsp artifacts` and `nupp lsp artifact`.\n\nOperation-only options: references only: `--include-declaration`;\nsymbols only: `--file`; rename only: `--write`; actions only: `--only`;\nartifact only: `--kind`, `-O0`, `-O1`, `-O2`.\nAsk `nupp lsp <operation> --schema` for an operation's JSON schema.\nSource positions are one-based byte line and column numbers. Rename\npreviews by default and changes files only with `--write`.\n\nExamples:\n\n    nupp lsp serve\n    nupp lsp inspect src/main.nupp 12 8\n    nupp lsp references --include-declaration src/main.nupp 12 8\n    nupp lsp artifact --kind lua -O2 src/main.nupp",["group"]=true,["hidden"]=false,["name"]="lsp",["summary"]="Language-server and semantic source operations."},["fieldCount"]=0,["fields"]={},["positionals"]={},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="f9b04c97b8d42c6979edcd18383a7f53e13c3dcb1ab05dc5d99730538bc1bc60",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedGroupRun"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Lsp:1",["members"]={{["arguments"]={{["kind"]="receiver"}},["helper"]={["member"]="derivedGroupRun",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="run",["namespace"]="instance",["operation"]="forward.v1",["paramNames"]={""},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(Lsp): integer"},{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="lsp"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Language-server and semantic source operations."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Lsp?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Lsp",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Lsp:1",Lsp,__nuppDerived) ;Lsp["run"]=function(__nuppT43)return _G.require("nupp.cli")["derivedGroupRun"](__nuppT43)end ;Lsp["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Lsp["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("lsp")end ;Lsp["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Language-server and semantic source operations.")end ;Lsp["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Lsp,__nuppT1[1],{ })










local Serve = {} Serve.__index = Serve




function Serve:run() 
return require ( "nupp.tools.lsp" ) . run ( self . root or "." )
end ;Serve.__nuppInit1=function(__nuppT45, a1) __nuppT45.root = a1 return __nuppT45 end ;do local __nuppT46={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Run the language server over stdio.\n\nExamples:\n\n    nupp lsp serve\n    nupp lsp serve ./examples/greeter",["group"]=false,["hidden"]=false,["name"]="serve",["summary"]="Run the language server over stdio."},["fieldCount"]=1,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ROOT",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="ROOT"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ROOT",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="ROOT"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="cc36ed4cd5127ef809ac4897dc796e503679a33230cf7d106e6d5128d9f1e32f",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Serve:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="serve"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Run the language server over stdio."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Serve?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Serve",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT47=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Serve:1",Serve,__nuppT46) ;Serve["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Serve["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("serve")end ;Serve["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Run the language server over stdio.")end ;Serve["fromCLI"]=function(__nuppT48)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT48,__nuppT47)end  end ;_G.nupp.__reflect.link(Serve,__nuppT1[2],{ })










local Inspect = {} Inspect.__index = Inspect























function Inspect:run() 
return typedOperation ( "inspect" , self , { self . file , self . line , self . column } )
end ;Inspect.__nuppInit1=function(__nuppT50, __nuppT53, a2, a3, a4, a5, a6) __nuppT50.root = __nuppT53 __nuppT50.format = a2 if a3 == nil then __nuppT50.schema = false else __nuppT50.schema = a3 end __nuppT50.file = a4 __nuppT50.line = a5 __nuppT50.column = a6 return __nuppT50 end ;do local __nuppT51={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Describe the symbol at a position.\n\nExamples:\n\n    nupp lsp inspect src/main.nupp 12 8\n    nupp lsp inspect --json src/main.nupp 12 8",["group"]=false,["hidden"]=false,["name"]="inspect",["summary"]="Describe the symbol at a position."},["fieldCount"]=6,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="4925ab4f8daada1a9c261bf7f9a3c61519faccdcd081d1a72720ad0687aef9bf",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Inspect:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="inspect"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Describe the symbol at a position."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Inspect?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Inspect",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT52=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Inspect:1",Inspect,__nuppT51) ;Inspect["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Inspect["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("inspect")end ;Inspect["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Describe the symbol at a position.")end ;Inspect["fromCLI"]=function(__nuppT54)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT54,__nuppT52)end  end ;_G.nupp.__reflect.link(Inspect,__nuppT1[3],{ })










local Definition = {} Definition.__index = Definition























function Definition:run() 
return typedOperation ( "definition" , self , { self . file , self . line , self . column } )
end ;Definition.__nuppInit1=function(__nuppT56, __nuppT59, __nuppT60, __nuppT61, __nuppT62, __nuppT63, __nuppT64) __nuppT56.root = __nuppT59 __nuppT56.format = __nuppT60 if __nuppT61 == nil then __nuppT56.schema = false else __nuppT56.schema = __nuppT61 end __nuppT56.file = __nuppT62 __nuppT56.line = __nuppT63 __nuppT56.column = __nuppT64 return __nuppT56 end ;do local __nuppT57={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Find where the symbol at a position is defined.\n\nExamples:\n\n    nupp lsp definition src/main.nupp 12 8\n    nupp lsp definition --json src/main.nupp 12 8",["group"]=false,["hidden"]=false,["name"]="definition",["summary"]="Find where the symbol at a position is defined."},["fieldCount"]=6,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="17cc63f4717e0b0bac65e4ecb1830cceef2b4a5b6d9baecc3f65408dc9f95418",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Definition:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="definition"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Find where the symbol at a position is defined."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Definition?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Definition",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT58=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Definition:1",Definition,__nuppT57) ;Definition["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Definition["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("definition")end ;Definition["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Find where the symbol at a position is defined.")end ;Definition["fromCLI"]=function(__nuppT65)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT65,__nuppT58)end  end ;_G.nupp.__reflect.link(Definition,__nuppT1[4],{ })










local Implementation = {} Implementation.__index = Implementation























function Implementation:run() 
return typedOperation ( "implementation" , self , { self . file , self . line , self . column } )
end ;Implementation.__nuppInit1=function(__nuppT67, __nuppT70, __nuppT71, __nuppT72, __nuppT73, __nuppT74, __nuppT75) __nuppT67.root = __nuppT70 __nuppT67.format = __nuppT71 if __nuppT72 == nil then __nuppT67.schema = false else __nuppT67.schema = __nuppT72 end __nuppT67.file = __nuppT73 __nuppT67.line = __nuppT74 __nuppT67.column = __nuppT75 return __nuppT67 end ;do local __nuppT68={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Find registered implementations of a service member.\n\nExamples:\n\n    nupp lsp implementation src/services.nupp 24 18\n    nupp lsp implementation --json src/services.nupp 24 18",["group"]=false,["hidden"]=false,["name"]="implementation",["summary"]="Find registered implementations of a service member."},["fieldCount"]=6,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="bc938d76722be8c03e1b86dda647950b2748a233e67dac8e39e42cfc4723c806",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Implementation:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="implementation"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Find registered implementations of a service member."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Implementation?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Implementation",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT69=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Implementation:1",Implementation,__nuppT68) ;Implementation["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Implementation["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("implementation")end ;Implementation["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Find registered implementations of a service member.")end ;Implementation["fromCLI"]=function(__nuppT76)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT76,__nuppT69)end  end ;_G.nupp.__reflect.link(Implementation,__nuppT1[5],{ })










local References = {} References.__index = References


























function References:run() 
return typedOperation ( "references" , self , { self . file , self . line , self . column } )
end ;References.__nuppInit1=function(__nuppT78, __nuppT81, __nuppT82, __nuppT83, __nuppT84, __nuppT85, __nuppT86, a7) __nuppT78.root = __nuppT81 __nuppT78.format = __nuppT82 if __nuppT83 == nil then __nuppT78.includeDeclaration = false else __nuppT78.includeDeclaration = __nuppT83 end if __nuppT84 == nil then __nuppT78.schema = false else __nuppT78.schema = __nuppT84 end __nuppT78.file = __nuppT85 __nuppT78.line = __nuppT86 __nuppT78.column = a7 return __nuppT78 end ;do local __nuppT79={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Find semantic references to the symbol at a position.\n\nExamples:\n\n    nupp lsp references src/main.nupp 12 8\n    nupp lsp references --include-declaration src/main.nupp 12 8",["group"]=false,["hidden"]=false,["name"]="references",["summary"]="Find semantic references to the symbol at a position."},["fieldCount"]=7,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--include-declaration",["documentation"]="Include the declaration among the references.",["field"]="includeDeclaration",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"include-declaration"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="0bc2cbe9dbfc42fc8296f4cc34d1a97d8f51688c696b971e02f682332b23b757",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:References:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="references"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Find semantic references to the symbol at a position."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (References?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="References",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT80=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:References:1",References,__nuppT79) ;References["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;References["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("references")end ;References["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Find semantic references to the symbol at a position.")end ;References["fromCLI"]=function(__nuppT87)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT87,__nuppT80)end  end ;_G.nupp.__reflect.link(References,__nuppT1[6],{ })











local Symbols = {} Symbols.__index = Symbols



















function Symbols:run() 
return typedOperation ( "symbols" , self , self . pattern and { self . pattern } or { } )
end ;Symbols.__nuppInit1=function(__nuppT89, __nuppT92, __nuppT93, __nuppT94, __nuppT95, __nuppT96) __nuppT89.root = __nuppT92 __nuppT89.format = __nuppT93 __nuppT89.file = __nuppT94 if __nuppT95 == nil then __nuppT89.schema = false else __nuppT89.schema = __nuppT95 end __nuppT89.pattern = __nuppT96 return __nuppT89 end ;do local __nuppT90={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Search workspace or document symbols.\n\nExamples:\n\n    nupp lsp symbols Parser\n    nupp lsp symbols --file src/main.nupp parse\n    nupp lsp symbols --json",["group"]=false,["hidden"]=false,["name"]="symbols",["summary"]="Search workspace or document symbols."},["fieldCount"]=5,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--file",["documentation"]="Search a document instead of the workspace.",["field"]="file",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"file"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FILE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="PATTERN",["documentation"]="Optional name fragment.",["field"]="pattern",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="PATTERN"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="PATTERN",["documentation"]="Optional name fragment.",["field"]="pattern",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="PATTERN"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="0d151106611c885017da4a7d9b0665aff4cb3010a074a675935a31ad244e2215",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Symbols:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="symbols"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Search workspace or document symbols."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Symbols?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Symbols",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT91=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Symbols:1",Symbols,__nuppT90) ;Symbols["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Symbols["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("symbols")end ;Symbols["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Search workspace or document symbols.")end ;Symbols["fromCLI"]=function(__nuppT97)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT97,__nuppT91)end  end ;_G.nupp.__reflect.link(Symbols,__nuppT1[7],{ })










local Rename = {} Rename.__index = Rename































function Rename:run() 
return typedOperation ( "rename" , self , { self . file , self . line , self . column , self . newName } )
end ;Rename.__nuppInit1=function(__nuppT99, __nuppT102, __nuppT103, __nuppT104, __nuppT105, __nuppT106, __nuppT107, __nuppT108, a8) __nuppT99.root = __nuppT102 __nuppT99.format = __nuppT103 if __nuppT104 == nil then __nuppT99.write = false else __nuppT99.write = __nuppT104 end if __nuppT105 == nil then __nuppT99.schema = false else __nuppT99.schema = __nuppT105 end __nuppT99.file = __nuppT106 __nuppT99.line = __nuppT107 __nuppT99.column = __nuppT108 __nuppT99.newName = a8 return __nuppT99 end ;do local __nuppT100={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Rename a symbol and every semantic reference to it.\n\nExamples:\n\n    nupp lsp rename src/main.nupp 12 8 newName\n    nupp lsp rename --write src/main.nupp 12 8 newName",["group"]=false,["hidden"]=false,["name"]="rename",["summary"]="Rename a symbol and every semantic reference to it."},["fieldCount"]=8,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--write",["documentation"]="Apply the rename instead of previewing it.",["field"]="write",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"write","w"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="NEW-NAME",["documentation"]="Replacement identifier.",["field"]="newName",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="NEW-NAME"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="NEW-NAME",["documentation"]="Replacement identifier.",["field"]="newName",["hidden"]=false,["index"]=8,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="NEW-NAME"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="5357b031c044ce5bdcbaaea7a53a2e8f068e07f30787f7d3746d80b5c8d8eb2b",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Rename:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="rename"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Rename a symbol and every semantic reference to it."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Rename?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Rename",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT101=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Rename:1",Rename,__nuppT100) ;Rename["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Rename["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("rename")end ;Rename["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Rename a symbol and every semantic reference to it.")end ;Rename["fromCLI"]=function(__nuppT109)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT109,__nuppT101)end  end ;_G.nupp.__reflect.link(Rename,__nuppT1[8],{ })










local Actions = {} Actions.__index = Actions



























function Actions:run() 
return typedOperation ( "actions" , self , { self . file , self . line , self . column } )
end ;Actions.__nuppInit1=function(__nuppT111, __nuppT114, __nuppT115, __nuppT116, __nuppT117, __nuppT118, __nuppT119, __nuppT120) __nuppT111.root = __nuppT114 __nuppT111.format = __nuppT115 __nuppT111.only = __nuppT116 if __nuppT117 == nil then __nuppT111.schema = false else __nuppT111.schema = __nuppT117 end __nuppT111.file = __nuppT118 __nuppT111.line = __nuppT119 __nuppT111.column = __nuppT120 return __nuppT111 end ;do local __nuppT112={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="List code actions available at a position.\n\nExamples:\n\n    nupp lsp actions src/main.nupp 12 8\n    nupp lsp actions --only quickfix src/main.nupp 12 8",["group"]=false,["hidden"]=false,["name"]="actions",["summary"]="List code actions available at a position."},["fieldCount"]=7,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="required",["choices"]={"quickfix"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--only",["documentation"]="Narrow the results to a kind of action.",["field"]="only",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"only"},["optional"]=true,["required"]=false,["role"]="option",["value"]="KIND"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=7,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="236392d3fb4706df17af51632bbdbfef57fbe6ef6f2478eb825c469bbe94a9a0",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Actions:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="actions"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="List code actions available at a position."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Actions?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Actions",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT113=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Actions:1",Actions,__nuppT112) ;Actions["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Actions["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("actions")end ;Actions["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("List code actions available at a position.")end ;Actions["fromCLI"]=function(__nuppT121)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT121,__nuppT113)end  end ;_G.nupp.__reflect.link(Actions,__nuppT1[9],{ })










local TraceCheck = {} TraceCheck.__index = TraceCheck























function TraceCheck:run() 
return typedOperation ( "trace-check" , self , { self . file , self . line , self . column } )
end ;TraceCheck.__nuppInit1=function(__nuppT123, __nuppT126, __nuppT127, __nuppT128, __nuppT129, __nuppT130, __nuppT131) __nuppT123.root = __nuppT126 __nuppT123.format = __nuppT127 if __nuppT128 == nil then __nuppT123.schema = false else __nuppT123.schema = __nuppT128 end __nuppT123.file = __nuppT129 __nuppT123.line = __nuppT130 __nuppT123.column = __nuppT131 return __nuppT123 end ;do local __nuppT124={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Check the function at a position for LuaJIT trace blockers.\n\nExamples:\n\n    nupp lsp trace-check src/main.nupp 12 8\n    nupp lsp trace-check --json src/main.nupp 12 8",["group"]=false,["hidden"]=false,["name"]="trace-check",["summary"]="Check the function at a position for LuaJIT trace blockers."},["fieldCount"]=6,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="488a5e1761cf7287854ae62209ad046d66cc7f918130e9b1457e0882239988b5",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:TraceCheck:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="trace-check"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Check the function at a position for LuaJIT trace blockers."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (TraceCheck?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="TraceCheck",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT125=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:TraceCheck:1",TraceCheck,__nuppT124) ;TraceCheck["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;TraceCheck["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("trace-check")end ;TraceCheck["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Check the function at a position for LuaJIT trace blockers.")end ;TraceCheck["fromCLI"]=function(__nuppT132)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT132,__nuppT125)end  end ;_G.nupp.__reflect.link(TraceCheck,__nuppT1[10],{ })










local Artifacts = {} Artifacts.__index = Artifacts























function Artifacts:run() 
return typedOperation ( "artifacts" , self , { self . file , self . line , self . column } )
end ;Artifacts.__nuppInit1=function(__nuppT134, __nuppT137, __nuppT138, __nuppT139, __nuppT140, __nuppT141, __nuppT142) __nuppT134.root = __nuppT137 __nuppT134.format = __nuppT138 if __nuppT139 == nil then __nuppT134.schema = false else __nuppT134.schema = __nuppT139 end __nuppT134.file = __nuppT140 __nuppT134.line = __nuppT141 __nuppT134.column = __nuppT142 return __nuppT134 end ;do local __nuppT135={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="List the compiled artifacts available at a position.\n\nExamples:\n\n    nupp lsp artifacts src/main.nupp 12 8\n    nupp lsp artifacts --json src/main.nupp 12 8",["group"]=false,["hidden"]=false,["name"]="artifacts",["summary"]="List the compiled artifacts available at a position."},["fieldCount"]=6,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="LINE",["documentation"]="One-based source line.",["field"]="line",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="LINE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="COLUMN",["documentation"]="One-based byte column.",["field"]="column",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="COLUMN"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="62ef4df4590c31aa2e5df6a989f46be03d69840e9a5328a1abf7c547af8fa8f7",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Artifacts:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="artifacts"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="List the compiled artifacts available at a position."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Artifacts?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Artifacts",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT136=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Artifacts:1",Artifacts,__nuppT135) ;Artifacts["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Artifacts["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("artifacts")end ;Artifacts["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("List the compiled artifacts available at a position.")end ;Artifacts["fromCLI"]=function(__nuppT143)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT143,__nuppT136)end  end ;_G.nupp.__reflect.link(Artifacts,__nuppT1[11],{ })










local Artifact = {} Artifact.__index = Artifact






























function Artifact:run() 
return typedOperation ( "artifact" , self , { self . file } )
end ;Artifact.__nuppInit1=function(__nuppT145, __nuppT148, __nuppT149, __nuppT150, __nuppT151, __nuppT152, __nuppT153) __nuppT145.root = __nuppT148 __nuppT145.format = __nuppT149 __nuppT145.kind = __nuppT150 __nuppT145.optLevel = __nuppT151 if __nuppT152 == nil then __nuppT145.schema = false else __nuppT145.schema = __nuppT152 end __nuppT145.file = __nuppT153 return __nuppT145 end ;do local __nuppT146={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Print what a file compiles to.\n\nExamples:\n\n    nupp lsp artifact --kind lua -O2 src/main.nupp\n    nupp lsp artifact --kind bytecode --json src/main.nupp",["group"]=false,["hidden"]=false,["name"]="artifact",["summary"]="Print what a file compiles to."},["fieldCount"]=6,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--root",["documentation"]="Project root.",["field"]="root",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"root"},["optional"]=true,["required"]=false,["role"]="option",["value"]="DIR"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="required",["choices"]={"lua","bytecode"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--kind",["documentation"]="Which artifact to resolve.",["field"]="kind",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"kind"},["required"]=true,["role"]="option",["value"]="KIND"},{["arity"]="required",["choices"]={"0","1","2"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="-O0, -O1, -O2",["displayOverride"]="-O0, -O1, -O2",["documentation"]="Optimization level to resolve the artifact at.",["field"]="optLevel",["hidden"]=false,["index"]=4,["long"]=false,["matchKey"]="O",["names"]={},["optional"]=true,["pattern"]="^%-O([0-2])$",["required"]=false,["role"]="option",["value"]="LEVEL"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source file.",["field"]="file",["hidden"]=false,["index"]=6,["long"]=true,["names"]={},["required"]=true,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="8e1a204f7f2185924d596f972741184d3da58e349cde9e3a9b9149168ad990be",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Artifact:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="artifact"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Print what a file compiles to."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Artifact?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Artifact",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppT147=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.lsp:Artifact:1",Artifact,__nuppT146) ;Artifact["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Artifact["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("artifact")end ;Artifact["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Print what a file compiles to.")end ;Artifact["fromCLI"]=function(__nuppT154)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT154,__nuppT147)end  end ;_G.nupp.__reflect.link(Artifact,__nuppT1[12],{ })


function Lsp . subcommands ( ) 
return {
(_G.nupp.__reflect.known( Serve ) and  Serve  or  _G.nupp.__reflect.ensure( Serve ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="serve"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="ROOT"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=5,["writable"]=true}},["fingerprint"]="9e3913e16dbb4f859d68f520ac865bf015d5b77269a9c958e6fc17dba8fc2964",["kind"]="record",["name"]="Serve",["qualifiedName"]="Serve",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="serve"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Serve:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="ROOT"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=5,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=5}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Serve",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=9,["write"]=9},{["name"]="cliName",["read"]=13,["write"]=13},{["name"]="cliSummary",["read"]=13,["write"]=13},{["name"]="fromCLI",["read"]=15,["write"]=15}},["supertypes"]={21},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=7,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=8,["returns"]={6},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=6}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=11,["parameters"]={},["returnPack"]=12,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=10}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=11,["parameters"]={},["returnPack"]=14,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=10}},["returnPack"]=20,["returns"]={16,17},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,18}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=19,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={6,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=16},{["mode"]="plain",["type"]=17}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=22,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=22}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=24,["parameters"]={{["mode"]="plain",["name"]="",["type"]=23}},["returnPack"]=8,["returns"]={6},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=21,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\0002",["21"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( Inspect ) and  Inspect  or  _G.nupp.__reflect.ensure( Inspect ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="inspect"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="line",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="column",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="9baadf21465bead81da8b171cb87e4ad2934dd1c43fc5fee5832d5661ece7730",["kind"]="record",["name"]="Inspect",["qualifiedName"]="Inspect",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="inspect"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="line",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="column",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Inspect:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="line",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="column",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Inspect",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\0003",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( Definition ) and  Definition  or  _G.nupp.__reflect.ensure( Definition ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="definition"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="line",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="column",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="b6ec5147be00dba721ee831c52884dd4801237d15d660d6f6241cb036ed8a46d",["kind"]="record",["name"]="Definition",["qualifiedName"]="Definition",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="definition"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="line",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="column",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Definition:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="line",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="column",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Definition",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\0004",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( Implementation ) and  Implementation  or  _G.nupp.__reflect.ensure( Implementation ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="implementation"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="line",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="column",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="3692688228dc71e4f4552eef848ce93ac9569408532840ada809172aeab7cab4",["kind"]="record",["name"]="Implementation",["qualifiedName"]="Implementation",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="implementation"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="line",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="column",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Implementation:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="line",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="column",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Implementation",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\0005",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( References ) and  References  or  _G.nupp.__reflect.ensure( References ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="references"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="includeDeclaration",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="line",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="column",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="ace9fd128b9230c46b73d19c237f26dea6527a980ba01da0d2f344fd26c1e630",["kind"]="record",["name"]="References",["qualifiedName"]="References",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="references"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="includeDeclaration",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="line",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="column",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:References:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="includeDeclaration",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="line",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="column",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="References",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\0006",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( Symbols ) and  Symbols  or  _G.nupp.__reflect.ensure( Symbols ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="symbols"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="file",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="PATTERN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="pattern",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="3df2ce75c2e5a5796015ad29d9ac4e6370c5817162401820f84e621331370b88",["kind"]="record",["name"]="Symbols",["qualifiedName"]="Symbols",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="symbols"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="file",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="pattern",["optional"]=true,["type"]=2}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Symbols:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="PATTERN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="pattern",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Symbols",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\0007",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( Rename ) and  Rename  or  _G.nupp.__reflect.ensure( Rename ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="rename"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="short",["value"]="w"}},["name"]="cli"}},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="write",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="line",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="column",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="NEW-NAME"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="newName",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="3ac1a9711505b2ccb82c9e7be3c82249595f0f4a819c8103fd96a19daf9bd736",["kind"]="record",["name"]="Rename",["qualifiedName"]="Rename",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="rename"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="write",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="line",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="column",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="newName",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Rename:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="short",["value"]="w"}},["name"]="cli"}},["defaultValue"]=false,["hasDefault"]=true,["name"]="write",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="line",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="column",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="NEW-NAME"}},["name"]="cli"}},["hasDefault"]=false,["name"]="newName",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Rename",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\0008",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( Actions ) and  Actions  or  _G.nupp.__reflect.ensure( Actions ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="actions"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="KIND"},{["kind"]="value",["name"]="choices",["value"]={"quickfix"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="only",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="line",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="column",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="82fc3e24ec2dfd8f31e32e7977965ebe7af7b8dde1289f8ceda64e2700c0bdc9",["kind"]="record",["name"]="Actions",["qualifiedName"]="Actions",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="actions"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="only",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="line",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="column",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Actions:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="KIND"},{["kind"]="value",["name"]="choices",["value"]={"quickfix"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="only",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="line",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="column",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Actions",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\0009",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( TraceCheck ) and  TraceCheck  or  _G.nupp.__reflect.ensure( TraceCheck ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="trace-check"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="line",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="column",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="e581928e86f16be30ce8d0e395642c4f2574e43b55f7e5fd8600129abf506bd9",["kind"]="record",["name"]="TraceCheck",["qualifiedName"]="TraceCheck",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="trace-check"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="line",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="column",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:TraceCheck:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="line",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="column",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="TraceCheck",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\00010",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( Artifacts ) and  Artifacts  or  _G.nupp.__reflect.ensure( Artifacts ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="artifacts"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="line",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="column",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="5e6be69b03973261f2fc02e63796d41cf240fdb4dbb313d5ce7bc44c36bbd736",["kind"]="record",["name"]="Artifacts",["qualifiedName"]="Artifacts",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="artifacts"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="line",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="column",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Artifacts:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="LINE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="line",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="COLUMN"}},["name"]="cli"}},["hasDefault"]=false,["name"]="column",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Artifacts",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\00011",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
(_G.nupp.__reflect.known( Artifact ) and  Artifact  or  _G.nupp.__reflect.ensure( Artifact ,function() return {["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="artifact"}},["name"]="cli"}},["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="root",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="format",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="KIND"},{["kind"]="value",["name"]="choices",["value"]={"lua","bytecode"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="kind",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="O"},{["kind"]="value",["name"]="long",["value"]=false},{["kind"]="value",["name"]="value",["value"]="LEVEL"},{["kind"]="value",["name"]="display",["value"]="-O0, -O1, -O2"},{["kind"]="value",["name"]="pattern",["value"]="^%-O([0-2])$"},{["kind"]="value",["name"]="choices",["value"]={"0","1","2"}}},["name"]="cli"}},["hasDefault"]=false,["kind"]="union",["name"]="optLevel",["readable"]=true,["stored"]=true,["type"]=2,["writable"]=true},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["kind"]="boolean",["name"]="schema",["readable"]=true,["stored"]=true,["type"]=5,["writable"]=true},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["kind"]="string",["name"]="file",["readable"]=true,["stored"]=true,["type"]=4,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="run",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true}},["fingerprint"]="f9dc02c1365020ec687d8c7b2fbb923a91890c2762821ff7ef3f65e9c744d835",["kind"]="record",["name"]="Artifact",["qualifiedName"]="Artifact",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="artifact"}},["name"]="cli"}},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={{["mode"]="plain",["name"]="root",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="format",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="kind",["optional"]=false,["type"]=4},{["mode"]="plain",["name"]="optLevel",["optional"]=true,["type"]=2},{["mode"]="plain",["name"]="schema",["optional"]=true,["type"]=5},{["mode"]="plain",["name"]="file",["optional"]=false,["type"]=4}},["requiresFactory"]=false},["copyable"]=true,["deriveKey"]="nupp.derive.runtime.v2:nupp.tools.cli.lsp:Artifact:1",["fields"]={{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="DIR"}},["name"]="cli"}},["hasDefault"]=false,["name"]="root",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="constantAliases",["value"]={["json"]="json",["text"]="text"}},{["kind"]="value",["name"]="value",["value"]="FORMAT"},{["kind"]="value",["name"]="choices",["value"]={"text","json"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="format",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="value",["value"]="KIND"},{["kind"]="value",["name"]="choices",["value"]={"lua","bytecode"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="kind",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="name",["value"]="O"},{["kind"]="value",["name"]="long",["value"]=false},{["kind"]="value",["name"]="value",["value"]="LEVEL"},{["kind"]="value",["name"]="display",["value"]="-O0, -O1, -O2"},{["kind"]="value",["name"]="pattern",["value"]="^%-O([0-2])$"},{["kind"]="value",["name"]="choices",["value"]={"0","1","2"}}},["name"]="cli"}},["hasDefault"]=false,["name"]="optLevel",["read"]=2,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=2},{["annotations"]={},["defaultValue"]=false,["hasDefault"]=true,["name"]="schema",["read"]=5,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=5},{["annotations"]={{["arguments"]={{["kind"]="value",["name"]="positional",["value"]="FILE"}},["name"]="cli"}},["hasDefault"]=false,["name"]="file",["read"]=4,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=4},{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.tools.cli.lsp",["name"]="Artifact",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={{["name"]="cliAliases",["read"]=10,["write"]=10},{["name"]="cliName",["read"]=14,["write"]=14},{["name"]="cliSummary",["read"]=14,["write"]=14},{["name"]="fromCLI",["read"]=16,["write"]=16},{["name"]="reportSchema",["read"]=22,["write"]=22}},["supertypes"]={25},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["kind"]="union",["members"]={3,4}},{["kind"]="nil"},{["kind"]="string"},{["kind"]="boolean"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=8,["parameters"]={{["mode"]="plain",["name"]="self",["type"]=1}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="integer"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=7}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=13,["returns"]={11},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=4,["kind"]="array"},{["alternatives"]={},["head"]={},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=11}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=15,["returns"]={4},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=4}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=13,["parameters"]={{["mode"]="plain",["name"]="argv",["type"]=11}},["returnPack"]=21,["returns"]={17,18},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={3,1}},{["kind"]="union",["members"]={3,19}},{["fields"]={{["name"]="destination",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="field",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="index",["read"]=20,["readable"]=true,["writable"]=false},{["name"]="kind",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="message",["read"]=4,["readable"]=true,["writable"]=false},{["name"]="option",["read"]=2,["readable"]=true,["writable"]=false},{["name"]="raw",["read"]=2,["readable"]=true,["writable"]=false}},["index"]={},["kind"]="shape"},{["kind"]="union",["members"]={7,3}},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=17},{["mode"]="plain",["type"]=18}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={},["returnPack"]=24,["returns"]={23},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="any"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=true,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="run",["read"]=26,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=26}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.cli",["name"]="Runnable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=28,["parameters"]={{["mode"]="plain",["name"]="",["type"]=27}},["returnPack"]=9,["returns"]={7},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["bound"]=25,["kind"]="typevar",["name"]="Runnable"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=27}},["kind"]="pack"}}},{["1"]="nupp.tools.cli.lsp\0runtime\00012",["25"]="../../../src/nupp/cli/init.g.nupp\0Runnable\0interface\0module\0001"} end) ) ,
}
end

function Inspect . reportSchema ( ) 
return OPERATION_SCHEMAS . inspect
end

function Definition . reportSchema ( ) 
return OPERATION_SCHEMAS . definition
end

function Implementation . reportSchema ( ) 
return OPERATION_SCHEMAS . implementation
end

function References . reportSchema ( ) 
return OPERATION_SCHEMAS . references
end

function Symbols . reportSchema ( ) 
return OPERATION_SCHEMAS . symbols
end

function Rename . reportSchema ( ) 
return OPERATION_SCHEMAS . rename
end

function Actions . reportSchema ( ) 
return OPERATION_SCHEMAS . actions
end

function TraceCheck . reportSchema ( ) 
return OPERATION_SCHEMAS [ "trace-check" ]
end

function Artifacts . reportSchema ( ) 
return OPERATION_SCHEMAS . artifacts
end

function Artifact . reportSchema ( ) 
return OPERATION_SCHEMAS . artifact
end

local __nuppExportValue= { commandType = Lsp } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.lsp"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.lsp"]=__nuppExports;return __nuppExports