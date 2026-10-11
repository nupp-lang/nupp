_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()








local fs = require ( "nupp.compiler.fs" )
local hash = require ( "nupp.compiler.hash" )
local packaging = require ( "nupp.tools.build.package" )
local platform = require ( "nupp.tools.build.platform" )
local stubs = require ( "nupp.tools.build.stubs" )

local release = { }
local json = require ( "nupp.codec.json" )

local HOST_FEATURES

= {
"lpeg" ,
"native-checksum" ,
"native-compression" ,
"native-files" ,
"native-gpu" ,
"native-net" ,
"native-process" ,
"native-tls" ,
"workers" ,
}

local function copyArray ( values ) 
local copied = { }
for index , value in ipairs ( values ) do
copied [ index ] = value
end

return copied
end

local function sameStringArray ( value , expected ) 
if type ( value ) ~= "table" then
return false
end
local count , highest = 0 , 0
for index , item in pairs ( value ) do
if type ( index ) ~= "number" or index < 1 or index ~= math . floor ( index ) or type ( item ) ~= "string" then
return false
end
count = count + 1
highest = math . max ( highest , index )
end
if count ~= highest or count ~= # expected then
return false
end
for index , item in ipairs ( expected ) do
if value [ index ] ~= item then
return false
end
end

return true
end

local function decode ( path ) 
local text , readErr = fs . readFile ( path )
if not text then
return nil , "cannot read " .. path .. ": " .. tostring ( readErr )
end
local value , invalid = json . decode ( text , json . NULL )
if invalid ~= nil then
return nil , "cannot decode " .. path .. ": " .. invalid
end

return value
end



local function pretty ( value , depth , seen ) 
if value == json . NULL then
return "null"
end
local kind = type ( value )

