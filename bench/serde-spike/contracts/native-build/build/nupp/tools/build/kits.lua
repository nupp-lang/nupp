_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















local files = require ( "nupp.io.files" )
local fs = require ( "nupp.compiler.fs" )
local hash = require ( "nupp.compiler.hash" )
local packaging = require ( "nupp.tools.build.package" )
local stubs = require ( "nupp.tools.build.stubs" )

local kits = { }














local function manifest ( directory ) 
local text = fs . readFile ( fs . join ( directory , "kit.json" ) )
if text == nil then
return nil
end
local json = require ( "nupp.codec.json" )
local value = json . decode ( text , json . NULL )
if type ( value ) ~= "table" then
return nil
end

return value
end


function kits . target ( directory ) 
local value = manifest ( directory )
if value == nil or type ( value . target ) ~= "string" then
return nil
end

return value . target
end


local function features ( directory ) 
local carried = { }
local value = manifest ( directory )
if value ~= nil and type ( value . features ) == "string" then
for name in ( value . features ) : gmatch ( "[^,%s]+" ) do
carried [ name ] = true
end
end

return carried
end


local function lacking ( directory , required ) 
local carried = features ( directory )
for _ , name in ipairs ( required ) do
if not carried [ name ] then
return "the link kit at " .. directory .. " was built without host feature " .. name
end
end

return nil
end



function kits . named ( directory , platform ) 
local own = kits . target ( directory )
if own == platform then
return directory , nil
end
local nested = fs . join ( directory , platform )
if kits . target ( nested ) == platform then
return nested , nil
end
if own ~= nil then
return nil , "NUPP_KIT_DIR names a kit for " .. own .. ", not " .. platform
end

return nil , "NUPP_KIT_DIR (" .. directory .. ") holds no link kit for " .. platform
end



function kits . cacheRoot ( ) 
local named = os . getenv ( "NUPP_KIT_CACHE" )
if named ~= nil and named ~= "" then
return named
end
local appData = os . getenv ( "LOCALAPPDATA" )
if appData ~= nil and appData ~= "" then
return fs . join ( appData , "nupp/kits" )
end
local home = os . getenv ( "HOME" ) or "."
local host = require ( "nupp.compiler.targetlayout" ) . hostKey ( )
if host ~= nil and ( host ) : match ( "%-apple%-darwin$" ) ~= nil then
return fs . join ( home , "Library/Caches/nupp/kits" )
end
local xdg = os . getenv ( "XDG_CACHE_HOME" )

return fs . join ( ( xdg ~= nil and xdg ~= "" ) and xdg or fs . join ( home , ".cache" ) , "nupp/kits" )
end


function kits . record ( platform ) 
local catalog , catalogErr = stubs . catalog ( )
if catalog == nil then
return nil , catalogErr
end
local record = type ( catalog . kits ) == "table" and catalog . kits [ platform ] or nil
if record == nil then
return nil , "the stub catalog " .. tostring ( catalog . catalogRelease ) .. " has no link kit for " .. platform
end
local where = "kit record for " .. platform
if type ( record ) ~= "table" or record . platform ~= platform then
return nil , where .. " claims platform " .. tostring ( type ( record ) == "table" and record . platform or nil )
end
if record . catalogRelease ~= catalog . catalogRelease or record . hostAbi ~= packaging . hostAbiVersion then
return nil , where .. " belongs to another release"
end
if not stubs . safeComponent ( record . artifact ) then
return nil , where .. " has an unsafe artifact name"
end
if type ( record . sha256 ) ~= "string" or # record . sha256 ~= 64 or not record . sha256 : match ( "^[0-9a-f]+$" ) then
return nil , where .. " requires a lowercase SHA-256"
end
if type ( record . size ) ~= "number" or record . size < 1 or record . size ~= math . floor ( record . size ) then
return nil , where .. " requires a positive integer size"
end
if type ( record . hostFeatures ) ~= "table" then
return nil , where .. " requires hostFeatures"
end
if record . url ~= nil and ( type ( record . url ) ~= "string" or not record . url : match ( "^https://" ) ) then
return nil , where .. " requires an HTTPS url"
end

return record , nil
end


local function unpack ( record , archive , entry ) 
local codegen = require ( "nupp.compiler.aot.llvm.codegen" )
local nonce = hash . sha256 ( entry .. tostring ( { } ) .. tostring ( os . clock ( ) ) ) : sub ( 1 , 16 )
local staging = entry .. ".tmp-" .. nonce
fs . mkdir ( staging )



local function abandon ( why ) 
if fs . exists ( staging ) then
files . remove ( staging , true )
end

return why
end

local err = codegen . unpackKit ( archive , record . sha256 , record . size , staging )
if err ~= nil then
return abandon ( "cannot unpack the link kit " .. record . artifact .. ": " .. err )
end
if kits . target ( staging ) ~= record . platform then
return abandon ( "the link kit " .. record . artifact .. " does not link for " .. record . platform )
end


local renamed = os . rename ( staging , entry )
if not renamed then
abandon ( nil )
if kits . target ( entry ) ~= record . platform then
return "cannot install the link kit at " .. entry
end
end

return nil
end



function kits . install ( record ) 
local directory = fs . join ( kits . cacheRoot ( ) , fs . join ( record . catalogRelease , fs . join ( record . platform , record . sha256 ) ) )
if kits . target ( directory ) == record . platform then
return directory , nil
end
fs . mkdir ( fs . dirname ( directory ) )
local stubDir = os . getenv ( "NUPP_STUB_DIR" )
local archive = stubDir ~= nil and stubDir ~= "" and fs . join ( stubDir , record . artifact ) or nil
if archive == nil or not fs . exists ( archive ) then
if record . url == nil then
return nil , ("the link kit %s for %s is not cached and its record names no URL; put it in NUPP_STUB_DIR")

: format ( record . artifact , record . platform )
end
archive = directory .. ".download"
local codegen = require ( "nupp.compiler.aot.llvm.codegen" )
local fetchErr = codegen . fetchKit ( record . url , archive , record . sha256 , record . size )
if fetchErr ~= nil then
return nil , "cannot fetch the link kit for " .. record . platform .. ": " .. fetchErr
end
end
local unpackErr = unpack ( record , archive , directory )
if archive == directory .. ".download" then
os . remove ( archive )
end
if unpackErr ~= nil then
return nil , unpackErr
end

return directory , nil
end




function kits . resolve (
platform ,
required ,
build
) 
local named = os . getenv ( "NUPP_KIT_DIR" )
local found = nil
if named ~= nil and named ~= "" then
local kit , err = kits . named ( named , platform )
if kit == nil then
return nil , err
end
found = kit
else
local record , recordErr = kits . record ( platform )
if record ~= nil then
local kit , installErr = kits . install ( record )
if kit == nil then
return nil , installErr
end
found = kit
elseif build ~= nil then
local kit , err = ( build ) ( )
if kit == nil then
return nil , "cannot build the link kit:\n" .. tostring ( err )
end
found = kit
else
return nil , tostring ( recordErr ) .. "; name a kit with NUPP_KIT_DIR"
end
end
local short = lacking ( found , required )
if short ~= nil then
return nil , short
end

return found , nil
end

local __nuppExportValue= kits ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.kits"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.kits"]=__nuppExports;return __nuppExports