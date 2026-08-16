_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON);


















local hash = require ( "nupp.compiler.build.hash" )
local json = require ( "cjson" ) . new ( )
local fs = require ( "nupp.compiler.fs" )

local join = fs . join
local dirname , basename = fs . dirname , fs . basename
local readFile , writeFile = fs . readFile , fs . writeFile
local listFiles = fs . listFiles

local cache = { }




























































































local function jsonArray ( items )
return setmetatable ( items , json . array_mt )
end

local function stable ( value , seen )



local kind = type ( value )

if kind == "nil" then
return "nil"
end
if kind == "boolean" or kind == "number" then
return tostring ( value )
end

if kind == "string" then
return ( "%q" ) : format ( value )
end

if kind ~= "table" then
return "<" .. kind .. ">"
end


local entries = value
seen = seen or { }
if seen [ value ] then
return "<cycle>"
end
seen [ value ] = true
local keys = { }
for key in pairs ( entries ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys , function ( a , b )
return tostring ( a ) < tostring ( b )
end )
local parts = { }
for _ , key in ipairs ( keys ) do
parts [ # parts + 1 ] = stable ( key , seen ) .. "=" .. stable ( entries [ key ] , seen )
end
seen [ value ] = nil

return "{" .. table . concat ( parts , "," ) .. "}"
end

local function hashFile ( path )
local text = readFile ( path )
return text and hash . digest ( text ) or nil
end

local function hashFiles ( files )
local parts = { }
for _ , path in ipairs ( files ) do
parts [ # parts + 1 ] = path .. "\0" .. ( hashFile ( path ) or "missing" )
end

return hash . digest ( table . concat ( parts , "\0" ) )
end

local function moduleDir ( )
local source = debug . getinfo ( 1 , "S" ) . source
return source : match ( "^@(.*)[/\\]" ) or "."
end




local toolFingerprintMemo = nil

local function toolFingerprint ( )
if toolFingerprintMemo then
return toolFingerprintMemo
end
local dir = moduleDir ( )


if basename ( dir ) == "build" then
dir = dirname ( dir )
end
local files = { }
if dir : match ( "bootstrap$" ) then
files = { join ( dir , "nupp.lua" ) }
else
for _ , path in ipairs ( listFiles ( dir ) ) do
if path : match ( "%.lua$" ) then
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
parts [ # parts + 1 ] = relative .. "\0" .. ( hashFile ( path ) or "missing" )
end
table . sort ( parts )
toolFingerprintMemo = hash . digest ( table . concat ( parts , "\0" ) )

return toolFingerprintMemo
end




local STATE_VERSION = 2

local function emptyState ( )
return { version = STATE_VERSION , modules = { } , dependencies = { } , outputs = { } , targets = { } }
end

local function loadState ( path )
local text = readFile ( path )
if not text then
return emptyState ( )
end
local ok , state = pcall ( json . decode , text )
if not ok or type ( state ) ~= "table" or state . version ~= STATE_VERSION then
return emptyState ( )
end
state . modules = state . modules or { }
state . dependencies = state . dependencies or { }
state . outputs = state . outputs or { }



state . targets = state . targets or { }

return state
end

local function saveState ( path , state )
return writeFile ( path , json . encode ( state ) .. "\n" )
end

cache . jsonArray = jsonArray
cache . stable = stable
cache . hashFile = hashFile
cache . hashFiles = hashFiles
cache . moduleDir = moduleDir
cache . toolFingerprint = toolFingerprint
cache . loadState = loadState
cache . saveState = saveState
cache . emptyState = emptyState
cache . STATE_VERSION = STATE_VERSION

return cache
