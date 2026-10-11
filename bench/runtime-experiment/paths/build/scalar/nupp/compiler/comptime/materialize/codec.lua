_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






local function allowed ( opts ) 
return not opts or not opts . probe or opts . probe ( )
end

local function within ( text , opts ) 
return not opts or not opts . limit or # text <= opts . limit
end

local function quoted ( value ) 
local text = ("%q") : format ( value )
text = text : gsub ( "\n" , "n" ) : gsub ( "\13" , "r" )

return text
end

local canonicalValue
canonicalValue = function ( value , opts , active ) 
if not ( not opts or not opts . probe or opts . probe ( ) ) then
return nil , "cancelled"
end
local kind = type ( value )
local scalar
if kind == "nil" then
scalar = "n"
elseif kind == "boolean" then
scalar = value and "t" or "f"
elseif kind == "number" and value == value and value ~= math . huge and value ~= - math . huge then
scalar = "d" .. string . format ( "%.17g" , value )
elseif kind == "string" then
scalar = "s" .. # value .. ":" .. value
elseif kind ~= "table" then
return nil , "invalid"
end
if scalar then
if ( not opts or not opts . limit or # scalar <= opts . limit ) then
return scalar , nil
end
return nil , "limit"
end
if active [ value ] then
return nil , "cycle"
end
active [ value ] = true
local entries = { }
local size = 1
for key in pairs ( value ) do
local encodedKey , keyError = canonicalValue ( key , opts , active )
if not encodedKey then
active [ value ] = nil ;
return nil , keyError
end
local encodedValue , valueError = canonicalValue ( value [ key ] , opts , active )
if not encodedValue then
active [ value ] = nil ;
return nil , valueError
end
local entry = encodedKey .. encodedValue
entries [ # entries + 1 ] = entry
size = size + # entry
if opts and opts . limit and size + 1 > opts . limit then
active [ value ] = nil
return nil , "limit"
end
end
table . sort ( entries )
local out = { "{" }
for _ , entry in ipairs ( entries ) do
out [ # out + 1 ] = entry
end
out [ # out + 1 ] = "}"
active [ value ] = nil
local encoded = table . concat ( out )

if ( not opts or not opts . limit or # encoded <= opts . limit ) then
return encoded , nil
end

return nil , "limit"
end



local function canonical ( value , opts ) 
return canonicalValue ( value , opts or { } , { } )
end

local function canonicalRoot ( value , opts ) 
local projected = { }
for key , field in pairs ( value ) do
if key ~= "key" and key ~= "fingerprint" then
projected [ key ] = field
end
end

return canonicalValue ( projected , opts or { } , { } )
end

local renderValue
renderValue = function ( value , opts , active ) 
if not ( not opts or not opts . probe or opts . probe ( ) ) then
return nil , "cancelled"
end
local kind = type ( value )
local scalar
if value == nil then
scalar = "nil"
elseif kind == "boolean" then
scalar = tostring ( value )
elseif kind == "string" then
scalar = quoted ( value )
elseif kind == "number" and value == value and value ~= math . huge and value ~= - math . huge then
scalar = value == 0 and 1 / value < 0 and "-0.0" or ("%.17g") : format ( value )
elseif kind ~= "table" then
return nil , "invalid"
end
if scalar then
if ( not opts or not opts . limit or # scalar <= opts . limit ) then
return scalar , nil
end
return nil , "limit"
end
if active [ value ] then
return nil , "cycle"
end
active [ value ] = true
local parts = { }
local size = 2
local length = # value
for key in pairs ( value ) do
if type ( key ) ~= "string" and ( type ( key ) ~= "number" or key ~= math . floor ( key ) or key < 1 or key > length ) then
active [ value ] = nil
return nil , "invalid"
end
end
for index = 1 , length do
local rendered , why = renderValue ( value [ index ] , opts , active )
if not rendered then
active [ value ] = nil ;
return nil , why
end
parts [ # parts + 1 ] = rendered
size = size + # rendered + ( # parts > 1 and 1 or 0 )
if opts and opts . limit and size > opts . limit then
active [ value ] = nil
return nil , "limit"
end
end
local keys = { }
for key in pairs ( value ) do
if type ( key ) == "string" then
keys [ # keys + 1 ] = key
end
end
table . sort ( keys )
for _ , key in ipairs ( keys ) do
local renderedKey , keyError = renderValue ( key , opts , active )
if not renderedKey then
active [ value ] = nil ;
return nil , keyError
end
local renderedValue , valueError = renderValue ( value [ key ] , opts , active )
if not renderedValue then
active [ value ] = nil ;
return nil , valueError
end
local entry = "[" .. renderedKey .. "]=" .. renderedValue
parts [ # parts + 1 ] = entry
size = size + # entry + ( # parts > 1 and 1 or 0 )
if opts and opts . limit and size > opts . limit then
active [ value ] = nil
return nil , "limit"
end
end
active [ value ] = nil
local rendered = "{" .. table . concat ( parts , "," ) .. "}"

if ( not opts or not opts . limit or # rendered <= opts . limit ) then
return rendered , nil
end

return nil , "limit"
end


local function render ( value , opts ) 
return renderValue ( value , opts or { } , { } )
end

local codec = {
MAX_CANONICAL_BYTES = 1048576 ,
MAX_OUTPUT_BYTES = 2097152 ,
canonical = canonical ,
canonicalRoot = canonicalRoot ,
render = render ,
}

local __nuppExportValue= codec ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.comptime.materialize.codec"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.comptime.materialize.codec"]=__nuppExports;return __nuppExports