_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.doc.collection\0runtime\0001") };

















local filesMod = require ( "nupp.tools.doc.files" )
local frontmatterMod = require ( "nupp.tools.doc.frontmatter" )
local urlsMod = require ( "nupp.tools.doc.urls" )

local collection = { }

local join , readFile , listMarkdown = filesMod . join , filesMod . readFile , filesMod . listMarkdown
local normalize = filesMod . normalize
local cleanRoute = urlsMod . cleanRoute









collection.Page = {} collection.Page.__index = collection.Page ;_G.nupp.__reflect.link(collection.Page,__nuppT1[1],{ })
























local INDEX = "index.md"





local function header ( title , fields ) 
local keys = { }
for key in pairs ( fields ) do
if key ~= "title" then
keys [ # keys + 1 ] = key
end
end
table . sort ( keys )
local meta = { }
for _ , key in ipairs ( keys ) do
local label = ( key : gsub ( "[-_]" , " " ) )
meta [ # meta + 1 ] = "**" .. label : sub ( 1 , 1 ) : upper ( ) .. label : sub ( 2 ) .. ":** " .. ( fields [ key ] or "" )
end
if # meta == 0 then
return "# " .. title .. "\n"
end

return "# " .. title .. "\n\n" .. table . concat ( meta , " &middot; " ) .. "\n"
end




local function titleOf ( fields , body , stem ) 
local named = fields . title
if named and named ~= "" then
return named
end
local heading = body : match ( "^#%s+([^\n]+)" ) or body : match ( "\n#%s+([^\n]+)" )

return heading or stem
end




local function numberOf ( stem ) 
local digits = stem : match ( "^(%d+)%-" )
if not digits then
return nil
end

return tostring ( tonumber ( digits ) )
end





local function expandOne ( base , settings , file ) 
local source , err = readFile ( file )
if not source then
return nil , err
end
local relative = normalize ( file ) : sub ( # base + 2 )
local stem = ( relative : gsub ( "%.md$" , "" ) )
local route = cleanRoute ( settings . path .. "/" .. stem )
if not route then
return nil , "a document does not name a route: " .. relative
end
local fields , body = frontmatterMod . parse ( source )
local name = titleOf ( fields , body , stem )
local number = numberOf ( stem )
local prefix = settings . title and ( settings . title : gsub ( "s$" , "" ) ) or nil
local title = name
if number and prefix then
title = prefix .. " " .. number .. ": " .. name
end

return ( _G.setmetatable({ markdown =
header ( title , fields ) .. body ,  name =
name ,  number =
number ,  path =
route ,  source =
join ( settings . directory , relative ) ,  status =
fields . status ,  title =
title ,  unlisted =
true }, collection.Page) )

end






function collection . expand ( root , settings ) 
local directory = settings . directory
if not directory or directory == "" then
return nil , "a documentation page directory must be named"
end
local route = cleanRoute ( settings . path )
if not route then
return nil , "invalid documentation page path"
end
local base = normalize ( join ( root , directory ) )
local pages = { }
for _ , file in ipairs ( listMarkdown ( base ) ) do
if normalize ( file ) ~= join ( base , "index.md" ) then
local page , err = expandOne ( base , settings , file )
if not page then
return nil , err
end
pages [ # pages + 1 ] = page
end
end
table . insert ( pages , 1 , collection . index ( base , settings , route , pages ) )

return pages
end






function collection . index (
base ,
settings ,
route ,
pages
) 
local preamble , title = "" , settings . title or route
local indexFile = join ( base , "index.md" )
local source = readFile ( indexFile )
if source then
local fields , body = frontmatterMod . parse ( source )
preamble , title = body , titleOf ( fields , body , title )
end
local numbered = false
for _ , page in ipairs ( pages ) do
numbered = numbered or page . number ~= nil
end
local out = { preamble , "" }
if # pages > 0 then
out [ # out + 1 ] = "| " .. ( numbered and "#" or "Document" ) .. " | Title | Status |"
out [ # out + 1 ] = "| --- | --- | --- |"
for _ , page in ipairs ( pages ) do
out [
# out + 1
] = "| " .. (
page . number or ""
) .. " | [" .. page . name .. "](" .. ( page . source or "" ) .. ") | " .. ( page . status or "—" ) .. " |"
end
end

return ( _G.setmetatable({ markdown =
table . concat ( out , "\n" ) ,  name =
title ,  path =
route ,  source =
source and join ( settings . directory , INDEX ) or nil ,  title =
title }, collection.Page) )

end

local __nuppExportValue= collection ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.collection"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.collection"]=__nuppExports;return __nuppExports