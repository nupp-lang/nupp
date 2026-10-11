_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()













local hash = require ( "nupp.compiler.hash" )
local process = require ( "nupp.compiler.process" )
local fs = require ( "nupp.compiler.fs" )
local deps = require ( "nupp.tools.build.deps" )
local modulesMod = require ( "nupp.tools.build.modules" )

local normalize , join = fs . normalize , fs . join
local dirname , basename = fs . dirname , fs . basename
local readFile , writeFile = fs . readFile , fs . writeFile
local expandGlob = deps . expandGlob
local resourceOutput = modulesMod . resourceOutput

local package_ = __nuppNew(0,8)




local function interpolate ( format , ... ) 
return string . format ( format , ... )
end

local function stringArray ( values ) 
local quoted = { }
for _ , value in ipairs ( values or { } ) do
quoted [ # quoted + 1 ] = interpolate ( "%q" , value )
end

return "{" .. table . concat ( quoted , "," ) .. "}"
end



local hostAbiVersion = 1















local function longString ( text ) 


if text : find ( "\13" , 1 , true ) or text : find ( "\26" , 1 , true ) then
local quoted = interpolate ( "%q" , text )
return ( quoted : gsub ( "\26" , "\\026" ) )
end
local level = 0
for closing in text : gmatch ( "%]=*%]" ) do
level = math . max ( level , # closing - 2 + 1 )
end
for opening in text : gmatch ( "%[=*%[" ) do
level = math . max ( level , # opening - 2 + 1 )
end
local equals = ("=") : rep ( level )

return "[" .. equals .. "[\n" .. text .. "]" .. equals .. "]"
end


local function entryModule ( root , outDir , target ) 
local mainName = "nupp.tools.main"
local entries = target . entries or { }
if entries [ 1 ] and not entries [ 1 ] : match ( "%.nupp$" ) then
mainName = entries [ 1 ]
end

return mainName , join ( root , join ( outDir , mainName : gsub ( "%." , "/" ) .. ".lua" ) )
end



























local function bundleText (
root ,
config ,
target ,
banner ,
modules ,
workerDispatch ,
runtimeModules ,
hostFeatures ,
component ,
builtOutDir
) 



local outDir = builtOutDir or target . outDir or "build"
local mainName , mainPath = entryModule ( root , outDir , target )
local chunks = component
and {
"-- NUPP-COMPONENT 1\n" ,
interpolate (
"return {format=1,hostAbi=%d,entry=%q,layoutTarget=%s,exports=%s,requiredHostFeatures=%s,install=function()\n" ,
1 ,
mainName ,
target . layoutTarget and interpolate ( "%q" , target . layoutTarget ) or "nil" ,
stringArray ( target . exports ) ,
stringArray ( hostFeatures )
) ,
}
or { banner or "" }
local collisionIndex
local installedModules = { }
local sharedModules


= { }
local compilerArtifactBundle = target . kind == "binary" and target . stub == "nupp" and mainName == "nupp.tools.main"
if compilerArtifactBundle then
chunks [ # chunks + 1 ] = "local __nuppCompilerSources = {}\n"
end

local function compilerArtifact ( name ) 
return compilerArtifactBundle
and name : match ( "^nupp%." ) ~= nil
and name : match ( "^nupp%.tools%." ) == nil
and ( name : match ( "^nupp%.compiler%." ) == nil or name : match ( "^nupp%.compiler%.runtime%." ) ~= nil )
end





local reloadModules


= { }

local function addModule ( name , text , shared , patchable ) 
if shared then
sharedModules [ # sharedModules + 1 ] = { name = name , hash = hash . digest ( text ) , }
chunks [
# chunks + 1
] = ("if package.loaded[%q] == nil and package.preload[%q] == nil then\n") : format ( name , name )
else
installedModules [ # installedModules + 1 ] = name
end
if compilerArtifact ( name ) then
chunks [
# chunks + 1
] = ("__nuppCompilerSources[%q] = %s\npackage.preload[%q] = assert(loadstring(__nuppCompilerSources[%q], %q))\n")

: format ( name , longString ( text ) , name , name , "@" .. name )
elseif patchable then




reloadModules [ # reloadModules + 1 ] = { name = name , hash = hash . digest ( text ) , }
chunks [
# chunks + 1
] = ("package.preload[%q] = function(...)\nlocal __nuppReloadOk, __nuppReloadValue = pcall(function(...)\n")

: format ( name )
chunks [ # chunks + 1 ] = text
chunks [
# chunks + 1
] = ("\nend, ...)\nif not __nuppReloadOk then _G.__nuppHotReload.abort(%q) error(__nuppReloadValue, 0) end\n_G.__nuppHotReload.seal(%q)\nreturn __nuppReloadValue\nend\n")


: format ( name , name )
else
chunks [ # chunks + 1 ] = ("package.preload[%q] = function(...)\n") : format ( name )
chunks [ # chunks + 1 ] = text
chunks [ # chunks + 1 ] = "\nend\n"
end
if shared then
chunks [ # chunks + 1 ] = "end\n"
end
end

if hostFeatures then
local selected = { }
for _ , feature in ipairs ( hostFeatures ) do
selected [ feature ] = true
end
chunks [ # chunks + 1 ] = "do\nlocal __nuppHost = rawget(_G, \"__nuppHost\")\n"
chunks [
# chunks + 1
] = ("if type(__nuppHost) ~= \"table\" or __nuppHost.hostAbi ~= %d then error(\"nupp: payload requires host ABI %d\", 0) end\n")


: format ( 1 , 1 )
chunks [ # chunks + 1 ] = "local __nuppHostFeatures = __nuppHost.hostFeatures or {}\n"
for _ , feature in ipairs ( hostFeatures ) do
chunks [
# chunks + 1
] = ("if not __nuppHostFeatures[%q] then error(%q, 0) end\n")

: format ( feature , "nupp: payload requires host feature " .. feature )
end
if not component then
local preloads = {
{ feature = "lpeg" , modules = { "lpeg" } } ,
{ feature = "workers" , modules = { "nupp.workers.native" } } ,
}
for _ , feature in ipairs ( preloads ) do
if not selected [ feature . feature ] then
for _ , moduleName in ipairs ( feature . modules ) do
chunks [ # chunks + 1 ] = ("package.preload[%q] = nil\n") : format ( moduleName )
end
end
end
chunks [ # chunks + 1 ] = "rawset(_G, \"__nuppHost\", nil)\n"
end
chunks [ # chunks + 1 ] = "end\n"
end
if component then
collisionIndex = # chunks + 1
chunks [ collisionIndex ] = ""
end















for _ , rock in ipairs ( deps . rockModules ( root , config , target ) ) do
local text , readErr = readFile ( rock . path )
if not text then
return nil , readErr
end
addModule ( rock . name , text )
end

local built = modules or { }
local names = { }
for name in pairs ( built ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local record = built [ name ]
local path = record . output
if path and ( component or normalize ( path ) ~= normalize ( mainPath ) ) then
local text , readErr = readFile ( path )
if not text then
return nil , readErr
end



addModule (
name ,
text ,
component and record . compilerRuntime ,
component and config . _reload and not record . compilerRuntime
)
end
end





if compilerArtifactBundle then
chunks [ # chunks + 1 ] = "rawset(_G, \"__nuppCompilerModuleArtifacts\", {\n"
for _ , name in ipairs ( names ) do
local record = built [ name ]
if record . output and compilerArtifact ( name ) then
chunks [
# chunks + 1
] = ("[%q] = {source = __nuppCompilerSources[%q], runtimeModules = {") : format ( name , name )
for _ , dependency in ipairs ( record . runtimeModules or { } ) do
chunks [ # chunks + 1 ] = ("%q,") : format ( dependency )
end
chunks [ # chunks + 1 ] = "}, effects = {"
for _ , effect in ipairs ( ( record . effects or { } ) ) do
chunks [ # chunks + 1 ] = ("%q,") : format ( effect )
end
chunks [ # chunks + 1 ] = "}},\n"
end
end
chunks [ # chunks + 1 ] = "})\n"
end






for _ , name in ipairs ( runtimeModules or { } ) do
if built [ name ] == nil and name ~= mainName then
local path = join ( root , join ( outDir , name : gsub ( "%." , "/" ) .. ".lua" ) )
local text , readErr = readFile ( path )
if not text then
return nil , readErr
end
addModule ( name , text , component )
end
end

local moduleDirPath = normalize ( dirname ( mainPath ) )


local namespaceRoot = mainName : find ( "." , 1 , true )
and normalize ( join ( root , join ( outDir , ( mainName : match ( "^[^.]+" ) ) ) ) )
or moduleDirPath
local resources


= { }
local unreachable = { }
local keyed = { }
for _ , resource in ipairs ( target . resources or { } ) do
local pattern
if type ( resource ) == "table" then
pattern = ( resource ) . source
else
pattern = resource
end
for _ , source in ipairs ( expandGlob ( root , pattern ) ) do
local staged = normalize ( join ( root , join ( outDir , resourceOutput ( config , resource , source , root ) ) ) )






local key = nil
if staged : sub ( 1 , # moduleDirPath + 1 ) == moduleDirPath .. "/" then
key = staged : sub ( # moduleDirPath + 1 )
elseif staged : sub ( 1 , # namespaceRoot + 1 ) == namespaceRoot .. "/" then
key = staged : sub ( # namespaceRoot + 1 )
end
if key then
local text , readErr = readFile ( staged )
if not text then
return nil , readErr
end
if keyed [ key ] and keyed [ key ] ~= staged then
return nil , ("resources %s and %s would both be carried as %s") : format ( keyed [ key ] , staged , key )
end
keyed [ key ] = staged
resources [ # resources + 1 ] = { name = key , text = text }
else





unreachable [ # unreachable + 1 ] = staged
end
end
end
table . sort ( resources , function ( a , b ) 
return a . name < b . name
end )
if not component or # resources > 0 then
installedModules [ # installedModules + 1 ] = "nupp.embedded"
chunks [ # chunks + 1 ] = "package.preload[\"nupp.embedded\"] = function()\n"
chunks [ # chunks + 1 ] = "return {\n"
for _ , resource in ipairs ( resources ) do
chunks [ # chunks + 1 ] = ("[%q] = %s,\n") : format ( resource . name , longString ( resource . text ) )
end
chunks [ # chunks + 1 ] = "}\nend\n"
end

local mainText
if not component or built [ mainName ] == nil then
local mainErr
mainText , mainErr = readFile ( mainPath )
if not mainText then
return nil , mainErr
end
end
if component then
if built [ mainName ] == nil then
installedModules [ # installedModules + 1 ] = mainName
chunks [ # chunks + 1 ] = ("package.preload[%q] = function(...)\n") : format ( mainName )
chunks [ # chunks + 1 ] = assert ( mainText )
chunks [ # chunks + 1 ] = "\nend\n"
end

local collision = { "do\nlocal __nuppLoaded = package.loaded\nlocal __nuppPreload = package.preload\n" , }
for _ , name in ipairs ( installedModules ) do
collision [
# collision + 1
] = interpolate (
"if __nuppLoaded[%q] ~= nil or __nuppPreload[%q] ~= nil then error(%q, 0) end\n" ,
name ,
name ,
"nupp: component module collision: " .. name
)
end
collision [
# collision + 1
] = "local __nuppShared = rawget(_G, \"__nuppComponentSharedModules\") or {}\nlocal __nuppSharedHash\n"
for _ , shared in ipairs ( sharedModules ) do
collision [
# collision + 1
] = interpolate (
"__nuppSharedHash = __nuppShared[%q]\nif __nuppSharedHash ~= nil and __nuppSharedHash ~= %q then error(%q, 0) end\nif __nuppSharedHash == nil and (__nuppLoaded[%q] ~= nil or __nuppPreload[%q] ~= nil) then error(%q, 0) end\n"

,
shared . name ,
shared . hash ,
"nupp: component shared module collision: " .. shared . name ,
shared . name ,
shared . name ,
"nupp: component module collision: " .. shared . name
)
end
collision [ # collision + 1 ] = "local __nuppPublic = rawget(_G, \"__nuppComponentExports\") or {}\n"
for _ , name in ipairs ( target . exports or { } ) do
collision [
# collision + 1
] = interpolate (
"if __nuppPublic[%q] then error(%q, 0) end\n" ,
name ,
"nupp: component export collision: " .. name
)
end
collision [ # collision + 1 ] = "rawset(_G, \"__nuppComponentExports\", __nuppPublic)\n"
collision [ # collision + 1 ] = "rawset(_G, \"__nuppComponentSharedModules\", __nuppShared)\n"
for _ , shared in ipairs ( sharedModules ) do
collision [ # collision + 1 ] = interpolate ( "__nuppShared[%q] = %q\n" , shared . name , shared . hash )
end
for _ , name in ipairs ( target . exports or { } ) do
collision [ # collision + 1 ] = interpolate ( "__nuppPublic[%q] = true\n" , name )
end
collision [ # collision + 1 ] = "end\n"
chunks [ assert ( collisionIndex ) ] = table . concat ( collision )

chunks [ # chunks + 1 ] = "local __nuppExports = {}\n"
for _ , name in ipairs ( target . exports or { } ) do
local moduleName , member = name : match ( "^(.*)%.([^.]+)$" )
chunks [
# chunks + 1
] = interpolate (
"__nuppExports[%q] = function(...) local __nuppModule = require(%q); local __nuppCallable = __nuppModule[%q]; if type(__nuppCallable) ~= \"function\" then error(%q, 0) end; return __nuppCallable(...) end\n"


,
name ,
moduleName ,
member ,
"nupp: component export is not callable: " .. name
)
end
if config . _reload then




chunks [ # chunks + 1 ] = "require(\"nupp.runtime.hotreload\")\n"
chunks [
# chunks + 1
] = "local __nuppReload = rawget(_G, \"__nuppComponentReload\") or {}\nrawset(_G, \"__nuppComponentReload\", __nuppReload)\n"

for _ , entry in ipairs ( reloadModules ) do
chunks [ # chunks + 1 ] = interpolate ( "__nuppReload[%q] = %q\n" , entry . name , entry . hash )
end
end
chunks [
# chunks + 1
] = interpolate ( "return {start=function() return require(%q) end,exports=__nuppExports}\nend}\n" , mainName )
elseif workerDispatch then




chunks [ # chunks + 1 ] = ("package.preload[%q] = function(...)\n") : format ( mainName )
chunks [ # chunks + 1 ] = mainText
chunks [ # chunks + 1 ] = "\nend\n"
chunks [ # chunks + 1 ] = "local __nuppEntry = rawget(_G, \"__nuppWorkerEntry\")\n"




chunks [ # chunks + 1 ] = "if __nuppEntry ~= nil then\n"
chunks [ # chunks + 1 ] = "local __nuppServed = require(__nuppEntry)\n"
chunks [ # chunks + 1 ] = "if __nuppEntry == \"nupp.workers\" and type(__nuppServed) == \"table\" then\n"
chunks [ # chunks + 1 ] = "local __nuppServe = rawget(__nuppServed, \"__runScheduler\")\n"
chunks [ # chunks + 1 ] = "if type(__nuppServe) == \"function\" then __nuppServe() end\n"
chunks [ # chunks + 1 ] = "end\n"
chunks [ # chunks + 1 ] = "return __nuppServed\n"
chunks [ # chunks + 1 ] = "end\n"







chunks [ # chunks + 1 ] = ("local __nuppLoaded = package.preload[%q](%q)\n") : format ( mainName , mainName )
chunks [ # chunks + 1 ] = "if __nuppLoaded == nil then return end\n"
chunks [ # chunks + 1 ] = "return __nuppLoaded\n"
else
chunks [ # chunks + 1 ] = mainText
end

return table . concat ( chunks ) , nil , unreachable
end


local function bundleOutput ( root , target , name , builtOutDir ) 
if builtOutDir then
return join ( root , join ( builtOutDir , basename ( target . output or ( name .. ".lua" ) ) ) )
end

return join ( root , target . output or join ( target . outDir or "build" , name .. ".lua" ) )
end


local function componentOutput ( root , target , name , builtOutDir ) 
if builtOutDir then
return join ( root , join ( builtOutDir , basename ( target . output or ( name .. ".nuppc" ) ) ) )
end

return join ( root , target . output or join ( target . outDir or "build" , name .. ".nuppc" ) )
end


local function binaryOutput (
root ,
target ,
name ,
outDir ,
selectedPlatform ,
outDirOverridden
) 
if selectedPlatform then
local suffix = require ( "nupp.tools.build.platform" ) . executableSuffix ( selectedPlatform )
if outDirOverridden then
return join ( root , join ( outDir , join ( name , join ( selectedPlatform , name .. suffix ) ) ) )
end
local configured = target . platformOutputs and target . platformOutputs [ selectedPlatform ]
return join ( root , configured or join ( outDir , join ( name , join ( selectedPlatform , name .. suffix ) ) ) )
end

local hostKey = require ( "nupp.tools.build.platform" ) . hostKey ( )
local hostSuffix = hostKey and require ( "nupp.tools.build.platform" ) . executableSuffix ( hostKey ) or ""













if target . output then
local spelled = tostring ( target . output )
local named = spelled : match ( "[^/\\]*$" ) or spelled
if hostSuffix ~= "" and not named : find ( "." , 1 , true ) then
spelled = spelled .. hostSuffix
end
if outDirOverridden then
spelled = join ( outDir , basename ( spelled ) )
end

return join ( root , spelled )
end

return join ( root , join ( outDir , name .. hostSuffix ) )
end




local PAYLOAD_MAGIC = "NUPPLOAD"
local PAYLOAD_VERSION = 1
local TRAILER_LENGTH = 48









local PAYLOAD_FLAG_BYTECODE = 1


local function littleEndian ( value , width ) 
local bytes = { }
for index = 1 , width do
bytes [ index ] = string . char ( value % 256 )
value = math . floor ( value / 256 )
end

return table . concat ( bytes )
end

local function integerAt ( text , offset , width ) 
if offset < 0 or offset + width > # text then
return nil
end
local value = 0
for index = width - 1 , 0 , -1 do
value = value * 256 + text : byte ( offset + index + 1 )
end

return value
end

local function replaceAt ( text , offset , replacement ) 
return text : sub ( 1 , offset ) .. replacement .. text : sub ( offset + # replacement + 1 )
end




local function sizeMachOLinkedit ( text ) 
if text : sub ( 1 , 4 ) ~= "销睨" then
return text
end
local commands = integerAt ( text , 16 , 4 )
local commandBytes = integerAt ( text , 20 , 4 )
if not commands or not commandBytes or 32 + commandBytes > # text then
return nil , "cannot stamp malformed arm64 Mach-O load commands"
end
local cursor = 32
for _ = 1 , commands do
local kind = integerAt ( text , cursor , 4 )
local length = integerAt ( text , cursor + 4 , 4 )
if not kind or not length or length < 8 or cursor + length > 32 + commandBytes then
return nil , "cannot stamp malformed arm64 Mach-O load command"
end
if kind == 25 and text : sub ( cursor + 9 , cursor + 24 ) : match ( "^__LINKEDIT" ) then
local fileOffset = integerAt ( text , cursor + 40 , 8 )
local vmSize = integerAt ( text , cursor + 32 , 8 )
if not fileOffset or not vmSize or fileOffset > # text then
return nil , "cannot stamp malformed arm64 Mach-O __LINKEDIT segment"
end


local fileSize = # text - fileOffset

local mapped = math . max ( vmSize , math . ceil ( fileSize / 16384 ) * 16384 )
text = replaceAt ( text , cursor + 32 , littleEndian ( mapped , 8 ) )

return replaceAt ( text , cursor + 48 , littleEndian ( fileSize , 8 ) )
end
cursor = cursor + length
end

return text
end




local function unsignedMachOStub ( text ) 
if text : sub ( 1 , 4 ) ~= "销睨" then
return text
end
local commands = integerAt ( text , 16 , 4 )
local commandBytes = integerAt ( text , 20 , 4 )
if not commands or not commandBytes or 32 + commandBytes > # text then
return nil , "cannot stamp malformed arm64 Mach-O load commands"
end
local cursor = 32
local signatureAt
local signatureSize
local signatureCommand
local signatureCommandSize
for _ = 1 , commands do
local kind = integerAt ( text , cursor , 4 )
local length = integerAt ( text , cursor + 4 , 4 )
if not kind or not length or length < 8 or cursor + length > 32 + commandBytes then
return nil , "cannot stamp malformed arm64 Mach-O load command"
end
if kind == 29 then
signatureAt = integerAt ( text , cursor + 8 , 4 )
signatureSize = integerAt ( text , cursor + 12 , 4 )
signatureCommand , signatureCommandSize = cursor , length
do break end
end
cursor = cursor + length
end
if not signatureCommand then
return text
end
if not signatureAt or not signatureSize or signatureAt + signatureSize ~= # text then
return nil , "cannot stamp a Mach-O whose code signature is not its final blob"
end
local foundCommand = assert ( signatureCommand )
local foundCommandSize = assert ( signatureCommandSize )
local loadCommands = text : sub ( 33 , 32 + commandBytes )
local relative = foundCommand - 32
loadCommands = loadCommands : sub (
1 ,
relative
) .. loadCommands : sub ( relative + foundCommandSize + 1 ) .. ("\0") : rep ( foundCommandSize )
text = replaceAt ( text , 16 , littleEndian ( commands - 1 , 4 ) )
text = replaceAt ( text , 20 , littleEndian ( commandBytes - foundCommandSize , 4 ) )
text = replaceAt ( text , 32 , loadCommands )
text = text : sub ( 1 , signatureAt )

return sizeMachOLinkedit ( text )
end




local function stampBinary ( stubText , payload , selectedPlatform , flags ) 
local macTarget = selectedPlatform == "aarch64-apple-darwin"
or ( selectedPlatform == nil and jit . os == "OSX" and stubText : sub ( 1 , 4 ) == "销睨" )
if macTarget then
local unsigned , unsignedErr = unsignedMachOStub ( stubText )
if not unsigned then
return nil , unsignedErr
end
stubText = unsigned
end
local offset = # stubText
local trailer = "NUPPLOAD" .. littleEndian (
1 ,
4
) .. littleEndian (
flags or 0 ,
4
) .. littleEndian (
offset ,
8
) .. littleEndian ( # payload , 8 ) .. hash . trailerDigest ( payload ) .. littleEndian ( 48 , 8 )
assert ( # trailer == 48 , "the trailer is a fixed size" )

local stamped = stubText .. payload .. trailer
if macTarget then
return sizeMachOLinkedit ( stamped )
end

return stamped
end

local function tarField ( value , width ) 
assert ( # value < width , "tar field fits its fixed width" )
return value .. ("\0") : rep ( width - # value )
end



local function posixArchive ( output , text ) 
local name = fs . basename ( output )
if # name >= 100 then
return nil , "cannot archive " .. output .. ": executable name exceeds the tar header limit"
end
local parts = {
tarField ( name , 100 ) ,
"0000755\0" ,
"0000000\0" ,
"0000000\0" ,
("%011o\0") : format ( # text ) ,
"00000000000\0" ,
"        " ,
"0" ,
("\0") : rep ( 100 ) ,
"ustar\0" ,
"00" ,
("\0") : rep ( 32 ) ,
("\0") : rep ( 32 ) ,
("\0") : rep ( 8 ) ,
("\0") : rep ( 8 ) ,
("\0") : rep ( 155 ) ,
("\0") : rep ( 12 ) ,
}
local header = table . concat ( parts )
assert ( # header == 512 , "tar header is one block" )
local checksum = 0
for index = 1 , # header do
checksum = checksum + header : byte ( index )
end
local checksumField = ("%06o\0 ") : format ( checksum )
header = header : sub ( 1 , 148 ) .. checksumField .. header : sub ( 157 )
local padding = ( 512 - ( # text % 512 ) ) % 512
local archive = output .. ".tar"
local written , writeErr = writeFile ( archive , header .. text .. ("\0") : rep ( padding ) .. ("\0") : rep ( 1024 ) )
if not written then
return nil , tostring ( writeErr )
end

return archive
end






























local function payloadBytes ( text , selectedPlatform ) 
local hostKey = require ( "nupp.tools.build.platform" ) . hostKey ( )
if selectedPlatform ~= nil and selectedPlatform ~= hostKey then
return text , 0
end
local chunk , loadErr = loadstring ( text , "=nupp-payload" )
if not chunk then
return nil , nil , "the bundle did not compile: " .. tostring ( loadErr )
end
local ok , dumped = pcall ( string . dump , chunk , "ds" )
if not ok then
return nil , nil , "the bundle did not dump: " .. tostring ( dumped )
end

return dumped , 1
end







local function stampFile (
output ,
stubText ,
payload ,
selectedPlatform ,
flags
) 
local stampedText , stampErr = stampBinary ( stubText , payload , selectedPlatform , flags )
if not stampedText then
return nil , stampErr
end
local written , writeErr = writeFile ( output , stampedText )
if not written then
return nil , tostring ( writeErr )
end
local posixTarget = selectedPlatform == nil or require ( "nupp.tools.build.platform" ) . isPosix ( selectedPlatform )
if posixTarget and jit . os ~= "Windows" then
local code , chmodErr = process . capture ( { "chmod" , "+x" , output } )
if code ~= 0 then
return nil , "cannot make " .. output .. " executable: " .. tostring ( chmodErr )
end
end





if selectedPlatform == nil and jit . os == "OSX" and stubText : sub ( 1 , 4 ) == "销睨" then
local code , signErr = process . capture ( {
"codesign" ,
"--force" ,
"--sign" ,
"-" ,
"--identifier" ,
"org.nupp.binary" ,
output
} )
if code ~= 0 then
return nil , "cannot ad-hoc sign " .. output .. ": " .. tostring ( signErr )
end
end

local archive
if selectedPlatform and posixTarget then
local archiveErr
archive , archiveErr = posixArchive ( output , stampedText )
if not archive then
return nil , archiveErr
end
end

return true , nil , archive
end

package_ . bundleText = bundleText
package_ . bundleOutput = bundleOutput
package_ . componentOutput = componentOutput
package_ . binaryOutput = binaryOutput
package_ . stampFile = stampFile
package_ . payloadBytes = payloadBytes
package_ . payloadFlagBytecode = 1
package_ . hostAbiVersion = 1

local __nuppExportValue= package_ ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.package"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.package"]=__nuppExports;return __nuppExports