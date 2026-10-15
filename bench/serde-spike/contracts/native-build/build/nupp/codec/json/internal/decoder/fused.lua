_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppModule = require("nupp.simd"); local __nuppT6={}; local function __nuppT3(...) return {n=select("#",...),...} end; local __nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT4(value) return value end; local function __nuppT5(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT12({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT13(v.primary) for _,reason in __nuppT14(v.suppressed) do text=text.."\ncleanup: "..__nuppT13(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






























































local _valueBuilder = require ( "nupp.codec.valuebuilder" )
local _jsonBuilder = require ( "nupp.codec.json.internal.builder" )
local array = require ( "nupp.mem.array" )
local simd = require ( "nupp.simd" )


local fused = { }







local function nibbleTable (
zero ,
e0 ,
e1 ,
e2 ,
e3 ,
e4 ,
e5 ,
e6 ,
e7 ,
e8 ,
e9 ,
e10 ,
e11 ,
e12 ,
e13 ,
e14 ,
e15
) 
return __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", __nuppModule.lane.method("insert","uint8", zero , 1 , e0 ) ,
2 , e1 ) ,
3 , e2 ) ,
4 , e3 ) ,
5 , e4 ) ,
6 , e5 ) ,
7 , e6 ) ,
8 , e7 ) ,
9 , e8 ) ,
10 , e9 ) ,
11 , e10 ) ,
12 , e11 ) ,
13 , e12 ) ,
14 , e13 ) ,
15 , e14 ) ,
16 , e15 )
end













local ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_builder
do
local ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_builderRegistrar = "ks_register_db5c9457e129530e_070172d80baf7574__neon"
local function ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_builderLoad ( ) 
local modules = rawget ( _G , "__nuppAotBuilderModules" ) or { }
rawset ( _G , "__nuppAotBuilderModules" , modules )
local here = debug . getinfo ( 1 , "S" ) . source : match ( "^@(.*)$" )
local directory = here and here : match ( "^(.*)[/\\]" ) or "."
local started = directory
for _ = 0 , 8 do
local path = directory .. "/lib/libcompiled_contracts_aot.dylib"
local cacheKey = path .. "\0ks_register_db5c9457e129530e_070172d80baf7574__neon"
local registered = modules [ cacheKey ]
if registered then return registered [ "__nuppConst_decodeFused_24f677cbe166e03f" ] end
do local __nuppT15=0; local  __nuppT21 ; local __nuppT16,__nuppT17,__nuppT18=__nuppT8(function() do local __nuppT22= io . open ( path , "rb" ) ; __nuppT21= __nuppT22 ; __nuppT15=1;  local probe=__nuppT21;
if probe then
probe : close ( )
local loadlib = rawget ( package , "loadlib" )
local open , why = loadlib ( path , "ks_register_db5c9457e129530e_070172d80baf7574__neon" )
if not open then error ( "cannot register AOT builder: " .. tostring ( why ) , 0 ) end
registered = open ( ( require ( "nupp.runtime.aotruntime" ) ) . table ( ) )
if type ( registered ) ~= "table" or type ( registered [ "__nuppConst_decodeFused_24f677cbe166e03f" ] ) ~= "function" then error ( "malformed AOT builder registration" , 0 ) end
modules [ cacheKey ] = registered
return "return",__nuppT3( registered [ "__nuppConst_decodeFused_24f677cbe166e03f" ] )
end
directory = directory .. "/.." end; return "normal" end,__nuppT4); local __nuppT19={}; local __nuppT20=0; if __nuppT15>=1 and __nuppT21~=nil then  local __nuppT23,__nuppT24=__nuppT7(__nuppCleanup1,__nuppT21);  if not __nuppT23 then __nuppT20=__nuppT20+1; __nuppT19[__nuppT20]=__nuppT24 end; end; if not __nuppT16 then if __nuppT20>0 then __nuppT9(__nuppT5(__nuppT17,__nuppT19,1),0) else __nuppT9(__nuppT17,0) end end; if __nuppT20>0 then if __nuppT20>1 then __nuppT9(__nuppT5(__nuppT19[1],__nuppT19,2),0) else __nuppT9(__nuppT19[1],0) end end; if __nuppT17=="return" then  return __nuppT10(__nuppT18,1,__nuppT18.n)  end; end
end
error ( "cannot find lib/libcompiled_contracts_aot.dylib at or above " .. started .. "; the compiled library has to travel with the module that calls it" , 0 )
end
ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_builder = ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_builderLoad ( )
end

