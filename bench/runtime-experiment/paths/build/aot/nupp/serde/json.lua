_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT5={}; local function __nuppT2(...) return {n=select("#",...),...} end; local __nuppT6,__nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT3(value) return value end; local function __nuppT4(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT11({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT12(v.primary) for _,reason in __nuppT13(v.suppressed) do text=text.."\ncleanup: "..__nuppT12(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.json"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local codec;__nuppExports["codec"]=function(...) return codec(...) end;local decode;__nuppExports["decode"]=function(...) return decode(...) end;local decodeBuffer;__nuppExports["decodeBuffer"]=function(...) return decodeBuffer(...) end;local decodeDocument;__nuppExports["decodeDocument"]=function(...) return decodeDocument(...) end;local documentPolicy;__nuppExports["documentPolicy"]=function(...) return documentPolicy(...) end;local encode;__nuppExports["encode"]=function(...) return encode(...) end;local encodeDocument;__nuppExports["encodeDocument"]=function(...) return encodeDocument(...) end;local encodeInto;__nuppExports["encodeInto"]=function(...) return encodeInto(...) end;local writeValue;__nuppExports["writeValue"]=function(...) return writeValue(...) end;



































local core = require ( "nupp.serde.internal.value" )
local publication = require ( "nupp.serde.internal.publication" )
local plans = require ( "nupp.serde.internal.json.plan" )
local readers = require ( "nupp.serde.internal.json.reader" )
local writers = require ( "nupp.serde.internal.json.writer" )
local documents = require ( "nupp.serde.internal.json.document" )
local syntax = require ( "nupp.serde.internal.json.syntax" )
local json = require ( "nupp.codec.json" )
local text = require ( "nupp.text" )
local contexts = require ( "nupp.serde.internal.context" )
local errors = require ( "nupp.serde.internal.errors" )
local extensions = require ( "nupp.serde.internal.json.extensions" )
local compiled = require ( "nupp.serde.internal.json.compiled" )
local lowering = require ( "nupp.serde.internal.json.lower" )
local defaults = require ( "nupp.serde.internal.json.defaults" )
local documentValues = require ( "nupp.serde.internal.document" )



const identity = { } ;__nuppExports["identity"]=identity






local Write = {} Write.__index = Write




function Write:writeValue(value, sink) 
local operation = self . operation
local encoding = operation . encoding
if encoding ~= nil then
local ok , problem = pcall (
encoding . write ,
encoding ,
value ,
sink ,
encoding . dynamic and _G.setmetatable({ values =  0 }, lowering.Budget) or nil
)
if not ok then
sink : abort ( )
error ( errors . wrap ( problem , "$" , nil ) , 0 )
end
return
end
do local __nuppT14=0; local  __nuppT20 ; local __nuppT21=false ; local __nuppT15,__nuppT16,__nuppT17=__nuppT7(function() do local __nuppT22= writers . output ( sink , self . factory , operation . policy , operation . plan , self . cache ) ; __nuppT20= __nuppT22 ; __nuppT14=1;  __nuppT21=true;  local writer=__nuppT20;
writer : emit ( self . adapter , value )
do (function(__nuppT23,...)  __nuppT21=false; return __nuppT23:close(...)  end)( writer ) end end; return "normal" end,__nuppT3); local __nuppT18={}; local __nuppT19=0; if __nuppT14>=1 and __nuppT21 then  local __nuppT24,__nuppT25=__nuppT6(__nuppCleanup1,__nuppT20);  if not __nuppT24 then __nuppT19=__nuppT19+1; __nuppT18[__nuppT19]=__nuppT25 end; end; if not __nuppT15 then if __nuppT19>0 then __nuppT8(__nuppT4(__nuppT16,__nuppT18,1),0) else __nuppT8(__nuppT16,0) end end; if __nuppT19>0 then if __nuppT19>1 then __nuppT8(__nuppT4(__nuppT18[1],__nuppT18,2),0) else __nuppT8(__nuppT18[1],0) end end; if __nuppT16=="return" then  return __nuppT9(__nuppT17,1,__nuppT17.n)  end; end
end

function Write:append(value, buffer) 
do local __nuppT27=0; local  __nuppT33 ; local __nuppT34=false ; local __nuppT28,__nuppT29,__nuppT30=__nuppT7(function() do local __nuppT35= json . newWriter ( buffer ) ; __nuppT33= __nuppT35 ; __nuppT27=1;  __nuppT34=true;  local sink=__nuppT33;
self : writeValue ( value , sink )
do (function(__nuppT36,...)  __nuppT34=false; return __nuppT36:close(...)  end)( sink ) end end; return "normal" end,__nuppT3); local __nuppT31={}; local __nuppT32=0; if __nuppT27>=1 and __nuppT34 then  local __nuppT37,__nuppT38=__nuppT6(__nuppCleanup1,__nuppT33);  if not __nuppT37 then __nuppT32=__nuppT32+1; __nuppT31[__nuppT32]=__nuppT38 end; end; if not __nuppT28 then if __nuppT32>0 then __nuppT8(__nuppT4(__nuppT29,__nuppT31,1),0) else __nuppT8(__nuppT29,0) end end; if __nuppT32>0 then if __nuppT32>1 then __nuppT8(__nuppT4(__nuppT31[1],__nuppT31,2),0) else __nuppT8(__nuppT31[1],0) end end; if __nuppT29=="return" then  return __nuppT9(__nuppT30,1,__nuppT30.n)  end; end
end

function Write:encode(value) 
local buffer = text . newBuffer ( )
self : append ( value , buffer )
return buffer : tostring ( )
end

local SelectWrite = {} SelectWrite.__index = SelectWrite



function SelectWrite:apply(adapter, state) 
self . result = _G.setmetatable({ adapter =
adapter ,  factory =
self . factory ,  operation =
self . cache : resolve ( adapter , "write" ) ,  cache =
self . cache }, Write)

end






local Read = {} Read.__index = Read





function Read:readBuffer(input, context) 
local native = self . native
if native ~= nil and native : acceptsBuffer ( input ) then
return native : decodeBuffer ( input )
end

return self : read ( input : tostring ( ) , context )
end

function Read:read(bytes, context) 
local operation = self . operation
local native = self . native
if native ~= nil and native : accepts ( bytes ) then
return native : decode ( bytes )
end
local cursor = syntax . reader ( bytes : sub ( 1 ) )
local source = contexts . builder ( identity , self . factory , context ) : freeze ( )
local reader = readers . input ( cursor , operation . policy , operation . plan , source )
local ok , result = pcall ( self . adapter . read , self . adapter , reader )
reader : expire ( )
if not ok then
error ( errors . wrap ( result , cursor : path ( ) , cursor : offset ( ) ) , 0 )
end
local complete , problem = pcall ( cursor . finish , cursor )
if not complete then
error ( publication . failure ( self . binding , result , problem ) , 0 )
end

return result
end

local SelectRead = {} SelectRead.__index = SelectRead




function SelectRead:apply(adapter, state) 
local operation = self . cache : resolve ( adapter , "read" )
self . result = _G.setmetatable({ binding =
self . binding ,  native =
getmetatable ( self . binding ) == core . Bound and operation . native or nil ,  adapter =
adapter ,  factory =
self . factory ,  operation =
operation }, Read)

end


local function decodeContents (
adapter ,
bytes ,
factory ,
context
) 
local cursor = syntax . reader ( bytes )
local source = contexts . builder ( identity , factory , context ) : freeze ( )
local reader = documents . contents ( cursor , source )
local ok , result = pcall ( adapter . readContents , adapter , reader )
reader : expire ( )
if not ok then
error ( errors . wrap ( result , cursor : path ( ) , cursor : offset ( ) ) , 0 )
end
local complete , problem = pcall ( cursor . finish , cursor )
if not complete then
error ( publication . failure ( adapter , result , problem ) , 0 )
end

return result
end




































local Cached = {} Cached.__index = Cached






function Cached:observeBinding(binding) 
if self . lastReadBinding ~= binding then
self . lastReadBinding , self . lastRead , self . lastWrite = binding , nil , nil
end
end

function Cached:writing(binding) 
self : observeBinding ( binding )
if self . lastWrite == nil then
local consumer = _G.setmetatable({ factory =  self . factory ,  cache =  self . cache }, SelectWrite)
binding : accept ( consumer , nil )
self . lastWrite = assert ( consumer . result , "binding did not supply its adapter" )
end

return self . lastWrite
end

function Cached:encodeDocument(adapter, value) 
return self : encode ( adapter : contents ( ) , value )
end

function Cached:decodeDocument(adapter, bytes, context) 
return decodeContents ( adapter , bytes , self . factory , context )
end

function Cached:writeValue(binding, value, sink) 
self : writing ( binding ) : writeValue ( value , sink )
end

function Cached:encode(binding, value) 
return self : writing ( binding ) : encode ( value )
end

function Cached:encodeInto(binding, value, buffer) 
local selected = self : writing ( binding )
local mark = # buffer
local ok , problem = pcall ( selected . append , selected , value , buffer )
if not ok then

local prefix = buffer : tostring ( ) : sub ( 1 , mark )
buffer : set ( prefix )
error ( problem , 0 )
end
end

function Cached:decode(binding, bytes, context) 
self : observeBinding ( binding )
local selected
if self . lastRead ~= nil then


selected = self . lastRead
else
local consumer = _G.setmetatable({ binding =  binding ,  factory =  self . factory ,  cache =  self . cache }, SelectRead)
binding : accept ( consumer , nil )
selected = assert ( consumer . result , "binding did not supply its adapter" )
self . lastReadBinding , self . lastRead = binding , selected
end

return selected : read ( bytes , context )
end

function Cached:decodeBuffer(binding, input, context) 
self : observeBinding ( binding )
local selected
if self . lastRead ~= nil then


selected = self . lastRead
else
local consumer = _G.setmetatable({ binding =  binding ,  factory =  self . factory ,  cache =  self . cache }, SelectRead)
binding : accept ( consumer , nil )
selected = assert ( consumer . result , "binding did not supply its adapter" )
self . lastReadBinding , self . lastRead = binding , selected
end

return selected : readBuffer ( input , context )
end

function Cached:clear() 
self . cache : clear ( )
self . lastReadBinding , self . lastRead , self . lastWrite = nil , nil , nil
end

function Cached:cachedBindings() 
return self . cache : size ( )
end


















const defaultPolicy = defaults . factory ;__nuppExports["defaultPolicy"]=defaultPolicy























const memberNamePolicy = documentValues . memberNames ;__nuppExports["memberNamePolicy"]=memberNamePolicy










documentPolicy=function ( member , epochTimestamps ) 
return documentValues . policy ( member , epochTimestamps )
end ;__nuppExports["documentPolicy"]=documentPolicy





const FieldName = documents . Name ;__nuppExports["FieldName"]=FieldName





const fieldName = documents . name ;__nuppExports["fieldName"]=fieldName



















codec=function ( policy , capacity ) 
local selected = policy or defaults . factory
return ( _G.setmetatable({ factory =  selected ,  cache =  extensions . scope ( selected , capacity ) ,  lastReadBinding =  nil ,  lastRead =  nil ,  lastWrite =  nil }, Cached) )
end ;__nuppExports["codec"]=codec

local shared = codec ( )

















encode=function ( binding , value ) 
return shared : encode ( binding , value )
end ;__nuppExports["encode"]=encode









encodeInto=function ( binding , value , buffer ) 
shared : encodeInto ( binding , value , buffer )
end ;__nuppExports["encodeInto"]=encodeInto






















decode=function ( binding , bytes , context ) 
return shared : decode ( binding , bytes , context )
end ;__nuppExports["decode"]=decode








decodeBuffer=function ( binding , input , context ) 
return shared : decodeBuffer ( binding , input , context )
end ;__nuppExports["decodeBuffer"]=decodeBuffer























writeValue=function ( binding , value , sink ) 
shared : writeValue ( binding , value , sink )
end ;__nuppExports["writeValue"]=writeValue







encodeDocument=function ( adapter , value ) 
return shared : encodeDocument ( adapter , value )
end ;__nuppExports["encodeDocument"]=encodeDocument









decodeDocument=function ( adapter , bytes , context ) 
return shared : decodeDocument ( adapter , bytes , context )
end ;__nuppExports["decodeDocument"]=decodeDocument
 end);if not __nuppOk then package.loaded["nupp.serde.json"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.json"]=__nuppExports;return __nuppExports