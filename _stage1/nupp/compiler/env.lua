_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);















local parser = require ( "nupp.compiler.parser" )
local check = require ( "nupp.compiler.check" )
local diagnostics = require ( "nupp.compiler.diagnostics" )
local cst = require ( "nupp.compiler.cst" )
local lexer = require ( "nupp.compiler.lexer" )
local T = require ( "nupp.compiler.types" )
local annotationMod = require ( "nupp.compiler.annotations" )
local native = require ( "nupp.compiler.native" )
local fs = require ( "nupp.compiler.fs" )
local bundledMod = require ( "nupp.compiler.bundled" )

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

local runtimeModulePatterns = { "/%s.nupp" , "/%s.g.nupp" , "/%s.lua" , "/%s/init.nupp" , "/%s/init.g.nupp" , "/%s/init.lua" , }

local function moduleDir ( )
local src = debug . getinfo ( 1 , "S" ) . source
return src : match ( "^@(.*)[/\\]" ) or "."
end




function envMod . compilerRoot ( )
local dir = moduleDir ( ) : gsub ( "\\" , "/" )
return dir : match ( "^(.*)/src/nupp/compiler$" ) or os . getenv ( "NUPP_COMPILER_ROOT" )
end

local function readFile ( path )
local f = io . open ( path , "rb" )
if not f then
return nil
end
local content = f : read ( "*a" )
f : close ( )

return content
end



local function normalizePath ( path )
path = path : gsub ( "\\" , "/" ) : gsub ( "/+" , "/" )
path = path : gsub ( "^%./" , "" ) : gsub ( "/%./" , "/" )
return ( path : gsub ( "/$" , "" ) )
end



















local listingsByEnv = setmetatable ( { } , { __mode = "k" } )

local function skipBookkeepingDirectory ( name )
return name : sub ( 1 , 1 ) == "."
end

