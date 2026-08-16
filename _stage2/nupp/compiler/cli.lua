_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);


















local specMod = require ( "nupp.compiler.cli.spec" )
local optionsMod = require ( "nupp.compiler.cli.options" )
local ansi = require ( "nupp.compiler.ansi" )

local cli = { }






local REGISTRY


= {
{
name = "init" ,
load = function ( )
return require ( "nupp.compiler.cli.init_command" )
end
} ,
{
name = "ast" ,
load = function ( )
return require ( "nupp.compiler.cli.ast" )
end
} ,
{
name = "bc" ,
load = function ( )
return require ( "nupp.compiler.cli.bc" )
end
} ,
{
name = "check" ,
load = function ( )
return require ( "nupp.compiler.cli.check" )
end
} ,
{
name = "fmt" ,
load = function ( )
return require ( "nupp.compiler.cli.fmt" )
end
} ,
{
name = "build" ,
load = function ( )
return require ( "nupp.compiler.cli.build" )
end
} ,
{
name = "clean" ,
load = function ( )
return require ( "nupp.compiler.cli.clean" )
end
} ,
{
name = "tasks" ,
load = function ( )
return require ( "nupp.compiler.cli.tasks" )
end
} ,
{
name = "lints" ,
load = function ( )
return require ( "nupp.compiler.cli.lints" )
end
} ,
{
name = "ownership-audit" ,
load = function ( )
return require ( "nupp.compiler.cli.ownership_audit" )
end
} ,
{
name = "explain" ,
load = function ( )
return require ( "nupp.compiler.cli.explain" )
end
} ,
{
name = "reference" ,
load = function ( )
return require ( "nupp.compiler.cli.reference" )
end
} ,
{
name = "completions" ,
load = function ( )
return require ( "nupp.compiler.cli.completions_command" )
end
} ,
{
name = "test" ,
load = function ( )
return require ( "nupp.compiler.cli.test" )
end
} ,
{
name = "coverage" ,
load = function ( )
return require ( "nupp.compiler.cli.coverage" )
end
} ,
{
name = "task" ,
load = function ( )
return require ( "nupp.compiler.cli.task" )
end
} ,
{
name = "doc" ,
load = function ( )
return require ( "nupp.compiler.cli.doc" )
end
} ,
{
name = "fixpoint" ,
load = function ( )
return require ( "nupp.compiler.cli.fixpoint" )
end
} ,
{
name = "run" ,
load = function ( )
return require ( "nupp.compiler.cli.run" )
end
} ,
{
name = "import-c" ,
load = function ( )
return require ( "nupp.compiler.cli.importc" )
end
} ,
{
name = "export-c" ,
load = function ( )
return require ( "nupp.compiler.cli.exportc" )
end
} ,
{
name = "rock" ,
load = function ( )
return require ( "nupp.compiler.cli.rock" )
end
} ,
{
name = "lsp" ,
load = function ( )
return require ( "nupp.compiler.cli.lsp" )
end
} ,
}



local HELP_COMMAND = specMod . command {
name = "help" ,
summary = "Show general or command-specific help" ,
usage = { "nupp help [command]" } ,
detail = "With no command, prints the command list." ,
}

local byName = { }
for _ , entry in ipairs ( REGISTRY ) do
byName [ entry . name ] = entry . load
end


local function lookup ( name )
local load = byName [ name ]
return load and load ( ) or nil
end



local function mainHelp ( )
local style = ansi . style ( io . stdout )
local out

= {
"Nupp compiler and project tool" ,
"" ,
style . strong ( "Usage:" ) ,
"  nupp <command> [options]" ,
"  nupp help [command]" ,
"" ,
style . strong ( "Commands:" ) ,
}
local width = # "import-c"
local summaries


