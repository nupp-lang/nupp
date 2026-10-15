_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
















local lexer = require ( "nupp.compiler.syntax.lexer" )
local parser = require ( "nupp.compiler.syntax.parser" )
local semantic = require ( "nupp.tools.lsp.semantic" )
local types = require ( "nupp.compiler.types" )

local syntaxstyle = { }









local TYPE_NAMES = { borrowed = true , ctype = true , metatable = true , owned = true , pinned = true , }
for name in pairs ( types . builtins ) do
TYPE_NAMES [ name ] = true
end

local CONTEXTUAL_KEYWORDS = {
[ "as" ] = true ,
associated = true ,
borrows = true ,
cdef = true ,
comptime = true ,
constructor = true ,
continue = true ,
exclusive = true ,
from = true ,
takes = true ,
const = true ,
global = true ,
interface = true ,
handle = true ,
[ "is" ] = true ,
keyof = true ,
satisfies = true ,
[ "new" ] = true ,
out = true ,
preserves = true ,
record = true ,
metamethod = true ,
scoped = true ,
[ "sealed" ] = true ,
suspension = true ,
unpackof = true ,
where = true ,
with = true ,
writekeyof = true ,
writeof = true ,
releases = true ,
retains = true ,
resumes = true ,
struct = true ,
type = true ,
yields = true ,
}

local LITERAL_KEYWORDS = { [ "false" ] = true , [ "nil" ] = true , [ "true" ] = true }



local DIRECTIVE_KEYWORDS = { comptime = true }

local PUNCTUATION = {
[ "(" ] = true ,
[ ")" ] = true ,
[ "[" ] = true ,
[ "]" ] = true ,
[ "{" ] = true ,
[ "}" ] = true ,
[ "," ] = true ,
[ ";" ] = true ,
[ ":" ] = true ,
[ "." ] = true ,
[ "@" ] = true ,
}

local TYPE_DECLARATIONS = { interface = true , record = true , struct = true , type = true , }



syntaxstyle . TYPE_DECLARATIONS = TYPE_DECLARATIONS

local SYNTAX_STYLES = {
decorator = "meta" ,
keyword = "keyword" ,
type = "type" ,
struct = "type" ,
interface = "type" ,
typeParameter = "type" ,
[ "function" ] = "function" ,
method = "function" ,
property = "property" ,
parameter = "variable" ,
variable = "variable" ,
}

local function tokenStyle ( tokens , index , syntaxKinds ) 
local token = tokens [ index ]
local previous = tokens [ index - 1 ]
local following = tokens [ index + 1 ]
if token . kind == "name" then
local syntaxKind = syntaxKinds [ token ]




if syntaxKind == "keyword" and DIRECTIVE_KEYWORDS [ token . text ] then
return "meta"
end
local syntaxStyle = SYNTAX_STYLES [ syntaxKind ]
if syntaxStyle then
return syntaxStyle
end
if DIRECTIVE_KEYWORDS [ token . text ] then
return "meta"
end
if CONTEXTUAL_KEYWORDS [ token . text ] then
return "keyword"
end
if TYPE_NAMES [ token . text ] or token . text : match ( "^%u" ) then
return "type"
end
if previous and previous . text == "@" then
return "meta"
end
if previous and previous . kind == "function" then
return "function"
end
if previous and previous . text == "metamethod" then
return "function"
end
if previous and TYPE_DECLARATIONS [ previous . text ] then
return "type"
end
if following and following . text == "(" then
return "function"
end
if previous and ( previous . text == "." or previous . text == ":" ) then
return "property"
end
return "variable"
elseif lexer . KEYWORDS [ token . kind ] then
return LITERAL_KEYWORDS [ token . text ] and "boolean" or "keyword"
elseif token . kind == "string"
or token . kind == "istringOpen"
or token . kind == "istringMid"
or token . kind == "istringClose"
then
return "string"
elseif token . kind == "number" then
return "number"
elseif PUNCTUATION [ token . text ] then
return token . text == "@" and "meta" or "punctuation"
end

return "operator"
end









function syntaxstyle . token ( tokens , index , syntaxKinds ) 
return tokenStyle ( tokens , index , syntaxKinds )
end












function syntaxstyle . spans ( source , name ) 
local parsed
local ok = pcall ( function ( ) 
parsed = parser . parse ( source , name or "highlight.nupp" )
end )
if not ok or parsed == nil or # ( parsed . errors or { } ) > 0 then
return nil
end
local tokens = parsed . tokens
local kinds = semantic . syntaxKinds ( parsed )
local spans = { }
for index , token in ipairs ( tokens ) do
for trivia = 1 , token . triviaCount do
local kind = lexer . triviaKind ( token , trivia )
local text = lexer . triviaText ( token , trivia )
local commented = kind == "comment" or kind == "hashbang"
spans [ # spans + 1 ] = { text = text , style = commented and "comment" or nil }
end
if token . kind ~= "eof" then
spans [ # spans + 1 ] = { text = token . text , style = tokenStyle ( tokens , index , kinds ) }
end
end

return spans
end

local __nuppExportValue= syntaxstyle ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.syntaxstyle"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.syntaxstyle"]=__nuppExports;return __nuppExports