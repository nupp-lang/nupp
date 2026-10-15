_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local runtime = { }

function runtime . install ( namespace ) 
local reflect = rawget ( namespace , "__reflect" )
if reflect == nil then
reflect = { }
rawset ( namespace , "__reflect" , reflect )
end
if reflect . witnessesReady then
return
end
reflect . witnessesReady = true
local blueprints = reflect . blueprints or setmetatable ( { } , { __mode = "k" } )
local references = reflect . references or setmetatable ( { } , { __mode = "k" } )
local declarations = reflect . declarations or setmetatable ( { } , { __mode = "v" } )
local targetsKey = reflect . targetsKey or { }
local ctypeTargets = reflect . ctypeTargets or setmetatable ( { } , { __mode = "k" } )
reflect . blueprints , reflect . references , reflect . declarations = blueprints , references , declarations
reflect . targetsKey , reflect . ctypeTargets = targetsKey , ctypeTargets

function reflect . reference ( key , moduleName ) 
local cell = declarations [ key ]
if cell == nil then
cell = { key = key , module = moduleName }
declarations [ key ] = cell
end

return cell
end

function reflect . declaration ( key ) 
local cell = declarations [ key ]
if cell == nil or cell [ 1 ] ~= nil then
cell = { key = key }
declarations [ key ] = cell
end

return cell
end

function reflect . link ( typeObject , owner , children ) 


local targets = owner
if children ~= nil then
owner [ 1 ] = typeObject
targets = { [ owner . key ] = owner }
for _ , cell in ipairs ( children ) do
targets [ cell . key ] = cell
end
end
if type ( typeObject ) == "table" then
rawset ( typeObject , targetsKey , targets )
else
ctypeTargets [ typeObject ] = targets
end
end

function reflect . known ( typeObject ) 
return blueprints [ typeObject ] ~= nil
end

function reflect . register ( typeObject , blueprint , targets ) 
blueprints [ typeObject ] = blueprint
references [ typeObject ] = targets
if type ( typeObject ) == "table" and rawget ( typeObject , "reflect" ) == nil then
rawset ( typeObject , "reflect" , function ( ) 
if reflect . get == nil then
require ( "nupp.compiler.runtime.reflect" ) . install ( namespace )
end
return reflect . get ( typeObject )
end )
end

return typeObject
end

function reflect . ensure ( typeObject , describe ) 
if blueprints [ typeObject ] == nil then
local blueprint , targets = describe ( )
reflect . register ( typeObject , blueprint , targets )
end

return typeObject
end
end

local __nuppExportValue= runtime ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.runtime.typewitness"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.runtime.typewitness"]=__nuppExports;return __nuppExports