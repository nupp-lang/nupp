_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



















const files = require ( "nupp.io.files" )



local stringsMod = require ( "nupp.tools.doc.strings" )
local filesMod = require ( "nupp.tools.doc.files" )
local extractMod = require ( "nupp.tools.doc.extract" )
local markdownMod = require ( "nupp.tools.doc.markdown" )
local highlightMod = require ( "nupp.tools.doc.highlight" )
local htmlMod = require ( "nupp.tools.doc.html" )
local assetsMod = require ( "nupp.tools.doc.assets" )
local urlsMod = require ( "nupp.tools.doc.urls" )
local apiMod = require ( "nupp.tools.doc.api" )
local pageMod = require ( "nupp.tools.doc.page" )
local collectionMod = require ( "nupp.tools.doc.collection" )
local sweepMod = require ( "nupp.tools.doc.sweep" )
local homeMod = require ( "nupp.tools.doc.home" )
local frontmatterMod = require ( "nupp.tools.doc.frontmatter" )
local diagnosticsMod = require ( "nupp.tools.doc.diagnostics" )
local stdlibMod = require ( "nupp.tools.doc.stdlib" )
local json = require ( "nupp.codec.json" )

local trim , htmlEscape = stringsMod . trim , stringsMod . htmlEscape
local escapeJs = stringsMod . escapeJs
local normalize , join , dirname = filesMod . normalize , filesMod . join , filesMod . dirname
local readFile , writeFile = filesMod . readFile , filesMod . writeFile
local listFiles , privateSource = filesMod . listFiles , filesMod . privateSource
local copyPublicFiles = filesMod . copyPublicFiles
local moduleName , childModules = extractMod . moduleName , extractMod . children
local namespaceModules = extractMod . namespaces
local internalModuleName = extractMod . internalModuleName
local configureScintillua = highlightMod . configureScintillua
local markdownHtml , markdownOutline = htmlMod . markdownHtml , htmlMod . markdownOutline
local THEME , SCRIPT = assert ( assetsMod . theme ( ) ) , assetsMod . SCRIPT
local moduleFile , routeFile = urlsMod . moduleFile , urlsMod . routeFile
local relativePrefix , cleanRoute = urlsMod . relativePrefix , urlsMod . cleanRoute
local symbolLinkIndex , symbolLinks = urlsMod . symbolLinkIndex , urlsMod . symbolLinks
local rewriteConfiguredPageLinks = urlsMod . rewriteConfiguredPageLinks
local moduleSummary , renderHtmlItem , itemGroups = apiMod . moduleSummary , apiMod . renderHtmlItem , apiMod . itemGroups
local nestedModules = apiMod . nestedModules
local renderPage , homeHero , homeFeatures = pageMod . render , pageMod . homeHero , pageMod . homeFeatures

local doc = { }













































































































































function doc . extract (
source ,
path ,
name ,
opts
) 
return extractMod . extract ( source , path , name , opts )
end





function doc . markdown (
modules ,
title ,
all ,
overview
) 
return markdownMod . render ( modules , title , all , overview )
end





local function sortedJson ( value ) 
if type ( value ) ~= "table" or value == json . EMPTY_ARRAY or value == json . EMPTY_OBJECT or value == json . NULL then
return json . encode ( value )
end
local entries = value
local parts = { }
if json . isArray ( entries ) then
for index = 1 , # entries do
parts [ index ] = sortedJson ( entries [ index ] )
end