= { }
for _ , entry in ipairs ( REGISTRY ) do
summaries [ # summaries + 1 ] = { name = entry . name , summary = entry . load ( ) . spec . summary }
if # entry . name > width then
width = # entry . name
end
end
summaries [ # summaries + 1 ] = { name = HELP_COMMAND . name , summary = HELP_COMMAND . summary }
local paint = ansi . forSeverity ( style , "note" )
for _ , entry in ipairs ( summaries ) do
out [ # out + 1 ] = "  " .. paint ( entry . name ) .. ( " " ) : rep ( width - # entry . name + 2 ) .. entry . summary
end
out [ # out + 1 ] = ""
out [ # out + 1 ] = "Run 'nupp help <command>' for command-specific options."

return table . concat ( out , "\n" ) .. "\n"
end

local function fail ( message , hint )
local style = ansi . style ( io . stderr )
io . stderr : write ( ansi . forSeverity ( style , "error" ) ( "nupp:" ) .. " " .. message .. "\n" .. hint .. "\n" )
return 2
end


local function runHelp ( args )
local name = args [ 1 ]
if args [ 2 ] then
return fail ( "help accepts at most one command name" , "Try 'nupp help' for a list of commands." )
end
if not name then
io . write ( mainHelp ( ) )
return 0
end
if name == "-h" or name == "--help" then
io . write ( HELP_COMMAND : help ( ) )
return 0
end
if name == "help" then
io . write ( HELP_COMMAND : help ( ) )
return 0
end
local command = lookup ( name )
if not command then
return fail ( "unknown command " .. name , "Try 'nupp help' for a list of commands." )
end
io . write ( command . spec : help ( ) )

return 0
end




local function applyColor ( values )
local wanted = values . color
if type ( wanted ) == "string" then
ansi . setMode ( wanted )
end
end







const JIT_DEFAULT_COMMANDS = { lsp = true , run = true , task = true }



















local function tuneJitFor ( name )
if JIT_DEFAULT_COMMANDS [ name ] or os . getenv ( "NUPP_JIT_DEFAULT" ) then
return
end
local override = os . getenv ( "NUPP_JIT_TUNE" )


if not override then
pcall ( jit . opt . start , "hotexit=200" , "hotloop=1000" )

return
end
local flags = { }
for flag in override : gmatch ( "[^,]+" ) do
flags [ # flags + 1 ] = flag
end
pcall ( function ( )
jit . opt . start ( unpack ( flags ) )
end )
end

function cli . main ( argv )
local name = argv [ 1 ]
if not name or name == "-h" or name == "--help" then


io . write ( mainHelp ( ) )
return 0
end
if name == "__comptime-worker" then
local rest = { }
for index = 2 , # argv do
rest [ # rest + 1 ] = argv [ index ]
end

local worker = require ( "nupp.compiler.comptime_worker" )

return worker . main ( rest )
elseif name == "__comptime-worker-service" then
local worker = require ( "nupp.compiler.comptime_worker" )

return worker . serviceMain ( )
elseif name == "__lsp-reader" then
local server = require ( "nupp.compiler.lsp.init" )

return server . readerMain ( )
end
local rest = { }
for index = 2 , # argv do
rest [ # rest + 1 ] = argv [ index ]
end
if name == "help" then
return runHelp ( rest )
end
tuneJitFor ( name )
local command = lookup ( name )
if not command then
return fail ( "unknown command " .. name , "Try 'nupp help' for a list of commands." )
end
if command . raw then


if rest [ 1 ] == "-h" or rest [ 1 ] == "--help" then
io . write ( command . spec : help ( ) )
return 0
end
if rest [ 1 ] == "--schema" and command . spec . schema then
require ( "nupp.compiler.cli.report" ) . write ( command . spec . schema )
return 0
end
return command . run ( rest )
end
local parsed , err = command . spec : parse ( rest )
if not parsed then
return command . spec : usageError ( err )
end
applyColor ( parsed . values )
if parsed . values . help then
io . write ( command . spec : help ( ) )
return 0
end
if parsed . values . schema then


require ( "nupp.compiler.cli.report" ) . write ( command . spec . schema )
return 0
end

return command . run ( parsed )
end

cli . spec = specMod
cli . options = optionsMod


function cli . names ( )
local names = { }
for _ , entry in ipairs ( REGISTRY ) do
names [ # names + 1 ] = entry . name
end
names [ # names + 1 ] = "help"

return names
end




function cli . commands ( )
local commands = { }
for _ , entry in ipairs ( REGISTRY ) do
commands [ # commands + 1 ] = { name = entry . name , spec = entry . load ( ) . spec }
end
commands [ # commands + 1 ] = { name = HELP_COMMAND . name , spec = HELP_COMMAND }

return commands
end

return cli
