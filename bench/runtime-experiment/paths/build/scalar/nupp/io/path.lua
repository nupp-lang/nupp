_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.io.path"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local currentDirectory;__nuppExports["currentDirectory"]=function(...) return currentDirectory(...) end;local newPath;__nuppExports["newPath"]=function(...) return newPath(...) end;local separator;__nuppExports["separator"]=function(...) return separator(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.io.path\0runtime\0001") };



















































































































const environment = require ( "nupp.io.path.provider" )
const pathtext = require ( "nupp.io.path.pathtext" )





local SEPARATOR = environment . separator ( )
local WINDOWS = SEPARATOR == "\\"



local textOf
local joined
local raw

const PATH_CACHE_CAPACITY = 1024
local pathCache = { }
local pathCacheSize = 0
local pathCacheNewest = nil
local pathCacheOldest = nil



local Path = {} Path.__index = Path






function Path:toString() 
return self . _text
end





function Path:join(...) 
return raw ( joined ( self , select ( "#" , ... ) , ... ) )
end




function Path:normalize() 
return raw ( pathtext . normalize ( self . _text , WINDOWS ) )
end








function Path:absolute() 
if # self . _text == 0 then
return nil , "cannot make an empty path absolute"
end
local text = self . _text
if not pathtext . isAbsolute ( text , WINDOWS ) then
local current , reason = environment . currentDirectory ( )
if current == nil then
return nil , reason
end
local drive = WINDOWS and text : match ( "^([A-Za-z]:)" ) or nil
if drive ~= nil then
local currentDrive = ( current ) : match ( "^([A-Za-z]:)" )
if currentDrive == nil or currentDrive : lower ( ) ~= drive : lower ( ) then
return nil , "cannot resolve a drive-relative path from another drive"
end
local suffix = text : sub ( # drive + 1 )
text = # suffix == 0 and current or pathtext . pushPart ( current , suffix , true )
else
text = pathtext . pushPart ( current , text , WINDOWS )
end
end

return raw ( pathtext . clean ( text , WINDOWS ) ) , nil
end






function Path:resolve(...) 
local absolute , reason = self : absolute ( )
if not absolute then
return nil , reason
end

return absolute : join ( ... ) : normalize ( ) , nil
end








function Path:canonicalize() 
local text , reason = environment . canonicalize ( self . _text )
if text == nil then
return nil , reason
end

return raw ( pathtext . finish ( text , WINDOWS ) ) , nil
end







function Path:relativeTo(base) 
local text , reason = pathtext . relative ( self . _text , textOf ( base ) , WINDOWS )
if text == nil then
return nil , reason
end

return raw ( text ) , nil
end




function Path:parent() 
local answer = pathtext . part ( self . _text , 0 , WINDOWS )
if answer == nil then
return nil
end

return raw ( answer )
end




function Path:fileName() 
return pathtext . part ( self . _text , 1 , WINDOWS )
end




function Path:stem() 
return pathtext . part ( self . _text , 2 , WINDOWS )
end




function Path:extension() 
return pathtext . part ( self . _text , 3 , WINDOWS )
end







function Path:withFileName(name) 
return raw ( pathtext . with ( self . _text , name , false , WINDOWS ) )
end







function Path:withExtension(extension) 
return raw ( pathtext . with ( self . _text , extension , true , WINDOWS ) )
end




function Path:isAbsolute() 
return pathtext . isAbsolute ( self . _text , WINDOWS )
end




function Path:isRelative() 
return not self : isAbsolute ( )
end ;_G.nupp.__reflect.link(Path,__nuppT1[1],{ }) ;__nuppExports["Path"]=Path









raw = function ( text ) 
local found = pathCache [ text ]
if found ~= nil then
if found ~= pathCacheNewest then
local older , newer = found . older , found . newer
if older ~= nil then
older . newer = newer
else
pathCacheOldest = newer
end
if newer ~= nil then
newer . older = older
end
found . older = pathCacheNewest
found . newer = nil
pathCacheNewest . newer = found
pathCacheNewest = found
end

return found . value
end

local value = setmetatable ( { _text = text , } , Path )
local entry = { value = value , older = pathCacheNewest , newer = nil }
if pathCacheNewest ~= nil then
pathCacheNewest . newer = entry
else
pathCacheOldest = entry
end
pathCacheNewest = entry
pathCache [ text ] = entry
pathCacheSize = pathCacheSize + 1
if pathCacheSize > 1024 then
local evicted = pathCacheOldest
pathCacheOldest = evicted . newer
pathCacheOldest . older = nil
pathCache [ evicted . value : toString ( ) ] = nil
pathCacheSize = pathCacheSize - 1
end

return value
end



joined = function ( first , count , ... ) 
local carried = textOf ( first )
for index = 1 , count do
carried = pathtext . pushPart ( carried , textOf ( select ( index , ... ) ) , WINDOWS )
end

return pathtext . finish ( carried , WINDOWS )
end


textOf = function ( value ) 
if type ( value ) == "string" then
return value
end

return ( value ) . _text
end

;
( Path ) . __tostring = function ( self ) 
return self : toString ( )
end

;
( Path ) . __eq = function ( left , right ) 
return left : toString ( ) == right : toString ( )
end















newPath=function ( first , ... ) 
return raw ( joined ( first , select ( "#" , ... ) , ... ) )
end ;__nuppExports["newPath"]=newPath





currentDirectory=function ( ) 
local text , reason = environment . currentDirectory ( )
if text == nil then
return nil , reason
end

return raw ( pathtext . finish ( text , WINDOWS ) ) , nil
end ;__nuppExports["currentDirectory"]=currentDirectory




separator=function ( ) 
return SEPARATOR
end ;__nuppExports["separator"]=separator
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Path]="nupp.io.path\0Path"; end);if not __nuppOk then package.loaded["nupp.io.path"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.path"]=__nuppExports;return __nuppExports