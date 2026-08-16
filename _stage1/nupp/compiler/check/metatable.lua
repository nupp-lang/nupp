_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
















local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local cst = require ( "nupp.compiler.cst" )
local operators = require ( "nupp.compiler.check.operators" )
local state = require ( "nupp.compiler.check.state" )

local isA = relations . isA
local rawType = T . unwrapOwnership

local metatable = { }





















function metatable . install ( c )
local ops = { }



local function receiverOf ( t )
if not t then
return nil
end
local bare = rawType ( t )
if bare . tag == "metatable" then
return bare . of
end
if bare . tag == "union" or bare . tag == "intersection" then
for _ , member in ipairs ( bare . members ) do
local of = receiverOf ( member )
if of then
return of
end
end
end

return nil
end




local function fieldOf ( literalType , name )
local bare = literalType and rawType ( literalType ) or nil
if bare and bare . tag == "shape" then
return bare . byname [ name ]
end

return nil
end



local function callable ( t )
local bare = rawType ( t )
if t == T . any or bare . tag == "func" then
return true
end
if bare . tag == "intersection" then
for _ , member in ipairs ( bare . members ) do
if rawType ( member ) . tag ~= "func" then
return false
end
end
return # bare . members > 0
end

return false
end

function ops . checkContract ( at , name , valueT , contract , of )
local ok , why = isA ( valueT , contract )
if ok then
return
end
c . diag (
"NUPP2123" ,
at ,
(
"%s does not fulfil the contract %s declares: %s"
) : format ( name , of and T . tostring ( of ) or "the receiver" , why ) ,
nil ,
{ help = ( "the contract is %s" ) : format ( T . tostring ( contract ) ) }
)
end






local function checkIndexTable ( value , valueT , of )
for _ , field in ipairs ( value . fields or { } ) do
if field . kind == "fieldNamed" and field . name then
local name = field . name . text
local declared = c . fieldType ( of , name )
local written = fieldOf ( valueT , name )
if declared and written then
local ok , why = isA ( written , declared )
if not ok then
c . diag ( "NUPP2123" , field . value or field , ( "__index %s: %s" ) : format ( name , why ) , nil , {
help = ( "%s declares it as %s" ) : format ( T . tostring ( of ) , T . tostring ( declared ) )
} )
end
end
end
end
end

local function checkField ( field , of , literalType )
local key = field . name
if not key then
return
end
local name = key . text
if name : sub ( 1 , 2 ) ~= "__" then
return
end
local value = field . value
local at = value or field
local contract = c . metamethodOf ( of , name )
local valueT = fieldOf ( literalType , name )
if contract then
if valueT then
ops . checkContract ( at , name , valueT , contract , of )
end
return
end
if not operators . runtimeMetamethod [ name ] then
c . diag (
"NUPP2118" ,
key ,
( "unknown metatable key %q" ) : format ( name ) ,
c . edits . spellingFix ( key , operators . runtimeMetamethod )
)
return
end
if not valueT then
return
end
if name == "__metatable" then

elseif name == "__mode" then
if not isA ( valueT , T . string ) then
c . diag ( "NUPP2123" , at , ( "__mode is read as a string, not %s" ) : format ( T . tostring ( valueT ) ) )
end
elseif name == "__index" or name == "__newindex" then
if not callable ( valueT ) and not isA ( valueT , T . table_ ) then
c . diag (
"NUPP2123" ,
at ,
( "%s is a table to defer to or a function to run, not %s" ) : format ( name , T . tostring ( valueT ) )
)
elseif name == "__index" and value and value . kind == "tableExpr" then
checkIndexTable ( value , valueT , of )
end
elseif not callable ( valueT ) then
c . diag (
"NUPP2123" ,
at ,
( "%s is called, so it holds a function, " .. "not %s" ) : format ( name , T . tostring ( valueT ) )
)
end
end






function ops . checkLiteral ( node , literalType , target )
if not node or node . kind ~= "tableExpr" then
return
end
local of = receiverOf ( target )
if not of then
return
end
for _ , field in ipairs ( node . fields or { } ) do
if field . kind == "fieldNamed" then
checkField ( field , of , literalType )
end
end
end

c . checkMetatableLiteral = ops . checkLiteral
c . checkMetamethodValue = ops . checkContract

return ops
end

return metatable
