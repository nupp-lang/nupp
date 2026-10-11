_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();const __nuppFfi = require("ffi"); local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.mem.sharedbytes\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.mem.sharedbytes\0runtime\0002") };







































local span = require ( "nupp.mem.span" )
















local loadedNative , nativeModule = pcall ( require , "nupp.mem.sharedbytes.native" )
if not loadedNative then
if tostring ( nativeModule ) : find ( "module 'nupp.mem.sharedbytes.native' not found" , 1 , true ) then
error ( "nupp: nupp.mem.sharedbytes needs the Nupp engine host, which a stamped binary provides" , 0 )
end
error ( nativeModule , 0 )
end
local native = nativeModule
local ffi = require ( "ffi" )

local foreignByteSpan = rawget (
span ,
"__foreignByteSpan"
)
local foreignSpan = rawget (
span ,
"__foreignSpan"
)

local sharedbytes = { }




sharedbytes.Region = {} sharedbytes.Region.__index = sharedbytes.Region ;_G.nupp.__reflect.link(sharedbytes.Region,__nuppT1[1],{ })





















local RegionMT = { __index = sharedbytes . Region }



rawset ( RegionMT , "__eq" , function ( left , right ) 
return native . pointer ( left . _handle ) == native . pointer ( right . _handle )
and left . _first == right . _first
and left . _length == right . _length
end )

local function wrap ( handle , first , length ) 
return setmetatable ( { _handle = handle , _first = first , _length = length } , RegionMT )
end

function sharedbytes . Region : length ( ) 
return self . _length
end




local function inside ( length , offset , count ) 
return offset % 1 == 0 and count % 1 == 0 and offset >= 0 and count >= 0 and offset + count <= length
end


function sharedbytes . Region : slice ( offset , count ) 
if not inside ( self . _length , offset , count ) then
error ( "nupp: a region slice is out of bounds" , 2 )
end

return wrap ( self . _handle , self . _first + offset , count )
end


function sharedbytes . Region : view ( offset , count ) 
local from = offset == nil and 0 or offset
local taking = count == nil and self . _length - from or count
if not inside ( self . _length , from , taking ) then
error ( "nupp: a region view is out of bounds" , 2 )
end

return foreignByteSpan ( self , native . pointer ( self . _handle ) , self . _first - 1 + from , taking )
end


function sharedbytes . Region : viewAs ( element ) 
local width = ffi . sizeof ( element )
local alignment = ffi . alignof ( element )
local byteOffset = self . _first - 1
if width < 1 or self . _length % width ~= 0 then
error ( "nupp: a typed region view must contain complete elements" , 2 )
end
local pointer = native . pointer ( self . _handle )
local address = tonumber ( __nuppFfi.cast("uint64_t" , pointer ) )
if self . _length > 0 and ( address + byteOffset ) % alignment ~= 0 then
error ( "nupp: a typed region view is not suitably aligned" , 2 )
end

local bytes = __nuppFfi.cast("uint8_t *" , pointer )
do
local start = ( bytes + byteOffset )
return foreignSpan ( self , start , 0 , _G.math.floor(( self . _length ) / ( width )) , element )
end
end


function sharedbytes . Region : toString ( ) 
local text = native . text ( self . _handle , self . _first , self . _first + self . _length - 1 )
if text == nil then
error ( "nupp: a region's storage has been released" , 2 )
end

return text
end



function sharedbytes . copy ( text ) 
local handle , length = native . fromString ( text )
if handle == nil then
error ( "nupp: cannot allocate a region" , 2 )
end

return wrap ( handle , 1 , length )
end






function sharedbytes . readFile ( path ) 
local handle , problem = native . readFile ( path )
if handle == nil then
return nil , tostring ( problem )
end

return wrap ( handle , 1 , native . length ( handle ) ) , nil
end



sharedbytes.BuilderToken = {}




sharedbytes.Builder = {} sharedbytes.Builder.__index = sharedbytes.Builder ;_G.nupp.__reflect.link(sharedbytes.Builder,__nuppT1[2],{ })

























local BuilderMT = { __index = sharedbytes . Builder }


function sharedbytes . Builder : append ( chunk ) 
local accepted , problem = native . builderAppend ( self . _handle , chunk )
if not accepted then
if problem == "open" then
error ( "nupp: a region builder has an open reservation" , 2 )
end
error ( "nupp: cannot grow a region builder" , 2 )
end
end



function sharedbytes . Builder : reserve ( count ) 
if count < 0 or count ~= math . floor ( count ) then
error ( "nupp: a region reservation must be a nonnegative integer" , 2 )
end
local pointer , problem = native . builderReserve ( self . _handle , count )
if pointer == nil then
if problem == "open" then
error ( "nupp: a region builder already has an open reservation" , 2 )
end
error ( "nupp: cannot grow a region builder" , 2 )
end

local typed = __nuppFfi.cast("uint8_t *" , pointer )

return span . writeCarray ( typed , count )
end



function sharedbytes . Builder : commit ( written ) 
if written < 0 or written ~= math . floor ( written ) then
error ( "nupp: a region commit must be a nonnegative integer" , 2 )
end
if not native . builderCommit ( self . _handle , written ) then
error ( "nupp: a commit does not match the builder's open reservation" , 2 )
end
end



function sharedbytes . Builder . freeze ( self ) 


local builder = self
local handle , length = native . builderFreeze ( builder . _handle )
if handle == nil then
if length == "open" then
error ( "nupp: a region builder has an open reservation" , 2 )
end
error ( "nupp: a region builder was already frozen" , 2 )
end

return wrap ( handle , 1 , length )
end



local releaseBuilder = rawget ( native , "builderRelease" )

function sharedbytes . Builder . drop ( self ) 
local builder = self
if releaseBuilder ~= nil then
releaseBuilder ( builder . _handle )
end
end



function sharedbytes . newBuilder ( ) 
local handle = native . builderNew ( )
if handle == nil then
error ( "nupp: cannot allocate a region builder" , 2 )
end

return setmetatable ( { _handle = handle } , BuilderMT )
end




rawset ( _G . nupp , "__regionMetatable" , RegionMT )
rawset ( sharedbytes , "__regionParts" , function ( region ) 
return region . _handle , region . _first , region . _length
end )
rawset ( sharedbytes , "__regionFromParts" , function ( handle , first , length ) 
return wrap ( handle , first , length )
end )

sharedbytes . Region = sharedbytes . Region
sharedbytes . Builder = sharedbytes . Builder
sharedbytes . BuilderToken = sharedbytes . BuilderToken

local __nuppExportValue= sharedbytes ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.mem.sharedbytes"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.mem.sharedbytes"]=__nuppExports;return __nuppExports