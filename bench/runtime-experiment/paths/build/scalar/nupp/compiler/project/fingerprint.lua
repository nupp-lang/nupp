_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

















local hash = require ( "nupp.compiler.hash" )
local fs = require ( "nupp.compiler.fs" )

local join = fs . join
local dirname = fs . dirname
local readFile = fs . readFile
local listFiles = fs . listFiles

local fingerprint = { }














local nativeDigestMemo = nil

function fingerprint . contentDigest ( native ) 
if native == false then
return hash . digest
end
if nativeDigestMemo == nil then


local ok , services = pcall ( require , "nupp.compiler.hostservices" )
local resolved = ok and services and services . hash and services . hash . digest or nil
nativeDigestMemo = resolved or false
end

return nativeDigestMemo or hash . digest
end

local function hashFile ( path , contentDigest ) 
local text = readFile ( path )
local digest = contentDigest or hash . digest

return text and digest ( text ) or nil
end

local function hashFiles ( files ) 
local parts = { }
for _ , path in ipairs ( files ) do
parts [ # parts + 1 ] = path .. "\0" .. ( hashFile ( path , hash . digest ) or "missing" )
end

return hash . digest ( table . concat ( parts , "\0" ) )
end



local function compilerDir ( ) 
local source = debug . getinfo ( 1 , "S" ) . source
return dirname ( source : match ( "^@(.*)[/\\]" ) or "." )
end










local function bundled ( ) 
local source = debug . getinfo ( 1 , "S" ) . source
return ( source : match ( "[^/\\]*$" ) or "" ) ~= "fingerprint.lua"
end




local toolFingerprintMemo = nil

local treeFilesMemo = nil



local function treeFiles ( dir ) 
if treeFilesMemo == nil then
local files = { }
for _ , path in ipairs ( listFiles ( dir ) ) do
if path : match ( "%.lua$" ) then
files [ # files + 1 ] = path
end
end
treeFilesMemo = files
end

return treeFilesMemo
end

local function relativeTo ( dir , path ) 
if path : sub ( 1 , # dir + 1 ) == dir .. "/" then
return path : sub ( # dir + 2 )
end

return path
end

local function toolFingerprint ( contentDigest ) 
if toolFingerprintMemo then
return toolFingerprintMemo
end
local digest = contentDigest or hash . digest



local dir = dirname ( compilerDir ( ) )
local files = { }
if bundled ( ) then
files = { ( debug . getinfo ( 1 , "S" ) . source : gsub ( "^@" , "" ) ) }
else
for _ , path in ipairs ( treeFiles ( dir ) ) do
local relative = relativeTo ( dir , path )
if relative : match ( "^compiler/" ) or relative : match ( "^tools/" ) then
files [ # files + 1 ] = path
end
end
end






local parts = { }
for _ , path in ipairs ( files ) do
local relative = path
if path : sub ( 1 , # dir + 1 ) == dir .. "/" then
relative = path : sub ( # dir + 2 )
end
parts [ # parts + 1 ] = relative .. "\0" .. ( hashFile ( path , digest ) or "missing" )
end
table . sort ( parts )
toolFingerprintMemo = digest ( table . concat ( parts , "\0" ) )

return toolFingerprintMemo
end

local besideToolMemo = nil








local function besideToolFingerprint ( digest ) 
if besideToolMemo then
return besideToolMemo
end
local dir = dirname ( compilerDir ( ) )
local parts = { }
for _ , path in ipairs ( treeFiles ( dir ) ) do
local relative = relativeTo ( dir , path )
if not relative : match ( "^compiler/" ) and not relative : match ( "^tools/" ) then
parts [ # parts + 1 ] = relative .. "\0" .. ( hashFile ( path , digest ) or "missing" )
end
end
table . sort ( parts )
besideToolMemo = digest ( table . concat ( parts , "\0" ) )

return besideToolMemo
end




local function graphFingerprint ( contentDigest ) 
local digest = contentDigest or hash . digest
if bundled ( ) then
return toolFingerprint ( digest )
end

return digest ( toolFingerprint ( digest ) .. "\0" .. besideToolFingerprint ( digest ) )
end
























local GRAPH_STAMP = "modules/2"

local graphMemo = nil





local graphAttempted = false

local graphStoredIn = { }






local function validGraph ( value ) 
if type ( value ) ~= "table"
or type ( value . files ) ~= "table"
or type ( value . edges ) ~= "table"
or type ( value . digests ) ~= "table"
or type ( value . unknown ) ~= "table"
then
return false
end
for name , path in pairs ( value . files ) do
if type ( name ) ~= "string"
or type ( path ) ~= "string"
or type ( value . digests [ name ] ) ~= "string"
or type ( value . edges [ name ] ) ~= "table"
or type ( value . unknown [ name ] ) ~= "boolean"
then
return false
end
local count = 0
for index , required in pairs ( value . edges [ name ] ) do
if type ( index ) ~= "number"
or index < 1
or index ~= math . floor ( index )
or type ( required ) ~= "string"
or type ( value . files [ required ] ) ~= "string"
then
return false
end
count = count + 1
end
for index = 1 , count do
if type ( value . edges [ name ] [ index ] ) ~= "string" then
return false
end
end
end
for name in pairs ( value . digests ) do
if type ( name ) ~= "string" or type ( value . files [ name ] ) ~= "string" then
return false
end
end
for name in pairs ( value . edges ) do
if type ( name ) ~= "string" or type ( value . files [ name ] ) ~= "string" then
return false
end
end
for name in pairs ( value . unknown ) do
if type ( name ) ~= "string" or type ( value . files [ name ] ) ~= "string" then
return false
end
end

return true
end



local function moduleNameOf ( root , path ) 
if path : sub ( 1 , # root + 1 ) ~= root .. "/" then
return nil
end
local relative = path : sub ( # root + 2 ) : gsub ( "%.lua$" , "" )
local name = relative : gsub ( "/" , "." )
name = name : gsub ( "%.init$" , "" )

return name ~= "" and name or nil
end























local function requiredBy ( text , path ) 
local lexer = require ( "nupp.compiler.syntax.lexer" )
local tokens = lexer . lex ( text , path )
local names = { }
local declared = { }
local reflective = false
for pattern in text : gmatch ( "@requires%-dynamically%s+([%w%.%*%-_]+)" ) do
if pattern == "nothing" then
reflective = true
else
declared [ # declared + 1 ] = pattern
end
end
for index = 1 , # tokens do
local token = tokens [ index ]
local previous = tokens [ index - 1 ]
local following = tokens [ index + 1 ]
local globalRequire = previous
and previous . text == "."
and tokens [ index - 2 ]
and tokens [ index - 2 ] . text == "_G"
and not ( tokens [ index - 3 ] and ( tokens [ index - 3 ] . text == "." or tokens [ index - 3 ] . text == ":" ) )
local callPrefix = globalRequire and tokens [ index - 3 ] or previous
if token . kind == "name"
and token . text == "require"
and ( globalRequire or not ( previous and ( previous . text == "." or previous . text == ":" ) ) )
and not ( previous and previous . text == "function" )
and not ( following and following . text == "=" )
then
local literal = nil
if following and following . kind == "string" then
literal = following
elseif following and following . text == "(" and tokens [ index + 2 ] and tokens [ index + 2 ] . kind == "string" then
literal = tokens [ index + 2 ]
elseif following
and following . text == ","
and callPrefix
and callPrefix . text == "("
and tokens [ index + 2 ]
and tokens [ index + 2 ] . kind == "string"
then
literal = tokens [ index + 2 ]
end
if not literal then
return names , not ( reflective or # declared > 0 ) , declared
end


local chunk = loadstring ( "return " .. literal . text )
if not chunk then
return names , not ( reflective or # declared > 0 ) , declared
end
local ok , value = pcall ( chunk )
if not ok or type ( value ) ~= "string" then
return names , not ( reflective or # declared > 0 ) , declared
end
names [ # names + 1 ] = value
end
end

return names , false , declared
end









local function moduleGraph (
cacheDir ,
digest ,
readOnly
) 
if graphAttempted and ( graphMemo == nil or cacheDir == nil or graphStoredIn [ cacheDir ] ) then
return graphMemo
end
graphAttempted = true
local dir = compilerDir ( )


if bundled ( ) then
return nil
end


local root = dirname ( dirname ( dir ) )
local store = nil
if cacheDir then
if not readOnly then
graphStoredIn [ cacheDir ] = true
end
store = require (
"nupp.compiler.project.store"
) . openValue ( join ( cacheDir , "modulegraph.buf" ) , "modules/2" .. "\0" .. graphFingerprint ( digest ) )
local stored = store . value
if validGraph ( stored ) then
graphMemo = stored

return graphMemo
end

if graphMemo ~= nil then
if not readOnly then
store . set ( graphMemo )
store . save ( )
end

return graphMemo
end
end
local graph = { files = { } , edges = { } , digests = { } , unknown = { } }
local sources = { }




for _ , path in ipairs ( treeFiles ( join ( root , "nupp" ) ) ) do
if path : match ( "%.lua$" ) then
local name = moduleNameOf ( root , path )
local text = name and readFile ( path ) or nil
if name and text then
graph . files [ name ] = path
graph . digests [ name ] = digest ( text )
sources [ name ] = text
end
end
end
for name , text in pairs ( sources ) do
local required , unknown , declared = requiredBy ( text , graph . files [ name ] or name )
graph . unknown [ name ] = unknown
local edges = { }
local added = { }
for _ , required_name in ipairs ( required ) do
if graph . files [ required_name ] and not added [ required_name ] then
added [ required_name ] = true
edges [ # edges + 1 ] = required_name
end
end


for _ , pattern in ipairs ( declared ) do
local prefix = pattern : match ( "^(.+)%.%*$" )
if prefix then
for candidate in pairs ( graph . files ) do
if candidate : sub ( 1 , # prefix + 1 ) == prefix .. "." and not added [ candidate ] then
added [ candidate ] = true
edges [ # edges + 1 ] = candidate
end
end
elseif graph . files [ pattern ] and not added [ pattern ] then
added [ pattern ] = true
edges [ # edges + 1 ] = pattern
end
end
table . sort ( edges )
graph . edges [ name ] = edges
end
graphMemo = graph
if store and not readOnly then
store . set ( graph )
store . save ( )
end

return graphMemo
end











function fingerprint . sharedCacheDir ( fallback ) 
local named = os . getenv ( "NUPP_CACHE_DIR" )
if named and named ~= "" then
return named
end

return fallback
end

local subsystemMemo = { }

















function fingerprint . subsystemFingerprint (
roots ,
cacheDir ,
contentDigest ,
readOnly
) 
local digest = contentDigest or hash . digest
local ordered = { }
for index , name in ipairs ( roots ) do
ordered [ index ] = name
end
table . sort ( ordered )
local memoKey = table . concat ( ordered , "\0" )
local remembered = subsystemMemo [ memoKey ]
if remembered then
return remembered
end
local graph = moduleGraph ( cacheDir , digest , readOnly )
local answer = nil
if graph then
local reached = { }
local pending = { }
for _ , name in ipairs ( ordered ) do
pending [ # pending + 1 ] = name
end
local complete = true
while # pending > 0 do
local name = table . remove ( pending )
if not reached [ name ] then
if not graph . digests [ name ] then
complete = false
do break end
end
if graph . unknown [ name ] then
complete = false
do break end
end
reached [ name ] = true
for _ , required in ipairs ( graph . edges [ name ] or { } ) do
pending [ # pending + 1 ] = required
end
end
end
if complete then
local parts = { }
for name in pairs ( reached ) do
parts [ # parts + 1 ] = name .. "\0" .. ( graph . digests [ name ] or "missing" )
end
table . sort ( parts )
answer = digest ( table . concat ( parts , "\0" ) )
end
end


answer = answer or graphFingerprint ( digest )
subsystemMemo [ memoKey ] = answer

return answer
end

local declarationMemo = nil


















function fingerprint . declarationFingerprint (
contentDigest ,
listDeclarations ,
readDeclaration
) 
local own = contentDigest == nil and listDeclarations == nil and readDeclaration == nil
if own and declarationMemo ~= nil then
return declarationMemo
end
local digest = contentDigest or hash . digest
local list = listDeclarations or require ( "nupp.compiler.bundledlist" ) . list
local read = readDeclaration or require ( "nupp.compiler.bundled" ) . source
local parts = { }
for _ , relative in ipairs ( list ( "/decls" ) ) do
parts [ # parts + 1 ] = relative .. "\0" .. ( read ( relative ) or "missing" )
end
table . sort ( parts )
local answer = digest ( table . concat ( parts , "\0" ) )
if own then
declarationMemo = answer
end

return answer
end

fingerprint . hashFile = hashFile
fingerprint . hashFiles = hashFiles
fingerprint . toolFingerprint = toolFingerprint
fingerprint . graphFingerprint = graphFingerprint

local __nuppExportValue= fingerprint ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.fingerprint"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.fingerprint"]=__nuppExports;return __nuppExports