local function listLjppFiles ( env , root , withDeclarations )
local listings = listingsByEnv [ env ]
if not listings then
listings = { }
listingsByEnv [ env ] = listings
end
local key = ( withDeclarations and "d\0" or "\0" ) .. root
if listings [ key ] then
return listings [ key ]
end
local files = { }
for _ , path in ipairs ( fs . listFiles ( root , skipBookkeepingDirectory ) ) do
if path : match ( "%.nupp$" ) and ( withDeclarations or not path : match ( "%.d%.nupp$" ) ) then
files [ # files + 1 ] = normalizePath ( path )
end
end
listings [ key ] = files

return files
end



local function isBookkeepingPath ( path , outDir )
local generated = path == outDir or path : sub ( 1 , # outDir + 1 ) == outDir .. "/"
local hidden = ( "/" .. path ) : find ( "/%." ) ~= nil
return generated or hidden
end

local function outDirFor ( env )
local rootDir = env . rootDir or "."
local build = ( env . config or { } ) . build or { }
return normalizePath ( rootDir .. "/" .. ( build . outDir or "build" ) )
end




function envMod . outDir ( env )
return outDirFor ( env )
end

function envMod . listProjectFiles ( env )
local files , seen = { } , { }
local outDir = outDirFor ( env )
for _ , root in ipairs ( env . roots or { } ) do
for _ , path in ipairs ( listLjppFiles ( env , root ) ) do
if not seen [ path ] and not isBookkeepingPath ( path , outDir ) then
seen [ path ] = true
files [ # files + 1 ] = path
end
end
end
table . sort ( files )

return files
end



















function envMod . listSourceFiles ( env , withDeclarations )
if withDeclarations == nil then
withDeclarations = true
end
local rootDir = env . rootDir or "."
local roots = { }
for _ , dir in ipairs ( ( env . config or { } ) . include or { } ) do
roots [ # roots + 1 ] = rootDir .. "/" .. dir
end
if # roots == 0 then
roots [ 1 ] = rootDir
end
local outDir = outDirFor ( env )
local files , seen = { } , { }
for _ , root in ipairs ( roots ) do
for _ , path in ipairs ( listLjppFiles ( env , root , withDeclarations ) ) do
if not seen [ path ] and not isBookkeepingPath ( path , outDir ) then
seen [ path ] = true
files [ # files + 1 ] = path
end
end
end
table . sort ( files )

return files
end



















function envMod . projectRoots ( rootDir , config )
local roots = { rootDir }
for _ , dir in ipairs ( ( config or { } ) . include or { } ) do
roots [ # roots + 1 ] = rootDir .. "/" .. dir
end

return roots
end

function envMod . isProjectPath ( env , path )
path = normalizePath ( path )
if not path : match ( "%.nupp$" ) then
return false
end
if isBookkeepingPath ( path , outDirFor ( env ) ) then
return false
end
for _ , rawRoot in ipairs ( env . roots or { } ) do
local root = normalizePath ( rawRoot )
if root == "." or root == "" then
if path : sub ( 1 , 1 ) ~= "/" then
return true
end
elseif path : sub ( 1 , # root + 1 ) == root .. "/" then
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
local rel = nil
if root == "." or root == "" then
if path : sub ( 1 , 1 ) ~= "/" then
rel = path
end
elseif path : sub ( 1 , # root + 1 ) == root .. "/" then
rel = path : sub ( # root + 2 )
end
if rel and rel : match ( "%.nupp$" ) and not rel : match ( "%.d%.nupp$" ) then
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
if rel and rel : match ( "%.d%.nupp$" ) then
rel = rel : gsub ( "%.d%.nupp$" , "" ) : gsub ( "/init$" , "" )
local name = rel : gsub ( "/" , "." )
if name ~= "" then
return name
end
end
end

return envMod . moduleNameInRoots ( env . roots or { } , path )
end

local function declarationKind ( stat )
if stat . kind == "recordDecl" then
return stat . declKind
end
return "type"
end

local function annotationString ( expr )
if not expr or expr . kind ~= "string" or not expr . token then
return nil
end
local text = expr . token . text
local chunk = loadstring ( "return " .. text )
if chunk then
local ok , value = pcall ( chunk )
if ok and type ( value ) == "string" then
return value
end
end

return nil
end

local function syntacticDeprecation ( application )
local deprecated = { }
for _ , argument in ipairs ( application . annotationArgs or { } ) do
local name = argument . name and argument . name . text or "reason"
local value = annotationString ( argument . expr )
if ( name == "reason" or name == "replacement" ) and value then
deprecated [ name ] = value
end
end

return deprecated
end

local function annotatedDeclaration ( stat )
local annotationDefinition = false
local deprecated = nil
while stat and stat . kind == "pragmaStmt" do
if stat . name and stat . name . text == "annotation" then
annotationDefinition = true
elseif stat . name and stat . name . text == "deprecated" then
deprecated = syntacticDeprecation ( stat )
end
stat = stat . stat
end

return stat , annotationDefinition , deprecated
end



local function declarationSignature ( stat )
local parts = { }
local function walk ( value )
if cst . isToken ( value ) then
if value . kind ~= "eof" and not value . missing then
parts [ # parts + 1 ] = value . kind .. "\1" .. value . text
end
else
for _ , child in ipairs ( value ) do
walk ( child )
end
end
end

walk ( stat )

return table . concat ( parts , "\2" )
end












local function declarationToken ( tok )



local trivia = { }
for index = 1 , tok and tok . triviaCount or 0 do
trivia [ index ] = lexer . triviaRecord ( tok , index )
end

return { kind = tok . kind , text = tok . text , offset = tok . offset , line = tok . line , col = tok . col , trivia = trivia }
end




function envMod . projectHeader ( env , path , parsed )
path = normalizePath ( path )
local header = { path = path , moduleName = envMod . moduleNameForPath ( env , path ) , declarations = { } , }
if not parsed or # parsed . errors > 0 then
return header
end
local moduleLocal = cst . returnedLocal ( parsed . root )
header . moduleLocal = moduleLocal
for _ , block in ipairs ( parsed . root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
local declaration , isAnnotation , deprecated = annotatedDeclaration ( stat )
local visibility = declaration and cst . declVisibility ( declaration , moduleLocal )
if declaration and (
declaration . kind == "typeAlias" or declaration . kind == "recordDecl"
) and ( visibility == "module" or visibility == "global" ) then
header . declarations [
# header . declarations + 1
] = {
name = declaration . name . text ,
kind = declarationKind ( declaration ) ,
statKind = declaration . kind ,
visibility = visibility ,
token = declarationToken ( declaration . name ) ,
signature = declarationSignature ( stat ) ,
isAnnotation = isAnnotation ,
deprecated = deprecated ,
}
end
end
end

return header
end




function envMod . buildProjectIndex ( headers , nominals )
local index = {
byName = { } ,
byPath = { } ,
modules = { } ,
annotationsByName = { } ,




moduleBasenames = { } ,
}
nominals = nominals or { }
for _ , header in ipairs ( headers or { } ) do
local moduleName = header . moduleName
if moduleName then
index . modules [ moduleName ] = header . path
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
} ,
}
if declaration . statKind ~= "typeAlias" then
local nominal = nominals [ identityKey ]
if not nominal then
nominal = T . nominal ( entry . name , entry . kind )
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
for _ , named in pairs ( index . moduleBasenames ) do
table . sort ( named )
end

return index
end








function envMod . headerStore ( env )
if env . headerStoreOpened then
return env . headerStore
end
env . headerStoreOpened = true
if env . cacheDisabled then
return nil
end
local storeMod = require ( "nupp.compiler.build.store" )
local cacheMod = require ( "nupp.compiler.build.cache" )






env . headerStore = storeMod . open (
( env . cacheDir or ( outDirFor ( env ) .. "/cache" ) ) .. "/headers.buf" ,
cacheMod . toolFingerprint ( )
)

return env . headerStore
end







function envMod . headerKey ( env , path , text )
local hashMod = require ( "nupp.compiler.build.hash" )
if not env . headerRootsKey then
local roots = { }
for index , root in ipairs ( env . roots or { } ) do
roots [ index ] = normalizePath ( root )
end
table . sort ( roots )
env . headerRootsKey = hashMod . digest ( table . concat ( roots , "\0" ) )
end

return hashMod . digest ( env . headerRootsKey .. "\0" .. path .. "\0" .. text )
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
env . annotationKeyMemo = require ( "nupp.compiler.build.hash" ) . digest ( table . concat ( parts , "\1" ) )

return env . annotationKeyMemo
end






function envMod . formatStore ( env )
if env . formatStoreOpened then
return env . formatStore
end
env . formatStoreOpened = true
if env . cacheDisabled then
return nil
end
local storeMod = require ( "nupp.compiler.build.store" )
local cacheMod = require ( "nupp.compiler.build.cache" )
env . formatStore = storeMod . open (
( env . cacheDir or ( outDirFor ( env ) .. "/cache" ) ) .. "/format.buf" ,
cacheMod . toolFingerprint ( )
)

return env . formatStore
end

function envMod . typeFunctionStore ( env )
if env . typeFunctionStoreOpened then
return env . typeFunctionStore
end
env . typeFunctionStoreOpened = true
if env . cacheDisabled then
return nil
end
local storeMod = require ( "nupp.compiler.build.store" )
local cacheMod = require ( "nupp.compiler.build.cache" )
env . typeFunctionStore = storeMod . open (
( env . cacheDir or ( outDirFor ( env ) .. "/cache" ) ) .. "/type-functions.buf" ,
cacheMod . toolFingerprint ( )
)

return env . typeFunctionStore
end



function envMod . persist ( env )
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





if not envMod . isProjectPath ( env , filename ) then
return nil
end
local path = normalizePath ( filename )
local entries = env . projectPathEntries and env . projectPathEntries (
env ,
path
) or projectIndexFor ( env ) . byPath [ path ] or { }
for _ , entry in ipairs ( entries ) do
if entry . name == name and entry . kind == kind and entry . visibility == visibility then
return entry . type , entry
end
end

return nil
end

local function findModulePath ( env , name , patterns )
local rel = name : gsub ( "%." , "/" )
for _ , root in ipairs ( env . roots ) do
for _ , pattern in ipairs ( patterns ) do
local candidate = root .. pattern : format ( rel )
local f = io . open ( candidate , "rb" )
if f then
f : close ( )
return candidate
end
end
end
for _ , root in ipairs ( env . typeRoots or { } ) do
for _ , pattern in ipairs ( patterns ) do
local candidate = root .. pattern : format ( rel )
local f = io . open ( candidate , "rb" )
if f then
f : close ( )
return candidate
end
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

return false
end



function envMod . findModulePath ( env , name )
return findModulePath ( env , name , modulePatterns )
end




function envMod . findRuntimeModulePath ( env , name )
return findModulePath ( env , name , runtimeModulePatterns )
end

local function seededExports ( env , path )
local exports = { types = { } , typeDefs = { } , values = { } , valueDefs = { } , comptimeFunctions = { } }
path = normalizePath ( path )
local entries = env . projectPathEntries and env . projectPathEntries (
env ,
path
) or projectIndexFor ( env ) . byPath [ path ] or { }
for _ , entry in ipairs ( entries ) do
if entry . visibility == "module" and entry . type then
exports . types [ entry . name ] = entry . type
exports . typeDefs [ entry . name ] = entry . definition
if entry . kind == "struct" then
exports . values [ entry . name ] = entry . type
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
local record = { inProgress = true , path = path , exports = seededExports ( env , path ) , }
env . loaded [ name ] = record
env . loadedPaths [ path ] = record
local result = parser . parse ( src , path )
if # result . errors == 0 then
local _ , moduleType , exports = check . check ( result , path , env , {
moduleName = name ,
initialExports = record . exports ,
} )
record . type = moduleType or T . any
record . exports = exports or record . exports
else
record . type = T . any
end
record . inProgress = false

return record
end



function envMod . resolveModule ( env , name )
local record = loadModule ( env , name )
if not record then
return nil
end

return record . inProgress and T . any or record . type
end

function envMod . resolveModuleExports ( env , name )
local record = loadModule ( env , name )
return record and record . exports or nil
end

function envMod . resolveCallGuarantees ( env , module , member )
local exports = envMod . resolveModuleExports ( env , module )
return exports and exports . callGuarantees and exports . callGuarantees [ member ] or nil
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
local entries = env . projectEntries and env . projectEntries ( env , name ) or projectIndexFor ( env ) . byName [ name ]
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
local entries = env . projectEntries and env . projectEntries ( env , name ) or projectIndexFor ( env ) . byName [ name ] or { }
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
local entries = env . projectEntries and env . projectEntries ( env , name ) or projectIndexFor ( env ) . byName [ name ]
local entry , err , conflicts = loadedGlobal ( env , entries , "struct" )
if not entry then
return nil , nil , err , nil , conflicts
end

return entry . type , entry . definition , nil , entry . moduleName
end




function envMod . resolveProjectAnnotation ( env , filename , name )
local entries = env . projectAnnotations and env . projectAnnotations (
env ,
name
) or projectIndexFor ( env ) . annotationsByName [ name ]
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
local entries = env . projectEntries and env . projectEntries (
env ,
typeName
) or projectIndexFor ( env ) . byName [ typeName ] or { }
for _ , candidate in ipairs ( entries ) do
if candidate . moduleName == moduleName and candidate . visibility == "module" and (
candidate . kind == "record" or candidate . kind == "struct"
) then
entry = candidate
break
end
end
if not entry then





local bundled = env . bundled and env . bundled [ moduleName ] or nil
local exported = bundled and bundled . exports and bundled . exports . types [ typeName ] or nil
if exported and exported . tag == "nominal" and (
exported . declKind == "record" or exported . declKind == "struct"
) then
return exported , bundled . exports . typeDefs [ typeName ]
end

return nil
end
if entry . type then
return entry . type , entry . definition
end
local exports = env . resolveModuleExports ( env , moduleName )

return exports and exports . types [ typeName ] or entry . type , exports and exports . typeDefs [ typeName ] or entry . definition
end



local function configAt ( dir )
local chunk = loadfile ( dir .. "/nupp.lua" )
if not chunk then
return { }
end
local ok , loaded = pcall ( chunk )

return ok and type ( loaded ) == "table" and loaded or { }
end











function envMod . new ( rootDir , opts )
rootDir = rootDir or "."
local env = {
globals = { } ,
globalTypes = { } ,
globalTypeDefs = { } ,
annotations = annotationMod . new ( ) ,
loaded = { } ,
loadedPaths = { } ,
bundled = { } ,
resolveModule = envMod . resolveModule ,
resolveModuleExports = envMod . resolveModuleExports ,
observeCallGuarantee = envMod . observeCallGuarantee ,
resolveCallGuarantees = envMod . resolveCallGuarantees ,
resolveProjectType = envMod . resolveProjectType ,
resolveProjectValue = envMod . resolveProjectValue ,
resolveProjectAnnotation = envMod . resolveProjectAnnotation ,
resolveQualifiedType = envMod . resolveQualifiedType ,
exportedNominal = envMod . exportedNominal ,
modulesNamed = envMod . modulesNamed ,
modulesExporting = envMod . modulesExporting ,
declarationType = envMod . declarationType ,
moduleNameForPath = envMod . moduleNameForPath ,
ensureProjectIndex = envMod . ensureProjectIndex ,
openTypeFunctionStore = envMod . typeFunctionStore ,
rootDir = rootDir ,




cacheDisabled = opts and opts . cache == false or nil ,
cacheDir = opts and opts . cacheDir or nil ,
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
local selectedTarget = env . config . _target or require ( "nupp.compiler.build.tasks" ) . targetConfig ( env . config )
env . layoutTarget = selectedTarget and selectedTarget . layoutTarget or nil

local typeRoots = opts and opts . typeRoots or nil
if not typeRoots then



local rocks = selectedTarget and require (
"nupp.compiler.build.deps"
) . rockPaths ( rootDir , env . config , selectedTarget ) or nil
typeRoots = rocks and rocks . typeRoots or { }
end
env . typeRoots = { }
for _ , dir in ipairs ( typeRoots or { } ) do
env . typeRoots [ # env . typeRoots + 1 ] = normalizePath ( dir )
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
addRoot ( folder .. "/" .. dir )
end
end
end


local preludePath = moduleDir ( ) .. "/decls/prelude.d.nupp"
local preludeOrigin = "nupp:prelude.d.nupp"
local src = bundledSource ( "/decls/prelude.d.nupp" )




assert ( src , "internal error: cannot read the prelude at " .. preludePath )
do
local result = parser . parse ( src , preludeOrigin )
assert (
# result . errors == 0 ,
"internal error: prelude has syntax errors: " .. ( result . errors [ 1 ] and result . errors [ 1 ] . msg or "?" )
)
local diags = check . check ( result , preludeOrigin , env , { declareGlobals = true } )
local fatal = nil
for _ , diagnostic in ipairs ( diags ) do
if diagnostics . isFatal ( diagnostic ) then
fatal = diagnostic
break
end
end
assert ( not fatal , "internal error: prelude has type errors: " .. ( fatal and fatal . msg or "?" ) )
local implementationSource = bundledSource ( "/decls/prelude_impl.d.nupp" )
assert ( implementationSource , "internal error: cannot read the prelude implementation" )
local function checkImplementation ( )
local implementation = parser . parse ( implementationSource , preludeOrigin )
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
local implementationDiags = check . check ( implementation , preludeOrigin , env , {
moduleName = "nupp.prelude" ,
strict = true
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
break
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
local generated , generatedDiags = require ( "nupp.compiler.gen" ) . generate ( implementation , preludeOrigin )
local generatedFatal = nil
for _ , diagnostic in ipairs ( generatedDiags ) do
if diagnostics . isFatal ( diagnostic ) then
generatedFatal = diagnostic
break
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
end




local BUNDLED = {
[ "string.buffer" ] = "/decls/stringbuffer.d.nupp" ,
[ "cjson" ] = "/decls/cjson.d.nupp" ,
[ "cjson.safe" ] = "/decls/cjsonsafe.d.nupp" ,
[ "ffi" ] = "/decls/ffi.d.nupp" ,
[ "lpeg" ] = "/decls/lpeg.d.nupp" ,
[ "re" ] = "/decls/re.d.nupp" ,



[ "jit.util" ] = "/decls/jit/util.d.nupp" ,
[ "jit.profile" ] = "/decls/jit/profile.d.nupp" ,
[ "jit.zone" ] = "/decls/jit/zone.d.nupp" ,
[ "jit.vmdef" ] = "/decls/jit/vmdef.d.nupp" ,
[ "nupp.io.processnative" ] = "/decls/processnative.d.nupp" ,
[ "nupp.io.httpnative" ] = "/decls/httpnative.d.nupp" ,
[ "nupp.workers.native" ] = "/decls/workersnative.d.nupp" ,
}





local BUNDLED_SOURCE = {
[ "nupp.resources" ] = "/nupp/resources.nupp" ,
[ "nupp.dynamic" ] = "/nupp/dynamic.nupp" ,
[ "nupp.derive" ] = "/nupp/derive.nupp" ,
[ "nupp.zone" ] = "/nupp/zone.nupp" ,
[ "nupp.profile" ] = "/nupp/profile.nupp" ,
[ "nupp.span" ] = "/nupp/span.nupp" ,
[ "nupp.heap" ] = "/nupp/heap.nupp" ,
[ "nupp.suspension" ] = "/nupp/suspension.nupp" ,
[ "nupp.io.process" ] = "/nupp/io/process.nupp" ,
[ "nupp.io.processtypes" ] = "/nupp/io/processtypes.nupp" ,
[ "nupp.workers" ] = "/nupp/workers.nupp" ,
[ "nupp.io.http" ] = "/nupp/io/http.nupp" ,
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
strict = false
} )
if # diags == 0 and moduleType then
if name == "lpeg" and exports then
local pattern = exports . types . Pattern
if pattern and pattern . tag == "nominal" then
pattern . lpegPattern = true
end
local moduleRecord = (
moduleType . tag == "metatable" or moduleType . tag == "typeobject"
) and moduleType . of or nil
if moduleRecord and moduleRecord . tag == "nominal" then
moduleRecord . lpegLibrary = true
moduleRecord . lpegPatternOrigin = pattern
end
end
return { type = moduleType , exports = exports }
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
setmetatable ( env . bundled , {
__index = function ( store , name )
local pending = PENDING [ name ]
local loaded = false
if pending then
loaded = loadBundled ( name , pending . file , pending . declaration )
end
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

return envMod
