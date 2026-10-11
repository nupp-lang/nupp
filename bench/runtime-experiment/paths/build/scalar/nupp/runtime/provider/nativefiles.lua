_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT19={}; local function __nuppT16(...) return {n=select("#",...),...} end; local __nuppT20,__nuppT21,__nuppT22,__nuppT23,__nuppT24,__nuppT25,__nuppT26,__nuppT27=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT17(value) return value end; local function __nuppT18(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT25({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT26(v.primary) for _,reason in __nuppT27(v.suppressed) do text=text.."\ncleanup: "..__nuppT26(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.mem.span#destroyWriteSpan"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.mem.span#destroyWriteSpan") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.internal.bytes#destroyLease"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.internal.bytes#destroyLease") end;__nuppCleanup2=cleanup;return cleanup(value) end;local __nuppDrop1 = function(__nuppV) if __nuppV == nil then return end __nuppCleanup1(__nuppV);  end;local __nuppExports={};package.loaded["nupp.runtime.provider.nativefiles"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local append;__nuppExports["append"]=function(...) return append(...) end;local applicationPath;__nuppExports["applicationPath"]=function(...) return applicationPath(...) end;local capabilities;__nuppExports["capabilities"]=function(...) return capabilities(...) end;local copy;__nuppExports["copy"]=function(...) return copy(...) end;local createDirectory;__nuppExports["createDirectory"]=function(...) return createDirectory(...) end;local createSymlink;__nuppExports["createSymlink"]=function(...) return createSymlink(...) end;local createTemporaryDirectory;__nuppExports["createTemporaryDirectory"]=function(...) return createTemporaryDirectory(...) end;local createTemporaryFile;__nuppExports["createTemporaryFile"]=function(...) return createTemporaryFile(...) end;local executableDirectory;__nuppExports["executableDirectory"]=function(...) return executableDirectory(...) end;local exists;__nuppExports["exists"]=function(...) return exists(...) end;local glob;__nuppExports["glob"]=function(...) return glob(...) end;local info;__nuppExports["info"]=function(...) return info(...) end;local isDirectory;__nuppExports["isDirectory"]=function(...) return isDirectory(...) end;local isFile;__nuppExports["isFile"]=function(...) return isFile(...) end;local isSymlink;__nuppExports["isSymlink"]=function(...) return isSymlink(...) end;local list;__nuppExports["list"]=function(...) return list(...) end;local open;__nuppExports["open"]=function(...) return open(...) end;local pendingTransfers;__nuppExports["pendingTransfers"]=function(...) return pendingTransfers(...) end;local read;__nuppExports["read"]=function(...) return read(...) end;local readLink;__nuppExports["readLink"]=function(...) return readLink(...) end;local remove;__nuppExports["remove"]=function(...) return remove(...) end;local rename;__nuppExports["rename"]=function(...) return rename(...) end;local requestPersistentStorage;__nuppExports["requestPersistentStorage"]=function(...) return requestPersistentStorage(...) end;local setReadOnly;__nuppExports["setReadOnly"]=function(...) return setReadOnly(...) end;local userFolder;__nuppExports["userFolder"]=function(...) return userFolder(...) end;local write;__nuppExports["write"]=function(...) return write(...) end;local writeAtomic;__nuppExports["writeAtomic"]=function(...) return writeAtomic(...) end;
local __nuppT1={ _G.nupp.__reflect.declaration("nupp.runtime.provider.nativefiles\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.runtime.provider.nativefiles\0runtime\0002") };























































































































































































































































































































const native = require ( "nupp.runtime.native" )
const suspension = require ( "nupp.suspension" )
const paths = require ( "nupp.io.path" )
const io = require ( "nupp.io" )
const span = require ( "nupp.mem.span" )
const messages = require ( "nupp.io.files.messages" )
const appPaths = require ( "nupp.io.files.path" )







_G.pcall(__nuppFfi.cdef, "struct NuppNativeFilesInfo { uint32_t kind; int32_t read_only; uint64_t size; double modified; };") const NuppNativeFilesInfo = __nuppFfi.typeof("struct NuppNativeFilesInfo")






_G.pcall(__nuppFfi.cdef, "struct NuppNativeFilesSlice { const char * data; uint64_t length; };") const NuppNativeFilesSlice = __nuppFfi.typeof("struct NuppNativeFilesSlice")




native . ffi . cdef [[
int32_t nuppNativeFilesInfo(
    struct NuppNativeFilesSlice, int32_t, struct NuppNativeFilesInfo *);
int32_t nuppNativeFilesReadLink(struct NuppNativeFilesSlice, uint64_t *);
int32_t nuppNativeFilesCreateSymlink(
    struct NuppNativeFilesSlice, struct NuppNativeFilesSlice, int32_t);
int32_t nuppNativeFilesSetReadOnly(struct NuppNativeFilesSlice, int32_t);
int32_t nuppNativeFilesCreateDirectory(struct NuppNativeFilesSlice);
int32_t nuppNativeFilesRemove(struct NuppNativeFilesSlice, int32_t);
int32_t nuppNativeFilesRename(
    struct NuppNativeFilesSlice, struct NuppNativeFilesSlice);
int32_t nuppNativeFilesList(struct NuppNativeFilesSlice, uint64_t *);
int32_t nuppNativeFilesGlob(struct NuppNativeFilesSlice, uint64_t *);
int32_t nuppNativeFilesCreateTemporary(
    struct NuppNativeFilesSlice, struct NuppNativeFilesSlice,
    struct NuppNativeFilesSlice,
    int32_t, uint64_t *);
int32_t nuppNativeFilesUserFolder(uint32_t, uint64_t *);
int32_t nuppNativeFilesApplicationBase(uint32_t, uint64_t *);
int32_t nuppNativeFilesExecutablePath(uint64_t *);

int32_t nuppNativeFileOpen(struct NuppNativeFilesSlice, uint32_t, uint64_t *);
int32_t nuppNativeFileRead(uint64_t, uint8_t *, size_t, size_t *);
int32_t nuppNativeFileWrite(uint64_t, const uint8_t *, size_t, size_t *);
int32_t nuppNativeFileSeek(uint64_t, int64_t, uint32_t, int64_t *);
int32_t nuppNativeFileSize(uint64_t, int64_t *);
int32_t nuppNativeFileFlush(uint64_t);
int32_t nuppNativeFileRelease(uint64_t);

int32_t nuppNativeFilesTransferSubmitRead(
    struct NuppNativeFilesSlice, uint64_t *);
int32_t nuppNativeFilesTransferSubmitWrite(
    struct NuppNativeFilesSlice, struct NuppNativeFilesSlice,
    uint32_t, uint64_t *);
int32_t nuppNativeFilesTransferSubmitCopy(
    struct NuppNativeFilesSlice, struct NuppNativeFilesSlice, uint64_t *);
int32_t nuppNativeFilesTransferStatus(uint64_t, uint32_t *);
int32_t nuppNativeFilesTransferTakeBytes(uint64_t, uint64_t *);
int32_t nuppNativeFilesTransferCancel(uint64_t);
int32_t nuppNativeFilesTransferRelease(uint64_t);
int32_t nuppNativeFilesTransferPending(size_t *);
]]

local ffi = native . ffi
local C = native . C
const FILES_FEATURE = 128
local featureChecked = false

local function requireFiles ( ) 
if not featureChecked then
native . requireFeature ( 128 , "files" )
featureChecked = true
end
end

local function slice ( text ) 
requireFiles ( )
local value = __nuppFfi.new(NuppNativeFilesSlice )



do
value . data = text
end
value . length = # text

return value
end

local function fileRead ( handle , destination , count , wrote ) 
local call = C . nuppNativeFileRead






return call ( handle , destination , count , wrote )
end

local function fileWrite ( handle , source , count , wrote ) 
local call = C . nuppNativeFileWrite






return call ( handle , source , count , wrote )
end




local KINDS = { [ 1 ] = "file" , [ 2 ] = "directory" , [ 3 ] = "other" , [ 4 ] = "symlink" , }
local ENTRIES = { f = "file" , d = "directory" , l = "symlink" , o = "other" , }
local FOLDERS = { home = 0 , documents = 1 , downloads = 2 , desktop = 3 , pictures = 4 , music = 5 , videos = 6 , }
local MODES = { r = 0 , w = 1 , a = 2 , [ "r+" ] = 3 , [ "w+" ] = 4 , [ "a+" ] = 5 , }
local ORIGINS = { set = 0 , current = 1 , [ "end" ] = 2 , }

local READ_SIZE = 65536
local MAX_EXACT_INTEGER = 9007199254740991
local PENDING = 0
local READY = 1
local FAILED = 2
local CANCELED = 3




local SOURCE = "nupp-files"




























local Info = messages . Info





local Entry = messages . Entry











local scratch


local function named ( value , what , level ) 
if type ( value ) == "string" then
return value
end
if appPaths . is ( value ) then
return ( value ) : toString ( )
end
if type ( value ) == "table" and ( value ) . toString ~= nil then
return ( value ) : toString ( )
end
error ( "nupp: io.files " .. what .. " must be a path or a string" , level )
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


local function counted ( value , what , level ) 
if whole ( value , what , level + 1 ) < 0 then
error ( "nupp: io.files " .. what .. " must not be negative" , level )
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



local function done ( status ) 
if status == 0 then
return true , nil
end

return false , ffi . string ( C . nuppNativeLastError ( ) )
end



local function answer ( status , output ) 
if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end

return native . bytes ( output [ 0 ] ) , nil
end


local function readBytes ( handle , into , count ) 
local output = ffi . new ( "size_t[1]" )
local status = C . nuppNativeFileRead ( handle , into , count , output )
if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end
local got = tonumber ( output [ 0 ] )
if got < 0 or got > count then
return nil , "the native files provider returned an invalid read count"
end
if got == 0 then
return "" , nil
end

return ffi . string ( into , got ) , nil
end










local File = {} File.__index = File













function File:read(count) 
if self . _closed then
return nil , "the file is closed"
end
local wanted = positive ( count , "File:read count" , 2 )
local into = scratch ( self , wanted )

return readBytes ( self . _handle , into , wanted )
end






function File:readSpan(destination) 
if self . _closed then
return nil , "the file is closed"
end
local wanted = positive ( # destination , "File:readSpan destination length" , 2 )
local pointer = destination : ref ( )
local output = ffi . new ( "size_t[1]" )
local status = fileRead ( self . _handle , pointer , wanted , output )
if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end

local got = tonumber ( output [ 0 ] )
if got < 0 or got > wanted then
return nil , "the native files provider returned an invalid read count"
end

return got , nil
end










function File:readInto(destination, offset, count) 





if self . _closed then
return nil , "the file is closed"
end
local from = counted ( offset or 0 , "File:readInto offset" , 2 )
local wanted = positive ( count or READ_SIZE , "File:readInto count" , 2 )
local chunk , failure = self : read ( wanted )
if chunk == nil then
return nil , failure
end
local taking = # ( chunk )
if taking == 0 then
return 0 , nil
end
local input = span . fromString ( chunk )
do local __nuppT28=0; local  __nuppT34 ; local __nuppT35=false ; local __nuppT29,__nuppT30,__nuppT31=__nuppT21(function() do local __nuppT36= destination : reserveWrite ( from , wanted ) ; __nuppT34= __nuppT36 ; __nuppT28=1;  __nuppT35=true;  local lease=__nuppT34;
do
do local __nuppT37=0; local  __nuppT43 ; local __nuppT44=false ; local __nuppT38,__nuppT39,__nuppT40=__nuppT21(function() do local __nuppT45= lease : span ( ) ; __nuppT43= __nuppT45 ; __nuppT37=1;  __nuppT44=true;  local output=__nuppT43;
for index = 1 , taking do
output :set( index , input :get( index ) )
end
do __nuppT44=false; __nuppDrop1( output ) end end; return "normal" end,__nuppT17); local __nuppT41={}; local __nuppT42=0; if __nuppT37>=1 and __nuppT44 then  local __nuppT46,__nuppT47=__nuppT20(__nuppCleanup1,__nuppT43);  if not __nuppT46 then __nuppT42=__nuppT42+1; __nuppT41[__nuppT42]=__nuppT47 end; end; if not __nuppT38 then if __nuppT42>0 then __nuppT22(__nuppT18(__nuppT39,__nuppT41,1),0) else __nuppT22(__nuppT39,0) end end; if __nuppT42>0 then if __nuppT42>1 then __nuppT22(__nuppT18(__nuppT41[1],__nuppT41,2),0) else __nuppT22(__nuppT41[1],0) end end; if __nuppT39=="return" then  return "return",__nuppT40  end; end
end
do (function(__nuppT48,...)  __nuppT35=false; return __nuppT48:commit(...)  end)( lease , taking ) end

return "return",__nuppT16( taking , nil ) end; return "normal" end,__nuppT17); local __nuppT32={}; local __nuppT33=0; if __nuppT28>=1 and __nuppT35 then  local __nuppT49,__nuppT50=__nuppT20(__nuppCleanup2,__nuppT34);  if not __nuppT49 then __nuppT33=__nuppT33+1; __nuppT32[__nuppT33]=__nuppT50 end; end; if not __nuppT29 then if __nuppT33>0 then __nuppT22(__nuppT18(__nuppT30,__nuppT32,1),0) else __nuppT22(__nuppT30,0) end end; if __nuppT33>0 then if __nuppT33>1 then __nuppT22(__nuppT18(__nuppT32[1],__nuppT32,2),0) else __nuppT22(__nuppT32[1],0) end end; if __nuppT30=="return" then  return __nuppT23(__nuppT31,1,__nuppT31.n)  end; end
end






function File:transferTo(destination) 
if self . _closed then
return nil , "the file is closed"
end
local total = 0
while true do
local chunk , why = self : read ( READ_SIZE )
if chunk == nil then
return nil , why
end
if # ( chunk ) == 0 then
return total , nil
end
local wrote , failure = destination : write ( chunk )
if not wrote then
return nil , failure
end
total = total + # ( chunk )
end
end







function File:write(bytes) 
if self . _closed then
return false , "the file is closed"
end
if type ( bytes ) ~= "string" then
error ( "nupp: io.files File:write needs a string" , 2 )
end
local output = ffi . new ( "size_t[1]" )
local status = C . nuppNativeFileWrite ( self . _handle , bytes , # bytes , output )
if status ~= 0 then
return false , ffi . string ( C . nuppNativeLastError ( ) )
end

local wrote = tonumber ( output [ 0 ] )
if wrote ~= # bytes then
return false , "the native files provider performed a short write"
end

return true , nil
end






function File:writeSpan(source) 
if self . _closed then
return nil , "the file is closed"
end
local count = source .count
if count == 0 then
return 0 , nil
end
local pointer = source : ref ( )
local output = ffi . new ( "size_t[1]" )
local status = fileWrite ( self . _handle , pointer , count , output )
if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end

local wrote = tonumber ( output [ 0 ] )
if wrote < 0 or wrote > count then
return nil , "the native files provider returned an invalid write count"
end

return wrote , nil
end






function File:size() 
if self . _closed then
error ( "nupp: io.files File is closed" , 2 )
end
local output = ffi . new ( "int64_t[1]" )
local status = C . nuppNativeFileSize ( self . _handle , output )
if status ~= 0 then
return nil , io . toError ( ffi . string ( C . nuppNativeLastError ( ) ) )
end

return tonumber ( output [ 0 ] ) , nil
end








function File:seek(offset, origin) 
if self . _closed then
error ( "nupp: io.files File is closed" , 2 )
end
local whence = ORIGINS [ origin or "set" ]
if whence == nil then
error ( "nupp: io.files has no seek origin named " .. tostring ( origin ) , 2 )
end
local output = ffi . new ( "int64_t[1]" )
local status = C . nuppNativeFileSeek ( self . _handle , whole ( offset or 0 , "seek offset" , 2 ) , whence , output )
if status ~= 0 then
return nil , io . toError ( ffi . string ( C . nuppNativeLastError ( ) ) )
end

return tonumber ( output [ 0 ] ) , nil
end





function File:position() 
return self : seek ( 0 , "current" )
end






function File:flush() 
if self . _closed then
return false , "the file is closed"
end

return done ( C . nuppNativeFileFlush ( self . _handle ) )
end




function File:isReleased() 
return self . _closed
end ;_G.nupp.__reflect.link(File,__nuppT1[1],{ }) ;__nuppExports["File"]=File











function File . close ( self ) 
local state = self
if state . _closed then
return
end
state . _closed = true
local handle = state . _handle
state . _handle = nil
state . _scratch = nil
state . _capacity = 0
C . nuppNativeFileRelease ( handle )
end











local TemporaryPath = {} TemporaryPath.__index = TemporaryPath







function TemporaryPath:toString() 
return self . _text
end




function TemporaryPath:path() 
return paths . newPath ( self . _text )
end






function TemporaryPath:persist(destination) 
if self . _closed then
return false , io . toError ( "the temporary path is released" , "closed" )
end
local to = named ( destination , "destination path" , 2 )
local moved , reason = done ( C . nuppNativeFilesRename ( slice ( self . _text ) , slice ( to ) ) )
if not moved then
return false , io . toError ( reason )
end
self . _closed = true

return true , nil
end




function TemporaryPath:isReleased() 
return self . _closed
end ;_G.nupp.__reflect.link(TemporaryPath,__nuppT1[2],{ }) ;__nuppExports["TemporaryPath"]=TemporaryPath
















function TemporaryPath . close ( self ) 
local state = self
if state . _closed then
return
end
state . _closed = true
C . nuppNativeFilesRemove ( slice ( state . _text ) , state . _directory and 1 or 0 )
end

;
( TemporaryPath ) . __tostring = function ( self ) 
return self : toString ( )
end



scratch = function ( self , count ) 
local state = self
if count > ( state . _capacity ) then
local size = ( state . _capacity ) * 2
if size < count then
size = count
end
if size < 65536 then
size = 65536
end
state . _scratch = __nuppFfi.new("uint8_t[?]" , size )
state . _capacity = size
end

return state . _scratch
end


local function described ( path , follow , level ) 
local text = named ( path , "path" , level + 1 )
local record = __nuppFfi.new("struct NuppNativeFilesInfo[1]" )
if C . nuppNativeFilesInfo ( slice ( text ) , follow and 1 or 0 , record ) ~= 0 then
return nil
end
local found = nil





do
found = {
kind = record [ 0 ] . kind ,
readOnly = record [ 0 ] . read_only ~= 0 ,
size = record [ 0 ] . size ,
modified = record [ 0 ] . modified ,
}
end

return found
end




local waits = { }

local function transferState ( handle ) 
local output = ffi . new ( "uint32_t[1]" )
local status = C . nuppNativeFilesTransferStatus ( handle , output )
if status ~= 0 then
return 2 , ffi . string ( C . nuppNativeLastError ( ) )
end

local state = tonumber ( output [ 0 ] )
if state < 0 or state > 3 then
return 2 , "the native files provider returned an invalid transfer status"
end
if state == 2 then
return state , ffi . string ( C . nuppNativeLastError ( ) )
end

return state , nil
end







local function harvest ( ) 
local moved = 0
local index = # waits
while index > 0 do
local entry = waits [ index ]
if transferState ( entry . handle ) ~= 0 then
waits [ index ] = waits [ # waits ]
waits [ # waits ] = nil
moved = moved + 1
entry . resume ( true )
end
index = index - 1
end

return moved
end

local function forget ( entry ) 
for index = 1 , # waits do
if waits [ index ] == entry then
waits [ index ] = waits [ # waits ]
waits [ # waits ] = nil

return
end
end
end



local function await ( handle ) 
if transferState ( handle ) ~= 0 then
return
end
suspension . suspend ( "file transfer" , function ( resume , context ) 
local entry = { handle = handle , resume = resume , }
context : source ( "nupp-files" , native . READINESS_PRIORITY , native . pump ( harvest ) )
waits [ # waits + 1 ] = entry


if transferState ( handle ) ~= 0 then
forget ( entry )
resume ( true )

return nil
end







local cancelled = false

return function ( ) 
if cancelled then
return
end
cancelled = true
forget ( entry )
C . nuppNativeFilesTransferCancel ( handle )
C . nuppNativeFilesTransferRelease ( handle )
end
end )
end



local function settled ( handle ) 
if handle == nil or handle == 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end
await ( handle )
local state , failure = transferState ( handle )
if state ~= 1 then
local reason = failure or ( state == 3 and "file transfer was cancelled" or "file transfer failed" )
C . nuppNativeFilesTransferRelease ( handle )

return nil , reason
end

return handle , nil
end

local function transferred ( handle ) 
local ready , reason = settled ( handle )
if ready == nil then
return false , reason
end
C . nuppNativeFilesTransferRelease ( ready )

return true , nil
end

local function fetched ( handle ) 
local ready , reason = settled ( handle )
if ready == nil then
return nil , reason
end
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesTransferTakeBytes ( ready , output )
if status ~= 0 then
local failure = ffi . string ( C . nuppNativeLastError ( ) )
C . nuppNativeFilesTransferRelease ( ready )

return nil , failure
end
local out = native . bytes ( output [ 0 ] )
C . nuppNativeFilesTransferRelease ( ready )

return out , nil
end






local function optional ( options , field , level ) 
local value = options ~= nil and ( options ) [ field ] or nil
if value == nil then
return ""
end
if type ( value ) ~= "string" then
error ( "nupp: io.files temporary " .. field .. " must be a string" , level )
end

return value
end


local function temporary ( options , directory , level ) 
if options ~= nil and type ( options ) ~= "table" then
error ( "nupp: io.files temporary options must be a table" , level )
end
local where = options ~= nil and ( options ) . directory or nil
local root = where ~= nil and named ( where , "temporary directory" , level + 1 ) or ""
local prefix = optional ( options , "prefix" , level + 1 )
local suffix = optional ( options , "suffix" , level + 1 )

local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesCreateTemporary (
slice ( root ) ,
slice ( prefix ) ,
slice ( suffix ) ,
directory and 1 or 0 ,
output
)

return answer ( status , output )
end


local function payload ( value , what , level ) 
if type ( value ) == "string" then
return tostring ( value )
end
if type ( value ) == "table" and ( value ) . getString ~= nil then
return ( value ) : getString ( )
end
error ( "nupp: io.files " .. what .. " must be bytes or a byte view" , level )
end



















info=function ( path ) 
local found = described ( path , true , 2 )
if found == nil then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end

return _G.setmetatable({ kind =
KINDS [ tonumber ( found . kind ) ] or "other" ,  size =
tonumber ( found . size ) ,  modified =


( found . modified ) * 1000 ,  readOnly =
found . readOnly }, Info)
, nil
end ;__nuppExports["info"]=info





exists=function ( path ) 
return described ( path , true , 2 ) ~= nil
end ;__nuppExports["exists"]=exists





isFile=function ( path ) 
local found = described ( path , true , 2 )

return found ~= nil and found . kind == 1
end ;__nuppExports["isFile"]=isFile





isDirectory=function ( path ) 
local found = described ( path , true , 2 )

return found ~= nil and found . kind == 2
end ;__nuppExports["isDirectory"]=isDirectory





isSymlink=function ( path ) 
local found = described ( path , false , 2 )

return found ~= nil and found . kind == 4
end ;__nuppExports["isSymlink"]=isSymlink






readLink=function ( path ) 
local text = named ( path , "path" , 2 )
local output = ffi . new ( "uint64_t[1]" )
local target , reason = answer ( C . nuppNativeFilesReadLink ( slice ( text ) , output ) , output )
if target == nil then
return nil , reason
end

return paths . newPath ( target ) , nil
end ;__nuppExports["readLink"]=readLink












createSymlink=function (
target ,
link ,
kind
) 
local to = named ( target , "symlink target" , 2 )
local at = named ( link , "symlink path" , 2 )
if kind ~= nil and kind ~= "file" and kind ~= "directory" then
error ( "nupp: io.files symlink kind must be 'file' or 'directory'" , 2 )
end

return done ( C . nuppNativeFilesCreateSymlink ( slice ( to ) , slice ( at ) , kind == "directory" and 1 or 0 ) )
end ;__nuppExports["createSymlink"]=createSymlink







setReadOnly=function ( path , readOnly ) 
local text = named ( path , "path" , 2 )
if type ( readOnly ) ~= "boolean" then
error ( "nupp: io.files readOnly must be a boolean" , 2 )
end

return done ( C . nuppNativeFilesSetReadOnly ( slice ( text ) , readOnly and 1 or 0 ) )
end ;__nuppExports["setReadOnly"]=setReadOnly








createDirectory=function ( path ) 
local text = named ( path , "path" , 2 )

return done ( C . nuppNativeFilesCreateDirectory ( slice ( text ) ) )
end ;__nuppExports["createDirectory"]=createDirectory







remove=function ( path , recursive ) 
local text = named ( path , "path" , 2 )
if recursive ~= nil and type ( recursive ) ~= "boolean" then
error ( "nupp: io.files recursive must be a boolean" , 2 )
end

return done ( C . nuppNativeFilesRemove ( slice ( text ) , recursive and 1 or 0 ) )
end ;__nuppExports["remove"]=remove







rename=function ( from , to ) 
local source = named ( from , "source path" , 2 )
local destination = named ( to , "destination path" , 2 )

return done ( C . nuppNativeFilesRename ( slice ( source ) , slice ( destination ) ) )
end ;__nuppExports["rename"]=rename

















list=function ( path ) 
local text = named ( path , "path" , 2 )
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesList ( slice ( text ) , output )
if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end

local blob = native . bytes ( output [ 0 ] )
local entries = { }
local at = 1
while at <= # blob do
local stop = blob : find ( "\0" , at + 1 , true )
entries [
# entries + 1
] = _G.setmetatable({ kind =  ENTRIES [ blob : sub ( at , at ) ] or "other" ,  name =  blob : sub ( at + 1 , stop - 1 ) }, Entry)
at = stop + 1
end

return entries , nil
end ;__nuppExports["list"]=list




















glob=function ( pattern ) 
if type ( pattern ) ~= "string" then
error ( "nupp: io.files glob pattern must be a string" , 2 )
end
local text = pattern
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesGlob ( slice ( text ) , output )
if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end
local blob = native . bytes ( output [ 0 ] )
local matches = { }
local at = 1
while at <= # blob do
local stop = blob : find ( "\0" , at , true )
if stop == nil then
matches [ # matches + 1 ] = paths . newPath ( blob : sub ( at ) )
do break end
end
matches [ # matches + 1 ] = paths . newPath ( blob : sub ( at , ( stop ) - 1 ) )
at = ( stop ) + 1
end

return matches , nil
end ;__nuppExports["glob"]=glob















read=function ( path ) 
local text = named ( path , "path" , 2 )
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesTransferSubmitRead ( slice ( text ) , output )

if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end

return fetched ( output [ 0 ] )
end ;__nuppExports["read"]=read







write=function ( path , bytes ) 
local text = named ( path , "path" , 2 )
local out = payload ( bytes , "contents" , 2 )
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesTransferSubmitWrite ( slice ( text ) , slice ( out ) , 0 , output )

if status ~= 0 then
return false , ffi . string ( C . nuppNativeLastError ( ) )
end

return transferred ( output [ 0 ] )
end ;__nuppExports["write"]=write







append=function ( path , bytes ) 
local text = named ( path , "path" , 2 )
local out = payload ( bytes , "contents" , 2 )
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesTransferSubmitWrite ( slice ( text ) , slice ( out ) , 1 , output )

if status ~= 0 then
return false , ffi . string ( C . nuppNativeLastError ( ) )
end

return transferred ( output [ 0 ] )
end ;__nuppExports["append"]=append











writeAtomic=function ( path , bytes ) 
local text = named ( path , "path" , 2 )
local out = payload ( bytes , "contents" , 2 )
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesTransferSubmitWrite ( slice ( text ) , slice ( out ) , 2 , output )

if status ~= 0 then
return false , ffi . string ( C . nuppNativeLastError ( ) )
end

return transferred ( output [ 0 ] )
end ;__nuppExports["writeAtomic"]=writeAtomic







copy=function ( from , to ) 
local source = named ( from , "source path" , 2 )
local destination = named ( to , "destination path" , 2 )
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFilesTransferSubmitCopy ( slice ( source ) , slice ( destination ) , output )

if status ~= 0 then
return false , ffi . string ( C . nuppNativeLastError ( ) )
end

return transferred ( output [ 0 ] )
end ;__nuppExports["copy"]=copy








pendingTransfers=function ( ) 
requireFiles ( )
local output = ffi . new ( "size_t[1]" )
if C . nuppNativeFilesTransferPending ( output ) ~= 0 then
return 0
end

return tonumber ( output [ 0 ] )
end ;__nuppExports["pendingTransfers"]=pendingTransfers























open=function ( path , mode ) 
local text = named ( path , "path" , 2 )
local selected = MODES [ mode or "r" ]
if selected == nil then
error ( "nupp: io.files has no mode named " .. tostring ( mode ) , 2 )
end
local output = ffi . new ( "uint64_t[1]" )
local status = C . nuppNativeFileOpen ( slice ( text ) , selected , output )
if status ~= 0 then
return nil , ffi . string ( C . nuppNativeLastError ( ) )
end

return _G.setmetatable({ _handle =  output [ 0 ] ,  _closed =  false ,  _scratch =  nil ,  _capacity =  0 }, File) , nil
end ;__nuppExports["open"]=open


























createTemporaryFile=function ( options ) 
local text , reason = temporary ( options , false , 2 )
if text == nil then
return nil , reason
end

return _G.setmetatable({ _text =  text ,  _directory =  false ,  _closed =  false }, TemporaryPath) , nil
end ;__nuppExports["createTemporaryFile"]=createTemporaryFile







createTemporaryDirectory=function ( options ) 
local text , reason = temporary ( options , true , 2 )
if text == nil then
return nil , reason
end

return _G.setmetatable({ _text =  text ,  _directory =  true ,  _closed =  false }, TemporaryPath) , nil
end ;__nuppExports["createTemporaryDirectory"]=createTemporaryDirectory







userFolder=function ( which ) 
local index = FOLDERS [ which ]
if index == nil then
error ( "nupp: io.files has no user folder named " .. tostring ( which ) , 2 )
end

requireFiles ( )
local output = ffi . new ( "uint64_t[1]" )
local folder , reason = answer ( C . nuppNativeFilesUserFolder ( index , output ) , output )
if folder == nil then
return nil , reason
end

return paths . newPath ( folder ) , nil
end ;__nuppExports["userFolder"]=userFolder


capabilities=function ( ) 
return ( _G.setmetatable({ available =
true ,  arbitraryPaths =
true ,  symbolicLinks =
true ,  readOnlyAttributes =
true ,  glob =
true ,  rename =
true ,  atomicWrite =
true ,  temporaryPaths =
true ,  concurrentOpenHandles =
true ,  currentDirectory =
true ,  userFolders =
true ,  executableDirectory =
true ,  persistentStorageRequest =
true }, messages.Capabilities) )

end ;__nuppExports["capabilities"]=capabilities

local APPLICATION_BASES = { configuration = 0 , data = 1 , cache = 2 , }

applicationPath=function (
kind ,
organization ,
application
) 
local code = APPLICATION_BASES [ kind ]
if code == nil then
return nil , "unknown application path kind"
end
requireFiles ( )
local output = ffi . new ( "uint64_t[1]" )
local base , reason = answer ( C . nuppNativeFilesApplicationBase ( code , output ) , output )
if base == nil then
return nil , reason
end
local value = appPaths . native ( base , organization , application )
local made , failure = done ( C . nuppNativeFilesCreateDirectory ( slice ( value : toString ( ) ) ) )
if not made then
return nil , failure
end

return value , nil
end ;__nuppExports["applicationPath"]=applicationPath

executableDirectory=function ( ) 
requireFiles ( )
local output = ffi . new ( "uint64_t[1]" )
local executable , reason = answer ( C . nuppNativeFilesExecutablePath ( output ) , output )
if executable == nil then
return nil , reason
end
local parent = paths . newPath ( executable ) : parent ( )
if parent == nil then
return nil , "the executable path has no parent directory"
end

return parent , nil
end ;__nuppExports["executableDirectory"]=executableDirectory

requestPersistentStorage=function ( ) 
return true , nil
end ;__nuppExports["requestPersistentStorage"]=requestPersistentStorage
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[File]="nupp.runtime.provider.nativefiles\0File";__nuppWorkerRecords[TemporaryPath]="nupp.runtime.provider.nativefiles\0TemporaryPath"; end);if not __nuppOk then package.loaded["nupp.runtime.provider.nativefiles"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.nativefiles"]=__nuppExports;return __nuppExports