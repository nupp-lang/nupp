_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.internal.timestamps"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local dateTime;__nuppExports["dateTime"]=function(...) return dateTime(...) end;local epoch;__nuppExports["epoch"]=function(...) return epoch(...) end;local parseDateTime;__nuppExports["parseDateTime"]=function(...) return parseDateTime(...) end;local parseEpoch;__nuppExports["parseEpoch"]=function(...) return parseEpoch(...) end;

local core = require ( "nupp.serde.internal.value" )

local function leap ( year ) 
return year % 4 == 0 and ( year % 100 ~= 0 or year % 400 == 0 )
end

local function before ( year ) 
local previous = year - 1
return 365 * previous + math . floor ( previous / 4 ) - math . floor ( previous / 100 ) + math . floor ( previous / 400 )
end

local months = { 31 , 28 , 31 , 30 , 31 , 30 , 31 , 31 , 30 , 31 , 30 , 31 }

parseDateTime=function ( text ) 
local y , m , d , h , minute , second , fraction = text : match ( "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)Z$" )
if y == nil then
error ( "expected a UTC date-time" , 2 )
end
local year , month , day = tonumber ( y ) , tonumber ( m ) , tonumber ( d )
local hour , min , sec = tonumber ( h ) , tonumber ( minute ) , tonumber ( second )
if year < 1 or month < 1 or month > 12 then
error ( "invalid date" , 2 )
end
local maximum = months [ month ] + ( month == 2 and ( year % 4 == 0 and ( year % 100 ~= 0 or year % 400 == 0 ) ) and 1 or 0 )
if day < 1 or day > maximum or hour > 23 or min > 59 or sec > 59 then
error ( "invalid date-time" , 2 )
end
local nanos = 0
if fraction ~= "" then
local digits = fraction : match ( "^%.(%d+)$" )
if digits == nil or # digits > 9 then
error ( "invalid nanosecond fraction" , 2 )
end
nanos = tonumber ( digits .. string . rep ( "0" , 9 - # digits ) )
end
local days = before ( year ) - before ( 1970 ) + day - 1
for index = 1 , month - 1 do
days += months [ index ]
end
if month > 2 and ( year % 4 == 0 and ( year % 100 ~= 0 or year % 400 == 0 ) ) then
days += 1
end

return ( _G.setmetatable({ seconds =  tostring ( days * 86400 + hour * 3600 + min * 60 + sec ) ,  nanos =  nanos }, core.Timestamp) )
end ;__nuppExports["parseDateTime"]=parseDateTime

dateTime=function ( value ) 
local seconds = tonumber ( value . seconds )
if seconds == nil or seconds % 1 ~= 0 or value . nanos < 0 or value . nanos >= 1000000000 then
error ( "invalid timestamp" , 2 )
end
local days = math . floor ( seconds / 86400 )
local low = 1
local high = 10000
local absolute = days + before ( 1970 )
if absolute < 0 or absolute >= before ( 10000 ) then
error ( "date-time year is out of range" , 2 )
end
while low + 1 < high do
local middle = math . floor ( ( low + high ) / 2 )
if before ( middle ) <= absolute then
low = middle
else
high = middle
end
end
local day = absolute - before ( low )
local month = 1
while true do
local size = months [ month ] + ( month == 2 and ( low % 4 == 0 and ( low % 100 ~= 0 or low % 400 == 0 ) ) and 1 or 0 )
if day < size then
do break end
end
day -= size
month += 1
end
local time = seconds - days * 86400
local fraction = value . nanos == 0 and "" or "." .. ( "%09d" ) : format ( value . nanos ) : gsub ( "0+$" , "" )

return (
"%04d-%02d-%02dT%02d:%02d:%02d%sZ"
) : format ( low , month , day + 1 , math . floor ( time / 3600 ) , math . floor ( time / 60 ) % 60 , time % 60 , fraction )
end ;__nuppExports["dateTime"]=dateTime


local function step ( digits , increase ) 
local result = { }
local carry = increase and 1 or -1
for index = # digits , 1 , -1 do
local value = string . byte ( digits , index ) - 48 + carry
if value == 10 then
value , carry = 0 , 1
elseif value == -1 then
value , carry = 9 , -1
else
carry = 0
end
result [ index ] = string . char ( 48 + value )
end
local text = table . concat ( result )
if carry == 1 then
text = "1" .. text
end
text = text : gsub ( "^0+" , "" )

return text == "" and "0" or text
end

local function seconds ( text ) 
if not text : match ( "^%-?%d+$" ) then
error ( "invalid epoch seconds" , 2 )
end
local digits = text : sub ( 1 , 1 ) == "-" and text : sub ( 2 ) or text
if # digits > 1 and digits : sub ( 1 , 1 ) == "0" then
error ( "epoch seconds have leading zeroes" , 2 )
end
end

epoch=function ( value ) 
seconds ( value . seconds )
if value . nanos < 0 or value . nanos >= 1000000000 then
error ( "invalid nanoseconds" , 2 )
end
if value . nanos == 0 then
return value . seconds
end
local whole , nanos = value . seconds , value . nanos
if whole : sub ( 1 , 1 ) == "-" and whole ~= "-0" then
whole , nanos = "-" .. step ( whole : sub ( 2 ) , false ) , 1000000000 - nanos
elseif whole == "-0" then
whole = "0"
end

return whole .. "." .. ( "%09d" ) : format ( nanos ) : gsub ( "0+$" , "" )
end ;__nuppExports["epoch"]=epoch

parseEpoch=function ( text ) 
local whole , fraction = text : match ( "^(%-?%d+)%.(%d+)$" )
if whole == nil then
seconds ( text )
return ( _G.setmetatable({ seconds =  text == "-0" and "0" or text ,  nanos =  0 }, core.Timestamp) )
end
seconds ( whole )
if # fraction > 9 then
error ( "timestamp precision exceeds nanoseconds" , 2 )
end
local nanos = tonumber ( fraction .. string . rep ( "0" , 9 - # fraction ) )
if whole : sub ( 1 , 1 ) == "-" and nanos ~= 0 then
whole , nanos = "-" .. step ( whole : sub ( 2 ) , true ) , 1000000000 - nanos
elseif whole == "-0" then
whole = "0"
end

return ( _G.setmetatable({ seconds =  whole ,  nanos =  nanos }, core.Timestamp) )
end ;__nuppExports["parseEpoch"]=parseEpoch
 end);if not __nuppOk then package.loaded["nupp.serde.internal.timestamps"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.timestamps"]=__nuppExports;return __nuppExports