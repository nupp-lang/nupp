_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);





local stringsMod = require ( "nupp.compiler.doc.strings" )
local htmlMod = require ( "nupp.compiler.doc.html" )
local highlightMod = require ( "nupp.compiler.doc.highlight" )
local extractMod = require ( "nupp.compiler.doc.extract" )
local urlsMod = require ( "nupp.compiler.doc.urls" )

local htmlEscape = stringsMod . htmlEscape
local summaryText = stringsMod . summaryText
local markdownHtml , tableHtml = htmlMod . markdownHtml , htmlMod . tableHtml
local inlineHtml = htmlMod . inlineHtml
local highlightNupp = highlightMod . nuppSource
local splitMembers = extractMod . splitMembers
local childModules = extractMod . children
local moduleFile = urlsMod . moduleFile

local api = { }










local DEFAULT_CONSTRUCTOR_PATTERN = "^new"

local function kindBadge ( kind )
return '<span class="nuppdoc-kind-badge nuppdoc-kind-' .. htmlEscape ( kind ) .. '">' .. htmlEscape ( kind ) .. '</span>'
end


local function annotationBadges ( annotations )
if not annotations or # annotations == 0 then
return ""
end
local marks = { }
for _ , annotation in ipairs ( annotations ) do
marks [ # marks + 1 ] = '<span class="nuppdoc-annotation">' .. htmlEscape ( annotation ) .. "</span>"
end

return '<div class="nuppdoc-annotations">' .. table . concat ( marks ) .. "</div>"
end




local function spelledParam ( param )
return ( param . mode and ( param . mode .. " " ) or "" ) .. param . name
end





local function htag ( level )
return "h" .. math . min ( level , 6 )
end




local function isConstructor ( item , pattern )
if pattern == "" or item . kind ~= "function" then
return false
end

return ( item . name : match ( "([^.]+)$" ) or item . name ) : match ( pattern ) ~= nil
end




local function displayKind ( item , constructorPattern )
if isConstructor ( item , constructorPattern or DEFAULT_CONSTRUCTOR_PATTERN ) then
return "constructor"
end

return item . kind
end

local function byName ( left , right )
local leftName , rightName = left . name : lower ( ) , right . name : lower ( )
if leftName == rightName then
return left . path < right . path
end

return leftName < rightName
end






local function itemGroups ( items , constructorPattern )
local pattern = constructorPattern or DEFAULT_CONSTRUCTOR_PATTERN
local groups = {
{ title = "Constructors" , path = "constructors" , kinds = false , items = { } } ,
{ title = "Types" , path = "types" , kinds = true , items = { } } ,
{ title = "Functions" , path = "functions" , kinds = true , items = { } } ,
{ title = "Values" , path = "values" , kinds = true , items = { } } ,
}
for _ , item in ipairs ( items ) do
local group = groups [ 2 ]
if isConstructor ( item , pattern ) then
group = groups [ 1 ]
elseif item . kind == "function" or item . kind == "method" then
group = groups [ 3 ]
elseif item . kind == "variable" then
group = groups [ 4 ]
end
group . items [ # group . items + 1 ] = item
end
for _ , group in ipairs ( groups ) do
table . sort ( group . items , byName )
end

return groups
end








local function unqualifiedName ( moduleName , name )
local tail = moduleName : match ( "([^.]+)$" ) or moduleName
local prefix = tail .. "."
if name : sub ( 1 , # prefix ) == prefix then
return name : sub ( # prefix + 1 )
end

return name
end



local function namespaceSummary ( modules , name )
local held = # childModules ( modules , name )

return held .. " module" .. ( held == 1 and "" or "s" )
end



local function nestedModules ( children , prefix , modules )
if # children == 0 then
return ""
end
local rows = { }
for _ , child in ipairs ( children ) do
rows [
# rows + 1
] = {
'<a href="' .. htmlEscape (
prefix .. moduleFile ( child . name )
) .. '"><code>' .. htmlEscape ( child . name ) .. '</code></a>' ,
child . namespace and namespaceSummary ( modules , child . name ) or inlineHtml ( summaryText ( child . text ) ) ,
}
end

return '<section class="nuppdoc-module-modules"><h2 id="modules">Submodules</h2>' .. tableHtml (
{ "Module" , "Description" } ,
rows
) .. "</section>"
end

local function moduleSummary ( module , constructorPattern )
local groups = itemGroups ( module . items , constructorPattern )
local out = { '<section class="nuppdoc-module-summary"><h2 id="module-contents">Module contents</h2>' }
for _ , group in ipairs ( groups ) do
if # group . items > 0 then
local rows = { }
for _ , item in ipairs ( group . items ) do
local row = {
'<a href="#' .. htmlEscape (
item . path
) .. '"><code>' .. htmlEscape ( unqualifiedName ( module . name , item . name ) ) .. '</code></a>'
}


if group . kinds then
row [ # row + 1 ] = kindBadge ( item . kind )
end
row [ # row + 1 ] = inlineHtml ( summaryText ( item . doc . text ) )
rows [ # rows + 1 ] = row
end
local headers = group . kinds and {
group . title : sub ( 1 , - 2 ) ,
"Kind" ,
"Description"
} or { group . title : sub ( 1 , - 2 ) , "Description" }
out [ # out + 1 ] = '<h3>' .. group . title .. '</h3>' .. tableHtml ( headers , rows )
end
end
out [ # out + 1 ] = "</section>"

return table . concat ( out )
end

local function inlineNupp ( source , links )
return "<code>" .. highlightNupp ( source , links ) .. "</code>"
end



local function raisesHtml ( raises , heading , links )
if # raises == 0 then
return ""
end
local entries = { }
for _ , condition in ipairs ( raises ) do
entries [ # entries + 1 ] = "<li>" .. markdownHtml ( condition , links ) .. "</li>"
end

return "<" .. heading .. ">Raises</" .. heading .. "><ul>" .. table . concat ( entries ) .. "</ul>"
end




local function structureMemberLinks ( item , links )
if not links or # item . members == 0 then
return nil
end
local members = { }
for _ , member in ipairs ( item . members ) do
local url = links [ item . name .. "." .. member . name ] or links [ member . path ]
if url then
members [ member . name ] = url
end
end

return next ( members ) and members or nil
end




local function memberHeading ( name , path , tag , extra , badge )
return '<div class="nuppdoc-api-member' .. (
extra or ""
) .. '" id="' .. htmlEscape (
path
) .. '"><' .. tag .. '><code>' .. htmlEscape (
name
) .. "</code>" .. (
badge and '<span class="nuppdoc-kind-badge nuppdoc-kind-' .. htmlEscape (
badge
) .. '">' .. htmlEscape ( badge ) .. "</span>" or ""
) .. '<a class="nuppdoc-header-anchor" href="#' .. htmlEscape (
path
) .. '" aria-label="Link to ' .. htmlEscape ( name ) .. '">#</a></' .. tag .. ">"
end









local function renderHtmlMembers (
out ,
members ,
links ,
level
)
local fields , methods , types = splitMembers ( members )
local hGroup , hName , hSub = htag ( level ) , htag ( level + 1 ) , htag ( level + 2 )
if # methods > 0 then
out [ # out + 1 ] = "<" .. hGroup .. ">Methods</" .. hGroup .. ">"
for _ , method in ipairs ( methods ) do
out [ # out + 1 ] = memberHeading ( method . name , method . path , hName )
out [ # out + 1 ] = annotationBadges ( method . annotations )
out [ # out + 1 ] = markdownHtml ( method . text , links )
out [
# out + 1
] = '<div class="nuppdoc-code-block" data-lang="nupp"><pre>'
.. '<code class="language-nupp">'
.. highlightNupp (
method . name .. ": " .. method . type ,
links
) .. "</code></pre></div>"
if # method . params > 0 then
local rows = { }
for _ , param in ipairs ( method . params ) do
rows [
# rows + 1
] = {
"<code>" .. htmlEscape ( spelledParam ( param ) ) .. "</code>" ,
inlineNupp ( param . type , links ) ,
markdownHtml ( param . text , links )
}
end
out [
# out + 1
] = "<" .. hSub .. ">Arguments</" .. hSub .. ">" .. tableHtml ( { "Name" , "Type" , "Description" } , rows )
end
if # method . returns > 0 then
local rows = { }
for _ , value in ipairs ( method . returns ) do
rows [ # rows + 1 ] = { inlineNupp ( value . type , links ) , markdownHtml ( value . text , links ) }
end
out [ # out + 1 ] = "<" .. hSub .. ">Returns</" .. hSub .. ">" .. tableHtml ( { "Type" , "Description" } , rows )
end
out [ # out + 1 ] = raisesHtml ( method . raises , hSub , links )
out [ # out + 1 ] = "</div>"
end
end
if # types > 0 then
out [ # out + 1 ] = "<" .. hGroup .. ">Types</" .. hGroup .. ">"
for _ , nested in ipairs ( types ) do
out [ # out + 1 ] = memberHeading ( nested . name , nested . path , hName , " nuppdoc-api-nested-type" , nested . type )
out [ # out + 1 ] = annotationBadges ( nested . annotations )
out [ # out + 1 ] = markdownHtml ( nested . text , links )
renderHtmlMembers ( out , nested . members , links , level + 2 )
out [ # out + 1 ] = "</div>"
end
end
if # fields > 0 then
out [ # out + 1 ] = "<" .. hGroup .. ">Fields</" .. hGroup .. ">"
for _ , field in ipairs ( fields ) do
out [ # out + 1 ] = memberHeading ( field . name , field . path , hName )
out [ # out + 1 ] = annotationBadges ( field . annotations )
out [ # out + 1 ] = markdownHtml ( field . text , links )
out [
# out + 1
] = '<div class="nuppdoc-code-block" data-lang="nupp"><pre>'
.. '<code class="language-nupp">'
.. highlightNupp (
field . name .. ": " .. field . type ,
links
) .. "</code></pre></div>"
out [ # out + 1 ] = "</div>"
end
end
end

local function renderHtmlItem (
out ,
item ,
links ,
constructorPattern
)
local kind = displayKind ( item , constructorPattern )
out [
# out + 1
] = '<section class="nuppdoc-api-item" id="' .. htmlEscape (
item . path
) .. '"><h3><code>' .. htmlEscape (
item . name
) .. '</code><span class="nuppdoc-kind-badge nuppdoc-kind-' .. htmlEscape (
kind
) .. '">' .. htmlEscape (
kind
) .. '</span><a class="nuppdoc-header-anchor" href="#' .. htmlEscape (
item . path
) .. '" aria-label="Link to ' .. htmlEscape ( item . name ) .. '">#</a></h3>'
out [ # out + 1 ] = annotationBadges ( item . annotations )
out [ # out + 1 ] = markdownHtml ( item . doc . text , links )
out [
# out + 1
] = '<div class="nuppdoc-code-block" data-lang="nupp"><pre>' .. '<code class="language-nupp">' .. highlightNupp (
item . signature ,
links ,
structureMemberLinks ( item , links )
) .. "</code></pre></div>"
if # item . typeargs > 0 then
local rows = { }
for _ , typearg in ipairs ( item . typeargs ) do
rows [ # rows + 1 ] = { "<code>" .. htmlEscape ( typearg . name ) .. "</code>" , markdownHtml ( typearg . text , links ) }
end
out [ # out + 1 ] = "<h4>Type parameters</h4>" .. tableHtml ( { "Name" , "Description" } , rows )
end
if # item . params > 0 then
local rows = { }
for _ , param in ipairs ( item . params ) do
rows [
# rows + 1
] = {
"<code>" .. htmlEscape ( spelledParam ( param ) ) .. "</code>" ,
inlineNupp ( param . type , links ) ,
markdownHtml ( param . text , links )
}
end
out [ # out + 1 ] = "<h4>Arguments</h4>" .. tableHtml ( { "Name" , "Type" , "Description" } , rows )
end
if # item . returns > 0 then
local rows = { }
for _ , value in ipairs ( item . returns ) do
rows [ # rows + 1 ] = { inlineNupp ( value . type , links ) , markdownHtml ( value . text , links ) }
end
out [ # out + 1 ] = "<h4>Returns</h4>" .. tableHtml ( { "Type" , "Description" } , rows )
end
out [ # out + 1 ] = raisesHtml ( item . raises , "h4" , links )
renderHtmlMembers ( out , item . members , links , 4 )
out [ # out + 1 ] = "</section>"
end

api . moduleSummary = moduleSummary
api . itemGroups = itemGroups
api . nestedModules = nestedModules
api . renderHtmlItem = renderHtmlItem
api . displayKind = displayKind

return api
