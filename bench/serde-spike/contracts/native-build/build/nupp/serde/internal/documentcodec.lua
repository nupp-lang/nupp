_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT9={}; local function __nuppT6(...) return {n=select("#",...),...} end; local __nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT7(value) return value end; local function __nuppT8(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT15({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT16(v.primary) for _,reason in __nuppT17(v.suppressed) do text=text.."\ncleanup: "..__nuppT16(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.internal.documentcodec"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local cachedBindings;__nuppExports["cachedBindings"]=function(...) return cachedBindings(...) end;local clear;__nuppExports["clear"]=function(...) return clear(...) end;local decoder;__nuppExports["decoder"]=function(...) return decoder(...) end;local decoderFor;__nuppExports["decoderFor"]=function(...) return decoderFor(...) end;local fromBinding;__nuppExports["fromBinding"]=function(...) return fromBinding(...) end;local into;__nuppExports["into"]=function(...) return into(...) end;

local core = require ( "nupp.serde.internal.value" )
local publication = require ( "nupp.serde.internal.publication" )
local memos = require ( "nupp.serde.internal.memo" )
local documents = require ( "nupp.serde.internal.document" )
local readers = require ( "nupp.serde.internal.documentreader" )
local numbers = require ( "nupp.serde.internal.numbers" )
local writers = require ( "nupp.serde.internal.documentwriter" )

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

function Unknown:captureValue(adapter) local __nuppT5;
self : live ( )
self . used = true
do const  __nuppT24= readers . reader ( self . value ) ; __nuppT5=__nuppT5 or {} ; local __nuppT25=__nuppT5[1]; if not __nuppT25 then __nuppT25=function(reader) do
local result = adapter : readContents ( reader )
local complete , problem = pcall ( reader . finish , reader )
if not complete then
error ( publication . failure ( adapter , result , problem ) , 0 )
end

return "return",__nuppT6( result ) end; return "normal" end; __nuppT5[1]=__nuppT25 end; const __nuppT19,__nuppT20,__nuppT21=__nuppT11(__nuppT25,__nuppT7,__nuppT24); const __nuppT18=1; local __nuppT22={}; local __nuppT23=0; if __nuppT18>=1 then  local __nuppT26,__nuppT27=__nuppT10(__nuppCleanup1,__nuppT24);  if not __nuppT26 then __nuppT23=__nuppT23+1; __nuppT22[__nuppT23]=__nuppT27 end; end; if not __nuppT19 then if __nuppT23>0 then __nuppT12(__nuppT8(__nuppT20,__nuppT22,1),0) else __nuppT12(__nuppT20,0) end end; if __nuppT23>0 then if __nuppT23>1 then __nuppT12(__nuppT8(__nuppT22[1],__nuppT22,2),0) else __nuppT12(__nuppT22[1],0) end end; if __nuppT20=="return" then  return __nuppT13(__nuppT21,1,__nuppT21.n)  end; end
end


local Input = {} Input.__index = Input




function Input:close() 
self . expired = true
end

function Input:scoped(value, selected) 
return ( _G.setmetatable({ value =  value ,  plan =  selected ,  used =  false ,  expired =  false }, Input) )
end

function Input:live() 
assert ( not self . expired and not self . used , "document value reader is no longer usable" )
end

function Input:context() 
self : live ( )
return self . value : context ( )
end

function Input:isNull() 
self : live ( )
return self . value . kind == "null"
end

function Input:consume(kind) 
self : live ( )
assert ( self . value . kind == kind , "document kind does not match the binding" )
self . used = true
end

function Input:readNull(member) 
assert ( self . plan . description . nullable or self . plan . description . kind == "null" , "binding does not admit null" )
self : consume ( "null" )
end

function Input:readBoolean(member) 
self : consume ( "boolean" )
return self . value : boolean ( )
end

function Input:readInteger(member, width, signed) 
self : consume ( "integer" )
return numbers . integer ( self . value : integer ( ) . decimal , width , signed )
end

function Input:readFloat(member, width) 
self : consume ( "float" )
return numbers . floating ( self . value : float ( ) . value , width , true )
end

function Input:readBigInteger(member) 
self : consume ( "bigInteger" )
return self . value : bigInteger ( )
end

function Input:readDecimal(member) 
self : consume ( "decimal" )
return self . value : decimal ( )
end

function Input:readNumberToken(member) 
self : consume ( "numberToken" )
return self . value : numberToken ( )
end

function Input:readString(member) 
self : consume ( "string" )
return self . value : string ( )
end

function Input:readBytes(member) 
self : consume ( "bytes" )
return self . value : bytes ( )
end

function Input:readTimestamp(member) 
self : consume ( "timestamp" )
return self . value : timestamp ( )
end

function Input:readAtom(member) 
self : consume ( "atom" )
return self . value : atom ( )
end

function Input:readDocument(member, adapter) local __nuppT45;
self : consume ( "document" )
local contents = self . value : document ( )
local context = self . value : context ( )
if contents : context ( ) == nil and context ~= nil then
contents = documents . withContext ( contents , context )
end
do const  __nuppT52= readers . reader ( contents ) ; __nuppT45=__nuppT45 or {} ; local __nuppT53=__nuppT45[2]; if not __nuppT53 then __nuppT53=function(reader) do
local result = adapter : readContents ( reader )
local complete , problem = pcall ( reader . finish , reader )
if not complete then
error ( publication . failure ( adapter , result , problem ) , 0 )
end

return "return",__nuppT6( result ) end; return "normal" end; __nuppT45[2]=__nuppT53 end; const __nuppT47,__nuppT48,__nuppT49=__nuppT11(__nuppT53,__nuppT7,__nuppT52); const __nuppT46=1; local __nuppT50={}; local __nuppT51=0; if __nuppT46>=1 then  local __nuppT54,__nuppT55=__nuppT10(__nuppCleanup1,__nuppT52);  if not __nuppT54 then __nuppT51=__nuppT51+1; __nuppT50[__nuppT51]=__nuppT55 end; end; if not __nuppT47 then if __nuppT51>0 then __nuppT12(__nuppT8(__nuppT48,__nuppT50,1),0) else __nuppT12(__nuppT48,0) end end; if __nuppT51>0 then if __nuppT51>1 then __nuppT12(__nuppT8(__nuppT50[1],__nuppT50,2),0) else __nuppT12(__nuppT50[1],0) end end; if __nuppT48=="return" then  return __nuppT13(__nuppT49,1,__nuppT49.n)  end; end
end

function Input:size() 
if self . value . kind == "structure"
or self . value . kind == "union"
or self . value . kind == "map"
or self . value . kind == "list"
or self . value . kind == "tuple"
then
return self . value : size ( )
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
local context = self . value : context ( )
if value : context ( ) == nil and context ~= nil then
value = documents . withContext ( value , context )
end

return ( _G.setmetatable({ value =  value ,  plan =  child ,  used =  false ,  expired =  false }, Input) )
end

function Input:object(kind, state, consume, unknown) 






self : consume ( kind )
if kind == "union" then
assert ( self . value : size ( ) == 1 , "union requires exactly one alternative" )
end
for index = 1 , self . value : size ( ) do
local entry = self . value : field ( index )
local member = self . plan . names [ entry . name ]
if member ~= nil then
do local __nuppT61=0; local  __nuppT67 ; local __nuppT62,__nuppT63,__nuppT64=__nuppT11(function() do local __nuppT68= self : child ( entry . value , assert ( self . plan . children [ member ] ) ) ; __nuppT67= __nuppT68 ; __nuppT61=1;  local child=__nuppT67;
consume : apply ( state , member , child )
assert ( child . used , "member callback did not consume its value" ) end; return "normal" end,__nuppT7); local __nuppT65={}; local __nuppT66=0; if __nuppT61>=1 then  local __nuppT69,__nuppT70=__nuppT10(__nuppCleanup1,__nuppT67);  if not __nuppT69 then __nuppT66=__nuppT66+1; __nuppT65[__nuppT66]=__nuppT70 end; end; if not __nuppT62 then if __nuppT66>0 then __nuppT12(__nuppT8(__nuppT63,__nuppT65,1),0) else __nuppT12(__nuppT63,0) end end; if __nuppT66>0 then if __nuppT66>1 then __nuppT12(__nuppT8(__nuppT65[1],__nuppT65,2),0) else __nuppT12(__nuppT65[1],0) end end; if __nuppT63=="return" then  return __nuppT13(__nuppT64,1,__nuppT64.n)  end; end
else
do local __nuppT71=0; local  __nuppT77 ; local __nuppT72,__nuppT73,__nuppT74=__nuppT11(function() do local __nuppT78= _G.setmetatable({ value =  entry . value ,  used =  false ,  expired =  false }, Unknown) ; __nuppT77= __nuppT78 ; __nuppT71=1;  local child=__nuppT77;
unknown : apply ( state , _G.setmetatable({ name =  entry . name }, documents.Name) , child )
assert ( child . used , "unknown callback did not consume its value" ) end; return "normal" end,__nuppT7); local __nuppT75={}; local __nuppT76=0; if __nuppT71>=1 then  local __nuppT79,__nuppT80=__nuppT10(__nuppCleanup1,__nuppT77);  if not __nuppT79 then __nuppT76=__nuppT76+1; __nuppT75[__nuppT76]=__nuppT80 end; end; if not __nuppT72 then if __nuppT76>0 then __nuppT12(__nuppT8(__nuppT73,__nuppT75,1),0) else __nuppT12(__nuppT73,0) end end; if __nuppT76>0 then if __nuppT76>1 then __nuppT12(__nuppT8(__nuppT75[1],__nuppT75,2),0) else __nuppT12(__nuppT75[1],0) end end; if __nuppT73=="return" then  return __nuppT13(__nuppT74,1,__nuppT74.n)  end; end
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
assert ( size == nil or self . value : size ( ) == size , "wrong tuple size" )
for index = 1 , self . value : size ( ) do
do local __nuppT84=0; local  __nuppT90 ; local __nuppT85,__nuppT86,__nuppT87=__nuppT11(function() do local __nuppT91= self : child ( self . value : at ( index ) , self : slot ( kind == "tuple" and index or 1 ) ) ; __nuppT90= __nuppT91 ; __nuppT84=1;  local child=__nuppT90;
consume : apply ( state , index , child )
assert ( child . used , "element callback did not consume its value" ) end; return "normal" end,__nuppT7); local __nuppT88={}; local __nuppT89=0; if __nuppT84>=1 then  local __nuppT92,__nuppT93=__nuppT10(__nuppCleanup1,__nuppT90);  if not __nuppT92 then __nuppT89=__nuppT89+1; __nuppT88[__nuppT89]=__nuppT93 end; end; if not __nuppT85 then if __nuppT89>0 then __nuppT12(__nuppT8(__nuppT86,__nuppT88,1),0) else __nuppT12(__nuppT86,0) end end; if __nuppT89>0 then if __nuppT89>1 then __nuppT12(__nuppT8(__nuppT88[1],__nuppT88,2),0) else __nuppT12(__nuppT88[1],0) end end; if __nuppT86=="return" then  return __nuppT13(__nuppT87,1,__nuppT87.n)  end; end
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
for index = 1 , self . value : size ( ) do
local entry = self . value : entry ( index )
local keyDocument , valueDocument = entry . key , entry . value
local context = self . value : context ( )
if context ~= nil then
if keyDocument : context ( ) == nil then
keyDocument = documents . withContext ( keyDocument , context )
end
if valueDocument : context ( ) == nil then
valueDocument = documents . withContext ( valueDocument , context )
end
end
do local __nuppT97=0; local  __nuppT103,__nuppT104 ; local __nuppT98,__nuppT99,__nuppT100=__nuppT11(function() do local __nuppT105= self : scoped ( keyDocument , self : slot ( 1 ) ) ; __nuppT103= __nuppT105 ; __nuppT97=1;  local key=__nuppT103;
local __nuppT106= self : scoped ( valueDocument , self : slot ( 2 ) ) ; __nuppT104= __nuppT106 ; __nuppT97=2;  local value=__nuppT104;
consume : apply ( state , key , value )
assert ( key . used and value . used , "entry callback did not consume key and value" ) end; return "normal" end,__nuppT7); local __nuppT101={}; local __nuppT102=0; if __nuppT97>=2 then  local __nuppT107,__nuppT108=__nuppT10(__nuppCleanup1,__nuppT104);  if not __nuppT107 then __nuppT102=__nuppT102+1; __nuppT101[__nuppT102]=__nuppT108 end; end; if __nuppT97>=1 then  local __nuppT109,__nuppT110=__nuppT10(__nuppCleanup1,__nuppT103);  if not __nuppT109 then __nuppT102=__nuppT102+1; __nuppT101[__nuppT102]=__nuppT110 end; end; if not __nuppT98 then if __nuppT102>0 then __nuppT12(__nuppT8(__nuppT99,__nuppT101,1),0) else __nuppT12(__nuppT99,0) end end; if __nuppT102>0 then if __nuppT102>1 then __nuppT12(__nuppT8(__nuppT101[1],__nuppT101,2),0) else __nuppT12(__nuppT101[1],0) end end; if __nuppT99=="return" then  return __nuppT13(__nuppT100,1,__nuppT100.n)  end; end
end
end


local function input ( value , selected ) 
return ( _G.setmetatable({ value =  value ,  plan =  selected ,  used =  false ,  expired =  false }, Input) )
end












local Reconstruction = {} Reconstruction.__index = Reconstruction



function Reconstruction:read(value) local __nuppT112;
do const  __nuppT119= input ( value , self . selected ) ; __nuppT112=__nuppT112 or {} ; local __nuppT120=__nuppT112[3]; if not __nuppT120 then __nuppT120=function(reader) do
local result = self . adapter : read ( reader )
if not reader . used then
error ( publication . failure ( self . discard , result , "binding did not consume its value" ) , 0 )
end

return "return",__nuppT6( result ) end; return "normal" end; __nuppT112[3]=__nuppT120 end; const __nuppT114,__nuppT115,__nuppT116=__nuppT11(__nuppT120,__nuppT7,__nuppT119); const __nuppT113=1; local __nuppT117={}; local __nuppT118=0; if __nuppT113>=1 then  local __nuppT121,__nuppT122=__nuppT10(__nuppCleanup1,__nuppT119);  if not __nuppT121 then __nuppT118=__nuppT118+1; __nuppT117[__nuppT118]=__nuppT122 end; end; if not __nuppT114 then if __nuppT118>0 then __nuppT12(__nuppT8(__nuppT115,__nuppT117,1),0) else __nuppT12(__nuppT115,0) end end; if __nuppT118>0 then if __nuppT118>1 then __nuppT12(__nuppT8(__nuppT117[1],__nuppT117,2),0) else __nuppT12(__nuppT117[1],0) end end; if __nuppT115=="return" then  return __nuppT13(__nuppT116,1,__nuppT116.n)  end; end
end

decoderFor=function (
adapter ,
description ,
discard
) 
return ( _G.setmetatable({ adapter =  adapter ,  selected =  plan ( description , { } ) ,  discard =  discard }, Reconstruction) )
end ;__nuppExports["decoderFor"]=decoderFor

local Resolve = {} Resolve.__index = Resolve


function Resolve:apply(adapter, state) 
self . result = decoderFor ( adapter , adapter : describe ( "read" ) , self . binding )
end

local memo = memos . new ( "document reconstruction" , 256 )

clear=function ( ) 
memo : clear ( )
end ;__nuppExports["clear"]=clear

cachedBindings=function ( ) 
return memo : size ( )
end ;__nuppExports["cachedBindings"]=cachedBindings

decoder=function ( binding ) 
local found , cached = memo : find ( binding , "read" )
if found then


return cached
end
local slot = memo : start ( binding , "read" )
local resolve = _G.setmetatable({ binding =  binding }, Resolve)
local ok , problem = pcall ( binding . accept , binding , resolve , nil )
if ok and resolve . result == nil then
ok , problem = false , "binding did not supply its adapter"
end

return memo : finish ( slot , ok , ok and resolve . result or problem )
end ;__nuppExports["decoder"]=decoder

fromBinding=function ( binding , value , context ) 
return writers . fromBinding ( binding , value , context )
end ;__nuppExports["fromBinding"]=fromBinding

into=function ( binding , value ) 
return decoder ( binding ) : read ( value )
end ;__nuppExports["into"]=into
 end);if not __nuppOk then package.loaded["nupp.serde.internal.documentcodec"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.documentcodec"]=__nuppExports;return __nuppExports