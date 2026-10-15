_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.profile\0runtime\0001") };










local profile = { }

profile.Profile = {} profile.Profile.__index = profile.Profile ;_G.nupp.__reflect.link(profile.Profile,__nuppT1[1],{ })
































local PROFILES = {
[
"aarch64-apple-darwin"
] = _G.setmetatable({ public =
"aarch64-apple-darwin" ,  llvmTriple =
"arm64-apple-macosx11.0.0" ,  cpu =
"apple-m1" ,  baseFeatures =
"+neon" ,  format =
"macho" ,  minimum =
"11.0.0" ,  functionAttributes =
"\"frame-pointer\"=\"non-leaf\"" ,  machine =
"arm64" ,  sizeType =
"i64" }, profile.Profile)
,
[
"x86_64-apple-darwin"
] = _G.setmetatable({ public =
"x86_64-apple-darwin" ,  llvmTriple =
"x86_64-apple-macosx10.14.0" ,  cpu =
"x86-64" ,  baseFeatures =
"" ,  format =
"macho" ,  minimum =
"10.14.0" ,  functionAttributes =
"\"frame-pointer\"=\"all\"" ,  machine =
"x86_64" ,  sizeType =
"i64" }, profile.Profile)
,
[
"x86_64-unknown-linux-gnu"
] = _G.setmetatable({ public =
"x86_64-unknown-linux-gnu" ,  llvmTriple =
"x86_64-unknown-linux-gnu" ,  cpu =
"x86-64" ,  baseFeatures =
"" ,  format =
"elf" ,  functionAttributes =
"" ,  machine =
"elf_x86_64" ,  sizeType =
"i64" }, profile.Profile)
,
[
"aarch64-unknown-linux-gnu"
] = _G.setmetatable({ public =
"aarch64-unknown-linux-gnu" ,  llvmTriple =
"aarch64-unknown-linux-gnu" ,  cpu =
"generic" ,  baseFeatures =
"+neon" ,  format =
"elf" ,  functionAttributes =
"\"frame-pointer\"=\"non-leaf\"" ,  machine =
"aarch64linux" ,  sizeType =
"i64" }, profile.Profile)
,
[ "i686-unknown-linux-gnu" ] = _G.setmetatable({ public =
"i686-unknown-linux-gnu" ,  llvmTriple =
"i686-unknown-linux-gnu" ,  cpu =
"pentium4" ,  baseFeatures =
"" ,  format =
"elf" ,  functionAttributes =



"\"frame-pointer\"=\"all\"" ,  machine =
"elf_i386" ,  sizeType =
"i32" ,  linkedRuntime =
"/aot/llvm/lua/runtime-i686.ll" }, profile.Profile)
,
[ "wasm32-unknown-emscripten" ] = _G.setmetatable({ public =
"wasm32-unknown-emscripten" ,  llvmTriple =


"wasm32-unknown-unknown" ,  cpu =
"generic" ,  baseFeatures =
"+bulk-memory,+nontrapping-fptoint,+sign-ext,+mutable-globals" ,  format =
"wasm" ,  functionAttributes =
"" ,  machine =
"wasm32" ,  sizeType =
"i32" }, profile.Profile)
,
[ "x86_64-pc-windows-msvc" ] = _G.setmetatable({ public =
"x86_64-pc-windows-msvc" ,  llvmTriple =
"x86_64-w64-windows-gnu" ,  cpu =
"x86-64" ,  baseFeatures =
"" ,  format =
"coff" ,  functionAttributes =


"\"prefer-vector-width\"=\"128\"" ,  machine =
"x64" ,  sizeType =
"i64" }, profile.Profile)
,
}








const TIER_FEATURES

= {
[ "baseline" ] = "" ,
[ "avx2" ] = "+avx2,+fma" ,
[ "avx512f" ] = "+avx512f" ,
[ "neon" ] = "+neon" ,
[ "simd128" ] = "+simd128" ,
[ "scalar" ] = "" ,
}


function profile . of ( public ) 
local found = PROFILES [ public ]
if found == nil then
return nil , "the LLVM backend has no profile for " .. public
end

return found , nil
end


function profile . features ( selected , tier ) 
local parts = { }
if selected . baseFeatures ~= "" then
parts [ # parts + 1 ] = selected . baseFeatures
end
local extra = TIER_FEATURES [ tier ]
if extra ~= nil and extra ~= "" and extra ~= selected . baseFeatures then
parts [ # parts + 1 ] = extra
end

return table . concat ( parts , "," )
end


function profile . options ( selected , tier ) 
return { triple = selected . llvmTriple , cpu = selected . cpu , features = profile . features ( selected , tier ) , opt = "3" }
end










function profile . sharedLink (
selected ,
output ,
objects ,
soname ,
strip
) 
local argv
if selected . format == "macho" then
argv = {
"ld64.lld" ,
"-arch" ,
selected . machine ,
"-platform_version" ,
"macos" ,
tostring ( selected . minimum ) ,
tostring ( selected . minimum ) ,
"-dylib" ,
"-install_name" ,
"@rpath/" .. soname ,
"-undefined" ,
"dynamic_lookup" ,
"-o" ,
output ,
}
if strip ~= nil then
argv [ # argv + 1 ] = "-oso_prefix"
argv [ # argv + 1 ] = strip
end
elseif selected . format == "elf" then
argv = {
"ld.lld" ,
"-m" ,
selected . machine ,
"-shared" ,
"--eh-frame-hdr" ,
"-z" ,
"noexecstack" ,
"-z" ,
"now" ,
"--hash-style=gnu" ,
"--gc-sections" ,
"-soname" ,
soname ,
"-o" ,
output ,
}
else
argv = {
"lld-link" ,
"-lldmingw" ,
"/dll" ,
"/noentry" ,
"/machine:" .. selected . machine ,
"/nodefaultlib" ,
"/out:" .. output
}
end
for _ , object in ipairs ( objects ) do
argv [ # argv + 1 ] = object
end

return argv
end

local __nuppExportValue= profile ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.profile"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.profile"]=__nuppExports;return __nuppExports