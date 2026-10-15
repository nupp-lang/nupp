_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["example.binarynumbers"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local decode;__nuppExports["decode"]=function(...) return decode(...) end;local encode;__nuppExports["encode"]=function(...) return encode(...) end;

local core = require ( "nupp.serde" )
local numbers = require ( "nupp.serde.codec" )



local function divide ( digits ) 
local result = { }
local remainder = 0
for index = 1 , # digits do
local value = remainder * 10 + assert ( digits : byte ( index ) ) - 48
local digit = math . floor ( value / 256 )
remainder = value % 256
if digit ~= 0 or # result > 0 then
result [ # result + 1 ] = string . char ( digit + 48 )
end
end

return # result == 0 and "0" or table . concat ( result ) , remainder
end

local function multiply ( digits , byte ) 
local result = { }
local carry = byte
for index = # digits , 1 , -1 do
local value = ( assert ( digits : byte ( index ) ) - 48 ) * 256 + carry
result [ # result + 1 ] = string . char ( value % 10 + 48 )
carry = math . floor ( value / 10 )
end
while carry > 0 do
result [ # result + 1 ] = string . char ( carry % 10 + 48 )
carry = math . floor ( carry / 10 )
end

return table . concat ( result ) : reverse ( )
end

local function complement ( bytes ) 
local carry = 1
for index = # bytes , 1 , -1 do
local value = 255 - bytes [ index ] + carry
bytes [ index ] = value % 256
carry = math . floor ( value / 256 )
end
end

encode=function ( value ) 
numbers . integer ( value . decimal , value . width , value . signed )
local negative = value . decimal : sub ( 1 , 1 ) == "-"
local digits = negative and value . decimal : sub ( 2 ) or value . decimal
local bytes = { }
for index = value . width / 8 , 1 , - 1 do
local remainder
digits , remainder = divide ( digits )
bytes [ index ] = remainder
end
assert ( digits == "0" , "integer payload overflow" )
if negative then
complement ( bytes )
end
local parts = { }
for index , byte in ipairs ( bytes ) do
parts [ index ] = string . char ( byte )
end

return table . concat ( parts )
end ;__nuppExports["encode"]=encode

decode=function ( source , width , signed ) 
assert ( # source == width / 8 , "integer payload length does not match its schema" )
local bytes = { }
for index = 1 , # source do
bytes [ index ] = assert ( source : byte ( index ) )
end
local negative = signed and bytes [ 1 ] >= 128
if negative then
complement ( bytes )
end
local digits = "0"
for _ , byte in ipairs ( bytes ) do
digits = multiply ( digits , byte )
end

return numbers . integer ( ( negative and "-" or "" ) .. digits , width , signed )
end ;__nuppExports["decode"]=decode
 end);if not __nuppOk then package.loaded["example.binarynumbers"]=nil;error(__nuppWhy,0) end;package.loaded["example.binarynumbers"]=__nuppExports;return __nuppExports