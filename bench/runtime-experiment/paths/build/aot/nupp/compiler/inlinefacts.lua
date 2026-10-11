_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local cst = require ( "nupp.compiler.syntax.cst" )
local T = require ( "nupp.compiler.types" )
local inlinefacts = { }
local SCALARS = { number = true , integer = true , boolean = true , string = true }
local OPERATORS = {
[ "+" ] = true ,
[ "-" ] = true ,
[ "*" ] = true ,
[ "/" ] = true ,
[ "%" ] = true ,
[ "^" ] = true ,
[ "==" ] = true ,
[ "~=" ] = true ,
[ "<" ] = true ,
[ "<=" ] = true ,
[ ">" ] = true ,
[ ">=" ] = true ,
[ "and" ] = true ,
[ "or" ] = true ,
[ "not" ] = true ,
[ "#" ] = true
}

function inlinefacts . infer ( body ) 
local stats = body and body . body and body . body . stats or { }
local returned = # stats == 1 and stats [ 1 ]
if not returned
or returned . kind ~= "returnStmt"
or # ( returned . exprs or { } ) ~= 1
or body . generics
or body . varargParam
or body . aotRequired
then
return { reason = "body-shape" }
end
local params , positions = { } , { }
for index , param in ipairs ( body . params or { } ) do
local name = param . name
local t = name and ( name . inferredType or name . definition and name . definition . type )
if not t or not SCALARS [ t . tag ] or not name . definition or param . vararg or param . constTok or param . modeTok then
return { reason = "parameter-representation" }
end
params [ index ] = { name = name . text , type = t . tag }
positions [ name . definition ] = index
end
local size = 0

local function encode ( node ) 
if not node or cst . isToken ( node ) then
return nil
end
size = size + 1
if size > 48
or node . effectUnknownOperation
or node . wideArithmetic
or node . wideIntegerLiteralText
or node . fixedArithmetic
or node . scalarIntrinsic
then
return nil
end
local kind = node . kind
if kind == "name" then
local position = node . token and positions [ node . token . definition ]
return position and { kind = "parameter" , position = position } or nil
elseif kind == "number" then
local text = node . token and node . token . text
return text and tonumber ( text ) and { kind = kind , text = text } or nil
elseif kind == "string" or kind == "nilExpr" or kind == "trueExpr" or kind == "falseExpr" then
local text = node . token . text
if text : find ( "[\13\n]" ) then
return nil
end
return { kind = kind , text = text }
elseif kind == "paren" then
local expression = encode ( node . expr )
return expression and { kind = "paren" , left = expression } or nil
elseif kind == "binop" or kind == "unop" then
local op = node . op and node . op . kind
local t = node . resolvedType or node . inferredType
if not OPERATORS [ op ] or t and not SCALARS [ t . tag ] then
return nil
end
local left = encode ( kind == "binop" and node . lhs or node . operand )
local right = kind == "binop" and encode ( node . rhs ) or nil
if not left or kind == "binop" and not right then
return nil
end
return { kind = kind , op = op , left = left , right = right , type = t and t . tag }
end

return nil
end

local expression = encode ( returned . exprs [ 1 ] )
if not expression then
return { reason = size > 48 and "body-budget" or "nonportable-operation" }
end

return { version = 1 , params = params , expression = expression , size = size }
end

function inlinefacts . instantiate ( artifact , at ) 
if not artifact or artifact . version ~= 1 or not artifact . expression or # ( artifact . params or { } ) > 16 then
return nil
end
local params , definitions = { } , { }

local function token ( kind , text ) 
return { kind = kind , text = text , trivia = { } , line = at . line , col = at . col , offset = at . offset }
end

for index , param in ipairs ( artifact . params or { } ) do
if type ( param . name ) ~= "string" or not SCALARS [ param . type ] then
return nil
end
params [ index ] = param . name
definitions [ param . name ] = { name = param . name , type = ( T ) [ param . type ] }
end
local size = 0

local function decode ( node ) 
if type ( node ) ~= "table" then
return nil
end
size = size + 1
if size > 48 then
return nil
end
local kind = node . kind
if kind == "parameter" then
local param = artifact . params [ node . position ]
if not param then
return nil
end
local name = token ( "name" , param . name )
name . definition = definitions [ param . name ]
return { name , kind = "name" , token = name , resolvedType = ( T ) [ param . type ] }
elseif kind == "number"
or kind == "string"
or kind == "nilExpr"
or kind == "trueExpr"
or kind == "falseExpr"
then
if type ( node . text ) ~= "string" then
return nil
end
local literal = token (
kind == "nilExpr" and "nil" or kind == "trueExpr" and "true" or kind == "falseExpr" and "false" or kind ,
node . text
)
return { literal , kind = kind , token = literal }
elseif kind == "paren" then
local expression = decode ( node . left )
if not expression then
return nil
end
return { token ( "(" , "(" ) , expression , token ( ")" , ")" ) , kind = "paren" , expr = expression }
elseif kind == "binop" or kind == "unop" then
if not OPERATORS [ node . op ] then
return nil
end
local left , right = decode ( node . left ) , node . right and decode ( node . right )
if not left or kind == "binop" and not right then
return nil
end
local op = token ( node . op , node . op )
local t = node . type and ( T ) [ node . type ]
if kind == "binop" then
return { left , op , right , kind = kind , lhs = left , op = op , rhs = right , resolvedType = t }
end
return { op , left , kind = kind , op = op , operand = left , resolvedType = t }
end

return nil
end

local expression = decode ( artifact . expression )
if not expression then
return nil
end

return { params = params , definitions = definitions , expr = expression , free = { } , prefix = { } , imported = true }
end

local __nuppExportValue= inlinefacts ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.inlinefacts"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.inlinefacts"]=__nuppExports;return __nuppExports