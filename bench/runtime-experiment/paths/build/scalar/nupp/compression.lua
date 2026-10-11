_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT19={}; local function __nuppT16(...) return {n=select("#",...),...} end; local __nuppT20,__nuppT21,__nuppT22,__nuppT23,__nuppT24,__nuppT25,__nuppT26,__nuppT27=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT17(value) return value end; local function __nuppT18(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT25({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT26(v.primary) for _,reason in __nuppT27(v.suppressed) do text=text.."\ncleanup: "..__nuppT26(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppT76;__nuppT76=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppT76=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppDrop2 = function(__nuppV) if __nuppV == nil then return end __nuppT76(__nuppV);  end;local __nuppDrop3 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup2(__nuppV);  end;local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()local format;__nuppExports["format"]=function(...) return format(...) end;local formats;__nuppExports["formats"]=function(...) return formats(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compression\0runtime\0004") };












































local spi = require ( "nupp.spi" )
local target = require ( "nupp.runtime.target" )

const io = require ( "nupp.io" )
const span = require ( "nupp.mem.span" )
const storage = require ( "nupp.runtime.storage" )
const provider = require ( "nupp.compression.spi" )

local DEFAULT_WORKSPACE = 65536
local DEFAULT_MAX_OUTPUT = 67108864
local RATIO_ALLOWANCE = 1024
local MAX_EXACT_INTEGER = 9007199254740991


























































local function positive ( value , fallback , what ) 
local answer = value == nil and fallback or value
if type ( answer ) ~= "number" or answer < 1 or answer > 9007199254740991 or answer ~= math . floor ( answer ) then
error ( "nupp: " .. what .. " must be a positive integer" , 3 )
end

return answer
end

local function settings ( options , what ) 
if options == nil then
return { }
end
if type ( options ) ~= "table" then
error ( "nupp: compression " .. what .. " options must be a table" , 3 )
end

return options
end

local function validProgress ( value , maximum ) 
return type ( value ) == "number" and value >= 0 and value <= maximum and value == math . floor ( value )
end

local function needsOutput ( status , written , capacity ) 
return status ~= 2 or written == capacity
end

local function optionKey ( name ) 
return name == "deflate-raw" and "deflateRaw" or name
end

local function validateKeys ( options , allowed , what ) 
if options == nil then
return
end
for name in pairs ( options ) do
if not allowed [ name ] then
error ( "nupp: unknown " .. what .. " option " .. name , 3 )
end
end
end

local function formatOptions (
settings ,
name ,
kind ,
common
) 
local expected = ( name == "deflate-raw" and "deflateRaw" or name )
local selected
for key , value in pairs ( settings ) do
if not common [ key ] then
if key ~= expected then
error ( "nupp: " .. key .. " " .. kind .. " options cannot configure " .. name , 3 )
elseif type ( value ) ~= "table" then
error ( "nupp: " .. expected .. " " .. kind .. " options must be a table" , 3 )
end
selected = value
end
end

return selected
end

local WRITER_COMMON = { workspaceBytes = true }
local READER_COMMON

= { workspaceBytes = true , maxOutputBytes = true , maxExpansionRatio = true , unbounded = true , }

local function encoderOptions ( settings , name ) 
local options = formatOptions ( settings , name , "writer" , WRITER_COMMON )
if name == "gzip" or name == "zlib" or name == "deflate-raw" then
validateKeys ( options , { level = true } , ( name == "deflate-raw" and "deflateRaw" or name ) .. " writer" )
local level = options ~= nil and options . level or 6
if type ( level ) ~= "number" or level < 0 or level > 9 or level ~= math . floor ( level ) then
error ( "nupp: compression level must be an integer from zero through nine" , 3 )
end
end

return options
end

local function decoderOptions ( settings , name ) 
local options = formatOptions ( settings , name , "reader" , READER_COMMON )
if name == "gzip" then
validateKeys ( options , { concatenatedMembers = true } , "gzip reader" )
local concatenatedMembers = options ~= nil and options . concatenatedMembers or nil
if concatenatedMembers ~= nil and type ( concatenatedMembers ) ~= "boolean" then
error ( "nupp: gzip concatenatedMembers must be a boolean" , 3 )
end
elseif name == "zlib" or name == "deflate-raw" then
validateKeys ( options , { } , ( name == "deflate-raw" and "deflateRaw" or name ) .. " reader" )
end

return options
end

local function closeBoth ( first , second ) 
local firstOk , firstFailure = pcall ( (function(first) local __nuppT12=true;  local __nuppT13=function ( )  do local __nuppT28=0; local  __nuppT34 ; local __nuppT35=false ; local __nuppT29,__nuppT30,__nuppT31=__nuppT21(function() do local __nuppT36= first ; __nuppT34= __nuppT36 ; __nuppT28=1;  __nuppT35=true;  local first=__nuppT34;
do (function(__nuppT37,...)  __nuppT35=false; return __nuppT37:close(...)  end)( first ) end end; return "normal" end,__nuppT17); local __nuppT32={}; local __nuppT33=0; if __nuppT28>=1 and __nuppT35 then  local __nuppT38,__nuppT39=__nuppT20(__nuppCleanup1,__nuppT34);  if not __nuppT38 then __nuppT33=__nuppT33+1; __nuppT32[__nuppT33]=__nuppT39 end; end; if not __nuppT29 then if __nuppT33>0 then __nuppT22(__nuppT18(__nuppT30,__nuppT32,1),0) else __nuppT22(__nuppT30,0) end end; if __nuppT33>0 then if __nuppT33>1 then __nuppT22(__nuppT18(__nuppT32[1],__nuppT32,2),0) else __nuppT22(__nuppT32[1],0) end end; if __nuppT30=="return" then  return __nuppT23(__nuppT31,1,__nuppT31.n)  end; end
end ; local __nuppT14={};  __nuppT14.__nuppRelease=function() if not __nuppT12 then return end; __nuppT12=false;  local __nuppT40={}; local __nuppT41=0;  local __nuppT42,__nuppT43=__nuppT20(__nuppCleanup1,first); if not __nuppT42 then __nuppT41=__nuppT41+1; __nuppT40[__nuppT41]=__nuppT43 end;  if __nuppT41>0 then if __nuppT41>1 then __nuppT22(__nuppT18(__nuppT40[1],__nuppT40,2),0) else __nuppT22(__nuppT40[1],0) end end end;  return _G.setmetatable(__nuppT14,{__call=function(_,...) if not __nuppT12 then __nuppT22("nupp: affine closure was already called or dropped",2) end;  __nuppT12=false; return __nuppT13(...) end}) end)( first ) )
local secondOk , secondFailure = pcall ( (function(second) local __nuppT44=true;  local __nuppT45=function ( )  do local __nuppT48=0; local  __nuppT54 ; local __nuppT55=false ; local __nuppT49,__nuppT50,__nuppT51=__nuppT21(function() do local __nuppT56= second ; __nuppT54= __nuppT56 ; __nuppT48=1;  __nuppT55=true;  local second=__nuppT54;
do (function(__nuppT57,...)  __nuppT55=false; return __nuppT57:close(...)  end)( second ) end end; return "normal" end,__nuppT17); local __nuppT52={}; local __nuppT53=0; if __nuppT48>=1 and __nuppT55 then  local __nuppT58,__nuppT59=__nuppT20(__nuppCleanup1,__nuppT54);  if not __nuppT58 then __nuppT53=__nuppT53+1; __nuppT52[__nuppT53]=__nuppT59 end; end; if not __nuppT49 then if __nuppT53>0 then __nuppT22(__nuppT18(__nuppT50,__nuppT52,1),0) else __nuppT22(__nuppT50,0) end end; if __nuppT53>0 then if __nuppT53>1 then __nuppT22(__nuppT18(__nuppT52[1],__nuppT52,2),0) else __nuppT22(__nuppT52[1],0) end end; if __nuppT50=="return" then  return __nuppT23(__nuppT51,1,__nuppT51.n)  end; end
end ; local __nuppT46={};  __nuppT46.__nuppRelease=function() if not __nuppT44 then return end; __nuppT44=false;  local __nuppT60={}; local __nuppT61=0;  local __nuppT62,__nuppT63=__nuppT20(__nuppCleanup1,second); if not __nuppT62 then __nuppT61=__nuppT61+1; __nuppT60[__nuppT61]=__nuppT63 end;  if __nuppT61>0 then if __nuppT61>1 then __nuppT22(__nuppT18(__nuppT60[1],__nuppT60,2),0) else __nuppT22(__nuppT60[1],0) end end end;  return _G.setmetatable(__nuppT46,{__call=function(_,...) if not __nuppT44 then __nuppT22("nupp: affine closure was already called or dropped",2) end;  __nuppT44=false; return __nuppT45(...) end}) end)( second ) )
if not firstOk then
if not secondOk then
error ( tostring ( firstFailure ) .. " (suppressed 1 cleanup failure)" , 0 )
end
error ( firstFailure , 0 )
elseif not secondOk then
error ( secondFailure , 0 )
end
end

local OwnedPair = {}




local PairOwner = {} PairOwner.__index = PairOwner



function PairOwner:close() 
closeBoth ( self . state , self . destination )
end












local Writer = {} Writer.__index = Writer








function Writer:write(bytes) 
local input = span . fromString ( bytes )
local written , reason = self : writeSpan ( input )
if written == nil or written ~= # bytes then
return false , reason or "compression writer accepted only part of the input"
end

return true , nil
end

function Writer:writeSpan(input) 
local at = 1
while at <= input .count do
local remaining = input : slice ( at , input .count )
do local __nuppT67=0; local  __nuppT73 ; local __nuppT74=false ; local __nuppT68,__nuppT69,__nuppT70=__nuppT21(function() do local __nuppT75= span . writeCarray ( self . output , self . capacity ) ; __nuppT73= __nuppT75 ; __nuppT67=1;  __nuppT74=true;  local output=__nuppT73;
local consumed , written , status , reason = self . state : write ( remaining , output )
do __nuppT74=false; __nuppDrop2( output ) end
if consumed == nil or written == nil or status == nil then
return "return",__nuppT16( nil , reason )
end
if not validProgress ( consumed , remaining .count )
or not validProgress ( written , self . capacity )
or ( status ~= provider . NEED_INPUT and status ~= provider . NEED_OUTPUT )
or ( status == provider . NEED_INPUT and consumed ~= remaining .count )
or not needsOutput ( status , written , self . capacity )
then
return "return",__nuppT16( nil , "compression provider reported invalid progress" )
end
local ok , why = self : drain ( written )
if not ok then
return "return",__nuppT16( nil , why )
end
if consumed == 0 and written == 0 then
return "return",__nuppT16( nil , "compression provider made no progress" )
end
at = at + consumed end; return "normal" end,__nuppT17); local __nuppT71={}; local __nuppT72=0; if __nuppT67>=1 and __nuppT74 then  local __nuppT77,__nuppT78=__nuppT20(__nuppT76,__nuppT73);  if not __nuppT77 then __nuppT72=__nuppT72+1; __nuppT71[__nuppT72]=__nuppT78 end; end; if not __nuppT68 then if __nuppT72>0 then __nuppT22(__nuppT18(__nuppT69,__nuppT71,1),0) else __nuppT22(__nuppT69,0) end end; if __nuppT72>0 then if __nuppT72>1 then __nuppT22(__nuppT18(__nuppT71[1],__nuppT71,2),0) else __nuppT22(__nuppT71[1],0) end end; if __nuppT69=="return" then  return __nuppT23(__nuppT70,1,__nuppT70.n)  end; end
end

return input .count , nil
end

function Writer:flush() 
while true do
do local __nuppT80=0; local  __nuppT86 ; local __nuppT87=false ; local __nuppT81,__nuppT82,__nuppT83=__nuppT21(function() do local __nuppT88= span . writeCarray ( self . output , self . capacity ) ; __nuppT86= __nuppT88 ; __nuppT80=1;  __nuppT87=true;  local output=__nuppT86;
local written , status , reason = self . state : flush ( output )
do __nuppT87=false; __nuppDrop2( output ) end
if written == nil or status == nil then
return "return",__nuppT16( false , reason )
end
if not validProgress ( written , self . capacity )
or ( status ~= provider . NEED_INPUT and status ~= provider . NEED_OUTPUT )
or not needsOutput ( status , written , self . capacity )
then
return "return",__nuppT16( false , "compression provider reported invalid progress" )
end
local ok , why = self : drain ( written )
if not ok then
return "return",__nuppT16( false , why )
end
if status == provider . NEED_INPUT then
return "return",__nuppT16( self . destination : flush ( ) )
end
if written == 0 then
return "return",__nuppT16( false , "compression provider made no flush progress" )
end end; return "normal" end,__nuppT17); local __nuppT84={}; local __nuppT85=0; if __nuppT80>=1 and __nuppT87 then  local __nuppT89,__nuppT90=__nuppT20(__nuppT76,__nuppT86);  if not __nuppT89 then __nuppT85=__nuppT85+1; __nuppT84[__nuppT85]=__nuppT90 end; end; if not __nuppT81 then if __nuppT85>0 then __nuppT22(__nuppT18(__nuppT82,__nuppT84,1),0) else __nuppT22(__nuppT82,0) end end; if __nuppT85>0 then if __nuppT85>1 then __nuppT22(__nuppT18(__nuppT84[1],__nuppT84,2),0) else __nuppT22(__nuppT84[1],0) end end; if __nuppT82=="return" then  return __nuppT23(__nuppT83,1,__nuppT83.n)  end; end
end
end

function Writer:finish() local __nuppT91;
local output , capacity = self . output , self . capacity
do const  __nuppT98= _G.setmetatable({ state =  self . state ,  destination =  self . destination }, PairOwner) ; __nuppT91=__nuppT91 or {} ; local __nuppT99=__nuppT91[1]; if not __nuppT99 then __nuppT99=function(owner) do
while true do
do local __nuppT100=0; local  __nuppT106 ; local __nuppT107=false ; local __nuppT101,__nuppT102,__nuppT103=__nuppT21(function() do local __nuppT108= span . writeCarray ( output , capacity ) ; __nuppT106= __nuppT108 ; __nuppT100=1;  __nuppT107=true;  local writable=__nuppT106;
local written , status , reason = owner . state : finish ( writable )
do __nuppT107=false; __nuppDrop2( writable ) end
if written == nil or status == nil then
return "return",__nuppT16( false , reason )
end
if not ( type ( written ) == "number" and written >= 0 and written <= capacity and written == math . floor ( written ) )
or ( status ~= provider . NEED_OUTPUT and status ~= provider . FINISHED )
or not ( status ~= 2 or written == capacity )
then
return "return",__nuppT16( false , "compression provider reported invalid progress" )
end
if written > 0 then
local bytes = span . fromCarray ( output , written )
local at = 1
while at <= written do
local remaining = bytes : slice ( at , written )
local moved , why = owner . destination : writeSpan ( remaining )
if moved == nil then
return "return",__nuppT16( false , why )
end
if moved < 1 or moved > remaining .count then
return "return",__nuppT16( false , "destination writer made invalid progress" )
end
at = at + moved
end
end
if status == provider . FINISHED then
local ok , why = owner . destination : flush ( )
return "return",__nuppT16( ok , why )
end
if written == 0 then
return "return",__nuppT16( false , "compression provider made no finish progress" )
end end; return "normal" end,__nuppT17); local __nuppT104={}; local __nuppT105=0; if __nuppT100>=1 and __nuppT107 then  local __nuppT109,__nuppT110=__nuppT20(__nuppT76,__nuppT106);  if not __nuppT109 then __nuppT105=__nuppT105+1; __nuppT104[__nuppT105]=__nuppT110 end; end; if not __nuppT101 then if __nuppT105>0 then __nuppT22(__nuppT18(__nuppT102,__nuppT104,1),0) else __nuppT22(__nuppT102,0) end end; if __nuppT105>0 then if __nuppT105>1 then __nuppT22(__nuppT18(__nuppT104[1],__nuppT104,2),0) else __nuppT22(__nuppT104[1],0) end end; if __nuppT102=="return" then  return "return",__nuppT103  end; end
end end; return "normal" end; __nuppT91[1]=__nuppT99 end; const __nuppT93,__nuppT94,__nuppT95=__nuppT21(__nuppT99,__nuppT17,__nuppT98); const __nuppT92=1;
local __nuppT96={}; local __nuppT97=0; if __nuppT92>=1 then  local __nuppT111,__nuppT112=__nuppT20(__nuppCleanup1,__nuppT98);  if not __nuppT111 then __nuppT97=__nuppT97+1; __nuppT96[__nuppT97]=__nuppT112 end; end; if not __nuppT93 then if __nuppT97>0 then __nuppT22(__nuppT18(__nuppT94,__nuppT96,1),0) else __nuppT22(__nuppT94,0) end end; if __nuppT97>0 then if __nuppT97>1 then __nuppT22(__nuppT18(__nuppT96[1],__nuppT96,2),0) else __nuppT22(__nuppT96[1],0) end end; if __nuppT94=="return" then  return __nuppT23(__nuppT95,1,__nuppT95.n)  end; end
end

function Writer:close() 
closeBoth ( self . state , self . destination )
error ( "nupp: compression writer was closed without finish" , 2 )
end



function Writer . drain ( self , count ) 
if count == 0 then
return true , nil
end
local bytes = span . fromCarray ( self . output , count )
local at = 1
while at <= count do
local remaining = bytes : slice ( at , count )
local written , reason = self . destination : writeSpan ( remaining )
if written == nil then
return false , reason
end
if written < 1 or written > remaining .count then
return false , "destination writer made invalid progress"
end
at = at + written
end

return true , nil
end

function Writer . abort ( self ) 
closeBoth ( self . state , self . destination )
end

local function makeWriter (
implementation ,
name ,
destination ,
options
) 
local configured = settings ( options , "writer" )
local capacity = positive ( configured . workspaceBytes , 65536 , "compression workspaceBytes" )
local formatSettings = encoderOptions ( configured , name )
return ( _G.setmetatable({ state =
implementation : createEncoder ( formatSettings ) ,  destination =
destination ,  output =
storage . allocateBytes ( capacity ) ,  capacity =
capacity }, Writer) )

end

local Reader = {} Reader.__index = Reader













function Reader:close() 
closeBoth ( self . state , self . source )
end




function Reader:readSpan(destination) 
local destinationLength
do
local output = destination
destinationLength = output .count
end
if destinationLength < 1 then
error ( "nupp: compression Reader:readSpan destination must be positive" , 2 )
end
if self . ended then
return 0 , nil
end
while true do
if self . streamFinished then
local hasInput , why = self : refill ( )
if hasInput == nil then
return nil , why
elseif hasInput then
return nil , "compressed stream has trailing bytes"
end
self . ended = true
return 0 , nil
end

if self . inputAt > self . inputLength then
local hasInput , why = self : refill ( )
if hasInput == nil then
return nil , why
end
if not hasInput then
local written , status , reason = self . state : finishInput ( destination )
if written == nil or status == nil then
return nil , reason
end
if not validProgress ( written , destinationLength )
or (
status ~= provider . NEED_INPUT
and status ~= provider . NEED_OUTPUT
and status ~= provider . FINISHED
)
or not ( status ~= 2 or written == destinationLength )
then
return nil , "compression provider reported invalid progress"
end
local limitFailure = self : account ( 0 , written )
if limitFailure ~= nil then
return nil , limitFailure
end
if status == provider . NEED_INPUT then
return nil , "compressed stream ended before its trailer"
end
self . streamFinished = status == provider . FINISHED
if written > 0 then
return written , nil
end
if status == provider . NEED_OUTPUT then
return nil , "compression provider made no progress"
end
self . ended = true
return 0 , nil
end
end

local all = span . fromCarray ( self . input , self . inputLength )
local input = all : slice ( self . inputAt , self . inputLength )
local consumed , written , status , reason = self . state : read ( input , destination )
if consumed == nil or written == nil or status == nil then
return nil , reason
end
if not validProgress ( consumed , input .count )
or not validProgress ( written , destinationLength )
or ( status ~= provider . NEED_INPUT and status ~= provider . NEED_OUTPUT and status ~= provider . FINISHED )
or ( status == provider . NEED_INPUT and consumed ~= input .count )
or not ( status ~= 2 or written == destinationLength )
then
return nil , "compression provider reported invalid progress"
end
self . inputAt = self . inputAt + consumed
local limitFailure = self : account ( consumed , written )
if limitFailure ~= nil then
return nil , limitFailure
end
if status == provider . FINISHED then
if self . inputAt <= self . inputLength then
return nil , "compressed stream has trailing bytes"
end
self . streamFinished = true
end
if written > 0 then
return written , nil
end
if consumed == 0 then
return nil , "compression provider made no progress"
end
end
end

function Reader:read(count) 
local wanted = positive ( count , count , "compression Reader:read count" )
local output = storage . allocateBytes ( wanted )
do local __nuppT120=0; local  __nuppT126 ; local __nuppT127=false ; local __nuppT121,__nuppT122,__nuppT123=__nuppT21(function() do local __nuppT128= span . writeCarray ( output , wanted ) ; __nuppT126= __nuppT128 ; __nuppT120=1;  __nuppT127=true;  local writable=__nuppT126;
local written , reason = self : readSpan ( writable )
do __nuppT127=false; __nuppDrop2( writable ) end
if written == nil then
return "return",__nuppT16( nil , reason )
end

return "return",__nuppT16( storage . string ( output , written ) , nil ) end; return "normal" end,__nuppT17); local __nuppT124={}; local __nuppT125=0; if __nuppT120>=1 and __nuppT127 then  local __nuppT129,__nuppT130=__nuppT20(__nuppT76,__nuppT126);  if not __nuppT129 then __nuppT125=__nuppT125+1; __nuppT124[__nuppT125]=__nuppT130 end; end; if not __nuppT121 then if __nuppT125>0 then __nuppT22(__nuppT18(__nuppT122,__nuppT124,1),0) else __nuppT22(__nuppT122,0) end end; if __nuppT125>0 then if __nuppT125>1 then __nuppT22(__nuppT18(__nuppT124[1],__nuppT124,2),0) else __nuppT22(__nuppT124[1],0) end end; if __nuppT122=="return" then  return __nuppT23(__nuppT123,1,__nuppT123.n)  end; end
end

function Reader:readInto(destination, offset, count) 





local from = offset == nil and 0 or offset
if type ( from ) ~= "number" or from < 0 or from > MAX_EXACT_INTEGER or from ~= math . floor ( from ) then
error ( "nupp: compression Reader:readInto offset must be a non-negative integer" , 2 )
end
local wanted = positive ( count , DEFAULT_WORKSPACE , "compression Reader:readInto count" )
do local __nuppT132=0; local  __nuppT138 ; local __nuppT139=false ; local __nuppT133,__nuppT134,__nuppT135=__nuppT21(function() do local __nuppT140= destination : reserveWrite ( from , wanted ) ; __nuppT138= __nuppT140 ; __nuppT132=1;  __nuppT139=true;  local lease=__nuppT138;
local written
local reason
do
do local __nuppT141=0; local  __nuppT147 ; local __nuppT148=false ; local __nuppT142,__nuppT143,__nuppT144=__nuppT21(function() do local __nuppT149= lease : span ( ) ; __nuppT147= __nuppT149 ; __nuppT141=1;  __nuppT148=true;  local output=__nuppT147;
written , reason = self : readSpan ( output )
do __nuppT148=false; __nuppDrop2( output ) end end; return "normal" end,__nuppT17); local __nuppT145={}; local __nuppT146=0; if __nuppT141>=1 and __nuppT148 then  local __nuppT150,__nuppT151=__nuppT20(__nuppT76,__nuppT147);  if not __nuppT150 then __nuppT146=__nuppT146+1; __nuppT145[__nuppT146]=__nuppT151 end; end; if not __nuppT142 then if __nuppT146>0 then __nuppT22(__nuppT18(__nuppT143,__nuppT145,1),0) else __nuppT22(__nuppT143,0) end end; if __nuppT146>0 then if __nuppT146>1 then __nuppT22(__nuppT18(__nuppT145[1],__nuppT145,2),0) else __nuppT22(__nuppT145[1],0) end end; if __nuppT143=="return" then  return "return",__nuppT144  end; end
end
if written == nil then
do __nuppT139=false; __nuppDrop3( lease ) end
return "return",__nuppT16( nil , reason )
end
do (function(__nuppT152,...)  __nuppT139=false; return __nuppT152:commit(...)  end)( lease , written ) end

return "return",__nuppT16( written , nil ) end; return "normal" end,__nuppT17); local __nuppT136={}; local __nuppT137=0; if __nuppT132>=1 and __nuppT139 then  local __nuppT153,__nuppT154=__nuppT20(__nuppCleanup2,__nuppT138);  if not __nuppT153 then __nuppT137=__nuppT137+1; __nuppT136[__nuppT137]=__nuppT154 end; end; if not __nuppT133 then if __nuppT137>0 then __nuppT22(__nuppT18(__nuppT134,__nuppT136,1),0) else __nuppT22(__nuppT134,0) end end; if __nuppT137>0 then if __nuppT137>1 then __nuppT22(__nuppT18(__nuppT136[1],__nuppT136,2),0) else __nuppT22(__nuppT136[1],0) end end; if __nuppT134=="return" then  return __nuppT23(__nuppT135,1,__nuppT135.n)  end; end
end

function Reader:transferTo(destination) 
local output = storage . allocateBytes ( self . capacity )
local total = 0
while true do
do local __nuppT156=0; local  __nuppT162 ; local __nuppT163=false ; local __nuppT157,__nuppT158,__nuppT159=__nuppT21(function() do local __nuppT164= span . writeCarray ( output , self . capacity ) ; __nuppT162= __nuppT164 ; __nuppT156=1;  __nuppT163=true;  local writable=__nuppT162;
local read , reason = self : readSpan ( writable )
do __nuppT163=false; __nuppDrop2( writable ) end
if read == nil then
return "return",__nuppT16( nil , reason )
elseif read == 0 then
return "return",__nuppT16( total , nil )
end
local bytes = span . fromCarray ( output , read )
local at = 1
while at <= read do
local remaining = bytes : slice ( at , read )
local written , why = destination : writeSpan ( remaining )
if written == nil then
return "return",__nuppT16( nil , why )
end
if written < 1 or written > remaining .count then
return "return",__nuppT16( nil , "destination writer made invalid progress" )
end
at = at + written
end
total = total + read end; return "normal" end,__nuppT17); local __nuppT160={}; local __nuppT161=0; if __nuppT156>=1 and __nuppT163 then  local __nuppT165,__nuppT166=__nuppT20(__nuppT76,__nuppT162);  if not __nuppT165 then __nuppT161=__nuppT161+1; __nuppT160[__nuppT161]=__nuppT166 end; end; if not __nuppT157 then if __nuppT161>0 then __nuppT22(__nuppT18(__nuppT158,__nuppT160,1),0) else __nuppT22(__nuppT158,0) end end; if __nuppT161>0 then if __nuppT161>1 then __nuppT22(__nuppT18(__nuppT160[1],__nuppT160,2),0) else __nuppT22(__nuppT160[1],0) end end; if __nuppT158=="return" then  return __nuppT23(__nuppT159,1,__nuppT159.n)  end; end
end
end


function Reader . refill ( self ) 
do local __nuppT168=0; local  __nuppT174 ; local __nuppT175=false ; local __nuppT169,__nuppT170,__nuppT171=__nuppT21(function() do local __nuppT176= span . writeCarray ( self . input , self . capacity ) ; __nuppT174= __nuppT176 ; __nuppT168=1;  __nuppT175=true;  local writable=__nuppT174;
local count , reason = self . source : readSpan ( writable )
do __nuppT175=false; __nuppDrop2( writable ) end
if count == nil then
return "return",__nuppT16( nil , reason )
end
if not validProgress ( count , self . capacity ) then
return "return",__nuppT16( nil , "source reader reported invalid progress" )
end
self . inputAt = 1
self . inputLength = count

return "return",__nuppT16( count > 0 , nil ) end; return "normal" end,__nuppT17); local __nuppT172={}; local __nuppT173=0; if __nuppT168>=1 and __nuppT175 then  local __nuppT177,__nuppT178=__nuppT20(__nuppT76,__nuppT174);  if not __nuppT177 then __nuppT173=__nuppT173+1; __nuppT172[__nuppT173]=__nuppT178 end; end; if not __nuppT169 then if __nuppT173>0 then __nuppT22(__nuppT18(__nuppT170,__nuppT172,1),0) else __nuppT22(__nuppT170,0) end end; if __nuppT173>0 then if __nuppT173>1 then __nuppT22(__nuppT18(__nuppT172[1],__nuppT172,2),0) else __nuppT22(__nuppT172[1],0) end end; if __nuppT170=="return" then  return __nuppT23(__nuppT171,1,__nuppT171.n)  end; end
end

function Reader . account ( self , consumed , written ) 
self . inputTotal = self . inputTotal + consumed
self . outputTotal = self . outputTotal + written
if self . maxOutputBytes ~= nil and self . outputTotal > self . maxOutputBytes then
return "decompressed output exceeds maxOutputBytes"
end
local ratioInput = math . max ( self . inputTotal , 1024 )
if self . maxExpansionRatio ~= nil and self . outputTotal > ratioInput * self . maxExpansionRatio then
return "decompressed output exceeds maxExpansionRatio"
end

return nil
end


local Format = {} Format.__index = Format







function Format:newReader(source, options) 
local configured = settings ( options , "reader" )
local capacity = positive ( configured . workspaceBytes , DEFAULT_WORKSPACE , "compression workspaceBytes" )
if configured . unbounded ~= nil and type ( configured . unbounded ) ~= "boolean" then
error ( "nupp: compression unbounded must be a boolean" , 2 )
end
if configured . unbounded and configured . maxOutputBytes ~= nil then
error ( "nupp: compression ReaderOptions cannot set both unbounded and maxOutputBytes" , 2 )
end
local maximum = configured . unbounded and nil
or positive ( configured . maxOutputBytes , DEFAULT_MAX_OUTPUT , "compression maxOutputBytes" )
local ratio = configured . maxExpansionRatio
if ratio ~= nil and ( type ( ratio ) ~= "number" or ratio <= 0 or ratio >= math . huge or ratio ~= ratio ) then
error ( "nupp: compression maxExpansionRatio must be positive and finite" , 2 )
end
local formatSettings = decoderOptions ( configured , self . name )

return ( _G.setmetatable({ state =
self . implementation : createDecoder ( formatSettings ) ,  source =
source ,  input =
storage . allocateBytes ( capacity ) ,  capacity =
capacity ,  inputAt =
1 ,  inputLength =
0 ,  inputTotal =
0 ,  outputTotal =
0 ,  maxOutputBytes =
maximum ,  maxExpansionRatio =
ratio ,  streamFinished =
false ,  ended =
false }, Reader) )

end



function Format:newWriter(destination, options) 
return makeWriter ( self . implementation , self . name , destination , options )
end



function Format:__nupp_m_653c2662e7337214405d4240a93eac8fa5ea092b1f7c8b474d995d065aa5d3b8(bytes, destination, options) 





do local __nuppT183=0; local  __nuppT189,__nuppT191 ; local __nuppT190=false ; local __nuppT192=false ; local __nuppT184,__nuppT185,__nuppT186=__nuppT21(function() do local __nuppT193= destination : newWriter ( ) ; __nuppT189= __nuppT193 ; __nuppT183=1;  __nuppT190=true;  local sink=__nuppT189;
local __nuppT194= (function(__nuppT195,...)  __nuppT190=false; return __nuppT195(...)  end)( makeWriter , self . implementation , self . name , sink , options ) ; __nuppT191= __nuppT194 ; __nuppT183=2;  __nuppT192=true;  local compressed=__nuppT191;
local written , reason = compressed : writeSpan ( bytes )
if written == nil then
do (function(__nuppT196,...)  __nuppT192=false; return __nuppT196:abort(...)  end)( compressed ) end
error ( reason or "compression failed" , 2 )
end
local ok
ok , reason = (function(__nuppT197,...)  __nuppT192=false; return __nuppT197:finish(...)  end)( compressed )
if not ok then
error ( reason or "compression failed" , 2 )
end end; return "normal" end,__nuppT17); local __nuppT187={}; local __nuppT188=0; if __nuppT183>=2 and __nuppT192 then  local __nuppT198,__nuppT199=__nuppT20(__nuppCleanup1,__nuppT191);  if not __nuppT198 then __nuppT188=__nuppT188+1; __nuppT187[__nuppT188]=__nuppT199 end; end; if __nuppT183>=1 and __nuppT190 then  local __nuppT200,__nuppT201=__nuppT20(__nuppCleanup1,__nuppT189);  if not __nuppT200 then __nuppT188=__nuppT188+1; __nuppT187[__nuppT188]=__nuppT201 end; end; if not __nuppT184 then if __nuppT188>0 then __nuppT22(__nuppT18(__nuppT185,__nuppT187,1),0) else __nuppT22(__nuppT185,0) end end; if __nuppT188>0 then if __nuppT188>1 then __nuppT22(__nuppT18(__nuppT187[1],__nuppT187,2),0) else __nuppT22(__nuppT187[1],0) end end; if __nuppT185=="return" then  return __nuppT23(__nuppT186,1,__nuppT186.n)  end; end
end



function Format:__nupp_m_a4e2ce3e897f4c45c05f8261928347e346407566a071b3bfbf5f8f98bc07b0e4(bytes, destination, options) 
local input = span . fromString ( bytes )
self :__nupp_m_653c2662e7337214405d4240a93eac8fa5ea092b1f7c8b474d995d065aa5d3b8 ( input , destination , options )
end



function Format:__nupp_m_0e3c35e8831e7c8ca090b998d04d2aae1b16be255626b2a57c060d8e836d81fa(bytes, options) 
do local __nuppT204=0; local  __nuppT210 ; local __nuppT211=false ; local __nuppT205,__nuppT206,__nuppT207=__nuppT21(function() do local __nuppT212= io . newBuffer ( ) ; __nuppT210= __nuppT212 ; __nuppT204=1;  __nuppT211=true;  local destination=__nuppT210;
self :__nupp_m_653c2662e7337214405d4240a93eac8fa5ea092b1f7c8b474d995d065aa5d3b8 ( bytes , destination , options )
local answer = destination : getString ( )
do (function(__nuppT213,...)  __nuppT211=false; return __nuppT213:close(...)  end)( destination ) end

return "return",__nuppT16( answer ) end; return "normal" end,__nuppT17); local __nuppT208={}; local __nuppT209=0; if __nuppT204>=1 and __nuppT211 then  local __nuppT214,__nuppT215=__nuppT20(__nuppCleanup1,__nuppT210);  if not __nuppT214 then __nuppT209=__nuppT209+1; __nuppT208[__nuppT209]=__nuppT215 end; end; if not __nuppT205 then if __nuppT209>0 then __nuppT22(__nuppT18(__nuppT206,__nuppT208,1),0) else __nuppT22(__nuppT206,0) end end; if __nuppT209>0 then if __nuppT209>1 then __nuppT22(__nuppT18(__nuppT208[1],__nuppT208,2),0) else __nuppT22(__nuppT208[1],0) end end; if __nuppT206=="return" then  return __nuppT23(__nuppT207,1,__nuppT207.n)  end; end
end



function Format:__nupp_m_75fa7e2a0c4a5ca62321bcc494da060357e10008be907ca6184b1f379d6f15f5(bytes, options) 
local input = span . fromString ( bytes )
return self :__nupp_m_0e3c35e8831e7c8ca090b998d04d2aae1b16be255626b2a57c060d8e836d81fa ( input , options )
end




function Format:__nupp_m_1166f64dd6863f29235530d4693184e3edafc7a955b5cb1739ab5c94bcf45447(bytes, destination, options) 





do local __nuppT218=0; local  __nuppT224,__nuppT226,__nuppT228 ; local __nuppT225=false ; local __nuppT227=false ; local __nuppT229=false ; local __nuppT219,__nuppT220,__nuppT221=__nuppT21(function() do local __nuppT230= io . newStringReader ( storage . string ( bytes : ref ( ) , bytes .count ) ) ; __nuppT224= __nuppT230 ; __nuppT218=1;  __nuppT225=true;  local source=__nuppT224;
local __nuppT231= (function(__nuppT232,...)  __nuppT225=false; return __nuppT232:newReader(...)  end)( self , source , options ) ; __nuppT226= __nuppT231 ; __nuppT218=2;  __nuppT227=true;  local reader=__nuppT226;
local __nuppT233= destination : newWriter ( ) ; __nuppT228= __nuppT233 ; __nuppT218=3;  __nuppT229=true;  local writer=__nuppT228;
local _ , reason = reader : transferTo ( writer )
do (function(__nuppT234,...)  __nuppT227=false; return __nuppT234:close(...)  end)( reader ) end
do (function(__nuppT235,...)  __nuppT229=false; return __nuppT235:close(...)  end)( writer ) end
if reason ~= nil then
error ( reason , 2 )
end end; return "normal" end,__nuppT17); local __nuppT222={}; local __nuppT223=0; if __nuppT218>=3 and __nuppT229 then  local __nuppT236,__nuppT237=__nuppT20(__nuppCleanup1,__nuppT228);  if not __nuppT236 then __nuppT223=__nuppT223+1; __nuppT222[__nuppT223]=__nuppT237 end; end; if __nuppT218>=2 and __nuppT227 then  local __nuppT238,__nuppT239=__nuppT20(__nuppCleanup1,__nuppT226);  if not __nuppT238 then __nuppT223=__nuppT223+1; __nuppT222[__nuppT223]=__nuppT239 end; end; if __nuppT218>=1 and __nuppT225 then  local __nuppT240,__nuppT241=__nuppT20(__nuppCleanup1,__nuppT224);  if not __nuppT240 then __nuppT223=__nuppT223+1; __nuppT222[__nuppT223]=__nuppT241 end; end; if not __nuppT219 then if __nuppT223>0 then __nuppT22(__nuppT18(__nuppT220,__nuppT222,1),0) else __nuppT22(__nuppT220,0) end end; if __nuppT223>0 then if __nuppT223>1 then __nuppT22(__nuppT18(__nuppT222[1],__nuppT222,2),0) else __nuppT22(__nuppT222[1],0) end end; if __nuppT220=="return" then  return __nuppT23(__nuppT221,1,__nuppT221.n)  end; end
end




function Format:__nupp_m_187d179979c1a1ed53a7274d3b61891a368bbe0c6ea4664bcda5690a830e069d(bytes, destination, options) 
local input = span . fromString ( bytes )
self :__nupp_m_1166f64dd6863f29235530d4693184e3edafc7a955b5cb1739ab5c94bcf45447 ( input , destination , options )
end




function Format:__nupp_m_77c0e2cc1a4da2481847de950d462c036d800ff13814a0f339f8841ac2a857d7(bytes, options) 
do local __nuppT244=0; local  __nuppT250 ; local __nuppT251=false ; local __nuppT245,__nuppT246,__nuppT247=__nuppT21(function() do local __nuppT252= io . newBuffer ( ) ; __nuppT250= __nuppT252 ; __nuppT244=1;  __nuppT251=true;  local destination=__nuppT250;
self :__nupp_m_1166f64dd6863f29235530d4693184e3edafc7a955b5cb1739ab5c94bcf45447 ( bytes , destination , options )
local answer = destination : getString ( )
do (function(__nuppT253,...)  __nuppT251=false; return __nuppT253:close(...)  end)( destination ) end

return "return",__nuppT16( answer ) end; return "normal" end,__nuppT17); local __nuppT248={}; local __nuppT249=0; if __nuppT244>=1 and __nuppT251 then  local __nuppT254,__nuppT255=__nuppT20(__nuppCleanup1,__nuppT250);  if not __nuppT254 then __nuppT249=__nuppT249+1; __nuppT248[__nuppT249]=__nuppT255 end; end; if not __nuppT245 then if __nuppT249>0 then __nuppT22(__nuppT18(__nuppT246,__nuppT248,1),0) else __nuppT22(__nuppT246,0) end end; if __nuppT249>0 then if __nuppT249>1 then __nuppT22(__nuppT18(__nuppT248[1],__nuppT248,2),0) else __nuppT22(__nuppT248[1],0) end end; if __nuppT246=="return" then  return __nuppT23(__nuppT247,1,__nuppT247.n)  end; end
end




function Format:__nupp_m_d5be7ea97bfd0d0a588f9451effc0a776910721f8f99bb5fe791b50898e27362(bytes, options) 
local input = span . fromString ( bytes )
return self :__nupp_m_77c0e2cc1a4da2481847de950d462c036d800ff13814a0f339f8841ac2a857d7 ( input , options )
end ;_G.nupp.__reflect.link(Format,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../src/nupp/compression/spi.nupp\0Format\0interface\0module\0001","nupp.compression.spi") }) ;__nuppExports["Format"]=Format


local function validate ( selected ) 
for name , implementation in pairs ( selected . formats ) do
if type ( name ) ~= "string"
or name == ""
or type ( implementation ) ~= "table"
or implementation . name ~= name
or type ( implementation . createEncoder ) ~= "function"
or type ( implementation . createDecoder ) ~= "function"
or WRITER_COMMON [ name ]
or READER_COMMON [ name ]
then
error ( "invalid compression format descriptor " .. tostring ( name ) , 2 )
end
end
end

local __nuppT258;do local __nuppT259,__nuppT260;repeat
const chosen = spi . select ( spi . load ("nupp.compression.spi.Provider") )
if chosen ~= nil then
do  __nuppT258= chosen ;__nuppT259=true;break end
end
assert ( target . host == "native" , "nupp.compression: no implementation is available" )
do  __nuppT258= _G . require ( "nupp.runtime.provider.nativecompression" ) ;__nuppT259=true;break end
 until true; end; local selected = __nuppT258
validate ( selected )
local standard = nil
if target . host == "native" then
standard = _G . require ( "nupp.runtime.provider.nativecompression" )
end
local available = { }
local names = { }
if standard ~= nil then
for name , implementation in pairs ( standard . formats ) do
available [ name ] = _G.setmetatable({ name =  name ,  implementation =  implementation }, Format)
end
end
for name , implementation in pairs ( selected . formats ) do
available [ name ] = _G.setmetatable({ name =  name ,  implementation =  implementation }, Format)
end
for name in pairs ( available ) do
names [ # names + 1 ] = name
end
table . sort ( names )


format=function ( name ) 
local found = available [ name ]
if found == nil then
error ( "unknown compression format " .. name , 2 )
end

return found
end ;__nuppExports["format"]=format


formats=function ( ) 
local result = { }
for index , name in ipairs ( names ) do
result [ index ] = name
end

return result
end ;__nuppExports["formats"]=formats
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Format]="nupp.compression\0Format"; end);if not __nuppOk then package.loaded["nupp.compression"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compression"]=__nuppExports;return __nuppExports