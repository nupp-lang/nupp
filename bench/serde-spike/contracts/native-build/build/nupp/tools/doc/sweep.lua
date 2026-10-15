_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.doc.sweep\0runtime\0001") };














local filesMod = require ( "nupp.tools.doc.files" )
local frontmatterMod = require ( "nupp.tools.doc.frontmatter" )
local urlsMod = require ( "nupp.tools.doc.urls" )
local syntax = require ( "nupp.compiler.shellsyntax" )

local sweep = { }

local join , readFile , normalize = filesMod . join , filesMod . readFile , filesMod . normalize
local listMarkdown = filesMod . listMarkdown
local cleanRoute = urlsMod . cleanRoute





sweep.Page = {} sweep.Page.__index = sweep.Page ;_G.nupp.__reflect.link(sweep.Page,__nuppT1[1],{ })





















local INDEX = "index.md"

local function patterns ( settings ) 
local glob = settings . glob

return type ( glob ) == "string" and { glob } or glob
end




local function anchor ( glob ) 
local prefix = glob : match ( "^(.-)[*?]" ) or glob

return prefix : match ( "^(.*)/" ) or "."
end




local function routeOf ( relative ) 
local stem = relative : gsub ( "%.md$" , "" )
if stem == ("index.md") : gsub ( "%.md$" , "" ) then
return ""
end
stem = ( stem : gsub ( "/index$" , "" ) )
if stem == "" then
return ""
end

return cleanRoute ( stem )
end




local function headingTitle ( body ) 
local heading = body : match ( "^#%s+([^\n]+)" ) or body : match ( "\n#%s+([^\n]+)" )
if not heading then
return nil
end

return ( heading : gsub ( "`" , "" ) : gsub ( "%s+$" , "" ) )
end




local function below ( directory , path ) 
local base = normalize ( directory )
path = normalize ( path )
if base == "." or base == "" then
return path
elseif path : sub ( 1 , # base + 1 ) == base .. "/" then
return path : sub ( # base + 2 )
end

return path
end

local function expandOne ( root , base , file ) 
local source , err = readFile ( file )
if not source then
return nil , err
end
local relative = below ( join ( root , base ) , file )
local route = routeOf ( relative )
if not route then
return nil , "a documentation page does not name a route: " .. relative
end
local fields , body = frontmatterMod . parse ( source )

return ( _G.setmetatable({ layout =
fields . layout ,  markdown =
body ,  order =
tonumber ( fields . order ) ,  path =
route ,  redirects =
frontmatterMod . list ( fields . redirects ) ,  source =
below ( root , file ) ,  title =
fields . title or headingTitle ( body ) }, sweep.Page) )

end






function sweep . expand ( root , settings ) 
local base = settings . base or anchor ( patterns ( settings ) [ 1 ] )
local excluded = { }
for _ , pattern in ipairs ( settings . exclude or { } ) do
excluded [ # excluded + 1 ] = syntax . glob ( normalize ( pattern ) )
end
local seen = { }
local pages = { }
for _ , glob in ipairs ( patterns ( settings ) ) do
local matches = syntax . glob ( normalize ( glob ) )
for _ , file in ipairs ( listMarkdown ( join ( root , anchor ( glob ) ) ) ) do
local relative = below ( root , file )
local skip = not matches ( relative ) or seen [ relative ]
for _ , drops in ipairs ( excluded ) do
skip = skip or drops ( relative )
end
if not skip then
seen [ relative ] = true
local page , err = expandOne ( root , base , file )
if not page then
return nil , err
end
pages [ # pages + 1 ] = page
end
end
end



local positions = { }
for index , page in ipairs ( pages ) do
positions [ page ] = index
end
table . sort ( pages , function ( left , right ) 
local leftOrder , rightOrder = left . order , right . order
if leftOrder ~= rightOrder then
if not leftOrder then
return false
elseif not rightOrder then
return true
end

return leftOrder < rightOrder
end

return ( positions [ left ] or 0 ) < ( positions [ right ] or 0 )
end )

return pages
end

local __nuppExportValue= sweep ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.sweep"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.sweep"]=__nuppExports;return __nuppExports