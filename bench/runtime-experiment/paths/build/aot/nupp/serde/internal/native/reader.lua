_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.internal.native.reader"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local decoderFor;__nuppExports["decoderFor"]=function(...) return decoderFor(...) end;

local core = require ( "nupp.serde.internal.value" )
local publication = require ( "nupp.serde.internal.publication" )
local documents = require ( "nupp.serde.internal.document" )
local readers = require ( "nupp.serde.internal.documentreader" )
local numbers = require ( "nupp.serde.internal.numbers" )



local function node ( value ) 
return value
end

local function nodeKind ( value ) 
return value [ 1 ]
end

local function nodeSize ( value ) 
local tag = nodeKind ( value )
if tag == "structure" or tag == "union" or tag == "map" then
return math . floor ( ( # value - 1 ) / 2 )
end

return # value - 1
end

local Plan = {} Plan.__index = Plan





local function plan ( description , seen ) 
local prior = seen [ description ]
if prior ~= nil then
return prior
end
assert ( description . canRead , "binding has no construction operation" )
local result = _G.setmetatable({ description =  description ,  names =  {} ,  children =  {} }, Plan)
seen [ description ] = result
for _ , child in ipairs ( description . children ) do
assert ( result . names [ child . member . name ] == nil , "duplicate logical member name" )
result . names [ child . member . name ] = child . member
result . children [ child . member ] = plan ( child : describe ( "read" ) , seen )
end

return result
end

local Unknown = {} Unknown.__index = Unknown





function Unknown:close() 
self . expired = true
end

function Unknown:live() 
assert ( not self . expired and not self . used , "unknown document reader is no longer usable" )
end

function Unknown:skipValue() 
self : live ( )
self . used = true
end

function Unknown:captureValue(adapter) local __nuppT8;
self : live ( )
self . used = true
local value = self . materialize ( self . value )
if self . source ~= nil then
value = documents . withContext ( value , self . source )
end
do const  __nuppT27= readers . reader ( value ) ; __nuppT8=__nuppT8 or {} ; local __nuppT28=__nuppT8[1]; if not __nuppT28 then __nuppT28=function(reader) do
local result = adapter : readContents ( reader )
local complete , problem = pcall ( reader . finish , reader )
if not complete then
error ( publication . failure ( adapter , result , problem ) , 0 )
end

return "return",__nuppT9( result ) end; return "normal" end; __nuppT8[1]=__nuppT28 end; const __nuppT22,__nuppT23,__nuppT24=__nuppT14(__nuppT28,__nuppT10,__nuppT27); const __nuppT21=1; local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 then  local __nuppT29,__nuppT30=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT29 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT30 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end


local Input = {} Input.__index = Input






function Input:close() 
self . expired = true
end

function Input:scoped(value, selected) 
return ( _G.setmetatable({ value =  value ,  plan =  selected ,  source =  self . source ,  materialize =  self . materialize ,  used =  false ,  expired =  false }, Input) )
end

function Input:live() 
assert ( not self . expired and not self . used , "document value reader is no longer usable" )
end

function Input:context() 
self : live ( )
return self . source
end

function Input:isNull() 
self : live ( )
return nodeKind ( self . value ) == "null"
end

function Input:consume(kind) 
self : live ( )
assert ( nodeKind ( self . value ) == kind , "document kind does not match the binding" )
self . used = true
end

function Input:readNull(member) 
assert ( self . plan . description . nullable or self . plan . description . kind == "null" , "binding does not admit null" )
self : consume ( "null" )
end

function Input:readBoolean(member) 
self : consume ( "boolean" )
return self . value [ 2 ]
end

function Input:readInteger(member, width, signed) 
self : consume ( "integer" )
return numbers . integer ( self . value [ 2 ] , width , signed )
end

function Input:readFloat(member, width) 
self : consume ( "float" )
return numbers . floating ( self . value [ 2 ] , width , true )
end

function Input:readBigInteger(member) 
self : consume ( "bigInteger" )
return self . value [ 2 ]
end

function Input:readDecimal(member) 
self : consume ( "decimal" )
return ( _G.setmetatable({ coefficient =  self . value [ 2 ] ,  exponent =  self . value [ 3 ] }, core.Decimal) )
end

function Input:readNumberToken(member) 
self : consume ( "numberToken" )
return self . value [ 2 ]
end

function Input:readString(member) 
self : consume ( "string" )
return self . value [ 2 ]
end

function Input:readBytes(member) 
self : consume ( "bytes" )
return self . value [ 2 ]
end

function Input:readTimestamp(member) 
self : consume ( "timestamp" )
return ( _G.setmetatable({ seconds =  self . value [ 2 ] ,  nanos =  self . value [ 3 ] }, core.Timestamp) )
end

function Input:readAtom(member) 
self : consume ( "atom" )
error ( "native persistence does not represent atoms" , 2 )
end

function Input:readDocument(member, adapter) local __nuppT48;
self : consume ( "document" )
local contents = self . materialize ( self . value [ 2 ] )
local context = self . source
if contents : context ( ) == nil and context ~= nil then
contents = documents . withContext ( contents , context )
end
do const  __nuppT55= readers . reader ( contents ) ; __nuppT48=__nuppT48 or {} ; local __nuppT56=__nuppT48[2]; if not __nuppT56 then __nuppT56=function(reader) do
local result = adapter : readContents ( reader )
local complete , problem = pcall ( reader . finish , reader )
if not complete then
error ( publication . failure ( adapter , result , problem ) , 0 )
end

return "return",__nuppT9( result ) end; return "normal" end; __nuppT48[2]=__nuppT56 end; const __nuppT50,__nuppT51,__nuppT52=__nuppT14(__nuppT56,__nuppT10,__nuppT55); const __nuppT49=1; local __nuppT53={}; local __nuppT54=0; if __nuppT49>=1 then  local __nuppT57,__nuppT58=__nuppT13(__nuppCleanup1,__nuppT55);  if not __nuppT57 then __nuppT54=__nuppT54+1; __nuppT53[__nuppT54]=__nuppT58 end; end; if not __nuppT50 then if __nuppT54>0 then __nuppT15(__nuppT11(__nuppT51,__nuppT53,1),0) else __nuppT15(__nuppT51,0) end end; if __nuppT54>0 then if __nuppT54>1 then __nuppT15(__nuppT11(__nuppT53[1],__nuppT53,2),0) else __nuppT15(__nuppT53[1],0) end end; if __nuppT51=="return" then  return __nuppT16(__nuppT52,1,__nuppT52.n)  end; end
end

function Input:size() 
if nodeKind ( self . value ) == "structure"
or nodeKind ( self . value ) == "union"
or nodeKind ( self . value ) == "map"
or nodeKind ( self . value ) == "list"
or nodeKind ( self . value ) == "tuple"
then
return nodeSize ( self . value )
end

return nil
end

function Input:containerSize() 
self : live ( )
return self : size ( )
end

function Input:slot(index) 
local child = assert ( self . plan . description . children [ index ] , "binding has no container child" )
return assert ( self . plan . children [ child . member ] )
end

function Input:child(value, child) 
return ( _G.setmetatable({ value =  value ,  plan =  child ,  source =  self . source ,  materialize =  self . materialize ,  used =  false ,  expired =  false }, Input) )
end

function Input:object(kind, state, consume, unknown) 






self : consume ( kind )
if kind == "union" then
assert ( nodeSize ( self . value ) == 1 , "union requires exactly one alternative" )
end
for index = 1 , nodeSize ( self . value ) do
local name = self . value [ index * 2 ]
local value = node ( self . value [ index * 2 + 1 ] )
local member = self . plan . names [ name ]
if member ~= nil then
do local __nuppT64=0; local  __nuppT70 ; local __nuppT65,__nuppT66,__nuppT67=__nuppT14(function() do local __nuppT71= self : child ( value , assert ( self . plan . children [ member ] ) ) ; __nuppT70= __nuppT71 ; __nuppT64=1;  local child=__nuppT70;
consume : apply ( state , member , child )
assert ( child . used , "member callback did not consume its value" ) end; return "normal" end,__nuppT10); local __nuppT68={}; local __nuppT69=0; if __nuppT64>=1 then  local __nuppT72,__nuppT73=__nuppT13(__nuppCleanup1,__nuppT70);  if not __nuppT72 then __nuppT69=__nuppT69+1; __nuppT68[__nuppT69]=__nuppT73 end; end; if not __nuppT65 then if __nuppT69>0 then __nuppT15(__nuppT11(__nuppT66,__nuppT68,1),0) else __nuppT15(__nuppT66,0) end end; if __nuppT69>0 then if __nuppT69>1 then __nuppT15(__nuppT11(__nuppT68[1],__nuppT68,2),0) else __nuppT15(__nuppT68[1],0) end end; if __nuppT66=="return" then  return __nuppT16(__nuppT67,1,__nuppT67.n)  end; end
else
do local __nuppT74=0; local  __nuppT80 ; local __nuppT75,__nuppT76,__nuppT77=__nuppT14(function() do local __nuppT81= _G.setmetatable({ value =  value ,  source =  self . source ,  materialize =  self . materialize ,  used =  false ,  expired =  false }, Unknown) ; __nuppT80= __nuppT81 ; __nuppT74=1;  local child=__nuppT80;
unknown : apply ( state , _G.setmetatable({ name =  name }, documents.Name) , child )
assert ( child . used , "unknown callback did not consume its value" ) end; return "normal" end,__nuppT10); local __nuppT78={}; local __nuppT79=0; if __nuppT74>=1 then  local __nuppT82,__nuppT83=__nuppT13(__nuppCleanup1,__nuppT80);  if not __nuppT82 then __nuppT79=__nuppT79+1; __nuppT78[__nuppT79]=__nuppT83 end; end; if not __nuppT75 then if __nuppT79>0 then __nuppT15(__nuppT11(__nuppT76,__nuppT78,1),0) else __nuppT15(__nuppT76,0) end end; if __nuppT79>0 then if __nuppT79>1 then __nuppT15(__nuppT11(__nuppT78[1],__nuppT78,2),0) else __nuppT15(__nuppT78[1],0) end end; if __nuppT76=="return" then  return __nuppT16(__nuppT77,1,__nuppT77.n)  end; end
end
end
end

function Input:readStruct(member, state, consume, unknown) 






self : object ( "structure" , state , consume , unknown )
end

function Input:readUnion(member, state, consume, unknown) 






self : object ( "union" , state , consume , unknown )
end

function Input:array(kind, size, state, consume) 






self : consume ( kind )
assert ( size == nil or nodeSize ( self . value ) == size , "wrong tuple size" )
for index = 1 , nodeSize ( self . value ) do
do local __nuppT87=0; local  __nuppT93 ; local __nuppT88,__nuppT89,__nuppT90=__nuppT14(function() do local __nuppT94= self : child ( node ( self . value [ index + 1 ] ) , self : slot ( kind == "tuple" and index or 1 ) ) ; __nuppT93= __nuppT94 ; __nuppT87=1;  local child=__nuppT93;
consume : apply ( state , index , child )
assert ( child . used , "element callback did not consume its value" ) end; return "normal" end,__nuppT10); local __nuppT91={}; local __nuppT92=0; if __nuppT87>=1 then  local __nuppT95,__nuppT96=__nuppT13(__nuppCleanup1,__nuppT93);  if not __nuppT95 then __nuppT92=__nuppT92+1; __nuppT91[__nuppT92]=__nuppT96 end; end; if not __nuppT88 then if __nuppT92>0 then __nuppT15(__nuppT11(__nuppT89,__nuppT91,1),0) else __nuppT15(__nuppT89,0) end end; if __nuppT92>0 then if __nuppT92>1 then __nuppT15(__nuppT11(__nuppT91[1],__nuppT91,2),0) else __nuppT15(__nuppT91[1],0) end end; if __nuppT89=="return" then  return __nuppT16(__nuppT90,1,__nuppT90.n)  end; end
end
end

function Input:readList(member, state, consume) 
self : array ( "list" , nil , state , consume )
end

function Input:readTuple(member, size, state, consume) 






self : array ( "tuple" , size , state , consume )
end

function Input:readMap(member, state, consume) 
self : consume ( "map" )
for index = 1 , nodeSize ( self . value ) do
local keyDocument = node ( self . value [ index * 2 ] )
local valueDocument = node ( self . value [ index * 2 + 1 ] )
do local __nuppT100=0; local  __nuppT106,__nuppT107 ; local __nuppT101,__nuppT102,__nuppT103=__nuppT14(function() do local __nuppT108= self : scoped ( keyDocument , self : slot ( 1 ) ) ; __nuppT106= __nuppT108 ; __nuppT100=1;  local key=__nuppT106;
local __nuppT109= self : scoped ( valueDocument , self : slot ( 2 ) ) ; __nuppT107= __nuppT109 ; __nuppT100=2;  local value=__nuppT107;
consume : apply ( state , key , value )
assert ( key . used and value . used , "entry callback did not consume key and value" ) end; return "normal" end,__nuppT10); local __nuppT104={}; local __nuppT105=0; if __nuppT100>=2 then  local __nuppT110,__nuppT111=__nuppT13(__nuppCleanup1,__nuppT107);  if not __nuppT110 then __nuppT105=__nuppT105+1; __nuppT104[__nuppT105]=__nuppT111 end; end; if __nuppT100>=1 then  local __nuppT112,__nuppT113=__nuppT13(__nuppCleanup1,__nuppT106);  if not __nuppT112 then __nuppT105=__nuppT105+1; __nuppT104[__nuppT105]=__nuppT113 end; end; if not __nuppT101 then if __nuppT105>0 then __nuppT15(__nuppT11(__nuppT102,__nuppT104,1),0) else __nuppT15(__nuppT102,0) end end; if __nuppT105>0 then if __nuppT105>1 then __nuppT15(__nuppT11(__nuppT104[1],__nuppT104,2),0) else __nuppT15(__nuppT104[1],0) end end; if __nuppT102=="return" then  return __nuppT16(__nuppT103,1,__nuppT103.n)  end; end
end
end


local function input (
value ,
selected ,
source ,
materialize
) 
return ( _G.setmetatable({ value =  value ,  plan =  selected ,  source =  source ,  materialize =  materialize ,  used =  false ,  expired =  false }, Input) )
end




local Reconstruction = {} Reconstruction.__index = Reconstruction




function Reconstruction:read(value, source) local __nuppT115;
do const  __nuppT122= input ( value , self . selected , source , self . materialize ) ; __nuppT115=__nuppT115 or {} ; local __nuppT123=__nuppT115[3]; if not __nuppT123 then __nuppT123=function(reader) do
local result = self . adapter : read ( reader )
if not reader . used then
error ( publication . failure ( self . discard , result , "binding did not consume its value" ) , 0 )
end

return "return",__nuppT9( result ) end; return "normal" end; __nuppT115[3]=__nuppT123 end; const __nuppT117,__nuppT118,__nuppT119=__nuppT14(__nuppT123,__nuppT10,__nuppT122); const __nuppT116=1; local __nuppT120={}; local __nuppT121=0; if __nuppT116>=1 then  local __nuppT124,__nuppT125=__nuppT13(__nuppCleanup1,__nuppT122);  if not __nuppT124 then __nuppT121=__nuppT121+1; __nuppT120[__nuppT121]=__nuppT125 end; end; if not __nuppT117 then if __nuppT121>0 then __nuppT15(__nuppT11(__nuppT118,__nuppT120,1),0) else __nuppT15(__nuppT118,0) end end; if __nuppT121>0 then if __nuppT121>1 then __nuppT15(__nuppT11(__nuppT120[1],__nuppT120,2),0) else __nuppT15(__nuppT120[1],0) end end; if __nuppT118=="return" then  return __nuppT16(__nuppT119,1,__nuppT119.n)  end; end
end

decoderFor=function (
adapter ,
description ,
discard ,
materialize
) 
return ( _G.setmetatable({ adapter =
adapter ,  selected =
plan ( description , { } ) ,  discard =
discard ,  materialize =
materialize }, Reconstruction) )

end ;__nuppExports["decoderFor"]=decoderFor
 end);if not __nuppOk then package.loaded["nupp.serde.internal.native.reader"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.native.reader"]=__nuppExports;return __nuppExports