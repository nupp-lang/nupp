_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitBand=bit.band;local __nuppBitBxor=bit.bxor;local __nuppBitLshift=bit.lshift;local __nuppBitRol=bit.rol;local __nuppBitRshift=bit.rshift;local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math")) require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.random\0runtime\0001") };





























local spi = require ( "nupp.spi" )
local target = require ( "nupp.runtime.target" )

local contracts = require ( "nupp.random.spi" )
local __nuppT2;do local __nuppT3,__nuppT4;repeat
const chosen = spi . select ( spi . load ("nupp.random.spi.Provider") )
if chosen ~= nil then
do  __nuppT2= chosen ;__nuppT3=true;break end
end
if target . host == "native" then
do  __nuppT2= _G . require ( "nupp.runtime.provider.nativecrypto" ) ;__nuppT3=true;break end
end
do  __nuppT2= _G . require ( "nupp.runtime.browser.crypto" ) ;__nuppT3=true;break end
 until true; end; local provider = __nuppT2





const randomBytes = provider . randomBytes ;__nuppExports["randomBytes"]=randomBytes

const INV32 = 1 / 4294967296
const TWO21 = 2097152
const TWO32 = 4294967296
const TWO53 = 9007199254740992
const DEFAULT_SEED = 1592594996
const GOLDEN = -1640531527
const ZERO = 0


local function mix32 ( value ) 
local shifted = __nuppBitTobit( (__nuppBitRshift( (__nuppBitTobit( value )%4294967296) ,__nuppBitBand( 16 ,31))%4294967296) )
local mixed = nupp . math . i32 . mul ( __nuppBitBxor( value , shifted ) , 569420461 )
shifted = __nuppBitTobit( (__nuppBitRshift( (__nuppBitTobit( mixed )%4294967296) ,__nuppBitBand( 15 ,31))%4294967296) )
mixed = nupp . math . i32 . mul ( __nuppBitBxor( mixed , shifted ) , 1935289751 )
shifted = __nuppBitTobit( (__nuppBitRshift( (__nuppBitTobit( mixed )%4294967296) ,__nuppBitBand( 15 ,31))%4294967296) )

return __nuppBitBxor( mixed , shifted )
end


local function expand ( seed ) 
local counter = __nuppBitTobit( seed )
counter = __nuppBitTobit(( counter )+( -1640531527 ))
local s0 = mix32 ( counter )
counter = __nuppBitTobit(( counter )+( -1640531527 ))
local s1 = mix32 ( counter )
counter = __nuppBitTobit(( counter )+( -1640531527 ))
local s2 = mix32 ( counter )
counter = __nuppBitTobit(( counter )+( -1640531527 ))
local s3 = mix32 ( counter )
if s0 == 0 and s1 == 0 and s2 == 0 and s3 == 0 then
return -1640531527 , 0 , 0 , 0
end

return s0 , s1 , s2 , s3
end



local Xoshiro128 = {} Xoshiro128.__index = Xoshiro128






function Xoshiro128.__nuppCtor1(seed) local self = _G.setmetatable({}, Xoshiro128)  local __nuppT7=self; 
self . s0 , self . s1 , self . s2 , self . s3 = expand ( seed or DEFAULT_SEED )
return __nuppT7 end


function Xoshiro128:next() 



local s0 = __nuppBitTobit( self . s0 )
local s1 = __nuppBitTobit( self . s1 )
local s2 = __nuppBitTobit( self . s2 )
local s3 = __nuppBitTobit( self . s3 )
local result = nupp . math . i32 . mul (
__nuppBitRol( nupp . math . i32 . mul ( s1 , __nuppBitTobit( 5 ) ) ,__nuppBitBand( 7 ,31)) ,
__nuppBitTobit( 9 )
)
local shifted = __nuppBitLshift( s1 ,__nuppBitBand( 9 ,31))
s2 = __nuppBitBxor( s2 , s0 )
s3 = __nuppBitBxor( s3 , s1 )
s1 = __nuppBitBxor( s1 , s2 )
s0 = __nuppBitBxor( s0 , s3 )
s2 = __nuppBitBxor( s2 , shifted )
s3 = __nuppBitRol( s3 ,__nuppBitBand( 11 ,31))
self . s0 , self . s1 , self . s2 , self . s3 = s0 , s1 , s2 , s3

return ( ( result ) * INV32 ) % 1
end








function Xoshiro128:integer(m, n) 
local low = 1
local high = m
if n ~= nil then
low = m
high = n
end
if low % 1 ~= 0 or high % 1 ~= 0 or math . abs ( low ) > TWO53 or math . abs ( high ) > TWO53 then
error (
"nupp: random.Xoshiro128:integer(" .. tostring (
low
) .. ", " .. tostring ( high ) .. ") needs finite integer bounds" ,
2
)
end
if high < low then
error (
"nupp: random.Xoshiro128:integer(" .. tostring ( low ) .. ", " .. tostring ( high ) .. ") has an empty range" ,
2
)
end
local span = high - low + 1
if span <= TWO32 then
return low + math . floor ( self : next ( ) * span )
end
if span > TWO53 then
error (
"nupp: random.Xoshiro128:integer(" .. tostring (
low
) .. ", " .. tostring ( high ) .. ") spans more than 2^53 values" ,
2
)
end





local limit = span * math . floor ( TWO53 / span )
while true do
local wide = math . floor ( self : next ( ) * TWO21 ) * TWO32 + self : next ( ) * TWO32
if wide < limit then
return ( low + wide % span )
end
end
end




function Xoshiro128:range(low, high) 
return low + self : next ( ) * ( high - low )
end


function Xoshiro128:shuffle(values) 
for index = # values , 2 , - 1 do
local other = 1 + math . floor ( self : next ( ) * index )
values [ index ] , values [ other ] = values [ other ] , values [ index ]
end

return values
end


function Xoshiro128:reseed(seed) 
self . s0 , self . s1 , self . s2 , self . s3 = expand ( seed )
end


function Xoshiro128:state() 
return { self . s0 , self . s1 , self . s2 , self . s3 }
end



function Xoshiro128:setState(words) 
if # words ~= 4 then
error ( "nupp: random.Xoshiro128:setState needs four state words" , 2 )
end
local s0 = __nuppBitTobit( words [ 1 ] )
local s1 = __nuppBitTobit( words [ 2 ] )
local s2 = __nuppBitTobit( words [ 3 ] )
local s3 = __nuppBitTobit( words [ 4 ] )
if s0 == ZERO and s1 == ZERO and s2 == ZERO and s3 == ZERO then
error ( "nupp: random.Xoshiro128:setState refused the all-zero state, the one xoshiro cannot leave" , 2 )
end
self . s0 , self . s1 , self . s2 , self . s3 = s0 , s1 , s2 , s3
end ;_G.nupp.__reflect.link(Xoshiro128,__nuppT1[1],{ }) ;__nuppExports["Xoshiro128"]=Xoshiro128
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Xoshiro128]="nupp.random\0Xoshiro128"; end);if not __nuppOk then package.loaded["nupp.random"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.random"]=__nuppExports;return __nuppExports