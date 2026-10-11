_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.codec.json.number"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local valid;__nuppExports["valid"]=function(...) return valid(...) end;



valid=function ( text ) 
local position = 1
if text : byte ( position ) == 45 then
position += 1
end
local byte = text : byte ( position )
if byte == 48 then
position += 1
elseif byte ~= nil and byte >= 49 and byte <= 57 then
repeat
position += 1
byte = text : byte ( position )
until byte == nil or byte < 48 or byte > 57
else
return false
end
if text : byte ( position ) == 46 then
position += 1
local first = position
byte = text : byte ( position )
while byte ~= nil and byte >= 48 and byte <= 57 do
position += 1
byte = text : byte ( position )
end
if position == first then
return false
end
end
byte = text : byte ( position )
if byte == 69 or byte == 101 then
position += 1
byte = text : byte ( position )
if byte == 43 or byte == 45 then
position += 1
end
local first = position
byte = text : byte ( position )
while byte ~= nil and byte >= 48 and byte <= 57 do
position += 1
byte = text : byte ( position )
end
if position == first then
return false
end
end

return position == # text + 1
end ;__nuppExports["valid"]=valid
 end);if not __nuppOk then package.loaded["nupp.codec.json.number"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.json.number"]=__nuppExports;return __nuppExports