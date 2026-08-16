_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local hash = require ( "nupp.compiler.build.hash" )
local process = require ( "nupp.compiler.build.process" )
local fs = require ( "nupp.compiler.fs" )
local deps = require ( "nupp.compiler.build.deps" )
local modulesMod = require ( "nupp.compiler.build.modules" )

local normalize , join = fs . normalize , fs . join
local dirname = fs . dirname
local readFile , writeFile = fs . readFile , fs . writeFile
local expandGlob = deps . expandGlob
local resourceOutput = modulesMod . resourceOutput

local package_ = { }



local hostAbiVersion = 1












local function longString ( text )
local level = 0
for closing in text : gmatch ( "%]=*%]" ) do
level = math . max ( level , # closing - 2 + 1 )
end
local equals = ( "=" ) : rep ( level )

return "[" .. equals .. "[\n" .. text .. "]" .. equals .. "]"
end


local function entryModule ( root , outDir , target )
local mainName = "nupp.compiler.main"
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
hostFeatures
)
local outDir = target . outDir or "build"
local mainName , mainPath = entryModule ( root , outDir , target )
local chunks = { banner or "" }

if hostFeatures then
local selected = { }
for _ , feature in ipairs ( hostFeatures ) do
selected [ feature ] = true
end
chunks [ # chunks + 1 ] = "do\nlocal __nuppHost = rawget(_G, \"__nuppHost\")\n"
chunks [
# chunks + 1
] = (
"if type(__nuppHost) ~= \"table\" or __nuppHost.hostAbi ~= %d then "
.. "error(\"nupp: payload requires host ABI %d\", 0) end\n"
) : format ( hostAbiVersion , hostAbiVersion )
chunks [ # chunks + 1 ] = "local __nuppHostFeatures = __nuppHost.hostFeatures or {}\n"
for _ , feature in ipairs ( hostFeatures ) do
chunks [
# chunks + 1
] = (
"if not __nuppHostFeatures[%q] then error(%q, 0) end\n"
) : format ( feature , "nupp: payload requires host feature " .. feature )
end
local preloads = {
{ feature = "cjson" , modules = { "cjson" , "cjson.safe" } } ,
{ feature = "lpeg" , modules = { "lpeg" } } ,
{ feature = "lua-utf8" , modules = { "lua-utf8" } } ,
{ feature = "workers" , modules = { "nupp.workers.native" } } ,
}
for _ , feature in ipairs ( preloads ) do
if not selected [ feature . feature ] then
for _ , moduleName in ipairs ( feature . modules ) do
chunks [ # chunks + 1 ] = ( "package.preload[%q] = nil\n" ) : format ( moduleName )
end
end
end
chunks [ # chunks + 1 ] = "rawset(_G, \"__nuppHost\", nil)\nend\n"
end















for _ , rock in ipairs ( deps . rockModules ( root , config , target ) ) do
local text , readErr = readFile ( rock . path )
if not text then
return nil , readErr
end
chunks [ # chunks + 1 ] = ( "package.preload[%q] = function(...)\n" ) : format ( rock . name )
chunks [ # chunks + 1 ] = text
chunks [ # chunks + 1 ] = "\nend\n"
end

local built = modules or { }
local names = { }
for name in pairs ( built ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local path = ( built [ name ] ) . output
if path and normalize ( path ) ~= normalize ( mainPath ) then
local text , readErr = readFile ( path )
if not text then
return nil , readErr
end
chunks [ # chunks + 1 ] = ( "package.preload[%q] = function(...)\n" ) : format ( name )
chunks [ # chunks + 1 ] = text
chunks [ # chunks + 1 ] = "\nend\n"
end
end






for _ , name in ipairs ( runtimeModules or { } ) do
if built [ name ] == nil and name ~= mainName then
local path = join ( root , join ( outDir , name : gsub ( "%." , "/" ) .. ".lua" ) )
local text , readErr = readFile ( path )
if not text then
return nil , readErr
end
chunks [ # chunks + 1 ] = ( "package.preload[%q] = function(...)\n" ) : format ( name )
chunks [ # chunks + 1 ] = text
chunks [ # chunks + 1 ] = "\nend\n"
end
end

local moduleDirPath = normalize ( dirname ( mainPath ) )
local resources , unreachable = { } , { }
for _ , resource in ipairs ( target . resources or { } ) do
local pattern
if type ( resource ) == "table" then
pattern = ( resource ) . source
else
pattern = resource
end
for _ , source in ipairs ( expandGlob ( root , pattern ) ) do
local staged = normalize ( join ( root , join ( outDir , resourceOutput ( config , resource , source , root ) ) ) )
if staged : sub ( 1 , # moduleDirPath + 1 ) == moduleDirPath .. "/" then
local text , readErr = readFile ( staged )
if not text then
return nil , readErr
end
resources [ # resources + 1 ] = { name = staged : sub ( # moduleDirPath + 1 ) , text = text }
else





unreachable [ # unreachable + 1 ] = staged
end
end
end
table . sort ( resources , function ( a , b )
return a . name < b . name
end )
chunks [ # chunks + 1 ] = 'package.preload["nupp.embedded"] = function()\n'
chunks [ # chunks + 1 ] = "return {\n"
for _ , resource in ipairs ( resources ) do
chunks [ # chunks + 1 ] = ( "[%q] = %s,\n" ) : format ( resource . name , longString ( resource . text ) )
end
chunks [ # chunks + 1 ] = "}\nend\n"

local mainText , mainErr = readFile ( mainPath )
if not mainText then
return nil , mainErr
end
if workerDispatch then




chunks [ # chunks + 1 ] = ( "package.preload[%q] = function(...)\n" ) : format ( mainName )
chunks [ # chunks + 1 ] = mainText
chunks [ # chunks + 1 ] = "\nend\n"
chunks [ # chunks + 1 ] = "local __nuppEntry = rawget(_G, \"__nuppWorkerEntry\")\n"
chunks [ # chunks + 1 ] = ( "return require(__nuppEntry or %q)\n" ) : format ( mainName )
else
chunks [ # chunks + 1 ] = mainText
end

return table . concat ( chunks ) , nil , unreachable
end


local function bundleOutput ( root , target , name )
local outDir = target . outDir or "build"
return join ( root , target . output or join ( outDir , name .. ".lua" ) )
end


local function binaryOutput (
root ,
target ,
name ,
outDir ,
selectedPlatform
)
if selectedPlatform then
local configured = target . platformOutputs and target . platformOutputs [ selectedPlatform ]
local suffix = require ( "nupp.compiler.build.platform" ) . executableSuffix ( selectedPlatform )
return join ( root , configured or join ( outDir , join ( name , join ( selectedPlatform , name .. suffix ) ) ) )
end

return join ( root , target . output or join ( outDir , name ) )
end




local PAYLOAD_MAGIC = "NUPPLOAD"
local PAYLOAD_VERSION = 1
local TRAILER_LENGTH = 48


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
for index = width - 1 , 0 , - 1 do
value = value * 256 + text : byte ( offset + index + 1 )
end

return value
end

local function replaceAt ( text , offset , replacement )
return text : sub ( 1 , offset ) .. replacement .. text : sub ( offset + # replacement + 1 )
end




local function sizeMachOLinkedit ( text )
if text : sub ( 1 , 4 ) ~= "\207\250\237\254" then
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
if kind == 0x19 and text : sub ( cursor + 9 , cursor + 24 ) : match ( "^__LINKEDIT" ) then
local fileOffset = integerAt ( text , cursor + 40 , 8 )
if not fileOffset or fileOffset > # text then
return nil , "cannot stamp malformed arm64 Mach-O __LINKEDIT segment"
end
return replaceAt ( text , cursor + 48 , littleEndian ( # text - fileOffset , 8 ) )
end
cursor = cursor + length
end

return text
end




local function unsignedMachOStub ( text )
if text : sub ( 1 , 4 ) ~= "\207\250\237\254" then
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
if kind == 0x1d then
signatureAt = integerAt ( text , cursor + 8 , 4 )
signatureSize = integerAt ( text , cursor + 12 , 4 )
signatureCommand , signatureCommandSize = cursor , length
break
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
) .. loadCommands : sub ( relative + foundCommandSize + 1 ) .. ( "\0" ) : rep ( foundCommandSize )
text = replaceAt ( text , 16 , littleEndian ( commands - 1 , 4 ) )
text = replaceAt ( text , 20 , littleEndian ( commandBytes - foundCommandSize , 4 ) )
text = replaceAt ( text , 32 , loadCommands )
text = text : sub ( 1 , signatureAt )

return sizeMachOLinkedit ( text )
end


local function digestPrefix ( hex , count )
local bytes = { }
for index = 1 , count do


local byte = assert ( tonumber ( hex : sub ( index * 2 - 1 , index * 2 ) , 16 ) , "a digest is hexadecimal" )
bytes [ index ] = string . char ( byte )
end

return table . concat ( bytes )
end




local function stampBinary ( stubText , payload , selectedPlatform )
local macTarget = selectedPlatform == "aarch64-apple-darwin" or (
selectedPlatform == nil and jit . os == "OSX" and stubText : sub ( 1 , 4 ) == "\207\250\237\254"
)
if macTarget then
local unsigned , unsignedErr = unsignedMachOStub ( stubText )
if not unsigned then
return nil , unsignedErr
end
stubText = unsigned
end
local offset = # stubText
local trailer = PAYLOAD_MAGIC .. littleEndian (
PAYLOAD_VERSION ,
4
) .. littleEndian (
0 ,
4
) .. littleEndian (
offset ,
8
) .. littleEndian ( # payload , 8 ) .. digestPrefix ( hash . sha256 ( payload ) , 8 ) .. littleEndian ( TRAILER_LENGTH , 8 )
assert ( # trailer == TRAILER_LENGTH , "the trailer is a fixed size" )

local stamped = stubText .. payload .. trailer
if macTarget then
return sizeMachOLinkedit ( stamped )
end

return stamped
end

local function tarField ( value , width )
assert ( # value < width , "tar field fits its fixed width" )
return value .. ( "\0" ) : rep ( width - # value )
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
( "%011o\0" ) : format ( # text ) ,
"00000000000\0" ,
"        " ,
"0" ,
( "\0" ) : rep ( 100 ) ,
"ustar\0" ,
"00" ,
( "\0" ) : rep ( 32 ) ,
( "\0" ) : rep ( 32 ) ,
( "\0" ) : rep ( 8 ) ,
( "\0" ) : rep ( 8 ) ,
( "\0" ) : rep ( 155 ) ,
( "\0" ) : rep ( 12 ) ,
}
local header = table . concat ( parts )
assert ( # header == 512 , "tar header is one block" )
local checksum = 0
for index = 1 , # header do
checksum = checksum + header : byte ( index )
end
local checksumField = ( "%06o\0 " ) : format ( checksum )
header = header : sub ( 1 , 148 ) .. checksumField .. header : sub ( 157 )
local padding = ( 512 - ( # text % 512 ) ) % 512
local archive = output .. ".tar"
local written , writeErr = writeFile ( archive , header .. text .. ( "\0" ) : rep ( padding ) .. ( "\0" ) : rep ( 1024 ) )
if not written then
return nil , tostring ( writeErr )
end

return archive
end






local function stampFile (
output ,
stubText ,
payload ,
selectedPlatform
)
local stampedText , stampErr = stampBinary ( stubText , payload , selectedPlatform )
if not stampedText then
return nil , stampErr
end
local written , writeErr = writeFile ( output , stampedText )
if not written then
return nil , tostring ( writeErr )
end
local posixTarget = selectedPlatform == nil or require ( "nupp.compiler.build.platform" ) . isPosix ( selectedPlatform )
if posixTarget and jit . os ~= "Windows" then
local code , chmodErr = process . capture ( { "chmod" , "+x" , output } )
if code ~= 0 then
return nil , "cannot make " .. output .. " executable: " .. tostring ( chmodErr )
end
end





if selectedPlatform == nil and jit . os == "OSX" and stubText : sub ( 1 , 4 ) == "\207\250\237\254" then
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

package_ . longString = longString
package_ . entryModule = entryModule
package_ . bundleText = bundleText
package_ . bundleOutput = bundleOutput
package_ . binaryOutput = binaryOutput
package_ . stampFile = stampFile
package_ . posixArchive = posixArchive
package_ . hostAbiVersion = hostAbiVersion

return package_
