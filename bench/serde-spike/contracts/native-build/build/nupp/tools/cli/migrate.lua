_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.migrate\0runtime\0001") };



local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "migrate" )
local cliModule = require ( "nupp.cli" )
local report = require ( "nupp.tools.cli.report" )

local REPORT_SCHEMA = {
type = "object" ,
properties = {
ok = report . OK ,
dryRun = { type = "boolean" } ,
migrations = {
type = "array" ,
items = {
type = "object" ,
properties = {
source = { type = "string" } ,
destination = { type = "string" } ,
dialect = { type = "string" } ,
text = { type = "string" } ,
edits = { type = "array" , items = { type = "object" } } ,
warnings = { type = "array" , items = { type = "object" } } ,
written = { type = "boolean" } ,
} ,
required = { "source" , "destination" , "dialect" , "edits" , "warnings" , "written" } ,
} ,
} ,
diagnostics = report . DIAGNOSTICS ,
} ,
required = { "ok" , "dryRun" , "migrations" , "diagnostics" } ,
}

local function publicPlan ( plan , written , includeText ) 
return {
source = plan . source ,
destination = plan . destination ,
dialect = plan . dialect ,
text = includeText and plan . text or nil ,
edits = plan . edits ,
warnings = plan . warnings ,
written = written ,
}
end

local function run ( options ) 
local positional = options . files
local paths = positional
if # paths == 0 then
return usageError ( "at least one source file is required" )
end
local asJson = options . format == "json"
local asking = options . dryRun and true or false
local dialect = options . dialect or "auto"
local fs = require ( "nupp.compiler.fs" )
local planner = require ( "nupp.tools.migrate" )
local plans = { }


local errors = { }
local failures = { }

