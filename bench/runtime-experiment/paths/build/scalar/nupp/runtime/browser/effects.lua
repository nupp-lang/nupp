_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local json = require ( "nupp.runtime.provider.lunajson" )
local effects = { }
local nextId = 1
local queued = { }
local waiting = { }
local hostTurns = 0
local browserHost = rawget ( _G , "__nuppBrowser" )
local relays = setmetatable ( { } , { __mode = "k" } )





local frozenText = setmetatable ( { } , { __mode = "k" } )




const FRAME_TEXT_BYTES = 983040
const FRAME_LEASE_BYTES = 2097152
const FRAME_LEASE_DESCRIPTOR_BYTES = 96
const FRAME_REQUESTS = 256

local function invalidResponse ( detail ) 
error ( "nupp: browser application returned an invalid effect response: " .. detail , 0 )
end

local function decodedResponse ( text ) 
if type ( text ) ~= "string" then
invalidResponse ( "expected JSON text" )
end
local decoded , response = pcall ( json . decode , text )
if not decoded then
invalidResponse ( "invalid JSON" )
end
if type ( response ) ~= "table" or json . isArray ( response ) then
invalidResponse ( "expected an object" )
end
if response . cancelled ~= nil and type ( response . cancelled ) ~= "boolean" then
invalidResponse ( "cancelled must be boolean" )
end
local responses = response . responses
if responses == nil then
responses = { }
elseif type ( responses ) ~= "table" or not json . isArray ( responses ) then
invalidResponse ( "responses must be an array" )
end
local count = 0
local highest = 0
for key in pairs ( responses ) do
if type ( key ) ~= "number" or key < 1 or key % 1 ~= 0 then
invalidResponse ( "responses must be an array" )
end
count = count + 1
highest = math . max ( highest , key )
end
if count ~= highest then
invalidResponse ( "responses must be an array" )
end
for _ , item in ipairs ( responses ) do
if type ( item ) ~= "table" or type ( item . id ) ~= "number" or item . id < 1 or item . id % 1 ~= 0 then
invalidResponse ( "every response needs a positive integer id" )
end
end

return response , responses
end

function effects . request (
kind ,
payload ,
resume ,
discard ,
frozen
) 
local id = nextId
nextId = nextId + 1
payload . id = id
payload . kind = kind



local encodable , encoded = pcall ( json . encode , payload )
if not encodable then
error ( "nupp: browser effect " .. kind .. " has no JSON form: " .. tostring ( encoded ) , 0 )
end
if frozen then
frozenText [ payload ] = encoded
end
queued [ # queued + 1 ] = payload
local active = true
waiting [ id ] = function ( response ) 
if not active then
return
end
active = false
waiting [ id ] = nil
resume ( response )
end



return function ( ) 
if not active then
return false
end
active = false


for index = # queued , 1 , -1 do
if queued [ index ] == payload then
table . remove ( queued , index )
waiting [ id ] = nil
return true
end
end



if discard == nil then
waiting [ id ] = nil
return false
end
waiting [ id ] = function ( response ) 
waiting [ id ] = nil
discard ( response )
end

return false
end
end

local function leaseIdentifiers ( request ) 
local found = { }
if request . lease ~= nil then
found [ # found + 1 ] = request . lease
end
if request . bodyLease ~= nil then
found [ # found + 1 ] = request . bodyLease
end
if request . resultLease ~= nil then
found [ # found + 1 ] = request . resultLease
end
if type ( request . spans ) == "table" then
for _ , span in ipairs ( request . spans ) do
if type ( span ) == "table" and span . lease ~= nil then
found [ # found + 1 ] = span . lease
end
end
end

return found
end




local function takeFrame ( ) 
local guestMemory = browserHost ~= nil and browserHost . memory or nil
local bytesOf = guestMemory ~= nil and rawget ( guestMemory , "leaseBytes" ) or nil
local taken = { }
local text = 0
local lent = 0
local seen = { }
local count = # queued
local index = 1
while index <= count and # taken < 256 do
local request = queued [ index ]

local encoded = frozenText [ request ] or json . encode ( request )
local requestText = # encoded
local requestLent = 0
local leases = leaseIdentifiers ( request )
for _ , lease in ipairs ( leases ) do
if not seen [ lease ] then
requestText = requestText + 96
if bytesOf ~= nil then
requestLent = requestLent + ( bytesOf ( lease ) )
end
end
end
if # taken > 0 and ( text + requestText > 983040 or lent + requestLent > 2097152 ) then
do break end
end
for _ , lease in ipairs ( leases ) do
seen [ lease ] = true
end
text = text + requestText
lent = lent + requestLent
taken [ # taken + 1 ] = encoded
index = index + 1
end
local rest = { }
for remaining = index , count do
rest [ # rest + 1 ] = queued [ remaining ]
end

return taken , # rest > 0 , rest
end

local preparers = { }






function effects . beforePark ( prepare ) 
preparers [ # preparers + 1 ] = prepare
end




function effects . canParkFrom ( thread ) 
local root = browserHost ~= nil and browserHost . root or nil
if root == nil then
return true
end
local current = thread
while current ~= nil do
if current == root then
return true
end
current = relays [ current ]
end

return false
end


function effects . canPark ( ) 
return effects . canParkFrom ( ( coroutine . running ( ) ) )
end





function effects . relay ( thread ) 
relays [ thread ] = coroutine . running ( )
end





function effects . outstanding ( ) 
return next ( waiting ) ~= nil
end


function effects . turns ( ) 
return hostTurns
end












function effects . park ( operation , turn ) 
if not effects . canPark ( ) then
error ( "nupp: " .. operation .. " cannot suspend here: only the browser application's root can wait" , 0 )
end
local runnable = false
for _ , prepare in ipairs ( preparers ) do
if prepare ( ) then
runnable = true
end
end
local encoded
local wake = ( turn == true or runnable ) and "turn" or "any"
if # queued == 0 then
encoded = json . encode ( { kind = "poll" , operation = operation , wake = wake , } )
else
local taken , more , rest = takeFrame ( )


if more then
wake = "turn"
end
encoded = "{\"kind\":\"effects\",\"requests\":[" .. table . concat ( taken , "," ) .. "],\"wake\":\"" .. wake .. "\"}"
queued = rest
end
local responseText = coroutine . yield ( encoded )
hostTurns = hostTurns + 1
local response , responses = decodedResponse ( responseText )
if response . cancelled then
error ( "nupp: browser application was cancelled" , 0 )
end
local dispatchFailure = nil
for _ , item in ipairs ( responses ) do
local deliver = waiting [ item . id ]
if deliver ~= nil then
local delivered , problem = pcall ( deliver , item )
if not delivered and dispatchFailure == nil then
dispatchFailure = problem
end
end
end
if dispatchFailure ~= nil then
error ( dispatchFailure , 0 )
end
end

local __nuppExportValue= effects ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.effects"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.effects"]=__nuppExports;return __nuppExports