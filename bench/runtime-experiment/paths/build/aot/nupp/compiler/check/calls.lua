_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local T = require ( "nupp.compiler.types" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local members = require ( "nupp.compiler.types.members" )
local relations = require ( "nupp.compiler.types.relations" )
local generics = require ( "nupp.compiler.types.generics" )
local fixedWidth = require ( "nupp.compiler.types.fixedwidth" )
local indexedViews = require ( "nupp.compiler.types.indexedviews" )
local cst = require ( "nupp.compiler.syntax.cst" )
local state = require ( "nupp.compiler.check.state" )

local calls = { }

local isA = relations . isA
local rawType = T . unwrapOwnership
















local function substType ( t , map , erased , control ) 
local found = generics . evaluate ( generics . materialize ( t , map ) , nil , control )
if erased then
for _ , name in ipairs ( found . gradual ) do
erased [ # erased + 1 ] = name
end
end

return found . type
end






local function reportGradualProjections ( c , site , erased ) 
local seen = { }
for _ , name in ipairs ( erased ) do
if not seen [ name ] then
seen [ name ] = true
c . diag (
"NUPP2511" ,
site ,
("%q is an associated type, and inference did not reach what answers it") : format ( name ) ,
nil ,
{
help = "the call is checked as `any` there; annotate the argument, or pass a value whose declaration answers it"

}
)
end
end
end

local substPack = generics . materializePack
local unify = generics . unify
local unifyPack = generics . unifyPack
local instantiateNominal = generics . instantiate
local specializeSelf = generics . specializeSelf
local dropSelf = generics . dropSelf




local function constructorResult ( result , instance ) 
if result and result . tag == "affine" then
return T . affine ( instance , result . cleanups , result . transferOnly , result . obligation )
end

return instance
end




local function callableMembers ( t ) 
if t . tag ~= "intersection" then
return nil
end
local members = { }
for _ , member in ipairs ( t . members ) do
if member . tag ~= "func" then
return nil
end
members [ # members + 1 ] = member
end

return members
end







local function isPluckPath ( node ) 
if not node then
return false
end
if node . kind == "name" then
return true
end

return node . kind == "dotIndex" and isPluckPath ( node . obj )
end






local function binderInScope ( c , expected ) 
local wanted = T . unwrapOwnership ( expected )
if wanted . tag ~= "typevar" then
return true
end
local visible = c . lookupType ( ( wanted ) . name )

return visible ~= nil and ( visible == wanted or visible . id == wanted . id )
end

local function retainEnclosingBinders (
c ,
pack ,
introduced ,
map
) 
for binder in pairs ( generics . bindersInPack ( pack ) ) do
if binder . tag == "typevar" and not introduced [ binder ] and binderInScope ( c , binder ) then
map [ binder ] = binder
end
end
end





local function slotBinders ( signature ) 
local found = { }
local walk

local function walkPack ( pack , inSlot ) 
if not pack then
return
end
for _ , member in ipairs ( pack . head or { } ) do
walk ( member , inSlot )
end
local tail = pack . tail
if tail then
if tail . kind == "computed" then

if tail . type then
walk ( tail . type , "opaque" )
end
if tail . term then
walk ( tail . term , "opaque" )
end
elseif tail . type then
walk ( tail . type , inSlot )
end
end
for _ , arm in ipairs ( pack . alternatives or { } ) do
walkPack ( arm , inSlot )
end
end

walk = function ( t , inSlot ) 
if type ( t ) ~= "table" or not t . tag then
return
end
local tag = t . tag
if tag == "typevar" then
if inSlot == "opaque" then
found [ t ] = false
elseif inSlot == true and found [ t ] == nil then
found [ t ] = true
end
elseif tag == "nominal" then
for _ , argument in ipairs ( t . typeArgs or { } ) do
walk ( argument , inSlot == "opaque" and inSlot or true )
end
for _ , argument in ipairs ( t . packArgs or { } ) do
walkPack ( argument , inSlot == "opaque" and inSlot or true )
end
elseif tag == "array" then
walk ( t . elem , inSlot == "opaque" and inSlot or true )
elseif tag == "map" then
walk ( t . key , inSlot == "opaque" and inSlot or true )
walk ( t . value , inSlot == "opaque" and inSlot or true )
walk ( t . writeKey , inSlot == "opaque" and inSlot or true )
walk ( t . writeValue , inSlot == "opaque" and inSlot or true )
elseif tag == "shape" then
for _ , field in ipairs ( t . fields or { } ) do
walk ( field . read , inSlot == "opaque" and inSlot or true )
walk ( field . write , inSlot == "opaque" and inSlot or true )
end
elseif tag == "tuple" then
for _ , member in ipairs ( t . elems or { } ) do
walk ( member , inSlot )
end
elseif tag == "union" or tag == "intersection" then
for _ , member in ipairs ( t . members or { } ) do
walk ( member , inSlot )
end
elseif tag == "affine" or tag == "borrowed" or tag == "pinned" or tag == "const" then
walk ( t . inner , inSlot )
elseif tag == "func" then
walkPack ( t . paramPack , inSlot )
walkPack ( t . retPack , inSlot )
elseif tag == "ptr" or tag == "carray" then
walk ( t . elem , inSlot )
elseif tag == "ctype" or tag == "metatable" or tag == "typeobject" then
walk ( t . of , inSlot )
elseif tag == "neutral" or tag == "projection" or tag == "typeHandle" or tag == "packResult" then


for _ , child in pairs ( t ) do
if type ( child ) == "table" then
if child . tag then
walk ( child , "opaque" )
else
for _ , grandchild in pairs ( child ) do
walk ( grandchild , "opaque" )
end
end
end
end
end
end
walkPack ( signature . paramPack , false )
walkPack ( signature . retPack , false )

return found
end



local function widenedLiteral ( t ) 
if t . tag == "literal" then
return t . base or T . string
elseif t . tag == "union" then
local members , changed = { } , false
for j , member in ipairs ( t . members ) do
if member . tag == "literal" then
members [ j ] , changed = member . base or T . string , true
else
members [ j ] = member
end
end
if changed then
return T . union ( members )
end
end

return nil
end





local function widenLiteralBindings ( map , only ) 
for tv , bound in pairs ( map ) do
if tv . tag == "typevar" and ( only == nil or only [ tv ] ) then
local widened = widenedLiteral ( bound )
local declared = ( tv ) . bound
if widened and ( not declared or isA ( widened , declared ) ) then
map [ tv ] = widened
end
end
end
end










local function widenedArgument ( param , actual , slots ) 
local binder = T . unwrapOwnership ( param )
if binder . tag ~= "typevar" or slots [ binder ] ~= true then
return actual
end
local widened = widenedLiteral ( actual )
if not widened then
return actual
end
local declared = ( binder ) . bound
if declared and not isA ( widened , declared ) then
return actual
end

return widened
end

local function constInferenceProblem ( ft , map ) 
for _ , cv in ipairs ( ft . constParams or { } ) do
local value = map [ cv ]
if not value then
return ("const parameter %s cannot be inferred from a runtime value") : format ( cv . name )
end
if value . tag == "constOp" and value . operation == "conflict" then
return ("conflicting const inferences for %s") : format ( cv . name )
end
local domain = value . domain
if domain and domain ~= cv . domain then
return ("const parameter %s requires %s, got %s") : format ( cv . name , cv . domain , domain )
end
end

return nil
end

local function probeArm ( ft , argPack , cdefCall , control ) 
local map = { }
if T . hasTypevar ( ft )
and ( # ( ft . typeParams or { } ) > 0 or # ( ft . packParams or { } ) > 0 or # ( ft . constParams or { } ) > 0 )
then
unifyPack ( ft . paramPack , argPack , map )
local constProblem = constInferenceProblem ( ft , map )
if constProblem then
return nil , constProblem
end
for j , tv in ipairs ( ft . typeParams or { } ) do
local bound = ft . typeBounds and ft . typeBounds [ j ]
local actual = map [ tv ]
if bound and actual then
local expected = substType ( bound , map )
local ok , why = isA ( actual , expected )
if not ok then
return nil , ("generic bound for %s: %s") : format ( tv . name , why or "not satisfied" )
end
end
end
end
local specialized , specializationProblem = ft , nil
if # ( ft . typeParams or { } ) > 0
or # ( ft . packParams or { } ) > 0
or # ( ft . constParams or { } ) > 0
or ( ft . paramPack . tail and ft . paramPack . tail . kind == "computed" )
or ( ft . retPack . tail and ft . retPack . tail . kind == "computed" )
then
specialized , specializationProblem = generics . instantiateFunction ( ft , map , control )
end
if specializationProblem then
return nil , specializationProblem
end
local params = specialized . paramPack
local actualCount = # argPack . head
if not argPack . tail and actualCount > # params . head and not params . tail then
return nil , ("too many arguments (expected %d, got %d)") : format ( # params . head , actualCount )
end
for j = 1 , math . min ( actualCount , # params . head ) do
local actual = argPack . head [ j ]
if cdefCall and actual . tag == "pinned" then
actual = rawType ( actual )
end
local mode = specialized . paramModes and specialized . paramModes [ j ] or "plain"
if mode == "scoped" and ( actual . tag == "affine" or actual . tag == "pinned" ) then
return nil , ("argument %d cannot borrow an affine value as a repeatable callback") : format ( j )
end
local ok , why = isA ( actual , params . head [ j ] )
if not ok then
return nil , ("argument %d: %s") : format ( j , why or "mismatch" )
end
end
if not argPack . tail and actualCount < # params . head then
for j = actualCount + 1 , # params . head do
local ok = isA ( T . nil_ , params . head [ j ] )
if not ok then
return nil , ("omitted argument %d supplies nil, not %s") : format ( j , T . tostring ( params . head [ j ] ) )
end
end
end
local tail = params . tail
if tail and tail . kind == "homogeneous" then
for j = # params . head + 1 , actualCount do
local mode = tail . mode
local actual = argPack . head [ j ]
if mode == "scoped" and ( actual . tag == "affine" or actual . tag == "pinned" ) then
return nil , ("argument %d cannot borrow an affine value as a repeatable callback") : format ( j )
end
local ok , why = isA ( argPack . head [ j ] , tail . type )
if not ok then
return nil , ("argument %d in pack tail: %s") : format ( j , why or "mismatch" )
end
end
if argPack . tail and argPack . tail . kind == "homogeneous" then
local ok , why = isA ( argPack . tail . type , tail . type )
if not ok then
return nil , "pack tail: " .. ( why or "mismatch" )
end
end
elseif not tail and argPack . tail and argPack . tail . kind == "homogeneous" then
return nil , "an expanding argument tail may supply surplus values"
end

return specialized
end

local function probeSignature ( ft , argPack , cdefCall , control ) 
if not argPack . alternatives then
return probeArm ( ft , argPack , cdefCall , control )
end
local selected = nil
for armIndex , arm in ipairs ( argPack . alternatives ) do
local specialized , why = probeArm ( ft , arm , cdefCall , control )
if not specialized then
return nil , ("argument-pack alternative %d: %s") : format ( armIndex , why or "mismatch" )
end
if selected and selected . id ~= specialized . id then
return nil , "argument-pack alternatives require different generic specializations"
end
selected = specialized
end

return selected or ft
end

local function signaturesText ( signatures ) 
local parts = { }
for j , signature in ipairs ( signatures ) do
parts [ j ] = T . tostring ( signature )
end

return table . concat ( parts , "; " )
end



























function calls . install ( c ) 
local ops = { }





local function callDetails ( node ) 
local callee = node and node . obj
local token = callee and ( callee . token or callee . name )
local definition = token and token . definition
local related = definition and c . related ( definition , "called function is declared here" ) or nil

return { related = related and { related } or nil , help = "compare the call with the declared parameter list" }
end






local function reborrowsExclusiveView ( expr , root ) 
local found , valid = false , true

local function visit ( node ) 
while node and ( node . kind == "paren" or node . kind == "castExpr" or node . kind == "newExpr" ) do
node = node . kind == "newExpr" and node . call or node . expr
end
if not node or cst . isToken ( node ) then
return
end
if node . kind == "name" then
local entry = c . ownershipState ( ( c . ownershipEntry ( node ) ) )
if entry and c . borrowRoot ( entry ) == root then
found = true
local facts = c . own . capabilityFacts ( entry , nil , false )
if not facts . exclusive or ( entry . activeBorrows or 0 ) > 0 then
valid = false
end
end
return
elseif node . kind == "dotIndex"
or node . kind == "safeIndex"
or node . kind == "bracketIndex"
or node . kind == "safeBracket"
then
visit ( node . obj )
return
elseif node . kind == "binop" then
visit ( node . lhs )
visit ( node . rhs )
return
elseif node . kind == "tableExpr" then
for _ , field in ipairs ( node . fields or { } ) do
visit ( field . value )
end
return
elseif node . kind == "call" and node . recordConstruct then
for _ , binding in ipairs ( node . recordFields or { } ) do
visit ( binding . node )
end
return
end

local facts = c . own . capabilityFacts ( node , nil , false )
for _ , owner in ipairs ( facts . roots or { } ) do
if c . borrowRoot ( owner ) == root then
found = true
local origin = c . ownershipState ( facts . origin )
if not facts . exclusive or origin and ( origin . activeBorrows or 0 ) > 0 then
valid = false
end
end
end
end

visit ( expr )

return found and valid
end







local function tableConstructionFix ( tbl ) 
local open , close , trailing = nil , nil , nil
local separators = { }
for _ , entry in ipairs ( tbl ) do
if cst . isToken ( entry ) then
if entry . kind == "{" then
open = open or entry
elseif entry . kind == "}" then
close = entry
elseif entry . kind == "," or entry . kind == ";" then
separators [ # separators + 1 ] = entry
trailing = entry
end
else
trailing = nil
if entry . kind == "fieldBracket" or entry . isConst then
return nil
end
end
end
if not open or not close then
return nil
end




local gapOffset = nil
for index = 1 , open . triviaCount do
local kind , text , offset = lexer . triviaFields ( open , index )
if kind ~= "whitespace" or text : find ( "\n" , 1 , true ) then
gapOffset = nil
do break end
end
gapOffset = gapOffset or offset
end
local opening = gapOffset and { offset = gapOffset , length = open . offset + # open . text - gapOffset , newText = "(" }
or c . edits . replaceToken ( open , "(" )
local edits = { opening , c . edits . replaceToken ( close , ")" ) }
for _ , separator in ipairs ( separators ) do



if separator == trailing then
edits [ # edits + 1 ] = { offset = separator . offset , length = # separator . text , newText = "" }
elseif separator . kind == ";" then
edits [ # edits + 1 ] = c . edits . replaceToken ( separator , "," )
end
end

return { { title = "build it from arguments" , edits = edits } }
end





c . fieldType = function ( t , name ) 
t = rawType ( t )
if t . tag == "ptr" then
return c . fieldType ( t . elem , name )
end


if t . tag == "metatable" or t . tag == "typeobject" then
local owner = rawType ( t . of )
if owner . tag == "nominal" then
local ft = owner . staticByname and owner . staticByname [ name ]
local definition = owner . staticFieldDefs and owner . staticFieldDefs [ name ]
if not ft then
ft = owner . byname and owner . byname [ name ]
definition = owner . fieldDefs and owner . fieldDefs [ name ]
end



if t . tag == "typeobject" and name == "reflect" and not ft then
owner . runtimeReflectionNeeded = true
return T . func ( { } , { T . any } , false )
end
return ft and specializeSelf ( owner , ft , owner ) or nil , definition
end
return c . fieldType ( owner , name )
end


if t . tag == "literal" then
return c . fieldType ( t . base , name )
end
if t . tag == "projection" then




local found = generics . evaluate ( t )
if found . type ~= t then
return c . fieldType ( found . type , name )
end
local associated = require ( "nupp.compiler.types.associated" )
local bound = associated . lookup ( ( t ) . of , ( t ) . name ) . bound
if not bound then
return nil
end



local entry = members . lookup ( bound , name )
if not entry or not entry . readType then
return nil
end

return specializeSelf ( bound , entry . readType , t ) , entry . definition , entry . definitions
end

if t == T . string and c . env and c . env . stringLib and c . env . stringLib . tag == "shape" then

return c . env . stringLib . byname [ name ]
end

local entry = members . lookup ( t , name )
if entry and entry . readType then
local ft = entry . readType
if t . tag == "nominal" then
ft = specializeSelf ( t , ft , t )
elseif t . tag == "typevar" and t . bound and t . bound . tag == "nominal" then
ft = specializeSelf ( t . bound , ft , t )
end



local owner = t . tag == "nominal" and t or t . tag == "typevar" and t . bound or nil
if owner
and owner . tag == "nominal"
and owner . declKind == "struct"
and owner . fieldDefs
and owner . fieldDefs [ name ]
then
ft = fixedWidth . loaded ( ft )
end
local element = owner and indexedViews . spanElement ( owner ) or nil
if element and name == "get" then
ft = T . withFirstResult ( ft , fixedWidth . loaded ( element ) )
end
return ft , entry . definition , entry . definitions
end


local indexer = members . view ( t ) . readIndexer
if indexer and isA ( T . literal ( name , T . string ) , indexer . keyType ) then
return T . optional ( indexer . valueType )
end

return nil
end

c . fieldWriteType = function ( t , name ) 
t = rawType ( t )
if t . tag == "ptr" then
return c . fieldWriteType ( t . elem , name )
end
if t . tag == "projection" then




local found = generics . evaluate ( t )
if found . type ~= t then
return c . fieldWriteType ( found . type , name )
end
local associated = require ( "nupp.compiler.types.associated" )
local bound = associated . lookup ( ( t ) . of , ( t ) . name ) . bound
if not bound then
return nil
end




local entry = members . lookup ( bound , name )
if not entry or not entry . writeType then
return nil
end

return specializeSelf ( bound , entry . writeType , t ) , entry . definition , entry . definitions
end

if t . tag == "metatable" or t . tag == "typeobject" then
local owner = rawType ( t . of )
if owner . tag == "nominal" then
local ft = owner . staticWriteByname and owner . staticWriteByname [ name ]
local definition = owner . staticWriteFieldDefs and owner . staticWriteFieldDefs [ name ]
if not ft then
ft = owner . writeByname and owner . writeByname [ name ]
definition = owner . writeFieldDefs and owner . writeFieldDefs [ name ]
end
return ft and specializeSelf ( owner , ft , owner ) or nil , definition
end
return c . fieldWriteType ( owner , name )
end
local entry = members . lookup ( t , name )
if entry and entry . writeType then
local ft = entry . writeType
if t . tag == "nominal" then
ft = specializeSelf ( t , ft , t )
elseif t . tag == "typevar" and t . bound and t . bound . tag == "nominal" then
ft = specializeSelf ( t . bound , ft , t )
end
return ft , entry . definition , entry . definitions
end

local indexer = members . view ( t ) . writeIndexer
if indexer and isA ( T . literal ( name , T . string ) , indexer . keyType ) then
return indexer . valueType
end

return nil
end

c . fieldNames = function ( t , writing ) 
t = rawType ( t )
if t . tag == "ptr" then
return c . fieldNames ( t . elem , writing )
end
if t . tag == "metatable" then
local owner = rawType ( t . of )
local names = c . fieldNames ( owner , writing )
if owner . tag == "nominal" then
local statics = writing and owner . staticWriteByname or owner . staticByname
for name in pairs ( statics or { } ) do
names [ name ] = true
end
end
return names
end
local names = { }
local surface = members . view ( t )
for _ , entry in ipairs ( surface . ordered ) do
if writing and entry . writeType or not writing and entry . readType then
names [ entry . name ] = true
end
end
if t == T . string and c . env and c . env . stringLib and c . env . stringLib . tag == "shape" then
for name in pairs ( c . env . stringLib . byname ) do
names [ name ] = true
end
end

return names
end



c . metamethodNames = function ( t ) 
t = rawType ( t )
if t . tag == "ptr" then
return c . metamethodNames ( t . elem )
end
if t . tag == "typevar" and t . bound then
return c . metamethodNames ( t . bound )
end
if t . tag == "metatable" then
return c . metamethodNames ( t . of )
end
if t . tag == "intersection" then
local names = { }
for _ , member in ipairs ( t . members ) do
for name in pairs ( c . metamethodNames ( member ) ) do
names [ name ] = true
end
end
return names
end
local names = { }
if t . tag == "nominal" then
for name in pairs ( t . metamethods or { } ) do
names [ name ] = true
end
end

return names
end







local function metamethodAs ( bound , name , receiver ) 
if bound . tag == "nominal" then
local ft = bound . metamethods and bound . metamethods [ name ]
return ft and specializeSelf ( bound , ft , receiver ) or nil
end
if bound . tag == "intersection" then
local contracts = { }
for _ , member in ipairs ( bound . members ) do
local ft = metamethodAs ( member , name , receiver )
if ft then
contracts [ # contracts + 1 ] = ft
end
end
return # contracts > 0 and T . intersection ( contracts ) or nil
end

return ops . metamethodOf ( bound , name )
end

function ops . metamethodOf ( t , name ) 
t = rawType ( t )


if t . tag == "metatable" or t . tag == "typeobject" then
return ops . metamethodOf ( t . of , name )
end
if t . tag == "typevar" and t . bound then
return metamethodAs ( t . bound , name , t )
end
if t . tag == "intersection" then
local contracts = { }
for _ , member in ipairs ( t . members ) do
local ft = ops . metamethodOf ( member , name )
if ft then
contracts [ # contracts + 1 ] = ft
end
end
return # contracts > 0 and T . intersection ( contracts ) or nil
end
if t . tag == "nominal" and t . metamethods then




local ft = t . metamethods [ name ]
return ft and specializeSelf ( t , ft , generics . ownInstance ( t ) ) or nil
end

return nil
end








local function boundHelp ( wanted , actual ) 
if wanted . tag ~= "func" or actual . tag ~= "func" then
return nil
end
if not ( wanted ) . sendable or ( actual ) . sendable then
return nil
end

return "pass a function a module exports, with the values it would have captured as arguments"
end

local function satisfiesBound ( actual , wanted ) 
if actual . tag == "func" and wanted . tag == "func" then
local have , want = actual , wanted
local pack = want . retPack
if not pack . alternatives and not have . retPack . alternatives then




local head = { }
local changed = false
for index , result in ipairs ( pack . head ) do
local value = T . packAt ( have . retPack , index )
if value and ( result == T . any or result == T . unknown ) then
head [ index ] , changed = value , true
else
head [ index ] = result
end
end
local tail = pack . tail
if tail and tail . kind == "homogeneous" and ( tail . type == T . any or tail . type == T . unknown ) then
for index = # head + 1 , # have . retPack . head do
head [ index ] = have . retPack . head [ index ]
end
tail , changed = have . retPack . tail , true
end
if changed then
wanted = T . funcWith ( want , { rets = head , retPack = T . pack ( head , tail , pack . modes ) } )
end
end
end

return isA ( actual , wanted )
end

function ops . validateTypeBounds ( params , bounds , map , node ) 



for _ , tv in ipairs ( params or { } ) do
local default = ( tv ) . default
if map [ tv ] == nil and default then
map [ tv ] = substType ( default , map , nil , c . reductionControl )
end
end
for j , tv in ipairs ( params or { } ) do
local bound = bounds and bounds [ j ]
local actual = map [ tv ]
if bound and actual and actual ~= T . any then
local wanted = substType ( bound , map , nil , c . reductionControl )
local ok , why
local binder = T . unwrapOwnership ( actual )
if actual ~= binder and T . hasCopyableBound ( wanted ) then
ok , why = isA ( actual , wanted )
elseif binder . tag == "typevar" then




local declared = ( binder ) . bound
if declared then
ok , why = satisfiesBound ( declared , wanted )
else
ok , why = false , ("%s declares no bound, so it is not known to be a %s")

: format ( T . tostring ( binder ) , T . tostring ( wanted ) )
end
else
ok , why = satisfiesBound ( actual , wanted )
end
if not ok then
c . diag (
"NUPP2116" ,
node ,
("type argument %s for %s: %s") : format ( T . tostring ( actual ) , tv . name , why ) ,
nil ,
{ help = boundHelp ( wanted , actual ) }
)
end
end
end
end

local function seedWrittenTypeArguments ( node , params , map ) 
local written = node . typeArgs or { }
if # written == 0 then
return
end
local declared = # ( params or { } )
if # written > declared then
node . invalidTypeArguments = true
c . diag ( "NUPP2007" , node , ("too many type arguments (expected %d, got %d)") : format ( declared , # written ) )
return
end
for j , binder in ipairs ( params or { } ) do
local argument = written [ j ]
if argument then
map [ binder ] = c . resolveType ( argument )
end
end
end





local function settledArgumentType ( node ) 
if node == nil or cst . isToken ( node ) then
return nil
end
local kind = node . kind
if kind == "number" or kind == "string" or kind == "trueExpr" or kind == "falseExpr" then
return c . infer ( node )
end
if isPluckPath ( node ) then
return c . refType ( node )
end

return nil
end



local function quietTypeArguments ( node , params , map ) 
local written = node . typeArgs or { }
if # written == 0 or # written > # ( params or { } ) then
return
end
local before = # c . diags
for j , binder in ipairs ( params or { } ) do
if written [ j ] then
map [ binder ] = c . resolveType ( written [ j ] )
end
end
for j = # c . diags , before + 1 , -1 do
c . diags [ j ] = nil
end
end








local function slotDestination (
node ,
signature ,
index ,
argumentAt ,
count
) 
local function slot ( j ) 
local param = signature . params [ j ]
if param ~= nil then
return param
end
local tail = signature . paramPack and signature . paramPack . tail or nil
if tail and tail . kind == "homogeneous" and signature . varargType then
return signature . varargType
end

return nil
end

local wanted = slot ( index )
if wanted == nil then
return nil
end
local binders = { }
for _ , binder in ipairs ( signature . typeParams or { } ) do
binders [ # binders + 1 ] = binder
end
for _ , binder in ipairs ( signature . packParams or { } ) do
binders [ # binders + 1 ] = binder
end
for _ , binder in ipairs ( signature . constParams or { } ) do
binders [ # binders + 1 ] = binder
end
if # binders == 0 then
return wanted
end
local mentioned = generics . bindersInPack ( T . pack ( { wanted } ) )
local open = false
for _ , binder in ipairs ( binders ) do
open = open or mentioned [ binder ] == true
end
if not open then
return wanted
end
local map = { }
quietTypeArguments ( node , signature . typeParams , map )
local slots = slotBinders ( signature )
for j = 1 , count do
local param = j ~= index and slot ( j ) or nil
local actual = param and argumentAt ( j ) or nil
if param and actual then
unify ( param , widenedArgument ( param , actual , slots ) , map )
end
end
for _ , binder in ipairs ( binders ) do
if mentioned [ binder ] and map [ binder ] == nil then
return nil
end
end

return generics . rebind ( wanted , map )
end





local function argumentDestinations ( node , candidates , args ) 
return function ( index , head ) 
local function argumentAt ( j ) 
if j < index then
return head [ j ]
end

return settledArgumentType ( args [ j ] )
end

local agreed = nil
for k , candidate in ipairs ( candidates ) do
local destination = slotDestination ( node , candidate , index , argumentAt , # args )
if destination == nil then
return nil
end
if k > 1 and agreed ~= nil and destination ~= agreed and destination . id ~= agreed . id then
return nil
end
agreed = destination
end

return agreed
end
end

local function callName ( node , fallback ) 
if node . kind == "methodCall" and node . name then
return node . name . text
end

return c . pathKey ( node . obj ) or fallback or "this call"
end

local function reportUninferred (
node ,
name ,
typeParams ,
packParams ,
map ,
resultPack
) 
if node . invalidTypeArguments then
return
end
local resultBinders = generics . bindersInPack ( resultPack )

local function report ( binder , kind ) 
if map [ binder ] == nil and not generics . wasGradual ( map , binder ) and resultBinders [ binder ] then
c . diag (
"NUPP2148" ,
node ,
("%s parameter %s cannot be inferred for %s") : format ( kind , binder . name , name ) ,
nil ,
{ help = ("write %s<%s>(...) to supply it explicitly") : format ( name , binder . name ) }
)
end
end

for _ , binder in ipairs ( typeParams or { } ) do
if ( binder ) . default == nil then
report ( binder , "type" )
end
end
for _ , binder in ipairs ( packParams or { } ) do
report ( binder , "type-pack" )
end
end




local function modePreference ( ft , pack ) 
local score = 0
for position , actual in ipairs ( pack . head ) do
local mode = ft . paramModes and ft . paramModes [ position ] or "plain"
local kind = c . ownershipKind ( actual )
if mode == "scoped" and kind ~= "affine" and kind ~= "pinned" then
score = score + 1
elseif mode == "takes" and ( kind == "affine" or kind == "pinned" ) then
score = score + 1
end
end

return score
end

local function retainPreferredModes ( survivors , originals , choices , packs ) 
if # survivors < 2 then
return survivors , originals , choices
end
local scores , best = { } , 0
for position , candidate in ipairs ( survivors ) do
scores [ position ] = modePreference ( candidate , packs [ position ] )
best = math . max ( best , scores [ position ] )
end
if best == 0 then
return survivors , originals , choices
end
local preferred , preferredOriginals , preferredChoices = { } , { } , { }
for position , score in ipairs ( scores ) do
if score == best then
preferred [ # preferred + 1 ] = survivors [ position ]
preferredOriginals [ # preferredOriginals + 1 ] = originals [ position ]
if choices then
preferredChoices [ # preferredChoices + 1 ] = choices [ position ]
end
end
end

return preferred , preferredOriginals , choices and preferredChoices or nil
end








local function selectOverload ( overloads , probe , site , operation , preferencePack , details ) 
local survivors = { }
local originals = { }
local choices = { }
local rejections = { }
for _ , candidate in ipairs ( overloads ) do
local specialized , choice , why = probe ( candidate )
if specialized then
survivors [ # survivors + 1 ] = specialized
originals [ # originals + 1 ] = candidate
choices [ # choices + 1 ] = choice or false
else
rejections [ # rejections + 1 ] = T . tostring ( candidate ) .. ": " .. ( why or "rejected" )
end
end
if preferencePack or choices [ 1 ] then
local packs = { }
for position , choice in ipairs ( choices ) do
packs [ position ] = choice and choice . pack or preferencePack
end
survivors , originals , choices = retainPreferredModes ( survivors , originals , choices , packs )
end
local named = operation and operation .. " " or ""
if # survivors == 0 then
c . diag (
"NUPP2125" ,
site ,
("no %soverload accepts this call: %s") : format ( named , table . concat ( rejections , "; " ) ) ,
nil ,
details
)
return nil
elseif # survivors > 1 then
c . diag (
"NUPP2126" ,
site ,
("several %soverloads accept this call: %s") : format ( named , signaturesText ( survivors ) ) ,
nil ,
details
)
return nil
end

return survivors [ 1 ] , originals [ 1 ] , choices [ 1 ] or nil
end







function ops . applyContract ( ft , ats , argNodes , site , operation ) 



site . effectUnknownOperation = true


local regionCandidate = c . nosuspend and c . nosuspend . contract and c . nosuspend . contract ( site , operation ) or nil
local overloads = ft and callableMembers ( ft ) or nil
if overloads then
local argPack = T . pack ( ats )
local winner = selectOverload (
overloads ,
function ( candidate ) 
local specialized , why = probeSignature ( candidate , argPack , nil , c . reductionControl )
return specialized , nil , why
end ,
site ,
operation ,
nil ,
nil
)
if not winner then
return T . any
end
ft = winner
end
if not ft or ft . tag ~= "func" then
c . diag ( "NUPP2003" , site , operation .. " contract is not a function" )
return T . any
end
if regionCandidate then
regionCandidate . calleeType = ft
end
local params , rets = ft . params , ft . rets
local paramPack , retPack = ft . paramPack , ft . retPack
local varargType = ft . varargType
if T . hasTypevar ( ft ) then
local map = { }
for j = 1 , math . min ( # ats , # params ) do
unify ( params [ j ] , ats [ j ] , map )
end
if varargType then
for j = # params + 1 , # ats do
unify ( varargType , ats [ j ] , map )
end
end
ops . validateTypeBounds ( ft . typeParams , ft . typeBounds , map , site )
local p2 , r2 = { } , { }
local erasedProjections = { }
for j , p in ipairs ( params ) do
p2 [ j ] = substType ( p , map , erasedProjections , c . reductionControl )
end
for j , r in ipairs ( rets ) do
r2 [ j ] = substType ( r , map , erasedProjections , c . reductionControl )
end
params , rets = p2 , r2
paramPack , retPack = substPack ( paramPack , map ) , substPack ( retPack , map )
if varargType then
varargType = substType ( varargType , map , erasedProjections , c . reductionControl )
end
reportGradualProjections ( c , site , erasedProjections )
end
local packProblem
paramPack , packProblem = generics . expandComputedPack ( paramPack , c . reductionControl )
if not packProblem then
retPack , packProblem = generics . expandComputedPack ( retPack , c . reductionControl )
end
if packProblem then
c . diag ( "NUPP2006" , site , operation .. " contract: " .. packProblem )
return T . any
end
params , rets = paramPack . head , retPack . head
if paramPack . tail and paramPack . tail . kind == "homogeneous" then
varargType = paramPack . tail . type
end
if varargType then
for j = # params + 1 , # ats do
local ok , why = isA ( ats [ j ] , varargType )
if not ok then
c . diag ( "NUPP2006" , argNodes [ j ] or site , ("%s argument %d: %s") : format ( operation , j , why ) )
end
end
end
if # ats > # params and not paramPack . tail then
c . diag ( "NUPP2007" , site , ("%s takes %d arguments, got %d") : format ( operation , # params , # ats ) )
end
for j = 1 , math . min ( # ats , # params ) do
local ok , why = isA ( ats [ j ] , params [ j ] )
if not ok then
c . diag ( "NUPP2006" , argNodes [ j ] or site , ("%s argument %d: %s") : format ( operation , j , why ) )
end
end

return rets [ 1 ] or T . nil_
end






function ops . inferCall ( node , calleeT , argsNode , knownAts ) 
node . signatureType = calleeT
if calleeT . ffiOut and # calleeT . ffiOut > 0 then
node . ffiOutContracts = calleeT . ffiOut
end
local args = argsNode and argsNode . exprs or { }
if argsNode and argsNode . table then
args = { argsNode . table }
elseif argsNode and argsNode . str then
args = { argsNode . str }
end




if ( calleeT . tag == "metatable" or calleeT . tag == "typeobject" )
and calleeT . of . tag == "nominal"
and ( calleeT . of . declKind == "record" or calleeT . of . declKind == "struct" )
then
calleeT = calleeT . of
node . signatureType = calleeT
end

local constructible = calleeT . tag == "nominal"
and ( calleeT . declKind == "struct" or calleeT . declKind == "record" )



if node . isNew and not constructible and not node . newReported and calleeT ~= T . any then
local named = node . obj and c . pathKey ( node . obj )
c . diag (
"NUPP2206" ,
node . obj or node ,
("%s cannot be constructed") : format ( named or T . tostring ( calleeT ) ) ,
nil ,
{ help = "`new` builds a record or a struct" }
)
node . newReported = true
end




if constructible and not node . isNew then
if calleeT . declKind == "record" then
local callContract = ops . metamethodOf ( calleeT , "__call" )
if callContract then
return ops . inferCall ( node , dropSelf ( callContract ) , argsNode )
end
end
local named = c . pathKey ( node . obj ) or calleeT . name
c . diag ( "NUPP2202" , node , ("%s is constructed with `new`") : format ( named ) , nil , {
help = ("write new %s%s") : format ( named , ( argsNode and argsNode . table ) and "{...}" or "(...)" )
} )
for _ , arg in ipairs ( args ) do
if not cst . isToken ( arg ) then
c . infer ( arg )
end
end
return calleeT , { calleeT }
end
if constructible then
local affineValues = { }
local deferredAffineRoots


= { }
local tbl = nil
if argsNode and argsNode . table then
tbl = argsNode . table
elseif # args == 1 and not cst . isToken ( args [ 1 ] ) and args [ 1 ] . kind == "tableExpr" then
tbl = args [ 1 ]
end




local constructors = calleeT . constructors
if constructors and # constructors > 0 then
local named = c . pathKey ( node . obj ) or calleeT . name
if tbl then
c . diag (
"NUPP2208" ,
node ,
("%s declares a constructor, so it is built by calling it") : format ( named ) ,
nil ,
{ help = ("write new %s(...) with the constructor's arguments") : format ( named ) }
)



c . infer ( tbl )
return calleeT , { calleeT }
end
node . constructorCall = named




node . isNew = nil
local builtSignatures , bySignature = { } , { }
local entries = calleeT . constructorEntries or { }
local genericInstance = generics . ownInstance ( calleeT )
for index , signature in ipairs ( constructors ) do
local entry = entries [ index ]
local result = constructorResult ( entry and entry . result or nil , genericInstance )
local typeParams , typeBounds , anyBound = { } , { } , false



for j , tv in ipairs ( calleeT . typeParams or { } ) do
typeParams [ # typeParams + 1 ] = tv
local bound = calleeT . typeBounds and calleeT . typeBounds [ j ] or nil
typeBounds [ # typeParams ] = bound
anyBound = anyBound or bound ~= nil
end
for j , tv in ipairs ( signature . typeParams or { } ) do
typeParams [ # typeParams + 1 ] = tv
local bound = signature . typeBounds and signature . typeBounds [ j ] or nil
typeBounds [ # typeParams ] = bound
anyBound = anyBound or bound ~= nil
end
local built = T . func (
signature . params ,
{ result } ,
signature . vararg ,
signature . paramModes ,
nil ,
# typeParams > 0 and typeParams or nil ,
anyBound and typeBounds or nil ,
nil ,
nil ,
nil ,
nil ,
signature . varargType ,
nil ,
signature . paramPack ,
T . pack ( { result } ) ,
signature . packParams ,
signature . yieldPack ,
signature . resumePack ,
signature . noYield ,
signature . paramNames
)
builtSignatures [ # builtSignatures + 1 ] = built
bySignature [ built ] = entry or { index = index , signature = signature , result = calleeT }
end
local callable = T . intersection ( builtSignatures )
local first , rets , pack = ops . inferCall ( node , callable , argsNode )
local selected = node . overloadWinner or ( # builtSignatures == 1 and builtSignatures [ 1 ] or nil )
local entry = selected and bySignature [ selected ] or nil
if entry then
node . constructorIndex = entry . index
node . constructorEntry = entry
end
if entry and calleeT . typeParams and node . argumentPack then
local map = node . genericBindings or { }
if not node . genericBindings then
seedWrittenTypeArguments ( node , calleeT . typeParams , map )
unifyPack ( entry . signature . paramPack , node . argumentPack , map )
end
ops . validateTypeBounds ( calleeT . typeParams , calleeT . typeBounds , map , node )
local instance = instantiateNominal ( calleeT , map )
local declaredResult = entry . result and substType ( entry . result , map ) or nil
local result = constructorResult ( declaredResult , instance )
first , rets , pack = result , { result } , T . pack ( { result } )
if node . signatureType and node . signatureType . tag == "func" then
local selectedSignature = node . signatureType
node . signatureType = T . func (
selectedSignature . params ,
{ result } ,
selectedSignature . vararg ,
selectedSignature . paramModes ,
selectedSignature . predicate ,
nil ,
nil ,
selectedSignature . borrowsParam ,
selectedSignature . borrowsSelf ,
selectedSignature . borrowsParams ,
selectedSignature . ffiOut ,
selectedSignature . varargType ,
selectedSignature . noreturn ,
selectedSignature . paramPack ,
T . pack ( { result } ) ,
nil ,
selectedSignature . yieldPack ,
selectedSignature . resumePack ,
selectedSignature . noYield ,
selectedSignature . paramNames ,
selectedSignature . preservesResults ,
selectedSignature . foreign ,
selectedSignature . constParams ,
selectedSignature . paramKinds ,
selectedSignature . partitionResults ,
selectedSignature . comptimeOnly ,
selectedSignature . explicitPreserves
)
end
node . valuePack = pack
c . lastCallRets = rets
end
return first , rets , pack
end
local declared = c . pathKey ( node . obj ) or calleeT . name
local isRecord = calleeT . declKind == "record"



if tbl then
c . diag (
"NUPP2202" ,
node ,
("%s is constructed from arguments, not from a table") : format ( declared ) ,
tableConstructionFix ( tbl ) ,
{
help = isRecord and ("write new %s(field = value, ...)") : format ( declared )
or ("write new %s(...) with one value per field, in order") : format ( declared ) ,
}
)
c . infer ( tbl )
return calleeT , { calleeT }
end
local genericMap = calleeT . typeParams and { } or nil
local explicitFrozen = { }
local constructionFailed = false
if genericMap then
seedWrittenTypeArguments ( node , calleeT . typeParams , genericMap )
explicitFrozen = generics . fixBound ( genericMap )
end
local constructionFields = { }
if isRecord then

node . recordConstruct = declared
c . fixedWidth . trust ( node , calleeT )
end




local order = calleeT . fieldOrder or { }
local declaration = ( calleeT . origin or calleeT )
local privateFields = declaration . privateFields or { }
local outsidePrivate = declaration . moduleName ~= c . result . moduleName
local sealedConstruction = outsidePrivate and next ( privateFields ) ~= nil
if sealedConstruction then
c . diag (
"NUPP2209" ,
node ,
("record %s has fields private to module %q") : format ( calleeT . name , declaration . moduleName or "?" ) ,
nil ,
{ help = "use a public constructor declared by that module" }
)
end



local aggregateRoots , rootSeen = { } , { }

local function rootedIn ( value ) 
for _ , root in ipairs ( c . own . provenanceOwners ( value ) ) do
if not rootSeen [ root ] then
rootSeen [ root ] , aggregateRoots [ # aggregateRoots + 1 ] = true , root
end
end
end

local function finished ( resultType ) 
if # aggregateRoots > 0 then
c . own . capabilityFacts ( node ) . roots = aggregateRoots
if not c . ownershipKind ( resultType ) then
resultType = T . borrowed ( resultType )
end
end

return resultType , { resultType }
end

local bindings , bound = { } , { }




local function recordConstructionMove ( value ) 
while value and ( value . kind == "paren" or value . kind == "castExpr" or value . kind == "orExitExpr" ) do
value = value . kind == "orExitExpr" and value . operand or value . expr
end
local move = value and value . automaticOwnerMove or nil
if move then
node . constructionOwnerMoves = node . constructionOwnerMoves or { }
node . constructionOwnerMoves [ # node . constructionOwnerMoves + 1 ] = move
end
end





local ahead = nil

local function fieldsAhead ( ) 
if ahead ~= nil then
return ahead
end
local found = { }
ahead = found
if not genericMap then
return found
end
local position = 0
for _ , arg in ipairs ( args ) do
local fname , value = nil , nil
if not cst . isToken ( arg ) and arg . kind == "namedArg" then
fname , value = arg . name and arg . name . text or nil , arg . value
elseif not cst . isToken ( arg ) and arg . kind ~= "pluckArg" then
position = position + 1
fname , value = order [ position ] , arg
end
local declaredField = fname and ( calleeT . writeByname [ fname ] or calleeT . byname [ fname ] ) or nil
local actual = declaredField and settledArgumentType ( value ) or nil
if declaredField and actual then
unify ( specializeSelf ( calleeT , declaredField , generics . ownInstance ( calleeT ) ) , actual , found )
end
end

return found
end

local function bindField ( fname , value , site , label ) 
if not fname then
c . infer ( value )
return
end
if bound [ fname ] then
c . diag ( "NUPP2202" , site , ("field %q is filled twice") : format ( fname ) )
c . infer ( value )
return
end
local ft = calleeT . writeByname [ fname ] or calleeT . byname [ fname ]
if not ft then
c . diag ( "NUPP2202" , site , ("no field %q in %s %s") : format ( fname , calleeT . declKind , calleeT . name ) )
c . infer ( value )
return
end






ft = specializeSelf ( calleeT , ft , generics . ownInstance ( calleeT ) )
bound [ fname ] = true
bindings [ # bindings + 1 ] = { name = fname , node = value }







if value . kind == "call" or value . kind == "safeCall" then
local settled = true
local mentioned = generics . bindersInPack ( T . pack ( { ft } ) )
local known = nil
if genericMap then
known = { }
for binder , bound in pairs ( genericMap ) do
known [ binder ] = bound
end
end
for _ , binder in ipairs ( calleeT . typeParams or { } ) do
if mentioned [ binder ] and ( known == nil or known [ binder ] == nil ) then
local later = fieldsAhead ( ) [ binder ]
if later == nil or known == nil then
settled = false
else
known [ binder ] = later
end
end
end
for _ , binder in ipairs ( calleeT . packParams or { } ) do
settled = settled and not mentioned [ binder ]
end





value . expectedResult = settled and ( known and generics . rebind ( ft , known ) or ft ) or nil
end
local vt = c . infer ( value )
constructionFields [ fname ] = { node = value , type = vt }
local _ , regionPath = c . regionOf ( value )
if regionPath and regionPath ~= "" then
local suffix = T . regionLastPartition ( regionPath )
if suffix then
node . partitionFields = node . partitionFields or { }
node . partitionFields [ fname ] = suffix
end
end
local borrowedRoot = calleeT . borrowedRootFields and calleeT . borrowedRootFields [ fname ]
local fieldOwnership = T . containedOwnershipKind ( ft )
local storesCapability = fieldOwnership == "affine" or fieldOwnership == "pinned"
local suppliesBorrowedField = false
for _ , source in pairs ( calleeT . fieldBorrowSources or { } ) do
suppliesBorrowedField = suppliesBorrowedField or source == fname
end





local valueKind = c . ownershipKind ( vt )
local dependentField = calleeT . fieldBorrowSources and calleeT . fieldBorrowSources [ fname ] ~= nil
if c . own . carriesProvenance ( value , vt ) then
if storesCapability and valueKind ~= "affine" and valueKind ~= "pinned" then
c . diag ( "NUPP2603" , value , "borrowed value cannot fill an owning record field" , nil , {
help = "move an owner into the field, or declare it `borrows (sibling)` naming the field it borrows from" ,
} )
elseif not dependentField then
rootedIn ( value )
end
end
if storesCapability and ( c . ownershipKind ( vt ) == "affine" or c . ownershipKind ( vt ) == "pinned" ) then
affineValues [ fname ] = vt
if borrowedRoot then
deferredAffineRoots [ fname ] = { node = value , type = vt }
else
c . moveExpression ( value , vt , "affine record construction" , c . ownershipKind ( vt ) )
recordConstructionMove ( value )
end
end
if genericMap then
unify ( ft , vt , genericMap )
end
local expected = genericMap and substType ( ft , genericMap ) or ft
local valueOwnership = c . ownershipKind ( vt )
local expectedOwnership = T . containedOwnershipKind ( expected )



if ( valueOwnership == "affine" or valueOwnership == "pinned" )
and expected . tag ~= "typevar"
and not expectedOwnership
and not suppliesBorrowedField
then
local erased = expected == T . any or expected == T . unknown
c . diag (
erased and "NUPP2611" or "NUPP2603" ,
value ,
erased and "a live capability cannot be erased into an any field"
or "an ownership-bearing value needs an ownership-bearing record field"
)
end
local checked = borrowedRoot and not storesCapability and rawType ( vt ) or vt
if storesCapability then
checked = T . containedOwnershipPayload ( checked )
expected = T . containedOwnershipPayload ( expected )
end
local physical = calleeT . declKind == "struct" and "store" or false
local ok , why , reported = c . fixedWidth . fits ( checked , expected , value , physical )
if not ok and not reported then
c . diag ( "NUPP2202" , site , ("%s: %s") : format ( label , why ) )
end
end

local positional , byOrder , namedStarted = 0 , false , false
for _ , arg in ipairs ( args ) do
if cst . isToken ( arg ) then
c . diag ( "NUPP2202" , node , ("%s is constructed from arguments") : format ( declared ) )
elseif arg . kind == "namedArg" then
local fname = arg . name and arg . name . text or nil
namedStarted = true
if not isRecord then



c . diag (
"NUPP2202" ,
arg ,
("a struct is built in field order, so %s takes its values positionally") : format ( declared ) ,
nil ,
{ help = ("write new %s(...) with one value per field, in order") : format ( declared ) }
)
c . infer ( arg . value or arg )
else
if fname then
local fieldDef = calleeT . writeFieldDefs and calleeT . writeFieldDefs [ fname ]
or ( calleeT . fieldDefs and calleeT . fieldDefs [ fname ] or nil )
c . markToken (
arg . name ,
fieldDef ,
calleeT . writeByname [ fname ] or calleeT . byname [ fname ] ,
"property"
)
end
bindField ( fname , arg . value or arg , arg , ("field %q") : format ( fname or "?" ) )
end
elseif arg . kind == "pluckArg" then



c . diag (
"NUPP2202" ,
arg ,
"a construction fills fields, so there are no parameters to pluck into" ,
nil ,
{ help = ("declare a constructor on %s, or name the fields") : format ( declared ) }
)
c . infer ( arg . value or arg )
else
if namedStarted then
c . diag ( "NUPP2202" , arg , "a positional value cannot follow a named field" )
end
positional = positional + 1
local fname = order [ positional ]
if not fname then
c . diag (
"NUPP2202" ,
arg ,
("too many values (%s %s has %d fields)") : format ( calleeT . declKind , calleeT . name , # order )
)
else
byOrder = true
end
bindField ( fname , arg , arg , ("value %d (field %q)") : format ( positional , fname or "?" ) )
end
end



if byOrder and isRecord then
c . diag ( "NUPP2512" , node , ("record %s is constructed by field order") : format ( calleeT . name ) , nil , {
help = ("write new %s(field = value, ...) to name the fields") : format ( declared )
} )
end
for _ , field in ipairs ( order ) do
local default = calleeT . fieldDefaults and calleeT . fieldDefaults [ field ] or nil
if not bound [ field ] and default then
bindings [ # bindings + 1 ] = { name = field , defaultValue = default . value , isDefault = true }
bound [ field ] = true
end
end
if isRecord and not sealedConstruction then
local requiredOrder = { }
local seen = { }
for _ , field in ipairs ( order ) do
requiredOrder [ # requiredOrder + 1 ] , seen [ field ] = field , true
end
local inherited = { }
for field in pairs ( calleeT . byname ) do
if not seen [ field ] then
inherited [ # inherited + 1 ] , seen [ field ] = field , true
end
end
for field in pairs ( calleeT . writeByname ) do
if not seen [ field ] then
inherited [ # inherited + 1 ] = field
end
end
table . sort ( inherited )
for _ , field in ipairs ( inherited ) do
requiredOrder [ # requiredOrder + 1 ] = field
end
local missing = { }
for _ , field in ipairs ( requiredOrder ) do
local fieldType = calleeT . byname [ field ] or calleeT . writeByname [ field ]
if genericMap and fieldType then
fieldType = generics . rebind ( fieldType , genericMap )
end
local method = calleeT . overloadedMethods and calleeT . overloadedMethods [ field ]
or fieldType and relations . isMethod ( fieldType , calleeT )
local nested = calleeT . nestedTypes and calleeT . nestedTypes [ field ]
if not bound [ field ]
and fieldType
and not method
and not nested
and fieldType . tag ~= "typeobject"
and ( not isA ( T . nil_ , fieldType ) or relations . typevarMismatch ( T . nil_ , fieldType ) )
then
missing [ # missing + 1 ] = field
end
end
if # missing > 0 then
constructionFailed = true
c . diag (
"NUPP2208" ,
node ,
("construction of %s leaves required fields unset: %s")

: format ( declared , table . concat ( missing , ", " ) ) ,
nil ,
{ help = "supply each required field, give it a default, or declare it optional" }
)
end
end
node . recordFields = bindings
if not isRecord then
node . structConstruct = declared
end
if genericMap then

widenLiteralBindings ( genericMap )
ops . validateTypeBounds ( calleeT . typeParams , calleeT . typeBounds , genericMap , node )
if not constructionFailed then
reportUninferred (
node ,
declared ,
calleeT . typeParams ,
nil ,
genericMap ,
T . pack ( {
generics . ownInstance ( calleeT )
} )
)
end
generics . unfix ( genericMap , explicitFrozen )
return finished ( instantiateNominal ( calleeT , genericMap ) )
end
for field , source in pairs ( calleeT . fieldBorrowSources or { } ) do
local borrowedValue = constructionFields [ field ]
local rootValue = constructionFields [ source ]
if borrowedValue and rootValue then
local actual = c . own . provenanceOwners ( borrowedValue . node )
local expected = c . own . provenanceOwners ( rootValue . node )
local matches = # actual > 0 and # expected > 0
for _ , root in ipairs ( actual ) do
local found = false
for _ , candidate in ipairs ( expected ) do
if root == candidate then
found = true
end
end
if not found then
matches = false
end
end
if not matches then
c . diag (
"NUPP2619" ,
borrowedValue . node ,
("field %q must derive from sibling root field %q") : format ( field , source )
)
end
local sourceType = calleeT . byname [ source ]
local internalRoot = c . ownershipKind ( sourceType ) == "affine"
or c . ownershipKind ( sourceType ) == "pinned"
if not internalRoot then
for _ , root in ipairs ( actual ) do
if not rootSeen [ root ] then
rootSeen [ root ] , aggregateRoots [ # aggregateRoots + 1 ] = true , root
end
end
end
end
end



for _ , root in pairs ( deferredAffineRoots ) do
c . moveExpression ( root . node , root . type , "affine record construction" , c . ownershipKind ( root . type ) )
recordConstructionMove ( root . node )
end
if calleeT . inherentCleanup then
return finished ( T . affine ( calleeT , { calleeT . inherentCleanup } ) )
end
if calleeT . affineFields and # calleeT . affineFields > 0 then
local cleanups , obligations , transferOnly = { } , { } , false
for j = # calleeT . affineFields , 1 , -1 do
local name = calleeT . affineFields [ j ]
local valueT = affineValues [ name ]
if c . ownershipKind ( valueT ) == "affine" then
local capability = T . capability ( valueT )
transferOnly = transferOnly or T . capabilityTransferOnly ( capability )
if capability . obligation then
obligations [ # obligations + 1 ] = T . aggregateObligation ( { capability . obligation } , name )
end
for _ , cleanup in ipairs ( T . capabilityCleanups ( capability ) ) do
cleanups [ # cleanups + 1 ] = T . fieldCleanup ( name , cleanup )
end
elseif c . ownershipKind ( valueT ) == "pinned" then
local cleanup = T . dropFieldCleanup ( name )
cleanups [ # cleanups + 1 ] = cleanup
obligations [ # obligations + 1 ] = T . cleanupObligation ( cleanup , name )
end
end
if # obligations == 0 then
return finished ( calleeT )
end
return finished ( T . affine ( calleeT , cleanups , transferOnly , T . aggregateObligation ( obligations ) ) )
end
if calleeT . fieldBorrowSources and next ( calleeT . fieldBorrowSources ) then
return finished ( T . borrowed ( calleeT ) )
end
return finished ( calleeT )
end





local callContract = ops . metamethodOf ( calleeT , "__call" )
if callContract then
return ops . inferCall ( node , dropSelf ( callContract ) , argsNode )
end






local unionMembers = nil
if calleeT . tag == "union" then
local members = { }
local allFunctions = true
for _ , member in ipairs ( calleeT . members ) do
local raw = rawType ( member )
if raw . tag == "func" then
members [ # members + 1 ] = raw
else
allFunctions = false
end
end
if allFunctions then
unionMembers = members
end
end
local plainArguments = true
for _ , arg in ipairs ( args ) do
if cst . isToken ( arg ) or arg . kind == "namedArg" or arg . kind == "pluckArg" then
plainArguments = false
end
end
if unionMembers and # unionMembers > 1 and plainArguments then

local unionPack = c . inferListPack ( args , nil , function ( ) 
return nil
end )
for _ , arg in ipairs ( args ) do
local argumentType = arg . inferredType
if argumentType and c . ownershipKind ( argumentType ) then
c . diag (
"NUPP2611" ,
arg ,
"a live capability cannot cross a call to one of several functions; select the function first"

)
end
end
local packs = { }
for _ , member in ipairs ( unionMembers ) do
local specialized , why = probeSignature ( member , unionPack , node . cdefCall , c . reductionControl )


if specialized and ( member . yieldPack or member . resumePack ) then
specialized , why = nil , "it suspends, and a suspending call needs its function selected"
end
if not specialized then
c . diag (
"NUPP2005" ,
node ,
("%s is not callable with these arguments: its member %s refuses them (%s)")

: format ( T . tostring ( calleeT ) , T . tostring ( member ) , why or "arguments do not fit" )
)
return T . any , nil , T . pack ( { } , { kind = "unknown" , type = T . any } )
end
packs [ # packs + 1 ] = specialized . retPack
end
node . argumentPack = unionPack
local resultPack = T . packUnion ( packs )
return T . packAt ( resultPack , 1 ) or T . nil_ , resultPack . head , resultPack
end

local overloads = callableMembers ( calleeT )
if calleeT == T . any or ( calleeT . tag ~= "func" and not overloads ) then


if calleeT ~= T . any and not node . newReported then
c . diag ( "NUPP2005" , node , ("%s is not callable") : format ( T . tostring ( calleeT ) ) )
end

for _ , arg in ipairs ( args ) do
if not cst . isToken ( arg ) then
local value = ( arg . kind == "namedArg" or arg . kind == "pluckArg" ) and arg . value or arg



if ( arg . kind == "namedArg" or arg . kind == "pluckArg" ) and ( c . provisionalDepth or 0 ) == 0 then
c . diag ( "NUPP2006" , arg , "named and plucked arguments require a statically known callable" )
end
if value . kind == "call" or value . kind == "safeCall" then
value . expectedResult = nil
end
local argumentType = c . infer ( value )
if c . ownershipKind ( argumentType ) then
c . diag (
"NUPP2611" ,
arg ,
"a live capability cannot cross an untyped call; use @unsafe nupp.release explicitly to abandon tracking"

)
end
end
end
return T . any , nil
end

local advanced = false
for _ , argument in ipairs ( args ) do
if not cst . isToken ( argument ) and ( argument . kind == "namedArg" or argument . kind == "pluckArg" ) then
advanced = true
do break end
end
end




local advancedOverloadSelected = false
local ats = knownAts or { }
local argPack
local argNodes = { }

if advanced then









local rawArguments = { }
local namedStarted = false




local function positionalDestination ( index ) 
if overloads or calleeT . tag ~= "func" then
return nil
end
local signature = calleeT

return slotDestination (
node ,
signature ,
index ,
function ( j ) 
local earlier = rawArguments [ j ]
return earlier and earlier . kind == "plain" and earlier . type or nil
end ,
# signature . params
)
end

local function namedDestination ( name ) 
if overloads or calleeT . tag ~= "func" then
return nil
end
local signature = calleeT
for j , paramName in ipairs ( signature . paramNames or { } ) do
if paramName == name then
return slotDestination (
node ,
signature ,
j ,
function ( _ ) 
return nil
end ,
# signature . params
)
end
end

return nil
end

for sourceIndex , argument in ipairs ( args ) do
if not cst . isToken ( argument ) and argument . kind == "namedArg" then
namedStarted = true
local value = argument . value or argument
if value . kind == "call" or value . kind == "safeCall" then
value . expectedResult = namedDestination ( argument . name and argument . name . text or "" )
end
rawArguments [
# rawArguments + 1
] = {
kind = "named" ,
name = argument . name and argument . name . text or "" ,
node = value ,
type = c . infer ( value ) ,
source = argument ,
}
elseif not cst . isToken ( argument ) and argument . kind == "pluckArg" then






namedStarted = true
local value = argument . value or argument
if not isPluckPath ( value ) then
c . diag ( "NUPP2006" , value , "a plucked operand must be a name or dotted field path" , nil , {
help = "bind the producing expression to a local, then pluck from that local or one of its dotted fields"
,
} )
end
local valueType = c . infer ( value )
if c . ownershipKind ( valueType ) then
c . diag ( "NUPP2603" , value , "an owned or borrowed container cannot be plucked from" )
end
local group , seenHere = argument , { }
for _ , token in ipairs ( argument . names or { } ) do
if seenHere [ token . text ] then
c . diag ( "NUPP2006" , token , ("a plucked group repeats %q") : format ( token . text ) )
end
seenHere [ token . text ] = true
local fieldType , definition = c . fieldType ( valueType , token . text )
if not fieldType then
c . diag (
"NUPP2004" ,
token ,
("no field %q in %s") : format ( token . text , T . tostring ( valueType ) ) ,
c . edits . nameSpellingFix ( token , c . fieldNames ( valueType ) ) ,
{
help = "a plucked name is read as that field of the operand and filled into the parameter of the same name"
,
}
)
else
c . markToken ( token , definition , fieldType , "property" )
end
rawArguments [
# rawArguments + 1
] = {
kind = "named" ,
name = token . text ,
node = value ,
type = fieldType or T . any ,
field = token . text ,
group = group ,
source = argument ,
}
end
else
if namedStarted then
c . diag ( "NUPP2006" , argument , "a positional argument cannot follow a named argument" )
end
local valueType
if cst . isToken ( argument ) then
valueType = argument . kind == "string" and T . string or T . any
elseif argument . kind == "shortfn" or argument . kind == "funcExpr" then
c . provisionalDepth = ( c . provisionalDepth or 0 ) + 1
valueType = c . infer ( argument )
c . provisionalDepth = c . provisionalDepth - 1
else
if argument . kind == "call" or argument . kind == "safeCall" then
argument . expectedResult = positionalDestination ( # rawArguments + 1 )
end
valueType = c . infer ( argument )
end
rawArguments [
# rawArguments + 1
] = { kind = "plain" , node = argument , type = valueType , source = argument }
end
end




local function normalization ( ft ) 
local labels = { }
for j , name in ipairs ( ft . paramNames or { } ) do
if name ~= "" then
labels [ name ] = j
end
end
local named , firstNamed , lastNamed , priorNamed = { } , nil , 0 , 0
local positional = { }
local at = 1
while at <= # rawArguments do
local argument = rawArguments [ at ]
if argument . kind ~= "named" then
positional [ # positional + 1 ] = argument
at = at + 1
else





local run = { argument }
local group = argument . group
at = at + 1
while group and at <= # rawArguments and rawArguments [ at ] . group == group do
run [ # run + 1 ] = rawArguments [ at ]
at = at + 1
end
local highest = priorNamed
for _ , entry in ipairs ( run ) do
local index = labels [ entry . name ]
if not index then
return nil , ("unknown named argument %q") : format ( entry . name )
end
if named [ index ] then
return nil , ("named argument %q is supplied twice") : format ( entry . name )
end
if index <= priorNamed then
return nil , "named arguments must follow parameter order"
end
highest = math . max ( highest , index )
firstNamed = firstNamed and math . min ( firstNamed , index ) or index
lastNamed = math . max ( lastNamed , index )
named [ index ] = entry
end
priorNamed = highest
end
end

local types , nodes , lowered = { } , { } , { }
for _ , argument in ipairs ( positional ) do
types [ # types + 1 ] = argument . type
nodes [ # nodes + 1 ] = argument . node
lowered [ # lowered + 1 ] = { generatedKind = "expr" , expr = argument . node }
end

if not firstNamed then
return { pack = T . pack ( types ) , types = types , nodes = nodes , lowered = lowered }
end
if # types >= firstNamed then
return nil , "a named argument overlaps the positional prefix"
end


for j = # types + 1 , math . max ( # types , lastNamed ) do
local entry = named [ j ]
if entry then
types [ j ] = entry . type
nodes [ j ] = entry . node
lowered [ j ] = entry . field and { generatedKind = "field" , source = entry . node , name = entry . field , }
or { generatedKind = "expr" , expr = entry . node }
else
types [ j ] = T . nil_
nodes [ j ] = node
lowered [ j ] = { generatedKind = "nil" }
end
end

return { pack = T . pack ( types ) , types = types , nodes = nodes , lowered = lowered }
end






local function namedAgainst ( ft ) 
local tail = ft . paramPack and ft . paramPack . tail or nil
if not tail or tail . kind ~= "computed" then
return ft
end
local prefix = { }
for _ , argument in ipairs ( rawArguments ) do
if argument . kind == "named" then
do break end
end
prefix [ # prefix + 1 ] = argument . type
end
local map = { }
unifyPack ( ft . paramPack , T . pack ( prefix ) , map )
local instantiated = generics . instantiateFunction ( ft , map , c . reductionControl )
if instantiated and instantiated . tag == "func" then
return instantiated
end

return ft
end

local function chooseFor ( ft ) 
local target = namedAgainst ( ft )
local choice , why = normalization ( target )
if not choice then
return nil , nil , why
end
local specialized , rejected = probeSignature ( target , choice . pack , node . cdefCall , c . reductionControl )
if specialized then
return choice , specialized
end

return nil , nil , rejected or "arguments do not fit"
end

local selected
if overloads then
node . overloadCandidates = overloads
local winner , original , choice = selectOverload (
overloads ,
function ( candidate ) 
local found , specialized , why = chooseFor ( candidate )
return specialized , found , why
end ,
node ,
nil ,
nil ,
callDetails ( node )
)
if not winner then
return T . any , nil , T . pack ( { } , { kind = "unknown" , type = T . any } )
end



calleeT = original
node . overloadWinner = original
node . signatureType = winner
selected = choice
advancedOverloadSelected = true
else
local choice , _ , why = chooseFor ( calleeT )
selected = choice
if not selected then
local code = why and why : find ( "several" , 1 , true ) and "NUPP2126" or "NUPP2125"
c . diag ( code , node , why or "call arguments cannot be bound" , nil , callDetails ( node ) )
return T . any , nil , T . pack ( { } , { kind = "unknown" , type = T . any } )
end
end
ats , argNodes , argPack = selected . types , selected . nodes , selected . pack
argsNode . loweredArgs = selected . lowered
elseif knownAts then
argPack = T . pack ( knownAts )
elseif # args == 1 and cst . isToken ( args [ 1 ] ) then
ats [ 1 ] = args [ 1 ] . kind == "string" and T . string or T . any
argPack = T . pack ( ats )
else
local inferenceModes = calleeT . paramModes
if overloads then
inferenceModes = { }
for _ , candidate in ipairs ( overloads ) do
for j , mode in ipairs ( candidate . paramModes or { } ) do
if mode == "takes" or mode == "scoped" then


inferenceModes [ j ] = "takes"
end
end
end
end
local candidates = overloads or { calleeT }
argPack = c . inferListPack ( args , inferenceModes , argumentDestinations ( node , candidates , args ) )



ats = { }
for j , actual in ipairs ( argPack . head ) do
ats [ j ] = actual
end
end
node . argumentPack = argPack
local selectionPack = argPack
if argPack . alternatives then
local maxHead = 0
for _ , arm in ipairs ( argPack . alternatives ) do
if # arm . head > maxHead then
maxHead = # arm . head
end
end
ats = { }
for j = 1 , maxHead do
ats [ j ] = T . packAt ( argPack , j ) or T . nil_
end
argPack = T . pack ( ats )
end
if not advanced then
for j = 1 , # argPack . head do
argNodes [ j ] = args [ math . min ( j , # args ) ] or node
end
end

if overloads and not advancedOverloadSelected then
node . overloadCandidates = overloads
local winner , original = selectOverload (
overloads ,
function ( candidate ) 
local specialized , why = probeSignature ( candidate , selectionPack , node . cdefCall , c . reductionControl )
return specialized , nil , why
end ,
node ,
nil ,
selectionPack ,
callDetails ( node )
)
if not winner then
return T . any , nil , T . pack ( { } , { kind = "unknown" , type = T . any } )
end


calleeT = original
node . overloadWinner = original
node . signatureType = winner
if winner . ffiOut and # winner . ffiOut > 0 then
node . ffiOutContracts = winner . ffiOut
end
end



local argumentBorrowOwners = { }
local exclusiveRegions


= { }
local sharedRegions


= { }
for j , source in ipairs ( argNodes ) do
if not cst . isToken ( source ) then
local expandedIndex = 1
if # args > 0 and source == args [ # args ] and j >= # args then
expandedIndex = j - # args + 1
end
local owners = c . own . capabilityFacts ( source , expandedIndex , false ) . roots
argumentBorrowOwners [ j ] = owners
end
end


local params , rets = calleeT . params , calleeT . rets
local paramPack , retPack = calleeT . paramPack , calleeT . retPack
local declaredParamPack , declaredRetPack = paramPack , retPack
local paramModes = calleeT . paramModes or { }
local preservesResults = calleeT . preservesResults or { }
if next ( preservesResults ) then
node . preservesArguments = preservesResults
end
local preservedByParam = { }
for result = 1 , # calleeT . rets do
local source = preservesResults [ result ]
if source then
preservedByParam [ source ] = result
end
end
local varargType = calleeT . varargType
local constInferenceFailed = false
local packProblem
local genericMap = nil
local explicitFrozen = { }





if T . hasTypevar ( calleeT )
and ( # ( calleeT . typeParams or { } ) > 0 or # ( calleeT . packParams or { } ) > 0 or # ( calleeT . constParams or { } ) > 0 )
then
local map = { }
genericMap = map




local introduced = { }
for _ , binder in ipairs ( calleeT . typeParams or { } ) do
introduced [ binder ] = true
end

retainEnclosingBinders ( c , paramPack , introduced , map )
retainEnclosingBinders ( c , retPack , introduced , map )


seedWrittenTypeArguments ( node , calleeT . typeParams , map )
explicitFrozen = generics . fixBound ( map )
local slots = slotBinders ( calleeT )
local unified = { }
for j , actual in ipairs ( argPack . head ) do
local param = paramPack . head [ j ] or varargType
unified [ j ] = param and widenedArgument ( param , actual , slots ) or actual
end
unifyPack ( paramPack , T . pack ( unified , argPack . tail , argPack . modes ) , map )
local expectedResult = ( node ) . expectedResult





local expectedHasBinder = false
for _ , binder in ipairs ( calleeT . typeParams or { } ) do
if map [ binder ] == nil and ( binder ) . default == nil then
expectedHasBinder = true
end
end
for _ , binder in ipairs ( calleeT . packParams or { } ) do
if map [ binder ] == nil then
expectedHasBinder = true
end
end
for _ , binder in ipairs ( calleeT . constParams or { } ) do
if map [ binder ] == nil and ( binder ) . default == nil then
expectedHasBinder = true
end
end
if expectedResult ~= nil and expectedHasBinder and # retPack . head == 1 and retPack . tail == nil then





local frozen = generics . fixBound ( map , generics . bindersInPack ( declaredParamPack ) )
unifyPack ( retPack , T . pack ( { expectedResult } ) , map )
generics . unfix ( map , frozen )
end
local constProblem = constInferenceProblem ( calleeT , map )
if constProblem then
constInferenceFailed = true
c . diag ( "NUPP2131" , node , constProblem )
end


if varargType then
for j = # params + 1 , # ats do
unify ( varargType , widenedArgument ( varargType , ats [ j ] , slots ) , map )
end
end
ops . validateTypeBounds ( calleeT . typeParams , calleeT . typeBounds , map , node )
local p2 , r2 = { } , { }
local erasedProjections = { }
for j , p in ipairs ( params ) do
p2 [ j ] = substType ( p , map , erasedProjections , c . reductionControl )
end
for j , r in ipairs ( rets ) do
r2 [ j ] = substType ( r , map , erasedProjections , c . reductionControl )
end




local paramEval = generics . evaluatePack ( substPack ( paramPack , map ) , c . reductionControl )
local retEval = generics . evaluatePack ( substPack ( retPack , map ) , c . reductionControl )
paramPack , retPack = paramEval . pack , retEval . pack
packProblem = paramEval . error or retEval . error
for _ , name in ipairs ( paramEval . gradual ) do
erasedProjections [ # erasedProjections + 1 ] = name
end
for _ , name in ipairs ( retEval . gradual ) do
erasedProjections [ # erasedProjections + 1 ] = name
end
params , rets = paramPack . head , retPack . head
paramModes = paramPack . modes
reportGradualProjections ( c , node , erasedProjections )
if paramPack . tail and paramPack . tail . kind == "homogeneous" then
varargType = paramPack . tail . type
elseif varargType then
varargType = substType ( varargType , map , nil , c . reductionControl )
end
end
if not packProblem then
paramPack , packProblem = generics . expandComputedPack ( paramPack , c . reductionControl )
end
if not packProblem then
retPack , packProblem = generics . expandComputedPack ( retPack , c . reductionControl )
end
if packProblem then
if not constInferenceFailed then
c . diag ( "NUPP2006" , node , packProblem , nil , callDetails ( node ) )
end
paramPack = T . pack ( params , { kind = "unknown" , type = T . any } , paramPack . modes )
end
params , rets = paramPack . head , retPack . head
paramModes = paramPack . modes
if paramPack . tail and paramPack . tail . kind == "homogeneous" then
varargType = paramPack . tail . type
end







if next ( preservesResults ) then
local function preservePack ( pack ) 
if pack . alternatives then
local alternatives = { }
for j , alternative in ipairs ( pack . alternatives ) do
alternatives [ j ] = preservePack ( alternative )
end
return T . packUnion ( alternatives )
end
local adjusted = { }
for j , result in ipairs ( pack . head ) do
local source = preservesResults [ j ]
local path = calleeT . preservesPaths and calleeT . preservesPaths [ j ] or nil
if source and ats [ source ] and not path then





path = T . preservationPath ( rawType ( result ) , rawType ( params [ source ] ) )
end



adjusted [ j ] = source
and ats [ source ]
and not T . capability ( result ) . obligation
and T . withOwnershipPayload ( ats [ source ] , rawType ( result ) , path )
or result
end

return T . pack ( adjusted , pack . tail , pack . modes )
end

retPack = preservePack ( retPack )
rets = retPack . head
end





local contextualArgs = false
for j , arg in ipairs ( args ) do
local expected = params [ j ]
local isFunction = not cst . isToken ( arg ) and ( arg . kind == "shortfn" or arg . kind == "funcExpr" )
if isFunction and expected and rawType ( expected ) . tag == "func" then
local priorScoped = c . scopedCaptureDepth
if paramModes [ j ] == "scoped" then
c . scopedCaptureDepth = priorScoped + 1
end
ats [ j ] = c . apply . inferExpected ( arg , expected )
c . scopedCaptureDepth = priorScoped
contextualArgs = true
end
end
if contextualArgs then
argPack = T . pack ( ats , argPack . tail , argPack . modes )
node . argumentPack = argPack
if genericMap then



local settled = { }
for tv in pairs ( genericMap ) do
settled [ tv ] = true
end
unifyPack ( declaredParamPack , argPack , genericMap )



local slots = slotBinders ( calleeT )
local fresh = { }
for tv in pairs ( genericMap ) do
if not settled [ tv ] and slots [ tv ] == true then
fresh [ tv ] = true
end
end
widenLiteralBindings ( genericMap , fresh )
local paramEval = generics . evaluatePack ( substPack ( declaredParamPack , genericMap ) , c . reductionControl )
local retEval = generics . evaluatePack ( substPack ( declaredRetPack , genericMap ) , c . reductionControl )
if not paramEval . error and not retEval . error then
paramPack , retPack = paramEval . pack , retEval . pack
params , rets = paramPack . head , retPack . head
paramModes = paramPack . modes
if paramPack . tail and paramPack . tail . kind == "homogeneous" then
varargType = paramPack . tail . type
end
end
end
end
if genericMap then
reportUninferred ( node , callName ( node ) , calleeT . typeParams , calleeT . packParams , genericMap , declaredRetPack )
node . genericBindings = genericMap
generics . unfix ( genericMap , explicitFrozen )
end

local jitBody = c . functionBodies [ # c . functionBodies ]

local function jitHazard ( code , at , message , help , disabledDefinition , disabledBody ) 
c . jitHazards [
# c . jitHazards + 1
] = {
code = code ,
at = at ,
body = jitBody ,
message = message ,
help = help ,
disabledDefinition = disabledDefinition ,
disabledBody = disabledBody ,
suppressed = not ( jitBody and jitBody . jitRequired ) and c . suppressed ( code ) ,
}
end

if node . cdefCall and calleeT . vararg then
jitHazard (
"jit-boundary" ,
node ,
"a variadic FFI call cannot safely execute on a compiled trace" ,
"move the call into a function disabled with jit.off, or remove @jit from this function"
)
end
if node . cdefCall then
local function optionalFunction ( t ) 
if t . tag == "func" then
return t
end
if t . tag == "union" and t . hasNil and # ( t . members or { } ) == 2 then
local first , second = t . members [ 1 ] , t . members [ 2 ]
local other = first == T . nil_ and second or first
return other and other . tag == "func" and other or nil
end

return nil
end

for j = 1 , math . min ( # ats , # params ) do
local expected = rawType ( params [ j ] )
local actual = rawType ( ats [ j ] )
local callback = optionalFunction ( expected )
if callback and callback . foreign and actual . tag == "func" and not actual . foreign then
local argument = argNodes [ j ]
local disabledDefinition , disabledBody = nil , nil
if argument and argument . kind == "name" and argument . token then
local entry = c . lookupEntry ( argument . token . text )
disabledDefinition = entry and ( entry . jitTarget or entry . definition ) or nil
elseif argument and ( argument . kind == "funcExpr" or argument . kind == "shortfn" ) then
disabledBody = argument . body or argument
elseif argument and argument . kind == "dotIndex" and argument . name then
disabledDefinition = argument . name . definition
end
jitHazard (
"jit-callback" ,
argument or node ,
"a Lua function passed to C becomes an FFI callback and cannot run from a compiled trace" ,
"disable the callback with jit.off before passing it to C" ,
disabledDefinition ,
disabledBody
)
end
end
end

local nparams = # params
local actualCount = # argPack . head
if not argPack . tail and actualCount > nparams and not paramPack . tail then
c . diag (
"NUPP2007" ,
node ,
("too many arguments (expected %d, got %d)") : format ( nparams , actualCount ) ,
nil ,
callDetails ( node )
)
c . checkPackDiscard ( argPack , nparams + 1 , node )
end
if not argPack . tail and actualCount < nparams then
for j = actualCount + 1 , nparams do
local ok = isA ( T . nil_ , params [ j ] )
if not ok then
c . diag (
"NUPP2006" ,
node ,
("omitted argument %d supplies nil, not %s") : format ( j , T . tostring ( params [ j ] ) ) ,
nil ,
callDetails ( node )
)
end
end
end



local parameterTail = paramPack . tail
for j = 1 , actualCount do
local tailSlot = j > nparams
local mode = tailSlot
and parameterTail
and parameterTail . kind == "homogeneous"
and ( parameterTail . mode or ( varargType == T . any and "plain" or nil ) )
or ( not tailSlot and ( paramModes [ j ] or "plain" ) or nil )
local actualForCheck = ats [ j ]
local preservationResult = preservedByParam [ j ]
if preservationResult then
actualForCheck = rawType ( actualForCheck )
end
if node . cdefCall and c . ownershipKind ( actualForCheck ) == "pinned" then
actualForCheck = rawType ( actualForCheck )
if not cst . isToken ( argNodes [ j ] ) then
argNodes [ j ] . passPinnedPointer = true
end
end
local ok , why , reported
if constInferenceFailed then
ok = true
else
local expected = tailSlot and ( varargType or T . any ) or params [ j ]
if mode == "borrows" or mode == "exclusive" then


expected = rawType ( expected )
actualForCheck = rawType ( actualForCheck )
end
local physical = node . cdefCall == true
or node . fixedWidthPhysicalParameters ~= nil and node . fixedWidthPhysicalParameters [ j ] == true
ok , why , reported = c . fixedWidth . fits (
actualForCheck ,
expected ,
cst . isToken ( argNodes [ j ] ) and node or argNodes [ j ] ,
physical
)
if ok and binderInScope ( c , expected ) and relations . typevarMismatch ( actualForCheck , expected ) then
ok = false
why = ("%s is not a value of the generic type %s")

: format ( T . tostring ( actualForCheck ) , T . tostring ( expected ) )
end
end
if not ok and not reported then
c . diag (
"NUPP2006" ,
cst . isToken ( argNodes [ j ] ) and node or argNodes [ j ] ,
("argument %d: %s") : format ( j , why ) ,
nil ,
callDetails ( node )
)
end



if not cst . isToken ( argNodes [ j ] ) then
c . checkMetatableLiteral ( argNodes [ j ] , ats [ j ] , tailSlot and ( varargType or T . any ) or params [ j ] )
end
if mode == "takes" then
local takenKind = c . ownershipKind ( ats [ j ] )
local conditional = node . kind == "safeCall"
or node . kind == "methodCall" and ( node . safeObj ~= nil or node . safeMethod ~= nil )
if conditional and ( takenKind == "affine" or takenKind == "pinned" ) then
c . diag (
"NUPP2602" ,
argNodes [ j ] or node ,
"a conditional call cannot take ownership; narrow the callee or receiver first"
)
elseif takenKind == "affine" or takenKind == "pinned" then
local movedNode = cst . isToken ( argNodes [ j ] ) and node or argNodes [ j ]
local sourceArg = args [ j ]
if movedNode . affineAggregate then
node . automaticOwnerMoves = node . automaticOwnerMoves or { }
for _ , move in ipairs ( (
sourceArg and sourceArg . automaticOwnerMoves
) or movedNode . automaticOwnerMoves or { } ) do
node . automaticOwnerMoves [ # node . automaticOwnerMoves + 1 ] = move
end
else
c . moveExpression ( movedNode , ats [ j ] , ("argument %d") : format ( j ) , takenKind )
if movedNode . automaticOwnerMove then
node . automaticOwnerMoves = node . automaticOwnerMoves or { }
node . automaticOwnerMoves [ # node . automaticOwnerMoves + 1 ] = movedNode . automaticOwnerMove
end
end
elseif takenKind == "borrowed" then



local scopeRoot = ( node ) . bodyScopeRoot
local roots = scopeRoot
and not cst . isToken ( argNodes [ j ] )
and c . own . capabilityFacts ( argNodes [ j ] , nil , false ) . roots
or nil
local ownScope = roots ~= nil and # roots > 0
for _ , root in ipairs ( roots or { } ) do
ownScope = ownScope and root == scopeRoot
end
if not ownScope then
c . diag (
"NUPP2602" ,
argNodes [ j ] or node ,
"a taking parameter cannot retain a borrowed value; use scoped for a callback"
)
end
end
elseif preservationResult then
local kind = c . ownershipKind ( ats [ j ] )
if kind == "affine" or kind == "pinned" then
local movedNode = cst . isToken ( argNodes [ j ] ) and node or argNodes [ j ]
local sourceEntry = c . ownershipEntry ( movedNode )
local conditional = node . kind == "safeCall"
or node . kind == "methodCall" and ( node . safeObj ~= nil or node . safeMethod ~= nil )
if conditional then
c . diag (
"NUPP2602" ,
movedNode ,
"a conditional call cannot preserve ownership; narrow the callee or receiver first"
)
elseif not ( node . discardingResults and sourceEntry ) then
c . moveExpression (
movedNode ,
ats [ j ] ,
("argument %d preserved as result %d") : format ( j , preservationResult ) ,
kind
)
if movedNode . automaticOwnerMove then
node . automaticOwnerMoves = node . automaticOwnerMoves or { }
node . automaticOwnerMoves [ # node . automaticOwnerMoves + 1 ] = movedNode . automaticOwnerMove
end
end
end
elseif mode == "scoped" then
local callback = rawType ( ats [ j ] )
local callbackArray = callback . tag == "array" and rawType ( callback . elem ) . tag == "func"
local kind = c . ownershipKind ( ats [ j ] )
if kind == "affine" or kind == "pinned" then
c . diag (
"NUPP2602" ,
argNodes [ j ] or node ,
"a scoped parameter cannot borrow an affine value as a repeatable callback" ,
nil ,
{ help = "use a takes parameter when the callback must be consumed" }
)
elseif callback ~= T . any
and callback ~= T . unknown
and callback . tag ~= "func"
and callback . tag ~= "intersection"
and not callbackArray
then
c . diag ( "NUPP2602" , argNodes [ j ] or node , "a scoped parameter requires a callback value" )
end
elseif mode == "exclusive" then
if c . ownershipKind ( ats [ j ] ) == "affine" then
c . own . expireTemporaryAfterStatement ( argNodes [ j ] )
end
local entry , nameNode = c . ownershipEntry ( argNodes [ j ] )
entry = c . ownershipState ( entry )
local entryFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
local regionRoot , regionPath = c . regionOf ( argNodes [ j ] )
if entry and entry . movedFields and next ( entry . movedFields ) then
c . diag (
"NUPP2602" ,
nameNode or argNodes [ j ] or node ,
"a partially moved record cannot be borrowed as a whole" ,
nil ,
{ help = "borrow the fields that remain, or refill the moved field first" }
)
end
if regionRoot and regionPath ~= nil then
for _ , prior in ipairs ( sharedRegions ) do
if prior . root == regionRoot and c . regionsOverlap ( prior . path , regionPath ) then
c . diag (
"NUPP2607" ,
argNodes [ j ] or node ,
"an exclusive argument overlaps a shared argument in the same call"
)
do break end
end
end
for _ , prior in ipairs ( exclusiveRegions ) do
if prior . root == regionRoot and c . regionsOverlap ( prior . path , regionPath ) then
c . diag (
"NUPP2607" ,
argNodes [ j ] or node ,
"exclusive arguments overlap the same writable region" ,
nil ,
c . own . conflictDetails ( regionRoot , regionPath )
)
do break end
end
end
exclusiveRegions [ # exclusiveRegions + 1 ] = { root = regionRoot , path = regionPath }
end
if not entry and regionRoot and regionPath and regionPath ~= "" then



local base = c . own . pathBase ( argNodes [ j ] )
if c . own . regionBlocked ( regionRoot , base , nil , regionRoot , regionPath , false ) then
c . diag (
"NUPP2607" ,
argNodes [ j ] or node ,
"an exclusive parameter cannot invalidate a region while a derived borrow is live" ,
nil ,
c . own . conflictDetails ( regionRoot , regionPath )
)
end
elseif c . ownershipKind ( ats [ j ] ) == "borrowed" then
local sole
if entry and entry . withBinding or entryFacts and entryFacts . exclusive then


sole = ( entry . activeBorrows or 0 ) == 0
else
local roots = entryFacts and entryFacts . roots or { }
sole = # roots > 0
for _ , root in ipairs ( roots ) do



if ( root . activeBorrows or 0 ) > 1 then
sole = false
end
end
end
if regionPath and regionPath ~= "" then
sole = not c . own . regionBlocked ( regionRoot , entry , entryFacts , regionRoot , regionPath , false )
end
if not sole then
c . diag (
"NUPP2607" ,
argNodes [ j ] or node ,
"an exclusive parameter needs the sole live borrowed view" ,
nil ,
c . own . conflictDetails ( regionRoot or entry , regionPath )
)
end
elseif entry and ( entry . activeBorrows or 0 ) > 0 then
c . diag (
"NUPP2607" ,
nameNode or argNodes [ j ] ,
"an exclusive parameter cannot invalidate a value while a derived borrow is live" ,
nil ,
c . own . conflictDetails ( entry , regionPath )
)
end
elseif mode == "borrows" then
if c . ownershipKind ( ats [ j ] ) == "affine" then
c . own . expireTemporaryAfterStatement ( argNodes [ j ] )
end


local entry , nameNode = c . ownershipEntry ( argNodes [ j ] )
entry = c . ownershipState ( entry )
local entryFacts = entry and c . own . capabilityFacts ( entry , nil , false ) or nil
if c . ownershipKind ( ats [ j ] ) == "affine" and rawType ( ats [ j ] ) . tag == "func" then
c . diag (
"NUPP2602" ,
nameNode or argNodes [ j ] or node ,
"an affine closure cannot be passed to a borrows parameter" ,
nil ,
{ help = "use a takes parameter when the callback must be consumed" }
)
elseif entry and entry . movedFields and next ( entry . movedFields ) then


c . diag (
"NUPP2602" ,
nameNode or argNodes [ j ] or node ,
"a partially moved record cannot be borrowed as a whole" ,
nil ,
{ help = "borrow the fields that remain, or refill the moved field first" }
)
end
if not ( entry and entryFacts and entryFacts . exclusive and ( entry . activeBorrows or 0 ) == 0 ) then
local regionRoot , regionPath = c . regionOf ( argNodes [ j ] )
if regionRoot and regionPath ~= nil then
for _ , prior in ipairs ( exclusiveRegions ) do
if prior . root == regionRoot and c . regionsOverlap ( prior . path , regionPath ) then
c . diag (
"NUPP2607" ,
argNodes [ j ] or node ,
"a shared argument overlaps an exclusive argument in the same call"
)
do break end
end
end
sharedRegions [ # sharedRegions + 1 ] = { root = regionRoot , path = regionPath }
end
local roots = entry and { entry } or c . own . provenanceOwners ( argNodes [ j ] )
local base = entry or c . own . pathBase ( argNodes [ j ] )
for _ , root in ipairs ( roots ) do
if not reborrowsExclusiveView ( argNodes [ j ] , c . borrowRoot ( root ) )
and c . own . regionBlocked ( root , base , entryFacts , regionRoot , regionPath , true )
then
c . diag (
"NUPP2607" ,
nameNode or argNodes [ j ] or node ,
"a shared argument cannot overlap a live exclusive view" ,
nil ,
c . own . conflictDetails ( regionRoot or root , regionPath , true )
)
do break end
end
end
end
elseif mode == "plain" and c . ownershipKind ( ats [ j ] ) then
local plainExpected = tailSlot and ( varargType or T . any ) or params [ j ]
local actualOwnership = c . ownershipKind ( ats [ j ] )
local entry = c . ownershipEntry ( argNodes [ j ] )
entry = c . ownershipState ( entry )
local ownershipNode = argNodes [ j ]
local ownershipUseReported = false
while ownershipNode do
ownershipUseReported = ownershipUseReported or ownershipNode . ownershipUseReported == true
ownershipNode = ownershipNode . obj
end








local forwarded = tailSlot and varargType == nil and actualOwnership == "borrowed"
local liveAcrossAny = plainExpected == T . any
and not forwarded
and not ownershipUseReported
and ( not entry or not entry . moved and ( entry . activeBorrows or 0 ) == 0 )
if plainExpected ~= T . any or liveAcrossAny then
c . diag (
plainExpected == T . any and "NUPP2611" or "NUPP2603" ,
argNodes [ j ] or node ,
plainExpected == T . any and "a live capability cannot cross an any parameter"
or "an owner or borrow needs a borrows, exclusive, or takes contract"
)
end
elseif mode == "plain" and node . cdefCall and c . pointerShaped ( ats [ j ] ) then
if c . unsafeDepth == 0 then
c . diag (
"NUPP2604" ,
argNodes [ j ] or node ,
"passing a raw pointer to C requires @unsafe on the call or a borrows, exclusive, takes, retains, or releases contract"

)
else
node . unsafeOwnershipOperation = "uncontracted foreign pointer argument"
end
elseif mode == "retains" or mode == "releases" then
local entry , nameNode = c . ownershipEntry ( argNodes [ j ] )
entry = c . ownershipState ( entry )
if not node . cdefCall then
c . diag ( "NUPP2602" , argNodes [ j ] or node , mode .. " is an imported C-function contract" )
elseif c . ownershipKind ( ats [ j ] ) ~= "pinned" or not entry then
c . diag ( "NUPP2602" , argNodes [ j ] or node , mode .. " argument requires a named pinned(T) handle" )
elseif entry . moved then

elseif mode == "retains" then
local entryFacts = c . own . capabilityFacts ( entry )
if entryFacts . retention then
c . diag ( "NUPP2602" , nameNode or argNodes [ j ] , "C already retains this pinned handle" )
else
entryFacts . retention = entry
end
elseif not c . own . capabilityFacts ( entry ) . retention then
c . diag ( "NUPP2602" , nameNode or argNodes [ j ] , "releases argument is not currently retained by C" )
else
c . own . capabilityFacts ( entry ) . retention = nil
end
end
end
for result = 1 , # calleeT . rets do
local source = preservesResults [ result ]
if source then
local owners = argumentBorrowOwners [ source ]
if not owners and c . ownershipKind ( ats [ source ] ) then
local sourceNode = argNodes [ source ]
local entry = sourceNode and c . ownershipEntry ( sourceNode )
if entry then
owners = { c . borrowRoot ( entry ) }
end
end
if owners then
c . own . capabilityFacts ( node , result ) . roots = owners
end
local sourceNode = argNodes [ source ]
local entry = sourceNode and c . ownershipEntry ( sourceNode )
entry = c . ownershipState ( entry )
if entry then
local resultFacts = c . own . capabilityFacts ( node , result )
resultFacts . origin = entry
resultFacts . retention = c . own . capabilityFacts ( entry , nil , false ) . retention
end
end
end
if calleeT and calleeT . tag == "func" and calleeT . partitionResults then
node . returnPartitionFields = calleeT . partitionResults
node . partitionFields = calleeT . partitionResults [ 1 ]
end





if calleeT
and calleeT . tag == "func"
and ( calleeT . borrowsParam or calleeT . borrowsSelf or calleeT . borrowsParams )
then
local sources = { }
if calleeT . borrowsSelf then
sources [ # sources + 1 ] = node . obj
end
if calleeT . borrowsParam then
sources [ # sources + 1 ] = argNodes [ calleeT . borrowsParam ]
end
for _ , at in ipairs ( calleeT . borrowsParams or { } ) do
sources [ # sources + 1 ] = argNodes [ at ]
end
local owners = { }
for _ , source in ipairs ( sources ) do





local sourceEntry = source and c . ownershipEntry ( source ) or nil
sourceEntry = c . own . ownershipState ( sourceEntry )



local base = not sourceEntry and source and c . own . pathBase ( source ) or nil
local found
if sourceEntry
and ( c . ownershipKind ( sourceEntry . t ) == "affine" or c . ownershipKind ( sourceEntry . t ) == "pinned" )
then
found = { sourceEntry }
elseif base then
found = { base }
else
found = source and c . own . provenanceOwners ( source ) or { }
end
if # found > 0 then
for _ , root in ipairs ( found ) do
owners [ # owners + 1 ] = root
end
elseif source then
c . diag ( "NUPP2619" , source , "a borrowed result needs a rooted argument to borrow from" )
end
end
local borrowedSlot = calleeT . borrowsResult or 1
if # owners > 0 then
c . own . capabilityFacts ( node , borrowedSlot ) . roots = owners
end
local exclusiveResult = calleeT . borrowsParam and calleeT . paramModes [ calleeT . borrowsParam ] == "exclusive"
if not exclusiveResult then
for _ , at in ipairs ( calleeT . borrowsParams or { } ) do
if calleeT . paramModes [ at ] == "exclusive" then
exclusiveResult = true
do break end
end
end
end
if exclusiveResult and # owners > 0 then
c . own . capabilityFacts ( node , borrowedSlot ) . exclusive = true
end
local resultRoot , resultPath , consistent = nil , nil , true
for _ , source in ipairs ( sources ) do
local root , path
if source then
root , path = c . regionOf ( source )
end
if root then
if not resultRoot then
resultRoot , resultPath = root , path or ""
elseif resultRoot ~= root or resultPath ~= ( path or "" ) then
consistent = false
end
end
end
if consistent and resultRoot and resultPath and resultPath ~= "" then
local resultFacts = c . own . capabilityFacts ( node )
resultFacts . regionRoot = resultRoot
resultFacts . regionPath = resultPath
end
end




local resultTail = declaredRetPack . tail
if resultTail and resultTail . kind == "generic" then
local inputStart = nil
local inputTail = declaredParamPack . tail
if inputTail and inputTail . kind == "generic" and inputTail . var == resultTail . var then
inputStart = # declaredParamPack . head + 1
end
if inputStart then
for j = # declaredRetPack . head + 1 , # retPack . head do
local source = inputStart + j - # declaredRetPack . head - 1
local owners = argumentBorrowOwners [ source ]
if owners then
c . own . capabilityFacts ( node , j ) . roots = owners
end
end
end
end
for _ , output in ipairs ( calleeT . ffiOut or { } ) do
if output . kind == "borrowed" then
local owners = { }
for _ , sourceParam in ipairs ( output . sourceParams or { } ) do
local source = sourceParam and argNodes [ sourceParam ] or nil
local entry = source and c . ownershipEntry ( source )
if entry then
owners [ # owners + 1 ] = c . borrowRoot ( entry )
elseif source then
c . diag ( "NUPP2619" , source , "a borrowed C output needs a named lifetime source" )
end
end
if # owners > 0 then
c . own . capabilityFacts ( node , output . returnIndex ) . roots = owners
end
end
end
node . signatureType = T . func (
params ,
rets ,
calleeT . vararg ,
paramModes ,
calleeT . predicate ,
calleeT . typeParams ,
calleeT . typeBounds ,
calleeT . borrowsParam ,
calleeT . borrowsSelf ,
calleeT . borrowsParams ,
calleeT . ffiOut ,
varargType ,
calleeT . noreturn ,
paramPack ,
retPack ,
calleeT . packParams ,
calleeT . yieldPack and genericMap and substPack ( calleeT . yieldPack , genericMap ) or calleeT . yieldPack ,
calleeT . resumePack and genericMap and substPack ( calleeT . resumePack , genericMap ) or calleeT . resumePack ,
calleeT . noYield ,
calleeT . paramNames ,
calleeT . preservesResults ,
calleeT . foreign ,
calleeT . constParams ,
calleeT . paramKinds ,
calleeT . partitionResults ,
calleeT . comptimeOnly ,
calleeT . explicitPreserves
)

return T . packAt ( retPack , 1 ) or T . nil_ , retPack . head , retPack
end

c . metamethodOf = ops . metamethodOf
c . validateTypeBounds = ops . validateTypeBounds
c . applyContract = ops . applyContract
c . inferCall = ops . inferCall

return ops
end

local __nuppExportValue= calls ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.calls"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.calls"]=__nuppExports;return __nuppExports