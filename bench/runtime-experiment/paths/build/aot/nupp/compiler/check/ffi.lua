_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()















local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )
local narrowing = require ( "nupp.compiler.types.narrowing" )
local cst = require ( "nupp.compiler.syntax.cst" )
local operators = require ( "nupp.compiler.check.operators" )
local state = require ( "nupp.compiler.check.state" )
local capabilities = require ( "nupp.compiler.capabilities" )

local isA = relations . isA
local subtract = narrowing . subtract
local rawType = T . unwrapOwnership

local ffi = { }



local function cHeader ( c ) 
return assert (
c . env and c . env . compilerServices and c . env . compilerServices . cheader ,
"native C-header compiler service is unavailable"
)
end
























local function fieldlessCdef ( t ) 
return t ~= nil and t . tag == "nominal" and t . cdefName ~= nil and # ( t . fieldOrder or { } ) == 0
end


local function cdefBody ( text ) 
return text : match ( "^%[%[(.*)%]%]$" )
or text : match ( "^\"(.*)\"$" )
or text : match ( "^'(.*)'$" )
or text : match ( "^%[=+%[(.*)%]=+%]$" )
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
if not capabilities . require ( c , "cinterop" , node ) then
return T . any
end
local spec = nil
local firstArg = args [ 1 ]
local specTok = firstArg and firstArg . kind == "string" and firstArg . token or nil
if specTok then
local t = specTok . text
spec = t : match ( "^\"(.*)\"$" ) or t : match ( "^'(.*)'$" ) or t : match ( "^%[%[(.*)%]%]$" )
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
local t , err = ( assert ( c . env and c . env . compilerServices and c . env . compilerServices . cheader , "native C-header compiler service is unavailable" ) ) . typeFromString ( spec , resolver )
if t then
resolved = t
else
c . diag ( "NUPP2304" , node , ("not a C type: %s (%s)") : format ( spec , tostring ( err ) ) )
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
if not capabilities . require ( c , "cinterop" , node ) then
for _ , e in ipairs ( argExprs ) do
c . infer ( e )
end
return T . any
end
local name = memberName
local argT = c . resolveType ( typeArg )
if name == "istype" then
node . typeTestTarget = argT
end
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
if name == "new" and ( argT ~= nil and argT . tag == "nominal" and argT . cdefName ~= nil and # ( argT . fieldOrder or { } ) == 0 ) then
c . diag (
"NUPP2203" ,
node ,
("%s declares no fields, so C gives it no size; use it only behind a pointer")

: format ( tostring ( ( argT ) . name ) )
)
return argT
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





local profile = c . env and c . env . targetProfile or nil
if profile ~= nil and not ( profile ) . ffiCallbacks then
c . diag (
"NUPP2904" ,
node ,
"an FFI callback needs a trampoline, and " .. tostring (
( profile ) . target
) .. " allocates none"
)
end
if c . unsafeDepth == 0 then
c . diag (
"NUPP2604" ,
node ,
"creating an FFI callback requires @unsafe on the cast and an explicit retained owner"
)
else




c . diag (
"jit-callback" ,
node ,
"a Lua function cast to a C callback stays registered and cannot be compiled through" ,
nil ,
{ help = "keep the callback off hot paths, or call C with a plain pointer instead" }
)
node . unsafeOwnershipOperation = "FFI callback creation"
end
end
if name == "cast" and ffiArgs [ 1 ] and c . ownershipKind ( ffiArgs [ 1 ] ) then
c . diag (
"NUPP2603" ,
node ,
"casting an affine value or borrow requires explicit @unsafe nupp.release or borrowFrom"
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
capabilities . require ( c , "cstorage" , node )
local args = argExprs
local elemT = args [ 1 ] and c . infer ( args [ 1 ] ) or nil
if elemT and elemT . tag == "typeobject" then
elemT = elemT . of
end
local countT = args [ 2 ] and c . infer ( args [ 2 ] ) or nil
if not elemT or elemT . tag ~= "nominal" or elemT . declKind ~= "struct" then
c . diag ( "NUPP2401" , node , "carray needs a struct type as its first argument" )
return T . any
end
if ( elemT ~= nil and elemT . tag == "nominal" and elemT . cdefName ~= nil and # ( elemT . fieldOrder or { } ) == 0 ) then
c . diag (
"NUPP2401" ,
node ,
("%s declares no fields, so C gives it no size and an array of it has no elements")

: format ( tostring ( elemT . name ) )
)
return T . any
end
if not countT or not ( countT == T . any or isA ( countT , T . number ) ) then
c . diag ( "NUPP2401" , node , "carray needs an element count as its second argument" )
return T . any
end



node . carrayElem = args [ 1 ]
local count = countT . tag == "literal"
and type ( countT . constant ) == "number"
and countT . constant >= 0
and countT . constant % 1 == 0
and countT . constant
or nil
return T . carray ( elemT , count )












elseif calleeName == "layoutof" then
capabilities . require ( c , "structvalue" , node )
local args = argExprs
local subject = args [ 1 ] and c . infer ( args [ 1 ] ) or nil
if subject and subject . tag == "typeobject" then
subject = subject . of
end
if not subject or subject . tag ~= "nominal" or subject . declKind ~= "struct" then
c . diag ( "NUPP2402" , node , "layoutof needs a struct type as its argument" , nil , {
help = "a record is a table and has no C layout; only a struct is laid out in memory"
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
local byValue = fieldType
and (
( fieldType . tag == "nominal" and fieldType . declKind == "struct" )
or ( elementOf and elementOf . tag == "nominal" and elementOf . declKind == "struct" )
)
if not spelling then


c . diag ( "NUPP2402" , node , ("field %q of %s has no C spelling") : format ( name , subject . name ) )
return T . any
end
parts [ # parts + 1 ] = name .. ":" .. ( byValue and ( "$" .. spelling ) or spelling )
printed [ # printed + 1 ] = name .. ":" .. ( expand ( fieldType ) or spelling )
if byValue then
nested [ # nested + 1 ] = elementOf and ( elementOf ) . name or spelling
end
end
if # parts == 0 then
c . diag ( "NUPP2402" , node , ("%s declares no fields, so it has no layout") : format ( subject . name ) )
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
if not capabilities . require ( c , "cinterop" , node ) then
return T . any
end
local args = argExprs

local function literal ( e ) 
if e and e . kind == "string" then
local t = e . token . text
return t : match ( "^\"(.*)\"$" ) or t : match ( "^'(.*)'$" )
end

return nil
end

local headerPath = literal ( args [ 1 ] )
local lib = literal ( args [ 2 ] )
if not headerPath then
c . diag ( "NUPP2301" , node , "cheader needs a header path written as a literal" )
return T . any
end




if args [ 2 ] and not lib and args [ 2 ] . kind ~= "nilExpr" then
c . diag ( "NUPP2301" , args [ 2 ] , "cheader's library must be a literal string or nil" )
return T . any
end
if args [ 3 ] and literal ( args [ 3 ] ) ~= "preprocess" then
c . diag ( "NUPP2301" , args [ 3 ] , "cheader's third argument can only be the literal \"preprocess\"" )
return T . any
end
if # args > 3 then
c . diag ( "NUPP2301" , args [ 4 ] , "cheader takes a path, a library and \"preprocess\", and nothing more" )
return T . any
end
local preprocess = args [ 3 ] ~= nil




local candidates
if headerPath : match ( "^[/\\]" ) or headerPath : match ( "^%a:[/\\]" ) then
candidates = { headerPath }
else
local dir = ( c . filename ) : match ( "^(.*)[/\\][^/\\]*$" ) or "."
candidates = { dir .. "/" .. headerPath , headerPath }
for _ , root in ipairs ( c . env and c . env . roots or { } ) do
candidates [ # candidates + 1 ] = root .. "/" .. headerPath
end
end
local cheaderMod = ( assert ( c . env and c . env . compilerServices and c . env . compilerServices . cheader , "native C-header compiler service is unavailable" ) )
local loaded , err , missing
local externalReader = c . env and c . env . externalFile and function ( externalPath ) 
return c . env . externalFile ( c . env , externalPath )
end or nil
for _ , candidate in ipairs ( candidates ) do
loaded , err , missing = cheaderMod . load ( candidate , { preprocess = preprocess , read = externalReader , } )
if not loaded and not missing then
do break end
end
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
preprocess = preprocess ,
}
if c . env and c . env . observeExternalInput then
c . env . observeExternalInput ( c . env , input )
end
do break end
end
end
if not loaded then
c . diag (
"NUPP2302" ,
node ,
missing and ( "cannot read " .. headerPath ) or err or ( "cannot read " .. headerPath )
)
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
local ok , _ , names = ( assert ( c . env and c . env . compilerServices and c . env . compilerServices . cheader , "native C-header compiler service is unavailable" ) ) . declare ( body )
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
local ok , err , names = ( assert ( c . env and c . env . compilerServices and c . env . compilerServices . cheader , "native C-header compiler service is unavailable" ) ) . declare ( body )
c . recordCDeclarations ( names )
node . cdefDeclarationBlock = true
if not ok then
c . diag (
"NUPP2303" ,
node ,
("LuaJIT could not parse these declarations: %s") : format ( tostring ( err ) )
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

local __nuppExportValue= ffi ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.ffi"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.ffi"]=__nuppExports;return __nuppExports