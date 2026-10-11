_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.facts\0runtime\0001") };





























local facts = { }

facts . FAMILIES = { "alias" , "access" , "effects" , "bounds" , "relations" , "extents" }


facts.Facts = {} facts.Facts.__index = facts.Facts ;_G.nupp.__reflect.link(facts.Facts,__nuppT1[1],{ })








function facts . all ( ) 
return ( _G.setmetatable({ alias =  true ,  access =  true ,  effects =  true ,  bounds =  true ,  relations =  true ,  extents =  true }, facts.Facts) )
end

function facts . none ( ) 
return ( _G.setmetatable({ alias =
false ,  access =
false ,  effects =
false ,  bounds =
false ,  relations =
false ,  extents =
false }, facts.Facts) )

end


function facts . parse ( text ) 
if text == "" or text == "all" then
return facts . all ( ) , nil
elseif text == "none" then
return facts . none ( ) , nil
end
local selected = facts . none ( )
for name in text : gmatch ( "[^,%s]+" ) do
if name == "alias" then
selected . alias = true
elseif name == "access" then
selected . access = true
elseif name == "effects" then
selected . effects = true
elseif name == "bounds" then
selected . bounds = true
elseif name == "relations" then
selected . relations = true
elseif name == "extents" then
selected . extents = true
else
return nil , "unknown AOT fact family " .. name .. "; the families are " .. table . concat (
facts . FAMILIES ,
", "
)
end
end

return selected , nil
end


function facts . key ( selected ) 
local names = { }
for _ , name in ipairs ( facts . FAMILIES ) do
if ( selected ) [ name ] == true then
names [ # names + 1 ] = name
end
end

return # names == # facts . FAMILIES and "all" or # names == 0 and "none" or table . concat ( names , "," )
end

local __nuppExportValue= facts ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.facts"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.facts"]=__nuppExports;return __nuppExports