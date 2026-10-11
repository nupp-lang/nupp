_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppBuffer = require("nupp.text"); const __nuppNew = require("table.new"); local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


































local pathtext = __nuppNew(0,4)



pathtext . PREFIX = 0


pathtext . ROOT = 1


pathtext . PARENT = 2


pathtext . NORMAL = 3

const byte = string . byte
const SLASH = 47
const BACKSLASH = 92
const DOT = 46
const COLON = 58

local function isSeparator ( value , windows ) 
if value == nil then
return false
end

return value == 47 or ( windows and value == 92 )
end

local function isDriveLetter ( value ) 
if value == nil then
return false
end

return ( value >= 65 and value <= 90 ) or ( value >= 97 and value <= 122 )
end




local function isVerbatim ( text , windows ) 
if not windows or # text < 4 then
return false
end

return byte ( text , 1 ) == 92
and byte ( text , 2 ) == 92
and byte ( text , 3 ) == 63
and byte ( text , 4 ) == 92
end








function pathtext . prefixLength ( text , windows ) 
if not windows then
return 0
end
local length = # text
if length >= 2 and byte ( text , 2 ) == 58 and isDriveLetter ( byte ( text , 1 ) ) then
return 2
end
if length >= 2 and isSeparator ( byte ( text , 1 ) , windows ) and isSeparator ( byte ( text , 2 ) , windows ) then
local third = byte ( text , 3 )
if length >= 4 and ( third == 63 or third == 46 ) and isSeparator ( byte ( text , 4 ) , windows ) then






local at = 4
local parts = 1
local seen = 0
while seen < parts do
local begin = at + 1
while at < length and not isSeparator ( byte ( text , at + 1 ) , windows ) do
at = at + 1
end
seen = seen + 1
if seen == 1 and third == 63 and at - begin == 2 and text : sub ( begin , at ) : upper ( ) == "UNC" then
parts = 3
end
if seen < parts then
if at == length then
do break end
end
at = at + 1
end
end

return at
end


local at = 2
local seen = 0
while seen < 2 do
while at < length and not isSeparator ( byte ( text , at + 1 ) , windows ) do
at = at + 1
end
seen = seen + 1
if seen < 2 then
while at < length and isSeparator ( byte ( text , at + 1 ) , windows ) do
at = at + 1
end
if at == length then
do break end
end
end
end

return at
end

return 0
end








function pathtext . isAbsolute ( text , windows ) 
local prefix = pathtext . prefixLength ( text , windows )
local rooted = prefix < # text and isSeparator ( byte ( text , prefix + 1 ) , windows )
if windows and prefix >= 2 and byte ( text , 2 ) == 58 then
return rooted
end

return prefix ~= 0 or rooted
end












function pathtext . finish ( value , windows ) 
if not windows or isVerbatim ( value , windows ) then
return value
end

return ( value : gsub ( "\\" , "/" ) )
end











