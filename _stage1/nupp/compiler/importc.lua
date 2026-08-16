_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
















local importc = { }
local cdecl = require ( "nupp.compiler.cdecl" )
local process = require ( "nupp.compiler.build.process" )

local function readFile ( path )
local f = io . open ( path , "rb" )
if not f then
return nil
end
local s = f : read ( "*a" )
f : close ( )

return s
end

local function capture ( argv )
local code , out = process . capture ( argv )
if code ~= 0 then
return nil
end

return out
end

local function normalizedPath ( path )
return ( path : gsub ( "\\" , "/" ) )
end

local function basename ( path )
return normalizedPath ( path ) : match ( "([^/]+)$" ) or path
end





local function targetMarker ( preprocessed , headerPath )
local wanted = normalizedPath ( headerPath )
local fallback = nil
for file in preprocessed : gmatch ( '#%s*%d+%s+"([^"]*)"' ) do
local normalized = normalizedPath ( file )
if normalized == wanted then
return file
end
if not fallback and basename ( normalized ) == basename ( wanted ) then
fallback = file
end
end

return fallback or headerPath
end


local function filterToHeader ( preprocessed , headerPath )
local target = targetMarker ( preprocessed , headerPath )
local keep = { }
local current = ""
for line in ( preprocessed .. "\n" ) : gmatch ( "(.-)\n" ) do
local file = line : match ( '^#%s*%d+%s+"([^"]*)"' )
if file then
current = file
elseif current == target and line : match ( "%S" ) then
keep [ # keep + 1 ] = line
end
end

return table . concat ( keep , "\n" )
end


local function normalize ( text )

while true do
local s2 , changed = text : gsub ( "__attribute__%s*%(%b()%)" , "" )
text = s2
if changed == 0 then
break
end
end
text = text : gsub ( "__asm__%s*%b()" , "" )
text = text : gsub ( "__asm%s*%b()" , "" )
for _ , word in ipairs ( {
"__restrict__" ,
"__restrict" ,
"__extension__" ,
"_Nullable" ,
"_Nonnull" ,
"_Null_unspecified" ,
"__inline__"
} ) do
text = text : gsub ( word , "" )
end

return text
end



local function statements ( text )
local out , buf , depth = { } , { } , 0
for ch in text : gmatch ( "." ) do
if ch == "{" then
depth = depth + 1

elseif ch == "}" then
depth = depth - 1
end
if ch == ";" and depth == 0 then
local stmt = table . concat ( buf ) : gsub ( "%s+" , " " ) : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" )
if # stmt > 0 then
out [ # out + 1 ] = stmt
end
buf = { }
else
buf [ # buf + 1 ] = ch
end
end

return out
end






local function stripLinemarkers ( text )
local out = { }
for line in ( text .. "\n" ) : gmatch ( "(.-)\n" ) do
if not line : match ( "^#" ) then
out [ # out + 1 ] = line
end
end

return table . concat ( out , "\n" )
end









local function collectTypedefs ( stmts )
local defs , seen = { } , { }
for _ , stmt in ipairs ( stmts ) do
if stmt : match ( "^typedef%f[%W]" ) and not stmt : find ( "[{}()]" ) then
local body = stmt : gsub ( "^typedef%s+" , "" )
local base , name = body : match ( "^(.-)%s*%f[%w_]([%a_][%w_]*)$" )
if base and name and base : match ( "%S" ) and not seen [ name ] then
seen [ name ] = true
defs [ # defs + 1 ] = { name = name , base = ( base : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) ) , }
end
end
end

return defs
end

local INTEGER_TYPE = {
[ 8 ] = { "int8" , "uint8" } ,
[ 16 ] = { "int16" , "uint16" } ,
[ 32 ] = { "int32" , "uint32" } ,
[ 64 ] = { "int64" , "uint64" } ,
}

local RESERVED = {
[ "and" ] = true ,
[ "break" ] = true ,
[ "do" ] = true ,
[ "else" ] = true ,
[ "elseif" ] = true ,
[ "end" ] = true ,
[ "false" ] = true ,
[ "for" ] = true ,
[ "function" ] = true ,
[ "goto" ] = true ,
[ "if" ] = true ,
[ "in" ] = true ,
[ "local" ] = true ,
[ "nil" ] = true ,
[ "not" ] = true ,
[ "or" ] = true ,
[ "repeat" ] = true ,
[ "return" ] = true ,
[ "then" ] = true ,
[ "true" ] = true ,
[ "until" ] = true ,
[ "while" ] = true ,
}

local function identifier ( name )
return name and name : match ( "^[%a_][%w_]*$" ) and not RESERVED [ name ]
end

local renderType
local renderFunctionType




renderType = function ( model , knownStructs , callbacks )
local kind = model and model . kind or "unknown"
if kind == "boolean" then
return "boolean"
elseif kind == "float" then
if model . bits == 32 then
return "float"
end
if model . bits == 64 then
return "number"
end
return nil
elseif kind == "integer" or kind == "enum" then
local pair = INTEGER_TYPE [ model . bits ]
if not pair then
return nil
end
return model . unsigned and pair [ 2 ] or pair [ 1 ]
elseif kind == "struct" or kind == "union" then
if model . name and knownStructs [ model . name ] then
return model . name
end
return nil
elseif kind == "pointer" then
local pointee = model . to
if pointee and pointee . kind == "integer" and pointee . bits == 8 and model . const then
return "cstring"
end
if pointee and pointee . kind == "function" then
if callbacks then
return renderFunctionType ( pointee , knownStructs )
end
return nil
end
if pointee and (
pointee . kind == "struct" or pointee . kind == "union"
) and pointee . name and knownStructs [ pointee . name ] then
return pointee . name .. "*"
end
if pointee and (
pointee . kind == "void"
or pointee . kind == "integer"
or pointee . kind == "float"
or pointee . kind == "boolean"
or pointee . kind == "enum"
) then
return "voidptr"
end
return nil
end

return nil
end

renderFunctionType = function ( fn , knownStructs )
local params = { }
for _ , param in ipairs ( fn . params or { } ) do
local rendered = renderType ( param . type , knownStructs , false )
if not rendered then
return nil
end
params [ # params + 1 ] = rendered
end
if fn . vararg then
params [ # params + 1 ] = "..."
end
local out = "function(" .. table . concat ( params , ", " ) .. ")"
if fn . returns and fn . returns . kind ~= "void" then
local ret = renderType ( fn . returns , knownStructs , false )
if not ret then
return nil
end
out = out .. ": " .. ret
end

return out
end


local function headerMacroNames ( rawHeader )
local names = { }
for name , after in rawHeader : gmatch ( "#%s*define%s+([%a_][%w_]*)([^\n]?)" ) do
if after ~= "(" then
names [ # names + 1 ] = name
end
end

return names
end

local function macroValues ( dmOutput )
local values = { }
for name , value in dmOutput : gmatch ( "#define%s+([%a_][%w_]*)%s+([^\n]+)" ) do
values [ name ] = value : gsub ( "\r$" , "" )
end

return values
end



local function constantExpr ( value )
value = value : gsub ( "([%dxXa-fA-F])[uUlL]+%f[%W]" , "%1" )
if value : match ( "^%s*$" ) then
return nil
end
if value : match ( '^"[^"]*"$' ) then
return value , "string"
end
if value : match ( "^[%d%sxXa-fA-F%.%+%-%*/%%%(%)<>|&~]+$" ) and value : match ( "%d" ) then
return value , "number"
end

return nil
end











function importc . import ( headerPath , opts )
opts = opts or { }
local warnings = { }
local raw = readFile ( headerPath )
if not raw then
return nil , { "cannot read " .. headerPath }
end
local headerBase = basename ( headerPath )
local cc = opts . cc or "cc"
local cpp = { cc , "-E" }
for _ , flag in ipairs ( opts . cppflags or { } ) do
cpp [ # cpp + 1 ] = flag
end
cpp [ # cpp + 1 ] = "-xc"
cpp [ # cpp + 1 ] = headerPath
local preprocessed = capture ( cpp )
local macros = { cc , "-E" , "-dM" }
for _ , flag in ipairs ( opts . cppflags or { } ) do
macros [ # macros + 1 ] = flag
end
macros [ # macros + 1 ] = "-xc"
macros [ # macros + 1 ] = headerPath
local dm = capture ( macros ) or ""
if not preprocessed or # preprocessed == 0 then
return nil , { "cc -E produced no output for " .. headerPath }
end

local text = normalize ( filterToHeader ( preprocessed , headerPath ) )









local ownTypedefs = { }
for _ , def in ipairs ( collectTypedefs ( statements ( text ) ) ) do
ownTypedefs [ def . name ] = true
end
local typedefText = { }
for _ , def in ipairs ( collectTypedefs ( statements ( normalize ( stripLinemarkers ( preprocessed ) ) ) ) ) do
if not ownTypedefs [ def . name ] then
typedefText [ # typedefText + 1 ] = ( "typedef %s %s;" ) : format ( def . base , def . name )
end
end









local units = { }
for _ , statement in ipairs ( statements ( text ) ) do
units [ # units + 1 ] = statement .. ";"
end
local parsed , ffiErr = cdecl . inspect ( units , typedefText )
if not parsed then
return nil , { "LuaJIT cdef: " .. tostring ( ffiErr ) }
end

local out = { }
local exports = { }
local knownStructs = { }
local function emit ( line )
out [ # out + 1 ] = line
end

emit ( ( "-- generated by nupp import-c from %s" ) : format ( headerBase ) )
emit ( "-- committed and hand-editable: fix or extend freely, re-import" )
emit ( "-- only when the header changes." )
emit ( "" )





if # parsed . rejected > 0 then
for _ , reject in ipairs ( parsed . rejected ) do
emit ( ( "-- import-c: skipped declaration (%s)" ) : format ( reject . reason ) )
emit ( "--   " .. reject . text : sub ( 1 , 100 ) )
end
emit ( "" )
warnings [
# warnings + 1
] = ( "%d of %d declarations skipped: %s" ) : format ( # parsed . rejected , parsed . declared , parsed . rejected [ 1 ] . reason )
end

for _ , declaration in ipairs ( parsed . structs ) do
local name = declaration . name
local fields = { }
local ok = identifier ( name ) and true or false
if ok then
knownStructs [ name ] = true
end
for _ , field in ipairs ( declaration . fields ) do
local rendered = renderType ( field . type , knownStructs , false )
if not rendered or not identifier ( field . name ) then
ok = false
break
end
fields [
# fields + 1
] = "   " .. field . name .. ": " .. rendered .. ( field . bitWidth and " : " .. tostring ( field . bitWidth ) or "" )
end
if ok then
emit ( "cdef " .. declaration . kind .. " " .. name )
for _ , field in ipairs ( fields ) do
emit ( field )
end
emit ( "end" )
emit ( "" )
exports [ # exports + 1 ] = name
else
knownStructs [ name ] = nil
emit ( "-- import-c: skipped " .. declaration . kind .. " " .. tostring ( name ) .. " (unsupported field type)" )
end
end

for _ , fn in ipairs ( parsed . functions ) do
local params = { }
local ok = identifier ( fn . name ) and true or false
for index , param in ipairs ( fn . params or { } ) do
local rendered = renderType ( param . type , knownStructs , true )
if not rendered then
ok = false
break
end
local name = identifier ( param . name ) and param . name or "arg" .. index
params [ # params + 1 ] = name .. ": " .. rendered
end
if fn . vararg then
params [ # params + 1 ] = "..."
end
local ret
if fn . returns and fn . returns . kind ~= "void" then
ret = renderType ( fn . returns , knownStructs , false )
if not ret then
ok = false
end
end
if ok then
local sig = "cdef function " .. fn . name .. "(" .. table . concat ( params , ", " ) .. ")"
if ret then
sig = sig .. ": " .. ret
end
if opts . lib then
sig = sig .. ( " from %q" ) : format ( opts . lib )
end
emit ( sig )
exports [ # exports + 1 ] = fn . name
else
emit ( "-- import-c: skipped function " .. tostring ( fn . name ) .. " (unsupported C type)" )
end
end


local constLines = { }
local taken = { }
local function constant ( name , typeName , expr )
if not identifier ( name ) or taken [ name ] then
return
end
taken [ name ] = true
constLines [ # constLines + 1 ] = ( "local %s: %s = %s" ) : format ( name , typeName , expr )
exports [ # exports + 1 ] = name
end





for _ , declaration in ipairs ( parsed . enums or { } ) do
for _ , member in ipairs ( declaration . values ) do
constant ( member . name , "int32" , tostring ( member . value ) )
end
end

local values = macroValues ( dm )
for _ , name in ipairs ( headerMacroNames ( raw ) ) do
local value = values [ name ]
if value then
local expr , vtype = constantExpr ( value )
if expr then
constant ( name , vtype == "string" and "string" or "number" , expr )
end
end
end
if # constLines > 0 then
emit ( "" )
for _ , line in ipairs ( constLines ) do
emit ( line )
end
end


emit ( "" )
local pairsOut = { }
for _ , name in ipairs ( exports ) do
pairsOut [ # pairsOut + 1 ] = name .. " = " .. name
end
emit ( "return { " .. table . concat ( pairsOut , ", " ) .. " }" )
emit ( "" )

return table . concat ( out , "\n" ) , warnings
end

return importc
