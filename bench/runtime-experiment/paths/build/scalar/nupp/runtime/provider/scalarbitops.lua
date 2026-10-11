_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















local MODULUS = 4294967296
local SIGN = 2147483648

local function unsigned ( value ) 
if value ~= value or value == math . huge or value == - math . huge then
return 0
end
local whole = math . floor ( value )
local fraction = value - whole
if fraction > 0.5 or fraction == 0.5 and whole % 2 ~= 0 then
whole = whole + 1
end

return whole % 4294967296
end

local function signed ( value ) 
value = unsigned ( value )
return ( value >= 2147483648 and value - 4294967296 or value )
end

local function combine ( left , right , operation ) 
left , right = unsigned ( left ) , unsigned ( right )
local place , answer = 1 , 0
for _ = 1 , 32 do
local a , b = left % 2 , right % 2
local selected = operation == "and" and a == 1 and b == 1
or operation == "or" and ( a == 1 or b == 1 )
or operation == "xor" and a ~= b
if selected then
answer = answer + place
end
left , right , place = math . floor ( left / 2 ) , math . floor ( right / 2 ) , place * 2
end

return signed ( answer )
end

local function fold ( operation , identity , first , ... ) 
local answer = combine ( identity , first , operation )
for index = 1 , select ( "#" , ... ) do
answer = combine ( answer , select ( index , ... ) , operation )
end

return answer
end

local function tobit ( value ) 
return signed ( value )
end

local function band ( first , ... ) 
return fold ( "and" , -1 , first , ... )
end

local function bor ( first , ... ) 
return fold ( "or" , 0 , first , ... )
end

local function bxor ( first , ... ) 
return fold ( "xor" , 0 , first , ... )
end

local function bnot ( value ) 
return signed ( 4294967295 - unsigned ( value ) )
end

local function lshift ( value , count ) 
return signed ( unsigned ( value ) * 2 ^ ( unsigned ( count ) % 32 ) )
end

local function rshift ( value , count ) 
return signed ( math . floor ( unsigned ( value ) / 2 ^ ( unsigned ( count ) % 32 ) ) )
end

local function arshift ( value , count ) 
count = unsigned ( count ) % 32
value = signed ( value )
return signed ( math . floor ( value / 2 ^ count ) )
end

local function rol ( value , count ) 
count = unsigned ( count ) % 32
if count == 0 then
return signed ( value )
end

return bor ( lshift ( value , count ) , rshift ( value , 32 - count ) )
end

local function ror ( value , count ) 
return rol ( value , 32 - unsigned ( count ) % 32 )
end

local function bswap ( value ) 
local b0 = band ( value , 255 )
local b1 = band ( ( signed ( math . floor ( unsigned ( value ) / 2 ^ ( unsigned ( 8 ) % 32 ) ) ) ) , 255 )
local b2 = band ( ( signed ( math . floor ( unsigned ( value ) / 2 ^ ( unsigned ( 16 ) % 32 ) ) ) ) , 255 )
local b3 = band ( ( signed ( math . floor ( unsigned ( value ) / 2 ^ ( unsigned ( 24 ) % 32 ) ) ) ) , 255 )

return bor ( ( signed ( unsigned ( b0 ) * 2 ^ ( unsigned ( 24 ) % 32 ) ) ) , ( signed ( unsigned ( b1 ) * 2 ^ ( unsigned ( 16 ) % 32 ) ) ) , ( signed ( unsigned ( b2 ) * 2 ^ ( unsigned ( 8 ) % 32 ) ) ) , b3 )
end

local function tohex ( value , digits ) 
digits = digits or 8
local upper = digits < 0
digits = math . min ( math . abs ( signed ( digits ) ) , 254 )
if digits == 0 then
return ""
end
local text = ("%08x") : format ( unsigned ( value ) )
text = digits > 8 and string . rep ( "0" , digits - 8 ) .. text or text : sub ( - digits )

return upper and text : upper ( ) or text
end

local __nuppExportValue= {
tobit = tobit ,
band = band ,
bor = bor ,
bxor = bxor ,
bnot = bnot ,
lshift = lshift ,
rshift = rshift ,
arshift = arshift ,
rol = rol ,
ror = ror ,
bswap = bswap ,
tohex = tohex ,
} ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.provider.scalarbitops"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.provider.scalarbitops"]=__nuppExports;return __nuppExports