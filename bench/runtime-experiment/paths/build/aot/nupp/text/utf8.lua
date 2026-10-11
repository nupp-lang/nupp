_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





































































































local stringByte = string . byte

local REPLACEMENT = 65533

local function bytes ( value ) 
if type ( value ) == "string" then

return tostring ( value )
end

return ( value ) : getString ( )
end


local function offset ( value , at , allowEnd ) 
if at ~= math . floor ( at ) then
error ( "nupp: UTF-8 byte offset must be an integer" , 3 )
end
local limit = # value + ( allowEnd and 1 or 0 )
if at < 1 or at > limit then
error ( "nupp: UTF-8 byte offset is out of range" , 3 )
end

return at
end




local function decode ( source , at ) 
local first = stringByte ( source , at )
if not first then
return nil , at
end
if first < 128 then
return first , at + 1
end
local need = 0
local code = 0
local min = 0
if first >= 194 and first <= 223 then
need , code , min = 1 , first - 192 , 128
elseif first >= 224 and first <= 239 then
need , code , min = 2 , first - 224 , 2048
elseif first >= 240 and first <= 244 then
need , code , min = 3 , first - 240 , 65536
else
return 65533 , at + 1
end
for index = 1 , need do
local continuation = stringByte ( source , at + index )
if not continuation or continuation < 128 or continuation > 191 then
return 65533 , at + 1
end
code = code * 64 + continuation - 128
end
if code < min or code > 1114111 or ( code >= 55296 and code <= 57343 ) then
return 65533 , at + 1
end

return code , at + need + 1
end










local function scan ( source , limit ) 
local at = 1
while at <= limit do
local lead = stringByte ( source , at )
if lead < 128 then
at = at + 1
elseif lead < 224 then
if lead < 194 or at + 1 > limit then
return at - 1
end
local second = stringByte ( source , at + 1 )
if second < 128 or second > 191 then
return at - 1
end
at = at + 2
elseif lead < 240 then
if at + 2 > limit then
return at - 1
end
local second = stringByte ( source , at + 1 )
local third = stringByte ( source , at + 2 )
if second < 128 or second > 191 or third < 128 or third > 191 then
return at - 1
end
if ( lead == 224 and second < 160 ) or ( lead == 237 and second > 159 ) then
return at - 1
end
at = at + 3
elseif lead < 245 then
if at + 3 > limit then
return at - 1
end
local second = stringByte ( source , at + 1 )
local third = stringByte ( source , at + 2 )
local fourth = stringByte ( source , at + 3 )
if second < 128 or second > 191 or third < 128 or third > 191 or fourth < 128 or fourth > 191 then
return at - 1
end
if ( lead == 240 and second < 144 ) or ( lead == 244 and second > 143 ) then
return at - 1
end
at = at + 4
else
return at - 1
end
end

return limit
end

local utf8 = { }













function utf8 . length ( value ) 
local source = bytes ( value )
local count = 0
local at = 1
while at <= # source do
local _ , nextAt = decode ( source , at )
at = nextAt
count = count + 1
end

return count
end






















function utf8 . decodeAt ( value , byteOffset ) 
local source = bytes ( value )

return decode ( source , offset ( source , byteOffset , true ) )
end





















function utf8 . decodeBefore ( value , byteOffset ) 
local source = bytes ( value )
local at = offset ( source , byteOffset , true )
if at == 1 then
return nil , 1
end
local start = at - 1
while start > 1 and stringByte ( source , start ) >= 128 and stringByte ( source , start ) <= 191 do
start = start - 1
end
local codepoint , nextAt = decode ( source , start )


if nextAt ~= at then
return 65533 , at - 1
end

return codepoint , start
end

















function utf8 . encode ( codepoint ) 
if codepoint ~= math . floor ( codepoint ) or codepoint < 0 or codepoint > 1114111 then
error ( "nupp: UTF-8 codepoint is out of range" , 2 )
end
if codepoint < 128 then
return string . char ( codepoint )
end


local low = ( codepoint % 64 )
if codepoint < 2048 then
return string . char ( 192 + math . floor ( codepoint / 64 ) , 128 + low )
end
local middle = ( math . floor ( codepoint / 64 ) % 64 )
if codepoint < 65536 then
return string . char ( 224 + math . floor ( codepoint / 4096 ) , 128 + middle , 128 + low )
end

return string . char (
240 + math . floor ( codepoint / 262144 ) ,
128 + ( math . floor ( codepoint / 4096 ) % 64 ) ,
128 + middle ,
128 + low
)
end












function utf8 . isValid ( value ) 
local source = bytes ( value )

return scan ( source , # source ) == # source
end















function utf8 . validPrefixLength ( value , maxBytes ) 
local source = bytes ( value )
if maxBytes ~= math . floor ( maxBytes ) or maxBytes == math . huge or maxBytes == - math . huge then
error ( "nupp: UTF-8 byte limit must be an integer" , 2 )
end

return scan ( source , math . max ( 0 , math . min ( # source , maxBytes ) ) )
end













function utf8 . truncate ( text , maxBytes ) 
return text : sub ( 1 , utf8 . validPrefixLength ( text , maxBytes ) )
end

local __nuppExportValue= utf8 ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.text.utf8"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.text.utf8"]=__nuppExports;return __nuppExports