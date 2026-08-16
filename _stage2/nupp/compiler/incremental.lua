_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
















local query = require ( "nupp.compiler.query" )
local parser = require ( "nupp.compiler.parser" )
local check = require ( "nupp.compiler.check" )
local envMod = require ( "nupp.compiler.env" )
local storeMod = require ( "nupp.compiler.build.store" )

local incremental = { }























































incremental.Inc = {} incremental.Inc.__index = incremental.Inc





























































































function incremental . new ( rootDir , opts )
opts = opts or { }
local env = envMod . new ( rootDir , opts )

local strict = opts . strict
local q = query . new ( )
local inc = setmetatable({ env =  env ,  q =  q }, incremental.Inc)





local headerStore = envMod . headerStore ( env ) or storeMod . open ( nil , "" )
inc . headerStore = headerStore

















local function checkpoint ( )
local host = env . host
if not host then
return
end
host . pump ( )
if host . cancelled ( ) then
error ( host . cancellation , 0 )
end
end

local diskPaths = { }
local openPaths = { }
for _ , path in ipairs ( envMod . listProjectFiles ( env ) ) do
diskPaths [ path ] = true
end


local function updateProjectFiles ( )
local files = { }
local seen = { }
for path in pairs ( diskPaths ) do
seen [ path ] = true
files [ # files + 1 ] = path
end
for path in pairs ( openPaths ) do
if not seen [ path ] then
files [ # files + 1 ] = path
end
end
table . sort ( files )
q : setInput ( "projectFiles" , "root" , files )
end

updateProjectFiles ( )

q : define ( "fileText" , function ( _ , path )
local f = io . open ( path , "rb" )
if not f then
return nil
end
local s = f : read ( "*a" )
f : close ( )

return s
end )

q : define ( "externalFile" , function ( _ , path )
local f = io . open ( path , "rb" )
if not f then
return nil
end
local s = f : read ( "*a" )
f : close ( )

return s
end )

q : define ( "parse" , function ( self , path )
local text = self : get ( "fileText" , path )
if not text then
return nil
end

return parser . parse ( text , path )
end )



local function sameHeader ( a , b )
if not a or not b then
return false
end
if a . path ~= b . path
or a . moduleName ~= b . moduleName
or a . moduleLocal ~= b . moduleLocal
or # a . declarations ~= # b . declarations
then
return false
end
for index , left in ipairs ( a . declarations ) do
local right = b . declarations [ index ]
if left . name ~= right . name
or left . kind ~= right . kind
or left . statKind ~= right . statKind
or left . visibility ~= right . visibility
or left . isAnnotation ~= right . isAnnotation
or left . signature ~= right . signature
or left . token . offset ~= right . token . offset
then
return false
end
end

return true
end










q : define (
"projectHeader" ,
function ( self , path )
checkpoint ( )
local text = self : get ( "fileText" , path )
if text == nil then
return envMod . projectHeader ( env , path , nil )
end
local key = envMod . headerKey ( env , path , text )
local cached = headerStore . get ( key )
if cached then
return cached
end


local header = envMod . projectHeader ( env , path , self : get ( "parse" , path ) )
headerStore . put ( key , header )

return header
end ,
sameHeader
)

local projectNominals = env . projectNominals or { }
env . projectNominals = projectNominals
q : define ( "projectIndex" , function ( self )
local headers = { }
for _ , path in ipairs ( self : get ( "projectFiles" , "root" ) ) do
headers [ # headers + 1 ] = self : get ( "projectHeader" , path )
end

return envMod . buildProjectIndex ( headers , projectNominals )
end )

local hash = require ( "nupp.compiler.build.hash" )
local stable = require ( "nupp.compiler.build.cache" ) . stable

local function entrySurface ( entry )
return {
name = entry . name ,
path = entry . path ,
moduleName = entry . moduleName ,
visibility = entry . visibility ,
kind = entry . kind ,
signature = entry . signature ,
isAnnotation = entry . isAnnotation ,
offset = entry . definition and entry . definition . token and entry . definition . token . offset or nil ,
}
end

local function entryListSurface ( entries )
local out = { }
for _ , entry in ipairs ( entries or { } ) do
out [ # out + 1 ] = entrySurface ( entry )
end

return out
end

local function sameStable ( a , b )
return stable ( a ) == stable ( b )
end

local function sameEntryLists ( a , b )
return sameStable ( entryListSurface ( a ) , entryListSurface ( b ) )
end

q : define (
"projectEntries" ,
function ( self , name )
return self : get ( "projectIndex" , "root" ) . byName [ name ] or { }
end ,
sameEntryLists
)

q : define (
"projectPathEntries" ,
function ( self , path )
return self : get ( "projectIndex" , "root" ) . byPath [ path ] or { }
end ,
sameEntryLists
)

q : define ( "projectModulePath" , function ( self , name )
return self : get ( "projectIndex" , "root" ) . modules [ name ]
end )

q : define (
"projectModuleBasenames" ,
function ( self , short )
return self : get ( "projectIndex" , "root" ) . moduleBasenames [ short ]
end ,
sameStable
)

q : define (
"projectAnnotations" ,
function ( self , name )
return self : get ( "projectIndex" , "root" ) . annotationsByName [ name ]
end ,
sameEntryLists
)



env . ensureProjectIndex = function ( )
return q : get ( "projectIndex" , "root" )
end


local function modulePath ( self , name )
return self : get ( "projectModulePath" , name ) or envMod . findModulePath ( env , name )
end




q : define ( "materializeDerives" , function ( _ , fingerprint )
return fingerprint
end )
local function internDeriveRecipe ( self , plan )
local executions = q . stats . materializeDerives or 0
q : get ( "materializeDerives" , plan . fingerprint )
return plan , ( q . stats . materializeDerives or 0 ) == executions
end

local checkModule = function ( self , path )
checkpoint ( )
local result = self : get ( "parse" , path )
if not result then
return { diags = { } , moduleType = nil , missing = true }
end
if # result . errors > 0 then
return { diags = result . errors , moduleType = nil , syntax = true , result = result }
end

result . externalInputs = { }
local qenv = setmetatable (
{
resolveModule = function ( _ , name )
local interface = self : get ( "moduleInterface" , name )
return interface and interface . type or nil
end ,
resolveModuleExports = function ( _ , name )
return self : get ( "moduleExports" , name )
end ,
observeCallGuarantee = function ( _ , module , member , identity , guarantee )
local key = table . concat ( { module , member , identity , guarantee } , "\0" )
local observed = self : get ( "moduleCallGuarantee" , key )
return observed and observed : sub ( - 8 ) == "\0present" or false
end ,
resolveCallGuarantees = function ( _ , module , member )
return self : get ( "moduleCallGuarantees" , module .. "\0" .. member )
end ,
projectEntries = function ( _ , name )
return self : get ( "projectEntries" , name )
end ,
projectPathEntries = function ( _ , requestedPath )
return self : get ( "projectPathEntries" , requestedPath )
end ,
projectModulePath = function ( _ , name )
return self : get ( "projectModulePath" , name )
end ,
projectModuleBasenames = function ( _ , short )
return self : get ( "projectModuleBasenames" , short )
end ,
projectAnnotations = function ( _ , name )
return self : get ( "projectAnnotations" , name )
end ,
externalFile = function ( _ , externalPath )
return self : get ( "externalFile" , externalPath )
end ,
observeExternalInput = function ( _ , input )
for _ , externalPath in ipairs ( input . paths or { } ) do
self : get ( "externalFile" , externalPath )
end
result . externalInputs [ # result . externalInputs + 1 ] = input
end ,
openTypeFunctionStore = function ( )




return envMod . typeFunctionStore ( env )
end ,
internDeriveRecipe = internDeriveRecipe ,
} ,
{ __index = env }
)
local external = envMod . isDependencyTypePath ( env , path )
local diags , moduleType , exports = check . check (
result ,
path ,
qenv ,
{
moduleName = envMod . moduleNameForPath ( env , path ) ,


strict = external and false or strict ,
}
)

return { diags = diags , moduleType = moduleType , exports = exports , result = result }
end





local observer = opts . observe
if observer then
q : define ( "checkModule" , function ( self , path )
observer . checking ( path )
local result = checkModule ( self , path )
observer . checked ( path )

return result
end )
else
q : define ( "checkModule" , checkModule )
end

q : define (
"moduleInterface" ,
function ( self , name )
local path = modulePath ( self , name )
if not path then

local bundled = env . bundled and env . bundled [ name ]
return bundled and {
type = bundled . type ,
nominalEffectFingerprint = bundled . exports and bundled . exports . nominalEffectFingerprint ,
deriveInterfaceFingerprint = bundled . exports and bundled . exports . deriveInterfaceFingerprint ,
} or nil
end


local r = self : get ( "checkModule" , path )

return r and {
type = r . moduleType ,
nominalEffectFingerprint = r . exports and r . exports . nominalEffectFingerprint ,
deriveInterfaceFingerprint = r . exports and r . exports . deriveInterfaceFingerprint ,
} or nil
end ,
function ( left , right )
if left == nil or right == nil then
return left == right
end
return left . type == right . type
and left . nominalEffectFingerprint == right . nominalEffectFingerprint
and left . deriveInterfaceFingerprint == right . deriveInterfaceFingerprint
end
)

local function sameTypeMap ( left , right )
left , right = left or { } , right or { }
for name , value in pairs ( left ) do
if right [ name ] ~= value then
return false
end
end
for name , value in pairs ( right ) do
if left [ name ] ~= value then
return false
end
end

return true
end

local function sameDeprecation ( left , right )
if left == nil or right == nil then
return left == right
end

return left . reason == right . reason and left . replacement == right . replacement
end

local function sameDefinitionMap ( left , right )
left , right = left or { } , right or { }
for name , definition in pairs ( left ) do
local other = right [ name ]
if not other or not sameDeprecation ( definition . deprecated , other . deprecated ) then
return false
end
end
for name in pairs ( right ) do
if not left [ name ] then
return false
end
end

return true
end

local function sameExports ( left , right )
if left == nil or right == nil then
return left == right
end
return left . nominalEffectFingerprint == right . nominalEffectFingerprint
and left . deriveInterfaceFingerprint == right . deriveInterfaceFingerprint
and left . comptimeFunctionFingerprint == right . comptimeFunctionFingerprint
and sameTypeMap (
left . types ,
right . types
) and sameTypeMap (
left . values ,
right . values
) and sameDefinitionMap ( left . typeDefs , right . typeDefs ) and sameDefinitionMap ( left . valueDefs , right . valueDefs )
end

q : define (
"moduleExports" ,
function ( self , name )
local path = modulePath ( self , name )
if not path then



local bundled = env . bundled and env . bundled [ name ]
return bundled and bundled . exports or nil
end
local r = self : get ( "checkModule" , path )

return r and r . exports or nil
end ,
sameExports
)



q : define (
"moduleCallGuarantees" ,
function ( self , key )
local module , member = key : match ( "^([^%z]+)%z(.+)$" )
local path = module and modulePath ( self , module ) or nil
local exports
if path then
local checked = self : get ( "checkModule" , path )
exports = checked and checked . exports or nil
else
local bundled = module and env . bundled and env . bundled [ module ]
exports = bundled and bundled . exports or nil
end

return exports and exports . callGuarantees and exports . callGuarantees [ member ] or nil
end ,
sameStable
)

q : define ( "moduleCallGuarantee" , function ( self , key )
local module , member , identity , guarantee = key : match ( "^([^%z]+)%z([^%z]+)%z([^%z]+)%z([^%z]+)$" )
local entry = module and self : get ( "moduleCallGuarantees" , module .. "\0" .. member ) or nil
local actualIdentity = entry and entry . identity or identity or ( ( module or "?" ) .. "." .. ( member or "?" ) )
local present = entry and entry [ guarantee ] == true

return actualIdentity .. ( present and "\0present" or "\0absent" )
end )


function inc . openDocument ( path , text )
local wasOpen = openPaths [ path ]
if envMod . moduleNameForPath ( env , path ) then
openPaths [ path ] = true
end
if not wasOpen and openPaths [ path ] and not diskPaths [ path ] then
updateProjectFiles ( )
end
q : setInput ( "fileText" , path , text )
end

inc . changeDocument = inc . openDocument
function inc . closeDocument ( path )
q : clearInput ( "fileText" , path )
if openPaths [ path ] then
openPaths [ path ] = nil
if not diskPaths [ path ] then
updateProjectFiles ( )
end
end
end




function inc . diskChanged ( path , changeType )
local existed = diskPaths [ path ] and true or false
if changeType == 3 then
diskPaths [ path ] = nil
elseif envMod . moduleNameForPath ( env , path ) then
diskPaths [ path ] = true
end
if not openPaths [ path ] then
q : clearInput ( "fileText" , path )
end
q : clearInput ( "externalFile" , path )
if existed ~= ( diskPaths [ path ] and true or false ) then
updateProjectFiles ( )
end
end


function inc . checkFile ( path )
return q : get ( "checkModule" , path )
end

function inc . projectIndex ( )
return q : get ( "projectIndex" , "root" )
end

function inc . projectFiles ( )
return q : get ( "projectFiles" , "root" )
end





function inc . fileText ( path )
return q : get ( "fileText" , path )
end

function inc . externalFile ( path )
return q : get ( "externalFile" , path )
end

function inc . projectHeader ( path )
return q : get ( "projectHeader" , path )
end




function inc . modulePath ( name )
return modulePath ( q , name )
end

function inc . moduleDependencies ( path )
q : get ( "checkModule" , path )
local byPath = q . memo . checkModule
local memo = byPath and byPath [ path ]
local names = { }
local seen = { }
for _ , dep in ipairs ( memo and memo . deps or { } ) do
if dep . name == "moduleInterface" and not seen [ dep . key ] then
seen [ dep . key ] = true
names [ # names + 1 ] = dep . key
end
end
table . sort ( names )

return names
end

local PROJECT_QUERY = {
projectEntries = true ,
projectPathEntries = true ,
projectModulePath = true ,
projectModuleBasenames = true ,
projectAnnotations = true ,
moduleCallGuarantees = true ,
moduleCallGuarantee = true ,
}

local function projectFingerprint ( name , key )
local value = q : get ( name , key )
if name == "projectEntries" or name == "projectPathEntries" or name == "projectAnnotations" then
value = entryListSurface ( value )
end

return hash . digest ( stable ( value ) )
end

local function projectDependencyPaths ( name , key )
local value = q : get ( name , key )
local paths , seen = { } , { }
local function add ( path )
if type ( path ) == "string" and not seen [ path ] then
seen [ path ] = true
paths [ # paths + 1 ] = path
end
end

if name == "moduleCallGuarantees" or name == "moduleCallGuarantee" then
local module = key : match ( "^([^%z]+)" )
add ( module and modulePath ( q , module ) or nil )
elseif name == "projectModulePath" then
add ( value )
elseif name == "projectPathEntries" then
add ( key )
for _ , entry in ipairs ( value or { } ) do
add ( entry . path )
end
elseif name == "projectEntries" or name == "projectAnnotations" then
for _ , entry in ipairs ( value or { } ) do
add ( entry . path )
end
elseif name == "projectModuleBasenames" then
for _ , module in ipairs ( value or { } ) do
add ( q : get ( "projectModulePath" , module ) )
end
end
table . sort ( paths )

return paths
end

function inc . projectDependencies ( path )
q : get ( "checkModule" , path )
local byPath = q . memo . checkModule
local memo = byPath and byPath [ path ]
local dependencies , seen = { } , { }
for _ , dep in ipairs ( memo and memo . deps or { } ) do
if PROJECT_QUERY [ dep . name ] then
local identity = dep . name .. "\0" .. tostring ( dep . key )
if not seen [ identity ] then
seen [ identity ] = true
dependencies [
# dependencies + 1
] = { name = dep . name , key = dep . key , fingerprint = projectFingerprint ( dep . name , dep . key ) , }
end
end
end
table . sort ( dependencies , function ( a , b )
return a . name < b . name or ( a . name == b . name and tostring ( a . key ) < tostring ( b . key ) )
end )

return dependencies
end

function inc . projectDependencyFingerprint ( name , key )
if not PROJECT_QUERY [ name ] then
return nil
end
return projectFingerprint ( name , key )
end

function inc . projectDependencyPaths ( name , key )
if not PROJECT_QUERY [ name ] then
return { }
end
return projectDependencyPaths ( name , key )
end

function inc . persist ( )
envMod . persist ( env )
headerStore . save ( )
end

function inc . deriveStats ( )
return {
executions = q . stats . materializeDerives or 0 ,
cacheHits = q . hits . materializeDerives or 0 ,
equalCutoffs = q . cutoffs . materializeDerives or 0 ,
downstreamChecks = q . stats . checkModule or 0 ,
}
end

return inc
end

return incremental
