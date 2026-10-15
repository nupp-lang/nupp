_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT7={}; local function __nuppT4(...) return {n=select("#",...),...} end; local __nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT5(value) return value end; local function __nuppT6(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT13({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT14(v.primary) for _,reason in __nuppT15(v.suppressed) do text=text.."\ncleanup: "..__nuppT14(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppExports={};package.loaded["nupp.io.internal.ownedreader"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local newOwnedReader;__nuppExports["newOwnedReader"]=function(...) return newOwnedReader(...) end;


local bytes = require ( "nupp.io.internal.bytes" )
local span = require ( "nupp.mem.span" )
local physical = require ( "nupp.runtime.storage" )



local positive = bytes . validatePositive
local integer_ = bytes . validateInteger
local DEFAULT_READ = 65536



local MemoryReader = {} MemoryReader.__index = MemoryReader





function MemoryReader:read(count) 
if self . _closed then
return nil , "the reader is closed"
end
local wanted = positive ( count , "Reader:read count" , 2 )
local taking = math . min ( wanted , self . _length - self . _at )
local bytes
do
local root = self . _data
bytes = physical . string ( ( root ) + self . _at , taking )
end
self . _at = self . _at + taking

return bytes , nil
end

function MemoryReader:readSpan(destination) 
if self . _closed then
return nil , "the reader is closed"
end
local wanted
do
local output = destination
wanted = positive ( output .count , "Reader:readSpan destination length" , 2 )
end
local taking = math . min ( wanted , self . _length - self . _at )
local pointer = destination : ref ( )
do
local root = self . _data
physical . copy ( pointer , ( root ) + self . _at , taking )
end
self . _at = self . _at + taking

return taking , nil
end

function MemoryReader:readInto(destination, offset, count) 





if self . _closed then
return nil , "the reader is closed"
end
local from = integer_ ( offset or 0 , "Reader:readInto offset" , 2 )
local wanted = positive ( count or DEFAULT_READ , "Reader:readInto count" , 2 )
local taking = math . min ( wanted , self . _length - self . _at )
if taking == 0 then
return 0 , nil
end
do local __nuppT16=0; local  __nuppT22 ; local __nuppT23=false ; local __nuppT17,__nuppT18,__nuppT19=__nuppT9(function() do local __nuppT24= destination : reserveWrite ( from , wanted ) ; __nuppT22= __nuppT24 ; __nuppT16=1;  __nuppT23=true;  local lease=__nuppT22;
do
do local __nuppT25=0; local  __nuppT31 ; local __nuppT32=false ; local __nuppT26,__nuppT27,__nuppT28=__nuppT9(function() do local __nuppT33= lease : span ( ) ; __nuppT31= __nuppT33 ; __nuppT25=1;  __nuppT32=true;  local output=__nuppT31;
local _read , _reason = self : readSpan ( output )
do __nuppT32=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT5); local __nuppT29={}; local __nuppT30=0; if __nuppT25>=1 and __nuppT32 then  local __nuppT34,__nuppT35=__nuppT8(__nuppCleanup1,__nuppT31);  if not __nuppT34 then __nuppT30=__nuppT30+1; __nuppT29[__nuppT30]=__nuppT35 end; end; if not __nuppT26 then if __nuppT30>0 then __nuppT10(__nuppT6(__nuppT27,__nuppT29,1),0) else __nuppT10(__nuppT27,0) end end; if __nuppT30>0 then if __nuppT30>1 then __nuppT10(__nuppT6(__nuppT29[1],__nuppT29,2),0) else __nuppT10(__nuppT29[1],0) end end; if __nuppT27=="return" then  return "return",__nuppT28  end; end
end
do (function(__nuppT36,...)  __nuppT23=false; return __nuppT36:commit(...)  end)( lease , taking ) end

return "return",__nuppT4( taking , nil ) end; return "normal" end,__nuppT5); local __nuppT20={}; local __nuppT21=0; if __nuppT16>=1 and __nuppT23 then  local __nuppT37,__nuppT38=__nuppT8(__nuppCleanup2,__nuppT22);  if not __nuppT37 then __nuppT21=__nuppT21+1; __nuppT20[__nuppT21]=__nuppT38 end; end; if not __nuppT17 then if __nuppT21>0 then __nuppT10(__nuppT6(__nuppT18,__nuppT20,1),0) else __nuppT10(__nuppT18,0) end end; if __nuppT21>0 then if __nuppT21>1 then __nuppT10(__nuppT6(__nuppT20[1],__nuppT20,2),0) else __nuppT10(__nuppT20[1],0) end end; if __nuppT18=="return" then  return __nuppT11(__nuppT19,1,__nuppT19.n)  end; end
end

function MemoryReader:transferTo(destination) 
if self . _closed then
return nil , "the reader is closed"
end
local source = span . fromCarray ( self . _data , self . _length )
local total = 0
while self . _at < self . _length do
local rest = source : slice ( self . _at + 1 , self . _length )
local written , reason = destination : writeSpan ( rest )
if written == nil then
return nil , reason
end
if written % 1 ~= 0 or written < 1 or written > rest .count then
return nil , "writer made invalid transfer progress"
end
self . _at = self . _at + written
total = total + written
end

return total , nil
end

function MemoryReader:close() 
local state = self
state . _closed = true
state . _length = 0
( state ) . _data = nil
end


newOwnedReader=function ( buffer ) 
local state = buffer
assert ( not ( state ) . _closed , "nupp: io.Buffer is closed" )
return ( _G.setmetatable({ _data =  ( state ) . _data ,  _length =  ( state ) . _length ,  _at =  0 ,  _closed =  false }, MemoryReader) )
end ;__nuppExports["newOwnedReader"]=newOwnedReader
 end);if not __nuppOk then package.loaded["nupp.io.internal.ownedreader"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.internal.ownedreader"]=__nuppExports;return __nuppExports