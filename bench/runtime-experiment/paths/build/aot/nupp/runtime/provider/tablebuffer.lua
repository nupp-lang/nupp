_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















const buffer = { }



local Buffer = {} Buffer.__index = Buffer





















function Buffer:put(...) 
const arrived = select ( "#" , ... )
for index = 1 , arrived do
const value = select ( index , ... )
const kind = type ( value )
if kind ~= "string" and kind ~= "number" then
const meta = getmetatable ( value )
if type ( meta ) ~= "table" or ( meta ) . __tostring == nil then
error ( "buffer put value must be a string, a number or have __tostring, not " .. kind , 2 )
end
end
const text = kind == "string" and value or tostring ( value )
if # text > 0 then
self . count = self . count + 1
self . pieces [ self . count ] = text
self . bytes = self . bytes + # text
end
end

return self
end




function Buffer:get(...) 
local arrived = select ( "#" , ... )
if arrived == 0 then
return self : take ( nil )
end


local counts = { ... }
local values = { }
for index = 1 , arrived do
values [ index ] = self : take ( counts [ index ] )
end

return unpack ( values , 1 , arrived )
end


function Buffer:tostring() 
if self . bytes == 0 then
return ""
end
local chunks = { self . pieces [ self . head ] : sub ( self . firstByte ) }
for index = self . head + 1 , self . count do
chunks [ # chunks + 1 ] = self . pieces [ index ]
end

return table . concat ( chunks )
end

function Buffer:putf(fmt, ...) 
return self : put ( string . format ( fmt , ... ) )
end

function Buffer:skip(count) 
self : take ( count )
return self
end

function Buffer:set(bytes) 
self : reset ( )
return self : put ( bytes )
end

function Buffer:free() 
return self : reset ( )
end

function Buffer:reset() 
self . pieces = { }
self . count = 0
self . head = 1
self . firstByte = 1
self . bytes = 0

return self
end


function Buffer . take ( self , count ) 
local wanted = count or self . bytes
assert ( wanted >= 0 and wanted % 1 == 0 , "buffer get count must be a nonnegative integer" )
wanted = math . min ( wanted , self . bytes )
local remaining = wanted
local chunks = { }
while remaining > 0 do
local piece = self . pieces [ self . head ]
local take = math . min ( remaining , # piece - self . firstByte + 1 )
chunks [ # chunks + 1 ] = piece : sub ( self . firstByte , self . firstByte + take - 1 )
self . firstByte = self . firstByte + take
remaining = remaining - take
if self . firstByte > # piece then
self . pieces [ self . head ] = nil
self . head = self . head + 1
self . firstByte = 1
end
end
self . bytes = self . bytes - wanted
if self . bytes == 0 then
self . head = 1
self . count = 0
elseif self . head > 64 and self . head > self . count / 2 then
local nextPieces = { }
for index = self . head , self . count do
nextPieces [ # nextPieces + 1 ] = self . pieces [ index ]
end
self . count = # nextPieces
self . head = 1
self . pieces = nextPieces
end

return table . concat ( chunks )
end

;
( Buffer ) . __len = function ( self ) 
return self . bytes
end

;
( Buffer ) . __concat = function ( left , right ) 
return tostring ( left ) .. tostring ( right )
end

;
( Buffer ) . __tostring = function ( self ) 
return self : tostring ( )
end



local proxyStates = setmetatable ( { } , { __mode = "k" } )
local proxyFactory = nil
local proxyPrototype = nil
local lengthProbe = setmetatable ( { } , {
__len = function ( ) 
return 1
end ,
} )
if # lengthProbe ~= 1 then
local makeProxy = rawget ( _G , "newproxy" )
assert ( type ( makeProxy ) == "function" , "table __len requires newproxy on this runtime" )
proxyFactory = makeProxy
proxyPrototype = makeProxy ( true )
local proxyMetatable = assert ( getmetatable ( proxyPrototype ) )
proxyMetatable . __index = proxyMetatable
proxyMetatable . put = function ( self , ... ) 
const state = assert ( proxyStates [ self ] )
state : put ( ... )
return self
end
proxyMetatable . get = function ( self , ... ) 
const state = assert ( proxyStates [ self ] )
return state : get ( ... )
end
proxyMetatable . tostring = function ( self ) 
const state = assert ( proxyStates [ self ] )
return state : tostring ( )
end
proxyMetatable . reset = function ( self ) 
const state = assert ( proxyStates [ self ] )
state : reset ( )
return self
end
for _ , name in ipairs ( { "putf" , "skip" , "set" , "free" } ) do
proxyMetatable [ name ] = function ( self , ... ) 
local state = assert ( proxyStates [ self ] )
state [ name ] ( state , ... )
return self
end
end
proxyMetatable . __len = function ( self ) 
const state = assert ( proxyStates [ self ] )
return ( Buffer ) . __len ( state )
end
proxyMetatable . __concat = ( Buffer ) . __concat
proxyMetatable . __tostring = proxyMetatable . tostring
end










function buffer . new ( size , options ) 
const state = _G.setmetatable({ pieces =  { } ,  count =  0 ,  head =  1 ,  firstByte =  1 ,  bytes =  0 }, Buffer)
if proxyPrototype ~= nil then
const proxy = proxyFactory ( proxyPrototype )
proxyStates [ proxy ] = state
return proxy
end

return state
end

local __nuppExportValue= buffer ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.tablebuffer"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.tablebuffer"]=__nuppExports;return __nuppExports