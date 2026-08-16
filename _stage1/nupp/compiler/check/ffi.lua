_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);













local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )
local narrowing = require ( "nupp.compiler.narrowing" )
local cst = require ( "nupp.compiler.cst" )
local operators = require ( "nupp.compiler.check.operators" )
local state = require ( "nupp.compiler.check.state" )

local isA = relations . isA
local subtract = narrowing . subtract
local rawType = T . unwrapOwnership

local ffi = { }






















local function cdefBody ( text )
return text : match (
"^%[%[(.*)%]%]$"
) or text : match ( '^"(.*)"$' ) or text : match ( "^'(.*)'$" ) or text : match ( "^%[=+%[(.*)%]=+%]$" )
end





function ffi . install ( c )




return function (
node ,
calleeName ,
baseName ,
memberName ,
typeArg ,
argExprs ,
argStr
)







if baseName == "ffi" then
c . lookupEntry ( baseName )
end

if not typeArg and baseName == "ffi" and operators . ffiTypeFirst [ memberName ] then
local name = memberName
local args = argExprs
for _ , e in ipairs ( args ) do
c . infer ( e )
end
local spec = nil
local firstArg = args [ 1 ]
local specTok = firstArg and firstArg . kind == "string" and firstArg . token or nil
if specTok then
local t = specTok . text
spec = t : match ( '^"(.*)"$' ) or t : match ( "^'(.*)'$" ) or t : match ( "^%[%[(.*)%]%]$" )
end
local resolved
if spec then
local resolver = function ( tag )
local found = c . lookupType ( tag )
if found and found . tag == "nominal" then
return found
end

return nil
end
local t , err = require ( "nupp.compiler.cheader" ) . typeFromString ( spec , resolver )
if t then
resolved = t
else
c . diag ( "NUPP2304" , node , ( "not a C type: %s (%s)" ) : format ( spec , tostring ( err ) ) )
return T . any
end
end
if name == "istype" then
return T . boolean
end
if name == "sizeof" or name == "alignof" then
return T . integer
end
if not resolved then

return name == "typeof" and T . ctype ( T . cdata ) or T . cdata
end
if name == "typeof" then
return T . ctype ( resolved )

elseif name == "cast" then


return subtract ( resolved , T . nil_ )
end
return resolved
end



if typeArg then
local name = memberName
local argT = c . resolveType ( typeArg )
if argT and argT . tag == "nominal" and argT . cdefIdentity then
node . cdefIdentity = argT . cdefIdentity
end
local hint = typeArg
node . ffiIntrinsic = name
node . ffiTypeNode = hint
node . ffiTypeName = hint . reified or hint . cdefName or nil
local ffiArgs = { }
for j , e in ipairs ( argExprs ) do
ffiArgs [ j ] = c . infer ( e )
end
if name == "new" or name == "cast" then
if name == "cast" and c . pointerShaped ( argT ) and ffiArgs [ 1 ] and isA ( ffiArgs [ 1 ] , T . string ) then
local roots = c . own . provenanceOwners ( argExprs [ 1 ] )
if # roots == 0 then
c . diag (
"NUPP2501" ,
node ,
"a pointer into managed storage needs a named or preserved lifetime root"
)
else
c . own . capabilityFacts ( node ) . roots = roots
end
return T . borrowed ( argT )
end
if name == "cast" and c . pointerShaped ( argT ) and ffiArgs [ 1 ] and rawType ( ffiArgs [ 1 ] ) . tag == "func" then
if c . unsafeDepth == 0 then
c . diag (
"NUPP2604" ,
node ,
"creating an FFI callback requires unsafe do and " .. "an explicit retained owner"
)
else




c . diag (
"jit-callback" ,
node ,
"a Lua function cast to a C callback stays " .. "registered and cannot be compiled through" ,
nil ,
{ help = "keep the callback off hot paths, " .. "or call C with a plain pointer instead" }
)
node . unsafeOwnershipOperation = "FFI callback creation"
end
end
if name == "cast" and ffiArgs [ 1 ] and c . ownershipKind ( ffiArgs [ 1 ] ) then
c . diag (
"NUPP2603" ,
node ,
"casting an affine value or borrow requires explicit unsafe release or borrowFrom"
)
end
return argT
elseif name == "typeof" then
return T . ctype ( argT )
elseif name == "istype" then
return T . boolean
elseif name == "sizeof" or name == "alignof" then
return T . integer
end
return T . any
end


