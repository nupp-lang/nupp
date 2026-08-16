_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
















local types = { }









































types.Prim = {} types.Prim.__index = types.Prim





types.Array = {} types.Array.__index = types.Array






types.Map = {} types.Map.__index = types.Map
















types.Tuple = {} types.Tuple.__index = types.Tuple






types.Shape = {} types.Shape.__index = types.Shape





















types.Union = {} types.Union.__index = types.Union












types.Intersection = {} types.Intersection.__index = types.Intersection








types.Ptr = {} types.Ptr.__index = types.Ptr






types.CArray = {} types.CArray.__index = types.CArray








types.ConstLiteral = {} types.ConstLiteral.__index = types.ConstLiteral







types.ConstVar = {} types.ConstVar.__index = types.ConstVar







types.ConstOp = {} types.ConstOp.__index = types.ConstOp








types.ComptimeTypeArgument = {} types.ComptimeTypeArgument.__index = types.ComptimeTypeArgument




types.ComptimePackArgument = {} types.ComptimePackArgument.__index = types.ComptimePackArgument




types.ComptimeConstArgument = {} types.ComptimeConstArgument.__index = types.ComptimeConstArgument











types.Cleanup = {} types.Cleanup.__index = types.Cleanup

















types.Affine = {} types.Affine.__index = types.Affine














types.Borrowed = {} types.Borrowed.__index = types.Borrowed






types.Pinned = {} types.Pinned.__index = types.Pinned








types.Obligation = {} types.Obligation.__index = types.Obligation







types.Loan = {} types.Loan.__index = types.Loan








types.PinnedAnchor = {} types.PinnedAnchor.__index = types.PinnedAnchor





types.ForeignRetention = {} types.ForeignRetention.__index = types.ForeignRetention







types.CapabilityFacts = {} types.CapabilityFacts.__index = types.CapabilityFacts


















types.Capability = {} types.Capability.__index = types.Capability








types.ValueSlot = {} types.ValueSlot.__index = types.ValueSlot





types.Const = {} types.Const.__index = types.Const






types.CType = {} types.CType.__index = types.CType






types.PackVar = {} types.PackVar.__index = types.PackVar

















types.Pack = {} types.Pack.__index = types.Pack









types.ProtocolThread = {} types.ProtocolThread.__index = types.ProtocolThread









types.GenericAlias = {} types.GenericAlias.__index = types.GenericAlias













types.Func = {} types.Func.__index = types.Func











































































































types.Literal = {} types.Literal.__index = types.Literal











types.TypeVar = {} types.TypeVar.__index = types.TypeVar









types.TypeHandle = {} types.TypeHandle.__index = types.TypeHandle






types.PackResult = {} types.PackResult.__index = types.PackResult







types.Neutral = {} types.Neutral.__index = types.Neutral























types.Metatable = {} types.Metatable.__index = types.Metatable








types.TypeObject = {} types.TypeObject.__index = types.TypeObject














types.Projection = {} types.Projection.__index = types.Projection
















types.AssociatedRequirement = {} types.AssociatedRequirement.__index = types.AssociatedRequirement























types.AssociatedAnswer = {} types.AssociatedAnswer.__index = types.AssociatedAnswer



















types.AssociatedReached = {} types.AssociatedReached.__index = types.AssociatedReached
























types.AssociatedLookup = {} types.AssociatedLookup.__index = types.AssociatedLookup
































types.Nominal = {} types.Nominal.__index = types.Nominal






























































































































































































































































local arena = { }

local packArena = { }
local packVarArena = { }
local capabilityArena = { }
local capabilityIdentity = setmetatable ( { } , { __mode = "k" } )
local nextCapabilityIdentity = 0
local constArena = { }

local function flowIdentity ( value )
if value == nil then
return 0
end
local found = capabilityIdentity [ value ]
if found then
return found
end
nextCapabilityIdentity = nextCapabilityIdentity + 1
capabilityIdentity [ value ] = nextCapabilityIdentity

return nextCapabilityIdentity
end














local nextSerial = 0

local function serial ( prefix )
nextSerial = nextSerial + 1

return prefix .. nextSerial
end













local MARK_TYPEVAR = "!t"

local MARK_PACKVAR = "!p"
local MARK_CONSTVAR = "!c"
local MARK_PROJECTION = "!j"
local MARKS = { MARK_TYPEVAR , MARK_PACKVAR , MARK_CONSTVAR , MARK_PROJECTION }


local function inheritedMarks ( key )
local marks = ""
for _ , mark in ipairs ( MARKS ) do
if key : find ( mark , 1 , true ) then
marks = marks .. mark
end
end

return marks
end













local function canonicalOrder ( a , b )
if a . tag ~= b . tag then
return a . tag < b . tag
end
if a . tag == "literal" then
local left = tostring ( ( a ) . constant )
local right = tostring ( ( b ) . constant )
if left ~= right then
return left < right
end
end
if a . tag == "nominal" then
local left , right = ( a ) . name , ( b ) . name
if left ~= right then
return left < right
end
end

return a . id < b . id
end





local function intern ( key , made )
local found = arena [ key ]
if found then
return found
end
made . id = inheritedMarks ( key ) .. serial ( "t" )
arena [ key ] = made

return made
end














local function interned ( key )
return arena [ key ]
end


local function prim ( tag )
local existing = interned ( tag )
if existing then
return existing
end

return intern ( tag , setmetatable({ tag =  tag }, types.Prim) )
end

types . any = prim ( "any" )



types . unknown = prim ( "unknown" )


types . never = prim ( "never" )
types . nil_ = prim ( "nil" )
types . boolean = prim ( "boolean" )
types . string = prim ( "string" )
types . number = prim ( "number" )
types . integer = prim ( "integer" )
types . table_ = prim ( "table" )
types . thread = prim ( "thread" )
types . userdata = prim ( "userdata" )



types . float = prim ( "float" )


types . cdata = prim ( "cdata" )


types . cstring = prim ( "cstring" )
types . voidptr = prim ( "voidptr" )

types . int8 = prim ( "int8" )
types . int16 = prim ( "int16" )
types . int32 = prim ( "int32" )
types . int64 = prim ( "int64" )
types . uint8 = prim ( "uint8" )
types . uint16 = prim ( "uint16" )
types . uint32 = prim ( "uint32" )
types . uint64 = prim ( "uint64" )


types . type_ = prim ( "type" )
types . typepack = prim ( "typepack" )
types . functionConst = prim ( "functionconst" )



local TABLE_SHAPED

= { array = true , map = true , tuple = true , shape = true , metatable = true , typeobject = true , nominal = true , }


local builtins

= {
any = types . any ,
unknown = types . unknown ,
never = types . never ,
boolean = types . boolean ,
string = types . string ,
number = types . number ,
integer = types . integer ,
table = types . table_ ,
thread = types . thread ,
userdata = types . userdata ,
float = types . float ,
int8 = types . int8 ,
int16 = types . int16 ,
int32 = types . int32 ,
int64 = types . int64 ,
uint8 = types . uint8 ,
uint16 = types . uint16 ,
uint32 = types . uint32 ,
uint64 = types . uint64 ,
cstring = types . cstring ,
voidptr = types . voidptr ,
cdata = types . cdata ,
type = types . type_ ,
typepack = types . typepack ,
[ "nil" ] = types . nil_ ,
}

types . builtins = builtins







function types . array ( elem )
local internKey = "{" .. elem . id .. "}"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "array" ,  elem =  elem }, types.Array) )
end



function types . map ( key , value )
return types . indexer ( key , value , key , value )
end


function types . indexer (
readKey ,
readValue ,
writeKey ,
writeValue
)
local key = readKey or writeKey or types . never
local value = readValue or writeValue or types . never
local id = "index(" .. (
readKey and readKey . id or "-"
) .. ":" .. (
readValue and readValue . id or "-"
) .. "," .. ( writeKey and writeKey . id or "-" ) .. ":" .. ( writeValue and writeValue . id or "-" ) .. ")"

local existing = interned ( id )
if existing then
return existing
end

return intern (
id , setmetatable({ tag =

"map" ,  key =
key ,  value =
value ,  readable =
readValue ~= nil ,  writeKey =
writeKey ,  writeValue =
writeValue }, types.Map)

)
end


function types . tuple ( elems )
local ids = { }
for j , e in ipairs ( elems ) do
ids [ j ] = e . id
end