do
local function ks_a5aec1231ee04251_normalize_impl_loop_runtime ( ) 
for cursor = - 0 , 0 do return 1 / cursor > 0 end
return false
end
local loopVm = rawget ( _G , "jit" )
if loopVm == nil then error ( "AOT numeric-for runtime requires LuaJIT" , 0 ) end
loopVm . off ( ks_a5aec1231ee04251_normalize_impl_loop_runtime , true )
if ks_a5aec1231ee04251_normalize_impl_loop_runtime ( ) ~= true then
error ( "AOT numeric-for runtime mismatch (expected luajit-dual)" , 0 )
end
end
local ks_a5aec1231ee04251_normalize_impl_builder
do
local ks_a5aec1231ee04251_normalize_impl_builderRegistrar = "ks_register_a5aec1231ee04251_5e40cbbf873d89d7__neon"
local function ks_a5aec1231ee04251_normalize_impl_builderLoad ( ) 
local modules = rawget ( _G , "__nuppAotBuilderModules" ) or { }
rawset ( _G , "__nuppAotBuilderModules" , modules )
local here = debug . getinfo ( 1 , "S" ) . source : match ( "^@(.*)$" )
local directory = here and here : match ( "^(.*)[/\\]" ) or "."
local started = directory
for _ = 0 , 8 do
local path = directory .. "/lib/libpaths_aot.dylib"
local cacheKey = path .. "\0ks_register_a5aec1231ee04251_5e40cbbf873d89d7__neon"
local registered = modules [ cacheKey ]
if registered then return registered [ "normalizeImpl" ] end
do local __nuppT21=0; local  __nuppT27 ; local __nuppT22,__nuppT23,__nuppT24=__nuppT14(function() do local __nuppT28= io . open ( path , "rb" ) ; __nuppT27= __nuppT28 ; __nuppT21=1;  local probe=__nuppT27;
if probe then
probe : close ( )
local loadlib = rawget ( package , "loadlib" )
local open , why = loadlib ( path , "ks_register_a5aec1231ee04251_5e40cbbf873d89d7__neon" )
if not open then error ( "cannot register AOT builder: " .. tostring ( why ) , 0 ) end
registered = open ( require ( "nupp.runtime.aotruntime" ) . table ( ) )
if type ( registered ) ~= "table" or type ( registered [ "normalizeImpl" ] ) ~= "function" then error ( "malformed AOT builder registration" , 0 ) end
modules [ cacheKey ] = registered
return "return",__nuppT9( registered [ "normalizeImpl" ] )
end
directory = directory .. "/.." end; return "normal" end,__nuppT10); local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 and __nuppT27~=nil then  local __nuppT29,__nuppT30=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT29 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT30 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end
error ( "cannot find lib/libpaths_aot.dylib at or above " .. started .. "; the compiled library has to travel with the module that calls it" , 0 )
end
ks_a5aec1231ee04251_normalize_impl_builder = ks_a5aec1231ee04251_normalize_impl_builderLoad ( )
end

local function normalizeImpl (
text ,
windows
) 
return ks_a5aec1231ee04251_normalize_impl_builder ( text , windows )
end

do
local entries = rawget ( _G , "__nuppAotCompiled" )
if entries == nil then
entries = setmetatable ( { } , { __mode = "k" } )
rawset ( _G , "__nuppAotCompiled" , entries )
end
entries [ normalizeImpl ] = true
end









function pathtext . normalize ( text , windows ) 
if isVerbatim ( text , windows ) then
return text
end

return ( ks_a5aec1231ee04251_normalize_impl_builder ( text , windows ) )
end




local function lastComponent ( text , windows ) 
local length = # text
local prefix = pathtext . prefixLength ( text , windows )
local rooted = prefix < length and isSeparator ( byte ( text , prefix + 1 ) , windows )
local anchored = rooted and prefix + 1 or prefix
local at = length
while at > anchored do
while at > anchored and isSeparator ( byte ( text , at ) , windows ) do
at = at - 1
end
if at == anchored then
do break end
end
local finish = at
while at > anchored and not isSeparator ( byte ( text , at ) , windows ) do
at = at - 1
end
local start = at + 1
local width = finish - start + 1
if not ( width == 1 and byte ( text , start ) == 46 ) then
local kind = width == 2 and byte ( text , start ) == 46 and byte ( text , start + 1 ) == 46 and pathtext . PARENT
or pathtext . NORMAL
return start , width , kind , anchored
end
end

if rooted then
return prefix + 1 , 1 , pathtext . ROOT , anchored
elseif prefix ~= 0 then
return 1 , prefix , pathtext . PREFIX , anchored
end

return nil , 0 , nil , anchored
end

local function beforeLast ( text , start , anchored , windows ) 
local at = start - 1
while at > anchored and isSeparator ( byte ( text , at ) , windows ) do
at = at - 1
end

return at
end

local function splitNameAt ( text , start , length ) 
local at = length
while at > 0 do
at = at - 1
if byte ( text , start + at ) == 46 then
if at == 0 then
return length , nil , 0
end

return at , start + at + 1 , length - at - 1
end
end

return length , nil , 0
end