local function failed ( line , diagnostic ) 
errors [ # errors + 1 ] = line
failures [ # failures + 1 ] = diagnostic
end

local function fileFailed ( path , err , help ) 
failed ( path .. ": " .. tostring ( err ) , report . fileDiagnostic ( path , tostring ( err ) , help ) )
end

for _ , path in ipairs ( paths ) do
local source , readErr = fs . readFile ( path )
if not source then
fileFailed ( path , readErr , "check that the path exists and is readable" )
else
local plan , planErr , planDiagnostic = planner . plan ( source , path , dialect )
if not plan then
failed ( path .. ": " .. tostring ( planErr ) , planDiagnostic )
elseif plan . destination ~= plan . source and fs . exists ( plan . destination ) then
failed (
plan . destination .. " already exists" ,
report . fileDiagnostic (
plan . destination ,
plan . destination .. " already exists" ,
"move it aside; a migration never replaces a file"
)
)
else
plans [ # plans + 1 ] = plan
end
end
end

local public = { }
local completed = { }
if # errors == 0 and not asking then
local parser = require ( "nupp.compiler.syntax.parser" )
local check = require ( "nupp.compiler.check" )
local diagnostics = require ( "nupp.compiler.diagnostics" )
local env = require ( "nupp.compiler.project.env" ) . new ( "." )




local function attempt ( plan ) 
local inplace = plan . destination == plan . source
if not inplace then
local wrote , writeErr = fs . writeFile ( plan . destination , plan . text )
if not wrote then
fileFailed ( plan . destination , writeErr , "check that the destination is writable" )
public [ # public + 1 ] = ( { source = plan . source , destination = plan . destination , dialect = plan . dialect , text = asJson and plan . text or nil , edits = plan . edits , warnings = plan . warnings , written = false , } )
return false
end
end
local result = parser . parse ( plan . text , plan . destination )
local checked = # result . errors == 0 and check . check ( result , plan . destination , env )
or result . errors
local fatal = nil
for _ , diagnostic in ipairs ( checked ) do
if diagnostics . isFatal ( diagnostic ) then
fatal = diagnostic
do break end
end
end
if fatal then
failed ( plan . destination .. ": " .. fatal . code .. ": " .. fatal . msg , fatal )
public [ # public + 1 ] = publicPlan ( plan , not inplace , asJson )
return false
end
if inplace then
local wrote , writeErr = fs . writeFile ( plan . destination , plan . text )
if not wrote then
fileFailed ( plan . destination , writeErr , "check that the destination is writable" )
public [ # public + 1 ] = ( { source = plan . source , destination = plan . destination , dialect = plan . dialect , text = asJson and plan . text or nil , edits = plan . edits , warnings = plan . warnings , written = false , } )
return false
end
else
local removed , removeErr = os . remove ( plan . source )
if not removed then
fileFailed ( plan . source , removeErr , "remove the source by hand; the migrated file is in place" )
public [ # public + 1 ] = ( { source = plan . source , destination = plan . destination , dialect = plan . dialect , text = asJson and plan . text or nil , edits = plan . edits , warnings = plan . warnings , written = true , } )
return false
end
end
public [ # public + 1 ] = ( { source = plan . source , destination = plan . destination , dialect = plan . dialect , text = asJson and plan . text or nil , edits = plan . edits , warnings = plan . warnings , written = true , } )
completed [ plan ] = true

return true
end

local stopped = false
for _ , plan in ipairs ( plans ) do
if stopped then
public [ # public + 1 ] = ( { source = plan . source , destination = plan . destination , dialect = plan . dialect , text = asJson and plan . text or nil , edits = plan . edits , warnings = plan . warnings , written = false , } )
else
stopped = not attempt ( plan )
end
end
else
for _ , plan in ipairs ( plans ) do
public [ # public + 1 ] = ( { source = plan . source , destination = plan . destination , dialect = plan . dialect , text = asJson and plan . text or nil , edits = plan . edits , warnings = plan . warnings , written = false , } )
end
end

if asJson then
report . write ( {
ok = # errors == 0 ,
dryRun = asking ,
migrations = public ,
diagnostics = report . diagnosticValues ( failures ) ,
} )
else
for _ , plan in ipairs ( plans ) do


if asking or completed [ plan ] then
io . write ( plan . source .. " -> " .. plan . destination .. ( asking and " (planned)\n" or "\n" ) )
for _ , item in ipairs ( plan . warnings ) do
io . stderr : write (
("%s:%d:%d: warning: %s: %s\n") : format ( plan . source , item . line , item . col , item . code , item . msg )
)
end
end
end
for _ , message in ipairs ( errors ) do
io . stderr : write ( "nupp: " .. message .. "\n" )
end
end

return # errors == 0 and 0 or 1
end













local Migrate = {} Migrate.__index = Migrate


















function Migrate:run() 
return run ( self )
end ;Migrate.__nuppInit1=function(__nuppT8, a1, a2, a3, a4, a5) if a1 == nil then __nuppT8.dryRun = false else __nuppT8.dryRun = a1 end if a2 == nil then __nuppT8.dialect = "auto" else __nuppT8.dialect = a2 end if a3 == nil then __nuppT8.format = "text" else __nuppT8.format = a3 end if a4 == nil then __nuppT8.schema = false else __nuppT8.schema = a4 end __nuppT8.files = a5 return __nuppT8 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Migrates annotated Lua or retired serialization APIs.\n\nAnnotated Lua moves to a checked `.nupp` destination. Serialization\nmigrations update `.nupp` files only after the replacement type-checks.\n\nExamples:\n\n    nupp migrate --dry-run src/legacy.lua\n    nupp migrate src/legacy.lua\n    nupp migrate --dialect luacats src/one.lua src/two.lua",["group"]=false,["hidden"]=false,["name"]="migrate",["summary"]="Migrates annotated Lua or retired serialization APIs."},["fieldCount"]=5,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--dry-run",["documentation"]="Print the migration plan without changing files.",["field"]="dryRun",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"dry-run"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"auto","emmy","luacats","luadoc","serde"},["constants"]={},["conversion"]="choice",["destination"]="string",["display"]="--dialect",["documentation"]="Select the source migration dialect.",["field"]="dialect",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"dialect"},["required"]=false,["role"]="option",["value"]="DIALECT"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Files to migrate.",["field"]="files",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=true,["role"]="positional",["value"]="FILE"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="FILE",["documentation"]="Files to migrate.",["field"]="files",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=true,["role"]="positional",["value"]="FILE"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="e0c1b2869246dc2aa93110c8a22f3a8e758d935a8306db364b7a895a88686ac5",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.migrate:Migrate:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="migrate"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Migrates annotated Lua or retired serialization APIs."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Migrate?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Migrate",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.migrate:Migrate:1",Migrate,__nuppDerived) ;Migrate["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Migrate["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("migrate")end ;Migrate["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Migrates annotated Lua or retired serialization APIs.")end ;Migrate["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Migrate,__nuppT1[1],{ })


function Migrate . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Migrate } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.migrate"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.migrate"]=__nuppExports;return __nuppExports