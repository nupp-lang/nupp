_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.derive").install(__nupp);local __nuppT13={}; local function __nuppT10(...) return {n=select("#",...),...} end; local __nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20,__nuppT21=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT11(value) return value end; local function __nuppT12(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT19({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT20(v.primary) for _,reason in __nuppT21(v.suppressed) do text=text.."\ncleanup: "..__nuppT20(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.cli.initcommand\0runtime\0001") };














local files = require ( "nupp.io.files" )
local ansi = require ( "nupp.cli" )
local usageError = require ( "nupp.tools.cli.error" ) . forCommand ( "init" )
local cliModule = require ( "nupp.cli" )
local report = require ( "nupp.tools.cli.report" )

local SCAFFOLD_SCHEMA = {
type = "object" ,
description = "A scaffold: what was written, or would be under --dry-run." ,
properties = {
ok = report . OK ,
directory = { type = "string" } ,
template = {
type = "object" ,
description = "What the TEMPLATE argument resolved to." ,
properties = {
kind = { type = "string" , enum = { "builtin" , "directory" , "remote" } } ,
name = { type = "string" , description = "The built-in's name." } ,
path = { type = "string" , description = "The directory it was read from." } ,
url = { type = "string" } ,
subdir = { type = "string" } ,
commit = { type = "string" , description = "The commit a repository template resolved to." } ,
} ,
required = { "kind" } ,
} ,
variables = {
type = "object" ,
description = "Every variable value used, derived ones included." ,
additionalProperties = { type = "string" } ,
} ,
written = {
type = "array" ,
items = { type = "string" } ,
description = "The paths written, or the paths that would be under --dry-run."
} ,
dryRun = { type = "boolean" } ,
steps = {
type = "array" ,
description = "The post-init steps that ran, and whether each succeeded." ,
items = {
type = "object" ,
properties = { name = { type = "string" } , ok = { type = "boolean" } } ,
required = { "name" , "ok" } ,
} ,
} ,
dropped = {
type = "array" ,
items = { type = "string" } ,
description = "Steps the template asked for that a repository template does not get."
} ,
} ,
required = { "ok" , "directory" , "template" , "variables" , "written" , "dryRun" , "steps" , "dropped" } ,
}

local LISTING_SCHEMA = {
type = "object" ,
description = "The templates --list names." ,
properties = {
ok = report . OK ,
templates = {
type = "array" ,
items = {
type = "object" ,
properties = {
name = { type = "string" } ,
description = { type = "string" } ,
kind = { type = "string" , enum = { "builtin" } } ,
} ,
required = { "name" , "description" , "kind" } ,
} ,
} ,
} ,
required = { "ok" , "templates" } ,
}

local REPORT_SCHEMA = { oneOf = { SCAFFOLD_SCHEMA , LISTING_SCHEMA , report . FAILURE } }



local function fail ( message , asJson , code ) 
if asJson then
return report . failure ( REPORT_SCHEMA , { report . runDiagnostic ( code or report . UNREADABLE , message ) } )
end
io . stderr : write ( ansi . severity ( ansi . style ( io . stderr ) , "error" ) ( "nupp:" ) .. " " .. message .. "\n" )

return 1
end


local function settings ( given ) 
local values = { }
for _ , entry in ipairs ( given or { } ) do
local key , value = entry : match ( "^([^=]+)=(.*)$" )
if not key then
return nil , "--set takes KEY=VALUE, not " .. entry
end
values [ key ] = value
end

return values
end






local function defaultDirectory ( source ) 
local fs = require ( "nupp.compiler.fs" )
if source . kind == "builtin" then
return source . name
end
if source . kind == "directory" then
return fs . basename ( source . path )
end
if source . subdir then
return fs . basename ( source . subdir )
end

return ( fs . basename ( source . url ) : gsub ( "%.git$" , "" ) )
end





local function confirm ( description , count , destination ) 
io . write (
"About to write " .. count .. " file" .. (
count == 1 and "" or "s"
) .. " from " .. description .. "\n  into " .. destination .. "\n"
)
if not ansi . isTerminal ( io . stdin ) then
return false , "refusing to write a repository template without a terminal to ask\nPass --yes to accept it unread."

end
io . write ( "Continue? [y/N] " )
io . stdout : flush ( )
local answer = io . read ( "*l" )
if answer ~= "y" and answer ~= "Y" and answer ~= "yes" then
return false , nil
end

return true
end

