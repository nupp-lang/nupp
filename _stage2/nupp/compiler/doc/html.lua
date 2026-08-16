_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






























local stringsMod = require ( "nupp.compiler.doc.strings" )
local highlightMod = require ( "nupp.compiler.doc.highlight" )
local urlsMod = require ( "nupp.compiler.doc.urls" )
local syntax = require ( "nupp.compiler.doc.syntax" )

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

local function markdownOutline ( text )
local out , fenced = { } , nil
for _ , line in ipairs ( syntax . lines : match ( tostring ( text or "" ) ) or { } ) do
local marker
fenced , marker = syntax . fenceState ( line , fenced , true )
if not marker and not fenced then
local hashes , heading = syntax . heading : match ( line )
if hashes and heading and # hashes <= 3 then
out [ # out + 1 ] = { path = headingId ( heading ) , name = heading : gsub ( "[`*_]" , "" ) , level = # hashes }
end
end
end

return out
end

local codeGroupIndex = 0
local markdownHtml

local ADMONITION_TITLES = { note = "Note" , info = "Info" , tip = "Tip" , warning = "Warning" , danger = "Danger" , }



local function lineNumberStart ( options )
local start = options and syntax . lineNumber : match ( options )
return start and ( tonumber ( start ) ) or nil
end



local function lineNumbersHtml ( source , start )
local out , number = { '<span class="nuppdoc-line-numbers" aria-hidden="true">' } , start
for _ in ( source .. "\n" ) : gmatch ( "(.-)\n" ) do
out [ # out + 1 ] = "<span>" .. tostring ( number ) .. "</span>"
number = number + 1
end
out [ # out + 1 ] = "</span>"

return table . concat ( out )
end

local function codeBlockHtml ( source , language , links , firstLine )
language = language ~= "" and language or "text"
return '<div class="nuppdoc-code-block' .. (
firstLine and " has-line-numbers" or ""
) .. '" data-lang="' .. htmlEscape (
language
) .. '"><pre>' .. (
firstLine and lineNumbersHtml ( source , firstLine ) or ""
) .. '<code class="language-' .. htmlEscape (
language
) .. '">' .. codeHtml ( source , language , links ) .. "</code></pre></div>"
end








local function urlFragmentEscape ( text )
return ( text : gsub ( "[^%w%-%._~]" , function ( c )
return ( "%%%02X" ) : format ( c : byte ( ) )
end ) )
end

local function playgroundHtml ( source , caption )
local trimmed = trim ( source )
local title = caption or "Nupp playground: an editor that checks as you type"
local fallback = ""
if trimmed ~= "" then
fallback = '<div class="nuppdoc-code-block" data-lang="nupp"'
.. ' data-reader-source slot="reader-source"><pre><code class="language-nupp">'
.. htmlEscape (
trimmed
) .. "</code></pre></div>"
end

return '<nupp-playground class="nuppdoc-playground" aria-label="' .. htmlEscape (
title
) .. '"' .. (
trimmed ~= "" and ' data-source="' .. urlFragmentEscape ( trimmed ) .. '"' or ""
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
local labeled = { }
for _ , block in ipairs ( blocks ) do
if block . caption then
labeled [ # labeled + 1 ] = block
end
end
if # labeled == 0 then
local out = { '<div class="nuppdoc-code-group" role="group">' }
for _ , block in ipairs ( blocks ) do
out [ # out + 1 ] = renderedCodeBlockHtml ( block , links )
end
out [ # out + 1 ] = "</div>"
return table . concat ( out )
end
codeGroupIndex = codeGroupIndex + 1
local name = "nuppdoc-code-group-" .. tostring ( codeGroupIndex )
local out = { '<div class="nuppdoc-code-group" role="radiogroup"' .. ' aria-label="Code examples">' }
for index , block in ipairs ( labeled ) do
local id = name .. "-" .. tostring ( index )
out [
# out + 1
] = '<input class="nuppdoc-code-tab-input" type="radio"' .. ' name="' .. name .. '" id="' .. id .. '"' .. (
index == 1 and " checked" or ""
) .. '><label class="nuppdoc-code-tab" for="' .. id .. '">' .. htmlEscape (
block . caption
) .. '</label><figure class="nuppdoc-code-panel">' .. renderedCodeBlockHtml ( block , links ) .. '</figure>'
end
out [ # out + 1 ] = "</div>"

return table . concat ( out )
end

local function admonitionHtml ( kind , title , source , links )
title = title ~= "" and title or ADMONITION_TITLES [ kind ]
return '<aside class="nuppdoc-admonition nuppdoc-admonition-' .. htmlEscape (
kind
) .. '" aria-label="' .. htmlEscape (
title
) .. '">' .. '<p class="nuppdoc-admonition-title">' .. htmlEscape (
title
) .. "</p>" .. '<div class="nuppdoc-admonition-body">' .. markdownHtml ( source , links ) .. "</div></aside>"
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
out [ # out + 1 ] = ( "<!--nuppdoc-block-%d-->" ) : format ( # rendered )
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
markup = '<figure class="nuppdoc-labeled-code"><figcaption>' .. htmlEscape (
block . caption
) .. '</figcaption>' .. markup .. '</figure>'
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
local slugs = { }
for line in ( text .. "\n" ) : gmatch ( "(.-)\n" ) do
local hashes , heading = line : match ( "^(#+)%s+(.+)$" )
if hashes then
slugs [ # slugs + 1 ] = { id = headingId ( heading ) , text = heading }
end
end

return slugs
end




local parse , headings , headingIndex , headingShiftBy = nil , { } , 0 , 1

local function buildParser ( )
local ok , lunamark = pcall ( require , "lunamark" )
if not ok then
return nil , lunamark
end
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
' id="' ,
htmlEscape ( id ) ,
'">' ,
content ,
'<a class="nuppdoc-header-anchor" href="#' ,
htmlEscape ( id ) ,
'" aria-label="Link to ' ,
htmlEscape ( label ) ,
'">#</a></h' ,
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

markdownHtml = function ( text , links , headingShift )



text = tostring ( text or "" ) : gsub ( "\r\n?" , "\n" )
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
headings , headingIndex = headingSlugs ( prepared ) , 0
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
html . markdownHtml = markdownHtml
html . inlineHtml = inlineHtml
html . markdownOutline = markdownOutline

return html
