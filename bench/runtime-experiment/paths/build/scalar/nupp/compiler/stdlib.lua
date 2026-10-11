_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()








local stdlib = { }

local function compact ( source ) 
return ( source : gsub ( "[\13\n]+%s*" , " " ) : gsub ( "%s+$" , "" ) )
end

local BASE = compact (
"local __nupp=_G.nupp or {};_G.nupp=__nupp\nlocal __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath)\nlocal function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end\nlocal __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile\n"





)






local HOT_BASE = compact (
"local __nupp=_G.nupp or {};_G.nupp=__nupp\nrawset(__nupp,\"math\",rawget(__nupp,\"math\")or{})\nlocal function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end\nlocal __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile\n"





)






local MATH = compact ( "require(\"nupp.compiler.runtime.math\").install(rawget(__nupp,\"math\"))\n"

)






local PEG_RUNTIME = compact (
"local __nuppPegRuntime=require(\"nupp.compiler.runtime.peg\")\nlocal __nuppPeg=rawget(__nupp,\"peg\")or{};rawset(__nupp,\"peg\",__nuppPeg)\nlocal __nuppPegCodegen,__nuppPegLpeg=__nuppPegRuntime.codegen,__nuppPegRuntime.lpegBackend\n"




)

local PEG_COMPILE = compact ( "__nuppPeg.compile=__nuppPegRuntime.compile\n"

)




local FIELDCODEC = compact ( "require(\"nupp.compiler.runtime.reflect\").installFieldCodec(__nupp)\n"

)

local REFLECTION = compact ( "require(\"nupp.compiler.runtime.reflect\").install(__nupp)\n"

)





local DERIVES = compact ( "require(\"nupp.derive\").install(__nupp)\n"

)

function stdlib . bootstrap ( effects , watch , installingManaged ) 
local out = { watch and HOT_BASE or BASE }
if not installingManaged then
out [ # out + 1 ] = "require(\"nupp.runtime.managed\").install(__nupp,_G);"
end
effects = effects or { }
if effects [ "stdlib.math" ] then
out [ # out + 1 ] = MATH
end
if effects [ "stdlib.peg" ] or effects [ "stdlib.peg.compile" ] then
out [ # out + 1 ] = PEG_RUNTIME
end
if effects [ "stdlib.lpeg.re" ] or effects [ "stdlib.peg.compile" ] then
out [ # out + 1 ] = "require(\"re\");"
end
if effects [ "stdlib.peg.compile" ] then
out [ # out + 1 ] = PEG_COMPILE
end
if effects [ "stdlib.fieldcodec" ] then
out [ # out + 1 ] = FIELDCODEC
end
if effects [ "stdlib.typewitness" ] or effects [ "stdlib.reflection" ] then
out [ # out + 1 ] = "require(\"nupp.compiler.runtime.typewitness\").install(__nupp);"
end
if effects [ "stdlib.reflection" ] then
out [ # out + 1 ] = REFLECTION
end
if effects [ "stdlib.derives" ] then
out [ # out + 1 ] = DERIVES
end
local code = table . concat ( out , " " )

return code : sub ( -1 ) == ";" and code or code .. ";"
end

local __nuppExportValue= stdlib ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.stdlib"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.stdlib"]=__nuppExports;return __nuppExports