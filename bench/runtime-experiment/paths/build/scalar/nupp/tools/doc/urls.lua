_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local filesMod = require ( "nupp.tools.doc.files" )

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



local function rewriteOutsideBackticks ( markdown , rewrite ) 
local out , position = { } , 1
while position <= # markdown do
local opening , closing = markdown : find ( "(`+).-%1" , position )
if not opening or not closing then
out [ # out + 1 ] = rewrite ( markdown : sub ( position ) )
do break end
end
out [ # out + 1 ] = rewrite ( markdown : sub ( position , opening - 1 ) )
out [ # out + 1 ] = markdown : sub ( opening , closing )
position = closing + 1
end

return table . concat ( out )
end






local function defaultTarget ( module , path ) 
return ( "modules/" .. module : gsub ( "[^%w._-]" , "-" ) : gsub ( "%." , "/" ) .. "/index.html" ) .. ( path and "#" .. path or "" )
end

local function symbolLinkIndex ( modules , target , extra ) 
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



for name , url in pairs ( extra or { } ) do
addSymbolLink ( links , ambiguous , name , url )
end

return links
end
























local function rewriteSymbolLinks ( markdown , resolve ) 
local function rewrite ( prose ) 
return ( prose : gsub ( "%[([^%[%]]*)%]%(([^%s%(%)]+)%)" , function ( text , target ) 
local name , fragment = target : match ( "^([^#]*)(#.*)$" )
name , fragment = name or target , fragment or ""
if target : match ( "^[%w+.-]+:" ) or name == "" or name : find ( "/" , 1 , true ) then
return "[" .. text .. "](" .. target .. ")"
end
local url = resolve ( name )
local named = text : match ( "^%s*$" ) ~= nil
if not url and not named then


return "[" .. text .. "](" .. target .. ")"
end
local label = named and "`" .. name .. "`" or text

return url and url ~= "" and "[" .. label .. "](" .. url .. fragment .. ")" or label
end ) )
end

return rewriteOutsideBackticks ( markdown , rewrite )
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
return prefix .. ( route == "" and "index.html" or route .. "/index.html" )
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




local function linkText ( text , path , title ) 
if title == nil or title == "" then
return text
end
local base = path : match ( "([^/]+)$" ) or path
local bare = text : match ( "^`(.*)`$" ) or text
if bare == base and base : match ( "%.md$" ) then
return title
end

return text
end

local function routesBySource ( pages ) 
local routes = { }
for _ , page in ipairs ( pages ) do
if page . source then
routes [ resolveDots ( normalize ( page . source ) ) ] = page
end
end

return routes
end




local function resolveRoutedLink (
target ,
routes ,
sourceDirectory ,
file
) 
if target : match ( "^[%w+.-]+:" ) or target : match ( "^[/#]" ) or target : find ( "%s" ) then
return nil
end
local path , fragment = target : match ( "^([^#]+)(#.*)$" )
path , fragment = path or target , fragment or ""
local destination = ( sourceDirectory and routes [ resolveDots ( normalize ( join ( sourceDirectory , path ) ) ) ] or nil )
or routes [ resolveDots ( normalize ( path ) ) ]
if destination == nil then
return nil
end

return relativePrefix ( file ) .. routeFile ( destination . path ) .. fragment , destination . title
end

local function rewriteConfiguredPageLinks (
markdown ,
candidate ,
pages ,
file
) 
local routes = routesBySource ( pages )




local sourceDirectory = candidate . source and dirname ( normalize ( candidate . source ) ) or nil

return rewriteOutsideBackticks ( markdown , function ( prose ) 
return ( prose : gsub ( "%[([^%]]+)%]%(([^%)]+)%)" , function ( text , target ) 
local written = "[" .. text .. "](" .. target .. ")"
local href , title = resolveRoutedLink ( target , routes , sourceDirectory , file )
if not href then
return written
end
local path = target : match ( "^([^#]+)" ) or target

return "[" .. linkText ( text , path , title ) .. "](" .. href .. ")"
end ) )
end )
end





local function resolvePageHref ( target , candidate , pages , file ) 
local routes = routesBySource ( pages )
local sourceDirectory = candidate . source and dirname ( normalize ( candidate . source ) ) or nil

return ( resolveRoutedLink ( target , routes , sourceDirectory , file ) ) or target
end

urls . moduleFile = moduleFile
urls . relativePrefix = relativePrefix
urls . symbolLinkIndex = symbolLinkIndex
urls . symbolLinks = symbolLinks
urls . rewriteSymbolLinks = rewriteSymbolLinks
urls . routeFile = routeFile
urls . cleanRoute = cleanRoute
urls . pageLink = pageLink
urls . resolvePageHref = resolvePageHref
urls . rewriteConfiguredPageLinks = rewriteConfiguredPageLinks

local __nuppExportValue= urls ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.urls"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.urls"]=__nuppExports;return __nuppExports