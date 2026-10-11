_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT8={}; local function __nuppT5(...) return {n=select("#",...),...} end; local __nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT6(value) return value end; local function __nuppT7(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT14({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT15(v.primary) for _,reason in __nuppT16(v.suppressed) do text=text.."\ncleanup: "..__nuppT15(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


















local parser = require ( "nupp.compiler.syntax.parser" )
local cst = require ( "nupp.compiler.syntax.cst" )
local check = require ( "nupp.compiler.check" )
local diagnostics = require ( "nupp.compiler.diagnostics" )
local T = require ( "nupp.compiler.types" )
local annotationMod = require ( "nupp.compiler.annotations" )
local native = require ( "nupp.compiler.native" )
local bundledMod = require ( "nupp.compiler.bundled" )
local headerMod = require ( "nupp.compiler.project.header" )




local function compilerPrivate ( name ) 
return require ( "nupp.compiler." .. name )
end

local envMod = { }













































































































































































































































































































































































































local modulePatterns = {
"/%s.d.nupp" ,
"/%s.nupp" ,
"/%s.g.nupp" ,
"/%s.lua" ,
"/%s/init.nupp" ,
"/%s/init.g.nupp" ,
"/%s/init.lua" ,
}


local bundledSource = bundledMod . source


























local preludeServed = false

local runtimeModulePatterns = { "/%s.nupp" , "/%s.g.nupp" , "/%s.lua" , "/%s/init.nupp" , "/%s/init.g.nupp" , "/%s/init.lua" , }

local function moduleDir ( ) 
local src = debug . getinfo ( 1 , "S" ) . source
return src : match ( "^@(.*)[/\\]" ) or "."
end




function envMod . compilerRoot ( ) 
local dir = moduleDir ( ) : gsub ( "\\" , "/" )
local hostOs = rawget ( _G , "os" )
return dir : match ( "^(.*)/src/nupp/compiler/project$" ) or hostOs and hostOs . getenv ( "NUPP_COMPILER_ROOT" ) or nil
end

local function readFile ( path ) 
do local __nuppT17=0; local  __nuppT23 ; local __nuppT18,__nuppT19,__nuppT20=__nuppT10(function() do local __nuppT24=__nuppT5( io . open ( path , "rb" ) ); __nuppT23= __nuppT24[1] ; __nuppT17=1;  local  f , err = __nuppT24[1] , __nuppT24[2] ;
if not f then
return "return",__nuppT5( nil , err )
end
local content = f : read ( "*a" )
f : close ( )

return "return",__nuppT5( content ) end; return "normal" end,__nuppT6); local __nuppT21={}; local __nuppT22=0; if __nuppT17>=1 and __nuppT23~=nil then  local __nuppT25,__nuppT26=__nuppT9(__nuppCleanup1,__nuppT23);  if not __nuppT25 then __nuppT22=__nuppT22+1; __nuppT21[__nuppT22]=__nuppT26 end; end; if not __nuppT18 then if __nuppT22>0 then __nuppT11(__nuppT7(__nuppT19,__nuppT21,1),0) else __nuppT11(__nuppT19,0) end end; if __nuppT22>0 then if __nuppT22>1 then __nuppT11(__nuppT7(__nuppT21[1],__nuppT21,2),0) else __nuppT11(__nuppT21[1],0) end end; if __nuppT19=="return" then  return __nuppT12(__nuppT20,1,__nuppT20.n)  end; end
end



local function normalizePath ( path ) 
path = path : gsub ( "\\" , "/" ) : gsub ( "/+" , "/" )
path = path : gsub ( "^%./" , "" ) : gsub ( "/%./" , "/" )
return ( path : gsub ( "/$" , "" ) )
end

local function isAbsolutePath ( path ) 
return path : sub ( 1 , 1 ) == "/" or path : match ( "^[A-Za-z]:/" ) ~= nil
end





local function climbsOut ( relative ) 
local depth = 0
for segment in relative : gmatch ( "[^/]+" ) do
if segment == ".." then
depth = depth - 1
if depth < 0 then
return true
end
elseif segment ~= "." then
depth = depth + 1
end
end

return false
end


























local listingsByEnv = setmetatable ( { } , { __mode = "k" } )

local function skipBookkeepingDirectory ( name ) 
return name : sub ( 1 , 1 ) == "."
end

local function listLjppFiles ( env , root , withDeclarations , outDir ) 
local listings = listingsByEnv [ env ]
if not listings then
listings = { }
listingsByEnv [ env ] = listings
end
local key = ( withDeclarations and "d\0" or "\0" ) .. root .. "\0" .. ( outDir or "" )
if listings [ key ] then
return listings [ key ]
end

local function skipDirectory ( name , path ) 
return ( name : sub ( 1 , 1 ) == "." ) or ( outDir ~= nil and normalizePath ( path ) == outDir )
end

local files = { }
local fs = ( require ( "nupp.compiler." .. "fs" ) )
for _ , path in ipairs ( fs . listFiles ( root , skipDirectory ) ) do
if path : match ( "%.nupp$" ) and ( withDeclarations or not path : match ( "%.d%.nupp$" ) ) then
files [ # files + 1 ] = normalizePath ( path )
end
end
listings [ key ] = files

return files
end



local function isBookkeepingPath ( path , outDir , rootDir ) 
local generated = path == outDir or path : sub ( 1 , # outDir + 1 ) == outDir .. "/"




local relative = path
if rootDir and rootDir ~= "" and rootDir ~= "." and path : sub ( 1 , # rootDir + 1 ) == rootDir .. "/" then
relative = path : sub ( # rootDir + 2 )
end
local hidden = false
for segment in relative : gmatch ( "[^/]+" ) do
if segment : sub ( 1 , 1 ) == "." and segment ~= "." and segment ~= ".." then
hidden = true
do break end
end
end

return generated or hidden
end





local function outDirFor ( env ) 
local rootDir = env . rootDir or "."
local config = env . config or { }
local selected = config . _target or ( require ( "nupp.compiler." .. "project.projectconfig" ) ) . targetConfig ( config )
local build = config . build or { }

return normalizePath ( rootDir .. "/" .. ( selected and selected . outDir or build . outDir or "build" ) )
end




function envMod . outDir ( env ) 
return outDirFor ( env )
end

function envMod . listProjectFiles ( env ) 
if env . memoryOnly then
return { }
end
local files , seen = { } , { }
local fs = ( require ( "nupp.compiler." .. "fs" ) )
local outDir = outDirFor ( env )
for _ , root in ipairs ( env . roots or { } ) do
for _ , path in ipairs ( listLjppFiles ( env , root , nil , outDir ) ) do
local identity = fs . canonical ( path )
if not seen [ identity ] and not isBookkeepingPath ( path , outDir , env . rootDir ) then
seen [ identity ] = true
files [ # files + 1 ] = path
end
end
end
table . sort ( files )

return files
end



















function envMod . listSourceFilesFor (
env ,
rootDir ,
includes ,
outDir ,
withDeclarations
) 
if env . memoryOnly then
return { }
end
rootDir = normalizePath ( rootDir )
outDir = normalizePath ( outDir )
if withDeclarations == nil then
withDeclarations = true
end
local roots = { }
for _ , dir in ipairs ( includes ) do
roots [ # roots + 1 ] = isAbsolutePath ( normalizePath ( dir ) ) and normalizePath ( dir ) or rootDir .. "/" .. dir
end
if # roots == 0 then
roots [ 1 ] = rootDir
end
local files , seen = { } , { }
for _ , root in ipairs ( roots ) do
for _ , path in ipairs ( listLjppFiles ( env , root , withDeclarations , outDir ) ) do
if not seen [ path ] and not isBookkeepingPath ( path , outDir , rootDir ) then
seen [ path ] = true
files [ # files + 1 ] = path
end
end
end
table . sort ( files )

return files
end

function envMod . listSourceFiles ( env , withDeclarations ) 
return envMod . listSourceFilesFor (
env ,
env . rootDir or "." ,
( env . config or { } ) . include or { } ,
outDirFor ( env ) ,
withDeclarations
)
end











function envMod . projectRoots ( rootDir , config ) 
local roots = { rootDir }
for _ , dir in ipairs ( ( config or { } ) . include or { } ) do
roots [ # roots + 1 ] = isAbsolutePath ( normalizePath ( dir ) ) and normalizePath ( dir ) or rootDir .. "/" .. dir
end
local selected = config and ( config . _target or ( require ( "nupp.compiler." .. "project.projectconfig" ) ) . targetConfig ( config ) ) or nil
local outDir = selected and selected . outDir or config and config . build and config . build . outDir or "build"
local generatorNames = { }
for name in pairs ( config and config . generators or { } ) do
generatorNames [ # generatorNames + 1 ] = name
end
table . sort ( generatorNames )
for _ , name in ipairs ( generatorNames ) do
roots [ # roots + 1 ] = rootDir .. "/" .. outDir .. "/generated/" .. name
end

return roots
end









function envMod . isProjectPath ( env , path ) 
path = normalizePath ( path )
if not path : match ( "%.nupp$" ) then
return false
end
if isBookkeepingPath ( path , outDirFor ( env ) , env . rootDir ) then
return false
end
for _ , rawRoot in ipairs ( env . roots or { } ) do
local root = normalizePath ( rawRoot )
if root == "." or root == "" then
if not isAbsolutePath ( path ) and not climbsOut ( path ) then
return true
end
elseif path : sub ( 1 , # root + 1 ) == root .. "/" and not climbsOut ( path : sub ( # root + 2 ) ) then
return true
end
end

return false
end









function envMod . moduleNameInRoots ( roots , path ) 
path = normalizePath ( path )
local best = nil
for _ , rawRoot in ipairs ( roots or { } ) do
local root = normalizePath ( rawRoot )
local comparedPath = path



if isAbsolutePath ( root ) ~= isAbsolutePath ( comparedPath ) then
local fs = ( require ( "nupp.compiler." .. "fs" ) )
root = fs . canonical ( root )
comparedPath = fs . canonical ( comparedPath )
end
local rel = nil
if root == "." or root == "" then
if not isAbsolutePath ( comparedPath ) then
rel = comparedPath
end
elseif comparedPath : sub ( 1 , # root + 1 ) == root .. "/" then
rel = comparedPath : sub ( # root + 2 )
end
if rel and rel : match ( "%.nupp$" ) and not rel : match ( "%.d%.nupp$" ) and not climbsOut ( rel ) then
rel = rel : gsub ( "%.g%.nupp$" , "" ) : gsub ( "%.nupp$" , "" )
rel = rel : gsub ( "/init$" , "" )
local name = rel : gsub ( "/" , "." )
if name ~= "" and ( not best or # name < # best ) then
best = name
end
end
end

return best
end

function envMod . moduleNameForPath ( env , path ) 
path = normalizePath ( path )





for _ , rawRoot in ipairs ( env . typeRoots or { } ) do
local root = normalizePath ( rawRoot )
local rel = nil
if path : sub ( 1 , # root + 1 ) == root .. "/" then
rel = path : sub ( # root + 2 )
end
if rel and rel : match ( "%.nupp$" ) then
rel = rel : gsub ( "%.d%.nupp$" , "" ) : gsub ( "%.g%.nupp$" , "" ) : gsub ( "%.nupp$" , "" ) : gsub ( "/init$" , "" )
local name = rel : gsub ( "/" , "." )
if name ~= "" then
return name
end
end
end

return envMod . moduleNameInRoots ( env . roots or { } , path )
end










function envMod . projectHeader ( env , path , parsed ) 
path = normalizePath ( path )

return headerMod . of ( path , envMod . moduleNameForPath ( env , path ) , parsed )
end




function envMod . buildProjectIndex ( headers , nominals ) 
local index = {
byName = { } ,
byPath = { } ,
modules = { } ,
annotationsByName = { } ,




moduleBasenames = { } ,
declaredModules = { } ,
internalModules = { } ,
internalTrees = { } ,
moduleDefinitions = { } ,
registrationDiagnostics = { } ,
}
nominals = nominals or { }
local declaredHeaders = { }




local providers = { }
for _ , header in ipairs ( headers or { } ) do
local moduleName = header . moduleName
if moduleName then
local named = providers [ moduleName ]
if not named then
named = { }
providers [ moduleName ] = named
end
named [ # named + 1 ] = header
if type ( header . declaredModuleName ) == "string" and not declaredHeaders [ moduleName ] then
declaredHeaders [ moduleName ] = header
end
index . internalModules [ moduleName ] = header . internal == true
if header . internal and ( header . path : match ( "/init%.nupp$" ) or header . path : match ( "/init%.g%.nupp$" ) ) then
index . internalTrees [ moduleName ] = true
end
index . modules [ moduleName ] = header . path
if type ( header . declaredModuleName ) == "string" then
index . declaredModules [ moduleName ] = true
index . moduleDefinitions [
moduleName
] = { filename = header . path , token = header . moduleToken , name = moduleName , kind = "module" , }
end
local short = moduleName : match ( "([^.]+)$" )
local named = index . moduleBasenames [ short ] or { }
named [ # named + 1 ] = moduleName
index . moduleBasenames [ short ] = named
end
local occurrences = { }
for _ , declaration in ipairs ( header . declarations or { } ) do
local occurrenceKey = declaration . name .. "\0" .. declaration . kind .. "\0" .. declaration . visibility
occurrences [ occurrenceKey ] = ( occurrences [ occurrenceKey ] or 0 ) + 1
local identityKey = header . path .. "\0" .. occurrenceKey .. "\0" .. tostring ( occurrences [ occurrenceKey ] )
local entry = {
name = declaration . name ,
path = header . path ,
moduleName = moduleName ,
visibility = declaration . visibility ,
kind = declaration . kind ,
signature = declaration . signature ,
definition = {
filename = header . path ,
token = declaration . token ,
name = declaration . name ,
kind = declaration . kind == "record" and "type" or declaration . kind ,
deprecated = declaration . deprecated ,
comptimeOnly = declaration . comptimeOnly ,
} ,
}
if declaration . statKind == "recordDecl" then
local nominal = nominals [ identityKey ]
if not nominal then
nominal = T . nominal ( entry . name , entry . kind , identityKey )
nominal . indexedPath = header . path
nominals [ identityKey ] = nominal
end
entry . type = nominal
end
local named = index . byName [ entry . name ] or { }
named [ # named + 1 ] = entry
index . byName [ entry . name ] = named
local inFile = index . byPath [ header . path ] or { }
inFile [ # inFile + 1 ] = entry
index . byPath [ header . path ] = inFile
if declaration . isAnnotation then
local definitions = index . annotationsByName [ entry . name ] or { }
definitions [ # definitions + 1 ] = entry
index . annotationsByName [ entry . name ] = definitions
end
end
end
local reserved = {
pin = true ,
borrow = true ,
borrowFrom = true ,
region = true ,
partition = true ,
attemptAll = true ,
sizeof = true ,
alignof = true ,
offsetof = true ,
types = true ,
reflect = true ,
}

for _ , header in ipairs ( headers or { } ) do
local named = header . moduleName and providers [ header . moduleName ]
if named and # named > 1 then
local related = { }
local allDeclared = true
for _ , other in ipairs ( named ) do
allDeclared = allDeclared and type ( other . declaredModuleName ) == "string"
if other ~= header then
related [
# related + 1
] = {
filename = other . path ,
line = other . moduleToken and other . moduleToken . line or 1 ,
col = other . moduleToken and other . moduleToken . col or 1 ,
msg = "another file providing it is here" ,
}
end
end
index . registrationDiagnostics [
# index . registrationDiagnostics + 1
] = {
path = header . path ,
token = header . moduleToken or { line = 1 , col = 1 , offset = 0 } ,
msg = (
allDeclared and "module %q is declared by more than one file"
or "module %q is provided by more than one file"
) : format ( header . moduleName ) ,
related = related ,
}
end
end
for moduleName , header in pairs ( declaredHeaders ) do
local first = moduleName : match ( "^nupp%.([^.]+)" )
if first and reserved [ first ] then
index . registrationDiagnostics [
# index . registrationDiagnostics + 1
] = {
path = header . path ,
token = header . moduleToken ,
msg = ("module %q collides with compiler-owned nupp.%s") : format ( moduleName , first ) ,
}
end
local parent = moduleName : match ( "^(.*)%.[^.]+$" )
while parent do
local parentHeader = declaredHeaders [ parent ]
if parentHeader then
if not ( parentHeader . path : match ( "/init%.nupp$" ) or parentHeader . path : match ( "/init%.g%.nupp$" ) ) then
index . registrationDiagnostics [
# index . registrationDiagnostics + 1
] = {
path = parentHeader . path ,
token = parentHeader . moduleToken ,
msg = ("module %q has child modules; move its source to %s/init.nupp")

: format ( parent , ( parentHeader . path : gsub ( "%.g%.nupp$" , "" ) : gsub ( "%.nupp$" , "" ) ) ) ,
}
end
local child = moduleName : sub ( # parent + 2 ) : match ( "^[^.]+" )
for _ , declaration in ipairs ( parentHeader . declarations or { } ) do
if declaration . visibility == "module" and declaration . name == child then
index . registrationDiagnostics [
# index . registrationDiagnostics + 1
] = {
path = header . path ,
token = header . moduleToken ,
msg = ("module %q collides with export %s.%s") : format ( moduleName , parent , child ) ,
related = {
{
filename = parentHeader . path ,
line = declaration . token and declaration . token . line or 0 ,
col = declaration . token and declaration . token . col or 0 ,
msg = "the colliding export is here" ,
} ,
} ,
}
end
end
end
parent = parent : match ( "^(.*)%.[^.]+$" )
end
if moduleName == "nupp" then
for _ , declaration in ipairs ( header . declarations or { } ) do
if declaration . visibility == "module" and reserved [ declaration . name ] then
index . registrationDiagnostics [
# index . registrationDiagnostics + 1
] = {
path = header . path ,
token = declaration . token ,
msg = ("export %q collides with compiler-owned nupp.%s")

: format ( declaration . name , declaration . name ) ,
}
end
end
end
end
for _ , named in pairs ( index . moduleBasenames ) do
table . sort ( named )
end

return index
end


















local function openStore (
env ,
field ,
opened ,
file ,
subsystems
) 
local slots = env
if slots [ opened ] then
return slots [ field ]
end
slots [ opened ] = true
if env . cacheDisabled then
return nil
end
local storeMod = ( require ( "nupp.compiler." .. "project.store" ) )
local fingerprintMod = ( require ( "nupp.compiler." .. "project.fingerprint" ) )
local cacheDir = env . cacheDir or ( outDirFor ( env ) .. "/cache" )
slots [
field
] = storeMod . open (
cacheDir .. "/" .. file ,
fingerprintMod . subsystemFingerprint (
subsystems ,
cacheDir ,
env . compilerServices and env . compilerServices . hash and env . compilerServices . hash . digest or nil ,
env . cacheReadOnly
)
)

return slots [ field ]
end









function envMod . headerStore ( env ) 
return openStore ( env , "headerStore" , "headerStoreOpened" , "headers.buf" , { "nupp.compiler.project.header" } )
end













function envMod . headerKey ( env , path , text ) 
local hashMod = ( require ( "nupp.compiler." .. "hash" ) )
local name = envMod . moduleNameForPath ( env , path )
local digest = env . compilerServices and env . compilerServices . hash and env . compilerServices . hash . digest
or hashMod . digest

return digest ( ( name or "" ) .. "\0" .. normalizePath ( path ) .. "\0" .. text )
end












function envMod . annotationKey ( env ) 
if env . annotationKeyMemo then
return env . annotationKeyMemo
end



local ensure = env . ensureProjectIndex or envMod . ensureProjectIndex
local index = ensure ( env )
local parts = { }
for name , entries in pairs ( index . annotationsByName or { } ) do
for _ , entry in ipairs ( entries ) do
parts [ # parts + 1 ] = name .. "\0" .. tostring ( entry . path ) .. "\0" .. tostring ( entry . signature )
end
end
table . sort ( parts )
local hashMod = ( require ( "nupp.compiler." .. "hash" ) )
local digest = env . compilerServices and env . compilerServices . hash and env . compilerServices . hash . digest
or hashMod . digest
env . annotationKeyMemo = digest ( table . concat ( parts , "\1" ) )

return env . annotationKeyMemo
end




envMod . openStore = openStore



function envMod . typeFunctionStore ( env ) 
return openStore ( env , "typeFunctionStore" , "typeFunctionStoreOpened" , "type-functions.buf" , { "nupp.compiler.check" } )
end



function envMod . persist ( env ) 
if env . cacheReadOnly then
return
end
if env . headerStore then
env . headerStore . save ( )
end
if env . formatStore then
env . formatStore . save ( )
end
if env . typeFunctionStore then
env . typeFunctionStore . save ( )
end
end








function envMod . ensureProjectIndex ( env ) 








if env . bootstrapping then
env . bootstrapIndex = env . bootstrapIndex or envMod . buildProjectIndex ( { } , env . projectNominals )

return env . bootstrapIndex
end
if env . projectIndex then
return env . projectIndex
end



local store = envMod . headerStore ( env )
local headers = { }
for _ , path in ipairs ( envMod . listProjectFiles ( env ) ) do
local source = readFile ( path )
local header = nil
local key = source and store and envMod . headerKey ( env , path , source )
if key then
header = store . get ( key )
end
if not header then
header = envMod . projectHeader ( env , path , source and parser . parse ( source , path ) or nil )
if key then
store . put ( key , header )
end
end
headers [ # headers + 1 ] = header
end
env . projectNominals = env . projectNominals or { }
env . projectIndex = envMod . buildProjectIndex ( headers , env . projectNominals )

return env . projectIndex
end

local function projectIndexFor ( env ) 
local ensure = env . ensureProjectIndex or envMod . ensureProjectIndex
return ensure ( env )
end



local function entriesNamed ( env , name ) 
if env . projectEntries then
return env . projectEntries ( env , name )
end

return projectIndexFor ( env ) . byName [ name ] or { }
end


local function entriesAt ( env , path ) 
if env . projectPathEntries then
return env . projectPathEntries ( env , path )
end

return projectIndexFor ( env ) . byPath [ path ] or { }
end

function envMod . declarationType (
env ,
filename ,
name ,
kind ,
visibility
) 
if visibility ~= "module" and visibility ~= "global" then
return nil
end








if not env . projectPathEntries and not envMod . isProjectPath ( env , filename ) then
return nil
end
local path = normalizePath ( filename )
local entries = entriesAt ( env , path )
for _ , entry in ipairs ( entries ) do
if entry . name == name and entry . kind == kind and entry . visibility == visibility then
return entry . type , entry
end
end

return nil
end





local function findModulePath ( env , name , patterns ) 
if env . memoryOnly then
return nil
end
local rel = name : gsub ( "%." , "/" )
for _ , root in ipairs ( env . roots ) do
for _ , pattern in ipairs ( patterns ) do
local candidate = root .. pattern : format ( rel )
do const  __nuppT63= io . open ( candidate , "rb" ) ; const __nuppT65={ candidate } ; local __nuppT64=__nuppT8[1]; if not __nuppT64 then __nuppT64=function(f,__nuppT66) do
if f then
f : close ( )
return "return",__nuppT5( __nuppT66[1] )
end end; return "normal" end; __nuppT8[1]=__nuppT64 end; const __nuppT58,__nuppT59,__nuppT60=__nuppT10(__nuppT64,__nuppT6,__nuppT63,__nuppT65); const __nuppT57=1; local __nuppT61={}; local __nuppT62=0; if __nuppT57>=1 and __nuppT63~=nil then  local __nuppT67,__nuppT68=__nuppT9(__nuppCleanup1,__nuppT63);  if not __nuppT67 then __nuppT62=__nuppT62+1; __nuppT61[__nuppT62]=__nuppT68 end; end; if not __nuppT58 then if __nuppT62>0 then __nuppT11(__nuppT7(__nuppT59,__nuppT61,1),0) else __nuppT11(__nuppT59,0) end end; if __nuppT62>0 then if __nuppT62>1 then __nuppT11(__nuppT7(__nuppT61[1],__nuppT61,2),0) else __nuppT11(__nuppT61[1],0) end end; if __nuppT59=="return" then  return __nuppT12(__nuppT60,1,__nuppT60.n)  end; end
end
end
for _ , root in ipairs ( env . typeRoots or { } ) do
for _ , pattern in ipairs ( patterns ) do
local candidate = root .. pattern : format ( rel )
do const  __nuppT75= io . open ( candidate , "rb" ) ; const __nuppT77={ candidate } ; local __nuppT76=__nuppT8[2]; if not __nuppT76 then __nuppT76=function(f,__nuppT78) do
if f then
f : close ( )
return "return",__nuppT5( __nuppT78[1] )
end end; return "normal" end; __nuppT8[2]=__nuppT76 end; const __nuppT70,__nuppT71,__nuppT72=__nuppT10(__nuppT76,__nuppT6,__nuppT75,__nuppT77); const __nuppT69=1; local __nuppT73={}; local __nuppT74=0; if __nuppT69>=1 and __nuppT75~=nil then  local __nuppT79,__nuppT80=__nuppT9(__nuppCleanup1,__nuppT75);  if not __nuppT79 then __nuppT74=__nuppT74+1; __nuppT73[__nuppT74]=__nuppT80 end; end; if not __nuppT70 then if __nuppT74>0 then __nuppT11(__nuppT7(__nuppT71,__nuppT73,1),0) else __nuppT11(__nuppT71,0) end end; if __nuppT74>0 then if __nuppT74>1 then __nuppT11(__nuppT7(__nuppT73[1],__nuppT73,2),0) else __nuppT11(__nuppT73[1],0) end end; if __nuppT71=="return" then  return __nuppT12(__nuppT72,1,__nuppT72.n)  end; end
end
end

return nil
end

function envMod . isDependencyTypePath ( env , path ) 
path = normalizePath ( path )
for _ , rawRoot in ipairs ( env . typeRoots or { } ) do
local root = normalizePath ( rawRoot )
if path : sub ( 1 , # root + 1 ) == root .. "/" then
return true
end
end
for _ , rawRoot in ipairs ( env . ambientTypeRoots or { } ) do
local root = normalizePath ( rawRoot )
if path : sub ( 1 , # root + 1 ) == root .. "/" then
return true
end
end

return false
end



function envMod . isRuntimeSourcePath ( env , path ) 
path = normalizePath ( path )
for _ , root in ipairs ( env . runtimeSourceRoots or { } ) do
if path : sub ( 1 , # root + 1 ) == root .. "/" then
return true
end
end

return false
end












function envMod . isStagedBundledSource ( env , name , path ) 
if env . bundledImplementation == nil then
return false
end
local file = env . bundledImplementation ( name )
if file == nil then
return false
end
path = normalizePath ( path )
local stagedRoots = { }
local staged = false
for _ , root in ipairs ( env . runtimeSourceRoots or { } ) do
stagedRoots [ root ] = true
staged = staged or path == root .. file
end
if not staged then
return false
end
local rel = name : gsub ( "%." , "/" )

local function shadowed ( roots ) 
for _ , rawRoot in ipairs ( roots ) do
if not stagedRoots [ normalizePath ( rawRoot ) ] then
for _ , pattern in ipairs ( modulePatterns ) do
do const  __nuppT91= io . open ( rawRoot .. pattern : format ( rel ) , "rb" ) ; local __nuppT92=__nuppT8[3]; if not __nuppT92 then __nuppT92=function(f) do
if f then
f : close ( )
return "return",__nuppT5( true )
end end; return "normal" end; __nuppT8[3]=__nuppT92 end; const __nuppT86,__nuppT87,__nuppT88=__nuppT10(__nuppT92,__nuppT6,__nuppT91); const __nuppT85=1; local __nuppT89={}; local __nuppT90=0; if __nuppT85>=1 and __nuppT91~=nil then  local __nuppT93,__nuppT94=__nuppT9(__nuppCleanup1,__nuppT91);  if not __nuppT93 then __nuppT90=__nuppT90+1; __nuppT89[__nuppT90]=__nuppT94 end; end; if not __nuppT86 then if __nuppT90>0 then __nuppT11(__nuppT7(__nuppT87,__nuppT89,1),0) else __nuppT11(__nuppT87,0) end end; if __nuppT90>0 then if __nuppT90>1 then __nuppT11(__nuppT7(__nuppT89[1],__nuppT89,2),0) else __nuppT11(__nuppT89[1],0) end end; if __nuppT87=="return" then  return __nuppT12(__nuppT88,1,__nuppT88.n)  end; end
end
end
end

return false
end

return not shadowed ( env . roots or { } ) and not shadowed ( env . typeRoots or { } )
end











local function loadAmbientTypeRoots ( env , roots ) 
if # roots == 0 then
return
end
local listFiles = ( require ( "nupp.compiler." .. "fs" ) ) . listFiles
local problems = env . ambientTypeProblems or { }
env . ambientTypeProblems = problems



local refused = { }

local function refuse ( path , why , line , col ) 
if refused [ path ] then
return
end
refused [ path ] = true
problems [ # problems + 1 ] = { path = path , msg = why , line = line or 1 , col = col or 1 }
end


local function take ( path , source ) 
local result = parser . parse ( source , path )
if # result . errors > 0 then
local problem = result . errors [ 1 ]
return { msg = "cannot be parsed: " .. tostring ( problem . msg ) }
end



local ok , diags = pcall ( check . check , result , path , env , {
declareGlobals = true ,
declarationFile = true ,
strict = false ,
} )
if not ok then
return { msg = "cannot be checked: " .. tostring ( diags ) }
end
for _ , diagnostic in ipairs ( diags ) do
if diagnostics . isFatal ( diagnostic ) then
return {
msg = tostring ( diagnostic . code ) .. " " .. tostring ( diagnostic . msg ) ,
line = diagnostic . line ,
col = diagnostic . col ,
}
end
end

return nil
end






local deferred


= { }
for _ , root in ipairs ( roots ) do
local files = { }
for _ , path in ipairs ( listFiles ( root ) ) do
if path : match ( "%.lua$" ) then
files [ # files + 1 ] = path
end
end
table . sort ( files )
for _ , path in ipairs ( files ) do
local source , readErr = readFile ( path )
if not source then
refuse ( path , "cannot be read: " .. tostring ( readErr ) )
elseif take ( path , source ) ~= nil then
deferred [ # deferred + 1 ] = { path = path , source = source }
end
end
end
for _ , pending in ipairs ( deferred ) do
local problem = take ( pending . path , pending . source )
if problem ~= nil then
refuse ( pending . path , problem . msg , problem . line , problem . col )
end
end
end



function envMod . findModulePath ( env , name ) 
return findModulePath ( env , name , modulePatterns )
end




function envMod . moduleAccess ( env , fromModule , name ) 
local owner = name : match ( "^[^.]+" ) or name
if fromModule and ( fromModule == owner or fromModule : sub ( 1 , # owner + 1 ) == owner .. "." ) then
return nil
end
local index = env . ensureProjectIndex ( env )
local hidden = ( "." .. name .. "." ) : find ( ".internal." , 1 , true ) ~= nil
or ( name : match ( "([^.]+)$" ) or "" ) : sub ( 1 , 1 ) == "_"
or index . internalModules and index . internalModules [ name ] == true
local parent = name
while parent and not hidden do
hidden = index . internalTrees and index . internalTrees [ parent ] == true
parent = parent : match ( "^(.*)%.[^.]+$" )
end
if not hidden and env . bundledInternal then
hidden = env . bundledInternal ( name )
end
if hidden then
return ("module %q is internal to package namespace %q; import its public API") : format ( name , owner )
end

return nil
end




function envMod . findRuntimeModulePath ( env , name ) 
local path = findModulePath ( env , name , runtimeModulePatterns )





if path ~= nil then
path = normalizePath ( path )
end

return path
end





local function seededExports ( env , path ) 
local exports = { types = { } , typeDefs = { } , values = { } , valueDefs = { } , comptimeFunctions = { } }
path = normalizePath ( path )
local entries = entriesAt ( env , path )
for _ , entry in ipairs ( entries ) do
if entry . visibility == "module" and entry . type then
exports . types [ entry . name ] = entry . type
exports . typeDefs [ entry . name ] = entry . definition
if entry . kind == "struct" then
exports . values [ entry . name ] = entry . type
elseif entry . kind == "record" then



exports . values [ entry . name ] = T . typeObject ( entry . type )
end
end
end

return exports
end

local function loadModule ( env , name ) 
local cached = env . loaded [ name ]
if cached then
return cached
end
if env . memoryOnly then
local bundled = env . bundled and env . bundled [ name ] or nil
if bundled then
env . loaded [ name ] = bundled
return bundled
end
end
local path = envMod . findModulePath ( env , name )
if not path then


local bundled = env . bundled and env . bundled [ name ]
return bundled
end
path = normalizePath ( path )
local byPath = env . loadedPaths [ path ]
if byPath then
env . loaded [ name ] = byPath
return byPath
end
local src = readFile ( path )
if not src then
return nil
end
local result = parser . parse ( src , path )
local declaredModuleName = # result . errors == 0 and cst . declaredModule ( result . root ) or nil
local record = {
inProgress = true ,
path = path ,
exports = seededExports ( env , path ) ,
declared = declaredModuleName ~= nil and cst . exportAssignment ( result . root ) == nil ,
}
env . loaded [ name ] = record
env . loadedPaths [ path ] = record
if # result . errors == 0 then
local diags , moduleType , exports = check . check ( result , path , env , {
moduleName = name ,
initialExports = record . exports ,
} )
record . compatDiagnostics = diags
record . source = src
record . type = moduleType or T . any
record . exports = exports or record . exports
else
record . compatDiagnostics = result . errors
record . type = T . any
end
record . inProgress = false

return record
end

local function interfaceType ( exports ) 
local fields = { }
for name , t in pairs ( exports and exports . values or { } ) do
fields [ # fields + 1 ] = { name = name , read = t }
end
table . sort ( fields , function ( a , b ) 
return a . name < b . name
end )

return T . shape ( fields )
end



function envMod . resolveModule ( env , name ) 
local record = loadModule ( env , name )
if not record then
return nil
end





return record . inProgress and ( record . declared and interfaceType ( record . exports ) or T . any ) or record . type
end

function envMod . resolveModuleExports ( env , name ) 
local record = loadModule ( env , name )
return record and record . exports or nil
end

function envMod . moduleInitializing ( env , name ) 
local record = env . loaded and env . loaded [ name ] or nil
return record and record . inProgress == true or false
end

function envMod . resolveCallGuarantees ( env , module , member ) 
local exports = envMod . resolveModuleExports ( env , module )
return exports and exports . callGuarantees and exports . callGuarantees [ member ] or nil
end

function envMod . resolveCallableFact ( env , module , member , fact ) 
local entry = envMod . resolveCallGuarantees ( env , module , member )
return entry and ( entry ) [ fact ] or nil
end

function envMod . observeCallGuarantee (
env ,
module ,
member ,
identity ,
guarantee
) 
local entry = envMod . resolveCallGuarantees ( env , module , member )
if not entry then
return false
end
if guarantee == "noAllocate" then
return entry . noAllocate == true
elseif guarantee == "noRaise" then
return entry . noRaise == true
end

return false
end








local function globalEntry ( entries , kind ) 
local found = nil
local matches = { }
for _ , entry in ipairs ( entries or { } ) do
if entry . visibility == "global" and ( not kind or entry . kind == kind ) then
matches [ # matches + 1 ] = entry
found = entry
end
end
if # matches > 1 then
return nil , "ambiguous project type" , matches
end

return found
end



local function loadedGlobal ( env , entries , kind ) 
local entry , err , conflicts = globalEntry ( entries , kind )
if not entry then
return nil , err , conflicts
end
if entry . moduleName then
env . resolveModuleExports ( env , entry . moduleName )
end

return entry , nil
end

function envMod . resolveProjectType (
env ,
filename ,
name
) 
local entries = entriesNamed ( env , name )
local entry , err , conflicts = loadedGlobal ( env , entries )
if not entry then
return nil , nil , err , nil , nil , conflicts
end

return entry . type , entry . definition , nil , entry . moduleName , entry . visibility
end




function envMod . modulesNamed ( env , short ) 
if env . projectModuleBasenames then
return env . projectModuleBasenames ( env , short )
end
return projectIndexFor ( env ) . moduleBasenames [ short ]
end






function envMod . modulesExporting ( env , name ) 
local modules , seen = { } , { }
local entries = entriesNamed ( env , name )
for _ , entry in ipairs ( entries ) do
if entry . visibility == "module" and entry . moduleName and not seen [ entry . moduleName ] then
seen [ entry . moduleName ] = true
modules [ # modules + 1 ] = entry . moduleName
end
end
table . sort ( modules )

return modules
end

function envMod . resolveProjectValue (
env ,
filename ,
name
) 
local entries = entriesNamed ( env , name )
local entry , err , conflicts = loadedGlobal ( env , entries , "struct" )
if not entry then
return nil , nil , err , nil , conflicts
end

return entry . type , entry . definition , nil , entry . moduleName
end




function envMod . resolveProjectAnnotation ( env , filename , name ) 
local entries = env . projectAnnotations and env . projectAnnotations ( env , name )
or projectIndexFor ( env ) . annotationsByName [ name ]
if not entries or # entries == 0 then
return nil
end
if # entries > 1 then
return nil , "ambiguous project annotation @" .. name
end
local entry = entries [ 1 ]
if normalizePath ( entry . path ) ~= normalizePath ( filename ) and entry . moduleName then
env . resolveModuleExports ( env , entry . moduleName )
end

return env . annotations : get ( name ) , nil
end

function envMod . resolveQualifiedType (
env ,
filename ,
moduleName ,
typeName
) 



if env . projectEntries then
env . projectEntries ( env , typeName )
end
local names = { moduleName }
local currentModule = envMod . moduleNameForPath ( env , filename )
local currentDir = currentModule and currentModule : match ( "^(.*)%.[^.]+$" )
if currentDir and not moduleName : find ( "%." , 1 , false ) then
table . insert ( names , 1 , currentDir .. "." .. moduleName )
end
local self_ = normalizePath ( filename )
for _ , candidate in ipairs ( names ) do



local candidatePath = envMod . findModulePath ( env , candidate )
if not candidatePath or normalizePath ( candidatePath ) ~= self_ then


local exports = env . resolveModuleExports ( env , candidate )
local t = exports and exports . types [ typeName ] or nil
if t then
return t , exports . typeDefs [ typeName ] , candidate
end
end
end

return nil
end









function envMod . exportedNominal ( env , moduleName , typeName ) 
local entry = nil
local entries = entriesNamed ( env , typeName )
for _ , candidate in ipairs ( entries ) do
if candidate . moduleName == moduleName
and candidate . visibility == "module"
and ( candidate . kind == "record" or candidate . kind == "struct" )
then
entry = candidate
do break end
end
end
if not entry and envMod . findModulePath ( env , moduleName ) then



local exports = env . resolveModuleExports ( env , moduleName )
local exported = exports and exports . types [ typeName ] or nil
if exported and exported . tag == "genericAlias" then
exported = exported . body
end
if exported
and exported . tag == "nominal"
and ( exported . declKind == "record" or exported . declKind == "struct" )
then
return exported , exports and exports . typeDefs [ typeName ]
end
return nil
end
if not entry then





local bundled = env . bundled and env . bundled [ moduleName ] or nil
local exported = bundled and bundled . exports and bundled . exports . types [ typeName ] or nil
if exported
and exported . tag == "nominal"
and ( exported . declKind == "record" or exported . declKind == "struct" )
then
return exported , bundled . exports . typeDefs [ typeName ]
end

return nil
end



local exports = env . resolveModuleExports ( env , moduleName )

return exports and exports . types [ typeName ] or entry . type , exports and exports . typeDefs [ typeName ] or entry . definition
end







local function configAt ( dir ) 
local loader = rawget ( _G , "loadfile" )
local chunk = loader and loader ( dir .. "/nupp.lua" ) or nil
if not chunk then
return { }
end
local ok , loaded = pcall ( chunk )

return ok and type ( loaded ) == "table" and loaded or { }
end











function envMod . new ( rootDir , opts ) 
rootDir = rootDir or "."
local memoryOnly = opts and opts . memoryOnly == true or false
local cacheDir = opts and opts . cacheDir or nil
if not cacheDir and not ( opts and opts . cache == false ) then
local fingerprint = ( require ( "nupp.compiler." .. "project.fingerprint" ) )
cacheDir = fingerprint . sharedCacheDir ( nil )
end
local compilerServices = opts and opts . compilerServices or nil
if not compilerServices and not memoryOnly and not ( opts and opts . nativeCompilerServices == false ) then
compilerServices = ( require ( "nupp.compiler." .. "hostservices" ) )
end
local env = {
globals = { } ,
globalTypes = { } ,
preludeComptimeFunctions = { } ,
globalTypeDefs = { } ,
annotations = annotationMod . new ( ) ,
loaded = { } ,
loadedPaths = { } ,
bundled = { } ,
moduleAccess = envMod . moduleAccess ,
resolveModule = envMod . resolveModule ,
resolveModuleExports = envMod . resolveModuleExports ,
moduleInitializing = envMod . moduleInitializing ,
observeCallGuarantee = envMod . observeCallGuarantee ,
resolveCallGuarantees = envMod . resolveCallGuarantees ,
resolveCallableFact = envMod . resolveCallableFact ,
resolveProjectType = envMod . resolveProjectType ,
resolveProjectValue = envMod . resolveProjectValue ,
resolveProjectAnnotation = envMod . resolveProjectAnnotation ,
resolveQualifiedType = envMod . resolveQualifiedType ,
exportedNominal = envMod . exportedNominal ,
modulesNamed = envMod . modulesNamed ,
modulesExporting = envMod . modulesExporting ,
declarationType = envMod . declarationType ,
moduleNameForPath = envMod . moduleNameForPath ,
findModulePath = envMod . findModulePath ,
ensureProjectIndex = envMod . ensureProjectIndex ,
openTypeFunctionStore = envMod . typeFunctionStore ,
rootDir = rootDir ,





cacheDisabled = opts and opts . cache == false or nil ,
cacheReadOnly = opts and opts . cacheReadOnly == true or nil ,
memoryOnly = memoryOnly or nil ,
capabilityResolution = opts and opts . capabilityResolution or nil ,
nativeCompilerServices = not ( opts and opts . nativeCompilerServices == false ) ,
compilerServices = compilerServices ,
projectNominals = opts and opts . projectNominals or nil ,



cacheDir = cacheDir ,
}
local deriveRecipes = { }
env . internDeriveRecipe = function ( _ , recipe ) 
local prior = deriveRecipes [ recipe . fingerprint ]
if prior then
return recipe , true
end
deriveRecipes [ recipe . fingerprint ] = true

return recipe , false
end
annotationMod . hydrateBuiltins ( env . annotations , T )

local config = opts and opts . config or configAt ( rootDir )
env . config = config or { }
local compatibility , compatError = require ( "nupp.compiler.compat" ) . resolve ( opts and opts . compat , env . config . compat )
if compatError then
error ( compatError , 2 )
end
env . compat = compatibility
local selectedTarget = env . config . _target or ( require ( "nupp.compiler." .. "project.projectconfig" ) ) . targetConfig ( env . config )
env . artifactHost = selectedTarget and selectedTarget . host or nil
env . layoutTarget = selectedTarget and selectedTarget . layoutTarget or nil






if env . layoutTarget ~= nil and env . nativeCompilerServices then
env . targetProfile = ( ( require ( "nupp.compiler." .. "compilerpacks" ) ) . profile ( env . layoutTarget ) )
end

local typeRoots = opts and opts . typeRoots or nil
if not typeRoots then



local projectConfig = selectedTarget and ( require ( "nupp.compiler." .. "project.projectconfig" ) ) or nil
local rocks = projectConfig and projectConfig . rockPaths ( rootDir , env . config , selectedTarget ) or nil
typeRoots = rocks and rocks . typeRoots or { }
end
env . typeRoots = { }
for _ , dir in ipairs ( typeRoots or { } ) do
env . typeRoots [ # env . typeRoots + 1 ] = normalizePath ( dir )
end
local ambientTypeRoots = opts and opts . ambientTypeRoots or nil
if not ambientTypeRoots and not memoryOnly then
local projectConfig = selectedTarget and ( require ( "nupp.compiler." .. "project.projectconfig" ) ) or nil
ambientTypeRoots = projectConfig and projectConfig . typeRoots ( rootDir , env . config ) or { }
end
env . ambientTypeRoots = { }
for _ , dir in ipairs ( ambientTypeRoots or { } ) do
env . ambientTypeRoots [ # env . ambientTypeRoots + 1 ] = normalizePath ( dir )
end
env . runtimeSourceRoots = { }
for _ , dir in ipairs ( opts and opts . runtimeSourceRoots or { } ) do
env . runtimeSourceRoots [ # env . runtimeSourceRoots + 1 ] = normalizePath ( dir )
end

env . roots = envMod . projectRoots ( rootDir , env . config )
local seenRoot = { }
for _ , root in ipairs ( env . roots ) do
seenRoot [ normalizePath ( root ) ] = true
end

local function addRoot ( dir ) 
if seenRoot [ normalizePath ( dir ) ] then
return
end
seenRoot [ normalizePath ( dir ) ] = true
env . roots [ # env . roots + 1 ] = dir
end

env . folders = { }
for _ , folder in ipairs ( opts and opts . folders or { } ) do
if normalizePath ( folder ) ~= normalizePath ( rootDir ) then
env . folders [ # env . folders + 1 ] = normalizePath ( folder )
addRoot ( folder )
for _ , dir in ipairs ( configAt ( folder ) . include or { } ) do
addRoot ( isAbsolutePath ( normalizePath ( dir ) ) and normalizePath ( dir ) or folder .. "/" .. dir )
end
end
end






local PRELUDE_FILES = { "/decls/lua.d.nupp" , "/decls/prelude.d.nupp" , }
local preludeOrigin = "nupp:prelude.d.nupp"
do
local image = opts and opts . preludeImage and opts . preludeImage . new ( ) or nil







local preludeKey = nil
local cacheStore = nil
local preludeCache = nil
local identityOrigin = nil
local writeImage = false
if not image and not preludeServed and not env . cacheDisabled and os . getenv ( "NUPP_NO_PRELUDE_CACHE" ) == nil then



preludeCache = ( require ( "nupp.compiler." .. "project.preludecache" ) )
identityOrigin = preludeCache . origin ( )
local hashMod = ( require ( "nupp.compiler." .. "hash" ) )
local parts = {
tostring ( env . layoutTarget or "" ) ,
tostring ( env . compat or "" ) ,
require ( "nupp.compiler.compat" ) . VERSION
}





local lints = ( env . config or { } ) . lints
if type ( lints ) == "table" then
local named = { }
for name , level in pairs ( lints ) do
named [ # named + 1 ] = tostring ( name ) .. "=" .. tostring ( level )
end
table . sort ( named )
parts [ # parts + 1 ] = table . concat ( named , "," )
end
for _ , preludeFile in ipairs ( PRELUDE_FILES ) do
parts [ # parts + 1 ] = bundledSource ( preludeFile ) or ""
end
parts [ # parts + 1 ] = bundledSource ( "/decls/prelude_impl.d.nupp" ) or ""
preludeKey = hashMod . digest ( table . concat ( parts , "\0" ) )
local remembered = nil
if not memoryOnly then
local storeMod = ( require ( "nupp.compiler." .. "project.store" ) )
local fingerprintMod = ( require ( "nupp.compiler." .. "project.fingerprint" ) )
local storeDir = cacheDir or ( outDirFor ( env ) .. "/cache" )






cacheStore = storeMod . open (
storeDir .. "/prelude.buf" ,
fingerprintMod . subsystemFingerprint (
{ "nupp.compiler.project.env" , "nupp.compiler.project.preludecache" } ,
storeDir ,
env . compilerServices and env . compilerServices . hash and env . compilerServices . hash . digest or nil ,
env . cacheReadOnly
)
)
remembered = cacheStore . get ( preludeKey )
end


if remembered ~= nil then
image = preludeCache . decode ( remembered , identityOrigin )
end


if not image
and not env . cacheReadOnly
and cacheStore ~= nil
and preludeCache . replaces ( remembered , identityOrigin )
then
writeImage = preludeCache . seal ( identityOrigin ) ~= nil
end
end

if image then
preludeServed = true
env . globals = image . globals
env . globalTypes = image . globalTypes
env . preludeComptimeFunctions = image . preludeComptimeFunctions
env . globalTypeDefs = image . globalTypeDefs
env . annotations . byname = image . annotationsByName
env . stringLib = image . stringLib
env . featureEffects = image . featureEffects
env . preludeRuntime = image . preludeRuntime
else
env . bootstrapping = true
for _ , preludeFile in ipairs ( PRELUDE_FILES ) do
local src = bundledSource ( preludeFile )




if not src then
error ( "internal error: cannot read the prelude at " .. bundledMod . moduleDir ( ) .. preludeFile , 0 )
end
local origin = "nupp:" .. ( preludeFile : match ( "([^/]+)$" ) or preludeFile )
local result = parser . parse ( src , origin )
assert (
# result . errors == 0 ,
"internal error: prelude has syntax errors: " .. ( result . errors [ 1 ] and result . errors [ 1 ] . msg or "?" )
)
local diags = check . check ( result , origin , env , { declareGlobals = true , } )
local fatal = nil
for _ , diagnostic in ipairs ( diags ) do
if diagnostics . isFatal ( diagnostic ) then
fatal = diagnostic
do break end
end
end
assert (
not fatal ,
"internal error: prelude has type errors: " .. origin .. ":" .. tostring (
fatal and ( fatal ) . line or "?"
) .. ":" .. tostring (
fatal and ( fatal ) . col or "?"
) .. ": " .. tostring ( fatal and ( fatal ) . code or "?" ) .. " " .. ( fatal and fatal . msg or "?" )
)
end
local implementationSource = bundledSource ( "/decls/prelude_impl.d.nupp" )
assert ( implementationSource , "internal error: cannot read the prelude implementation" )

local function checkImplementation ( ) 
local implementation = parser . parse ( implementationSource , "nupp:prelude.d.nupp" )
assert (
# implementation . errors == 0 ,
"internal error: prelude implementation has syntax errors: " .. (
implementation . errors [ 1 ] and implementation . errors [ 1 ] . msg or "?"
)
)




local hiddenGlobals = { }
local hiddenTypes = { }
for _ , block in ipairs ( implementation . root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
if stat . kind == "localFuncStmt" and stat . name then
local name = stat . name . text
if env . globals [ name ] then
hiddenGlobals [ name ] = env . globals [ name ]
env . globals [ name ] = nil
end
if env . globalTypes [ name ] then
hiddenTypes [ name ] = env . globalTypes [ name ]
env . globalTypes [ name ] = nil
end
end
end
end
local implementationDiags = check . check ( implementation , "nupp:prelude.d.nupp" , env , {
moduleName = "nupp.prelude" ,
strict = true ,
} )
for name , entry in pairs ( hiddenGlobals ) do
env . globals [ name ] = entry
end
for name , t in pairs ( hiddenTypes ) do
env . globalTypes [ name ] = t
end
local implementationFatal = nil
for _ , diagnostic in ipairs ( implementationDiags ) do
if diagnostics . isFatal ( diagnostic ) then
implementationFatal = diagnostic
do break end
end
end
assert (
not implementationFatal ,
"internal error: prelude implementation has type errors: " .. (
implementationFatal and implementationFatal . msg or "?"
)
)

return implementation
end

local implementation = checkImplementation ( )
local generated , generatedDiags = require ( "nupp.compiler.lua.gen" ) . generate ( implementation , "nupp:prelude.d.nupp" )
local generatedFatal = nil
for _ , diagnostic in ipairs ( generatedDiags ) do
if diagnostics . isFatal ( diagnostic ) then
generatedFatal = diagnostic
do break end
end
end
assert (
not generatedFatal ,
"internal error: prelude does not generate: " .. ( generatedFatal and generatedFatal . msg or "?" )
)
env . preludeRuntime = generated
annotationMod . bindBuiltinDeclarations ( env . annotations , env . globalTypes , env . globalTypeDefs )
local strlib = env . globals [ "string" ]
env . stringLib = strlib and strlib . t or nil
env . featureEffects = native . decorateGlobals ( env . globals )
env . bootstrapping = nil
preludeServed = true




if writeImage then
local flattened = preludeCache . encode (
{
annotationsByName = env . annotations . byname ,
featureEffects = env . featureEffects ,
globalTypeDefs = env . globalTypeDefs ,
globalTypes = env . globalTypes ,
globals = env . globals ,
preludeComptimeFunctions = env . preludeComptimeFunctions ,
preludeRuntime = env . preludeRuntime ,
stringLib = env . stringLib ,
} ,
identityOrigin
)



if flattened ~= nil and cacheStore ~= nil then
cacheStore . put ( preludeKey , flattened )
cacheStore . save ( )
end
end
end
end

loadAmbientTypeRoots ( env , env . ambientTypeRoots )




local BUNDLED = {
[ "nupp.text.internal.buffer" ] = "/nupp/text/internal/buffer.d.nupp" ,
[ "string.buffer" ] = "/decls/stringbuffer.d.nupp" ,
[ "bit" ] = "/decls/bit.d.nupp" ,
[ "ffi" ] = "/decls/ffi.d.nupp" ,
[ "lpeg" ] = "/decls/lpeg.d.nupp" ,
[ "re" ] = "/decls/re.d.nupp" ,



[ "jit.util" ] = "/decls/jit/util.d.nupp" ,
[ "jit.profile" ] = "/decls/jit/profile.d.nupp" ,
[ "jit.zone" ] = "/decls/jit/zone.d.nupp" ,
[ "jit.vmdef" ] = "/decls/jit/vmdef.d.nupp" ,
[ "nupp.workers.native" ] = "/nupp/workers/native.d.nupp" ,
}





local BUNDLED_SOURCE = {
[ "nupp.runtime.workersprovider" ] = "/nupp/runtime/workersprovider.nupp" ,
[ "nupp.runtime.timeprovider" ] = "/nupp/runtime/timeprovider.nupp" ,
[ "re" ] = "/re.g.nupp" ,
[ "nupp.io.http.spi" ] = "/nupp/io/http/spi.nupp" ,
[ "nupp.runtime.provider.nativegpurelease" ] = "/nupp/runtime/provider/nativegpurelease.nupp" ,
[ "nupp.gpu.operations" ] = "/nupp/gpu/operations.nupp" ,
[ "nupp.runtime.provider.nativegpu" ] = "/nupp/runtime/provider/nativegpu.nupp" ,
[ "nupp.gpu.spi" ] = "/nupp/gpu/spi.nupp" ,
[ "nupp.gpu.api" ] = "/nupp/gpu/api.nupp" ,
[ "nupp.gpu.types" ] = "/nupp/gpu/types.nupp" ,
[ "nupp.runtime.provider.nativehttp" ] = "/nupp/runtime/provider/nativehttp.nupp" ,
[ "nupp.mem.representation" ] = "/nupp/mem/representation/init.nupp" ,
[ "nupp.workers.spi" ] = "/nupp/workers/spi.nupp" ,
[ "nupp.runtime.provider.workers" ] = "/nupp/runtime/provider/workers.nupp" ,

[ "nupp.runtime.uuidprovider" ] = "/nupp/runtime/uuidprovider.nupp" ,
[ "nupp.runtime.provider.nativeuuid" ] = "/nupp/runtime/provider/nativeuuid.nupp" ,

[ "nupp.runtime.provider.nativestorage" ] = "/nupp/runtime/provider/nativestorage.nupp" ,
[ "nupp.runtime.structvalue" ] = "/nupp/runtime/structvalue.nupp" ,

[ "nupp.runtime.provider.suspension" ] = "/nupp/runtime/provider/suspension.nupp" ,
[ "nupp.suspension.cancellation" ] = "/nupp/suspension/cancellation.nupp" ,
[ "nupp.suspension.spi" ] = "/nupp/suspension/spi.nupp" ,
[ "nupp.suspension.selected" ] = "/nupp/suspension/selected.nupp" ,
[ "nupp.runtime.provider.nativeprocess" ] = "/nupp/runtime/provider/nativeprocess.nupp" ,
[ "nupp.io.process.spi" ] = "/nupp/io/process/spi.nupp" ,
[ "nupp.runtime.provider.nativetls" ] = "/nupp/runtime/provider/nativetls.nupp" ,
[ "nupp.io.tls.spi" ] = "/nupp/io/tls/spi.nupp" ,
[ "nupp.runtime.provider.nativenet" ] = "/nupp/runtime/provider/nativenet.nupp" ,
[ "nupp.io.net.spi" ] = "/nupp/io/net/spi.nupp" ,
[ "nupp.text" ] = "/nupp/text/init.nupp" ,
[ "nupp.runtime.provider.nativebuffer" ] = "/nupp/runtime/provider/nativebuffer.nupp" ,
[ "nupp.runtime.provider.tablebuffer" ] = "/nupp/runtime/provider/tablebuffer.nupp" ,
[ "nupp.gpu.internal" ] = "/nupp/gpu/internal.nupp" ,
[ "nupp.gpu.layoutfacts" ] = "/nupp/gpu/layoutfacts.nupp" ,
[ "nupp.runtime.browser.webgpu.internal" ] = "/nupp/runtime/browser/webgpu/internal.nupp" ,
[ "nupp.runtime.browser.uri" ] = "/nupp/runtime/browser/uri.nupp" ,
[ "nupp.io.uri.whatwg" ] = "/nupp/io/uri/whatwg.nupp" ,
[ "nupp.io.uri.provider" ] = "/nupp/io/uri/provider.nupp" ,
[ "nupp.gpu" ] = "/nupp/gpu/init.nupp" ,
[ "nupp.gpu.layout" ] = "/nupp/gpu/layout.nupp" ,
[ "nupp.io.net.internal" ] = "/nupp/io/net/internal.nupp" ,
[ "nupp.io.net.types" ] = "/nupp/io/net/types.nupp" ,
[ "nupp.io.process.types" ] = "/nupp/io/process/types.nupp" ,
[ "nupp.io.tls.types" ] = "/nupp/io/tls/types.nupp" ,
[ "nupp.io.http.messages" ] = "/nupp/io/http/messages.nupp" ,
[ "nupp.io.internal.bytes" ] = "/nupp/io/internal/bytes.nupp" ,
[ "nupp.io.internal.ownedreader" ] = "/nupp/io/internal/ownedreader.nupp" ,
[ "nupp.io.internal.scalars" ] = "/nupp/io/internal/scalars.nupp" ,
[ "nupp.io.internal.lines" ] = "/nupp/io/internal/lines.nupp" ,
[ "nupp.io.http.internal.transport" ] = "/nupp/io/http/internal/transport.nupp" ,

[ "nupp.runtime.bitops" ] = "/nupp/runtime/bitops.nupp" ,
[ "nupp.runtime.provider.nativetime" ] = "/nupp/runtime/provider/nativetime.nupp" ,
[ "nupp.runtime.provider.nativepath" ] = "/nupp/runtime/provider/nativepath.nupp" ,
[ "nupp.runtime.provider.nativeuri" ] = "/nupp/runtime/provider/nativeuri.nupp" ,
[ "nupp.spi" ] = "/nupp/spi/init.nupp" ,
[ "nupp.text.spi" ] = "/nupp/text/spi.nupp" ,
[ "nupp.random.spi" ] = "/nupp/random/spi.nupp" ,
[ "nupp.mem.representation.spi" ] = "/nupp/mem/representation/spi.nupp" ,
[ "nupp.codec.json.spi" ] = "/nupp/codec/json/spi.nupp" ,
[ "nupp.codec.json.number" ] = "/nupp/codec/json/number.nupp" ,
[ "nupp.io.path.spi" ] = "/nupp/io/path/spi.nupp" ,
[ "nupp.io.path.pathtext" ] = "/nupp/io/path/pathtext.nupp" ,
[ "nupp.runtime.provider.lunajson" ] = "/nupp/runtime/provider/lunajson.nupp" ,
[ "nupp.time.spi" ] = "/nupp/time/spi.nupp" ,
[ "nupp.io.uri.spi" ] = "/nupp/io/uri/spi.nupp" ,
[ "nupp.util.spi" ] = "/nupp/util/spi.nupp" ,
[ "nupp.runtime.target" ] = "/nupp/runtime/target.nupp" ,
[ "nupp.derive" ] = "/nupp/derive.nupp" ,
[ "nupp.cli" ] = "/nupp/cli/init.g.nupp" ,
[ "nupp.cli.internal.optparser" ] = "/nupp/cli/internal/optparser.nupp" ,
[ "nupp.cli.internal.decode" ] = "/nupp/cli/internal/decode.g.nupp" ,
[ "nupp.cli.internal.terminal" ] = "/nupp/cli/internal/terminal.nupp" ,
[ "nupp.cli.internal.table" ] = "/nupp/cli/internal/table.nupp" ,
[ "nupp.cli.internal.application" ] = "/nupp/cli/internal/application.g.nupp" ,
[ "nupp.compiler.runtime.extensions" ] = "/nupp/compiler/runtime/extensions.nupp" ,
[ "nupp.test" ] = "/nupp/test.nupp" ,
[ "nupp.profile.zone" ] = "/nupp/profile/zone.nupp" ,
[ "nupp.profile.trace" ] = "/nupp/profile/trace.nupp" ,
[ "nupp.profile" ] = "/nupp/profile/init.nupp" ,
[ "nupp.mem.indexed" ] = "/nupp/mem/indexed.nupp" ,
[ "nupp.mem.span" ] = "/nupp/mem/span.nupp" ,
[ "nupp.simd" ] = "/nupp/simd.nupp" ,
[ "nupp.mem.heap" ] = "/nupp/mem/heap.nupp" ,
[ "nupp.mem.sharedbytes" ] = "/nupp/mem/sharedbytes.nupp" ,
[ "nupp.mem.soa" ] = "/nupp/mem/soa.nupp" ,
[ "nupp.random" ] = "/nupp/random/init.nupp" ,
[ "nupp.mem.array" ] = "/nupp/mem/array.nupp" ,
[ "nupp.util.internal.pool" ] = "/nupp/util/internal/pool.nupp" ,
[ "nupp.mem.arena" ] = "/nupp/mem/arena.nupp" ,
[ "nupp.events" ] = "/nupp/events.nupp" ,
[ "nupp.codec.json" ] = "/nupp/codec/json/init.nupp" ,
[ "nupp.codec.json.provider" ] = "/nupp/codec/json/provider.nupp" ,
[ "nupp.codec.json.aot" ] = "/nupp/codec/json/aot.nupp" ,
[ "nupp.codec.json.internal.decode" ] = "/nupp/codec/json/internal/decode.nupp" ,
[ "nupp.codec.json.internal.decoder.fused" ] = "/nupp/codec/json/internal/decoder/fused.nupp" ,
[ "nupp.codec.json.internal.decoder.eager" ] = "/nupp/codec/json/internal/decoder/eager.nupp" ,
[ "nupp.codec.json.internal.decoder.serde" ] = "/nupp/codec/json/internal/decoder/serde.nupp" ,
[ "nupp.codec.json.internal.builder" ] = "/nupp/codec/json/internal/builder.nupp" ,
[ "nupp.serde" ] = "/nupp/serde/init.nupp" ,
[ "nupp.serde.internal.accessors" ] = "/nupp/serde/internal/accessors.nupp" ,
[ "nupp.serde.internal.context" ] = "/nupp/serde/internal/context.nupp" ,
[ "nupp.serde.debug" ] = "/nupp/serde/debug.nupp" ,
[ "nupp.serde.internal.declaration" ] = "/nupp/serde/internal/declaration.nupp" ,
[ "nupp.serde.internal.json.defaults" ] = "/nupp/serde/internal/json/defaults.nupp" ,
[ "nupp.serde.internal.document" ] = "/nupp/serde/internal/document.nupp" ,
[ "nupp.serde.internal.documentcodec" ] = "/nupp/serde/internal/documentcodec.nupp" ,
[ "nupp.serde.internal.documentreader" ] = "/nupp/serde/internal/documentreader.nupp" ,
[ "nupp.serde.internal.documentwriter" ] = "/nupp/serde/internal/documentwriter.nupp" ,
[ "nupp.serde.internal.errors" ] = "/nupp/serde/internal/errors.nupp" ,
[ "nupp.serde.adapters" ] = "/nupp/serde/adapters.nupp" ,
[ "nupp.serde.codec" ] = "/nupp/serde/codec.nupp" ,
[ "nupp.serde.internal.identity" ] = "/nupp/serde/internal/identity.lua" ,
[ "nupp.serde.document" ] = "/nupp/serde/document.nupp" ,
[ "nupp.serde.json" ] = "/nupp/serde/json.nupp" ,
[ "nupp.serde.internal.json.compiled" ] = "/nupp/serde/internal/json/compiled.nupp" ,
[ "nupp.serde.internal.json.encoder" ] = "/nupp/serde/internal/json/encoder.nupp" ,
[ "nupp.serde.internal.json.diagnostic" ] = "/nupp/serde/internal/json/diagnostic.nupp" ,
[ "nupp.serde.internal.json.document" ] = "/nupp/serde/internal/json/document.nupp" ,
[ "nupp.serde.internal.json.extensions" ] = "/nupp/serde/internal/json/extensions.nupp" ,
[ "nupp.serde.internal.json.lower" ] = "/nupp/serde/internal/json/lower.nupp" ,
[ "nupp.serde.internal.json.plan" ] = "/nupp/serde/internal/json/plan.nupp" ,
[ "nupp.serde.internal.json.reader" ] = "/nupp/serde/internal/json/reader.nupp" ,
[ "nupp.serde.internal.json.syntax" ] = "/nupp/serde/internal/json/syntax.nupp" ,
[ "nupp.serde.internal.json.writer" ] = "/nupp/serde/internal/json/writer.nupp" ,
[ "nupp.serde.internal.list" ] = "/nupp/serde/internal/list.nupp" ,
[ "nupp.serde.internal.memo" ] = "/nupp/serde/internal/memo.nupp" ,
[ "nupp.serde.internal.indexed" ] = "/nupp/serde/internal/indexed.nupp" ,
[ "nupp.serde.native" ] = "/nupp/serde/native.nupp" ,
[ "nupp.serde.internal.native.reader" ] = "/nupp/serde/internal/native/reader.nupp" ,
[ "nupp.serde.internal.native.writer" ] = "/nupp/serde/internal/native/writer.nupp" ,
[ "nupp.serde.internal.numbers" ] = "/nupp/serde/internal/numbers.nupp" ,
[ "nupp.serde.internal.persistence" ] = "/nupp/serde/internal/persistence.nupp" ,
[ "nupp.serde.internal.publication" ] = "/nupp/serde/internal/publication.nupp" ,
[ "nupp.serde.internal.scalar" ] = "/nupp/serde/internal/scalar.nupp" ,
[ "nupp.serde.internal.structure" ] = "/nupp/serde/internal/structure.nupp" ,
[ "nupp.serde.internal.timestamps" ] = "/nupp/serde/internal/timestamps.nupp" ,
[ "nupp.serde.internal.value" ] = "/nupp/serde/internal/value.nupp" ,
[ "nupp.serde.internal.view" ] = "/nupp/serde/internal/view.nupp" ,
[ "nupp.digest.internal.streaming" ] = "/nupp/digest/internal/streaming.nupp" ,
[ "nupp.runtime.provider.tablestruct" ] = "/nupp/runtime/provider/tablestruct.nupp" ,
[ "nupp.runtime.storage" ] = "/nupp/runtime/storage.nupp" ,
[ "nupp.runtime.managed" ] = "/nupp/runtime/managed.g.nupp" ,
[ "nupp.runtime.browser.effects" ] = "/nupp/runtime/browser/effects.g.nupp" ,
[ "nupp.runtime.browser.response" ] = "/nupp/runtime/browser/response.g.nupp" ,
[ "nupp.runtime.browser.crypto" ] = "/nupp/runtime/browser/crypto.g.nupp" ,
[ "nupp.runtime.browser.memory" ] = "/nupp/runtime/browser/memory.g.nupp" ,
[ "nupp.runtime.browser.http" ] = "/nupp/runtime/browser/http.g.nupp" ,
[ "nupp.runtime.browser.path" ] = "/nupp/runtime/browser/path.nupp" ,
[ "nupp.runtime.browser.suspension" ] = "/nupp/runtime/browser/suspension.g.nupp" ,
[ "nupp.runtime.browser.time" ] = "/nupp/runtime/browser/time.g.nupp" ,
[ "nupp.text.utf8" ] = "/nupp/text/utf8.nupp" ,
[ "nupp.codec.base64" ] = "/nupp/codec/base64.nupp" ,
[ "nupp.runtime.native" ] = "/nupp/runtime/native.nupp" ,
[ "nupp.time" ] = "/nupp/time/init.nupp" ,
[ "nupp.tasks" ] = "/nupp/tasks.nupp" ,
[ "nupp.digest" ] = "/nupp/digest/init.nupp" ,
[ "nupp.mac.spi" ] = "/nupp/mac/spi.nupp" ,
[ "nupp.system.spi" ] = "/nupp/system/spi.nupp" ,
[ "nupp.runtime.provider.digest" ] = "/nupp/runtime/provider/digest.nupp" ,
[ "nupp.runtime.provider.checksum" ] = "/nupp/runtime/provider/checksum.nupp" ,
[ "nupp.runtime.provider.mac" ] = "/nupp/runtime/provider/mac.nupp" ,
[ "nupp.runtime.provider.nativecrypto" ] = "/nupp/runtime/provider/nativecrypto.nupp" ,
[ "nupp.runtime.provider.nativesystem" ] = "/nupp/runtime/provider/nativesystem.nupp" ,
[ "nupp.digest.spi" ] = "/nupp/digest/spi.nupp" ,
[ "nupp.digest.internal.context" ] = "/nupp/digest/internal/context.nupp" ,
[ "nupp.digest.internal.builtin" ] = "/nupp/digest/internal/builtin.nupp" ,
[ "nupp.digest.internal.words" ] = "/nupp/digest/internal/words.nupp" ,
[ "nupp.digest.internal.constants" ] = "/nupp/digest/internal/constants.nupp" ,
[ "nupp.checksum" ] = "/nupp/checksum/init.nupp" ,
[ "nupp.checksum.spi" ] = "/nupp/checksum/spi.nupp" ,
[ "nupp.checksum.internal.builtin" ] = "/nupp/checksum/internal/builtin.nupp" ,
[ "nupp.runtime.provider.nativecrc" ] = "/nupp/runtime/provider/nativecrc.nupp" ,
[ "nupp.runtime.browser.crc" ] = "/nupp/runtime/browser/crc.nupp" ,
[ "nupp.mac" ] = "/nupp/mac/init.nupp" ,
[ "nupp.compression" ] = "/nupp/compression/init.nupp" ,
[ "nupp.compression.spi" ] = "/nupp/compression/spi.nupp" ,
[ "nupp.runtime.provider.nativecompression" ] = "/nupp/runtime/provider/nativecompression.nupp" ,
[ "nupp.util.internal.hash" ] = "/nupp/util/internal/hash.nupp" ,
[ "nupp.util.internal.uuid" ] = "/nupp/util/internal/uuid.nupp" ,
[ "nupp.codec.hex" ] = "/nupp/codec/hex.nupp" ,
[ "nupp.system" ] = "/nupp/system/init.nupp" ,
[ "nupp.host" ] = "/nupp/host/init.nupp" ,
[ "nupp.host.spi" ] = "/nupp/host/spi.nupp" ,
[ "nupp.host.pump" ] = "/nupp/host/pump.nupp" ,
[ "nupp.host.internal.values" ] = "/nupp/host/internal/values.g.nupp" ,
[ "nupp.runtime.provider.nativehost" ] = "/nupp/runtime/provider/nativehost.g.nupp" ,
[ "nupp.runtime.browser.host" ] = "/nupp/runtime/browser/host.g.nupp" ,
[ "nupp.runtime.browser.hostwire" ] = "/nupp/runtime/browser/hostwire.g.nupp" ,
[ "nupp.runtime.browser.system" ] = "/nupp/runtime/browser/system.nupp" ,
[ "nupp.util" ] = "/nupp/util/init.nupp" ,
[ "nupp.util.internal.bitset" ] = "/nupp/util/internal/bitset.nupp" ,
[ "nupp.util.internal.store" ] = "/nupp/util/internal/store.nupp" ,
[ "nupp.util.internal.protected" ] = "/nupp/util/internal/protected.nupp" ,
[ "nupp.mem" ] = "/nupp/mem/init.nupp" ,
[ "nupp.log" ] = "/nupp/log.nupp" ,
[ "nupp.suspension" ] = "/nupp/suspension/init.nupp" ,
[ "nupp.suspension.host" ] = "/nupp/suspension/host.nupp" ,
[ "nupp.compiler.runtime.peg" ] = "/nupp/compiler/runtime/peg.nupp" ,
[ "nupp.compiler.runtime.math" ] = "/nupp/compiler/runtime/math.nupp" ,
[ "nupp.compiler.runtime.reflect" ] = "/nupp/compiler/runtime/reflect.nupp" ,
[ "nupp.compiler.runtime.typewitness" ] = "/nupp/compiler/runtime/typewitness.nupp" ,
[ "nupp.runtime.hotreload" ] = "/nupp/runtime/hotreload.nupp" ,
[ "nupp.io.process" ] = "/nupp/io/process/init.nupp" ,
[ "nupp.workers" ] = "/nupp/workers/init.nupp" ,
[ "nupp.io.http" ] = "/nupp/io/http/init.nupp" ,
[ "nupp.codec.valuebuilder" ] = "/nupp/codec/valuebuilder.nupp" ,
[ "nupp.io.path" ] = "/nupp/io/path/init.nupp" ,
[ "nupp.io.path.provider" ] = "/nupp/io/path/provider.nupp" ,
[ "nupp.io.uri" ] = "/nupp/io/uri/init.nupp" ,
[ "nupp.io.files" ] = "/nupp/io/files/init.nupp" ,
[ "nupp.io.files.messages" ] = "/nupp/io/files/messages.nupp" ,
[ "nupp.io.files.path" ] = "/nupp/io/files/path.nupp" ,
[ "nupp.io.files.spi" ] = "/nupp/io/files/spi.nupp" ,
[ "nupp.io.net" ] = "/nupp/io/net/init.nupp" ,
[ "nupp.io.tls" ] = "/nupp/io/tls/init.nupp" ,
[ "nupp.io" ] = "/nupp/io/init.nupp" ,
}



local function loadBundled ( name , file , declarationFile ) 
local bundledSrc = bundledSource ( file )
if not bundledSrc then
return false
end
local result = parser . parse ( bundledSrc , name )
if # result . errors > 0 then
return false
end











local diags , moduleType , exports = check . check ( result , name , env , {
moduleName = name ,
declarationFile = declarationFile ,
strict = false ,
} )




local failed = false
for _ , diag in ipairs ( diags ) do
failed = failed or diag . severity == "error"
end
if moduleType and ( not failed or env . compat == "lua51" ) then
if name == "lpeg" and exports then
local pattern = exports . types . Pattern
if pattern and pattern . tag == "nominal" then
pattern . lpegPattern = true
end
local moduleRecord = ( moduleType . tag == "metatable" or moduleType . tag == "typeobject" ) and moduleType . of
or nil
if moduleRecord and moduleRecord . tag == "nominal" then
moduleRecord . lpegLibrary = true
moduleRecord . lpegPatternOrigin = pattern
end
end
return {
type = moduleType ,
exports = exports ,
source = bundledSrc ,
resource = file ,
declarationOnly = declarationFile ,
compatDiagnostics = diags ,
declared = cst . declaredModule ( result . root ) ~= nil ,
}
end

return false
end







local PENDING


= { }
for name , file in pairs ( BUNDLED ) do
PENDING [ name ] = { file = file , declaration = true }
end
for name , file in pairs ( BUNDLED_SOURCE ) do
PENDING [ name ] = { file = file , declaration = false }
end
local privacy = { }
env . bundledInternal = function ( name ) 
if privacy [ name ] ~= nil then
return privacy [ name ] == true
end
local hidden = false
local candidate = name
while candidate and not hidden do
local pending = PENDING [ candidate ]
local source = bundledSource ( pending and pending . file or ( "/" .. candidate : gsub ( "%." , "/" ) .. "/init.nupp" ) )
if source
and (
candidate == name
or not pending
or ( pending . file : match ( "/init%.nupp$" ) or pending . file : match ( "/init%.g%.nupp$" ) )
)
then
hidden = parser . parse ( source , candidate ) . root . documentationInternal == true
end
candidate = candidate : match ( "^(.*)%.[^.]+$" )
end
privacy [ name ] = hidden

return hidden
end
env . bundledImplementation = function ( name ) 
local pending = PENDING [ name ]
if pending == nil or pending . declaration then
return nil
end

return pending . file
end
env . loadBundledModule = function ( name ) 
local pending = PENDING [ name ]
return pending and loadBundled ( name , pending . file , pending . declaration ) or false
end
setmetatable ( env . bundled , {
__index = function ( store , name ) 
local loaded = env . loadBundledModule ( name )
rawset ( store , name , loaded )

return loaded
end
} )

return env
end




function envMod . fmtMethodParensDefault ( env ) 
local fmtConfig = env . config . fmt
return not ( fmtConfig and fmtConfig . methodParens == false )
end

local __nuppExportValue= envMod ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.env"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.env"]=__nuppExports;return __nuppExports