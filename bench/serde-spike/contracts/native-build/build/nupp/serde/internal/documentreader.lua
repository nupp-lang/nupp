_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT23={}; local function __nuppT20(...) return {n=select("#",...),...} end; local __nuppT24,__nuppT25,__nuppT26,__nuppT27,__nuppT28,__nuppT29,__nuppT30,__nuppT31=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT21(value) return value end; local function __nuppT22(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT29({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT30(v.primary) for _,reason in __nuppT31(v.suppressed) do text=text.."\ncleanup: "..__nuppT30(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.internal.documentreader"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local reader;__nuppExports["reader"]=function(...) return reader(...) end;local snapshot;__nuppExports["snapshot"]=function(...) return snapshot(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.documentreader\0runtime\0001") };

local core = require ( "nupp.serde.internal.value" )
local publication = require ( "nupp.serde.internal.publication" )
local documents = require ( "nupp.serde.internal.document" )

local Reader = {} Reader.__index = Reader






function Reader:close() 
self . expired = true
end



function Reader:finish() 
assert ( not self . expired and self . used , "document adapter did not consume its value" )
end




function Reader:live() 
assert ( not self . expired , "document reader scope has expired" )
assert ( not self . used , "document value has already been consumed" )
end




function Reader:context() 
self : live ( )
return self . source
end



function Reader:kind() 
self : live ( )
return self . value . kind
end





function Reader:consume(kind) 
self : live ( )
assert ( self . value . kind == kind , "document kind mismatch" )
self . used = true
end




function Reader:readNull() 
self : consume ( "null" )
end




function Reader:readBoolean() 
self : consume ( "boolean" )
return self . value : boolean ( )
end




function Reader:readNumberToken() 
self : consume ( "numberToken" )
return self . value : numberToken ( )
end




function Reader:readString() 
self : consume ( "string" )
return self . value : string ( )
end




function Reader:readBytes() 
self : consume ( "bytes" )
return self . value : bytes ( )
end




function Reader:readTimestamp() 
self : consume ( "timestamp" )
return self . value : timestamp ( )
end




function Reader:readInteger() 
self : consume ( "integer" )
return self . value : integer ( )
end




function Reader:readDecimal() 
self : consume ( "decimal" )
return self . value : decimal ( )
end




function Reader:readFloat() 
self : consume ( "float" )
return self . value : float ( )
end




function Reader:readBigInteger() 
self : consume ( "bigInteger" )
return self . value : bigInteger ( )
end




function Reader:readAtom() 
self : consume ( "atom" )
return self . value : atom ( )
end







function Reader:readDocument(adapter) local __nuppT19;
self : consume ( "document" )
local value = self . value : document ( )
do const  __nuppT38= _G.setmetatable({ value =  value ,  source =  value : context ( ) or self . source ,  used =  false ,  expired =  false }, Reader) ; __nuppT19=__nuppT19 or {} ; local __nuppT39=__nuppT19[1]; if not __nuppT39 then __nuppT39=function(child) do
local result = adapter : readContents ( child )
if not child . used then
error ( publication . failure ( adapter , result , "document adapter did not consume its contents" ) , 0 )
end

return "return",__nuppT20( result ) end; return "normal" end; __nuppT19[1]=__nuppT39 end; const __nuppT33,__nuppT34,__nuppT35=__nuppT25(__nuppT39,__nuppT21,__nuppT38); const __nuppT32=1; local __nuppT36={}; local __nuppT37=0; if __nuppT32>=1 then  local __nuppT40,__nuppT41=__nuppT24(__nuppCleanup1,__nuppT38);  if not __nuppT40 then __nuppT37=__nuppT37+1; __nuppT36[__nuppT37]=__nuppT41 end; end; if not __nuppT33 then if __nuppT37>0 then __nuppT26(__nuppT22(__nuppT34,__nuppT36,1),0) else __nuppT26(__nuppT34,0) end end; if __nuppT37>0 then if __nuppT37>1 then __nuppT26(__nuppT22(__nuppT36[1],__nuppT36,2),0) else __nuppT26(__nuppT36[1],0) end end; if __nuppT34=="return" then  return __nuppT27(__nuppT35,1,__nuppT35.n)  end; end
end










function Reader:elements(kind, state, consumer) 
self : consume ( kind )
for index = 1 , self . value : size ( ) do
local value = self . value : at ( index )
do local __nuppT43=0; local  __nuppT49 ; local __nuppT44,__nuppT45,__nuppT46=__nuppT25(function() do local __nuppT50= _G.setmetatable({ value =
value ,  source =
value : context ( ) or self . source ,  used =
false ,  expired =
false }, Reader) ; __nuppT49= __nuppT50 ; __nuppT43=1;  local child=__nuppT49;

consumer : apply ( state , index , child )
assert ( child . used , "document callback did not consume its value" ) end; return "normal" end,__nuppT21); local __nuppT47={}; local __nuppT48=0; if __nuppT43>=1 then  local __nuppT51,__nuppT52=__nuppT24(__nuppCleanup1,__nuppT49);  if not __nuppT51 then __nuppT48=__nuppT48+1; __nuppT47[__nuppT48]=__nuppT52 end; end; if not __nuppT44 then if __nuppT48>0 then __nuppT26(__nuppT22(__nuppT45,__nuppT47,1),0) else __nuppT26(__nuppT45,0) end end; if __nuppT48>0 then if __nuppT48>1 then __nuppT26(__nuppT22(__nuppT47[1],__nuppT47,2),0) else __nuppT26(__nuppT47[1],0) end end; if __nuppT45=="return" then  return __nuppT27(__nuppT46,1,__nuppT46.n)  end; end
end
end







function Reader:readList(state, consumer) 
self : elements ( "list" , state , consumer )
end







function Reader:readTuple(state, consumer) 
self : elements ( "tuple" , state , consumer )
end










function Reader:members(kind, state, consumer) 
self : consume ( kind )
for index = 1 , self . value : size ( ) do
local field = self . value : field ( index )
local value = field . value
do local __nuppT56=0; local  __nuppT62 ; local __nuppT57,__nuppT58,__nuppT59=__nuppT25(function() do local __nuppT63= _G.setmetatable({ value =
value ,  source =
value : context ( ) or self . source ,  used =
false ,  expired =
false }, Reader) ; __nuppT62= __nuppT63 ; __nuppT56=1;  local child=__nuppT62;

consumer : apply ( state , field . name , child )
assert ( child . used , "document callback did not consume its value" ) end; return "normal" end,__nuppT21); local __nuppT60={}; local __nuppT61=0; if __nuppT56>=1 then  local __nuppT64,__nuppT65=__nuppT24(__nuppCleanup1,__nuppT62);  if not __nuppT64 then __nuppT61=__nuppT61+1; __nuppT60[__nuppT61]=__nuppT65 end; end; if not __nuppT57 then if __nuppT61>0 then __nuppT26(__nuppT22(__nuppT58,__nuppT60,1),0) else __nuppT26(__nuppT58,0) end end; if __nuppT61>0 then if __nuppT61>1 then __nuppT26(__nuppT22(__nuppT60[1],__nuppT60,2),0) else __nuppT26(__nuppT60[1],0) end end; if __nuppT58=="return" then  return __nuppT27(__nuppT59,1,__nuppT59.n)  end; end
end
end







function Reader:readStruct(state, consumer) 
self : members ( "structure" , state , consumer )
end







function Reader:readUnion(state, consumer) 
self : members ( "union" , state , consumer )
end









function Reader:readMap(state, consumer) 
self : consume ( "map" )
for index = 1 , self . value : size ( ) do
local entry = self . value : entry ( index )
do local __nuppT69=0; local  __nuppT75,__nuppT76 ; local __nuppT70,__nuppT71,__nuppT72=__nuppT25(function() do local __nuppT77= _G.setmetatable({ value =
entry . key ,  source =
entry . key : context ( ) or self . source ,  used =
false ,  expired =
false }, Reader) ; __nuppT75= __nuppT77 ; __nuppT69=1;  local key=__nuppT75;

local __nuppT78= _G.setmetatable({ value =
entry . value ,  source =
entry . value : context ( ) or self . source ,  used =
false ,  expired =
false }, Reader) ; __nuppT76= __nuppT78 ; __nuppT69=2;  local value=__nuppT76;

consumer : apply ( state , key , value )
assert ( key . used and value . used , "document callback must consume both key and value" ) end; return "normal" end,__nuppT21); local __nuppT73={}; local __nuppT74=0; if __nuppT69>=2 then  local __nuppT79,__nuppT80=__nuppT24(__nuppCleanup1,__nuppT76);  if not __nuppT79 then __nuppT74=__nuppT74+1; __nuppT73[__nuppT74]=__nuppT80 end; end; if __nuppT69>=1 then  local __nuppT81,__nuppT82=__nuppT24(__nuppCleanup1,__nuppT75);  if not __nuppT81 then __nuppT74=__nuppT74+1; __nuppT73[__nuppT74]=__nuppT82 end; end; if not __nuppT70 then if __nuppT74>0 then __nuppT26(__nuppT22(__nuppT71,__nuppT73,1),0) else __nuppT26(__nuppT71,0) end end; if __nuppT74>0 then if __nuppT74>1 then __nuppT26(__nuppT22(__nuppT73[1],__nuppT73,2),0) else __nuppT26(__nuppT73[1],0) end end; if __nuppT71=="return" then  return __nuppT27(__nuppT72,1,__nuppT72.n)  end; end
end
end ;_G.nupp.__reflect.link(Reader,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") , _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") }) ;__nuppExports["Reader"]=Reader


