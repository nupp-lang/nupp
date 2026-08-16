_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local annotations = { }


annotations.Deprecation = {} annotations.Deprecation.__index = annotations.Deprecation













local KNOWN_TARGETS = {
statement = true ,
declaration = true ,
binding = true ,
[ "local-binding" ] = true ,
[ "function" ] = true ,
[ "local-function" ] = true ,
[ "named-function" ] = true ,
[ "type-declaration" ] = true ,
record = true ,
interface = true ,
struct = true ,
alias = true ,
[ "c-declaration" ] = true ,
[ "c-function" ] = true ,
block = true ,
loop = true ,
conditional = true ,
assignment = true ,
call = true ,
field = true ,
}

local CATEGORIES = {
localStmt = { declaration = true , binding = true , [ "local-binding" ] = true } ,
localFuncStmt = { declaration = true , [ "function" ] = true , [ "local-function" ] = true , } ,
funcStmt = { declaration = true , [ "function" ] = true , [ "named-function" ] = true , } ,
inlineMethod = { declaration = true , [ "function" ] = true , [ "named-function" ] = true , } ,
constructorDecl = { declaration = true , [ "function" ] = true , [ "named-function" ] = true , } ,
typeAlias = { declaration = true , [ "type-declaration" ] = true , alias = true } ,
cdefFunc = { declaration = true , [ "c-declaration" ] = true , [ "c-function" ] = true , } ,
cdefStruct = { declaration = true , [ "type-declaration" ] = true , struct = true , [ "c-declaration" ] = true , } ,
doStmt = { block = true } ,
unsafeStmt = { block = true } ,
ifStmt = { conditional = true } ,
whileStmt = { loop = true } ,
repeatStmt = { loop = true } ,
fornumStmt = { loop = true } ,
forinStmt = { loop = true } ,
assignStmt = { assignment = true } ,
compoundAssignStmt = { assignment = true } ,
callStmt = { call = true } ,
fieldDecl = { field = true } ,
}













local Registry = { }
Registry . __index = Registry

local function identifier ( name )
return type ( name ) == "string" and name : match ( "^[%a_][%w_]*$" ) ~= nil
end

function Registry : define ( spec )
if type ( spec ) ~= "table" then
return nil , "annotation definition must be a table"
end
if not identifier ( spec . name ) then
return nil , "annotation name must be an identifier"
end
local previous = self . byname [ spec . name ]
if previous and ( not spec . source or previous . source ~= spec . source ) then
return nil , ( "annotation @%s is already defined" ) : format ( spec . name )
end
if spec . arguments ~= "none"
and spec . arguments ~= "names"
and spec . arguments ~= "affine"
and spec . arguments ~= "effects"
and spec . arguments ~= "warnings"
and spec . arguments ~= "typed"
and spec . arguments ~= "definition"
then
return nil , "unknown annotation argument policy"
end
if spec . arguments == "warnings" and spec . name ~= "allow" then
return nil , "the warnings argument policy is reserved for @allow"
end
if type ( spec . targets ) ~= "table" or # spec . targets == 0 then
return nil , "annotation definition must name at least one target"
end

