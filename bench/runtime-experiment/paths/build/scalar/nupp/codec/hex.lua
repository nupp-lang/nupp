_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.codec.hex"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local decode;__nuppExports["decode"]=function(...) return decode(...) end;local encode;__nuppExports["encode"]=function(...) return encode(...) end;
















encode=function ( bytes ) 
local parts = { }
for index = 1 , # bytes do
parts [ index ] = string . format ( "%02x" , bytes : byte ( index ) )
end

return table . concat ( parts )
end ;__nuppExports["encode"]=encode



decode=function ( text ) 
if # text % 2 ~= 0 then
return nil , "hex input must contain an even number of digits"
end
if text : find ( "[^0-9a-fA-F]" ) then
return nil , "hex input contains a non-hexadecimal digit"
end
local parts = { }
for index = 1 , # text , 2 do
parts [ # parts + 1 ] = string . char ( assert ( tonumber ( text : sub ( index , index + 1 ) , 16 ) ) )
end

return table . concat ( parts )
end ;__nuppExports["decode"]=decode
local __nuppWorkerSendables=_G.rawget(_G.nupp,"__workerSendables");if _G.type(__nuppWorkerSendables)~="table" then __nuppWorkerSendables=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerSendables",__nuppWorkerSendables) end;__nuppWorkerSendables[__nuppExports["encode"]]={module="nupp.codec.hex",member="encode",captures={values={},count=0},input="string",output="string"}; end);if not __nuppOk then package.loaded["nupp.codec.hex"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.hex"]=__nuppExports;return __nuppExports