reader=function ( value ) 
return ( _G.setmetatable({ value =  value ,  source =  value : context ( ) ,  used =  false ,  expired =  false }, Reader) )
end ;__nuppExports["reader"]=reader

snapshot=function ( value ) 
do const  __nuppT91= reader ( value ) ; local __nuppT92=__nuppT23[2]; if not __nuppT92 then __nuppT92=function(input) do
local result = documents . documentAdapter ( ) : readContents ( input )
input : finish ( )
return "return",__nuppT20( result ) end; return "normal" end; __nuppT23[2]=__nuppT92 end; const __nuppT86,__nuppT87,__nuppT88=__nuppT25(__nuppT92,__nuppT21,__nuppT91); const __nuppT85=1; local __nuppT89={}; local __nuppT90=0; if __nuppT85>=1 then  local __nuppT93,__nuppT94=__nuppT24(__nuppCleanup1,__nuppT91);  if not __nuppT93 then __nuppT90=__nuppT90+1; __nuppT89[__nuppT90]=__nuppT94 end; end; if not __nuppT86 then if __nuppT90>0 then __nuppT26(__nuppT22(__nuppT87,__nuppT89,1),0) else __nuppT26(__nuppT87,0) end end; if __nuppT90>0 then if __nuppT90>1 then __nuppT26(__nuppT22(__nuppT89[1],__nuppT89,2),0) else __nuppT26(__nuppT89[1],0) end end; if __nuppT87=="return" then  return __nuppT27(__nuppT88,1,__nuppT88.n)  end; end
end ;__nuppExports["snapshot"]=snapshot
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Reader]="nupp.serde.internal.documentreader\0Reader"; end);if not __nuppOk then package.loaded["nupp.serde.internal.documentreader"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.documentreader"]=__nuppExports;return __nuppExports