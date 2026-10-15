_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local text = { }

local HEX = "0123456789ABCDEF"


local function hex32 ( value ) 
local digits = { }
local rest = value
for position = 8 , 1 , -1 do
local digit = rest % 16
digits [ position ] = ("0123456789ABCDEF") : sub ( digit + 1 , digit + 1 )
rest = ( rest - digit ) / 16
end

return table . concat ( digits )
end


function text . doubleWords ( value ) 
if value ~= value then
return 2146959360 , 0
end
if value == math . huge then
return 2146435072 , 0
elseif value == - math . huge then
return 4293918720 , 0
end
local sign = ( value < 0 or ( value == 0 and 1 / value < 0 ) ) and 2147483648 or 0
local magnitude = math . abs ( value )
if magnitude == 0 then
return sign , 0
end
local fraction , exponent = math . frexp ( magnitude )


local biased = exponent + 1022
local mantissa
if biased <= 0 then

biased = 0
mantissa = magnitude / 2 ^ -1074
else
mantissa = ( fraction * 2 - 1 ) * 2 ^ 52
end
local low = mantissa % 2 ^ 32
local high = sign + biased * 2 ^ 20 + ( mantissa - low ) / 2 ^ 32

return high , low
end


function text . double ( value ) 
local high , low = text . doubleWords ( value )

return "0x" .. hex32 ( high ) .. hex32 ( low )
end




function text . decimal ( spelling ) 
local value = tonumber ( spelling )
if spelling == "inf" then
value = math . huge
elseif spelling == "-inf" then
value = - math . huge
end
if value == nil then
error ( "not a numeric literal: " .. spelling , 0 )
end

return text . double ( value )
end



function text . float ( value ) 
return text . double ( value )
end



function text . roundToFloat ( value ) 
if value ~= value or value == 0 or value == math . huge or value == - math . huge then
return value
end
local magnitude = math . abs ( value )
local _ , exponent = math . frexp ( magnitude )

local unit = 2 ^ math . max ( exponent - 24 , -149 )
local scaled = magnitude / unit
local floor = math . floor ( scaled )
local rest = scaled - floor
local rounded = floor
if rest > 0.5 or ( rest == 0.5 and floor % 2 == 1 ) then
rounded = floor + 1
end
local result = rounded * unit
if result >= 2 ^ 128 then
result = math . huge
end

return value < 0 and - result or result
end


function text . bytes ( value ) 
local parts = { }
for index = 1 , # value do
local byte = value : byte ( index )
if byte >= 32 and byte < 127 and byte ~= 34 and byte ~= 92 then
parts [ # parts + 1 ] = string . char ( byte )
else
parts [
# parts + 1
] = "\\" .. ("0123456789ABCDEF") : sub (
math . floor ( byte / 16 ) + 1 ,
math . floor ( byte / 16 ) + 1
) .. ("0123456789ABCDEF") : sub ( byte % 16 + 1 , byte % 16 + 1 )
end
end

return table . concat ( parts )
end


function text . name ( sigil , value ) 
if value : match ( "^[%a_$.][%w_$.]*$" ) ~= nil then
return sigil .. value
end

return sigil .. "\"" .. text . bytes ( value ) .. "\""
end


function text . integer ( value ) 
return ("%.0f") : format ( value )
end

local __nuppExportValue= text ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.text"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.text"]=__nuppExports;return __nuppExports