_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()local algorithm;__nuppExports["algorithm"]=function(...) return algorithm(...) end;local algorithms;__nuppExports["algorithms"]=function(...) return algorithms(...) end;local digest;__nuppExports["digest"]=function(...) return digest(...) end;local hexDigest;__nuppExports["hexDigest"]=function(...) return hexDigest(...) end;local lookup;__nuppExports["lookup"]=function(...) return lookup(...) end;local newMac;__nuppExports["newMac"]=function(...) return newMac(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.mac\0runtime\0001") };







































local spi = require ( "nupp.spi" )

const context = require ( "nupp.digest.internal.context" )
const provider = require ( "nupp.mac.spi" )





local Algorithm = {} Algorithm.__index = Algorithm











function Algorithm:newMac(key) 
return context . wrap ( self . implementation : create ( key ) , self . name , self . digestSize )
end ;_G.nupp.__reflect.link(Algorithm,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../../src/nupp/mac/spi.nupp\0Algorithm\0interface\0module\0001","nupp.mac.spi") }) ;__nuppExports["Algorithm"]=Algorithm


local standard = require ( "nupp.runtime.provider.mac" )

local function validate ( selected ) 
for name , implementation in pairs ( selected . algorithms ) do
if type ( name ) ~= "string"
or name == ""
or type ( implementation ) ~= "table"
or implementation . name ~= name
or type ( implementation . digestSize ) ~= "number"
or implementation . digestSize <= 0
or implementation . digestSize % 1 ~= 0
or type ( implementation . create ) ~= "function"
then
error ( "invalid mac algorithm descriptor " .. tostring ( name ) , 2 )
end
local expected = standard . algorithms [ name ]
if expected ~= nil and implementation . digestSize ~= expected . digestSize then
error ( "mac provider has the wrong digestSize for " .. name , 2 )
end
end
end

local selected = spi . select ( spi . load ("nupp.mac.spi.Provider") ) ?? standard
validate ( selected )
local available = { }
for name , implementation in pairs ( standard . algorithms ) do
available [
name
] = _G.setmetatable({ name =  name ,  digestSize =  implementation . digestSize ,  implementation =  implementation }, Algorithm)
end
for name , implementation in pairs ( selected . algorithms ) do
available [
name
] = _G.setmetatable({ name =  name ,  digestSize =  implementation . digestSize ,  implementation =  implementation }, Algorithm)
end
local names = { }
for name in pairs ( available ) do
names [ # names + 1 ] = name
end
table . sort ( names )




lookup=function ( name ) 
return available [ name ]
end ;__nuppExports["lookup"]=lookup





algorithm=function ( name ) 
local found = lookup ( name )
if found == nil then
error ( "unknown MAC algorithm " .. name , 2 )
end

return found
end ;__nuppExports["algorithm"]=algorithm






newMac=function ( name , key ) 
return algorithm ( name ) : newMac ( key )
end ;__nuppExports["newMac"]=newMac



algorithms=function ( ) 
local result = { }
for index , name in ipairs ( names ) do
result [ index ] = name
end

return result
end ;__nuppExports["algorithms"]=algorithms







digest=function ( name , key , bytes ) 
do local __nuppT21=0; local  __nuppT27 ; local __nuppT28=false ; local __nuppT22,__nuppT23,__nuppT24=__nuppT14(function() do local __nuppT29= newMac ( name , key ) ; __nuppT27= __nuppT29 ; __nuppT21=1;  __nuppT28=true;  local mac=__nuppT27;
mac : write ( bytes )
return "return",__nuppT9( (function(__nuppT30,...)  __nuppT28=false; return __nuppT30:__nupp_m_9166925de18d3bf1bbca4cbc246e4c6e931afb529073d9863b1609ada6c40511(...)  end)( mac ) ) end; return "normal" end,__nuppT10); local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 and __nuppT28 then  local __nuppT31,__nuppT32=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT31 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT32 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end ;__nuppExports["digest"]=digest







hexDigest=function ( name , key , bytes ) 
do local __nuppT34=0; local  __nuppT40 ; local __nuppT41=false ; local __nuppT35,__nuppT36,__nuppT37=__nuppT14(function() do local __nuppT42= newMac ( name , key ) ; __nuppT40= __nuppT42 ; __nuppT34=1;  __nuppT41=true;  local mac=__nuppT40;
mac : write ( bytes )
return "return",__nuppT9( (function(__nuppT43,...)  __nuppT41=false; return __nuppT43:hexDigest(...)  end)( mac ) ) end; return "normal" end,__nuppT10); local __nuppT38={}; local __nuppT39=0; if __nuppT34>=1 and __nuppT41 then  local __nuppT44,__nuppT45=__nuppT13(__nuppCleanup1,__nuppT40);  if not __nuppT44 then __nuppT39=__nuppT39+1; __nuppT38[__nuppT39]=__nuppT45 end; end; if not __nuppT35 then if __nuppT39>0 then __nuppT15(__nuppT11(__nuppT36,__nuppT38,1),0) else __nuppT15(__nuppT36,0) end end; if __nuppT39>0 then if __nuppT39>1 then __nuppT15(__nuppT11(__nuppT38[1],__nuppT38,2),0) else __nuppT15(__nuppT38[1],0) end end; if __nuppT36=="return" then  return __nuppT16(__nuppT37,1,__nuppT37.n)  end; end
end ;__nuppExports["hexDigest"]=hexDigest
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Algorithm]="nupp.mac\0Algorithm"; end);if not __nuppOk then package.loaded["nupp.mac"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mac"]=__nuppExports;return __nuppExports