return "[" .. table . concat ( parts , "," ) .. "]"
end
local keys = { }
for key in pairs ( entries ) do
if type ( key ) ~= "string" then
error ( "JSON object keys must be strings" , 0 )
end
keys [ # keys + 1 ] = key
end
table . sort ( keys )
for index , key in ipairs ( keys ) do
parts [ index ] = json . encode ( key ) .. ":" .. sortedJson ( entries [ key ] )
end

return "{" .. table . concat ( parts , "," ) .. "}"
end




function doc . json ( modules ) 
local function array ( items , convert ) 
local out = json . asArray ( { } )
for _ , item in ipairs ( items or { } ) do
out [ # out + 1 ] = convert and convert ( item ) or item
end

return out
end

local function annotations ( items ) 
return items and array ( items ) or nil
end

local function param ( value ) 
return { name = value . name , type = value . type , mode = value . mode , text = value . text }
end

local function result ( value ) 
return { type = value . type , text = value . text }
end



local function raise ( value ) 
return { type = value . type , text = value . text }
end

local member
member = function ( value ) 
return {
name = value . name ,
type = value . type ,
text = value . text ,
path = value . path ,
params = array ( value . params , param ) ,
returns = array ( value . returns , result ) ,
raises = array ( value . raises , raise ) ,
isFunction = value . isFunction ,
isMetamethod = value . isMetamethod ,
isType = value . isType ,
comptimeKind = value . comptimeKind ,
members = value . members and array ( value . members , member ) or nil ,
annotations = annotations ( value . annotations ) ,
}
end

local function item ( value ) 
local info = value . doc

return {
name = value . name ,
kind = value . kind ,
comptimeKind = value . comptimeKind ,
signature = value . signature ,
path = value . path ,
module = value . module ,
line = value . line ,
doc = {
text = info . text ,
params = info . params ,
returns = array ( info . returns ) ,
raises = array ( info . raises , raise ) ,
fields = info . fields ,
typeargs = info . typeargs ,
tags = info . tags ,
} ,
members = array ( value . members , member ) ,
params = array ( value . params , param ) ,
returns = array ( value . returns , result ) ,
raises = array ( value . raises , raise ) ,
typeargs = array (
value . typeargs ,
function ( typearg ) 
return { name = typearg . name , text = typearg . text }
end
) ,
annotations = annotations ( value . annotations ) ,
}
end

local model = array ( modules , function ( value ) 
return {
name = value . name ,
path = value . path ,
text = value . text ,
items = array ( value . items , item ) ,
documentationInternal = value . documentationInternal ,
namespace = value . namespace ,
}
end )

return sortedJson ( { schemaVersion = 3 , modules = model } ) .. "\n"
end





local function sourceFiles ( root , config , settings , requested ) 
local paths , seen = { } , { }
local sources = requested and # requested > 0 and requested or settings . sources or config . include or { "." }
for _ , source in ipairs ( sources ) do
local path = join ( root , source )
local candidates = path : match ( "%.nupp$" ) and { path } or listFiles ( path )
for _ , candidate in ipairs ( candidates ) do
candidate = normalize ( candidate )
if not seen [ candidate ] then
seen [ candidate ] = true
paths [ # paths + 1 ] = candidate
end
end
end
table . sort ( paths )

return paths
end

local function byKindThenName ( left , right ) 
if left . kind == right . kind then
return left . name < right . name
end
return left . kind < right . kind
end

local function loadModules ( root , config , settings , requested ) 
local modules = { }
local errors




= { }
local namespaceBacked , implied = { } , { }
for _ , path in ipairs ( sourceFiles ( root , config , settings , requested ) ) do
local source , readErr = readFile ( path )
if not source then
errors [ # errors + 1 ] = { filename = path , line = 1 , col = 1 , msg = tostring ( readErr ) }
else
local name = moduleName ( path , root , config . include or { } )
local module , parseErrors , extraModules = doc . extract ( source , path , name , {
includePrivate = settings . includePrivate
} )
if module then
modules [ # modules + 1 ] = module
for _ , extra in ipairs ( extraModules or { } ) do
modules [ # modules + 1 ] = extra
namespaceBacked [ extra . name ] = true
implied [ extra ] = true
end
else
for _ , err in ipairs ( parseErrors ) do
errors [ # errors + 1 ] = err
end
end
end
end






local keeper = { }
local order = { }
for _ , module in ipairs ( modules ) do
local held = keeper [ module . name ]
if not held then
keeper [ module . name ] = module
order [ # order + 1 ] = module . name
elseif implied [ held ] and not implied [ module ] then
keeper [ module . name ] = module
end
end
for _ , module in ipairs ( modules ) do
local into = keeper [ module . name ]
if into ~= module then




local byPath = { }
for _ , item in ipairs ( into . items ) do
byPath [ item . path ] = item
end
for _ , item in ipairs ( module . items ) do
local held = byPath [ item . path ]
if not held then
into . items [ # into . items + 1 ] = item
byPath [ item . path ] = item
elseif held . doc . text == "" then
held . doc = item . doc
end
end
if into . text == "" then
into . text = module . text
end
into . documentationInternal = into . documentationInternal or module . documentationInternal
end
end
if # order < # modules then
local folded = { }
for _ , name in ipairs ( order ) do
folded [ # folded + 1 ] = keeper [ name ]
end
modules = folded
end








local byName = { }
for _ , module in ipairs ( modules ) do
byName [ module . name ] = byName [ module . name ] or module
end





local function copy ( value ) 
if type ( value ) ~= "table" then
return value
end
local out = { }
for key , child in pairs ( value ) do
out [ key ] = copy ( child )
end

return out
end





local declarationWords = { }
for _ , word in ipairs ( {
"affine" ,
"cdef" ,
"comptime" ,
"const" ,
"function" ,
"global" ,
"interface" ,
"local" ,
"record" ,
"sealed" ,
"struct" ,
"type" ,
} ) do
declarationWords [ word ] = true
end









local function renamed ( signature , member , name ) 
local rewritten = signature : gsub ( "([%w_]+)%." .. member .. "%f[^%w_]" , name )
local at = 1
while true do
local space , word = rewritten : match ( "^(%s*)([%w_]+)" , at )
if not space or not word then
return rewritten
end
local start = at + # space
if word == member then
return rewritten : sub ( 1 , start - 1 ) .. name .. rewritten : sub ( start + # word )
end
if not declarationWords [ word ] then
return rewritten
end
at = start + # word
end
end

local function projected ( item , module , seen ) 
local aliasText = item . aliasSource and "= " .. item . aliasSource or item . signature
local alias , member = aliasText : match ( "=%s*([%w_]+)%.([%w_]+)%s*$" )
if not alias then
alias , member = aliasText : match ( "=%s*([%w_]+)%.([%w_]+)%b<>%s*$" )
end
if not alias then


local plucked = aliasText : match ( "=%s*([%w_]+)%s*$" ) or aliasText : match ( "=%s*([%w_]+)%b<>%s*$" )
alias = plucked and module . importedMembers and module . importedMembers [ plucked ] and plucked or nil
member = alias and module . importedMembers [ alias ] or nil
end
local origin = alias and module . imports and byName [ module . imports [ alias ] ] or nil
if not origin or seen [ item ] then
return item
end
seen [ item ] = true
for _ , candidate in ipairs ( origin . items ) do
if candidate . name == member
or ( origin . moduleLocal and candidate . name == origin . moduleLocal .. "." .. member )
then
local expanded = copy ( projected ( candidate , origin , seen ) )
expanded . name , expanded . path , expanded . module , expanded . line = item . name , item . path , item . module , item . line
expanded . signature = renamed ( expanded . signature , member , item . name )
if item . doc . text ~= "" then
expanded . doc = item . doc
end





local function renameMembers ( members ) 
for _ , field in ipairs ( members or { } ) do
field . type = field . type and renamed ( field . type , member , item . name ) or field . type
for _ , param in ipairs ( field . params or { } ) do
param . type = param . type and renamed ( param . type , member , item . name ) or param . type
end
for _ , value in ipairs ( field . returns or { } ) do
value . type = value . type and renamed ( value . type , member , item . name ) or value . type
end
renameMembers ( field . members )
end
end

renameMembers ( expanded . members )
for _ , field in ipairs ( expanded . members or { } ) do
field . path = item . path .. "." .. field . name
end
return expanded
end
end

return item
end

for _ , module in ipairs ( modules ) do
local projectedItems , published = { } , { }
for _ , item in ipairs ( module . items ) do
local expanded = projected ( item , module , { } )
local key = expanded . path .. "\0" .. expanded . kind .. "\0" .. expanded . signature
if not published [ key ] then
projectedItems [ # projectedItems + 1 ] = expanded
published [ key ] = true
end
end
module . items = projectedItems
end


local internalTrees = { }
for _ , module in ipairs ( modules ) do
if module . documentationInternal and module . path and module . path : match ( "[/\\]init%.nupp$" ) then
internalTrees [ # internalTrees + 1 ] = module . name
end
end

local function hiddenModule ( module ) 
if settings . includePrivate then
return false
end
if module . documentationInternal or internalModuleName ( module . name ) then
return true
end
if module . path and privateSource ( root , module . path ) then
return true
end
for _ , namespace in ipairs ( internalTrees ) do
if module . name == namespace or module . name : sub ( 1 , # namespace + 1 ) == namespace .. "." then
return true
end
end

return false
end



local function aliasNamespace ( module , item , origin ) 
local name = module . name .. "." .. item . name
local alias = {
name = name ,



path = module . path ,
text = item . doc . text ~= "" and item . doc . text or origin . text ,
items = { } ,
}
for _ , candidate in ipairs ( origin . items ) do
if candidate . kind == "variable" or candidate . kind == "function" then
local copied = copy ( candidate )
copied . module = nil
copied . path = name .. "." .. candidate . name
for _ , member in ipairs ( copied . members or { } ) do
member . path = copied . path .. "." .. member . name
end
alias . items [ # alias . items + 1 ] = copied
end
end

return alias
end
















local aliasedNamespaces = { }
for _ , module in ipairs ( modules ) do
local kept = { }
for _ , item in ipairs ( module . items ) do
local binding = item . kind == "variable" and item . aliasSource and item . aliasSource : match ( "^[%a_][%w_]*$" )
or nil
local imported = binding and module . imports and module . imports [ binding ] or nil
local origin = imported and byName [ imported ] or nil
if not origin or origin == module or byName [ module . name .. "." .. item . name ] then
kept [ # kept + 1 ] = item
elseif hiddenModule ( origin ) then
aliasedNamespaces [ # aliasedNamespaces + 1 ] = aliasNamespace ( module , item , origin )
else
item . signature = item . signature .. " = " .. origin . name
kept [ # kept + 1 ] = item
end
end
module . items = kept
end
for _ , alias in ipairs ( aliasedNamespaces ) do
modules [ # modules + 1 ] = alias
byName [ alias . name ] = byName [ alias . name ] or alias
end
for _ , module in ipairs ( modules ) do
local kept = { }
for _ , item in ipairs ( module . items ) do
local target = item . module and byName [ item . module ] or nil
local nested = target and byName [ ( item . module ) .. "." .. item . name ] or nil
if not settings . includePrivate and item . module and internalModuleName ( item . module ) then




elseif nested and namespaceBacked [ nested . name ] then
if item . doc . text ~= "" then
nested . text = item . doc . text
end
elseif target and target ~= module then
item . path = ( item . module ) .. "." .. item . name
for _ , member in ipairs ( item . members ) do
member . path = item . path .. "." .. member . name
end
target . items [ # target . items + 1 ] = item
else
kept [ # kept + 1 ] = item
end
end
module . items = kept
end
for _ , module in ipairs ( modules ) do
table . sort ( module . items , byKindThenName )
end
if not settings . includePrivate then
local public = { }
for _ , module in ipairs ( modules ) do
if not hiddenModule ( module ) then
public [ # public + 1 ] = module
end
end
modules = public
end


for _ , namespace in ipairs ( namespaceModules ( modules ) ) do
modules [ # modules + 1 ] = namespace
end
table . sort ( modules , function ( left , right ) 
return left . name < right . name
end )

return modules , errors
end

















local stripFrontMatter = frontmatterMod . strip

local function embedFiles ( root , markdown ) 
local out , fence = { } , nil
for line in ( markdown .. "\n" ) : gmatch ( "(.-)\n" ) do
local marker = line : match ( "^%s*(```+)" ) or line : match ( "^%s*(~~~+)" )
if marker then
if not fence then
fence = marker
elseif marker : sub ( 1 , 1 ) == fence : sub ( 1 , 1 ) and # marker >= # fence then
fence = nil
end
end
local path = not fence and line : match ( "^<<<%s+@(%S+)%s*$" )
if path then
local contents , err = readFile ( join ( root , path ) )
if not contents then
return nil , err
end
out [ # out + 1 ] = "```" .. ( path : match ( "%.([%w_]+)$" ) or "text" )
out [ # out + 1 ] = ( contents : gsub ( "\n$" , "" ) )
out [ # out + 1 ] = "```"
else
out [ # out + 1 ] = line
end
end

return table . concat ( out , "\n" )
end









local function rewriteModuleDocLinks ( module , pages , file ) 
local page = { path = "" }

local function rewrite ( text ) 
if not text or text == "" then
return text or ""
end

return rewriteConfiguredPageLinks ( text , page , pages , file )
end

local function rewriteParts ( params , returns , raises ) 
for _ , param in ipairs ( params ) do
param . text = rewrite ( param . text )
end
for _ , result in ipairs ( returns ) do
result . text = rewrite ( result . text )
end



for _ , raise in ipairs ( raises ) do
raise . text = rewrite ( raise . text )
end
end

local rewriteMembers
rewriteMembers = function ( members ) 
for _ , member in ipairs ( members or { } ) do
member . text = rewrite ( member . text )
rewriteParts ( member . params , member . returns , member . raises )
rewriteMembers ( member . members )
end
end
module . text = rewrite ( module . text )
for _ , item in ipairs ( module . items ) do
item . doc . text = rewrite ( item . doc . text )
for name , text in pairs ( item . doc . params ) do
item . doc . params [ name ] = rewrite ( text )
end
for index , text in ipairs ( item . doc . returns ) do
item . doc . returns [ index ] = rewrite ( text )
end
rewriteParts ( item . params , item . returns , item . raises )
for _ , typearg in ipairs ( item . typeargs ) do
typearg . text = rewrite ( typearg . text )
end
rewriteMembers ( item . members )
end
end








local function decorate ( candidate ) 
if candidate . layout ~= "home" or not homeMod . decorated ( candidate . markdown ) then
return candidate
end
local sections = homeMod . parse ( candidate . markdown )
candidate . markdown = sections . markdown
candidate . heroTitle = sections . heroTitle
candidate . heroText = sections . heroText
candidate . heroContent = sections . heroContent
candidate . heroImage = sections . heroImage
candidate . heroImageAlt = sections . heroImageAlt
candidate . heroActions = sections . heroActions
candidate . features = sections . features

return candidate
end



local function sweptPages ( root , configured , reserved , title ) 
local exclude = { }
for _ , pattern in ipairs ( reserved ) do
exclude [ # exclude + 1 ] = pattern
end
for _ , pattern in ipairs ( configured . exclude or { } ) do
exclude [ # exclude + 1 ] = pattern
end
local expanded , err = sweepMod . expand ( root , { base = configured . base , exclude = exclude , glob = configured . glob } )
if not expanded then
return nil , err
end
local candidates = { }
for _ , swept in ipairs ( expanded ) do
local markdown , embedErr = embedFiles ( root , swept . markdown )
if not markdown then
return nil , embedErr
end
candidates [ # candidates + 1 ] = decorate ( {
path = swept . path ,



title = swept . title or ( swept . path == "" and title or nil ) ,
source = swept . source ,
layout = swept . layout ,
redirects = swept . redirects ,
markdown = markdown ,
} )
end

return candidates
end

local function configuredPages ( root , settings , title ) 
local pages = { }
local seen , home = { } , false



local reserved = { }
for _ , configured in ipairs ( settings . pages or { } ) do
if type ( configured ) == "table" and configured . directory then
reserved [ # reserved + 1 ] = configured . directory .. "/**"
end
end



local diagnosticsSource = settings . diagnostics and settings . diagnostics . source
if diagnosticsSource then
reserved [ # reserved + 1 ] = diagnosticsSource
end
for index , configured in ipairs ( settings . pages or { } ) do
if type ( configured ) ~= "table" then
return nil , "documentation page " .. index .. " must be a table"
end
if configured . glob then
local expanded , expandErr = sweptPages ( root , configured , reserved , title )
if not expanded then
return nil , expandErr
end
for _ , swept in ipairs ( expanded ) do
if seen [ swept . path ] then
return nil , "duplicate documentation page path: " .. swept . path
end
seen [ swept . path ] , home = true , home or swept . path == ""
pages [ # pages + 1 ] = swept
end
elseif configured . directory then
local expanded , expandErr = collectionMod . expand ( root , configured )
if not expanded then
return nil , expandErr
end
for _ , member in ipairs ( expanded ) do
if seen [ member . path ] then
return nil , "duplicate documentation page path: " .. member . path
end
seen [ member . path ] = true
local embedded
embedded , expandErr = embedFiles ( root , member . markdown )
if not embedded then
return nil , expandErr
end
member . markdown = embedded
pages [
# pages + 1
] = {
path = member . path ,
title = member . title ,
source = member . source ,
markdown = member . markdown ,
unlisted = member . unlisted ,
}
end
else
local route = cleanRoute ( configured . path )
if not route then
return nil , "invalid documentation page path"
end
if seen [ route ] then
return nil , "duplicate documentation page path: " .. route
end
seen [ route ] , home = true , home or route == ""
local candidate = { }
for key , value in pairs ( configured ) do
candidate [ key ] = value
end
candidate . path = route
candidate . markdown = ""
if candidate . source then
local source , err = readFile ( join ( root , candidate . source ) )
if not source then
return nil , err
end
local fields , body = frontmatterMod . parse ( source )
candidate . title = candidate . title or fields . title
candidate . layout = candidate . layout or fields . layout
source , err = embedFiles ( root , body )
if not source then
return nil , err
end
candidate . markdown = source
end
candidate . title = candidate . title or ( route == "" and title or route )
pages [ # pages + 1 ] = decorate ( candidate )
end
end




local published = { }
for _ , candidate in ipairs ( pages ) do
if candidate . source then
published [ candidate . source ] = true
end
end





local function addGenerated (
generated ,
what ,
api ,
navigationTitle
) 
if not generated then
return true
end
local route = cleanRoute ( generated . path )
if not route then
return nil , "invalid " .. what .. " path"
end
if seen [ route ] then
return nil , what .. " collides with a configured page: " .. route
end
seen [ route ] = true
pages [
# pages + 1
] = {
path = route ,
title = generated . title ,
navigationTitle = navigationTitle ,
markdown = generated . markdown ,
source = generated . source ,
redirects = generated . redirects ,
symbols = generated . symbols ,
api = api
}

return true
end





local diagnosticsSettings = settings . diagnostics
if diagnosticsSettings and diagnosticsSettings . source then
local prose , proseErr = readFile ( join ( root , diagnosticsSettings . source ) )
if not prose then
return nil , proseErr
end
prose , proseErr = embedFiles ( root , stripFrontMatter ( prose ) )
if not prose then
return nil , proseErr
end
diagnosticsSettings = {
path = diagnosticsSettings . path ,
title = diagnosticsSettings . title ,
source = diagnosticsSettings . source ,
redirects = diagnosticsSettings . redirects ,
prose = prose
}
published [ diagnosticsSettings . source ] = true
end
local added , addErr = addGenerated ( diagnosticsMod . page ( diagnosticsSettings , published ) , "diagnostic index" )
if not added then
return nil , addErr
end
added , addErr = addGenerated ( stdlibMod . page ( settings . stdlib ) , "standard library index" , true , "LuaJIT" )
if not added then
return nil , addErr
end
if not home then
table . insert ( pages , 1 , {
path = "" ,
title = title ,
layout = "home" ,
heroTitle = title ,
heroText = settings . description or "API reference generated directly from Nupp source." ,
markdown = ""
} )
end

return pages
end





local function redirectHtml ( target ) 
return "<!doctype html><meta charset=\"utf-8\"><meta http-equiv=\"refresh\" content=\"0; url=" .. htmlEscape (
target
) .. "\"><link rel=\"canonical\" href=\"" .. htmlEscape (
target
) .. "\"><a href=\"" .. htmlEscape ( target ) .. "\">Documentation moved</a>\n"
end

local function searchIndexJs ( entries ) 
local out = { "window.NUPP_SEARCH_INDEX = [\n" }
for _ , entry in ipairs ( entries ) do
out [
# out + 1
] = "  {title:\"" .. escapeJs (
entry . title
) .. "\",url:\"" .. escapeJs ( entry . url ) .. "\",text:\"" .. escapeJs ( entry . text ) .. "\"},\n"
end
out [ # out + 1 ] = "];\n"

return table . concat ( out )
end

local function appendSearchEntries ( entries , candidate , file , markdown ) 
local url = "../" .. file
if candidate . module then
local module = candidate . module
entries [
# entries + 1
] = {
title = ( module . namespace and "Namespace › " or "Module › " ) .. module . name ,
url = url ,
text = module . name .. " " .. ( module . text or "" ) ,
}
for _ , item in ipairs ( module . items ) do
local itemText = { item . name , item . signature , item . doc . text or "" }
for _ , param in ipairs ( item . params ) do
itemText [ # itemText + 1 ] = param . name .. " " .. param . type .. " " .. ( param . text or "" )
end
for _ , value in ipairs ( item . returns ) do
itemText [ # itemText + 1 ] = value . type .. " " .. ( value . text or "" )
end
entries [
# entries + 1
] = { title = "API › " .. item . name , url = url .. "#" .. item . path , text = table . concat ( itemText , " " ) }
for _ , member in ipairs ( item . members ) do
entries [
# entries + 1
] = {
title = "API › " .. item . name .. "." .. member . name ,
url = url .. "#" .. member . path ,
text = member . name .. " " .. ( member . type or "" ) .. " " .. ( member . text or "" ) ,
}
end
end
else
entries [
# entries + 1
] = { title = candidate . title , url = url , text = ( candidate . heroText or "" ) .. " " .. markdown }
for _ , heading in ipairs ( markdownOutline ( markdown ) ) do
if heading . level ~= 1 then
entries [
# entries + 1
] = {
title = candidate . title .. " › " .. heading . name ,
url = url .. "#" .. heading . path ,
text = heading . name .. " " .. candidate . title ,
}
end
end
end
end









local memberOutline

memberOutline = function ( members ) 
local entries = { }
for _ , member in ipairs ( members or { } ) do
entries [
# entries + 1
] = _G.setmetatable({ path =  member . path ,  name =  member . name ,  items =  memberOutline ( member . members ) }, pageMod.Entry)
end

return # entries > 0 and entries or nil
end

local function appendOutline ( items , markdown ) 
for _ , heading in ipairs ( markdownOutline ( markdown ) ) do
local parent = items [ # items ]
if heading . level > 2 and parent then
local children = parent . items or { }
children [ # children + 1 ] = _G.setmetatable({ path =  heading . path ,  name =  heading . name }, pageMod.Entry)
parent . items = children
else
items [ # items + 1 ] = _G.setmetatable({ path =  heading . path ,  name =  heading . name }, pageMod.Entry)
end
end
end





local function renderSite ( root , outDir , modules , title , settings ) 
configureScintillua ( root , settings )
local ok , err = copyPublicFiles ( root , outDir , settings . public )
if not ok then
return nil , err
end
local css = THEME
if settings . customCss then
local custom
custom , err = readFile ( join ( root , tostring ( settings . customCss ) ) )
if not custom then
return nil , err
end
css = css .. "\n" .. custom
end
ok , err = writeFile ( join ( outDir , "assets/style.css" ) , css )
if not ok then
return nil , err
end
ok , err = writeFile ( join ( outDir , "assets/site.js" ) , SCRIPT )
if not ok then
return nil , err
end
local pages
pages , err = configuredPages ( root , settings , title )
if not pages then
return nil , err
end





local configured = { }
local moduleRoutes = { }
local ordered = { }
for _ , candidate in ipairs ( pages ) do
configured [ candidate . path ] = candidate
end
for _ , module in ipairs ( modules ) do
local route = moduleFile ( module . name ) : gsub ( "/index%.html$" , "" )
if moduleRoutes [ route ] then
return nil , "two modules document to the same page: " .. route
end
moduleRoutes [ route ] = true
end
for _ , candidate in ipairs ( pages ) do
if not moduleRoutes [ candidate . path ] then


candidate . title = candidate . title or candidate . path
ordered [ # ordered + 1 ] = candidate
end
end
for _ , module in ipairs ( modules ) do
local route = moduleFile ( module . name ) : gsub ( "/index%.html$" , "" )
local overview = configured [ route ]
ordered [ # ordered + 1 ] = {
path = route ,
title = overview and overview . title or module . name ,
module = module ,
overview = overview and overview . markdown or nil ,
source = overview and overview . source or nil ,


redirects = overview and overview . redirects or nil ,
}
end
pages = ordered
local linkPages = pages
local navPages = pages
for _ , candidate in ipairs ( pages ) do
if candidate . module then
rewriteModuleDocLinks ( candidate . module , linkPages , routeFile ( candidate . path ) )
end
end

local generatedLinks = { }
for _ , candidate in ipairs ( pages ) do
for name , anchor in pairs ( candidate . symbols or { } ) do
generatedLinks [ name ] = routeFile ( candidate . path ) .. "#" .. anchor
end
end
local allMarkdown


= { }
local linkIndex = symbolLinkIndex ( modules , nil , generatedLinks )
local searchEntries = { }
for _ , candidate in ipairs ( pages ) do
local linkCandidate = candidate
local file = routeFile ( candidate . path )
local markdown , body , current = candidate . markdown or "" , { } , nil
local items = { }
if candidate . module then
local module = candidate . module
local children = childModules ( modules , module . name )
local overview = candidate . overview or ""
current = module . name


appendOutline ( items , overview ~= "" and overview or module . text )
if # children > 0 then
items [ # items + 1 ] = _G.setmetatable({ path =  "modules" ,  name =  "Submodules" }, pageMod.Entry)
end
if # module . items > 0 then
items [ # items + 1 ] = _G.setmetatable({ path =  "module-contents" ,  name =  "Module contents" }, pageMod.Entry)
end
local groups = itemGroups ( module . items )
for _ , group in ipairs ( groups ) do
if # group . items > 0 then
local entries = { }
for _ , item in ipairs ( group . items ) do
entries [
# entries + 1
] = _G.setmetatable({ path =  item . path ,  name =  item . name ,  items =  memberOutline ( item . members ) }, pageMod.Entry)
end
items [ # items + 1 ] = _G.setmetatable({ path =  group . path ,  name =  group . title ,  items =  entries }, pageMod.Entry)
end
end
markdown = doc . markdown ( { module } , nil , modules , overview )
local links = symbolLinks ( linkIndex , module , relativePrefix ( file ) )
body [ # body + 1 ] = "<h1><code>" .. htmlEscape ( module . name ) .. "</code></h1>"


if overview ~= "" then
body [
# body + 1
] = markdownHtml ( rewriteConfiguredPageLinks ( overview , linkCandidate , linkPages , file ) , links , 0 )
elseif module . namespace then
body [
# body + 1
] = "<p class=\"nuppdoc-namespace-note\">Modules nested under <code>" .. htmlEscape (
module . name
) .. "</code>. Nothing is required by this name itself.</p>"
elseif module . text ~= "" then
body [ # body + 1 ] = markdownHtml ( module . text , links , 0 )
end
if overview ~= "" and module . text ~= "" then
body [ # body + 1 ] = markdownHtml ( module . text , links , 0 )
end
body [ # body + 1 ] = nestedModules ( children , relativePrefix ( file ) , modules )




if # module . items > 0 then
body [ # body + 1 ] = moduleSummary ( module )
for _ , group in ipairs ( groups ) do
if # group . items > 0 then
body [
# body + 1
] = "<section class=\"nuppdoc-api-group\"><h2 id=\"" .. htmlEscape (
group . path
) .. "\">" .. htmlEscape (
group . title
) .. "<a class=\"nuppdoc-header-anchor\" href=\"#" .. htmlEscape (
group . path
) .. "\" aria-label=\"Link to " .. htmlEscape ( group . title ) .. "\">#</a></h2>"
for _ , item in ipairs ( group . items ) do
renderHtmlItem ( body , item , links )
end
body [ # body + 1 ] = "</section>"
end
end
end
else
local links = symbolLinks ( linkIndex , nil , relativePrefix ( file ) )
appendOutline ( items , markdown )




for _ , feature in ipairs ( candidate . features or { } ) do
if feature . details then
feature . details = rewriteConfiguredPageLinks ( feature . details , linkCandidate , linkPages , file )
end
end
body [ # body + 1 ] = homeHero ( candidate , links , function ( href ) 
return urlsMod . resolvePageHref ( href , linkCandidate , linkPages , file )
end )




if candidate . path ~= "" and markdown ~= "" and not markdown : match ( "^#%s" ) then
body [ # body + 1 ] = "<h1>" .. htmlEscape ( candidate . title ) .. "</h1>"
end
local renderedMarkdown = rewriteConfiguredPageLinks ( markdown , linkCandidate , linkPages , file )
local featureStart , featureEnd
if candidate . path == "" then


featureStart , featureEnd = markdown : find ( "<!-- nupp:features -->" , 1 , true )
end
if featureStart and featureEnd then
local introduction = rewriteConfiguredPageLinks (
markdown : sub ( 1 , featureStart - 1 ) ,
linkCandidate ,
linkPages ,
file
)
local remainder = rewriteConfiguredPageLinks (
markdown : sub ( featureEnd + 1 ) ,
linkCandidate ,
linkPages ,
file
)
body [ # body + 1 ] = markdownHtml ( introduction , links , 0 )
body [ # body + 1 ] = homeFeatures ( candidate , links )
body [ # body + 1 ] = markdownHtml ( remainder , links , 0 )
else
body [ # body + 1 ] = markdownHtml ( renderedMarkdown , links , 0 )
end
if candidate . path == "" then
if not featureStart then
body [ # body + 1 ] = homeFeatures ( candidate , links )
end
end
end
local html = renderPage (
candidate . title ,
title ,
table . concat ( body , "\n" ) ,
modules ,
current ,
items ,
file ,
settings ,
navPages ,
candidate . path ,
candidate . layout
)
appendSearchEntries ( searchEntries , candidate , file , markdown )
ok , err = writeFile ( join ( outDir , file ) , html )
if not ok then
return nil , err
end


for _ , former in ipairs ( candidate . redirects or { } ) do
local formerRoute = cleanRoute ( former )
if not formerRoute or formerRoute == "" then
return nil , "invalid redirect route on page " .. candidate . path
end
local formerFile = routeFile ( formerRoute )
ok , err = writeFile ( join ( outDir , formerFile ) , redirectHtml ( relativePrefix ( formerFile ) .. file ) )
if not ok then
return nil , err
end
end
local mdFile = candidate . path == "" and "index.md" or candidate . path .. ".md"
ok , err = writeFile ( join ( outDir , mdFile ) , markdown )
if not ok then
return nil , err
end
if candidate . path ~= "" then
ok , err = writeFile ( join ( outDir , candidate . path .. "/llms.txt" ) , markdown )
if not ok then
return nil , err
end
end
allMarkdown [ # allMarkdown + 1 ] = { page = candidate , text = markdown }
end

local llms = { "# " .. ( settings . name or title ) , "" }
if settings . description and settings . description ~= "" then
llms [ # llms + 1 ] = "> " .. settings . description
llms [ # llms + 1 ] = ""
end
llms [ # llms + 1 ] = "## Documentation"
for _ , entry in ipairs ( allMarkdown ) do
local target = entry . page . path == "" and "index.md" or entry . page . path .. "/llms.txt"
llms [ # llms + 1 ] = "- [" .. ( entry . page . title or entry . page . path ) .. "](" .. target .. ")"
end
llms [ # llms + 1 ] = ""
llms [ # llms + 1 ] = "- [Complete documentation](llms-full.txt)"
ok , err = writeFile ( join ( outDir , "llms.txt" ) , table . concat ( llms , "\n" ) .. "\n" )
if not ok then
return nil , err
end
local full = { "# " .. ( settings . name or title ) }
for _ , entry in ipairs ( allMarkdown ) do
full [ # full + 1 ] = "\n---\n\n## " .. ( entry . page . title or entry . page . path ) .. "\n\n" .. trim ( entry . text ) .. "\n"
end
ok , err = writeFile ( join ( outDir , "llms-full.txt" ) , table . concat ( full , "\n" ) )
if not ok then
return nil , err
end
ok , err = writeFile ( join ( outDir , "assets/search-index.js" ) , searchIndexJs ( searchEntries ) )
if not ok then
return nil , err
end

return true
end





local function report ( errors ) 
for _ , err in ipairs ( errors ) do
io . stderr : write (
("%s:%d:%d: error: %s\n")

: format ( err . filename or "?" , err . line or 1 , err . col or 1 , err . msg or "documentation error" )
)
end
end









function doc . defaultOutDir ( format ) 
if format == "markdown" then
return "docs/api.md"
elseif format == "json" then
return "build/docs.json"
end

return "build/docs"
end




local function removeReplaced ( path ) 
for attempt = 1 , 20 do
local removed = files . remove ( path )
if removed then
return
end
local deadline = os . clock ( ) + 0.1
while os . clock ( ) < deadline do
end
end
end





local function insideOutput ( output , path ) 
if path : sub ( 1 , # output + 1 ) ~= output .. "/" or path : find ( "%z" ) then
return false
end
for segment in ( path : sub ( # output + 2 ) .. "/" ) : gmatch ( "([^/]*)/" ) do
if segment == "" or segment == "." or segment == ".." then
return false
end
end

return true
end





local function reconcileSiteFiles ( output , written ) 
local statePath = join ( output , ".nupp-doc-files.json" )
local previous = { }
local encoded = readFile ( statePath )
if encoded then
local decoded = json . decode ( encoded , json . NULL )
if type ( decoded ) == "table" then
previous = decoded
end
end
local current = { }
for _ , path in ipairs ( written ) do
current [ normalize ( path ) ] = true
end
for _ , entry in ipairs ( previous ) do
local path = type ( entry ) == "string" and normalize ( entry ) or ""
if not current [ path ] and insideOutput ( output , path ) then
removeReplaced ( path )





local directory = dirname ( path )
while directory ~= output and directory : sub ( 1 , # output + 1 ) == output .. "/" and files . remove ( directory ) do
directory = dirname ( directory )
end
end
end
table . sort ( written )

return filesMod . writeFile ( statePath , json . encode ( written ) .. "\n" )
end











function doc . build ( root , config , settings , opts ) 
root = root or "."
local config = config
local settings = ( settings or { } )
local opts = opts or { }
local modules , errors = loadModules ( root , config or { } , settings , opts . sources )
if # errors > 0 then
if opts . diagnostics then
local collected = opts . diagnostics
for _ , err in ipairs ( errors ) do
collected [ # collected + 1 ] = err
end
else
report ( errors )
end
return 1
end
if opts . checkOnly then
return 0
end
local format = opts . format or settings . format or "site"
local title = opts . title or settings . title or config . name or "Nupp API"


local configuredOutDir = format == ( settings . format or "site" ) and settings . outDir or nil
local output = normalize ( opts . output or configuredOutDir or doc . defaultOutDir ( format ) )
output = join ( root , output )


local written = opts . written or { }
filesMod . collect ( written )
local code , message = 0 , nil
if format == "markdown" then
local ok , err = writeFile ( output , doc . markdown ( modules , title , nil , nil ) )
if not ok then
code , message = 1 , tostring ( err )
end
elseif format == "site" then
local ok , err = renderSite ( root , output , modules , title , settings )
if not ok then
code , message = 1 , tostring ( err )
end
elseif format == "both" then
local ok , err = renderSite ( root , output , modules , title , settings )
if ok then
ok , err = writeFile ( join ( output , "api.md" ) , doc . markdown ( modules , title , nil , nil ) )
end
if not ok then
code , message = 1 , tostring ( err )
end
elseif format == "json" then
local ok , err = writeFile ( output , doc . json ( modules ) )
if not ok then
code , message = 1 , tostring ( err )
end
else
code = 2
message = "documentation format must be site, markdown, json, or both"
end
filesMod . collect ( nil )
if code == 0 and ( format == "site" or format == "both" ) then
local ok , err = reconcileSiteFiles ( output , written )
if not ok then
code , message = 1 , tostring ( err )
end
end
if message and opts . diagnostics then
local collected = opts . diagnostics
collected [ # collected + 1 ] = require ( "nupp.tools.cli.report" ) . runDiagnostic ( "NUPP0001" , message , nil , output )
elseif message then
io . stderr : write ( "nupp: " .. message .. "\n" )
end

return code , output , format
end







local function withName ( target , name ) 
local copy = { }
for key , value in pairs ( target ) do
copy [ key ] = value
end
copy . targetName = name

return copy
end












function doc . manifestSettings ( config , requested ) 
local targets = config . build and config . build . targets or { }
if requested then
local target = targets [ requested ]
if not target then
return nil , "unknown build target " .. requested
end
if target . kind ~= "docs" then
return nil , ("build target %s is a %s target, not a docs target")

: format ( requested , tostring ( target . kind or "modules" ) )
end

return withName ( target , requested )
end
if type ( config . docs ) == "table" then
return config . docs
end
local found


= { }
for name , target in pairs ( targets ) do
if type ( target ) == "table" and target . kind == "docs" then
found [ # found + 1 ] = { name = name , target = target }
end
end
table . sort ( found , function ( a , b ) 
return a . name < b . name
end )
local first = found [ 1 ]
if not first then
return { }
end
if # found > 1 then
local preferred = config . build and config . build . default or nil
local target = preferred and targets [ preferred ] or nil
if preferred and target and target . kind == "docs" then
return withName ( target , preferred )
end
local names = { }
for index , entry in ipairs ( found ) do
names [ index ] = entry . name
end

return nil , ("the manifest has %d docs targets (%s): name one with --target, ")

: format ( # found , table . concat ( names , ", " ) ) .. "or say which the build defaults to with build.default"
end

return withName ( first . target , first . name )
end

doc . theme = THEME
doc . highlight = highlightMod . nuppSource

local __nuppExportValue= doc ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc"]=__nuppExports;return __nuppExports