_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
local __nuppT1={ _G.nupp.__reflect.declaration("nupp.gpu.types\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.gpu.types\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.gpu.types\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.gpu.types\0runtime\0004") };


local api = require ( "nupp.gpu.api" )

local gpu = { }












gpu . PORTABLE_WORKGROUP_THREADS = 256




gpu . PORTABLE_SCRATCH_BYTES = 16384





gpu.Buffer = {} gpu.Buffer.__index = gpu.Buffer


















function gpu.Buffer:close() 
local buffer = self
if not buffer . _root or buffer . _state . released then
return
end
buffer . _state . released = true
local context = buffer . _context
local release = context . _releaseBuffer
release ( context , buffer )
end ;_G.nupp.__reflect.link(gpu.Buffer,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../../src/nupp/mem/span.nupp\0Span\0interface\0module\0001","nupp.mem.span") })



























gpu.Kernel = {} gpu.Kernel.__index = gpu.Kernel










function gpu.Kernel:close() 
if self . _released then
return
end
self . _released = true
local context = self . _anchor
local release = context . _releaseKernel
release ( context , self . _handle )
end ;_G.nupp.__reflect.link(gpu.Kernel,__nuppT1[2],{ })






gpu . ArtifactSet = api . ArtifactSet







gpu.Shared = {} gpu.Shared.__index = gpu.Shared ;_G.nupp.__reflect.link(gpu.Shared,__nuppT1[3],{ })










gpu.Phases = {} gpu.Phases.__index = gpu.Phases ;_G.nupp.__reflect.link(gpu.Phases,__nuppT1[4],{ })






















function gpu . markClosed ( state ) 
state . _closed = true
end

local __nuppExportValue= gpu ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.gpu.types"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.gpu.types"]=__nuppExports;return __nuppExports