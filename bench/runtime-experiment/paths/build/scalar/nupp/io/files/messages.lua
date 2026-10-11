_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.io.files.messages"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.io.files.messages\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.io.files.messages\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.io.files.messages\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.io.files.messages\0runtime\0004") };

local paths = require ( "nupp.io.path" )







local Info = {} Info.__index = Info ;_G.nupp.__reflect.link(Info,__nuppT1[1],{ }) ;__nuppExports["Info"]=Info
















local Entry = {} Entry.__index = Entry ;_G.nupp.__reflect.link(Entry,__nuppT1[2],{ }) ;__nuppExports["Entry"]=Entry








local TemporaryOptions = {} TemporaryOptions.__index = TemporaryOptions ;_G.nupp.__reflect.link(TemporaryOptions,__nuppT1[3],{ _G.nupp.__reflect.reference("nupp.io.path\0runtime\0001","nupp.io.path") }) ;__nuppExports["TemporaryOptions"]=TemporaryOptions











local Capabilities = {} Capabilities.__index = Capabilities ;_G.nupp.__reflect.link(Capabilities,__nuppT1[4],{ }) ;__nuppExports["Capabilities"]=Capabilities
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Capabilities]="nupp.io.files.messages\0Capabilities";__nuppWorkerRecords[Entry]="nupp.io.files.messages\0Entry";__nuppWorkerRecords[Info]="nupp.io.files.messages\0Info";__nuppWorkerRecords[TemporaryOptions]="nupp.io.files.messages\0TemporaryOptions"; end);if not __nuppOk then package.loaded["nupp.io.files.messages"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.files.messages"]=__nuppExports;return __nuppExports