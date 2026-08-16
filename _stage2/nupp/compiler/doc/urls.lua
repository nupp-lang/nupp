_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








local filesMod = require ( "nupp.compiler.doc.files" )

local normalize , join , dirname = filesMod . normalize , filesMod . join , filesMod . dirname

local urls = { }













local function moduleFile ( name )
return "modules/" .. name : gsub ( "[^%w._-]" , "-" ) : gsub ( "%." , "/" ) .. "/index.html"
end

local function relativePrefix ( file )
local _ , count = file : gsub ( "/" , "" )
return string . rep ( "../" , count )
end

local function addSymbolLink ( links , ambiguous , name , url )
if not name or name == "" or ambiguous [ name ] then
return
end
if links [ name ] and links [ name ] ~= url then
links [ name ] = nil
ambiguous [ name ] = true
else
links [ name ] = url
end
end






local function defaultTarget ( module , path )
return moduleFile ( module ) .. ( path and "#" .. path or "" )
end

local function symbolLinkIndex ( modules , target )
local target = target or defaultTarget
local links , ambiguous = { } , { }
for _ , module in ipairs ( modules ) do
for _ , item in ipairs ( module . items ) do
local url = target ( module . name , item . path )
addSymbolLink ( links , ambiguous , item . path , url )
addSymbolLink ( links , ambiguous , item . name , url )
local tail = item . name : match ( "([^.]+)$" )
addSymbolLink ( links , ambiguous , tail , url )
for _ , member in ipairs ( item . members ) do
local memberUrl = target ( module . name , member . path )
addSymbolLink ( links , ambiguous , member . path , memberUrl )
addSymbolLink ( links , ambiguous , item . name .. "." .. member . name , memberUrl )
end
end
end




for _ , module in ipairs ( modules ) do
if links [ module . name ] == nil and not ambiguous [ module . name ] then
links [ module . name ] = target ( module . name )
end
end

return links
end




















local function rewriteSymbolLinks ( markdown , resolve )
local function rewrite ( prose )
return ( prose : gsub ( "%[([^%[%]]*)%]%(([^%s%(%)]+)%)" , function ( text , target )
if target : match ( "^[%w+.-]+:" ) or target : find ( "[/#]" ) then
return "[" .. text .. "](" .. target .. ")"
end
local url = resolve ( target )
local named = text : match ( "^%s*$" ) ~= nil
if not url and not named then


return "[" .. text .. "](" .. target .. ")"
end
local label = named and "`" .. target .. "`" or text

return url and url ~= "" and "[" .. label .. "](" .. url .. ")" or label
end ) )
end




local out , position = { } , 1
while position <= # markdown do
local opening , closing = markdown : find ( "(`+).-%1" , position )
if not opening or not closing then
out [ # out + 1 ] = rewrite ( markdown : sub ( position ) ) ;
break
end
out [ # out + 1 ] = rewrite ( markdown : sub ( position , opening - 1 ) )
out [ # out + 1 ] = markdown : sub ( opening , closing )
position = closing + 1
end

return table . concat ( out )
end

local function symbolLinks ( index , module , prefix )
local links = { }
if module then
for _ , item in ipairs ( module . items ) do
local url = prefix .. moduleFile ( module . name ) .. "#" .. item . path
links [ item . name ] = url
links [ item . name : match ( "([^.]+)$" ) or item . name ] = url
for _ , member in ipairs ( item . members ) do
local memberUrl = prefix .. moduleFile ( module . name ) .. "#" .. member . path
links [ member . path ] = memberUrl
links [ item . name .. "." .. member . name ] = memberUrl
end
end
end

return setmetatable ( links , {
__index = function ( _ , name )
local url = index [ name ]
return url and prefix .. url or nil
end
} )
end

local function routeFile ( route )
return route == "" and "index.html" or route .. "/index.html"
end

local function cleanRoute ( route )
route = normalize ( tostring ( route or "" ) ) : gsub ( "^/" , "" )
route = route : gsub ( "/index%.html$" , "" ) : gsub ( "%.html$" , "" )
if route == "." then
route = ""
end
for segment in route : gmatch ( "[^/]+" ) do
if segment == "." or segment == ".." then
return nil
end
end

return route
end

local function pageLink ( prefix , route )
return prefix .. routeFile ( route )
end






local function resolveDots ( path )
local parts = { }
for segment in path : gmatch ( "[^/]+" ) do
if segment == ".." and # parts > 0 and parts [ # parts ] ~= ".." then
parts [ # parts ] = nil
elseif segment ~= "." then
parts [ # parts + 1 ] = segment
end
end

return table . concat ( parts , "/" )
end

local function rewriteConfiguredPageLinks (
markdown ,
candidate ,
pages ,
file
)
local routes = { }
for _ , page in ipairs ( pages ) do
if page . source then
routes [ resolveDots ( normalize ( page . source ) ) ] = page . path
end
end



local sourceDirectory = candidate . source and dirname ( normalize ( candidate . source ) ) or nil

return ( markdown : gsub ( "(%[[^%]]+%]%()([^%)]+)(%))" , function ( opening , target , closing )
if target : match ( "^[%w+.-]+:" ) or target : match ( "^[/#]" ) or target : find ( "%s" ) then
return opening .. target .. closing
end
local path , fragment = target : match ( "^([^#]+)(#.*)$" )
path , fragment = path or target , fragment or ""
local route = (
sourceDirectory and routes [ resolveDots ( normalize ( join ( sourceDirectory , path ) ) ) ] or nil
) or routes [ resolveDots ( normalize ( path ) ) ]
if route == nil then
return opening .. target .. closing
end

return opening .. relativePrefix ( file ) .. routeFile ( route ) .. fragment .. closing
end ) )
end

urls . moduleFile = moduleFile
urls . relativePrefix = relativePrefix
urls . symbolLinkIndex = symbolLinkIndex
urls . symbolLinks = symbolLinks
urls . rewriteSymbolLinks = rewriteSymbolLinks
urls . routeFile = routeFile
urls . cleanRoute = cleanRoute
urls . pageLink = pageLink
urls . rewriteConfiguredPageLinks = rewriteConfiguredPageLinks

return urls
