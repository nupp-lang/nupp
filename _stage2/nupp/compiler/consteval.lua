_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);

local T = require ( "nupp.compiler.types" )
local cst = require ( "nupp.compiler.cst" )

local consteval = { }

local MAX_EXACT = 9007199254740991




local function integer ( text )
local value = tonumber ( text )
if not value or value ~= math . floor ( value ) or math . abs ( value ) > MAX_EXACT then
return nil
end

return value
end

function consteval . fromType ( t )
if t . tag == "literal" then
if t . base == T . string then
return T . constLiteral ( "string" , t . constant )
elseif t . base == T . boolean then
return T . constLiteral ( "boolean" , t . constant )
elseif t . base == T . integer then
return T . constLiteral ( "integer" , t . constant )
end
elseif t . tag == "neutral" and t . op == "singleton" then
return t . constTerm
end

return nil
end

function consteval . singleton ( term )



if term . tag == "constLiteral" and term . domain ~= "function" then
local base = term . domain == "string" and T . string or term . domain == "boolean" and T . boolean or T . integer
return T . literal ( term . value , base )
end

return T . neutral ( "singleton" , nil , nil , nil , nil , nil , nil , nil , term )
end

function consteval . parse ( node , lookup )
if not node then
return nil , "const expression expected"
end
if node . kind == "number" then
local value = node . token and integer ( node . token . text ) or nil
if not value then
return nil , "const integer must be exactly representable"
end
return T . constLiteral ( "integer" , value ) , nil
elseif node . kind == "string" then
local text = node . token and node . token . text or "''"
return T . constLiteral ( "string" , text : sub ( 2 , - 2 ) )
elseif node . kind == "trueExpr" or node . kind == "falseExpr" then
return T . constLiteral ( "boolean" , node . kind == "trueExpr" )
elseif node . kind == "name" and node . token then
local found = lookup ( node . token . text )
return found , found and nil or ( "%q is not a compile-time-known value" ) : format ( node . token . text )
elseif node . kind == "paren" then
return consteval . parse ( node . expr , lookup )
elseif node . kind == "unop" and node . op and ( node . op . kind == "-" or node . op . kind == "+" ) then
local operand , err = consteval . parse ( node . operand , lookup )
if not operand then
return nil , err
end
return T . constOp ( node . op . kind , { operand } )
elseif node . kind == "binop" and node . op then
local allowed = {
[ '+' ] = true ,
[ '-' ] = true ,
[ '*' ] = true ,
[ '//' ] = true ,
[ '%' ] = true ,
[ '==' ] = true ,
[ '~=' ] = true ,
[ '<' ] = true ,
[ '<=' ] = true ,
[ '>' ] = true ,
[ '>=' ] = true
}
if not allowed [ node . op . kind ] then
return nil , ( "operator %q is not in the const expression grammar" ) : format ( node . op . kind )
end
local left , leftErr = consteval . parse ( node . lhs , lookup )
if not left then
return nil , leftErr
end
local right , rightErr = consteval . parse ( node . rhs , lookup )
if not right then
return nil , rightErr
end
return T . constOp ( node . op . kind , { left , right } )
end

return nil , "expression is not admitted in a const generic argument"
end

local function checkedInteger ( value )
if value ~= math . floor ( value ) or math . abs ( value ) > MAX_EXACT then
return nil , "const integer operation overflowed the exact integer domain"
end
return value
end

function consteval . reduce ( term , bindings )
if term . tag == "constLiteral" then
return term
end
if term . tag == "constVar" then
return bindings and bindings [ term ] or term
end
if term . operation == "conflict" then
return term , "conflicting const inference candidates"
end
local operands = { }
local closed = true
for j , operand in ipairs ( term . operands ) do
local reduced , err = consteval . reduce ( operand , bindings )
if err then
return term , err
end
operands [ j ] = reduced
if reduced . tag ~= "constLiteral" then
closed = false
end
end
if not closed then
return T . constOp ( term . operation , operands ) , nil
end
local left = operands [ 1 ]
local right = operands [ 2 ]
local op = term . operation
if # operands == 1 then
if left . domain ~= "integer" then
return term , "unary const arithmetic requires integer"
end
local value , err = checkedInteger ( op == "-" and - ( left . value ) or left . value )
return value and T . constLiteral ( "integer" , value ) or term , err
end
if op == "==" or op == "~=" then
local equal = left . domain == right . domain and left . value == right . value
return T . constLiteral ( "boolean" , op == "==" and equal or not equal )
end
if op == "<" or op == "<=" or op == ">" or op == ">=" then
if left . domain ~= right . domain then
return term , "const comparison domains differ"
end
if left . domain == "boolean" then
return term , "booleans are not ordered const values"
end
local value
if left . domain == "integer" then
local a , b = left . value , right . value
value = op == "<" and a < b or op == "<=" and a <= b or op == ">" and a > b or a >= b
else
local a , b = left . value , right . value
value = op == "<" and a < b or op == "<=" and a <= b or op == ">" and a > b or a >= b
end
return T . constLiteral ( "boolean" , value )
end
if left . domain ~= "integer" or right . domain ~= "integer" then
return term , "const arithmetic requires integer operands"
end
local a , b = left . value , right . value
if ( op == "//" or op == "%" ) and b == 0 then
return term , "const integer division by zero"
end
local raw = op == "+" and a + b or op == "-" and a - b or op == "*" and a * b or op == "//" and math . floor (
a / b
) or a % b
local value , err = checkedInteger ( raw )

return value and T . constLiteral ( "integer" , value ) or term , err
end

return consteval
