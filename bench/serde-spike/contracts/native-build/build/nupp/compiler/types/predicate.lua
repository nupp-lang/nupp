_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.types.predicate\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.types.predicate\0runtime\0002") };























local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )

local predicate = { }



predicate.Node = {} predicate.Node.__index = predicate.Node ;_G.nupp.__reflect.link(predicate.Node,__nuppT1[1],{ __nuppT1[1] })

































local COMPARISONS = {
[ "==" ] = true ,
[ "~=" ] = true ,
[ "<" ] = true ,
[ "<=" ] = true ,
[ ">" ] = true ,
[ ">=" ] = true ,
}



local FLIPPED = {
[ "==" ] = "==" ,
[ "~=" ] = "~=" ,
[ "<" ] = ">" ,
[ "<=" ] = ">=" ,
[ ">" ] = "<" ,
[ ">=" ] = "<=" ,
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
if quote ~= "\"" and quote ~= "'" then
return nil
end
return text , lexer . stringValue ( text ) or text : sub ( 2 , -2 )
elseif kind == "number" and node . token then
local text = node . token . text : gsub ( "_" , "" )
local lower = text : lower ( )
if lower : match ( "ull$" ) or lower : match ( "ll$" ) or lower : match ( "i$" ) then
return nil
end
local value = tonumber ( text )
if value == nil then
return nil
end

return text , value
elseif kind == "unop" and node . op and ( node . op . kind == "-" or node . op . kind == "+" ) then
local text , value = literalOf ( node . operand )
if not text or type ( value ) ~= "number" then
return nil
end
if node . op . kind == "-" then
return "-(" .. text .. ")" , - ( value )
else
return text , value
end
elseif kind == "trueExpr" then
return "true" , true
elseif kind == "falseExpr" then
return "false" , false
elseif kind == "nilExpr" then
return "nil" , nil
end

return nil
end






local function lengthPath ( node ) 
node = unwrap ( node )
if not node or node . kind ~= "unop" then
return nil
end
if not node . op or node . op . kind ~= "#" then
return nil
end

return pathOf ( node . operand )
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
return ( _G.setmetatable({ op =  "const" ,  value =  kind == "trueExpr" }, predicate.Node) )
end

if kind == "unop" and node . op and node . op . kind == "not" then
local inner , why = predicate . build ( node . operand )
if not inner then
return nil , why
end
return ( _G.setmetatable({ op =  "not" ,  a =  inner }, predicate.Node) )
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
return ( _G.setmetatable({ op =  op ,  a =  left ,  b =  right }, predicate.Node) )
end
if COMPARISONS [ op ] then


local typePath = typeCallPath ( node . lhs ) or typeCallPath ( node . rhs )
if typePath then
local other = typeCallPath ( node . lhs ) and node . rhs or node . lhs
local text , value = literalOf ( other )
if not text or type ( value ) ~= "string" then
return nil , "a type() test compared with something other than a type name"
end
if not LUA_TYPES [ value ] then
return nil , ("%q, which type() never answers") : format ( value )
end
if op ~= "==" and op ~= "~=" then
return nil , "a type() test ordered rather than compared"
end
local test = _G.setmetatable({ op =  "typeis" ,  path =  typePath ,  luaType =  value }, predicate.Node)
if op == "~=" then
return ( _G.setmetatable({ op =  "not" ,  a =  test }, predicate.Node) )
end
return test
end


local lenPath = lengthPath ( node . lhs ) or lengthPath ( node . rhs )
if lenPath then
local flipped = lengthPath ( node . rhs ) ~= nil and lengthPath ( node . lhs ) == nil
local text , value = literalOf ( flipped and node . lhs or node . rhs )
if not text or type ( value ) ~= "number" then
return nil , "a length compared against something that is not a number"
end
local inner = _G.setmetatable({ op =
"cmp" ,  cmp =
flipped and FLIPPED [ op ] or op ,  path =
{ } ,  literal =
text ,  constant =
value }, predicate.Node)

return ( _G.setmetatable({ op =  "len" ,  path =  lenPath ,  a =  inner }, predicate.Node) )
end

local path = pathOf ( node . lhs )
local other = node . rhs
local flipped = false
if not path then
path , other = pathOf ( node . rhs ) , node . lhs
flipped = path ~= nil
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
return nil , "a comparison of two things that are not the declaration's own fields"
end
local text , value = literalOf ( other )
if not text then
return nil , "a comparison against something that is not a literal"
end
if op ~= "==" and op ~= "~=" and type ( value ) ~= "number" and type ( value ) ~= "string" then
return nil , "an ordered comparison against a value Lua cannot order"
end
return ( _G.setmetatable({ op =
"cmp" ,  cmp =
flipped and FLIPPED [ op ] or op ,  path =
path ,  literal =
text ,  constant =
value }, predicate.Node) )

end
return nil , ("the %s operator") : format ( op )
end


local path = pathOf ( node )
if path then
if # path == 0 then
return nil , "the subject itself"
end
return ( _G.setmetatable({ op =  "truthy" ,  path =  path }, predicate.Node) )
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
text = ("%q") : format ( constant )
elseif kind == "number" then
text = tostring ( constant )
elseif kind == "boolean" then
text = constant and "true" or "false"
end
if not text then
return nil
end

return ( _G.setmetatable({ op =  "cmp" ,  cmp =  "==" ,  path =  path ,  literal =  text ,  constant =  constant }, predicate.Node) )
end


function predicate . both ( a , b ) 
if not a then
return b
end
if not b then
return a
end

return ( _G.setmetatable({ op =  "and" ,  a =  a ,  b =  b }, predicate.Node) )
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



local PRIMITIVE_LUA_TYPE

= {
string = "string" ,
cstring = "string" ,
number = "number" ,
integer = "number" ,
float = "number" ,
boolean = "boolean" ,
table = "table" ,
thread = "thread" ,
userdata = "userdata" ,
}





local function luaTypeOf ( t ) 
if type ( t ) ~= "table" then
return nil
end
local tag = t . tag
if tag == "literal" then
return luaTypeOf ( t . base )
end
local primitive = PRIMITIVE_LUA_TYPE [ tag ]
if primitive then
return primitive
end
if tag == "nominal" then
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






local function truthinessOf ( t ) 
if type ( t ) ~= "table" then
return nil
end
local tag = t . tag
if tag == "nil" then
return false
elseif tag == "literal" then
if t . constant == false then
return false
end
if t . constant == true then
return true
end
return truthinessOf ( t . base )
elseif tag == "boolean" or tag == "any" or tag == "unknown" or tag == "union" or tag == "typevar" then
return nil
elseif luaTypeOf ( t ) ~= nil or tag == "affine" or tag == "borrowed" or tag == "pinned" or tag == "const" then
return true
end

return nil
end




local function compare ( cmp , left , right ) 
if cmp == "==" then
return left == right
elseif cmp == "~=" then
return left ~= right
end
local kind = type ( left )
if kind ~= type ( right ) or kind ~= "number" and kind ~= "string" then
return nil
end
if cmp == "<" then
return left < right
elseif cmp == "<=" then
return left <= right
elseif cmp == ">" then
return left > right
elseif cmp == ">=" then
return left >= right
end

return nil
end











function predicate . satisfiedByValue ( node , value ) 
if not node then
return nil
end
local op = node . op

if op == "const" then
return node . value
elseif op == "not" then
local inner = predicate . satisfiedByValue ( node . a , value )
if inner == nil then
return nil
end
return not inner
elseif op == "and" or op == "or" then
local left = predicate . satisfiedByValue ( node . a , value )
local right = predicate . satisfiedByValue ( node . b , value )
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

local at = value
for _ , segment in ipairs ( node . path or { } ) do
if type ( at ) ~= "table" then
return nil
end
at = ( at ) [ segment ]
end

if op == "len" then
if type ( at ) ~= "string" then
return nil
end
return predicate . satisfiedByValue ( node . a , # ( at ) )
elseif op == "integral" then
if type ( at ) ~= "number" then
return false
end
return ( at ) % 1 == 0
elseif op == "typeis" then
return type ( at ) == node . luaType
elseif op == "truthy" then
return at ~= nil and at ~= false
elseif op == "cmp" then
return compare ( node . cmp , at , node . constant )
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

if op == "len" then


if type ( t ) ~= "table" or t . tag ~= "literal" or type ( t . constant ) ~= "string" then
return nil
end
return predicate . satisfiedByValue ( node . a , # ( t . constant ) )
end

if op == "typeis" then
local answer = luaTypeOf ( t )
if answer == nil then
return nil
end
return answer == node . luaType
elseif op == "truthy" then
return truthinessOf ( t )
elseif op == "cmp" and ( node . cmp == "==" or node . cmp == "~=" ) then


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
if node . op == "and" then
if left == false or right == false then
return false
end
if left == true and right == true then
return true
end
return nil
else
if left == true or right == true then
return true
end
if left == false and right == false then
return false
end

return nil
end
end

return nil
end













function predicate . key ( node ) 
if not node then
return "#any"
end
local op = node . op

if op == "const" then
return node . value and "#t" or "#f"
elseif op == "not" then
return "(not " .. predicate . key ( node . a ) .. ")"
elseif op == "and" or op == "or" then
local parts = { }
predicate . flatten ( node , op , parts )
local keys = { }
for j , part in ipairs ( parts ) do
keys [ j ] = predicate . key ( part )
end
table . sort ( keys )


local unique , seen = { } , { }
for _ , one in ipairs ( keys ) do
if not seen [ one ] then
seen [ one ] = true
unique [ # unique + 1 ] = one
end
end
if # unique == 1 then
return unique [ 1 ]
end
return "(" .. op .. " " .. table . concat ( unique , " " ) .. ")"
end

local path = "." .. table . concat ( node . path or { } , "." )
if op == "cmp" then
return ("(cmp %s %s %s)") : format ( node . cmp or "==" , path , node . literal or "nil" )
elseif op == "typeis" then
return ("(typeis %s %s)") : format ( path , node . luaType or "nil" )
elseif op == "len" then
return ("(len %s %s)") : format ( path , predicate . key ( node . a ) )
elseif op == "integral" then
return ("(integral %s)") : format ( path )
end

return ("(truthy %s)") : format ( path )
end



function predicate . flatten ( node , op , out ) 
if not node then
return out
end
if node . op == op then
predicate . flatten ( node . a , op , out )
predicate . flatten ( node . b , op , out )
return out
end
out [ # out + 1 ] = node

return out
end






function predicate . normalize ( node ) 
if not node then
return nil
end
local op = node . op
if op == "not" then
return ( _G.setmetatable({ op =  "not" ,  a =  predicate . normalize ( node . a ) }, predicate.Node) )
elseif op == "len" then
return ( _G.setmetatable({ op =  "len" ,  path =  node . path ,  a =  predicate . normalize ( node . a ) }, predicate.Node) )
elseif op ~= "and" and op ~= "or" then
return node
end

local parts = { }
predicate . flatten ( node , op , parts )
local keyed



= { }
for _ , part in ipairs ( parts ) do
local one = predicate . normalize ( part )
if one then





local bare = # ( one . path or { } ) == 0
local rank = bare and one . op == "typeis" and 0 or bare and one . op == "integral" and 1 or 2
keyed [ # keyed + 1 ] = { key = predicate . key ( one ) , rank = rank , node = one }
end
end
table . sort ( keyed , function ( a , b ) 
if a . rank ~= b . rank then
return a . rank < b . rank
end
return a . key < b . key
end )
local out , seen = nil , { }
for j = # keyed , 1 , -1 do
local entry = keyed [ j ]
if not seen [ entry . key ] then
seen [ entry . key ] = true
if out then
out = _G.setmetatable({ op =  op ,  a =  entry . node ,  b =  out }, predicate.Node)
else
out = entry . node
end
end
end

return out
end











predicate.Decomposition = {} predicate.Decomposition.__index = predicate.Decomposition ;_G.nupp.__reflect.link(predicate.Decomposition,__nuppT1[2],{ })










local function narrowBound (
into ,
low ,
high ,
cmp ,
value
) 
local fields = into


if cmp ~= ">=" and cmp ~= "<=" and cmp ~= "==" then
return false
end
if cmp == ">=" or cmp == "==" then
local currentLow = fields [ low ]
if not currentLow or value > currentLow then
fields [ low ] = value
end
end
if cmp == "<=" or cmp == "==" then
local currentHigh = fields [ high ]
if not currentHigh or value < currentHigh then
fields [ high ] = value
end
end

return true
end





function predicate . decompose ( node ) 
if not node then
return nil
end
local parts = { }
predicate . flatten ( node , "and" , parts )
local out = _G.setmetatable({ others =  { } }, predicate.Decomposition)
for _ , part in ipairs ( parts ) do
local op = part . op
local taken = false
if op == "cmp" and # ( part . path or { } ) == 0 and type ( part . constant ) == "number" then
taken = narrowBound ( out , "min" , "max" , part . cmp , part . constant )
elseif op == "len" and # ( part . path or { } ) == 0 then
local inner = part . a
if inner and inner . op == "cmp" and # ( inner . path or { } ) == 0 and type ( inner . constant ) == "number" then
taken = narrowBound ( out , "minLength" , "maxLength" , inner . cmp , inner . constant )
end
elseif op == "and" or op == "or" then


return nil
end


if not taken then
out . others [ predicate . key ( part ) ] = true
end
end

return out
end








function predicate . implies ( a , b ) 
if predicate . key ( a ) == predicate . key ( b ) then
return true
end
local wide = predicate . decompose ( b )
if not wide then
return false
end
local narrow = predicate . decompose ( a )
if not narrow then
return false
end
if wide . min and ( not narrow . min or narrow . min < wide . min ) then
return false
end
if wide . max and ( not narrow . max or narrow . max > wide . max ) then
return false
end
if wide . minLength and ( not narrow . minLength or narrow . minLength < wide . minLength ) then
return false
end
if wide . maxLength and ( not narrow . maxLength or narrow . maxLength > wide . maxLength ) then
return false
end
for key in pairs ( wide . others ) do
if not narrow . others [ key ] then
return false
end
end

return true
end



function predicate . disjoint ( a , b ) 
local left , right = predicate . decompose ( a ) , predicate . decompose ( b )
if not left or not right then
return false
end
if left . min and right . max and left . min > right . max then
return true
end
if right . min and left . max and right . min > left . max then
return true
end
if left . minLength and right . maxLength and left . minLength > right . maxLength then
return true
end
if right . minLength and left . maxLength and right . minLength > left . maxLength then
return true
end

return false
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
if op == "len" then






local target = subject
for j , segment in ipairs ( node . path or { } ) do
target = target .. ( j > 1 and "?." or "." ) .. segment
end
local inner = node . a
local comparison = inner
and inner . op == "cmp"
and ("#%s %s %s") : format ( target , inner . cmp or "==" , inner . literal or "nil" )
or predicate . render ( inner , "#" .. target )
return ("(type(%s) == \"string\" and %s)") : format ( target , comparison )
end





local access = subject
for j , segment in ipairs ( node . path or { } ) do
access = access .. ( j > 1 and "?." or "." ) .. segment
end

if op == "cmp" then
local comparison = access .. " " .. ( node . cmp or "==" ) .. " " .. ( node . literal or "nil" )
if node . cmp ~= "==" and node . cmp ~= "~=" then
return ("(type(%s) == %q and %s)") : format ( access , type ( node . constant ) , comparison )
end
return comparison
elseif op == "integral" then




return ("%s %% 1 == 0") : format ( access )
elseif op == "typeis" then
return ("type(%s) == %q") : format ( access , node . luaType or "nil" )
end



return access
end






function predicate . guardsType ( node ) 
if not node then
return false
end
if node . op == "typeis" and # ( node . path or { } ) == 0 then
return true
end
if node . op ~= "and" then
return false
end

return predicate . guardsType ( node . a ) or predicate . guardsType ( node . b )
end






function predicate . test ( node , subject ) 
local body = predicate . render ( node , subject )
if predicate . constant ( node ) ~= nil or predicate . guardsType ( node ) then
return body
end

return ("(type(%s) == \"table\" and %s)") : format ( subject , body )
end

local __nuppExportValue= predicate ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types.predicate"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types.predicate"]=__nuppExports;return __nuppExports