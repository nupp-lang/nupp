_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppT39 = function(__nuppV) return __nuppV:close() end;local __nuppDrop2 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppExports={};package.loaded["nupp.digest.internal.context"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local wrap;__nuppExports["wrap"]=function(...) return wrap(...) end;













const span = require ( "nupp.mem.span" )
const storage = require ( "nupp.runtime.storage" )
const hex = require ( "nupp.codec.hex" )
const provider = require ( "nupp.digest.spi" )


local Digest = {}





























local StateOwner = {} StateOwner.__index = StateOwner

function StateOwner:close() 
self . state : close ( )
end


local Context = {} Context.__index = Context




function Context:close() 
self . state : close ( )
end

function Context:algorithm() 
return self . name
end

function Context:digestSize() 
return self . size
end

function Context:write(bytes) 
if type ( bytes ) ~= "string" then
error ( "nupp: Digest:write bytes must be a string" , 2 )
end
local view = span . fromString ( bytes )
self . state : update ( view )

return true , nil
end

function Context:writeSpan(bytes) 
self . state : update ( bytes )

return bytes .count , nil
end

function Context:flush() 
return true , nil
end

function Context:__nupp_m_9c0cecb5a21234b04dd6039de28da32db7f3a6fafaf6f7b69708f5d590238cf0(destination) local __nuppT8;


local size = self . size
do const  __nuppT27= _G.setmetatable({ state =  self . state }, StateOwner) ; __nuppT8=__nuppT8 or {} ; local __nuppT28=__nuppT8[1]; if not __nuppT28 then __nuppT28=function(owner) do
if destination .count < size then
error ( "digest destination needs " .. size .. " bytes" , 2 )
end
do const  __nuppT35= destination : slice ( 1 , size ) ; __nuppT8=__nuppT8 or {} ; local __nuppT36=__nuppT8[2]; if not __nuppT36 then __nuppT36=function(exact) do
owner . state : finish ( exact )
return "return",__nuppT9( size ) end; return "normal" end; __nuppT8[2]=__nuppT36 end; const __nuppT30,__nuppT31,__nuppT32=__nuppT14(__nuppT36,__nuppT10,__nuppT35); const __nuppT29=1; local __nuppT33={}; local __nuppT34=0; if __nuppT29>=1 then  local __nuppT37,__nuppT38=__nuppT13(__nuppCleanup1,__nuppT35);  if not __nuppT37 then __nuppT34=__nuppT34+1; __nuppT33[__nuppT34]=__nuppT38 end; end; if not __nuppT30 then if __nuppT34>0 then __nuppT15(__nuppT11(__nuppT31,__nuppT33,1),0) else __nuppT15(__nuppT31,0) end end; if __nuppT34>0 then if __nuppT34>1 then __nuppT15(__nuppT11(__nuppT33[1],__nuppT33,2),0) else __nuppT15(__nuppT33[1],0) end end; if __nuppT31=="return" then  return "return",__nuppT32  end; end end; return "normal" end; __nuppT8[1]=__nuppT28 end; const __nuppT22,__nuppT23,__nuppT24=__nuppT14(__nuppT28,__nuppT10,__nuppT27); const __nuppT21=1;
local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 then  local __nuppT40,__nuppT41=__nuppT13(__nuppT39,__nuppT27);  if not __nuppT40 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT41 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end

function Context:__nupp_m_9166925de18d3bf1bbca4cbc246e4c6e931afb529073d9863b1609ada6c40511() local __nuppT42;
local size = self . size
do const  __nuppT49= _G.setmetatable({ state =  self . state }, StateOwner) ; __nuppT42=__nuppT42 or {} ; local __nuppT50=__nuppT42[3]; if not __nuppT50 then __nuppT50=function(owner) do
local bytes = storage . allocateBytes ( size )
do local __nuppT51=0; local  __nuppT57 ; local __nuppT58=false ; local __nuppT52,__nuppT53,__nuppT54=__nuppT14(function() do local __nuppT59= span . writeCarray ( bytes , size ) ; __nuppT57= __nuppT59 ; __nuppT51=1;  __nuppT58=true;  local output=__nuppT57;
owner . state : finish ( output )
do __nuppT58=false; __nuppDrop2( output ) end
return "return",__nuppT9( storage . string ( bytes , size ) ) end; return "normal" end,__nuppT10); local __nuppT55={}; local __nuppT56=0; if __nuppT51>=1 and __nuppT58 then  local __nuppT60,__nuppT61=__nuppT13(__nuppCleanup1,__nuppT57);  if not __nuppT60 then __nuppT56=__nuppT56+1; __nuppT55[__nuppT56]=__nuppT61 end; end; if not __nuppT52 then if __nuppT56>0 then __nuppT15(__nuppT11(__nuppT53,__nuppT55,1),0) else __nuppT15(__nuppT53,0) end end; if __nuppT56>0 then if __nuppT56>1 then __nuppT15(__nuppT11(__nuppT55[1],__nuppT55,2),0) else __nuppT15(__nuppT55[1],0) end end; if __nuppT53=="return" then  return "return",__nuppT54  end; end end; return "normal" end; __nuppT42[3]=__nuppT50 end; const __nuppT44,__nuppT45,__nuppT46=__nuppT14(__nuppT50,__nuppT10,__nuppT49); const __nuppT43=1;
local __nuppT47={}; local __nuppT48=0; if __nuppT43>=1 then  local __nuppT62,__nuppT63=__nuppT13(__nuppT39,__nuppT49);  if not __nuppT62 then __nuppT48=__nuppT48+1; __nuppT47[__nuppT48]=__nuppT63 end; end; if not __nuppT44 then if __nuppT48>0 then __nuppT15(__nuppT11(__nuppT45,__nuppT47,1),0) else __nuppT15(__nuppT45,0) end end; if __nuppT48>0 then if __nuppT48>1 then __nuppT15(__nuppT11(__nuppT47[1],__nuppT47,2),0) else __nuppT15(__nuppT47[1],0) end end; if __nuppT45=="return" then  return __nuppT16(__nuppT46,1,__nuppT46.n)  end; end
end

function Context:hexDigest() local __nuppT64;
local size = self . size
do const  __nuppT71= _G.setmetatable({ state =  self . state }, StateOwner) ; __nuppT64=__nuppT64 or {} ; local __nuppT72=__nuppT64[4]; if not __nuppT72 then __nuppT72=function(owner) do
local bytes = storage . allocateBytes ( size )
do local __nuppT73=0; local  __nuppT79 ; local __nuppT80=false ; local __nuppT74,__nuppT75,__nuppT76=__nuppT14(function() do local __nuppT81= span . writeCarray ( bytes , size ) ; __nuppT79= __nuppT81 ; __nuppT73=1;  __nuppT80=true;  local output=__nuppT79;
owner . state : finish ( output )
do __nuppT80=false; __nuppDrop2( output ) end
return "return",__nuppT9( hex . encode ( storage . string ( bytes , size ) ) ) end; return "normal" end,__nuppT10); local __nuppT77={}; local __nuppT78=0; if __nuppT73>=1 and __nuppT80 then  local __nuppT82,__nuppT83=__nuppT13(__nuppCleanup1,__nuppT79);  if not __nuppT82 then __nuppT78=__nuppT78+1; __nuppT77[__nuppT78]=__nuppT83 end; end; if not __nuppT74 then if __nuppT78>0 then __nuppT15(__nuppT11(__nuppT75,__nuppT77,1),0) else __nuppT15(__nuppT75,0) end end; if __nuppT78>0 then if __nuppT78>1 then __nuppT15(__nuppT11(__nuppT77[1],__nuppT77,2),0) else __nuppT15(__nuppT77[1],0) end end; if __nuppT75=="return" then  return "return",__nuppT76  end; end end; return "normal" end; __nuppT64[4]=__nuppT72 end; const __nuppT66,__nuppT67,__nuppT68=__nuppT14(__nuppT72,__nuppT10,__nuppT71); const __nuppT65=1;
local __nuppT69={}; local __nuppT70=0; if __nuppT65>=1 then  local __nuppT84,__nuppT85=__nuppT13(__nuppT39,__nuppT71);  if not __nuppT84 then __nuppT70=__nuppT70+1; __nuppT69[__nuppT70]=__nuppT85 end; end; if not __nuppT66 then if __nuppT70>0 then __nuppT15(__nuppT11(__nuppT67,__nuppT69,1),0) else __nuppT15(__nuppT67,0) end end; if __nuppT70>0 then if __nuppT70>1 then __nuppT15(__nuppT11(__nuppT69[1],__nuppT69,2),0) else __nuppT15(__nuppT69[1],0) end end; if __nuppT67=="return" then  return __nuppT16(__nuppT68,1,__nuppT68.n)  end; end
end



wrap=function ( state , name , size ) 
return ( _G.setmetatable({ state =  state ,  name =  name ,  size =  size }, Context) )
end ;__nuppExports["wrap"]=wrap
 end);if not __nuppOk then package.loaded["nupp.digest.internal.context"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.digest.internal.context"]=__nuppExports;return __nuppExports