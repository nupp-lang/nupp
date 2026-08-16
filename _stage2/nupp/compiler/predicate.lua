_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);





















local cst = require ( "nupp.compiler.cst" )

local predicate = { }



predicate.Node = {} predicate.Node.__index = predicate.Node




























local COMPARISONS = {
[ "==" ] = true ,
[ "~=" ] = true ,
[ "<" ] = true ,
[ "<=" ] = true ,
[ ">" ] = true ,
[ ">=" ] = true ,
}



local LUA_TYPES = {
[ "nil" ] = true ,
boolean = true ,
number = true ,
string = true ,
table = true ,
[ "function" ] = true ,
thread = true ,
userdata = true ,
cdata = true ,
}




local function unwrap ( node )
while node and node . kind == "paren" do
node = node . expr
end
return node
end




local function pathOf ( node )
node = unwrap ( node )
if not node then
return nil
end
if node . kind == "name" then
if node . token and node . token . text == "self" then
return { }
end
return nil
end
if node . kind == "dotIndex" then
local base = pathOf ( node . obj )
if not base or not node . name then
return nil
end
local out = { }
for j , segment in ipairs ( base ) do
out [ j ] = segment
end
out [ # out + 1 ] = node . name . text
return out
end

return nil
end




local function literalOf ( node )
node = unwrap ( node )
if not node then
return nil
end
local kind = node . kind
if kind == "string" and node . token then
local text = node . token . text
local quote = text : sub ( 1 , 1 )
if quote ~= '"' and quote ~= "'" then
return nil
end
return text , text : sub ( 2 , - 2 )
elseif kind == "number" and node . token then
local text = node . token . text
if not text : match ( "^%d+$" ) and not text : match ( "^%d+%.%d+$" ) then
return nil
end
return text , tonumber ( text )
elseif kind == "trueExpr" then
return "true" , true
elseif kind == "falseExpr" then
return "false" , false
elseif kind == "nilExpr" then
return "nil" , nil
end

return nil
end


local function typeCallPath ( node )
node = unwrap ( node )
if not node or node . kind ~= "call" then
return nil
end
local callee = unwrap ( node . obj )
if not callee or callee . kind ~= "name" then
return nil
end
if not callee . token or callee . token . text ~= "type" then
return nil
end
local call = node
local args = call . args and ( call . args ) . exprs or nil
if not args or # args ~= 1 then
return nil
end

return pathOf ( args [ 1 ] )
end









function predicate . build ( node )
node = unwrap ( node )
if not node then
return nil , "an empty refinement"
end
local kind = node . kind

if kind == "trueExpr" or kind == "falseExpr" then
return setmetatable({ op =  "const" ,  value =  kind == "trueExpr" }, predicate.Node)
end

if kind == "unop" and node . op and node . op . kind == "not" then
local inner , why = predicate . build ( node . operand )
if not inner then
return nil , why
end
return setmetatable({ op =  "not" ,  a =  inner }, predicate.Node)
end

if kind == "binop" and node . op then
local op = node . op . kind
if op == "and" or op == "or" then
local left , why = predicate . build ( node . lhs )
if not left then
return nil , why
end
local right , why2 = predicate . build ( node . rhs )
if not right then
return nil , why2
end
return setmetatable({ op =  op ,  a =  left ,  b =  right }, predicate.Node)
end
if COMPARISONS [ op ] then


local typePath = typeCallPath ( node . lhs ) or typeCallPath ( node . rhs )
if typePath then
local other = typeCallPath ( node . lhs ) and node . rhs or node . lhs
local text , value = literalOf ( other )
if not text or type ( value ) ~= "string" then
return nil , "a type() test compared with something other " .. "than a type name"
end
if not LUA_TYPES [ value ] then
return nil , ( "%q, which type() never answers" ) : format ( value )
end
if op ~= "==" and op ~= "~=" then
return nil , "a type() test ordered rather than compared"
end
local test = setmetatable({ op =  "typeis" ,  path =  typePath ,  luaType =  value }, predicate.Node)
if op == "~=" then
return setmetatable({ op =  "not" ,  a =  test }, predicate.Node)
end
return test
end

local path = pathOf ( node . lhs )
local other = node . rhs
if not path then
path , other = pathOf ( node . rhs ) , node . lhs
end
if not path then


for _ , side in ipairs ( { unwrap ( node . lhs ) , unwrap ( node . rhs ) } ) do
local sideKind = side and side . kind
if sideKind == "call" or sideKind == "methodCall" or sideKind == "safeCall" then
return nil , "a call"
end
if sideKind == "binop" then
return nil , "arithmetic"
end
end
return nil , "a comparison of two things that are not the " .. "declaration's own fields"
end
local text , value = literalOf ( other )
if not text then
return nil , "a comparison against something that is not a literal"
end
return setmetatable({ op =  "cmp" ,  cmp =  op ,  path =  path ,  literal =  text ,  constant =  value }, predicate.Node)
end
return nil , ( "the %s operator" ) : format ( op )
end


local path = pathOf ( node )
if path then
if # path == 0 then
return nil , "the subject itself"
end
return setmetatable({ op =  "truthy" ,  path =  path }, predicate.Node)
end

if kind == "call" or kind == "methodCall" or kind == "safeCall" then
return nil , "a call"
end
if kind == "string" or kind == "number" or kind == "nilExpr" then
return nil , "a literal"
end

return nil , "this expression"
end










function predicate . equals ( path , constant )
local kind = type ( constant )
local text = nil
if kind == "string" then
text = ( "%q" ) : format ( constant )
elseif kind == "number" then
text = tostring ( constant )
elseif kind == "boolean" then
text = constant and "true" or "false"
end
if not text then
return nil
end

return setmetatable({ op =  "cmp" ,  cmp =  "==" ,  path =  path ,  literal =  text ,  constant =  constant }, predicate.Node)
end


function predicate . both ( a , b )
if not a then
return b
end
if not b then
return a
end

return setmetatable({ op =  "and" ,  a =  a ,  b =  b }, predicate.Node)
end



function predicate . paths ( node , out )
out = out or { }
if not node then
return out
end
if node . path then
out [ # out + 1 ] = node . path
end
predicate . paths ( node . a , out )
predicate . paths ( node . b , out )

return out
end





local function luaTypeOf ( t )
if type ( t ) ~= "table" then
return nil
end
local tag = t . tag
if tag == "literal" then
return luaTypeOf ( t . base )

elseif tag == "prim" then





local name = tag
if name == "string" or name == "cstring" then
return "string"
end
if name == "number" or name == "integer" or name == "float" then
return "number"
end
if name == "boolean" then
return "boolean"

elseif name == "table" then
return "table"

elseif name == "thread" then
return "thread"

elseif name == "userdata" then
return "userdata"
end
return nil

elseif tag == "nominal" then
if t . declKind == "struct" then
return "cdata"
end
if t . declKind == "record" or t . declKind == "interface" then
return "table"
end
return nil
end
if tag == "shape" or tag == "map" or tag == "array" or tag == "tuple" then
return "table"
end
if tag == "func" then
return "function"
end

return nil
end












function predicate . satisfiedBy ( node , fieldAt )
if not node then
return nil
end
local op = node . op

if op == "const" then
return node . value

elseif op == "not" then
local inner = predicate . satisfiedBy ( node . a , fieldAt )
if inner == nil then
return nil
end
return not inner
end
if op == "and" or op == "or" then
local left = predicate . satisfiedBy ( node . a , fieldAt )
local right = predicate . satisfiedBy ( node . b , fieldAt )
if op == "and" then

if left == false or right == false then
return false
end
if left == true and right == true then
return true
end
return nil
end
if left == true or right == true then
return true
end
if left == false and right == false then
return false
end
return nil
end

local t = fieldAt ( node . path or { } )
if t == nil then
return nil
end

if op == "typeis" then
local answer = luaTypeOf ( t )
if answer == nil then
return nil
end
return answer == node . luaType
end
if op == "cmp" and ( node . cmp == "==" or node . cmp == "~=" ) then


if type ( t ) ~= "table" or t . tag ~= "literal" then
return nil
end
local same = t . constant == node . constant
if node . cmp == "~=" then
return not same
else
return same
end
end

return nil
end






function predicate . constant ( node )
if not node then
return nil
end
if node . op == "const" then
return node . value
end
if node . op == "not" then
local inner = predicate . constant ( node . a )
if inner == nil then
return nil
end
return not inner
end
if node . op == "and" or node . op == "or" then
local left , right = predicate . constant ( node . a ) , predicate . constant ( node . b )
if left == nil or right == nil then
return nil
end
if node . op == "and" then
return left and right
else
return left or right
end
end

return nil
end







function predicate . render ( node , subject )
if not node then
return "true"
end
local op = node . op

if op == "const" then
return node . value and "true" or "false"

elseif op == "not" then
return "not (" .. predicate . render ( node . a , subject ) .. ")"
end
if op == "and" or op == "or" then
return "(" .. predicate . render ( node . a , subject ) .. " " .. op .. " " .. predicate . render ( node . b , subject ) .. ")"
end





local access = subject
for j , segment in ipairs ( node . path or { } ) do
access = access .. ( j > 1 and "?." or "." ) .. segment
end

if op == "cmp" then
return access .. " " .. ( node . cmp or "==" ) .. " " .. ( node . literal or "nil" )
elseif op == "typeis" then
return ( "type(%s) == %q" ) : format ( access , node . luaType or "nil" )
end

return access .. " ~= nil"
end






function predicate . test ( node , subject )
local body = predicate . render ( node , subject )
if predicate . constant ( node ) ~= nil then
return body
end

return ( "(type(%s) == \"table\" and %s)" ) : format ( subject , body )
end

return predicate