if kind ~= "table" then
return json . encode ( value )
end
local entries = value
if seen [ entries ] then
error ( "release JSON contains a cycle" )
end
seen [ entries ] = true
local current = ("  ") : rep ( depth )
local nested = ("  ") : rep ( depth + 1 )
local parts = { }
local opening , closing
if json . isArray ( entries ) then
opening , closing = "[" , "]"
for index = 1 , # entries do
parts [ index ] = nested .. pretty ( entries [ index ] , depth + 1 , seen )
end
else
opening , closing = "{" , "}"
local keys = { }
for key in pairs ( entries ) do
if type ( key ) ~= "string" then
error ( "release JSON object has a non-string key" )
end
keys [ # keys + 1 ] = key
end
table . sort ( keys )
for index , key in ipairs ( keys ) do
parts [ index ] = nested .. json . encode ( key ) .. ": " .. pretty ( entries [ key ] , depth + 1 , seen )
end
end
seen [ entries ] = nil
if # parts == 0 then
return opening .. closing
end

return opening .. "\n" .. table . concat ( parts , ",\n" ) .. "\n" .. current .. closing
end

local function writeJson ( path , value ) 
local ok , text = pcall ( pretty , value , 0 , { } )
if not ok then
return nil , tostring ( text )
end

return fs . writeFile ( path , text .. "\n" )
end

local function validateRecord ( value , selectedPlatform , catalogRelease ) 
if type ( value ) ~= "table" then
return nil , "stub record for " .. selectedPlatform .. " is not an object"
end
if value . platform ~= selectedPlatform then
return nil , "stub record for " .. selectedPlatform .. " claims platform " .. tostring ( value . platform )
end
if value . catalogRelease ~= catalogRelease then
return nil , "stub record for " .. selectedPlatform .. " has the wrong catalog release"
end
if value . hostAbi ~= packaging . hostAbiVersion then
return nil , "stub record for " .. selectedPlatform .. " has the wrong hostAbi"
end
if not sameStringArray ( value . hostFeatures , HOST_FEATURES ) then
return nil , "stub record for " .. selectedPlatform .. " is not a universal host"
end
if value . executableSuffix ~= platform . executableSuffix ( selectedPlatform ) then
return nil , "stub record for " .. selectedPlatform .. " has the wrong executable suffix"
end
if not stubs . safeComponent ( value . artifact ) then
return nil , "stub record for " .. selectedPlatform .. " has an unsafe artifact name"
end
if not stubs . safeComponent ( value . noticeArtifact ) then
return nil , "stub record for " .. selectedPlatform .. " has an unsafe notice artifact name"
end
if type ( value . sha256 ) ~= "string" or # value . sha256 ~= 64 or not value . sha256 : match ( "^[0-9a-f]+$" ) then
return nil , "stub record for " .. selectedPlatform .. " requires a lowercase SHA-256"
end
if type ( value . size ) ~= "number" or value . size < 1 or value . size ~= math . floor ( value . size ) then
return nil , "stub record for " .. selectedPlatform .. " requires a positive integer size"
end

return true
end

local function verifyRecord ( value , root ) 
local artifactPath = fs . join ( root , value . artifact )
local bytes , readErr = fs . readFile ( artifactPath )
if not bytes then
return nil , "cannot read stub artifact " .. artifactPath .. ": " .. tostring ( readErr )
end
local valid , validErr = stubs . validateArtifact ( value . platform , value . size , value . sha256 , bytes , artifactPath )
if not valid then
return nil , validErr
end
local noticePath = fs . join ( root , value . noticeArtifact )
local notices , noticeErr = fs . readFile ( noticePath )
if not notices then
return nil , "cannot read stub notices " .. noticePath .. ": " .. tostring ( noticeErr )
end
if # notices == 0 then
return nil , "stub notices are empty: " .. noticePath
end

return true
end

function release . record (
selectedPlatform ,
catalogRelease ,
artifactPath ,
noticePath ,
output
) 
if not stubs . safeComponent ( catalogRelease ) then
return nil , "catalog release must be one safe path component"
end
if not platform . has ( selectedPlatform ) then
return nil , "unsupported stub platform " .. selectedPlatform
end
local bytes , readErr = fs . readFile ( artifactPath )
if not bytes then
return nil , "cannot read stub artifact " .. artifactPath .. ": " .. tostring ( readErr )
end
local executable , executableErr = stubs . validateExecutable ( selectedPlatform , bytes , artifactPath )
if not executable then
return nil , executableErr
end
local notices , noticeErr = fs . readFile ( noticePath )
if not notices then
return nil , "cannot read stub notices " .. noticePath .. ": " .. tostring ( noticeErr )
end

return writeJson ( output , {
artifact = fs . basename ( artifactPath ) ,
catalogRelease = catalogRelease ,
executableSuffix = platform . executableSuffix ( selectedPlatform ) ,
hostAbi = packaging . hostAbiVersion ,
hostFeatures = json . asArray ( copyArray ( HOST_FEATURES ) ) ,
noticeArtifact = fs . basename ( noticePath ) ,
platform = selectedPlatform ,
sha256 = hash . sha256 ( bytes ) ,
size = # bytes ,
} )
end



function release . kitRecord (
selectedPlatform ,
catalogRelease ,
archivePath ,
url ,
output
) 
if not stubs . safeComponent ( catalogRelease ) then
return nil , "catalog release must be one safe path component"
end
if require ( "nupp.compiler.aot.llvm.profile" ) . of ( selectedPlatform ) == nil then
return nil , "no link kit links for " .. selectedPlatform
end
if not url : match ( "^https://" ) then
return nil , "a kit URL must be HTTPS: " .. url
end
local bytes , readErr = fs . readFile ( archivePath )
if not bytes then
return nil , "cannot read kit archive " .. archivePath .. ": " .. tostring ( readErr )
end
if bytes : sub ( 1 , 2 ) ~= "\31‹" then
return nil , "kit archive " .. archivePath .. " is not gzip"
end

return writeJson ( output , {
kind = "kit" ,
artifact = fs . basename ( archivePath ) ,
catalogRelease = catalogRelease ,
hostAbi = packaging . hostAbiVersion ,
hostFeatures = json . asArray ( copyArray ( HOST_FEATURES ) ) ,
platform = selectedPlatform ,
sha256 = hash . sha256 ( bytes ) ,
size = # bytes ,
url = url ,
} )
end

local function validateKit ( value , root , catalogRelease ) 
local where = "kit record for " .. tostring ( value . platform )
if value . catalogRelease ~= catalogRelease or value . hostAbi ~= packaging . hostAbiVersion then
return nil , where .. " belongs to another release"
end
if not sameStringArray ( value . hostFeatures , HOST_FEATURES ) then
return nil , where .. " is not a universal kit"
end
if not stubs . safeComponent ( value . artifact ) then
return nil , where .. " has an unsafe artifact name"
end
if type ( value . url ) ~= "string" or not value . url : match ( "^https://" ) then
return nil , where .. " requires an HTTPS url"
end
local path = fs . join ( root , value . artifact )
local bytes , readErr = fs . readFile ( path )
if not bytes then
return nil , "cannot read kit archive " .. path .. ": " .. tostring ( readErr )
end
if # bytes ~= value . size or hash . sha256 ( bytes ) ~= value . sha256 then
return nil , where .. " does not describe " .. path
end

return true
end



function release . kitCatalog (
catalogRelease ,
recordPaths ,
artifactRoot ,
output
) 
if not stubs . safeComponent ( catalogRelease ) then
return nil , "catalog release must be one safe path component"
end
local kits = { }
for _ , path in ipairs ( recordPaths ) do
local value , decodeErr = decode ( path )
if not value then
return nil , decodeErr
end
if type ( value ) ~= "table" or value . kind ~= "kit" then
return nil , path .. " is not a kit record"
end
local key = tostring ( value . platform )
if kits [ key ] ~= nil then
return nil , "duplicate kit record for " .. key
end
local valid , validErr = validateKit ( value , artifactRoot , catalogRelease )
if not valid then
return nil , validErr
end
value . kind = nil
kits [ key ] = value
end

return writeJson ( output , {
catalogRelease = catalogRelease ,
hostAbi = packaging . hostAbiVersion ,
kits = json . asObject ( kits ) ,
stubs = json . asObject ( { } ) ,
} )
end

function release . catalog (
catalogRelease ,
recordPaths ,
artifactRoot ,
output
) 
if not stubs . safeComponent ( catalogRelease ) then
return nil , "catalog release must be one safe path component"
end
local records = { }
local kits = { }
for _ , path in ipairs ( recordPaths ) do
local value , decodeErr = decode ( path )
if not value then
return nil , decodeErr
end
if type ( value ) ~= "table" then
return nil , path .. " is not a release record"
end
if value . kind == "kit" then
local key = tostring ( value . platform )
if kits [ key ] ~= nil then
return nil , "duplicate kit record for " .. key
end
local valid , validErr = validateKit ( value , artifactRoot , catalogRelease )
if not valid then
return nil , validErr
end
value . kind = nil
kits [ key ] = value
else
local selectedPlatform = type ( value . platform ) == "string" and value . platform or ""
if not platform . has ( selectedPlatform ) then
return nil , "unsupported stub platform " .. tostring ( value . platform )
end
if records [ selectedPlatform ] ~= nil then
return nil , "duplicate stub record for " .. selectedPlatform
end
local valid , validErr = validateRecord ( value , selectedPlatform , catalogRelease )
if not valid then
return nil , validErr
end
local verified , verifyErr = verifyRecord ( value , artifactRoot )
if not verified then
return nil , verifyErr
end
records [ selectedPlatform ] = value
end
end
local missing = { }
for _ , key in ipairs ( platform . keys ( ) ) do
if records [ key ] == nil then
missing [ # missing + 1 ] = key
end
end
if # missing > 0 then
return nil , "catalog is missing stub records: " .. table . concat ( missing , ", " )
end

return writeJson ( output , {
catalogRelease = catalogRelease ,
hostAbi = packaging . hostAbiVersion ,
kits = json . asObject ( kits ) ,
stubs = json . asObject ( records ) ,
} )
end

function release . stampPayload (
stubPath ,
payloadPath ,
selectedPlatform ,
output
) 
if not platform . has ( selectedPlatform ) then
return nil , "unsupported stub platform " .. selectedPlatform
end
local stub , stubErr = fs . readFile ( stubPath )
if not stub then
return nil , "cannot read stub " .. stubPath .. ": " .. tostring ( stubErr )
end
local executable , executableErr = stubs . validateExecutable ( selectedPlatform , stub , stubPath )
if not executable then
return nil , executableErr
end
local payload , payloadErr = fs . readFile ( payloadPath )
if not payload then
return nil , "cannot read payload " .. payloadPath .. ": " .. tostring ( payloadErr )
end
local written , writeErr = packaging . stampFile ( output , stub , payload , selectedPlatform , 0 )
if not written then
return nil , writeErr
end

return true
end

local __nuppExportValue= release ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.release"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.release"]=__nuppExports;return __nuppExports