_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
















local hash = require ( "nupp.compiler.hash" )
local json = require ( "nupp.codec.json" )
local fs = require ( "nupp.compiler.fs" )
local fingerprint = require ( "nupp.compiler.project.fingerprint" )

local readFile , writeFile = fs . readFile , fs . writeFile

local cache = { }


















































































































































































































































local function jsonArray ( items ) 
return json . asArray ( items )
end









function cache . moduleCompilerFingerprint (
cacheDir ,
contentDigest ,
listDeclarations ,
readDeclaration
) 
local digest = contentDigest or hash . digest
local code = fingerprint . subsystemFingerprint ( { "nupp.tools.build.modules" } , cacheDir , contentDigest )
local declarations = fingerprint . declarationFingerprint ( contentDigest , listDeclarations , readDeclaration )

return digest ( code .. "\0" .. declarations )
end




local STATE_VERSION = 6

local function emptyState ( ) 
return { version = 6 , modules = { } , dependencies = { } , outputs = { } , targets = { } }
end

local function denseStrings ( value ) 
if type ( value ) ~= "table" then
return false
end
local count , maximum = 0 , 0
for index , entry in pairs ( value ) do
if type ( index ) ~= "number" or index < 1 or index ~= math . floor ( index ) or type ( entry ) ~= "string" then
return false
end
count = count + 1
maximum = math . max ( maximum , index )
end

return count == maximum
end

local function validState ( state ) 
for _ , field in ipairs ( { "modules" , "dependencies" , "outputs" , "targets" } ) do
if type ( state [ field ] ) ~= "table" then
return false
end
end
for name , record in pairs ( state . modules ) do
if type ( name ) ~= "string"
or type ( record ) ~= "table"
or record . output ~= nil and type ( record . output ) ~= "string"
or record . artifactHash ~= nil and type ( record . artifactHash ) ~= "string"
then
return false
end
end
for name , record in pairs ( state . dependencies ) do
if type ( name ) ~= "string" or type ( record ) ~= "table" then
return false
end
end
for output , present in pairs ( state . outputs ) do
if type ( output ) ~= "string" or type ( present ) ~= "boolean" then
return false
end
end
for name , outputs in pairs ( state . targets ) do
if type ( name ) ~= "string" or not denseStrings ( outputs ) then
return false
end
end

return true
end







local function adoptState ( state ) 
if type ( state ) ~= "table" or state . version ~= 6 then
return emptyState ( )
end
state . modules = state . modules or { }
state . dependencies = state . dependencies or { }
state . outputs = state . outputs or { }



state . targets = state . targets or { }
if not validState ( state ) then
return emptyState ( )
end

return state
end

local function loadState ( path ) 
local text = readFile ( path )
if not text then
return emptyState ( )
end
local state , invalid = json . decode ( text , json . NULL )
if invalid ~= nil then
return emptyState ( )
end

return adoptState ( state )
end

local function saveState ( path , state ) 
return writeFile ( path , json . encode ( state ) .. "\n" )
end

cache . jsonArray = jsonArray
cache . loadState = loadState
cache . adoptState = adoptState
cache . saveState = saveState
cache . emptyState = emptyState

local __nuppExportValue= cache ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.cache"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.cache"]=__nuppExports;return __nuppExports