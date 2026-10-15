_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()








local stringsMod = require ( "nupp.tools.doc.strings" )
local htmlMod = require ( "nupp.tools.doc.html" )
local highlightMod = require ( "nupp.tools.doc.highlight" )
local extractMod = require ( "nupp.tools.doc.extract" )
local urlsMod = require ( "nupp.tools.doc.urls" )

local htmlEscape = stringsMod . htmlEscape
local summaryText = stringsMod . summaryText
local markdownHtml , tableHtml = htmlMod . markdownHtml , htmlMod . tableHtml
local inlineHtml = htmlMod . inlineHtml
local kindBadge = htmlMod . kindBadge
local highlightNupp = highlightMod . nuppSource
local childModules = extractMod . children
local moduleFile = urlsMod . moduleFile

local api = { }









local function annotationBadges ( annotations ) 
if not annotations or # annotations == 0 then
return ""
end
local marks = { }
for _ , annotation in ipairs ( annotations ) do
marks [ # marks + 1 ] = "<span class=\"nuppdoc-annotation\">" .. htmlEscape ( annotation ) .. "</span>"
end

return "<div class=\"nuppdoc-annotations\">" .. table . concat ( marks ) .. "</div>"
end




local function spelledParam ( param ) 
return ( param . mode and ( param . mode .. " " ) or "" ) .. param . name
end





local function htag ( level ) 
return "h" .. math . min ( level , 6 )
end




local function displayKind ( item ) 
if item . comptimeKind then
return "comptime " .. item . comptimeKind
end

return item . kind
end







local function memberKind ( member ) 
if member . comptimeKind then
return "comptime " .. member . comptimeKind
end
if member . isType then
return member . type
end
if member . isAlias then
return "type"
end
if member . isMetamethod then
return "metamethod"
end
if member . name == "constructor" then
return "constructor"
end
if member . isFunction then
return "method"
end

return "field"
end





local function displaySignature ( item ) 
if # item . members == 0 then
return item . signature
end

return item . signature .. " ..."
end

local function byName ( left , right ) 
local leftName , rightName = left . name : lower ( ) , right . name : lower ( )
if leftName == rightName then
return left . path < right . path
end

return leftName < rightName
end






local function itemGroups ( items ) 
local groups

= {
{ title = "Types" , path = "types" , kinds = true , items = { } } ,
{ title = "Functions" , path = "functions" , kinds = true , items = { } } ,
{ title = "Values" , path = "values" , kinds = true , items = { } } ,
}
for _ , item in ipairs ( items ) do
local group = groups [ 1 ]
if item . kind == "function" or item . kind == "method" then
group = groups [ 2 ]
elseif item . kind == "variable" then
group = groups [ 3 ]
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
"<a href=\"" .. htmlEscape (
prefix .. moduleFile ( child . name )
) .. "\"><code>" .. htmlEscape ( child . name ) .. "</code></a>" ,
child . namespace and namespaceSummary ( modules , child . name ) or inlineHtml ( summaryText ( child . text ) ) ,
}
end

return "<section class=\"nuppdoc-module-modules\"><h2 id=\"modules\">Submodules</h2>" .. tableHtml (
{ "Module" , "Description" } ,
rows
) .. "</section>"
end

