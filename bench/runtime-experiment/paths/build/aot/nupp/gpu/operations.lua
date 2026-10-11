_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nuppBitTobit=bit.tobit;local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math"));local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


local api = require ( "nupp.gpu.api" )
local types = require ( "nupp.gpu.types" )
local tensorlayout = require ( "nupp.gpu.layout" )
local layoutFacts = require ( "nupp.gpu.layoutfacts" ) . layoutFacts

local array = require ( "nupp.mem.array" )
local gpu = { }


const SCALAR_KINDS

= {
[ array . uint8 ] = "uint8" ,
[ array . int8 ] = "int8" ,
[ array . uint16 ] = "uint16" ,
[ array . int16 ] = "int16" ,
[ array . uint32 ] = "uint32" ,
[ array . int32 ] = "int32" ,
[ array . uint64 ] = "uint64" ,
[ array . int64 ] = "int64" ,
[ array . float ] = "float" ,
[ array . number ] = "number" ,
}


gpu . Buffer = types . Buffer

gpu . Kernel = types . Kernel

gpu . Shared = types . Shared

gpu . Phases = types . Phases

gpu . PORTABLE_WORKGROUP_THREADS = types . PORTABLE_WORKGROUP_THREADS

local function copied ( values ) 
local out = { }
for index , value in ipairs ( values ) do
out [ index ] = value
end

return out
end




function gpu . denseShape ( shape ) 
if # shape < 1 or # shape > 4 then
error ( "nupp: GPU tensors take one through four dimensions" , 3 )
end
local count = 1
local strides = { }
for index = # shape , 1 , -1 do
local dimension = shape [ index ]
if type ( dimension ) ~= "number" or dimension % 1 ~= 0 or dimension < 1 or count > _G.math.floor(( 4294967295 ) / ( dimension )) then
error ( "nupp: GPU tensor dimensions must have 1 through 4294967295 elements" , 3 )
end
strides [ index ] = count
count = count * dimension
end

return count , strides , copied ( shape )
end

local function liveBuffer ( state ) 
if state . released then
error ( "nupp: GPU buffer was released" , 3 )
end
end

function gpu . Shared . get ( self , index ) 
if type ( index ) ~= "number" or index % 1 ~= 0 or index < 0 or index >= self . count then
error ( "nupp: GPU shared-scratch index out of bounds" , 2 )
end
return self . _values [ index + 1 ]
end

function gpu . Shared . set ( self , index , value ) 
if type ( index ) ~= "number" or index % 1 ~= 0 or index < 0 or index >= self . count then
error ( "nupp: GPU shared-scratch index out of bounds" , 2 )
end
self . _values [ index + 1 ] = value
end

local sharedType = types . Shared
local sharedMembers = rawget ( sharedType , "__index" )
local sharedGet = rawget ( sharedType , "get" )
local sharedSet = rawget ( sharedType , "set" )
rawset ( sharedType , "__index" , function ( self , key ) 
if type ( key ) == "number" then
return sharedGet ( self , key )
end

return sharedMembers [ key ]
end )
rawset ( sharedType , "__newindex" , function ( self , key , value ) 
if type ( key ) == "number" then
sharedSet ( self , key , value )
return
end
rawset ( self , key , value )
end )

function gpu . Phases . scratch ( self , initial , count ) 
if type ( count ) ~= "number" or count % 1 ~= 0 or count < 1 then
error ( "nupp: GPU shared scratch must contain at least one element" , 2 )
end
local values = { }
for index = 1 , count do
values [ index ] = initial
end

return ( _G.setmetatable({ _values =  values ,  count =  count }, types.Shared) )
end

function gpu . Phases . run ( self , stage ) 
for index = 0 , self . _size - 1 do
stage ( (__nuppBitTobit( index )%4294967296) )
end
end

function gpu . Phases . reduceSum ( self , valuesInput ) 
local values = valuesInput
if values . count ~= self . _size or self . _size < 1 or self . _size & ( self . _size - 1 ) ~= 0 then
error ( "nupp: fixed-tree reduction needs one power-of-two value per lane" , 2 )
end
local stride = _G.math.floor(( self . _size ) / ( 2 ))
while stride > 0 do
local active = stride
self : run ( function ( localIndex ) 
local lane = localIndex
if lane < active then
values [
lane
] = nupp . math . f32 . add ( nupp . math . f32 . narrow ( values [ lane ] ) , nupp . math . f32 . narrow ( values [ lane + active ] ) )
end
end )
stride = _G.math.floor(( stride ) / ( 2 ))
end
end

