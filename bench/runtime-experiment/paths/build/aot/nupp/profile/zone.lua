_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()








































local zone = __nuppNew(0,4)


local stack = require ( "jit.zone" )



local references = 0
local generation = 0




zone . __nuppActive = false
zone . __nuppDepth = 0
zone . __nuppStack = stack
zone . __nuppVersion = 0



local pathVersion = -1
local pathText = ""
local pathBuffer = { }


function zone . isActive ( ) 
return zone . __nuppActive
end


function zone . depth ( ) 
return zone . __nuppDepth
end




function zone . acquire ( ) 
references = references + 1
if references > 1 then
return
end

for index = # stack , 1 , -1 do
stack [ index ] = nil
end
zone . __nuppDepth = 0
zone . __nuppVersion = ( zone . __nuppVersion + 1 )
generation = generation + 1
zone . __nuppActive = true
end



function zone . release ( ) 
if references == 0 then
return
end

references = references - 1
if references > 0 then
return
end

for index = # stack , 1 , -1 do
stack [ index ] = nil
end
zone . __nuppDepth = 0
zone . __nuppVersion = ( zone . __nuppVersion + 1 )
zone . __nuppActive = false
end














function zone . push ( name ) 
if not zone . __nuppActive then
return
end

zone . __nuppDepth = ( zone . __nuppDepth + 1 )
stack [ zone . __nuppDepth ] = name
zone . __nuppVersion = ( zone . __nuppVersion + 1 )
end








function zone . pop ( ) 
if not zone . __nuppActive or zone . __nuppDepth == 0 then
return nil
end

local name = stack [ zone . __nuppDepth ]
stack [ zone . __nuppDepth ] = nil
zone . __nuppDepth = ( zone . __nuppDepth - 1 )
zone . __nuppVersion = ( zone . __nuppVersion + 1 )

return name
end


function zone . current ( ) 
if zone . __nuppDepth == 0 then
return nil
end
return stack [ zone . __nuppDepth ]
end








function zone . path ( ) 
if zone . __nuppVersion == pathVersion then
return pathText
end

if zone . __nuppDepth == 0 then
pathText = ""
else
for index = 1 , zone . __nuppDepth do
pathBuffer [ index ] = stack [ index ]
end
pathText = table . concat ( pathBuffer , "/" , 1 , zone . __nuppDepth )
end
pathVersion = zone . __nuppVersion

return pathText
end















function zone . enter ( name ) 
if not zone . __nuppActive then
return 0
end

zone . __nuppDepth = ( zone . __nuppDepth + 1 )
stack [ zone . __nuppDepth ] = name
zone . __nuppVersion = ( zone . __nuppVersion + 1 )

return generation
end





function zone . leave ( token ) 
if token == 0 or not zone . __nuppActive or token ~= generation then
return
end
if zone . __nuppDepth == 0 then
return
end

stack [ zone . __nuppDepth ] = nil
zone . __nuppDepth = ( zone . __nuppDepth - 1 )
zone . __nuppVersion = ( zone . __nuppVersion + 1 )
end

local __nuppExportValue= zone ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.profile.zone"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.profile.zone"]=__nuppExports;return __nuppExports