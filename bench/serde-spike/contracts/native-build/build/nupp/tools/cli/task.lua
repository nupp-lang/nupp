_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.task\0runtime\0001") };

















local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "task" )
local ansi = require ( "nupp.cli" )
local cliModule = require ( "nupp.cli" )

local report = require ( "nupp.tools.cli.report" )

local TASK_PROPERTIES

= {
name = { type = "string" } ,
[ "default" ] = { type = "boolean" } ,
description = { type = "string" } ,
kind = { type = "string" } ,
category = { type = "string" } ,
command = { type = "array" , items = { type = "string" } } ,
outDir = {
type = "string" ,
description = "Where the target writes, including the default a docs target takes from the generator rather than from the manifest."


} ,
buildTarget = { type = "string" } ,
cwd = { type = "string" , description = "Task working directory, relative to the project root." } ,
includePrivate = {
type = "boolean" ,
description = "Documentation: include unexported, internal and private declarations."
} ,
entries = { type = "array" , items = { type = "string" } } ,
sources = { type = "array" , items = { type = "string" } } ,
resources = { type = "array" , items = { type = "string" } } ,
dependencies = { type = "array" , items = { type = "string" } } ,
nativeFeatures = { type = "object" , additionalProperties = { type = "boolean" } } ,
layoutTarget = { type = "string" } ,
platforms = { type = "array" , items = { type = "string" } } ,
argv = { type = "array" , items = { type = "string" } } ,
}



local ONE_TASK = { ok = report . OK }
for key , value in pairs ( TASK_PROPERTIES ) do
ONE_TASK [ key ] = value
end

local REPORT_SCHEMA = {
description = "The task list, one task's effective configuration when a name was given, or why neither could be read." ,
oneOf = {
{
type = "object" ,
description = "Every task, when no name was given." ,
properties = {
ok = report . OK ,
[ "default" ] = { type = "string" , description = "The default build target." } ,
tasks = { type = "array" , items = { [ "$ref" ] = "#/definitions/task" } } ,
} ,
required = { "ok" , "tasks" } ,
} ,
{
type = "object" ,
description = "One task, when a name was given." ,
properties = ONE_TASK ,
required = { "ok" , "name" } ,
} ,
report . FAILURE ,
} ,
definitions = { task = { type = "object" , properties = TASK_PROPERTIES , required = { "name" } } } ,
}

