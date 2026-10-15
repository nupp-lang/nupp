_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT20={}; local function __nuppT17(...) return {n=select("#",...),...} end; local __nuppT21,__nuppT22,__nuppT23,__nuppT24,__nuppT25,__nuppT26,__nuppT27,__nuppT28=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT18(value) return value end; local function __nuppT19(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT26({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT27(v.primary) for _,reason in __nuppT28(v.suppressed) do text=text.."\ncleanup: "..__nuppT27(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.native"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local codec;__nuppExports["codec"]=function(...) return codec(...) end;local decode;__nuppExports["decode"]=function(...) return decode(...) end;local decodeDocument;__nuppExports["decodeDocument"]=function(...) return decodeDocument(...) end;local encode;__nuppExports["encode"]=function(...) return encode(...) end;local encodeDocument;__nuppExports["encodeDocument"]=function(...) return encodeDocument(...) end;

































local core = require ( "nupp.serde.internal.value" )
local target = require ( "nupp.runtime.target" )
local publication = require ( "nupp.serde.internal.publication" )
local documents = require ( "nupp.serde.internal.document" )
local bridge = require ( "nupp.serde.internal.native.reader" )
local readers = require ( "nupp.serde.internal.documentreader" )
local writers = require ( "nupp.serde.internal.native.writer" )
local numbers = require ( "nupp.serde.internal.numbers" )
local json = require ( "nupp.codec.json" )
local contexts = require ( "nupp.serde.internal.context" )
local memos = require ( "nupp.serde.internal.memo" )


const identity = { } ;__nuppExports["identity"]=identity

local profile = { }



local header = "NUPP\0LJ\1"
local maxBytes = 16777216
local maxDepth = 128
local maxNodes = 1000000
local materialize
local supported

= {
null = true ,
boolean = true ,
integer = true ,
float = true ,
bigInteger = true ,
decimal = true ,
numberToken = true ,
string = true ,
bytes = true ,
timestamp = true ,
document = true ,
dynamic = true ,
structure = true ,
union = true ,
list = true ,
tuple = true ,
map = true
}

local function runtime ( ) 
assert (
target . host == "native" and rawget ( _G , "__nuppBrowser" ) == nil ,
"native persistence requires a native LuaJIT host"
)
local ok , jit = pcall ( _G . require , "jit" )
assert ( ok and type ( jit ) == "table" , "native persistence requires LuaJIT" )
local loaded , buffer = pcall ( _G . require , "string.buffer" )
assert ( loaded , "native persistence requires LuaJIT string.buffer" )

return buffer
end

local function validate (
description ,
direction ,
seen
) 
if seen [ description ] then
return
end
seen [ description ] = true
assert ( supported [ description . kind ] , "unsupported native persistence kind: " .. description . kind )
assert ( direction ~= "read" or description . canRead , "binding has no construction operation" )
for _ , child in ipairs ( description . children ) do
validate ( child : describe ( direction ) , direction , seen )
end
end

local function selectDecoder (
adapter ,
binding ,
direction
) 
local description = adapter : describe ( direction )
validate ( description , direction , { } )
if direction == "read" then
return bridge . decoderFor ( adapter , description , binding , materialize )
else
return nil
end
end

local Scope = {} Scope.__index = Scope

function Scope:resolve(adapter, binding, direction) 





local found , cached = self . memo : find ( binding , direction )
if found then
return cached
end
local slot = self . memo : start ( binding , direction )
local ok , result = pcall ( selectDecoder , adapter , binding , direction )

return self . memo : finish ( slot , ok , result )
end

function Scope:clear() 
self . memo : clear ( )
end

local Check = {} Check.__index = Check



function Check:apply(adapter, state) 
self . scope : resolve ( adapter , self . binding , self . direction )
end

local Read = {} Read.__index = Read


function Read:apply(adapter, state) 
local selected = assert ( self . scope : resolve ( adapter , self . binding , "read" ) , "missing native decoder" )
return selected
end

local Budget = {} Budget.__index = Budget

function Budget:take(depth) 
self . nodes += 1
assert ( self . nodes <= maxNodes and depth <= maxDepth , "native persistence tree limit exceeded" )
end


local function text ( value ) 
assert ( type ( value ) == "string" , "expected native string" )
return value
end

local function integer ( value ) 
assert ( type ( value ) == "number" , "expected native integer" )
local number = value
assert ( number == number and number % 1 == 0 and math . abs ( number ) <= 9007199254740991 , "invalid native integer" )
return number
end

local function unpack ( value , budget , depth ) 
budget : take ( depth )
assert ( type ( value ) == "table" and getmetatable ( value ) == nil , "expected native node" )
local node = value
local size = # node
for key in pairs ( value ) do
assert (
type ( key ) == "number" and ( key ) >= 1 and ( key ) <= size and ( key ) % 1 == 0 ,
"native node is not a dense array"
)
end
local kind = text ( node [ 1 ] )
if kind == "null" then
assert ( size == 1 , "invalid native null" )
return documents . null ( )
elseif kind == "string" or kind == "bytes" or kind == "numberToken" or kind == "bigInteger" then
assert ( size == 2 , "invalid native scalar" )
local scalar = text ( node [ 2 ] )
if kind == "string" then
return documents . string ( scalar )
elseif kind == "bytes" then
return documents . bytes ( scalar )
elseif kind == "numberToken" then
return documents . numberToken ( scalar )
else
return documents . bigInteger ( scalar )
end
elseif kind == "boolean" then
assert ( size == 2 and type ( node [ 2 ] ) == "boolean" , "invalid native boolean" )
return documents . boolean ( node [ 2 ] )
elseif kind == "integer" then
assert ( size == 4 and type ( node [ 4 ] ) == "boolean" , "invalid native integer" )
local width = integer ( node [ 3 ] )
assert ( width == 8 or width == 16 or width == 32 or width == 64 , "invalid native integer width" )
return documents . integer ( numbers . integer ( text ( node [ 2 ] ) , width , node [ 4 ] ) )
elseif kind == "float" then
assert ( size == 3 and type ( node [ 2 ] ) == "number" , "invalid native float" )
local width = integer ( node [ 3 ] )
assert ( width == 32 or width == 64 , "invalid native float width" )
return documents . float (
_G.setmetatable({ value =
numbers . floating ( node [ 2 ] , width , true ) ,  width =
width }, core.Float)

)
elseif kind == "decimal" then
assert ( size == 3 , "invalid native decimal" )
local coefficient = text ( node [ 2 ] )
documents . bigInteger ( coefficient )
return documents . decimal ( _G.setmetatable({ coefficient =  coefficient ,  exponent =  integer ( node [ 3 ] ) }, core.Decimal) )
elseif kind == "timestamp" then
assert ( size == 3 , "invalid native timestamp" )
local seconds = numbers . integer ( text ( node [ 2 ] ) , 64 , true ) . decimal
return documents . timestamp ( _G.setmetatable({ seconds =  seconds ,  nanos =  integer ( node [ 3 ] ) }, core.Timestamp) )
elseif kind == "document" then
assert ( size == 2 , "invalid native document boundary" )
return documents . document ( unpack ( node [ 2 ] , budget , depth + 1 ) )
elseif kind == "structure" or kind == "union" then
assert ( size % 2 == 1 and ( kind ~= "union" or size == 3 ) , "invalid native named aggregate" )
local fields = { }
for index = 2 , size , 2 do
fields [
# fields + 1
] = _G.setmetatable({ name =  text ( node [ index ] ) ,  value =  unpack ( node [ index + 1 ] , budget , depth + 1 ) }, documents.Entry)
end
if kind == "union" then
return documents . union ( fields [ 1 ] . name , fields [ 1 ] . value )
else
return documents . object ( fields )
end
elseif kind == "list" or kind == "tuple" then
local values = { }
for index = 2 , size do
values [ # values + 1 ] = unpack ( node [ index ] , budget , depth + 1 )
end
return kind == "list" and documents . list ( values ) or documents . tuple ( values )
elseif kind == "map" then
assert ( size % 2 == 1 , "invalid native map" )
local values = { }
for index = 2 , size , 2 do
values [
# values + 1
] = _G.setmetatable({ key =
unpack ( node [ index ] , budget , depth + 1 ) ,  value =
unpack ( node [ index + 1 ] , budget , depth + 1 ) }, documents.MapEntry)

end
return documents . map ( values )
end
error ( "unsupported native value tag: " .. kind , 2 )
end

materialize = function ( value ) 
return unpack ( value , _G.setmetatable({ nodes =  0 }, Budget) , 0 )
end

local function validateTree ( value , budget , depth ) 
budget : take ( depth )
assert ( type ( value ) == "table" and getmetatable ( value ) == nil , "expected native node" )
local node = value
local size = # node
for key in pairs ( value ) do
assert (
type ( key ) == "number" and ( key ) >= 1 and ( key ) <= size and ( key ) % 1 == 0 ,
"native node is not a dense array"
)
end
local kind = text ( node [ 1 ] )
if kind == "structure" or kind == "union" then
assert ( size % 2 == 1 and ( kind ~= "union" or size == 3 ) , "invalid native named aggregate" )
local names = { }
for index = 2 , size , 2 do
local name = text ( node [ index ] )
assert ( not names [ name ] , "duplicate native member" )
names [ name ] = true
validateTree ( node [ index + 1 ] , budget , depth + 1 )
end
elseif kind == "list" or kind == "tuple" then
for index = 2 , size do
validateTree ( node [ index ] , budget , depth + 1 )
end
elseif kind == "map" then
assert ( size % 2 == 1 , "invalid native map" )
for index = 2 , size do
validateTree ( node [ index ] , budget , depth + 1 )
end
elseif kind == "document" then
assert ( size == 2 , "invalid native document boundary" )
validateTree ( node [ 2 ] , budget , depth + 1 )
elseif kind == "null" then
assert ( size == 1 , "invalid native null" )
elseif kind == "string" or kind == "bytes" or kind == "numberToken" or kind == "bigInteger" then
assert ( size == 2 , "invalid native scalar" )
local scalar = text ( node [ 2 ] )
if kind == "numberToken" then
json . numberToken ( scalar )
elseif kind == "bigInteger" then
assert (
scalar : match ( "^-?[0-9]+$" ) and ( scalar == "0" or scalar == "-0" or scalar : match ( "^-?[1-9][0-9]*$" ) ) ,
"invalid big integer"
)
end
elseif kind == "boolean" then
assert ( size == 2 and type ( node [ 2 ] ) == "boolean" , "invalid native boolean" )
elseif kind == "integer" then
assert ( size == 4 and type ( node [ 4 ] ) == "boolean" , "invalid native integer" )
local width = integer ( node [ 3 ] )
assert ( width == 8 or width == 16 or width == 32 or width == 64 , "invalid native integer width" )
numbers . integer ( text ( node [ 2 ] ) , width , node [ 4 ] )
elseif kind == "float" then
assert ( size == 3 and type ( node [ 2 ] ) == "number" , "invalid native float" )
local width = integer ( node [ 3 ] )
assert ( width == 32 or width == 64 , "invalid native float width" )
numbers . floating ( node [ 2 ] , width , true )
elseif kind == "decimal" then
assert ( size == 3 , "invalid native decimal" )
local coefficient = text ( node [ 2 ] )
assert (
coefficient : match ( "^-?[0-9]+$" )
and ( coefficient == "0" or coefficient == "-0" or coefficient : match ( "^-?[1-9][0-9]*$" ) ) ,
"invalid big integer"
)
integer ( node [ 3 ] )
elseif kind == "timestamp" then
assert ( size == 3 , "invalid native timestamp" )
numbers . integer ( text ( node [ 2 ] ) , 64 , true )
local nanos = integer ( node [ 3 ] )
assert ( nanos >= 0 and nanos < 1000000000 , "invalid timestamp nanos" )
else
error ( "unsupported native value tag: " .. kind , 2 )
end
end

local function encodeValue ( binding , value , scope ) 
local buffer = runtime ( )
binding : accept ( _G.setmetatable({ binding =  binding ,  direction =  "write" ,  scope =  scope }, Check) , nil )
local tree = writers . value ( binding , value )
local result = "NUPP\0LJ\1" .. ( buffer . encode ( tree ) )
assert ( # result <= 16777216 , "native persistence output exceeds byte limit" )

return result
end

local function decodeValue ( binding , bytes , scope ) 
local buffer = runtime ( )
local selected = binding : accept ( _G.setmetatable({ binding =  binding ,  scope =  scope }, Read) , nil )
assert ( # bytes <= 16777216 and bytes : sub ( 1 , 8 ) == "NUPP\0LJ\1" , "unsupported native persistence frame" )
local value = buffer . decode ( bytes : sub ( 9 ) )
validateTree ( value , _G.setmetatable({ nodes =  0 }, Budget) , 0 )

return selected : read ( value , contexts . builder ( identity , profile ) : freeze ( ) )
end

local function decodeContents ( adapter , bytes ) local __nuppT16;
local buffer = runtime ( )
assert ( # bytes <= 16777216 and bytes : sub ( 1 , 8 ) == "NUPP\0LJ\1" , "unsupported native persistence frame" )
local value = documents . withContext (
unpack ( buffer . decode ( bytes : sub ( 9 ) ) , _G.setmetatable({ nodes =  0 }, Budget) , 0 ) ,
contexts . builder ( identity , profile ) : freeze ( )
)
do const  __nuppT35= readers . reader ( value ) ; __nuppT16=__nuppT16 or {} ; local __nuppT36=__nuppT16[1]; if not __nuppT36 then __nuppT36=function(reader) do
local result = adapter : readContents ( reader )
local complete , problem = pcall ( reader . finish , reader )
if not complete then
error ( publication . failure ( adapter , result , problem ) , 0 )
end

return "return",__nuppT17( result ) end; return "normal" end; __nuppT16[1]=__nuppT36 end; const __nuppT30,__nuppT31,__nuppT32=__nuppT22(__nuppT36,__nuppT18,__nuppT35); const __nuppT29=1; local __nuppT33={}; local __nuppT34=0; if __nuppT29>=1 then  local __nuppT37,__nuppT38=__nuppT21(__nuppCleanup1,__nuppT35);  if not __nuppT37 then __nuppT34=__nuppT34+1; __nuppT33[__nuppT34]=__nuppT38 end; end; if not __nuppT30 then if __nuppT34>0 then __nuppT23(__nuppT19(__nuppT31,__nuppT33,1),0) else __nuppT23(__nuppT31,0) end end; if __nuppT34>0 then if __nuppT34>1 then __nuppT23(__nuppT19(__nuppT33[1],__nuppT33,2),0) else __nuppT23(__nuppT33[1],0) end end; if __nuppT31=="return" then  return __nuppT24(__nuppT32,1,__nuppT32.n)  end; end
end






















local Cached = {} Cached.__index = Cached

function Cached:encode(binding, value) 
return encodeValue ( binding , value , self . scope )
end

function Cached:decode(binding, bytes) 
return decodeValue ( binding , bytes , self . scope )
end

function Cached:encodeDocument(adapter, value) 
return encodeValue ( adapter : contents ( ) , value , self . scope )
end

function Cached:decodeDocument(adapter, bytes) 
return decodeContents ( adapter , bytes )
end

function Cached:clear() 
self . scope : clear ( )
end

function Cached:cachedBindings() 
return self . scope . memo : size ( )
end








codec=function ( capacity ) 
runtime ( )
return ( _G.setmetatable({ scope =  _G.setmetatable({ memo =  memos . new ( "native extension" , capacity ) }, Scope) }, Cached) )
end ;__nuppExports["codec"]=codec

local defaultCodec = _G.setmetatable({ scope =  _G.setmetatable({ memo =  memos . new ( "native extension" , 256 ) }, Scope) }, Cached)







encode=function ( binding , value ) 
return defaultCodec : encode ( binding , value )
end ;__nuppExports["encode"]=encode








decode=function ( binding , bytes ) 
return defaultCodec : decode ( binding , bytes )
end ;__nuppExports["decode"]=decode














encodeDocument=function ( adapter , value ) 
return defaultCodec : encodeDocument ( adapter , value )
end ;__nuppExports["encodeDocument"]=encodeDocument







decodeDocument=function ( adapter , bytes ) 
return defaultCodec : decodeDocument ( adapter , bytes )
end ;__nuppExports["decodeDocument"]=decodeDocument
 end);if not __nuppOk then package.loaded["nupp.serde.native"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.native"]=__nuppExports;return __nuppExports