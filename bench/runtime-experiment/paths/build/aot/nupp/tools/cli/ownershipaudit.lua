_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.ownershipaudit\0runtime\0001") };



local cliModule = require ( "nupp.cli" )











local cliReport = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = cliReport . OK ,
diagnostics = cliReport . DIAGNOSTICS ,
foreign = { type = "array" , items = { type = "object" } } ,
unsafe = { type = "array" , items = { type = "object" } } ,
regions = { type = "array" , items = { type = "object" } } ,
} ,
required = { "ok" , "diagnostics" , "foreign" , "unsafe" } ,
}

local function pointerShaped ( t , T ) 
t = T . unwrapOwnership ( t )
if t . tag == "ptr" or t . tag == "carray" or t == T . cstring or t == T . voidptr then
return true
end
if t . tag == "union" then
for _ , member in ipairs ( t . members ) do
if member ~= T . nil_ and pointerShaped ( member , T ) then
return true
end
end
end

return false
end

local function sourceFiles ( paths , fs ) 
if # paths > 0 then
return paths
end
local found = { }
for _ , path in ipairs ( fs . listFiles ( "src" ) ) do
if path : match ( "%.nupp$" ) then
found [ # found + 1 ] = path
end
end

return found
end

local function run ( options ) 
local positional = options . files
local fs = require ( "nupp.compiler.fs" )
local parser = require ( "nupp.compiler.syntax.parser" )
local check = require ( "nupp.compiler.check" )
local env = require ( "nupp.compiler.project.env" ) . new ( "." )
local T = require ( "nupp.compiler.types" )
local cst = require ( "nupp.compiler.syntax.cst" )
local foreign = { }
local unsafeSites = { }
local regions = { }
local failed = false

local function firstToken ( node ) 
if not node then
return nil
end
if cst . isToken ( node ) then
return node
end
for _ , child in ipairs ( node ) do
local found = firstToken ( child )
if found then
return found
end
end

return nil
end

local function cleanupName ( cleanup ) 
if cleanup . kind == "function" then
return cleanup . name or cleanup . id
elseif cleanup . kind == "closure" then
return "generated closure terminal"
elseif cleanup . kind == "method" then
return ":" .. cleanup . name
elseif cleanup . kind == "field" then
return cleanup . field .. " -> " .. cleanupName ( cleanup . cleanup )
end

return cleanup . id or cleanup . kind
end

local markedOperands = { }

local function visit ( node , file , inUnsafe ) 
if not node or cst . isToken ( node ) then
return
end
local operand = node . expressionPermissionOperand
local previous = operand and markedOperands [ operand ]
if operand then
markedOperands [ operand ] = true
end
if node . kind == "funcbody" or node . kind == "shortfn" then
inUnsafe = false
elseif markedOperands [ node ] or ( node . expressionAnnotations and not operand ) then
inUnsafe = true
end
if options . regions and node . kind == "block" and node . automaticOwners then
local owners = { }
for _ , owner in ipairs ( node . automaticOwners ) do
if owner . lowerable then
local cleanups , cleanupIds = { } , { }
for _ , cleanup in ipairs ( owner . cleanups or { } ) do
cleanups [ # cleanups + 1 ] = cleanupName ( cleanup )
cleanupIds [ # cleanupIds + 1 ] = cleanup . id
end
owners [
# owners + 1
] = {
name = owner . name ,
line = owner . token and owner . token . line or 0 ,
column = owner . token and owner . token . col or 0 ,
capability = table . concat ( cleanupIds , "+" ) ,
cleanups = cleanups ,
optional = owner . optional == true ,
mayMove = owner . moved == true or owner . movedFields ~= nil ,
}
end
end
if # owners > 0 then
local activation , cleanup = { } , { }
for _ , owner in ipairs ( owners ) do
activation [ # activation + 1 ] = owner . name
end
for j = # owners , 1 , -1 do
cleanup [ # cleanup + 1 ] = owners [ j ] . name
end
regions [
# regions + 1
] = {
file = file ,
line = owners [ 1 ] . line ,
column = owners [ 1 ] . column ,
lowering = node . automaticDirect and "direct" or # owners > 1 and "fused" or "general" ,
protection = node . automaticDirect and "elided: empty live interval and non-raising cleanup"
or "raised exits and cleanup failures" ,
activationOrder = activation ,
cleanupOrder = cleanup ,
owners = owners ,
}
end
end
if node . kind == "cdefFunc" and node . signatureType then
local ft = node . physicalSignatureType or node . signatureType
local params , results = { } , { }
for j , param in ipairs ( ft . params or { } ) do
if pointerShaped ( param , T ) then
params [
# params + 1
] = {
index = j ,
name = ft . paramNames and ft . paramNames [ j ] ~= "" and ft . paramNames [ j ] or nil ,
type = T . tostring ( param ) ,
contract = ft . paramModes and ft . paramModes [ j ] or "plain" ,
}
end
end
for j , result in ipairs ( ft . rets or { } ) do
if pointerShaped ( result , T ) or result . tag == "affine" then
results [ # results + 1 ] = { index = j , type = T . tostring ( result ) }
end
end
if # params > 0 or # results > 0 or ft . vararg then
local entry = {
file = file ,
line = node . name and node . name . line or 0 ,
name = node . name and node . name . text or "<anonymous>" ,
parameters = params ,
results = results ,
variadic = ft . vararg == true ,
trusted = true ,
}
if node . countedAbi then
entry . countedBy = { }
for _ , mapping in ipairs ( node . countedAbi . mappings or { } ) do
entry . countedBy [
# entry . countedBy + 1
] = { access = mapping . kind , pointer = mapping . pointerName , count = mapping . countName , }
end
entry . zeroCount = "calls once; foreign implementation must not dereference"
end
foreign [ # foreign + 1 ] = entry
end
elseif node . kind == "fieldDecl" then
for _ , application in ipairs ( node . annotations or { } ) do
if application . name and application . name . text == "partition" then
local token = firstToken ( application )
unsafeSites [
# unsafeSites + 1
] = {
file = file ,
line = token and token . line or 0 ,
column = token and token . col or 0 ,
kind = "ownership contract: partitioned result fields" ,
}
end
end
elseif node . kind == "pragmaStmt" and node . name . text == "unsafe" then
local token = firstToken ( node )
unsafeSites [
# unsafeSites + 1
] = {
file = file ,
line = token and token . line or 0 ,
column = token and token . col or 0 ,
kind = "unsafe assertion region" ,
}
inUnsafe = true




elseif node . ownershipIntrinsic
and ( inUnsafe or node . ownershipIntrinsic == "adopt" or node . ownershipIntrinsic == "release" )
and node . ownershipIntrinsic ~= "borrow"
and node . ownershipIntrinsic ~= "drop"
then
local token = firstToken ( node )
unsafeSites [
# unsafeSites + 1
] = {
file = file ,
line = token and token . line or 0 ,
column = token and token . col or 0 ,
kind = "ownership assertion: " .. node . ownershipIntrinsic ,
}
elseif inUnsafe and node . unsafeOwnershipOperation then
local token = firstToken ( node )
unsafeSites [
# unsafeSites + 1
] = {
file = file ,
line = token and token . line or 0 ,
column = token and token . col or 0 ,
kind = node . unsafeOwnershipOperation ,
}
end
if node . expressionAnnotations
and node . ownershipIntrinsic ~= "adopt"
and node . ownershipIntrinsic ~= "release"
then
for _ , application in ipairs ( node . expressionAnnotations ) do
if application . name . text == "unsafe" then
local token = firstToken ( application )
unsafeSites [
# unsafeSites + 1
] = {
file = file ,
line = token and token . line or 0 ,
column = token and token . col or 0 ,
kind = "unsafe assertion expression" ,
}
end
end
end
for _ , child in ipairs ( node ) do
visit ( child , file , inUnsafe )
end
if operand then
markedOperands [ operand ] = previous
end
end

local diagnosticMod = require ( "nupp.compiler.diagnostics" )


local asJson = options . format == "json"
local collected = { }

local function say ( values ) 
if not asJson then
diagnosticMod . report ( values )
return
end
for _ , value in ipairs ( values ) do
collected [ # collected + 1 ] = value
end
end

for _ , file in ipairs ( sourceFiles ( positional , fs ) ) do
local source , readErr = fs . readFile ( file )
if source then
local result = parser . parse ( source , file )
if # result . errors == 0 then
local diags = check . check ( result , file , env , { strict = false } )
local errors = { }
for _ , diag in ipairs ( diags ) do
if diag . severity == "error" then
errors [ # errors + 1 ] = diag
failed = true
end
end
if # errors > 0 then
say ( errors )
end
visit ( result . root , file , false )
else
say ( result . errors )
failed = true
end
else
cliReport . fileFailure (
file ,
"cannot read " .. file .. ( readErr and ": " .. tostring ( readErr ) or "" ) ,
"check that the path exists and is readable" ,
asJson and collected or nil
)
failed = true
end
end
table . sort ( foreign , function ( a , b ) 
return a . file == b . file and a . line < b . line or a . file < b . file
end )
table . sort ( unsafeSites , function ( a , b ) 
return a . file == b . file and a . line < b . line or a . file < b . file
end )
table . sort ( regions , function ( a , b ) 
return a . file == b . file and ( a . line == b . line and a . column < b . column or a . line < b . line ) or a . file < b . file
end )
local regionOrdinals = { }
for _ , region in ipairs ( regions ) do
local capabilities = { }
for _ , owner in ipairs ( region . owners ) do
capabilities [ # capabilities + 1 ] = owner . capability
end
local base = "automatic:" .. table . concat ( capabilities , "|" )
regionOrdinals [ base ] = ( regionOrdinals [ base ] or 0 ) + 1
region . id = base .. "#" .. tostring ( regionOrdinals [ base ] )
end
local report

= { ok = not failed , diagnostics = cliReport . diagnosticValues ( collected ) , foreign = foreign , unsafe = unsafeSites , }
if options . regions then
report . regions = regions
end
if asJson then
cliReport . write ( report )
else
io . write ( "Foreign ownership contracts\n" )
for _ , entry in ipairs ( foreign ) do
io . write (
("  %s:%d  %s%s\n") : format ( entry . file , entry . line , entry . name , entry . variadic and "  [variadic]" or "" )
)
for _ , param in ipairs ( entry . parameters ) do
io . write (
("    parameter %d%s: %s  %s\n")

: format ( param . index , param . name and " " .. param . name or "" , param . type , param . contract )
)
end
for _ , result in ipairs ( entry . results ) do
io . write ( ("    result %d: %s\n") : format ( result . index , result . type ) )
end
for _ , mapping in ipairs ( entry . countedBy or { } ) do
io . write ( ("    counted %s: %s by %s\n") : format ( mapping . access , mapping . pointer , mapping . count ) )
end
if entry . zeroCount then
io . write ( "    zero count: " .. entry . zeroCount .. "\n" )
end
end
io . write ( "Unsafe assertion sites\n" )
for _ , entry in ipairs ( unsafeSites ) do
io . write ( ("  %s:%d:%d  %s\n") : format ( entry . file , entry . line , entry . column , entry . kind ) )
end
if options . regions then
io . write ( "Automatic cleanup regions\n" )
for _ , region in ipairs ( regions ) do
io . write (
("  %s:%d:%d  %s  [%s]\n")

: format ( region . file , region . line , region . column , region . id , region . lowering )
)
io . write ( "    activate: " .. table . concat ( region . activationOrder , ", " ) .. "\n" )
io . write ( "    cleanup: " .. table . concat ( region . cleanupOrder , ", " ) .. "\n" )
end
end
end

return failed and 1 or 0
end













local OwnershipAudit = {} OwnershipAudit.__index = OwnershipAudit














function OwnershipAudit:run() 
return run ( self )
end ;OwnershipAudit.__nuppInit1=function(__nuppT13, a1, a2, a3, a4) if a1 == nil then __nuppT13.regions = false else __nuppT13.regions = a1 end if a2 == nil then __nuppT13.format = "text" else __nuppT13.format = a2 end if a3 == nil then __nuppT13.schema = false else __nuppT13.schema = a3 end if a4 == nil then __nuppT13.files = {} else __nuppT13.files = a4 end return __nuppT13 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="List foreign pointer contracts and unsafe assertion sites.\n\nWith no files, scans Nupp sources under src. The report enumerates trusted\nC contracts and explicit unsafe regions.\n\nExamples:\n\n    nupp ownership-audit\n    nupp ownership-audit --regions src/native.nupp\n    nupp ownership-audit --json src/native.nupp",["group"]=false,["hidden"]=false,["name"]="ownership-audit",["summary"]="List foreign pointer contracts and unsafe assertion sites."},["fieldCount"]=4,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--regions",["documentation"]="Include automatic cleanup regions.",["field"]="regions",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"regions"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source files to inspect.",["field"]="files",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Source files to inspect.",["field"]="files",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="1a4a14e16efcf9a7f509c054a629f125056a81b1707e90070ff3fb9f97254a83",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.ownershipaudit:OwnershipAudit:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="ownership-audit"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="List foreign pointer contracts and unsafe assertion sites."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (OwnershipAudit?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="OwnershipAudit",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.ownershipaudit:OwnershipAudit:1",OwnershipAudit,__nuppDerived) ;OwnershipAudit["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;OwnershipAudit["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("ownership-audit")end ;OwnershipAudit["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("List foreign pointer contracts and unsafe assertion sites.")end ;OwnershipAudit["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(OwnershipAudit,__nuppT1[1],{ })


function OwnershipAudit . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = OwnershipAudit } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.ownershipaudit"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.ownershipaudit"]=__nuppExports;return __nuppExports