_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





local cst = require ( "nupp.compiler.syntax.cst" )
local receiverIntrinsics = require ( "nupp.compiler.check.receiverintrinsics" )

local moduleobject = { }

local function dottedPath ( node ) 
local parts = { }
local current = node
while current and current . kind == "dotIndex" do
if not current . name then
return nil
end
table . insert ( parts , 1 , current . name . text )
current = current . obj
end
if not current or current . kind ~= "name" or not current . token then
return nil
end
table . insert ( parts , 1 , current . token . text )

return parts
end


local function qualifiedModule ( node , declaredModules ) 
local parts = dottedPath ( node )
if not parts or not declaredModules then
return nil
end
for length = # parts , 1 , -1 do
local candidate = table . concat ( parts , "." , 1 , length )
if declaredModules [ candidate ] then
return candidate
end
end

return nil
end





local function globalRequire ( node ) 
local callee = node . obj
if not callee
or callee . kind ~= "dotIndex"
or not callee . name
or callee . name . text ~= "require"
or not callee . obj
or callee . obj . kind ~= "name"
or not callee . obj . token
or callee . obj . token . text ~= "_G"
then
return nil
end
local argument = node . args and node . args . exprs and node . args . exprs [ 1 ]
if not argument or argument . kind ~= "string" or not argument . token then
return nil
end
local chunk = loadstring ( "return " .. argument . token . text )
if not chunk then
return nil
end
local ok , value = pcall ( chunk )

return ok and type ( value ) == "string" and value or nil
end




function moduleobject . emit ( path , parsed , header , index ) 
local supported = index . supportedModules
local dependencySet = { }
for _ , name in ipairs ( header . dependencies or { } ) do
if not supported or supported [ name ] ~= false then
dependencySet [ name ] = true
end
end




local constGenerics = false

local function walk ( node , insideDot ) 
if node == nil or cst . isToken ( node ) then
return
end
if node . kind == "localFuncStmt" and node . body and node . body . generics then
for _ , isConst in pairs ( node . body . generics . consts or { } ) do
constGenerics = constGenerics or isConst == true
end
end
if node . kind == "call" and node . obj and node . obj . kind == "dotIndex" and node . obj . name then
local intrinsicModule = receiverIntrinsics [ node . obj . name . text ]
if intrinsicModule ~= nil then
dependencySet [ intrinsicModule ] = true
end
local required = globalRequire ( node )
if required and index . declaredModules and index . declaredModules [ required ] then
dependencySet [ required ] = true
end
end
if node . kind == "dotIndex" and not insideDot then
local reached = qualifiedModule ( node , index . declaredModules )
if reached and ( not supported or supported [ reached ] ~= false ) then
dependencySet [ reached ] = true
end
end
for _ , child in ipairs ( node ) do
walk ( child , node . kind == "dotIndex" )
end
end

walk ( parsed . root , false )
local dependencies = { }
for name in pairs ( dependencySet ) do
dependencies [ # dependencies + 1 ] = name
end
table . sort ( dependencies )

return {
path = path ,
moduleName = header . moduleName ,
dependencies = dependencies ,
constGenerics = constGenerics or nil ,
}
end







function moduleobject . link ( objects ) 
local byName = { }
local paths = { }
for _ , object in ipairs ( objects ) do
if object . moduleName then
byName [ object . moduleName ] = object
end
paths [ # paths + 1 ] = object . path
end
table . sort ( paths )

local edges = { }
for _ , object in ipairs ( objects ) do
local targets = { }
local seen = { }
for _ , dependency in ipairs ( object . dependencies or { } ) do
local target = byName [ dependency ]
if target and not seen [ target . path ] then
seen [ target . path ] = true
targets [ # targets + 1 ] = target . path
end
end
table . sort ( targets )
edges [ object . path ] = targets
end


local counter = 0
local indices = { }
local low = { }
local open = { }
local onOpen = { }
local components = { }
local componentOf = { }

for _ , start in ipairs ( paths ) do
if indices [ start ] == nil then
local frames = { }
counter = counter + 1
indices [ start ] , low [ start ] = counter , counter
open [ # open + 1 ] = start
onOpen [ start ] = true
frames [ 1 ] = { node = start , at = 0 }
while # frames > 0 do
local frame = frames [ # frames ]
local node = frame . node
frame . at = frame . at + 1
local target = ( edges [ node ] ) [ frame . at ]
if target ~= nil then
if indices [ target ] == nil then
counter = counter + 1
indices [ target ] , low [ target ] = counter , counter
open [ # open + 1 ] = target
onOpen [ target ] = true
frames [ # frames + 1 ] = { node = target , at = 0 }
elseif onOpen [ target ] then
low [ node ] = math . min ( low [ node ] , indices [ target ] )
end
else
frames [ # frames ] = nil
local parent = frames [ # frames ]
if parent ~= nil then
local parentNode = parent . node
low [ parentNode ] = math . min ( low [ parentNode ] , low [ node ] )
end
if low [ node ] == indices [ node ] then
local component = { }
repeat
local member = open [ # open ]
open [ # open ] = nil
onOpen [ member ] = nil
component [ # component + 1 ] = member
until member == node
table . sort ( component )
components [ # components + 1 ] = component
for _ , member in ipairs ( component ) do
componentOf [ member ] = # components
end
end
end
end
end
end

local dependencies = { }
local dependents = { }
local linked = { }
for index = 1 , # components do
dependencies [ index ] , dependents [ index ] , linked [ index ] = { } , { } , { }
end
for index , component in ipairs ( components ) do
local seen = linked [ index ]
for _ , path in ipairs ( component ) do
for _ , target in ipairs ( edges [ path ] ) do
local dependency = componentOf [ target ]
if dependency ~= index and not seen [ dependency ] then
seen [ dependency ] = true
local into = dependencies [ index ]
into [ # into + 1 ] = dependency
local back = dependents [ dependency ]
back [ # back + 1 ] = index
end
end
end
table . sort ( dependencies [ index ] )
end
for index = 1 , # components do
table . sort ( dependents [ index ] )
end

return { components = components , dependencies = dependencies , dependents = dependents , }
end

local __nuppExportValue= moduleobject ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.moduleobject"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.moduleobject"]=__nuppExports;return __nuppExports