local function writeItems ( out , style , label , items ) 
out [ # out + 1 ] = style . faint ( label .. ":" )
if # items == 0 then
out [ # out + 1 ] = "  (none)"
return
end
for _ , item in ipairs ( items ) do
out [ # out + 1 ] = "  - " .. item
end
end



local function writeTask ( out , style , task ) 
local function field ( label , value ) 
if value ~= nil then
out [ # out + 1 ] = style . faint ( label .. ":" ) .. " " .. tostring ( value )
end
end

out [ # out + 1 ] = style . faint ( "Name:" ) .. " " .. style . strong ( task . name )
field ( "Default" , task . default and "yes" or "no" )
field ( "Description" , task . description )
field ( "Kind" , task . kind )
field ( "Category" , task . category )
if task . command then
field ( "Command" , table . concat ( task . command , " " ) )
end
field ( "Output directory" , task . outDir )
field ( "Build target" , task . buildTarget )
field ( "Working directory" , task . cwd )
field ( "Layout target" , task . layoutTarget )
if task . platforms and # task . platforms > 0 then
writeItems ( out , style , "Platforms" , task . platforms )
end
field ( "Stage zero" , task . bootstrap )
field ( "Title" , task . title )
field ( "Format" , task . format )
if task . includePrivate ~= nil then
field ( "Include private" , tostring ( task . includePrivate ) )
end
if task . argv then
writeItems ( out , style , "Arguments" , task . argv )
end
if task . env then
local environment = { }
for name , value in pairs ( task . env ) do
environment [ # environment + 1 ] = name .. "=" .. value
end
table . sort ( environment )
writeItems ( out , style , "Environment" , environment )
end
if task . entries then
writeItems ( out , style , "Entries" , task . entries )
end
if task . sources and # task . sources > 0 then
writeItems ( out , style , "Sources" , task . sources )
end
if task . resources then
writeItems ( out , style , "Resources" , task . resources )
end
if task . dependencies then
writeItems ( out , style , "Dependencies" , task . dependencies )
end
if task . nativeFeatures then
local overrides = { }
for name , enabled in pairs ( task . nativeFeatures ) do
overrides [ # overrides + 1 ] = ( enabled and "+" or "-" ) .. name
end
table . sort ( overrides )
writeItems ( out , style , "Native feature overrides" , overrides )
end
end

local function list ( name , format ) 
local project = require ( "nupp.tools.build.project" )
local info , err , code = project . describeTasks ( "." , name )
if not info then
if format == "json" then
return report . failure ( REPORT_SCHEMA , {
report . runDiagnostic ( code or report . MANIFEST , tostring ( err ) , nil , "nupp.lua" )
} )
end
io . stderr : write ( tostring ( err ) .. "\n" )
return 1
end
if format == "json" then
local document = info
document . ok = true
io . write ( project . encode ( document ) .. "\n" )
return 0
end
local style = ansi . style ( io . stdout )
if name then
local out = { }
writeTask ( out , style , info )
if # out > 0 then
io . write ( table . concat ( out , "\n" ) , "\n" )
end

return 0
end


local rows = { }
local kindColors

= {
modules = style . cyan ,
bundle = style . blue ,
binary = style . yellow ,
component = style . white ,
docs = style . magenta ,
test = style . green ,
[ "self-host" ] = style . red ,
task = style . gray ,
}
for _ , task in ipairs ( info . tasks ) do
local name
if task . default then
name = ansi . annotatedCell ( task . name , " (default)" , style . strong )
else
name = ansi . paintedCell ( task . name , style . strong )
end
rows [
# rows + 1
] = {
name ,
ansi . paintedCell ( tostring ( task . kind or "" ) , kindColors [ task . kind or "" ] or style . faint ) ,
ansi . cell ( task . description or "" ) ,
}
end
ansi . writeTable (
io . stdout ,
{
columns = { { heading = "task" } , { heading = "kind" } , { heading = "description" } } ,
rows = rows ,
style = style ,
}
)

return 0
end















local Task = {} Task.__index = Task



















function Task:run() 
if self . list then
if # self . arguments > 0 then
return usageError ( "only one task name may be queried" )
end

return list ( self . name , self . format )
elseif self . format ~= nil then
return usageError ( "--format, --json, and --text require --list" )
elseif self . name == nil then
return usageError ( "a task name or --list is required" )
end

return require ( "nupp.tools.build.project" ) . runTask ( "." , self . name , self . arguments )
end ;Task.__nuppInit1=function(__nuppT7, a1, a2, a3, a4, a5) if a1 == nil then __nuppT7.list = false else __nuppT7.list = a1 end __nuppT7.format = a2 if a3 == nil then __nuppT7.schema = false else __nuppT7.schema = a3 end __nuppT7.name = a4 if a5 == nil then __nuppT7.arguments = {} else __nuppT7.arguments = a5 end return __nuppT7 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="List, inspect, or run project tasks from nupp.lua.\n\nWith `--list`, lists build targets plus configured actions, or inspects NAME.\nOtherwise runs `tasks.<name>` from nupp.lua: builds `tasks.<name>.build` first when\nit names one, then executes `tasks.<name>.argv` from `tasks.<name>.cwd`\n(the project root by default) with every trailing argument appended.\n\nExamples:\n\n    nupp task --list\n    nupp task --list app\n    nupp task serve --port 8080",["group"]=false,["hidden"]=false,["name"]="task",["summary"]="List, inspect, or run project tasks from nupp.lua."},["fieldCount"]=5,["fields"]={{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--list",["documentation"]="List project tasks, or inspect NAME.",["field"]="list",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"list","l"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"text","json"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the list representation.",["field"]="format",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"format","json","text"},["optional"]=true,["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of list output and exit.",["field"]="schema",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="NAME",["documentation"]="Configured task to run, or inspect with --list.",["field"]="name",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments appended to the configured command.",["field"]="arguments",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="NAME",["documentation"]="Configured task to run, or inspect with --list.",["field"]="name",["hidden"]=false,["index"]=4,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments appended to the configured command.",["field"]="arguments",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"}},["preserveUnknown"]=false,["remainder"]={["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="ARGUMENTS",["documentation"]="Arguments appended to the configured command.",["field"]="arguments",["hidden"]=false,["index"]=5,["long"]=true,["names"]={},["repeated"]=true,["required"]=false,["role"]="remainder",["value"]="ARG"},["stopAtFirstArgument"]=true}},["effects"]={},["fields"]={},["fingerprint"]="3ed9eee45c857ad01f1c1bec79c5272474ea6b2bb2d0210937e82ce5ac21aeae",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.task:Task:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="task"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="List, inspect, or run project tasks from nupp.lua."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Task?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Task",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.task:Task:1",Task,__nuppDerived) ;Task["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Task["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("task")end ;Task["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("List, inspect, or run project tasks from nupp.lua.")end ;Task["fromCLI"]=function(__nuppT8)return _G.require("nupp.cli")["derivedFromCLI"](__nuppT8,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Task,__nuppT1[1],{ })


function Task . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Task } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.task"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.task"]=__nuppExports;return __nuppExports