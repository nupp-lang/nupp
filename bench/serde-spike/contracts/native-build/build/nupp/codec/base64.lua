_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitBand=bit.band;local __nuppBitBor=bit.bor;local __nuppBitLshift=bit.lshift;local __nuppBitRshift=bit.rshift;local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

























local valuebuilder = require ( "nupp.codec.valuebuilder" )

local base64 = { }








const INVALID = { }

local function u32 ( value ) 
return (__nuppBitTobit( value )%4294967296)
end

local function add ( a , b ) 
return (__nuppBitTobit(( a )+( b ))%4294967296)
end

local function shr ( value , count ) 
return (__nuppBitRshift( value ,__nuppBitBand( count ,31))%4294967296)
end

local function shl ( value , count ) 
return (__nuppBitLshift( value ,__nuppBitBand( count ,31))%4294967296)
end

local function andBits ( a , b ) 
return (__nuppBitBand( a , b )%4294967296)
end

local function orBits ( a , b ) 
return (__nuppBitBor( a , b )%4294967296)
end




local function reversed ( word ) 
return orBits (
orBits ( shl ( word , 24 ) , shl ( andBits ( word , 65280 ) , 8 ) ) ,
orBits ( andBits ( shr ( word , 8 ) , 65280 ) , shr ( word , 24 ) )
)
end


local ks_07af12f296a4e582_encode_aot_builder
do
local ks_07af12f296a4e582_encode_aot_builderRegistrar = "ks_register_07af12f296a4e582_4fbf2519c42b2677__neon"
local function ks_07af12f296a4e582_encode_aot_builderLoad ( ) 
local modules = rawget ( _G , "__nuppAotBuilderModules" ) or { }
rawset ( _G , "__nuppAotBuilderModules" , modules )
local here = debug . getinfo ( 1 , "S" ) . source : match ( "^@(.*)$" )
local directory = here and here : match ( "^(.*)[/\\]" ) or "."
local started = directory
for _ = 0 , 8 do
local path = directory .. "/lib/libcompiled_contracts_aot.dylib"
local cacheKey = path .. "\0ks_register_07af12f296a4e582_4fbf2519c42b2677__neon"
local registered = modules [ cacheKey ]
if registered then return registered [ "encodeAot" ] end
do local __nuppT21=0; local  __nuppT27 ; local __nuppT22,__nuppT23,__nuppT24=__nuppT14(function() do local __nuppT28= io . open ( path , "rb" ) ; __nuppT27= __nuppT28 ; __nuppT21=1;  local probe=__nuppT27;
if probe then
probe : close ( )
local loadlib = rawget ( package , "loadlib" )
local open , why = loadlib ( path , "ks_register_07af12f296a4e582_4fbf2519c42b2677__neon" )
if not open then error ( "cannot register AOT builder: " .. tostring ( why ) , 0 ) end
registered = open ( ( require ( "nupp.runtime.aotruntime" ) ) . table ( ) )
if type ( registered ) ~= "table" or type ( registered [ "encodeAot" ] ) ~= "function" then error ( "malformed AOT builder registration" , 0 ) end
modules [ cacheKey ] = registered
return "return",__nuppT9( registered [ "encodeAot" ] )
end
directory = directory .. "/.." end; return "normal" end,__nuppT10); local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 and __nuppT27~=nil then  local __nuppT29,__nuppT30=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT29 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT30 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end
error ( "cannot find lib/libcompiled_contracts_aot.dylib at or above " .. started .. "; the compiled library has to travel with the module that calls it" , 0 )
end
ks_07af12f296a4e582_encode_aot_builder = ks_07af12f296a4e582_encode_aot_builderLoad ( )
end

local function encodeAot (
source ,
nullValue
) 
return ks_07af12f296a4e582_encode_aot_builder ( source , nullValue )
end

do
local entries = rawget ( _G , "__nuppAotCompiled" )
if entries == nil then
entries = setmetatable ( { } , { __mode = "k" } )
rawset ( _G , "__nuppAotCompiled" , entries )
end
entries [ encodeAot ] = true
end





