_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






























const files = require ( "nupp.io.files" )

local lexer = require ( "nupp.compiler.syntax.lexer" )
local parser = require ( "nupp.compiler.syntax.parser" )
local semantic = require ( "nupp.tools.lsp.semantic" )
local syntaxstyle = require ( "nupp.tools.syntaxstyle" )
local stringsMod = require ( "nupp.tools.doc.strings" )
local filesMod = require ( "nupp.tools.doc.files" )

local htmlEscape = stringsMod . htmlEscape
local join , dirname , exists = filesMod . join , filesMod . dirname , filesMod . exists

local highlight = { }





local function qualifiedName ( tokens , index ) 
local name = tokens [ index ] . text
local cursor = index - 1
while cursor > 1 and tokens [ cursor ] . text == "." and tokens [ cursor - 1 ] . kind == "name" do
name = tokens [ cursor - 1 ] . text .. "." .. name
cursor = cursor - 2
end

return name
end

local function tokenClasses ( style , text ) 
if style == "type" then
return "token class-name nuppdoc-token-type"

elseif style == "meta" then
return "token directive nuppdoc-token-meta"

elseif style == "keyword" then
return "token keyword keyword-" .. text : gsub ( "[^%w%-]" , "-" ) .. " nuppdoc-token-keyword"
end

return "token " .. style .. " nuppdoc-token-" .. style
end

local function declarationName ( tokens , index ) 
local previous = tokens [ index - 1 ]
return previous
and (
previous . kind == "function" or previous . text == "metamethod" or syntaxstyle . TYPE_DECLARATIONS [ previous . text ]
)
end




local function lineWriter ( source ) 
if source == "" then
return {
lines = { } ,
append = function ( ) 
end
}
end
local lines = { "" }

