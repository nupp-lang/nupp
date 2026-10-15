_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT6={}; local function __nuppT3(...) return {n=select("#",...),...} end; local __nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT4(value) return value end; local function __nuppT5(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT12({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT13(v.primary) for _,reason in __nuppT14(v.suppressed) do text=text.."\ncleanup: "..__nuppT13(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()local algorithm;__nuppExports["algorithm"]=function(...) return algorithm(...) end;local algorithms;__nuppExports["algorithms"]=function(...) return algorithms(...) end;local digest;__nuppExports["digest"]=function(...) return digest(...) end;local hexDigest;__nuppExports["hexDigest"]=function(...) return hexDigest(...) end;local lookup;__nuppExports["lookup"]=function(...) return lookup(...) end;local newDigest;__nuppExports["newDigest"]=function(...) return newDigest(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.digest\0runtime\0001") };







































local spi = require ( "nupp.spi" )

const provider = require ( "nupp.digest.spi" )

const contexts = require ( "nupp.digest.internal.context" )





local Algorithm = {} Algorithm.__index = Algorithm











function Algorithm:newDigest() 
do local __nuppT15=0; local  __nuppT21 ; local __nuppT22=false ; local __nuppT16,__nuppT17,__nuppT18=__nuppT8(function() do local __nuppT23= self . implementation : create ( ) ; __nuppT21= __nuppT23 ; __nuppT15=1;  __nuppT22=true;  local state=__nuppT21;
return "return",__nuppT3( (function(__nuppT24,...)  __nuppT22=false; return __nuppT24(...)  end)( contexts . wrap , state , self . name , self . digestSize ) ) end; return "normal" end,__nuppT4); local __nuppT19={}; local __nuppT20=0; if __nuppT15>=1 and __nuppT22 then  local __nuppT25,__nuppT26=__nuppT7(__nuppCleanup1,__nuppT21);  if not __nuppT25 then __nuppT20=__nuppT20+1; __nuppT19[__nuppT20]=__nuppT26 end; end; if not __nuppT16 then if __nuppT20>0 then __nuppT9(__nuppT5(__nuppT17,__nuppT19,1),0) else __nuppT9(__nuppT17,0) end end; if __nuppT20>0 then if __nuppT20>1 then __nuppT9(__nuppT5(__nuppT19[1],__nuppT19,2),0) else __nuppT9(__nuppT19[1],0) end end; if __nuppT17=="return" then  return __nuppT10(__nuppT18,1,__nuppT18.n)  end; end
end ;_G.nupp.__reflect.link(Algorithm,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../../src/nupp/digest/spi.nupp\0Algorithm\0interface\0module\0001","nupp.digest.spi") }) ;__nuppExports["Algorithm"]=Algorithm


local standard = require ( "nupp.runtime.provider.digest" )

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
error ( "invalid digest algorithm descriptor " .. tostring ( name ) , 2 )
end
local expected = standard . algorithms [ name ]
if expected ~= nil and implementation . digestSize ~= expected . digestSize then
error ( "digest provider has the wrong digestSize for " .. name , 2 )
end
end
end

local selected = spi . select ( spi . load ("nupp.digest.spi.Provider") ) ?? standard
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
error ( "unknown digest algorithm " .. name , 2 )
end

return found
end ;__nuppExports["algorithm"]=algorithm





newDigest=function ( name ) 
return algorithm ( name ) : newDigest ( )
end ;__nuppExports["newDigest"]=newDigest



algorithms=function ( ) 
local result = { }
for index , name in ipairs ( names ) do
result [ index ] = name
end

return result
end ;__nuppExports["algorithms"]=algorithms






digest=function ( name , bytes ) 
do local __nuppT33=0; local  __nuppT39 ; local __nuppT40=false ; local __nuppT34,__nuppT35,__nuppT36=__nuppT8(function() do local __nuppT41= newDigest ( name ) ; __nuppT39= __nuppT41 ; __nuppT33=1;  __nuppT40=true;  local context=__nuppT39;
context : write ( bytes )
return "return",__nuppT3( (function(__nuppT42,...)  __nuppT40=false; return __nuppT42:__nupp_m_9166925de18d3bf1bbca4cbc246e4c6e931afb529073d9863b1609ada6c40511(...)  end)( context ) ) end; return "normal" end,__nuppT4); local __nuppT37={}; local __nuppT38=0; if __nuppT33>=1 and __nuppT40 then  local __nuppT43,__nuppT44=__nuppT7(__nuppCleanup1,__nuppT39);  if not __nuppT43 then __nuppT38=__nuppT38+1; __nuppT37[__nuppT38]=__nuppT44 end; end; if not __nuppT34 then if __nuppT38>0 then __nuppT9(__nuppT5(__nuppT35,__nuppT37,1),0) else __nuppT9(__nuppT35,0) end end; if __nuppT38>0 then if __nuppT38>1 then __nuppT9(__nuppT5(__nuppT37[1],__nuppT37,2),0) else __nuppT9(__nuppT37[1],0) end end; if __nuppT35=="return" then  return __nuppT10(__nuppT36,1,__nuppT36.n)  end; end
end ;__nuppExports["digest"]=digest






hexDigest=function ( name , bytes ) 
do local __nuppT46=0; local  __nuppT52 ; local __nuppT53=false ; local __nuppT47,__nuppT48,__nuppT49=__nuppT8(function() do local __nuppT54= newDigest ( name ) ; __nuppT52= __nuppT54 ; __nuppT46=1;  __nuppT53=true;  local context=__nuppT52;
context : write ( bytes )
return "return",__nuppT3( (function(__nuppT55,...)  __nuppT53=false; return __nuppT55:hexDigest(...)  end)( context ) ) end; return "normal" end,__nuppT4); local __nuppT50={}; local __nuppT51=0; if __nuppT46>=1 and __nuppT53 then  local __nuppT56,__nuppT57=__nuppT7(__nuppCleanup1,__nuppT52);  if not __nuppT56 then __nuppT51=__nuppT51+1; __nuppT50[__nuppT51]=__nuppT57 end; end; if not __nuppT47 then if __nuppT51>0 then __nuppT9(__nuppT5(__nuppT48,__nuppT50,1),0) else __nuppT9(__nuppT48,0) end end; if __nuppT51>0 then if __nuppT51>1 then __nuppT9(__nuppT5(__nuppT50[1],__nuppT50,2),0) else __nuppT9(__nuppT50[1],0) end end; if __nuppT48=="return" then  return __nuppT10(__nuppT49,1,__nuppT49.n)  end; end
end ;__nuppExports["hexDigest"]=hexDigest
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Algorithm]="nupp.digest\0Algorithm"; end);if not __nuppOk then package.loaded["nupp.digest"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.digest"]=__nuppExports;return __nuppExports