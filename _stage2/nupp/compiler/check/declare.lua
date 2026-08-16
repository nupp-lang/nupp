_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local generics = require ( "nupp.compiler.generics" )
local cst = require ( "nupp.compiler.cst" )
local operators = require ( "nupp.compiler.check.operators" )
local predicate = require ( "nupp.compiler.predicate" )
local methodslots = require ( "nupp.compiler.methodslots" )
local state = require ( "nupp.compiler.check.state" )

local declare = { }




local BITFIELD_BASE

= {
boolean = true ,
integer = true ,
int8 = true ,
int16 = true ,
int32 = true ,
int64 = true ,
uint8 = true ,
uint16 = true ,
uint32 = true ,
uint64 = true ,
}

local isA = relations . isA


local substType = generics . rebind
local addSelf = generics . addSelf
local dropSelf = generics . dropSelf



local function defaultValue ( node )
if not node then
return nil , false
end
local kind = node . kind
if kind == "nilExpr" then
return nil , true
elseif kind == "trueExpr" or kind == "falseExpr" then
return kind == "trueExpr" , true
elseif kind == "number" or kind == "string" then
local text = node . token and node . token . text or ( kind == "number" and "0" or '""' )
if kind == "number" then
text = text : gsub ( "_" , "" )
elseif text : sub ( 1 , 1 ) == "`" then
local body = text : sub ( 2 , - 2 ) : gsub ( "\\([`$])" , "%1" ) : gsub ( '"' , '\\"' ) : gsub ( "\n" , "\\n" )
text = '"' .. body .. '"'
end
local chunk = loadstring ( "return " .. text )
if chunk then
local ok , value = pcall ( chunk )
if ok and ( type ( value ) == "number" or type ( value ) == "string" ) then
return value , true
end
end
return nil , false
elseif kind == "paren" then
return defaultValue ( node . expr )
elseif kind == "unop" and node . op and ( node . op . kind == "-" or node . op . kind == "+" ) then
local value , ok = defaultValue ( node . operand )
if ok and type ( value ) == "number" then
return node . op . kind == "-" and - value or value , true
end
return nil , false
elseif kind == "tableExpr" then
local value , nextIndex = { } , 1
for _ , field in ipairs ( node . fields or { } ) do
local child , ok = defaultValue ( field . value )
if not ok then
return nil , false
end
if field . kind == "fieldItem" then
value [ nextIndex ] = child
nextIndex = nextIndex + 1
elseif field . kind == "fieldNamed" and field . name and not field . isConst then
value [ field . name . text ] = child
elseif field . kind == "fieldBracket" then
local key , keyOk = defaultValue ( field . key )
if not keyOk or key == nil or type ( key ) == "table" then
return nil , false
end
value [ key ] = child
else
return nil , false
end
end
return value , true
end

return nil , false
end

local function hasReceiver ( body , declKind )



if declKind == "struct" then
return true
end
local first = body and body . params and body . params [ 1 ]

return first ~= nil and first . name ~= nil and first . name . text == "self"
end




local function implementationLabelsFit ( have , want )
for j , wanted in ipairs ( want . paramNames or { } ) do
if wanted ~= "" and ( have . paramNames and have . paramNames [ j ] or "" ) ~= wanted then
return false
end
end

return true
end



















function declare . install (
c ,
reifiableField ,
fix ,
insertBefore ,
validateAnnotation
)










local function containedByValue ( t , target )
local seen = { }
local function reaches ( current )
if not current or current . tag ~= "nominal" or current . declKind ~= "struct" then
return nil
end
if current == target then
return target . name
end
if seen [ current ] then



return nil
end
seen [ current ] = true
for _ , name in ipairs ( current . fieldOrder or { } ) do
local found = reaches ( current . byname [ name ] )
if found then
return current . name
end
end

return nil
end

return reaches ( t )
end






local STRUCT_ENTRY = { fieldDecl = true , inlineMethod = true , constructorDecl = true , }










local function refuseAot ( entry , what )
for _ , application in ipairs ( entry . annotations or { } ) do
if application . name and application . name . text == "aot" then
c . diag ( "NUPP2902" , application . name , ( "@aot cannot compile %s" ) : format ( what ) )
end
end
end


















local function suggestStruct ( stat , n )
if stat . isAnnotationDefinition or stat . generics or # ( stat . supertypes or { } ) > 0 then
return
end
local fields = 0
for _ , e in ipairs ( stat . entries or { } ) do
if not STRUCT_ENTRY [ e . kind ] then
return
end
if e . kind == "fieldDecl" then

if e . capability then
return
end
local ft = e . name and n . byname [ e . name . text ]
if not ft or not reifiableField ( ft ) then
return
end
fields = fields + 1
end
end
if fields == 0 then
return
end



local keyword = nil
for _ , child in ipairs ( stat ) do
if child == stat . name then
break
end
if cst . isToken ( child ) and child . text == "record" then
keyword = child
break
end
end
local fixes = keyword and {
c . edits . fix ( "change `record` to `struct`" , c . edits . replaceToken ( keyword , "struct" ) )
} or nil
c . diag (
"NUPP2509" ,
stat . name ,
( "record %s declares only fields that reify" ) : format ( n . name ) ,
fixes ,
{
help = "declaring it `struct` puts its instances in C memory, off the "
.. "collector's graph, at the cost of a fixed layout: no fields added "
.. "after construction" ,
notes = {






"an instance is cdata, not a table: `pairs` needs a `__pairs` "
.. "metamethod, and a serializer that walks tables will refuse it "
.. "unless it is converted first" ,
}
}
)
end