local function moduleSummary ( module ) 
local groups = itemGroups ( module . items )
local out = { "<section class=\"nuppdoc-module-summary\"><h2 id=\"module-contents\">Module contents</h2>" }
for _ , group in ipairs ( groups ) do
if # group . items > 0 then
local rows = { }
for _ , item in ipairs ( group . items ) do
local row = {
"<a href=\"#" .. htmlEscape (
item . path
) .. "\"><code>" .. htmlEscape ( unqualifiedName ( module . name , item . name ) ) .. "</code></a>"
}
if group . kinds then
row [ # row + 1 ] = kindBadge ( displayKind ( item ) )
end
row [ # row + 1 ] = inlineHtml ( summaryText ( item . doc . text ) )
rows [ # rows + 1 ] = row
end
local headers = group . kinds and { group . title : sub ( 1 , -2 ) , "Kind" , "Description" }
or { group . title : sub ( 1 , -2 ) , "Description" }
out [ # out + 1 ] = "<h3>" .. group . title .. "</h3>" .. tableHtml ( headers , rows )
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
local rows = { }
for _ , raise in ipairs ( raises ) do
rows [ # rows + 1 ] = { inlineNupp ( raise . type , links ) , markdownHtml ( raise . text , links ) }
end

return "<" .. heading .. ">Raises</" .. heading .. ">" .. tableHtml ( { "Type" , "Condition" } , rows )
end




local function memberHeading ( name , path , tag , extra , badge ) 
return "<div class=\"nuppdoc-api-member" .. (
extra or ""
) .. "\" id=\"" .. htmlEscape (
path
) .. "\"><" .. tag .. "><code>" .. htmlEscape (
name
) .. "</code>" .. kindBadge (
badge
) .. "<a class=\"nuppdoc-header-anchor\" href=\"#" .. htmlEscape (
path
) .. "\" aria-label=\"Link to " .. htmlEscape ( name ) .. "\">#</a></" .. tag .. ">"
end




local function memberSpelling ( member ) 
if member . isAlias then
return "type " .. member . name .. ( member . generics or "" ) .. " = " .. member . type
end

return member . name .. ": " .. member . type
end

local function memberCode ( source , links ) 
return "<div class=\"nuppdoc-code-block\" data-lang=\"nupp\"><pre>" .. "<code class=\"language-nupp\">" .. highlightNupp (
source ,
links
) .. "</code></pre></div>"
end





local function memberSummary ( members , links ) 
if not members or # members == 0 then
return ""
end
local rows = { }
for _ , member in ipairs ( members ) do
rows [
# rows + 1
] = {
"<a href=\"#" .. htmlEscape ( member . path ) .. "\"><code>" .. htmlEscape ( member . name ) .. "</code></a>" ,
kindBadge ( memberKind ( member ) ) ,
inlineHtml ( summaryText ( member . text ) )
}
end

return "<div class=\"nuppdoc-api-members\"><h4>Members</h4>" .. tableHtml (
{ "Name" , "Kind" , "Description" } ,
rows
) .. "</div>"
end





local function renderHtmlMembers ( out , members , links , level ) 
local hName , hSub = ( "h" .. math . min ( level , 6 ) ) , ( "h" .. math . min ( ( level + 1 ) , 6 ) )
for _ , member in ipairs ( members or { } ) do
out [
# out + 1
] = memberHeading (
member . name ,
member . path ,
hName ,
member . isType and " nuppdoc-api-nested-type" or nil ,
memberKind ( member )
)


if not member . isType then
out [ # out + 1 ] = memberCode ( memberSpelling ( member ) , links )
end
out [ # out + 1 ] = annotationBadges ( member . annotations )
out [ # out + 1 ] = markdownHtml ( member . text , links )
if # member . params > 0 then
local rows = { }
for _ , param in ipairs ( member . params ) do
rows [
# rows + 1
] = {
"<code>" .. htmlEscape ( ( ( param . mode and ( param . mode .. " " ) or "" ) .. param . name ) ) .. "</code>" ,
inlineNupp ( param . type , links ) ,
markdownHtml ( param . text , links )
}
end
out [
# out + 1
] = "<" .. hSub .. ">Arguments</" .. hSub .. ">" .. tableHtml ( { "Name" , "Type" , "Description" } , rows )
end
if # member . returns > 0 then
local rows = { }
for _ , value in ipairs ( member . returns ) do
rows [ # rows + 1 ] = { inlineNupp ( value . type , links ) , markdownHtml ( value . text , links ) }
end
out [ # out + 1 ] = "<" .. hSub .. ">Returns</" .. hSub .. ">" .. tableHtml ( { "Type" , "Description" } , rows )
end
out [ # out + 1 ] = raisesHtml ( member . raises , hSub , links )
if member . isType then
out [ # out + 1 ] = memberSummary ( member . members , links )
renderHtmlMembers ( out , member . members , links , level + 1 )
end
out [ # out + 1 ] = "</div>"
end
end

local function renderHtmlItem ( out , item , links ) 
local kind = displayKind ( item )
out [
# out + 1
] = "<section class=\"nuppdoc-api-item\" id=\"" .. htmlEscape (
item . path
) .. "\"><h3><code>" .. htmlEscape (
item . name
) .. "</code>" .. kindBadge (
kind
) .. "<a class=\"nuppdoc-header-anchor\" href=\"#" .. htmlEscape (
item . path
) .. "\" aria-label=\"Link to " .. htmlEscape ( item . name ) .. "\">#</a></h3>"
out [ # out + 1 ] = memberCode ( displaySignature ( item ) , links )
out [ # out + 1 ] = annotationBadges ( item . annotations )
out [ # out + 1 ] = markdownHtml ( item . doc . text , links )
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
"<code>" .. htmlEscape ( ( ( param . mode and ( param . mode .. " " ) or "" ) .. param . name ) ) .. "</code>" ,
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
out [ # out + 1 ] = memberSummary ( item . members , links )
renderHtmlMembers ( out , item . members , links , 4 )
out [ # out + 1 ] = "</section>"
end

api . moduleSummary = moduleSummary
api . itemGroups = itemGroups
api . nestedModules = nestedModules
api . renderHtmlItem = renderHtmlItem
api . displayKind = displayKind
api . displaySignature = displaySignature
api . memberKind = memberKind
api . memberSpelling = memberSpelling

local __nuppExportValue= api ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.api"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.api"]=__nuppExports;return __nuppExports