local ks_07af12f296a4e582_decode_aot_builder
do
local ks_07af12f296a4e582_decode_aot_builderRegistrar = "ks_register_07af12f296a4e582_4fbf2519c42b2677__neon"
local function ks_07af12f296a4e582_decode_aot_builderLoad ( ) 
local modules = rawget ( _G , "__nuppAotBuilderModules" ) or { }
rawset ( _G , "__nuppAotBuilderModules" , modules )
local here = debug . getinfo ( 1 , "S" ) . source : match ( "^@(.*)$" )
local directory = here and here : match ( "^(.*)[/\\]" ) or "."
local started = directory
for _ = 0 , 8 do
local path = directory .. "/lib/libcompiled_contracts_aot.dylib"
local cacheKey = path .. "\0ks_register_07af12f296a4e582_4fbf2519c42b2677__neon"
local registered = modules [ cacheKey ]
if registered then return registered [ "decodeAot" ] end
do local __nuppT33=0; local  __nuppT39 ; local __nuppT34,__nuppT35,__nuppT36=__nuppT14(function() do local __nuppT40= io . open ( path , "rb" ) ; __nuppT39= __nuppT40 ; __nuppT33=1;  local probe=__nuppT39;
if probe then
probe : close ( )
local loadlib = rawget ( package , "loadlib" )
local open , why = loadlib ( path , "ks_register_07af12f296a4e582_4fbf2519c42b2677__neon" )
if not open then error ( "cannot register AOT builder: " .. tostring ( why ) , 0 ) end
registered = open ( ( require ( "nupp.runtime.aotruntime" ) ) . table ( ) )
if type ( registered ) ~= "table" or type ( registered [ "decodeAot" ] ) ~= "function" then error ( "malformed AOT builder registration" , 0 ) end
modules [ cacheKey ] = registered
return "return",__nuppT9( registered [ "decodeAot" ] )
end
directory = directory .. "/.." end; return "normal" end,__nuppT10); local __nuppT37={}; local __nuppT38=0; if __nuppT33>=1 and __nuppT39~=nil then  local __nuppT41,__nuppT42=__nuppT13(__nuppCleanup1,__nuppT39);  if not __nuppT41 then __nuppT38=__nuppT38+1; __nuppT37[__nuppT38]=__nuppT42 end; end; if not __nuppT34 then if __nuppT38>0 then __nuppT15(__nuppT11(__nuppT35,__nuppT37,1),0) else __nuppT15(__nuppT35,0) end end; if __nuppT38>0 then if __nuppT38>1 then __nuppT15(__nuppT11(__nuppT37[1],__nuppT37,2),0) else __nuppT15(__nuppT37[1],0) end end; if __nuppT35=="return" then  return __nuppT16(__nuppT36,1,__nuppT36.n)  end; end
end
error ( "cannot find lib/libcompiled_contracts_aot.dylib at or above " .. started .. "; the compiled library has to travel with the module that calls it" , 0 )
end
ks_07af12f296a4e582_decode_aot_builder = ks_07af12f296a4e582_decode_aot_builderLoad ( )
end

local function decodeAot (
text ,
nullValue
) 
return ks_07af12f296a4e582_decode_aot_builder ( text , nullValue )
end

do
local entries = rawget ( _G , "__nuppAotCompiled" )
if entries == nil then
entries = setmetatable ( { } , { __mode = "k" } )
rawset ( _G , "__nuppAotCompiled" , entries )
end
entries [ decodeAot ] = true
end









function base64 . encode ( value ) 
return ( ks_07af12f296a4e582_encode_aot_builder ( value , false ) )
end















function base64 . decode ( text ) 
if # text % 4 ~= 0 then
return nil , "base64 input length is not a multiple of four"
end
local decoded = ( ks_07af12f296a4e582_decode_aot_builder ( text , INVALID ) )
if decoded == INVALID then
return nil , "base64 input is not canonical padded base64"
end

return decoded , nil
end

local __nuppExportValue= base64 ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.codec.base64"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.base64"]=__nuppExports;return __nuppExports