local targetSet , targets = { } , { }
for j , target in ipairs ( spec . targets ) do
if not KNOWN_TARGETS [ target ] then
return nil , ( "unknown annotation target %q" ) : format ( tostring ( target ) )
end
if not targetSet [ target ] then
targetSet [ target ] = true
targets [ # targets + 1 ] = target
end
end

local definition = {
name = spec . name ,
arguments = spec . arguments ,
targets = targets ,
targetSet = targetSet ,
reserved = spec . reserved ,
members = spec . members ,
memberOrder = spec . memberOrder ,
singleValue = spec . singleValue ,
declaration = spec . declaration ,
source = spec . source ,
builtin = spec . builtin ,
}
self . byname [ definition . name ] = definition

return definition
end

function Registry : removeSource ( source )
for name , definition in pairs ( self . byname ) do
if definition . source == source then
self . byname [ name ] = nil
end
end
end

function Registry : get ( name )
return self . byname [ name ]
end

local function categories ( node )
local out = { }
if node and node . kind ~= "fieldDecl" then
out . statement = true
end
local fixed = node and CATEGORIES [ node . kind ]
for name in pairs ( fixed or { } ) do
out [ name ] = true
end
if node and node . kind == "recordDecl" then
out . declaration = true
out [ "type-declaration" ] = true
out [ node . declKind or "record" ] = true
end

return out
end

function Registry : accepts ( definition , node )
local actual = categories ( node )
for target in pairs ( definition . targetSet ) do
if actual [ target ] then
return true
end
end

return false
end

function Registry : describeTargets ( definition )
return table . concat ( definition . targets , ", " )
end

local BUILTINS = {
{ name = "annotation" , arguments = "definition" , targets = { "record" , "struct" } , } ,
{ name = "annotationValue" , arguments = "none" , targets = { "field" } , } ,
{ name = "ref" , arguments = "none" , targets = { "field" } , } ,
{ name = "allow" , arguments = "warnings" , targets = { "statement" } , } ,
{ name = "override" , arguments = "none" , targets = { "function" } , } ,
{ name = "partition" , arguments = "names" , targets = { "field" } , builtin = true , } ,
{ name = "effects" , arguments = "effects" , targets = { "function" , "c-function" , "local-binding" } , } ,
{ name = "relax" , arguments = "names" , targets = { "function" } , } ,
{ name = "derive" , arguments = "names" , targets = { "record" } , builtin = true , } ,
{ name = "json" , arguments = "typed" , targets = { "record" , "field" } , builtin = true , } ,
{ name = "debug" , arguments = "typed" , targets = { "field" } , builtin = true , } ,
{ name = "deprecated" , arguments = "typed" , targets = { "declaration" , "field" , "c-declaration" } , builtin = true , } ,
{ name = "syntax" , arguments = "typed" , targets = { "local-binding" } , builtin = true , } ,
{ name = "jit" , arguments = "none" , targets = { "function" } , } ,
{ name = "aot" , arguments = "typed" , targets = { "function" } , builtin = true , } ,
}

function annotations . new ( withBuiltins )



local registry = setmetatable (
{
byname = { } ,
define = Registry . define ,
get = Registry . get ,
accepts = Registry . accepts ,
describeTargets = Registry . describeTargets ,
removeSource = Registry . removeSource ,
} ,
Registry
)
if withBuiltins ~= false then
for _ , spec in ipairs ( BUILTINS ) do
assert ( registry : define ( spec ) )
end
end

return registry
end

local defaultRegistry = annotations . new ( )

function annotations . default ( )
return defaultRegistry
end




function annotations . hydrateBuiltins ( registry , typesApi )
local function optional ( t )
return typesApi . union ( { t , typesApi . nil_ } )
end

local function member ( name , t , isOptional )
return { name = name , type = t , optional = isOptional == true }
end

local json = registry : get ( "json" )
json . members = {
unknown = member (
"unknown" ,
typesApi . union ( {
typesApi . literal ( "reject" ) ,
typesApi . literal ( "ignore" )
} ) ,
true
) ,
name = member ( "name" , optional ( typesApi . string ) , true ) ,
omit = member ( "omit" , optional ( typesApi . boolean ) , true ) ,
omitEmpty = member ( "omitEmpty" , optional ( typesApi . boolean ) , true ) ,
}
json . memberOrder = { "unknown" , "name" , "omit" , "omitEmpty" }

local aot = registry : get ( "aot" )






aot . members = { lanes = member ( "lanes" , optional ( typesApi . boolean ) , true ) , }
aot . memberOrder = { "lanes" }

local debug = registry : get ( "debug" )
debug . members = {
skip = member ( "skip" , optional ( typesApi . boolean ) , true ) ,
redact = member ( "redact" , optional ( typesApi . boolean ) , true ) ,
}
debug . memberOrder = { "skip" , "redact" }

local deprecated = registry : get ( "deprecated" )
deprecated . members = {
reason = member ( "reason" , optional ( typesApi . string ) , true ) ,
replacement = member ( "replacement" , optional ( typesApi . string ) , true ) ,
}
deprecated . memberOrder = { "reason" , "replacement" }
deprecated . singleValue = "reason"

local syntax = registry : get ( "syntax" )
syntax . members = { value = member ( "value" , typesApi . string , false ) }
syntax . memberOrder = { "value" }
syntax . singleValue = "value"

end


function annotations . deprecationOf ( values )
for _ , annotation in ipairs ( values or { } ) do
if annotation . name == "deprecated" then
local deprecated = setmetatable({ }, annotations.Deprecation)
for _ , argument in ipairs ( annotation . arguments or { } ) do
if argument . name == "reason" and type ( argument . value ) == "string" then
deprecated . reason = argument . value
elseif argument . name == "replacement" and type ( argument . value ) == "string" then
deprecated . replacement = argument . value
end
end
return deprecated
end
end

return nil
end


function annotations . deprecationMarkdown ( deprecated )
if not deprecated then
return nil
end
local text = "**Deprecated.**"
if deprecated . reason and deprecated . reason ~= "" then
text = text .. " " .. deprecated . reason
end
if deprecated . replacement and deprecated . replacement ~= "" then
text = text .. " Use `" .. deprecated . replacement : gsub ( "`" , "\\`" ) .. "` instead."
end

return text
end



function annotations . bindBuiltinDeclarations (
registry ,
globalTypes ,
globalTypeDefs
)
local schemas = {
json = "nupp.derive.JSONOptions" ,
debug = "nupp.derive.DebugOptions" ,
deprecated = "nupp.__DeprecatedAnnotation" ,
}
local function resolve ( path )
local segments = { }
for segment in path : gmatch ( "[^.]+" ) do
segments [ # segments + 1 ] = segment
end
local schema = globalTypes and globalTypes [ segments [ 1 ] .. "." .. ( segments [ 2 ] or "" ) ]
for index = 3 , # segments do
schema = schema and schema . nestedTypes and schema . nestedTypes [ segments [ index ] ]
end

return schema
end

for annotationName , typeName in pairs ( schemas ) do
local definition = registry : get ( annotationName )
local schema = resolve ( typeName )
if definition and schema then
definition . declaration = schema . definition or globalTypeDefs and globalTypeDefs [ typeName ] or nil
for name , member in pairs ( definition . members or { } ) do
member . definition = schema . fieldDefs and schema . fieldDefs [ name ] or nil
end
end
end
end

return annotations