local internKey = "tuple(" .. table . concat ( ids , "," ) .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "tuple" ,  elems =  elems }, types.Tuple) )
end






function types . shape ( fields , indexer , fresh )
local sorted = { }
for j , f in ipairs ( fields ) do
sorted [ j ] = f
end
table . sort ( sorted , function ( a , b )
return a . name < b . name
end )
local parts = { }
local byname = { }
local writeByname = { }
for _ , f in ipairs ( sorted ) do
local read = f . read
local write = f . write
if f . type then
if f . capability == "read" then
read = f . type
elseif f . capability == "write" then
write = f . type
else
read , write = f . type , f . type
end
end
f . read , f . write = read , write
parts [ # parts + 1 ] = f . name .. ":r=" .. ( read and read . id or "-" ) .. ":w=" .. ( write and write . id or "-" )
if read then
byname [ f . name ] = read
end
if write then
writeByname [ f . name ] = write
end
end
local irk = indexer and indexer . readKey or nil
local irv = indexer and indexer . readValue or nil
local iwk = indexer and indexer . writeKey or nil
local iwv = indexer and indexer . writeValue or nil
parts [
# parts + 1
] = "[r=" .. (
irk and irk . id or "-"
) .. ":" .. ( irv and irv . id or "-" ) .. ":w=" .. ( iwk and iwk . id or "-" ) .. ":" .. ( iwv and iwv . id or "-" ) .. "]"
local key = "shape(" .. table . concat ( parts , "," ) .. ")" .. ( fresh and "!fresh" or "" )

local existing = interned ( key )
if existing then
return existing
end

return intern (
key , setmetatable({ tag =

"shape" ,  fields =
sorted ,  byname =
byname ,  writeByname =
writeByname ,  indexReadKey =
irk ,  indexReadValue =
irv ,  indexWriteKey =
iwk ,  indexWriteValue =
iwv ,  fresh =
fresh or nil }, types.Shape)

)
end








local function pushUnionMember (
t ,
seen ,
flat ,
functionByContract
)
if t . tag == "union" then
for _ , m in ipairs ( t . members ) do
pushUnionMember ( m , seen , flat , functionByContract )
end
elseif t . tag == "func" and functionByContract [ t . unlabeledId ] then
local at = functionByContract [ t . unlabeledId ]
local prior = flat [ at ]
if prior ~= t then


local merged = types . func (
prior . params ,
prior . rets ,
prior . vararg ,
prior . paramModes ,
prior . predicate ,
prior . typeParams ,
prior . typeBounds ,
prior . borrowsParam ,
prior . borrowsSelf ,
prior . borrowsParams ,
prior . ffiOut ,
prior . varargType ,
prior . noreturn ,
prior . paramPack ,
prior . retPack ,
prior . packParams ,
prior . yieldPack ,
prior . resumePack ,
prior . noYield ,
nil ,
prior . preservesResults ,
prior . foreign ,
prior . constParams ,
prior . paramKinds ,
prior . partitionResults ,
prior . comptimeOnly ,
prior . explicitPreserves
)
seen [ prior ] = nil
seen [ merged ] = true
flat [ at ] = merged
end
elseif not seen [ t ] then
seen [ t ] = true
flat [ # flat + 1 ] = t
if t . tag == "func" then
functionByContract [ t . unlabeledId ] = # flat
end
end
end







function types . union ( members )
local seen = { }
local flat = { }
local functionByContract = { }

for _ , m in ipairs ( members ) do
pushUnionMember ( m , seen , flat , functionByContract )
end
if # flat == 1 then
return flat [ 1 ]
end

for _ , m in ipairs ( flat ) do
if m == types . any then
return types . any
end
end





local structured = false
for _ , m in ipairs ( flat ) do
if TABLE_SHAPED [ m . tag ] then
structured = true
end
end
if structured then
local kept = { }
for _ , m in ipairs ( flat ) do
if m ~= types . table_ then
kept [ # kept + 1 ] = m
end
end
flat = kept
if # flat == 1 then
return flat [ 1 ]
end
end
table . sort ( flat , canonicalOrder )
local ids = { }
for j , m in ipairs ( flat ) do
ids [ j ] = m . id
end

local internKey = "union(" .. table . concat ( ids , "|" ) .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

local hasNil = false
for _ , m in ipairs ( flat ) do
if m == types . nil_ then
hasNil = true
end
end

return intern ( internKey , setmetatable({ tag =  "union" ,  members =  flat ,  hasNil =  hasNil }, types.Union) )
end







local function pushIntersectionMember ( t , seen , flat )
if t == types . never then
for index = # flat , 1 , - 1 do
flat [ index ] = nil
end
for member in pairs ( seen ) do
seen [ member ] = nil
end
flat [ 1 ] = types . never
seen [ types . never ] = true
elseif t . tag == "intersection" then
for _ , m in ipairs ( t . members ) do
pushIntersectionMember ( m , seen , flat )
end
elseif t ~= types . unknown and t ~= types . any and not seen [ t ] and not seen [ types . never ] then
seen [ t ] = true
flat [ # flat + 1 ] = t
end
end





function types . intersection ( members )
local seen = { }
local flat = { }

for _ , m in ipairs ( members ) do
pushIntersectionMember ( m , seen , flat )
end
if # flat == 0 then
return types . unknown
end
if # flat == 1 then
return flat [ 1 ]
end
table . sort ( flat , canonicalOrder )
local ids = { }
for j , m in ipairs ( flat ) do
ids [ j ] = m . id
end

local internKey = "intersection(" .. table . concat ( ids , "&" ) .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "intersection" ,  members =  flat }, types.Intersection) )
end


function types . optional ( t )
return types . union ( { t , types . nil_ } )
end


function types . ptr ( t )
local internKey = t . id .. "*"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "ptr" ,  elem =  t }, types.Ptr) )
end


function types . functionCleanup ( key , name , functionType )
return setmetatable({ id =
"function:" .. key ,  kind =
"function" ,  key =
key ,  name =
name ,  functionType =
functionType ,  constTerm =
types . constLiteral ( "function" , key ) }, types.Cleanup)

end


function types . constFunctionCleanup ( term , name , functionType )
local key = term . tag == "constLiteral" and term . domain == "function" and term . value or nil
return setmetatable({ id =
key and "function:" .. key or "functionconst:" .. term . id ,  kind =
"function" ,  key =
key ,  name =
name or key and ( key : match ( "#(.*)$" ) or key ) or types . tostringConst ( term ) ,  functionType =
functionType ,  constTerm =
term }, types.Cleanup)

end


function types . closureCleanup ( )
return setmetatable({ id =  "generated:closure" ,  kind =  "closure" }, types.Cleanup)
end


function types . fieldCleanup ( field , cleanup )
return setmetatable({ id =
"field:" .. field .. ":" .. cleanup . id ,  kind =
"field" ,  field =
field ,  cleanup =
cleanup }, types.Cleanup)

end


function types . dropFieldCleanup ( field )
return setmetatable({ id =  "dropfield:" .. field ,  kind =  "dropfield" ,  field =  field }, types.Cleanup)
end







local function obligationId ( obligation )
if not obligation then
return "none"
end
if obligation . kind == "cleanup" then
return "cleanup(" .. (
obligation . cleanup and obligation . cleanup . id or "?"
) .. ")@" .. ( obligation . component or "" )
elseif obligation . kind == "transfer-only" then
return "transfer@" .. ( obligation . component or "" )
elseif obligation . kind ~= "aggregate" then
return "none"
end
local children = { }
for j , child in ipairs ( obligation . children or { } ) do
children [ j ] = obligationId ( child )
end

return "aggregate(" .. table . concat ( children , "," ) .. ")@" .. ( obligation . component or "" )
end

function types . cleanupObligation ( cleanup , component )
return setmetatable({ kind =  "cleanup" ,  cleanup =  cleanup ,  component =  component }, types.Obligation)
end

function types . transferObligation ( component )
return setmetatable({ kind =  "transfer-only" ,  component =  component }, types.Obligation)
end

function types . aggregateObligation ( children , component )
return setmetatable({ kind =  "aggregate" ,  children =  children ,  component =  component }, types.Obligation)
end

