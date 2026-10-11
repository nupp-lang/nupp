_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.migrate\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.tools.migrate\0runtime\0002") };




local parser = require ( "nupp.compiler.syntax.parser" )
local annotated = require ( "nupp.compiler.annotatedlua" )
local cst = require ( "nupp.compiler.syntax.cst" )

local migrate = { }

migrate.Edit = {} migrate.Edit.__index = migrate.Edit ;_G.nupp.__reflect.link(migrate.Edit,__nuppT1[1],{ })





migrate.Plan = {} migrate.Plan.__index = migrate.Plan ;_G.nupp.__reflect.link(migrate.Plan,__nuppT1[2],{ __nuppT1[1] , _G.nupp.__reflect.reference("nupp.compiler.annotatedlua\0runtime\0001","nupp.compiler.annotatedlua") })








local function typeText ( node ) 
return ( cst . textOf ( node ) : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) )
end

local function addEdit ( edits , offset , text ) 
edits [ # edits + 1 ] = _G.setmetatable({ offset =  offset ,  length =  0 ,  newText =  text }, migrate.Edit)
end

local function bodyClose ( body ) 
for _ , child in ipairs ( body ) do
if cst . isToken ( child ) and child . kind == ")" then
return child
end
end

return nil
end

local function collectBody ( body , edits ) 
for _ , writtenParam in ipairs ( body . params or { } ) do
local param = writtenParam
if param . type and param . type . foreignAnnotation then
local anchor = param . name or cst . firstToken ( param )
if anchor then
addEdit ( edits , anchor . offset + # anchor . text , ": " .. typeText ( param . type ) )
end
end
end
if body . generics and body . generics . foreignAnnotation then
local open = cst . firstToken ( body )
if open then
addEdit ( edits , open . offset , typeText ( body . generics ) )
end
end
if body . returnPack and body . returnPack . foreignAnnotation then
local close = bodyClose ( body )
if close then
local pieces = { }
for _ , ret in ipairs ( body . rets or { } ) do
pieces [ # pieces + 1 ] = ( ( cst . textOf ( ret ) : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) ) )
end
addEdit ( edits , math . floor ( close . offset + # close . text ) , ": " .. table . concat ( pieces , ", " ) )
end
end
end

local function collectNode ( node , edits ) 
if type ( node ) ~= "table" or cst . isToken ( node ) then
return
end
if node . kind == "localStmt" then
for index , name in ipairs ( node . names or { } ) do
local t = node . types and node . types [ index ]
if t and t . foreignAnnotation then
addEdit ( edits , math . floor ( name . offset + # name . text ) , ": " .. ( ( cst . textOf ( t ) : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) ) ) )
end
end
end
local body = nil
if node . kind == "localFuncStmt" or node . kind == "funcStmt" then
body = node . body
elseif node . kind == "funcExpr" then
body = node . body
end
if body then
collectBody ( body , edits )
end
for _ , child in ipairs ( node ) do
collectNode ( child , edits )
end
end

local function collectSemantic ( node , edits ) 
if type ( node ) ~= "table" or cst . isToken ( node ) then
return
end
if node . kind == "block" then
for _ , stat in ipairs ( node . stats or { } ) do
if stat . kind == "assignStmt" and stat . foreignAnnotation and stat . foreignInsertOffset then
addEdit ( edits , stat . foreignInsertOffset , "\n" .. cst . textOf ( stat ) : gsub ( "^%s+" , "" ) )
end
end
end
for _ , child in ipairs ( node ) do
collectSemantic ( child , edits )
end
end

local function apply ( source , edits ) 
table . sort ( edits , function ( a , b ) 
if a . offset == b . offset then
if a . length ~= b . length then
return a . length > b . length
end
return a . newText > b . newText
end

return a . offset > b . offset
end )
for _ , edit in ipairs ( edits ) do
source = source : sub ( 1 , edit . offset - 1 ) .. edit . newText .. source : sub ( edit . offset + edit . length )
end

return source
end



local function serdePlan ( source , path ) 
local parsed = parser . parse ( source , path )
if # parsed . errors > 0 then
return nil , parsed . errors [ 1 ] . msg , parsed . errors [ 1 ]
end
local env = require ( "nupp.compiler.project.env" ) . new ( "." , { cache = false } )
require ( "nupp.compiler.check" ) . check ( parsed , path , env , { legacySerializationMigration = true } )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local edits = { }
local problem = nil
local used = { }
for _ , token in ipairs ( parsed . tokens ) do
used [ token . text ] = true
end

local function fresh ( base ) 
local name , index = base , 1
while used [ name ] do
index += 1
name = base .. tostring ( index )
end
used [ name ] = true

return name
end

local serdeName , jsonName , decodeName = fresh ( "serde" ) , fresh ( "serdeJSON" ) , fresh ( "decodeJSON" )
local needsSerde , needsJSON , needsDecode = false , false , false

local function refuse ( node , message ) 
local token = cst . firstToken ( node )
problem = problem
or {
filename = path ,
code = "NUPP0003" ,
msg = message ,
line = token and token . line ,
col = token and token . col ,
offset = token and token . offset ,
length = token and # token . text
}
end

local function replace ( node , text ) 
local first , last = cst . firstToken ( node ) , cst . lastToken ( node )
if first and last then
edits [
# edits + 1
] = _G.setmetatable({ offset =
first . offset ,  length =
last . offset + # last . text - first . offset ,  newText =
text }, migrate.Edit)

end
end

local editedAnnotations = { }

local function annotationEdit ( annotation , replacement ) 
if editedAnnotations [ annotation ] then
return
end
editedAnnotations [ annotation ] = true
local first = assert ( cst . firstToken ( annotation ) )
local last = annotation . close or annotation . name
edits [
# edits + 1
] = _G.setmetatable({ offset =
first . offset ,  length =
math . floor ( last . offset + # last . text - first . offset ) ,  newText =
replacement }, migrate.Edit)

end

local seen = { }
local nodes = { }

local function visit ( node ) 
if type ( node ) ~= "table" or cst . isToken ( node ) or seen [ node ] then
return
end
seen [ node ] = true
nodes [ # nodes + 1 ] = node
for _ , child in ipairs ( node ) do
visit ( child )
end
end

visit ( parsed . root )
local records = { }

local function options ( annotations ) 
local out = { }
for _ , annotation in ipairs ( annotations or { } ) do
if annotation . name and annotation . name . text == "json" then
annotationEdit ( annotation , "" )
for _ , argument in ipairs ( annotation . annotationArgs or { } ) do
local name , value = argument . name and argument . name . text , argument . expr
if name == nil or value == nil or value . token == nil then
refuse ( annotation , "JSON migration requires literal annotation options" )
elseif value . kind == "string" then
out [ name ] = lexer . stringValue ( value . token . text )
elseif value . token . text == "true" or value . token . text == "false" then
out [ name ] = value . token . text == "true"
else
refuse ( argument , "JSON migration requires literal annotation options" )
end
end
end
end

return out
end

for _ , node in ipairs ( nodes ) do
if node . kind == "recordDecl" then
local legacy , json = false , false
for _ , annotation in ipairs ( node . deriveApplications or { } ) do
local retained = { }
local changed = false
for _ , argument in ipairs ( annotation . annotationArgs or { } ) do
if argument . deriveProviderModule == "nupp.derive"
and ( argument . deriveProviderMember == "JSON" or argument . deriveProviderMember == "Serde" )
then
legacy , changed = true , true
json = json or argument . deriveProviderMember == "JSON"
else
retained [ # retained + 1 ] = ( ( cst . textOf ( argument ) : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) ) )
end
end
if changed then
annotationEdit (
annotation ,
# retained == 0 and "" or "@derive(" .. table . concat ( retained , ", " ) .. ")"
)
end
end
if legacy then
if node . generics ~= nil or # ( node . qualifiers or { } ) > 0 or node . visibility == "nested" then
refuse ( node , "migrate this generic or nested declaration with an explicit binding factory" )
end
local mapping = { node = node , name = node . name . text , json = json }
local recordOptions = options ( node . annotations )

for _ , wrapper in ipairs ( nodes ) do
if wrapper . kind == "pragmaStmt" and wrapper . name and wrapper . name . text == "json" then
local target = wrapper . stat
while target and target . kind == "pragmaStmt" do
target = target . stat
end
if target == node then
local extra = options ( { wrapper } )
for key , value in pairs ( extra ) do
recordOptions [ key ] = value
end
end
end
end
local fields = { }
local custom = recordOptions . unknown ~= nil
for _ , field in ipairs ( node . entries or { } ) do
if json
and field . name
and (
field . name . text == "writeJSON"
or field . name . text == "fromJSON"
or field . name . text == "fieldCodec"
)
then
refuse ( field , "resolve the handwritten member's conflict with the JSON derive before migrating" )
end
if field . kind == "fieldDecl" and field . name then
local fieldOptions = options ( field . annotations )
custom = custom or next ( fieldOptions ) ~= nil
if not fieldOptions . omit then
local arguments = { }
if fieldOptions . name ~= nil then
arguments [ # arguments + 1 ] = "name = " .. string . format ( "%q" , fieldOptions . name )
end
if fieldOptions . omitEmpty then
arguments [ # arguments + 1 ] = "omitEmpty = true"
end
fields [
# fields + 1
] = "[" .. string . format (
"%q" ,
field . name . text
) .. "] = new " .. serdeName .. ".FieldOptions(" .. table . concat ( arguments , ", " ) .. ")"
end
end
end
if custom then
mapping . binding = fresh ( node . name . text .. "JSON" )
local cached = fresh ( node . name . text .. "JSONBinding" )
local arguments = "fields = {" .. table . concat ( fields , ", " ) .. "}"
if recordOptions . unknown ~= nil then
arguments = arguments .. ", unknownMembers = " .. string . format ( "%q" , recordOptions . unknown )
end
local last = assert ( cst . lastToken ( node ) )
addEdit (
edits ,
last . offset + # last . text ,
"\nlocal "
.. cached
.. ": "
.. serdeName
.. ".Binding<"
.. mapping . name
.. ">?\nlocal function "
.. mapping . binding
.. "(): "
.. serdeName
.. ".Binding<"
.. mapping . name
.. ">\n    if "
.. cached
.. " == nil then\n        "
.. cached
.. " = "
.. serdeName
.. ".binding("
.. mapping . name
.. ", new "
.. serdeName
.. ".Options("
.. arguments
.. "))\n    end\n    return assert("
.. cached
.. ")\nend\n"
)
needsSerde = true
end
records [ node . resolvedType or node . hoistedType ] = mapping
end
end
end

local function nominal ( t ) 
if t and ( t . tag == "ctype" or t . tag == "typeobject" ) then
t = t . of
end
return t and ( t . origin or t )
end

local function nestedPolicy ( t , owner , visited ) 
t = nominal ( t )
if t == nil or visited [ t ] then
return false
end
visited [ t ] = true
if t ~= owner and records [ t ] and records [ t ] . binding then
return true
end
if t . tag == "nominal" or t . tag == "shape" then
for _ , child in pairs ( t . byname or { } ) do
if nestedPolicy ( child , owner , visited ) then
return true
end
end
elseif t . tag == "union" or t . tag == "intersection" then
for _ , child in ipairs ( t . members ) do
if nestedPolicy ( child , owner , visited ) then
return true
end
end
elseif t . tag == "tuple" then
for _ , child in ipairs ( t . elems ) do
if nestedPolicy ( child , owner , visited ) then
return true
end
end
elseif t . tag == "array" or t . tag == "const" then
return nestedPolicy ( t . elem , owner , visited )
elseif t . tag == "map" then
return nestedPolicy ( t . value , owner , visited )
end

return false
end

local function needsUnionAdapter ( t , visited ) 
t = nominal ( t )
if t == nil or visited [ t ] then
return false
end
visited [ t ] = true
if t . tag == "union" then
local count , literals = 0 , true
local family = nil
for _ , child in ipairs ( t . members ) do
if child . tag ~= "nil" then
count += 1
local base = child . tag == "literal" and child . base . tag or nil
if base == "integer" then
base = "number"
end
literals = literals and base ~= nil and ( family == nil or family == base )
family = base
if needsUnionAdapter ( child , visited ) then
return true
end
end
end
return count > 1 and not literals
elseif t . tag == "nominal" or t . tag == "shape" then
for _ , child in pairs ( t . byname or { } ) do
if needsUnionAdapter ( child , visited ) then
return true
end
end
elseif t . tag == "tuple" then
for _ , child in ipairs ( t . elems ) do
if needsUnionAdapter ( child , visited ) then
return true
end
end
elseif t . tag == "array" or t . tag == "const" then
return needsUnionAdapter ( t . elem , visited )
elseif t . tag == "map" then
return needsUnionAdapter ( t . value , visited )
end

return false
end

for _ , mapping in pairs ( records ) do
if needsUnionAdapter ( mapping . node . resolvedType or mapping . node . hoistedType , { } ) then
refuse ( mapping . node , "select an explicit union adapter before migrating this declaration" )
end
end

local function selected ( mapping , at ) 
needsSerde = true
local owner = nominal ( mapping . node . resolvedType or mapping . node . hoistedType )
if nestedPolicy ( owner , owner , { } ) then
refuse ( at , "select nested JSON policies explicitly with a binding adapter before migrating this call" )
end
if mapping . binding then
if assert ( cst . firstToken ( at ) ) . offset <= assert ( cst . lastToken ( mapping . node ) ) . offset then
refuse ( at , "move this serialization call after the declaration's explicit JSON mapping" )
end
return mapping . binding .. "()"
end

return serdeName .. ".binding(" .. mapping . name .. ")"
end

for _ , node in ipairs ( nodes ) do
local callee = node . kind == "call" and node . obj or nil
local identity = callee and callee . exactCallExport
if identity and identity . module == "nupp.serde" and identity . member == "of" then
replace ( callee , serdeName .. ".binding" )
needsSerde = true
elseif callee and callee . kind == "dotIndex" and callee . name . text == "fromJSON" then
local mapping = records [ nominal ( callee . obj . inferredType ) ]
if mapping and mapping . json then
local args = node . args and node . args . exprs or { }
if # args ~= 1 then
refuse ( node , "fromJSON migration expects one input expression" )
else
replace ( node , decodeName .. "(" .. selected ( mapping , node ) .. ", " .. typeText ( args [ 1 ] ) .. ")" )
needsJSON , needsDecode = true , true
end
end
elseif node . kind == "methodCall" and node . name . text == "writeJSON" then
local mapping = records [ nominal ( node . obj . inferredType ) ]
if mapping and mapping . json then
local args = node . args and node . args . exprs or { }
if # args ~= 1 then
refuse ( node , "writeJSON migration expects one writer expression" )
else
replace (
node ,
jsonName .. ".writeValue(" .. selected (
mapping ,
node
) .. ", " .. typeText ( node . obj ) .. ", " .. typeText ( args [ 1 ] ) .. ")"
)
needsJSON = true
end
end
end
end
if problem ~= nil then
return nil , problem . msg , problem
end
local imports = { }
if needsSerde then
imports [ # imports + 1 ] = "local " .. serdeName .. " = require(\"nupp.serde\")"
end
if needsJSON then
imports [ # imports + 1 ] = "local " .. jsonName .. " = require(\"nupp.serde.json\")"
end
if needsDecode then
imports [
# imports + 1
] = "local function "
.. decodeName
.. "<T>(binding: "
.. serdeName
.. ".Binding<T>, bytes: string): (T?, string?)\n"
.. "    local ok, result = pcall("
.. jsonName
.. ".decode, binding, bytes)\n    if not ok then return nil, tostring(result) end\n    return result as T, nil\nend"


end
if # imports > 0 then
local offset = source : match ( "^#![^\n]*\n" ) and ( assert ( source : find ( "\n" , 1 , true ) ) + 1 ) or 1
for _ , node in ipairs ( nodes ) do
if node . kind == "moduleStmt" then
local last = assert ( cst . lastToken ( node ) )
offset = last . offset + # last . text
do break end
end
end
addEdit ( edits , offset , "\n" .. table . concat ( imports , "\n" ) .. "\n" )
end


table . sort ( edits , function ( a , b ) 
if a . offset == b . offset then
return a . length < b . length
end
return a . offset < b . offset
end )
local finish = 0
for _ , edit in ipairs ( edits ) do
if edit . offset < finish then

return nil , "migrate nested serialization calls separately" , { filename = path , code = "NUPP0003" , msg = "migrate nested serialization calls separately" }
end
finish = edit . offset + edit . length
end

return _G.setmetatable({ source =
path ,  destination =
path ,  text =
apply ( source , edits ) ,  edits =
edits ,  warnings =
{ } ,  dialect =
"serde" }, migrate.Plan)
, nil
end








function migrate . plan ( source , path , dialect ) 
if path : match ( "%.nupp$" ) then
if dialect ~= nil and dialect ~= "auto" and dialect ~= "serde" then

return nil , "a Nupp source migration requires the serde dialect" , { filename = path , code = "NUPP0003" , msg = "a Nupp source migration requires the serde dialect" }
end
return serdePlan ( source , path )
end
if not path : match ( "%.lua$" ) then
local message = "unsupported migration source extension in " .. path
return nil , message , { filename = path , code = "NUPP0003" , msg = message }
end
dialect = dialect or "auto"
if dialect ~= "auto" and dialect ~= "luacats" and dialect ~= "emmy" and dialect ~= "luadoc" then
local message = "unsupported annotated Lua dialect " .. dialect
return nil , message , { filename = path , code = "NUPP0003" , msg = message }
end
local parsed = parser . parse ( source , path )
if # parsed . errors > 0 then
return nil , parsed . errors [ 1 ] . msg , parsed . errors [ 1 ]
end
local warnings = annotated . decorate ( parsed , path , dialect )
local edits = { }
local declarations = { }
local first = parsed . root . blocks and parsed . root . blocks [ 1 ]
for _ , stat in ipairs ( first and first . stats or { } ) do
if stat . foreignAnnotation and ( stat . kind == "typeAlias" or stat . kind == "recordDecl" ) then
declarations [ # declarations + 1 ] = cst . textOf ( stat ) : gsub ( "^%s+" , "" )
end
end
if # declarations > 0 then
local offset = source : match ( "^#![^\n]*\n" ) and ( assert ( source : find ( "\n" , 1 , true ) ) + 1 ) or 1
addEdit ( edits , offset , table . concat ( declarations , "" ) .. "\n" )
end
collectNode ( parsed . root , edits )
collectSemantic ( parsed . root , edits )
local destination = path : gsub ( "%.lua$" , ".g.nupp" )

return _G.setmetatable({ source =
path ,  destination =
destination ,  text =
apply ( source , edits ) ,  edits =
edits ,  warnings =
warnings ,  dialect =
dialect }, migrate.Plan)
, nil
end

local __nuppExportValue= migrate ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.migrate"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.migrate"]=__nuppExports;return __nuppExports