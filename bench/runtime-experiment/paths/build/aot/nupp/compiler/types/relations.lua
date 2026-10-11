_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local T = require ( "nupp.compiler.types" )
local members = require ( "nupp.compiler.types.members" )
local fixedWidth = require ( "nupp.compiler.types.fixedwidth" )

local relations = { }
local rigidBinders = setmetatable ( { } , { __mode = "k" } )











local function admitsNil ( t ) 
if t == T . nil_ or t == T . any or t == T . unknown then
return true
end
return t . tag == "union" and t . hasNil or false
end






local WIDENS = { }

local function widen ( from , toList ) 
local into = WIDENS [ from ] or { }
WIDENS [ from ] = into
for _ , to in ipairs ( toList ) do
into [ to ] = true
end
end

widen ( "integer" , { "number" } )
widen ( "float" , { "number" } )
for _ , t in ipairs ( { "int8" , "int16" , "int32" , "uint8" , "uint16" , "uint32" } ) do
widen ( t , { "integer" , "number" } )
end





local BOXED = { int64 = true , uint64 = true }

local CDATA_NUM

= {
float = true ,
int8 = true ,
int16 = true ,
int32 = true ,
int64 = true ,
uint8 = true ,
uint16 = true ,
uint32 = true ,
uint64 = true ,
}

local function runtimeCategory ( t ) 
local tag = t . tag
if tag == "literal" or tag == "constrained" then
return runtimeCategory ( t . base )
end
if tag == "nil" or tag == "boolean" or tag == "string" then
return tag
end
if tag == "number" or tag == "integer" or CDATA_NUM [ tag ] then
return "number"
end
if tag == "array"
or tag == "map"
or tag == "tuple"
or tag == "shape"
or tag == "table"
or tag == "metatable"
or tag == "typeobject"
then
return "table"
end
if tag == "func" then
return "function"
end
if tag == "thread" or tag == "protocolThread" then
return "thread"
end
if tag == "userdata" then
return "userdata"
end
if tag == "ptr" or tag == "carray" or tag == "cstring" or tag == "voidptr" or tag == "ctype" or tag == "cdata" then
return "cdata"
end

return nil
end

local disjoint



disjoint = function ( a , b ) 
if a == T . never or b == T . never then
return "one member is never"
end
if a == T . any or b == T . any or a == T . unknown or b == T . unknown or a . tag == "typevar" or b . tag == "typevar" then
return nil
end
if a == b then
return nil
end
if a . tag == "intersection" then
for _ , member in ipairs ( a . members ) do
local why = disjoint ( member , b )
if why then
return why
end
end
return nil
end
if b . tag == "intersection" then
return disjoint ( b , a )
end
if a . tag == "union" then
local witness = nil
for _ , member in ipairs ( a . members ) do
local why = disjoint ( member , b )
if not why then
return nil
end
witness = witness or why
end
return witness
end
if b . tag == "union" then
return disjoint ( b , a )
end
if a . tag == "constrained" or b . tag == "constrained" then
local predicate = require ( "nupp.compiler.types.predicate" )
if a . tag == "constrained"
and b . tag == "constrained"
and predicate . disjoint ( ( a ) . predicate , ( b ) . predicate )
then
return "constraints that admit nothing in common"
end
return disjoint ( T . unconstrained ( a ) , T . unconstrained ( b ) )
end
if a . tag == "literal" and b . tag == "literal" then
if a . base == b . base and a . constant ~= b . constant then
return "distinct literal values"
end
return disjoint ( a . base , b . base )
end
if a . tag == "literal" then
local ac , bc = runtimeCategory ( a ) , runtimeCategory ( b )
if ac and bc and ac ~= bc then
return "different runtime categories"
end
return nil
end
if b . tag == "literal" then
return disjoint ( b , a )
end
if a . tag == "nominal"
and b . tag == "nominal"
and a ~= b
and a . id ~= b . id
and a . declKind ~= "interface"
and b . declKind ~= "interface"
then
return "distinct concrete nominal types"
end
local ac , bc = runtimeCategory ( a ) , runtimeCategory ( b )
if ac and bc and ac ~= bc then
return "different runtime categories"
end
local ar = ( a . tag == "shape" or a . tag == "nominal" ) and a . byname or nil
local br = ( b . tag == "shape" or b . tag == "nominal" ) and b . byname or nil
if ar and br then
for name , at in pairs ( ar ) do
local bt = br [ name ]
if bt and not admitsNil ( at ) and not admitsNil ( bt ) then
local why = disjoint ( at , bt )
if why then
return ("required field %q has incompatible types") : format ( name )
end
end
end
end

return nil
end

relations . disjoint = disjoint



local cache = setmetatable ( { } , { __mode = "k" } )












local generation = 0
local cachedAt = 0

local isA




local assuming = setmetatable ( { } , { __mode = "k" } )
local assumptionDepth = 0
local usedAssumption = false








local function sameSealedDeclaration ( a , b ) 
return a == b
or (
a . tag == "nominal"
and b . tag == "nominal"
and a . sealedModule ~= nil
and a . sealedModule == b . sealedModule
and a . moduleName == b . moduleName
and a . name == b . name
and # ( a . typeArgs or { } ) == 0
and # ( b . typeArgs or { } ) == 0
and # ( a . constArgs or { } ) == 0
and # ( b . constArgs or { } ) == 0
)
end




