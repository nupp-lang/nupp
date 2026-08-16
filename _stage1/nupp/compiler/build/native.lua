_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local envMod = require ( "nupp.compiler.env" )
local native = require ( "nupp.compiler.native" )
local fs = require ( "nupp.compiler.fs" )
local process = require ( "nupp.compiler.build.process" )
local deps = require ( "nupp.compiler.build.deps" )

local stage = { }

local join = fs . join


function stage . dependencyEffects (
root ,
config ,
target ,
effects
)
local resolved = { }
for effect in pairs ( effects or { } ) do
resolved [ effect ] = true
end
local env = envMod . new ( root , { config = config } )
for _ , module in ipairs ( deps . rockModules ( root , config , target ) ) do
local source = fs . readFile ( module . path )
if source then
for effect in pairs ( native . sourceEffects ( source , module . path , env ) ) do
resolved [ effect ] = true
end
end
end

return resolved
end

function stage . resolve ( effects , overrides )
return native . resolve ( effects , overrides )
end



function stage . hostStub (
root ,
outDir ,
target ,
effects
)
if target . stub ~= "nupp" then
return target . stub
end
if target . platforms then
local required = { }
for _ , feature in ipairs ( native . features ( effects ) ) do
if feature . host then
required [ # required + 1 ] = feature . host
end
end
table . sort ( required )
local stubs = require ( "nupp.compiler.build.stubs" )
local record , recordErr = target . _stubRecord , nil
if not record then
record , recordErr = stubs . record ( assert ( target . layoutTarget ) )
end
if not record then
return nil , recordErr
end
return stubs . acquire ( root , record , required )
end
local compilerRoot = envMod . compilerRoot ( )
if not compilerRoot then
return nil , "the compiler-owned Nupp stub needs compiler source; "
.. "use a source checkout or name a prebuilt stub path"
end
local featureNames = { }
for _ , feature in ipairs ( native . features ( effects ) ) do
if feature . host then
featureNames [ # featureNames + 1 ] = feature . host
end
end
table . sort ( featureNames )
local targetDir = join ( root , join ( outDir , "native/host" ) )
local argv = {
"cargo" ,
"build" ,
"--release" ,
"--no-default-features" ,
"--manifest-path" ,
join ( compilerRoot , "host/Cargo.toml" ) ,
"--target-dir" ,
targetDir
}
if # featureNames > 0 then
argv [ # argv + 1 ] = "--features"
argv [ # argv + 1 ] = table . concat ( featureNames , "," )
end
local code , text = process . capture ( argv )
if code ~= 0 then
return nil , "cannot build the compiler-owned Nupp host:\n" .. text
end
local executable = jit . os == "Windows" and "nupp-host.exe" or "nupp-host"

return join ( targetDir , join ( "release" , executable ) )
end

local function libraryFile ( name )
if jit . os == "Windows" then
return name .. ".dll"
end
if jit . os == "OSX" then
return "lib" .. name .. ".dylib"
end

return "lib" .. name .. ".so"
end


function stage . build (
root ,
outDir ,
effects ,
selectedPlatform
)
local outputs = { }
local providers




= { }
local providerKeys = { }
for _ , feature in ipairs ( native . features ( effects ) ) do
if feature . cargo then
if selectedPlatform and feature . host then


goto continue
end
if selectedPlatform and not feature . host then
return nil , (
"binary target %s needs sidecar-only native feature %s; no %s provider artifact exists"
) : format ( tostring ( selectedPlatform ) , feature . name , tostring ( selectedPlatform ) )
end
local libraryName = feature . library
local key = feature . cargo .. "\0" .. libraryName
local provider = providers [ key ]
if not provider then
provider = { cargo = feature . cargo , library = libraryName , names = { } , cargoFeatures = { } }
providers [ key ] = provider
providerKeys [ # providerKeys + 1 ] = key
end
provider . names [ # provider . names + 1 ] = feature . name
if feature . cargoFeature then
provider . cargoFeatures [ # provider . cargoFeatures + 1 ] = feature . cargoFeature
end
end
:: continue ::
end
local compilerRoot = envMod . compilerRoot ( )
table . sort ( providerKeys )
for _ , key in ipairs ( providerKeys ) do
local provider = assert ( providers [ key ] )
if not compilerRoot then
return nil , "native facilities need compiler source; use a source checkout to build this target"
end
table . sort ( provider . names )
table . sort ( provider . cargoFeatures )
local targetDir = join ( root , join ( outDir , "native/" .. provider . library ) )
local argv = {
"cargo" ,
"build" ,
"--release" ,
"--manifest-path" ,
join ( compilerRoot , provider . cargo ) ,
"--target-dir" ,
targetDir
}
if # provider . cargoFeatures > 0 then
argv [ # argv + 1 ] = "--no-default-features"
argv [ # argv + 1 ] = "--features"
argv [ # argv + 1 ] = table . concat ( provider . cargoFeatures , "," )
end
local code , captured = process . capture ( argv )
if code ~= 0 then
return nil , ( "cannot build native facilities %s:\n%s" ) : format ( table . concat ( provider . names , ", " ) , captured )
end
local filename = libraryFile ( provider . library )
local built = join ( targetDir , join ( "release" , filename ) )



local staged = jit . os == "Windows" and filename or provider . library
local output = join ( root , join ( outDir , join ( "lib" , staged ) ) )
local copied , err = fs . copyFile ( built , output )
if not copied then
return nil , (
"cannot stage native facilities %s: %s"
) : format ( table . concat ( provider . names , ", " ) , tostring ( err ) )
end
outputs [ output ] = true
end




for _ , feature in ipairs ( native . features ( effects ) ) do
local moduleName = feature . runtimeModule
if moduleName then
if not compilerRoot then
return nil , (
"the %s runtime needs compiler source; use a source checkout to build this target"
) : format ( feature . name )
end
local relative = ( moduleName : gsub ( "%." , "/" ) ) .. ".lua"
local built = join ( compilerRoot , join ( "build" , relative ) )
local output = join ( root , join ( outDir , relative ) )
local copied , err = fs . copyFile ( built , output )
if not copied then
return nil , ( "cannot stage the %s runtime: %s" ) : format ( feature . name , tostring ( err ) )
end
outputs [ output ] = true
end
end

return outputs
end

return stage
