_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);

local spec = require ( "nupp.compiler.cli.spec" )

local command = spec . command {
name = "rock" ,
summary = "Create and package typed LuaRocks libraries" ,
usage = { "nupp rock init <name> [directory]" , "nupp rock pack [rockspec]" , "nupp rock test [rockspec]" , } ,
universal = false ,
options = { spec . helpOption } ,
detail = [[A Nupp rock installs runtime Lua normally and carries matching public
declarations in its versioned `nupp/` directory. `pack` validates and builds that
layout; `test` installs the result into a fresh tree and checks a fresh consumer.]] ,
}

local function operation ( name , summary , usage , detail )
return spec . command {
name = "rock " .. name ,
helpName = "rock" ,
summary = summary ,
usage = { usage } ,
universal = false ,
options = { spec . helpOption } ,
detail = detail ,
}
end

local INIT = operation (
"init" ,
"Create a typed Nupp library rock" ,
"nupp rock init <name> [directory]" ,
"The directory defaults to the rock name and must not already exist."
)
local PACK = operation (
"pack" ,
"Build and pack the current Nupp library" ,
"nupp rock pack [rockspec]" ,
"With no path, the one rockspec in the current directory is used."
)
local TEST = operation (
"test" ,
"Install and check the rock from a clean consumer" ,
"nupp rock test [rockspec]" ,
"Packs first, installs into a temporary tree, and checks every declared module."
)

local OPERATIONS = { init = INIT , pack = PACK , test = TEST }

local function parsed ( operation , args )
local result , err = operation : parse ( args )
if not result then
return nil , operation : usageError ( err )
end
if result . values . help then
io . write ( operation : help ( ) )
return nil , 0
end

return result
end

local function run ( args )
local name = table . remove ( args , 1 )
if not name then
io . write ( command : help ( ) )
return 0
end
local operation = OPERATIONS [ name ]
if not operation then
return command : usageError ( "unknown rock operation " .. name )
end
local result , answered = parsed ( operation , args )
if not result then
return answered
end
local positional = result . positional
local library = require ( "nupp.compiler.rock" )
if name == "init" then
if not positional [ 1 ] then
return operation : usageError ( "a rock name is required" )
end
if positional [ 3 ] then
return operation : usageError ( "init accepts a name and optional directory" )
end
local ok , err = library . init ( positional [ 1 ] , positional [ 2 ] )
if not ok then
io . stderr : write ( "nupp: " .. tostring ( err ) .. "\n" )
return 1
end
io . write ( "Created " .. ( positional [ 2 ] or positional [ 1 ] ) .. "\n" )
return 0
end
if positional [ 2 ] then
return operation : usageError ( name .. " accepts at most one rockspec" )
end
local packed , err
if name == "pack" then
packed , err = library . pack ( "." , positional [ 1 ] )
else
packed , err = library . test ( "." , positional [ 1 ] )
end
if not packed then
io . stderr : write ( "nupp: " .. tostring ( err ) .. "\n" )
return 1
end
io . write ( ( name == "pack" and "Packed " or "Checked " ) .. packed .. "\n" )

return 0
end

return setmetatable({ spec =  command ,  raw =  true ,  run =  run }, spec.Handler)
