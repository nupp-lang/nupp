_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


















local contracts = require ( "nupp.io.uri.spi" )
const whatwg = require ( "nupp.io.uri.whatwg" )
local browserHost = rawget ( _G , "__nuppBrowser" )
local provider = { }



function provider . parse ( text ) 
local hostParse = browserHost ~= nil and browserHost . url or nil
if hostParse == nil then
return whatwg . parse ( text )
end


local refused = whatwg . refusal ( text )
if refused ~= nil then
return nil , refused
end
local answer = hostParse ( text )
if type ( answer ) ~= "table" or type ( answer . href ) ~= "string" then
local problem = type ( answer ) == "table" and answer . error or nil
return nil , type ( problem ) == "string" and problem or "invalid URL"
end



local parts , reason = whatwg . parse ( answer . href , nil , true )

return parts , reason
end

local checked = { parse = provider . parse }
local __nuppExportValue= checked ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.uri"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.uri"]=__nuppExports;return __nuppExports