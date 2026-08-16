_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON);










local hash = require ( "nupp.compiler.build.hash" )
local importc = require ( "nupp.compiler.importc" )
local json = require ( "cjson" ) . new ( )
local process = require ( "nupp.compiler.build.process" )
local fs = require ( "nupp.compiler.fs" )
local cache = require ( "nupp.compiler.build.cache" )
local syntax = require ( "nupp.compiler.build.syntax" )

local normalize , join = fs . normalize , fs . join
local dirname , basename = fs . dirname , fs . basename
local readFile , writeFile = fs . readFile , fs . writeFile
local exists , mkdir = fs . exists , fs . mkdir
local copyFile , listFiles = fs . copyFile , fs . listFiles
local stable , hashFiles = cache . stable , cache . hashFiles

local deps = { }
























local function expandGlob ( root , glob )
glob = normalize ( glob )
if not glob : find ( "[*?]" ) then
local path = join ( root , glob )
return exists ( path ) and { path } or { }
end
local prefix = glob : match ( "^(.-)[*?]" ) or "."
prefix = prefix : match ( "^(.*)/" ) or "."
local base = join ( root , prefix )
local isMatch = syntax . glob ( join ( root , glob ) )
local matches = { }
for _ , path in ipairs ( listFiles ( base ) ) do
if isMatch ( path ) then
matches [ # matches + 1 ] = path
end
end

return matches
end

local function sharedLibraryName ( name )
name = name : gsub ( "%-" , "_" )
local osName = ( jit and jit . os or "" ) : lower ( )
if osName == "windows" then
return name .. ".dll"

elseif osName == "osx" then
return "lib" .. name .. ".dylib"
end

return "lib" .. name .. ".so"
end

local function fetchGit ( root , name , source )
if type ( source ) ~= "table" or not source . git then
return root
end
if type ( source . rev ) ~= "string" or source . rev == "" then
return nil , "dependency " .. name .. " requires an exact source.rev"
end
local checkout = join ( root , ".nupp/deps/" .. name )
if not exists ( join ( checkout , ".git/HEAD" ) ) then
mkdir ( dirname ( checkout ) )
local code = process . run ( { "git" , "clone" , source . git , checkout } )
if code ~= 0 then
return nil , "git clone failed for " .. name
end
end
local code , head = process . capture ( { "git" , "rev-parse" , "HEAD" } , { cwd = checkout } )
if code ~= 0 or normalize ( ( head : gsub ( "%s+$" , "" ) ) ) ~= source . rev then
if process . run ( { "git" , "fetch" , "--depth" , "1" , "origin" , source . rev } , { cwd = checkout } ) ~= 0 then
return nil , "git fetch failed for " .. name
end
if process . run ( { "git" , "checkout" , "--detach" , "FETCH_HEAD" } , { cwd = checkout } ) ~= 0 then
return nil , "git checkout failed for " .. name
end
end

return checkout
end

local function dependencyFiles ( base , patterns )
local files = { }
for _ , pattern in ipairs ( patterns or { } ) do
local expanded = expandGlob ( base , pattern )
for _ , path in ipairs ( expanded ) do
files [ # files + 1 ] = path
end
end
table . sort ( files )

return files
end

local function bindingConfig ( dep )
if type ( dep . bindings ) == "table" then
return dep . bindings
end
if dep . header then
return { header = dep . header }
end

return nil
end

local function generateBinding ( root , outDir , name , dep , base , libraryPath , extraCppflags )
local binding = bindingConfig ( dep )
if not binding or not binding . header then
return nil
end
local header = binding . header
if header : sub ( 1 , 1 ) ~= "/" then
header = join ( base , header )
end
local text , warnings = importc . import ( header , {
lib = binding . library or dep . load or libraryPath ,
cc = dep . cc ,
cppflags = extraCppflags or dep . cppflags ,
} )
if not text then
return nil , table . concat ( warnings or { } , "; " )
end
for _ , warning in ipairs ( warnings or { } ) do
io . stderr : write ( "nupp: warning: " .. warning .. "\n" )
end
local output = join ( root , binding . out or join ( outDir , "generated/" .. name .. ".nupp" ) )
local current = readFile ( output )
if current ~= text then
local ok , err = writeFile ( output , text )
if not ok then
return nil , err
end
end

return output
end

local function buildC ( root , outDir , name , dep , previous , childResults )
local base , fetchErr = fetchGit ( root , name , dep . source )
if not base then
return nil , fetchErr
end
if dep . source then
base = join ( base , dep . path or "." )
else
base = join ( root , dep . path or "." )
end
local sources = dependencyFiles ( base , dep . sources or { } )
local nativeInputs = { }
for _ , path in ipairs ( sources ) do
nativeInputs [ # nativeInputs + 1 ] = path
end
for _ , path in ipairs ( dependencyFiles ( base , dep . headers or { } ) ) do
nativeInputs [ # nativeInputs + 1 ] = path
end
local configuredBinding = bindingConfig ( dep )
if configuredBinding and configuredBinding . header then
local header = configuredBinding . header
if header : sub ( 1 , 1 ) ~= "/" then
header = join ( base , header )
end
nativeInputs [ # nativeInputs + 1 ] = header
end
table . sort ( nativeInputs )
local compiler = dep . cc or "cc"
local _ , version = process . capture ( { compiler , "--version" } )
local pkgFlags = { }
if dep . pkgConfig then
local code , flags = process . capture ( { "pkg-config" , "--cflags" , "--libs" , dep . pkgConfig } )
if code ~= 0 then
return nil , "pkg-config failed for " .. dep . pkgConfig .. ": " .. flags
end
local parsed = syntax . shellWords : match ( flags )
if not parsed then
return nil , "pkg-config returned invalid flags for " .. dep . pkgConfig
end
pkgFlags = parsed
end
local key = hash . digest (
stable (
dep
) .. "\0" .. hashFiles (
nativeInputs
) .. "\0" .. version .. "\0" .. stable ( pkgFlags ) .. "\0" .. stable ( childResults )
)
local output = nil
if # sources > 0 then
output = join ( root , dep . out or join ( outDir , "lib/" .. sharedLibraryName ( name ) ) )
if not previous or previous . key ~= key or not exists ( output ) then
mkdir ( dirname ( output ) )
local stagedOutput = output .. ".tmp"
os . remove ( stagedOutput )
local argv = { compiler }
local osName = ( jit and jit . os or "" ) : lower ( )
if osName == "osx" then
argv [ # argv + 1 ] = "-dynamiclib"
elseif osName ~= "windows" then
argv [ # argv + 1 ] = "-shared" ;
argv [ # argv + 1 ] = "-fPIC"
else
argv [ # argv + 1 ] = "-shared"
end
argv [ # argv + 1 ] = "-o" ;
argv [ # argv + 1 ] = stagedOutput
for _ , dir in ipairs ( dep . includeDirs or { } ) do
argv [ # argv + 1 ] = "-I" .. join ( base , dir )
end
for _ , flag in ipairs ( dep . cflags or { } ) do
argv [ # argv + 1 ] = flag
end
for _ , source in ipairs ( sources ) do
argv [ # argv + 1 ] = source
end
for _ , childName in ipairs ( dep . dependencies or { } ) do
local child = childResults and childResults [ childName ]
if child . output then
argv [ # argv + 1 ] = child . output
end
end
for _ , flag in ipairs ( pkgFlags ) do
argv [ # argv + 1 ] = flag
end
for _ , flag in ipairs ( dep . ldflags or { } ) do
argv [ # argv + 1 ] = flag
end
if process . run ( argv ) ~= 0 then
os . remove ( stagedOutput )
return nil , "C build failed for " .. name
end
local binary , binaryErr = readFile ( stagedOutput )
os . remove ( stagedOutput )
if not binary then
return nil , binaryErr
end
local installed , installErr = writeFile ( output , binary )
if not installed then
return nil , installErr
end
end
end
local cppflags = { }
for _ , flag in ipairs ( dep . cppflags or { } ) do
cppflags [ # cppflags + 1 ] = flag
end
for _ , dir in ipairs ( dep . includeDirs or { } ) do
cppflags [ # cppflags + 1 ] = "-I" .. join ( base , dir )
end
for _ , flag in ipairs ( pkgFlags ) do
if flag : match ( "^-I" ) or flag : match ( "^-D" ) then
cppflags [ # cppflags + 1 ] = flag
end
end
local binding , bindingErr = generateBinding (
root ,
outDir ,
name ,
dep ,
base ,
dep . load or output or dep . pkgConfig ,
cppflags
)
if bindingErr then
return nil , bindingErr
end

return { key = key , output = output , binding = binding }
end

local function cargoSourceFiles ( crateDir )
local files = { }
for _ , path in ipairs ( listFiles ( crateDir ) ) do
if path : match (
"%.rs$"
) or basename ( path ) == "Cargo.toml" or basename ( path ) == "Cargo.lock" or path : match ( "build%.rs$" ) then
files [ # files + 1 ] = path
end
end

return files
end

local function buildCargo ( root , outDir , name , dep , previous )
local manifest = join ( root , dep . manifest or join ( dep . path or name , "Cargo.toml" ) )
local crateDir = dirname ( manifest )
local cargo = dep . cargo or "cargo"
local _ , version = process . capture ( { cargo , "--version" } )
local key = hash . digest ( stable ( dep ) .. "\0" .. hashFiles ( cargoSourceFiles ( crateDir ) ) .. "\0" .. version )
local targetDir = join ( root , dep . targetDir or join ( outDir , "cargo/" .. name ) )
local profile = dep . profile or "release"
local crateName = ( dep . library or name ) : gsub ( "%-" , "_" )
local targetPart = dep . target and ( dep . target .. "/" ) or ""
local artifact = dep . artifactPath or join ( targetDir , targetPart .. profile .. "/" .. sharedLibraryName ( crateName ) )
local output = join ( root , dep . out or join ( outDir , "lib/" .. sharedLibraryName ( crateName ) ) )
if not previous or previous . key ~= key or not exists ( output ) then
local argv = { cargo , "build" , "--manifest-path" , manifest , "--target-dir" , targetDir }
if profile == "release" then
argv [ # argv + 1 ] = "--release"
elseif profile ~= "debug" then
argv [ # argv + 1 ] = "--profile" ;
argv [ # argv + 1 ] = profile
end
if dep . target then
argv [ # argv + 1 ] = "--target" ;
argv [ # argv + 1 ] = dep . target
end
if dep . locked ~= false then
argv [ # argv + 1 ] = "--locked"
end
if dep . offline then
argv [ # argv + 1 ] = "--offline"
end
if # ( dep . features or { } ) > 0 then
argv [ # argv + 1 ] = "--features"
argv [ # argv + 1 ] = table . concat ( dep . features , "," )
end
argv [ # argv + 1 ] = "--message-format=json-render-diagnostics"
local cargoCode , cargoOutput = process . capture ( argv , { cwd = root } )
if cargoCode ~= 0 then
io . stderr : write ( cargoOutput )
return nil , "Cargo build failed for " .. name
end
if not dep . artifactPath then
for line in cargoOutput : gmatch ( "[^\r\n]+" ) do
local parsed , message = pcall ( json . decode , line )
if parsed and type (
message
) == "table" and message . reason == "compiler-artifact" and message . target and message . target . name : gsub (
"%-" ,
"_"
) == crateName then
for _ , filename in ipairs ( message . filenames or { } ) do
if filename : match ( "%.so$" ) or filename : match ( "%.dylib$" ) or filename : match ( "%.dll$" ) then
artifact = filename
end
end
end
end
end
if not exists ( artifact ) then
return nil , "Cargo artifact not found: " .. artifact
end
local ok , err = copyFile ( artifact , output )
if not ok then
return nil , err
end
end
local binding = bindingConfig ( dep )
if binding and binding . cbindgen then
local header = binding . header or join ( outDir , "generated/" .. name .. ".h" )
header = join ( root , header )
mkdir ( dirname ( header ) )
local argv = { binding . command or "cbindgen" , "--output" , header }
if process . run ( argv , { cwd = crateDir } ) ~= 0 then
return nil , "cbindgen failed for " .. name
end
binding . header = header
end
local generated , bindingErr = generateBinding ( root , outDir , name , dep , crateDir , dep . load or output )
if bindingErr then
return nil , bindingErr
end

return { key = key , output = output , binding = generated }
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
local _ , printed = process . capture ( windows and { "cmd" , "/d" , "/c" , "cd" } or { "pwd" } )
currentDirectory = normalize ( ( ( printed or "." ) : gsub ( "%s+$" , "" ) ) )
end
if path == "" or path == "." then
return currentDirectory
end

return join ( currentDirectory , path )
end







local function luaDirectory ( dep )
if dep . luaDir then
return dep . luaDir
end
local named = os . getenv ( "NUPP_LUA_DIR" )
if named and named ~= "" then
return named
end
for entry in ( package . cpath .. ";" ) : gmatch ( "([^;]*);" ) do
local prefix = entry : match ( "^(.*)/lib/lua/" )
if prefix and ( exists ( join ( prefix , "include/luajit-2.1/lua.h" ) ) or exists ( join ( prefix , "include/lua.h" ) ) ) then
return prefix
end
end

return nil
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





local function prepended ( current , entries )
current = current or ""
local fresh = { }
for entry in ( entries .. ";" ) : gmatch ( "([^;]*);" ) do
if entry ~= "" and not ( ";" .. current .. ";" ) : find ( ";" .. entry .. ";" , 1 , true ) then
fresh [ # fresh + 1 ] = entry
end
end
if # fresh == 0 then
return current
end

return table . concat ( fresh , ";" ) .. ";" .. current
end

local function rockTree ( root , dep )
return absolute ( join ( root , dep . tree or ROCK_TREE ) ) , dep . luaVersion or ROCK_LUA_VERSION
end

local function declaredVersion ( rockspec )
local text = rockspec and readFile ( rockspec )
if not text then
return nil
end

return text : match ( "[\r\n]version%s*=%s*[\"']([^\"']+)[\"']" ) or text : match ( "^version%s*=%s*[\"']([^\"']+)[\"']" )
end




local listings = { }
local toolVersions = { }
local toolFailures = { }

local function toolArgv ( tool )
local suffix = tool : lower ( ) : match ( "%.([^.]+)$" )
if windows and ( suffix == "bat" or suffix == "cmd" ) then
return { "cmd" , "/d" , "/c" , "call" , tool }
end

return { tool }
end



local function toolVersion ( luarocks )
if toolVersions [ luarocks ] == nil then
local argv = toolArgv ( luarocks )
argv [ # argv + 1 ] = "--version"
local code , printed = process . capture ( argv )
toolVersions [ luarocks ] = code == 0 and ( printed or "" ) or false
toolFailures [ luarocks ] = code ~= 0 and printed or nil
end

return toolVersions [ luarocks ]
end

local function installedRocks ( argv , tree , luaVersion )
local id = tree .. "\0" .. luaVersion
if listings [ id ] then
return listings [ id ]
end
local listArgv = { }
for _ , item in ipairs ( argv ) do
listArgv [ # listArgv + 1 ] = item
end
listArgv [ # listArgv + 1 ] = "list"
listArgv [ # listArgv + 1 ] = "--porcelain"
local code , printed = process . capture ( listArgv )
local installed = { }
if code == 0 then
for line in printed : gmatch ( "[^\r\n]+" ) do
local rock , version = line : match ( "^(%S+)\t(%S+)\t" )
if rock then
installed [ rock ] = version
end
end
end
listings [ id ] = installed

return installed
end




local ROCK_ARTIFACTS = { o = true , a = true , so = true , dylib = true , dll = true }

local function rockSourceFiles ( dir )
local files = { }
for _ , path in ipairs ( listFiles ( dir ) ) do
local suffix = path : match ( "%.([%w]+)$" )
if not ( suffix and ROCK_ARTIFACTS [ suffix : lower ( ) ] ) then
files [ # files + 1 ] = path
end
end
table . sort ( files )

return files
end

local function buildRock ( root , outDir , name , dep , previous )
local rock = dep . rock or name
local tree , luaVersion = rockTree ( root , dep )
local source = dep . path and absolute ( join ( root , dep . path ) ) or nil
local rockspec = dep . rockspec and absolute ( join ( root , dep . rockspec ) ) or nil
if rockspec and not exists ( rockspec ) then
return nil , "dependency " .. name .. " names a rockspec that is not " .. "there: " .. dep . rockspec
end
local declared = declaredVersion ( rockspec )
if dep . version and declared and declared ~= dep . version then
return nil , (
"dependency %s asks for %s %s, and %s declares %s"
) : format ( name , rock , dep . version , dep . rockspec , declared )
end
local wanted = dep . version or declared

local luarocks = dep . luarocks or os . getenv ( "NUPP_LUAROCKS" ) or ( windows and "luarocks.bat" or "luarocks" )
local version = toolVersion ( luarocks )
if not version then
return nil , (
"dependency %s cannot run LuaRocks through %s: %s"
) : format ( name , luarocks , toolFailures [ luarocks ] or "the command failed" )
end
local argv = toolArgv ( luarocks )
argv [ # argv + 1 ] = "--lua-version=" .. luaVersion
argv [ # argv + 1 ] = "--tree=" .. tree
local luaDir = luaDirectory ( dep )
if luaDir then
argv [ # argv + 1 ] = "--lua-dir=" .. luaDir
end
if dep . server then
argv [ # argv + 1 ] = "--server=" .. dep . server
end

local inputs = { }
if rockspec then
inputs [ # inputs + 1 ] = rockspec
end
if source then
local files = rockSourceFiles ( source )



if # files == 0 then
return nil , ( "dependency %s builds from %s, which has nothing in it" ) : format ( name , dep . path )
end
for _ , path in ipairs ( files ) do
inputs [ # inputs + 1 ] = path
end
end
local key = hash . sha256 ( stable ( dep ) .. "\0" .. hashFiles ( inputs ) .. "\0" .. version .. "\0" .. tree )







local installed = installedRocks ( argv , tree , luaVersion )
local present = installed [ rock ]
local satisfied = present ~= nil and ( wanted == nil or present == wanted )
local unchanged = previous ~= nil and previous . key == key
if not satisfied or ( source and not unchanged ) then
local install = { }
for _ , item in ipairs ( argv ) do
install [ # install + 1 ] = item
end
if source then


install [ # install + 1 ] = "make"
if rockspec then
install [ # install + 1 ] = rockspec
end
else
install [ # install + 1 ] = "install"
if rockspec then
install [ # install + 1 ] = rockspec
else
install [ # install + 1 ] = rock
install [ # install + 1 ] = dep . version
end
end
local code , printed = process . capture ( install , { cwd = source } )
if code ~= 0 then
io . stderr : write ( printed )
return nil , "LuaRocks install failed for " .. name
end
installed [ rock ] = wanted or "installed"
end

local paths = treePaths ( tree , luaVersion )
package . path = prepended ( package . path , paths . path )
package . cpath = prepended ( package . cpath , paths . cpath )

return {
key = key ,
rock = rock ,
version = installed [ rock ] ,
tree = tree ,
luaVersion = luaVersion ,
path = paths . path ,
cpath = paths . cpath ,
typeRoot = rockTypeRoot ( tree , luaVersion , rock , installed [ rock ] ) ,
}
end







local function rockPaths (
root ,
config ,
target ,
records
)
local paths , cpaths , typeRoots , seen = { } , { } , { } , { }
for _ , name in ipairs ( target and target . dependencies or { } ) do
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
local rock = dep . rock or name
local rockspec = dep . rockspec and absolute ( join ( root , dep . rockspec ) ) or nil
local version = record and record . version or dep . version or declaredVersion ( rockspec )
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













local function rockModules ( root , config , target )
local selected , seen = { } , { }
for _ , name in ipairs ( target and target . dependencies or { } ) do
local dep = ( config . dependencies or { } ) [ name ]
if type ( dep ) == "table" and dep . kind == "luarocks" and dep . bundle then
local tree , luaVersion = rockTree ( root , dep )
local share = join ( tree , "share/lua/" .. luaVersion )
for _ , pattern in ipairs ( dep . bundle ) do
for _ , path in ipairs ( expandGlob ( share , pattern ) ) do
local relative = path : sub ( # share + 2 )
local module = relative : gsub ( "%.lua$" , "" ) : gsub ( "/init$" , "" ) : gsub ( "/" , "." )
if not seen [ module ] then
seen [ module ] = true
selected [ # selected + 1 ] = { name = module , path = path }
end
end
end
end
end
table . sort ( selected , function ( a , b )
return a . name < b . name
end )

return selected
end

local PROVIDERS = { c = buildC , cargo = buildCargo , rust = buildCargo , luarocks = buildRock }




local function buildDependencies (
root ,
outDir ,
config ,
previous ,
target
)
local results = { }
local visiting = { }
local function buildOne ( name )
if results [ name ] then
return results [ name ]
end
if visiting [ name ] then
return nil , "dependency cycle involving " .. name
end
local dep = ( config . dependencies and config . dependencies [ name ] )
if type ( dep ) ~= "table" then
return nil , "unknown dependency " .. tostring ( name )
end
local provider = PROVIDERS [ dep . kind ]
if not provider then
return nil , "unsupported dependency kind " .. tostring ( dep . kind )
end
visiting [ name ] = true
local childResults = { }
for _ , child in ipairs ( dep . dependencies or { } ) do
local childResult , err = buildOne ( child )
if err then
return nil , err
end
childResults [ child ] = childResult
end
local result , err = provider ( root , outDir , name , dep , previous [ name ] , childResults )
visiting [ name ] = nil
if not result then
return nil , err
end
results [ name ] = result

return result
end

local targetDeps = ( target or config . _target or { } ) . dependencies or { }
for _ , name in ipairs ( targetDeps ) do
local _ , err = buildOne ( name )
if err then
return nil , err
end
end

return results
end

deps . expandGlob = expandGlob
deps . build = buildDependencies
deps . rockPaths = rockPaths
deps . rockModules = rockModules

return deps
