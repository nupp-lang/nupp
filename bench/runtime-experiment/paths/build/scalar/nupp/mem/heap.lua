_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT6={}; local function __nuppT3(...) return {n=select("#",...),...} end; local __nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT4(value) return value end; local function __nuppT5(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT12({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT13(v.primary) for _,reason in __nuppT14(v.suppressed) do text=text.."\ncleanup: "..__nuppT13(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.heap#free_nosuspend"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.heap#free_nosuspend") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.mem.heap#destroyArray"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.heap#destroyArray") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.mem.heap\0runtime\0001") };




































local heap = { }
local ffi = require ( "ffi" )
local span = require ( "nupp.mem.span" )

_G.pcall(__nuppFfi.cdef, "void * malloc(uint64_t);") const malloc = __nuppFfi.C.malloc
_G.pcall(__nuppFfi.cdef, "void free(void *);") const free = __nuppFfi.C.free
local free_nosuspend = free

local function finish_array ( self ) 
do
local raw = self
do local __nuppT15=0; local  __nuppT21 ; local __nuppT22=false ; local __nuppT16,__nuppT17,__nuppT18=__nuppT8(function() do local __nuppT23= raw . pointer ; __nuppT21= __nuppT23 ; __nuppT15=1;  __nuppT22=true;  local pointer=__nuppT21;


raw . pointer = nil
do (function(__nuppT24,...)  __nuppT22=false; return __nuppT24(...)  end)( free_nosuspend , pointer ) end end; return "normal" end,__nuppT4); local __nuppT19={}; local __nuppT20=0; if __nuppT15>=1 and __nuppT22 then  local __nuppT25,__nuppT26=__nuppT7(__nuppCleanup1,__nuppT21);  if not __nuppT25 then __nuppT20=__nuppT20+1; __nuppT19[__nuppT20]=__nuppT26 end; end; if not __nuppT16 then if __nuppT20>0 then __nuppT9(__nuppT5(__nuppT17,__nuppT19,1),0) else __nuppT9(__nuppT17,0) end end; if __nuppT20>0 then if __nuppT20>1 then __nuppT9(__nuppT5(__nuppT19[1],__nuppT19,2),0) else __nuppT9(__nuppT19[1],0) end end; if __nuppT17=="return" then  return __nuppT10(__nuppT18,1,__nuppT18.n)  end; end
end
end

local finish_array_nosuspend = finish_array












function heap . destroyArray ( self ) 
self : close ( )
end __nuppCleanups["nupp.mem.heap#destroyArray"]= heap.destroyArray;




heap.Array = {} heap.Array.__index = heap.Array ;_G.nupp.__reflect.link(heap.Array,__nuppT1[1],{ })





















function heap . Array . read ( self ) 
return span . fromCarray ( self . pointer , self . count )
end

function heap . Array . close ( self ) 
finish_array_nosuspend ( self )
end

function heap . Array . write ( self ) 
return span . writeCarray ( self . pointer , self . count )
end





















function heap . allocate ( element , count ) __nuppCleanups["nupp.mem.heap#destroyArray"]=heap.destroyArray; 
if count < 0 or count ~= math . floor ( count ) then
error ( "nupp: heap array count must be a nonnegative integer" , 2 )
end

local width = ffi . sizeof ( element )
if width <= 0 or ( count > 0 and count > _G.math.floor(( 9007199254740991 ) / ( width )) ) then
error ( "nupp: heap array byte size is too large" , 2 )
end

local bytes = width * count
if bytes == 0 then
bytes = 1
end
local raw = malloc ( bytes )
if raw == nil then
error ( "nupp: heap array allocation failed" , 2 )
end




local pointerType = ffi . typeof ( "$ *" , element )
do
local pointer = ffi . cast ( pointerType , raw )
local array = _G.setmetatable({ pointer =  pointer ,  count =  count }, heap.Array)
return array
end
end







local MOVABLE_ELEMENTS

= { "uint8_t" , "int8_t" , "uint16_t" , "int16_t" , "uint32_t" , "int32_t" , "uint64_t" , "int64_t" , "float" , "double" , }
local tagByPointerType = { }
local pointerTypeByTag = { }
for tag , element in ipairs ( MOVABLE_ELEMENTS ) do
local pointerType = ffi . typeof ( element .. " *" )
tagByPointerType [ tostring ( pointerType ) ] = tag
pointerTypeByTag [ tag ] = pointerType
end

local pointerBox = ffi . new ( "void *[1]" )
local POINTER_SIZE = ffi . sizeof ( "void *" )

local getmetatable_nosuspend = getmetatable
do local __nuppT32=0; local  __nuppT38 ; local __nuppT39=false ; local __nuppT33,__nuppT34,__nuppT35=__nuppT8(function() do local __nuppT40= heap . allocate ( __nuppFfi.typeof("int32_t" ) , 0 ) ; __nuppT38= __nuppT40 ; __nuppT32=1;  __nuppT39=true;  local movedProbe=__nuppT38;
local arrayMetatable = nil
do
local raw = (function() __nuppT39=false; return  movedProbe  end)()
arrayMetatable = getmetatable_nosuspend ( raw )
do local __nuppT41=0; local  __nuppT47 ; local __nuppT48=false ; local __nuppT42,__nuppT43,__nuppT44=__nuppT8(function() do local __nuppT49= raw . pointer ; __nuppT47= __nuppT49 ; __nuppT41=1;  __nuppT48=true;  local pointer=__nuppT47;
do (function(__nuppT50,...)  __nuppT48=false; return __nuppT50(...)  end)( free_nosuspend , pointer ) end end; return "normal" end,__nuppT4); local __nuppT45={}; local __nuppT46=0; if __nuppT41>=1 and __nuppT48 then  local __nuppT51,__nuppT52=__nuppT7(__nuppCleanup1,__nuppT47);  if not __nuppT51 then __nuppT46=__nuppT46+1; __nuppT45[__nuppT46]=__nuppT52 end; end; if not __nuppT42 then if __nuppT46>0 then __nuppT9(__nuppT5(__nuppT43,__nuppT45,1),0) else __nuppT9(__nuppT43,0) end end; if __nuppT46>0 then if __nuppT46>1 then __nuppT9(__nuppT5(__nuppT45[1],__nuppT45,2),0) else __nuppT9(__nuppT45[1],0) end end; if __nuppT43=="return" then  return "return",__nuppT44  end; end
end

local function movableTag ( value ) 
local raw = value
local pointer = raw . pointer
if pointer == nil then
return nil
end

return tagByPointerType [ tostring ( ffi . typeof ( pointer ) ) ]
end

rawset ( _G . nupp , "__heapArrayMetatable" , arrayMetatable )
rawset ( heap , "__heapArrayMovable" , movableTag )



rawset ( heap , "__heapArrayParts" , function ( value ) 
local tag = movableTag ( value )
if tag == nil then
return nil , nil , nil
end
local raw = value
pointerBox [ 0 ] = raw . pointer
local bytes = ffi . string ( pointerBox , POINTER_SIZE )
raw . pointer = nil

return bytes , raw . count , tag
end )

rawset ( heap , "__heapArrayFromParts" , function ( pointer , count , tag ) 
local pointerType = pointerTypeByTag [ tag ]
if pointerType == nil or count % 1 ~= 0 or count < 0 then
return nil
end

return setmetatable ( { pointer = ffi . cast ( pointerType , pointer ) , count = count } , arrayMetatable )
end )




rawset ( heap , "__heapArrayFree" , function ( pointer ) 
local raw = pointer
if type ( pointer ) == "string" then
raw = ( ffi . cast ( "void * const *" , pointer ) ) [ 0 ]
end
do
do local __nuppT57=0; local  __nuppT63 ; local __nuppT64=false ; local __nuppT58,__nuppT59,__nuppT60=__nuppT8(function() do local __nuppT65= ( ffi . cast ( "void *" , raw ) ) ; __nuppT63= __nuppT65 ; __nuppT57=1;  __nuppT64=true;  local owned=__nuppT63;
do (function(__nuppT66,...)  __nuppT64=false; return __nuppT66(...)  end)( free_nosuspend , owned ) end end; return "normal" end,__nuppT4); local __nuppT61={}; local __nuppT62=0; if __nuppT57>=1 and __nuppT64 then  local __nuppT67,__nuppT68=__nuppT7(__nuppCleanup1,__nuppT63);  if not __nuppT67 then __nuppT62=__nuppT62+1; __nuppT61[__nuppT62]=__nuppT68 end; end; if not __nuppT58 then if __nuppT62>0 then __nuppT9(__nuppT5(__nuppT59,__nuppT61,1),0) else __nuppT9(__nuppT59,0) end end; if __nuppT62>0 then if __nuppT62>1 then __nuppT9(__nuppT5(__nuppT61[1],__nuppT61,2),0) else __nuppT9(__nuppT61[1],0) end end; if __nuppT59=="return" then  return __nuppT10(__nuppT60,1,__nuppT60.n)  end; end
end
end )

local __nuppExportValue= heap ;__nuppExports=__nuppExportValue end; return "normal" end,__nuppT4); local __nuppT36={}; local __nuppT37=0; if __nuppT32>=1 and __nuppT39 then  local __nuppT69,__nuppT70=__nuppT7(__nuppCleanup2,__nuppT38);  if not __nuppT69 then __nuppT37=__nuppT37+1; __nuppT36[__nuppT37]=__nuppT70 end; end; if not __nuppT33 then if __nuppT37>0 then __nuppT9(__nuppT5(__nuppT34,__nuppT36,1),0) else __nuppT9(__nuppT34,0) end end; if __nuppT37>0 then if __nuppT37>1 then __nuppT9(__nuppT5(__nuppT36[1],__nuppT36,2),0) else __nuppT9(__nuppT36[1],0) end end; if __nuppT34=="return" then  return __nuppT10(__nuppT35,1,__nuppT35.n)  end; end
 end);if not __nuppOk then package.loaded["nupp.mem.heap"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mem.heap"]=__nuppExports;return __nuppExports