_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local builder = require ( "nupp.compiler.aot.llvm.builder" )

local detector = { }


detector . SYMBOL = "ks_aot_feature_tier"

const CPUID = "call { i32, i32, i32, i32 } asm sideeffect \"cpuid\", \"={ax},={bx},={cx},={dx},{ax},{cx},~{dirflag},~{fpsr},~{flags}\"(i32 %d, i32 0)"


const XGETBV = "call { i32, i32 } asm sideeffect \"xgetbv\", \"={ax},={dx},{cx},~{dirflag},~{fpsr},~{flags}\"(i32 0)"



local function bits ( f , value , mask , all ) 
local masked = builder . value ( f , ("and i32 %s, %d") : format ( value , mask ) )
if all then
return builder . value ( f , ("icmp eq i32 %s, %d") : format ( masked , mask ) )
end

return builder . value ( f , ("icmp ne i32 %s, 0") : format ( masked ) )
end


function detector . module ( attributes ) 
local module = builder . module ( )
local attrs = builder . attributes ( module , "noinline nounwind uwtable " .. attributes )
local f = builder . func ( module , ("define i32 @%s() %s {") : format ( detector . SYMBOL , attrs ) )
local none = builder . label ( f , "none" )


local leaf0 = builder . value ( f , ("call { i32, i32, i32, i32 } asm sideeffect \"cpuid\", \"={ax},={bx},={cx},={dx},{ax},{cx},~{dirflag},~{fpsr},~{flags}\"(i32 %d, i32 0)") : format ( 0 ) )
local highest = builder . value ( f , ("extractvalue { i32, i32, i32, i32 } %s, 0") : format ( leaf0 ) )
local hasLeaf7 = builder . value ( f , ("icmp uge i32 %s, 7") : format ( highest ) )
local leaf1Label = builder . label ( f , "leaf1" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( hasLeaf7 , leaf1Label , none ) )



builder . start ( f , leaf1Label )
local leaf1 = builder . value ( f , ("call { i32, i32, i32, i32 } asm sideeffect \"cpuid\", \"={ax},={bx},={cx},={dx},{ax},{cx},~{dirflag},~{fpsr},~{flags}\"(i32 %d, i32 0)") : format ( 1 ) )
local ecx = builder . value ( f , ("extractvalue { i32, i32, i32, i32 } %s, 2") : format ( leaf1 ) )
local osxsave = bits ( f , ecx , 134217728 , false )

local fma = bits ( f , ecx , 4096 , false )
local enabledLabel = builder . label ( f , "enabled" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( osxsave , enabledLabel , none ) )



builder . start ( f , enabledLabel )
local xcr = builder . value ( f , "call { i32, i32 } asm sideeffect \"xgetbv\", \"={ax},={dx},{cx},~{dirflag},~{fpsr},~{flags}\"(i32 0)" )
local enabled = builder . value ( f , ("extractvalue { i32, i32 } %s, 0") : format ( xcr ) )
local ymm = bits ( f , enabled , 6 , true )
local leaf7Label = builder . label ( f , "leaf7" )
builder . terminate ( f , ("br i1 %s, label %%%s, label %%%s") : format ( ymm , leaf7Label , none ) )


builder . start ( f , leaf7Label )
local leaf7 = builder . value ( f , ("call { i32, i32, i32, i32 } asm sideeffect \"cpuid\", \"={ax},={bx},={cx},={dx},{ax},{cx},~{dirflag},~{fpsr},~{flags}\"(i32 %d, i32 0)") : format ( 7 ) )
local ebx = builder . value ( f , ("extractvalue { i32, i32, i32, i32 } %s, 1") : format ( leaf7 ) )
local zmm = bits ( f , enabled , 230 , true )
local avx512f = bits ( f , ebx , 65536 , false )
local avx2 = bits ( f , ebx , 32 , false )
local wideVector = builder . value ( f , ("and i1 %s, %s") : format ( zmm , avx512f ) )
local wide = builder . value ( f , ("and i1 %s, %s") : format ( wideVector , fma ) )
local narrowVector = builder . value ( f , ("and i1 %s, %s") : format ( avx2 , fma ) )
local narrow = builder . value ( f , ("select i1 %s, i32 1, i32 0") : format ( narrowVector ) )
local tier = builder . value ( f , ("select i1 %s, i32 2, i32 %s") : format ( wide , narrow ) )
builder . terminate ( f , "ret i32 " .. tier )

builder . start ( f , none )
builder . finish ( f , "ret i32 0" )

return builder . render ( module )
end

local __nuppExportValue= detector ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.detector"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.detector"]=__nuppExports;return __nuppExports