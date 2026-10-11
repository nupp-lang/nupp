_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local fs = require ( "nupp.compiler.fs" )
local process = require ( "nupp.compiler.process" )
local diagnostics = require ( "nupp.compiler.diagnostics" )

local join , normalize , dirname , basename = fs . join , fs . normalize , fs . dirname , fs . basename
local readFile , writeFile = fs . readFile , fs . writeFile

local rock = { }
local windows = package . config : sub ( 1 , 1 ) == "\\"

local function commandPath ( path ) 
if not windows then
return path
end
path = path : gsub ( "^/([A-Za-z])(/)" , "%1:%2" )

return ( path : gsub ( "/" , "\\" ) )
end







local function moduleName ( name ) 
return name : gsub ( "-" , "_" )
end

local function quote ( value ) 
return string . format ( "%q" , value )
end

local function rootRockspec ( root , asked ) 
if asked then
if normalize ( asked ) ~= basename ( normalize ( asked ) ) then
return nil , "the rockspec must be in the project root"
end
local path = join ( root , asked )
if not fs . exists ( path ) then
return nil , asked .. " is not there"
end
return path
end
local found = { }
for _ , path in ipairs ( fs . listFiles ( root ) ) do
local relative = normalize ( path ) : sub ( # normalize ( root ) + ( root == "." and 0 or 2 ) )
if not relative : find ( "/" , 1 , true ) and relative : match ( "%.rockspec$" ) then
found [ # found + 1 ] = path
end
end
if # found == 0 then
return nil , "no rockspec found in " .. root
end
if # found > 1 then
return nil , "more than one rockspec found; name the one to use"
end

return found [ 1 ]
end

local function metadata ( root , asked ) 
local rockspec , err = rootRockspec ( root , asked )
if not rockspec then
return nil , err
end
local text , readErr = readFile ( rockspec )
if not text then
return nil , readErr
end



local deps = require ( "nupp.tools.build.deps" )
local name = deps . rockspecField ( text , "package" )
local version = deps . rockspecField ( text , "version" )
if not name or not version then
return nil , rockspec .. " must declare literal package and version strings"
end

return { name = name , version = version , rockspec = rockspec }
end

local function declarationModules ( root ) 
local base = join ( root , "nupp" )
local modules = { }
for _ , path in ipairs ( fs . listFiles ( base ) ) do
local relative = normalize ( path ) : sub ( # normalize ( base ) + 2 )
local name = relative : match ( "^(.*)%.d%.nupp$" )
if name then
name = name : gsub ( "/init$" , "" ) : gsub ( "/" , "." )
modules [ # modules + 1 ] = name
end
end
table . sort ( modules )
if # modules == 0 then
return nil , "nupp/ contains no .d.nupp module declarations"
end

return modules
end

local function validateDeclarations ( root , modules ) 
local incremental = require ( "nupp.compiler.project.incremental" )
local inc = incremental . new ( join ( root , ".nupp-rock-check" ) , {
cache = false ,
config = { include = { } } ,
typeRoots = { join ( root , "nupp" ) } ,
} )
local failed = { }
for _ , name in ipairs ( modules ) do
local path = inc . modulePath ( name )
local result = path and inc . checkFile ( path ) or nil
for _ , diag in ipairs ( result and result . diags or { } ) do
failed [ # failed + 1 ] = diag
end
end
if # failed > 0 then
diagnostics . report ( failed )
return nil , "rock declarations have errors"
end

return true
end

local function packedPath ( output ) 
for line in output : gmatch ( "[^\13\n]+" ) do
local path = line : match ( "Packed:%s*(.+%.rock)%s*$" )
if path then
return normalize ( path )
end
end

return nil
end


function rock . pack ( root , asked ) 
root = normalize ( root or "." )
local meta , err = metadata ( root , asked )
if not meta then
return nil , err
end
local modules , modulesErr = declarationModules ( root )
if not modules then
return nil , modulesErr
end
local valid , validErr = validateDeclarations ( root , modules )
if not valid then
return nil , validErr
end
if require ( "nupp.tools.build.project" ) . build ( root ) ~= 0 then
return nil , "project build failed"
end
local relativeRockspec = meta . rockspec
if root ~= "." and relativeRockspec : sub ( 1 , # root + 1 ) == root .. "/" then
relativeRockspec = relativeRockspec : sub ( # root + 2 )
end
local code , output = process . capture (
{ "luarocks" , "--lua-version=5.1" , "make" , "--pack-binary-rock" , relativeRockspec } ,
{ cwd = root }
)
if code ~= 0 then
io . stderr : write ( output )
return nil , "LuaRocks could not pack " .. meta . name
end
local path = packedPath ( output )
if not path then
return nil , "LuaRocks packed the project but did not report the output path"
end
local absolute = path : sub ( 1 , 1 ) == "/" or path : match ( "^[A-Za-z]:/" ) ~= nil
if not absolute and root ~= "." then
path = join ( root , path )
end

return path
end

local function removeTree ( path ) 
if windows then
return process . run ( { "cmd" , "/d" , "/c" , "rmdir" , "/s" , "/q" , commandPath ( path ) } )
end
return process . run ( { "rm" , "-rf" , path } )
end


function rock . test ( root , asked ) 
root = normalize ( root or "." )
local meta , err = metadata ( root , asked )
if not meta then
return nil , err
end
local packed , packErr = rock . pack ( root , asked )
if not packed then
return nil , packErr
end
local temp = os . tmpname ( )
os . remove ( temp )
if not fs . mkdir ( temp ) then
return nil , "cannot create temporary rock tree"
end
local localArtifact = ( windows and ".\\" or "./" ) .. basename ( packed )
local code , output = process . capture (
{ "luarocks" , "--lua-version=5.1" , "--tree=" .. commandPath ( temp ) , "install" , localArtifact , } ,
{ cwd = commandPath ( dirname ( packed ) ) }
)
if code ~= 0 then
io . stderr : write ( output )
removeTree ( temp )
return nil , ("the packed rock %s could not be installed from %s (present: %s)")

: format ( localArtifact , dirname ( packed ) , tostring ( fs . exists ( packed ) ) )
end
local modules , modulesErr = declarationModules (
join ( temp , "lib/luarocks/rocks-5.1/" .. meta . name .. "/" .. meta . version )
)
if not modules then
removeTree ( temp )
return nil , modulesErr
end
local consumer = join ( temp , "consumer" )
local dependency = moduleName ( meta . name )
local requires = { }
local returned = { }
for index , name in ipairs ( modules ) do
local runtime = join ( temp , "share/lua/5.1/" .. name : gsub ( "%." , "/" ) )
if not fs . exists ( runtime .. ".lua" ) and not fs . exists ( runtime .. "/init.lua" ) then
removeTree ( temp )
return nil , "declaration " .. name .. " has no installed runtime module"
end
requires [ # requires + 1 ] = ("local module%d = require(%s)\n") : format ( index , quote ( name ) )
returned [ # returned + 1 ] = "module" .. index
end
local consumerManifest = ("return {\n   include = { \"src\" },\n   dependencies = {\n      [%s] = { kind = \"luarocks\", rock = %s, version = %s, tree = %s },\n   },\n   build = { entries = { \"main\" }, dependencies = { %s } },\n}\n")








: format ( quote ( dependency ) , quote ( meta . name ) , quote ( meta . version ) , quote ( temp ) , quote ( dependency ) )
local ok , writeErr = writeFile ( join ( consumer , "nupp.lua" ) , consumerManifest )
if ok then
ok , writeErr = writeFile (
join ( consumer , "src/main.nupp" ) ,
table . concat ( requires ) .. "return {" .. table . concat ( returned , ", " ) .. "}\n"
)
end
if not ok then
removeTree ( temp )
return nil , writeErr
end




local checked = require ( "nupp.tools.build.project" ) . build ( consumer , { checkOnly = true , progress = "never" } )
removeTree ( temp )
if checked ~= 0 then
return nil , "the clean consumer could not check the installed rock"
end

return packed
end

local __nuppExportValue= rock ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.rock"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.rock"]=__nuppExports;return __nuppExports