_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); const __nuppT4={}; const __nuppT5,__nuppT6,__nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12=pcall,xpcall,error,unpack,select,setmetatable,tostring,ipairs; const function __nuppT1(...) return {n=__nuppT9("#",...),...} end; const function __nuppT2(value) return value end; const function __nuppT3(primary,errors,start) const secondary={} for i=start,#errors do secondary[#secondary+1]=errors[i] end return __nuppT10({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT11(v.primary) for _,reason in __nuppT12(v.suppressed) do text=text.."\ncleanup: "..__nuppT11(reason) end return text end}) end; local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.heap#free_nosuspend"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.heap#free_nosuspend") end;__nuppCleanup1=cleanup;return cleanup(value) end;







local heap = { }
local ffi = require ( "ffi" )
local span = require ( "nupp.span" )

pcall(__nuppFfi.cdef, "void * malloc(uint64_t);") const malloc = __nuppFfi.C.malloc
pcall(__nuppFfi.cdef, "void free(void *);") const free = __nuppFfi.C.free
local free_nosuspend = free

local function finish_array ( self )
do
local raw = self
do local __nuppT13=0; local  __nuppT19 ; local __nuppT20=false ; const __nuppT14,__nuppT15,__nuppT16=__nuppT6(function() do const __nuppT21= raw . pointer ; __nuppT19= __nuppT21 ; __nuppT13=1;  __nuppT20=true;  local pointer=__nuppT19;
do (function(__nuppT22,...)  __nuppT20=false;  return __nuppT22(...)  end)( free_nosuspend , pointer ) end end; return "normal" end,__nuppT2); const __nuppT17={}; local __nuppT18=0; if __nuppT13>=1 and __nuppT20 then  const __nuppT23,__nuppT24=__nuppT5(__nuppCleanup1,__nuppT19);  if not __nuppT23 then __nuppT18=__nuppT18+1; __nuppT17[__nuppT18]=__nuppT24 end; end; if not __nuppT14 then if __nuppT18>0 then __nuppT7(__nuppT3(__nuppT15,__nuppT17,1),0) else __nuppT7(__nuppT15,0) end end; if __nuppT18>0 then if __nuppT18>1 then __nuppT7(__nuppT3(__nuppT17[1],__nuppT17,2),0) else __nuppT7(__nuppT17[1],0) end end; if __nuppT15=="return" then  return __nuppT8(__nuppT16,1,__nuppT16.n)  end; end
end
end

local finish_array_nosuspend = finish_array






function heap . destroyArray ( self )
self : close ( )
end ;__nuppCleanups["nupp.heap#heap.destroyArray"]=heap.destroyArray




heap.Array = {} heap.Array.__index = heap.Array















function heap . Array . read ( self )
return span . fromCarray ( self . pointer , self . count )
end

function heap . Array . close ( self )
finish_array_nosuspend ( self )
end

function heap . Array . drop ( self )
self : close ( )
end

function heap . Array . write ( self )
return span . writeCarray ( self . pointer , self . count )
end






function heap . allocate ( element , count ) __nuppCleanups["nupp.heap#heap.destroyArray"]=heap.destroyArray;
if count < 0 then
error ( "heap array count cannot be negative" , 2 )
end

local width = ffi . sizeof ( element )
if width <= 0 or ( count > 0 and count > math.floor(( 9007199254740991 ) / ( width )) ) then
error ( "heap array byte size is too large" , 2 )
end

local bytes = width * count
if bytes == 0 then
bytes = 1
end
local raw = malloc ( bytes )
if raw == nil then
error ( "heap array allocation failed" , 2 )
end



local pointerSpec = "$ *"
local pointerType = ffi . typeof ( pointerSpec , element )
do
local pointer = ffi . cast ( pointerType , raw )
local array = setmetatable({ pointer =  pointer ,  count =  count }, heap.Array)
return array
end
end

return heap