local function __nuppConst_decodeFused_24f677cbe166e03f (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
local native1 , native2 , native3 = ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_builder ( source , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
return native1 , (__nuppBitTobit( native2 )%4294967296) , (__nuppBitTobit( native3 )%4294967296)
end

do
local entries = rawget ( _G , "__nuppAotCompiled" )
if entries == nil then
entries = setmetatable ( { } , { __mode = "k" } )
rawset ( _G , "__nuppAotCompiled" , entries )
end
entries [ __nuppConst_decodeFused_24f677cbe166e03f ] = true
end

local ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_builder
do
local ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_builderRegistrar = "ks_register_db5c9457e129530e_070172d80baf7574__neon"
local function ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_builderLoad ( ) 
local modules = rawget ( _G , "__nuppAotBuilderModules" ) or { }
rawset ( _G , "__nuppAotBuilderModules" , modules )
local here = debug . getinfo ( 1 , "S" ) . source : match ( "^@(.*)$" )
local directory = here and here : match ( "^(.*)[/\\]" ) or "."
local started = directory
for _ = 0 , 8 do
local path = directory .. "/lib/libcompiled_contracts_aot.dylib"
local cacheKey = path .. "\0ks_register_db5c9457e129530e_070172d80baf7574__neon"
local registered = modules [ cacheKey ]
if registered then return registered [ "__nuppConst_decodeFused_a640dbc37ebbc1be" ] end
do local __nuppT27=0; local  __nuppT33 ; local __nuppT28,__nuppT29,__nuppT30=__nuppT8(function() do local __nuppT34= io . open ( path , "rb" ) ; __nuppT33= __nuppT34 ; __nuppT27=1;  local probe=__nuppT33;
if probe then
probe : close ( )
local loadlib = rawget ( package , "loadlib" )
local open , why = loadlib ( path , "ks_register_db5c9457e129530e_070172d80baf7574__neon" )
if not open then error ( "cannot register AOT builder: " .. tostring ( why ) , 0 ) end
registered = open ( ( require ( "nupp.runtime.aotruntime" ) ) . table ( ) )
if type ( registered ) ~= "table" or type ( registered [ "__nuppConst_decodeFused_a640dbc37ebbc1be" ] ) ~= "function" then error ( "malformed AOT builder registration" , 0 ) end
modules [ cacheKey ] = registered
return "return",__nuppT3( registered [ "__nuppConst_decodeFused_a640dbc37ebbc1be" ] )
end
directory = directory .. "/.." end; return "normal" end,__nuppT4); local __nuppT31={}; local __nuppT32=0; if __nuppT27>=1 and __nuppT33~=nil then  local __nuppT35,__nuppT36=__nuppT7(__nuppCleanup1,__nuppT33);  if not __nuppT35 then __nuppT32=__nuppT32+1; __nuppT31[__nuppT32]=__nuppT36 end; end; if not __nuppT28 then if __nuppT32>0 then __nuppT9(__nuppT5(__nuppT29,__nuppT31,1),0) else __nuppT9(__nuppT29,0) end end; if __nuppT32>0 then if __nuppT32>1 then __nuppT9(__nuppT5(__nuppT31[1],__nuppT31,2),0) else __nuppT9(__nuppT31[1],0) end end; if __nuppT29=="return" then  return __nuppT10(__nuppT30,1,__nuppT30.n)  end; end
end
error ( "cannot find lib/libcompiled_contracts_aot.dylib at or above " .. started .. "; the compiled library has to travel with the module that calls it" , 0 )
end
ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_builder = ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_builderLoad ( )
end

local function __nuppConst_decodeFused_a640dbc37ebbc1be (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
local native1 , native2 , native3 = ks_db5c9457e129530e___nupp_const_decode_fused_a640dbc37ebbc1be__5f5f6e757070436f6e73745f6465636f646546757365645f61363430646263333765626263316265_builder ( source , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
return native1 , (__nuppBitTobit( native2 )%4294967296) , (__nuppBitTobit( native3 )%4294967296)
end

do
local entries = rawget ( _G , "__nuppAotCompiled" )
if entries == nil then
entries = setmetatable ( { } , { __mode = "k" } )
rawset ( _G , "__nuppAotCompiled" , entries )
end
entries [ __nuppConst_decodeFused_a640dbc37ebbc1be ] = true
end

local ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_builder
do
local ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_builderRegistrar = "ks_register_db5c9457e129530e_070172d80baf7574__neon"
local function ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_builderLoad ( ) 
local modules = rawget ( _G , "__nuppAotBuilderModules" ) or { }
rawset ( _G , "__nuppAotBuilderModules" , modules )
local here = debug . getinfo ( 1 , "S" ) . source : match ( "^@(.*)$" )
local directory = here and here : match ( "^(.*)[/\\]" ) or "."
local started = directory
for _ = 0 , 8 do
local path = directory .. "/lib/libcompiled_contracts_aot.dylib"
local cacheKey = path .. "\0ks_register_db5c9457e129530e_070172d80baf7574__neon"
local registered = modules [ cacheKey ]
if registered then return registered [ "__nuppConst_decodeFused_f007fffb3d50ef9f" ] end
do local __nuppT39=0; local  __nuppT45 ; local __nuppT40,__nuppT41,__nuppT42=__nuppT8(function() do local __nuppT46= io . open ( path , "rb" ) ; __nuppT45= __nuppT46 ; __nuppT39=1;  local probe=__nuppT45;
if probe then
probe : close ( )
local loadlib = rawget ( package , "loadlib" )
local open , why = loadlib ( path , "ks_register_db5c9457e129530e_070172d80baf7574__neon" )
if not open then error ( "cannot register AOT builder: " .. tostring ( why ) , 0 ) end
registered = open ( ( require ( "nupp.runtime.aotruntime" ) ) . table ( ) )
if type ( registered ) ~= "table" or type ( registered [ "__nuppConst_decodeFused_f007fffb3d50ef9f" ] ) ~= "function" then error ( "malformed AOT builder registration" , 0 ) end
modules [ cacheKey ] = registered
return "return",__nuppT3( registered [ "__nuppConst_decodeFused_f007fffb3d50ef9f" ] )
end
directory = directory .. "/.." end; return "normal" end,__nuppT4); local __nuppT43={}; local __nuppT44=0; if __nuppT39>=1 and __nuppT45~=nil then  local __nuppT47,__nuppT48=__nuppT7(__nuppCleanup1,__nuppT45);  if not __nuppT47 then __nuppT44=__nuppT44+1; __nuppT43[__nuppT44]=__nuppT48 end; end; if not __nuppT40 then if __nuppT44>0 then __nuppT9(__nuppT5(__nuppT41,__nuppT43,1),0) else __nuppT9(__nuppT41,0) end end; if __nuppT44>0 then if __nuppT44>1 then __nuppT9(__nuppT5(__nuppT43[1],__nuppT43,2),0) else __nuppT9(__nuppT43[1],0) end end; if __nuppT41=="return" then  return __nuppT10(__nuppT42,1,__nuppT42.n)  end; end
end
error ( "cannot find lib/libcompiled_contracts_aot.dylib at or above " .. started .. "; the compiled library has to travel with the module that calls it" , 0 )
end
ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_builder = ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_builderLoad ( )
end

local function __nuppConst_decodeFused_f007fffb3d50ef9f (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
local native1 , native2 , native3 = ks_db5c9457e129530e___nupp_const_decode_fused_f007fffb3d50ef9f__5f5f6e757070436f6e73745f6465636f646546757365645f66303037666666623364353065663966_builder ( source , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
return native1 , (__nuppBitTobit( native2 )%4294967296) , (__nuppBitTobit( native3 )%4294967296)
end

do
local entries = rawget ( _G , "__nuppAotCompiled" )
if entries == nil then
entries = setmetatable ( { } , { __mode = "k" } )
rawset ( _G , "__nuppAotCompiled" , entries )
end
entries [ __nuppConst_decodeFused_f007fffb3d50ef9f ] = true
end

local function decodeFused (
source ,
variant ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 

if variant == 2 then
return __nuppConst_decodeFused_24f677cbe166e03f ( source , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
elseif variant == 0 then
return __nuppConst_decodeFused_a640dbc37ebbc1be ( source , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
elseif variant == 1 then
return __nuppConst_decodeFused_f007fffb3d50ef9f ( source , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
end
error ( "no compiled const application exists for this argument tuple" , 2 )
end
local ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_compiledEntries = rawget ( _G , "__nuppAotCompiled" )
if ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_compiledEntries == nil then
ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_compiledEntries = setmetatable ( { } , { __mode = "k" } )
rawset ( _G , "__nuppAotCompiled" , ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_compiledEntries )
end
ks_db5c9457e129530e___nupp_const_decode_fused_24f677cbe166e03f__5f5f6e757070436f6e73745f6465636f646546757365645f32346636373763626531363665303366_compiledEntries [ decodeFused ] = true


function fused . decodePull (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
return decodeFused ( source , 0 , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
end




function fused . decodeSerde (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
return decodeFused ( source , 1 , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
end


function fused . decodeEager (
source ,
nullValue ,
arrayMarker ,
objectMarker ,
shape ,
arrayShapeMarker ,
serdeMarkers
) 
return decodeFused ( source , 2 , nullValue , arrayMarker , objectMarker , shape , arrayShapeMarker , serdeMarkers )
end

local __nuppExportValue= fused ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.codec.json.internal.decoder.fused"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.json.internal.decoder.fused"]=__nuppExports;return __nuppExports