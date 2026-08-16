_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON);








local json = require ( "cjson" ) . new ( )
local cache = require ( "nupp.compiler.build.cache" )
local manifest = require ( "nupp.compiler.build.manifest" )

local jsonArray = cache . jsonArray

local tasks = { }
































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
return require ( "nupp.compiler.doc" ) . defaultOutDir ( target . format or "site" )
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




all = target . all ,
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

if not buildOnly and config . test then
local name = actionName ( "test" )
tasks [
# tasks + 1
] = {
name = name ,
default = false ,
category = "project" ,
description = "Build and run the configured test command" ,
kind = "test" ,
buildTarget = config . test . build ,
argv = copyStrings ( config . test . argv ) ,
env = config . test . env ,
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
bootstrap = config . selfHost . bootstrap or "bootstrap/nupp.lua" ,
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








function tasks . describe ( root , requested , opts )
local config , err = manifest . load ( root or "." )
if not config then
return nil , err
end
local build = config . build
if not build then
return nil , "nupp: build is not configured"
end
local tasks , defaultName = configuredTasks ( config , opts and opts . buildOnly )
if requested then
for _ , task in ipairs ( tasks ) do
if task . name == requested then
return task
end
end
return nil , "nupp: unknown project task " .. requested
end

return { default = defaultName , tasks = jsonArray ( tasks ) }
end

function tasks . encodeJson ( value )
return json . encode ( value )
end

tasks . targetConfig = targetConfig
tasks . configured = configuredTasks

return tasks
