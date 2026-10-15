_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.model"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local binding;__nuppExports["binding"]=function(...) return binding(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.model\0runtime\0001") };

const core = require ( "contract.dispatch" )

local Schema = {} Schema.__index = Schema ;_G.nupp.__reflect.link(Schema,__nuppT1[1],{ }) ;__nuppExports["Schema"]=Schema




local Named = {} Named.__index = Named




local TextAdapter = {} TextAdapter.__index = TextAdapter


function TextAdapter:write(value, writer) 
writer : string ( self . member , value )
end



binding=function ( schema ) 
return ( _G.setmetatable({ adapter =
_G.setmetatable({ member =  _G.setmetatable({ name =  schema . name ,  schema =  schema }, Named) }, TextAdapter) }, core.Bound) )

end ;__nuppExports["binding"]=binding
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Schema]="example.model\0Schema"; end);if not __nuppOk then package.loaded["example.model"]=nil;error(__nuppWhy,0) end;package.loaded["example.model"]=__nuppExports;return __nuppExports