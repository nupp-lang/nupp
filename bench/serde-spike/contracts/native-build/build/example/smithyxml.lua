_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["example.smithyxml"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local policy;__nuppExports["policy"]=function(...) return policy(...) end;

local core = require ( "nupp.serde" )
local smithy = require ( "example.smithy" )
local xml = require ( "example.xmlcodec" )
local syntax = require ( "example.xmlsyntax" )
local Policy = {} Policy.__index = Policy
function Policy:field(member) 
assert ( getmetatable ( member ) == smithy . Member , "expected Smithy member" )
local selected = member
local name = selected : trait ( "smithy.api#xmlName" )
local namespace = selected : trait ( "smithy.api#xmlNamespace" )
local attribute = selected : trait ( "smithy.api#xmlAttribute" )

return ( _G.setmetatable({ namespaceUri =
namespace ~= nil and assert ( namespace : get ( "uri" ) ) : string ( ) or "" ,  localName =
name ~= nil and name : string ( ) or selected . name ,  role =
attribute ~= nil and "attribute" or "element" }, syntax.Field) )

end

function Policy:flattened(member) 
assert ( getmetatable ( member ) == smithy . Member , "expected Smithy member" )
return ( member ) : trait ( "smithy.api#xmlFlattened" ) ~= nil
end

policy=function ( ) 
return ( _G.setmetatable({ }, Policy) )
end ;__nuppExports["policy"]=policy
 end);if not __nuppOk then package.loaded["example.smithyxml"]=nil;error(__nuppWhy,0) end;package.loaded["example.smithyxml"]=__nuppExports;return __nuppExports