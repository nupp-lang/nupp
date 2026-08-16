_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local T = require ( "nupp.compiler.types" )
local members = require ( "nupp.compiler.members" )
local consteval = require ( "nupp.compiler.consteval" )
local narrowing = require ( "nupp.compiler.narrowing" )

local generics = { }













local PRESERVE = "preserve"

local MATERIALIZE = "materialize"









local normalize

local newBudget

local reduceProjection

local substWith

local function substConst ( term , map )
if term . tag == "constVar" then
local replacement = map [ term ]
if replacement and replacement . tag ~= "pack" then
return replacement
end
elseif term . tag == "constOp" then
local operands = { }
for j , operand in ipairs ( term . operands ) do
operands [ j ] = substConst ( operand , map )
end
return T . constOp ( term . operation , operands )
end

return term
end

local function substCleanup ( cleanup , map , unmapped )
if cleanup . kind == "function" and cleanup . constTerm then
local term = substConst ( cleanup . constTerm , map )
local specialized = T . constFunctionCleanup (
term ,
term . tag == "constLiteral" and nil or cleanup . name ,
cleanup . functionType and substWith ( cleanup . functionType , map , unmapped ) or nil
)
specialized . validated = cleanup . validated
return specialized
elseif cleanup . kind == "field" and cleanup . cleanup then
return T . fieldCleanup ( cleanup . field , substCleanup ( cleanup . cleanup , map , unmapped ) )
end

return cleanup
end


function generics . materializeConst ( term , map )
return substConst ( term , map )
end


local substPackWith

