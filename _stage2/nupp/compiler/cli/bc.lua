_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON);



















local spec = require ( "nupp.compiler.cli.spec" )
local optionsMod = require ( "nupp.compiler.cli.options" )


local function bcOptions ( )
local list = optionsMod . format ( )
list [
# list + 1
] = { name = "--check" , key = "check" , help = "Report bytecode a loop cannot compile, and exit non-zero for it" , }
list [
# list + 1
] = {
name = "--prologue" ,
key = "prologue" ,
help = "Include the generated runtime preamble, folded away by default" ,
}

return list
end

local command = spec . command {
name = "bc" ,
summary = "Show the bytecode a Nupp file compiles to" ,
usage = { "nupp bc [--check] [--prologue] [--format text|json] <file>" } ,
options = bcOptions ( ) ,
schema = {
type = "object" ,
description = "The bytecode of one Nupp file, by function." ,
properties = {
file = { type = "string" } ,
functions = {
type = "array" ,
items = {
type = "object" ,
properties = {
what = { type = "string" , enum = { "chunk" , "function" } } ,
firstLine = { type = "integer" } ,
lastLine = { type = "integer" } ,
instructions = {
type = "array" ,
items = {
type = "object" ,
properties = {
pc = { type = "integer" } ,
op = { type = "string" } ,
text = { type = "string" } ,
line = { type = "integer" } ,
inLoop = { type = "boolean" } ,
unrecordable = {
type = "string" ,
description = "Why a loop holding this cannot be "
.. "compiled. Absent when it can." ,
} ,
} ,
required = { "pc" , "op" , "text" } ,
} ,
} ,
} ,
required = { "what" , "instructions" } ,
} ,
} ,
unrecordable = {
type = "integer" ,
description = "How many instructions sit in a loop that therefore never compiles." ,
} ,
} ,
required = { "file" , "functions" , "unrecordable" } ,
} ,
detail = [[Source lines are shown against the instructions they produced. The generated
runtime preamble all lands on line 1 and is folded away unless `--prologue`
asks for it.

`--check` marks every instruction LuaJIT cannot record that sits inside a loop,
and exits 1 when there is one. Building a function is the usual cause: the loop
holding it aborts trace recording and is blacklisted, so it runs interpreted
however hot it gets. Nothing else reports that, because nothing about the
program's answers changes.]] ,
}


local UNRECORDABLE = { FNEW = "builds a function" , UCLO = "closes an upvalue" , }



local BACK_EDGE = {
FORL = true ,
IFORL = true ,
JFORL = true ,
ITERL = true ,
IITERL = true ,
JITERL = true ,
LOOP = true ,
ILOOP = true ,
JLOOP = true ,
}


local function instructionsOf ( util , bc , fn )
local out = { }
local pc = 0
while true do
local raw = util . funcbc ( fn , pc )
if not raw then
return out
end
local text = bc . line ( fn , pc , "" )

local op = text : match ( "^%s*%d+%s+=?>?%s*([A-Z][A-Z0-9]*)" ) or "?"
local located = util . funcinfo ( fn , pc )
out [
# out + 1
] = {
pc = pc ,
op = op ,
text = ( text : gsub ( "\n$" , "" ) ) ,
line = located and located . currentline or nil ,
jump = tonumber ( text : match ( "=> (%d+)" ) ) ,
}
pc = pc + 1
end
end













local function markLoops ( instructions )
for _ , ins in ipairs ( instructions ) do
if BACK_EDGE [ ins . op ] and ins . jump then
for _ , other in ipairs ( instructions ) do
if other . pc >= ins . jump - 1 and other . pc <= ins . pc then
other . inLoop = true
end
end
end
end






for index , ins in ipairs ( instructions ) do
local previous = instructions [ index - 1 ]
local conditional = ins . op == "JMP" and previous ~= nil and previous . op : sub ( 1 , 2 ) == "IS"
if conditional and ins . jump and ins . jump - 1 > ins . pc then
for _ , other in ipairs ( instructions ) do
if other . pc > ins . pc and other . pc < ins . jump - 1 then
other . skippable = true
end
end
end
end
end


local function childrenOf ( util , fn )
local out = { }
local index = 0
while true do
local ok , constant = pcall ( util . funck , fn , - ( index + 1 ) )
if not ok or constant == nil then
return out
end
if type ( constant ) == "proto" or type ( constant ) == "function" then
out [ # out + 1 ] = constant
end
index = index + 1
end
end

local function collect ( util , bc , fn , depth , into , seen )
if seen [ fn ] then
return
end
seen [ fn ] = true
local info = util . funcinfo ( fn )
local instructions = instructionsOf ( util , bc , fn )
markLoops ( instructions )
for _ , ins in ipairs ( instructions ) do
if ins . inLoop and not ins . skippable then
ins . unrecordable = UNRECORDABLE [ ins . op ]
end
end
into [
# into + 1
] = {
what = depth == 0 and "chunk" or "function" ,
depth = depth ,
firstLine = info . linedefined ,
lastLine = info . lastlinedefined ,
instructions = instructions ,
}
for _ , child in ipairs ( childrenOf ( util , fn ) ) do
collect ( util , bc , child , depth + 1 , into , seen )
end
end

local function sourceLines ( text )
local out = { }
for line in ( text .. "\n" ) : gmatch ( "(.-)\n" ) do
out [ # out + 1 ] = line
end

return out
end

local function run ( parsed )
local paths = parsed . positional
if # paths ~= 1 then
return command : usageError ( "exactly one source file is required" )
end
local path = paths [ 1 ]

local ok , util = pcall ( require , "jit.util" )
local okBc , bc = pcall ( require , "jit.bc" )
if not ok or not okBc then
io . stderr : write ( "nupp: bytecode needs LuaJIT's jit.util and jit.bc\n" )
return 1
end

local fs = require ( "nupp.compiler.fs" )
local source , readErr = fs . readFile ( path )
if not source then
io . stderr : write ( "nupp: " .. tostring ( readErr ) .. "\n" )
return 1
end

local compile = require ( "nupp.compiler.cli.compile" )
local env = require ( "nupp.compiler.env" ) . new ( "." )
local code , compileErr = compile . module ( path , env , compile . settings ( parsed . values ) )
if not code then
io . stderr : write ( "nupp: " .. tostring ( compileErr ) .. "\n" )
return 1
end
local chunk , loadErr = loadstring ( code , "@" .. path )
if not chunk then
io . stderr : write ( "nupp: generated code did not load: " .. tostring ( loadErr ) .. "\n" )
return 1
end

local functions = { }
collect ( util , bc , chunk , 0 , functions , { } )

local unrecordable = 0
for _ , fn in ipairs ( functions ) do
for _ , ins in ipairs ( fn . instructions ) do
if ins . unrecordable then
unrecordable = unrecordable + 1
end
end
end

if ( parsed . values . format or "text" ) == "json" then
local json = require ( "cjson" ) . new ( )
json . encode_empty_table_as_object ( false )
io . write ( json . encode ( { file = path , functions = functions , unrecordable = unrecordable } ) .. "\n" )
else
local lines = sourceLines ( source )


local prologue = not parsed . values . prologue
for _ , fn in ipairs ( functions ) do
local indent = ( "  " ) : rep ( fn . depth )
io . write ( ( "%s-- %s, lines %s-%s\n" ) : format ( indent , fn . what , tostring ( fn . firstLine ) , tostring ( fn . lastLine ) ) )
local shown = nil
local folded = 0
for _ , ins in ipairs ( fn . instructions ) do
local isPreamble = prologue and fn . depth == 0 and ( ins . line or 0 ) <= 1
if isPreamble then
folded = folded + 1
else
if folded > 0 then
io . write ( ( "%s     ... %d instructions of runtime preamble\n" ) : format ( indent , folded ) )
folded = 0
end
if ins . line and ins . line ~= shown then
shown = ins . line
local text = lines [ ins . line ]
if text and text : match ( "%S" ) then
io . write ( ( "%s%5d | %s\n" ) : format ( indent , ins . line , text ) )
end
end
io . write ( indent .. "      " .. ins . text )
if ins . unrecordable and parsed . values . check then
io . write ( "   <-- this loop never compiles: " .. ins . unrecordable )
end
io . write ( "\n" )
end
end
if folded > 0 then
io . write ( ( "%s     ... %d instructions of runtime preamble\n" ) : format ( indent , folded ) )
end
io . write ( "\n" )
end
end

if parsed . values . check and unrecordable > 0 then
io . stderr : write (
(
"nupp: %d instruction%s in a loop that cannot compile\n"
) : format ( unrecordable , unrecordable == 1 and "" or "s" )
)
return 1
end

return 0
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