local function declaresContract ( a , b , seen ) 
if ( a == b or ( a . tag == "nominal" and b . tag == "nominal" and a . sealedModule ~= nil and a . sealedModule == b . sealedModule and a . moduleName == b . moduleName and a . name == b . name and # ( a . typeArgs or { } ) == 0 and # ( b . typeArgs or { } ) == 0 and # ( a . constArgs or { } ) == 0 and # ( b . constArgs or { } ) == 0 ) ) then
return true
end
if a . tag ~= "nominal" then
return false
end
seen = seen or { }
if seen [ a ] then
return false
end
seen [ a ] = true
for _ , parent in ipairs ( ( a ) . supertypes or { } ) do
if ( parent == b or ( parent . tag == "nominal" and b . tag == "nominal" and parent . sealedModule ~= nil and parent . sealedModule == b . sealedModule and parent . moduleName == b . moduleName and parent . name == b . name and # ( parent . typeArgs or { } ) == 0 and # ( b . typeArgs or { } ) == 0 and # ( parent . constArgs or { } ) == 0 and # ( b . constArgs or { } ) == 0 ) ) or declaresContract ( parent , b , seen ) then
return true
end
end



local origin = ( a ) . origin
if origin then
for _ , parent in ipairs ( origin . supertypes or { } ) do
if ( parent == b or ( parent . tag == "nominal" and b . tag == "nominal" and parent . sealedModule ~= nil and parent . sealedModule == b . sealedModule and parent . moduleName == b . moduleName and parent . name == b . name and # ( parent . typeArgs or { } ) == 0 and # ( b . typeArgs or { } ) == 0 and # ( parent . constArgs or { } ) == 0 and # ( b . constArgs or { } ) == 0 ) ) or declaresContract ( parent , b , seen ) then
return true
end
end
end

return false
end


local function hasAffineClaim ( t , seen ) 
if t . tag ~= "nominal" then
return false
end
local nominal = t
if ( ( nominal . origin or nominal ) ) . intrinsicAffine then
return true
end
seen = seen or { }
if seen [ nominal ] then
return false
end
seen [ nominal ] = true
for _ , parent in ipairs ( nominal . supertypes or { } ) do
if hasAffineClaim ( parent , seen ) then
return true
end
end

return false
end

local function affineTermCleanupId ( term ) 
if not term then
return nil
end
if term . tag == "constLiteral" and term . domain == "function" then
local key = term . value
local method = key : match ( "^self%.([%a_][%w_]*)$" )
return method and "method:" .. method or "function:" .. key
end

return "functionconst:" .. term . id
end











local function associatedAnswersFit ( a , b ) 
local associated = require ( "nupp.compiler.types.associated" )
local owed = associated . requirementNames ( b )
if # owed == 0 then
return true , nil
end
if a . tag ~= "nominal" then
return false , ("%s is not a %s (it declares associated types, which a structural value cannot answer)")

: format ( T . tostring ( a ) , T . tostring ( b ) )
end
if ( a ) . declKind == "interface" then


if associated . declares ( a , b ) then
return true , nil
end

return false , ("%s is not a %s (it does not declare that contract, and an interface answers nothing itself)")

: format ( T . tostring ( a ) , T . tostring ( b ) )
end
for _ , name in ipairs ( owed ) do
local found = associated . lookup ( a , name )
if not found . gradual then
if not found . resolved then
return false , ("%s is not a %s (%s is %s)")

: format ( T . tostring ( a ) , T . tostring ( b ) , name , found . reason or "unanswered" )
end
if found . bound and not isA ( found . resolved , found . bound ) then
return false , ("%s is not a %s (%s = %s does not fit %s)")

: format ( T . tostring ( a ) , T . tostring ( b ) , name , T . tostring ( found . resolved ) , T . tostring ( found . bound ) )
end
end
end

return true , nil
end






local function fail ( a , b ) 
return false , ("%s is not a %s") : format ( T . tostring ( a ) , T . tostring ( b ) )
end



local surfaceOwner = setmetatable ( { } , { __mode = "k" } )





function relations . hasReceiver ( ft , owner ) 
if # ft . params < 1 then
return false
end
if ft . paramNames and ft . paramNames [ 1 ] == "self" then
return true
end
if not owner then
return false
end
local first = T . unwrapOwnership ( ft . params [ 1 ] )
if first . tag == "const" then
first = first . inner
end
if first == owner or first . id == owner . id then
return true
end
if owner . tag == "nominal" then
local selfType = owner . selfType
if selfType and ( first == selfType or first . id == selfType . id ) then
return true
end
return owner . origin ~= nil and first . tag == "nominal" and first . origin == owner . origin
elseif owner . tag == "intersection" then
for _ , member in ipairs ( owner . members ) do
if first == member or first . id == member . id then
return true
end
end
end

return false
end



function relations . isMethod ( value , owner ) 
if value . tag == "func" then
return relations . hasReceiver ( value , owner )
elseif value . tag ~= "intersection" or # value . members == 0 then
return false
end
for _ , member in ipairs ( value . members ) do
if member . tag ~= "func" or not relations . hasReceiver ( member , owner ) then
return false
end
end

return true
end




local function borrowRelation ( ft ) 
local sources = { }
if ft . borrowsParam then
sources [ # sources + 1 ] = ft . borrowsParam
end
for _ , param in ipairs ( ft . borrowsParams or { } ) do
sources [ # sources + 1 ] = param
end
local implicitSelf = ft . borrowsSelf
if implicitSelf and ft . paramNames and ft . paramNames [ 1 ] == "self" then
sources [ # sources + 1 ] = 1
implicitSelf = false
end
if # sources == 0 and not implicitSelf then
return ""
end
table . sort ( sources )

return table . concat ( sources , "," ) .. ( implicitSelf and "|self" or "" ) .. "|into" .. ( ft . borrowsResult or 1 )
end









local function memberIsA ( have , want , haveOwner , wantOwner ) 
if have . tag == "func"
and want . tag == "func"
and relations . hasReceiver ( have , haveOwner )
and relations . hasReceiver ( want , wantOwner )
then
local haveReceiverMode = have . paramModes and have . paramModes [ 1 ] or "plain"
local wantReceiverMode = want . paramModes and want . paramModes [ 1 ] or "plain"
if ( haveReceiverMode == "takes" ) ~= ( wantReceiverMode == "takes" ) then
return false
end
for result = 1 , math . max ( # have . rets , # want . rets ) do
local haveSource = have . preservesResults and have . preservesResults [ result ]
local wantSource = want . preservesResults and want . preservesResults [ result ]
if ( haveSource == 1 ) ~= ( wantSource == 1 ) then
return false
end
end
if borrowRelation ( have ) ~= borrowRelation ( want ) then
return false
end
local hp , wp = { } , { }
for j = 2 , # have . params do
hp [ # hp + 1 ] = have . params [ j ]
end
for j = 2 , # want . params do
wp [ # wp + 1 ] = want . params [ j ]
end
local hm , wm = { } , { }
local hn , wn = { } , { }
for j = 2 , # have . params do
hm [ # hm + 1 ] = have . paramModes and have . paramModes [ j ] or "plain"
end
for j = 2 , # want . params do
wm [ # wm + 1 ] = want . paramModes and want . paramModes [ j ] or "plain"
end
for j = 2 , # have . params do
hn [ # hn + 1 ] = have . paramNames and have . paramNames [ j ] or ""
end
for j = 2 , # want . params do
wn [ # wn + 1 ] = want . paramNames and want . paramNames [ j ] or ""
end

local function shiftedPreserves ( ft ) 
local shifted = { }
for result = 1 , # ft . rets do
local source = ft . preservesResults and ft . preservesResults [ result ]
if source and source > 1 then
shifted [ result ] = source - 1
end
end

return next ( shifted ) and shifted or nil
end



local function withoutReceiver ( ft , params , modes , names ) 
return T . funcWith ( ft , {
params = params ,
paramModes = modes ,
predicate = false ,
borrowsParam = false ,
borrowsSelf = false ,
borrowsParams = false ,
borrowsResult = false ,
ffiOut = false ,
noreturn = false ,
paramPack = T . pack ( params , ft . paramPack . tail , modes ) ,
paramNames = names ,
preservesResults = shiftedPreserves ( ft ) or false ,
foreign = false ,
partitionResults = false ,
comptimeOnly = false ,
explicitPreserves = false ,
} )
end

return ( isA ( withoutReceiver ( have , hp , hm , hn ) , withoutReceiver ( want , wp , wm , wn ) ) )
end

return ( isA ( have , want ) )
end



local function tupleReadsAs ( elems , b ) 
if b . tag == "tuple" then
if # elems ~= # b . elems then
return false , ("%d positions are not a %s") : format ( # elems , T . tostring ( b ) )
end
for j , e in ipairs ( elems ) do
if not isA ( e , b . elems [ j ] ) then
return false , ("position %d: %s is not a %s") : format ( j , T . tostring ( e ) , T . tostring ( b . elems [ j ] ) )
end
end
return true
end
local elem = ( b ) . elem
for j , e in ipairs ( elems ) do
if not isA ( e , elem ) then
return false , ("position %d: %s is not a %s") : format ( j , T . tostring ( e ) , T . tostring ( elem ) )
end
end

return true
end

local function optionalIsA ( a , b ) 
if not a or not b then
return false
end
return ( isA ( a , b ) )
end

local function affine ( t ) 
if not t then
return false
end
if t . tag == "affine" or t . tag == "pinned" then
return true
end
if t . tag == "union" or t . tag == "intersection" then
for _ , member in ipairs ( t . members ) do
if affine ( member ) then
return true
end
end
end

return false
end


function relations . packIsA ( have , want ) 
if have == want then
return true
end
if ( have . tail and have . tail . kind == "computed" ) or ( want . tail and want . tail . kind == "computed" ) then
local generic = require ( "nupp.compiler.types.generics" )
local expandedHave , haveError = generic . expandComputedPack ( have )
local expandedWant , wantError = generic . expandComputedPack ( want )
if haveError or wantError then
return false , haveError or wantError
end
if expandedHave ~= have or expandedWant ~= want then
return relations . packIsA ( expandedHave , expandedWant )
end
end
if have . alternatives then
for _ , arm in ipairs ( have . alternatives ) do
local ok , why = relations . packIsA ( arm , want )
if not ok then
return false , why
end
end
return true
end
if want . alternatives then
for _ , arm in ipairs ( want . alternatives ) do
if relations . packIsA ( have , arm ) then
return true
end
end
return false , ("pack %s fits no alternative of %s") : format ( T . tostringPack ( have ) , T . tostringPack ( want ) )
end
for j , expected in ipairs ( want . head ) do


local actual = T . packAt ( have , j ) or T . nil_
if not have . head [ j ] and have . tail and have . tail . kind == "homogeneous" then
actual = T . optional ( actual )
end
if affine ( actual ) and not affine ( expected ) then
return false , ("pack slot %d would erase an ownership obligation") : format ( j )
end
if not isA ( actual , expected ) then
return false , ("pack slot %d: %s is not a %s") : format ( j , T . tostring ( actual ) , T . tostring ( expected ) )
end
end
if want . tail and want . tail . kind == "homogeneous" then
for j = # want . head + 1 , # have . head do
if affine ( have . head [ j ] ) and not affine ( want . tail . type ) then
return false , ("pack tail slot %d would erase an ownership obligation") : format ( j )
end
if not isA ( have . head [ j ] , want . tail . type ) then
return false , ("pack tail slot %d is not a %s") : format ( j , T . tostring ( want . tail . type ) )
end
end
if have . tail
and have . tail . kind == "homogeneous"
and ( affine ( have . tail . type ) and not affine ( want . tail . type ) or not isA ( have . tail . type , want . tail . type ) )
then
return false , "homogeneous pack tails are incompatible"
end
elseif want . tail and want . tail . kind == "generic" then
if not have . tail or have . tail . kind ~= "generic" or have . tail . var ~= want . tail . var then
return false , "generic pack tails are incompatible"
end
elseif not want . tail then
for j = # want . head + 1 , # have . head do
if affine ( have . head [ j ] ) then
return false , "an affine extra result would be truncated"
end
end
if have . tail and ( have . tail . kind == "generic" or affine ( have . tail . type ) ) then
return false , "a potentially affine result tail would be truncated"
end
end

return true
end







local function intersectionSurface ( t ) 
local surface = members . view ( t )
local fields = { }
for _ , entry in ipairs ( surface . ordered ) do
fields [ # fields + 1 ] = { name = entry . name , read = entry . readType , write = entry . writeType }
end

local shape = T . shape ( fields , {
readKey = surface . readIndexer and surface . readIndexer . keyType or nil ,
readValue = surface . readIndexer and surface . readIndexer . valueType or nil ,
writeKey = surface . writeIndexer and surface . writeIndexer . keyType or nil ,
writeValue = surface . writeIndexer and surface . writeIndexer . valueType or nil ,
} )
surfaceOwner [ shape ] = t

return shape
end





local function mayOmit ( a , owner , fresh , want ) 
if fresh or a . tag == "shape" and a . closed then
return true
end



if want == T . optional ( T . type_ ) then
return true
end
if owner . tag == "nominal" then
local kind = ( owner ) . declKind
if kind == "record" or kind == "struct" then
return true
end
end

return a . indexReadValue ~= nil and optionalIsA ( T . string , a . indexReadKey ) and optionalIsA ( a . indexReadValue , want )
end




local function propertiesFit ( a , b ) 
local aReads = a . byname or { }
local aWrites = a . writeByname or { }
local fresh = a . tag == "shape" and a . fresh == true
local aOwner = surfaceOwner [ a ] or a
local bOwner = surfaceOwner [ b ] or b
for name , want in pairs ( b . byname or { } ) do
local have = aReads [ name ]
if not have then
if not admitsNil ( want ) then
return false , ("%s is not a %s (no readable member %q)") : format ( T . tostring ( a ) , T . tostring ( b ) , name )
elseif not mayOmit ( a , aOwner , fresh , want ) then
return false , ("%s is not a %s (no readable member %q; only a fresh table, a record or a struct may omit an optional member)")

: format ( T . tostring ( a ) , T . tostring ( b ) , name )
end
elseif not memberIsA ( have , want , aOwner , bOwner ) then
return false , ("%s is not a %s (read member %q does not match)") : format ( T . tostring ( a ) , T . tostring ( b ) , name )
end
end
for name , want in pairs ( b . writeByname or { } ) do
if not fresh then
local have = aWrites [ name ]
if not have then
return false , ("%s is not a %s (no writable member %q)") : format ( T . tostring ( a ) , T . tostring ( b ) , name )
end
if not memberIsA ( want , have , bOwner , aOwner ) then
return false , ("%s is not a %s (write member %q does not match)")

: format ( T . tostring ( a ) , T . tostring ( b ) , name )
end
end
end

return true
end





local function indexersFit ( a , b ) 
local readOk = not (
b . indexReadValue
and (
not a . indexReadValue
or not optionalIsA ( b . indexReadKey , a . indexReadKey )
or not optionalIsA ( a . indexReadValue , b . indexReadValue )
)
)
local writeOk = not (
b . indexWriteValue
and (
not a . indexWriteValue
or not optionalIsA ( b . indexWriteKey , a . indexWriteKey )
or not optionalIsA ( b . indexWriteValue , a . indexWriteValue )
)
)

return readOk , writeOk
end

local function sameCleanups ( a , b ) 
local left = a or { }
local right = b or { }
if # left ~= # right then
return false
end
for j , cleanup in ipairs ( left ) do
if cleanup . id ~= right [ j ] . id then
return false
end
end

return true
end





local function symbolicMappedView ( t ) 
if t . tag ~= "neutral" or t . op ~= "mapped" or t . remap then
return nil
end
local keys , value = t . keys , t . value
local subject = keys and keys . tag == "neutral" and keys . op == "keyof" and keys . subject or nil
if not subject
or not value
or value . tag ~= "neutral"
or value . op ~= "member"
or value . subject ~= subject
or value . key ~= t . binder
then
return nil
end
local fields = { }
if subject . tag == "nominal" then
for name in pairs ( subject . fieldDefs or { } ) do
local member = subject . byname [ name ]
fields [
# fields + 1
] = {
name = name ,
read = t . capability == "read" and member or nil ,
write = t . capability == "write" and member or nil ,
}
end
elseif subject . tag == "shape" then
for _ , field in ipairs ( subject . fields ) do
local member = field . type or field . read or field . write
fields [
# fields + 1
] = {
name = field . name ,
read = t . capability == "read" and member or nil ,
write = t . capability == "write" and member or nil ,
}
end
else
return nil
end

return T . shape ( fields )
end





local function copyable ( t , seen ) 
if t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" then
return false
end
if seen [ t ] then
return true
end
seen [ t ] = true
if t . tag == "typevar" then
return t . bound ~= nil and copyable ( t . bound , seen )
elseif t . tag == "union" or t . tag == "intersection" then
for _ , member in ipairs ( t . members ) do
if not copyable ( member , seen ) then
return false
end
end
elseif t . tag == "array" then
return copyable ( t . elem , seen )
elseif t . tag == "map" then
return copyable ( t . key , seen ) and copyable ( t . value , seen )
elseif t . tag == "tuple" then
for _ , member in ipairs ( t . elems ) do
if not copyable ( member , seen ) then
return false
end
end
elseif t . tag == "nominal" then
if t . inherentCleanup or t . affineFields and # t . affineFields > 0 or t . fieldBorrowSources then
return false
end
for _ , member in pairs ( t . byname ) do
if not copyable ( member , seen ) then
return false
end
end
for _ , member in pairs ( t . writeByname ) do
if not copyable ( member , seen ) then
return false
end
end
if t . indexReadValue and not copyable ( t . indexReadValue , seen ) then
return false
end
if t . indexWriteValue and not copyable ( t . indexWriteValue , seen ) then
return false
end
elseif t . tag == "shape" then
for _ , field in ipairs ( t . fields ) do
if field . read and not copyable ( field . read , seen ) then
return false
end
if field . write and not copyable ( field . write , seen ) then
return false
end
end
if t . indexReadValue and not copyable ( t . indexReadValue , seen ) then
return false
end
if t . indexWriteValue and not copyable ( t . indexWriteValue , seen ) then
return false
end
elseif t . tag == "neutral" then
return false
end

return true
end


function relations . isCopyable ( t ) 
return copyable ( t , { } )
end





local function check ( a , b ) 
if a == b then
return true
end
local atag , btag = a . tag , b . tag
if btag == "nominal" and T . hasCopyableBound ( b ) then
if not copyable ( a , { } ) then
return false , ("%s carries ownership or a scoped borrow and is not Copyable") : format ( T . tostring ( a ) )
end
if ( ( b . origin or b ) ) . intrinsicCopyable then
return true
end
end




if btag == "never" then
return false , ("%s is not never; no value is") : format ( T . tostring ( a ) )
end
if atag == "any" or btag == "any" then
return true
end
if atag == "neutral" or btag == "neutral" then




local generic = require ( "nupp.compiler.types.generics" )
local reducedA = atag == "neutral" and generic . normalize ( a ) . type or a
local reducedB = btag == "neutral" and generic . normalize ( b ) . type or b
if reducedA ~= a or reducedB ~= b then
return isA ( reducedA , reducedB )
end
reducedA = symbolicMappedView ( a ) or a
reducedB = symbolicMappedView ( b ) or b
if reducedA ~= a or reducedB ~= b then
return isA ( reducedA , reducedB )
end
return false , ("blocked type term %s is not identical to %s") : format ( T . tostring ( a ) , T . tostring ( b ) )
end




if atag == "never" then
return true
end
if btag == "unknown" then
return true
end


if btag == "typevar" and rigidBinders [ b ] then
if atag == "typevar" and a . bound then
return isA ( a . bound , b )
end
return fail ( a , b )
end
if atag == "typevar" then
if a . bound then
return isA ( a . bound , b )
end
return not rigidBinders [ a ]
end
if btag == "typevar" then
return true
end




if btag == "affine" and b . inner . tag == "nominal" then
local target = b . inner
if ( ( target . origin or target ) ) . intrinsicAffine then
return isA ( a , target )
end
end



if btag == "nominal" and b . declKind == "interface" and hasAffineClaim ( b ) then
local source = atag == "affine" and ( a ) . inner or atag == "borrowed" and ( a ) . inner or a
local sourceNominal = source . tag == "nominal" and source or nil
local target = b
local cleanup = atag == "affine" and ( a ) . cleanups [ 1 ] or nil
if atag ~= "affine" then
cleanup = sourceNominal and sourceNominal . inherentCleanup or nil
end
if ( ( target . origin or target ) ) . intrinsicAffine then
local wanted = affineTermCleanupId ( target . constArgs and target . constArgs [ 1 ] or nil )
if not cleanup
or not wanted
or cleanup . id ~= wanted
or not ( atag == "affine" or sourceNominal and hasAffineClaim ( sourceNominal ) )
then
return fail ( a , b )
end
return true
end
if not sourceNominal
or not hasAffineClaim ( sourceNominal )
or not cleanup
or not target . inherentCleanup
or cleanup . id ~= target . inherentCleanup . id
then
return fail ( a , b )
end
end




if atag == "affine" then
if btag == "affine" then







local takingSource = # ( a . cleanups or { } ) == 0 and not a . transferOnly
if # ( b . cleanups or { } ) > 0 and not takingSource and not sameCleanups ( a . cleanups , b . cleanups ) then
return fail ( a , b )
end
return isA ( a . inner , b . inner )

elseif btag == "borrowed" then
return isA ( a . inner , b . inner )
end
return isA ( a . inner , b )

elseif atag == "borrowed" then
if btag == "borrowed" then
return isA ( a . inner , b . inner )

elseif btag == "affine" then
return fail ( a , b )
end
return isA ( a . inner , b )

elseif atag == "pinned" then
if btag == "pinned" then
return isA ( a . inner , b . inner )
end
return fail ( a , b )
end
if btag == "affine" and a == T . nil_ then
local inner = b . inner
if inner . tag == "union" and inner . hasNil then
return true
end
end
if btag == "affine" or btag == "borrowed" or btag == "pinned" then
return fail ( a , b )
end


if atag == "union" then
for _ , m in ipairs ( a . members ) do
local ok = isA ( m , b )
if not ok then
return false , ("%s is not a %s (member %s does not fit)")

: format ( T . tostring ( a ) , T . tostring ( b ) , T . tostring ( m ) )
end
end
return true
end
if btag == "union" then
for _ , m in ipairs ( b . members ) do
if isA ( a , m ) then
return true
end
end
return fail ( a , b )




elseif btag == "intersection" then
for _ , m in ipairs ( b . members ) do
local ok , why = isA ( a , m )
if not ok then
return false , ("%s is not a %s (intersection member %s: %s)")

: format ( T . tostring ( a ) , T . tostring ( b ) , T . tostring ( m ) , why or "" )
end
end
return true
end










if atag == "constrained" or btag == "constrained" then
local predicate = require ( "nupp.compiler.types.predicate" )
if atag == "constrained" and btag == "constrained" then
local fits , why = isA ( ( a ) . base , ( b ) . base )
if not fits then
return false , why
end
if predicate . implies ( ( a ) . predicate , ( b ) . predicate ) then
return true
end
return false , ("%s is not established as %s") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
if atag == "constrained" then
return isA ( ( a ) . base , b )
end





local constraint = ( b ) . predicate
local into = ( b ) . base
if atag == "literal" and predicate . satisfiedByValue ( constraint , ( a ) . constant ) == true then




if isA ( a . base or T . string , into ) then
return true
end
if type ( ( a ) . constant ) == "number"
and fixedWidth . literalFits ( ( a ) . constant , into )
then
return true
end
end

return false , ("%s is not established as %s") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
if atag == "intersection" then
for _ , m in ipairs ( a . members ) do
if isA ( m , b ) then
return true
end
end
if btag == "shape" or ( btag == "nominal" and b . declKind == "interface" ) then
return isA ( intersectionSurface ( a ) , b )
end
return fail ( a , b )




elseif atag == "nominal" then
for _ , parent in ipairs ( a . supertypes or { } ) do
if parent == b or isA ( parent , b ) then


return associatedAnswersFit ( a , b )
end
end
end




if atag == "metatable" and btag == "shape" then
local owner = a . of
if owner and owner . tag == "nominal" then
local fields = { }
local names = { }
for name in pairs ( owner . staticByname or { } ) do
names [ name ] = true
end
for name in pairs ( owner . staticWriteByname or { } ) do
names [ name ] = true
end
for name in pairs ( names ) do
fields [
# fields + 1
] = {
name = name ,
read = owner . staticByname and owner . staticByname [ name ] or nil ,
write = owner . staticWriteByname and owner . staticWriteByname [ name ] or nil ,
}
end
return isA ( T . shape ( fields ) , b )
end
end







if atag == "literal"
and type ( a . constant ) == "number"
and ( fixedWidth . isValue ( b ) or BOXED [ btag ] )
and fixedWidth . literalFits ( a . constant , b )
then
return true
end


local widensFrom = WIDENS [ atag ]
if widensFrom and widensFrom [ btag ] then
return true
end





if CDATA_NUM [ btag ]
and not fixedWidth . isValue ( b )
and not BOXED [ btag ]
and ( atag == "number" or atag == "integer" or widensFrom )
then
return true
end





if a == T . nil_ and ( btag == "ptr" or btag == "voidptr" or btag == "cstring" ) then
return false , ("nil is not a %s; write %s? for a pointer that may be NULL")

: format ( T . tostring ( b ) , T . tostring ( b ) )
end
if btag == "ptr" and atag == "nominal" and a . declKind == "struct" and b . elem == a then
return true
end



if btag == "cstring" and a == T . string then
return true
end
if btag == "voidptr" and ( atag == "ptr" or atag == "cstring" or ( atag == "nominal" and a . declKind == "struct" ) ) then
return true
end






if atag == "nominal" and btag == "nominal" and a . origin and a . origin == b . origin then
local aConsts , bConsts = a . constArgs or { } , b . constArgs or { }
for j , value in ipairs ( aConsts ) do
if bConsts [ j ] ~= value then
return false , ("%s and %s have different const argument %d") : format ( T . tostring ( a ) , T . tostring ( b ) , j )
end
end
local origin = a . origin
local intrinsicInvariant = ( origin . moduleName == "nupp.simd" or origin . sealedModule == "nupp.simd" )
and (
origin . name == "Vector"
or origin . name == "Mask"
or origin . name == "Species"
or origin . name == "Fixed"
or origin . name == "Preferred"
)
if intrinsicInvariant then
local aArgs , bArgs = a . typeArgs or { } , b . typeArgs or { }
if # aArgs ~= # bArgs or # aConsts ~= # bConsts then
return fail ( a , b )
end
for j , have in ipairs ( aArgs ) do
local want = bArgs [ j ]
if want == nil or not isA ( have , want ) or not isA ( want , have ) then
return false , ("%s is not a %s (invariant argument %d)") : format ( T . tostring ( a ) , T . tostring ( b ) , j )
end
end
return true
end
if next ( a . byname or { } ) or next ( a . writeByname or { } ) or a . indexReadValue or a . indexWriteValue then
local ok , why = propertiesFit ( a , b )
if not ok then
return false , why
end
local readOk , writeOk = indexersFit ( a , b )
if not readOk or not writeOk then
return fail ( a , b )
end
return true
end
local aArgs = a . typeArgs or { }
local bArgs = b . typeArgs or { }
for j , at in ipairs ( aArgs ) do
local bt = bArgs [ j ]
if bt and not isA ( at , bt ) then
return false , ("%s is not a %s (argument %d)") : format ( T . tostring ( a ) , T . tostring ( b ) , j )
end
end
local aPacks , bPacks = a . packArgs or { } , b . packArgs or { }
for j , have in ipairs ( aPacks ) do
local want = bPacks [ j ]
if want then
local ok , why = relations . packIsA ( have , want )
if not ok then
return false , ("%s is not a %s (pack argument %d: %s)")

: format ( T . tostring ( a ) , T . tostring ( b ) , j , why or "incompatible pack" )
end
end
end
return true
end





if btag == "const" then
local source = atag == "const" and a . inner or a
local inner = b . inner
if source . tag == "tuple" and ( inner . tag == "tuple" or inner . tag == "array" ) then
return tupleReadsAs ( source . elems , inner )
end
if source . tag == "array" and inner . tag == "array" then
return isA ( source . elem , inner . elem )
end
return isA ( source , inner )
end
if atag == "const" then
return false , ("%s is read-only; %s is not") : format ( T . tostring ( a ) , T . tostring ( b ) )
end


if btag == "cdata" then
if atag == "ptr"
or atag == "carray"
or atag == "cstring"
or atag == "voidptr"
or atag == "ctype"
or ( atag == "nominal" and a . declKind == "struct" )
then
return true
end
end


if atag == "literal" then
if b == ( a . base or T . string ) then
return true
end
return isA ( a . base or T . string , b )
end






if atag == "projection" or btag == "projection" then




local generic = require ( "nupp.compiler.types.generics" )
local reducedA = atag == "projection" and generic . normalize ( a ) . type or a
local reducedB = btag == "projection" and generic . normalize ( b ) . type or b
if reducedA ~= a or reducedB ~= b then
return isA ( reducedA , reducedB )
end
end
if atag == "projection" then
local associated = require ( "nupp.compiler.types.associated" )
local found = associated . lookup ( ( a ) . of , ( a ) . name )
if found . bound and isA ( found . bound , b ) then
return true
end

return fail ( a , b )
end
if btag == "projection" then
return fail ( a , b )
end




if btag == "nominal" and b . declKind == "interface" and b . byname then



local bOrigin = ( b . origin or b )
local invariant = ( bOrigin . moduleName == "nupp.simd" or bOrigin . sealedModule == "nupp.simd" )
and (
bOrigin . name == "Vector"
or bOrigin . name == "Mask"
or bOrigin . name == "Species"
or bOrigin . name == "Fixed"
or bOrigin . name == "Preferred"
)
if invariant then
if atag ~= "nominal" or ( a . origin or a ) ~= bOrigin then
return fail ( a , b )
end
local aTypes , bTypes = a . typeArgs or { } , b . typeArgs or { }
local aConsts , bConsts = a . constArgs or { } , b . constArgs or { }
if # aTypes ~= # bTypes or # aConsts ~= # bConsts then
return fail ( a , b )
end
for index , wanted in ipairs ( bTypes ) do
local have = aTypes [ index ]
if not isA ( have , wanted ) or not isA ( wanted , have ) then
return fail ( a , b )
end
end
for index , wanted in ipairs ( bConsts ) do
if aConsts [ index ] . id ~= wanted . id then
return fail ( a , b )
end
end
return true
end
if b . sealedModule and not declaresContract ( a , b ) then
return false , ("%s is not a %s (the interface is sealed by module %q)")

: format ( T . tostring ( a ) , T . tostring ( b ) , b . sealedModule )
end
local answersFit , answersWhy = associatedAnswersFit ( a , b )
if not answersFit then
return false , answersWhy
end
if ( atag == "nominal" or atag == "shape" ) and a . byname then
local ok , why = propertiesFit ( a , b )
if not ok then
return false , why
end
local readOk , writeOk = indexersFit ( a , b )
if not readOk then
return false , ("%s is not a %s (read indexer does not match)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
if not writeOk then
return false , ("%s is not a %s (write indexer does not match)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
for name , want in pairs ( b . metamethods or { } ) do
local have = atag == "nominal" and a . metamethods and a . metamethods [ name ] or nil
if not have then
return false , ("%s is not a %s (metamethod %q does not match)")

: format ( T . tostring ( a ) , T . tostring ( b ) , name )
end
if not isA ( have , want ) then
return false , ("%s is not a %s (metamethod %q does not match)")

: format ( T . tostring ( a ) , T . tostring ( b ) , name )
end
end
return true
end
end

if btag == "table" then

if atag == "array"
or atag == "map"
or atag == "tuple"
or atag == "shape"
or atag == "metatable"
or atag == "typeobject"
or atag == "nominal"
then
return true
end
return fail ( a , b )
end



if atag == "table" then
if btag == "array"
or btag == "map"
or btag == "tuple"
or btag == "shape"
or btag == "metatable"
or btag == "typeobject"
or btag == "nominal"
then
return true
end
return fail ( a , b )
end

if btag == "metatable" then




if atag == "shape" or atag == "map" or atag == "table" or atag == "metatable" then
return true
end
return fail ( a , b )
elseif btag == "typeobject" then

if b . of . tag == "nominal" and b . of . declKind == "interface" then
if atag == "typeobject" then
return isA ( a . of , b . of )
end
end
return fail ( a , b )
end

if atag == "array" and btag == "array" then



local ok = isA ( a . elem , b . elem )
if ok and not a . fresh then
ok = isA ( b . elem , a . elem )
end
if ok then
return true
end
return fail ( a , b )
end



if atag == "array" and a . fresh and a . elems and btag == "tuple" then
return tupleReadsAs ( a . elems , b )
end





if atag == "tuple" and btag == "tuple" then
if # a . elems ~= # b . elems then
return fail ( a , b )
end
for j , e in ipairs ( a . elems ) do
if not isA ( e , b . elems [ j ] ) or not isA ( b . elems [ j ] , e ) then
return fail ( a , b )
end
end
return true
end



if atag == "tuple" and btag == "array" then
for _ , e in ipairs ( a . elems ) do
if not isA ( e , b . elem ) or not isA ( b . elem , e ) then
return fail ( a , b )
end
end
return true
end





if b . tag == "map" and a . tag == "shape" then
if b . readable then
if not isA ( T . string , b . key ) then
return fail ( a , b )
end
if a . indexReadValue then
if not optionalIsA ( b . key , a . indexReadKey ) or not optionalIsA ( a . indexReadValue , b . value ) then
return fail ( a , b )
end
else
for _ , f in ipairs ( a . fields ) do
if f . read and not isA ( f . read , b . value ) then
return false , ("%s is not a %s (field %q: %s is not a %s)")

: format ( T . tostring ( a ) , T . tostring ( b ) , f . name , T . tostring ( f . read ) , T . tostring ( b . value ) )
end
end
end
end
if b . writeValue
and a . indexWriteValue
and ( not optionalIsA ( b . writeKey , a . indexWriteKey ) or not optionalIsA ( b . writeValue , a . indexWriteValue ) )
then
return fail ( a , b )
elseif b . writeValue and not a . indexWriteValue then
if not optionalIsA ( T . string , b . writeKey ) then
return fail ( a , b )
end
if not a . fresh then
for _ , f in ipairs ( a . fields ) do
if not f . write or not isA ( b . writeValue , f . write ) then
return false , ("%s is not a %s (field %q is not writable as %s)")

: format ( T . tostring ( a ) , T . tostring ( b ) , f . name , T . tostring ( b . writeValue ) )
end
end
end
end
return true
end





if ( atag == "array" or atag == "tuple" ) and btag == "map" then
local element = atag == "array" and ( a ) . elem or T . union ( ( a ) . elems )
if b . readable and ( not isA ( T . integer , b . key ) or not isA ( element , b . value ) ) then
return fail ( a , b )
end
if b . writeValue
and ( atag == "tuple" or not optionalIsA ( b . writeKey , T . integer ) or not isA ( b . writeValue , element ) )
then
return fail ( a , b )
end
return true
end

if atag == "map" and btag == "map" then
if b . readable and ( not a . readable or not isA ( b . key , a . key ) or not isA ( a . value , b . value ) ) then
return fail ( a , b )
end
if b . writeValue
and (
not a . writeValue
or not optionalIsA ( b . writeKey , a . writeKey )
or not optionalIsA ( b . writeValue , a . writeValue )
)
then
return fail ( a , b )
end
return true
end



local arrayPart = a . tag == "nominal" and a . arrayOf or nil
if b . tag == "array" and arrayPart then
if isA ( arrayPart , b . elem ) and isA ( b . elem , arrayPart ) then
return true
end
return fail ( a , b )
end




if btag == "shape" then
if ( atag == "shape" or atag == "nominal" ) and a . byname then
local ok , why = propertiesFit ( a , b )
if not ok then
return false , why
end
local readOk , writeOk = indexersFit ( a , b )
if not readOk or not writeOk then
return fail ( a , b )
end
return true
end
return fail ( a , b )
end



if atag == "carray" and btag == "carray" then

if a . elem == b . elem and ( b . count == nil or a . count == b . count ) then
return true
end
return fail ( a , b )
end
if atag == "carray" and btag == "voidptr" then
return true
end
if atag == "carray" and btag == "ptr" and b . elem == a . elem then
return true
end

if atag == "ptr" and btag == "ptr" then

if isA ( a . elem , b . elem ) and isA ( b . elem , a . elem ) then
return true
end
return fail ( a , b )
end

if atag == "func" and btag == "func" then
if ( # ( a . typeParams or { } ) + # ( a . packParams or { } ) + # ( a . constParams or { } ) ) > 0
and ( # ( b . typeParams or { } ) + # ( b . packParams or { } ) + # ( b . constParams or { } ) ) > 0
then
if # ( a . packParams or { } ) ~= # ( b . packParams or { } )
or # ( a . typeParams or { } ) ~= # ( b . typeParams or { } )
or # ( a . constParams or { } ) ~= # ( b . constParams or { } )
then
return false , ("%s is not a %s (generic parameter count)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
local generic = require ( "nupp.compiler.types.generics" )
local map = { }
for index , variable in ipairs ( a . packParams or { } ) do
map [ variable ] = T . pack ( { } , { kind = "generic" , var = ( b . packParams or { } ) [ index ] } )
end
for index , variable in ipairs ( a . typeParams or { } ) do
map [ variable ] = ( b . typeParams or { } ) [ index ]
end
for index , variable in ipairs ( a . constParams or { } ) do
map [ variable ] = ( b . constParams or { } ) [ index ]
end
for index , bound in ipairs ( a . typeBounds or { } ) do
local expected = b . typeBounds and b . typeBounds [ index ]
if bound and ( expected == nil or not isA ( expected , generic . rebind ( bound , map ) ) ) then
return false , ("%s is not a %s (generic bound)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
end
local aligned = generic . rebind ( a , map )


local witnesses = { }
for _ , variable in ipairs ( b . typeParams or { } ) do
local witness = T . typevar (
variable . name ,
"quantified:" .. a . id .. ":" .. b . id .. ":" .. variable . id
)
rigidBinders [ witness ] = true
witnesses [ variable ] = witness
end
for index , variable in ipairs ( b . typeParams or { } ) do
local bound = b . typeBounds and b . typeBounds [ index ]
if bound then
( witnesses [ variable ] ) . bound = generic . rebind ( bound , witnesses )
end
end
local closed = {
typeParams = false ,
typeBounds = false ,
packParams = false ,
constParams = false ,
paramKinds = false
}
return isA (
T . funcWith ( generic . rebind ( aligned , witnesses ) , closed ) ,
T . funcWith ( generic . rebind ( b , witnesses ) , closed )
)
end




if ( # ( a . typeParams or { } ) > 0 or # ( a . packParams or { } ) > 0 )
and # ( b . typeParams or { } ) == 0
and # ( b . packParams or { } ) == 0
then
local generic = require ( "nupp.compiler.types.generics" )
local map = { }
generic . unifyPack ( a . paramPack , b . paramPack , map )
for j , tv in ipairs ( a . typeParams or { } ) do
local bound = a . typeBounds and a . typeBounds [ j ]
local actual = map [ tv ]
if bound and actual and not isA ( actual , generic . materialize ( bound , map ) ) then
return false , ("type argument %s does not satisfy %s") : format ( T . tostring ( actual ) , T . tostring ( bound ) )
end
end
local concrete = generic . instantiateFunction ( a , map )
return isA ( concrete , b )
end





local aParamTail , bParamTail = a . paramPack . tail , b . paramPack . tail
if ( aParamTail and aParamTail . kind == "computed" ) or ( bParamTail and bParamTail . kind == "computed" ) then
local generic = require ( "nupp.compiler.types.generics" )
local expandedA , aWhy = generic . expandFunctionPacks ( a )
local expandedB , bWhy = generic . expandFunctionPacks ( b )
if not aWhy and not bWhy and ( expandedA ~= a or expandedB ~= b ) then
return isA ( expandedA , expandedB )
end
end



if b . noYield and not a . noYield then
return false , ("%s is not a %s (it may suspend)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end



if b . sendable and not a . sendable then
return false , ("%s is not %s (another Lua state cannot reproduce it)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end









local n = # a . params
if # b . params < n then
n = # b . params
end
for j = 1 , n do
local am = a . paramModes and a . paramModes [ j ] or "plain"
local bm = b . paramModes and b . paramModes [ j ] or "plain"







if am ~= bm and not ( ( am == "scoped" or am == "borrows" ) and bm == "plain" ) then
return false , ("%s is not a %s (parameter %d ownership mode)") : format ( T . tostring ( a ) , T . tostring ( b ) , j )
end

if not isA ( b . params [ j ] , a . params [ j ] ) then
return false , ("%s is not a %s (parameter %d)") : format ( T . tostring ( a ) , T . tostring ( b ) , j )
end
end
local bExtra = b . paramPack . tail
for j = # b . params + 1 , # a . params do
local am = a . paramModes and a . paramModes [ j ] or "plain"
if b . vararg then


local element = bExtra and bExtra . kind == "homogeneous" and bExtra . type or T . unknown





local moot = element == T . any or element == T . unknown
if not moot and am ~= ( bExtra and bExtra . mode or "plain" ) then
return false , ("%s is not a %s (parameter %d ownership mode)")

: format ( T . tostring ( a ) , T . tostring ( b ) , j )
end
if not isA ( element , a . params [ j ] ) then
return false , ("%s is not a %s (parameter %d)") : format ( T . tostring ( a ) , T . tostring ( b ) , j )
end
elseif not admitsNil ( a . params [ j ] ) then
return false , ("%s is not a %s (parameter count %d vs %d)")

: format ( T . tostring ( a ) , T . tostring ( b ) , # a . params , # b . params )
end
end


if b . noreturn and not a . noreturn then
return false , ("%s is not a %s (it can return)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end



if a . varargType and b . varargType and not isA ( b . varargType , a . varargType ) then
return false , ("%s is not a %s (extra arguments)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end





local aTail , bTail = a . paramPack . tail , b . paramPack . tail
local aTailMode = aTail and aTail . mode or "plain"
local bTailMode = bTail and bTail . mode or "plain"
local bTailType = bTail and bTail . kind == "homogeneous" and bTail . type or nil
local mootTail = ( bTailType == T . any or bTailType == T . unknown )
and ( aTailMode == "scoped" or aTailMode == "borrows" )
and bTailMode == "plain"
if aTail
and bTail
and aTail . kind == "homogeneous"
and bTail . kind == "homogeneous"
and aTailMode ~= bTailMode
and not mootTail
then
return false , ("%s is not a %s (extra argument ownership mode)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
local rn = # a . rets
if # b . rets < rn then
rn = # b . rets
end
for j = 1 , rn do

if not isA ( a . rets [ j ] , b . rets [ j ] ) then
return false , ("%s is not a %s (return %d)") : format ( T . tostring ( a ) , T . tostring ( b ) , j )
end
end
local packsOk , packsWhy = relations . packIsA ( a . retPack , b . retPack )
if not packsOk then
return false , ("%s is not a %s (%s)") : format ( T . tostring ( a ) , T . tostring ( b ) , packsWhy )
end
if b . yieldPack then
if not a . yieldPack then
return false , ("%s is not a %s (missing yield protocol)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
local yieldOk = relations . packIsA ( a . yieldPack , b . yieldPack )
local resumeOk = a . resumePack and b . resumePack and relations . packIsA ( b . resumePack , a . resumePack )
if not yieldOk or not resumeOk then
return false , ("%s is not a %s (coroutine protocol)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
end




for result = 1 , math . max ( # a . rets , # b . rets ) do
local as = a . preservesResults and a . preservesResults [ result ]
local bs = b . preservesResults and b . preservesResults [ result ]
if as ~= bs then
return false , ("%s is not a %s (return %d preservation relation)")

: format ( T . tostring ( a ) , T . tostring ( b ) , result )
end
end



if borrowRelation ( a ) ~= borrowRelation ( b ) then
return false , ("%s is not a %s (result borrow relation)") : format ( T . tostring ( a ) , T . tostring ( b ) )
end
return true
end

if atag == "protocolThread" and btag == "thread" then
return true
end
if atag == "protocolThread" and btag == "protocolThread" then
return fail ( a , b )
end




return fail ( a , b )
end









isA = function ( a , b ) 


if a == b or a . id == b . id then
return true
end
if cachedAt ~= generation then
cache = setmetatable ( { } , { __mode = "k" } )
cachedAt = generation
end
local perA = cache [ a ] or { }
cache [ a ] = perA
local hit = perA [ b ]
if hit ~= nil then
if hit == true then
return true
end
return false , tostring ( hit )
end










local pending = assuming [ a ]
if pending ~= nil and pending [ b ] then
usedAssumption = true
return true
end
if pending == nil then
pending = { }
assuming [ a ] = pending
end
local outer = assumptionDepth
if outer == 0 then
usedAssumption = false
end
pending [ b ] = true
assumptionDepth = outer + 1
local ok , why = check ( a , b )
assumptionDepth = outer
pending [ b ] = nil
if not usedAssumption then
perA [ b ] = ok or why or false
end

return ok , why
end

relations . isA = isA
relations . memberIsA = memberIsA

local function containsBinder ( t , binder ) 
if t == binder or t . id == binder . id then
return true
end
if t . tag == "union" or t . tag == "intersection" then
for _ , member in ipairs ( t . members ) do
if containsBinder ( member , binder ) then
return true
end
end
elseif t . tag == "const" or t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" then
return containsBinder ( t . inner , binder )
end

return false
end







function relations . typevarMismatch ( actual , expected ) 
actual , expected = T . unwrapOwnership ( actual ) , T . unwrapOwnership ( expected )
if actual . tag == "typevar" then
if containsBinder ( expected , actual ) then
return false
end
if expected . tag == "typevar" then
return not ( actual . bound and not relations . typevarMismatch ( actual . bound , expected ) )
end
if expected == T . any or expected == T . unknown then
return false
end
return not ( actual . bound and isA ( actual . bound , expected ) )
end







local positions = actual . tag == "tuple" and actual . elems
or actual . tag == "array" and actual . fresh and actual . elems
or nil
if positions and expected . tag == "tuple" and # positions == # expected . elems then
for j , member in ipairs ( positions ) do
if relations . typevarMismatch ( member , expected . elems [ j ] ) then
return true
end
end
return false
end
if actual . tag == "array" and expected . tag == "array" then
return relations . typevarMismatch ( actual . elem , expected . elem )
end
if expected . tag == "typevar" then
if actual == expected or actual . id == expected . id or actual == T . never then
return false
end
local tag = actual . tag
if tag == "union" then


for _ , member in ipairs ( actual . members ) do
if member ~= T . nil_ and relations . typevarMismatch ( member , expected ) then
return true
end
end
return false
elseif tag == "intersection" then
for _ , member in ipairs ( actual . members ) do
if not relations . typevarMismatch ( member , expected ) then
return false
end
end
return true
elseif tag == "nominal" then



local owner = actual
local binder = owner . selfType or owner . origin and ( owner . origin ) . selfType or nil
return not ( binder and ( binder == expected or binder . id == expected . id ) )
elseif tag == "array"
or tag == "map"
or tag == "tuple"
or tag == "shape"
or tag == "func"
or tag == "literal"
then

return true
end
return not T . hasTypevar ( actual )
end

return false
end










function relations . invalidate ( ) 
generation = generation + 1
end









function relations . associatedLookup ( head , name ) 
local associated = require ( "nupp.compiler.types.associated" )
local found = associated . lookup ( head , name )
if found . reason == nil and found . resolved and found . bound and not isA ( found . resolved , found . bound ) then
found . reason = "unfit"
end

return found
end

local __nuppExportValue= relations ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types.relations"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types.relations"]=__nuppExports;return __nuppExports