_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local MAX_NODES = 20000
local MAX_SOURCE_BYTES = 512 * 1024

local HELPERS = {
[ "nupp.peg.codegen" ] = "__nuppPegCodegen" ,
[ "nupp.peg.lpeg" ] = "__nuppPegLpeg" ,
[ "nupp.fieldcodec.keyed" ] = "_G.nupp.fieldcodec.keyed" ,
}



const ir = {} ir.__index = ir




ir . ABI = 1

local function quote ( value )
local kind = type ( value )
if value == nil then
return "nil"
elseif kind == "boolean" then
return tostring ( value )
elseif kind == "string" then
return ( "%q" ) : format ( value )
elseif kind == "number" and value == value and value ~= math . huge and value ~= - math . huge then
if value == 0 and 1 / value < 0 then
return "-0.0"
end
return ( "%.17g" ) : format ( value )
end

return nil
end

local function validName ( name )
return type ( name ) == "string" and name : find ( "^[%a_][%w_]*$" ) ~= nil
end







function ir . render ( root )
local count = 0
local scopes = { { } }

local function visit ( node )
count = count + 1
if count > MAX_NODES then
return nil , "runtime-expression IR exceeds the 20000-node limit"
end
if type ( node ) ~= "table" or type ( node . tag ) ~= "string" then
return nil , "runtime-expression IR contains a node without a tag"
end

return true
end

local function inScope ( id )
if type ( id ) ~= "number" or id ~= math . floor ( id ) or id < 1 then
return false
end
for index = # scopes , 1 , - 1 do
if scopes [ index ] [ id ] then
return true
end
end

return false
end

local renderExpr , renderStats

renderExpr = function ( node )
local ok , why = visit ( node )
if not ok then
return nil , why
end
local tag = node . tag
if tag == "literal" then
local text = quote ( node . value )
if not text then
return nil , "runtime-expression literal is not finite JSON data"
end

return text
elseif tag == "local" then
if not inScope ( node . id ) then
return nil , "runtime-expression IR references an undeclared local"
end

return "_nupp_m" .. tostring ( node . id )
elseif tag == "helper" then
local path = HELPERS [ node . name ]
if not path then
return nil , "runtime-expression IR requests an unknown compiler helper"
end

return path
elseif tag == "table" then
local parts = { }
for _ , child in ipairs ( node . array or { } ) do
local text , err = renderExpr ( child )
if not text then
return nil , err
end
parts [ # parts + 1 ] = text
end
local seen = { }
for _ , field in ipairs ( node . fields or { } ) do
if type ( field ) ~= "table" or not validName ( field . name ) or seen [ field . name ] then
return nil , "runtime-expression table has an invalid or repeated field"
end
seen [ field . name ] = true
local text , err = renderExpr ( field . value )
if not text then
return nil , err
end
parts [ # parts + 1 ] = field . name .. "=" .. text
end

return "{" .. table . concat ( parts , "," ) .. "}"
elseif tag == "field" then
if not validName ( node . name ) then
return nil , "runtime-expression field has an invalid name"
end
local object , err = renderExpr ( node . object )
if not object then
return nil , err
end

return "(" .. object .. ")." .. node . name
elseif tag == "call" then
local callee , err = renderExpr ( node . callee )
if not callee then
return nil , err
end
local args = { }
for _ , argument in ipairs ( node . args or { } ) do
local text , argErr = renderExpr ( argument )
if not text then
return nil , argErr
end
args [ # args + 1 ] = text
end

return "(" .. callee .. ")(" .. table . concat ( args , "," ) .. ")"
elseif tag == "function" then
local own = { }
local params = { }
for _ , id in ipairs ( node . params or { } ) do
if type ( id ) ~= "number" or id ~= math . floor ( id ) or id < 1 or own [ id ] then
return nil , "runtime-expression closure has an invalid parameter slot"
end
own [ id ] = true
params [ # params + 1 ] = "_nupp_m" .. tostring ( id )
end
scopes [ # scopes + 1 ] = own
local body , bodyErr = renderStats ( node . body or { } )
scopes [ # scopes ] = nil
if not body then
return nil , bodyErr
end

return "function(" .. table . concat ( params , "," ) .. ") " .. body .. " end"
elseif tag == "iife" then
scopes [ # scopes + 1 ] = { }
local body , bodyErr = renderStats ( node . body or { } )
scopes [ # scopes ] = nil
if not body then
return nil , bodyErr
end

return "(function() " .. body .. " end)()"
end

return nil , "runtime-expression IR uses unknown expression tag " .. tostring ( tag )
end

renderStats = function ( stats )
if type ( stats ) ~= "table" then
return nil , "runtime-expression closure body is not a statement list"
end
local parts = { }
for _ , stat in ipairs ( stats ) do
local ok , why = visit ( stat )
if not ok then
return nil , why
end
if stat . tag == "let" then
local id = stat . id
local current = scopes [ # scopes ]
if type ( id ) ~= "number" or id ~= math . floor ( id ) or id < 1 or current [ id ] then
return nil , "runtime-expression IR declares an invalid local slot"
end
local value , err = renderExpr ( stat . value )
if not value then
return nil , err
end
current [ id ] = true
parts [ # parts + 1 ] = "local _nupp_m" .. tostring ( id ) .. "=" .. value
elseif stat . tag == "return" then
local value , err = renderExpr ( stat . value )
if not value then
return nil , err
end
parts [ # parts + 1 ] = "return " .. value
elseif stat . tag == "callstat" then
local value , err = renderExpr ( stat . value )
if not value then
return nil , err
end
parts [ # parts + 1 ] = value
else
return nil , "runtime-expression IR uses unknown statement tag " .. tostring ( stat . tag )
end
end

return table . concat ( parts , ";" )
end

local rendered , err = renderExpr ( root )
if not rendered then
return nil , { message = err }
end
if rendered : find ( "[\r\n]" ) then
return nil , { message = "runtime-expression IR rendered more than one logical line" }
end
if # rendered > MAX_SOURCE_BYTES then
return nil , { message = "materialized output exceeds the 524288-byte source limit" }
end

return rendered , nil
end

return ir