if calleeName == "carray" then
local args = argExprs
local elemT = args [ 1 ] and c . infer ( args [ 1 ] ) or nil
local countT = args [ 2 ] and c . infer ( args [ 2 ] ) or nil
if not elemT or elemT . tag ~= "nominal" or elemT . declKind ~= "struct" then
c . diag ( "NUPP2401" , node , "carray needs a struct type as its first argument" )
return T . any
end
if not countT or not ( countT == T . any or isA ( countT , T . number ) ) then
c . diag ( "NUPP2401" , node , "carray needs an element count as its second argument" )
return T . any
end



node . carrayElem = args [ 1 ]
local count = countT . tag == "literal" and type (
countT . constant
) == "number" and countT . constant >= 0 and countT . constant % 1 == 0 and countT . constant or nil
return T . carray ( elemT , count )












elseif calleeName == "layoutof" then
local args = argExprs
local subject = args [ 1 ] and c . infer ( args [ 1 ] ) or nil
if not subject or subject . tag ~= "nominal" or subject . declKind ~= "struct" then
c . diag ( "NUPP2402" , node , "layoutof needs a struct type as its argument" , nil , {
help = "a record is a table and has no C layout; only a " .. "struct is laid out in memory"
} )
return T . any
end







local function expand ( t )
if not t then
return nil
end
if t . tag == "nominal" and t . declKind == "struct" then
local inner = { }
for _ , fname in ipairs ( t . fieldOrder or { } ) do
local one = expand ( t . byname [ fname ] )
if not one then
return nil
end
inner [ # inner + 1 ] = fname .. ":" .. one
end
return "{" .. table . concat ( inner , "," ) .. "}"
end

return T . cName ( t )
end

local parts , nested , printed = { } , { } , { }
for _ , name in ipairs ( subject . fieldOrder or { } ) do
local fieldType = subject . byname [ name ]
local spelling = T . cName ( fieldType )








local elementOf = fieldType and fieldType . tag == "carray" and fieldType . count and fieldType . elem or nil
local byValue = fieldType and (
(
fieldType . tag == "nominal" and fieldType . declKind == "struct"
) or ( elementOf and elementOf . tag == "nominal" and elementOf . declKind == "struct" )
)
if not spelling then


c . diag ( "NUPP2402" , node , ( "field %q of %s has no C spelling" ) : format ( name , subject . name ) )
return T . any
end
parts [ # parts + 1 ] = name .. ":" .. ( byValue and ( "$" .. spelling ) or spelling )
printed [ # printed + 1 ] = name .. ":" .. ( expand ( fieldType ) or spelling )
if byValue then
nested [ # nested + 1 ] = elementOf and ( elementOf ) . name or spelling
end
end
if # parts == 0 then
c . diag ( "NUPP2402" , node , ( "%s declares no fields, so it has no layout" ) : format ( subject . name ) )
return T . any
end
node . layoutOf = {
name = subject . name ,
spec = table . concat ( parts , "," ) ,
printed = table . concat ( printed , "," ) ,
nested = nested
}
return c . lookupType ( "Layout" ) or T . any





elseif calleeName == "cheader" then
local args = argExprs
local function literal ( e )
if e and e . kind == "string" then
local t = e . token . text
return t : match ( '^"(.*)"$' ) or t : match ( "^'(.*)'$" )
end

return nil
end

local headerPath = literal ( args [ 1 ] )
local lib = literal ( args [ 2 ] )
if not headerPath then
c . diag ( "NUPP2301" , node , "cheader needs a header path written as a literal" )
return T . any
end
local dir = c . filename : match ( "^(.*)[/\\][^/\\]*$" ) or "."
local candidates = { dir .. "/" .. headerPath , headerPath }
for _ , root in ipairs ( c . env and c . env . roots or { } ) do
candidates [ # candidates + 1 ] = root .. "/" .. headerPath
end
local cheaderMod = require ( "nupp.compiler.cheader" )
local loaded , err
local externalReader = c . env and c . env . externalFile and function ( externalPath )
return c . env . externalFile ( c . env , externalPath )
end or nil
for _ , candidate in ipairs ( candidates ) do
loaded , err = cheaderMod . load ( candidate , {
preprocess = literal ( args [ 3 ] ) == "preprocess" ,
read = externalReader ,
} )
if loaded then
node . cheaderCdef = loaded . cdef
node . cheaderLib = lib
local firstArg = args [ 1 ]
local consumerLine = firstArg
and firstArg . kind == "string"
and firstArg . token
and firstArg . token . line
or 1
local input = {
identity = "header\0" .. loaded . sourcePath ,
kind = "header" ,
display = headerPath ,
paths = loaded . dependencies ,
sourcePath = loaded . sourcePath ,
fingerprint = loaded . semanticFingerprint ,
consumer = tostring ( c . filename or "<module>" ) .. ":" .. tostring ( consumerLine ) ,
binary = false ,
library = lib ,
preprocess = literal ( args [ 3 ] ) == "preprocess" ,
}
if c . env and c . env . observeExternalInput then
c . env . observeExternalInput ( c . env , input )
end
break
end
end
if not loaded then
c . diag ( "NUPP2302" , node , err or ( "cannot read " .. headerPath ) )
return T . any
end


c . recordCDeclarations ( loaded . exports )
local fields = { }
for name , t in pairs ( loaded . exports ) do
fields [ # fields + 1 ] = { name = name , type = t }
end
return T . shape ( fields )
end




if calleeName == "pcall" or calleeName == "xpcall" then
local callee = argExprs [ 1 ]
local subject = argExprs [ calleeName == "pcall" and 2 or 3 ]
if callee
and callee . kind == "dotIndex"
and callee . name
and callee . name . text == "cdef"
and callee . obj
and callee . obj . kind == "name"
and callee . obj . token
and callee . obj . token . text == "ffi"
and subject
and subject . kind == "string"
and subject . token
then
local body = cdefBody ( subject . token . text )
if body then
local ok , _ , names = require ( "nupp.compiler.cheader" ) . declare ( body )
if ok then
c . recordCDeclarations ( names )
node . cdefDeclarationBlock = true
end
end
end
end



if baseName == "ffi" and memberName == "cdef" then
local args = argExprs
local strTok = argStr
local firstArg = args [ 1 ]
if not strTok and firstArg and firstArg . kind == "string" then
strTok = firstArg . token
end
if strTok then
local body = cdefBody ( strTok . text )
if body then
local ok , err , names = require ( "nupp.compiler.cheader" ) . declare ( body )
c . recordCDeclarations ( names )
node . cdefDeclarationBlock = true
if not ok then
c . diag (
"NUPP2303" ,
node ,
( "LuaJIT could not parse these declarations: %s" ) : format ( tostring ( err ) )
)
end
end
else
for _ , e in ipairs ( args ) do
c . infer ( e )
end
end
return T . nil_
end




if baseName == "ffi" and memberName == "load" then
local first = argExprs [ 1 ]
if first and first . kind == "string" and first . token then
node . ffiLoadLib = cdefBody ( first . token . text )
else
node . ffiLoadDynamic = true
end
for _ , e in ipairs ( argExprs ) do
c . infer ( e )
end
return c . cNamespaceType ( )
end

if baseName == "ffi" and memberName == "gc" then
local args = argExprs
local valueT = args [ 1 ] and c . infer ( args [ 1 ] ) or T . any
for j = 2 , # args do
c . infer ( args [ j ] )
end
local entry = args [ 1 ] and c . ownershipEntry ( args [ 1 ] ) or nil
entry = c . ownershipState ( entry )
if c . ownershipKind ( valueT ) or entry and c . own . capabilityFacts ( entry , nil , false ) . retention then
c . diag (
"NUPP2603" ,
args [ 1 ] or node ,
"ffi.gc would add an untracked second cleanup path to a capability-bearing value"
)
return rawType ( valueT )
end
return valueT
end

return nil
end
end

return ffi
