_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT24={}; local function __nuppT21(...) return {n=select("#",...),...} end; local __nuppT25,__nuppT26,__nuppT27,__nuppT28,__nuppT29,__nuppT30,__nuppT31,__nuppT32=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT22(value) return value end; local function __nuppT23(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT30({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT31(v.primary) for _,reason in __nuppT32(v.suppressed) do text=text.."\ncleanup: "..__nuppT31(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.soa#free_nosuspend"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.soa#free_nosuspend") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.mem.soa\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.mem.soa\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.mem.soa\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.mem.soa\0runtime\0004") , _G.nupp.__reflect.declaration("nupp.mem.soa\0runtime\0007") };






































local soa = { }
local ffi = require ( "ffi" )
local span = require ( "nupp.mem.span" )

_G.pcall(__nuppFfi.cdef, "void * malloc(uint64_t);") const malloc = __nuppFfi.C.malloc
_G.pcall(__nuppFfi.cdef, "void free(void *);") const free = __nuppFfi.C.free
local free_nosuspend = free

local MAX_EXACT_INTEGER = 9007199254740991



soa.FieldLayout = {} soa.FieldLayout.__index = soa.FieldLayout ;_G.nupp.__reflect.link(soa.FieldLayout,__nuppT1[1],{ })
























soa.SegmentLayout = {} soa.SegmentLayout.__index = soa.SegmentLayout ;_G.nupp.__reflect.link(soa.SegmentLayout,__nuppT1[2],{ __nuppT1[1] })












soa.InstanceLayout = {} soa.InstanceLayout.__index = soa.InstanceLayout ;_G.nupp.__reflect.link(soa.InstanceLayout,__nuppT1[3],{ __nuppT1[2] })












soa.Layout = {} soa.Layout.__index = soa.Layout
















function soa.Layout:forCount(count) 
if count < 0 or count ~= math . floor ( count ) then
error ( "nupp: SoA row count must be a nonnegative integer" , 2 )
end

local segments = { }
local cursor = 0
for ordinal , field in ipairs ( self . fields ) do
if count > 0 and count > _G.math.floor(( MAX_EXACT_INTEGER ) / ( field . elementSize )) then
error ( "nupp: SoA field byte size is too large" , 2 )
end
local byteCount = ( field . elementSize * count )
local remainder = cursor % field . alignment
if remainder ~= 0 then
cursor = ( cursor + field . alignment - remainder )
end
if cursor > MAX_EXACT_INTEGER - byteCount then
error ( "nupp: SoA slab byte size is too large" , 2 )
end
segments [ ordinal ] = _G.setmetatable({ field =  field ,  offset =  cursor ,  byteCount =  byteCount }, soa.SegmentLayout)
cursor = ( cursor + byteCount )
end

return ( _G.setmetatable({ count =  count ,  byteSize =  cursor ,  segments =  segments }, soa.InstanceLayout) )
end ;_G.nupp.__reflect.link(soa.Layout,__nuppT1[4],{ __nuppT1[1] })


local layoutCache = setmetatable ( { } , { __mode = "k" } )





function soa . _layout ( raw ) 
local prior = layoutCache [ raw ]
if prior then
return prior
end

local fields = { }
local fingerprint = { "soa1" , raw . name }
local alignment = 1
for ordinal , source in ipairs ( raw . fields ) do
local fieldAlignment = source . alignment
if fieldAlignment > alignment then
alignment = fieldAlignment
end
local field = _G.setmetatable({ name =
source . name ,  identity =
( raw . name ) .. "." .. ( source . name ) ,  ctype =
source . ctype ,  ordinal =
ordinal ,  elementSize =
source . size ,  alignment =
fieldAlignment ,  pointerType =
source . pointerType }, soa.FieldLayout)

fields [ ordinal ] = field
fingerprint [
# fingerprint + 1
] = string . format ( "%s:%s@%d/%d" , field . identity , field . ctype , field . elementSize , field . alignment )
end

local layout = _G.setmetatable({ name =
raw . name ,  fingerprint =
table . concat ( fingerprint , "|" ) ,  alignment =
alignment ,  fields =
fields }, soa.Layout)

layoutCache [ raw ] = layout

return layout
end
















function soa . destroyArray ( self ) 
self : close ( )
end __nuppCleanups["nupp.mem.soa#destroyArray"]= soa.destroyArray;








function soa . destroyWriteSpan ( self ) 
do
local _raw = self
end
end __nuppCleanups["nupp.mem.soa#destroyWriteSpan"]= soa.destroyWriteSpan;











soa.Span = {}









local SpanImpl = {} SpanImpl.__index = SpanImpl







function SpanImpl:checkedIndex(index) 
if index % 1 ~= 0 or index < 1 or index > self . count then
error ( "nupp: SoA row index out of bounds" , 2 )
end
return self . offset + index - 1
end

function SpanImpl:get(index) 
local physical = self : checkedIndex ( index )
local value = ffi . new ( self . element )
for ordinal , field in ipairs ( self . layout . fields ) do
( value ) [ field . name ] = ( self . columns [ ordinal ] ) [ physical ]
end

return value
end

function SpanImpl:slice(first, last) 
local finish = last or self . count
if first % 1 ~= 0 or finish % 1 ~= 0 or first < 1 or finish < first - 1 or finish > self . count then
error ( "nupp: SoA slice out of bounds" , 2 )
end

return ( _G.setmetatable({ anchor =
self ,  element =
self . element ,  layout =
self . layout ,  columns =
self . columns ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, SpanImpl) )

end

function SpanImpl:fieldBySlot(ordinal) 
local pointer = ( self . columns [ ordinal ] ) + self . offset
do
local rooted = pointer
return span . fromCarray ( rooted , self . count )
end
end

















































local WriteSpanImpl = {} WriteSpanImpl.__index = WriteSpanImpl







function WriteSpanImpl:checkedIndex(index) 
if index % 1 ~= 0 or index < 1 or index > self . count then
error ( "nupp: SoA row index out of bounds" , 2 )
end
return self . offset + index - 1
end

function WriteSpanImpl:get(index) 
local physical = self : checkedIndex ( index )
local value = ffi . new ( self . element )
for ordinal , field in ipairs ( self . layout . fields ) do
( value ) [ field . name ] = ( self . columns [ ordinal ] ) [ physical ]
end

return value
end

function WriteSpanImpl:set(index, value) 
local physical = self : checkedIndex ( index )
for ordinal , field in ipairs ( self . layout . fields ) do
( self . columns [ ordinal ] ) [ physical ] = ( value ) [ field . name ]
end
end

function WriteSpanImpl:fieldBySlot(ordinal) 
local pointer = ( self . columns [ ordinal ] ) + self . offset
do
local rooted = pointer
return span . writeCarray ( rooted , self . count )
end
end

function WriteSpanImpl:shared() 
return ( _G.setmetatable({ anchor =
self ,  element =
self . element ,  layout =
self . layout ,  columns =
self . columns ,  offset =
self . offset ,  count =
self . count }, SpanImpl) )

end




function WriteSpanImpl:copyFrom(targetFirst, source, sourceFirst, count) 






if count % 1 ~= 0
or targetFirst % 1 ~= 0
or sourceFirst % 1 ~= 0
or count < 0
or targetFirst < 1
or sourceFirst < 1
or targetFirst - 1 > self . count - count
or sourceFirst - 1 > source .count - count
then
error ( "nupp: SoA copy range is out of bounds" , 2 )
end
if count == 0 then
return
end
local other = source
for ordinal , field in ipairs ( self . layout . fields ) do
local destination = ( self . columns [ ordinal ] ) + self . offset + targetFirst - 1
local input = ( other . columns [ ordinal ] ) + other . offset + sourceFirst - 1
ffi . copy ( destination , input , count * field . elementSize )
end
end

function WriteSpanImpl:slice(first, last) 




local finish = last or self . count
if first % 1 ~= 0 or finish % 1 ~= 0 or first < 1 or finish < first - 1 or finish > self . count then
error ( "nupp: SoA slice out of bounds" , 2 )
end

return ( _G.setmetatable({ anchor =
self ,  element =
self . element ,  layout =
self . layout ,  columns =
self . columns ,  offset =
self . offset + first - 1 ,  count =
finish - first + 1 }, WriteSpanImpl) )

end




function WriteSpanImpl . drop ( self ) 
do
local _raw = self
end
end



soa.Array = {} soa.Array.__index = soa.Array ;_G.nupp.__reflect.link(soa.Array,__nuppT1[5],{ __nuppT1[4] })





























function soa . Array . read ( self ) 
return ( _G.setmetatable({ anchor =
self ,  element =
self . element ,  layout =
self . layout ,  columns =
self . columns ,  offset =
0 ,  count =
self . count }, SpanImpl) )

end

function soa . Array . write (
self
) 
return ( _G.setmetatable({ anchor =
self ,  element =
self . element ,  layout =
self . layout ,  columns =
self . columns ,  offset =
0 ,  count =
self . count }, WriteSpanImpl) )

end

local function finishArray ( self ) 
do
local raw = self
do local __nuppT33=0; local  __nuppT39 ; local __nuppT40=false ; local __nuppT34,__nuppT35,__nuppT36=__nuppT26(function() do local __nuppT41= raw . raw ; __nuppT39= __nuppT41 ; __nuppT33=1;  __nuppT40=true;  local pointer=__nuppT39;
do (function(__nuppT42,...)  __nuppT40=false; return __nuppT42(...)  end)( free_nosuspend , pointer ) end end; return "normal" end,__nuppT22); local __nuppT37={}; local __nuppT38=0; if __nuppT33>=1 and __nuppT40 then  local __nuppT43,__nuppT44=__nuppT25(__nuppCleanup1,__nuppT39);  if not __nuppT43 then __nuppT38=__nuppT38+1; __nuppT37[__nuppT38]=__nuppT44 end; end; if not __nuppT34 then if __nuppT38>0 then __nuppT27(__nuppT23(__nuppT35,__nuppT37,1),0) else __nuppT27(__nuppT35,0) end end; if __nuppT38>0 then if __nuppT38>1 then __nuppT27(__nuppT23(__nuppT37[1],__nuppT37,2),0) else __nuppT27(__nuppT37[1],0) end end; if __nuppT35=="return" then  return __nuppT28(__nuppT36,1,__nuppT36.n)  end; end
end
end

local finishArrayNosuspend = finishArray

function soa . Array . close ( self ) 
finishArrayNosuspend ( self )
end





function soa . _allocate ( element , count , rawLayout ) __nuppCleanups["nupp.mem.soa#destroyArray"]=soa.destroyArray; 
local layout = soa . _layout ( rawLayout )
local instance = layout : forCount ( count )
local bytes = instance . byteSize
local alignment = layout . alignment
local padding = alignment - 1
if bytes > 9007199254740991 - padding then
error ( "nupp: SoA aligned slab byte size is too large" , 2 )
end
local allocationBytes = bytes + padding
if allocationBytes == 0 then
allocationBytes = 1
end
local raw = malloc ( allocationBytes )
if raw == nil then
error ( "nupp: SoA allocation failed" , 2 )
end

local columns = { }
do
local rawAddress = tonumber ( __nuppFfi.cast("uint64_t" , raw ) )
local adjustment = ( alignment - ( rawAddress % alignment ) ) % alignment
local allocation = __nuppFfi.cast("uint8_t *" , raw )
local base = allocation + adjustment
for ordinal , segment in ipairs ( instance . segments ) do
columns [ ordinal ] = ffi . cast ( segment . field . pointerType , base + segment . offset )
end
return ( _G.setmetatable({ raw =
raw ,  element =
element ,  layout =
layout ,  columns =
columns ,  count =
count ,  fingerprint =
layout . fingerprint }, soa.Array) )

end
end




















function soa . allocate ( element , count ) __nuppCleanups["nupp.mem.soa#destroyArray"]=soa.destroyArray; 
error ( "nupp: soa.allocate requires compiler lowering" , 2 )
end

















function soa . layoutof ( element ) 
error ( "nupp: soa.layoutof requires compiler lowering" , 2 )
end

local __nuppExportValue= soa ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.mem.soa"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mem.soa"]=__nuppExports;return __nuppExports