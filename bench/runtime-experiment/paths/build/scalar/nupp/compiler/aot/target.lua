_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.target\0runtime\0001") };





















local targetLayout = require ( "nupp.compiler.targetlayout" )

local target = __nuppNew(0,2)






target . TIERS = {

[ "baseline" ] = 16 ,


[ "avx2" ] = 32 ,


[ "avx512f" ] = 64 ,



[ "neon" ] = 32 ,


[ "simd128" ] = 16 ,


[ "scalar" ] = 0 ,
}







target . DEFAULT_TIERS = {
[ "x86_64" ] = "baseline" ,
[ "i686" ] = "baseline" ,
[ "aarch64" ] = "neon" ,
[ "wasm32" ] = "scalar" ,
}


target.Target = {} target.Target.__index = target.Target ;_G.nupp.__reflect.link(target.Target,__nuppT1[1],{ })











function target . architecture ( triple ) 
return triple : match ( "^([^-]+)" ) or triple
end





function target . hostTriple ( ) 
return targetLayout . hostKey ( )
end







function target . system ( triple ) 
if triple : find ( "emscripten" , 1 , true ) ~= nil then
return "emscripten"
elseif triple : find ( "darwin" , 1 , true ) ~= nil then
return "darwin"
elseif triple : find ( "windows" , 1 , true ) ~= nil then
return "windows"
end

return "linux"
end

local function dualNumberLoops ( ) 
for cursor = - 0 , 0 do
return 1 / cursor > 0
end
return false
end

local hostJit = rawget ( _G , "jit" )
if hostJit ~= nil then


hostJit . off ( dualNumberLoops , true )
end




function target . numericForRuntime ( selected ) 
if selected . architecture == "wasm32" then
return "luajit-single"
elseif hostJit ~= nil and selected . triple == target . hostTriple ( ) then
return dualNumberLoops ( ) and "luajit-dual" or "luajit-single"
elseif selected . architecture == "aarch64" then
return "luajit-dual"
end

return "luajit-single"
end


function target . tiers ( architecture ) 
if architecture == "wasm32" then
return { "scalar" , "simd128" }
elseif architecture == "aarch64" then
return { "neon" }
elseif architecture == "x86_64" then
return { "baseline" , "avx2" , "avx512f" }
end

return { "baseline" , "avx2" }
end









function target . buildTiers ( triple , features


) 
local base , baseErr = target . select ( triple , nil )
if base == nil then
return nil , baseErr
end

local actual = base
local architecture = actual . architecture
if features == nil and architecture ~= "x86_64" then
local selected , selectedErr = target . select ( actual . triple , nil )
if selected == nil then
return nil , selectedErr
end

return { selected } , nil
end

local known = target . tiers ( architecture )
local first = known [ 1 ]
local last = known [ # known ]
if features ~= nil then
first = features . minimum or first
last = features . maximum or last
end
local _ , firstErr = target . select ( actual . triple , first )
if firstErr ~= nil then
return nil , firstErr
end
local _ , lastErr = target . select ( actual . triple , last )
if lastErr ~= nil then
return nil , lastErr
end

local firstIndex , lastIndex = nil , nil
for index , tier in ipairs ( known ) do
if tier == first then
firstIndex = index
end
if tier == last then
lastIndex = index
end
end
if ( firstIndex ) > ( lastIndex ) then
return nil , "feature tier minimum " .. first .. " is wider than maximum " .. last
end

local selected = { }
for index = firstIndex , lastIndex do
local one = target . select ( actual . triple , known [ index ] )
if one ~= nil then
selected [ # selected + 1 ] = one
end
end

return selected , nil
end


function target . symbol ( symbol , tier ) 
return symbol .. "__" .. tier : gsub ( "[^%w_]" , "_" )
end


function target . rank ( tier ) 
if tier == "avx512f" then
return 2
elseif tier == "avx2" then
return 1
end

return 0
end






function target . select ( triple , tier ) 
local named = triple or targetLayout . hostKey ( )
if named == nil then
return nil , "this host is not a modeled target; name one with --target"
end
if not targetLayout . has ( named ) then
return nil , "unknown target " .. tostring ( named )
end

local architecture = target . architecture ( named )
local selected = tier or target . DEFAULT_TIERS [ architecture ]
if selected == nil then
return nil , "no feature tier is known for " .. architecture
end

local available = target . tiers ( architecture )
local admitted = false
for _ , one in ipairs ( available ) do
if one == selected then
admitted = true
end
end
if not admitted then
return nil , ("%s has no feature tier %s; it has %s")

: format ( architecture , tostring ( selected ) , table . concat ( available , ", " ) )
end

return _G.setmetatable({ triple =  named ,  architecture =  architecture ,  tier =  selected }, target.Target) , nil
end




















target . FRAME_VECTOR_CEILING = { [ "windows" ] = 16 }



function target . vectorCeiling ( selected ) 
return target . FRAME_VECTOR_CEILING [ target . system ( selected . triple ) ]
end


local function held ( selected , width ) 
local ceiling = target . vectorCeiling ( selected )
if ceiling ~= nil and width > ( ceiling ) then
return ceiling
end

return width
end









function target . simdWidth ( selected ) 
if ( target . TIERS [ selected . tier ] or 0 ) == 0 then


return 0
end
if selected . tier == "avx512f" then
return held ( selected , 64 )
elseif selected . tier == "avx2" then
return held ( selected , 32 )
end

return held ( selected , 16 )
end

local __nuppExportValue= target ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.target"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.target"]=__nuppExports;return __nuppExports