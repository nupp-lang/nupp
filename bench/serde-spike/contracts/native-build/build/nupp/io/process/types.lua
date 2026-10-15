_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local __nuppT1={ _G.nupp.__reflect.declaration("nupp.io.process.types\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.io.process.types\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.io.process.types\0runtime\0003") };





local process = { }















































process.Exit = {} process.Exit.__index = process.Exit ;_G.nupp.__reflect.link(process.Exit,__nuppT1[1],{ })















process.Result = {} process.Result.__index = process.Result










function process.Result:succeeded() 
return self . exit : succeeded ( )
end ;_G.nupp.__reflect.link(process.Result,__nuppT1[2],{ __nuppT1[1] })


process.Interest = {} process.Interest.__index = process.Interest ;_G.nupp.__reflect.link(process.Interest,__nuppT1[3],{ })











function process . exited ( exitCode , killed , timedOut ) 
return {
exitCode = exitCode ,
killed = killed ,
timedOut = timedOut ,
succeeded = function ( self ) 

return not self . killed and not self . timedOut and self . exitCode == 0
end ,
}
end

local __nuppExportValue= process ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.io.process.types"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.process.types"]=__nuppExports;return __nuppExports