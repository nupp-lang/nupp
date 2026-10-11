_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.internal.scalar"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local atom;__nuppExports["atom"]=function(...) return atom(...) end;local bigInteger;__nuppExports["bigInteger"]=function(...) return bigInteger(...) end;local boolean;__nuppExports["boolean"]=function(...) return boolean(...) end;local bytes;__nuppExports["bytes"]=function(...) return bytes(...) end;local convert;__nuppExports["convert"]=function(...) return convert(...) end;local decimal;__nuppExports["decimal"]=function(...) return decimal(...) end;local document;__nuppExports["document"]=function(...) return document(...) end;local float;__nuppExports["float"]=function(...) return float(...) end;local integer;__nuppExports["integer"]=function(...) return integer(...) end;local nativeScalar;__nuppExports["nativeScalar"]=function(...) return nativeScalar(...) end;local text;__nuppExports["text"]=function(...) return text(...) end;local timestamp;__nuppExports["timestamp"]=function(...) return timestamp(...) end;

local core = require ( "nupp.serde.internal.value" )

local Description = {} Description.__index = Description









local Text = {} Text.__index = Text

function Text:describe(direction) 
return self . description
end

function Text:write(value, writer) 
writer : writeString ( self . description . member , value : sub ( 1 ) )
end

function Text:read(reader) 
return reader : readString ( self . description . member )
end


local Time = {} Time.__index = Time

function Time:describe(direction) 
return self . description
end

function Time:write(value, writer) 
writer : writeTimestamp ( self . description . member , value )
end

function Time:read(reader) 
return reader : readTimestamp ( self . description . member )
end


text=function ( member ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "string" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) }, Text) )
end ;__nuppExports["text"]=text

timestamp=function ( member ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "timestamp" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) }, Time) )
end ;__nuppExports["timestamp"]=timestamp
















local Converted = {} Converted.__index = Converted


function Converted:describe(direction) 
return self . base : describe ( direction )
end

function Converted:write(value, writer) 
local projected = self . conversion : project ( value )
self . base : write ( projected , writer )
end

function Converted:read(reader) 
return self . conversion : restore ( self . base : read ( reader ) )
end


convert=function (
base ,
conversion
) 
return ( _G.setmetatable({ base =  base ,  conversion =  conversion }, Converted) )
end ;__nuppExports["convert"]=convert

local Boolean = {} Boolean.__index = Boolean

function Boolean:describe(direction) 
return self . description
end

function Boolean:write(value, writer) 
writer : writeBoolean ( self . description . member , value == true )
end

function Boolean:read(reader) 
return reader : readBoolean ( self . description . member )
end

boolean=function ( member ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "boolean" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) }, Boolean) )
end ;__nuppExports["boolean"]=boolean

local Bytes = {} Bytes.__index = Bytes

function Bytes:describe(direction) 
return self . description
end

function Bytes:write(value, writer) 
writer : writeBytes ( self . description . member , value : sub ( 1 ) )
end

function Bytes:read(reader) 
return reader : readBytes ( self . description . member )
end

bytes=function ( member ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "bytes" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) }, Bytes) )
end ;__nuppExports["bytes"]=bytes

local BigInteger = {} BigInteger.__index = BigInteger

function BigInteger:describe(direction) 
return self . description
end

function BigInteger:write(value, writer) 
assert ( value : match ( "^%-?%d+$" ) , "invalid big integer" )
writer : writeBigInteger ( self . description . member , value : sub ( 1 ) )
end

function BigInteger:read(reader) 
return reader : readBigInteger ( self . description . member )
end

bigInteger=function ( member ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "bigInteger" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) }, BigInteger) )
end ;__nuppExports["bigInteger"]=bigInteger

local Decimal = {} Decimal.__index = Decimal

function Decimal:describe(direction) 
return self . description
end

function Decimal:write(value, writer) 
writer : writeDecimal ( self . description . member , value )
end

function Decimal:read(reader) 
return reader : readDecimal ( self . description . member )
end

decimal=function ( member ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "decimal" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) }, Decimal) )
end ;__nuppExports["decimal"]=decimal

local Atom = {} Atom.__index = Atom

function Atom:describe(direction) 
return self . description
end

function Atom:write(value, writer) 
writer : writeAtom ( self . description . member , value )
end

function Atom:read(reader) 
return reader : readAtom ( self . description . member )
end

atom=function ( member ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "atom" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) }, Atom) )
end ;__nuppExports["atom"]=atom

local Integer = {} Integer.__index = Integer



function Integer:describe(direction) 
return self . description
end

function Integer:write(value, writer) 
local numbers = require ( "nupp.serde.internal.numbers" )
writer : writeInteger ( self . description . member , numbers . integer ( value . decimal , self . width , self . signed ) )
end

function Integer:read(reader) 
return reader : readInteger ( self . description . member , self . width , self . signed )
end

integer=function (
member ,
width ,
signed
) 
return ( _G.setmetatable({ description =
_G.setmetatable({ member =  member ,  kind =  "integer" ,  width =  width ,  signed =  signed ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) ,  width =
width ,  signed =
signed }, Integer) )

end ;__nuppExports["integer"]=integer

local Float = {} Float.__index = Float


function Float:describe(direction) 
return self . description
end

function Float:write(value, writer) 
writer : writeFloat ( self . description . member , value * 1 , self . width )
end

function Float:read(reader) 
return reader : readFloat ( self . description . member , self . width )
end

float=function ( member , width ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "float" ,  width =  width ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) ,  width =  width }, Float) )
end ;__nuppExports["float"]=float

local Document = {} Document.__index = Document


function Document:describe(direction) 
return self . description
end

function Document:write(value, writer) 
writer : writeDocument ( self . description . member , value , self . document )
end

function Document:read(reader) 
return reader : readDocument ( self . description . member , self . document )
end

document=function ( member , adapter ) 
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "document" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) ,  document =  adapter }, Document) )
end ;__nuppExports["document"]=document


nativeScalar=function ( adapter ) 
local identity = getmetatable ( adapter )
if identity == Text then
return "string"
elseif identity == Boolean then
return "boolean"
elseif identity == Float and ( adapter ) . width == 64 then
return "number"
end

return nil
end ;__nuppExports["nativeScalar"]=nativeScalar
 end);if not __nuppOk then package.loaded["nupp.serde.internal.scalar"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.scalar"]=__nuppExports;return __nuppExports