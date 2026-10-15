_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["example.xmlcodec"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local codec;__nuppExports["codec"]=function(...) return codec(...) end;

local __serdeJson = require ( "nupp.serde.json" )

local core = require ( "nupp.serde" )
local publication = require ( "nupp.serde.codec" )
local syntax = require ( "example.xmlsyntax" )
local assembly = require ( "example.xmlassembly" )
local numbers = require ( "nupp.serde.codec" )
local documents = require ( "nupp.serde.document" )
local documentReaders = require ( "nupp.serde.document" )
local bridge = require ( "nupp.serde.document" )
local contexts = require ( "nupp.serde.codec" )
local utf8 = require ( "nupp.text.utf8" )





local family = { }
local supported = { string = true , boolean = true , integer = true , structure = true , list = true }

local function identity ( field ) 
return field . role .. ":" .. # field . namespaceUri .. ":" .. field . namespaceUri .. field . localName
end

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
assert ( not description . nullable , "XML fixture has no null representation" )
assert ( direction ~= "read" or description . canRead , "binding has no construction operation" )
local kind = description . kind
assert ( supported [ kind ] , "unsupported XML fixture kind: " .. kind )
local field = policy : field ( description . member )
assert ( field . localName : match ( "^[A-Za-z_][A-Za-z0-9_.-]*$" ) ~= nil , "invalid XML local name" )
local flattened = policy : flattened ( description . member )
assert ( not flattened or kind == "list" , "only XML lists can be flattened" )
assert (
field . role ~= "attribute" or kind == "string" or kind == "boolean" or kind == "integer" ,
"XML attribute must be scalar"
)
local result = _G.setmetatable({ description =  description ,  field =  field ,  flattened =  flattened ,  children =  {} ,  ordered =  {} ,  mappings =  {} }, Plan)
seen [ description ] = result
local names = { }
for index , child in ipairs ( description . children ) do
local selected = plan ( child : describe ( direction ) , policy , direction , seen )
result . children [ child . member ] = selected
result . ordered [ index ] = selected
if kind == "structure" then
local key = identity ( selected . field )
assert ( not names [ key ] , "colliding expanded XML field" )
names [ key ] = true
result . mappings [
index
] = _G.setmetatable({ member =  child . member ,  field =  selected . field ,  repeated =  selected . flattened }, assembly.Mapping)
else
assert (
kind == "list" and index == 1 and selected . field . role == "element" ,
"XML list requires one element binding"
)
end
end
if kind == "list" then
assert ( # result . ordered == 1 , "XML list requires an element binding" )
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
error ( "recursive XML extension initialization" , 2 )
end
end
assert ( self . count < 256 , "XML fixture extension cache is full" )
local slot = _G.setmetatable({ state =  "initializing" }, Slot)
cache [ adapter ] = slot
self . count += 1
self . active += 1
local ok , selected = pcall ( function ( ) 
local description = adapter : describe ( direction )
assert ( description . kind == "structure" , "XML fixture root must be a structure" )
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
return ( _G.setmetatable({ family =  family ,  node =  assembly . copy ( self . node ) }, Opaque) )
end

local Unknown = {} Unknown.__index = Unknown




function Unknown:live() 
assert ( not self . closed and not self . used , "XML unknown reader has expired" )
end

function Unknown:skipValue() 
self : live ( )
self . used = true
end

function Unknown:captureValue(adapter) local __nuppT8;
self : live ( )
local value = documents . withContext (
documents . atom ( _G.setmetatable({ family =  family ,  node =  assembly . copy ( self . node ) }, Opaque) ) ,
self . source
)
do const  __nuppT27= documentReaders . reader ( value ) ; __nuppT8=__nuppT8 or {} ; local __nuppT28=__nuppT8[1]; if not __nuppT28 then __nuppT28=function(reader) do
local result = adapter : readContents ( reader )
local complete , problem = pcall ( reader . finish , reader )
if not complete then
error ( publication . discardFailed ( adapter , result , problem ) , 0 )
end
self . used = true

return "return",__nuppT9( result ) end; return "normal" end; __nuppT8[1]=__nuppT28 end; const __nuppT22,__nuppT23,__nuppT24=__nuppT14(__nuppT28,__nuppT10,__nuppT27); const __nuppT21=1; local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 then  local __nuppT29,__nuppT30=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT29 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT30 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end

function Unknown:close() 
self . closed = true
end

local Group = {} Group.__index = Group



local Collect = {} Collect.__index = Collect
function Collect:apply(state, member, values) 
local owned = { }
for _ , node in ipairs ( values ) do
owned [ # owned + 1 ] = assembly . copy ( node )
end
state [ # state + 1 ] = _G.setmetatable({ member =  member ,  values =  owned }, Group)
end

function Collect:unknown(state, value) 
state [ # state + 1 ] = _G.setmetatable({ values =  { value } }, Group)
end

local Input = {} Input.__index = Input






function Input:live() 
assert ( not self . closed and not self . used , "XML reader has expired" )
assert ( self . depth <= 128 , "XML nesting limit exceeded" )
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
"XML adapter does not match its description"
)
self . used = true
end

function Input:readString(member) 
self : consume ( member , "string" )
return assembly . text ( self . value )
end

function Input:readBytes(member) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readInteger(member, width, signed) 
self : consume ( member , "integer" )
assert (
width == self . selected . description . width and signed == self . selected . description . signed ,
"integer access does not match its schema"
)

return numbers . integer ( assembly . text ( self . value ) , width , signed )
end

function Input:child(selected, value) 
return ( _G.setmetatable({ selected =  selected ,  value =  value ,  source =  self . source ,  depth =  self . depth + 1 ,  used =  false ,  closed =  false }, Input) )
end

function Input:readStruct(member, state, consume, unknown) 






self : consume ( member , "structure" )
local groups = { }
assembly . read ( self . value , self . selected . mappings , groups , _G.setmetatable({ }, Collect) )
for _ , group in ipairs ( groups ) do
local selected = group . member ~= nil and self . selected . children [ group . member ] or nil
local node = group . values [ 1 ]
if selected ~= nil then
if selected . flattened then
local content = { }
for _ , value in ipairs ( group . values ) do
content [ # content + 1 ] = value
end
node = _G.setmetatable({ field =  selected . field ,  attributes =  { } ,  content =  content }, assembly.Node)
end
do local __nuppT43=0; local  __nuppT49 ; local __nuppT44,__nuppT45,__nuppT46=__nuppT14(function() do local __nuppT50= self : child ( selected , node ) ; __nuppT49= __nuppT50 ; __nuppT43=1;  local reader=__nuppT49;
consume : apply ( state , selected . description . member , reader )
assert ( reader . used , "XML member was not consumed" ) end; return "normal" end,__nuppT10); local __nuppT47={}; local __nuppT48=0; if __nuppT43>=1 then  local __nuppT51,__nuppT52=__nuppT13(__nuppCleanup1,__nuppT49);  if not __nuppT51 then __nuppT48=__nuppT48+1; __nuppT47[__nuppT48]=__nuppT52 end; end; if not __nuppT44 then if __nuppT48>0 then __nuppT15(__nuppT11(__nuppT45,__nuppT47,1),0) else __nuppT15(__nuppT45,0) end end; if __nuppT48>0 then if __nuppT48>1 then __nuppT15(__nuppT11(__nuppT47[1],__nuppT47,2),0) else __nuppT15(__nuppT47[1],0) end end; if __nuppT45=="return" then  return __nuppT16(__nuppT46,1,__nuppT46.n)  end; end
else
do local __nuppT53=0; local  __nuppT59 ; local __nuppT54,__nuppT55,__nuppT56=__nuppT14(function() do local __nuppT60= _G.setmetatable({ node =  node ,  source =  self . source ,  used =  false ,  closed =  false }, Unknown) ; __nuppT59= __nuppT60 ; __nuppT53=1;  local reader=__nuppT59;
unknown : apply ( state , node . field , reader )
assert ( reader . used , "unknown XML field was not consumed" ) end; return "normal" end,__nuppT10); local __nuppT57={}; local __nuppT58=0; if __nuppT53>=1 then  local __nuppT61,__nuppT62=__nuppT13(__nuppCleanup1,__nuppT59);  if not __nuppT61 then __nuppT58=__nuppT58+1; __nuppT57[__nuppT58]=__nuppT62 end; end; if not __nuppT54 then if __nuppT58>0 then __nuppT15(__nuppT11(__nuppT55,__nuppT57,1),0) else __nuppT15(__nuppT55,0) end end; if __nuppT58>0 then if __nuppT58>1 then __nuppT15(__nuppT11(__nuppT57[1],__nuppT57,2),0) else __nuppT15(__nuppT57[1],0) end end; if __nuppT55=="return" then  return __nuppT16(__nuppT56,1,__nuppT56.n)  end; end
end
end
end

function Input:readTuple(member, size, state, consume) 






error ( "unsupported XML fixture operation" , 2 )
end

function Input:containerSize() 
self : live ( )
return nil
end

function Input:close() 
self . closed = true
end

function Input:readNull(member) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readBoolean(member) 
self : consume ( member , "boolean" )
local text = assembly . text ( self . value )
assert ( text == "true" or text == "false" , "invalid XML boolean" )
return text == "true"
end

function Input:readFloat(member, width) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readBigInteger(member) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readDecimal(member) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readNumberToken(member) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readTimestamp(member) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readAtom(member) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readDocument(member, adapter) 
error ( "unsupported XML fixture operation" , 2 )
end

function Input:readUnion(member, state, consume, unknown) 






error ( "unsupported XML fixture operation" , 2 )
end

function Input:readList(member, state, consume) local __nuppT76;
self : consume ( member , "list" )
assert ( # self . value . attributes == 0 , "XML list has attributes" )
local selected = self . selected . ordered [ 1 ]
local index = 0
for _ , item in ipairs ( self . value . content ) do
if type ( item ) == "string" then
assert ( ( item ) : match ( "^%s*$" ) ~= nil , "XML list has mixed content" )
else
local node = item
assert (
self . selected . flattened or identity ( node . field ) == identity ( selected . field ) ,
"unexpected XML list element"
)
index += 1
do const  __nuppT83= self : child ( selected , node ) ; __nuppT76=__nuppT76 or {} ; local __nuppT84=__nuppT76[2]; if not __nuppT84 then __nuppT84=function(input) do
consume : apply ( state , index , input )
assert ( input . used , "XML list item was not consumed" ) end; return "normal" end; __nuppT76[2]=__nuppT84 end; const __nuppT78,__nuppT79,__nuppT80=__nuppT14(__nuppT84,__nuppT10,__nuppT83); const __nuppT77=1; local __nuppT81={}; local __nuppT82=0; if __nuppT77>=1 then  local __nuppT85,__nuppT86=__nuppT13(__nuppCleanup1,__nuppT83);  if not __nuppT85 then __nuppT82=__nuppT82+1; __nuppT81[__nuppT82]=__nuppT86 end; end; if not __nuppT78 then if __nuppT82>0 then __nuppT15(__nuppT11(__nuppT79,__nuppT81,1),0) else __nuppT15(__nuppT79,0) end end; if __nuppT82>0 then if __nuppT82>1 then __nuppT15(__nuppT11(__nuppT81[1],__nuppT81,2),0) else __nuppT15(__nuppT81[1],0) end end; if __nuppT79=="return" then  return __nuppT16(__nuppT80,1,__nuppT80.n)  end; end
end
end
end

function Input:readMap(member, state, consume) 
error ( "unsupported XML fixture operation" , 2 )
end


local Frame = {} Frame.__index = Frame




local Output = {} Output.__index = Output





function Output:live() 
assert ( not self . closed , "XML writer has expired" )
assert ( # self . frames <= 128 , "XML nesting limit exceeded" )
end

function Output:selected(member) 
self : live ( )
local frame = self . frames [ # self . frames ]
if frame == nil then
assert ( self . root . description . member == member , "foreign XML root member" )
return self . root
end

return assert ( frame . selected . children [ member ] , "foreign XML member" )
end

function Output:include(member) 
self : selected ( member )
return true
end

function Output:put(member, kind, value) 
local selected = self : selected ( member )
assert ( selected . description . kind == kind , "XML adapter does not match its description" )
local frame = assert ( self . frames [ # self . frames ] , "scalar XML root is unsupported" )
if frame . selected . description . kind == "structure" then
assert ( not frame . seen [ member ] , "duplicate XML member" )
frame . seen [ member ] = true
end
if selected . field . role == "attribute" then
frame . node . attributes [
# frame . node . attributes + 1
] = _G.setmetatable({ field =  selected . field ,  value =  assembly . text ( value ) }, syntax.Attribute)
elseif selected . flattened then
for _ , item in ipairs ( value . content ) do
assert ( type ( item ) ~= "string" , "invalid flattened XML content" )
local node = item
frame . node . content [
# frame . node . content + 1
] = _G.setmetatable({ field =  selected . field ,  attributes =  node . attributes ,  content =  node . content }, assembly.Node)
end
else
frame . node . content [ # frame . node . content + 1 ] = value
end
end

function Output:scalar(member, kind, value) 
self : put (
member ,
kind ,
_G.setmetatable({ field =  self : selected ( member ) . field ,  attributes =  { } ,  content =  { value } }, assembly.Node)
)
end

function Output:writeString(member, value) 
assert ( utf8 . isValid ( value ) , "invalid UTF-8 string" )
self : scalar ( member , "string" , value )
end

function Output:writeBytes(member, value) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeInteger(member, value) 
local selected = self : selected ( member )
self : scalar (
member ,
"integer" ,
numbers . integer (
value . decimal ,
selected . description . width ,
selected . description . signed == true
) . decimal
)
end

function Output:aggregate(member, kind, source, emit) 
local selected = self : selected ( member )
assert ( selected . description . kind == kind , "XML aggregate does not match its description" )
local node = _G.setmetatable({ field =  selected . field ,  attributes =  { } ,  content =  { } }, assembly.Node)
self . frames [ # self . frames + 1 ] = _G.setmetatable({ selected =  selected ,  node =  node ,  seen =  {} }, Frame)
emit : apply ( source , self )
self . frames [ # self . frames ] = nil
if # self . frames == 0 then
assert ( self . result == nil , "XML root was written twice" )
self . result = node
else
self : put ( member , kind , node )
end
end

function Output:writeStruct(member, source, emit) 
self : aggregate ( member , "structure" , source , emit )
end

function Output:writeTuple(member, size, source, emit) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeUnknown(field, value, adapter) 





self : live ( )
local selected = syntax . identity ( field )
local frame = assert ( self . frames [ # self . frames ] , "unknown XML field outside structure" )
assert ( frame . selected . description . kind == "structure" , "unknown XML field outside structure" )
for _ , mapping in ipairs ( frame . selected . mappings ) do
assert ( identity ( mapping . field ) ~= ( selected . role .. ":" .. # selected . namespaceUri .. ":" .. selected . namespaceUri .. selected . localName ) , "unknown XML field collides with a known member" )
end
local source = adapter : context ( value )
assert (
source ~= nil and source . codec == family and source . profile == self . policy ,
"unknown XML value needs its original protocol context"
)
local captured = bridge . from ( adapter : contents ( ) , value )
local atom = captured : atom ( )
assert ( getmetatable ( atom ) == Opaque and atom . family == family , "unknown XML value is not an owned subtree" )
local node = assembly . copy ( ( atom ) . node )
assert ( identity ( node . field ) == ( selected . role .. ":" .. # selected . namespaceUri .. ":" .. selected . namespaceUri .. selected . localName ) , "unknown XML identity changed" )
if selected . role == "attribute" then
frame . node . attributes [
# frame . node . attributes + 1
] = _G.setmetatable({ field =  selected ,  value =  assembly . text ( node ) }, syntax.Attribute)
else
frame . node . content [ # frame . node . content + 1 ] = node
end
end

function Output:close() 
self . closed = true
end

function Output:writeNull(member) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeBoolean(member, value) 
self : scalar ( member , "boolean" , value and "true" or "false" )
end

function Output:writeFloat(member, value, width) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeNumberToken(member, value) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeBigInteger(member, value) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeDecimal(member, value) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeTimestamp(member, value) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeAtom(member, value) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeDocument(member, value, adapter) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeUnion(member, source, emit) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeList(member, size, source, emit) 
self : aggregate ( member , "list" , source , emit )
end

function Output:writeMap(member, size, source, emit) 
error ( "unsupported XML fixture operation" , 2 )
end

function Output:writeEntry(key, keyEmit, value, valueEmit) 






error ( "unsupported XML fixture operation" , 2 )
end


local function output ( selected , policy ) 
return ( _G.setmetatable({ root =  selected ,  policy =  policy ,  frames =  {} ,  closed =  false }, Output) )
end

local function input ( selected , bytes , source ) 
local node = assembly . parse ( bytes )
assert ( identity ( node . field ) == identity ( selected . field ) , "unexpected XML root" )
return ( _G.setmetatable({ selected =  selected ,  value =  node ,  source =  source ,  depth =  0 ,  used =  false ,  closed =  false }, Input) )
end

local Encode = {} Encode.__index = Encode

function Encode:apply(adapter, value) local __nuppT116;
local selected = self . scope : resolve ( adapter , "write" )
do const  __nuppT123= output ( selected , self . scope . policy ) ; __nuppT116=__nuppT116 or {} ; local __nuppT124=__nuppT116[3]; if not __nuppT124 then __nuppT124=function(writer) do
adapter : write ( value , writer )
local result = assembly . encode ( assert ( writer . result , "XML binding did not write its root" ) )
assert ( # result <= 16777216 , "XML output exceeds byte limit" )

return "return",__nuppT9( result ) end; return "normal" end; __nuppT116[3]=__nuppT124 end; const __nuppT118,__nuppT119,__nuppT120=__nuppT14(__nuppT124,__nuppT10,__nuppT123); const __nuppT117=1; local __nuppT121={}; local __nuppT122=0; if __nuppT117>=1 then  local __nuppT125,__nuppT126=__nuppT13(__nuppCleanup1,__nuppT123);  if not __nuppT125 then __nuppT122=__nuppT122+1; __nuppT121[__nuppT122]=__nuppT126 end; end; if not __nuppT118 then if __nuppT122>0 then __nuppT15(__nuppT11(__nuppT119,__nuppT121,1),0) else __nuppT15(__nuppT119,0) end end; if __nuppT122>0 then if __nuppT122>1 then __nuppT15(__nuppT11(__nuppT121[1],__nuppT121,2),0) else __nuppT15(__nuppT121[1],0) end end; if __nuppT119=="return" then  return __nuppT16(__nuppT120,1,__nuppT120.n)  end; end
end

local Decode = {} Decode.__index = Decode



function Decode:apply(adapter, state) local __nuppT127;
local selected = self . scope : resolve ( adapter , "read" )
local source = contexts . contextBuilder ( family , self . scope . policy ) : freeze ( )
do const  __nuppT134= input ( selected , self . bytes , source ) ; __nuppT127=__nuppT127 or {} ; local __nuppT135=__nuppT127[4]; if not __nuppT135 then __nuppT135=function(reader) do
local value = adapter : read ( reader )
if not reader . used then
error ( publication . discardFailed ( self . binding , value , "XML binding did not consume its root" ) , 0 )
end

return "return",__nuppT9( value ) end; return "normal" end; __nuppT127[4]=__nuppT135 end; const __nuppT129,__nuppT130,__nuppT131=__nuppT14(__nuppT135,__nuppT10,__nuppT134); const __nuppT128=1; local __nuppT132={}; local __nuppT133=0; if __nuppT128>=1 then  local __nuppT136,__nuppT137=__nuppT13(__nuppCleanup1,__nuppT134);  if not __nuppT136 then __nuppT133=__nuppT133+1; __nuppT132[__nuppT133]=__nuppT137 end; end; if not __nuppT129 then if __nuppT133>0 then __nuppT15(__nuppT11(__nuppT130,__nuppT132,1),0) else __nuppT15(__nuppT130,0) end end; if __nuppT133>0 then if __nuppT133>1 then __nuppT15(__nuppT11(__nuppT132[1],__nuppT132,2),0) else __nuppT15(__nuppT132[1],0) end end; if __nuppT130=="return" then  return __nuppT16(__nuppT131,1,__nuppT131.n)  end; end
end





local Cached = {} Cached.__index = Cached

function Cached:encode(binding, value) 
return binding : accept ( _G.setmetatable({ scope =  self . scope }, Encode) , value )
end

function Cached:decode(binding, bytes) 
assert ( # bytes <= 16777216 , "XML input exceeds byte limit" )
return binding : accept ( _G.setmetatable({ binding =  binding ,  scope =  self . scope ,  bytes =  bytes }, Decode) , nil )
end

codec=function ( policy ) 
return ( _G.setmetatable({ scope =  _G.setmetatable({ policy =  policy ,  writes =  {} ,  reads =  {} ,  count =  0 ,  active =  0 }, Scope) }, Cached) )
end ;__nuppExports["codec"]=codec
 end);if not __nuppOk then package.loaded["example.xmlcodec"]=nil;error(__nuppWhy,0) end;package.loaded["example.xmlcodec"]=__nuppExports;return __nuppExports