_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.derive\0runtime\0001") };


















local derive = { }

derive.Entry = {} derive.Entry.__index = derive.Entry ;_G.nupp.__reflect.link(derive.Entry,__nuppT1[1],{ })








local entryKey = { }
local derivedByType = setmetatable ( { } , { __mode = "kv" } )


local ctypes = setmetatable ( { } , { __mode = "k" } )

local function register ( key , mt , schema ) 
local entry = { key = key , mt = mt , schema = schema }
if type ( mt ) == "table" then
rawset ( mt , entryKey , entry )
else
ctypes [ mt ] = entry
end
derivedByType [ mt ] = entry

return entry
end



function derive . entry ( typeObject ) 
return derivedByType [ typeObject ] or ctypes [ typeObject ]
end



function derive . forEach ( callback ) 
for _ , entry in pairs ( derivedByType ) do
callback ( entry )
end
end



function derive . initializer ( typeObject ) 
local entry = derive . entry ( typeObject )
local name = entry and entry . schema and entry . schema . initializer or nil
if entry == nil or type ( name ) ~= "string" then
return nil
end

return entry . mt [ name ]
end




function derive . debug ( target , value ) 
local rendering = require ( "nupp.serde.debug" )
return rendering . derived ( target , value )
end



function derive . install ( namespace ) 
local runtime = rawget ( namespace , "__derive" )
if runtime == nil then
runtime = { }
rawset ( namespace , "__derive" , runtime )
end
runtime . register = register
runtime . entry = derive . entry
runtime . debug = derive . debug
end






































































































































local __nuppExportValue= derive ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.derive"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.derive"]=__nuppExports;return __nuppExports