local function returnedExpression ( block )
local statements = { }
for _ , entry in ipairs ( block and block . stats or { } ) do
if not cst . isToken ( entry ) and entry . kind ~= "emptyStmt" then
statements [ # statements + 1 ] = entry
end
end
local only = # statements == 1 and statements [ 1 ] or nil
if not only or only . kind ~= "returnStmt" then
return nil
end
local values = only . exprs or { }

return # values == 1 and values [ 1 ] or nil
end






local function refinementTest ( clause )
local body = clause . body
if not body then
return nil , "empty"
end
local params = body . params or { }
local first = params [ 1 ]
if # params ~= 1 or not first or not first . name or first . name . text ~= "self" then
return nil , "parameter"
end
if body . kind == "shortfn" and body . expr then
return body . expr
end
local expression = returnedExpression ( body . kind == "shortfn" and body . body or body . body )
if not expression then
return nil , "body"
end

return expression
end









local function checkRefinement ( stat , n , clause )
local help = "a refinement tests the declaration's own fields: "
.. "`satisfies |self| -> self.kind == \"circle\"`"







if stat . declKind ~= "interface" then
c . diag (
"NUPP2122" ,
clause ,
(
"a %s is identified by what builds it, so a refinement would "
.. "be a second answer to the same question"
) : format ( stat . declKind ) ,
nil ,
{ help = "put it on an interface this declares with `is`, or " .. "remove it" }
)
return
end

local test , shape = refinementTest ( clause )
if not test then
local said = shape == "parameter"
and "a refinement takes the value it tests, and only that"
or shape == "body"
and "a refinement is one test, so its body is one `return`"
or "a refinement needs a test"
c . diag ( "NUPP2122" , clause , said , nil , { help = help } )
return
end


clause . expr = test

local built , why = predicate . build ( test )
if not built then
c . diag ( "NUPP2122" , clause , ( "a refinement cannot be %s" ) : format ( why ) , nil , { help = help } )
return
end

local always = predicate . constant ( built )
if always ~= nil then
c . diag (
"NUPP2122" ,
clause ,
always
and "this refinement is always true, so it identifies "
.. "every value rather than this declaration's"
or "this refinement is always false, so nothing can "
.. "ever be one of these" ,
nil ,
{ help = help }
)
return
end




local ok = true
for _ , path in ipairs ( predicate . paths ( built ) ) do
local current = n
for depth , segment in ipairs ( path ) do
local field = current and current . tag == "nominal" and current . byname and current . byname [ segment ] or nil
if not field then
c . diag (
"NUPP2122" ,
clause ,
(
"a refinement reads %q, which %s does not have"
) : format ( table . concat ( path , "." , 1 , depth ) , n . name ) ,
nil ,
{ help = help }
)
ok = false
break
end
current = field
end
end
if not ok then
return
end

n . predicate = built
end











local function checkInheritedRefinements ( stat , n )
local function fieldAt ( path )
local current = n
for _ , segment in ipairs ( path ) do
current = current and current . tag == "nominal" and current . byname and current . byname [ segment ] or nil
if not current then
return nil
end
end

return current
end

for _ , super in ipairs ( n . supertypes or { } ) do
if super . predicate then
if predicate . satisfiedBy ( super . predicate , fieldAt ) == false then
local at = nil
for _ , node in ipairs ( stat . supertypes or { } ) do
at = at or node
end
c . diag (
"NUPP2122" ,
at or stat . name ,
(
"%s declares %s, whose refinement its own fields " .. "cannot satisfy"
) : format ( n . name , super . name ) ,
nil ,
{
help = (
"`is %s` would answer no for every %s; change " .. "the fields or the refinement"
) : format ( super . name , n . name )
}
)
end
end
end
end







local function predeclareAssociated ( c , stat , n )
local written = { }
local typeNames = { }
for _ , e in ipairs ( stat . entries or { } ) do
if ( e . kind == "typeAlias" or e . kind == "recordDecl" ) and e . name then
typeNames [ e . name . text ] = e
end
end
for _ , e in ipairs ( stat . entries or { } ) do
if e . kind == "associatedDecl" and e . name then
local name = e . name . text
if written [ name ] then
c . diag (
"NUPP2129" ,
e . name ,
( "%s already has an associated type %q" ) : format ( stat . name . text , name ) ,
nil ,
{ help = "one declaration states each associated type once" }
)
elseif typeNames [ name ] then
c . diag ( "NUPP2129" , e . name , ( "%s already has a type member %q" ) : format ( stat . name . text , name ) , nil , {
help = "an associated type and a nested declaration share one "
.. "namespace; rename one of them"
} )
else
written [ name ] = e
if stat . declKind == "interface" then




n . associatedRequirements = n . associatedRequirements or { }
n . associatedRequirements [
# n . associatedRequirements + 1
] = setmetatable({ name =  name ,  selfBinder =  n . selfType }, T.AssociatedRequirement)
end
end
end
end

return written
end






local function checkAssociatedMember ( c , stat , n , e )
local name = e . name and e . name . text
if not name then
return nil
end
local definition = c . definition ( e . name , "type" )



definition . associated = true
local bound = e . bound and c . resolveType ( e . bound ) or nil
local value = e . value and c . resolveType ( e . value ) or nil
c . markToken ( e . name , definition , value or bound or T . unknown , "type" )
if stat . declKind == "interface" then
n . associatedRequirements = n . associatedRequirements or { }
local requirement = nil
for _ , candidate in ipairs ( n . associatedRequirements ) do
if candidate . name == name then
requirement = candidate
end
end
if not requirement then
requirement = setmetatable({ name =  name ,  selfBinder =  n . selfType }, T.AssociatedRequirement)
n . associatedRequirements [ # n . associatedRequirements + 1 ] = requirement
end
requirement . bound = bound
requirement . definition = definition
if value then
if bound and not isA ( value , bound ) then
c . diag (
"NUPP2116" ,
e . value ,
(
"%s does not fit the bound %s declares for %q"
) : format ( T . tostring ( value ) , stat . name . text , name ) ,
nil ,
{ help = "a default has to satisfy the bound beside it" }
)
end
n . associatedAnswers = n . associatedAnswers or { }
n . associatedAnswers [
name
] = setmetatable({ type =
value ,  selfBinder =
n . selfType ,  kind =
e . fixed and "fixed" or "default" ,  definition =
definition }, T.AssociatedAnswer)

end

return nil
end
if e . fixed then
c . diag (
"NUPP2128" ,
e . name ,
( "%s answers %q, so it says what it is with `=`" ) : format ( stat . name . text , name ) ,
nil ,
{
help = "`==` fixes an associated type on the contract that states it; "
.. "a concrete declaration already answers exactly"
}
)
end
if bound then
c . diag (
"NUPP2128" ,
e . bound ,
( "%s answers %q rather than stating it, so it cannot bound it" ) : format ( stat . name . text , name ) ,
nil ,
{ help = "what may answer an associated type is declared on the interface that states it" }
)
end
if not value then
c . diag (
"NUPP2128" ,
e . name ,
( "%s %q states a requirement, which only an interface can do" ) : format ( stat . declKind , name ) ,
nil ,
{
help = "nothing inherits from a "
.. stat . declKind
.. ", so nobody could answer it; write `associated type "
.. name
.. " = <type>` to answer one"
}
)

return nil
end
n . associatedAnswers = n . associatedAnswers or { }
n . associatedAnswers [
name
] = setmetatable({ type =  value ,  selfBinder =  n . selfType ,  kind =  "answer" ,  definition =  definition }, T.AssociatedAnswer)

return name
end


















local function checkAssociatedCycles ( c , stat , n , declared )
local reported = { }
for name , entry in pairs ( n . associatedAnswers or { } ) do



local observed = stat . declKind ~= "interface" or entry . kind == "fixed"
if observed then
local found = generics . normalize ( T . projection ( n , name ) )
local loop = found . cycle and table . concat ( found . cycle , " -> " ) or nil


local component = found . cycleKeys and table . concat ( found . cycleKeys , "\0" ) or nil
if loop and component and not reported [ component ] then
reported [ component ] = true
c . diag (
"NUPP2135" ,
declared [ name ] and declared [ name ] . name or stat . name ,
( "%s answers %q through itself: %s" ) : format ( n . name , name , loop ) ,
nil ,
{ help = "an associated type has to be answered with a type that does not reach it" }
)
end
end
end
end

local function checkAssociatedConformance ( c , stat , n , declared )
local associated = require ( "nupp.compiler.associated" )
local owed = associated . requirementNames ( n )
local owedSet = { }
for _ , name in ipairs ( owed ) do
owedSet [ name ] = true
end
for name , e in pairs ( declared ) do
if not owedSet [ name ] then
c . diag (
"NUPP2128" ,
e . name ,
( "%s answers %q, which no contract it takes states" ) : format ( n . name , name ) ,
nil ,
{
help = "declare `associated type "
.. name
.. "` on an interface this takes, or write `type "
.. name
.. " = <type>` for a nested alias that answers nothing"
}
)
end
end
if stat . declKind == "interface" then
return
end
for _ , name in ipairs ( owed ) do
local found = relations . associatedLookup ( n , name )
if found . reason == "missing" then
c . diag ( "NUPP2127" , stat . name , ( "%s does not name the associated type %q" ) : format ( n . name , name ) , nil , {
help = "add `associated type " .. name .. " = <type>` to its body"
} )
elseif found . reason == "conflict" then
c . diag (
"NUPP2127" ,
stat . name ,
( "%s takes contracts that default %q differently" ) : format ( n . name , name ) ,
nil ,
{ help = "write `associated type " .. name .. " = <type>` to say which it means" }
)
elseif found . reason == "contradicted" then
c . diag (
"NUPP2127" ,
declared [ name ] and declared [ name ] . name or stat . name ,
( "%s answers %q otherwise than the contract fixes it" ) : format ( n . name , name ) ,
nil ,
{
help = "a contract that fixes an associated type with `==` promises it; "
.. "every implementor answers exactly that"
}
)
elseif found . reason == "unfit" then
c . diag (
"NUPP2116" ,
declared [ name ] and declared [ name ] . value or stat . name ,
(
"%s does not fit what %q is bounded by"
) : format ( found . resolved and T . tostring ( found . resolved ) or "the answer" , name ) ,
nil ,
{ help = found . bound and ( "it has to be a " .. T . tostring ( found . bound ) ) or nil }
)
elseif found . answer and not declared [ name ] then


n . associatedAnswers = n . associatedAnswers or { }
n . associatedAnswers [ name ] = found . answer
end
end
end


local function inheritedDefault ( n , member )
for _ , super in ipairs ( n . supertypes or { } ) do
if super . defaultEntries and super . defaultEntries [ member ] then
return super . name
end
end

return nil
end







local function checkInheritedDefaults ( stat , n )
n . inheritedDefaults = { }
local providers = { }
for _ , super in ipairs ( n . supertypes or { } ) do
for member , inherited in pairs ( super . defaultEntries or { } ) do
local into = providers [ member ] or { }
into [ # into + 1 ] = { name = super . name , methodName = inherited . name , super = super }
providers [ member ] = into
n . inheritedDefaults [ member ] = super
end
end
local localSlots = { }
for _ , entries in pairs ( n . methodEntries or { } ) do
for _ , entry in ipairs ( entries ) do
localSlots [ entry . member ] = true
end
end
for member , from in pairs ( providers ) do
if # from > 1 and not localSlots [ member ] then
local names = { }
for j , provider in ipairs ( from ) do
names [ j ] = provider . name
end
table . sort ( names )
local methodName = from [ 1 ] . methodName
c . diag (
"NUPP2118" ,
stat . name ,
(
"%s inherits a default %q from %s, and cannot choose"
) : format ( n . name , methodName , table . concat ( names , " and " ) ) ,
nil ,
{ help = ( "write %s in %s to say which behaviour it means" ) : format ( methodName , n . name ) }
)
n . inheritedDefaults [ member ] = nil
elseif localSlots [ member ] then


n . inheritedDefaults [ member ] = nil
end
end

if stat . declKind == "interface" then
n . defaults = n . defaults or { }
n . defaultEntries = n . defaultEntries or { }
for member , super in pairs ( n . inheritedDefaults ) do
local inherited = super . defaultEntries [ member ]
n . defaults [ inherited . name ] = true
n . defaultEntries [
member
] = {
name = inherited . name ,
member = n . overloadedMethods [ inherited . name ] and member or inherited . member ,
slot = member ,
entry = inherited . entry
}
end
end



local byNominal = { }
for _ , node in ipairs ( stat . supertypes or { } ) do
local resolved = node . resolvedSupertype
if resolved and node . interfaceName then
byNominal [ resolved ] = node . interfaceName
end
end
for contract , runtimeName in pairs ( stat . deriveInterfaceRuntimeNames or { } ) do
byNominal [ contract ] = runtimeName
end
local taken = { }
for member , super in pairs ( n . inheritedDefaults ) do
local from = byNominal [ super ]
if from then
local inherited = super . defaultEntries [ member ]
taken [
# taken + 1
] = {
name = inherited . name ,
member = n . overloadedMethods [ inherited . name ] and member or inherited . member ,
fromMember = inherited . member ,
from = from
}
end
end
table . sort ( taken , function ( a , b )
return a . member < b . member
end )
stat . inheritedDefaultNames = taken
end







local function assignedFields ( node , out )
out = out or { }
if not node or cst . isToken ( node ) then
return out
end
if node . kind == "assignStmt" then
for _ , target in ipairs ( node . targets or { } ) do
local base = target . obj
if target . kind == "dotIndex"
and base
and base . kind == "name"
and base . token
and base . token . text == "self"
and target . name
then
out [ target . name . text ] = true
end
end
end
for _ , child in ipairs ( node ) do
assignedFields ( child , out )
end

return out
end







local function checkConstructor ( e , n , stat )
if stat . declKind == "interface" then
c . diag (
"NUPP2208" ,
e ,
"an interface declares a contract and builds nothing, so it " .. "cannot carry a constructor" ,
nil ,
{ help = "put the constructor on the records that declare it" }
)
return
end
if e . body and e . body . rets and # e . body . rets > 0 then
c . diag (
"NUPP2208" ,
e . body . rets [ 1 ] ,
"a constructor returns the value it builds, so it declares no " .. "return type" ,
nil ,
{ help = "remove the return annotation" }
)
end




if e . body and e . body . kind == "shortfn" and e . body . expr then
c . diag (
"NUPP2208" ,
e . body . expr ,
"a constructor returns the instance it fills in, so its body is statements" ,
nil ,
{ help = "write `-> do ... end`, or the `constructor(self, ...) ... end` form" }
)
return
end



local receiver = e . body and e . body . params and e . body . params [ 1 ]
if not ( receiver and receiver . name and receiver . name . text == "self" ) then
c . diag (
"NUPP2208" ,
e . body or e ,
"a constructor names the instance it fills in as its first parameter" ,
nil ,
{ help = "write `constructor(self, ...)`" }
)
end

local ft = c . checkFuncbody ( e . body , n )
c . raises . check ( e , e . body )

for _ , prior in ipairs ( n . constructorEntries or { } ) do
if prior . signature . paramPack . id == ft . paramPack . id then
c . diag (
"NUPP2208" ,
e ,
(
"%s already has a constructor with parameter pack %s"
) : format ( n . name , T . tostringPack ( ft . paramPack ) ) ,
nil ,
{ help = "constructor overloads need distinguishable parameter packs" }
)
return
end
end



local assigned = assignedFields ( e . body )



local order , seen = { } , { }
for _ , name in ipairs ( n . fieldOrder or { } ) do
order [ # order + 1 ] = name
seen [ name ] = true
end
local inherited = { }
for name in pairs ( n . byname or { } ) do
if not seen [ name ] then
inherited [ # inherited + 1 ] = name
end
end
table . sort ( inherited )
for _ , name in ipairs ( inherited ) do
order [ # order + 1 ] = name
end

local missing = { }
for _ , name in ipairs ( order ) do
local ft2 = n . byname [ name ]
if ft2 and ft2 . tag ~= "func" and ft2 . tag ~= "nominal" and not assigned [
name
] and not ( n . fieldDefaults and n . fieldDefaults [ name ] ) and not isA ( T . nil_ , ft2 ) then
missing [ # missing + 1 ] = name
end
end
if # missing > 0 then
c . diag (
"NUPP2208" ,
e ,
(
"this constructor leaves %s unset, and %s cannot hold nil"
) : format ( table . concat ( missing , ", " ) , # missing == 1 and "it" or "they" ) ,
nil ,
{ help = "assign every field, or declare the ones that may be " .. "absent as optional" }
)
end

n . constructors = n . constructors or { }
n . constructors [ # n . constructors + 1 ] = ft
n . constructorEntries = n . constructorEntries or { }
local index = # n . constructorEntries + 1
n . constructorEntries [ index ] = { signature = ft , declaration = e , index = index }
e . constructorIndex = index
e . ownerNominal = n
end

c . declaredNominal = function ( stat , kind )
local t , projectEntry = nil , nil
if c . env and c . env . declarationType then
t , projectEntry = c . env . declarationType ( c . env , c . filename , stat . name . text , kind , c . visibilityOf ( stat ) )
end

return t or T . nominal ( stat . name . text , kind ) , projectEntry
end

c . publishType = function ( stat , t , projectEntry )
local name = stat . name . text
local def = c . rootScope . typeDefs [ c . declKey ( stat ) ]
if projectEntry then
projectEntry . type = t
projectEntry . definition = def or projectEntry . definition
end
local visibility = c . visibilityOf ( stat )







if stat . qualifiers and # stat . qualifiers > 1 then
c . diag ( "NUPP2119" , stat . name , ( "declaration %q may attach to one table, not a path" ) : format ( name ) )
end



if stat . qualifiers and ( stat . visibility == "local" or stat . visibility == "global" ) then



local fixes = { }
if stat . modifier then
fixes [ 1 ] = fix ( ( "drop `%s`" ) : format ( stat . visibility ) , {
offset = stat . modifier . offset ,
length = ( stat . sealedTok or stat . keyword ) . offset - stat . modifier . offset ,
newText = ""
} )
end
c . diag (
"NUPP2119" ,
stat . name ,
(
"declaration %q says where it lives twice; drop `%s` or the " .. "table it names"
) : format ( name , stat . visibility ) ,
fixes
)
end
if visibility == "module"
and not stat . qualifiers
and not c . declarationFile
and not stat . isAnnotationDefinition
then
local suggestion = c . moduleLocal and (
"write it as %s.%s, or mark it local or global"
) : format ( c . moduleLocal , name ) or "mark it local or global, or attach it to a table"
local fixes = { }
if stat . keyword then
if c . moduleLocal then
fixes [
# fixes + 1
] = fix ( ( "attach it to %s" ) : format ( c . moduleLocal ) , insertBefore ( stat . name , c . moduleLocal .. "." ) )
end
local firstKeyword = stat . sealedTok or stat . keyword
fixes [ # fixes + 1 ] = fix ( "mark it local" , insertBefore ( firstKeyword , "local " ) )
fixes [ # fixes + 1 ] = fix ( "mark it global" , insertBefore ( firstKeyword , "global " ) )
end
c . diag ( "NUPP2119" , stat . name , ( "declaration %q has no visibility; %s" ) : format ( name , suggestion ) , fixes )
end
if visibility == "module" then
c . moduleExports . types [ name ] = t
c . moduleExports . typeDefs [ name ] = def
if t . tag == "nominal" and t . declKind == "struct" and not stat . isAnnotationDefinition then
c . moduleExports . values [ name ] = t
end
elseif visibility == "global" and c . env then



if not projectEntry then
c . env . globalTypes [ name ] = t
c . env . globalTypeDefs [ name ] = def
end
if not projectEntry
and not stat . isAnnotationDefinition
and t . tag == "nominal"
and t . declKind == "struct"
then
local entry = c . rootScope . vars [ name ]
if entry then
entry . globalModule = c . result . moduleName
c . env . globals [ name ] = entry
end
end
end
end

c . checkTypedecl = function ( stat )
local kind = stat . kind
if kind == "typeAlias" then
local name = c . declKey ( stat )
local t = stat . hoistedAlias and stat . hoistedAlias . resolved
if not t then
local owner = c . scope
while owner and not ( owner . pending and owner . pending [ name ] ) do
owner = owner . parent
end
if owner and stat . hoistedAlias then
t = c . resolvePendingAlias ( name , stat . hoistedAlias , owner )
end
end
t = t or c . resolveType ( stat . value )
stat . resolvedType = t
c . bindDeclaredType ( stat , t )
local projectEntry = nil
if c . env and c . env . declarationType then
local ignored
ignored , projectEntry = c . env . declarationType (
c . env ,
c . filename ,
stat . name . text ,
"type" ,
c . visibilityOf ( stat )
)
end
c . publishType ( stat , t , projectEntry )
elseif kind == "recordDecl" then
local n , projectEntry = stat . hoistedType , stat . hoistedEntry
if not n then
n , projectEntry = c . declaredNominal ( stat , stat . declKind )
end


n . byname = n . byname or { }
n . writeByname = n . writeByname or { }
n . staticByname = n . staticByname or { }
n . staticWriteByname = n . staticWriteByname or { }
n . metamethods = n . metamethods or { }
n . nestedTypes = n . nestedTypes or { }
n . methodEntries = { }
n . methodDispatchEntries = { }
n . overloadedMethods = { }
n . staticEntries = { }
n . overloadedStatics = { }
n . defaultEntries = { }
c . nominalEffectOwners [ n ] = true
n . annotations = stat . semanticAnnotations or { }

c . bindDeclaredType ( stat , n )




if stat . declKind == "record" and not stat . isAnnotationDefinition then
c . bindDeclaredVar ( stat , T . typeObject ( n ) )
end


c . pushScope ( )
n . selfType = c . typevarAt ( stat . name , "self" )




local selfBinder = n . selfType
selfBinder . bound = n
c . bindType ( "self" , n . selfType )



if c . qualifierOf ( stat ) then
c . bindType ( stat . name . text , n , nil )
end
if stat . generics then
local nominalTypes , nominalBounds , nominalPacks , nominalConsts , nominalKinds , nominalDefaults = c . bindGenerics (
stat . generics ,
"nominal" ,
n
)
n . typeParams , n . typeBounds , n . packParams = nominalTypes , nominalBounds , nominalPacks
n . constParams , n . paramKinds = nominalConsts , nominalKinds
n . paramDefaults = nominalDefaults
else
n . typeParams , n . typeBounds , n . packParams = nil , nil , nil
n . constParams , n . paramKinds = nil , nil
n . paramDefaults = nil
end
n . fieldOrder = { }
n . fieldDefaults = { }
n . fieldDefs = { }
n . writeFieldDefs = { }
n . staticFieldDefs = { }
n . staticWriteFieldDefs = { }
stat . resolvedType = n
n . moduleName = c . result . moduleName
if n . declKind == "interface" and stat . sealedTok then
n . sealedModule = n . moduleName or c . filename
end
if c . result . moduleName == "nupp.resources" and n . name == "Set" then
n . resourceSet = true
elseif c . result . moduleName == "nupp.dynamic" and n . name == "StoreState" then
n . dynamicStore = true
end



local declaredAssociated = predeclareAssociated ( c , stat , n )
local answeredAssociated = { }


for _ , e in ipairs ( stat . entries ) do
if e . kind == "recordDecl" then
local nestedKind = e . declKind
local nested = e . hoistedType or T . nominal ( e . name . text , nestedKind )
e . hoistedType = nested


nested . runtimePath = ( n . runtimePath or n . name ) .. "." .. e . name . text
c . bindType ( e . name . text , nested , e . name )
n . nestedTypes [ e . name . text ] = nested
if nestedKind == "record" or nestedKind == "struct" then



local held = nestedKind == "record" and T . typeObject ( nested ) or nested
n . byname [ e . name . text ] = held
n . writeByname [ e . name . text ] = held
end
end
end


n . supertypes = { }
for _ , superNode in ipairs ( stat . supertypes or { } ) do
local super = c . resolveType ( superNode )
if super . tag ~= "nominal" or super . declKind ~= "interface" then
c . diag (
"NUPP2117" ,
superNode ,
( "%s may inherit contracts only from interfaces" ) : format ( stat . declKind )
)
else
if super . sealedModule and super . sealedModule ~= ( c . result . moduleName or c . filename ) then
c . diag (
"NUPP2136" ,
superNode ,
(
"sealed interface %s may be implemented only in module %q"
) : format ( T . tostring ( super ) , super . sealedModule ) ,
nil ,
{
help = "use a value produced by the interface's module instead of declaring a new implementation"
}
)
end
n . supertypes [ # n . supertypes + 1 ] = super


superNode . resolvedSupertype = super
local selfMap = super . selfType and { [ super . selfType ] = n . selfType } or { }
for name , inherited in pairs ( super . byname or { } ) do
if not n . byname [ name ] then
n . byname [ name ] = substType ( inherited , selfMap )
end
end
for name in pairs ( super . overloadedMethods or { } ) do
n . overloadedMethods [ name ] = true
end
for name , inheritedEntries in pairs ( super . methodDispatchEntries or super . methodEntries or { } ) do
local into = n . methodDispatchEntries [ name ] or { }
for _ , entry in ipairs ( inheritedEntries ) do
into [
# into + 1
] = {
signature = substType ( entry . signature , selfMap ) ,
declaration = entry . declaration ,
member = entry . member ,
parameterKey = entry . parameterKey ,
definition = entry . definition ,
}
end
n . methodDispatchEntries [ name ] = into
end
for name , inherited in pairs ( super . writeByname or { } ) do
if not n . writeByname [ name ] then
n . writeByname [ name ] = substType ( inherited , selfMap )
end
end


if not n . indexReadValue and super . indexReadValue then
n . indexReadKey = substType ( super . indexReadKey , selfMap )
n . indexReadValue = substType ( super . indexReadValue , selfMap )
end
if not n . indexWriteValue and super . indexWriteValue then
n . indexWriteKey = substType ( super . indexWriteKey , selfMap )
n . indexWriteValue = substType ( super . indexWriteValue , selfMap )
end
for name , inherited in pairs ( super . metamethods or { } ) do
if not n . metamethods [ name ] then
n . metamethods [ name ] = substType ( inherited , selfMap )
end
end
end
end
c . derives . claim ( stat , n )





for _ , super in ipairs ( n . deriveClaimedContracts or { } ) do
local selfMap = super . selfType and { [ super . selfType ] = n . selfType } or { }
for name , inherited in pairs ( super . byname or { } ) do
if not n . byname [ name ] then
n . byname [ name ] = substType ( inherited , selfMap )
end
end
for name , inheritedEntries in pairs ( super . methodDispatchEntries or super . methodEntries or { } ) do
local into = n . methodDispatchEntries [ name ] or { }
for _ , entry in ipairs ( inheritedEntries ) do
into [
# into + 1
] = {
signature = substType ( entry . signature , selfMap ) ,
declaration = entry . declaration ,
member = entry . member ,
parameterKey = entry . parameterKey ,
definition = entry . definition ,
}
end
n . methodDispatchEntries [ name ] = into
end
for name , inherited in pairs ( super . writeByname or { } ) do
if not n . writeByname [ name ] then
n . writeByname [ name ] = substType ( inherited , selfMap )
end
end
end


for name , entries in pairs ( n . methodDispatchEntries ) do
local members , seen = { } , { }
for _ , entry in ipairs ( entries ) do
if not seen [ entry . member ] then
seen [ entry . member ] = true
members [ # members + 1 ] = entry . signature
end
end
if # members > 1 then
n . byname [ name ] = T . intersection ( members )
n . writeByname [ name ] = n . byname [ name ]
n . overloadedMethods [ name ] = true
end
end














for _ , e in ipairs ( stat . entries ) do
if e . kind == "associatedDecl" and declaredAssociated [ e . name and e . name . text or "" ] == e then
local answered = checkAssociatedMember ( c , stat , n , e )
if answered then
answeredAssociated [ answered ] = e
end
end
end
checkAssociatedConformance ( c , stat , n , answeredAssociated )
checkAssociatedCycles ( c , stat , n , answeredAssociated )

local inlineSignatures = { }
local staticSignatures = { }
for _ , e in ipairs ( stat . entries ) do
if e . kind == "inlineMethod" then
local receiver = hasReceiver ( e . body , stat . declKind )
e . inlineStatic = not receiver
local signature = c . signatureOf ( e . body , receiver and n or nil )
local name = e . name . text
local groups = receiver and inlineSignatures or staticSignatures
local group = groups [ name ] or { }
group [ # group + 1 ] = signature
groups [ name ] = group
end
end
for name , localSignatures in pairs ( inlineSignatures ) do
if # localSignatures == 1 and not n . overloadedMethods [ name ] then
n . byname [ name ] = localSignatures [ 1 ]
n . writeByname [ name ] = localSignatures [ 1 ]
else
local byParameters , order = { } , { }
local inherited = n . byname [ name ]
local inheritedMembers = inherited and inherited . tag == "intersection" and inherited . members or (
inherited and { inherited } or { }
)
for _ , signature in ipairs ( inheritedMembers ) do
if signature . tag == "func" then
local key = methodslots . parameters ( dropSelf ( signature ) )
if not byParameters [ key ] then
order [ # order + 1 ] = key
end
byParameters [ key ] = signature
end
end
for _ , signature in ipairs ( localSignatures ) do
local key = methodslots . parameters ( dropSelf ( signature ) )
if not byParameters [ key ] then
order [ # order + 1 ] = key
end
byParameters [ key ] = signature
end
local members = { }
for _ , key in ipairs ( order ) do
members [ # members + 1 ] = byParameters [ key ]
end
local combined = T . intersection ( members )
n . byname [ name ] = combined
n . writeByname [ name ] = combined
n . overloadedMethods [ name ] = # members > 1
end
end
for name , signatures in pairs ( staticSignatures ) do
if inlineSignatures [ name ] or n . byname [ name ] then
c . diag ( "NUPP2118" , stat , ( "static member %q conflicts with an instance member" ) : format ( name ) )
end
local combined = # signatures == 1 and signatures [ 1 ] or T . intersection ( signatures )
n . staticByname [ name ] = combined
n . staticWriteByname [ name ] = combined
n . overloadedStatics [ name ] = # signatures > 1
end
local localMembers , localMetamethods = { } , { }
for _ , e in ipairs ( stat . entries ) do
if e . kind == "fieldDecl" then
if e . privacy and stat . declKind ~= "record" then
c . diag ( "NUPP2209" , e . privacy , "private fields are available only on records" )
end
if e . type and e . type . kind == "tfunc" then
c . raises . checkParams ( e , ( e . type ) . params or { } )
end
local partitionApplication = nil
for _ , application in ipairs ( e . annotations or { } ) do
local definition2 , valid = validateAnnotation ( application , e , stat )
if definition2 and valid and application . name . text == "partition" then
partitionApplication = application
end
end
local ft = c . resolveType ( e . type )
if stat . declKind ~= "struct" then
c . fixedWidth . storageOnly ( e . type , ft , ( "the %q table-backed field" ) : format ( e . name . text ) )
end
if e . defaultValue then
if stat . declKind == "interface" or stat . isAnnotationDefinition then
c . diag (
"NUPP2202" ,
e . defaultValue ,
"only stored record and struct fields have construction defaults"
)
else
local value , constant = defaultValue ( e . defaultValue )
if not constant then
c . diag (
"NUPP2202" ,
e . defaultValue ,
"a field default must be a constant scalar or table value"
)
end
local actual = c . infer ( e . defaultValue )
if constant then
local ok , why , reported = c . fixedWidth . fits (
actual ,
ft ,
e . defaultValue ,
stat . declKind == "struct"
)
if not ok and not reported then
c . diag (
"NUPP2202" ,
e . defaultValue ,
"field default does not fit " .. T . tostring ( ft ) .. ( why and ( ": " .. why ) or "" )
)
else
n . fieldDefaults [ e . name . text ] = { value = value }
end
end
end
end
if partitionApplication then
local names , seen = { } , { }
for _ , argument in ipairs ( partitionApplication . annotationArgs or { } ) do
local expr = argument . expr
local name = expr and expr . kind == "name" and expr . token . text or nil
if name and not seen [ name ] then
seen [ name ] = true
names [ # names + 1 ] = name
end
end
local result = ft . tag == "func" and ft . rets [ 1 ] or nil
result = result and T . unwrapOwnership ( result ) or nil
if stat . declKind ~= "interface" or not n . sealedModule then
c . diag (
"NUPP2602" ,
partitionApplication ,
"@partition is available only on a sealed interface method"
)
elseif # names ~= 2 then
c . diag (
"NUPP2602" ,
partitionApplication ,
"@partition names exactly two sibling result fields"
)
elseif not result or result . tag ~= "nominal" or not result . byname [
names [ 1 ]
] or not result . byname [ names [ 2 ] ] then
c . diag (
"NUPP2602" ,
partitionApplication ,
"@partition names must be readable fields of the first result"
)
else
ft = T . withPartitionResults ( ft , { [ 1 ] = { [ names [ 1 ] ] = "L" , [ names [ 2 ] ] = "R" } } )
end
end
local fieldBorrowRelation = e . type and (
e . type . kind == "tborrows" and e . type or e . type . kind == "tfunc" and e . type . captureBorrows
) or nil
if fieldBorrowRelation then
local sources = fieldBorrowRelation . params or fieldBorrowRelation . names or {
fieldBorrowRelation . param
}
if stat . declKind ~= "record" then
c . diag ( "NUPP2602" , e , "borrowed field relations are available only on nominal records" )
elseif not sources [ 1 ] then
c . diag ( "NUPP2602" , e , "a borrowed field must name its sibling root field" )
else
n . fieldBorrowSources = n . fieldBorrowSources or { }
n . borrowedRootFields = n . borrowedRootFields or { }
n . fieldBorrowSources [ e . name . text ] = sources [ 1 ] . text
n . borrowedRootFields [ sources [ 1 ] . text ] = true
ft = T . borrowed ( ft )
end
elseif e . type and e . type . kind == "tpreserves" then
c . diag ( "NUPP2602" , e , "preserves is a callable result relation, not a field relation" )
end
local capability = e . capability and e . capability . propertyCapability or nil
if capability and ( stat . declKind == "struct" or stat . isAnnotationDefinition ) then
c . diag (
"NUPP2118" ,
e . capability ,
e . capability . text
.. " properties are available on records, "
.. "interfaces, and shapes, not "
.. (
stat . isAnnotationDefinition and "annotation schemas" or "structs"
)
)
capability = nil
end
if c . ownershipKind ( ft ) == "affine" or c . ownershipKind ( ft ) == "pinned" then
n . affineFields = n . affineFields or { }
n . affineFields [ # n . affineFields + 1 ] = e . name . text
end
local name = e . name . text
if e . privacy and stat . declKind == "record" then
n . privateFields = n . privateFields or { }
n . privateFields [ name ] = true
end
local state = localMembers [ name ]
if not state then
state = { }
localMembers [ name ] = state
n . fieldOrder [ # n . fieldOrder + 1 ] = name
end
local grantsRead = capability ~= "write"
local grantsWrite = capability ~= "read"
if ( grantsRead and state . read ) or ( grantsWrite and state . write ) then
c . diag ( "NUPP2118" , e . name , ( "duplicate property capability for %q" ) : format ( name ) )
end
local definition = c . definition ( e . name , "property" )
definition . type = ft
definition . annotations = e . semanticAnnotations or { }
if stat . declKind == "interface" and ft . tag == "intersection" then
local contracts , callable = { } , true
for _ , signature in ipairs ( ft . members ) do
if signature . tag ~= "func" then
callable = false
break
end
local plain = dropSelf ( signature )
contracts [
# contracts + 1
] = {
signature = signature ,
declaration = nil ,
member = methodslots . member ( name , plain ) ,
parameterKey = methodslots . parameters ( plain ) ,
definition = definition ,
}
end
if callable then
n . overloadedMethods [ name ] = true
n . methodDispatchEntries [ name ] = contracts
end
end
if grantsRead then
state . read = true
n . byname [ name ] = ft
n . fieldDefs [ name ] = definition
end
if grantsWrite then
state . write = true
n . writeByname [ name ] = ft
n . writeFieldDefs [ name ] = definition
end
c . markToken ( e . name , definition , ft , "property" )
if e . bitWidth then






if stat . declKind ~= "struct" or stat . isAnnotationDefinition then
c . diag (
"NUPP2201" ,
e . bitWidth ,
(
"field %q: a bit width belongs to a struct field, "
.. "which is the only kind laid out in C memory"
) : format ( e . name . text ) ,
nil ,
{ help = "drop the width, or declare the type a struct" }
)
elseif not BITFIELD_BASE [ ft . tag ] then
c . diag (
"NUPP2201" ,
e . bitWidth ,
(
"struct field %q: %s carries no bit width; C allows "
.. "one on an integer or boolean field only"
) : format ( e . name . text , T . tostring ( ft ) ) ,
nil ,
{ help = "drop the width, or give the field an " .. "integer or boolean type" }
)
end
end
if stat . declKind == "struct" and not stat . isAnnotationDefinition and not reifiableField ( ft ) then
c . diag (
"NUPP2201" ,
e ,
(
"struct field %q: %s is not reifiable " .. "(use a record for GC types, or a pointer)"
) : format ( e . name . text , T . tostring ( ft ) )
)
elseif stat . declKind == "struct" and not stat . isAnnotationDefinition then







local cycle = containedByValue ( ft , n )
if cycle then
c . diag (
"NUPP2201" ,
e ,
(
"struct field %q makes %s contain itself, which has " .. "no size"
) : format ( e . name . text , n . name ) ,
nil ,
{
help = cycle == n . name and (
"hold it by pointer instead: `%s: %s*`"
) : format (
e . name . text ,
n . name
) or (
"the cycle runs through %s; hold one step of it " .. "by pointer"
) : format ( cycle )
}
)
end
end
elseif e . kind == "indexerDecl" then
local key = c . resolveType ( e . key )
local value = c . resolveType ( e . value )
local capability = e . capability and e . capability . propertyCapability or nil
if stat . declKind == "struct" or stat . isAnnotationDefinition then
c . diag (
"NUPP2118" ,
e ,
"indexers are available on records and interfaces, not " .. (
stat . isAnnotationDefinition and "annotation schemas" or "structs"
)
)
else
local grantsRead = capability ~= "write"
local grantsWrite = capability ~= "read"
if grantsRead and n . indexReadValue then
c . diag ( "NUPP2118" , e , "duplicate readonly indexer capability" )
elseif grantsRead then
n . indexReadKey , n . indexReadValue = key , value
end
if grantsWrite and n . indexWriteValue then
c . diag ( "NUPP2118" , e , "duplicate writeonly indexer capability" )
elseif grantsWrite then
n . indexWriteKey , n . indexWriteValue = key , value
end
end
elseif e . kind == "arrayPart" then


local at = c . resolveType ( e . type )
if stat . declKind == "struct" then
c . diag ( "NUPP2204" , e , "a struct has no Lua array part " .. "(use a fixed C array field, T[N])" )
elseif at . tag ~= "array" then
c . diag ( "NUPP2205" , e , ( "an array part is written {T}, got %s" ) : format ( T . tostring ( at ) ) )
else
n . arrayOf = at . elem
end
elseif e . kind == "metamethodDecl" then
local mt = c . resolveType ( e . type )
if stat . declKind == "struct" then
c . diag (
"NUPP2118" ,
e ,
"struct metamethods need runtime ffi.metatype "
.. "installation and cannot be declaration-only"
)
elseif mt . tag ~= "func" then
c . diag ( "NUPP2118" , e , "a metamethod contract must be a function type" )
elseif not e . name . text : match ( "^__[%a%d_]+$" ) then
c . diag (
"NUPP2118" ,
e . name ,
"a metamethod name must begin with '__'" ,
c . edits . spellingFix ( e . name , operators . contractMetamethod )
)
elseif not operators . contractMetamethod [ e . name . text ] then
local fixes = not operators . runtimeMetamethod [
e . name . text
] and c . edits . spellingFix ( e . name , operators . contractMetamethod ) or nil
c . diag (
"NUPP2118" ,
e . name ,
( "metamethod %s is not dispatched by this LuaJIT " .. "target" ) : format ( e . name . text ) ,
fixes
)
elseif localMetamethods [ e . name . text ] then
c . diag ( "NUPP2118" , e . name , ( "duplicate metamethod contract %q" ) : format ( e . name . text ) )
else
localMetamethods [ e . name . text ] = true
n . metamethods [ e . name . text ] = mt
c . markToken ( e . name , c . definition ( e . name , "method" ) , mt , "method" )
end
elseif e . kind == "constructorDecl" then
refuseAot ( e , "a constructor" )
checkConstructor ( e , n , stat )
elseif e . kind == "inlineMethod" then
refuseAot ( e , "an inline interface requirement" )
local isOverride = false
for _ , application in ipairs ( e . annotations or { } ) do
local definition2 , valid = validateAnnotation ( application , e , stat )
if definition2 and valid then
if application . name . text == "override" then
isOverride = true
end
end
end
local name = e . name . text
local state = localMembers [ name ]
if state and not state . method then
c . diag ( "NUPP2118" , e . name , ( "duplicate record member %q" ) : format ( name ) )
end
if not state then
state = { read = true , write = true , method = true }
localMembers [ name ] = state
end
local receiver = hasReceiver ( e . body , stat . declKind )
local checked = c . checkFuncbody ( e . body , receiver and n or nil )
local ft = receiver and addSelf ( checked , n , e . body . receiverMode ) or checked
c . raises . check ( e , e . body )
local callable = ( receiver and dropSelf ( ft ) or ft )
local parameterKey = methodslots . parameters ( callable )
local memberName = methodslots . member ( name , callable )
local entryGroups = receiver and n . methodEntries or n . staticEntries
local entries = entryGroups [ name ] or { }
for _ , prior in ipairs ( entries ) do
if prior . parameterKey == parameterKey then
c . diag (
"NUPP2118" ,
e . name ,
(
"%s %q already has an entry with parameter pack %s"
) : format (
receiver and "method" or "static function" ,
name ,
T . tostringPack ( callable . paramPack )
) ,
nil ,
{
help = "overloads need distinguishable "
.. "parameter packs; return types do not select one"
}
)
end
end
local definition = c . definition ( e . name , receiver and "method" or "function" )
definition . type = ft
local entry = {
signature = ft ,
declaration = e ,
member = memberName ,
parameterKey = parameterKey ,
definition = definition
}
entries [ # entries + 1 ] = entry
entryGroups [ name ] = entries
if receiver then
e . methodEntry = entry










if not n . overloadedMethods [ name ] and # entries == 1 then
n . byname [ name ] = ft
n . writeByname [ name ] = ft
end
end



if receiver and stat . declKind == "interface" then
n . defaults = n . defaults or { }
n . defaults [ name ] = true
n . defaultEntries [
memberName
] = {
name = name ,
member = n . overloadedMethods [ name ] and memberName or name ,
slot = memberName ,
entry = entry
}
end
e . overridesDefault = receiver and inheritedDefault ( n , memberName ) or nil
if not receiver and isOverride then
c . diag ( "NUPP2118" , e . name , "a static function cannot override an instance default" , nil , {
help = "add `self` as the first parameter, or remove @override"
} )
elseif e . overridesDefault and not isOverride then
c . diag (
"NUPP2118" ,
e . name ,
(
"%q replaces the matching default %s declares, which " .. "has to be said"
) : format ( name , e . overridesDefault ) ,
nil ,
{ help = "write @override above it" }
)
elseif isOverride and not e . overridesDefault then
c . diag (
"NUPP2118" ,
e . name ,
(
"%q overrides nothing: no interface this declares " .. "provides that parameter pack"
) : format ( name ) ,
nil ,
{
help = "remove @override, or declare the interface "
.. "that provides the matching default"
}
)
end
if receiver then
n . fieldDefs [ name ] = n . fieldDefs [ name ] or definition
n . writeFieldDefs [ name ] = n . fieldDefs [ name ]
else
n . staticFieldDefs [ name ] = n . staticFieldDefs [ name ] or definition
n . staticWriteFieldDefs [ name ] = n . staticFieldDefs [ name ]
end
c . markToken ( e . name , definition , ft , receiver and "method" or "function" )
elseif e . kind == "recordDecl" or e . kind == "typeAlias" then
if stat . declKind == "struct" then
c . diag ( "NUPP2201" , e , "struct bodies hold fields only (no nested declarations)" )
else
c . checkTypedecl ( e )
local nested = e . resolvedType or e . hoistedType
if nested then
if nested . tag == "nominal" and not nested . runtimePath then
nested . runtimePath = ( n . runtimePath or n . name ) .. "." .. e . name . text
end
n . nestedTypes [ e . name . text ] = nested
if nested . tag == "nominal" and (
nested . declKind == "record" or nested . declKind == "struct"
) then
local held = nested . declKind == "record" and T . typeObject ( nested ) or nested
n . byname [ e . name . text ] = held
n . writeByname [ e . name . text ] = held
n . fieldDefs [ e . name . text ] = c . definition ( e . name , "property" )
n . writeFieldDefs [ e . name . text ] = n . fieldDefs [ e . name . text ]
end
end
end
end
end
for field , source in pairs ( n . fieldBorrowSources or { } ) do
if field == source then
c . diag ( "NUPP2602" , stat , ( "field %q cannot borrow from itself" ) : format ( field ) )
elseif not n . byname [ source ] then
c . diag ( "NUPP2109" , stat , ( "borrowed field %q names no sibling field %q" ) : format ( field , source ) )
elseif n . fieldBorrowSources [ source ] then
c . diag ( "NUPP2602" , stat , "borrowed field relations cannot form chains or cycles" )
end


n . writeByname [ field ] = nil
n . writeByname [ source ] = nil
n . writeFieldDefs [ field ] = nil
n . writeFieldDefs [ source ] = nil
end


for name , entries in pairs ( n . methodEntries ) do
local byMember , order , inheritedMembers = { } , { } , { }
for _ , entry in ipairs ( n . methodDispatchEntries [ name ] or { } ) do
if not byMember [ entry . member ] then
order [ # order + 1 ] = entry . member
end
byMember [ entry . member ] = entry
inheritedMembers [ entry . member ] = entry
end
local inheritedClaims = { }
for _ , entry in ipairs ( entries ) do
local inherited = inheritedMembers [ entry . member ]
if not inherited then
local localCallable = dropSelf ( entry . signature )
local positionalKey = methodslots . unlabeledParameters ( localCallable )
for _ , candidate in pairs ( inheritedMembers ) do
local inheritedCallable = dropSelf ( candidate . signature )
if methodslots . unlabeledParameters (
inheritedCallable
) == positionalKey and implementationLabelsFit ( localCallable , inheritedCallable ) then
inherited = candidate
break
end
end
end
if inherited then
local localCallable = dropSelf ( entry . signature )
local inheritedCallable = dropSelf ( inherited . signature )
local compatible , why = isA ( localCallable , inheritedCallable )
if not compatible then
c . diag (
"NUPP2118" ,
entry . declaration . name ,
(
"method %q does not satisfy its inherited " .. "overload: %s"
) : format ( name , why or "incompatible signature" )
)
end
local priorClaim = inheritedClaims [ inherited . member ]
if priorClaim and priorClaim ~= entry then
c . diag (
"NUPP2118" ,
entry . declaration . name ,
( "several local overloads implement the same inherited slot of %q" ) : format ( name )
)
else
inheritedClaims [ inherited . member ] = entry
entry . member = inherited . member
end
end
if not byMember [ entry . member ] then
order [ # order + 1 ] = entry . member
end
byMember [ entry . member ] = entry
end
local dispatch = { }
for _ , member in ipairs ( order ) do
dispatch [ # dispatch + 1 ] = byMember [ member ]
end
n . methodDispatchEntries [ name ] = dispatch
if stat . declKind ~= "interface" and n . overloadedMethods [ name ] then
for _ , entry in ipairs ( dispatch ) do
if not entry . declaration then
local plain = dropSelf ( entry . signature )
c . diag (
"NUPP2118" ,
stat . name ,
(
"%s does not implement overload %s of %q"
) : format ( n . name , T . tostringPack ( plain . paramPack ) , name ) ,
nil ,
{ help = "write a method body with that parameter pack" }
)
end
end
end
if n . overloadedMethods [ name ] then
for _ , entry in ipairs ( entries ) do
entry . declaration . overloadMember = entry . member
end
end
end
for _ , entries in pairs ( n . staticEntries ) do
if # entries > 1 then
for _ , entry in ipairs ( entries ) do
entry . declaration . overloadMember = entry . member
end
end
end
c . derives . merge ( stat , n )





for _ , e in ipairs ( stat . entries ) do
if e . kind == "satisfiesDecl" then
if n . predicate then
c . diag ( "NUPP2122" , e , ( "%s already declares how it is matched" ) : format ( n . name ) , nil , {
help = "combine the tests with `and`"
} )
else
checkRefinement ( stat , n , e )
end
end
end



if stat . whereClause then
c . diag (
"NUPP2122" ,
stat . whereClause ,
"a refinement is written as a `satisfies` declaration in the body" ,
nil ,
{ help = "write `satisfies |self| -> <test>` among the fields" }
)
end









if stat . declKind == "interface" and not n . predicate then
local derived = nil
for _ , name in ipairs ( n . fieldOrder or { } ) do
local ft = n . byname [ name ]
if ft and ft . tag == "literal" then
derived = predicate . both ( derived , predicate . equals ( { name } , ft . constant ) )
end
end
n . predicate = derived
end






if n . predicate then
local associatedMod = require ( "nupp.compiler.associated" )
for _ , owed in ipairs ( associatedMod . requirementNames ( n ) ) do
local settled = relations . associatedLookup ( n , owed )



local resolvedTo = settled . resolved
local unsettled = resolvedTo == nil
or settled . reason ~= nil
or settled . gradual == true
or resolvedTo == T . any
or (
resolvedTo ~= nil and resolvedTo . tag == "projection"
)
if unsettled then
c . diag (
"NUPP2122" ,
stat . name ,
( "%s refines, but leaves %q unsettled" ) : format ( n . name , owed ) ,
nil ,
{
help = "a refinement is a run-time test and an associated type is erased; "
.. "fix it with `associated type "
.. owed
.. " == <type>`, or drop the refinement"
}
)
end
end
end
checkInheritedDefaults ( stat , n )
checkInheritedRefinements ( stat , n )



relations . invalidate ( )
c . popScope ( )
if stat . isAnnotationDefinition then


elseif stat . declKind == "struct" then

c . bindDeclaredVar ( stat , n )
elseif stat . declKind == "record" then





suggestStruct ( stat , n )
else



c . bindDeclaredVar ( stat , T . metatable ( n ) )
end
c . publishType ( stat , n , projectEntry )
end
end
end

return declare
