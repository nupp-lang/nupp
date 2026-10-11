_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




local cst = require ( "nupp.compiler.syntax.cst" )
local checkpoint = { }

function checkpoint . restore ( result ) 
local saved = result . optimizationSyntax
if not saved then
return
end
do
for _ , entry in ipairs ( saved . nodes ) do
for key in pairs ( entry . node ) do
entry . node [ key ] = nil
end
for key , value in pairs ( entry . fields ) do
entry . node [ key ] = value
end
end
for definition , value in pairs ( saved . views ) do
definition . virtualIndexedView = value ~= false and value or nil
end
if result . analysis then
local bodies = { }
for i , body in ipairs ( saved . bodies ) do
bodies [ i ] = body
end
result . analysis . bodies = bodies
end
return
end
end

function checkpoint . prepare ( result ) 
local saved = result . optimizationSyntax
if saved then
checkpoint . restore ( result )
return
end
local nodes , seen , views = { } , { } , { }
local lists = { "blocks" , "stats" , "clauses" , "exprs" , "params" , "names" , "targets" }
local visit
visit = function ( node ) 
if type ( node ) ~= "table" or seen [ node ] then
return
end
seen [ node ] = true
local fields = { }
for key , value in pairs ( node ) do
fields [ key ] = value
end
nodes [ # nodes + 1 ] = { node = node , fields = fields }
if cst . isToken ( node ) and node . definition then
views [ node . definition ] = node . definition . virtualIndexedView or false
end
for _ , child in ipairs ( node ) do
visit ( child )
end
if node . kind and not cst . isToken ( node ) then
for _ , key in ipairs ( lists ) do
if node [ key ] then
visit ( node [ key ] )
end
end
end
end
visit ( result . root )
local bodies = { }
for i , body in ipairs ( result . analysis and result . analysis . bodies or { } ) do
bodies [ i ] = body
end
result . optimizationSyntax = { nodes = nodes , views = views , bodies = bodies }
end

local __nuppExportValue= checkpoint ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.syntax.checkpoint"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.syntax.checkpoint"]=__nuppExports;return __nuppExports