_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT28={}; local function __nuppT25(...) return {n=select("#",...),...} end; local __nuppT29,__nuppT30,__nuppT31,__nuppT32,__nuppT33,__nuppT34,__nuppT35,__nuppT36=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT26(value) return value end; local function __nuppT27(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT34({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT35(v.primary) for _,reason in __nuppT36(v.suppressed) do text=text.."\ncleanup: "..__nuppT35(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppT62 = function(__nuppV) return __nuppV:close() end;local __nuppMove3 = function(__nuppT119,__nuppT115,...) __nuppT115[-4]=false; return __nuppT119:close(...) end;local __nuppMove4 = function(__nuppT120,__nuppT115,...) __nuppT115[-4]=false; return __nuppT120:close(...) end;local __nuppMove5 = function(__nuppT141,__nuppT137,...) __nuppT137[-4]=false; return __nuppT141:close(...) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


local effects = require ( "nupp.runtime.browser.effects" )
local messages = require ( "nupp.io.files.messages" )
local appPaths = require ( "nupp.io.files.path" )
local io = require ( "nupp.io" )
local span = require ( "nupp.mem.span" )
local suspension = require ( "nupp.suspension" )
local memory = require ( "nupp.runtime.browser.memory" )

local files = { }
local pending = 0
local READ_SIZE = 65536
local ORIGINS = { set = 0 , current = 1 , [ "end" ] = 2 , }
local MODES = { r = true , w = true , a = true , [ "r+" ] = true , [ "w+" ] = true , [ "a+" ] = true , }
local APPLICATION_KINDS = { configuration = true , data = true , cache = true , }
local MAX_EXACT_INTEGER = 9007199254740991

local function unavailable ( operation ) 
return "browser files do not support " .. operation
end

local function descriptor ( value , level ) 
if not appPaths . is ( value ) then
error ( "nupp: browser file paths must come from an application path" , level )
end
local described = appPaths . descriptor ( value )
if described . provider ~= "browser" then
error ( "nupp: browser file paths must come from this browser provider" , level )
end

return { root = described . root , parts = described . parts , }
end

local function whole ( value , what , level ) 
if type ( value ) ~= "number"
or value ~= math . floor ( value )
or math . abs ( value ) > 9007199254740991
then
error ( "nupp: io.files " .. what .. " must be an integer" , level )
end

return value
end

local function positive ( value , what , level ) 
local answer = whole ( value , what , level + 1 )
if answer < 1 then
error ( "nupp: io.files " .. what .. " must be positive" , level )
end

return answer
end

local function counted ( value , what , level ) 
local answer = whole ( value , what , level + 1 )
if answer < 0 then
error ( "nupp: io.files " .. what .. " must not be negative" , level )
end

return answer
end

local function protocol ( value , field , minimum ) 
if type ( value ) ~= "table" then
return nil , "browser file host returned no " .. field
end
local answer = ( value ) [ field ]
if type ( answer ) ~= "number"
or answer ~= math . floor ( answer )
or ( answer ) < minimum
or ( answer ) > 9007199254740991
then
return nil , "browser file host returned an invalid " .. field
end

return answer , nil
end

local function effect ( operation , path , extra , discard ) 
local payload = extra or { }
payload . operation = operation
if path ~= nil then
local described = descriptor ( path , 4 )
payload . root = described . root
payload . parts = described . parts
end
local completed , suspended = pcall ( suspension . suspend , "browser file operation" , function (
resume
) 
return effects . request ( "files" , payload , resume , discard )
end )
if not completed then



if payload . lease ~= nil then
memory . releaseLease ( payload . lease )
end
error ( suspended , 0 )
end
local answer = suspended
if type ( answer ) ~= "table" or type ( answer . ok ) ~= "boolean" then
return nil , "browser file host returned an invalid response"
end
if not answer . ok then
return nil , type ( answer . error ) == "string" and answer . error or "browser file operation failed"
end

return answer . value , nil
end

function files . capabilities ( ) 
local value = effect ( "capabilities" , nil )
local available = type ( value ) == "table" and value . available == true
return ( _G.setmetatable({ available =
available ,  arbitraryPaths =
false ,  symbolicLinks =
false ,  readOnlyAttributes =
false ,  glob =
false ,  rename =
false ,  atomicWrite =
false ,  temporaryPaths =
false ,  concurrentOpenHandles =
false ,  currentDirectory =
false ,  userFolders =
false ,  executableDirectory =
false ,  persistentStorageRequest =
available and value . persistentAvailable == true }, messages.Capabilities) )

end

function files . applicationPath (
kind ,
organization ,
application
) 
if APPLICATION_KINDS [ kind ] == nil then
return nil , "unknown application path kind"
end
local path = appPaths . browser ( kind , organization , application )
local value , reason = effect ( "create-directory" , path )
if reason ~= nil then
return nil , reason
end
if type ( value ) ~= "table" or value . created ~= true then
return nil , "browser file host returned an invalid create result"
end

return path , nil
end

function files . info ( path ) 
local value , reason = effect ( "info" , path )
if value == nil then
return nil , reason
end

local kind = type ( value ) == "table" and value . kind or nil
local size = type ( value ) == "table" and value . size or nil
local modified = type ( value ) == "table" and value . modified or nil
if ( kind ~= "file" and kind ~= "directory" )
or type ( size ) ~= "number"
or size ~= math . floor ( size )
or ( size ) < 0
or ( size ) > 9007199254740991
or type ( modified ) ~= "number"
or modified ~= modified
or modified == math . huge
or modified == - math . huge
then
return nil , "browser file host returned invalid metadata"
end



return _G.setmetatable({ kind =  kind ,  size =  size ,  modified =  ( modified ) * 1000 ,  readOnly =  false }, messages.Info) , nil
end

function files . exists ( path ) 
local value = files . info ( path )
return value ~= nil
end

function files . isFile ( path ) 
local value = files . info ( path )
return value ~= nil and value . kind == "file"
end

function files . isDirectory ( path ) 
local value = files . info ( path )
return value ~= nil and value . kind == "directory"
end

function files . isSymlink ( path ) 
descriptor ( path , 2 )
return false
end

function files . readLink ( path ) 
descriptor ( path , 2 )
return nil , "browser files do not support symbolic links"
end

function files . createSymlink ( target , link , kind ) 
descriptor ( target , 2 )
descriptor ( link , 2 )
return false , "browser files do not support symbolic links"
end

function files . setReadOnly ( path , readOnly ) 
descriptor ( path , 2 )
return false , "browser files do not support read-only attributes"
end

function files . createDirectory ( path ) 
local value , reason = effect ( "create-directory" , path )
if value == nil then
return false , reason
end

return type ( value ) == "table" and value . created == true , type ( value ) == "table" and value . created == true and nil
or "browser file host returned an invalid create result"
end

function files . remove ( path , recursive ) 
local value , reason = effect ( "remove" , path , { recursive = recursive == true , } )
if value == nil then
return false , reason
end

return type ( value ) == "table" and value . removed == true , type ( value ) == "table" and value . removed == true and nil
or "browser file host returned an invalid remove result"
end

function files . rename ( from , to ) 
descriptor ( from , 2 )
descriptor ( to , 2 )
return false , "browser files do not support rename"
end

function files . list ( path ) 
local value , reason = effect ( "list" , path )
if value == nil then
return nil , reason
end
if type ( value ) ~= "table" then
return nil , "browser file host returned an invalid directory listing"
end
local entries = { }
for _ , entry in ipairs ( value ) do
if type ( entry ) ~= "table"
or type ( entry . name ) ~= "string"
or entry . name == ""
or ( entry . kind ~= "file" and entry . kind ~= "directory" )
then
return nil , "browser file host returned an invalid directory entry"
end
entries [ # entries + 1 ] = _G.setmetatable({ name =  entry . name ,  kind =  entry . kind }, messages.Entry)
end

return entries , nil
end

function files . glob ( pattern ) 
if type ( pattern ) ~= "string" then
error ( "nupp: io.files glob pattern must be a string" , 2 )
end
return nil , "browser files do not support glob"
end

local File = {} File.__index = File



function File:read(count) 
if self . _closed then
return nil , "the file is closed"
end
local wanted = math . min ( positive ( count , "File:read count" , 2 ) , READ_SIZE )
do local __nuppT37=0; local  __nuppT43,__nuppT44 ; local __nuppT45=false ; local __nuppT38,__nuppT39,__nuppT40=__nuppT30(function() do local __nuppT46= io . newBuffer ( wanted ) ; __nuppT43= __nuppT46 ; __nuppT37=1;  local destination=__nuppT43;
local __nuppT47= destination : reserveWrite ( 0 , wanted ) ; __nuppT44= __nuppT47 ; __nuppT37=2;  __nuppT45=true;  local lease=__nuppT44;
local got
local reason
do
do local __nuppT48=0; local  __nuppT54 ; local __nuppT55=false ; local __nuppT49,__nuppT50,__nuppT51=__nuppT30(function() do local __nuppT56= lease : span ( ) ; __nuppT54= __nuppT56 ; __nuppT48=1;  __nuppT55=true;  local output=__nuppT54;
got , reason = self : readSpan ( output )
do __nuppT55=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT26); local __nuppT52={}; local __nuppT53=0; if __nuppT48>=1 and __nuppT55 then  local __nuppT57,__nuppT58=__nuppT29(__nuppCleanup1,__nuppT54);  if not __nuppT57 then __nuppT53=__nuppT53+1; __nuppT52[__nuppT53]=__nuppT58 end; end; if not __nuppT49 then if __nuppT53>0 then __nuppT31(__nuppT27(__nuppT50,__nuppT52,1),0) else __nuppT31(__nuppT50,0) end end; if __nuppT53>0 then if __nuppT53>1 then __nuppT31(__nuppT27(__nuppT52[1],__nuppT52,2),0) else __nuppT31(__nuppT52[1],0) end end; if __nuppT50=="return" then  return "return",__nuppT51  end; end
end
do (function(__nuppT59,...)  __nuppT45=false; return __nuppT59:commit(...)  end)( lease , got or 0 ) end
if got == nil then
return "return",__nuppT25( nil , reason )
end

return "return",__nuppT25( destination : getString ( ) , nil ) end; return "normal" end,__nuppT26); local __nuppT41={}; local __nuppT42=0; if __nuppT37>=2 and __nuppT45 then  local __nuppT60,__nuppT61=__nuppT29(__nuppCleanup2,__nuppT44);  if not __nuppT60 then __nuppT42=__nuppT42+1; __nuppT41[__nuppT42]=__nuppT61 end; end; if __nuppT37>=1 then  local __nuppT63,__nuppT64=__nuppT29(__nuppT62,__nuppT43);  if not __nuppT63 then __nuppT42=__nuppT42+1; __nuppT41[__nuppT42]=__nuppT64 end; end; if not __nuppT38 then if __nuppT42>0 then __nuppT31(__nuppT27(__nuppT39,__nuppT41,1),0) else __nuppT31(__nuppT39,0) end end; if __nuppT42>0 then if __nuppT42>1 then __nuppT31(__nuppT27(__nuppT41[1],__nuppT41,2),0) else __nuppT31(__nuppT41[1],0) end end; if __nuppT39=="return" then  return __nuppT32(__nuppT40,1,__nuppT40.n)  end; end
end

function File:readSpan(destination) 
if self . _closed then
return nil , "the file is closed"
end
local pointer , capacity = destination : ref ( )
local count = positive ( math . min ( capacity , READ_SIZE ) , "File:readSpan destination length" , 2 )
local leaseRead = memory . lease




local lease = leaseRead ( pointer , count , true )
local value , reason = effect ( "file-read" , nil , { handle = self . _handle , lease = lease , count = count , } )
memory . releaseLease ( lease )
if value == nil then
return nil , reason
end
local got , invalid = protocol ( value , "bytes" , 0 )
if got ~= nil and got > count then
return nil , "browser file host returned an invalid byte count"
end

return got , invalid
end

function File:readInto(destination, offset, count) 





local from = counted ( offset or 0 , "File:readInto offset" , 2 )
local wanted = math . min ( positive ( count or READ_SIZE , "File:readInto count" , 2 ) , READ_SIZE )
do local __nuppT67=0; local  __nuppT73 ; local __nuppT74=false ; local __nuppT68,__nuppT69,__nuppT70=__nuppT30(function() do local __nuppT75= destination : reserveWrite ( from , wanted ) ; __nuppT73= __nuppT75 ; __nuppT67=1;  __nuppT74=true;  local lease=__nuppT73;
local got
local reason
do
do local __nuppT76=0; local  __nuppT82 ; local __nuppT83=false ; local __nuppT77,__nuppT78,__nuppT79=__nuppT30(function() do local __nuppT84= lease : span ( ) ; __nuppT82= __nuppT84 ; __nuppT76=1;  __nuppT83=true;  local output=__nuppT82;
got , reason = self : readSpan ( output )
do __nuppT83=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT26); local __nuppT80={}; local __nuppT81=0; if __nuppT76>=1 and __nuppT83 then  local __nuppT85,__nuppT86=__nuppT29(__nuppCleanup1,__nuppT82);  if not __nuppT85 then __nuppT81=__nuppT81+1; __nuppT80[__nuppT81]=__nuppT86 end; end; if not __nuppT77 then if __nuppT81>0 then __nuppT31(__nuppT27(__nuppT78,__nuppT80,1),0) else __nuppT31(__nuppT78,0) end end; if __nuppT81>0 then if __nuppT81>1 then __nuppT31(__nuppT27(__nuppT80[1],__nuppT80,2),0) else __nuppT31(__nuppT80[1],0) end end; if __nuppT78=="return" then  return "return",__nuppT79  end; end
end
if got == nil then
do (function(__nuppT87,...)  __nuppT74=false; return __nuppT87:commit(...)  end)( lease , 0 ) end
return "return",__nuppT25( nil , reason )
end
do (function(__nuppT88,...)  __nuppT74=false; return __nuppT88:commit(...)  end)( lease , got ) end

return "return",__nuppT25( got , nil ) end; return "normal" end,__nuppT26); local __nuppT71={}; local __nuppT72=0; if __nuppT67>=1 and __nuppT74 then  local __nuppT89,__nuppT90=__nuppT29(__nuppCleanup2,__nuppT73);  if not __nuppT89 then __nuppT72=__nuppT72+1; __nuppT71[__nuppT72]=__nuppT90 end; end; if not __nuppT68 then if __nuppT72>0 then __nuppT31(__nuppT27(__nuppT69,__nuppT71,1),0) else __nuppT31(__nuppT69,0) end end; if __nuppT72>0 then if __nuppT72>1 then __nuppT31(__nuppT27(__nuppT71[1],__nuppT71,2),0) else __nuppT31(__nuppT71[1],0) end end; if __nuppT69=="return" then  return __nuppT32(__nuppT70,1,__nuppT70.n)  end; end
end

function File:transferTo(destination) 
local total = 0
while true do
local chunk , reason = self : read ( READ_SIZE )
if chunk == nil then
return nil , reason
end
if # chunk == 0 then
return total , nil
end
local wrote , failure = destination : write ( chunk )
if not wrote then
return nil , failure
end
total = total + # chunk
end
end

function File:write(bytes) 
if self . _closed then
return false , "the file is closed"
end
local source = span . fromString ( bytes )
local wrote , reason = self : writeSpan ( source )
if wrote == nil then
return false , reason
end
if wrote ~= # bytes then
return false , "browser file host performed a short write"
end

return true , nil
end

function File:writeSpan(source) 
if self . _closed then
return nil , "the file is closed"
end
local total = 0
while total < source .count do
local count = math . min ( READ_SIZE , source .count - total )
local chunk = source : slice ( total + 1 , total + count )
local pointer = chunk : ref ( )
local leaseWrite = memory . lease




local lease = leaseWrite ( pointer , count , false )
local value , reason = effect ( "file-write" , nil , { handle = self . _handle , lease = lease , count = count , } )
memory . releaseLease ( lease )
if value == nil then
return nil , reason
end
local wrote , invalid = protocol ( value , "bytes" , 0 )
if wrote == nil then
return nil , invalid
end
if wrote ~= count then
return nil , "browser file host performed a short write"
end
total = total + wrote
end

return total , nil
end

function File:size() 
if self . _closed then
error ( "nupp: io.files File is closed" , 2 )
end
local value , reason = effect ( "file-size" , nil , { handle = self . _handle , } )
if value == nil then
return nil , io . toError ( reason )
end
local size , invalid = protocol ( value , "size" , 0 )

return size , io . toError ( invalid , "invalid" )
end

function File:seek(offset, origin) 
if self . _closed then
error ( "nupp: io.files File is closed" , 2 )
end
local whence = ORIGINS [ origin or "set" ]
if whence == nil then
error ( "nupp: io.files has no seek origin named " .. tostring ( origin ) , 2 )
end

local value , reason = effect ( "file-seek" , nil , {
handle = self . _handle ,
offset = whole ( offset or 0 , "seek offset" , 2 ) ,
origin = whence ,
} )
if value == nil then
return nil , io . toError ( reason )
end
local position , invalid = protocol ( value , "position" , 0 )

return position , io . toError ( invalid , "invalid" )
end

function File:position() 
return self : seek ( 0 , "current" )
end

function File:flush() 
if self . _closed then
return false , "the file is closed"
end
local value , reason = effect ( "file-flush" , nil , { handle = self . _handle , } )
if value == nil then
return false , reason
end
if type ( value ) ~= "table" or value . flushed ~= true then
return false , "browser file host returned an invalid flush result"
end

return true , nil
end

function File:isReleased() 
return self . _closed
end




function File . close ( self ) 
local state = self
if state . _closed then
return
end
state . _closed = true
effects . request ( "files" , { operation = "file-close" , handle = state . _handle , } , function ( ) 
end )
end




local function closeOrphan ( response ) 
if type ( response ) == "table"
and response . ok
and type ( response . value ) == "table"
and type ( response . value . handle ) == "number"
and response . value . handle == math . floor ( response . value . handle )
and response . value . handle >= 1
and response . value . handle <= 9007199254740991
then
effects . request ( "files" , { operation = "file-close" , handle = response . value . handle , } , function ( ) 
end )
end
end

function files . open ( path , mode ) 
local selected = mode or "r"
if MODES [ selected ] == nil then
error ( "nupp: io.files has no mode named " .. tostring ( mode ) , 2 )
end
local value , reason = effect ( "open" , path , { mode = selected , } , closeOrphan )
if value == nil then
return nil , reason
end
local handle , invalid = protocol ( value , "handle" , 1 )
if handle == nil then
return nil , invalid
end

return _G.setmetatable({ _handle =  handle ,  _closed =  false }, File) , nil
end

local function wholeRead ( path ) 
pending = pending + 1 do local __nuppT115={[0]=0 ,[1]=path }; local __nuppT116=__nuppT28[1]; const __nuppT106,__nuppT107,__nuppT108=__nuppT30(__nuppT116,__nuppT26,__nuppT115); local __nuppT109={}; local __nuppT110=0; if __nuppT115[0]>=2 and __nuppT115[-4] then  local __nuppT121,__nuppT122=__nuppT29(__nuppT62,__nuppT115[-3]);  if not __nuppT121 then __nuppT110=__nuppT110+1; __nuppT109[__nuppT110]=__nuppT122 end; end; if __nuppT115[0]>=1 and __nuppT115[-2] and __nuppT115[-1]~=nil then  local __nuppT123,__nuppT124=__nuppT29(__nuppT62,__nuppT115[-1]);  if not __nuppT123 then __nuppT110=__nuppT110+1; __nuppT109[__nuppT110]=__nuppT124 end; end; if not __nuppT106 then if __nuppT110>0 then __nuppT31(__nuppT27(__nuppT107,__nuppT109,1),0) else __nuppT31(__nuppT107,0) end end; if __nuppT110>0 then if __nuppT110>1 then __nuppT31(__nuppT27(__nuppT109[1],__nuppT109,2),0) else __nuppT31(__nuppT109[1],0) end end; if __nuppT107=="return" then  return __nuppT32(__nuppT108,1,__nuppT108.n)  end; end end; __nuppT28[1]=function(__nuppT115) do
local __nuppT117=__nuppT25( files . open ( __nuppT115[1] , "r" ) ); __nuppT115[-1]= __nuppT117[1] ; __nuppT115[0]=1;  __nuppT115[-2]=true;  local  opened , reason = __nuppT117[1] , __nuppT117[2] ;
if opened == nil then
pending = pending - 1
return "return",__nuppT25( nil , reason )
end
local __nuppT118= opened ;  __nuppT115[-2]=false; __nuppT115[-3]= __nuppT118 ; __nuppT115[0]=2;  __nuppT115[-4]=true;  local file=__nuppT115[-3];
local pieces = { }
while true do
local chunk , failure = file : read ( 65536 )
if chunk == nil then
do __nuppMove3( file ,__nuppT115 ) end
pending = pending - 1
return "return",__nuppT25( nil , failure )
end
if # chunk == 0 then
do break end
end
pieces [ # pieces + 1 ] = chunk
end
do __nuppMove4( file ,__nuppT115 ) end
pending = pending - 1

return "return",__nuppT25( table . concat ( pieces ) , nil ) end; return "normal" end;


function files . read ( path ) 
return wholeRead ( path )
end

local function wholeWrite ( path , bytes , mode ) 
if type ( bytes ) ~= "string" and ( type ( bytes ) ~= "table" or bytes . getString == nil ) then
error ( "nupp: io.files contents must be bytes or a byte view" , 3 )
end
local text = type ( bytes ) == "string" and bytes or bytes : getString ( )
pending = pending + 1 do local __nuppT137={[0]=0 ,[1]=path ,[2]=mode ,[3]=text }; local __nuppT138=__nuppT28[2]; const __nuppT128,__nuppT129,__nuppT130=__nuppT30(__nuppT138,__nuppT26,__nuppT137); local __nuppT131={}; local __nuppT132=0; if __nuppT137[0]>=2 and __nuppT137[-4] then  local __nuppT142,__nuppT143=__nuppT29(__nuppT62,__nuppT137[-3]);  if not __nuppT142 then __nuppT132=__nuppT132+1; __nuppT131[__nuppT132]=__nuppT143 end; end; if __nuppT137[0]>=1 and __nuppT137[-2] and __nuppT137[-1]~=nil then  local __nuppT144,__nuppT145=__nuppT29(__nuppT62,__nuppT137[-1]);  if not __nuppT144 then __nuppT132=__nuppT132+1; __nuppT131[__nuppT132]=__nuppT145 end; end; if not __nuppT128 then if __nuppT132>0 then __nuppT31(__nuppT27(__nuppT129,__nuppT131,1),0) else __nuppT31(__nuppT129,0) end end; if __nuppT132>0 then if __nuppT132>1 then __nuppT31(__nuppT27(__nuppT131[1],__nuppT131,2),0) else __nuppT31(__nuppT131[1],0) end end; if __nuppT129=="return" then  return __nuppT32(__nuppT130,1,__nuppT130.n)  end; end end; __nuppT28[2]=function(__nuppT137) do
local __nuppT139=__nuppT25( files . open ( __nuppT137[1] , __nuppT137[2] ) ); __nuppT137[-1]= __nuppT139[1] ; __nuppT137[0]=1;  __nuppT137[-2]=true;  local  opened , reason = __nuppT139[1] , __nuppT139[2] ;
if opened == nil then
pending = pending - 1
return "return",__nuppT25( false , reason )
end
local __nuppT140= opened ;  __nuppT137[-2]=false; __nuppT137[-3]= __nuppT140 ; __nuppT137[0]=2;  __nuppT137[-4]=true;  local file=__nuppT137[-3];
local wrote , failure = file : write ( __nuppT137[3] )
do __nuppMove5( file ,__nuppT137 ) end
pending = pending - 1

return "return",__nuppT25( wrote , failure ) end; return "normal" end;


function files . write ( path , bytes ) 
return wholeWrite ( path , bytes , "w" )
end

function files . append ( path , bytes ) 
return wholeWrite ( path , bytes , "a" )
end

function files . writeAtomic ( path , bytes ) 
descriptor ( path , 2 )
return false , "browser files do not support atomic replacement"
end

function files . copy ( from , to ) 
local bytes , reason = wholeRead ( from )
if bytes == nil then
return false , reason
end

return wholeWrite ( to , bytes , "w" )
end

function files . pendingTransfers ( ) 
return pending
end

function files . createTemporaryFile ( options ) 
return nil , "browser files do not support temporary paths"
end

function files . createTemporaryDirectory ( options ) 
return nil , "browser files do not support temporary paths"
end

function files . userFolder ( which ) 
return nil , "browser files do not support user folders"
end

function files . executableDirectory ( ) 
return nil , "browser files do not support an executable directory"
end

function files . requestPersistentStorage ( ) 
local value , reason = effect ( "persist" , nil )
if value == nil then
return false , reason
end
if type ( value ) ~= "table" or type ( value . granted ) ~= "boolean" then
return false , "browser file host returned an invalid persistence result"
end

return value . granted == true , value . granted == true and nil or "persistent storage was not granted"
end

local __nuppExportValue= files ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.files"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.files"]=__nuppExports;return __nuppExports