local function append ( text , class , href ) 
local start = 1
while true do
local finish = text : find ( "\n" , start , true )
local piece = finish and text : sub ( start , finish - 1 ) or text : sub ( start )
local rendered = htmlEscape ( piece )
if class and piece ~= "" then
rendered = "<span class=\"" .. class .. "\">" .. rendered .. "</span>"
if href then
rendered = "<a class=\"nuppdoc-code-link nuppdoc-code-link-"
.. href . style
.. "\" href=\""
.. htmlEscape (
href . url
) .. "\">" .. rendered .. "</a>"
end
end
lines [ # lines ] = lines [ # lines ] .. rendered
if not finish then
do break end
end
lines [ # lines + 1 ] = ""
start = finish + 1
end
end

return { lines = lines , append = append }
end




local function containerMemberUrls ( parsed , memberLinks ) 
local urls = { }
if not memberLinks then
return urls
end
for _ , block in ipairs ( parsed . root . blocks or { } ) do
for _ , outer in ipairs ( block . stats or { } ) do
local declaration = outer
while declaration . kind == "pragmaStmt" and declaration . stat do
declaration = declaration . stat
end
if declaration . kind == "recordDecl" then
for _ , entry in ipairs ( declaration . entries or { } ) do
local name = entry . name
local url = name and memberLinks [ name . text ]
if url then
urls [ name ] = url
end
end
end
end
end

return urls
end

local function highlightNuppLines ( source , links , memberLinks ) 
local out = lineWriter ( source )
local parsed = parser . parse ( source , "documentation-code-block.nupp" )
local tokens = parsed . tokens
local syntaxKinds = semantic . syntaxKinds ( parsed )
local memberUrls = containerMemberUrls ( parsed , memberLinks )
for index , token in ipairs ( tokens ) do
for index = 1 , token . triviaCount do
local kind = lexer . triviaKind ( token , index )
local text = lexer . triviaText ( token , index )
if kind == "comment" or kind == "hashbang" then
out . append ( text , "token comment nuppdoc-token-comment" )
else
out . append ( text )
end
end
if token . kind ~= "eof" then
local style = syntaxstyle . token ( tokens , index , syntaxKinds )
local url = memberUrls [ token ]
if not url and links and token . kind == "name" and not declarationName ( tokens , index ) then
url = links [ qualifiedName ( tokens , index ) ] or links [ token . text ]
end
out . append ( token . text , tokenClasses ( style , token . text ) , url and { url = url , style = style } or nil )
end
end
if source : sub ( -1 ) == "\n" then
out . lines [ # out . lines ] = nil
end

return out . lines
end

local function highlightNupp ( source , links , memberLinks ) 
return table . concat ( highlightNuppLines ( source , links , memberLinks ) , "\n" )
end

local SCINTILLUA_ALIASES = {
[ "c++" ] = "cpp" ,
html = "hypertext" ,
js = "javascript" ,
md = "markdown" ,
sh = "bash" ,
shell = "bash" ,
ts = "typescript" ,
}
local scintilluaDirectory , scintilluaSearchPath , scintilluaLibrary = nil , nil , nil
local scintilluaBundled = false
local scintilluaLexers = { }





local BUNDLED_MODULE = "scintillua.lexers."
local BUNDLED_DIRECTORY = "@bundled/scintillua/lexers"

local function bundledName ( path ) 
if type ( path ) ~= "string" then
return nil
end

if path : sub ( 1 , 27 ) ~= "@bundled/scintillua/lexers/" then
return nil
end

return path : sub ( 28 ) : match ( "^([%w_+-]+)%.lua$" )
end







local function bundledLoadfile ( path , mode , env ) 
local chunk , err
local name = bundledName ( path )
if name then
chunk = package . preload [ "scintillua.lexers." .. name ]


if not chunk then
return nil , "cannot open " .. path
end
else
chunk , err = loadfile ( path )
if not chunk then
return nil , err
end
end


if env then
setfenv ( chunk , env )
end

return chunk
end





local LEXER_MODULE = "scintillua/lexers/lexer"

local function installedLexers ( ) 
for template in package . path : gmatch ( "[^;]+" ) do
local candidate = template : gsub ( "%?" , "scintillua/lexers/lexer" )
if exists ( candidate ) then
return dirname ( candidate )
end
end

return nil
end

local function configureScintillua ( root , settings ) 




local installed = installedLexers ( )
if installed and not exists ( join ( installed , "lexer.lua" ) ) then
installed = nil
end
local bundled = not installed and package . preload [ "scintillua.lexers.lexer" ] ~= nil
if not installed and not bundled then
scintilluaDirectory , scintilluaSearchPath , scintilluaLibrary , scintilluaLexers = nil , nil , nil , { }
scintilluaBundled = false
return
end
local base = installed or "@bundled/scintillua/lexers"
local searchPath = base
local lexerDir = settings and settings . lexers
if lexerDir then
local custom = join ( root , lexerDir )


if files . isDirectory ( custom ) then
searchPath = custom .. ";" .. base
end
end
if scintilluaSearchPath ~= searchPath then
scintilluaDirectory , scintilluaSearchPath , scintilluaLibrary , scintilluaLexers = base , searchPath , nil , { }
end
scintilluaBundled = bundled
end

local function loadScintillua ( language ) 
if not scintilluaDirectory then
return nil
end
language = tostring ( language or "" ) : lower ( )
language = SCINTILLUA_ALIASES [ language ] or language
if not language : match ( "^[%w_+-]+$" ) then
return nil
end
if scintilluaLexers [ language ] ~= nil then
return scintilluaLexers [ language ] or nil
end
if not scintilluaLibrary then
local chunk
if scintilluaBundled then
chunk = package . preload [ "scintillua.lexers.lexer" ]




if chunk then
setfenv ( chunk , setmetatable ( { loadfile = bundledLoadfile } , { __index = _G } ) )
end
else
chunk = loadfile ( join ( scintilluaDirectory , "lexer.lua" ) )
end
if not chunk then
return nil
end
local ok , library = pcall ( chunk )
if not ok or type ( library ) ~= "table" then
return nil
end
library . property = setmetatable ( { [ "scintillua.lexers" ] = scintilluaSearchPath , } , {
__index = function ( ) 
return ""
end ,
__newindex = function ( t , key , value ) 
rawset ( t , key , tostring ( value ) )
end ,
} )
scintilluaLibrary = library
end
local ok , loaded = pcall ( scintilluaLibrary . load , language )
scintilluaLexers [ language ] = ok and loaded or false

return ok and loaded or nil
end

local function scintilluaStyle ( tag ) 
local base = tostring ( tag or "default" ) : match ( "^[^%.]+" )
if base == "whitespace" or base == "default" then
return nil
end
if base == "comment" then
return "comment"

elseif base == "keyword" then
return "keyword"
end
if base == "string" or base == "regex" then
return "string"
end
if base == "number" then
return "number"
end
if base == "function" or base == "label" then
return "function"
end
if base == "type" or base == "class" then
return "type"
end
if base == "preprocessor" or base == "annotation" then
return "meta"
end
if base == "operator" then
return "operator"

elseif base == "constant" then
return "boolean"

elseif base == "property" then
return "property"
end
if base == "identifier" or base == "variable" then
return "variable"
end

return nil
end

local function highlightScintilluaLines ( source , language ) 
local loaded = loadScintillua ( language )
if not loaded then
return nil
end
local ok , tags = pcall ( loaded . lex , loaded , source )
if not ok or type ( tags ) ~= "table" then
return nil
end
local out , start = lineWriter ( source ) , 1
for index = 1 , # tags , 2 do
local finish = tonumber ( tags [ index + 1 ] )
if not finish then
return nil
end
local text = source : sub ( start , finish - 1 )
local style = scintilluaStyle ( tags [ index ] )
if style then
out . append ( text , tokenClasses ( style , text ) )
else
out . append ( text )
end
start = finish
end
if start <= # source then
out . append ( source : sub ( start ) )
end
if source : sub ( -1 ) == "\n" then
out . lines [ # out . lines ] = nil
end

return out . lines
end




local function highlightScintillua ( source , language ) 
local lines = highlightScintilluaLines ( source , language )
return lines and table . concat ( lines , "\n" ) or nil
end

local function codeLines ( source , language , links ) 
if language == "nupp" then
return highlightNuppLines ( source , links )
end
local highlighted = highlightScintilluaLines ( source , language )
if highlighted then
return highlighted
end
local out = lineWriter ( source )
out . append ( source )
if source : sub ( -1 ) == "\n" then
out . lines [ # out . lines ] = nil
end

return out . lines
end

local function codeHtml ( source , language , links ) 
return table . concat ( codeLines ( source , language , links ) , "\n" )
end

highlight . nuppSource = highlightNupp
highlight . scintilluaSource = highlightScintillua
highlight . codeHtml = codeHtml
highlight . codeLines = codeLines
highlight . configureScintillua = configureScintillua

local __nuppExportValue= highlight ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.highlight"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.highlight"]=__nuppExports;return __nuppExports