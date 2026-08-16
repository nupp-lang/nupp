_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






local T = require ( "nupp.compiler.types" )
local tree = require ( "nupp.compiler.lsp.tree" )
local wire = require ( "nupp.compiler.lsp.wire" )
local semantic = require ( "nupp.compiler.lsp.semantic" )

local complete = { }

local COMPTIME_GLOBALS = {
assert = true ,
error = true ,
ipairs = true ,
pairs = true ,
select = true ,
tonumber = true ,
tostring = true ,
type = true ,
math = true ,
string = true ,
table = true ,
bit = true ,
nupp = true ,
}































































function complete . completionContext ( result , offset )
local tokens = result and result . tokens or { }
local index = nil
for cursor , tok in ipairs ( tokens ) do
if tok . kind == "eof" or tok . offset >= offset then
break
end
index = cursor
end
if not index then
return nil
end
local context = { prefix = "" , typePosition = false }
local tok = tokens [ index ]
if tok . kind == "name" and offset <= tok . offset + # tok . text then
context . prefix = tok . text : sub ( 1 , offset - tok . offset )
index = index - 1
tok = tokens [ index ]
end
if not tok then
return context
end




if tok . kind == ":" and tok . typeColon then
context . typePosition = true
return context
end
if tok . kind ~= "." and tok . kind ~= ":" then
return context
end
context . method = tok . kind == ":"
context . path = { }
index = index - 1
while tokens [ index ] and tokens [ index ] . kind == "name" do
table . insert ( context . path , 1 , tokens [ index ] . text )
index = index - 1
if tokens [ index ] and tokens [ index ] . kind == "." then
index = index - 1
else
break
end
end
if # context . path == 0 then
context . path = nil
context . method = nil
end

return context
end




function complete . membersOf ( t , fromModule )
local members = { }
if type ( t ) ~= "table" then
return members
end
if ( t ) . tag == "projection" then




local generics = require ( "nupp.compiler.generics" )
local associated = require ( "nupp.compiler.associated" )
local subject = t
local reduced = generics . normalize ( subject ) . type
if reduced ~= subject then
return complete . membersOf ( reduced , fromModule )
end
local projection = t
local found = associated . lookup ( projection . of , projection . name )
local effective = found . bound
if not effective then
return members
end
for name , entry in pairs ( complete . membersOf ( effective , fromModule ) ) do
members [ name ] = { type = generics . specializeSelf ( effective , entry . type , subject ) , kind = entry . kind }
end

return members
end
if ( t ) . tag == "intersection" then
for _ , part in ipairs ( ( t ) . members ) do
for name , entry in pairs ( complete . membersOf ( part , fromModule ) ) do
local prior = members [ name ]
if prior then
local combined = T . intersection ( { prior . type , entry . type } )
local callable = combined . tag == "func"
if combined . tag == "intersection" then
callable = true
for _ , candidate in ipairs ( combined . members ) do
if candidate . tag ~= "func" then
callable = false ;
break
end
end
end
members [
name
] = {
type = combined ,
kind = callable and "function" or "property" ,
definition = prior . definition or entry . definition ,
}
else
members [ name ] = entry
end
end
end
return members
end
if ( t ) . tag == "metatable" or ( t ) . tag == "typeobject" then
local owner = ( t ) . of
if owner . tag == "nominal" then
local nominal = owner
for name , member in pairs ( nominal . staticByname or { } ) do
members [
name
] = {
type = member ,
kind = type ( member ) == "table" and member . tag == "func" and "function" or "property" ,
definition = nominal . staticFieldDefs and nominal . staticFieldDefs [ name ] or nil ,
}
end
for name , member in pairs ( nominal . byname or { } ) do
if not members [
name
] and not (
nominal . privateFields and nominal . privateFields [ name ] and nominal . moduleName ~= fromModule
) then
members [
name
] = {
type = member ,
kind = type ( member ) == "table" and member . tag == "func" and "function" or "property" ,
definition = nominal . fieldDefs and nominal . fieldDefs [ name ] or nil ,
}
end
end
for name , nested in pairs ( nominal . nestedTypes or { } ) do
members [ name ] = { type = nested , kind = "type" }
end
end
return members
end


