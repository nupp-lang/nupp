_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()














local frontmatter = { }






function frontmatter . parse ( source ) 



source = source : gsub ( "\13\n?" , "\n" )
if source : sub ( 1 , 4 ) ~= "---\n" then
return { } , source
end
local ending = source : find ( "\n---\n" , 5 , true )
if not ending then
return { } , source
end
local fields = { }
for line in source : sub ( 5 , ending ) : gmatch ( "[^\n]+" ) do
local key , value = line : match ( "^([%w_-]+)%s*:%s*(.-)%s*$" )
if key and value then




local quoted = value : match ( "^\"(.*)\"$" ) or value : match ( "^'(.*)'$" )
fields [ key ] = quoted or value
end
end




return fields , ( source : sub ( ending + 5 ) : gsub ( "^\n+" , "" ) )
end


function frontmatter . strip ( source ) 
local _ , body = frontmatter . parse ( source )

return body
end





function frontmatter . list ( value ) 
if not value then
return nil
end
local items = { }
for item in value : gmatch ( "[^,]+" ) do
local trimmed = item : match ( "^%s*(.-)%s*$" )
if trimmed ~= "" then
items [ # items + 1 ] = trimmed
end
end

return # items > 0 and items or nil
end

local __nuppExportValue= frontmatter ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.frontmatter"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.frontmatter"]=__nuppExports;return __nuppExports