function pathtext . pushPart ( carried , part , windows ) 
local prefix = pathtext . prefixLength ( part , windows )
local rooted = prefix ~= 0 or ( # part ~= 0 and isSeparator ( byte ( part , 1 ) , windows ) )
local head = carried
if rooted then
head = ""
if prefix == 0 then
local currentPrefix = pathtext . prefixLength ( carried , windows )
if currentPrefix ~= 0 then
head = carried : sub ( 1 , currentPrefix )
end
end
elseif # carried ~= 0 and not isSeparator ( byte ( carried , # carried ) , windows ) then






local currentPrefix = pathtext . prefixLength ( carried , windows )
if currentPrefix ~= # carried or byte ( carried , # carried ) ~= 58 then
head = carried .. ( isVerbatim ( carried , windows ) and "\\" or "/" )
end
end

return head .. part
end






function pathtext . join ( parts , windows ) 
local carried = ""
for _ , part in ipairs ( parts ) do
carried = pathtext . pushPart ( carried , part , windows )
end

return pathtext . finish ( carried , windows )
end




local function nextComponent (
text ,
at ,
phase ,
windows
) 
local length = # text
if phase == 0 then
local prefix = pathtext . prefixLength ( text , windows )
at , phase = prefix , 1
if prefix ~= 0 then
return 1 , prefix , pathtext . PREFIX , at , phase
end
end
if phase == 1 then
phase = 2
if at < length and isSeparator ( byte ( text , at + 1 ) , windows ) then
local start = at + 1
while at < length and isSeparator ( byte ( text , at + 1 ) , windows ) do
at = at + 1
end

return start , 1 , pathtext . ROOT , at , phase
end
end
while at < length do
local start = at + 1
while at < length and not isSeparator ( byte ( text , at + 1 ) , windows ) do
at = at + 1
end
local width = at - start + 1
if width ~= 0 and not ( width == 1 and byte ( text , start ) == 46 ) then
local kind = width == 2 and byte ( text , start ) == 46 and byte ( text , start + 1 ) == 46 and pathtext . PARENT
or pathtext . NORMAL
while at < length and isSeparator ( byte ( text , at + 1 ) , windows ) do
at = at + 1
end

return start , width , kind , at , phase
end
while at < length and isSeparator ( byte ( text , at + 1 ) , windows ) do
at = at + 1
end
end

return nil , 0 , nil , at , phase
end

local function appendComponent (
answer ,
needsSeparator ,
text ,
start ,
length ,
kind
) 
if kind == pathtext . PREFIX then
return answer .. text : sub ( start , start + length - 1 ) , false
elseif kind == pathtext . ROOT then
return answer .. "/" , false
end

return answer .. ( needsSeparator and "/" or "" ) .. text : sub ( start , start + length - 1 ) , true
end










function pathtext . clean ( text , windows ) 
if isVerbatim ( text , windows ) then
return text
end
local answer = ""
local needsSeparator = false
local at = 0
local phase = 0
while true do
local start , length , kind , nextAt , nextPhase = nextComponent ( text , at , phase , windows )
if start == nil then
do break end
end
answer , needsSeparator = appendComponent (
answer ,
needsSeparator ,
text ,
start ,
length ,
kind
)
at , phase = nextAt , nextPhase
end

return pathtext . finish ( answer , windows )
end












function pathtext . relative ( target , base , windows ) 
if isVerbatim ( target , windows ) or isVerbatim ( base , windows ) then
return nil , "a verbatim path is carried rather than reasoned about"
end
local targetAbsolute = pathtext . isAbsolute ( target , windows )
local baseAbsolute = pathtext . isAbsolute ( base , windows )
if targetAbsolute ~= baseAbsolute then
if targetAbsolute then
return pathtext . clean ( target , windows ) , nil
end

return nil , "paths do not share a relative coordinate system"
end

local targetAt , targetPhase = 0 , 0
local baseAt , basePhase = 0 , 0
local targetStart , targetLength , targetKind , nextTargetAt , nextTargetPhase = nextComponent (
target ,
targetAt ,
targetPhase ,
windows
)
local baseStart , baseLength , baseKind , nextBaseAt , nextBasePhase = nextComponent ( base , baseAt , basePhase , windows )
while targetStart ~= nil and baseStart ~= nil do
if targetKind ~= baseKind or targetLength ~= baseLength then
do break end
end



if targetKind ~= pathtext . ROOT then
local targetPart = target : sub ( targetStart , ( targetStart ) + targetLength - 1 )
local basePart = base : sub ( baseStart , ( baseStart ) + baseLength - 1 )
if targetKind == pathtext . PREFIX then
targetPart = pathtext . finish ( targetPart , windows )
basePart = pathtext . finish ( basePart , windows )
end
if targetPart ~= basePart then
do break end
end
end
targetAt , targetPhase = nextTargetAt , nextTargetPhase
baseAt , basePhase = nextBaseAt , nextBasePhase
targetStart , targetLength , targetKind , nextTargetAt , nextTargetPhase = nextComponent (
target ,
targetAt ,
targetPhase ,
windows
)
baseStart , baseLength , baseKind , nextBaseAt , nextBasePhase = nextComponent ( base , baseAt , basePhase , windows )
end



if baseStart ~= nil
and (
baseKind == pathtext . PREFIX
or baseKind == pathtext . ROOT
or ( targetStart ~= nil and ( targetKind == pathtext . PREFIX or targetKind == pathtext . ROOT ) )
)
then
return nil , "paths do not share a relative coordinate system"
end

local parents = 0
while baseStart ~= nil do
if baseKind == pathtext . PARENT then
return nil , "paths do not share a relative coordinate system"
end
parents = parents + 1
baseAt , basePhase = nextBaseAt , nextBasePhase
baseStart , baseLength , baseKind , nextBaseAt , nextBasePhase = nextComponent ( base , baseAt , basePhase , windows )
end

local answer = "" local __nuppBuf_1 = __nuppBuffer.newBuffer()
local needsSeparator = false
for _ = 1 , parents do
__nuppBuf_1:put( ( needsSeparator and "/" or "" ) , ".." )
needsSeparator = true
end answer = __nuppBuf_1:tostring()
while targetStart ~= nil do
answer , needsSeparator = appendComponent (
answer ,
needsSeparator ,
target ,
targetStart ,
targetLength ,
targetKind
)
targetAt , targetPhase = nextTargetAt , nextTargetPhase
targetStart , targetLength , targetKind , nextTargetAt , nextTargetPhase = nextComponent (
target ,
targetAt ,
targetPhase ,
windows
)
end
if # answer == 0 then

answer = "."
end

return pathtext . finish ( answer , windows ) , nil
end
















function pathtext . with ( text , replacement , extension , windows ) 
local what = extension and "an extension" or "a file name"
if not extension and ( replacement == "" or replacement == "." or replacement == ".." ) then
error ( "nupp: " .. what .. " must be one path component, not " .. ("%q") : format ( replacement ) , 3 )
end
for at = 1 , # replacement do
local value = byte ( replacement , at )
if value == 0 or isSeparator ( value , windows ) or ( windows and value == 58 ) then
error ( "nupp: " .. what .. " must be one path component, not " .. ("%q") : format ( replacement ) , 3 )
end
end

local start , length , kind , anchored = lastComponent ( text , windows )
local hasName = start ~= nil and kind == pathtext . NORMAL
if extension then
if not hasName then
return pathtext . finish ( text , windows )
end


local found = start
local stemLength = splitNameAt ( text , found , length )
local head = text : sub ( 1 , found - 1 + stemLength )
if # replacement == 0 then
return pathtext . finish ( head , windows )
end

return pathtext . finish ( head .. "." .. replacement , windows )
end
local head = hasName and text : sub ( 1 , beforeLast ( text , start , anchored , windows ) ) or text
if # head ~= 0 and not isSeparator ( byte ( head , # head ) , windows ) then
head = head .. ( isVerbatim ( head , windows ) and "\\" or "/" )
end

return pathtext . finish ( head .. replacement , windows )
end












function pathtext . part ( text , kind , windows ) 
local start , length , componentKind , anchored = lastComponent ( text , windows )
if kind == 0 then


if start == nil or componentKind == pathtext . ROOT or componentKind == pathtext . PREFIX then
return nil
end

return pathtext . finish ( text : sub ( 1 , beforeLast ( text , start , anchored , windows ) ) , windows )
end
if start == nil or componentKind ~= pathtext . NORMAL then
return nil
end
local found = start
local stemLength , extensionAt , extensionLength = splitNameAt ( text , found , length )
if kind == 1 then
return pathtext . finish ( text : sub ( found , found + length - 1 ) , windows )
elseif kind == 2 then
return pathtext . finish ( text : sub ( found , found + stemLength - 1 ) , windows )
elseif extensionAt ~= nil then
local at = extensionAt

return pathtext . finish ( text : sub ( at , at + extensionLength - 1 ) , windows )
end

return nil
end

local __nuppExportValue= pathtext ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.io.path.pathtext"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.path.pathtext"]=__nuppExports;return __nuppExports