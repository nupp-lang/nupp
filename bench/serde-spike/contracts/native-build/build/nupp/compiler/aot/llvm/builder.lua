_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.builder\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.builder\0runtime\0002") };















local text = require ( "nupp.compiler.aot.llvm.text" )

local builder = { }

builder.Module = {} builder.Module.__index = builder.Module ;_G.nupp.__reflect.link(builder.Module,__nuppT1[1],{ })



























function builder . module ( ) 
return ( _G.setmetatable({ order =
{ } ,  pieces =
{ } ,  attributes =
{ } ,  attributeOrder =
{ } ,  metadata =
{ } ,  metadataByText =
{ } ,  named =
{ } ,  namedOrder =
{ } ,  functions =
{ } ,  serial =
0 }, builder.Module) )

end



function builder . once ( module , key , piece ) 
if module . pieces [ key ] ~= nil then
return false
end
module . pieces [ key ] = piece
module . order [ # module . order + 1 ] = key

return true
end


function builder . declare ( module , name , signature ) 
builder . once ( module , "declare " .. name , signature )
end


function builder . attributes ( module , body ) 
local number = module . attributes [ body ]
if number == nil then
number = # module . attributeOrder
module . attributes [ body ] = number
module . attributeOrder [ number + 1 ] = body
end

return "#" .. tostring ( number )
end


function builder . metadata ( module , body ) 
local number = module . metadataByText [ body ]
if number == nil then
number = # module . metadata
module . metadataByText [ body ] = number
module . metadata [ number + 1 ] = body
end

return "!" .. tostring ( number )
end


function builder . distinct ( module , body ) 
local number = # module . metadata
module . metadata [ number + 1 ] = "distinct " .. body

return "!" .. tostring ( number )
end


function builder . named ( module , name , node ) 
local list = module . named [ name ]
if list == nil then
list = { }
module . named [ name ] = list
module . namedOrder [ # module . namedOrder + 1 ] = name
end
( list ) [ # ( list ) + 1 ] = node
end



function builder . loopMetadata ( module , properties ) 
local references = { }
for _ , property in ipairs ( properties ) do
references [ # references + 1 ] = builder . metadata ( module , property )
end
local number = # module . metadata
local self = "!" .. tostring ( number )
local operands = { self }
for _ , reference in ipairs ( references ) do
operands [ # operands + 1 ] = reference
end
module . metadata [ number + 1 ] = "distinct !{" .. table . concat ( operands , ", " ) .. "}"

return self
end


function builder . bytes ( module , value , align ) 
local key = "bytes " .. value
local existing = module . pieces [ key ]
if existing ~= nil then
return ( existing ) : match ( "^(@[^ ]+)" )
end
module . serial = module . serial + 1
local name = "@nupp.bytes." .. tostring ( module . serial )
builder . once (
module ,
key ,
("%s = private unnamed_addr constant [%d x i8] c\"%s\", align %d")

: format ( name , # value , text . bytes ( value ) , align or 1 )
)

return name
end


function builder . render ( module ) 
local lines = { }


local defined = { }
for _ , definition in ipairs ( module . functions ) do
local name = definition : match ( "^define [^@]*(@[%w_.$]+)%(" )
if name ~= nil then
defined [ name ] = true
end
end
for _ , key in ipairs ( module . order ) do
if key : sub ( 1 , 8 ) ~= "declare " or not defined [ key : sub ( 9 ) ] then
lines [ # lines + 1 ] = module . pieces [ key ]
end
end
for _ , definition in ipairs ( module . functions ) do
lines [ # lines + 1 ] = ""
lines [ # lines + 1 ] = definition
end
lines [ # lines + 1 ] = ""
for number , body in ipairs ( module . attributeOrder ) do
lines [ # lines + 1 ] = "attributes #" .. tostring ( number - 1 ) .. " = { " .. body .. " }"
end
for _ , name in ipairs ( module . namedOrder ) do
lines [ # lines + 1 ] = "!" .. name .. " = !{" .. table . concat ( module . named [ name ] , ", " ) .. "}"
end
for number , body in ipairs ( module . metadata ) do
lines [ # lines + 1 ] = "!" .. tostring ( number - 1 ) .. " = " .. body
end

return table . concat ( lines , "\n" ) .. "\n"
end





builder.Function = {} builder.Function.__index = builder.Function ;_G.nupp.__reflect.link(builder.Function,__nuppT1[2],{ __nuppT1[1] })
























function builder . func ( module , header ) 
return ( _G.setmetatable({ module =
module ,  header =
header ,  allocas =
{ } ,  lines =
{ } ,  serial =
0 ,  labelSerial =
0 ,  terminated =
false ,  current =
"body" ,  location =
nil }, builder.Function) )

end


function builder . temp ( f ) 
f . serial = f . serial + 1

return "%t" .. tostring ( f . serial )
end


function builder . label ( f , hint ) 
f . labelSerial = f . labelSerial + 1

return hint .. "." .. tostring ( f . labelSerial )
end




function builder . emit ( f , instruction ) 
if f . terminated then
builder . start ( f , builder . label ( f , "dead" ) )
end
f . lines [ # f . lines + 1 ] = f . location ~= nil and "  " .. instruction .. ", !dbg " .. tostring ( f . location )
or "  " .. instruction
end


function builder . value ( f , instruction ) 
local name = builder . temp ( f )
builder . emit ( f , name .. " = " .. instruction )

return name
end


function builder . terminate ( f , instruction ) 
builder . emit ( f , instruction )
f . terminated = true
end


function builder . jump ( f , label ) 
if not f . terminated then
builder . terminate ( f , "br label %" .. label )
end
end


function builder . start ( f , label ) 
builder . jump ( f , label )
f . lines [ # f . lines + 1 ] = label .. ":"
f . current = label
f . terminated = false
end





function builder . alloca ( f , type , align ) 
f . serial = f . serial + 1
local name = "%slot" .. tostring ( f . serial )
local aligned = type : find ( "<" , 1 , true ) ~= nil and "" or ", align " .. tostring ( align or 8 )
f . allocas [ # f . allocas + 1 ] = "  " .. name .. " = alloca " .. type .. aligned

return name
end


function builder . finish ( f , fallthrough ) 
if not f . terminated then
builder . terminate ( f , fallthrough )
end
local lines = { f . header , "entry:" }
for _ , line in ipairs ( f . allocas ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = "  br label %body"
lines [ # lines + 1 ] = "body:"
for _ , line in ipairs ( f . lines ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = "}"
f . module . functions [ # f . module . functions + 1 ] = table . concat ( lines , "\n" )
end

local __nuppExportValue= builder ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.builder"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.builder"]=__nuppExports;return __nuppExports