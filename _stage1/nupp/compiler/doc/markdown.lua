_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






local stringsMod = require ( "nupp.compiler.doc.strings" )
local extractMod = require ( "nupp.compiler.doc.extract" )
local urlsMod = require ( "nupp.compiler.doc.urls" )
local apiMod = require ( "nupp.compiler.doc.api" )

local markdownEscape , markdownCell = stringsMod . markdownEscape , stringsMod . markdownCell
local summaryText = stringsMod . summaryText
local childModules = extractMod . children
local symbolLinkIndex = urlsMod . symbolLinkIndex
local rewriteSymbolLinks = urlsMod . rewriteSymbolLinks
local itemGroups = apiMod . itemGroups
local displayKind = apiMod . displayKind

local markdown = { }





local anchors = nil
local known = nil





local function prose ( text )
local text = tostring ( text or "" )
if not anchors then
return text
end

return rewriteSymbolLinks ( text , function ( name )
return anchors [ name ] or known and known [ name ]
end )
end



local function cell ( text )
return markdownCell ( prose ( text ) )
end

local splitMembers = extractMod . splitMembers



local function heading ( level )
return ( "#" ) : rep ( math . min ( level , 6 ) )
end


local function markdownAnnotations ( out , annotations )
if not annotations or # annotations == 0 then
return
end
local marks = { }
for index , annotation in ipairs ( annotations ) do
marks [ index ] = "`" .. markdownEscape ( annotation ) .. "`"
end
out [ # out + 1 ] = table . concat ( marks , " " )
out [ # out + 1 ] = ""
end

local function markdownArguments ( out , params , heading )
if # params == 0 then
return
end
out [ # out + 1 ] = heading .. " Arguments"
out [ # out + 1 ] = ""
out [ # out + 1 ] = "| Name | Type | Description |"
out [ # out + 1 ] = "| --- | --- | --- |"
for _ , param in ipairs ( params ) do


local spelled = ( param . mode and ( param . mode .. " " ) or "" ) .. param . name
out [
# out + 1
] = "| `" .. markdownEscape (
spelled
) .. "` | `" .. markdownEscape ( param . type ) .. "` | " .. cell ( param . text ) .. " |"
end
out [ # out + 1 ] = ""
end

local function markdownReturns ( out , returns , heading )
if # returns == 0 then
return
end
out [ # out + 1 ] = heading .. " Returns"
out [ # out + 1 ] = ""
out [ # out + 1 ] = "| Type | Description |"
out [ # out + 1 ] = "| --- | --- |"
for _ , value in ipairs ( returns ) do
out [ # out + 1 ] = "| `" .. markdownEscape ( value . type ) .. "` | " .. cell ( value . text ) .. " |"
end
out [ # out + 1 ] = ""
end



local function markdownRaises ( out , raises , heading )
if # raises == 0 then
return
end
out [ # out + 1 ] = heading .. " Raises"
out [ # out + 1 ] = ""
for _ , condition in ipairs ( raises ) do
out [ # out + 1 ] = "- " .. cell ( condition )
end
out [ # out + 1 ] = ""
end








local function renderMarkdownMembers ( out , members , level )
local fields , methods , types = splitMembers ( members )
local hGroup , hName , hSub = heading ( level ) , heading ( level + 1 ) , heading ( level + 2 )
if # methods > 0 then
out [ # out + 1 ] = hGroup .. " Methods"
out [ # out + 1 ] = ""
for _ , method in ipairs ( methods ) do
out [ # out + 1 ] = '<a id="' .. method . path .. '"></a>'
out [ # out + 1 ] = hName .. " `" .. method . name .. "`"
out [ # out + 1 ] = ""
markdownAnnotations ( out , method . annotations )
if method . text ~= "" then
out [ # out + 1 ] = prose ( method . text )
out [ # out + 1 ] = ""
end
out [ # out + 1 ] = "```nupp"
out [ # out + 1 ] = method . name .. ": " .. method . type
out [ # out + 1 ] = "```"
out [ # out + 1 ] = ""
markdownArguments ( out , method . params , hSub )
markdownReturns ( out , method . returns , hSub )
markdownRaises ( out , method . raises , hSub )
end
end
if # types > 0 then
out [ # out + 1 ] = hGroup .. " Types"
out [ # out + 1 ] = ""
for _ , nested in ipairs ( types ) do
out [ # out + 1 ] = '<a id="' .. nested . path .. '"></a>'
out [ # out + 1 ] = hName .. " `" .. nested . name .. "` _" .. nested . type .. "_"
out [ # out + 1 ] = ""
markdownAnnotations ( out , nested . annotations )
if nested . text ~= "" then
out [ # out + 1 ] = prose ( nested . text )
out [ # out + 1 ] = ""
end
renderMarkdownMembers ( out , nested . members , level + 2 )
end
end
if # fields > 0 then
out [ # out + 1 ] = hGroup .. " Fields"
out [ # out + 1 ] = ""
for _ , field in ipairs ( fields ) do
out [ # out + 1 ] = '<a id="' .. field . path .. '"></a>'
out [ # out + 1 ] = hName .. " `" .. field . name .. "`"
out [ # out + 1 ] = ""
markdownAnnotations ( out , field . annotations )
if field . text ~= "" then
out [ # out + 1 ] = prose ( field . text )
out [ # out + 1 ] = ""
end
out [ # out + 1 ] = "```nupp"
out [ # out + 1 ] = field . name .. ": " .. field . type
out [ # out + 1 ] = "```"
out [ # out + 1 ] = ""
end
end
end

local function renderMarkdownItem ( out , item , constructorPattern , level )
level = level or 3
local h , hSub = heading ( level ) , heading ( level + 1 )
out [ # out + 1 ] = '<a id="' .. item . path .. '"></a>'
out [ # out + 1 ] = h .. " `" .. item . name .. "` _" .. displayKind ( item , constructorPattern ) .. "_"
out [ # out + 1 ] = ""
markdownAnnotations ( out , item . annotations )



if item . doc . text ~= "" then
out [ # out + 1 ] = prose ( item . doc . text ) ;
out [ # out + 1 ] = ""
end
out [ # out + 1 ] = "```nupp"
out [ # out + 1 ] = item . signature
out [ # out + 1 ] = "```"
out [ # out + 1 ] = ""
if # item . typeargs > 0 then
out [ # out + 1 ] = hSub .. " Type parameters"
out [ # out + 1 ] = ""
out [ # out + 1 ] = "| Name | Description |"
out [ # out + 1 ] = "| --- | --- |"
for _ , typearg in ipairs ( item . typeargs ) do
out [ # out + 1 ] = "| `" .. markdownEscape ( typearg . name ) .. "` | " .. cell ( typearg . text ) .. " |"
end
out [ # out + 1 ] = ""
end
markdownArguments ( out , item . params , hSub )
markdownReturns ( out , item . returns , hSub )
markdownRaises ( out , item . raises , hSub )
renderMarkdownMembers ( out , item . members , level + 1 )
end













function markdown . items ( items , level , constructorPattern )
local out = { }
for _ , item in ipairs ( items ) do
renderMarkdownItem ( out , item , constructorPattern , level or 3 )
end

return table . concat ( out , "\n" )
end










function markdown . render (
modules ,
title ,
all ,
overview ,
constructorPattern
)
local all = all or modules
anchors = symbolLinkIndex ( modules , function ( module , path )
return "#" .. ( path or module )
end )
known = symbolLinkIndex ( all , function ( )
return ""
end )
local out = { }
if title and title ~= "" then
out [ # out + 1 ] = "# " .. title ;
out [ # out + 1 ] = ""
end
for moduleIndex , module in ipairs ( modules ) do
out [ # out + 1 ] = '<a id="' .. module . name .. '"></a>'
out [ # out + 1 ] = ( module . namespace and "# Namespace: `" or "# Module: `" ) .. module . name .. "`"
out [ # out + 1 ] = ""


if overview and overview ~= "" then
out [ # out + 1 ] = overview
out [ # out + 1 ] = ""
if module . text ~= "" then
out [ # out + 1 ] = prose ( module . text )
out [ # out + 1 ] = ""
end
elseif module . namespace then
out [ # out + 1 ] = "Modules nested under `" .. module . name .. "`. Nothing is required by this name itself."
out [ # out + 1 ] = ""
elseif module . text ~= "" then
out [ # out + 1 ] = prose ( module . text ) ;
out [ # out + 1 ] = ""
end
local children = childModules ( all , module . name )
if # children > 0 then
out [ # out + 1 ] = "## Submodules"
out [ # out + 1 ] = ""
out [ # out + 1 ] = "| Module | Description |"
out [ # out + 1 ] = "| --- | --- |"
for _ , child in ipairs ( children ) do


local label = "`" .. markdownEscape ( child . name ) .. "`"
local anchor = anchors and anchors [ child . name ]
local held = # childModules ( all , child . name )
local description = child . namespace and held .. " module" .. (
held == 1 and "" or "s"
) or markdownCell ( summaryText ( child . text ) )
out [
# out + 1
] = "| " .. ( anchor and "[" .. label .. "](" .. anchor .. ")" or label ) .. " | " .. description .. " |"
end
out [ # out + 1 ] = ""
end
for _ , group in ipairs ( itemGroups ( module . items , constructorPattern ) ) do
if # group . items > 0 then
out [ # out + 1 ] = "## " .. group . title
out [ # out + 1 ] = ""
for _ , item in ipairs ( group . items ) do
renderMarkdownItem ( out , item , constructorPattern )
end
end
end
if moduleIndex < # modules then
out [ # out + 1 ] = "---" ;
out [ # out + 1 ] = ""
end
end
anchors , known = nil , nil

return table . concat ( out , "\n" ) .. "\n"
end

return markdown
