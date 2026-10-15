_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.annotations\0runtime\0001") };









local annotations = { }
local pathtext = require ( "nupp.io.path.pathtext" )

local function sameSource ( left , right ) 
if type ( left ) == "string" and type ( right ) == "string" then
local windows = package . config : sub ( 1 , 1 ) == "\\"
return pathtext . normalize ( left , windows ) == pathtext . normalize ( right , windows )
end

return left == right
end


annotations.Deprecation = {} annotations.Deprecation.__index = annotations.Deprecation ;_G.nupp.__reflect.link(annotations.Deprecation,__nuppT1[1],{ })
















local KNOWN_TARGETS = {
expression = true ,
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
type = true ,
indexer = true ,
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
withStmt = { block = true } ,
ifStmt = { conditional = true } ,
whileStmt = { loop = true } ,
repeatStmt = { loop = true } ,
fornumStmt = { loop = true } ,
forinStmt = { loop = true } ,
assignStmt = { assignment = true } ,
compoundAssign = { assignment = true } ,
callStmt = { call = true } ,
fieldDecl = { field = true } ,
indexerDecl = { indexer = true } ,
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
if previous and ( not spec . source or not sameSource ( previous . source , spec . source ) ) then
return nil , ("annotation @%s is already defined") : format ( spec . name )
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
return nil , ("unknown annotation target %q") : format ( tostring ( target ) )
end
if target == "expression" and not spec . builtin then
return nil , "expression annotations must be compiler-registered"
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
qualifiedNames = spec . qualifiedNames ,
doc = spec . doc ,
docsPath = spec . docsPath ,
}
self . byname [ definition . name ] = definition

return definition
end

function Registry : removeSource ( source ) 


if source == nil then
return
end
for name , definition in pairs ( self . byname ) do
if sameSource ( definition . source , source ) then
self . byname [ name ] = nil
end
end
end


