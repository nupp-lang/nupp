_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.view"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local adapter;__nuppExports["adapter"]=function(...) return adapter(...) end;local of;__nuppExports["of"]=function(...) return of(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.view\0runtime\0001") };

local core = require ( "nupp.serde.internal.value" )
local documents = require ( "nupp.serde.internal.document" )
local bridge = require ( "nupp.serde.internal.documentcodec" )



local View = {} View.__index = View











function View:context() 
return self . source
end



function View:document() 
return bridge . fromBinding ( self . binding , self . value , self . source )
end








function View:snapshot() 
return ( _G.setmetatable({ binding =
self . binding ,  value =
bridge . into ( self . binding , self : document ( ) ) ,  source =
self . source }, View) )

end ;_G.nupp.__reflect.link(View,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0Binding\0interface\0module\0001","nupp.serde.internal.value") , _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") }) ;__nuppExports["View"]=View


local Contents = {} Contents.__index = Contents


function Contents:describe(direction) 
return self . original : describe ( direction )
end

function Contents:write(value, writer) 
assert ( value . binding == self . binding , "typed document belongs to another binding" )
self . original : write ( value . value , writer )
end

function Contents:read(reader) 
return ( _G.setmetatable({ binding =  self . binding ,  value =  self . original : read ( reader ) ,  source =  reader : context ( ) }, View) )
end

local Select = {} Select.__index = Select


function Select:apply(adapter, state) 
self . result = _G.setmetatable({ adapter =
_G.setmetatable({ binding =  self . binding ,  original =  adapter }, Contents) }, core.Bound)

end

local Adapter = {} Adapter.__index = Adapter


function Adapter:context(document) 
assert ( document . binding == self . binding , "typed document belongs to another binding" )
return document : context ( )
end

function Adapter:contents() 
return self . selected
end

function Adapter:readContents(reader) 
local source = reader : context ( )
local logical = documents . documentAdapter ( ) : readContents ( reader )
return ( _G.setmetatable({ binding =  self . binding ,  value =  bridge . into ( self . binding , logical ) ,  source =  source }, View) )
end

function Adapter:discard(value) 
local _copy = value
end

of=function ( binding , value , context ) 
return ( _G.setmetatable({ binding =  binding ,  value =  value ,  source =  context }, View) )
end ;__nuppExports["of"]=of

adapter=function ( binding ) 
local select = _G.setmetatable({ binding =  binding }, Select)
binding : accept ( select , nil )
return ( _G.setmetatable({ binding =  binding ,  selected =  assert ( select . result ) }, Adapter) )
end ;__nuppExports["adapter"]=adapter
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[View]="nupp.serde.internal.view\0View"; end);if not __nuppOk then package.loaded["nupp.serde.internal.view"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.view"]=__nuppExports;return __nuppExports