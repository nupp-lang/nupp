_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local shape = require ( "nupp.compiler.aot.simdshape" )

local cast = { }


const ELEMENTS = {
f32 = true ,
f64 = true ,
i8 = true ,
u8 = true ,
i16 = true ,
u16 = true ,
i32 = true ,
u32 = true ,
i64 = true ,
u64 = true ,
}





function cast . matches ( source , destination , reinterpret ) 
local fromFamily , from = shape . parts ( source )
local toFamily , to = shape . parts ( destination )
if fromFamily ~= "vector"
or toFamily ~= "vector"
or ELEMENTS [ from ] == nil
or ELEMENTS [ to ] == nil
then
return false
end
if not shape . sameLanes ( source , destination ) then
return false
end

return not reinterpret or ( from ) : sub ( 2 ) == ( to ) : sub ( 2 )
end

local __nuppExportValue= cast ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.simdcast"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.simdcast"]=__nuppExports;return __nuppExports