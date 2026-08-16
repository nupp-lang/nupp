_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);

local MAX_CANONICAL_BYTES = 1048576
local MAX_OUTPUT_BYTES = 2097152

local function allowed ( opts )
return not opts or not opts . probe or opts . probe ( )
end

local function within ( text , opts )
return not opts or not opts . limit or # text <= opts . limit
end

local canonicalValue
canonicalValue = function ( value , opts , active )
if not allowed ( opts ) then
return nil , "cancelled"
end
local kind = type ( value )
local scalar
if kind == "nil" then
scalar = "n"
elseif kind == "boolean" then
scalar = value and "t" or "f"
elseif kind == "number" then
scalar = "d" .. string . format ( "%.17g" , value )
elseif kind == "string" then
scalar = "s" .. # value .. ":" .. value
elseif kind ~= "table" then
return nil , "invalid"
end
if scalar then
return within ( scalar , opts ) and scalar or nil , within ( scalar , opts ) and nil or "limit"
end
if active [ value ] then
return nil , "cycle"
end
active [ value ] = true
local keys = { }
for key in pairs ( value ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys , function ( a , b )
return tostring ( a ) < tostring ( b )
end )
local out = { "{" }
local size = 1
for _ , key in ipairs ( keys ) do
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
out [ # out + 1 ] = encodedKey
out [ # out + 1 ] = encodedValue
size = size + # encodedKey + # encodedValue
if opts and opts . limit and size + 1 > opts . limit then
active [ value ] = nil
return nil , "limit"
end
end
out [ # out + 1 ] = "}"
active [ value ] = nil
local encoded = table . concat ( out )

return within ( encoded , opts ) and encoded or nil , within ( encoded , opts ) and nil or "limit"
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
if not allowed ( opts ) then
return nil , "cancelled"
end
local kind = type ( value )
local scalar
if value == nil then
scalar = "nil"
elseif kind == "boolean" then
scalar = tostring ( value )
elseif kind == "string" then
scalar = ( "%q" ) : format ( value )
elseif kind == "number" then
scalar = value == 0 and 1 / value < 0 and "-0.0" or ( "%.17g" ) : format ( value )
elseif kind ~= "table" then
return nil , "invalid"
end
if scalar then
return within ( scalar , opts ) and scalar or nil , within ( scalar , opts ) and nil or "limit"
end
if active [ value ] then
return nil , "cycle"
end
active [ value ] = true
local parts = { }
local size = 2
for index = 1 , # value do
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

return within ( rendered , opts ) and rendered or nil , within ( rendered , opts ) and nil or "limit"
end


local function render ( value , opts )
return renderValue ( value , opts or { } , { } )
end

local codec = {
MAX_CANONICAL_BYTES = MAX_CANONICAL_BYTES ,
MAX_OUTPUT_BYTES = MAX_OUTPUT_BYTES ,
canonical = canonical ,
canonicalRoot = canonicalRoot ,
render = render ,
}

return codec
