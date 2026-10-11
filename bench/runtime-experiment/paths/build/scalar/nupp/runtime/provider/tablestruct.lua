_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















local provider = { }
provider . referenceValued = true

local function wrapInteger ( value , bits , signed ) 
local modulus = 2 ^ bits
value = value % modulus
if signed and value >= modulus / 2 then
value = value - modulus
end

return value
end



local function binary32 ( value ) 
if value ~= value or value == math . huge or value == - math . huge or value == 0 then
return value
end
local sign = value < 0 and -1 or 1
local absolute = math . abs ( value )
local exponent = math . floor ( math . log ( absolute ) / math . log ( 2 ) ) + 1
local fraction = absolute / 2 ^ exponent
if exponent < -125 then
local scaled = math . abs ( value ) / 2 ^ -149
local floor = math . floor ( scaled )
local rest = scaled - floor
local rounded = floor
if rest > 0.5 or rest == 0.5 and floor % 2 == 1 then
rounded = floor + 1
end

return sign * rounded * 2 ^ -149
end
if exponent > 128 then
return sign * math . huge
end
local scaled = fraction * 2 ^ 24
local floor = math . floor ( scaled )
local rest = scaled - floor
local rounded = floor
if rest > 0.5 or rest == 0.5 and floor % 2 == 1 then
rounded = floor + 1
end
if rounded == 2 ^ 24 then
rounded = 2 ^ 23
exponent = exponent + 1
end
if exponent > 128 then
return sign * math . huge
end

return sign * rounded * 2 ^ ( exponent - 24 )
end

local NORMALIZE = {
float = binary32 ,
int8 = function ( value ) 
return wrapInteger ( value , 8 , true )
end ,
int16 = function ( value ) 
return wrapInteger ( value , 16 , true )
end ,
int32 = function ( value ) 
return wrapInteger ( value , 32 , true )
end ,
integer = function ( value ) 
return wrapInteger ( value , 32 , true )
end ,
uint8 = function ( value ) 
return wrapInteger ( value , 8 , false )
end ,
uint16 = function ( value ) 
return wrapInteger ( value , 16 , false )
end ,
uint32 = function ( value ) 
return wrapInteger ( value , 32 , false )
end ,
}

local function stored ( field , value ) 
if field . type ~= nil then
return field . type : copy ( value )
end
local normalize = NORMALIZE [ field . kind ]

return normalize and normalize ( value ) or value
end

function provider . scalar ( kind ) 
local fixed = { }
function fixed : new ( ) 
return kind == "boolean" and false or 0
end

fixed . zero = fixed . new
function fixed : copy ( value ) 
local normalize = NORMALIZE [ kind ]

return normalize and normalize ( value ) or value
end

function fixed : isa ( value ) 
if kind == "boolean" then
return type ( value ) == "boolean"
end

return type ( value ) == "number"
end

return fixed
end

function provider . define ( layout , methods ) 
local byName = { }
for _ , field in ipairs ( layout . fields ) do
byName [ field . name ] = field
end
local identity = { }
local instances = {
__index = function ( self , name ) 
local method = methods . __index and methods . __index [ name ]
if method ~= nil then
return method
end

assert ( byName [ name ] ~= nil , "nupp: " .. layout . name .. " has no field " .. tostring ( name ) )

return rawget ( self , identity ) [ name ]
end ,
__newindex = function ( self , name , value ) 
local field = byName [ name ]
assert ( field ~= nil , "nupp: " .. layout . name .. " has no field " .. tostring ( name ) )
rawget ( self , identity ) [ name ] = stored ( field , value )
end ,
}
local fixed = { name = layout . name , }
function fixed : zero ( ) 
local value = setmetatable ( { [ identity ] = { } } , instances )
for _ , field in ipairs ( layout . fields ) do
local initial = field . type and field . type : new ( ) or false
if field . kind ~= "boolean" then
initial = field . type and initial or 0
end
value [ field . name ] = initial
end

return value
end

fixed . new = fixed . zero
function fixed : of ( ... ) 
local value = self : zero ( )
local args = { ... }
for index , field in ipairs ( layout . fields ) do
if args [ index ] ~= nil then
value [ field . name ] = args [ index ]
end
end

return value
end

function fixed : copy ( value ) 
assert ( self : isa ( value ) , "nupp: cannot copy a value of another struct type" )
local out = self : zero ( )
for _ , field in ipairs ( layout . fields ) do
out [ field . name ] = value [ field . name ]
end

return out
end

function fixed : isa ( value ) 
return type ( value ) == "table" and getmetatable ( value ) == instances
end




setmetatable ( fixed , {
__call = function ( _ , ... ) 
return fixed : of ( ... )
end ,
__index = methods . __index ,
} )

return fixed
end

function provider . array ( element , count ) 
local identity = { }
local values = {
__index = function ( self , index ) 
assert (
type ( index ) == "number" and index % 1 == 0 and index >= 0 and index < count ,
"fixed-array index out of bounds"
)

return rawget ( self , identity ) [ index ]
end ,
__newindex = function ( self , index , value ) 
assert (
type ( index ) == "number" and index % 1 == 0 and index >= 0 and index < count ,
"fixed-array index out of bounds"
)
rawget ( self , identity ) [ index ] = element : copy ( value )
end ,
}
local fixed = { }
function fixed : new ( ) 
local out = setmetatable ( { [ identity ] = { } } , values )
for index = 0 , count - 1 do
rawget ( out , identity ) [ index ] = element : zero ( )
end

return out
end

function fixed : copy ( value ) 
assert ( self : isa ( value ) , "nupp: cannot copy a value of another fixed-array type" )
local out = self : new ( )
for index = 0 , count - 1 do
rawget ( out , identity ) [ index ] = element : copy ( value [ index ] )
end

return out
end

function fixed : isa ( value ) 
return type ( value ) == "table" and getmetatable ( value ) == values
end

return fixed
end

local __nuppExportValue= provider ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.tablestruct"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.tablestruct"]=__nuppExports;return __nuppExports