_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

















local fs = require ( "nupp.compiler.fs" )

local normalize , join = fs . normalize , fs . join
local readFile , exists = fs . readFile , fs . exists

local projectconfig = { }






local function targetConfig ( config , requested ) 
local build = ( config . build or { } )
if build . targets then
local name = requested or build . default
if not name then
local names = { }
for candidate in pairs ( build . targets ) do
names [ # names + 1 ] = candidate
end
table . sort ( names )
name = names [ 1 ]
end
local target = ( name and build . targets [ name ] )
if type ( target ) ~= "table" then
return nil , "unknown build target " .. tostring ( name )
end
local merged = { }
for key , value in pairs ( build ) do
if key ~= "targets" and key ~= "default" then
merged [ key ] = value
end
end
for key , value in pairs ( target ) do
merged [ key ] = value
end
if merged . kind == "docs" then
merged . targetName = name
else
merged . name = name
end
return merged
end



return build
end


function projectconfig . targetNames ( config , target ) 
local selected = { }

local function visit ( name ) 
if selected [ name ] then
return
end
selected [ name ] = true
local dependency = ( config . dependencies or { } ) [ name ]
for _ , child in ipairs ( dependency and dependency . dependencies or { } ) do
visit ( child )
end
end

for _ , name in ipairs ( target and target . dependencies or { } ) do
visit ( name )
end
local names = { }
for name in pairs ( selected ) do
names [ # names + 1 ] = name
end
table . sort ( names )

return names
end










local ROCK_LUA_VERSION = "5.1"
local ROCK_TREE = ".rocks"

local windows = package . config : sub ( 1 , 1 ) == "\\"

local currentDirectory = nil

local function absolute ( path ) 
path = normalize ( path or "" )
if path : sub ( 1 , 1 ) == "/" or path : match ( "^%a:" ) then
return path
end
if not currentDirectory then
currentDirectory = normalize ( fs . absolute ( "." ) )
end
if path == "" or path == "." then
return currentDirectory
end

return join ( currentDirectory , path )
end

local function treePaths ( tree , luaVersion ) 
local share = tree .. "/share/lua/" .. luaVersion
return {
path = share .. "/?.lua;" .. share .. "/?/init.lua" ,
cpath = tree .. "/lib/lua/" .. luaVersion .. ( windows and "/?.dll" or "/?.so" ) ,
}
end

local function rockTypeRoot ( tree , luaVersion , rock , version ) 
if not version or version == "installed" then
return nil
end
return join ( tree , "lib/luarocks/rocks-" .. luaVersion .. "/" .. rock .. "/" .. version .. "/nupp" )
end

local function rockTree ( root , dep ) 
return absolute ( join ( root , dep . tree or ".rocks" ) ) , dep . luaVersion or "5.1"
end




function projectconfig . rockspecField ( text , field ) 
return text : match ( "[\13\n]" .. field .. "%s*=%s*[\"']([^\"']+)[\"']" )
or text : match ( "^" .. field .. "%s*=%s*[\"']([^\"']+)[\"']" )
end

local function declaredVersion ( rockspec ) 
local text = rockspec and readFile ( rockspec )
if not text then
return nil
end

return projectconfig . rockspecField ( text , "version" )
end

local function declaredPackage ( rockspec ) 
local text = rockspec and readFile ( rockspec )
if not text then
return nil
end

return projectconfig . rockspecField ( text , "package" )
end




local function rockIdentity ( record , dep , rockspec , name ) 
return record and record . rock
or dep . rock
or declaredPackage ( rockspec )
or name , record and record . version
or dep . version
or declaredVersion ( rockspec )
end







local function rockPaths (
root ,
config ,
target ,
records
) 
local paths , cpaths , typeRoots , seen = { } , { } , { } , { }
for _ , name in ipairs ( projectconfig . targetNames ( config , target ) ) do
local dep = ( config . dependencies or { } ) [ name ]
if type ( dep ) == "table" and dep . kind == "luarocks" then
local tree , luaVersion = rockTree ( root , dep )
local id = tree .. "\0" .. luaVersion
if not seen [ id ] then
seen [ id ] = true
local entries = treePaths ( tree , luaVersion )
paths [ # paths + 1 ] = entries . path
cpaths [ # cpaths + 1 ] = entries . cpath
end
local record = records and records [ name ] or nil




local rockspec = dep . rockspec and absolute ( join ( root , dep . rockspec ) ) or nil
local rock , version = rockIdentity ( record , dep , rockspec , name )
local typeRoot = record and record . typeRoot or rockTypeRoot ( tree , luaVersion , rock , version )
if typeRoot then
typeRoots [ # typeRoots + 1 ] = typeRoot
end
end
end
if # paths == 0 then
return nil
end

return { path = table . concat ( paths , ";" ) , cpath = table . concat ( cpaths , ";" ) , typeRoots = typeRoots , }
end

local function scopeKey ( name , usage ) 
if usage == "target" then
return name
end
return usage .. ":" .. name
end

local function dependencyRecord ( records , name , usage ) 
return records and records [ scopeKey ( name , usage or "target" ) ] or nil
end




local function typeRoots ( root , config , records ) 
local roots = { }
local target = config . _target or { }
local names = target . compileDependencies
if names == nil then
names = { }
for name , dep in pairs ( config . dependencies or { } ) do
if dep . kind == "types" then
names [ # names + 1 ] = name
end
end
end
local selected = { }
for _ , name in ipairs ( names ) do
selected [ name ] = true
end
for _ , name in ipairs ( projectconfig . targetNames ( config , target ) ) do
selected [ name ] = true
end
for name in pairs ( selected ) do
local dep = ( config . dependencies or { } ) [ name ]
if dep then
local record = ( records and records [ scopeKey ( name , "compile" ) ] or nil ) or ( records and records [ scopeKey ( name , "target" ) ] or nil )
local checkout = join ( root , ".nupp/deps/" .. name )
local path = record and ( record . typesRoot or record . typeRoot )
or dep . kind == "types" and join ( checkout , dep . path or "." )
or nil
if path and exists ( path ) then
roots [ # roots + 1 ] = path
end
end
end
table . sort ( roots )

return roots
end

projectconfig . targetConfig = targetConfig
projectconfig . absolute = absolute
projectconfig . treePaths = treePaths
projectconfig . rockTypeRoot = rockTypeRoot
projectconfig . rockTree = rockTree
projectconfig . rockIdentity = rockIdentity
projectconfig . declaredVersion = declaredVersion
projectconfig . declaredPackage = declaredPackage
projectconfig . rockPaths = rockPaths
projectconfig . scopeKey = scopeKey
projectconfig . record = dependencyRecord
projectconfig . typeRoots = typeRoots

local __nuppExportValue= projectconfig ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.projectconfig"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.projectconfig"]=__nuppExports;return __nuppExports