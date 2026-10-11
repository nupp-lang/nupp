_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.comptime.materialize.ir\0runtime\0001") };











local MAX_NODES = 20000
local MAX_SOURCE_BYTES = 524288

local HELPERS = {
[ "nupp.peg.codegen" ] = "__nuppPegCodegen" ,
[ "nupp.peg.lpeg" ] = "__nuppPegLpeg" ,
[ "nupp.fieldcodec.keyed" ] = "_G.nupp.fieldcodec.keyed" ,
}

local RESERVED

= {
[ "and" ] = true ,
[ "break" ] = true ,
[ "do" ] = true ,
[ "else" ] = true ,
[ "elseif" ] = true ,
[ "end" ] = true ,
[ "false" ] = true ,
[ "for" ] = true ,
[ "function" ] = true ,
[ "goto" ] = true ,
[ "if" ] = true ,
[ "in" ] = true ,
[ "local" ] = true ,
[ "nil" ] = true ,
[ "not" ] = true ,
[ "or" ] = true ,
[ "repeat" ] = true ,
[ "return" ] = true ,
[ "then" ] = true ,
[ "true" ] = true ,
[ "until" ] = true ,
[ "while" ] = true ,
}



local ir = {} ir.__index = ir ;_G.nupp.__reflect.link(ir,__nuppT1[1],{ })




ir . ABI = 2

local function quote ( value ) 
local kind = type ( value )
if value == nil then
return "nil"
elseif kind == "boolean" then
return tostring ( value )
elseif kind == "string" then
local text = ("%q") : format ( value )
text = text : gsub ( "\n" , "n" ) : gsub ( "\13" , "r" )

return text
elseif kind == "number" and value == value and value ~= math . huge and value ~= - math . huge then
if value == 0 and 1 / value < 0 then
return "-0.0"
end
return ("%.17g") : format ( value )
end

return nil
end

local function validName ( name ) 
return type ( name ) == "string" and name : find ( "^[%a_][%w_]*$" ) ~= nil and not RESERVED [ name ]
end

local function validTypePath ( path ) 
if type ( path ) ~= "string"
or path == ""
or path : sub ( 1 , 1 ) == "."
or path : sub ( -1 ) == "."
or path : find ( ".." , 1 , true )
then
return false
end
for name in path : gmatch ( "[^.]+" ) do
if not ( type ( name ) == "string" and name : find ( "^[%a_][%w_]*$" ) ~= nil and not RESERVED [ name ] ) then
return false
end
end

return true
end

local function list ( value , description ) 
if value == nil then
return { }
end
if type ( value ) ~= "table" then
return nil , "runtime-expression " .. description .. " is not a list"
end
local count = # value
local seen = 0
for key in pairs ( value ) do
if type ( key ) ~= "number" or key ~= math . floor ( key ) or key < 1 or key > count then
return nil , "runtime-expression " .. description .. " is not a dense list"
end
seen = seen + 1
end
if seen ~= count then
return nil , "runtime-expression " .. description .. " is not a dense list"
end

return value
end







function ir . render ( root ) 
local count = 0
local scopes = { { } }

local function visit ( node ) 
count = count + 1
if count > 20000 then
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
for index = # scopes , 1 , -1 do
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
elseif tag == "typeobject" then
if not validTypePath ( node . path ) then
return nil , ("runtime-expression type object has invalid path %q") : format ( tostring ( node . path ) )
end

return node . path
elseif tag == "table" then
local parts = { }
local array , arrayError = list ( node . array , "table array" )
if not array then
return nil , arrayError
end
for _ , child in ipairs ( array ) do
local text , err = renderExpr ( child )
if not text then
return nil , err
end
parts [ # parts + 1 ] = text
end
local seen = { }
local fields , fieldsError = list ( node . fields , "table fields" )
if not fields then
return nil , fieldsError
end
for _ , field in ipairs ( fields ) do
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
local arguments , argumentsError = list ( node . args , "call arguments" )
if not arguments then
return nil , argumentsError
end
for _ , argument in ipairs ( arguments ) do
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
local parameters , parametersError = list ( node . params , "closure parameters" )
if not parameters then
return nil , parametersError
end
for _ , id in ipairs ( parameters ) do
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
local statements , statementsError = list ( stats , "closure body" )
if not statements then
return nil , statementsError
end
local parts = { }
local returned = false
for _ , stat in ipairs ( statements ) do
if returned then
return nil , "runtime-expression closure has a statement after return"
end
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
returned = true
elseif stat . tag == "callstat" then
if type ( stat . value ) ~= "table" or ( stat . value . tag ~= "call" and stat . value . tag ~= "iife" ) then
return nil , "runtime-expression call statement does not contain a call"
end
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
if rendered : find ( "[\13\n]" ) then
return nil , { message = "runtime-expression IR rendered more than one logical line" }
end
if # rendered > 524288 then
return nil , { message = "materialized output exceeds the 524288-byte source limit" }
end

return rendered , nil
end

local __nuppExportValue= ir ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.comptime.materialize.ir"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.comptime.materialize.ir"]=__nuppExports;return __nuppExports