local function listBuiltins ( asJson ) 
local template = require ( "nupp.tools.template" )
if asJson then
local templates = { }
for _ , name in ipairs ( template . builtins ( ) ) do
templates [ # templates + 1 ] = { name = name , description = template . builtinDescription ( name ) , kind = "builtin" }
end
report . write ( { ok = true , templates = templates } )

return 0
end
local style = ansi . style ( io . stdout )
local names = template . builtins ( )
local rows = { }
for index , name in ipairs ( names ) do
rows [
index
] = { ansi . paintedCell ( name , ansi . severity ( style , "note" ) ) , ansi . cell ( template . builtinDescription ( name ) ) , }
end
ansi . writeTable (
io . stdout ,
{
columns = { { heading = "built-in template" } , { heading = "what it writes" } } ,
rows = rows ,
style = style ,
indent = "  " ,
}
)

return 0
end

local function reportSteps ( plan , destination , dryRun ) 
local template = require ( "nupp.tools.template" )
local ran = { }
if dryRun then
return ran
end





local nupp = os . getenv ( "NUPP" ) or "nupp"
for _ , step in ipairs ( plan . steps ) do
local ok = template . step ( step , destination , nupp )
ran [ # ran + 1 ] = { name = step , ok = ok }
if not ok then
io . stderr : write ( "nupp: the " .. step .. " step did not succeed\n" )
end
end

return ran
end






local function scaffold ( source , destination , values , set ) 
local template = require ( "nupp.tools.template" )
local fs = require ( "nupp.compiler.fs" )
local asJson = values . format == "json"
local dryRun = values . dryRun and true or false
local plan , planErr = template . plan ( source , destination , { name = values . name , set = set } )
if not plan then
return fail ( planErr , asJson )
end
if source . kind == "remote" and not values . yes and not dryRun then
local accepted , refusal = confirm ( template . describe ( source ) , # plan . files , plan . destination )
if not accepted then
if refusal then
return fail ( refusal , asJson )
end
if asJson then
return fail ( "the template was declined; nothing was written" , true )
end
io . write ( "Nothing was written.\n" )

return 1
end
end
local written = { }
if dryRun then
for _ , file in ipairs ( plan . files ) do
written [ # written + 1 ] = fs . join ( plan . destination , file . output )
end
else
local paths , writeErr = template . write ( plan )
if not paths then
return fail ( writeErr , asJson )
end
written = paths
end
local ran = reportSteps ( plan , plan . destination , dryRun )
if asJson then
report . write ( {
ok = true ,
directory = plan . destination ,
template = {
kind = source . kind ,
name = source . name ,
path = source . path ,
url = source . url ,
subdir = source . subdir ,
commit = source . commit ,
} ,
variables = plan . values ,
written = written ,
dryRun = dryRun ,
steps = ran ,
dropped = plan . dropped ,
} )

return 0
end
local style = ansi . style ( io . stdout )
if dryRun then
io . write ( "Would write " .. # written .. " files into " .. plan . destination .. ":\n" )
for _ , path in ipairs ( written ) do
io . write ( "  " .. path .. "\n" )
end
else
io . write ( "Created " .. style . strong ( plan . destination ) .. " from " .. template . describe ( source ) .. "\n" )
end
if # plan . dropped > 0 then
io . write (
"\nNot run, because a repository template's steps are reduced to git init: " .. table . concat (
plan . dropped ,
", "
) .. "\nRead the project, then run them yourself.\n"
)
end
if not dryRun then
io . write ( "\nNext:\n  cd " .. plan . destination .. "\n  nupp check\n  nupp test\n" )
end

return 0
end

local function run ( options ) 
local positional = { }
if options . template ~= nil then
positional [ # positional + 1 ] = options . template
end
if options . directory ~= nil then
positional [ # positional + 1 ] = options . directory
end
local values = options
if values . list then
if # positional > 0 or values . templateFrom then
return usageError ( "--list takes no other arguments" )
end
return listBuiltins ( values . format == "json" )
end



local spelling = not values . templateFrom and positional [ 1 ] or nil
local named = values . templateFrom and positional [ 1 ] or positional [ 2 ]
local limit = values . templateFrom and 1 or 2
if # positional > limit then
return usageError ( "unexpected argument " .. positional [ limit + 1 ] )
end
local set , setErr = settings ( values . set )
if not set then
return usageError ( setErr )
end
local template = require ( "nupp.tools.template" )


local source , resolveErr = template . resolve ( spelling , values . templateFrom , values . rev )
if not source then
return usageError ( resolveErr )
end
local destination = named or values . name or defaultDirectory ( source )
if source . kind ~= "remote" then
return scaffold ( source , destination , values , set )
end




do local __nuppT22=0; local  __nuppT28 ; local __nuppT29=false ; local __nuppT23,__nuppT24,__nuppT25=__nuppT15(function() do local __nuppT30=__nuppT10( files . createTemporaryDirectory ( { prefix = "nupp-template-" } ) ); __nuppT28= __nuppT30[1] ; __nuppT22=1;  __nuppT29=true;  local  owned , scratchErr = __nuppT30[1] , __nuppT30[2] ;
if not owned then
return "return",__nuppT10( fail ( "cannot create a temporary directory: " .. tostring ( scratchErr ) , values . format == "json" ) )
end
local code
local fetched , fetchErr = template . fetch ( source , owned : toString ( ) )
if not fetched then
code = fail ( fetchErr , values . format == "json" , report . TOOL_FAILED )
else
code = scaffold ( source , destination , values , set )
end
files . remove ( owned : toString ( ) , true )
do (function(__nuppT31,...)  __nuppT29=false; return __nuppT31:close(...)  end)( owned ) end

return "return",__nuppT10( code ) end; return "normal" end,__nuppT11); local __nuppT26={}; local __nuppT27=0; if __nuppT22>=1 and __nuppT29 and __nuppT28~=nil then  local __nuppT32,__nuppT33=__nuppT14(__nuppCleanup1,__nuppT28);  if not __nuppT32 then __nuppT27=__nuppT27+1; __nuppT26[__nuppT27]=__nuppT33 end; end; if not __nuppT23 then if __nuppT27>0 then __nuppT16(__nuppT12(__nuppT24,__nuppT26,1),0) else __nuppT16(__nuppT24,0) end end; if __nuppT27>0 then if __nuppT27>1 then __nuppT16(__nuppT12(__nuppT26[1],__nuppT26,2),0) else __nuppT16(__nuppT26[1],0) end end; if __nuppT24=="return" then  return __nuppT17(__nuppT25,1,__nuppT25.n)  end; end
end










local Init = {} Init.__index = Init








































function Init:run() 
return run ( self )
end ;Init.__nuppInit1=function(__nuppT35, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11) __nuppT35.name = a1 if a2 == nil then __nuppT35.set = {} else __nuppT35.set = a2 end __nuppT35.templateFrom = a3 __nuppT35.rev = a4 if a5 == nil then __nuppT35.list = false else __nuppT35.list = a5 end if a6 == nil then __nuppT35.yes = false else __nuppT35.yes = a6 end if a7 == nil then __nuppT35.dryRun = false else __nuppT35.dryRun = a7 end if a8 == nil then __nuppT35.format = "text" else __nuppT35.format = a8 end if a9 == nil then __nuppT35.schema = false else __nuppT35.schema = a9 end __nuppT35.template = a10 __nuppT35.directory = a11 return __nuppT35 end ;do local __nuppDerived={["data"]={["cli"]={["command"]={["aliases"]={},["documentation"]="Create a project from a template.\n\nExamples:\n\n    nupp init --list\n    nupp init app hello\n    nupp init lib math",["group"]=false,["hidden"]=false,["name"]="init",["summary"]="Create a project from a template."},["fieldCount"]=11,["fields"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--name",["documentation"]="Project name; defaults to the directory basename.",["field"]="name",["hidden"]=false,["index"]=1,["long"]=true,["names"]={"name"},["optional"]=true,["required"]=false,["role"]="option",["value"]="NAME"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--set",["documentation"]="Set a template variable.",["field"]="set",["hidden"]=false,["index"]=2,["long"]=true,["names"]={"set"},["repeated"]=true,["required"]=false,["role"]="option",["value"]="KEY=VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--from",["documentation"]="Use a template directory on disk.",["field"]="templateFrom",["hidden"]=false,["index"]=3,["long"]=true,["names"]={"from"},["optional"]=true,["required"]=false,["role"]="option",["value"]="PATH"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="--rev",["documentation"]="Commit, tag, or branch for a repository template.",["field"]="rev",["hidden"]=false,["index"]=4,["long"]=true,["names"]={"rev"},["optional"]=true,["required"]=false,["role"]="option",["value"]="REV"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--list",["documentation"]="List built-in templates and exit.",["field"]="list",["hidden"]=false,["index"]=5,["long"]=true,["names"]={"list"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--yes",["documentation"]="Do not ask before writing a repository template.",["field"]="yes",["hidden"]=false,["index"]=6,["long"]=true,["names"]={"yes"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--dry-run",["documentation"]="Print what would be written and write nothing.",["field"]="dryRun",["hidden"]=false,["index"]=7,["long"]=true,["names"]={"dry-run"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["choices"]={"json","text"},["constants"]={["json"]="json",["text"]="text"},["conversion"]="choice",["destination"]="string",["display"]="--format",["documentation"]="Select the report representation.",["field"]="format",["hidden"]=false,["index"]=8,["long"]=true,["names"]={"format","json","text"},["required"]=false,["role"]="option",["value"]="FORMAT"},{["arity"]="none",["constants"]={},["conversion"]="boolean",["destination"]="boolean",["display"]="--schema",["documentation"]="Print the JSON Schema of JSON output and exit.",["field"]="schema",["hidden"]=false,["index"]=9,["long"]=true,["names"]={"schema"},["required"]=false,["role"]="option",["value"]="VALUE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="TEMPLATE",["documentation"]="Template name or repository.",["field"]="template",["hidden"]=false,["index"]=10,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="TEMPLATE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="DIRECTORY",["documentation"]="Destination directory.",["field"]="directory",["hidden"]=false,["index"]=11,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="DIRECTORY"}},["positionals"]={{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="TEMPLATE",["documentation"]="Template name or repository.",["field"]="template",["hidden"]=false,["index"]=10,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="TEMPLATE"},{["arity"]="required",["constants"]={},["conversion"]="string",["destination"]="string",["display"]="DIRECTORY",["documentation"]="Destination directory.",["field"]="directory",["hidden"]=false,["index"]=11,["long"]=true,["names"]={},["optional"]=true,["required"]=false,["role"]="positional",["value"]="DIRECTORY"}},["preserveUnknown"]=false,["stopAtFirstArgument"]=false}},["effects"]={},["fields"]={},["fingerprint"]="d86f03dcf0edd0b3166704b48655c9e047e029e8d2affbbadaec71b45a5471d9",["helperABI"]={["nupp.cli.derivedFromCLI"]=1,["nupp.cli.derivedStrings"]=1,["nupp.cli.derivedText"]=1},["initializer"]="__nuppInit1",["inputs"]={},["key"]="nupp.derive.runtime.v2:nupp.tools.cli.initcommand:Init:1",["members"]={{["arguments"]={{["kind"]="constant",["value"]={}}},["helper"]={["member"]="derivedStrings",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliAliases",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): {string}"},{["arguments"]={{["kind"]="constant",["value"]="init"}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliName",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="constant",["value"]="Create a project from a template."}},["helper"]={["member"]="derivedText",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="cliSummary",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(): string"},{["arguments"]={{["kind"]="argument",["name"]="argv"},{["kind"]="entry"}},["helper"]={["member"]="derivedFromCLI",["module"]="nupp.cli"},["interface"]="cliModule.Runnable",["name"]="fromCLI",["namespace"]="static",["operation"]="forward.v1",["paramNames"]={"argv"},["provider"]="05e942631f9a8560d803c7587cae474a4892015a33a3814f709f02cad14b3c9e",["signature"]="function(argv: {string}): (Init?, {@readonly destination: string?, @readonly field: string?, @readonly index: integer?, @readonly kind: string, @readonly message: string, @readonly option: string?, @readonly raw: string?}?)"}},["name"]="Init",["providerABI"]={["cliModule.Command"]=1}} ;local __nuppDerivedEntry=_G.nupp.__derive.register("nupp.derive.runtime.v2:nupp.tools.cli.initcommand:Init:1",Init,__nuppDerived) ;Init["cliAliases"]=function()return _G.require("nupp.cli")["derivedStrings"]({})end ;Init["cliName"]=function()return _G.require("nupp.cli")["derivedText"]("init")end ;Init["cliSummary"]=function()return _G.require("nupp.cli")["derivedText"]("Create a project from a template.")end ;Init["fromCLI"]=function(argv)return _G.require("nupp.cli")["derivedFromCLI"](argv,__nuppDerivedEntry)end  end ;_G.nupp.__reflect.link(Init,__nuppT1[1],{ })


function Init . reportSchema ( ) 
return REPORT_SCHEMA
end

local __nuppExportValue= { commandType = Init } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.initcommand"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.initcommand"]=__nuppExports;return __nuppExports