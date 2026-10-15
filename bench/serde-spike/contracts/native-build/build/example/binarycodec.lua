_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT11={}; local function __nuppT8(...) return {n=select("#",...),...} end; local __nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT9(value) return value end; local function __nuppT10(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT17({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT18(v.primary) for _,reason in __nuppT19(v.suppressed) do text=text.."\ncleanup: "..__nuppT18(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["example.binarycodec"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local codec;__nuppExports["codec"]=function(...) return codec(...) end;

local __serdeJson = require ( "nupp.serde.json" )

local core = require ( "nupp.serde" )
local publication = require ( "nupp.serde.codec" )
local syntax = require ( "example.binary" )
local integers = require ( "example.binarynumbers" )
local positional = require ( "example.binarypositional" )
local documents = require ( "nupp.serde.document" )
local documentReaders = require ( "nupp.serde.document" )
local bridge = require ( "nupp.serde.document" )
local contexts = require ( "nupp.serde.codec" )
local utf8 = require ( "nupp.text.utf8" )




local family = { }
local wire = { string = 1 , bytes = 2 , integer = 3 , structure = 4 , tuple = 5 }

local Plan = {} Plan.__index = Plan








local function plan (
description ,
policy ,
direction ,
seen
) 
local previous = seen [ description ]
if previous ~= nil then
return previous
end
assert ( not description . nullable , "binary fixture has no null representation" )
assert ( direction ~= "read" or description . canRead , "binding has no construction operation" )
local kind = description . kind
local tag = assert ( wire [ kind ] , "unsupported binary fixture kind: " .. kind )
local number = policy : number ( description . member )
assert ( number >= 1 and number <= 65535 , "binary field number is out of range" )
local result = _G.setmetatable({ description =  description ,  field =  _G.setmetatable({ number =  number ,  wire =  tag }, syntax.Field) ,  children =  {} ,  numbered =  {} ,  ordered =  {} ,  positional =  {} }, Plan)
seen [ description ] = result
if kind == "integer" then
assert (
description . width == 8 or description . width == 16 or description . width == 32 or description . width == 64 ,
"binary integer needs a width"
)
assert ( description . signed ~= nil , "binary integer needs a signedness" )
end
for index , child in ipairs ( description . children ) do
local selected = plan ( child : describe ( direction ) , policy , direction , seen )
assert ( result . children [ child . member ] == nil , "duplicate binary member" )
result . children [ child . member ] = selected
result . ordered [ index ] = selected
if kind == "structure" then
assert ( result . numbered [ selected . field . number ] == nil , "colliding binary field number" )
result . numbered [ selected . field . number ] = selected
elseif kind == "tuple" then
local childKind = selected . description . kind
assert (
childKind == "integer" or childKind == "string" or childKind == "bytes" ,
"positional fixture slots must be scalar"
)
result . positional [
index
] = _G.setmetatable({ kind =
childKind ,  width =
( selected . description . width or 64 ) ,  signed =
selected . description . signed ~= false }, positional.Slot)

else
error ( "scalar binary description has children" , 2 )
end
end

return result
end

local Slot = {} Slot.__index = Slot




local Scope = {} Scope.__index = Scope





function Scope:resolve(adapter, direction) 
local cache = direction == "write" and self . writes or self . reads
local previous = cache [ adapter ]
if previous ~= nil then
if previous . state == "ready" then
return previous . value
elseif previous . state == "failed" then
error ( previous . value , 0 )
else
error ( "recursive binary extension initialization" , 2 )
end
end
assert ( self . count < 256 , "binary fixture extension cache is full" )
local slot = _G.setmetatable({ state =  "initializing" }, Slot)
cache [ adapter ] = slot
self . count += 1
self . active += 1
local ok , selected = pcall ( function ( ) 
local description = adapter : describe ( direction )
assert ( description . kind == "structure" , "binary fixture root must be a structure" )
return plan ( description , self . policy , direction , { } )
end )
self . active -= 1
slot . state = ok and "ready" or "failed"
slot . value = selected
if not ok then
error ( selected , 0 )
end

return selected
end


local Opaque = {} Opaque.__index = Opaque



function Opaque:snapshot() 
return ( _G.setmetatable({ family =
family ,  field =
_G.setmetatable({ number =  self . field . number ,  wire =  self . field . wire }, syntax.Field) ,  bytes =
self . bytes : sub ( 1 ) }, Opaque) )

end


local Unknown = {} Unknown.__index = Unknown




function Unknown:live() 
assert ( not self . closed and not self . used , "binary unknown reader has expired" )
end

function Unknown:skipValue() 
self : live ( )
self . used = true
end

function Unknown:captureValue(adapter) local __nuppT7;
self : live ( )
local value = documents . withContext (
documents . atom ( _G.setmetatable({ family =  family ,  field =  self . entry . field ,  bytes =  self . entry . bytes }, Opaque) ) ,
self . source
)
do const  __nuppT26= documentReaders . reader ( value ) ; __nuppT7=__nuppT7 or {} ; local __nuppT27=__nuppT7[1]; if not __nuppT27 then __nuppT27=function(reader) do
local result = adapter : readContents ( reader )
local complete , problem = pcall ( reader . finish , reader )
if not complete then
error ( publication . discardFailed ( adapter , result , problem ) , 0 )
end
self . used = true

return "return",__nuppT8( result ) end; return "normal" end; __nuppT7[1]=__nuppT27 end; const __nuppT21,__nuppT22,__nuppT23=__nuppT13(__nuppT27,__nuppT9,__nuppT26); const __nuppT20=1; local __nuppT24={}; local __nuppT25=0; if __nuppT20>=1 then  local __nuppT28,__nuppT29=__nuppT12(__nuppCleanup1,__nuppT26);  if not __nuppT28 then __nuppT25=__nuppT25+1; __nuppT24[__nuppT25]=__nuppT29 end; end; if not __nuppT21 then if __nuppT25>0 then __nuppT14(__nuppT10(__nuppT22,__nuppT24,1),0) else __nuppT14(__nuppT22,0) end end; if __nuppT25>0 then if __nuppT25>1 then __nuppT14(__nuppT10(__nuppT24[1],__nuppT24,2),0) else __nuppT14(__nuppT24[1],0) end end; if __nuppT22=="return" then  return __nuppT15(__nuppT23,1,__nuppT23.n)  end; end
end

function Unknown:close() 
self . closed = true
end


local Input = {} Input.__index = Input






function Input:live() 
assert ( not self . closed and not self . used , "binary reader has expired" )
assert ( self . depth <= 128 , "binary nesting limit exceeded" )
end

function Input:context() 
self : live ( )
return self . source
end

function Input:isNull() 
self : live ( )
return false
end

function Input:consume(member, kind) 
self : live ( )
assert (
member == self . selected . description . member and kind == self . selected . description . kind ,
"binary adapter does not match its description"
)
self . used = true
end

function Input:readString(member) 
self : consume ( member , "string" )
assert ( type ( self . value ) == "string" , "invalid string carrier" )
assert ( utf8 . isValid ( self . value ) , "invalid UTF-8 string" )
return self . value
end

function Input:readBytes(member) 
self : consume ( member , "bytes" )
assert ( type ( self . value ) == "string" , "invalid byte carrier" )
return self . value
end

function Input:readInteger(member, width, signed) 
self : consume ( member , "integer" )
assert (
width == self . selected . description . width and signed == self . selected . description . signed ,
"integer access does not match its schema"
)
if type ( self . value ) == "string" then
return integers . decode ( self . value , width , signed )
else
local numbers = require ( "nupp.serde.codec" )
return numbers . integer ( ( self . value ) . decimal , width , signed )
end
end

function Input:child(selected, value) 
return ( _G.setmetatable({ selected =  selected ,  value =  value ,  source =  self . source ,  depth =  self . depth + 1 ,  used =  false ,  closed =  false }, Input) )
end

function Input:readStruct(member, state, consume, unknown) 






self : consume ( member , "structure" )
local reader = syntax . reader ( self . value )
local seen = { }
while true do
local entry = reader : next ( )
if entry == nil then
do break end
end
local child = self . selected . numbered [ entry . field . number ]
if child ~= nil then
assert ( entry . field . wire == child . field . wire , "binary wire type does not match its schema" )
assert ( not seen [ child . description . member ] , "duplicate binary scalar member" )
seen [ child . description . member ] = true
do local __nuppT40=0; local  __nuppT46 ; local __nuppT41,__nuppT42,__nuppT43=__nuppT13(function() do local __nuppT47= self : child ( child , entry . bytes ) ; __nuppT46= __nuppT47 ; __nuppT40=1;  local input=__nuppT46;
consume : apply ( state , child . description . member , input )
assert ( input . used , "binary member was not consumed" ) end; return "normal" end,__nuppT9); local __nuppT44={}; local __nuppT45=0; if __nuppT40>=1 then  local __nuppT48,__nuppT49=__nuppT12(__nuppCleanup1,__nuppT46);  if not __nuppT48 then __nuppT45=__nuppT45+1; __nuppT44[__nuppT45]=__nuppT49 end; end; if not __nuppT41 then if __nuppT45>0 then __nuppT14(__nuppT10(__nuppT42,__nuppT44,1),0) else __nuppT14(__nuppT42,0) end end; if __nuppT45>0 then if __nuppT45>1 then __nuppT14(__nuppT10(__nuppT44[1],__nuppT44,2),0) else __nuppT14(__nuppT44[1],0) end end; if __nuppT42=="return" then  return __nuppT15(__nuppT43,1,__nuppT43.n)  end; end
else
do local __nuppT50=0; local  __nuppT56 ; local __nuppT51,__nuppT52,__nuppT53=__nuppT13(function() do local __nuppT57= _G.setmetatable({ entry =  entry ,  source =  self . source ,  used =  false ,  closed =  false }, Unknown) ; __nuppT56= __nuppT57 ; __nuppT50=1;  local input=__nuppT56;
unknown : apply ( state , entry . field , input )
assert ( input . used , "unknown binary field was not consumed" ) end; return "normal" end,__nuppT9); local __nuppT54={}; local __nuppT55=0; if __nuppT50>=1 then  local __nuppT58,__nuppT59=__nuppT12(__nuppCleanup1,__nuppT56);  if not __nuppT58 then __nuppT55=__nuppT55+1; __nuppT54[__nuppT55]=__nuppT59 end; end; if not __nuppT51 then if __nuppT55>0 then __nuppT14(__nuppT10(__nuppT52,__nuppT54,1),0) else __nuppT14(__nuppT52,0) end end; if __nuppT55>0 then if __nuppT55>1 then __nuppT14(__nuppT10(__nuppT54[1],__nuppT54,2),0) else __nuppT14(__nuppT54[1],0) end end; if __nuppT52=="return" then  return __nuppT15(__nuppT53,1,__nuppT53.n)  end; end
end
end
end

function Input:readTuple(member, size, state, consume) 






self : consume ( member , "tuple" )
assert ( size == # self . selected . ordered , "tuple access does not match its schema" )
local values = positional . decode ( self . selected . positional , self . value )
for index , value in ipairs ( values ) do
do local __nuppT61=0; local  __nuppT67 ; local __nuppT62,__nuppT63,__nuppT64=__nuppT13(function() do local __nuppT68= self : child ( self . selected . ordered [ index ] , value ) ; __nuppT67= __nuppT68 ; __nuppT61=1;  local input=__nuppT67;
consume : apply ( state , index , input )
assert ( input . used , "binary tuple slot was not consumed" ) end; return "normal" end,__nuppT9); local __nuppT65={}; local __nuppT66=0; if __nuppT61>=1 then  local __nuppT69,__nuppT70=__nuppT12(__nuppCleanup1,__nuppT67);  if not __nuppT69 then __nuppT66=__nuppT66+1; __nuppT65[__nuppT66]=__nuppT70 end; end; if not __nuppT62 then if __nuppT66>0 then __nuppT14(__nuppT10(__nuppT63,__nuppT65,1),0) else __nuppT14(__nuppT63,0) end end; if __nuppT66>0 then if __nuppT66>1 then __nuppT14(__nuppT10(__nuppT65[1],__nuppT65,2),0) else __nuppT14(__nuppT65[1],0) end end; if __nuppT63=="return" then  return __nuppT15(__nuppT64,1,__nuppT64.n)  end; end
end
end

function Input:containerSize() 
self : live ( )
return self . selected . description . kind == "tuple" and # self . selected . ordered or nil
end

function Input:close() 
self . closed = true
end

function Input:readNull(member) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readBoolean(member) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readFloat(member, width) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readBigInteger(member) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readDecimal(member) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readNumberToken(member) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readTimestamp(member) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readAtom(member) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readDocument(member, adapter) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readUnion(member, state, consume, unknown) 






error ( "unsupported binary fixture operation" , 2 )
end

function Input:readList(member, state, consume) 
error ( "unsupported binary fixture operation" , 2 )
end

function Input:readMap(member, state, consume) 
error ( "unsupported binary fixture operation" , 2 )
end


local Frame = {} Frame.__index = Frame





local Output = {} Output.__index = Output





function Output:live() 
assert ( not self . closed , "binary writer has expired" )
assert ( # self . frames <= 128 , "binary nesting limit exceeded" )
end

function Output:selected(member) 
self : live ( )
local frame = self . frames [ # self . frames ]
if frame == nil then
assert ( self . root . description . member == member , "foreign binary root member" )
return self . root
end

return assert ( frame . selected . children [ member ] , "foreign binary member" )
end

function Output:include(member) 
self : selected ( member )
return true
end

function Output:put(member, kind, value) 
local selected = self : selected ( member )
assert ( selected . description . kind == kind , "binary adapter does not match its description" )
local frame = self . frames [ # self . frames ]
assert ( frame ~= nil , "scalar binary root is unsupported" )
assert ( not frame . seen [ member ] , "duplicate binary member" )
frame . seen [ member ] = true
if frame . selected . description . kind == "tuple" then
local position = # frame . values + 1
assert ( frame . selected . ordered [ position ] == selected , "tuple members are out of order" )
frame . values [ position ] = value
else
local bytes = type ( value ) == "string" and value or integers . encode ( value )
frame . entries [ # frame . entries + 1 ] = _G.setmetatable({ field =  selected . field ,  bytes =  bytes }, syntax.Entry)
end
end

function Output:writeString(member, value) 
assert ( utf8 . isValid ( value ) , "invalid UTF-8 string" )
self : put ( member , "string" , value )
end

function Output:writeBytes(member, value) 
self : put ( member , "bytes" , value )
end

function Output:writeInteger(member, value) 
local selected = self : selected ( member )
local numbers = require ( "nupp.serde.codec" )
self : put (
member ,
"integer" ,
numbers . integer (
value . decimal ,
selected . description . width ,
selected . description . signed == true
)
)
end

function Output:aggregate(member, kind, source, emit) 
local selected = self : selected ( member )
assert ( selected . description . kind == kind , "binary aggregate does not match its description" )
local frame = _G.setmetatable({ selected =  selected ,  entries =  {} ,  values =  {} ,  seen =  {} }, Frame)
self . frames [ # self . frames + 1 ] = frame
emit : apply ( source , self )
self . frames [ # self . frames ] = nil
local bytes = kind == "structure" and syntax . encode ( frame . entries )
or positional . encode ( selected . positional , frame . values )
if # self . frames == 0 then
assert ( self . result == nil , "binary root was written twice" )
self . result = bytes
else
self : put ( member , kind , bytes )
end
end

function Output:writeStruct(member, source, emit) 
self : aggregate ( member , "structure" , source , emit )
end

function Output:writeTuple(member, size, source, emit) 
assert ( size == # self : selected ( member ) . ordered , "tuple arity does not match its schema" )
self : aggregate ( member , "tuple" , source , emit )
end

function Output:writeUnknown(field, value, adapter) 





self : live ( )
local selected = syntax . identity ( field )
local frame = assert ( self . frames [ # self . frames ] , "unknown binary field outside structure" )
assert ( frame . selected . description . kind == "structure" , "unknown positional slot has no schema" )
assert ( frame . selected . numbered [ selected . number ] == nil , "unknown binary field collides with a known member" )
local source = adapter : context ( value )
assert (
source ~= nil and source . codec == family and source . profile == self . policy ,
"unknown binary value needs its original protocol context"
)
local captured = bridge . from ( adapter : contents ( ) , value )
local atom = captured : atom ( )
assert (
getmetatable ( atom ) == Opaque and atom . family == family ,
"unknown binary value is not an owned wire payload"
)
local opaque = atom
assert (
opaque . field . number == selected . number and opaque . field . wire == selected . wire ,
"unknown binary identity changed"
)
frame . entries [ # frame . entries + 1 ] = _G.setmetatable({ field =  selected ,  bytes =  opaque . bytes }, syntax.Entry)
end

function Output:close() 
self . closed = true
end

function Output:writeNull(member) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeBoolean(member, value) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeFloat(member, value, width) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeNumberToken(member, value) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeBigInteger(member, value) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeDecimal(member, value) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeTimestamp(member, value) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeAtom(member, value) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeDocument(member, value, adapter) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeUnion(member, source, emit) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeList(member, size, source, emit) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeMap(member, size, source, emit) 
error ( "unsupported binary fixture operation" , 2 )
end

function Output:writeEntry(key, keyEmit, value, valueEmit) 






error ( "unsupported binary fixture operation" , 2 )
end


local function output ( selected , policy ) 
return ( _G.setmetatable({ root =  selected ,  policy =  policy ,  frames =  {} ,  closed =  false }, Output) )
end

local function input ( selected , bytes , source ) 
return ( _G.setmetatable({ selected =  selected ,  value =  bytes ,  source =  source ,  depth =  0 ,  used =  false ,  closed =  false }, Input) )
end

local Encode = {} Encode.__index = Encode

function Encode:apply(adapter, value) local __nuppT112;
local selected = self . scope : resolve ( adapter , "write" )
do const  __nuppT119= output ( selected , self . scope . policy ) ; __nuppT112=__nuppT112 or {} ; local __nuppT120=__nuppT112[2]; if not __nuppT120 then __nuppT120=function(writer) do
adapter : write ( value , writer )
local result = assert ( writer . result , "binary binding did not write its root" ) : sub ( 1 )
assert ( # result <= 16777216 , "binary output exceeds byte limit" )

return "return",__nuppT8( result ) end; return "normal" end; __nuppT112[2]=__nuppT120 end; const __nuppT114,__nuppT115,__nuppT116=__nuppT13(__nuppT120,__nuppT9,__nuppT119); const __nuppT113=1; local __nuppT117={}; local __nuppT118=0; if __nuppT113>=1 then  local __nuppT121,__nuppT122=__nuppT12(__nuppCleanup1,__nuppT119);  if not __nuppT121 then __nuppT118=__nuppT118+1; __nuppT117[__nuppT118]=__nuppT122 end; end; if not __nuppT114 then if __nuppT118>0 then __nuppT14(__nuppT10(__nuppT115,__nuppT117,1),0) else __nuppT14(__nuppT115,0) end end; if __nuppT118>0 then if __nuppT118>1 then __nuppT14(__nuppT10(__nuppT117[1],__nuppT117,2),0) else __nuppT14(__nuppT117[1],0) end end; if __nuppT115=="return" then  return __nuppT15(__nuppT116,1,__nuppT116.n)  end; end
end

local Decode = {} Decode.__index = Decode



function Decode:apply(adapter, state) local __nuppT123;
local selected = self . scope : resolve ( adapter , "read" )
local source = contexts . contextBuilder ( family , self . scope . policy ) : freeze ( )
do const  __nuppT130= input ( selected , self . bytes , source ) ; __nuppT123=__nuppT123 or {} ; local __nuppT131=__nuppT123[3]; if not __nuppT131 then __nuppT131=function(reader) do
local value = adapter : read ( reader )
if not reader . used then
error ( publication . discardFailed ( self . binding , value , "binary binding did not consume its root" ) , 0 )
end

return "return",__nuppT8( value ) end; return "normal" end; __nuppT123[3]=__nuppT131 end; const __nuppT125,__nuppT126,__nuppT127=__nuppT13(__nuppT131,__nuppT9,__nuppT130); const __nuppT124=1; local __nuppT128={}; local __nuppT129=0; if __nuppT124>=1 then  local __nuppT132,__nuppT133=__nuppT12(__nuppCleanup1,__nuppT130);  if not __nuppT132 then __nuppT129=__nuppT129+1; __nuppT128[__nuppT129]=__nuppT133 end; end; if not __nuppT125 then if __nuppT129>0 then __nuppT14(__nuppT10(__nuppT126,__nuppT128,1),0) else __nuppT14(__nuppT126,0) end end; if __nuppT129>0 then if __nuppT129>1 then __nuppT14(__nuppT10(__nuppT128[1],__nuppT128,2),0) else __nuppT14(__nuppT128[1],0) end end; if __nuppT126=="return" then  return __nuppT15(__nuppT127,1,__nuppT127.n)  end; end
end





local Cached = {} Cached.__index = Cached

function Cached:encode(binding, value) 
return binding : accept ( _G.setmetatable({ scope =  self . scope }, Encode) , value )
end

function Cached:decode(binding, bytes) 
assert ( # bytes <= 16777216 , "binary input exceeds byte limit" )
return binding : accept ( _G.setmetatable({ binding =  binding ,  scope =  self . scope ,  bytes =  bytes }, Decode) , nil )
end

codec=function ( policy ) 
return ( _G.setmetatable({ scope =  _G.setmetatable({ policy =  policy ,  writes =  {} ,  reads =  {} ,  count =  0 ,  active =  0 }, Scope) }, Cached) )
end ;__nuppExports["codec"]=codec
 end);if not __nuppOk then package.loaded["example.binarycodec"]=nil;error(__nuppWhy,0) end;package.loaded["example.binarycodec"]=__nuppExports;return __nuppExports