_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()










local json = require ( "nupp.codec.json" )
local cache = require ( "nupp.tools.build.cache" )
local manifest = require ( "nupp.tools.build.manifest" )
local projectconfig = require ( "nupp.compiler.project.projectconfig" )

local jsonArray = cache . jsonArray

local tasks = { }










































local function targetConfig ( config , requested ) 
local target , err = projectconfig . targetConfig ( config , requested )

return target , err
end

local function copyStrings ( items ) 
local copied = jsonArray ( { } )
for _ , item in ipairs ( items or { } ) do
copied [ # copied + 1 ] = item
end

return copied
end

local function copyResources ( items ) 
local copied = jsonArray ( { } )
for _ , item in ipairs ( items or { } ) do
if type ( item ) == "table" then
local resource = item
copied [ # copied + 1 ] = resource . source .. " -> " .. resource . output
else
copied [ # copied + 1 ] = item
end
end

return copied
end





local function outDirOf ( target ) 
if target . outDir then
return target . outDir
end
if target . kind == "docs" then
return require ( "nupp.tools.doc" ) . defaultOutDir ( target . format or "site" )
end

return "build"
end

local function taskDescription ( config , name , isDefault ) 
local requested = config . build . targets and name or nil
local target , err = targetConfig ( config , requested )
if not target then
return nil , err
end

return {
name = name ,
default = isDefault ,
category = "build" ,
description = target . description ,
kind = target . kind or "modules" ,
outDir = outDirOf ( target ) ,
entries = copyStrings ( target . entries ) ,
sources = copyStrings ( target . sources ) ,
format = target . format ,
title = target . title ,
includePrivate = target . includePrivate ,
resources = copyResources ( target . resources ) ,
dependencies = copyStrings ( target . dependencies ) ,
nativeFeatures = target . nativeFeatures ,
layoutTarget = target . layoutTarget ,
platforms = copyStrings ( target . platforms ) ,
command = jsonArray ( { "nupp" , "build" , "--target" , name } ) ,
}
end

local function configuredTasks ( config , buildOnly ) 


local build = config . build
local names , defaultName = { } , nil
if build . targets then
for name in pairs ( build . targets ) do
names [ # names + 1 ] = name
end
table . sort ( names )
defaultName = build . default or names [ 1 ]
else
names [ 1 ] , defaultName = "default" , "default"
end
local tasks , used = { } , { }
for _ , name in ipairs ( names ) do
local task = assert ( taskDescription ( config , name , name == defaultName ) )
tasks [ # tasks + 1 ] , used [ name ] = task , true
end

local function actionName ( name ) 
while used [ name ] do
name = "command:" .. name
end
return name
end

if not buildOnly then
local test = manifest . testConfig ( config )
local name = actionName ( "test" )
tasks [
# tasks + 1
] = {
name = name ,
default = false ,
category = "project" ,
description = "Build and run project tests" ,
kind = "test" ,
buildTarget = test . build ,
argv = copyStrings ( manifest . testArgv ( test ) ) ,
env = test . env ,
command = jsonArray ( { "nupp" , "test" } ) ,
}
used [ name ] = true
end
if not buildOnly and config . selfHost then
local name = actionName ( "fixpoint" )
tasks [
# tasks + 1
] = {
name = name ,
default = false ,
category = "project" ,
description = "Verify the self-hosting compiler rebuild" ,
kind = "self-host" ,
buildTarget = config . selfHost . target ,
bootstrap = config . selfHost . bootstrap ,
command = jsonArray ( { "nupp" , "fixpoint" } ) ,
}
used [ name ] = true
end
if not buildOnly and config . tasks then
local customNames = { }
for customName in pairs ( config . tasks ) do
customNames [ # customNames + 1 ] = customName
end
table . sort ( customNames )
for _ , customName in ipairs ( customNames ) do


local custom = ( config . tasks or { } ) [ customName ]
local name = actionName ( customName )
tasks [
# tasks + 1
] = {
name = name ,
default = false ,
category = "task" ,
description = custom . description ,
kind = "task" ,
buildTarget = custom . build ,
cwd = custom . cwd ,
argv = copyStrings ( custom . argv ) ,
env = custom . env ,
command = jsonArray ( { "nupp" , "task" , customName } ) ,
}
used [ name ] = true
end
end
table . sort ( tasks , function ( left , right ) 
return left . name < right . name
end )

return tasks , defaultName
end










function tasks . describe (
root ,
requested ,
opts
) 
local config , err = manifest . load ( root or "." )
if not config then
return nil , err , "NUPP0002"
end
local build = config . build
if not build then
return nil , "nupp: build is not configured" , "NUPP0002"
end
local tasks , defaultName = configuredTasks ( config , opts and opts . buildOnly )
if requested then
for _ , task in ipairs ( tasks ) do
if task . name == requested then
return task
end
end
return nil , "nupp: unknown project task " .. requested , "NUPP0003"
end

return { default = defaultName , tasks = jsonArray ( tasks ) }
end

function tasks . encode ( value ) 
return json . encode ( value )
end

tasks . targetConfig = targetConfig

local __nuppExportValue= tasks ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.tasks"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.tasks"]=__nuppExports;return __nuppExports