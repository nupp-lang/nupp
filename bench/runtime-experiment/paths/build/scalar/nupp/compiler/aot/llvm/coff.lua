_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


















local coff = __nuppNew(0,5)


coff . ENTRY = "ks_dll_main"




const CRT

= {
"acos" ,
"asin" ,
"atan" ,
"atan2" ,
"ceil" ,
"cos" ,
"cosh" ,
"exp" ,
"floor" ,
"fmod" ,
"frexp" ,
"ldexp" ,
"log" ,
"log10" ,
"memchr" ,
"memcmp" ,
"memcpy" ,
"memmove" ,
"memset" ,
"modf" ,
"pow" ,
"sin" ,
"sinh" ,
"sqrt" ,
"strlen" ,
"tan" ,
"tanh" ,
}







const UCRT

= {
"ceilf" ,
"cbrt" ,
"cbrtf" ,
"exp2" ,
"exp2f" ,
"expf" ,
"floorf" ,
"fma" ,
"fmaf" ,
"fmax" ,
"fmaxf" ,
"fmin" ,
"fminf" ,
"fmodf" ,
"log2" ,
"log2f" ,
"logf" ,
"nearbyint" ,
"nearbyintf" ,
"powf" ,
"rint" ,
"rintf" ,
"round" ,
"roundf" ,
"sinf" ,
"cosf" ,
"sqrtf" ,
"tanf" ,
"trunc" ,
"truncf" ,
}


coff . UCRT_MODULE = "api-ms-win-crt-math-l1-1-0.dll"


const KERNEL32 = { "GetModuleHandleA" , "GetProcAddress" }

coff . CRT = CRT
coff . UCRT = UCRT
coff . KERNEL32 = KERNEL32

local function cString ( name ) 
return ("private unnamed_addr constant [%d x i8] c\"%s\\00\"") : format ( # name + 1 , name )
end



function coff . binding ( triple , names ) 
local lines = {
"; The Lua C API for a Windows DLL of AOT code, bound when it loads." ,
"target triple = \"" .. triple .. "\"" ,
"" ,
"module asm \".text\"" ,


"module asm \".globl ___chkstk_ms\"" ,
"module asm \"___chkstk_ms:\"" ,
"module asm \"    pushq %rcx\"" ,
"module asm \"    pushq %rax\"" ,
"module asm \"    cmpq $0x1000, %rax\"" ,
"module asm \"    leaq 24(%rsp), %rcx\"" ,
"module asm \"    jb 1f\"" ,
"module asm \"2:  subq $0x1000, %rcx\"" ,
"module asm \"    testq %rcx, (%rcx)\"" ,
"module asm \"    subq $0x1000, %rax\"" ,
"module asm \"    cmpq $0x1000, %rax\"" ,
"module asm \"    ja 2b\"" ,
"module asm \"1:  subq %rax, %rcx\"" ,
"module asm \"    testq %rcx, (%rcx)\"" ,
"module asm \"    popq %rax\"" ,
"module asm \"    popq %rcx\"" ,
"module asm \"    retq\"" ,
}
for _ , name in ipairs ( names ) do
lines [ # lines + 1 ] = "module asm \".globl " .. name .. "\""
lines [ # lines + 1 ] = "module asm \"" .. name .. ":\""
lines [ # lines + 1 ] = "module asm \"    jmpq *ks_lua_slot_" .. name .. "(%rip)\""
end
lines [ # lines + 1 ] = ""
for _ , name in ipairs ( names ) do
lines [ # lines + 1 ] = "@ks_lua_slot_" .. name .. " = hidden global ptr null"
lines [ # lines + 1 ] = "@ks_lua_name_" .. name .. " = " .. ( ("private unnamed_addr constant [%d x i8] c\"%s\\00\"") : format ( # name + 1 , name ) )
end
lines [ # lines + 1 ] = "@ks_lua_module = " .. ( ("private unnamed_addr constant [%d x i8] c\"%s\\00\"") : format ( 10 , "lua51.dll" ) )
lines [ # lines + 1 ] = "@ks_lua_probe = " .. ( ("private unnamed_addr constant [%d x i8] c\"%s\\00\"") : format ( 11 , "lua_gettop" ) )
lines [ # lines + 1 ] = ""
lines [ # lines + 1 ] = "declare dllimport ptr @GetModuleHandleA(ptr)"
lines [ # lines + 1 ] = "declare dllimport ptr @GetProcAddress(ptr, ptr)"
lines [ # lines + 1 ] = ""


lines [ # lines + 1 ] = "define dso_local i32 @" .. coff . ENTRY .. "(ptr %instance, i32 %reason, ptr %reserved) {"
lines [ # lines + 1 ] = "entry:"
lines [ # lines + 1 ] = "  %attach = icmp eq i32 %reason, 1"
lines [ # lines + 1 ] = "  br i1 %attach, label %bind, label %done"
lines [ # lines + 1 ] = "bind:"
lines [ # lines + 1 ] = "  %self = call ptr @GetModuleHandleA(ptr null)"
lines [ # lines + 1 ] = "  %probe = call ptr @GetProcAddress(ptr %self, ptr @ks_lua_probe)"
lines [ # lines + 1 ] = "  %exports = icmp ne ptr %probe, null"
lines [ # lines + 1 ] = "  br i1 %exports, label %found, label %library"
lines [ # lines + 1 ] = "library:"
lines [ # lines + 1 ] = "  %lua = call ptr @GetModuleHandleA(ptr @ks_lua_module)"
lines [ # lines + 1 ] = "  br label %found"
lines [ # lines + 1 ] = "found:"
lines [ # lines + 1 ] = "  %module = phi ptr [ %self, %bind ], [ %lua, %library ]"
lines [ # lines + 1 ] = "  %none = icmp eq ptr %module, null"
lines [ # lines + 1 ] = "  br i1 %none, label %fail, label %fill"
lines [ # lines + 1 ] = "fill:"
local ok = "true"
for position , name in ipairs ( names ) do
lines [
# lines + 1
] = ("  %%f%d = call ptr @GetProcAddress(ptr %%module, ptr @ks_lua_name_%s)") : format ( position , name )
lines [ # lines + 1 ] = ("  store ptr %%f%d, ptr @ks_lua_slot_%s") : format ( position , name )
lines [ # lines + 1 ] = ("  %%has%d = icmp ne ptr %%f%d, null") : format ( position , position )
lines [ # lines + 1 ] = ("  %%ok%d = and i1 %s, %%has%d") : format ( position , ok , position )
ok = "%ok" .. tostring ( position )
end
lines [ # lines + 1 ] = "  br i1 " .. ok .. ", label %done, label %fail"
lines [ # lines + 1 ] = "fail:"
lines [ # lines + 1 ] = "  ret i32 0"
lines [ # lines + 1 ] = "done:"
lines [ # lines + 1 ] = "  ret i32 1"
lines [ # lines + 1 ] = "}"

return table . concat ( lines , "\n" ) .. "\n"
end

local __nuppExportValue= coff ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.coff"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.coff"]=__nuppExports;return __nuppExports