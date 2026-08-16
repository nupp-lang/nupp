_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local cst = require ( "nupp.compiler.cst" )
local lints = require ( "nupp.compiler.lints" )
local state = require ( "nupp.compiler.check.state" )

local pragma = { }








function pragma . install ( c )
local marks = c . marks
local defineAnnotation = marks . defineAnnotation
local validateAnnotation = marks . validateAnnotation
local stringValue , nameText = marks . stringValue , marks . nameText

local handlers = { }
local RELAXATIONS = {
[ "function-identity" ] = true ,
[ "load-order" ] = true ,
[ "error-site" ] = true ,
frames = true ,
[ "gc-timing" ] = true ,
[ "table-order" ] = true ,




[ "fp-contract" ] = true ,
}

local function effectContract ( application )
local listMembers = {
reads = true ,
writes = true ,
shapes = true ,
metatables = true ,
escapes = true ,
calls = true ,
returns = true ,
}
local boolMembers = { allocates = true , yields = true , raises = true , external = true , }
local contract = {
reads = { } ,
writes = { } ,
shapes = { } ,
metatables = { } ,
escapes = { } ,
calls = { } ,
returns = { } ,
allocates = false ,
yields = false ,
raises = false ,
external = false ,
}
local seen = { }
for _ , arg in ipairs ( application . annotationArgs or { } ) do
local name = arg . name and arg . name . text or nil
if not name or seen [ name ] or not ( listMembers [ name ] or boolMembers [ name ] ) then
c . diag ( "NUPP2112" , arg , "@effects arguments must be unique named effect members" )
elseif listMembers [ name ] then
seen [ name ] = true
local expr = arg . expr
if not expr or expr . kind ~= "tableExpr" then
c . diag ( "NUPP2112" , arg , ( "@effects.%s must be an array of strings" ) : format ( name ) )
else
for _ , field in ipairs ( expr . fields or { } ) do
local value = field . kind == "fieldItem" and stringValue ( field . value ) or nil
if not value then
c . diag ( "NUPP2112" , field , ( "@effects.%s entries must be strings" ) : format ( name ) )
else
contract [ name ] [ # contract [ name ] + 1 ] = value
end
end
end
else
seen [ name ] = true
local expr = arg . expr
if not expr or ( expr . kind ~= "trueExpr" and expr . kind ~= "falseExpr" ) then
c . diag ( "NUPP2112" , arg , ( "@effects.%s must be true or false" ) : format ( name ) )
else
contract [ name ] = expr . kind == "trueExpr"
end
end
end

return contract
end

handlers . pragmaStmt = function ( stat )
local annotationName = stat . name
if not annotationName then
return
end
local written = annotationName . text
local target = stat . stat
while target and target . kind == "pragmaStmt" do
target = target . stat
end



local targetKind = target and target . kind or ""
local targetBody = nil
if target then
if target . kind == "funcStmt"
or target . kind == "localFuncStmt"
or target . kind == "inlineMethod"
or target . kind == "constructorDecl"
then
targetBody = target . body
end
end
if written == "annotation" and target and targetKind == "recordDecl" then
target . isAnnotationDefinition = true
end
local annotation , valid = validateAnnotation ( stat , target )
local targetAny = target




if written == "deprecated" and valid and target and targetAny . deprecation then
local function deprecate ( tok )
if tok then
tok . deprecation = targetAny . deprecation
local annotationToken = cst . firstToken ( stat )
tok . deprecationToken = annotationToken or nil
end
end

if target . kind == "localStmt" then
for _ , name in ipairs ( target . names or { } ) do
deprecate ( name )
end
elseif target . kind == "funcStmt" and target . name then
local _ , member = c . funcOwner ( target . name )
deprecate ( member or targetAny . name . base )
else
deprecate ( targetAny . name )
end
end

if written == "syntax" and valid and target and target . kind == "localStmt" then
local values = ( stat ) . annotationValues
local value = values and values . value
local format = value and stringValue ( value . expr ) or nil
if format then


targetAny . embeddedStringFormat = format
end
end

if not annotation then
if stat . stat then
c . checkStat ( stat . stat )
end
return
end
if written == "annotation" then
if stat . stat then
c . checkStat ( stat . stat )
end
if valid and target and targetKind == "recordDecl" then
defineAnnotation ( stat , target )
end
return

elseif written == "jit" then
if valid and targetBody then
if targetBody . aotRequired then
c . diag ( "NUPP2901" , annotationName , "@jit and @aot name different compilers for one body" )
end
targetBody . jitRequired = true
end
if stat . stat then
c . checkStat ( stat . stat )
end
return

elseif written == "aot" then




if valid and ( targetKind == "constructorDecl" or targetKind == "inlineMethod" ) then
c . diag (
"NUPP2902" ,
annotationName ,
(
"@aot cannot compile %s"
) : format ( targetKind == "constructorDecl" and "a constructor" or "an inline interface requirement" )
)
elseif valid and targetBody then
if targetBody . jitRequired then
c . diag ( "NUPP2901" , annotationName , "@aot and @jit name different compilers for one body" )
end
targetBody . aotRequired = true




local values = ( stat ) . annotationValues
local lanes = values and values . lanes
if lanes and lanes . expr and lanes . expr . kind == "falseExpr" then
targetBody . lanesDeclined = true
elseif lanes and lanes . expr and lanes . expr . kind == "trueExpr" then
targetBody . lanesRequired = true
end
end
if stat . stat then
c . checkStat ( stat . stat )
end



if valid and targetBody and targetBody . aotRequired then
c . aot . body ( targetBody )
end
return

elseif written == "derive" then
if valid and target and target . kind == "recordDecl" then
target . deriveApplications = target . deriveApplications or { }
local seen = false
for _ , prior in ipairs ( target . deriveApplications ) do
if prior == stat then
seen = true
break
end
end
if not seen then
target . deriveApplications [ # target . deriveApplications + 1 ] = stat
end
end
if stat . stat then
c . checkStat ( stat . stat )
end
return

elseif written == "effects" then
if valid and target then
local contract = effectContract ( stat )
target . effectContract = contract
if targetBody then
targetBody . effectContract = contract
end
end
if stat . stat then
c . checkStat ( stat . stat )
end
if valid and target and target . kind == "localStmt" and target . effectContract then
for _ , name in ipairs ( target . names or { } ) do
if name . definition then
name . definition . effectContract = target . effectContract
end
end
end
return

elseif written == "relax" then
local relaxed = { }
for _ , arg in ipairs ( stat . annotationArgs or { } ) do
local expr = arg . expr
local value = nameText ( expr ) or stringValue ( expr )
if not value or not RELAXATIONS [ value ] then
c . diag (
"NUPP2112" ,
arg ,
"@relax names function-identity, load-order, error-site, "
.. "frames, gc-timing, table-order, or fp-contract"
)
else
relaxed [ value ] = true
end
end
if valid and target then
target . relaxedGuarantees = relaxed
if targetBody then
targetBody . relaxedGuarantees = relaxed
end
end
if stat . stat then
c . checkStat ( stat . stat )
end
return

end

if written ~= "allow" then
if stat . stat then
c . checkStat ( stat . stat )
end
return
end





local set = { }
if not stat . annotationArgs or # stat . annotationArgs == 0 then
set [ "*" ] = true
else
for _ , arg in ipairs ( stat . annotationArgs ) do
local expr = arg . kind == "annotationArg" and arg . expr or nil
local named = arg . kind == "annotationArg" and arg . name or nil
local spelled = nil
if expr and expr . kind == "name" then
local tok = expr . token
spelled = tok and tok . text or nil
end
local name = spelled or stringValue ( expr )
if named or not name then
c . diag ( "NUPP2112" , arg , "@allow arguments must be lint names or codes" )
elseif not lints . get ( name ) then


c . diag ( "NUPP2108" , arg , ( "%s is not a lint, so it cannot be allowed" ) : format ( name ) )
end
if name then
set [ name ] = true
end
end
end
c . allowed [ # c . allowed + 1 ] = set
if stat . stat then
c . checkStat ( stat . stat )
end
c . allowed [ # c . allowed ] = nil
end

return handlers
end

return pragma
