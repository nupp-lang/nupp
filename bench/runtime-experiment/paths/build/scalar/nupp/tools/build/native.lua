_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local envMod = require ( "nupp.compiler.project.env" )
local native = require ( "nupp.compiler.native" )
local check = require ( "nupp.compiler.check" )
local parser = require ( "nupp.compiler.syntax.parser" )
local fs = require ( "nupp.compiler.fs" )
local process = require ( "nupp.compiler.process" )
local deps = require ( "nupp.tools.build.deps" )

local stage = { }

local join = fs . join
local windows = package . config : sub ( 1 , 1 ) == "\\"




function stage . sourceEffects ( source , filename , env ) 
local parsed = parser . parse ( source , filename )
if # parsed . errors > 0 then
return { }
end
check . check ( parsed , filename , env , { strict = false } )

return parsed . effects or { }
end







local function driven ( compilerRoot , what , features ) 
local driver = join ( compilerRoot , "scripts/toolchain" )



local argv = windows and { "sh.exe" , driver , what , table . concat ( features , "," ) }
or { driver , what , table . concat ( features , "," ) }
local code , text = process . capture ( argv )
if code ~= 0 then
return nil , text
end
local answer = nil
for line in text : gmatch ( "[^\13\n]+" ) do
if line : match ( "%S" ) then
answer = line
end
end
if not answer then
return nil , "the toolchain driver built " .. what .. " but named no file"
end

return answer , ""
end


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
for effect in pairs ( stage . sourceEffects ( source , module . path , env ) ) do
resolved [ effect ] = true
end
end
end

return resolved
end

function stage . resolve ( effects , overrides ) 
return native . resolve ( effects , overrides )
end



function stage . hostStub ( root , outDir , target , effects ) 
if target . stub ~= "nupp" then
return target . stub
end
if target . platforms then
local required = native . requiredHostFeatureNames ( effects )
local stubs = require ( "nupp.tools.build.stubs" )
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
return nil , "the compiler-owned Nupp stub needs compiler source; use a source checkout or name a prebuilt stub path"

end
local featureNames = native . hostFeatureNames ( effects )
local built , problem = driven ( compilerRoot , "host" , featureNames )
if not built then
return nil , "cannot build the compiler-owned Nupp host:\n" .. problem
end

return built
end




function stage . linkHost (
root ,
target ,
effects ,
output ,
archives ,
flags
) 
local selected = target . layoutTarget
local host = require ( "nupp.tools.build.platform" ) . hostKey ( )
local aotllvm = require ( "nupp.tools.build.aotllvm" )
local compilerRoot = envMod . compilerRoot ( )
local featureNames = native . hostFeatureNames ( effects )
local linked = selected or host
if linked == nil then
return nil , "standalone native linking needs a target platform"
end
if require ( "nupp.compiler.aot.llvm.profile" ) . of ( linked ) == nil then
return nil , "standalone native linking has no link kit for " .. tostring ( linked )
end



local available , availableErr = aotllvm . selected ( )
if available ~= true then
return nil , tostring ( availableErr )
end
local build = nil
if compilerRoot ~= nil and linked == host then
build = function ( ) 
return driven ( compilerRoot , "kit" , featureNames )
end
end
local kit , kitErr = require ( "nupp.tools.build.kits" ) . resolve ( linked , featureNames , build )
if kit == nil then
return nil , kitErr
end
local linkErr = aotllvm . linkStandalone ( kit , output , archives , flags )
if linkErr ~= nil then
return nil , linkErr
end

return output , nil
end

local libraryFile = deps . sharedLibraryName


function stage . build (
root ,
outDir ,
effects ,
selectedPlatform ,
availableOutputs ,
standalone
) 
local outputs = { }
local providers





= { }
local providerKeys = { }
for _ , feature in ipairs ( native . features ( effects ) ) do
if feature . provider then
if standalone and feature . host then


goto continue
end
if standalone and not feature . host then
return nil , "standalone binary needs sidecar-only native feature "
.. feature . name
.. "; no static host implementation exists"
end
if selectedPlatform and feature . host then


goto continue
end
if selectedPlatform and not feature . host then
return nil , ("binary target %s needs sidecar-only native feature %s; no %s provider artifact exists")

: format ( tostring ( selectedPlatform ) , feature . name , tostring ( selectedPlatform ) )
end
local libraryName = feature . library
local driver = feature . providerDriver or "native"
local key = driver .. "\0" .. feature . provider .. "\0" .. libraryName
local provider = providers [ key ]
if not provider then
provider = {
provider = feature . provider ,
driver = driver ,
library = libraryName ,
names = { } ,
providerFeatures = { } ,
}
providers [ key ] = provider
providerKeys [ # providerKeys + 1 ] = key
end
provider . names [ # provider . names + 1 ] = feature . name
if feature . providerFeature then
provider . providerFeatures [ # provider . providerFeatures + 1 ] = feature . providerFeature
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
table . sort ( provider . providerFeatures )
local built , problem = driven ( compilerRoot , provider . driver , provider . providerFeatures )
if not built then
return nil , ("cannot build native facilities %s:\n%s") : format ( table . concat ( provider . names , ", " ) , problem )
end
local filename = libraryFile ( provider . library )



local staged = jit . os == "Windows" and filename or provider . library
local output = join ( root , join ( outDir , join ( "lib" , staged ) ) )
local copied , err = fs . copyFile ( built , output )
if not copied then
return nil , ("cannot stage native facilities %s: %s")

: format ( table . concat ( provider . names , ", " ) , tostring ( err ) )
end
outputs [ output ] = true
end






for _ , feature in ipairs ( native . features ( effects ) ) do
local moduleName = feature . runtimeModule
if moduleName then
local relative = ( moduleName : gsub ( "%." , "/" ) ) .. ".lua"
local output = join ( root , join ( outDir , relative ) )
if not availableOutputs or not availableOutputs [ output ] then
if not compilerRoot then
return nil , ("the %s runtime was not staged from the installed compiler") : format ( feature . name )
end
local built = join ( compilerRoot , join ( "build" , relative ) )
local copied , err = fs . copyFile ( built , output )
if not copied then
return nil , ("cannot stage the %s runtime: %s") : format ( feature . name , tostring ( err ) )
end
end
outputs [ output ] = true
end
end

return outputs
end

local __nuppExportValue= stage ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.native"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.native"]=__nuppExports;return __nuppExports