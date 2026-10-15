_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












const json = require ( "nupp.codec.json" )

local fs = require ( "nupp.compiler.fs" )
local explain = require ( "nupp.tools.explain" )
local diagnosticMod = require ( "nupp.compiler.diagnostics" )

local report = { }









local function indexed ( text ) 
local lineStarts = { 1 }
local at = text : find ( "\n" , 1 , true )
while at do
lineStarts [ # lineStarts + 1 ] = at + 1
at = text : find ( "\n" , at + 1 , true )
end

return { text = text , lineStarts = lineStarts }
end




local function positionAtByte ( source , offset ) 
if not source or not offset or offset < 1 then
return { line = 0 , column = 0 , offset = offset or 0 }
end
local starts = source . lineStarts
local low , high = 1 , # starts
while low < high do
local middle = math . floor ( ( low + high + 1 ) / 2 )
if starts [ middle ] <= offset then
low = middle
else
high = middle - 1
end
end

return { line = low , column = offset - starts [ low ] + 1 , offset = offset }
end



local function sourceReader ( ) 
local sources = { }
return function ( path ) 
if not path then
return nil
end
if sources [ path ] == nil then
local text = fs . readFile ( path )
sources [ path ] = text and indexed ( text ) or false
end

return sources [ path ] or nil
end
end

local function rangeAt ( source , offset , length ) 
local start = positionAtByte ( source , offset or 1 )
local span = length or 0
if source then
return { start = start , [ "end" ] = positionAtByte ( source , math . min ( # source . text + 1 , ( offset or 1 ) + span ) ) }
end

return {
start = start ,
[ "end" ] = { line = start . line , column = start . column + ( length or 1 ) , offset = start . offset + ( length or 1 ) }
}
end

local function withArrayEmpties ( value , seen ) 
if type ( value ) ~= "table" then
return value
end
seen = seen or { }
if seen [ value ] then
return seen [ value ]
end
local copied = { }
seen [ value ] = copied
for key , item in pairs ( value ) do
copied [ key ] = withArrayEmpties ( item , seen )
end
if next ( copied ) == nil then
return json . asArray ( copied )
end

return copied
end




local REPLACEMENT = "ï¿½"

local function validUtf8 ( text ) 
if not text : find ( "[€-ÿ]" ) then
return text
end
local out = { }
local index = 1
local length = # text
while index <= length do
local first = text : byte ( index )
local width = 0
local low , high = 128 , 191
if first < 128 then
width = 1
elseif first >= 194 and first <= 223 then
width = 2
elseif first >= 224 and first <= 239 then
width = 3
low = first == 224 and 160 or 128
high = first == 237 and 159 or 191
elseif first >= 240 and first <= 244 then
width = 4
low = first == 240 and 144 or 128
high = first == 244 and 143 or 191
end
local valid = width > 0 and index + width - 1 <= length
for offset = 1 , width - 1 do
local byte = text : byte ( index + offset )
local lower , upper = 128 , 191
if offset == 1 then
lower , upper = low , high
end
if not byte or byte < lower or byte > upper then
valid = false
do break end
end
end
if valid then
out [ # out + 1 ] = text : sub ( index , index + width - 1 )
index = index + width
else
out [ # out + 1 ] = "ï¿½"
index = index + 1
end
end

return table . concat ( out )
end

local function stableEncode ( value , visiting ) 
if type ( value ) == "string" then
return json . encode ( validUtf8 ( value ) )
end
if type ( value ) ~= "table" then
return json . encode ( value )
end
visiting = visiting or { }
if visiting [ value ] then
error ( "cannot serialize a cyclic Lua table" , 0 )
end
visiting [ value ] = true
local parts = { }
if json . isArray ( value ) then
for index , item in ipairs ( value ) do
parts [ index ] = stableEncode ( item , visiting )
end
visiting [ value ] = nil

return "[" .. table . concat ( parts , "," ) .. "]"
end
local keys = { }
for key in pairs ( value ) do
if type ( key ) ~= "string" then
error ( "JSON object keys must be strings" , 0 )
end
keys [ # keys + 1 ] = key
end
table . sort ( keys )
for index , key in ipairs ( keys ) do
parts [ index ] = json . encode ( validUtf8 ( key ) ) .. ":" .. stableEncode ( ( value ) [ key ] , visiting )
end
visiting [ value ] = nil

return "{" .. table . concat ( parts , "," ) .. "}"
end





function report . encode ( value ) 
return stableEncode ( withArrayEmpties ( value ) )
end








local function indented ( compact ) 
local out = { }
local depth = 0
local index = 1
while index <= # compact do
local at = compact : find ( "[%[%]{},:\"]" , index )
if not at then
out [ # out + 1 ] = compact : sub ( index )
do break end
end
if at > index then
out [ # out + 1 ] = compact : sub ( index , at - 1 )
end
local char = compact : sub ( at , at )
index = at + 1
if char == "\"" then
local stop = index
while stop <= # compact do
local inner = compact : sub ( stop , stop )
if inner == "\\" then
stop = stop + 2
elseif inner == "\"" then
do break end
else
stop = stop + 1
end
end
out [ # out + 1 ] = compact : sub ( at , stop )
index = stop + 1
elseif char == "{" or char == "[" then


local closing = compact : sub ( index , index )
if closing == "}" or closing == "]" then
out [ # out + 1 ] = char .. closing
index = index + 1
else
depth = depth + 1
out [ # out + 1 ] = char .. "\n" .. string . rep ( "  " , depth )
end
elseif char == "}" or char == "]" then
depth = depth - 1
out [ # out + 1 ] = "\n" .. string . rep ( "  " , depth ) .. char
elseif char == "," then
out [ # out + 1 ] = ",\n" .. string . rep ( "  " , depth )
else
out [ # out + 1 ] = ": "
end
end

return table . concat ( out )
end




function report . encodePretty ( value ) 
return indented ( report . encode ( value ) )
end



function report . write ( value ) 
io . write ( report . encode ( value ) .. "\n" )
end





local function diagnosticRange ( source , e ) 
if type ( e . offset ) == "number" and e . offset >= 1 then
return rangeAt ( source , e . offset , e . length )
end
if type ( e . line ) == "number" and e . line >= 1 then
local column = type ( e . col ) == "number" and e . col >= 1 and e . col or 1
local offset = 0
if source and source . lineStarts [ e . line ] then
offset = source . lineStarts [ e . line ] + column - 1
end
local start = { line = e . line , column = column , offset = offset }
local width = type ( e . length ) == "number" and e . length or 0

return { start = start , [ "end" ] = { line = e . line , column = column + width , offset = offset + width } }
end

return nil
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
message = item . message or item . msg or "related location" ,
range = rangeAt ( read ( relatedFile ) , item . offset , item . length )
}
end
values [ # values + 1 ] = {
file = e . filename ,
severity = diagnosticMod . severityOf ( e ) ,
code = e . code ,
status = e . status ,
hotness = e . hotness ,
hotnessSamples = e . hotnessSamples ,
hotnessRange = e . hotnessRange ,
lint = e . lint ,



docs = explain . anchor ( e . code ) ,
message = e . msg ,
range = diagnosticRange ( source , e ) ,
fixes = fixes ,
help = e . help ,
notes = e . notes or { } ,
related = related ,
}
end

return values
end




function report . fileDiagnostic ( path , msg , help ) 
return { filename = path , code = report . UNREADABLE , msg = msg or "cannot access " .. path , help = help , }
end



report . UNREADABLE = "NUPP0001"

report . MANIFEST = "NUPP0002"
report . UNKNOWN_NAME = "NUPP0003"
report . TOOL_FAILED = "NUPP0004"





function report . runDiagnostic ( code , msg , help , file ) 
local text = tostring ( msg ) : gsub ( "^nupp: " , "" )
return { filename = file , code = code , msg = text , help = help }
end




function report . fileFailure ( path , err , help , collected ) 
local diagnostic = report . fileDiagnostic ( path , err , help )
if collected then
collected [ # collected + 1 ] = diagnostic
else
io . stderr : write ( "nupp: " .. diagnostic . msg .. "\n" )
end

return diagnostic
end





local POSITION = {
type = "object" ,
description = "A 1-based byte position." ,
properties = { line = { type = "integer" } , column = { type = "integer" } , offset = { type = "integer" } , } ,
required = { "line" , "column" , "offset" } ,
}

local RANGE = { type = "object" , properties = { start = POSITION , [ "end" ] = POSITION } , required = { "start" , "end" } , }



report . RANGE = RANGE


report . LOCATION = {
type = "object" ,
properties = { file = { type = "string" } , range = RANGE } ,
required = { "file" , "range" } ,
}

local EDIT = {
type = "object" ,
properties = { file = { type = "string" } , range = RANGE , newText = { type = "string" } , } ,
required = { "file" , "range" , "newText" } ,
}


report . DIAGNOSTIC = {
type = "object" ,
properties = {
file = { type = "string" } ,
severity = { type = "string" , enum = { "error" , "warning" , "note" } } ,
code = {
type = "string" ,
description = "A stable code such as NUPP2004, or OPT-n for an optimizer remark."
} ,
lint = {
type = "string" ,
description = "The lint name, when the diagnostic came from one. This is what an @allow suppression writes."

} ,
docs = {
type = "string" ,
description = "The reference section covering this code, as a path and anchor. 'nupp explain <code>' says more."

} ,
message = { type = "string" } ,
status = { type = "string" , enum = { "fired" , "declined" , "unavailable" } } ,
hotness = { type = "string" , enum = { "unknown" , "sampled" } } ,
hotnessSamples = { type = "integer" } ,
hotnessRange = {
type = "object" ,
properties = { startLine = { type = "integer" } , endLine = { type = "integer" } } ,
required = { "startLine" , "endLine" }
} ,
range = {
type = "object" ,
description = "Where the diagnostic is. Absent for one about something with no place in source, such as a file that could not be read or a manifest that could not be used."

,
properties = { start = POSITION , [ "end" ] = POSITION } ,
required = { "start" , "end" } ,
} ,
help = { type = "string" , description = "A concrete repair direction." } ,
notes = { type = "array" , items = { type = "string" } } ,
related = {
type = "array" ,
items = {
type = "object" ,
properties = { file = { type = "string" } , message = { type = "string" } , range = RANGE } ,
required = { "file" , "message" , "range" } ,
} ,
} ,
fixes = {
type = "array" ,
description = "Machine-applicable repairs. A fix is all-or-nothing: apply every edit in it or none." ,
items = {
type = "object" ,
properties = { title = { type = "string" } , edits = { type = "array" , items = EDIT } } ,
required = { "title" , "edits" } ,
} ,
} ,
} ,
required = { "severity" , "message" , "fixes" , "notes" , "related" } ,
}



report . DIAGNOSTICS = { type = "array" , items = report . DIAGNOSTIC }


report . PARALLEL = {
type = "object" ,
description = "How a cold whole-project check or build used its workers. Absent when they were not considered: a warm run, a run over named files."
,
properties = {
mode = { type = "string" , enum = { "parallel" , "serial" , "serial-fallback" } , } ,
workers = { type = "integer" } ,
retries = { type = "integer" } ,
batches = { type = "integer" } ,
rechecked = {
type = "integer" ,
description = "Worker-produced modules done again in the coordinating process because their records did not validate. Present only in parallel mode."
,
} ,
reason = { type = "string" , description = "Why the run selected or returned to a single process." , } ,
} ,
required = { "mode" , "workers" , "retries" , "batches" } ,
}



report . OK = {
type = "boolean" ,
description = "Whether the command did what it was asked; the same answer as exit status 0. False always comes with at least one error in `diagnostics` that carries a code."

,
}



report . FAILURE = {
type = "object" ,
description = "The command failed; `diagnostics` says why." ,
properties = { ok = { type = "boolean" , enum = { false } } , diagnostics = report . DIAGNOSTICS } ,
required = { "ok" , "diagnostics" } ,
}

local function emptyValue ( schema ) 
local kind = schema and schema . type
if kind == "array" then
return { }
elseif kind == "object" then
local value = { }
for _ , name in ipairs ( schema . required or { } ) do
value [ name ] = emptyValue ( schema . properties and schema . properties [ name ] )
end
return value
elseif kind == "string" then
return ""
elseif kind == "integer" or kind == "number" then
return 0
elseif kind == "boolean" then
return false
end

return json . NULL
end


local function failureShape ( schema ) 
if not schema or not schema . oneOf then
return schema
end
for _ , branch in ipairs ( schema . oneOf ) do
local ok = branch . properties and branch . properties . ok
if ok and ok . enum and # ok . enum == 1 and ok . enum [ 1 ] == false then
return branch
end
end

return schema . oneOf [ 1 ]
end






function report . failure ( schema , diagnostics , fields ) 
local document = fields or { }
document . ok = false
document . diagnostics = report . diagnosticValues ( diagnostics )
local shape = failureShape ( schema )
for _ , name in ipairs ( shape and shape . required or { } ) do
if document [ name ] == nil then
document [ name ] = emptyValue ( shape . properties and shape . properties [ name ] )
end
end
report . write ( document )

return 1
end

local __nuppExportValue= report ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.report"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.report"]=__nuppExports;return __nuppExports