for name , member in pairs ( ( t ) . byname or { } ) do
local nominal = t
if not ( nominal . privateFields and nominal . privateFields [ name ] and nominal . moduleName ~= fromModule ) then
members [
name
] = {
type = member ,
kind = type ( member ) == "table" and member . tag == "func" and "function" or "property" ,
definition = nominal . fieldDefs and nominal . fieldDefs [ name ] or nil ,
}
end
end
for name , nested in pairs ( ( t ) . nestedTypes or { } ) do
members [ name ] = { type = nested , kind = "type" }
end

return members
end












function complete . associatedNamesOf ( t )
local names = { }
if type ( t ) ~= "table" then
return names
end
local associated = require ( "nupp.compiler.associated" )
local tag = ( t ) . tag
if tag == "union" then
local first = nil
for _ , member in ipairs ( ( t ) . members ) do
local arm = complete . associatedNamesOf ( member )
if not first then
first = arm
else
for name in pairs ( first ) do
if not arm [ name ] then
first [ name ] = nil
end
end
end
end

return first or names
elseif tag == "intersection" then
for _ , member in ipairs ( ( t ) . members ) do
for name , sites in pairs ( complete . associatedNamesOf ( member ) ) do
local into = names [ name ] or { }
local seen = { }
for _ , site in ipairs ( into ) do
seen [ site ] = true
end
for _ , site in ipairs ( sites ) do
if not seen [ site ] then
seen [ site ] = true
into [ # into + 1 ] = site
end
end
names [ name ] = into
end
end

return names
elseif tag == "typevar" then
local bound = ( t ) . bound
if bound then
return complete . associatedNamesOf ( bound )
end

return names
end
local head = t
for _ , name in ipairs ( associated . requirementNames ( head ) ) do
local found = associated . lookup ( head , name )
local sites = { }
for _ , reached in ipairs ( found . requirements ) do
sites [ # sites + 1 ] = reached . requirement
end
names [ name ] = sites
end

return names
end

function complete . signatureAt ( result , offset )
local best , bestSize
tree . walkNodes ( result . root , function ( node )
local call = node
if (
node . kind == "call" or node . kind == "safeCall" or node . kind == "methodCall"
) and ( ( call . signatureType and call . signatureType . tag == "func" ) or call . overloadCandidates ) and call . args then
local first , last = tree . nodeBounds ( call . args )
if first and offset >= first and offset <= last then


local size = ( last ) - first
if not bestSize or size < bestSize then
best , bestSize = call , size
end
end
end
end )

return best
end

complete . completionKinds = {
method = 2 ,
[ "function" ] = 3 ,
variable = 6 ,
parameter = 6 ,
property = 10 ,
module = 9 ,
keyword = 14 ,
type = 25 ,
struct = 22 ,
interface = 8 ,
typeParameter = 25 ,
}

complete . completionWords = {
"and" ,
"as" ,
"break" ,
"cdef" ,
"const" ,
"constructor" ,
"continue" ,
"do" ,
"else" ,
"elseif" ,
"end" ,
"false" ,
"for" ,
"function" ,
"global" ,
"goto" ,
"if" ,
"in" ,
"interface" ,
"is" ,
"local" ,
"satisfies" ,
"new" ,
"nil" ,
"not" ,
"or" ,
"affine" ,
"borrowed" ,
"borrows" ,
"exclusive" ,
"out" ,
"takes" ,
"pinned" ,
"releases" ,
"retains" ,
"unsafe" ,
"with" ,
"where" ,
"metamethod" ,
"record" ,
"repeat" ,
"return" ,
"struct" ,
"then" ,
"true" ,
"type" ,
"until" ,
"while" ,
}



local TYPE_KINDS = { type = true , struct = true , interface = true , typeParameter = true , }




function complete . requirePrefix ( source , offset )
local before = source : sub ( 1 , math . max ( 0 , offset - 1 ) )
local line = before : match ( "([^\n]*)$" ) or ""
local at , _ , prefix = line : match ( "()%f[%a]require%s*%(%s*([\"'])([^\"']*)$" )
if not at then
return nil
end

return prefix
end




function complete . install ( s , nav )
local documentationFor , resolveReceiver = nav . documentationFor , nav . resolveReceiver
local completionContext , membersOf = complete . completionContext , complete . membersOf
local completionKinds , completionWords = complete . completionKinds , complete . completionWords
local functionSignature = tree . functionSignature
local moduleMemberDeclarations = tree . moduleMemberDeclarations
local TYPE_WORDS = semantic . TYPE_WORDS




local function moduleCompletions ( moduleName , add )
local index = s . inc . projectIndex ( )
for _ , entries in pairs ( index . byName or { } ) do
for _ , entry in ipairs ( entries ) do
if entry . moduleName == moduleName and entry . visibility == "module" then
add ( entry . name , entry . kind == "record" and "type" or entry . kind , entry . type , entry . definition , 1 )
end
end
end
local path = s . inc . modulePath ( moduleName )
local checked = path and s . inc . checkFile ( path )
local result = checked and checked . result
if not result then
return
end
for _ , member in ipairs ( moduleMemberDeclarations ( result , moduleName ) ) do
local definition = member . token . definition or {
filename = path ,
token = member . token ,
name = member . name ,
kind = "function" ,
signature = functionSignature ( member . stat ) ,
}
add ( member . name , "function" , nil , definition , 1 )
end
end

local function completionItems ( doc , offset )
local items = wire . array ( { } )
local seen = { }
local context = ( completionContext ( doc . result , offset ) or { } )
local comptimeNode , comptimeFrom , comptimeTo = tree . comptimeAt ( doc . result , offset )
local inComptime = comptimeNode ~= nil
and comptimeFrom ~= nil
and comptimeTo ~= nil
and offset >= comptimeFrom
and offset <= comptimeTo
local comptimeBindings = { }
local scopeFrom = comptimeFrom or 1
local scopeTo = comptimeTo or 0
local function inComptimeScope ( def )
local at = def . token and def . token . offset
return def . comptimeFunction == true or at ~= nil and at >= scopeFrom and at <= scopeTo
end

if inComptime then
for _ , def in ipairs ( doc . result . symbols or { } ) do
if inComptimeScope ( def ) then
comptimeBindings [ def . name ] = true
if def . qualifiedName then
comptimeBindings [ def . qualifiedName ] = true
end
end
end
end
local function callableSnippet ( label , kind , t )
local ft = t
if type ( ft ) == "table" then
ft = T . unwrapOwnership ( ft )
end
if type ( ft ) == "table" and ft . tag == "intersection" then
for _ , candidate in ipairs ( ft . members ) do
if candidate . tag == "func" then
ft = candidate
break
end
end
end
local arguments = { }
if type ( ft ) == "table" and ft . tag == "func" then
for index in ipairs ( ft . params or { } ) do
local name = ft . paramNames and ft . paramNames [ index ] or ""
if not ( kind == "method" and index == 1 and name == "self" ) then
if name == "" then
name = "arg" .. tostring ( index )
end
arguments [ # arguments + 1 ] = "${" .. tostring ( # arguments + 1 ) .. ":" .. name .. "}"
end
end
if ft . vararg then
arguments [ # arguments + 1 ] = "${" .. tostring ( # arguments + 1 ) .. ":...}"
end
end

return label .. "(" .. table . concat ( arguments , ", " ) .. ")$0"
end

local function add ( label , kind , t , def , priority )
if not label or seen [ label ] then
return
end


if context . typePosition and not TYPE_KINDS [ kind or "variable" ] then
return
end
seen [ label ] = true
local item = {
label = label ,
kind = completionKinds [ kind ] or completionKinds . variable ,
sortText = tostring ( priority or 5 ) .. label ,
}
if t then
item . detail = T . tostring ( t )
end
if def and def . deprecated then
item . tags = wire . array ( { 1 } )
end
local docs = documentationFor ( def )
if def and def . generatedBy then
local provenance = (
"Generated by `@derive(%s)` for `%s`."
) : format ( def . generatedBy , def . generatedOwner or "<anonymous>" )
if def . generatedInterface then
provenance = provenance .. " Implements `" .. def . generatedInterface .. "`."
end
if def . generatedHelper then
provenance = provenance .. " Forwards to `" .. def . generatedHelper .. "`."
end
docs = docs and docs .. "\n\n" .. provenance or provenance
end
if docs then
item . documentation = docs
end
if kind == "function" or kind == "method" then
item . insertText = callableSnippet ( label , kind , t )
item . insertTextFormat = 2
end
items [ # items + 1 ] = item
end

local requirePrefix = complete . requirePrefix ( doc . text , offset )
if requirePrefix then
for name in pairs ( s . inc . projectIndex ( ) . modules or { } ) do
if name : sub ( 1 , # requirePrefix ) == requirePrefix then
add ( name , "module" , nil , nil , 1 )
end
end
table . sort ( items , function ( a , b )
return a . label < b . label
end )
return items
end




if context . path then
if inComptime and not COMPTIME_GLOBALS [ context . path [ 1 ] ] and not comptimeBindings [ context . path [ 1 ] ] then
return items
end
local t , moduleName = resolveReceiver ( doc . checked , context . path )
if inComptime and not t and not moduleName then
local global = s . inc . env . globals and s . inc . env . globals [ context . path [ 1 ] ]
t = global and global . t or nil
for index = 2 , # context . path do
local member = membersOf ( t , doc . result . moduleName ) [ context . path [ index ] ]
t = member and member . type or nil
if not t then
break
end
end
end
if moduleName then
moduleCompletions ( moduleName , add )
else
for name , member in pairs ( membersOf ( t , doc . result . moduleName ) ) do

if not context . method or member . kind == "function" then
add ( name , context . method and "method" or member . kind , member . type , member . definition , 1 )
end
end
end
table . sort ( items , function ( a , b )
return a . label < b . label
end )
return items
end

local definitions = { }
for _ , def in ipairs ( doc . result . symbols or { } ) do
local inScope = not def . scopeFrom or not def . scopeTo or offset >= def . scopeFrom and offset <= def . scopeTo
if def . lexical and inScope and (
not inComptime or inComptimeScope ( def )
) and ( not def . token or def . token . offset <= offset ) then
definitions [ # definitions + 1 ] = def
end
end
table . sort ( definitions , function ( a , b )
if ( a . scopeDepth or 0 ) ~= ( b . scopeDepth or 0 ) then
return ( a . scopeDepth or 0 ) > ( b . scopeDepth or 0 )
end

return ( a . token and a . token . offset or 0 ) > ( b . token and b . token . offset or 0 )
end )
for _ , def in ipairs ( definitions ) do

add ( def . qualifiedName or def . name , def . kind , def . type , def , 1 )
end
for name , entry in pairs ( s . inc . env . globals or { } ) do
if not inComptime or COMPTIME_GLOBALS [ name ] then
add ( name , entry . definition and entry . definition . kind or "variable" , entry . t , entry . definition , 2 )
end
end
for name , t in pairs ( s . inc . env . globalTypes or { } ) do
add ( name , "type" , t , s . inc . env . globalTypeDefs and s . inc . env . globalTypeDefs [ name ] , 2 )
end
if not inComptime and s . inc . env . ensureProjectIndex then



local index = s . inc . env . ensureProjectIndex ( s . inc . env )
for name , entries in pairs ( index . byName or { } ) do
local entry = entries [ 1 ]
if # entries == 1 and entry . visibility == "global" then
add (
name ,
entry . kind == "struct" and "struct" or entry . kind == "interface" and "interface" or "type" ,
entry . type ,
entry . definition ,
2
)
end
end
end
for name , t in pairs ( T . builtins ) do
add ( name , "type" , t , nil , 3 )
end
for _ , word in ipairs ( completionWords ) do


local kind = TYPE_WORDS [ word ] and "type" or "keyword"
add ( word , kind , nil , nil , word == "cdef" and 3 or 4 )
end
table . sort ( items , function ( a , b )
return a . sortText < b . sortText or ( a . sortText == b . sortText and a . label < b . label )
end )

return items
end

return { moduleCompletions = moduleCompletions , completionItems = completionItems }
end

return complete
