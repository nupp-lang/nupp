_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.serde.internal.json.document"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local contents;__nuppExports["contents"]=function(...) return contents(...) end;local name;__nuppExports["name"]=function(...) return name(...) end;local unknown;__nuppExports["unknown"]=function(...) return unknown(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.json.document\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.json.document\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.serde.internal.json.document\0runtime\0003") };

local core = require ( "nupp.serde.internal.value" )
local publication = require ( "nupp.serde.internal.publication" )
local syntax = require ( "nupp.serde.internal.json.syntax" )

local Name = {} Name.__index = Name






function Name:diagnosticLabel() 
return self . name
end ;_G.nupp.__reflect.link(Name,__nuppT1[1],{ }) ;__nuppExports["Name"]=Name


name=function ( field ) 
if getmetatable ( field ) ~= Name then
error ( "field identity is not a JSON name" , 2 )
end
return ( field ) . name
end ;__nuppExports["name"]=name

local Contents = {} Contents.__index = Contents




function Contents:live() 
if self . expired then
error ( "document reader scope has expired" , 2 )
end
end

function Contents:context() 
self : live ( )
return self . sourceContext
end

function Contents:kind() 
self : live ( )
local token = self . cursor : peek ( )
if token == "object" then
return "structure"
elseif token == "array" then
return "list"
elseif token == "number" then
return "numberToken"
else
return token
end
end

function Contents:readNull() 
self : live ( )
self . cursor : readNull ( )
end

function Contents:readBoolean() 
self : live ( )
return self . cursor : readBoolean ( )
end

function Contents:readNumberToken() 
self : live ( )
return self . cursor : readNumber ( )
end

function Contents:readString() 
self : live ( )
return self . cursor : readString ( )
end

function Contents:readBytes() 
error ( "JSON bytes require model context" , 2 )
end

function Contents:readTimestamp() 
error ( "JSON timestamps require model context" , 2 )
end

function Contents:readInteger() 
error ( "JSON integer width requires model context" , 2 )
end

function Contents:readDecimal() 
error ( "JSON decimal interpretation requires model context" , 2 )
end

function Contents:readFloat() 
error ( "JSON float width requires model context" , 2 )
end

function Contents:readBigInteger() 
error ( "JSON big integer interpretation requires model context" , 2 )
end

function Contents:readAtom() 
error ( "JSON atoms require model context" , 2 )
end

function Contents:readDocument(adapter) 
error ( "JSON document boundaries require model context" , 2 )
end

function Contents:readTuple(state, consume) 
error ( "JSON tuples require model context" , 2 )
end

function Contents:readUnion(state, consume) 
error ( "JSON unions require model context" , 2 )
end

function Contents:readMap(state, consume) 
error ( "JSON typed maps require model context" , 2 )
end

function Contents:readList(state, consume) 
self : live ( )
self . cursor : start ( "array" )
local index = 0
while self . cursor : nextElement ( ) do
index += 1
local mark = self . cursor : mark ( )
local child = _G.setmetatable({ cursor =  self . cursor ,  sourceContext =  self . sourceContext ,  expired =  false }, Contents)
local ok , problem = pcall ( consume . apply , consume , state , index , child )
child . expired = true
if not ok then
error ( problem , 0 )
end
self . cursor : consumed ( mark )
end
end

function Contents:readStruct(state, consume) 
self : live ( )
self . cursor : start ( "object" )
while true do
local key = self . cursor : nextKey ( )
if key == nil then
do break end
end
local mark = self . cursor : mark ( )
local child = _G.setmetatable({ cursor =  self . cursor ,  sourceContext =  self . sourceContext ,  expired =  false }, Contents)
local ok , problem = pcall ( consume . apply , consume , state , key , child )
child . expired = true
if not ok then
error ( problem , 0 )
end
self . cursor : consumed ( mark )
end
end

function Contents:expire() 
self . expired = true
end ;_G.nupp.__reflect.link(Contents,__nuppT1[2],{ _G.nupp.__reflect.reference("nupp.serde.internal.json.syntax\0runtime\0004","nupp.serde.internal.json.syntax") , _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") }) ;__nuppExports["Contents"]=Contents


local Unknown = {} Unknown.__index = Unknown





function Unknown:live() 
if self . expired then
error ( "unknown reader scope has expired" , 2 )
end
if self . used then
error ( "unknown value has already been consumed" , 2 )
end
self . used = true
end

function Unknown:skipValue() 
self : live ( )
self . cursor : skipValue ( )
end

function Unknown:captureValue(adapter) 
self : live ( )
local mark = self . cursor : mark ( )
local child = _G.setmetatable({ cursor =  self . cursor ,  sourceContext =  self . sourceContext ,  expired =  false }, Contents)
local ok , result = pcall ( adapter . readContents , adapter , child )
child : expire ( )
if not ok then
error ( result , 0 )
end
local complete , problem = pcall ( self . cursor . consumed , self . cursor , mark )
if not complete then
error ( publication . failure ( adapter , result , problem ) , 0 )
end

return result
end

function Unknown:expire() 
self . expired = true
end ;_G.nupp.__reflect.link(Unknown,__nuppT1[3],{ _G.nupp.__reflect.reference("nupp.serde.internal.json.syntax\0runtime\0004","nupp.serde.internal.json.syntax") , _G.nupp.__reflect.reference("../../../../src/nupp/serde/internal/value.nupp\0Context\0interface\0module\0001","nupp.serde.internal.value") }) ;__nuppExports["Unknown"]=Unknown


contents=function ( cursor , context ) 
return ( _G.setmetatable({ cursor =  cursor ,  sourceContext =  context ,  expired =  false }, Contents) )
end ;__nuppExports["contents"]=contents

unknown=function ( cursor , context ) 
return ( _G.setmetatable({ cursor =  cursor ,  sourceContext =  context ,  expired =  false ,  used =  false }, Unknown) )
end ;__nuppExports["unknown"]=unknown
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Contents]="nupp.serde.internal.json.document\0Contents";__nuppWorkerRecords[Name]="nupp.serde.internal.json.document\0Name";__nuppWorkerRecords[Unknown]="nupp.serde.internal.json.document\0Unknown"; end);if not __nuppOk then package.loaded["nupp.serde.internal.json.document"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.document"]=__nuppExports;return __nuppExports