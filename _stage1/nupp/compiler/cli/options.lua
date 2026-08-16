_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local options = { }


options . strict = { name = "--strict" , help = "Treat strict checker rules as errors" , }




local DUPLICATE_FORMAT = "output format was specified more than once"



function options . format ( )
return {
{
name = "--format" ,
value = "FORMAT" ,
choices = { "text" , "json" } ,
duplicate = DUPLICATE_FORMAT ,
help = "Output format: text (default) or json"
} ,
{
name = "--json" ,
key = "format" ,
constant = "json" ,
duplicate = DUPLICATE_FORMAT ,
help = "Shorthand for --format json"
} ,
{
name = "--text" ,
key = "format" ,
constant = "text" ,
duplicate = DUPLICATE_FORMAT ,
help = "Shorthand for --format text"
} ,
}
end




local DUPLICATE_PROGRESS = "progress reporting was both asked for and refused"



function options . progress ( )
return {
{
name = "--progress" ,
value = "WHEN" ,
form = "optional" ,
constant = "always" ,
choices = { "always" , "never" , "auto" } ,
duplicate = DUPLICATE_PROGRESS ,
help = "When to report progress and timing on standard error: always, "
.. "never, or auto (default), which reports only to a terminal"
} ,
{
names = { "-q" , "--quiet" } ,
key = "progress" ,
constant = "never" ,
duplicate = DUPLICATE_PROGRESS ,
help = "Report no progress or timing; the same as --progress=never"
} ,
}
end





function options . optimize ( )
return {
{
name = "-O" ,
pattern = "^%-O(%d)$" ,
value = "n" ,
key = "optLevel" ,
choices = { "0" , "1" , "2" } ,
display = "-O0, -O1, -O2" ,
invalid = "the optimization level is -O0, -O1 or -O2" ,
help = "Optimization level (default -O0, which rewrites nothing)"
} ,
{ name = "--remarks" , help = "Report what the optimizer did and what it declined to do" } ,
{
name = "--relax" ,
value = "GUARANTEE" ,
form = "attached" ,
key = "relaxed" ,
repeats = true ,
set = true ,
choices = { "function-identity" , "load-order" , "error-site" , "frames" , "gc-timing" , "table-order" } ,
display = "--relax=GUARANTEE" ,
help = "Allow optimizations to change one named observable guarantee"
} ,
{
name = "-Zno-opt" ,
value = "CODE" ,
form = "attached" ,
key = "disabled" ,
repeats = true ,
set = true ,
display = "-Zno-opt=CODE" ,
help = "Turn off one pass, named by its stable code, to bisect a "
.. "miscompile. Unstable: the spelling may change or go away"
} ,
}
end



function options . join ( ... )
local joined = { }
for _ , group in ipairs ( { ... } ) do
if group . name or group . names then
joined [ # joined + 1 ] = group
else
for _ , option in ipairs ( group ) do
joined [ # joined + 1 ] = option
end
end
end

return joined
end

return options