local function obligationFrom ( cleanups , transferOnly )
local children = { }
for _ , cleanup in ipairs ( cleanups ) do
children [ # children + 1 ] = types . cleanupObligation ( cleanup , cleanup . field )
end
if transferOnly or # children == 0 then
children [ # children + 1 ] = types . transferObligation ( )
end
if # children == 1 and not children [ 1 ] . component then
return children [ 1 ]
end

return types . aggregateObligation ( children )
end

function types . affine (
t ,
cleanups ,
transferOnly ,
obligation
)
local list = { }
local ids = { }
for j , cleanup in ipairs ( cleanups or { } ) do
list [ j ] = cleanup
ids [ j ] = cleanup . id
end

obligation = obligation or obligationFrom ( list , transferOnly )
local internKey = "affine(" .. table . concat (
ids ,
","
) .. ":" .. t . id .. ( transferOnly and ":transfer" or "" ) .. ":" .. obligationId ( obligation ) .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern (
internKey , setmetatable({ tag =

"affine" ,  inner =
t ,  cleanups =
list ,  transferOnly =
transferOnly == true ,  obligation =
obligation }, types.Affine)

)
end

function types . obligationFor ( t )
return t . tag == "affine" and t . obligation or nil
end

function types . borrowed ( t )
local internKey = "borrowed(" .. t . id .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "borrowed" ,  inner =  t }, types.Borrowed) )
end




function types . pinned ( t )
local internKey = "pinned(" .. t . id .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "pinned" ,  inner =  t }, types.Pinned) )
end


function types . unwrapOwnership ( t )
if t . tag == "affine" or t . tag == "borrowed" or t . tag == "pinned" then
return t . inner
end
return t
end