function Registry : definedBy ( source ) 
local names = { }
for name , definition in pairs ( self . byname ) do
if source ~= nil and sameSource ( definition . source , source ) then
names [ # names + 1 ] = name
end
end
table . sort ( names )
local out = { }
for index , name in ipairs ( names ) do
out [ index ] = self . byname [ name ]
end

return out
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
if definition . name == "unsafe" then
local allowed = {
doStmt = true ,
ifStmt = true ,
fornumStmt = true ,
forinStmt = true ,
whileStmt = true ,
repeatStmt = true ,
localStmt = true ,
assignStmt = true ,
compoundAssign = true ,
callStmt = true ,
}
return node ~= nil and allowed [ node . kind ] == true
end
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
{
name = "nosuspend" ,
arguments = "none" ,
builtin = true ,
targets = { "type" , "block" , "loop" } ,
doc = "Requires a callable type, block or loop that cannot suspend." ,
docsPath = "docs/learn/runtime/concurrency/suspension.md#non-suspending-regions" ,
} ,
{
name = "sendable" ,
arguments = "none" ,
builtin = true ,
targets = { "type" } ,
doc = "Requires a callable type reproducible in another isolated Lua state." ,
docsPath = "docs/reference/annotations.md#built-in-annotations" ,
} ,
{
name = "comptime" ,
arguments = "none" ,
builtin = true ,
targets = { "type" , "function" , "type-declaration" } ,
doc = "Restricts a callable or type declaration to compile-time use." ,
docsPath = "docs/reference/annotations.md#built-in-annotations" ,
} ,
{
name = "noalloc" ,
arguments = "none" ,
builtin = true ,
targets = { "block" } ,
doc = "Requires a block that performs no allocation." ,
docsPath = "docs/learn/language/effects.md#allocation-and-raising-regions" ,
} ,
{
name = "noraise" ,
arguments = "none" ,
builtin = true ,
targets = { "block" } ,
doc = "Requires a block that cannot raise an error." ,
docsPath = "docs/learn/language/effects.md#allocation-and-raising-regions" ,
} ,
{
name = "readonly" ,
arguments = "none" ,
builtin = true ,
targets = { "field" , "indexer" } ,
doc = "Makes a declared property or indexer readable but not writable." ,
docsPath = "docs/learn/language/types/properties.md#declaring-a-capability" ,
} ,
{
name = "writeonly" ,
arguments = "none" ,
builtin = true ,
targets = { "field" , "indexer" } ,
doc = "Makes a declared property or indexer writable but not readable." ,
docsPath = "docs/learn/language/types/properties.md#declaring-a-capability" ,
} ,
{
name = "private" ,
arguments = "none" ,
builtin = true ,
targets = { "field" } ,
doc = "Restricts a record field to its declaring module." ,
docsPath = "docs/learn/language/types/records-and-structs.md#private-fields" ,
} ,
{
name = "unsafe" ,
arguments = "none" ,
builtin = true ,
targets = { "expression" , "block" , "conditional" , "loop" , "local-binding" , "assignment" , "call" } ,
doc = "Authorizes unsafe operations in one statement or operand; nested function bodies authorize their own operations." ,
docsPath = "docs/reference/annotations.md#unsafe-operations" ,
} ,
{
name = "annotation" ,
arguments = "definition" ,
targets = { "record" , "struct" } ,
doc = "Declares a record or struct as an annotation definition; `targets` says where applications may attach." ,
docsPath = "docs/reference/annotations.md#defining-an-annotation" ,
} ,
{
name = "annotationValue" ,
arguments = "none" ,
targets = { "field" } ,
doc = "Marks one annotation-definition field as the single positional value, so `@name(value)` and `@name(field = value)` mean the same thing." ,
docsPath = "docs/reference/annotations.md#single-value-applications" ,
} ,
{
name = "ref" ,
arguments = "none" ,
targets = { "field" } ,
doc = "Marks an annotation-definition field whose value is a type reference rather than a literal constant." ,
docsPath = "docs/reference/annotations.md#type-reference-members" ,
} ,
{
name = "allow" ,
arguments = "warnings" ,
targets = { "statement" } ,
doc = "Suppresses the named lints, by name or code, for the statement it decorates. Does not suppress a type error." ,
docsPath = "docs/reference/annotations.md#allow" ,
} ,
{
name = "override" ,
arguments = "none" ,
targets = { "function" } ,
doc = "Marks a method that replaces an inherited interface method; required on child-interface overrides and on implementations replacing a default, and an error when no matching method exists." ,
docsPath = "docs/reference/annotations.md#override" ,
} ,
{
name = "partition" ,
arguments = "names" ,
targets = { "field" } ,
builtin = true ,
doc = "An audited ownership assertion: the method's first result carries two sibling-disjoint regions in the named fields, on a sealed interface only." ,
docsPath = "docs/reference/annotations.md#partition" ,
} ,
{
name = "effects" ,
arguments = "effects" ,
targets = { "function" , "c-function" , "local-binding" } ,
doc = "A complete, pessimistic effect contract: reads, writes, shapes, metatables, escapes, calls, returns, allocates, suspends, raises, external." ,
docsPath = "docs/learn/language/effects.md#complete-contract" ,
} ,
{
name = "relax" ,
arguments = "names" ,
targets = { "function" } ,
doc = "Names guarantees a function may give up, of eight: function-identity, load-order, error-site, frames, gc-timing, table-order, and the numeric fp-contract and fp-transcendentals. Permits a rewrite that would otherwise change observable behavior." ,
docsPath = "docs/reference/annotations.md#relaxing-observable-guarantees" ,
} ,
{
name = "derive" ,
arguments = "names" ,
targets = { "record" , "struct" } ,
builtin = true ,
qualifiedNames = true ,
doc = "Runs a closed comptime recipe, e.g. `nupp.derive.Debug`, that adds checked members or data without exposing source or AST macros." ,
docsPath = "docs/reference/annotations.md#derive" ,
} ,
{
name = "cli" ,
arguments = "typed" ,
targets = { "record" , "field" } ,
builtin = true ,
doc = "Configures command and field metadata consumed by `nupp.cli` derives." ,
docsPath = "docs/learn/projects/command-line-applications.md#derive-typed-arguments" ,
} ,
{
name = "debug" ,
arguments = "typed" ,
targets = { "field" } ,
builtin = true ,
doc = "Configures how the debug derive shows a derived record's field: skip or redact." ,
docsPath = "docs/reference/derives.md#debug" ,
} ,
{
name = "event" ,
arguments = "typed" ,
targets = { "record" , "struct" } ,
builtin = true ,
doc = "Names the event a declaration deriving `nupp.events.Event` registers as." ,
docsPath = "docs/reference/derives.md#event" ,
} ,
{
name = "deprecated" ,
arguments = "typed" ,
targets = { "declaration" , "field" , "c-declaration" } ,
builtin = true ,
doc = "Marks an API for migration while keeping it callable. Hover shows the reason and replacement, and a use reports the suppressible `deprecated` lint." ,
docsPath = "docs/reference/annotations.md#deprecated" ,
} ,
{
name = "syntax" ,
arguments = "typed" ,
targets = { "local-binding" } ,
builtin = true ,
doc = "Names the embedded language of a local/const long-string initializer, e.g. `@syntax(\"json\")`, for editor syntax highlighting." ,
docsPath = "docs/reference/annotations.md#syntax" ,
} ,
{
name = "jit" ,
arguments = "none" ,
targets = { "function" } ,
doc = "An absence-of-known-blockers contract for the selected LuaJIT trace profile; a call path to a catalogued recorder blocker reports NUPP2707." ,
docsPath = "docs/reference/annotations.md#jit" ,
} ,
{
name = "aot" ,
arguments = "typed" ,
targets = { "function" } ,
builtin = true ,
doc = "Reserves a required whole-function ahead-of-time compilation contract. A build's `aot` policy decides what happens with it: off (default), require, emit-wasm or require-wasm." ,
docsPath = "docs/reference/annotations.md#aot" ,
} ,
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
definedBy = Registry . definedBy ,
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




local function member ( name , t , isOptional , doc , docsPath ) 
return { name = name , type = t , optional = isOptional == true , doc = doc , docsPath = docsPath }
end

local cli = registry : get ( "cli" )
local cliDocs = "docs/learn/projects/command-line-applications.md#derive-typed-arguments"

local function cliMember ( name , t , reference ) 
local value = member ( name , optional ( t ) , true , nil , "docs/learn/projects/command-line-applications.md#derive-typed-arguments" )
value . reference = reference == true
return value
end

cli . members = {
name = cliMember ( "name" , typesApi . string ) ,
long = cliMember ( "long" , typesApi . boolean ) ,
aliases = cliMember ( "aliases" , typesApi . array ( typesApi . string ) ) ,
constantAliases = cliMember ( "constantAliases" , typesApi . map ( typesApi . string , typesApi . string ) ) ,
short = cliMember ( "short" , typesApi . string ) ,
value = cliMember ( "value" , typesApi . string ) ,
display = cliMember ( "display" , typesApi . string ) ,
invalid = cliMember ( "invalid" , typesApi . string ) ,
arity = cliMember (
"arity" ,
typesApi . union ( {
typesApi . literal ( "none" ) ,
typesApi . literal ( "required" ) ,
typesApi . literal ( "optionalAttached" ) ,
typesApi . literal ( "attachedOnly" )
} )
) ,
positional = cliMember ( "positional" , typesApi . string ) ,
remainder = cliMember ( "remainder" , typesApi . boolean ) ,
hidden = cliMember ( "hidden" , typesApi . boolean ) ,
group = cliMember ( "group" , typesApi . boolean ) ,
preserveUnknown = cliMember ( "preserveUnknown" , typesApi . boolean ) ,
stopAtFirstArgument = cliMember ( "stopAtFirstArgument" , typesApi . boolean ) ,
constant = cliMember ( "constant" , typesApi . union ( { typesApi . string , typesApi . integer , typesApi . boolean } ) ) ,
pattern = cliMember ( "pattern" , typesApi . string ) ,
choices = cliMember ( "choices" , typesApi . array ( typesApi . string ) ) ,
complete = cliMember ( "complete" , typesApi . any , true ) ,
}
cli . memberOrder = {
"name" ,
"long" ,
"aliases" ,
"constantAliases" ,
"short" ,
"value" ,
"display" ,
"invalid" ,
"arity" ,
"positional" ,
"remainder" ,
"hidden" ,
"group" ,
"preserveUnknown" ,
"stopAtFirstArgument" ,
"constant" ,
"pattern" ,
"choices" ,
"complete"
}
cli . singleValue = "name"

local aot = registry : get ( "aot" )
aot . members = {
target = member (
"target" ,
optional (
typesApi . union ( {
typesApi . literal ( "cpu" ) ,
typesApi . literal ( "gpu" )
} )
) ,
true ,
"Selects the execution family: `\"cpu\"` (the default) or `\"gpu\"`." ,
"docs/reference/annotations.md#aot"
) ,
}
aot . memberOrder = { "target" }

local event = registry : get ( "event" )
event . members = {
name = member (
"name" ,
optional ( typesApi . string ) ,
true ,
"The name the event registers under; the declaration's own name when omitted." ,
"docs/reference/derives.md#event"
) ,
}
event . memberOrder = { "name" }

local debug = registry : get ( "debug" )

debug . members = {
skip = member (
"skip" ,
optional ( typesApi . boolean ) ,
true ,
"Omits this field from the derived debug representation." ,
"docs/reference/derives.md#debug"
) ,
redact = member (
"redact" ,
optional ( typesApi . boolean ) ,
true ,
"Shows this field's value redacted in the derived debug representation." ,
"docs/reference/derives.md#debug"
) ,
}
debug . memberOrder = { "skip" , "redact" }

local deprecated = registry : get ( "deprecated" )

deprecated . members = {
reason = member (
"reason" ,
optional ( typesApi . string ) ,
true ,
"Why the API is deprecated, shown on hover and in generated documentation." ,
"docs/reference/annotations.md#deprecated"
) ,
replacement = member (
"replacement" ,
optional ( typesApi . string ) ,
true ,
"The API to migrate to, shown on hover and in generated documentation." ,
"docs/reference/annotations.md#deprecated"
) ,
}
deprecated . memberOrder = { "reason" , "replacement" }
deprecated . singleValue = "reason"

local syntax = registry : get ( "syntax" )
syntax . members = {
value = member (
"value" ,
typesApi . string ,
false ,
"The embedded language name, e.g. `\"json\"`, used for editor syntax highlighting." ,
"docs/reference/annotations.md#syntax"
) ,
}
syntax . memberOrder = { "value" }
syntax . singleValue = "value"

end


function annotations . deprecationOf ( values ) 
for _ , annotation in ipairs ( values or { } ) do
if annotation . name == "deprecated" then
local deprecated = _G.setmetatable({ }, annotations.Deprecation)
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
local schemas

= {
debug = "nupp.derive.DebugOptions" ,
event = "nupp.derive.EventOptions" ,
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

local __nuppExportValue= annotations ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.annotations"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.annotations"]=__nuppExports;return __nuppExports