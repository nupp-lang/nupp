_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()








































































































local hash = require ( "nupp.compiler.hash" )
local triviaarena = require ( "nupp.compiler.syntax.triviaarena" )
local types = require ( "nupp.compiler.types" )

local preludecache = { }





local ROOT_NAMES = {
"annotationsByName" ,
"featureEffects" ,
"globalTypeDefs" ,
"globalTypes" ,
"globals" ,
"preludeComptimeFunctions" ,
"stringLib" ,
}



local FORMAT = 3
















function preludecache . origin ( ) 
local identity = types . identity ( )

return { serial = identity . serial , capability = identity . capability , nominal = identity . nominal }
end






function preludecache . seal ( origin ) 
if origin . digest ~= nil then
return origin . digest
end
local identity = types . identity ( )
if identity . serial ~= origin . serial
or identity . capability ~= origin . capability
or identity . nominal ~= origin . nominal
then
return nil
end
local lines = { }
for bucket , entries in pairs ( identity . arenas ) do
for key , value in pairs ( entries ) do
local id = type ( value ) == "table" and ( value ) . id or nil
lines [ # lines + 1 ] = bucket .. "\0" .. key .. "\0" .. tostring ( id )
end
end
table . sort ( lines )
origin . digest = hash . digest ( table . concat ( lines , "\n" ) )

return origin . digest
end

local function isOrigin ( value ) 
return type ( value ) == "table"
and type ( value . serial ) == "number"
and type ( value . capability ) == "number"
and type ( value . nominal ) == "number"
and type ( value . digest ) == "string"
end



local function sameOrigin ( recorded , origin ) 
if not ( type ( recorded ) == "table" and type ( recorded . serial ) == "number" and type ( recorded . capability ) == "number" and type ( recorded . nominal ) == "number" and type ( recorded . digest ) == "string" )
or recorded . serial ~= origin . serial
or recorded . capability ~= origin . capability
or recorded . nominal ~= origin . nominal
then
return false
end

return recorded . digest == preludecache . seal ( origin )
end









function preludecache . replaces ( stored , origin ) 
local recorded = type ( stored ) == "table" and stored . format == 3 and stored . origin or nil
if not ( type ( recorded ) == "table" and type ( recorded . serial ) == "number" and type ( recorded . capability ) == "number" and type ( recorded . nominal ) == "number" and type ( recorded . digest ) == "string" ) then
return true
end
if recorded . serial ~= origin . serial then
return recorded . serial > origin . serial
end

return sameOrigin ( recorded , origin )
end

local function isScalar ( value ) 
local kind = type ( value )

return kind == "boolean" or kind == "number" or kind == "string"
end






local WALK_DEPTH = 8










const _DYNAMIC_REQUIRES = "@requires-dynamically nothing"






local function ownedByModules ( ) 
local owned = { }
local moduleNames = { }
for name in pairs ( package . loaded ) do
if type ( name ) == "string" and name : match ( "^nupp%." ) then
moduleNames [ # moduleNames + 1 ] = name
end
end
table . sort ( moduleNames )

local function claim ( value , moduleName , path , depth ) 
if type ( value ) ~= "table" or owned [ value ] ~= nil or depth > 8 then
return
end
owned [ value ] = { moduleName , path }
local keys = { }
for key in pairs ( value ) do
if type ( key ) == "string" then
keys [ # keys + 1 ] = key
end
end
table . sort ( keys )
for _ , key in ipairs ( keys ) do
claim ( ( value ) [ key ] , moduleName , path == "" and key or ( path .. "." .. key ) , depth + 1 )
end
end

for _ , moduleName in ipairs ( moduleNames ) do
claim ( package . loaded [ moduleName ] , moduleName , "" , 0 )
end

return owned
end


local function resolveOwned ( entry ) 
if type ( entry ) ~= "table" or type ( entry [ 1 ] ) ~= "string" or type ( entry [ 2 ] ) ~= "string" then
return nil
end
local loaded = package . loaded [ entry [ 1 ] ]
if loaded == nil then
local ok , required = pcall ( require , entry [ 1 ] )
if not ok then
return nil
end
loaded = required
end
local value = loaded
if entry [ 2 ] ~= "" then
for part in ( entry [ 2 ] ) : gmatch ( "[^%.]+" ) do
if type ( value ) ~= "table" then
return nil
end
value = value [ part ]
end
end
if type ( value ) ~= "table" then
return nil
end

return value
end


local SCALAR = 0
local REFERENCE = 1
local OWNED = 2

local function isInteger ( value ) 
return type ( value ) == "number"
and value == value
and value ~= math . huge
and value ~= - math . huge
and value == math . floor ( value )
end


local function arrayLength ( value ) 
if type ( value ) ~= "table" then
return nil
end
local length = # value
for key in pairs ( value ) do
if not ( type ( key ) == "number" and key == key and key ~= math . huge and key ~= - math . huge and key == math . floor ( key ) ) or key < 1 or key > length then
return nil
end
end
for index = 1 , length do
if value [ index ] == nil then
return nil
end
end

return length
end











function preludecache . encode ( roots , origin ) 
if origin == nil or origin . digest == nil then
return nil
end
local owned = ownedByModules ( )
local identity = types . identity ( )





local internedAt = { }
for bucket , entries in pairs ( identity . arenas ) do
for key , value in pairs ( entries ) do
if internedAt [ value ] == nil then
internedAt [ value ] = { bucket , key }
end
end
end
local externs = { }
local externIds = { }
local ids = { }
local tables = { }
local pending = { }
local arenaIds = { }
local arenas = { }
local metas = { }
local metaExterns = { }
local triviaOf = { }

local function externFor ( value ) 
local known = externIds [ value ]
if known ~= nil then
return known
end
local id = # externs + 1
externs [ id ] = owned [ value ]
externIds [ value ] = id

return id
end

local function identify ( value ) 
if type ( value ) ~= "table" or ids [ value ] ~= nil then
return
end



if owned [ value ] ~= nil and internedAt [ value ] == nil then
return
end
local id = # tables + 1
ids [ value ] = id
tables [ id ] = value
pending [ # pending + 1 ] = value
end

local function arenaFor ( arena ) 
local known = arenaIds [ arena ]
if known ~= nil then
return known
end
local source = ( arena ) . source
local count = ( arena ) . count
if type ( source ) ~= "string" or type ( count ) ~= "number" then
return nil
end
local records = { }
for index = 1 , count do
local kind , offset , length , line , col = ( arena ) : record ( index )
local at = # records
records [ at + 1 ] = kind
records [ at + 2 ] = offset
records [ at + 3 ] = length
records [ at + 4 ] = line
records [ at + 5 ] = col
end
local id = # arenas + 1
arenas [ id ] = { source = source , records = records }
arenaIds [ arena ] = id

return id
end

for _ , name in ipairs ( ROOT_NAMES ) do


if owned [ roots [ name ] ] ~= nil then
return nil
end
identify ( roots [ name ] )
end











for _ , entries in pairs ( identity . arenas ) do
for _ , value in pairs ( entries ) do
identify ( value )
end
end

local at = 1
while at <= # pending do
local owner = pending [ at ]
local id = ids [ owner ]
local trivia = ( owner ) . trivia
if trivia ~= nil then
local arena = arenaFor ( trivia )
if arena == nil then
return nil
end
triviaOf [ id ] = arena
end
for key , value in pairs ( owner ) do
if key ~= "trivia" then
if not isScalar ( key ) and type ( key ) ~= "table" then
return nil
end
if not isScalar ( value ) and type ( value ) ~= "table" then
return nil
end
identify ( key )
identify ( value )
end
end
local meta = getmetatable ( owner )
if meta ~= nil then
if type ( meta ) ~= "table" then
return nil
end
if owned [ meta ] ~= nil and internedAt [ meta ] == nil then
metaExterns [ id ] = externFor ( meta )
else
identify ( meta )
metas [ id ] = ids [ meta ]
end
end
at = at + 1
end



local counts = { }
local cells = { }
local tags = { }
local written = 0

local function writeCell ( value ) 
written = written + 1
if owned [ value ] ~= nil and internedAt [ value ] == nil then
tags [ written ] = 2
cells [ written ] = externFor ( value )
elseif ids [ value ] ~= nil then
tags [ written ] = 1
cells [ written ] = ids [ value ]
else
tags [ written ] = 0
cells [ written ] = value
end
end

for id = 1 , # tables do
local members = 0
for key , value in pairs ( tables [ id ] ) do
if key ~= "trivia" then
members = members + 1
writeCell ( key )
writeCell ( value )
end
end
counts [ id ] = members
end

local rootIds = { }
for index , name in ipairs ( ROOT_NAMES ) do
rootIds [ index ] = ids [ roots [ name ] ] or 0
end

local internedAs = { }
for value , where in pairs ( internedAt ) do
local id = ids [ value ]
if id ~= nil then
internedAs [ id ] = where
end
end

return {
format = 3 ,
counts = counts ,
cells = cells ,
tags = tags ,
externs = externs ,
metas = metas ,
metaExterns = metaExterns ,
arenas = arenas ,
triviaOf = triviaOf ,
internedAs = internedAs ,
identity = { serial = identity . serial , capability = identity . capability , nominal = identity . nominal , } ,
origin = {
serial = origin . serial ,
capability = origin . capability ,
nominal = origin . nominal ,
digest = origin . digest ,
} ,
roots = rootIds ,
runtime = roots . preludeRuntime ,
}
end












function preludecache . decode ( image , origin ) 
if type ( image ) ~= "table" or image . format ~= 3 then
return nil
end
if not sameOrigin ( image . origin , origin or preludecache . origin ( ) ) then
return nil
end
local counts = image . counts
local cells = image . cells
local tags = image . tags
local countLength = arrayLength ( counts )
local cellLength = arrayLength ( cells )
local tagLength = arrayLength ( tags )
local externLength = arrayLength ( image . externs )
local arenaLength = arrayLength ( image . arenas )
local rootLength = arrayLength ( image . roots )
if countLength == nil
or cellLength == nil
or tagLength == nil
or externLength == nil
or arenaLength == nil
or rootLength ~= # ROOT_NAMES
or type ( image . metas ) ~= "table"
or type ( image . metaExterns ) ~= "table"
or type ( image . triviaOf ) ~= "table"
or type ( image . internedAs ) ~= "table"
or type ( image . identity ) ~= "table"
or type ( image . runtime ) ~= "string"
then
return nil
end

local externs = { }
for index , entry in ipairs ( image . externs ) do
if arrayLength ( entry ) ~= 2
or type ( entry [ 1 ] ) ~= "string"
or not ( entry [ 1 ] ) : match ( "^nupp%." )
or type ( entry [ 2 ] ) ~= "string"
then
return nil
end
local resolved = resolveOwned ( entry )

if resolved == nil then
return nil
end
externs [ index ] = resolved
end





local expected = 0
for id = 1 , countLength do
local members = counts [ id ]
if not ( type ( members ) == "number" and members == members and members ~= math . huge and members ~= - math . huge and members == math . floor ( members ) ) or members < 0 or members > ( cellLength - expected ) / 2 then
return nil
end
expected = expected + ( members ) * 2
end
if expected ~= cellLength or tagLength ~= cellLength then
return nil
end
for index = 1 , cellLength do
local tag = tags [ index ]
if tag == 1 then
local target = cells [ index ]
if not ( type ( target ) == "number" and target == target and target ~= math . huge and target ~= - math . huge and target == math . floor ( target ) ) or target < 1 or target > countLength then
return nil
end
elseif tag == 2 then
local target = cells [ index ]
if not ( type ( target ) == "number" and target == target and target ~= math . huge and target ~= - math . huge and target == math . floor ( target ) ) or target < 1 or target > externLength then
return nil
end
elseif tag ~= 0 or not isScalar ( cells [ index ] ) then
return nil
elseif index % 2 == 1 and type ( cells [ index ] ) == "number" and cells [ index ] ~= cells [ index ] then
return nil
end
end

local liveIdentity = types . identity ( )
local internedKeys = { }
for id , where in pairs ( image . internedAs ) do
if not ( type ( id ) == "number" and id == id and id ~= math . huge and id ~= - math . huge and id == math . floor ( id ) )
or id < 1
or id > countLength
or arrayLength ( where ) ~= 2
or type ( where [ 1 ] ) ~= "string"
or type ( where [ 2 ] ) ~= "string"
or type ( liveIdentity . arenas [ where [ 1 ] ] ) ~= "table"
then
return nil
end
local bucket = where [ 1 ]
local key = where [ 2 ]
local seen = internedKeys [ bucket ]
if seen == nil then
seen = { }
internedKeys [ bucket ] = seen
elseif seen [ key ] then
return nil
end
seen [ key ] = true
end

for _ , field in ipairs ( { image . metas , image . metaExterns , image . triviaOf } ) do
for id , target in pairs ( field ) do
if not ( type ( id ) == "number" and id == id and id ~= math . huge and id ~= - math . huge and id == math . floor ( id ) ) or id < 1 or id > countLength or not ( type ( target ) == "number" and target == target and target ~= math . huge and target ~= - math . huge and target == math . floor ( target ) ) or target < 1 then
return nil
end
end
end
for id , target in pairs ( image . metas ) do
if target > countLength or image . metaExterns [ id ] ~= nil then
return nil
end
end
for _ , target in pairs ( image . metaExterns ) do
if target > externLength then
return nil
end
end
for _ , target in pairs ( image . triviaOf ) do
if target > arenaLength then
return nil
end
end

for _ , arena in ipairs ( image . arenas ) do
if type ( arena ) ~= "table" or type ( arena . source ) ~= "string" then
return nil
end
local recordLength = arrayLength ( arena . records )
if recordLength == nil or recordLength % 5 ~= 0 then
return nil
end
local previousEnd = 1
for cursor = 1 , recordLength , 5 do
local kind = arena . records [ cursor ]
local offset = arena . records [ cursor + 1 ]
local length = arena . records [ cursor + 2 ]
local line = arena . records [ cursor + 3 ]
local col = arena . records [ cursor + 4 ]
if not ( type ( kind ) == "number" and kind == kind and kind ~= math . huge and kind ~= - math . huge and kind == math . floor ( kind ) )
or kind < 1
or kind > 4
or not ( type ( offset ) == "number" and offset == offset and offset ~= math . huge and offset ~= - math . huge and offset == math . floor ( offset ) )
or offset < previousEnd
or not ( type ( length ) == "number" and length == length and length ~= math . huge and length ~= - math . huge and length == math . floor ( length ) )
or length < 1
or offset + length - 1 > # ( arena . source )
or not ( type ( line ) == "number" and line == line and line ~= math . huge and line ~= - math . huge and line == math . floor ( line ) )
or line < 1
or not ( type ( col ) == "number" and col == col and col ~= math . huge and col ~= - math . huge and col == math . floor ( col ) )
or col < 1
then
return nil
end
previousEnd = ( offset ) + ( length )
end
end

for index = 1 , rootLength do
local id = image . roots [ index ]
if not ( type ( id ) == "number" and id == id and id ~= math . huge and id ~= - math . huge and id == math . floor ( id ) ) or id < 0 or id > countLength then
return nil
end
end
for _ , name in ipairs ( { "serial" , "capability" , "nominal" } ) do
local value = image . identity [ name ]
if not ( type ( value ) == "number" and value == value and value ~= math . huge and value ~= - math . huge and value == math . floor ( value ) ) or value < 0 then
return nil
end
end















local built = { }
local mine = { }
local adopting = { }
for id = 1 , countLength do
local where = image . internedAs [ id ]
local live = nil
if type ( where ) == "table" and type ( where [ 1 ] ) == "string" and type ( where [ 2 ] ) == "string" then
live = types . interned ( where [ 1 ] , where [ 2 ] )
if live == nil then
adopting [ # adopting + 1 ] = id
end
end
built [ id ] = live or { }
mine [ id ] = live == nil
end

local at = 1

local function readCell ( ) 
local tag = tags [ at ]
local cell = cells [ at ]
at = at + 1
if tag == 1 then
return built [ cell ]
elseif tag == 2 then
return externs [ cell ]
end

return cell
end

for id = 1 , countLength do
local target = mine [ id ] and built [ id ] or nil
for _ = 1 , counts [ id ] do
local key = readCell ( )
local value = readCell ( )
if key == nil then
return nil
end
if target ~= nil then
target [ key ] = value
end
end
end
for id , meta in pairs ( image . metas ) do
local owner = mine [ id ] and built [ id ] or nil
local metatable = built [ meta ]
if metatable == nil then
return nil
end
if owner ~= nil then
setmetatable ( owner , metatable )
end
end
for id , extern in pairs ( image . metaExterns ) do
local owner = mine [ id ] and built [ id ] or nil
local metatable = externs [ extern ]
if metatable == nil then
return nil
end
if owner ~= nil then
setmetatable ( owner , metatable )
end
end

local rebuilt = { }
for index , arena in ipairs ( image . arenas ) do
local made = triviaarena . new ( arena . source )
local records = arena . records
local count = # records
local cursor = 1
while cursor + 4 <= count do
made : append (
records [ cursor ] ,
records [ cursor + 1 ] ,
records [ cursor + 2 ] ,
records [ cursor + 3 ] ,
records [ cursor + 4 ]
)
cursor = cursor + 5
end
rebuilt [ index ] = made
end
for id , arena in pairs ( image . triviaOf ) do
local owner = mine [ id ] and built [ id ] or nil
local made = rebuilt [ arena ]
if made == nil then
return nil
end
if owner ~= nil then
owner . trivia = made
end
end


for _ , id in ipairs ( adopting ) do
local where = image . internedAs [ id ]
types . adopt ( where [ 1 ] , where [ 2 ] , built [ id ] )
end


types . resumeIdentity ( image . identity )

local roots = { }
for index , name in ipairs ( ROOT_NAMES ) do
local id = image . roots [ index ]
roots [ name ] = id ~= 0 and built [ id ] or nil
end
roots . preludeRuntime = image . runtime

return roots
end

local __nuppExportValue= preludecache ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.preludecache"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.preludecache"]=__nuppExports;return __nuppExports