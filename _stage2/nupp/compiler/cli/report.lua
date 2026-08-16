_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON);











local fs = require ( "nupp.compiler.fs" )
local explain = require ( "nupp.compiler.explain" )

local report = { }

local REPORTED = { note = "note" , warning = "warning" }



local function positionAtByte ( source , offset )
if not source or not offset or offset < 1 then
return { line = 0 , column = 0 , offset = offset or 0 }
end
local line , lineStart , cursor = 1 , 1 , 1
while cursor < offset and cursor <= # source do
if source : byte ( cursor ) == 10 then
line , lineStart = line + 1 , cursor + 1
end
cursor = cursor + 1
end

return { line = line , column = offset - lineStart + 1 , offset = offset }
end


local function sourceReader ( )
local sources = { }
return function ( path )
if not path then
return nil
end
if sources [ path ] == nil then
sources [ path ] = fs . readFile ( path ) or false
end

return sources [ path ] or nil
end
end

local function rangeAt ( source , offset , length )
local start = positionAtByte ( source , offset or 1 )
local span = length or 0
if source then
return { start = start , [ "end" ] = positionAtByte ( source , math . min ( # source + 1 , ( offset or 1 ) + span ) ) }
end

return {
start = start ,
[ "end" ] = { line = start . line , column = start . column + ( length or 1 ) , offset = start . offset + ( length or 1 ) }
}
end





function report . encode ( value )
local encoder = require ( "cjson" ) . new ( )
encoder . encode_empty_table_as_object ( false )
encoder . encode_invalid_numbers ( false )
return encoder . encode ( value )
end



function report . write ( value )
io . write ( report . encode ( value ) .. "\n" )
end



function report . diagnosticValues ( diagnostics )
local read = sourceReader ( )
local values = { }
for _ , e in ipairs ( diagnostics ) do
local source = read ( e . filename )
local fixes = { }
for _ , fix in ipairs ( e . fixes or { } ) do
local edits = { }
for _ , edit in ipairs ( fix . edits or { } ) do
edits [
# edits + 1
] = {
file = e . filename ,
range = {
start = positionAtByte ( source , edit . offset ) ,
[ "end" ] = positionAtByte ( source , edit . offset + edit . length )
} ,
newText = edit . newText ,
}
end
fixes [ # fixes + 1 ] = { title = fix . title , edits = edits }
end
local related = { }
for _ , item in ipairs ( e . related or { } ) do
local relatedFile = item . filename or e . filename
related [
# related + 1
] = {
file = relatedFile ,
message = item . message ,
range = rangeAt ( read ( relatedFile ) , item . offset , item . length )
}
end
values [ # values + 1 ] = {
file = e . filename ,
severity = REPORTED [ e . severity ] or "error" ,
code = e . code ,
lint = e . lint ,



docs = explain . anchor ( e . code ) ,
message = e . msg ,
range = rangeAt ( source , e . offset , e . length ) ,
fixes = fixes ,
help = e . help ,
notes = e . notes or { } ,
related = related ,
}
end

return values
end



function report . json ( diagnostics )
report . write ( { diagnostics = report . diagnosticValues ( diagnostics ) } )
end


function report . fatal ( diagnostic )
return REPORTED [ diagnostic . severity ] == nil
end





local POSITION = {
type = "object" ,
description = "A 1-based byte position." ,
properties = { line = { type = "integer" } , column = { type = "integer" } , offset = { type = "integer" } , } ,
required = { "line" , "column" , "offset" } ,
}

local RANGE = { type = "object" , properties = { start = POSITION , [ "end" ] = POSITION } , required = { "start" , "end" } , }



report . POSITION = POSITION

report . RANGE = RANGE


report . LOCATION = {
type = "object" ,
properties = { file = { type = "string" } , range = RANGE } ,
required = { "file" , "range" } ,
}

local EDIT = {
type = "object" ,
properties = { file = { type = "string" } , range = RANGE , newText = { type = "string" } , } ,
required = { "range" , "newText" } ,
}


report . DIAGNOSTIC = {
type = "object" ,
properties = {
file = { type = "string" } ,
severity = { type = "string" , enum = { "error" , "warning" , "note" } } ,
code = {
type = "string" ,
description = "A stable code such as NUPP2004, or OPT-n for an " .. "optimizer remark."
} ,
lint = {
type = "string" ,
description = "The lint name, when the diagnostic came from one. "
.. "This is what an @allow suppression writes."
} ,
docs = {
type = "string" ,
description = "The reference section covering this code, as a path "
.. "and anchor. 'nupp explain <code>' says more."
} ,
message = { type = "string" } ,
range = RANGE ,
help = { type = "string" , description = "A concrete repair direction." } ,
notes = { type = "array" , items = { type = "string" } } ,
related = {
type = "array" ,
items = {
type = "object" ,
properties = { file = { type = "string" } , message = { type = "string" } , range = RANGE } ,
required = { "range" } ,
} ,
} ,
fixes = {
type = "array" ,
description = "Machine-applicable repairs. A fix is all-or-nothing: " .. "apply every edit in it or none." ,
items = {
type = "object" ,
properties = { title = { type = "string" } , edits = { type = "array" , items = EDIT } } ,
required = { "title" , "edits" } ,
} ,
} ,
} ,
required = { "severity" , "message" , "range" , "fixes" , "notes" , "related" } ,
}



report . DIAGNOSTICS = { type = "array" , items = report . DIAGNOSTIC }

return report
