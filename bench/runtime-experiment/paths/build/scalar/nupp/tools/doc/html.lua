_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





































local stringsMod = require ( "nupp.tools.doc.strings" )
local highlightMod = require ( "nupp.tools.doc.highlight" )
local urlsMod = require ( "nupp.tools.doc.urls" )
local syntax = require ( "nupp.compiler.syntax.docsyntax" )
local utf8 = require ( "nupp.text.utf8" )

local trim , htmlEscape = stringsMod . trim , stringsMod . htmlEscape
local headingId = stringsMod . headingId
local rewriteSymbolLinks = urlsMod . rewriteSymbolLinks
local codeHtml = highlightMod . codeHtml

local html = { }









local function tableHtml ( headers , rows ) 
local out = { "<table><thead><tr>" }
for _ , header in ipairs ( headers ) do
out [ # out + 1 ] = "<th>" .. header .. "</th>"
end
out [ # out + 1 ] = "</tr></thead><tbody>"
for _ , row in ipairs ( rows ) do
out [ # out + 1 ] = "<tr>"
for _ , cell in ipairs ( row ) do
out [ # out + 1 ] = "<td>" .. cell .. "</td>"
end
out [ # out + 1 ] = "</tr>"
end
out [ # out + 1 ] = "</tbody></table>"

return table . concat ( out )
end

local function kindClass ( kind ) 
local class = kind : gsub ( "[^%w_-]+" , "-" )
return ( htmlEscape ( class ) )
end

local function kindBadge ( kind ) 
return "<span class=\"nuppdoc-kind-badge nuppdoc-kind-" .. kindClass ( kind ) .. "\">" .. htmlEscape ( kind ) .. "</span>"
end









local function headingBadge ( heading ) 
local name , _ , kind = heading : match ( "^(.-`[^`]+`)%s+([_*])([%l][%l ]*)%2$" )
if not name then
return heading , nil
end

return name , kind
end

local function markdownOutline ( text ) 
local out , fenced = { } , nil
for _ , line in ipairs ( syntax . lines : match ( tostring ( text or "" ) ) or { } ) do
local marker
fenced , marker = syntax . fenceState ( line , fenced , true )
if not marker and not fenced then
local hashes , heading = syntax . heading : match ( line )
if hashes and heading and # hashes <= 3 then
local name = headingBadge ( heading )



out [ # out + 1 ] = { path = headingId ( heading ) , name = name : gsub ( "[`*_]" , "" ) , level = # hashes }
end
end
end

return out
end

local codeGroupIndex = 0
local markdownHtml

local ADMONITION_TITLES = {
note = "Note" ,
info = "Info" ,
tip = "Tip" ,
warning = "Warning" ,
danger = "Danger" ,
seealso = "See also" ,
deepdive = "Dive deeper" ,
}




local COLLAPSED = { deepdive = true }



local function lineNumberStart ( options ) 
local start = options and syntax . lineNumber : match ( options )
return start and ( tonumber ( start ) ) or nil
end



local function lineNumbersHtml ( source , start ) 
local out , number = { "<span class=\"nuppdoc-line-numbers\" aria-hidden=\"true\">" } , start
for _ in ( source .. "\n" ) : gmatch ( "(.-)\n" ) do
out [ # out + 1 ] = "<span>" .. tostring ( number ) .. "</span>"
number = number + 1
end
out [ # out + 1 ] = "</span>"

return table . concat ( out )
end

local function codeBlockHtml ( source , language , links , firstLine ) 
language = language ~= "" and language or "text"
return "<div class=\"nuppdoc-code-block" .. (
firstLine and " has-line-numbers" or ""
) .. "\" data-lang=\"" .. htmlEscape (
language
) .. "\"><pre>" .. (
firstLine and lineNumbersHtml ( source , firstLine ) or ""
) .. "<code class=\"language-" .. htmlEscape (
language
) .. "\">" .. codeHtml ( source , language , links ) .. "</code></pre></div>"
end








local function urlFragmentEscape ( text ) 
return ( text : gsub ( "[^%w%-%._~]" , function ( c ) 
return ("%%%02X") : format ( c : byte ( ) )
end ) )
end

local function playgroundHtml ( source , caption ) 
local trimmed = trim ( source )
local title = caption or "Nupp playground: an editor that checks as you type"
local fallback = ""
if trimmed ~= "" then
fallback = "<div class=\"nuppdoc-code-block\" data-lang=\"nupp\""
.. " data-reader-source slot=\"reader-source\"><pre><code class=\"language-nupp\">"
.. htmlEscape (
trimmed
) .. "</code></pre></div>"
end

return "<nupp-playground class=\"nuppdoc-playground\" aria-label=\"" .. htmlEscape (
title
) .. "\"" .. (
trimmed ~= "" and " data-source=\"" .. urlFragmentEscape ( trimmed ) .. "\"" or ""
) .. ">" .. fallback .. "</nupp-playground>"
end




local function isPlayground ( block ) 
if block . language == "playground" then
return true
end
return block . language == "nupp" and block . playground == true and not block . firstLine
end

local function renderedCodeBlockHtml ( block , links ) 
if isPlayground ( block ) then
return playgroundHtml ( block . source , block . caption )
end
return codeBlockHtml ( block . source , block . language , links , block . firstLine )
end

local function codeGroupHtml ( blocks , links ) 
local captioned = false
for _ , block in ipairs ( blocks ) do
captioned = captioned or block . caption ~= nil
end
if not captioned then
local out = { "<div class=\"nuppdoc-code-group\" role=\"group\">" }
for _ , block in ipairs ( blocks ) do
out [ # out + 1 ] = renderedCodeBlockHtml ( block , links )
end
out [ # out + 1 ] = "</div>"
return table . concat ( out )
end
codeGroupIndex = codeGroupIndex + 1
local name = "nuppdoc-code-group-" .. tostring ( codeGroupIndex )
local out = { "<div class=\"nuppdoc-code-group\" role=\"radiogroup\" aria-label=\"Code examples\">" }




out [ # out + 1 ] = "<div class=\"nuppdoc-code-tabs\">"
for index , block in ipairs ( blocks ) do


local id = name .. "-" .. tostring ( index )
out [
# out + 1
] = "<input class=\"nuppdoc-code-tab-input\" type=\"radio\"" .. " name=\"" .. name .. "\" id=\"" .. id .. "\"" .. (
index == 1 and " checked" or ""
) .. "><label class=\"nuppdoc-code-tab\" for=\"" .. id .. "\">" .. htmlEscape (
block . caption or block . language
) .. "</label>"
end
out [ # out + 1 ] = "</div>"
for _ , block in ipairs ( blocks ) do
out [ # out + 1 ] = "<figure class=\"nuppdoc-code-panel\">" .. renderedCodeBlockHtml ( block , links ) .. "</figure>"
end
out [ # out + 1 ] = "</div>"

return table . concat ( out )
end

local function admonitionHtml ( kind , title , source , links ) 
title = title ~= "" and title or ADMONITION_TITLES [ kind ]
local body = "<div class=\"nuppdoc-admonition-body\">" .. markdownHtml ( source , links ) .. "</div>"
local classes = "nuppdoc-admonition nuppdoc-admonition-" .. htmlEscape ( kind )
if COLLAPSED [ kind ] then
return "<details class=\"" .. classes .. "\"><summary class=\"nuppdoc-admonition-title\">" .. htmlEscape (
title
) .. "</summary>" .. body .. "</details>"
end

return "<aside class=\"" .. classes .. "\" aria-label=\"" .. htmlEscape (
title
) .. "\">" .. "<p class=\"nuppdoc-admonition-title\">" .. htmlEscape ( title ) .. "</p>" .. body .. "</aside>"
end








local function readFence ( lines , index ) 
local _ , fence , rest = syntax . markdownFence : match ( lines [ index ] )
if not fence then
return nil , index
end
local language , options = syntax . fenceInfo : match ( rest or "" )
options = trim ( options or "" )

local function closes ( line ) 
local _ , closer , closerRest = syntax . markdownFence : match ( line )
return syntax . closes ( fence , closer , closerRest )
end

local code = { }
index = index + 1
while index <= # lines and not closes ( lines [ index ] ) do
code [ # code + 1 ] = lines [ index ]
index = index + 1
end

return {
language = language ~= "" and language or "text" ,
caption = syntax . caption : match ( options ) ,
firstLine = lineNumberStart ( options ) ,
playground = syntax . playground : match ( options ) ~= nil ,
source = table . concat ( code , "\n" ) ,
} , index + 1
end




local function readContainer ( lines , index ) 
local body , depth , fenced = { } , 1 , nil
index = index + 1
while index <= # lines do
local line = lines [ index ]
local marker
fenced , marker = syntax . fenceState ( line , fenced , true )
if not marker and not fenced then
local marker = trim ( line )
if marker == ":::" then
depth = depth - 1
if depth == 0 then
return table . concat ( body , "\n" ) , index + 1
end
elseif marker : match ( "^:::%s+[%w-]+" ) then
depth = depth + 1
end
end
body [ # body + 1 ] = line
index = index + 1
end

return nil , index
end




local function extractBlocks ( text , links , rendered ) 
local lines , out = syntax . lines : match ( text ) or { } , { }
local index = 1

local function placeholder ( markup ) 
rendered [ # rendered + 1 ] = markup
out [ # out + 1 ] = ""
out [ # out + 1 ] = ("<!--nuppdoc-block-%d-->") : format ( # rendered )
out [ # out + 1 ] = ""
end

while index <= # lines do
local line = lines [ index ]
local marker = trim ( line )
local directive , title = syntax . directive : match ( line )
title = trim ( title or "" )
if marker == "::: code-group" then
local blocks = { }
index = index + 1
while index <= # lines and trim ( lines [ index ] ) ~= ":::" do
local block , after = readFence ( lines , index )
if block then
blocks [ # blocks + 1 ] = block
index = after
else
index = index + 1
end
end
placeholder ( codeGroupHtml ( blocks , links ) )
elseif marker == "::: columns" then
local body , after = readContainer ( lines , index )
if body then
index = after - 1

local groups = { }
for _ , bodyLine in ipairs ( syntax . lines : match ( body ) or { } ) do
if bodyLine : match ( "^##%s" ) then
groups [ # groups + 1 ] = { }
end
if # groups > 0 then
local current = groups [ # groups ]
current [ # current + 1 ] = bodyLine
end
end

local sections = { }
for _ , group in ipairs ( groups ) do
sections [
# sections + 1
] = "<div class=\"nuppdoc-column\">" .. markdownHtml ( table . concat ( group , "\n" ) , links , 0 ) .. "</div>"
end

placeholder ( "<div class=\"nuppdoc-columns\">" .. table . concat ( sections ) .. "</div>" )
else
out [ # out + 1 ] = line
end
elseif directive and ADMONITION_TITLES [ directive ] then
local body , after = readContainer ( lines , index )
if body then
index = after - 1
placeholder ( admonitionHtml ( directive , title , body , links ) )
else
out [ # out + 1 ] = line
end
elseif syntax . markdownFence : match ( lines [ index ] ) then
local block , after = readFence ( lines , index )
index = after - 1
if isPlayground ( block ) then
placeholder ( renderedCodeBlockHtml ( block , links ) )
else
local markup = renderedCodeBlockHtml ( block , links )
if block . caption then
markup = "<figure class=\"nuppdoc-labeled-code\"><figcaption>" .. htmlEscape (
block . caption
) .. "</figcaption>" .. markup .. "</figure>"
end
placeholder ( markup )
end
else
out [ # out + 1 ] = line
end
index = index + 1
end

return table . concat ( out , "\n" )
end







local function headingSlugs ( text ) 
local slugs , out = { } , { }
for line in ( text .. "\n" ) : gmatch ( "(.-)\n" ) do
local hashes , heading = line : match ( "^(#+)%s+(.+)$" )
if hashes then
local name , badge = headingBadge ( heading )


slugs [ # slugs + 1 ] = { id = headingId ( heading ) , text = name : gsub ( "[`*_]" , "" ) , badge = badge }
out [ # out + 1 ] = badge and hashes .. " " .. name or line
else
out [ # out + 1 ] = line
end
end

return slugs , table . concat ( out , "\n" )
end




local parse , headings , headingIndex , headingShiftBy = nil , { } , 0 , 1







local function referenceLower ( text ) 
return ( text : gsub ( "[A-Z]" , function ( character ) 
return string . char ( ( string . byte ( character ) ) + 32 )
end ) )
end

local function lunamarkParser ( ) 
local lunamark = require ( "lunamark" )
local writer = lunamark . writer . html . new ( )
writer . header = function ( content , level ) 
headingIndex = headingIndex + 1
local heading = headings [ headingIndex ]
local id = heading and heading . id or "section"
local label = heading and heading . text or ""
level = math . min ( level + headingShiftBy , 6 )

return {
"<h" ,
level ,
" id=\"" ,
htmlEscape ( id ) ,
"\">" ,
content ,
heading and heading . badge and kindBadge ( heading . badge ) or "" ,
"<a class=\"nuppdoc-header-anchor\" href=\"#" ,
htmlEscape ( id ) ,
"\" aria-label=\"Link to " ,
htmlEscape ( label ) ,
"\">#</a></h" ,
level ,
">"
}
end

return lunamark . reader . markdown . new ( writer , {
fenced_code_blocks = true ,
header_attributes = true ,
pipe_tables = true ,
} )
end

local function buildParser ( ) 
local previousPreload = package . preload [ "lua-utf8" ]
local previousLoaded = package . loaded [ "lua-utf8" ]
package . loaded [ "lua-utf8" ] = nil
package . preload [ "lua-utf8" ] = function ( ) 
return { char = utf8 . encode , lower = referenceLower }
end
local ok , built = pcall ( lunamarkParser )
rawset ( package . preload , "lua-utf8" , previousPreload )
rawset ( package . loaded , "lua-utf8" , previousLoaded )
if not ok then
return nil , built
end

return built
end

markdownHtml = function ( text , links , headingShift ) 



text = tostring ( text or "" ) : gsub ( "\13\n?" , "\n" )
if text == "" then
return ""
end
if not parse then
local built , err = buildParser ( )
if not built then
error (
"nupp doc needs lunamark; declare it as a luarocks "
.. "dependency of the docs target and it is installed with "
.. "the build ("
.. tostring (
err
) .. ")" ,
0
)
end
parse = built
end
local rendered = { }




local prepared = extractBlocks ( text .. "\n" , links , rendered )



if links then
prepared = rewriteSymbolLinks ( prepared , function ( name ) 
return links [ name ]
end )
end
local slugs , withoutBadges = headingSlugs ( prepared )
headings , headingIndex , prepared = slugs , 0 , withoutBadges
headingShiftBy = headingShift == nil and 1 or headingShift



local out = parse ( prepared .. "\n" )
out = out : gsub ( "<!%-%-nuppdoc%-block%-(%d+)%-%->" , function ( index ) 


return rendered [ tonumber ( index ) ] or ""
end )

return trim ( out )
end




local function inlineHtml ( text , links ) 
local out = markdownHtml ( text , links )
local inner = out : match ( "^<p>(.*)</p>$" )
if inner and not inner : find ( "<p>" , 1 , true ) then
return inner
end

return out
end



html . urlFragmentEscape = urlFragmentEscape

html . tableHtml = tableHtml






html . kindBadge = kindBadge

html . markdownHtml = markdownHtml
html . inlineHtml = inlineHtml
html . markdownOutline = markdownOutline

local __nuppExportValue= html ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.html"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.html"]=__nuppExports;return __nuppExports