local function sortedFlowValues ( values )
local result , seen = { } , { }
for _ , value in ipairs ( values or { } ) do
if value ~= nil and not seen [ value ] then
seen [ value ] = true
result [ # result + 1 ] = value
end
end
table . sort ( result , function ( left , right )
return flowIdentity ( left ) < flowIdentity ( right )
end )

return result
end

local function loanId ( loan )
local roots = { }
for j , root in ipairs ( loan . roots ) do
roots [ j ] = tostring ( flowIdentity ( root ) )
end

return loan . access .. ":" .. tostring (
flowIdentity ( loan . regionRoot )
) .. ":" .. loan . regionPath .. ":" .. table . concat ( roots , "," ) .. "@" .. ( loan . component or "" )
end

local function anchorId ( anchor )
return tostring ( flowIdentity ( anchor . root ) ) .. "@" .. ( anchor . component or "" )
end

local function retentionId ( retention )
return tostring ( flowIdentity ( retention . identity ) ) .. "@" .. ( retention . component or "" )
end



function types . capability ( t , facts )
facts = facts or setmetatable({ }, types.CapabilityFacts)
local obligation = types . obligationFor ( t )
local loans = { }
for _ , loan in ipairs ( facts . loans or { } ) do
loans [ # loans + 1 ] = loan
end
local roots = sortedFlowValues ( facts . roots )
if t . tag == "borrowed" or # roots > 0 or facts . regionRoot then
loans [
# loans + 1
] = setmetatable({ roots =
roots ,  access =
facts . exclusive and "exclusive" or "shared" ,  regionRoot =
facts . regionRoot or roots [ 1 ] ,  regionPath =
facts . regionPath or "" ,  component =
facts . component }, types.Loan)

end
for j = 2 , # loans do
local value , k = loans [ j ] , j - 1
while k > 0 and loanId ( value ) < loanId ( loans [ k ] ) do
loans [ k + 1 ] = loans [ k ]
k = k - 1
end
loans [ k + 1 ] = value
end

local anchors = { }
for _ , anchor in ipairs ( facts . anchors or { } ) do
anchors [ # anchors + 1 ] = anchor
end
if t . tag == "pinned" and # anchors == 0 then
anchors [ 1 ] = setmetatable({ root =  facts . anchor or t ,  component =  facts . component }, types.PinnedAnchor)
end
for j = 2 , # anchors do
local value , k = anchors [ j ] , j - 1
while k > 0 and anchorId ( value ) < anchorId ( anchors [ k ] ) do
anchors [ k + 1 ] = anchors [ k ]
k = k - 1
end
anchors [ k + 1 ] = value
end

local retentions = { }
for _ , retention in ipairs ( facts . retentions or { } ) do
retentions [ # retentions + 1 ] = retention
end
if facts . retention then
retentions [
# retentions + 1
] = setmetatable({ identity =  facts . retention ,  component =  facts . component }, types.ForeignRetention)
end
for j = 2 , # retentions do
local value , k = retentions [ j ] , j - 1
while k > 0 and retentionId ( value ) < retentionId ( retentions [ k ] ) do
retentions [ k + 1 ] = retentions [ k ]
k = k - 1
end
retentions [ k + 1 ] = value
end

local loanIds , anchorIds , retentionIds = { } , { } , { }
for j , loan in ipairs ( loans ) do
loanIds [ j ] = loanId ( loan )
end
for j , anchor in ipairs ( anchors ) do
anchorIds [ j ] = anchorId ( anchor )
end
for j , retention in ipairs ( retentions ) do
retentionIds [ j ] = retentionId ( retention )
end
local id = obligationId (
obligation
) .. ":loans=" .. table . concat (
loanIds ,
";"
) .. ":anchors=" .. table . concat ( anchorIds , ";" ) .. ":retentions=" .. table . concat ( retentionIds , ";" )
local found = capabilityArena [ id ]
if found then
return found
end
local made = setmetatable({ id =
id ,  obligation =
obligation ,  loans =
loans ,  anchors =
anchors ,  retentions =
retentions }, types.Capability)

capabilityArena [ id ] = made

return made
end

function types . capabilityKind ( capability )
if capability . obligation then
return "affine"
elseif # capability . anchors > 0 or # capability . retentions > 0 then
return "pinned"
elseif # capability . loans > 0 then
return "borrowed"
end

return nil
end

function types . capabilityHasMovable ( capability )
return capability . obligation ~= nil or # capability . anchors > 0 or # capability . retentions > 0
end

local function collectObligationCleanups ( obligation , into )
if not obligation then
return
end
if obligation . kind == "cleanup" and obligation . cleanup then
into [ # into + 1 ] = obligation . cleanup
else
for _ , child in ipairs ( obligation . children or { } ) do
collectObligationCleanups ( child , into )
end
end
end

function types . capabilityCleanups ( capability )
local cleanups = { }
collectObligationCleanups ( capability . obligation , cleanups )
return cleanups
end

local function obligationHasTransfer ( obligation )
if not obligation then
return false
end
if obligation . kind == "transfer-only" then
return true
elseif obligation . kind == "cleanup" then
return false
elseif obligation . kind ~= "aggregate" then
return false
end
for _ , child in ipairs ( obligation . children or { } ) do
if obligationHasTransfer ( child ) then
return true
end
end

return false
end

function types . capabilityTransferOnly ( capability )
return obligationHasTransfer ( capability . obligation )
end

function types . valueSlot ( t , facts )
return setmetatable({ payload =  types . unwrapOwnership ( t ) ,  capability =  types . capability ( t , facts ) }, types.ValueSlot)
end




local function regionAppend ( path , kind , value )
return ( path or "" ) .. "/" .. kind .. tostring ( # value ) .. ":" .. value
end

function types . regionField ( path , name )
return regionAppend ( path , "F" , name )
end

function types . regionTupleSlot ( path , slot )
return regionAppend ( path , "T" , tostring ( slot ) )
end

function types . regionDeref ( path )
return regionAppend ( path , "D" , "" )
end

function types . regionIndex ( path , index )
return regionAppend ( path , index and "I" or "U" , index and tostring ( index ) or "" )
end



function types . regionRange ( path , first , last )
if not first or not last then
return regionAppend ( path , "U" , "" )
end

return regionAppend ( path , "R" , tostring ( first ) .. ":" .. tostring ( last ) )
end

function types . regionPartition ( path , side )
return regionAppend ( path , "P" , side )
end

local function regionSegments ( path )



local result = { }
path = path or ""
local at = 1
while at <= # path do
if path : sub ( at , at ) ~= "/" then


local legacy = path : sub ( at , at )
result [ # result + 1 ] = { kind = "P" , value = legacy == "L" and "left" or "right" }
at = at + 1
else
local kind = path : sub ( at + 1 , at + 1 )
local colon = path : find ( ":" , at + 2 , true )
if not colon then
return { { kind = "U" , value = "" } }
end
local length = tonumber ( path : sub ( at + 2 , colon - 1 ) )
if not length then
return { { kind = "U" , value = "" } }
end
local value = path : sub ( colon + 1 , colon + length )
result [ # result + 1 ] = { kind = kind , value = value }
at = colon + length + 1
end
end

return result
end

function types . regionsOverlap ( left , right )
local a , b = regionSegments ( left ) , regionSegments ( right )
local common = math . min ( # a , # b )
for j = 1 , common do
local x , y = a [ j ] , b [ j ]
if x . kind == "U" or y . kind == "U" then
return true
end
if x . kind == "R" and y . kind == "R" then
local xf , xl = x . value : match ( "^(-?%d+):(-?%d+)$" )
local yf , yl = y . value : match ( "^(-?%d+):(-?%d+)$" )
if not xf or not yf then
return true
end
if tonumber ( xl ) < tonumber ( yf ) or tonumber ( yl ) < tonumber ( xf ) then
return false
end
elseif x . kind == "R" and y . kind == "I" or x . kind == "I" and y . kind == "R" then
local range , index = x . kind == "R" and x or y , x . kind == "I" and x or y
local first , last = range . value : match ( "^(-?%d+):(-?%d+)$" )
local at = tonumber ( index . value )
if not first or not at then
return true
end
if at < tonumber ( first ) or at > tonumber ( last ) then
return false
end
elseif x . kind ~= y . kind or x . value ~= y . value then
return false
end
end

return true
end

function types . regionContains ( parent , child )
local a , b = regionSegments ( parent ) , regionSegments ( child )
if # a > # b then
return false
end
for j = 1 , # a do
if a [ j ] . kind ~= b [ j ] . kind or a [ j ] . value ~= b [ j ] . value then
return false
end
end

return true
end

function types . regionLastPartition ( path )
local segments = regionSegments ( path )
local last = segments [ # segments ]
return last and last . kind == "P" and last . value or nil
end

local function preservedPath ( t , target , seen )
if types . unwrapOwnership ( t ) . id == target . id then
return { }
end
t = types . unwrapOwnership ( t )
seen = seen or { }
if seen [ t ] then
return nil
end
seen [ t ] = true
local found = nil
local function consider ( name , child )
local suffix = preservedPath ( child , target , seen )
if suffix then
local path = { name }
for _ , segment in ipairs ( suffix ) do
path [ # path + 1 ] = segment
end
if found then
found = nil
return false
end
found = path
end

return true
end

if t . tag == "nominal" then
for name in pairs ( t . fieldDefs or { } ) do
local child = t . byname [ name ]
if child and not consider ( name , child ) then
return nil
end
end
elseif t . tag == "shape" then
for _ , field in ipairs ( t . fields ) do
local child = field . type or field . read or field . write
if child and not consider ( field . name , child ) then
return nil
end
end
elseif t . tag == "tuple" then
for j , child in ipairs ( t . elems ) do
if not consider ( tostring ( j ) , child ) then
return nil
end
end
elseif t . tag == "union" or t . tag == "intersection" then





for _ , member in ipairs ( t . members ) do
if member ~= types . nil_ then
local path = preservedPath ( member , target , seen )
if path then
if found and table . concat ( found , "." ) ~= table . concat ( path , "." ) then
return nil
end
found = path
end
end
end
elseif t . tag == "neutral" and t . op == "mapped" and not t . remap then




local keys = t . keys
local value = t . value
local subject = keys and keys . tag == "neutral" and keys . op == "keyof" and keys . subject or nil
if subject
and value
and value . tag == "neutral"
and value . op == "member"
and value . subject == subject
and value . key == t . binder
then
found = preservedPath ( subject , target , seen )
end
end
seen [ t ] = nil

return found
end

local function cleanupAtPath ( cleanup , path )
for j = # path , 1 , - 1 do
cleanup = types . fieldCleanup ( path [ j ] , cleanup )
end
return cleanup
end

local function obligationAtPath ( obligation , path )
local component = table . concat ( path , "." )
if obligation . kind == "cleanup" and obligation . cleanup then
return types . cleanupObligation ( cleanupAtPath ( obligation . cleanup , path ) , component )
elseif obligation . kind == "transfer-only" then
return types . transferObligation ( component )
end
local children = { }
for j , child in ipairs ( obligation . children or { } ) do
children [ j ] = obligationAtPath ( child , path )
end

return types . aggregateObligation ( children , component )
end






function types . withOwnershipPayload ( source , payload , selectedPath )
local slot = types . valueSlot ( source )
if slot . capability . obligation then
local path = selectedPath or preservedPath ( payload , slot . payload )
if path and # path > 0 then
local cleanups = { }
for j , cleanup in ipairs ( types . capabilityCleanups ( slot . capability ) ) do
cleanups [ j ] = cleanupAtPath ( cleanup , path )
end
return types . affine (
payload ,
cleanups ,
types . capabilityTransferOnly ( slot . capability ) ,
obligationAtPath ( slot . capability . obligation , path )
)
end
return types . affine (
payload ,
types . capabilityCleanups ( slot . capability ) ,
types . capabilityTransferOnly ( slot . capability ) ,
slot . capability . obligation
)
elseif # slot . capability . loans > 0 then
return types . borrowed ( payload )
elseif # slot . capability . anchors > 0 then
return types . pinned ( payload )
end

return payload
end



function types . preservationPath ( payload , source )
return preservedPath ( payload , types . unwrapOwnership ( source ) )
end

local function packTailId ( tail )
if not tail then
return ""
end
if tail . kind == "homogeneous" then
return "..." .. ( tail . mode or "plain" ) .. ":" .. tail . type . id
end
if tail . kind == "generic" then
return tail . var . id .. "..."
end
if tail . kind == "computed" then
return "unpackof(" .. tail . type . id .. ")"
end
if tail . kind == "slice" then
return "slice(" .. tostring ( tail . id ) .. ")"
end

return "...unknown"
end


function types . pack ( head , tail , modes )
local hs , ms , copied = { } , { } , { }
for j , t in ipairs ( head or { } ) do
copied [ j ] , hs [ j ] = t , t . id
ms [ j ] = modes and modes [ j ] or "plain"
end
local keyParts = { }
for j , id in ipairs ( hs ) do
keyParts [ j ] = ms [ j ] .. ":" .. id
end
local key = "pack(" .. table . concat ( keyParts , "," ) .. packTailId ( tail ) .. ")"
local found = packArena [ key ]
if found then
return found
end
local made = setmetatable({ tag =  "pack" ,  head =  copied ,  modes =  ms ,  tail =  tail }, types.Pack)
made . id = inheritedMarks ( key ) .. serial ( "p" )
packArena [ key ] = made

return made
end

function types . packvar ( name , identity )
local key = "pv(" .. ( identity or name ) .. ")"
local found = packVarArena [ key ]
if found then
return found
end
local made = setmetatable({ tag =  "packvar" ,  name =  name }, types.PackVar)
made . id = "!p" .. serial ( "pv" )
packVarArena [ key ] = made

return made
end

function types . constLiteral ( domain , value )
local key = "cl(" .. domain .. ":" .. tostring ( value ) .. ")"
local found = constArena [ key ]
if found then
return found
end
local made = setmetatable({ tag =  "constLiteral" ,  domain =  domain ,  value =  value }, types.ConstLiteral)
made . id = serial ( "c" )
constArena [ key ] = made

return made
end

function types . constvar ( name , domain , identity )
local key = "cv(" .. ( identity or name ) .. ":" .. domain .. ")"
local found = constArena [ key ]
if found then
return found
end
local made = setmetatable({ tag =  "constVar" ,  name =  name ,  domain =  domain }, types.ConstVar)
made . id = "!c" .. serial ( "c" )
constArena [ key ] = made

return made
end

function types . constOp ( operation , operands )
local ids = { }
for j , operand in ipairs ( operands ) do
ids [ j ] = operand . id
end
local key = "co(" .. operation .. ":" .. table . concat ( ids , "," ) .. ")"
local found = constArena [ key ]
if found then
return found
end
local made = setmetatable({ tag =  "constOp" ,  operation =  operation ,  operands =  operands }, types.ConstOp)
made . id = inheritedMarks ( key ) .. serial ( "c" )
constArena [ key ] = made

return made
end

function types . tostringConst ( term )
if term . tag == "constLiteral" then



if term . domain == "function" then
local value = term . value

return value : match ( "#(.*)$" ) or value
end

return term . domain == "string" and string . format ( "%q" , term . value ) or tostring ( term . value )
elseif term . tag == "constVar" then
return term . name
end
if # term . operands == 1 then
return term . operation .. types . tostringConst ( term . operands [ 1 ] )
end

return "(" .. types . tostringConst (
term . operands [ 1 ]
) .. " " .. term . operation .. " " .. types . tostringConst ( term . operands [ 2 ] ) .. ")"
end

function types . packUnion ( alternatives )
local flat , seen , ids = { } , { } , { }
for _ , p in ipairs ( alternatives ) do
for _ , q in ipairs ( p . alternatives or { p } ) do
if not seen [ q . id ] then
seen [ q . id ] = true ;
flat [ # flat + 1 ] = q
end
end
end
table . sort ( flat , canonicalOrder )
if # flat == 1 then
return flat [ 1 ]
end
for j , p in ipairs ( flat ) do
ids [ j ] = p . id
end
local key = "packunion(" .. table . concat ( ids , "|" ) .. ")"
local found = packArena [ key ]
if found then
return found
end
local made = setmetatable({ tag =  "pack" ,  head =  { } ,  modes =  { } ,  alternatives =  flat }, types.Pack)
made . id = key
packArena [ key ] = made

return made
end

function types . packAt ( pack , index )
if pack . alternatives then
local members = { }
for _ , arm in ipairs ( pack . alternatives ) do
members [ # members + 1 ] = types . packAt ( arm , index ) or types . nil_
end
return types . union ( members )
end
if pack . head [ index ] then
return pack . head [ index ]
end
local tail = pack . tail
if tail and ( tail . kind == "homogeneous" or tail . kind == "unknown" ) then
return tail . type or types . any
end

return nil
end

function types . packMayExpand ( pack )
return pack . tail ~= nil or pack . alternatives ~= nil
end

function types . protocolThread (
startPack ,
resumePack ,
yieldPack ,
returnPack
)
local key = "thread<" .. startPack . id .. "," .. resumePack . id .. "," .. yieldPack . id .. "," .. returnPack . id .. ">"
local existing = interned ( key )
if existing then
return existing
end

return intern (
key , setmetatable({ tag =

"protocolThread" ,  startPack =
startPack ,  resumePack =
resumePack ,  yieldPack =
yieldPack ,  returnPack =
returnPack }, types.ProtocolThread)

)
end

function types . genericAlias (
name ,
body ,
typeParams ,
typeBounds ,
packParams ,
constParams ,
paramKinds ,
paramDefaults
)
local parts = { "alias(" .. name , body . id }
for _ , tv in ipairs ( typeParams or { } ) do
parts [ # parts + 1 ] = tv . id
end
for _ , pv in ipairs ( packParams or { } ) do
parts [ # parts + 1 ] = pv . id
end
for _ , cv in ipairs ( constParams or { } ) do
parts [ # parts + 1 ] = cv . id
end
local key = table . concat ( parts , "|" ) .. ")"

local existing = interned ( key )
if existing then
return existing
end

return intern (
key , setmetatable({ tag =

"genericAlias" ,  name =
name ,  body =
body ,  typeParams =
typeParams or { } ,  typeBounds =
typeBounds or { } ,  packParams =
packParams or { } ,  constParams =
constParams or { } ,  paramKinds =
paramKinds or { } ,  paramDefaults =
paramDefaults or { } }, types.GenericAlias)

)
end

function types . tostringPack ( pack )
if pack . alternatives then
local arms = { }
for j , arm in ipairs ( pack . alternatives ) do
arms [ j ] = types . tostringPack ( arm )
end
return "(" .. table . concat ( arms , " | " ) .. ")"
end
local parts = { }
for j , t in ipairs ( pack . head ) do
parts [ j ] = types . tostring ( t )
end
if pack . tail then
if pack . tail . kind == "homogeneous" then
parts [ # parts + 1 ] = "..." .. types . tostring ( pack . tail . type )
elseif pack . tail . kind == "generic" then
parts [ # parts + 1 ] = pack . tail . var . name .. "..."
elseif pack . tail . kind == "computed" then
parts [ # parts + 1 ] = "unpackof " .. types . tostring ( pack . tail . type )
else
parts [ # parts + 1 ] = "...unknown"
end
end

return "(" .. table . concat ( parts , ", " ) .. ")"
end







function types . func (
params ,
rets ,
vararg ,
paramModes ,
predicate ,
typeParams ,
typeBounds ,
borrowsParam ,
borrowsSelf ,
borrowsParams ,
ffiOut ,
varargType ,
noreturn ,
paramPack ,
retPack ,
packParams ,
yieldPack ,
resumePack ,
noYield ,
paramNames ,
preservesResults ,
foreign ,
constParams ,
paramKinds ,
partitionResults ,
comptimeOnly ,
explicitPreserves
)



if # rets == 1 and rets [ 1 ] == types . never then
noreturn = true
end
local pids = { }
local rids = { }
local modes = { }
local names = { }
local preservesPaths = { }
for j , p in ipairs ( params ) do
pids [ j ] = p . id
modes [ j ] = paramModes and paramModes [ j ] or "plain"
names [ j ] = paramNames and paramNames [ j ] or ""
end
for j , r in ipairs ( rets ) do
rids [ j ] = r . id
end
local keyedParams = { }
for j , id in ipairs ( pids ) do
keyedParams [ j ] = modes [ j ] .. ":" .. id
end
local varargPart = ""
if vararg then
varargPart = varargType and ( ",..." .. varargType . id ) or ",..."
end
paramPack = paramPack or types . pack (
params ,
vararg and { kind = varargType and "homogeneous" or "unknown" , type = varargType or types . any } or nil ,
modes
)
retPack = retPack or types . pack ( rets )
local key = "fn" .. paramPack . id .. ":" .. retPack . id
if predicate then
key = key .. "|is" .. predicate . param .. ":" .. predicate . type . id
end
if typeParams and # typeParams > 0 then
local genericParts = { }
for j , tv in ipairs ( typeParams ) do
genericParts [ j ] = tv . id .. "<:" .. ( ( typeBounds and typeBounds [ j ] ) and typeBounds [ j ] . id or "any" )
end
key = key .. "|<" .. table . concat ( genericParts , "," ) .. ">"
end
if packParams and # packParams > 0 then
local pp = { }
for j , pv in ipairs ( packParams ) do
pp [ j ] = pv . id
end
key = key .. "|<" .. table . concat ( pp , "," ) .. ">"
end
if constParams and # constParams > 0 then
local cp = { }
for j , cv in ipairs ( constParams ) do
cp [ j ] = cv . id
end
key = key .. "|<const " .. table . concat ( cp , "," ) .. ">"
end
if yieldPack then
key = key .. "|yields" .. yieldPack . id
end
if resumePack then
key = key .. "|resumes" .. resumePack . id
end
if borrowsParam then
key = key .. "|borrows" .. borrowsParam
end
if borrowsParams and # borrowsParams > 0 then
key = key .. "|borrows(" .. table . concat ( borrowsParams , "," ) .. ")"
end
for _ , output in ipairs ( ffiOut or { } ) do
local cleanupIds = { }
for j , cleanup in ipairs ( output . cleanups or { } ) do
cleanupIds [ j ] = cleanup . id
end
local sourceIds = { }
for j , sourceParam in ipairs ( output . sourceParams or { } ) do
sourceIds [ j ] = tostring ( sourceParam )
end
key = key .. "|out:" .. (
output . kind or "affine"
) .. ":" .. output . name .. ":" .. table . concat (
cleanupIds ,
","
) .. ":" .. ( output . success or "always" ) .. ":" .. table . concat ( sourceIds , "," )
end
if borrowsSelf then
key = key .. "|borrowsself"
end
if preservesResults then
for result = 1 , # rets do
local source = preservesResults [ result ]
if source then
key = key .. "|preserves" .. tostring ( result ) .. ":" .. tostring ( source )
local path = params [ source ] and types . preservationPath ( rets [ result ] , params [ source ] ) or nil
if path then
preservesPaths [ result ] = path
key = key .. "@" .. table . concat ( path , "." )
else
key = key .. "@ambiguous"
end
end
end
end
if partitionResults then
for result = 1 , # rets do
local fields = partitionResults [ result ]
if fields then
local fieldNames = { }
for name in pairs ( fields ) do
fieldNames [ # fieldNames + 1 ] = name
end
table . sort ( fieldNames )
for _ , name in ipairs ( fieldNames ) do
key = key .. "|partition" .. tostring ( result ) .. ":" .. name .. "=" .. tostring ( fields [ name ] )
end
end
end
end
if noreturn then
key = key .. "|noreturn"
end
if noYield then
key = key .. "|noyield"
end
if foreign then
key = key .. "|foreign"
end
if comptimeOnly then
key = key .. "|comptime"
end
local unlabeledId = key
if explicitPreserves then
local written = { }
for result = 1 , # rets do
if explicitPreserves [ result ] then
written [ # written + 1 ] = tostring ( result )
end
end
if # written > 0 then
key = key .. "|written-preserves(" .. table . concat ( written , "," ) .. ")"
end
end
if paramNames then
key = key .. "|names(" .. table . concat ( names , "," ) .. ")"
end

local existing = interned ( key )
if existing then
return existing
end

return intern (
key , setmetatable({ tag =

"func" ,  params =
params ,  rets =
rets ,  vararg =
vararg or false ,  varargType =
vararg and varargType or nil ,  paramModes =
modes ,  paramNames =
names ,  unlabeledId =
unlabeledId ,  predicate =
predicate ,  typeParams =
typeParams ,  typeBounds =
typeBounds ,  borrowsParam =
borrowsParam ,  borrowsSelf =
borrowsSelf ,  borrowsParams =
borrowsParams ,  preservesResults =
preservesResults ,  explicitPreserves =
explicitPreserves ,  preservesPaths =
next ( preservesPaths ) and preservesPaths or nil ,  partitionResults =
partitionResults ,  foreign =
foreign or nil ,  ffiOut =
ffiOut ,  noreturn =
noreturn or nil ,  noYield =
noYield or nil ,  paramPack =
paramPack ,  retPack =
retPack ,  packParams =
packParams ,  constParams =
constParams ,  paramKinds =
paramKinds ,  yieldPack =
yieldPack ,  resumePack =
resumePack ,  comptimeOnly =
comptimeOnly or nil }, types.Func)

)
end












function types . withYields ( ft , mayYield )
if ft . tag ~= "func" then
return ft
end
local fn = ft
local want = not mayYield or nil
if ( fn . noYield or nil ) == want then
return ft
end

return types . func (
fn . params ,
fn . rets ,
fn . vararg ,
fn . paramModes ,
fn . predicate ,
fn . typeParams ,
fn . typeBounds ,
fn . borrowsParam ,
fn . borrowsSelf ,
fn . borrowsParams ,
fn . ffiOut ,
fn . varargType ,
fn . noreturn ,
fn . paramPack ,
fn . retPack ,
fn . packParams ,
fn . yieldPack ,
fn . resumePack ,
want ,
fn . paramNames ,
fn . preservesResults ,
fn . foreign ,
fn . constParams ,
fn . paramKinds ,
fn . partitionResults ,
fn . comptimeOnly ,
fn . explicitPreserves
)
end





function types . foreignFunction ( ft )
if ft . tag ~= "func" or ft . foreign then
return ft
end
local fn = ft

return types . func (
fn . params ,
fn . rets ,
fn . vararg ,
fn . paramModes ,
fn . predicate ,
fn . typeParams ,
fn . typeBounds ,
fn . borrowsParam ,
fn . borrowsSelf ,
fn . borrowsParams ,
fn . ffiOut ,
fn . varargType ,
fn . noreturn ,
fn . paramPack ,
fn . retPack ,
fn . packParams ,
fn . yieldPack ,
fn . resumePack ,
fn . noYield ,
fn . paramNames ,
fn . preservesResults ,
true ,
fn . constParams ,
fn . paramKinds ,
fn . partitionResults ,
fn . comptimeOnly ,
fn . explicitPreserves
)
end


function types . withFirstResult ( ft , first )
if ft . tag ~= "func" or not ft . rets [ 1 ] or ft . retPack . alternatives then
return ft
end
local fn = ft
local rets = { }
for j , result in ipairs ( fn . rets ) do
rets [ j ] = j == 1 and first or result
end
local retPack = types . pack ( rets , fn . retPack . tail , fn . retPack . modes )

return types . func (
fn . params ,
rets ,
fn . vararg ,
fn . paramModes ,
fn . predicate ,
fn . typeParams ,
fn . typeBounds ,
fn . borrowsParam ,
fn . borrowsSelf ,
fn . borrowsParams ,
fn . ffiOut ,
fn . varargType ,
fn . noreturn ,
fn . paramPack ,
retPack ,
fn . packParams ,
fn . yieldPack ,
fn . resumePack ,
fn . noYield ,
fn . paramNames ,
fn . preservesResults ,
fn . foreign ,
fn . constParams ,
fn . paramKinds ,
fn . partitionResults ,
fn . comptimeOnly ,
fn . explicitPreserves
)
end




function types . withPartitionResults ( ft , partitionResults )
if ft . tag ~= "func" then
return ft
end
local fn = ft

return types . func (
fn . params ,
fn . rets ,
fn . vararg ,
fn . paramModes ,
fn . predicate ,
fn . typeParams ,
fn . typeBounds ,
fn . borrowsParam ,
fn . borrowsSelf ,
fn . borrowsParams ,
fn . ffiOut ,
fn . varargType ,
fn . noreturn ,
fn . paramPack ,
fn . retPack ,
fn . packParams ,
fn . yieldPack ,
fn . resumePack ,
fn . noYield ,
fn . paramNames ,
fn . preservesResults ,
fn . foreign ,
fn . constParams ,
fn . paramKinds ,
partitionResults ,
fn . comptimeOnly ,
fn . explicitPreserves
)
end





function types . literal ( value , base )
local of = base or types . string
local internKey = "lit(" .. of . tag .. ":" .. tostring ( value ) .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "literal" ,  constant =  value ,  base =  of }, types.Literal) )
end





function types . carray ( elem , count , countTerm )
local term = countTerm or ( count and types . constLiteral ( "integer" , count ) or nil )
local internKey = "carray(" .. elem . id .. "," .. ( term and term . id or "?" ) .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "carray" ,  elem =  elem ,  count =  count ,  countTerm =  term }, types.CArray) )
end



function types . constOf ( t )
if t . tag == "const" then
return t
end
local internKey = "const(" .. t . id .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "const" ,  inner =  t }, types.Const) )
end


function types . ctype ( t )
local internKey = "ctype(" .. t . id .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "ctype" ,  of =  t }, types.CType) )
end




function types . typevar ( name , identity )


local internKey = "!ttv(" .. ( identity or name ) .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "typevar" ,  name =  name }, types.TypeVar) )
end

function types . typeHandle ( bound )
local key = "type<" .. bound . id .. ">"
local existing = interned ( key )
if existing then
return existing
end

return intern ( key , setmetatable({ tag =  "typeHandle" ,  bound =  bound }, types.TypeHandle) )
end

function types . packResult ( pack )
local key = "packResult(" .. pack . id .. ")"
local existing = interned ( key )
if existing then
return existing
end

return intern ( key , setmetatable({ tag =  "packResult" ,  pack =  pack }, types.PackResult) )
end




function types . neutral (
op ,
subject ,
key ,
capability ,
binder ,
keys ,
value ,
remap ,
constTerm ,
templateParts
)





local templateIds = { }
for j , part in ipairs ( templateParts or { } ) do
templateIds [
j
] = type (
part
) == "string" and "s" .. # ( part ) .. ":" .. ( part ) or "t:" .. ( part ) . id
end
local id = "neutral(" .. op .. ":" .. (
capability or "-"
) .. ":" .. (
subject and subject . id or "-"
) .. ":" .. (
key and key . id or "-"
) .. ":" .. (
binder and binder . id or "-"
) .. ":" .. (
keys and keys . id or "-"
) .. ":" .. (
value and value . id or "-"
) .. ":" .. (
remap and remap . id or "-"
) .. ":" .. ( constTerm and constTerm . id or "-" ) .. ":" .. table . concat ( templateIds , "," ) .. ")"

local existing = interned ( id )
if existing then
return existing
end

return intern (
id , setmetatable({ tag =

"neutral" ,  op =
op ,  capability =
capability ,  subject =
subject ,  key =
key ,  binder =
binder ,  keys =
keys ,  value =
value ,  remap =
remap ,  constTerm =
constTerm ,  templateParts =
templateParts }, types.Neutral)

)
end




function types . comptimeCall (
identity ,
helper ,
arguments ,
bound ,
resultPack
)
local ids = { identity , bound and bound . id or types . unknown . id , resultPack and "pack" or "type" }
for _ , argument in ipairs ( arguments ) do
if argument . kind == "type" then
ids [ # ids + 1 ] = "t:" .. argument . value . id
elseif argument . kind == "typepack" then
ids [ # ids + 1 ] = "p:" .. argument . value . id
else
ids [ # ids + 1 ] = "c:" .. argument . value . id
end
end
local id = "neutral(comptime:" .. table . concat ( ids , "," ) .. ")"

local existing = interned ( id )
if existing then
return existing
end

return intern (
id , setmetatable({ tag =

"neutral" ,  op =
"comptimeCall" ,  comptimeIdentity =
identity ,  comptimeHelper =
helper ,  comptimeArguments =
arguments ,  comptimeBound =
bound or types . unknown ,  comptimeResultPack =
resultPack }, types.Neutral)

)
end

function types . metatable ( t )
local internKey = "metatable(" .. t . id .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "metatable" ,  of =  t }, types.Metatable) )
end


function types . typeObject ( t )
local internKey = "Type(" .. t . id .. ")"
local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "typeobject" ,  of =  t }, types.TypeObject) )
end


function types . projection ( of , name )
local internKey = "!jproj(" .. of . id .. "," .. name .. ")"

local existing = interned ( internKey )
if existing then
return existing
end

return intern ( internKey , setmetatable({ tag =  "projection" ,  of =  of ,  name =  name }, types.Projection) )
end



function types . hasProjection ( t )
return t . id : find ( MARK_PROJECTION , 1 , true ) ~= nil
end


function types . hasTypevar ( t )
if t . tag == "nominal" and t . origin then
for _ , argument in ipairs ( t . typeArgs or { } ) do
if types . hasTypevar ( argument ) then
return true
end
end
for _ , argument in ipairs ( t . packArgs or { } ) do
if argument . id : find (
MARK_TYPEVAR ,
1 ,
true
) or argument . id : find ( MARK_PACKVAR , 1 , true ) or argument . id : find ( MARK_CONSTVAR , 1 , true ) then
return true
end
end
for _ , argument in ipairs ( t . constArgs or { } ) do
if argument . id : find ( MARK_CONSTVAR , 1 , true ) then
return true
end
end
end







local marked = t . id : find (
MARK_TYPEVAR ,
1 ,
true
) ~= nil or t . id : find ( MARK_PACKVAR , 1 , true ) ~= nil or t . id : find ( MARK_CONSTVAR , 1 , true ) ~= nil
if marked then
return true
end

local tag = t . tag
if tag == "affine" or tag == "borrowed" or tag == "pinned" or tag == "const" then
return types . hasTypevar ( t . inner )
elseif tag == "ctype" or tag == "metatable" then
return types . hasTypevar ( t . of )
elseif tag == "ptr" or tag == "carray" or tag == "array" then
return types . hasTypevar ( t . elem )
elseif tag == "typeHandle" then
return types . hasTypevar ( t . bound )
elseif tag == "map" then
return (
t . key and types . hasTypevar ( t . key )
) or (
t . value and types . hasTypevar ( t . value )
) or ( t . writeKey and types . hasTypevar ( t . writeKey ) ) or ( t . writeValue and types . hasTypevar ( t . writeValue ) ) or false
elseif tag == "tuple" then
for _ , member in ipairs ( t . elems ) do
if types . hasTypevar ( member ) then
return true
end
end
elseif tag == "shape" then
for _ , field in ipairs ( t . fields ) do
if field . read and types . hasTypevar ( field . read ) then
return true
end
if field . write and types . hasTypevar ( field . write ) then
return true
end
end
elseif tag == "union" or tag == "intersection" then
for _ , member in ipairs ( t . members ) do
if types . hasTypevar ( member ) then
return true
end
end
elseif tag == "func" then
for _ , member in ipairs ( t . params ) do
if types . hasTypevar ( member ) then
return true
end
end
for _ , member in ipairs ( t . rets ) do
if types . hasTypevar ( member ) then
return true
end
end
end

return false
end





local nominalCounter = 0






function types . nominal ( name , declKind )
nominalCounter = nominalCounter + 1
local t = setmetatable({ tag =
"nominal" ,  declKind =
declKind ,  name =
name ,  byname =
{ } ,  writeByname =
{ } ,  staticByname =
{ } ,  staticWriteByname =
{ } ,  metamethods =
{ } ,  nestedTypes =
{ } }, types.Nominal)

t . id = "nominal#" .. nominalCounter .. "(" .. name .. ")"

return t
end






function types . tostring ( t )
local tag = t . tag
if tag == "nominal" then
if # ( t . typeArgs or { } ) > 0 or # ( t . packArgs or { } ) > 0 or # ( t . constArgs or { } ) > 0 then
local parts = { }
local typeAt , packAt , constAt = 1 , 1 , 1
for _ , kind in ipairs ( t . paramKinds or { } ) do
if kind == "type" then
parts [ # parts + 1 ] = types . tostring ( ( t . typeArgs ) [ typeAt ] )
typeAt = typeAt + 1
elseif kind == "pack" then
parts [ # parts + 1 ] = types . tostringPack ( ( t . packArgs ) [ packAt ] )
packAt = packAt + 1
elseif kind == "const" then
parts [ # parts + 1 ] = types . tostringConst ( ( t . constArgs ) [ constAt ] )
constAt = constAt + 1
end
end
if # parts == 0 then
for _ , argument in ipairs ( t . typeArgs or { } ) do
parts [ # parts + 1 ] = types . tostring ( argument )
end
for _ , argument in ipairs ( t . packArgs or { } ) do
parts [ # parts + 1 ] = types . tostringPack ( argument )
end
for _ , argument in ipairs ( t . constArgs or { } ) do
parts [ # parts + 1 ] = types . tostringConst ( argument )
end
end
return t . name .. "<" .. table . concat ( parts , ", " ) .. ">"
end
return t . name
elseif tag == "array" then
return "{" .. types . tostring ( t . elem ) .. "}"
elseif tag == "map" then
if t . readable and t . writeKey == t . key and t . writeValue == t . value then
return "{[" .. types . tostring ( t . key ) .. "]: " .. types . tostring ( t . value ) .. "}"
end
local parts = { }
if t . readable then
parts [ # parts + 1 ] = "readonly [" .. types . tostring ( t . key ) .. "]: " .. types . tostring ( t . value )
end
if t . writeKey and t . writeValue then
parts [ # parts + 1 ] = "writeonly [" .. types . tostring ( t . writeKey ) .. "]: " .. types . tostring ( t . writeValue )
end
return "{" .. table . concat ( parts , ", " ) .. "}"
elseif tag == "tuple" then
local parts = { }
for j , e in ipairs ( t . elems ) do
parts [ j ] = types . tostring ( e )
end
return "{" .. table . concat ( parts , ", " ) .. "}"
elseif tag == "shape" then
local parts = { }
for j , f in ipairs ( t . fields ) do
if f . read and f . write and f . read == f . write then
parts [ # parts + 1 ] = f . name .. ": " .. types . tostring ( f . read )
else
if f . read then
parts [ # parts + 1 ] = "readonly " .. f . name .. ": " .. types . tostring ( f . read )
end
if f . write then
parts [ # parts + 1 ] = "writeonly " .. f . name .. ": " .. types . tostring ( f . write )
end
end
end
if t . indexReadKey and t . indexReadValue then
parts [
# parts + 1
] = "readonly [" .. types . tostring ( t . indexReadKey ) .. "]: " .. types . tostring ( t . indexReadValue )
end
if t . indexWriteKey and t . indexWriteValue then
parts [
# parts + 1
] = "writeonly [" .. types . tostring ( t . indexWriteKey ) .. "]: " .. types . tostring ( t . indexWriteValue )
end
return "{" .. table . concat ( parts , ", " ) .. "}"
elseif tag == "union" then

if t . hasNil and # t . members == 2 then
local other = t . members [ 1 ] == types . nil_ and t . members [ 2 ] or t . members [ 1 ]
local rendered = types . tostring ( other )
if other . tag == "intersection" then
rendered = "(" .. rendered .. ")"
end
return rendered .. "?"
end
local parts = { }
for j , m in ipairs ( t . members ) do
parts [ j ] = types . tostring ( m )
end
return table . concat ( parts , " | " )
elseif tag == "intersection" then
local parts = { }
for j , m in ipairs ( t . members ) do
local rendered = types . tostring ( m )
if m . tag == "union" then
rendered = "(" .. rendered .. ")"
end
parts [ j ] = rendered
end
return table . concat ( parts , " & " )
elseif tag == "const" then
return "const " .. types . tostring ( t . inner )
elseif tag == "ctype" then
return "ctype<" .. types . tostring ( t . of ) .. ">"
elseif tag == "carray" then
local elem = types . tostring ( t . elem )
if t . elem . tag == "union" or t . elem . tag == "intersection" then
elem = "(" .. elem .. ")"
end
return elem .. "[" .. ( t . countTerm and types . tostringConst ( t . countTerm ) or "?" ) .. "]"
elseif tag == "ptr" then
local elem = types . tostring ( t . elem )
if t . elem . tag == "union" or t . elem . tag == "intersection" then
elem = "(" .. elem .. ")"
end
return elem .. "*"
elseif tag == "affine" then
local terminal = t . cleanups and t . cleanups [ 1 ]
return "affine(" .. types . tostring (
t . inner
) .. ( terminal and ", " .. ( terminal . name or terminal . id ) or "" ) .. ")"
elseif tag == "borrowed" then
return types . tostring ( t . inner )
elseif tag == "pinned" then
return "pinned(" .. types . tostring ( t . inner ) .. ")"
elseif tag == "typevar" then
return t . name
elseif tag == "typeHandle" then
return "type<" .. types . tostring ( t . bound ) .. ">"
elseif tag == "packResult" then
return "typepack(" .. types . tostringPack ( t . pack ) .. ")"
elseif tag == "neutral" then
if t . op == "comptimeCall" then
local arguments = { }
for _ , argument in ipairs ( t . comptimeArguments or { } ) do
if argument . kind == "type" then
arguments [ # arguments + 1 ] = types . tostring ( argument . value )
elseif argument . kind == "typepack" then
arguments [ # arguments + 1 ] = types . tostringPack ( argument . value )
else
arguments [ # arguments + 1 ] = types . tostringConst ( argument . value )
end
end
local helper = t . comptimeHelper
local name = helper and helper . name and helper . name . text or "<type function>"
return name .. "(" .. table . concat ( arguments , ", " ) .. ")"
elseif t . op == "singleton" then
return types . tostringConst ( t . constTerm )
elseif t . op == "keyof" then
return ( t . capability == "write" and "writekeyof " or "keyof " ) .. types . tostring ( t . subject )
elseif t . op == "member" then
return (
t . capability == "write" and "writeof " or ""
) .. types . tostring ( t . subject ) .. ".[" .. types . tostring ( t . key ) .. "]"
elseif t . op == "mapped" then
return "{" .. (
t . capability == "write" and "writeonly" or "readonly"
) .. " [" .. (
t . binder and t . binder . name or "K"
) .. " in " .. types . tostring ( t . keys ) .. "]: " .. types . tostring ( t . value ) .. "}"
elseif t . op == "template" then
local parts = { }
for j , part in ipairs ( t . templateParts or { } ) do
parts [ j ] = type ( part ) == "string" and part or "${" .. types . tostring ( part ) .. "}"
end
return "`" .. table . concat ( parts ) .. "`"
elseif t . op == "tupleConcat" then
local prefix = t . subject
local parts = { }
for j , elem in ipairs ( prefix . elems ) do
parts [ j ] = types . tostring ( elem )
end
parts [ # parts + 1 ] = "unpackof " .. types . tostring ( t . key )
return "{" .. table . concat ( parts , ", " ) .. "}"
end
return "<" .. t . op .. ">"
elseif tag == "metatable" then
return "metatable<" .. types . tostring ( t . of ) .. ">"
elseif tag == "typeobject" then
return "Type<" .. types . tostring ( t . of ) .. ">"
elseif tag == "projection" then
return types . tostring ( t . of ) .. "." .. t . name
elseif tag == "literal" then
if t . base == types . string then
return ( "%q" ) : format ( t . constant )
end
return tostring ( t . constant )
elseif tag == "func" then
local ps = { }
for j , p in ipairs ( t . params ) do
local mode = t . paramModes and t . paramModes [ j ]
local label = t . paramNames and t . paramNames [ j ]
ps [
j
] = (
mode and mode ~= "plain" and mode .. " " or ""
) .. ( label and label ~= "" and label .. ": " or "" ) .. types . tostring ( p )
end
local paramTail = t . paramPack . tail
if paramTail then
if paramTail . kind == "homogeneous" then
ps [
# ps + 1
] = (
paramTail . mode and paramTail . mode ~= "plain" and paramTail . mode .. " " or ""
) .. "...: " .. types . tostring ( paramTail . type )
elseif paramTail . kind == "generic" then
ps [ # ps + 1 ] = paramTail . var . name .. "..."
elseif paramTail . kind == "computed" then
ps [ # ps + 1 ] = "...: unpackof " .. types . tostring ( paramTail . type )
else
ps [ # ps + 1 ] = "..."
end
end
local renderedResults = { }
for j , result in ipairs ( t . retPack . head ) do
local rendered = types . tostring ( result )
local source = t . preservesResults and t . preservesResults [ j ]
if source then
local name = t . paramNames and t . paramNames [ source ]
rendered = rendered .. " preserves " .. ( name and name ~= "" and name or ( "#" .. tostring ( source ) ) )
end
renderedResults [ j ] = rendered
end
local hasRet = # t . retPack . head > 0 or t . retPack . tail ~= nil or t . retPack . alternatives ~= nil
local ret = ""
if hasRet then
ret = ": " .. (
# t . retPack . head == 1 and not t . retPack . tail and not t . retPack . alternatives and renderedResults [
1
] or (
t . retPack . alternatives or t . retPack . tail
) and types . tostringPack ( t . retPack ) or "(" .. table . concat ( renderedResults , ", " ) .. ")"
)
end
local protocol = t . yieldPack and (
" yields " .. types . tostringPack (
t . yieldPack
) .. " resumes " .. types . tostringPack ( t . resumePack or types . pack ( { } , { kind = "unknown" , type = types . any } ) )
) or ""
local binders = { }
for _ , tv in ipairs ( t . typeParams or { } ) do
binders [ # binders + 1 ] = tv . name
end
for _ , pv in ipairs ( t . packParams or { } ) do
binders [ # binders + 1 ] = pv . name .. "..."
end
for _ , cv in ipairs ( t . constParams or { } ) do
binders [ # binders + 1 ] = "const " .. cv . name .. ": " .. cv . domain
end
local generic = # binders > 0 and "<" .. table . concat ( binders , ", " ) .. ">" or ""
return "function" .. generic .. "(" .. table . concat ( ps , ", " ) .. ")" .. ret .. protocol
elseif tag == "protocolThread" then
return "thread<" .. types . tostringPack (
t . startPack
) .. ", " .. types . tostringPack (
t . resumePack
) .. ", " .. types . tostringPack ( t . yieldPack ) .. ", " .. types . tostringPack ( t . returnPack ) .. ">"
elseif tag == "genericAlias" then
return t . name
end

return tag
end




local C_NAME

= {
number = "double" ,
float = "float" ,
boolean = "bool" ,
integer = "int32_t" ,
int8 = "int8_t" ,
int16 = "int16_t" ,
int32 = "int32_t" ,
int64 = "int64_t" ,
uint8 = "uint8_t" ,
uint16 = "uint16_t" ,
uint32 = "uint32_t" ,
uint64 = "uint64_t" ,
cstring = "const char *" ,
voidptr = "void *" ,
}










function types . cName ( t )
if not t then
return nil
end
local tag = t . tag
if C_NAME [ tag ] then
return C_NAME [ tag ]
end
if tag == "nominal" and t . declKind == "struct" then



return t . name
end
if tag == "ptr" then



local inner = types . cName ( t . elem )
return ( inner or "void" ) .. " *"

elseif tag == "carray" then
local elem = types . cName ( t . elem )
if elem and t . count then
return elem .. "[" .. tostring ( t . count ) .. "]"
end
return nil
end
if tag == "union" and # t . members == 2 and t . hasNil then


local other = t . members [ 1 ] == types . nil_ and t . members [ 2 ] or t . members [ 1 ]
return types . cName ( other )
end

return nil
end

return types
