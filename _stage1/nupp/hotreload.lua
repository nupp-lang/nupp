_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);













local hotreload = { }
local debugAny = debug

local STATE_KEY = "__nuppHotReloadState"
local API_KEY = "__nuppHotReload"

local state = _G [ STATE_KEY ]
if not state then
state = {
generation = 1 ,
modules = { } ,
bySlots = setmetatable ( { } , {
__mode = "k"
} ) ,
staging = nil ,
preparedSerial = 0 ,
}
_G [ STATE_KEY ] = state
end

local function upvalues ( fn , selfName )
local byName , order = { } , { }
local index = 1
while true do
local name = debug . getupvalue ( fn , index )
if not name then
break
end
if name ~= selfName then
if byName [ name ] then
error ( "nupp hot reload: duplicate upvalue " .. name , 3 )
end
byName [ name ] = index
order [ # order + 1 ] = name
end
index = index + 1
end
table . sort ( order )

return { byName = byName , order = order }
end

local function sameNames ( left , right )
if # left ~= # right then
return false
end
for index = 1 , # left do
if left [ index ] ~= right [ index ] then
return false
end
end

return true
end





local function detachSelf ( fn , selfName )
if not selfName then
return
end



local found = nil
local index = 1
while true do
local name = debug . getupvalue ( fn , index )
if not name then
break
end
if name == selfName then
found = index
break
end
index = index + 1
end
if not found then
return
end
local value = fn
local function anchor ( )
return value
end

debugAny . upvaluejoin ( fn , found , anchor , 1 )
end

local function moduleForSlots ( slots )
local module = state . bySlots [ slots ]
if not module then
error ( "nupp hot reload: an implementation used an unknown slot array" , 3 )
end

return module
end




function hotreload . module ( name )
local module = state . modules [ name ]
if module then
if state . staging and not module . loaded then
error ( "nupp hot reload: patch names unloaded module " .. name , 2 )
end
return module . slots
end
if state . staging then
error ( "nupp hot reload: patch names unloaded module " .. name , 2 )
end
module = { name = name , slots = { } , definitions = { } , policies = { } , loaded = false }
state . modules [ name ] = module
state . bySlots [ module . slots ] = module

return module . slots
end



function hotreload . policy ( slots , key )
local module = moduleForSlots ( slots )
local staging = state . staging
if not staging then
module . policies [ key ] = true
return
end
local policies = staging . policies [ module ] or { }
staging . policies [ module ] = policies
policies [ key ] = true
end



function hotreload . seal ( name )
local module = state . modules [ name ]
if not module or module . loaded then
error ( "nupp hot reload: cannot seal unknown or loaded module " .. name , 2 )
end
module . loaded = true
end


function hotreload . abort ( name )
local module = state . modules [ name ]
if not module or module . loaded then
return
end
state . bySlots [ module . slots ] = nil
state . modules [ name ] = nil
end




function hotreload . define (
slots ,
index ,
id ,
signature ,
selfName ,
implementation
)
local module = moduleForSlots ( slots )
detachSelf ( implementation , selfName )
local captures = upvalues ( implementation , selfName )
local staging = state . staging
if not staging then
if module . definitions [ index ] then
error ( "nupp hot reload: slot " .. tostring ( index ) .. " was defined twice" , 2 )
end
module . definitions [ index ] = { id = id , signature = signature , selfName = selfName , captures = captures , }
slots [ index ] = implementation
return
end

local live = module . definitions [ index ]
if not live or live . id ~= id then
error ( "nupp hot reload: stable function identity changed for " .. id , 2 )
end
if live . signature ~= signature then
error ( "nupp hot reload: signature changed for " .. id .. "; restart required" , 2 )
end
if live . selfName ~= selfName then
error ( "nupp hot reload: recursive binding changed for " .. id .. "; restart required" , 2 )
end
if not sameNames ( live . captures . order , captures . order ) then
error ( "nupp hot reload: captured bindings changed for " .. id .. "; restart required" , 2 )
end
for _ , name in ipairs ( captures . order ) do
debugAny . upvaluejoin ( implementation , captures . byName [ name ] , slots [ index ] , live . captures . byName [ name ] )
end
local key = module . name .. "\0" .. tostring ( index )
if staging . byKey [ key ] then
error ( "nupp hot reload: patch defines " .. id .. " twice" , 2 )
end
local candidate = { module = module , index = index , implementation = implementation }
staging . byKey [ key ] = candidate
staging . candidates [ # staging . candidates + 1 ] = candidate
end




function hotreload . stage ( source , baseGeneration )
if state . staging then
return nil , "another patch is already staging"
end
if baseGeneration ~= state . generation then
return nil , "stale generation"
end
local chunk , loadError = loadstring ( source , "@nupp-hot-patch" )
if not chunk then
return nil , tostring ( loadError )
end
local staging = { baseGeneration = baseGeneration , candidates = { } , byKey = { } , policies = { } }
state . staging = staging
local ok , reason = pcall ( chunk )
state . staging = nil
if not ok then
return nil , tostring ( reason )
end
local changedModules = { }
for _ , candidate in ipairs ( staging . candidates ) do
changedModules [ candidate . module ] = true
end
local policyCount = _G . __nuppDynamicPolicyCount
for module in pairs ( changedModules ) do
local candidatePolicies = staging . policies [ module ] or { }
for policy in pairs ( module . policies or { } ) do
if not candidatePolicies [ policy ] and policyCount and policyCount ( policy ) > 0 then
return nil , "live dynamic capability policy changed; drain its store entries before reloading"
end
end
end
state . preparedSerial = state . preparedSerial + 1

return {
baseGeneration = baseGeneration ,
generation = baseGeneration + 1 ,
serial = state . preparedSerial ,
candidates = staging . candidates ,
policies = staging . policies ,
committed = false ,
}
end




function hotreload . commit ( prepared )
if type ( prepared ) ~= "table" or prepared . committed then
return nil , "patch was already committed or is invalid"
end
if prepared . baseGeneration ~= state . generation then
return nil , "stale generation"
end


for _ , candidate in ipairs ( prepared . candidates ) do
candidate . module . slots [ candidate . index ] = candidate . implementation
end
for module , policies in pairs ( prepared . policies or { } ) do
module . policies = policies
end
prepared . committed = true
state . generation = prepared . generation
jit . flush ( )

return state . generation
end


function hotreload . generation ( )
return state . generation
end


function hotreload . loaded ( name )
local module = state . modules [ name ]
return module ~= nil and module . loaded == true
end


function hotreload . resetForTesting ( )
state . generation = 1
state . modules = { }
state . bySlots = setmetatable ( { } , { __mode = "k" } )
state . staging = nil
state . preparedSerial = 0
end

_G [ API_KEY ] = hotreload

return hotreload
