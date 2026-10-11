_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT12={}; local function __nuppT9(...) return {n=select("#",...),...} end; local __nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT10(value) return value end; local function __nuppT11(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT18({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT19(v.primary) for _,reason in __nuppT20(v.suppressed) do text=text.."\ncleanup: "..__nuppT19(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.project.incremental\0runtime\0001") };


















local query = require ( "nupp.compiler.project.query" )
local parser = require ( "nupp.compiler.syntax.parser" )
local cst = require ( "nupp.compiler.syntax.cst" )
local check = require ( "nupp.compiler.check" )
local envMod = require ( "nupp.compiler.project.env" )
local storeMod = require ( "nupp.compiler.project.store" )
local T = require ( "nupp.compiler.types" )

local incremental = { }
local hostServices = require ( "nupp.compiler.hostservices" )































































incremental.Inc = {} incremental.Inc.__index = incremental.Inc ;_G.nupp.__reflect.link(incremental.Inc,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.project.query\0runtime\0001","nupp.compiler.project.query") })























































































































function incremental . new ( rootDir , opts ) 
opts = opts or { }
opts . compilerServices = opts . compilerServices or hostServices
local env = envMod . new ( rootDir , opts )

local strict = opts . strict
local traceInspection = opts . traceInspection == true
local q = query . new ( )
local activeModules = { }





q : define ( "importedModule" , function ( _ , _ ) 
return nil
end )





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





local headerStore = envMod . headerStore ( env ) or storeMod . open ( nil , "" )

















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



local function wholeFile ( _ , path ) 
do const  __nuppT27= io . open ( path , "rb" ) ; local __nuppT28=__nuppT12[1]; if not __nuppT28 then __nuppT28=function(f) do
if not f then
return "return",__nuppT9( nil )
end
local s = f : read ( "*a" )
f : close ( )

return "return",__nuppT9( s ) end; return "normal" end; __nuppT12[1]=__nuppT28 end; const __nuppT22,__nuppT23,__nuppT24=__nuppT14(__nuppT28,__nuppT10,__nuppT27); const __nuppT21=1; local __nuppT25={}; local __nuppT26=0; if __nuppT21>=1 and __nuppT27~=nil then  local __nuppT29,__nuppT30=__nuppT13(__nuppCleanup1,__nuppT27);  if not __nuppT29 then __nuppT26=__nuppT26+1; __nuppT25[__nuppT26]=__nuppT30 end; end; if not __nuppT22 then if __nuppT26>0 then __nuppT15(__nuppT11(__nuppT23,__nuppT25,1),0) else __nuppT15(__nuppT23,0) end end; if __nuppT26>0 then if __nuppT26>1 then __nuppT15(__nuppT11(__nuppT25[1],__nuppT25,2),0) else __nuppT15(__nuppT25[1],0) end end; if __nuppT23=="return" then  return __nuppT16(__nuppT24,1,__nuppT24.n)  end; end
end

q : define ( "generatedSource" , function ( ) 
return false
end )
q : define ( "fileText" , wholeFile )
q : define ( "externalFile" , wholeFile )

q : define ( "parse" , function ( self , path ) 
local text = self : get ( "fileText" , path )
if not text then
return nil
end

return parser . parse ( text , path )
end )








local function sameDeprecation ( left , right ) 
if left == nil or right == nil then
return left == right
end

return left . reason == right . reason and left . replacement == right . replacement
end

local function sameHeader ( a , b ) 
if not a or not b then
return false
end
if a . path ~= b . path
or a . moduleName ~= b . moduleName
or a . declaredModuleName ~= b . declaredModuleName
or ( a . moduleToken and a . moduleToken . offset ) ~= ( b . moduleToken and b . moduleToken . offset )
or a . moduleLocal ~= b . moduleLocal
or # a . declarations ~= # b . declarations
or # ( a . dependencies or { } ) ~= # ( b . dependencies or { } )
then
return false
end
for index , name in ipairs ( a . dependencies or { } ) do
if name ~= b . dependencies [ index ] then
return false
end
end
for index , left in ipairs ( a . declarations ) do
local right = b . declarations [ index ]
if left . name ~= right . name
or left . kind ~= right . kind
or left . statKind ~= right . statKind
or left . visibility ~= right . visibility
or left . isAnnotation ~= right . isAnnotation
or not sameDeprecation ( left . deprecated , right . deprecated )
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

local hash = require ( "nupp.compiler.hash" )
local stable = require ( "nupp.compiler.stable" )



local contentDigest = env . compilerServices and env . compilerServices . hash and env . compilerServices . hash . digest
or hash . digest

local function entrySurface ( entry ) 
return {
name = entry . name ,
path = entry . path ,
moduleName = entry . moduleName ,
visibility = entry . visibility ,
kind = entry . kind ,
signature = entry . signature ,
isAnnotation = entry . isAnnotation ,
deprecated = entry . deprecated ,
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









q : define (
"projectRegistrations" ,
function ( self , path ) 
local mine = { }
for _ , diagnostic in ipairs ( self : get ( "projectIndex" , "root" ) . registrationDiagnostics or { } ) do
if diagnostic . path == path then
mine [ # mine + 1 ] = diagnostic
end
end

return mine
end ,
sameStable
)








q : define (
"projectModuleDeclaration" ,
function ( self , name ) 
local index = self : get ( "projectIndex" , "root" )

return {
definition = index . moduleDefinitions [ name ] or false ,
declared = index . declaredModules [ name ] == true ,
internal = index . internalModules [ name ] == true ,
internalTree = index . internalTrees [ name ] == true ,
}
end ,
sameStable
)













local function keyedIndexView ( field ) 
local view = { }

return setmetatable ( view , {
__index = function ( _ , name ) 
if type ( name ) ~= "string" then
return nil
end
local value = q : get ( "projectModuleDeclaration" , name ) [ field ]

return value ~= false and value or nil
end
} )
end

local indexView = {
declaredModules = keyedIndexView ( "declared" ) ,
moduleDefinitions = keyedIndexView ( "definition" ) ,
internalModules = keyedIndexView ( "internal" ) ,
internalTrees = keyedIndexView ( "internalTree" ) ,
}
setmetatable ( indexView , {
__index = function ( _ , field ) 
return q : get ( "projectIndex" , "root" ) [ field ]
end
} )

env . ensureProjectIndex = function ( ) 
return indexView
end







env . projectEntries = function ( _ , name ) 
return q : get ( "projectEntries" , name )
end
env . projectPathEntries = function ( _ , path ) 
return q : get ( "projectPathEntries" , path )
end
env . projectModuleBasenames = function ( _ , short ) 
return q : get ( "projectModuleBasenames" , short )
end
env . projectAnnotations = function ( _ , name ) 
return q : get ( "projectAnnotations" , name )
end


local function modulePath ( self , name ) 
return self : get ( "projectModulePath" , name ) or envMod . findModulePath ( env , name )
end



local function stagedCarriedText ( name , path , text ) 
if text == nil or not envMod . isStagedBundledSource ( env , name , path ) then
return false
end
local file = env . bundledImplementation and env . bundledImplementation ( name ) or nil

return file ~= nil and require ( "nupp.compiler.bundled" ) . source ( file ) == text
end










local function answeringPath ( self , name ) 
local path = modulePath ( self , name )
if path ~= nil and stagedCarriedText ( name , path , self : get ( "fileText" , path ) ) then
return nil
end

return path
end




local function checkedModuleName ( path ) 
local name = envMod . moduleNameForPath ( env , path )
if not name and path : match ( "%.d%.nupp$" ) then
name = envMod . moduleNameInRoots ( env . roots or { } , ( path : gsub ( "%.d%.nupp$" , ".nupp" ) ) )
end

return name
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
local seeded = { types = { } , typeDefs = { } , values = { } , valueDefs = { } , comptimeFunctions = { } }
for _ , entry in ipairs ( self : get ( "projectPathEntries" , path ) or { } ) do
if entry . visibility == "module" and entry . type then
seeded . types [ entry . name ] = entry . type
seeded . typeDefs [ entry . name ] = entry . definition
if entry . kind == "struct" then
seeded . values [ entry . name ] = entry . type
end
end
end
local sourceDeclaredModule = cst . declaredModule ( result . root )
activeModules [
path
] = { exports = seeded , declared = sourceDeclaredModule ~= nil and cst . exportAssignment ( result . root ) == nil , }


result . externalInputs = { }
local qenv = setmetatable (
{
resolveModule = function ( _ , name ) 
local interface = self : get ( "moduleInterface" , name )
local target = modulePath ( self , name )
local active = target and activeModules [ target ]
if not interface and active then
return active . declared and interfaceType ( active . exports ) or T . any
end

return interface and interface . type or nil
end ,
compatibilityModule = function ( _ , name ) 
local target = modulePath ( self , name )
if not target or activeModules [ target ] then
return nil
end
local imported = self : get ( "importedModule" , name )
if imported then
return {
path = target ,
compatDiagnostics = imported . diags or { } ,
source = imported . source ,
declarationOnly = target : match ( "%.d%.nupp$" ) ~= nil ,
}
end
local checked = self : get ( "checkModule" , target )

return {
path = target ,
compatDiagnostics = checked . diags ,
source = checked . result and checked . result . source ,
declarationOnly = target : match ( "%.d%.nupp$" ) ~= nil
}
end ,
resolveModuleExports = function ( _ , name ) 
local exports = self : get ( "moduleExports" , name )
local target = modulePath ( self , name )
local active = target and activeModules [ target ]
return exports or active and active . declared and active . exports or nil
end ,
moduleInitializing = function ( _ , name ) 
local target = modulePath ( self , name )
return target ~= nil and activeModules [ target ] ~= nil
end ,
observeCallGuarantee = function ( _ , module , member , identity , guarantee ) 
local key = table . concat ( { module , member , identity , guarantee } , "\0" )
local observed = self : get ( "moduleCallGuarantee" , key )
return observed and observed : sub ( -8 ) == "\0present" or false
end ,
resolveCallableFact = function ( _ , module , member , fact ) 
return self : get ( "moduleCallableFact" , table . concat ( { module , member , fact } , "\0" ) )
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




local fileStrict = strict
if envMod . isDependencyTypePath ( env , path ) or envMod . isRuntimeSourcePath ( env , path ) then
fileStrict = false
end
local diags , moduleType , exports = check . check ( result , path , qenv , {
moduleName = checkedModuleName ( path ) ,
strict = fileStrict ,
traceInspection = traceInspection ,
generatedSource = self : get ( "generatedSource" , path ) ,
initialExports = seeded ,
} )

activeModules [ path ] = nil




for _ , diagnostic in ipairs ( self : get ( "projectRegistrations" , path ) ) do
local token = diagnostic . token or { }
diags [
# diags + 1
] = {
code = "NUPP1002" ,
msg = diagnostic . msg ,
filename = path ,
severity = "error" ,
line = token . line or 0 ,
col = token . col or 0 ,
offset = token . offset or 0 ,
length = token . text and # token . text or 0 ,
related = diagnostic . related ,
}
end

return { diags = diags , moduleType = moduleType , exports = exports , result = result , }
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
local imported = self : get ( "importedModule" , name )
if imported then
return imported . interface
end
local path = answeringPath ( self , name )
if not path then

local bundled = env . bundled and env . bundled [ name ]
return bundled
and {
type = bundled . type ,
nominalEffectFingerprint = bundled . exports and bundled . exports . nominalEffectFingerprint ,
deriveInterfaceFingerprint = bundled . exports and bundled . exports . deriveInterfaceFingerprint ,
}
or nil
end


local r = self : get ( "checkModule" , path )

return r
and {
type = r . moduleType ,
nominalEffectFingerprint = r . exports and r . exports . nominalEffectFingerprint ,
deriveInterfaceFingerprint = r . exports and r . exports . deriveInterfaceFingerprint ,
}
or nil
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

local function sameDefinitionMap ( left , right ) 
left , right = left or { } , right or { }
for name , definition in pairs ( left ) do
local other = right [ name ]
if not other
or definition . comptimeOnly ~= other . comptimeOnly
or not sameDeprecation ( definition . deprecated , other . deprecated )
then
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
and sameTypeMap ( left . types , right . types )
and sameTypeMap ( left . values , right . values )
and sameDefinitionMap ( left . typeDefs , right . typeDefs )
and sameDefinitionMap ( left . valueDefs , right . valueDefs )
end

q : define (
"moduleExports" ,
function ( self , name ) 
local imported = self : get ( "importedModule" , name )
if imported then
return imported . exports
end
local path = answeringPath ( self , name )
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
local imported = module and self : get ( "importedModule" , module ) or nil
if imported then
local importedExports = imported . exports
return importedExports and importedExports . callGuarantees and importedExports . callGuarantees [ member ]
or nil
end
local path = module and answeringPath ( self , module ) or nil
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

q : define (
"moduleCallableFact" ,
function ( self , key ) 
local module , member , fact = key : match ( "^([^%z]+)%z([^%z]+)%z([^%z]+)$" )
local entry = module and self : get ( "moduleCallGuarantees" , module .. "\0" .. member ) or nil
return entry and entry [ fact ] or nil
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



q : define ( "bundledModule" , function ( _ , name ) 
return env . loadBundledModule and env . loadBundledModule ( name ) or false
end )
env . bundled = setmetatable ( { } , {
__index = function ( _ , name ) 
return q : get ( "bundledModule" , name )
end
} )
env . resolveModule = function ( _ , name ) 
local resolved = q : get ( "moduleInterface" , name )
local path = modulePath ( q , name )
local active = path and activeModules [ path ]
if not resolved and active then
return active . declared and interfaceType ( active . exports ) or T . any
end

return resolved and resolved . type or nil
end
env . resolveModuleExports = function ( _ , name ) 
local exports = q : get ( "moduleExports" , name )
local path = modulePath ( q , name )
local active = path and activeModules [ path ]
return exports or active and active . declared and active . exports or nil
end







local function apiOpenDocument ( path , text ) 
q : setInput ( "generatedSource" , path , false )
local wasOpen = openPaths [ path ]
if envMod . moduleNameForPath ( env , path ) then
openPaths [ path ] = true
end
if not wasOpen and openPaths [ path ] and not diskPaths [ path ] then
updateProjectFiles ( )
end
q : setInput ( "fileText" , path , text )
end







local function apiStageCarriedDocument ( name , path , text ) 
if stagedCarriedText ( name , path , text ) then
q : setInput ( "generatedSource" , path , false )
q : setInput ( "fileText" , path , text )
else
apiOpenDocument ( path , text )
end
end

local function apiOpenGeneratedDocument ( path , text ) 
apiOpenDocument ( path , text )
q : setInput ( "generatedSource" , path , true )
end

local function apiCloseDocument ( path ) 
q : clearInput ( "generatedSource" , path )
q : clearInput ( "fileText" , path )
if openPaths [ path ] then
openPaths [ path ] = nil
if not diskPaths [ path ] then
updateProjectFiles ( )
end
end
end




local function apiDiskChanged ( path , changeType ) 
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




















local DEEP_GRAPH = 64



local walk = { revision = -1 }

local function checkFromTheBottom ( path ) 
if # q . stack > 0 then
return
end
if walk . revision ~= q . revision then
walk = { revision = q . revision , index = { } , low = { } , height = { } , cyclic = { } , count = 0 }
end
local index , low , height , cyclic = walk . index , walk . low , walk . height , walk . cyclic
if index [ path ] then
return
end


local finished = { }
local open = { }
local onOpen = { }
local frames = { }

local function visit ( node ) 
walk . count = walk . count + 1
index [ node ] , low [ node ] = walk . count , walk . count
open [ # open + 1 ] = node
onOpen [ node ] = true
local targets = { }
local header = q : get ( "projectHeader" , node )
for _ , name in ipairs ( header and header . dependencies or { } ) do
local target = modulePath ( q , name )
if target then
targets [ # targets + 1 ] = target
end
end
frames [ # frames + 1 ] = { node = node , targets = targets , at = 0 , height = 0 }
end

visit ( path )
while # frames > 0 do
local frame = frames [ # frames ]
frame . at = frame . at + 1
local target = frame . targets [ frame . at ]
if target == frame . node then
cyclic [ target ] = true
elseif target and not index [ target ] then
visit ( target )
elseif target and onOpen [ target ] then
low [ frame . node ] = math . min ( low [ frame . node ] , index [ target ] )
elseif target then
frame . height = math . max ( frame . height , height [ target ] or 0 )
else
frames [ # frames ] = nil
local node = frame . node
height [ node ] = frame . height + 1
local parent = frames [ # frames ]
if parent then
low [ parent . node ] = math . min ( low [ parent . node ] , low [ node ] )
parent . height = math . max ( parent . height , height [ node ] )
end
if low [ node ] == index [ node ] then
local members = { }
repeat
local member = open [ # open ]
open [ # open ] = nil
onOpen [ member ] = nil
members [ # members + 1 ] = member
until member == node
if # members > 1 then
for _ , member in ipairs ( members ) do
cyclic [ member ] = true
end
end
end
finished [ # finished + 1 ] = node
end
end
if height [ path ] <= 64 then
return
end
for _ , node in ipairs ( finished ) do
if node ~= path and not cyclic [ node ] then
q : get ( "checkModule" , node )
end
end
end










local function checkEntered ( path ) 
local name = checkedModuleName ( path )
if name ~= nil and modulePath ( q , name ) == path then
q : get ( "moduleInterface" , name )
end

return q : get ( "checkModule" , path )
end


local function apiCheckFile ( path ) 


local walked , problem = pcall ( checkFromTheBottom , path )
if not walked then
walk = { revision = -1 }
error ( problem , 0 )
end

return checkEntered ( path )
end





local function apiCheckReadyFile ( path ) 
return checkEntered ( path )
end

local function apiProjectIndex ( ) 
return q : get ( "projectIndex" , "root" )
end

local function apiProjectFiles ( ) 
return q : get ( "projectFiles" , "root" )
end





local function apiFileText ( path ) 
return q : get ( "fileText" , path )
end

local function apiExternalFile ( path ) 
return q : get ( "externalFile" , path )
end

local function apiProjectHeader ( path ) 
return q : get ( "projectHeader" , path )
end




local function apiModulePath ( name ) 
return modulePath ( q , name )
end

local function apiModuleDependencies ( path ) 
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

local function apiModuleSemantic ( name , knownPath ) 
local path = knownPath or modulePath ( q , name )
local checked = path and q : get ( "checkModule" , path ) or nil

return {
interface = checked
and {
type = checked . moduleType ,
nominalEffectFingerprint = checked . exports and checked . exports . nominalEffectFingerprint ,
deriveInterfaceFingerprint = checked . exports and checked . exports . deriveInterfaceFingerprint ,
}
or q : get ( "moduleInterface" , name ) ,
exports = checked and checked . exports or q : get ( "moduleExports" , name ) ,
diags = checked and checked . diags or { } ,
source = checked and checked . result and checked . result . source or nil ,



annotations = path and env . annotations : definedBy ( path ) or { } ,
}
end

local function apiImportModules ( semantics ) 
for name , semantic in pairs ( semantics ) do
for _ , definition in ipairs ( semantic . annotations or { } ) do
env . annotations : define ( definition )
end
q : setInput ( "importedModule" , name , semantic )
end
end

local PROJECT_QUERY = {
projectEntries = true ,
projectPathEntries = true ,
projectModulePath = true ,
projectModuleBasenames = true ,
projectAnnotations = true ,
moduleCallGuarantees = true ,
moduleCallGuarantee = true ,
moduleCallableFact = true ,
}





local function projectFingerprint ( name , key ) 
local value = q : get ( name , key )
if name == "projectEntries" or name == "projectPathEntries" or name == "projectAnnotations" then





local kept = { }
for _ , entry in ipairs ( value or { } ) do
if entry . visibility == "global"
or entry . moduleName == nil
or entry . path == nil
or not envMod . isStagedBundledSource ( env , entry . moduleName , entry . path )
then
kept [ # kept + 1 ] = entry
end
end
value = entryListSurface ( kept )
elseif name == "projectModulePath"
and type ( value ) == "string"
and envMod . isStagedBundledSource ( env , key , value )
then



value = nil
end

return contentDigest ( stable ( value ) )
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

if name == "moduleCallGuarantees" or name == "moduleCallGuarantee" or name == "moduleCallableFact" then
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

local function apiProjectDependencies ( path ) 
local checked = q : get ( "checkModule" , path )
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
local root = checked and checked . result and checked . result . root
for key in pairs ( root and root . optimizationDependencies or { } ) do

local identity = "moduleCallableFact" .. "\0" .. key
if not seen [ identity ] then
seen [ identity ] = true
dependencies [ # dependencies + 1 ] = { name = "moduleCallableFact" , key = key , fingerprint = projectFingerprint ( "moduleCallableFact" , key ) }
end
end
table . sort ( dependencies , function ( a , b ) 
return a . name < b . name or ( a . name == b . name and tostring ( a . key ) < tostring ( b . key ) )
end )

return dependencies
end

local function apiProjectDependencyFingerprint ( name , key ) 
if not PROJECT_QUERY [ name ] then
return nil
end
return projectFingerprint ( name , key )
end

local function apiProjectDependencyPaths ( name , key ) 
if not PROJECT_QUERY [ name ] then
return { }
end
return projectDependencyPaths ( name , key )
end

local function externalFingerprint ( path ) 
local bytes = q : get ( "externalFile" , path )
if bytes == nil then
return "absent"
end

return "file:" .. contentDigest ( bytes )
end

local function apiExternalInputs ( path ) 



q : get ( "checkModule" , path )
local byPath = q . memo . checkModule
local memo = byPath and byPath [ path ]
local inputs


= { }
local seen = { }
for _ , dep in ipairs ( memo and memo . deps or { } ) do
if dep . name == "externalFile" and type ( dep . key ) == "string" and not seen [ dep . key ] then
seen [ dep . key ] = true
inputs [ # inputs + 1 ] = { path = dep . key , fingerprint = externalFingerprint ( dep . key ) }
end
end
table . sort ( inputs , function ( a , b ) 
return a . path < b . path
end )

return inputs
end

local function apiPersist ( ) 
envMod . persist ( env )
if not env . cacheReadOnly then
headerStore . save ( )
end
end

local function apiDeriveStats ( ) 
return {
executions = q . stats . materializeDerives or 0 ,
cacheHits = q . hits . materializeDerives or 0 ,
equalCutoffs = q . cutoffs . materializeDerives or 0 ,
downstreamChecks = q . stats . checkModule or 0 ,
}
end

return ( _G.setmetatable({ env =
env ,  q =
q ,  headerStore =
headerStore ,  changeDocument =
apiOpenDocument ,  openDocument =
apiOpenDocument ,  openGeneratedDocument =
apiOpenGeneratedDocument ,  stageCarriedDocument =
apiStageCarriedDocument ,  closeDocument =
apiCloseDocument ,  diskChanged =
apiDiskChanged ,  checkFile =
apiCheckFile ,  checkReadyFile =
apiCheckReadyFile ,  projectIndex =
apiProjectIndex ,  projectFiles =
apiProjectFiles ,  fileText =
apiFileText ,  externalFile =
apiExternalFile ,  projectHeader =
apiProjectHeader ,  modulePath =
apiModulePath ,  moduleDependencies =
apiModuleDependencies ,  moduleSemantic =
apiModuleSemantic ,  importModules =
apiImportModules ,  projectDependencies =
apiProjectDependencies ,  projectDependencyFingerprint =
apiProjectDependencyFingerprint ,  projectDependencyPaths =
apiProjectDependencyPaths ,  externalInputs =
apiExternalInputs ,  externalInputFingerprint =
externalFingerprint ,  persist =
apiPersist ,  deriveStats =
apiDeriveStats }, incremental.Inc) )

end

local __nuppExportValue= incremental ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.incremental"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.incremental"]=__nuppExports;return __nuppExports