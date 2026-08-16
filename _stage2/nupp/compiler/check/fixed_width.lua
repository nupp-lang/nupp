_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local fixed = require ( "nupp.compiler.fixed_width" )
local state = require ( "nupp.compiler.check.state" )

local fixedCheck = { }

local isA = relations . isA














local function copyFacts ( facts )
if not facts then
return nil
end
local out = { }
for name , value in pairs ( facts ) do
out [ name ] = value
end

return out
end

function fixedCheck . install ( c )
local ops = { }

ops . markLiteral = function ( node , value )
local facts = { }
for _ , target in ipairs ( { T . float , T . int32 , T . uint32 } ) do
if fixed . literalFits ( value , target ) then
facts [ target . tag ] = true
end
end
node . fixedWidthEstablished = next ( facts ) and facts or nil
end

ops . mark = function ( node , t )
if node and fixed . isValue ( t ) then
node . fixedWidthEstablished = { [ T . unwrapOwnership ( t ) . tag ] = true }
end
end

ops . trust = function ( node , t )
if node and fixed . requiresTrust ( t ) then
node . fixedWidthTrusted = true
end
end

ops . copy = function ( target , source )
if target then
target . fixedWidthEstablished = source and copyFacts ( source . fixedWidthEstablished ) or nil
target . fixedWidthTrusted = source and source . fixedWidthTrusted == true or nil
target . fixedWidthCallableUntrusted = source and source . fixedWidthCallableUntrusted == true or nil
end
end

ops . intersect = function ( target , left , right )
local facts = { }
for name in pairs ( left and left . fixedWidthEstablished or { } ) do
if right and right . fixedWidthEstablished and right . fixedWidthEstablished [ name ] then
facts [ name ] = true
end
end
target . fixedWidthEstablished = next ( facts ) and facts or nil
target . fixedWidthTrusted = left
and left . fixedWidthTrusted == true
and right
and right . fixedWidthTrusted == true
or nil
end

local function sourceFacts ( source , resultIndex )
local index = resultIndex or source and source . fixedWidthResultIndex or 1
local byResult = source and source . fixedWidthResultEstablished
if byResult then
return byResult [ index ]
end

return source and source . fixedWidthEstablished or nil
end

local function sourceTrusted ( source , resultIndex )
local index = resultIndex or source and source . fixedWidthResultIndex or 1
local byResult = source and source . fixedWidthResultTrusted
if byResult then
return byResult [ index ] == true
end

return source and source . fixedWidthTrusted == true or false
end

ops . setBinding = function ( entry , source , resultIndex )
if entry then
entry . fixedWidthEstablished = copyFacts ( sourceFacts ( source , resultIndex ) )
entry . fixedWidthTrusted = fixed . requiresTrust ( entry . t ) and sourceTrusted ( source , resultIndex ) or nil
entry . fixedWidthCallableUntrusted = source and source . fixedWidthCallableUntrusted == true or nil
end
end

ops . copyBinding = function ( node , entry )
if node then
node . fixedWidthEstablished = entry and copyFacts ( entry . fixedWidthEstablished ) or nil
node . fixedWidthTrusted = entry and entry . fixedWidthTrusted == true or nil
node . fixedWidthCallableUntrusted = entry and entry . fixedWidthCallableUntrusted == true or nil
end
end

ops . established = function ( node , target )
if not fixed . isValue ( target ) then
return true
end
local tag = T . unwrapOwnership ( target ) . tag

local facts = sourceFacts ( node )

return facts ~= nil and facts [ tag ] == true
end

local function conversionFor ( source , target )
local tag = T . unwrapOwnership ( target ) . tag
if tag == "float" then
return fixed . conversionPath ( target )
elseif tag == "int32" or tag == "uint32" then
local raw = T . unwrapOwnership ( source )
if raw == T . any or isA ( raw , T . integer ) then
return fixed . conversionPath ( target )
end

return nil
else
return nil
end
end

local function fixes ( node , source , target , conversion )
local out = conversion and c . edits . refinementFix ( node , target ) or { }
local typeNode = node and node . fixedWidthTargetTypeNode or nil
local widened = fixed . widenedName ( target )
if widened == "integer" and not isA ( source , T . integer ) then
widened = "number"
end
local typeFix = typeNode and widened and c . edits . typeFix ( typeNode , widened ) or nil
if typeFix then
out [ # out + 1 ] = typeFix
end

return out
end

ops . fits = function ( source , target , node , physical )
if physical then
local accepted = fixed . physicalStoreAccepts ( source , target )
if accepted ~= nil then
return accepted , accepted and nil or (
"%s is not numeric storage for %s"
) : format ( T . tostring ( source ) , T . tostring ( target ) ) , false
end
end

local ok , why = isA ( source , target )
if ok and fixed . requiresTrust ( target ) and not sourceTrusted ( node ) then
c . diag (
"NUPP2011" ,
node ,
( "%s has unestablished fixed-width record fields" ) : format ( T . tostring ( source ) ) ,
nil ,
{
help = "use a checked construction, parameter, or function result without erasing it through any or as"
}
)
return false , nil , true
end
if not fixed . isValue ( target ) then
return ok , why , false
end
if ok and ops . established ( node , target ) and not ( node and node . fixedWidthUntrusted == true ) then
return true , nil , false
end

local raw = T . unwrapOwnership ( source )
local numeric = raw == T . any or isA ( raw , T . number )
if ok or numeric then
local conversion = conversionFor ( source , target )
c . diag (
"NUPP2011" ,
node ,
( "%s is not established as %s" ) : format ( T . tostring ( source ) , T . tostring ( target ) ) ,
fixes ( node , source , target , conversion ) ,
{
help = conversion and (
"use %s, a reified load, an exact literal, or an established result"
) : format ( conversion ) or "first produce an integer, or widen the destination type"
}
)
return false , nil , true
end

return false , why , false
end

ops . storageOnly = function ( node , t , context )
local found = fixed . storageOnlyValue ( t )
if not found then
return
end
local raw = T . unwrapOwnership ( found )
local replacement = raw . tag : sub ( 1 , 1 ) == "u" and "uint32" or "int32"
local edit = fixed . isStorageOnly ( t ) and c . edits . typeFix ( node , replacement ) or nil
c . diag (
"NUPP2012" ,
node ,
( "%s describes physical storage and cannot be used as %s" ) : format ( T . tostring ( raw ) , context ) ,
edit and { edit } or nil ,
{
help = (
"use %s for values; keep %s on a struct, C array, pointer, cdef, or span element"
) : format ( replacement , raw . tag )
}
)
end

return ops
end

return fixedCheck