substPackWith = function ( pack , map , unmapped )
if pack . alternatives then
local alternatives = { }
for j , arm in ipairs ( pack . alternatives ) do
alternatives [ j ] = substPackWith ( arm , map , unmapped )
end
return T . packUnion ( alternatives )
end
local head , modes = { } , { }
for j , value in ipairs ( pack . head ) do
head [ j ] = substWith ( value , map , unmapped )
modes [ j ] = pack . modes [ j ] or "plain"
end
local tail = pack . tail
if tail and tail . kind == "homogeneous" then
tail = { kind = "homogeneous" , type = substWith ( tail . type , map , unmapped ) , mode = tail . mode }
elseif tail and tail . kind == "computed" then
tail = { kind = "computed" , type = substWith ( tail . type , map , unmapped ) }
elseif tail and tail . kind == "generic" then
local replacement = map [ tail . var ]
if replacement and replacement . tag == "pack" then
for j , value in ipairs ( replacement . head ) do
head [ # head + 1 ] = value
modes [ # modes + 1 ] = replacement . modes [ j ] or "plain"
end
tail = replacement . tail
elseif unmapped == PRESERVE then


tail = tail
else
tail = { kind = "unknown" , type = T . any }
end
end

return T . pack ( head , tail , modes )
end

substWith = function ( t , map , unmapped )
if not T . hasTypevar ( t ) then
return t
end
local tag = t . tag
if tag == "projection" then



return T . projection ( substWith ( t . of , map , unmapped ) , t . name )
end
if tag == "typevar" then
local bound = map [ t ]
if bound then
return bound
end

return unmapped == PRESERVE and t or T . any
elseif tag == "array" then
return T . array ( substWith ( t . elem , map , unmapped ) )
elseif tag == "map" then
return T . indexer (
t . readable and substWith ( t . key , map , unmapped ) or nil ,
t . readable and substWith ( t . value , map , unmapped ) or nil ,
t . writeKey and substWith ( t . writeKey , map , unmapped ) or nil ,
t . writeValue and substWith ( t . writeValue , map , unmapped ) or nil
)
elseif tag == "tuple" then
local elems = { }
for j , e in ipairs ( t . elems ) do
elems [ j ] = substWith ( e , map , unmapped )
end
return T . tuple ( elems )
elseif tag == "shape" then
local fields = { }
for j , f in ipairs ( t . fields ) do
fields [
j
] = {
name = f . name ,
read = f . read and substWith ( f . read , map , unmapped ) or nil ,
write = f . write and substWith ( f . write , map , unmapped ) or nil
}
end
return T . shape (
fields ,
{
readKey = t . indexReadKey and substWith ( t . indexReadKey , map , unmapped ) or nil ,
readValue = t . indexReadValue and substWith ( t . indexReadValue , map , unmapped ) or nil ,
writeKey = t . indexWriteKey and substWith ( t . indexWriteKey , map , unmapped ) or nil ,
writeValue = t . indexWriteValue and substWith ( t . indexWriteValue , map , unmapped ) or nil ,
} ,
t . fresh
)
elseif tag == "union" then
local members = { }
for j , m in ipairs ( t . members ) do
members [ j ] = substWith ( m , map , unmapped )
end
return T . union ( members )
elseif tag == "intersection" then
local members = { }
for j , m in ipairs ( t . members ) do
members [ j ] = substWith ( m , map , unmapped )
end
return T . intersection ( members )
elseif tag == "neutral" then
if t . op == "comptimeCall" then
local arguments = { }
for position , argument in ipairs ( t . comptimeArguments or { } ) do
if argument . kind == "type" then
arguments [
position
] = { kind = "type" , value = substWith ( argument . value , map , unmapped ) , }
elseif argument . kind == "typepack" then
arguments [
position
] = {
kind = "typepack" ,
value = substPackWith ( argument . value , map , unmapped ) ,
}
else
arguments [
position
] = { kind = "const" , value = substConst ( argument . value , map ) , }
end
end
return T . comptimeCall (
t . comptimeIdentity ,
t . comptimeHelper ,
arguments ,
t . comptimeBound and substWith ( t . comptimeBound , map , unmapped ) or T . unknown ,
t . comptimeResultPack
)
end
local innerMap = map
if t . binder then
innerMap = { }
for variable , replacement in pairs ( map ) do
innerMap [ variable ] = replacement
end
innerMap [ t . binder ] = t . binder
end
local templateParts = nil
if t . templateParts then
templateParts = { }
for j , part in ipairs ( t . templateParts ) do
templateParts [ j ] = type ( part ) == "string" and part or substWith ( part , map , unmapped )
end
end
local rebound = T . neutral (
t . op ,
t . subject and substWith ( t . subject , map , unmapped ) or nil ,
t . key and substWith ( t . key , map , unmapped ) or nil ,
t . capability ,
t . binder ,
t . keys and substWith ( t . keys , map , unmapped ) or nil ,
t . value and substWith ( t . value , innerMap , unmapped ) or nil ,
t . remap and substWith ( t . remap , innerMap , unmapped ) or nil ,
t . constTerm and substConst ( t . constTerm , map ) or nil ,
templateParts
)



return rebound
elseif tag == "typeHandle" then
return T . typeHandle ( substWith ( t . bound , map , unmapped ) )
elseif tag == "packResult" then
return T . packResult ( substPackWith ( t . pack , map , unmapped ) )
elseif tag == "ptr" then
return T . ptr ( substWith ( t . elem , map , unmapped ) )
elseif tag == "carray" then
local term = t . countTerm and substConst ( t . countTerm , map ) or nil
local count = t . count
if term then
local reduced = consteval . reduce ( term )
term = reduced
if reduced . tag == "constLiteral" and reduced . domain == "integer" then
count = reduced . value
end
end
return T . carray ( substWith ( t . elem , map , unmapped ) , count , term )
elseif tag == "const" then
return T . constOf ( substWith ( t . inner , map , unmapped ) )
elseif tag == "ctype" then
return T . ctype ( substWith ( t . of , map , unmapped ) )
elseif tag == "affine" then
local cleanups = { }
for j , cleanup in ipairs ( t . cleanups or { } ) do
cleanups [ j ] = substCleanup ( cleanup , map , unmapped )
end
return T . affine ( substWith ( t . inner , map , unmapped ) , cleanups , t . transferOnly )
elseif tag == "borrowed" then
return T . borrowed ( substWith ( t . inner , map , unmapped ) )
elseif tag == "pinned" then
return T . pinned ( substWith ( t . inner , map , unmapped ) )
elseif tag == "metatable" then
return T . metatable ( substWith ( t . of , map , unmapped ) )
elseif tag == "typeobject" then
return T . typeObject ( substWith ( t . of , map , unmapped ) )
elseif tag == "protocolThread" then
return T . protocolThread (
substPackWith ( t . startPack , map , unmapped ) ,
substPackWith ( t . resumePack , map , unmapped ) ,
substPackWith ( t . yieldPack , map , unmapped ) ,
substPackWith ( t . returnPack , map , unmapped )
)
elseif tag == "genericAlias" then
return substWith ( t . body , map , unmapped )
elseif tag == "nominal" and t . origin then
local origin = t . origin
local applied = { }
for j , parameter in ipairs ( origin . typeParams or { } ) do
local argument = t . typeArgs and t . typeArgs [ j ] or T . any



if argument . tag == "typevar" and not map [ argument ] then
for binder , replacement in pairs ( map ) do
if binder . tag == "typevar" and binder . id == argument . id then
argument = replacement
break
end
end
end
applied [ parameter ] = substWith ( argument , map , unmapped )
end
for j , parameter in ipairs ( origin . packParams or { } ) do
local argument = t . packArgs and t . packArgs [ j ] or T . pack ( { } , { kind = "unknown" , type = T . any } )
applied [ parameter ] = substPackWith ( argument , map , unmapped )
end
for j , parameter in ipairs ( origin . constParams or { } ) do
local argument = t . constArgs and t . constArgs [ j ] or parameter
applied [ parameter ] = substConst ( argument , map )
end
return generics . instantiate ( origin , applied )
elseif tag == "func" then
local paramPack = substPackWith ( t . paramPack , map , unmapped )
local retPack = substPackWith ( t . retPack , map , unmapped )
local params , rets = paramPack . head , retPack . head
local bounds = nil
if t . typeBounds then
bounds = { }
for j , b in ipairs ( t . typeBounds ) do
bounds [ j ] = substWith ( b , map , unmapped )
end
end
return T . func (
params ,
rets ,
t . vararg ,
t . paramModes ,
t . predicate ,
t . typeParams ,
bounds ,
t . borrowsParam ,
t . borrowsSelf ,
t . borrowsParams ,
t . ffiOut ,
t . varargType and substWith ( t . varargType , map , unmapped ) or nil ,
t . noreturn ,
paramPack ,
retPack ,
t . packParams ,
t . yieldPack and substPackWith ( t . yieldPack , map , unmapped ) or nil ,
t . resumePack and substPackWith ( t . resumePack , map , unmapped ) or nil ,



t . noYield ,
t . paramNames ,
t . preservesResults ,
t . foreign ,
t . constParams ,
t . paramKinds ,
t . partitionResults ,
t . comptimeOnly ,
t . explicitPreserves
)
end

return t
end









reduceProjection = function ( head , name , memo , budget )
if head == T . any then
budget . gradual [ # budget . gradual + 1 ] = name

return T . any
end
if head . tag == "union" then




local arms = { }
for _ , member in ipairs ( ( head ) . members ) do
local reducedArm = reduceProjection ( member , name , memo , budget )
if reducedArm . tag == "projection" then
return T . projection ( head , name )
end
arms [ # arms + 1 ] = reducedArm
end

return T . union ( arms )
end
if head . tag == "typevar" then




local bound = ( head ) . bound
if bound and bound . tag == "nominal" and ( bound ) . declKind ~= "interface" then
return reduceProjection ( bound , name , memo , budget )
end

return T . projection ( head , name )
end
if head . tag ~= "nominal" then
return T . projection ( head , name )
end



local answers = ( head ) . associatedAnswers
local entry = answers and answers [ name ] or nil
if not entry then
return T . projection ( head , name )
end
if ( head ) . declKind == "interface" and entry . kind ~= "fixed" then





return T . projection ( head , name )
end
local answer = entry . type
if entry . selfBinder then




answer = generics . rebind ( answer , { [ entry . selfBinder ] = head } )
end
local key = head . id .. "." .. name
local label = T . tostring ( head ) .. "." .. name
if budget . active [ key ] then



if not budget . cycle then
local loop = { }
local keys = { }
local from = nil
for j , seen in ipairs ( budget . path ) do
if seen . key == key then
from = j
break
end
end
for j = from or # budget . path , # budget . path do
loop [ # loop + 1 ] = budget . path [ j ] . label
keys [ # keys + 1 ] = budget . path [ j ] . key
end
loop [ # loop + 1 ] = label
table . sort ( keys )
budget . cycle = loop
budget . cycleKeys = keys
end

return T . projection ( head , name )
end
budget . active [ key ] = true
budget . path [ # budget . path + 1 ] = { key = key , label = label }




local reduced , err = normalize ( answer , memo , budget )
budget . path [ # budget . path ] = nil
budget . active [ key ] = nil

return reduced , err
end

























function generics . normalize ( t )
local found = generics . evaluate ( t )

return { type = found . type , gradual = found . gradual , cycle = found . cycle , cycleKeys = found . cycleKeys }
end









function generics . normalizePack ( pack )
local budget = newBudget ( nil )
local memo = { }
local head = { }
for j , value in ipairs ( pack . head ) do
head [ j ] = ( normalize ( value , memo , budget ) )
end
local tail = pack . tail
if tail and tail . kind == "homogeneous" then
tail = { kind = "homogeneous" , type = ( normalize ( tail . type , memo , budget ) ) , mode = tail . mode }
end

return { pack = T . pack ( head , tail , pack . modes ) , gradual = budget . gradual , cycle = budget . cycle , }
end









function generics . rebind ( t , map )
return substWith ( t , map , PRESERVE )
end








function generics . materialize ( t , map )
return substWith ( t , map , MATERIALIZE )
end

local MAX_MAPPED_FIELDS = 256
local MAX_REDUCTION_VISITS = 4096

local function literalKeys ( t )
if t == T . never then
return { }
end
if t . tag == "literal" and ( t . base == T . string or t . base == T . integer ) then
return { t }
end
if t . tag ~= "union" then
return nil
end
local out = { }
for _ , member in ipairs ( t . members ) do
if member == T . never then

elseif member . tag ~= "literal" or ( member . base ~= T . string and member . base ~= T . integer ) then
return nil
else
out [ # out + 1 ] = member
end
end

return out
end

local function keyFits ( key , allowed )
if allowed == T . any then
return true
end
if key == allowed then
return true
end
if key . tag == "literal" then
if key . base == allowed then
return true
end
if allowed . tag == "union" then
for _ , member in ipairs ( allowed . members ) do
if keyFits ( key , member ) then
return true
end
end
end
end

return false
end
















































newBudget = function ( control )
return { visits = 0 , control = control , active = { } , path = { } , gradual = { } , }
end








local function blocked ( t )
return T . hasTypevar ( t ) or t . tag == "neutral" or t . tag == "projection"
end

local function reduceKeyof ( t , memo , budget )
local subject , err = normalize ( t . subject , memo , budget )
if err then
return T . any , err
end
local surfaceSubject = subject
if subject . tag == "typevar" and subject . bound then
surfaceSubject , err = normalize ( subject . bound , memo , budget )
if err then
return T . any , err
end
elseif blocked ( subject ) then
return T . neutral ( "keyof" , subject , nil , t . capability ) , nil
end
if surfaceSubject == T . any then
return T . any
elseif surfaceSubject == T . unknown then
return T . any , "unknown has no known member keys"
elseif surfaceSubject == T . never then
return T . never
end
local surface = members . view ( surfaceSubject )
local keys = { }
for _ , entry in ipairs ( surface . ordered ) do
if t . capability == "write" and entry . writeType or t . capability ~= "write" and entry . readType then
keys [ # keys + 1 ] = T . literal ( entry . name , T . string )
end
end
local indexer = t . capability == "write" and surface . writeIndexer or surface . readIndexer
if indexer then
keys [ # keys + 1 ] = indexer . keyType
end

return # keys > 0 and T . union ( keys ) or T . never
end

local function reduceMember ( t , memo , budget )
local subject , subjectErr = normalize ( t . subject , memo , budget )
if subjectErr then
return T . any , subjectErr
end
local key , keyErr = normalize ( t . key , memo , budget )
if keyErr then
return T . any , keyErr
end
if blocked ( subject ) or blocked ( key ) then
return T . neutral ( "member" , subject , key , t . capability ) , nil
end
if subject == T . any or key == T . any then
return T . any
elseif subject == T . unknown then
return T . any , "unknown has no known members"
elseif subject == T . never or key == T . never then
return T . never
end
local keys = literalKeys ( key )
if not keys then
return T . any , "indexed member key must be a finite union of literal keys"
end
local surface = members . view ( subject )
local values = { }
for _ , literal in ipairs ( keys ) do
local entry = literal . base == T . string and surface . byname [ tostring ( literal . constant ) ] or nil
local value = entry and ( t . capability == "write" and entry . writeType or entry . readType ) or nil
if not value then
local indexer = t . capability == "write" and surface . writeIndexer or surface . readIndexer
if indexer and keyFits ( literal , indexer . keyType ) then
value = indexer . valueType
end
end
if not value then
return T . any , (
"member %q has no %s capability"
) : format ( tostring ( literal . constant ) , t . capability == "write" and "write" or "read" )
end
values [ # values + 1 ] = value
end
if # values == 0 then
return T . never
end

return t . capability == "write" and T . intersection ( values ) or T . union ( values )
end

local function reduceMapped ( t , memo , budget )
local keysType , err = normalize ( t . keys , memo , budget )
if err then
return T . any , err
end
if blocked ( keysType ) then
return T . neutral ( "mapped" , nil , nil , t . capability , t . binder , keysType , t . value , t . remap ) , nil
end
local keys = literalKeys ( keysType )
if not keys then
return T . any , "mapped keys must be a finite union of string or integer literals"
end
if # keys > MAX_MAPPED_FIELDS then
return T . any , ( "mapped shape has %d fields; limit is %d" ) : format ( # keys , MAX_MAPPED_FIELDS )
end
local fields , seen = { } , { }
for _ , key in ipairs ( keys ) do
local name = tostring ( key . constant )
local dropped = false
if t . remap then
local remapped = substWith ( t . remap , { [ t . binder ] = key } , PRESERVE )
local reducedRemap , remapError = normalize ( remapped , memo , budget )
if remapError then
return T . any , remapError
end
if reducedRemap == T . never then
dropped = true
elseif reducedRemap . tag ~= "literal" or reducedRemap . base ~= T . string then
return T . any , "mapped key remap must reduce to a string literal or never"
else
name = reducedRemap . constant
end
end
if not dropped then
if seen [ name ] then
return T . any , ( "mapped key %q is duplicated" ) : format ( name )
end
seen [ name ] = true
local value = substWith ( t . value , { [ t . binder ] = key } , PRESERVE )
local reduced , valueErr = normalize ( value , memo , budget )
if valueErr then
return T . any , valueErr
end
fields [
# fields + 1
] = {
name = name ,
read = t . capability == "read" and reduced or nil ,
write = t . capability == "write" and reduced or nil
}
end
end

return T . shape ( fields )
end

local function templateAlternatives ( t )
if t . tag == "literal" and t . base == T . string then
return { t . constant }
end
if t . tag ~= "union" then
return nil
end
local out = { }
for _ , member in ipairs ( t . members ) do
if member . tag ~= "literal" or member . base ~= T . string then
return nil
end
out [ # out + 1 ] = member . constant
end

return out
end

local function reduceTemplate ( t , memo , budget )
local products = { "" }
for _ , part in ipairs ( t . templateParts or { } ) do
if type ( part ) == "string" then
for j = 1 , # products do
products [ j ] = products [ j ] .. ( part )
end
else
local reduced , err = normalize ( part , memo , budget )
if err then
return T . any , err
end
if reduced == T . any then
return T . string
end
if T . hasTypevar ( reduced ) or reduced . tag == "neutral" then
return T . neutral ( "template" , nil , nil , nil , nil , nil , nil , nil , nil , t . templateParts ) , nil
end
local alternatives = templateAlternatives ( reduced )
if not alternatives then
return T . any , "template holes must reduce to finite string literals"
end
if # products * # alternatives > MAX_MAPPED_FIELDS then
return T . any , ( "template product exceeds %d members" ) : format ( MAX_MAPPED_FIELDS )
end
local expanded = { }
for _ , prefix in ipairs ( products ) do
for _ , suffix in ipairs ( alternatives ) do
expanded [ # expanded + 1 ] = prefix .. suffix
end
end
products = expanded
end
end
local out = { }
for j , value in ipairs ( products ) do
out [ j ] = T . literal ( value , T . string )
end

return T . union ( out )
end



local function reduceTupleConcat ( t , memo , budget )
local prefix , prefixError = normalize ( t . subject , memo , budget )
if prefixError then
return T . any , prefixError
end
local tail , tailError = normalize ( t . key , memo , budget )
if tailError then
return T . any , tailError
end
if prefix . tag ~= "tuple" then
return T . any , "tuple unpack prefix did not reduce to a tuple"
end
if tail . tag == "tuple" then
local elems = { }
for _ , elem in ipairs ( prefix . elems ) do
elems [ # elems + 1 ] = elem
end
for _ , elem in ipairs ( tail . elems ) do
elems [ # elems + 1 ] = elem
end
return T . tuple ( elems )
end
if tail . tag == "array" and tail . elem == T . never then
return prefix
end
if T . hasTypevar ( tail ) or tail . tag == "neutral" then
return T . neutral ( "tupleConcat" , prefix , tail )
end

return T . any , ( "tuple unpack must reduce to a tuple, got %s" ) : format ( T . tostring ( tail ) )
end

local normalizeReductionPack
normalizeReductionPack = function ( pack , memo , budget )
if pack . alternatives then
local alternatives = { }
for j , alternative in ipairs ( pack . alternatives ) do
local err
alternatives [ j ] , err = normalizeReductionPack ( alternative , memo , budget )
if err then
return pack , err
end
end
return T . packUnion ( alternatives )
end
local head = { }
for j , member in ipairs ( pack . head ) do
local err
head [ j ] , err = normalize ( member , memo , budget )
if err then
return pack , err
end
end
local tail = pack . tail
if tail and tail . kind == "homogeneous" then
local reduced , err = normalize ( tail . type , memo , budget )
if err then
return pack , err
end
tail = { kind = "homogeneous" , type = reduced , mode = tail . mode }
elseif tail and tail . kind == "computed" then
local reduced , err = normalize ( tail . type , memo , budget )
if err then
return pack , err
end
tail = { kind = "computed" , type = reduced }
end

return T . pack ( head , tail , pack . modes )
end

normalize = function ( t , memo , budget )
budget . visits = budget . visits + 1
if budget . control and budget . control . cancelled and budget . visits % 32 == 0 and budget . control . cancelled ( ) then
return T . any , "type reduction cancelled"
end
if budget . visits > MAX_REDUCTION_VISITS then
return T . any , ( "finite type reduction exceeded %d visited nodes" ) : format ( MAX_REDUCTION_VISITS )
end
local cached = memo and memo [ t ]
if cached then
return cached . type , cached . error
end

local out , err = t , nil
if t . tag == "projection" then



local head , headErr = normalize ( t . of , memo , budget )
if headErr then
out , err = T . any , headErr
else
out , err = reduceProjection ( head , t . name , memo , budget )
end
elseif t . tag == "typeHandle" then
local bound
bound , err = normalize ( t . bound , memo , budget )
if not err then
out = T . typeHandle ( bound )
end
elseif t . tag == "packResult" then
local pack
pack , err = normalizeReductionPack ( t . pack , memo , budget )
if not err then
out = T . packResult ( pack )
end
elseif t . tag == "neutral" then
if t . op == "comptimeCall" then
local arguments , open = { } , false
for position , argument in ipairs ( t . comptimeArguments or { } ) do
if argument . kind == "type" then
local reduced
reduced , err = normalize ( argument . value , memo , budget )
if err then
break
end
arguments [ position ] = { kind = "type" , value = reduced }
open = open or T . hasTypevar ( reduced ) or T . hasProjection ( reduced ) or reduced . tag == "neutral"
elseif argument . kind == "typepack" then
local reduced
reduced , err = normalizeReductionPack ( argument . value , memo , budget )
if err then
break
end
arguments [ position ] = { kind = "typepack" , value = reduced }
local wrapped = T . packResult ( reduced )
open = open or T . hasTypevar ( wrapped ) or T . hasProjection ( wrapped )
for _ , member in ipairs ( reduced . head or { } ) do
open = open or member . tag == "neutral"
end
else
local reduced
reduced , err = consteval . reduce ( argument . value )
if err then
break
end
if reduced . tag == "constLiteral" and reduced . domain == "function" then
arguments [ position ] = { kind = "const" , value = reduced }
else
arguments [
position
] = { kind = "value" , value = reduced . tag == "constLiteral" and reduced . value or reduced }
end
open = open or reduced . tag ~= "constLiteral"
end
end
if not err and open then
local rebound = { }
for position , argument in ipairs ( arguments ) do
if argument . kind == "type" or argument . kind == "typepack" then
rebound [ position ] = argument
else
rebound [ position ] = { kind = "const" , value = argument . value }
end
end
out = T . comptimeCall (
t . comptimeIdentity ,
t . comptimeHelper ,
rebound ,
t . comptimeBound ,
t . comptimeResultPack
)
elseif not err and budget . control and budget . control . evaluateTypeFunction then
local failure
local evaluated
evaluated , failure = budget . control . evaluateTypeFunction ( t . comptimeHelper , arguments )
if evaluated then
out = evaluated . tag == "pack" and T . packResult ( evaluated ) or evaluated
else
err = failure and failure . message or tostring ( failure or "type-function evaluation failed" )
end
if not err and out and not t . comptimeResultPack and t . comptimeBound then
local relations = require (
"nupp.compiler.relations"
)
local fits , why = relations . isA ( out , t . comptimeBound )
if not fits then
err = "generated type violates its declared result bound: " .. ( why or "not satisfied" )
out = T . any
end
end
elseif not err then
out = t
end
elseif t . op == "singleton" then
local term
term , err = consteval . reduce ( t . constTerm )
out = not err and consteval . singleton ( term ) or T . any
elseif t . op == "keyof" then
out , err = reduceKeyof ( t , memo , budget )
elseif t . op == "member" then
out , err = reduceMember ( t , memo , budget )
elseif t . op == "mapped" then
out , err = reduceMapped ( t , memo , budget )
elseif t . op == "template" then
out , err = reduceTemplate ( t , memo , budget )
elseif t . op == "tupleConcat" then
out , err = reduceTupleConcat ( t , memo , budget )
else
err = "unknown type reduction operation " .. string . format ( "%q" , t . op )
out = T . any
end

elseif t . tag == "union" or t . tag == "intersection" then
local parts = { }
for j , member in ipairs ( t . members ) do
parts [ j ] , err = normalize ( member , memo , budget )
if err then
break
end
end
if not err then
out = t . tag == "union" and T . union ( parts ) or T . intersection ( parts )
end
elseif t . tag == "array" then
local elem
elem , err = normalize ( t . elem , memo , budget )
if not err then
out = T . array ( elem )
end
elseif t . tag == "map" then
local readKey , readValue , writeKey , writeValue = nil , nil , nil , nil
if t . readable then
readKey , err = normalize ( t . key , memo , budget )
end
if not err and t . readable then
readValue , err = normalize ( t . value , memo , budget )
end
if not err and t . writeKey then
writeKey , err = normalize ( t . writeKey , memo , budget )
end
if not err and t . writeValue then
writeValue , err = normalize ( t . writeValue , memo , budget )
end
if not err then
out = T . indexer ( readKey , readValue , writeKey , writeValue )
end
elseif t . tag == "tuple" then
local elems = { }
for j , elem in ipairs ( t . elems ) do
elems [ j ] , err = normalize ( elem , memo , budget )
if err then
break
end
end
if not err then
out = T . tuple ( elems )
end
elseif t . tag == "ptr" then
local elem
elem , err = normalize ( t . elem , memo , budget )
if not err then
out = T . ptr ( elem )
end
elseif t . tag == "carray" then
local elem
elem , err = normalize ( t . elem , memo , budget )
local count , term = t . count , t . countTerm
if not err and term then
term , err = consteval . reduce ( term )
if not err and term . tag == "constLiteral" then
if term . domain ~= "integer" or ( term . value ) < 0 then
err = "C array length must be a non-negative integer const"
else
count = term . value
end
end
end
if not err then
out = T . carray ( elem , count , term )
end
elseif t . tag == "const" then
local inner
inner , err = normalize ( t . inner , memo , budget )
if not err then
out = T . constOf ( inner )
end
elseif t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" then
local inner
inner , err = normalize ( t . inner , memo , budget )
if not err then
if t . tag == "affine" then
out = T . affine ( inner , t . cleanups , t . transferOnly )
elseif t . tag == "borrowed" then
out = T . borrowed ( inner )
else
out = T . pinned ( inner )
end
end
elseif t . tag == "ctype" then
local inner
inner , err = normalize ( t . of , memo , budget )
if not err then
out = T . ctype ( inner )
end
elseif t . tag == "metatable" then
local inner
inner , err = normalize ( t . of , memo , budget )
if not err then
out = T . metatable ( inner )
end
elseif t . tag == "typeobject" then
local inner
inner , err = normalize ( t . of , memo , budget )
if not err then
out = T . typeObject ( inner )
end
elseif t . tag == "func" then




local paramPack , paramErr = normalizeReductionPack ( t . paramPack , memo , budget )
local retPack , retErr = normalizeReductionPack ( t . retPack , memo , budget )
err = err or paramErr or retErr
local changed = paramPack ~= t . paramPack or retPack ~= t . retPack
local varargType = t . varargType
if varargType then
local reduced , varargErr = normalize ( varargType , memo , budget )
err = err or varargErr
changed = changed or reduced ~= varargType
varargType = reduced
end
local bounds = t . typeBounds
if bounds then
local reducedBounds = { }
for j , bound in ipairs ( bounds ) do
local reduced , boundErr = normalize ( bound , memo , budget )
err = err or boundErr
reducedBounds [ j ] = reduced
changed = changed or reduced ~= bound
end
bounds = reducedBounds
end
local yieldPack , resumePack = t . yieldPack , t . resumePack
if yieldPack then
local reduced , yieldErr = normalizeReductionPack ( yieldPack , memo , budget )
err = err or yieldErr
changed = changed or reduced ~= yieldPack
yieldPack = reduced
end
if resumePack then
local reduced , resumeErr = normalizeReductionPack ( resumePack , memo , budget )
err = err or resumeErr
changed = changed or reduced ~= resumePack
resumePack = reduced
end
if changed then
out = T . func (
paramPack . head ,
retPack . head ,
t . vararg ,
t . paramModes ,
t . predicate ,
t . typeParams ,
bounds ,
t . borrowsParam ,
t . borrowsSelf ,
t . borrowsParams ,
t . ffiOut ,
varargType ,
t . noreturn ,
paramPack ,
retPack ,
t . packParams ,
yieldPack ,
resumePack ,
t . noYield ,
t . paramNames ,
t . preservesResults ,
t . foreign ,
t . constParams ,
t . paramKinds ,
t . partitionResults ,
t . comptimeOnly ,
t . explicitPreserves
)
end
elseif t . tag == "shape" then
local fields = { }
for j , field in ipairs ( t . fields ) do
local read , write = nil , nil
if field . read then
read , err = normalize ( field . read , memo , budget )
end
if not err and field . write then
write , err = normalize ( field . write , memo , budget )
end
fields [ j ] = { name = field . name , read = read , write = write }
if err then
break
end
end
local readKey , readValue , writeKey , writeValue = t . indexReadKey , t . indexReadValue , t . indexWriteKey , t . indexWriteValue
if not err and readKey then
readKey , err = normalize ( readKey , memo , budget )
end
if not err and readValue then
readValue , err = normalize ( readValue , memo , budget )
end
if not err and writeKey then
writeKey , err = normalize ( writeKey , memo , budget )
end
if not err and writeValue then
writeValue , err = normalize ( writeValue , memo , budget )
end
if not err then
out = T . shape (
fields ,
{ readKey = readKey , readValue = readValue , writeKey = writeKey , writeValue = writeValue , } ,
t . fresh
)
end
end


if memo and not err then
memo [ t ] = { type = out , error = err }
end

return out , err
end






























function generics . evaluatePack ( pack , control )
local budget = newBudget ( control )
local reduced , err = normalizeReductionPack ( pack , { } , budget )

return { pack = reduced , error = err , gradual = budget . gradual , cycle = budget . cycle }
end






function generics . evaluate ( t , map , control )
local budget = newBudget ( control )
local rebound = map and substWith ( t , map , PRESERVE ) or t
local reduced , err = normalize ( rebound , { } , budget )

return { type = reduced , error = err , gradual = budget . gradual , cycle = budget . cycle , cycleKeys = budget . cycleKeys , }
end

function generics . reduce (
t ,
map ,
memo ,
control
)
local rebound = substWith ( t , map or { } , PRESERVE )

return normalize ( rebound , memo or { } , newBudget ( control ) )
end


function generics . rebindPack ( pack , map )
return substPackWith ( pack , map , PRESERVE )
end


function generics . materializePack ( pack , map )
return substPackWith ( pack , map , MATERIALIZE )
end




function generics . expandComputedPack ( pack , control )
local tail = pack . tail
if not tail or tail . kind ~= "computed" then
return pack
end
local computed , reductionError = generics . reduce ( tail . type , nil , nil , control )
if reductionError then
return pack , "unpackof could not reduce its type: " .. reductionError
end
if computed . tag == "tuple" then
local head , modes = { } , { }
for j , value in ipairs ( pack . head ) do
head [ j ] , modes [ j ] = value , pack . modes [ j ] or "plain"
end
for _ , value in ipairs ( computed . elems ) do
head [ # head + 1 ] , modes [ # modes + 1 ] = value , "plain"
end
return T . pack ( head , nil , modes )
end
if computed . tag == "array" then
if computed . elem == T . never then
return T . pack ( pack . head , nil , pack . modes )
end
return T . pack ( pack . head , { kind = "homogeneous" , type = computed . elem } , pack . modes )
end
if computed . tag == "packResult" then
local head , modes = { } , { }
for position , value in ipairs ( pack . head ) do
head [ position ] , modes [ position ] = value , pack . modes [ position ] or "plain"
end
for position , value in ipairs ( computed . pack . head ) do
head [ # head + 1 ] , modes [ # modes + 1 ] = value , computed . pack . modes [ position ] or "plain"
end
return T . pack ( head , computed . pack . tail , modes )
end
if computed == T . any or computed == T . unknown or computed . tag == "neutral" or computed . tag == "typevar" then
return T . pack ( pack . head , { kind = "unknown" , type = T . any } , pack . modes )
end

return pack , ( "unpackof type must reduce to a tuple or array, got %s" ) : format ( T . tostring ( computed ) )
end




function generics . instantiateFunction ( t , map , control )
local evaluated = generics . evaluate ( substWith ( t , map , MATERIALIZE ) , nil , control )
local concrete = evaluated . type
if evaluated . error then
return t , evaluated . error
end
if concrete . tag ~= "func" then
return t
end

local paramPack , packError = generics . expandComputedPack ( concrete . paramPack , control )
if packError then
return concrete , packError
end
local retPack
retPack , packError = generics . expandComputedPack ( concrete . retPack , control )
if packError then
return concrete , packError
end

return T . func (
paramPack . head ,
retPack . head ,
paramPack . tail ~= nil ,
paramPack . modes ,
concrete . predicate ,
nil ,
nil ,
concrete . borrowsParam ,
concrete . borrowsSelf ,
concrete . borrowsParams ,
concrete . ffiOut ,
concrete . varargType ,
concrete . noreturn ,
paramPack ,
retPack ,
nil ,
concrete . yieldPack ,
concrete . resumePack ,
concrete . noYield ,
concrete . paramNames ,
concrete . preservesResults ,
concrete . foreign ,
nil ,
nil ,
concrete . partitionResults ,
concrete . comptimeOnly ,
concrete . explicitPreserves
)
end


function generics . unifyPack ( param , arg , map )
if param . alternatives then
for _ , arm in ipairs ( param . alternatives ) do
generics . unifyPack ( arm , arg , map )
end
return
end
for j , expected in ipairs ( param . head ) do
generics . unify ( expected , T . packAt ( arg , j ) or T . nil_ , map )
end
local tail = param . tail
if not tail then
return
end
if tail . kind == "generic" then
local rest , modes = { } , { }
for j = # param . head + 1 , # arg . head do
rest [ # rest + 1 ] = arg . head [ j ]
modes [ # modes + 1 ] = arg . modes [ j ] or "plain"
end
local actualTail = # param . head < # arg . head and arg . tail or arg . tail
local remaining = T . pack ( rest , actualTail , modes )
local prior = map [ tail . var ]
if prior then
for j , value in ipairs ( remaining . head ) do
generics . unify ( T . packAt ( prior , j ) or T . nil_ , value , map )
end
else
map [ tail . var ] = remaining
end
elseif tail . kind == "homogeneous" then
for j = # param . head + 1 , # arg . head do
generics . unify ( tail . type , arg . head [ j ] , map )
end
if arg . tail and arg . tail . kind == "homogeneous" then
generics . unify ( tail . type , arg . tail . type , map )
end
end
end




local instantiations = { }
local fillingInstantiations = { }




local function fillInstantiationMembers ( inst , declaration , map )
for name , ft in pairs ( declaration . byname ) do
inst . byname [ name ] = substWith ( ft , map , PRESERVE )
end
for name , ft in pairs ( declaration . writeByname or { } ) do
inst . writeByname [ name ] = substWith ( ft , map , PRESERVE )
end
for name , ft in pairs ( declaration . staticByname or { } ) do
inst . staticByname [ name ] = substWith ( ft , map , PRESERVE )
end
for name , ft in pairs ( declaration . staticWriteByname or { } ) do
inst . staticWriteByname [ name ] = substWith ( ft , map , PRESERVE )
end
for name , ft in pairs ( declaration . metamethods or { } ) do
inst . metamethods [ name ] = substWith ( ft , map , PRESERVE )
end
end





function generics . instantiate ( n , map )
local parts = { n . id }
for _ , tv in ipairs ( n . typeParams or { } ) do
parts [ # parts + 1 ] = "type:" .. ( map [ tv ] or T . any ) . id
end
for _ , pv in ipairs ( n . packParams or { } ) do
local argument = map [ pv ]
parts [ # parts + 1 ] = "pack:" .. ( argument and argument . id or "unbound" )
end
for _ , cv in ipairs ( n . constParams or { } ) do
local value = map [ cv ]
parts [ # parts + 1 ] = "const:" .. ( value and value . id or "unbound" )
end
local key = table . concat ( parts , "|" )
local cached = instantiations [ key ]
if cached then
if not fillingInstantiations [ key ] then
fillingInstantiations [ key ] = true
fillInstantiationMembers ( cached , n , map )
fillingInstantiations [ key ] = nil
end
return cached
end
local inst = T . nominal ( n . name , n . declKind )
inst . origin = n
inst . lpegPattern = n . lpegPattern
inst . lpegLibrary = n . lpegLibrary
inst . lpegPatternOrigin = n . lpegPatternOrigin
inst . typeArgs = { }
for j , tv in ipairs ( n . typeParams or { } ) do
inst . typeArgs [ j ] = map [ tv ] or T . any
end
inst . packArgs = { }
for j , pv in ipairs ( n . packParams or { } ) do
inst . packArgs [ j ] = map [ pv ] or T . pack ( { } , { kind = "unknown" , type = T . any } )
end
inst . constArgs = { }
for j , cv in ipairs ( n . constParams or { } ) do
inst . constArgs [ j ] = map [ cv ] or cv
end
inst . paramKinds = n . paramKinds
inst . fieldOrder = n . fieldOrder
inst . fieldDefaults = n . fieldDefaults
inst . privateFields = n . privateFields
inst . moduleName = n . moduleName
inst . sealedModule = n . sealedModule
inst . affineFields = n . affineFields
inst . fieldBorrowSources = n . fieldBorrowSources
inst . borrowedRootFields = n . borrowedRootFields
inst . arrayOf = n . arrayOf and substWith ( n . arrayOf , map , PRESERVE ) or nil
inst . fieldDefs = n . fieldDefs
inst . writeFieldDefs = n . writeFieldDefs
inst . staticFieldDefs = n . staticFieldDefs
inst . staticWriteFieldDefs = n . staticWriteFieldDefs
inst . deriveKey = n . deriveKey
inst . deriveRecipe = n . deriveRecipe
inst . derivedDefinitions = n . derivedDefinitions
inst . derivedStaticDefinitions = n . derivedStaticDefinitions
inst . derivedContracts = n . derivedContracts
inst . selfType = n . selfType
inst . supertypes = { }
for j , parent in ipairs ( n . supertypes or { } ) do
inst . supertypes [ j ] = substWith ( parent , map , PRESERVE )
end


instantiations [ key ] = inst
fillingInstantiations [ key ] = true
fillInstantiationMembers ( inst , n , map )





local complete = { }
for binder , stands in pairs ( map ) do
complete [ binder ] = stands
end
for _ , binder in ipairs ( n . typeParams or { } ) do
if complete [ binder ] == nil then
complete [ binder ] = T . any
end
end
for _ , binder in ipairs ( n . packParams or { } ) do
if complete [ binder ] == nil then
complete [ binder ] = T . pack ( { } , { kind = "unknown" , type = T . any } )
end
end
if n . associatedRequirements then
inst . associatedRequirements = { }
for j , requirement in ipairs ( n . associatedRequirements ) do



inst . associatedRequirements [
j
] = setmetatable({ name =
requirement . name ,  bound =
requirement . bound and generics . rebind ( requirement . bound , complete ) or nil ,  selfBinder =
requirement . selfBinder ,  definition =
requirement . definition }, T.AssociatedRequirement)

end
end
if n . associatedAnswers then
inst . associatedAnswers = { }
for name , entry in pairs ( n . associatedAnswers ) do



inst . associatedAnswers [
name
] = setmetatable({ type =
generics . rebind ( entry . type , complete ) ,  selfBinder =
entry . selfBinder ,  kind =
entry . kind ,  definition =
entry . definition }, T.AssociatedAnswer)

end
end
inst . overloadedMethods = { }
inst . overloadedStatics = { }
inst . methodEntries = { }
inst . methodDispatchEntries = { }
inst . staticEntries = { }
for name in pairs ( n . overloadedMethods or { } ) do
inst . overloadedMethods [ name ] = true
end
for name in pairs ( n . overloadedStatics or { } ) do
inst . overloadedStatics [ name ] = true
end
for name , entries in pairs ( n . methodEntries or { } ) do
local specialized = { }
for j , entry in ipairs ( entries ) do
specialized [
j
] = {
signature = substWith ( entry . signature , map , PRESERVE ) ,
declaration = entry . declaration ,
member = entry . member ,
parameterKey = entry . parameterKey ,
definition = entry . definition ,
}
end
inst . methodEntries [ name ] = specialized
end
for name , entries in pairs ( n . methodDispatchEntries or { } ) do
local specialized = { }
for j , entry in ipairs ( entries ) do
specialized [
j
] = {
signature = substWith ( entry . signature , map , PRESERVE ) ,
declaration = entry . declaration ,
member = entry . member ,
parameterKey = entry . parameterKey ,
definition = entry . definition ,
}
end
inst . methodDispatchEntries [ name ] = specialized
end
for name , entries in pairs ( n . staticEntries or { } ) do
local specialized = { }
for j , entry in ipairs ( entries ) do
specialized [
j
] = {
signature = substWith ( entry . signature , map , PRESERVE ) ,
declaration = entry . declaration ,
member = entry . member ,
parameterKey = entry . parameterKey ,
definition = entry . definition ,
}
end
inst . staticEntries [ name ] = specialized
end
inst . indexReadKey = n . indexReadKey and substWith ( n . indexReadKey , map , PRESERVE ) or nil
inst . indexReadValue = n . indexReadValue and substWith ( n . indexReadValue , map , PRESERVE ) or nil
inst . indexWriteKey = n . indexWriteKey and substWith ( n . indexWriteKey , map , PRESERVE ) or nil
inst . indexWriteValue = n . indexWriteValue and substWith ( n . indexWriteValue , map , PRESERVE ) or nil
inst . constructors = { }
inst . constructorEntries = { }
for j , signature in ipairs ( n . constructors or { } ) do
local specialized = substWith ( signature , map , PRESERVE )
inst . constructors [ j ] = specialized
local entry = n . constructorEntries and n . constructorEntries [ j ] or nil
inst . constructorEntries [
j
] = {
signature = specialized ,
declaration = entry and entry . declaration or nil ,
index = entry and entry . index or j ,
}
end

fillingInstantiations [ key ] = nil

return inst
end








function generics . unify ( param , arg , map )
param , arg = T . unwrapOwnership ( param ) , T . unwrapOwnership ( arg )
if not T . hasTypevar ( param ) then
return
end
local tag = param . tag
if tag == "typevar" then
if arg ~= T . any and arg ~= T . nil_ then



local bound = map [ param ]
map [ param ] = bound and T . union ( { bound , arg } ) or arg
end
elseif tag == "neutral" and param . op == "singleton" and param . constTerm and param . constTerm . tag == "constVar" then
local actual = consteval . fromType ( arg )
local variable = param . constTerm
if actual then
local prior = map [ variable ]
if prior and prior . id ~= actual . id then
map [ variable ] = T . constOp ( "conflict" , { prior , actual } )
else
map [ variable ] = actual
end
end
elseif tag == "array" then
if arg . tag == "array" then
generics . unify ( param . elem , arg . elem , map )
elseif arg . tag == "tuple" then
for _ , e in ipairs ( arg . elems ) do
generics . unify ( param . elem , e , map )
end
end
elseif tag == "metatable" then



if arg . tag == "metatable" then
generics . unify ( param . of , arg . of , map )
elseif arg . tag == "typeobject" then
generics . unify ( param . of , arg . of , map )
end
elseif tag == "typeobject" then
if arg . tag == "typeobject" then
generics . unify ( param . of , arg . of , map )
end
elseif tag == "map" then
if arg . tag == "map" then
if param . readable and arg . readable then
generics . unify ( param . key , arg . key , map )
generics . unify ( param . value , arg . value , map )
end
if param . writeKey and param . writeValue and arg . writeKey and arg . writeValue then
generics . unify ( param . writeKey , arg . writeKey , map )
generics . unify ( param . writeValue , arg . writeValue , map )
end
end
elseif tag == "union" then



local tv = nil
local rest = { }
for _ , m in ipairs ( param . members ) do
if m . tag == "typevar" and not tv then
tv = m
else
rest [ # rest + 1 ] = m
end
end
if tv then
local residue = arg
for _ , r in ipairs ( rest ) do
residue = narrowing . subtract ( residue , r )
end
generics . unify ( tv , residue , map )
end
for _ , r in ipairs ( rest ) do
generics . unify ( r , arg , map )
end
elseif tag == "intersection" then


for _ , member in ipairs ( param . members ) do
generics . unify ( member , arg , map )
end
elseif tag == "shape" then
local staticOwner = arg . tag == "metatable" and arg . of and arg . of . tag == "nominal" and arg . of or nil
local reads = arg . tag == "shape" and arg . byname or (
arg . tag == "nominal" and arg . byname
) or staticOwner and staticOwner . staticByname
local writes = arg . tag == "shape" and arg . writeByname or (
arg . tag == "nominal" and arg . writeByname
) or staticOwner and staticOwner . staticWriteByname
if reads or writes then
for _ , f in ipairs ( param . fields ) do
local read = reads and reads [ f . name ]
local write = writes and writes [ f . name ]
if f . read and read then
generics . unify ( f . read , read , map )
end
if f . write and write then
generics . unify ( f . write , write , map )
end
end
end
elseif tag == "func" then
if arg . tag == "func" then
generics . unifyPack ( param . paramPack , arg . paramPack , map )
generics . unifyPack ( param . retPack , arg . retPack , map )
end
elseif tag == "nominal" then
if arg . tag == "nominal" then
local po = param . origin or param
local function view ( candidate , seen )
if seen [ candidate ] then
return nil
end
seen [ candidate ] = true
local candidateOrigin = candidate . origin or candidate
if candidateOrigin == po or candidateOrigin . id == po . id then
return candidate
end
for _ , parent in ipairs ( candidate . supertypes or { } ) do
if parent . tag == "nominal" then
local found = view ( parent , seen )
if found then
return found
end
end
end

return nil
end

local nominalArg = view ( arg , { } )
local ao = nominalArg and ( nominalArg . origin or nominalArg ) or arg . origin or arg




if po == ao or po . id == ao . id then
for j , p in ipairs ( param . typeArgs or { } ) do
local a = nominalArg and nominalArg . typeArgs and nominalArg . typeArgs [ j ]
if a then
generics . unify ( p , a , map )
end
end
for j , p in ipairs ( param . packArgs or { } ) do
local a = nominalArg and nominalArg . packArgs and nominalArg . packArgs [ j ]
if a then
generics . unifyPack ( p , a , map )
end
end
end
end
elseif tag == "ptr" then
if arg . tag == "ptr" then
generics . unify ( param . elem , arg . elem , map )
end
elseif tag == "carray" then
if arg . tag == "carray" then
generics . unify ( param . elem , arg . elem , map )
end
elseif tag == "ctype" then
if arg . tag == "ctype" then
generics . unify ( param . of , arg . of , map )
end
elseif tag == "const" then
if arg . tag == "const" then
generics . unify ( param . inner , arg . inner , map )
else
generics . unify ( param . inner , arg , map )
end
end
end















local selfMemoRoot = setmetatable ( { } , { __mode = "k" } )

local function selfMemo ( binder , target )
local byTarget = selfMemoRoot [ binder ]
if not byTarget then
byTarget = setmetatable ( { } , { __mode = "k" } )
selfMemoRoot [ binder ] = byTarget
end
local byMember = byTarget [ target ]
if not byMember then
byMember = setmetatable ( { } , { __mode = "k" } )
byTarget [ target ] = byMember
end

return byMember
end








function generics . specializeSelf ( owner , ft , receiver )
local binder = owner and owner . tag == "nominal" and ( owner ) . selfType or nil
if not binder then




return ft
end
local target = ( receiver or owner )
local cached = selfMemo ( binder , target ) [ ft ]
if cached then
return cached
end

local out
if ft . tag == "intersection" then
local members = { }
for j , member in ipairs ( ( ft ) . members ) do
members [ j ] = generics . specializeSelf ( owner , member , receiver )
end
out = T . intersection ( members )
else




out = generics . rebind ( ft , { [ binder ] = target } )
end
selfMemo ( binder , target ) [ ft ] = out

return out
end



function generics . specializeReceiver ( ft , receiver )
if ft . tag == "intersection" then
local members = { }
for j , member in ipairs ( ft . members ) do
members [ j ] = generics . specializeReceiver ( member , receiver )
end
return T . intersection ( members )
end
if ft . tag == "func" and # ft . params >= 1 and T . hasTypevar ( ft ) then
local receiverBindings = { }
generics . unify ( ft . params [ 1 ] , receiver , receiverBindings )
if next ( receiverBindings ) then
return generics . rebind ( ft , receiverBindings )
end
end

return ft
end






function generics . dropSelf ( ft )
if ft . tag == "intersection" then
local members = { }
for j , member in ipairs ( ft . members ) do
members [ j ] = generics . dropSelf ( member )
end
return T . intersection ( members )
end
if ft . tag == "func" and # ft . params >= 1 then
local params = { }
local modes = { }
local names = { }
for j = 2 , # ft . params do
params [ # params + 1 ] = ft . params [ j ]
end
for j = 2 , # ft . params do
modes [ # modes + 1 ] = ft . paramModes and ft . paramModes [ j ] or "plain"
names [ # names + 1 ] = ft . paramNames and ft . paramNames [ j ] or ""
end
local paramPack = T . pack ( params , ft . paramPack . tail , modes )
local preserves = { }
for result = 1 , # ft . rets do
local source = ft . preservesResults and ft . preservesResults [ result ]
if source and source > 1 then
preserves [ result ] = source - 1
end
end
local borrowsSelf = ft . borrowsSelf or ft . borrowsParam == 1
local borrowsParam = ft . borrowsParam and ft . borrowsParam > 1 and ft . borrowsParam - 1 or nil
local borrowsParams = { }
for _ , source in ipairs ( ft . borrowsParams or { } ) do
if source == 1 then
borrowsSelf = true
elseif source > 1 then
borrowsParams [ # borrowsParams + 1 ] = source - 1
end
end
return T . func (
params ,
ft . rets ,
ft . vararg ,
modes ,
nil ,
ft . typeParams ,
ft . typeBounds ,
borrowsParam ,
borrowsSelf ,
next ( borrowsParams ) and borrowsParams or nil ,
ft . ffiOut ,
ft . varargType ,
ft . noreturn ,
paramPack ,
ft . retPack ,
ft . packParams ,
ft . yieldPack ,
ft . resumePack ,

ft . noYield ,
names ,
next ( preserves ) and preserves or nil ,
ft . foreign ,
ft . constParams ,
ft . paramKinds ,
ft . partitionResults ,
ft . comptimeOnly ,
ft . explicitPreserves
)
end

return ft
end







function generics . addSelf ( ft , selfType , selfMode )
if ft . tag == "intersection" then
local members = { }
for j , member in ipairs ( ft . members ) do
members [ j ] = generics . addSelf ( member , selfType , selfMode )
end
return T . intersection ( members )
end
if ft . tag ~= "func" then
return ft
end
local params = { selfType }
local modes = { selfMode or "plain" }
local names = { "self" }
for _ , p in ipairs ( ft . params ) do
params [ # params + 1 ] = p
end
for _ , mode in ipairs ( ft . paramModes or { } ) do
modes [ # modes + 1 ] = mode
end
for _ , name in ipairs ( ft . paramNames or { } ) do
names [ # names + 1 ] = name
end
local paramPack = T . pack ( params , ft . paramPack . tail , modes )

return T . func (
params ,
ft . rets ,
ft . vararg ,
modes ,
ft . predicate ,
ft . typeParams ,
ft . typeBounds ,
ft . borrowsParam ,
ft . borrowsSelf ,
ft . borrowsParams ,
ft . ffiOut ,
ft . varargType ,
ft . noreturn ,
paramPack ,
ft . retPack ,
ft . packParams ,
ft . yieldPack ,
ft . resumePack ,
ft . noYield ,
names ,
( function ( )
local shifted = { }
for result = 1 , # ft . rets do
local source = ft . preservesResults and ft . preservesResults [ result ]
if source then
shifted [ result ] = source + 1
end
end

return next ( shifted ) and shifted or nil
end ) ( ) ,
ft . foreign ,
ft . constParams ,
ft . paramKinds ,
ft . partitionResults ,
ft . comptimeOnly ,
ft . explicitPreserves
)
end

return generics