function gpu . Phases . inclusiveScan (
self ,
valuesInput ,
temporaryInput
) 
local values = valuesInput
local temporary = temporaryInput
if values . count ~= self . _size
or temporary . count ~= self . _size
or self . _size < 1
or self . _size & ( self . _size - 1 ) ~= 0
then
error ( "nupp: fixed scan needs two power-of-two arrays with one value per lane" , 2 )
end
local offset = 1
local valuesAreSource = true
while offset < self . _size do
local distance = offset
if valuesAreSource then
self : run ( function ( localIndex ) 
local lane = localIndex
local value = values [ lane ]
if lane >= distance then
value = (__nuppBitTobit((
(__nuppBitTobit( value )%4294967296) )+(
(__nuppBitTobit( values [ lane - distance ] )%4294967296) ))%4294967296)

end
temporary [ lane ] = value
end )
else
self : run ( function ( localIndex ) 
local lane = localIndex
local value = temporary [ lane ]
if lane >= distance then
value = (__nuppBitTobit((
(__nuppBitTobit( value )%4294967296) )+(
(__nuppBitTobit( temporary [ lane - distance ] )%4294967296) ))%4294967296)

end
values [ lane ] = value
end )
end
valuesAreSource = not valuesAreSource
offset = offset * 2
end
if not valuesAreSource then
self : run ( function ( localIndex ) 
local lane = localIndex
values [ lane ] = temporary [ lane ]
end )
end
end










function gpu . workgroups ( groups , size , controller ) 
local groupCount = groups
local groupSize = size
if groupSize < 1 or groupSize > gpu . PORTABLE_WORKGROUP_THREADS then
error ( "nupp: GPU workgroup size exceeds the portable limit" , 2 )
end
local phases = _G.setmetatable({ _size =  groupSize }, types.Phases)
for groupIndex = 0 , groupCount - 1 do
controller ( (__nuppBitTobit( groupIndex )%4294967296) , phases )
end
end



function gpu . elementType ( element ) 
local kind = SCALAR_KINDS [ element ]
if kind ~= nil then
return require ( "nupp.runtime.storage" ) . scalar ( kind )
end

return element
end

function gpu . Buffer . dimensions ( self ) 
liveBuffer ( self . _state )
return copied ( self . _shape )
end

function gpu . Buffer . strides ( self ) 
liveBuffer ( self . _state )
return copied ( self . _strides )
end











function gpu . refuseReadWriteAlias ( bound , state ) 
for _ , other in pairs ( bound ) do
if rawequal ( other , state ) then
error ( "nupp: a GPU buffer cannot be bound for both reading and writing in one dispatch" , 3 )
end
end
end

function gpu . Buffer . isDense ( buffer ) 
liveBuffer ( buffer . _state )
local _ , _ , dense = layoutFacts ( buffer . _shape , buffer . _strides , 2 )
return dense
end

function gpu . Buffer . isInjective ( buffer ) 
liveBuffer ( buffer . _state )
local _ , _ , _ , injective = layoutFacts ( buffer . _shape , buffer . _strides , 2 )
return injective
end

function gpu . Buffer . layout ( buffer ) 
liveBuffer ( buffer . _state )
return tensorlayout . new ( buffer . _shape , buffer . _strides , buffer . _offset )
end

function gpu . Buffer . view ( buffer , layout ) 
liveBuffer ( buffer . _state )
local offset = layout : offset ( )
local extent = layout : extent ( )
if offset > buffer . _capacity or extent > buffer . _capacity - offset then
error ( "nupp: GPU tensor view exceeds its allocation" , 2 )
end

return ( _G.setmetatable({ _elementType =
nil ,  _anchor =
buffer ,  _context =
buffer . _context ,  _handle =
buffer . _handle ,  _width =
buffer . _width ,  _offset =
offset ,  _capacity =
buffer . _capacity ,  _root =
false ,  _state =
buffer . _state ,  _shape =
layout : dimensions ( ) ,  _strides =
layout : strides ( ) ,  count =
layout . count }, types.Buffer) )

end

function gpu . Buffer . subview (
self ,
origin ,
shape
) 
liveBuffer ( self . _state )
if # origin ~= # self . _shape or # shape ~= # self . _shape then
error ( "nupp: GPU tensor subview rank does not match its buffer" , 2 )
end
local count , extent = layoutFacts ( shape , self . _strides , 2 )
local offset = self . _offset
for index = # shape , 1 , -1 do
local first = origin [ index ]
local dimension = shape [ index ]
if type ( first ) ~= "number"
or first % 1 ~= 0
or first < 0
or first > self . _shape [ index ]
or dimension > self . _shape [ index ] - first
then
error ( "nupp: GPU tensor subview is outside its buffer" , 2 )
end
offset = offset + first * self . _strides [ index ]
end
if offset > self . _capacity or extent > self . _capacity - offset then
error ( "nupp: GPU tensor subview exceeds its allocation" , 2 )
end

return ( _G.setmetatable({ _elementType =
nil ,  _anchor =
self ,  _context =
self . _context ,  _handle =
self . _handle ,  _width =
self . _width ,  _offset =
offset ,  _capacity =
self . _capacity ,  _root =
false ,  _state =
self . _state ,  _shape =
copied ( shape ) ,  _strides =
copied ( self . _strides ) ,  count =
count }, types.Buffer) )

end

local __nuppExportValue= gpu ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.gpu.operations"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.gpu.operations"]=__nuppExports;return __nuppExports