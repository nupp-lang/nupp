_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppModule = require("nupp.mem.indexed"); local __nuppT31={}; local function __nuppT28(...) return {n=select("#",...),...} end; local __nuppT32,__nuppT33,__nuppT34,__nuppT35,__nuppT36,__nuppT37,__nuppT38,__nuppT39=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT29(value) return value end; local function __nuppT30(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT37({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT38(v.primary) for _,reason in __nuppT39(v.suppressed) do text=text.."\ncleanup: "..__nuppT38(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.io.tls\0runtime\0001") };











































local spi = require ( "nupp.spi" )
local target = require ( "nupp.runtime.target" )

const io = require ( "nupp.io" )




local net = require ( "nupp.io.net" )
local takeStreamHandle = require ( "nupp.io.net.internal" ) . takeStreamHandle
local suspension = require ( "nupp.suspension" )
local span = require ( "nupp.mem.span" )
local physical = require ( "nupp.runtime.storage" )
local spanStringValue = physical . string

const contract = require ( "nupp.io.tls.spi" )
local __nuppT2;do local __nuppT3,__nuppT4;repeat
const chosen = spi . select ( spi . load ("nupp.io.tls.spi.Provider") )
if chosen ~= nil then
do  __nuppT2= chosen ;__nuppT3=true;break end
end
assert ( target . host == "native" , "nupp.io.tls: no implementation is available" )
do  __nuppT2= _G . require ( "nupp.runtime.provider.nativetls" ) ;__nuppT3=true;break end
 until true; end; local provider = __nuppT2
local tls = { }
const shared = require ( "nupp.io.tls.types" )









const READ_SIZE = 65536


local function positive ( value , what , level ) 
if value < 1 or math . floor ( value ) ~= value then
error ( "nupp: " .. what .. " must be a positive integer" , level + 1 )
end

return value
end







local function packProtocols ( protocols , level ) 
if protocols == nil or # protocols == 0 then
return ""
end
local packed = { }
for index , protocol in ipairs ( protocols ) do
if # protocol < 1 or # protocol > 255 then
error ( "nupp: tls protocol " .. index .. " must be 1 through 255 bytes" , level + 1 )
end
if protocol : find ( "\0" , 1 , true ) ~= nil then
error ( "nupp: tls protocol " .. index .. " must not hold a NUL" , level + 1 )
end
packed [ index ] = protocol
end

return table . concat ( packed , "\0" ) .. "\0"
end






local function await ( operation , ready ) 
if ready ( ) then
return
end
suspension . suspend ( operation , function ( resume , context ) 


local resumed = false
const source = context : source (
"nupp.io.tls" ,
50 ,
function ( ) 
net . pump ( 0 )
if not resumed and ready ( ) then
resumed = true
resume ( true )

return 1
end

return 0
end ,
function ( waitMs ) 
net . pump ( waitMs )

return 0
end
)

return function ( ) 
source : release ( )
end
end )
end






tls.Session = {} tls.Session.__index = tls.Session












function tls.Session:isConnected() 
if self . _closed then
return false
end

return self . _provider : connected ( self . _session )
end


function tls.Session:isReady() 
return self . _ready
end


function tls.Session:isReleased() 
return self . _closed
end


function tls.Session:isEnded() 
return self . _ended
end








function tls.Session:protocol() 
if self . _closed or not self . _ready then
return nil
end

return self . _provider : protocol ( self . _session )
end





function tls.Session:isVerified() 
if self . _closed or not self . _ready then
return false
end

return self . _provider : verified ( self . _session )
end







function tls.Session:isResumed() 
if self . _closed or not self . _ready then
return false
end

const resumed = self . _provider . resumed

return resumed ~= nil and resumed ( self . _provider , self . _session ) or false
end










function tls.Session:step() 
if self . _closed then
return nil , io . toError ( "the session is closed" )
end
if self . _ready then
return true
end
const done , why = self . _provider : handshake ( self . _session )
if done == nil then
return nil , io . toError ( why )
end
if done then
self . _ready = true
end

return self . _ready
end






function tls.Session:handshake() 
if self . _closed then
return false , io . toError ( "the session is closed" )
end
if not self : isConnected ( ) then
return false , io . toError ( "the connection underneath was closed first" )
end
if self . _ready then
return true
end
local failure = nil
await ( "nupp.io.tls handshake" , function ( ) 
const done , why = self : step ( )
if done == nil then
failure = why or io . toError ( "the handshake failed" )

return true
end

return done or false
end )
if failure ~= nil then
return false , failure
end

return true
end













function tls.Session:read(count) 
if self . _closed then
return nil , "the session is closed"
end
if not self . _ready then
return nil , "the handshake has not finished"
end
const wanted = positive ( count , "tls.Session read count" , 2 )
local chunk = nil
local failure = nil
local ended = false


const provider = self . _provider
const session = self . _session
await ( "nupp.io.tls read" , function ( ) 
const got , why = provider : read ( session , wanted )
if why ~= nil then
failure = why

return true
end
if got == nil then
return false
end
if # got > wanted then
failure = "the TLS provider returned more bytes than requested"

return true
end
chunk = got
ended = # got == 0

return true
end )
if ended then
self . _ended = true
end
if failure ~= nil then
return nil , failure
end

return chunk or ""
end



function tls.Session:readSpan(destination) 
const wanted = positive ( # destination , "tls.Session readSpan destination length" , 2 )
const chunk , why = self : read ( wanted )
if chunk == nil then
return nil , why
end
const __nuppT25= chunk ; const input = #__nuppT25
for index = 1 , # chunk do
destination :set( index , __nuppFfi.cast("const uint8_t *", __nuppT25 )[ 0 + __nuppModule._checkedIndex( input , index ,"span index out of bounds") -1] )
end

return # chunk
end



function tls.Session:readInto(destination, offset, count) 





const wanted = positive ( count or READ_SIZE , "tls.Session readInto count" , 2 )
const chunk , why = self : read ( wanted )
if chunk == nil then
return nil , why
end
const landed = # chunk
if landed > 0 then
const __nuppT27= chunk ; const input = #__nuppT27
do local __nuppT40=0; local  __nuppT46 ; local __nuppT47=false ; local __nuppT41,__nuppT42,__nuppT43=__nuppT33(function() do local __nuppT48= destination : reserveWrite ( offset or 0 , landed ) ; __nuppT46= __nuppT48 ; __nuppT40=1;  __nuppT47=true;  const lease=__nuppT46;
do
do local __nuppT49=0; local  __nuppT55 ; local __nuppT56=false ; local __nuppT50,__nuppT51,__nuppT52=__nuppT33(function() do local __nuppT57= lease : span ( ) ; __nuppT55= __nuppT57 ; __nuppT49=1;  __nuppT56=true;  const output=__nuppT55;
for index = 1 , landed do
output :set( index , __nuppFfi.cast("const uint8_t *", __nuppT27 )[ 0 + __nuppModule._checkedIndex( input , index ,"span index out of bounds") -1] )
end
do __nuppT56=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT29); local __nuppT53={}; local __nuppT54=0; if __nuppT49>=1 and __nuppT56 then  local __nuppT58,__nuppT59=__nuppT32(__nuppCleanup1,__nuppT55);  if not __nuppT58 then __nuppT54=__nuppT54+1; __nuppT53[__nuppT54]=__nuppT59 end; end; if not __nuppT50 then if __nuppT54>0 then __nuppT34(__nuppT30(__nuppT51,__nuppT53,1),0) else __nuppT34(__nuppT51,0) end end; if __nuppT54>0 then if __nuppT54>1 then __nuppT34(__nuppT30(__nuppT53[1],__nuppT53,2),0) else __nuppT34(__nuppT53[1],0) end end; if __nuppT51=="return" then  return "return",__nuppT52  end; end
end
do (function(__nuppT60,...)  __nuppT47=false; return __nuppT60:commit(...)  end)( lease , landed ) end end; return "normal" end,__nuppT29); local __nuppT44={}; local __nuppT45=0; if __nuppT40>=1 and __nuppT47 then  local __nuppT61,__nuppT62=__nuppT32(__nuppCleanup2,__nuppT46);  if not __nuppT61 then __nuppT45=__nuppT45+1; __nuppT44[__nuppT45]=__nuppT62 end; end; if not __nuppT41 then if __nuppT45>0 then __nuppT34(__nuppT30(__nuppT42,__nuppT44,1),0) else __nuppT34(__nuppT42,0) end end; if __nuppT45>0 then if __nuppT45>1 then __nuppT34(__nuppT30(__nuppT44[1],__nuppT44,2),0) else __nuppT34(__nuppT44[1],0) end end; if __nuppT42=="return" then  return __nuppT35(__nuppT43,1,__nuppT43.n)  end; end
end

return landed
end


function tls.Session:transferTo(destination) 
local moved = 0
while true do
const chunk , why = self : read ( READ_SIZE )
if chunk == nil then
return nil , why
end
if # chunk == 0 then
return moved
end
const wrote , wroteWhy = destination : write ( chunk )
if not wrote then
return nil , wroteWhy
end
moved = moved + ( # chunk )
end
end






function tls.Session:write(bytes) 
if self . _closed then
return false , "the session is closed"
end
if not self : isConnected ( ) then
return false , "the connection underneath was closed first"
end
if not self . _ready then
return false , "the handshake has not finished"
end


const backend , session = self . _provider , self . _session
local at = 1
while at <= # bytes do
local took = nil
local failure = nil
const remaining = bytes : sub ( at )
await ( "nupp.io.tls write" , function ( ) 
const moved , why = backend : write ( session , remaining )
if why ~= nil then
failure = why

return true
end
if moved == nil then
return false
end
if moved < 1 or moved > # remaining or math . floor ( moved ) ~= moved then
failure = "the TLS provider returned an invalid write count"

return true
end
took = moved

return true
end )
if failure ~= nil then
return false , failure
end
at = at + ( took or 0 )
end

return true
end


function tls.Session:writeSpan(source) 
const bytes = spanStringValue ( source : ref ( ) , source .count )
const wrote , why = self : write ( bytes )
if not wrote then
return nil , why
end

return # bytes
end







function tls.Session:flush() 
if self . _closed then
return false , "the session is closed"
end
if not self : isConnected ( ) then
return false , "the connection underneath was closed first"
end

local complete = false
local failure = nil
await ( "nupp.io.tls flush" , function ( ) 
const done , why = self . _provider : flushed ( self . _session )
if why ~= nil then
failure = why

return true
end
complete = done

return done
end )
if failure ~= nil then
return false , failure
end

return complete
end







function tls.Session:close() 
if self . _closed then
return
end
if self . _ready and self : isConnected ( ) then







const chosen , session = self . _provider , self . _session
await ( "nupp.io.tls close" , function ( ) 
const sent , why = chosen : closeNotify ( session )

return sent or why ~= nil
end )
end
self . _closed = true
self . _provider : destroy ( self . _session )
end ;_G.nupp.__reflect.link(tls.Session,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../../src/nupp/io/tls/spi.nupp\0Provider\0interface\0module\0001","nupp.io.tls.spi") })














function tls . client ( stream , options ) 
const chosen = provider
const given = options or { }
const verify = given . verify ~= false
if verify and ( given . hostname == nil or given . hostname == "" ) then
error ( "nupp: tls.client needs a hostname to verify the peer against" , 2 )
end
const protocols = packProtocols ( given . protocols , 2 )
const session , why = chosen : wrap (
takeStreamHandle ( stream ) ,
false ,
given . hostname or "" ,
"" ,
"" ,
given . authority ,
protocols ,
verify
)
if session == nil then
return nil , io . toError ( why )
end

return ( _G.setmetatable({ _provider =  chosen ,  _session =  session ,  _closed =  false ,  _ready =  false ,  _ended =  false }, tls.Session) )
end







function tls . server ( stream , options ) 
const chosen = provider
const protocols = packProtocols ( options . protocols , 2 )
const session , why = chosen : wrap (
takeStreamHandle ( stream ) ,
true ,
"" ,
options . certificate ,
options . privateKey ,
nil ,
protocols ,
false
)
if session == nil then
return nil , io . toError ( why )
end

return ( _G.setmetatable({ _provider =  chosen ,  _session =  session ,  _closed =  false ,  _ready =  false ,  _ended =  false }, tls.Session) )
end

local __nuppExportValue= tls ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.io.tls"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.tls"]=__nuppExports;return __nuppExports