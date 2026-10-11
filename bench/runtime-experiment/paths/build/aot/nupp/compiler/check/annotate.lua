_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local T = require ( "nupp.compiler.types" )
local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local relations = require ( "nupp.compiler.types.relations" )
local state = require ( "nupp.compiler.check.state" )
local annotationMod = require ( "nupp.compiler.annotations" )

local annotate = { }

local isA = relations . isA


























function annotate . install ( c ) 
local ops = { }

function ops . annotationType ( expr ) 
local names = { }

local function collect ( node ) 
if not node then
return false
elseif node . kind == "name" and node . token then
names [ # names + 1 ] = node . token
return true
elseif node . kind == "dotIndex" and node . name and collect ( node . obj ) then
names [ # names + 1 ] = node . name
return true
end

return false
end

if not collect ( expr ) or not names [ 1 ] then
return nil
end
local node = _G.setmetatable({ kind =  "tname" ,  base =  names [ 1 ] }, cst.Tname)
for _ , token in ipairs ( names ) do
node [ # node + 1 ] = token
end

return node
end




function ops . nameText ( expr ) 
if not expr or expr . kind ~= "name" then
return nil
end
local tok = expr . token

return tok and tok . text or nil
end

function ops . stringValue ( expr ) 
if not expr or expr . kind ~= "string" then
return nil
end
local text = expr . token . text
local quote = text : sub ( 1 , 1 )
if ( quote == "\"" or quote == "'" ) and text : sub ( -1 ) == quote then
return text : sub ( 2 , -2 )
end

return nil
end

local function constantAnnotationExpr ( expr ) 
if not expr then
return false
end
local kind = expr . kind
if kind == "string" or kind == "number" or kind == "nilExpr" or kind == "trueExpr" or kind == "falseExpr" then
return true
end
if kind ~= "tableExpr" then
return false
end
for _ , field in ipairs ( expr . fields or { } ) do
if field . kind == "fieldItem" or field . kind == "fieldNamed" then
if not constantAnnotationExpr ( field . value ) then
return false
end
else
return false
end
end

return true
end




local function constantAnnotationValue ( expr ) 
if not expr then
return nil
end
local kind = expr . kind
if kind == "nilExpr" then
return nil
elseif kind == "trueExpr" then
return true
elseif kind == "falseExpr" then
return false
elseif kind == "number" or kind == "string" then
local text = expr . token and expr . token . text or ( kind == "number" and "0" or "\"\"" )
local chunk = loadstring ( "return " .. text )
if chunk then
local ok , value = pcall ( chunk )
if ok then
return value
end
end
return text
elseif kind == "tableExpr" then
local value , nextIndex = { } , 1
for _ , field in ipairs ( expr . fields or { } ) do
if field . kind == "fieldItem" then
value [ nextIndex ] = constantAnnotationValue ( field . value )
nextIndex = nextIndex + 1
elseif field . kind == "fieldNamed" then
value [ field . name and field . name . text or "" ] = constantAnnotationValue ( field . value )
end
end
return value
end

return nil
end

local function resolvedAnnotation ( application , definition2 ) 
if definition2 . arguments ~= "typed" then
return nil
end
local reflected = { name = definition2 . name , arguments = { } }
for _ , memberName in ipairs ( definition2 . memberOrder or { } ) do
local arg = application . annotationValues and application . annotationValues [ memberName ]
if arg then
local entry = { name = memberName }
if arg . annotationReferenceType then
entry . kind = "type"
entry . type = arg . annotationReferenceType
elseif arg . expr and arg . expr . kind == "nilExpr" then
entry . kind = "nil"
else
entry . kind = "value"
entry . value = constantAnnotationValue ( arg . expr )
end
reflected . arguments [ # reflected . arguments + 1 ] = entry
end
end

return reflected
end

local function annotationReferencePath ( expr ) 
if not expr then
return nil
end
if expr . kind == "name" then
return { expr . token . text } , { expr . token }
end
if expr . kind ~= "dotIndex" then
return nil
end
local names , tokens = annotationReferencePath ( expr . obj )
if not names then
return nil
end
names [ # names + 1 ] = expr . name . text
tokens [ # tokens + 1 ] = expr . name

return names , tokens
end






local function resolveAnnotationReference ( application , member , arg ) 
local names , tokens = annotationReferencePath ( arg . expr )
if not names then
c . diag ( "NUPP2115" , arg . expr , ("@%s.%s must be a type reference") : format ( application . name . text , member . name ) )
return nil , false
end

local name = names [ # names ]
local tok = tokens [ # tokens ]
local t , def , lookupErr
if # names == 1 then
t = T . builtins [ name ]
if not t then
t , def , lookupErr = c . lookupType ( name )
end
else
local moduleNames = { }
for j = 1 , # names - 1 do
moduleNames [ j ] = names [ j ]
end
local moduleName = table . concat ( moduleNames , "." )
if # moduleNames == 1 then
local holder = c . lookupEntry ( moduleNames [ 1 ] )
if holder and holder . requiredModule then
moduleName = holder . requiredModule
end
end
if c . env and c . env . resolveQualifiedType then
t , def = c . env . resolveQualifiedType ( c . env , c . filename , moduleName , name )
end
end

c . markToken ( tok , def , t , def and def . kind or "type" )
if t then
arg . annotationReferenceType = t
return t , true
end
local message = lookupErr
and ("ambiguous type reference %q; use a module-qualified name") : format ( table . concat ( names , "." ) )
or ("unknown type reference %q") : format ( table . concat ( names , "." ) )
c . diag ( "NUPP2115" , arg . expr , message )

return nil , false
end

local function annotationTargets ( application ) 
local targets = nil
for _ , arg in ipairs ( application . annotationArgs or { } ) do
if not arg . name or arg . name . text ~= "targets" or targets then
c . diag ( "NUPP2114" , arg , "@annotation accepts one named argument: targets" )
elseif not arg . expr or arg . expr . kind ~= "tableExpr" then
c . diag ( "NUPP2114" , arg , "@annotation targets must be an array of target names" )
else
targets = { }
for _ , field in ipairs ( arg . expr . fields or { } ) do
local value = field . kind == "fieldItem" and ops . stringValue ( field . value ) or nil
if not value then
c . diag ( "NUPP2114" , field , "annotation targets must be string literals" )
else
targets [ # targets + 1 ] = value
end
end
end
end
if not targets or # targets == 0 then
c . diag ( "NUPP2114" , application , "@annotation requires a non-empty targets array" )
return nil
end

return targets
end

local function validateTypedAnnotation ( application , definition2 ) 
local members = definition2 . members or { }
local provided = { }
local positional = nil

for _ , arg in ipairs ( application . annotationArgs or { } ) do
local member
if arg . name then
member = members [ arg . name . text ]
if not member then
c . diag ( "NUPP2115" , arg . name , ("@%s has no member %q") : format ( definition2 . name , arg . name . text ) )
elseif provided [ arg . name . text ] then
c . diag (
"NUPP2115" ,
arg . name ,
("@%s member %q was supplied twice") : format ( definition2 . name , arg . name . text )
)
end
elseif positional then
c . diag ( "NUPP2115" , arg , ("@%s accepts at most one positional value") : format ( definition2 . name ) )
elseif not definition2 . singleValue then
c . diag ( "NUPP2115" , arg , ("@%s has no single-value member; use named values") : format ( definition2 . name ) )
else
positional = arg
member = members [ definition2 . singleValue ]
end

if member and not provided [ member . name ] then
if arg . name and member . definition then
c . markToken ( arg . name , member . definition , member . type , "property" )
elseif arg . name and member . doc then



c . markToken (
arg . name ,
{ name = member . name , kind = "property" , doc = member . doc , docsPath = member . docsPath } ,
member . type ,
"property"
)
end
provided [ member . name ] = arg
local actual , hasActual
if member . reference then
actual , hasActual = resolveAnnotationReference ( application , member , arg )
else
if not constantAnnotationExpr ( arg . expr ) then
c . diag ( "NUPP2115" , arg . expr , "annotation values must be compile-time constants" )
end
actual , hasActual = c . infer ( arg . expr ) , true
end
if hasActual then
local ok , why = isA ( actual , member . type )
if not ok then
c . diag (
"NUPP2115" ,
arg . expr ,
("@%s.%s: %s is not a %s%s")

: format (
definition2 . name ,
member . name ,
T . tostring ( actual ) ,
T . tostring ( member . type ) ,
why and ( " (" .. why .. ")" ) or ""
)
)
end
end
end
end

for _ , name in ipairs ( definition2 . memberOrder or { } ) do
local member = members [ name ]
if member and not member . optional and not provided [ name ] then
c . diag ( "NUPP2115" , application , ("@%s requires member %q") : format ( definition2 . name , name ) )
end
end
application . annotationValues = provided
end

function ops . validateAnnotation ( application , target , owner ) 
local annotation = c . annotationRegistry : get ( application . name . text )
local resolutionError = nil
if c . env
and c . env . resolveProjectAnnotation
and ( not annotation or annotation . source and annotation . source ~= c . filename )
then
annotation , resolutionError = c . env . resolveProjectAnnotation ( c . env , c . filename , application . name . text )
end
if not annotation then
if resolutionError then
c . diag ( "NUPP2111" , application . name , resolutionError )
else
c . diag ( "NUPP2111" , application . name , ("unknown annotation @%s") : format ( application . name . text ) )
end
return nil , false
end
application . annotationDefinition = annotation
local annotationSite = annotation . declaration
if annotationSite and not annotationSite . token and type ( annotationSite . name ) == "table" then
annotationSite = annotationSite . name . definition
end
if annotationSite then
c . markToken ( application . name , annotationSite , nil , "annotation" )
elseif annotation . doc then




c . markToken (
application . name ,
{ name = annotation . name , kind = "annotation" , doc = annotation . doc , docsPath = annotation . docsPath } ,
nil ,
"annotation"
)
end

local valid = true
local accepts = target and c . annotationRegistry : accepts ( annotation , target )
if application . typeAttachment then
accepts = annotation . builtin and annotation . targetSet . type
elseif application . propertyCapabilityAttachment then
accepts = annotation . builtin
and ( application . name . text == "readonly" or application . name . text == "writeonly" )
and (
target . kind == "tshapeField" and annotation . targetSet . field
or ( target . kind == "tmap" or target . kind == "tmapped" ) and annotation . targetSet . indexer
)
elseif application . expressionAttachment then
local direct = target
while direct and direct . kind == "paren" do
direct = direct . expr
end
accepts = annotation . builtin
and annotation . targetSet . expression
and direct
and direct . kind ~= "funcExpr"
and direct . kind ~= "shortfn"
end
if not accepts then
c . diag (
"NUPP2112" ,
application . name ,
("@%s may attach only to: %s")

: format ( application . name . text , c . annotationRegistry : describeTargets ( annotation ) ) ,
nil ,
{
help = application . name . text == "unsafe"
and "annotate operations inside a function body; use return @unsafe expression or yield @unsafe expression"
or "expression targets require explicit compiler support"
}
)
valid = false
end
if annotation . arguments == "none" and application . open then
c . diag ( "NUPP2112" , application . name , ("@%s does not take arguments") : format ( application . name . text ) )
valid = false
elseif annotation . arguments == "names" then
local function derivePath ( expr ) 
if not expr then
return false
end
if expr . kind == "name" then
return true
end

return expr . kind == "dotIndex" and derivePath ( expr . obj ) and expr . name and expr . name . text ~= nil
end

for _ , arg in ipairs ( application . annotationArgs or { } ) do
local qualifiedProvider = annotation . qualifiedNames and derivePath ( arg . expr )
if arg . name
or not arg . expr
or ( arg . expr . kind ~= "name" and arg . expr . kind ~= "string" and not qualifiedProvider )
then
c . diag ( "NUPP2112" , arg , ("@%s arguments must be names or strings") : format ( application . name . text ) )
valid = false
end
end
elseif annotation . arguments == "typed" then
validateTypedAnnotation ( application , annotation )
end
if annotation . reserved and valid then
c . diag (
"NUPP2113" ,
application . name ,
("@%s is reserved for %s, which is not implemented") : format ( application . name . text , annotation . reserved )
)
end
if ( application . name . text == "annotationValue" or application . name . text == "ref" )
and not ( owner and owner . isAnnotationDefinition )
then
c . diag (
"NUPP2114" ,
application ,
("@%s is valid only on an annotation definition member") : format ( application . name . text )
)
valid = false
end

if valid and target then
local targetAny = target
local reflected = resolvedAnnotation ( application , annotation )
if reflected and application . semanticAnnotationTarget ~= target then
targetAny . semanticAnnotations = targetAny . semanticAnnotations or { }
targetAny . semanticAnnotations [ # targetAny . semanticAnnotations + 1 ] = reflected
application . semanticAnnotationTarget = target
end
if reflected and reflected . name == "deprecated" then
targetAny . deprecation = annotationMod . deprecationOf ( { reflected } )
if targetAny . name and cst . isToken ( targetAny . name ) then
targetAny . name . deprecation = targetAny . deprecation
end
end
end

return annotation , valid
end

function ops . defineAnnotation ( application , declaration ) 
local name = declaration . name . text
if c . annotationDefinitions [ name ] then
c . diag ( "NUPP2114" , declaration . name , ("annotation @%s is already defined in this file") : format ( name ) )
return
end
c . annotationDefinitions [ name ] = true
local targets = annotationTargets ( application )
if not targets then
return
end
local nominal = declaration . resolvedType
local members , order = { } , { }
local singleValue = nil
for _ , entry in ipairs ( declaration . entries or { } ) do
if entry . kind == "fieldDecl" then
local name = entry . name . text
local member = {
name = name ,
type = nominal and nominal . byname [ name ] or T . any ,
optional = nominal
and nominal . byname [ name ]
and nominal . byname [ name ] . tag == "union"
and nominal . byname [ name ] . hasNil
or false ,
definition = nominal and nominal . fieldDefs and nominal . fieldDefs [ name ] or nil ,
}
members [ name ] = member
order [ # order + 1 ] = name
for _ , attached in ipairs ( entry . annotations or { } ) do
if attached . name . text == "annotationValue" then
if singleValue then
c . diag ( "NUPP2114" , attached , "an annotation has only one @annotationValue member" )
else
singleValue = name
end
elseif attached . name . text == "ref" then
member . reference = true
end
end
end
end
local definition2 , err = c . annotationRegistry : define ( {
name = name ,
arguments = "typed" ,
targets = targets ,
members = members ,
memberOrder = order ,
singleValue = singleValue ,
declaration = declaration ,
source = c . filename ,
} )
if not definition2 then
local reserved = c . annotationRegistry : get ( name )
c . diag (
"NUPP2114" ,
declaration . name ,
reserved and reserved . builtin and ( "annotation @" .. name .. " is reserved by Nupp" ) or err ,
nil ,
reserved
and reserved . builtin
and { help = "rename the project annotation; built-in annotation names are project-wide" }
or nil
)
return
end
declaration . annotationDefinition = definition2
application . definesAnnotation = definition2
end

return ops
end

local __nuppExportValue= annotate ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.annotate"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.annotate"]=__nuppExports;return __nuppExports