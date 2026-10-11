_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.carried\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.carried\0runtime\0002") };









local scalarIR = require ( "nupp.compiler.aot.scalar" )
local carried = { }



carried.Frame = {} carried.Frame.__index = carried.Frame ;_G.nupp.__reflect.link(carried.Frame,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00056","nupp.compiler.aot.scalar") })





carried.State = {} carried.State.__index = carried.State ;_G.nupp.__reflect.link(carried.State,__nuppT1[2],{ __nuppT1[1] })










local walk

local function declare ( state , uniqueName , declared ) 
state . depth [ uniqueName ] = # state . frames
declared . assigned = nil
state . declared [ uniqueName ] = declared
end



local function assigned ( state , target ) 
if target . kind ~= "local" or target . uniqueName == nil then
return
end
local uniqueName = target . uniqueName
local declared = state . declared [ uniqueName ]
if declared ~= nil then
declared . assigned = true
end
local from = state . depth [ uniqueName ]
if from == nil then
return
end
local type = target . type
if type == nil and declared ~= nil then
type = declared . type
end
for level = ( from ) + 1 , # state . frames do
local frame = state . frames [ level ]
if not frame . present [ uniqueName ] then
frame . present [ uniqueName ] = true
frame . order [
# frame . order + 1
] = _G.setmetatable({ name =
target . name ,  uniqueName =
uniqueName ,  type =
type }, scalarIR.Carried)

end
end
end

local function loop ( state , node , body , binding ) 
local frame = _G.setmetatable({ node =  node ,  order =  { } ,  present =  { } }, carried.Frame)
state . frames [ # state . frames + 1 ] = frame
if binding ~= nil then
declare ( state , ( binding ) . uniqueName , binding )
end
if node . op == "while" and node . conditionBody ~= nil then
walk ( node . conditionBody , state )
end
walk ( body , state )
if node . op == "repeat" and node . conditionBody ~= nil then
walk ( node . conditionBody , state )
end
state . frames [ # state . frames ] = nil
node . carried = frame . order
end

walk = function ( statements , state ) 
for _ , statement in ipairs ( statements ) do
local op = statement . op
if op == "let" then
local declared = statement
declare ( state , declared . uniqueName , declared )
elseif op == "multi_let" then
for _ , bound in ipairs ( ( statement ) . bindings ) do
declare ( state , bound . uniqueName , bound )
end
elseif op == "assign" then
for _ , entry in ipairs ( ( statement ) . values ) do
assigned ( state , entry . target )
end
elseif op == "if" then
local branch = statement
for _ , clause in ipairs ( branch . clauses ) do
walk ( clause . body , state )
end
if branch . elseBody ~= nil then
walk ( branch . elseBody , state )
end
elseif op == "while" then
local node = statement
loop ( state , node , node . body , nil )
elseif op == "repeat" then
local node = statement
loop ( state , node , node . body , nil )
elseif op == "fornum" then
local node = statement
loop ( state , node , node . body , node . binding )
elseif op == "block" then
walk ( ( statement ) . body , state )
elseif op == "reducer_region" then
walk ( ( statement ) . body , state )
elseif op == "phase" then
walk ( ( statement ) . body , state )
end
end
end





function carried . body ( statements , state ) 
walk ( statements , state )
end

function carried . state ( ) 
return ( _G.setmetatable({ depth =  { } ,  declared =  { } ,  frames =  { } }, carried.State) )
end


function carried . program ( program ) 
local state = carried . state ( )
if program . loop ~= nil then
walk ( ( program . loop ) . statements , state )
end
if program . workgroup ~= nil then
local group = program . workgroup
walk ( group . prelude , state )
walk ( group . statements , state )
end
if program . body ~= nil then
walk ( program . body , state )
end

return program
end

local __nuppExportValue= carried ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.carried"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.carried"]=__nuppExports;return __nuppExports