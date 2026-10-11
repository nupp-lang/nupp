_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT5={}; local function __nuppT2(...) return {n=select("#",...),...} end; local __nuppT6,__nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT3(value) return value end; local function __nuppT4(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT11({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT12(v.primary) for _,reason in __nuppT13(v.suppressed) do text=text.."\ncleanup: "..__nuppT12(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




















local importc = { }
local cdecl = require ( "nupp.compiler.cinterop.cdecl" )
local process = require ( "nupp.compiler.process" )
local hash = require ( "nupp.compiler.hash" )





local function readFile ( path ) 
do const  __nuppT20= io . open ( path , "rb" ) ; local __nuppT21=__nuppT5[1]; if not __nuppT21 then __nuppT21=function(f) do
if not f then
return "return",__nuppT2( nil )
end
local s = f : read ( "*a" )
f : close ( )

return "return",__nuppT2( s ) end; return "normal" end; __nuppT5[1]=__nuppT21 end; const __nuppT15,__nuppT16,__nuppT17=__nuppT7(__nuppT21,__nuppT3,__nuppT20); const __nuppT14=1; local __nuppT18={}; local __nuppT19=0; if __nuppT14>=1 and __nuppT20~=nil then  local __nuppT22,__nuppT23=__nuppT6(__nuppCleanup1,__nuppT20);  if not __nuppT22 then __nuppT19=__nuppT19+1; __nuppT18[__nuppT19]=__nuppT23 end; end; if not __nuppT15 then if __nuppT19>0 then __nuppT8(__nuppT4(__nuppT16,__nuppT18,1),0) else __nuppT8(__nuppT16,0) end end; if __nuppT19>0 then if __nuppT19>1 then __nuppT8(__nuppT4(__nuppT18[1],__nuppT18,2),0) else __nuppT8(__nuppT18[1],0) end end; if __nuppT16=="return" then  return __nuppT9(__nuppT17,1,__nuppT17.n)  end; end
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
return ( ( path : gsub ( "\\" , "/" ) ) ) : match ( "([^/]+)$" ) or path
end





local function targetMarker ( preprocessed , headerPath ) 
local wanted = ( ( headerPath : gsub ( "\\" , "/" ) ) )
local fallback = nil
for file in preprocessed : gmatch ( "#%s*%d+%s+\"([^\"]*)\"" ) do
local normalized = ( ( file : gsub ( "\\" , "/" ) ) )
if normalized == wanted then
return file
end
if not fallback and ( ( ( normalized : gsub ( "\\" , "/" ) ) ) : match ( "([^/]+)$" ) or normalized ) == ( ( ( wanted : gsub ( "\\" , "/" ) ) ) : match ( "([^/]+)$" ) or wanted ) then
fallback = file
end
end

return fallback or headerPath
end




local function filterToHeader ( preprocessed , headerPath ) 
local target = targetMarker ( preprocessed , headerPath )
local keep = { }
local lines = { }
local current = ""
local lineNumber = 0
for line in ( preprocessed .. "\n" ) : gmatch ( "(.-)\n" ) do
local number , file = line : match ( "^#%s*(%d+)%s+\"([^\"]*)\"" )
if file then
current = file
lineNumber = ( ( tonumber ( number ) or 1 ) ) - 1
else
lineNumber = lineNumber + 1
if current == target and line : match ( "%S" ) then
keep [ # keep + 1 ] = line
lines [ # lines + 1 ] = lineNumber
end
end
end

return table . concat ( keep , "\n" ) , lines
end







local LUAJIT_ATTRIBUTES

= {
aligned = true ,
packed = true ,
mode = true ,
vector_size = true ,
regparm = true ,
cdecl = true ,
thiscall = true ,
fastcall = true ,
stdcall = true ,
sseregparm = true ,
}




local REFUSED_ATTRIBUTES

= {
ext_vector_type = true ,
matrix_type = true ,
ms_struct = true ,
gcc_struct = true ,
transparent_union = true ,
ms_abi = true ,
sysv_abi = true ,
vectorcall = true ,
regcall = true ,
pcs = true ,
overloadable = true ,
swiftcall = true ,
swiftasynccall = true ,
preserve_most = true ,
preserve_all = true ,
aarch64_vector_pcs = true ,
aarch64_sve_pcs = true ,
}



local REFUSED_MARKER = "__nupp_refused_attribute_"



local function newlinesOf ( text ) 
return ( text : gsub ( "[^\n]" , "" ) )
end


local function attributeItems ( list ) 
local items = { }
local depth , start = 0 , 1
for index = 1 , # list do
local ch = list : sub ( index , index )
if ch == "(" then
depth = depth + 1
elseif ch == ")" then
depth = depth - 1
elseif ch == "," and depth == 0 then
items [ # items + 1 ] = list : sub ( start , index - 1 )
start = index + 1
end
end
items [ # items + 1 ] = list : sub ( start )

return items
end

local function rewriteAttribute ( whole , parens , keepLayout ) 
local kept = { }
for _ , item in ipairs ( attributeItems ( parens : sub ( 3 , -3 ) ) ) do
local name = item : match ( "^%s*([%a_][%w_]*)" )
if name then
local bare = name : gsub ( "^__" , "" ) : gsub ( "__$" , "" )
if REFUSED_ATTRIBUTES [ bare ] then
return " " .. "__nupp_refused_attribute_" .. bare .. " " .. ( ( whole : gsub ( "[^\n]" , "" ) ) )
end
if keepLayout and LUAJIT_ATTRIBUTES [ bare ] then
kept [ # kept + 1 ] = ( item : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) )
end
end
end
if # kept == 0 then
return " " .. ( ( whole : gsub ( "[^\n]" , "" ) ) )
end

return " __attribute__((" .. table . concat ( kept , ", " ) .. ")) " .. ( ( whole : gsub ( "[^\n]" , "" ) ) )
end




local function normalize ( text , keepLayout ) 
for _ , spelling in ipairs ( { "__attribute__" , "__attribute" } ) do
text = text : gsub ( spelling .. "%s*(%(%b()%))" , function ( parens ) 


if parens : sub ( 1 , 2 ) ~= "((" then
return nil
end
return rewriteAttribute ( spelling .. parens , parens , keepLayout )
end )
end
text = text : gsub ( "__asm__%s*%b()" , newlinesOf )
text = text : gsub ( "__asm%s*%b()" , newlinesOf )
text = text : gsub ( "__inline__" , "inline" ) : gsub ( "__inline" , "inline" )
for _ , word in ipairs ( {
"__restrict__" ,
"__restrict" ,
"__extension__" ,
"_Nullable" ,
"_Nonnull" ,
"_Null_unspecified"
} ) do
text = text : gsub ( word , "" )
end

return text
end











local function applyPack ( directive , stack ) 
local args = directive : match ( "^%s*#%s*pragma%s+pack%s*(%b())" )
if not args then
return stack
end
local parts = { }
for part in args : sub ( 2 , -2 ) : gmatch ( "[^,]+" ) do
parts [ # parts + 1 ] = ( part : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) )
end
local current = stack [ # stack ] or 0
if parts [ 1 ] == "push" then
stack [ # stack + 1 ] = ( tonumber ( parts [ # parts ] ) or current )
elseif parts [ 1 ] == "pop" then
stack [ # stack ] = nil
else

stack [ math . max ( # stack , 1 ) ] = ( tonumber ( parts [ 1 ] ) or 0 )
end

return stack
end









local function statements ( text , lineMap ) 
local out = { }
local buf = { }
local depth = 0
local line = 1
local startLine = nil
local atLineStart = true
local pack = { }
local packed = false
local index = 1
local length = # text

local function reset ( ) 
buf = { }
startLine = nil
packed = false
end

while index <= length do
local ch = text : sub ( index , index )
if atLineStart and ch == "#" then
local eol = text : find ( "\n" , index , true ) or ( length + 1 )
pack = applyPack ( text : sub ( index , eol - 1 ) , pack )
index = eol
else
local discard = false
if ch == "{" then
depth = depth + 1

elseif ch == "}" then
depth = depth - 1
if depth == 0 then
local prefix = table . concat ( buf ) : gsub ( "^%s+" , "" )
local aggregate = prefix : match ( "^typedef%s+struct%f[%W]" )
or prefix : match ( "^typedef%s+union%f[%W]" )
or prefix : match ( "^typedef%s+enum%f[%W]" )
or prefix : match ( "^struct%f[%W]" )
or prefix : match ( "^union%f[%W]" )
or prefix : match ( "^enum%f[%W]" )
if prefix : find ( "%b()" ) and not aggregate then




reset ( )
discard = true
end
end
end
if discard then

elseif ch == ";" and depth == 0 then
local stmt = table . concat ( buf ) : gsub ( "%s+" , " " ) : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" )
if # stmt > 0 then
out [
# out + 1
] = {
text = stmt ,
line = startLine and ( lineMap and lineMap [ startLine ] or startLine ) ,
packed = packed ,
}
end
reset ( )
else
if not ch : match ( "%s" ) then
startLine = startLine or line
local top = pack [ # pack ]
packed = packed or ( top ~= nil and top > 0 )
end
buf [ # buf + 1 ] = ch
end
if ch == "\n" then
line = line + 1
atLineStart = true
elseif not ch : match ( "%s" ) then
atLineStart = false
end
index = index + 1
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
for _ , statement in ipairs ( stmts ) do
local stmt = statement . text
if stmt : match ( "^typedef%f[%W]" ) and not stmt : find ( "[{}()]" ) and not stmt : find ( "__nupp_refused_attribute_" , 1 , true ) then
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



local function aggregateName ( model , knownStructs ) 
return model and ( model . name or ( model . id and knownStructs [ model . id ] or nil ) ) or nil
end







renderType = function ( model , knownStructs ) 
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
return nil , ("a %d-bit float") : format ( model . bits or 0 )
elseif kind == "integer" or kind == "enum" then
local pair = INTEGER_TYPE [ model . bits ]
if not pair then
return nil , ("a %d-bit integer") : format ( model . bits or 0 )
end
return model . unsigned and pair [ 2 ] or pair [ 1 ]
elseif kind == "struct" or kind == "union" then
local name = ( model and ( model . name or ( model . id and knownStructs [ model . id ] or nil ) ) or nil )
if name and knownStructs [ name ] then
return name
end
return nil , ("%s %s is not imported") : format ( kind , tostring ( name or "(anonymous)" ) )
elseif kind == "pointer" then
local pointee = model . to
if pointee and pointee . kind == "integer" and pointee . bits == 8 and model . const then
return "cstring?"
end
if pointee and pointee . kind == "function" then
local rendered , why = renderFunctionType ( pointee , knownStructs )
return rendered and ( rendered .. "?" ) or nil , why
end
local pointeeName = ( pointee and ( pointee . name or ( pointee . id and knownStructs [ pointee . id ] or nil ) ) or nil )
if pointee
and ( pointee . kind == "struct" or pointee . kind == "union" )
and pointeeName
and knownStructs [ pointeeName ]
then
return ( model . const and "const " or "" ) .. pointeeName .. "*?"
end
if pointee and pointee . kind == "void" then
return "voidptr"
end
local rendered , why = renderType ( pointee , knownStructs )
if rendered then
return ( model . const and "const " or "" ) .. rendered .. "*?"
end
return nil , why
elseif kind == "array" then
local element , why = renderType ( model . of , knownStructs )
if not element then
return nil , why
end
if not model . count or model . count < 0 or model . count % 1 ~= 0 then
return nil , "an array with no fixed length"
end
return element .. "[" .. tostring ( model . count ) .. "]"
elseif kind == "vector" then
return nil , "a vector type"
elseif kind == "complex" then
return nil , "a complex type"
end

return nil , "a C type Nupp does not spell"
end

renderFunctionType = function ( fn , knownStructs ) 
local params = { }
for _ , param in ipairs ( fn . params or { } ) do
local rendered , why = renderType ( param . type , knownStructs )
if not rendered then
return nil , why
end
params [ # params + 1 ] = rendered
end
if fn . vararg then
params [ # params + 1 ] = "..."
end
local out = "function(" .. table . concat ( params , ", " ) .. ")"
if fn . returns and fn . returns . kind ~= "void" then
local ret , why = renderType ( fn . returns , knownStructs )
if not ret then
return nil , why
end
out = out .. ": " .. ret
end

return out
end





local function probeDeclarator ( model , name , knownStructs ) 
local kind = model and model . kind or "unknown"
if kind == "integer" or kind == "enum" then
if not INTEGER_TYPE [ model . bits ] then
return nil
end
return ("%sint%d_t %s") : format ( model . unsigned and "u" or "" , model . bits , name )
elseif kind == "boolean" then
return "bool " .. name
elseif kind == "float" then
return ( model . bits == 32 and "float " or "double " ) .. name
elseif kind == "pointer" then
return "void *" .. name
elseif kind == "struct" or kind == "union" then
if model . name then
return kind .. " " .. model . name .. " " .. name
end
local typedef = model . id and knownStructs [ model . id ] or nil
return typedef and ( typedef .. " " .. name ) or nil
elseif kind == "array" and model . count then
return probeDeclarator ( model . of , name .. "[" .. tostring ( model . count ) .. "]" , knownStructs )
end

return nil
end





local function layoutProblem ( declaration , knownStructs ) 
local body = { }
for _ , field in ipairs ( declaration . fields ) do
local member = probeDeclarator ( field . type , field . name , knownStructs )
if not member then
return ("member %s has no C spelling") : format ( field . name )
end
body [ # body + 1 ] = member .. ( field . bitWidth and ( " : " .. tostring ( field . bitWidth ) ) or "" ) .. ";"
end
local rendered , err = cdecl . layout ( declaration . kind , table . concat ( body , " " ) )
if not rendered then
return "the rendered members do not parse: " .. tostring ( err )
end
if rendered . size ~= declaration . size then
return ("it is %s bytes in C and %s as rendered") : format ( tostring ( declaration . size ) , tostring ( rendered . size ) )
end
if rendered . align ~= declaration . align then
return ("it is aligned to %s bytes in C and %s as rendered")

: format ( tostring ( declaration . align ) , tostring ( rendered . align ) )
end
for index , field in ipairs ( declaration . fields ) do
local other = rendered . fields [ index ]
if not other
or other . offset ~= field . offset
or other . bitPos ~= field . bitPos
or other . bitWidth ~= field . bitWidth
then
return ("member %s is at offset %s in C and %s as rendered")

: format ( field . name , tostring ( field . offset ) , tostring ( other and other . offset ) )
end
end

return nil
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
for line in ( dmOutput .. "\n" ) : gmatch ( "([^\n]*)\n" ) do
local name , rest = line : gsub ( "\13$" , "" ) : match ( "^%s*#%s*define%s+([%a_][%w_]*)(.*)$" )
if name and rest : sub ( 1 , 1 ) ~= "(" then
values [ name ] = ( rest : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) )
end
end

return values
end









local EXACT = 2 ^ 53












local TWO_CHAR_OPERATORS

= {
[ "<<" ] = true ,
[ ">>" ] = true ,
[ "<=" ] = true ,
[ ">=" ] = true ,
[ "==" ] = true ,
[ "!=" ] = true ,
[ "&&" ] = true ,
[ "||" ] = true ,
}
local ONE_CHAR_OPERATORS = "+-*/%&|^~!<>?:()"






local function cTokens ( text ) 
local tokens = { }
local index = 1
local length = # text
while index <= length do
local ch = text : sub ( index , index )
if ch : match ( "%s" ) then
index = index + 1
elseif ch : match ( "%d" ) or ( ch == "." and text : sub ( index + 1 , index + 1 ) : match ( "%d" ) ) then
local stop = index
while stop <= length do
local d = text : sub ( stop , stop )
if d : match ( "[eEpP]" ) and text : sub ( stop + 1 , stop + 1 ) : match ( "[%+%-]" ) then
stop = stop + 2
elseif d : match ( "[%w_%.]" ) then
stop = stop + 1
else
do break end
end
end
tokens [ # tokens + 1 ] = { kind = "number" , text = text : sub ( index , stop - 1 ) }
index = stop
elseif ch : match ( "[%a_]" ) then
local word = text : match ( "^[%a_][%w_]*" , index )
if text : sub ( index + # word , index + # word ) : match ( "['\"]" ) then
return nil , "a wide or Unicode literal"
end
tokens [ # tokens + 1 ] = { kind = "name" , text = word }
index = index + # word
elseif ch == "'" or ch == "\"" then
local stop = index + 1
while stop <= length and text : sub ( stop , stop ) ~= ch do
if text : sub ( stop , stop ) == "\\" then
stop = stop + 1
end
stop = stop + 1
end
if stop > length then
return nil , "an unterminated literal"
end
tokens [ # tokens + 1 ] = { kind = ch == "'" and "char" or "string" , text = text : sub ( index + 1 , stop - 1 ) }
index = stop + 1
elseif TWO_CHAR_OPERATORS [ text : sub ( index , index + 1 ) ] then
tokens [ # tokens + 1 ] = { kind = "op" , text = text : sub ( index , index + 1 ) }
index = index + 2
elseif ("+-*/%&|^~!<>?:()") : find ( ch , 1 , true ) then
tokens [ # tokens + 1 ] = { kind = "op" , text = ch }
index = index + 1
else
return nil , ("%q is not part of a constant expression") : format ( ch )
end
end

return tokens
end

local SIMPLE_ESCAPES

= { n = 10 , t = 9 , r = 13 , a = 7 , b = 8 , f = 12 , v = 11 , [ "\\" ] = 92 , [ "'" ] = 39 , [ "\"" ] = 34 , [ "?" ] = 63 , }



local function literalBytes ( body ) 
local bytes = { }
local index = 1
while index <= # body do
local ch = body : sub ( index , index )
if ch ~= "\\" then
bytes [ # bytes + 1 ] = ch : byte ( )
index = index + 1
else
local escape = body : sub ( index + 1 , index + 1 )
local simple = SIMPLE_ESCAPES [ escape ]
if simple then
bytes [ # bytes + 1 ] = simple
index = index + 2
elseif escape : match ( "[0-7]" ) then
local digits = body : match ( "^[0-7][0-7]?[0-7]?" , index + 1 )
local value = tonumber ( digits , 8 )
if value > 255 then
return nil , "an escape wider than a byte"
end
bytes [ # bytes + 1 ] = value
index = index + 1 + # digits
elseif escape == "x" then
local digits = body : match ( "^%x+" , index + 2 )
local value = digits and tonumber ( digits , 16 ) or nil
if not digits or not value or value > 255 then
return nil , "an escape wider than a byte"
end
bytes [ # bytes + 1 ] = value
index = index + 2 + # digits
else
return nil , "an escape Nupp does not read"
end
end
end

return bytes
end


local longBits = nil

local function integerType ( rank , unsigned ) 
if not longBits then
longBits = ( ( cdecl . sizeof ( "long" ) or 8 ) * 8 )
end
local bits = rank == 1 and 32 or rank == 2 and longBits or 64

return { kind = "int" , bits = bits , unsigned = unsigned , rank = rank }
end

local function integerValue ( value , t ) 
return { kind = "int" , value = value , bits = t . bits , unsigned = t . unsigned , rank = t . rank }
end


local function integerLiteral ( text ) 
local digits , suffix , base = text : match ( "^0[xX](%x+)([uUlL]*)$" )
base = 16
if not digits then
digits , suffix = text : match ( "^0[bB]([01]+)([uUlL]*)$" )
base = 2
end
if not digits then
digits , suffix = text : match ( "^(0[0-7]*)([uUlL]*)$" )
base = 8
end
if not digits then
digits , suffix = text : match ( "^([1-9]%d*)([uUlL]*)$" )
base = 10
end
if not digits or not suffix then
return nil
end



local value = 0
for index = 1 , # digits do
value = value * base + ( tonumber ( digits : sub ( index , index ) , 16 ) )
if value > EXACT then
return nil , text .. " is too large to hold exactly"
end
end
local lower = suffix : lower ( )
local unsigned = lower : find ( "u" , 1 , true ) ~= nil
local _ , longs = lower : gsub ( "l" , "" )
if # lower > 3 or longs > 2 then
return nil
end
for rank = longs + 1 , 3 do
local signed = integerType ( rank , false )
if not unsigned and value <= 2 ^ ( ( signed . bits ) - 1 ) - 1 then
return ( { kind = "int" , value = value , bits = signed . bits , unsigned = signed . unsigned , rank = signed . rank } )
end
local unsignedType = integerType ( rank , true )
if ( unsigned or base ~= 10 ) and value <= 2 ^ ( unsignedType . bits ) - 1 then
return ( { kind = "int" , value = value , bits = unsignedType . bits , unsigned = unsignedType . unsigned , rank = unsignedType . rank } )
end
end

return nil , text .. " has no C integer type"
end

local function numberLiteral ( text ) 
local integer , why = integerLiteral ( text )
if integer or why then
return integer , why
end
local hex = text : match ( "^0[xX]" ) ~= nil
local body , suffix = text : match ( "^(.-)([fFlL]?)$" )
local isFloat = body ~= nil
and ( body : find ( "." , 1 , true ) or ( not hex and body : find ( "[eE]" ) ) or ( hex and body : find ( "[pP]" ) ) )
local value = isFloat and tonumber ( body ) or nil
if not value then
return nil , text .. " is not a C number"
end
local single = suffix == "f" or suffix == "F"

return { kind = "float" , value = single and cdecl . float32 ( value ) or value , single = single }
end



local function convertInteger ( value , t ) 
local width = 2 ^ ( t . bits )
local converted = value % width
if not t . unsigned and converted >= width / 2 then
converted = converted - width
end
if math . abs ( converted ) > EXACT then
return nil , "the value is too large to hold exactly"
end

return converted
end


local function commonType ( a , b ) 
if a . unsigned == b . unsigned then
return ( a . rank ) >= ( b . rank ) and a or b
end
local u = a . unsigned and a or b
local s = a . unsigned and b or a
if ( u . rank ) >= ( s . rank ) then
return u
end
if ( s . bits ) > ( u . bits ) then
return s
end

return integerType ( s . rank , true )
end



local function fitted ( value , t ) 
if math . abs ( value ) > EXACT * 2 then
return nil , "the value is too large to hold exactly"
end
if t . unsigned then
local converted , why = convertInteger ( value , t )
if not converted then
return nil , why
end
return ( { kind = "int" , value = converted , bits = t . bits , unsigned = t . unsigned , rank = t . rank } )
end
local half = 2 ^ ( ( t . bits ) - 1 )
if value < - half or value > half - 1 then
return nil , "the expression overflows its C type"
end
if math . abs ( value ) > EXACT then
return nil , "the value is too large to hold exactly"
end

return ( { kind = "int" , value = value , bits = t . bits , unsigned = t . unsigned , rank = t . rank } )
end

local bit = require ( "bit" )






local WORD = 2 ^ 32

local function halves ( value ) 
return math . floor ( value / WORD ) % WORD , value % WORD
end

local function joined ( high , low , t ) 
high , low = high % WORD , low % WORD
local value
if t . bits == 32 then
value = ( not t . unsigned and low >= WORD / 2 ) and low - WORD or low
else
value = ( not t . unsigned and high >= WORD / 2 ) and ( high - WORD ) * WORD + low or high * WORD + low
end
if math . abs ( value ) > EXACT then
return nil , "the value is too large to hold exactly"
end

return ( { kind = "int" , value = value , bits = t . bits , unsigned = t . unsigned , rank = t . rank } )
end



local INT = 1

local function truth ( v ) 
return ( v . value ) ~= 0
end

local function boolValue ( yes ) 
return integerValue ( yes and 1 or 0 , integerType ( 1 , false ) )
end

local function arithmetic ( op , a , b ) 
if a . kind == "string" or b . kind == "string" then
return nil , "a string is not an arithmetic operand"
end
if op == "&&" then
return boolValue ( ( ( a . value ) ~= 0 ) and ( ( b . value ) ~= 0 ) )
elseif op == "||" then
return boolValue ( ( ( a . value ) ~= 0 ) or ( ( b . value ) ~= 0 ) )
end
if a . kind == "float" or b . kind == "float" then
local x , y = a . value , b . value
local single = ( a . kind ~= "float" or a . single == true ) and ( b . kind ~= "float" or b . single == true )
local r
if op == "+" then
r = x + y
elseif op == "-" then
r = x - y
elseif op == "*" then
r = x * y
elseif op == "/" then
r = x / y
elseif op == "<" then
return ( integerValue ( ( x < y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == ">" then
return ( integerValue ( ( x > y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == "<=" then
return ( integerValue ( ( x <= y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == ">=" then
return ( integerValue ( ( x >= y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == "==" then
return ( integerValue ( ( x == y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == "!=" then
return ( integerValue ( ( x ~= y ) and 1 or 0 , integerType ( 1 , false ) ) )
else
return nil , "`" .. op .. "` needs integer operands"
end
return { kind = "float" , value = single and cdecl . float32 ( r ) or r , single = single }
end


if op == "<<" or op == ">>" then
local count = b . value
if count < 0 or count >= ( a . bits ) then
return nil , "a shift by " .. tostring ( count ) .. " is undefined"
end
local x = a . value
if op == ">>" then
return integerValue ( math . floor ( x / 2 ^ count ) , a )
elseif not a . unsigned and x < 0 then
return nil , "shifting a negative value left is undefined"
elseif not a . unsigned then
return fitted ( x * 2 ^ count , a )
else
return fitted ( ( x * 2 ^ count ) % 2 ^ ( a . bits ) , a )
end
end

local t = commonType ( a , b )
local x , whyX = convertInteger ( a . value , t )
local y , whyY = convertInteger ( b . value , t )
if not x or not y then
return nil , whyX or whyY
end
if op == "+" then
return fitted ( x + y , t )
elseif op == "-" then
return fitted ( x - y , t )
elseif op == "*" then
return fitted ( x * y , t )
elseif op == "/" or op == "%" then
if y == 0 then
return nil , "the expression divides by zero"
end
local ux , uy = math . abs ( x ) , math . abs ( y )
local q = math . floor ( ux / uy )
local r = ux - q * uy
if r < 0 then
q , r = q - 1 , r + uy
elseif r >= uy then
q , r = q + 1 , r - uy
end
local result = op == "/" and ( ( ( x < 0 ) ~= ( y < 0 ) ) and - q or q ) or ( x < 0 and - r or r )
return fitted ( result , t )
elseif op == "&" or op == "|" or op == "^" then
local xh , xl = halves ( x )
local yh , yl = halves ( y )
local f = op == "&" and bit . band or op == "|" and bit . bor or bit . bxor
return joined ( f ( xh , yh ) , f ( xl , yl ) , t )
elseif op == "<" then
return ( integerValue ( ( x < y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == ">" then
return ( integerValue ( ( x > y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == "<=" then
return ( integerValue ( ( x <= y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == ">=" then
return ( integerValue ( ( x >= y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == "==" then
return ( integerValue ( ( x == y ) and 1 or 0 , integerType ( 1 , false ) ) )
elseif op == "!=" then
return ( integerValue ( ( x ~= y ) and 1 or 0 , integerType ( 1 , false ) ) )
end

return nil , "`" .. op .. "` is not a constant operator"
end



local function castType ( spelling ) 
local pointerBits = ( ( cdecl . sizeof ( "void *" ) or 8 ) * 8 )
local pointerRank = pointerBits == 32 and 1 or ( longBits == 64 and 2 or 3 )
local narrow = {
[ "signed char" ] = { 8 , false } ,
[ "unsigned char" ] = { 8 , true } ,
[ "short" ] = { 16 , false } ,
[ "short int" ] = { 16 , false } ,
[ "signed short" ] = { 16 , false } ,
[ "unsigned short" ] = { 16 , true } ,
[ "unsigned short int" ] = { 16 , true } ,
int8_t = { 8 , false } ,
uint8_t = { 8 , true } ,
int16_t = { 16 , false } ,
uint16_t = { 16 , true } ,
}
local hit = narrow [ spelling ]
if hit then
return { kind = "int" , bits = hit [ 1 ] , unsigned = hit [ 2 ] , rank = 0 }
end
local ranked = {
[ "int" ] = { 1 , false } ,
[ "signed" ] = { 1 , false } ,
[ "signed int" ] = { 1 , false } ,
[ "unsigned" ] = { 1 , true } ,
[ "unsigned int" ] = { 1 , true } ,
int32_t = { 1 , false } ,
uint32_t = { 1 , true } ,
[ "long" ] = { 2 , false } ,
[ "long int" ] = { 2 , false } ,
[ "signed long" ] = { 2 , false } ,
[ "unsigned long" ] = { 2 , true } ,
[ "unsigned long int" ] = { 2 , true } ,
[ "long long" ] = { 3 , false } ,
[ "long long int" ] = { 3 , false } ,
[ "signed long long" ] = { 3 , false } ,
[ "unsigned long long" ] = { 3 , true } ,
[ "unsigned long long int" ] = { 3 , true } ,
int64_t = { longBits == 64 and 2 or 3 , false } ,
uint64_t = { longBits == 64 and 2 or 3 , true } ,
size_t = { pointerRank , true } ,
uintptr_t = { pointerRank , true } ,
intptr_t = { pointerRank , false } ,
ptrdiff_t = { pointerRank , false } ,
}
local rank = ranked [ spelling ]
if rank then
return integerType ( rank [ 1 ] , rank [ 2 ] )
end
if spelling == "float" or spelling == "double" then
return { kind = "float" , single = spelling == "float" }
end

return nil
end

local function cast ( t , v ) 
if v . kind == "string" then
return nil , "a string cannot be cast to a number"
end
if t . kind == "float" then
local value = v . value
return { kind = "float" , value = t . single and cdecl . float32 ( value ) or value , single = t . single }
end
local value = v . value
if v . kind == "float" then
if value ~= value or value == math . huge or value == - math . huge then
return nil , "the value is not finite"
end
value = value < 0 and math . ceil ( value ) or math . floor ( value )
end
local converted , why = convertInteger ( value , t )
if not converted then
return nil , why
end
if ( t . rank ) < 1 then

return integerValue ( converted , integerType ( 1 , false ) )
end

return ( { kind = "int" , value = converted , bits = t . bits , unsigned = t . unsigned , rank = t . rank } )
end


local BINARY_PRECEDENCE

= {
[ "||" ] = 1 ,
[ "&&" ] = 2 ,
[ "|" ] = 3 ,
[ "^" ] = 4 ,
[ "&" ] = 5 ,
[ "==" ] = 6 ,
[ "!=" ] = 6 ,
[ "<" ] = 7 ,
[ ">" ] = 7 ,
[ "<=" ] = 7 ,
[ ">=" ] = 7 ,
[ "<<" ] = 8 ,
[ ">>" ] = 8 ,
[ "+" ] = 9 ,
[ "-" ] = 9 ,
[ "*" ] = 10 ,
[ "/" ] = 10 ,
[ "%" ] = 10 ,
}

local function evaluateTokens ( tokens ) 
local position = 1

local function peek ( ) 
return tokens [ position ]
end

local expression

local function castAhead ( ) 
local words = { }
local index = position + 1
while tokens [ index ] and tokens [ index ] . kind == "name" do
words [ # words + 1 ] = tokens [ index ] . text
index = index + 1
end
if # words > 0 and tokens [ index ] and tokens [ index ] . text == ")" then
local t = castType ( table . concat ( words , " " ) )
if t then
return t , index + 1
end
end

return nil , nil
end

local function unary ( ) 
local upcoming = peek ( )
if not upcoming then
return nil , "the expression ends early"
end
local token = upcoming
if token . kind == "op"
and ( token . text == "-" or token . text == "+" or token . text == "~" or token . text == "!" )
then
position = position + 1
local operand , why = unary ( )
if not operand then
return nil , why
end
if operand . kind == "string" then
return nil , "a string is not an arithmetic operand"
end
if token . text == "!" then
return boolValue ( not ( ( operand . value ) ~= 0 ) )
elseif token . text == "+" then
return operand
elseif token . text == "-" and operand . kind == "float" then
return { kind = "float" , value = - ( operand . value ) , single = operand . single }
elseif token . text == "-" then
return fitted ( - ( operand . value ) , operand )
elseif operand . kind == "float" then
return nil , "`~` needs an integer operand"
else
local high , low = halves ( operand . value )
return joined ( bit . bnot ( high ) , bit . bnot ( low ) , operand )
end
end
if token . kind == "op" and token . text == "(" then
local t , after = castAhead ( )
if t and after then
position = after
local operand , why = unary ( )
if not operand then
return nil , why
end
return cast ( t , operand )
end
position = position + 1
local inner , why = expression ( 0 )
if not inner then
return nil , why
end
local close = peek ( )
if not close or close . text ~= ")" then
return nil , "an unbalanced parenthesis"
end
position = position + 1
return inner
end
position = position + 1
if token . kind == "number" then
return numberLiteral ( token . text )
elseif token . kind == "char" then
local bytes , why = literalBytes ( token . text )
if not bytes or # bytes ~= 1 then
return nil , why or "a character constant holds one byte"
end

if bytes [ 1 ] > 127 then
return nil , "a character constant outside ASCII"
end
return integerValue ( bytes [ 1 ] , integerType ( 1 , false ) )
elseif token . kind == "string" then
local parts = { }
local current = token
while current and current . kind == "string" do
local bytes , why = literalBytes ( current . text )
if not bytes then
return nil , why
end
for _ , byte in ipairs ( bytes ) do
parts [ # parts + 1 ] = string . char ( byte )
end
current = peek ( )
if current and current . kind == "string" then
position = position + 1
end
end
return { kind = "string" , text = table . concat ( parts ) }
elseif token . kind == "name" then
return nil , "names " .. token . text .. ", which is not a constant"
end

return nil , "`" .. token . text .. "` cannot start an expression"
end

expression = function ( minimum ) 
local first , why = unary ( )
if not first then
return nil , why
end
local left = first
while true do
local token = peek ( )
if not token or token . kind ~= "op" then
do break end
end
if token . text == "?" and minimum == 0 then
position = position + 1
local yes , whyYes = expression ( 0 )
if not yes then
return nil , whyYes
end
local colon = peek ( )
if not colon or colon . text ~= ":" then
return nil , "a conditional without `:`"
end
position = position + 1
local no , whyNo = expression ( 0 )
if not no then
return nil , whyNo
end
if left . kind == "string" then
return nil , "a string is not a condition"
end
local chosen = ( ( left . value ) ~= 0 ) and yes or no
if yes . kind == "int" and no . kind == "int" then
local t = commonType ( yes , no )
local converted , whyConvert = convertInteger ( chosen . value , t )
if not converted then
return nil , whyConvert
end
return ( { kind = "int" , value = converted , bits = t . bits , unsigned = t . unsigned , rank = t . rank } )
end
return chosen
end
local precedence = BINARY_PRECEDENCE [ token . text ]
if not precedence or precedence <= minimum then
do break end
end
position = position + 1
local right , whyRight = expression ( precedence )
if not right then
return nil , whyRight
end
local combined , whyCombined = arithmetic ( token . text , left , right )
if not combined then
return nil , whyCombined
end
left = combined
end

return left
end

local value , why = expression ( 0 )
if not value then
return nil , why
end
if position <= # tokens then
return nil , "`" .. tokens [ position ] . text .. "` is not part of a constant expression"
end

return value
end




local function expandMacros (
tokens ,
values ,
active
) 
local out = { }
for _ , token in ipairs ( tokens ) do
local body = token . kind == "name" and not active [ token . text ] and values [ token . text ] or nil
if body then
local inner , why = cTokens ( body )
if not inner then
return nil , why
end
active [ token . text ] = true
local expanded , whyExpanded = expandMacros ( inner , values , active )
active [ token . text ] = nil
if not expanded then
return nil , whyExpanded
end
for _ , one in ipairs ( expanded ) do
out [ # out + 1 ] = one
end
else
out [ # out + 1 ] = token
end
end

return out
end



local function luaString ( bytes ) 
return "\"" .. bytes : gsub ( "[%c\"\\€-ÿ]" , function ( ch ) 
return ("\\%03d") : format ( ch : byte ( ) )
end ) .. "\""
end


local function numberText ( value ) 
if value == 0 then
return "0"
end
if value % 1 == 0 and math . abs ( value ) <= EXACT then
return ("%.0f") : format ( value )
end
for digits = 15 , 17 do
local text = ( "%." .. tostring ( digits ) .. "g" ) : format ( value )
if tonumber ( text ) == value then
return text
end
end

return ("%.17g") : format ( value )
end


local function macroConstant ( value , values , name ) 
local tokens , why = cTokens ( value )
if not tokens then
return nil , why
end
local expanded , whyExpanded = expandMacros ( tokens , values , { [ name ] = true } )
if not expanded then
return nil , whyExpanded
end
local result , whyResult = evaluateTokens ( expanded )
if not result then
return nil , whyResult
end
if result . kind == "string" then
return luaString ( result . text ) , "string"
end
local number = result . value
if number ~= number or number == math . huge or number == - math . huge then
return nil , "the value is not finite"
end

return numberText ( number ) , "number"
end

local function balancedEnd ( text , startAt , open , close ) 
local depth = 0
for index = startAt , # text do
local ch = text : sub ( index , index )
if ch == open then
depth = depth + 1
elseif ch == close then
depth = depth - 1
if depth == 0 then
return index
end
end
end

return nil
end















local function staticInlineSignatures ( text ) 
local scan = text : gsub ( "__attribute_?_?%s*%b()" , function ( attribute ) 
return ( attribute : gsub ( "[^\n]" , " " ) )
end )
local found = { }
local cursor = 1
while true do
local startAt , after , name = scan : find ( "%f[%w_]static%s+inline%s+.-%f[%w_]([%a_][%w_]*)%s*%(" , cursor )
if not startAt then
do break end
end
local open = scan : find ( "(" , ( after ) - 1 , true )
local close = open and balancedEnd ( scan , open , "(" , ")" ) or nil
local body = close and scan : find ( "%S" , close + 1 ) or nil
if body and scan : sub ( body , body ) == "{" then
local signature = text : sub ( startAt , close ) : gsub ( "^static%s+inline%s+" , "" ) : gsub ( "%s+" , " " )
local bodyEnd = balancedEnd ( scan , body , "{" , "}" )
found [ # found + 1 ] = { name = name , signature = signature , startAt = startAt , endAt = bodyEnd or close }
cursor = ( bodyEnd or close ) + 1
else
cursor = ( close or after ) + 1
end
end

return found
end

local function withoutStaticInlineDefinitions ( text ) 
local definitions = staticInlineSignatures ( text )
local out = { }
local cursor = 1
for _ , definition in ipairs ( definitions ) do
out [ # out + 1 ] = text : sub ( cursor , definition . startAt - 1 )
out [ # out + 1 ] = newlinesOf ( text : sub ( definition . startAt , definition . endAt ) )
cursor = definition . endAt + 1
end
out [ # out + 1 ] = text : sub ( cursor )

return table . concat ( out )
end

local RECIPE_C_TYPE = {
boolean = "_Bool" ,
float = "float" ,
number = "double" ,
integer = "int32_t" ,
int8 = "int8_t" ,
int16 = "int16_t" ,
int32 = "int32_t" ,
int64 = "int64_t" ,
uint8 = "uint8_t" ,
uint16 = "uint16_t" ,
uint32 = "uint32_t" ,
uint64 = "uint64_t" ,
}

local function recipeCType ( spec ) 
if type ( spec ) ~= "string" then
return nil
end
spec = spec : gsub ( "%?" , "" ) : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" )

return RECIPE_C_TYPE [ spec ]
end

local function functionMacroArities ( raw ) 
local out = { }

for name , params in raw : gmatch ( "#%s*define%s+([%a_][%w_]*)(%b())" ) do
local body = params : sub ( 2 , -2 )
local count = body : match ( "^%s*$" ) and 0 or 1
for _ in body : gmatch ( "," ) do
count = count + 1
end
out [ name ] = body : find ( "%.%.%." , 1 , false ) and -1 or count
end

return out
end

local function cString ( value ) 
return "\"" .. value : gsub ( "\\" , "\\\\" ) : gsub ( "\"" , "\\\"" ) .. "\""
end




local function ownedPointer ( rendered ) 
return rendered : sub ( -1 ) == "?" and rendered : sub ( 1 , -2 ) or rendered
end





















































function importc . import ( headerPath , opts ) 
local warnings = { }
local raw = readFile ( headerPath )
if not raw then
return nil , { "cannot read " .. headerPath }
end
local headerBase = ( ( ( headerPath : gsub ( "\\" , "/" ) ) ) : match ( "([^/]+)$" ) or headerPath )
local ownership = opts . ownership or { }
local returnedOwned = ownership . returns or { }
local takenParameters = ownership . takes or { }
local cleanupTerminals = { }
for _ , cleanup in pairs ( returnedOwned ) do
cleanupTerminals [ cleanup ] = true
end
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



local filtered , lineMap = filterToHeader ( preprocessed , headerPath )
local targetText = normalize ( filtered , true )
local text = withoutStaticInlineDefinitions ( targetText )
local targetStatements = statements ( text , lineMap )









local ownTypedefs = { }
for _ , def in ipairs ( collectTypedefs ( targetStatements ) ) do
ownTypedefs [ def . name ] = true
end
local typedefText = { }
for _ , def in ipairs ( collectTypedefs ( statements ( normalize ( stripLinemarkers ( preprocessed ) , true ) ) ) ) do
if not ownTypedefs [ def . name ] then
typedefText [ # typedefText + 1 ] = ("typedef %s %s;") : format ( def . base , def . name )
end
end












local units = { }
local unitStatements = { }
local refusedStatements = { }
for _ , statement in ipairs ( targetStatements ) do
if statement . text : find ( "__nupp_refused_attribute_" , 1 , true ) then
refusedStatements [ # refusedStatements + 1 ] = statement
else
units [ # units + 1 ] = statement . text .. ";"
unitStatements [ # units ] = statement
end
end
local parsed , ffiErr = cdecl . inspect ( units , typedefText )
if not parsed then
return nil , { "LuaJIT cdef: " .. tostring ( ffiErr ) }
end

local function lineOf ( unit ) 
local statement = unit and unitStatements [ unit ] or nil
return statement and statement . line or nil
end


local function where ( line ) 
return line and ( headerBase .. ":" .. tostring ( line ) .. ": " ) or ""
end


local function at ( line ) 
return line and ( " at " .. headerBase .. ":" .. tostring ( line ) ) or ""
end

local out = { }
local exports = { }
local knownStructs = { }
local details = { direct = 0 , bridged = 0 , skipped = # parsed . rejected + # refusedStatements , dispositions = { } , }
for _ , reject in ipairs ( parsed . rejected ) do
details . dispositions [
# details . dispositions + 1
] = { kind = "skipped" , reason = "parse-failure" , detail = reject . reason , line = lineOf ( reject . unit ) , }
end

local function emit ( line ) 
out [ # out + 1 ] = line
end

emit ( ("-- generated by nupp import-c from %s") : format ( headerBase ) )
emit ( "-- committed and hand-editable: fix or extend freely, re-import" )
emit ( "-- only when the header changes." )
emit ( "" )
emit ( "module " .. opts . module )
emit ( "" )





local rejectedTotal = # parsed . rejected + # refusedStatements
if rejectedTotal > 0 then
for _ , statement in ipairs ( refusedStatements ) do
local attribute = statement . text : match ( "__nupp_refused_attribute_([%w_]+)" ) or "?"
local reason = ("the %s attribute changes it in a way LuaJIT would not see") : format ( attribute )
emit ( ("-- import-c: skipped declaration%s (unsupported-attribute: %s)") : format ( at ( statement . line ) , reason ) )
emit ( "--   " .. statement . text : gsub ( "__nupp_refused_attribute_" , "__attribute__ " ) : sub ( 1 , 100 ) )
details . dispositions [
# details . dispositions + 1
] = { kind = "skipped" , reason = "unsupported-attribute" , detail = reason , line = statement . line , }
warnings [ # warnings + 1 ] = where ( statement . line ) .. "skipped a declaration: " .. reason
end
for _ , reject in ipairs ( parsed . rejected ) do
emit ( ("-- import-c: skipped declaration%s (%s)") : format ( at ( lineOf ( reject . unit ) ) , reject . reason ) )
emit ( "--   " .. reject . text : sub ( 1 , 100 ) )
end
emit ( "" )
local first = parsed . rejected [ 1 ] and parsed . rejected [ 1 ] . reason or "an unsupported attribute"
warnings [
# warnings + 1
] = ("%d of %d declarations skipped: %s") : format ( rejectedTotal , parsed . declared + # refusedStatements , first )
end




local function skip ( kind , name , reason , detail , line , warn ) 
emit (
("-- import-c: skipped %s %s%s (%s%s)")

: format ( kind , tostring ( name ) , at ( line ) , reason , detail and ( ": " .. detail ) or "" )
)
details . skipped = details . skipped + 1
details . dispositions [
# details . dispositions + 1
] = { name = name , kind = "skipped" , reason = reason , detail = detail , line = line , }
if warn then
warnings [
# warnings + 1
] = ("%sskipped %s %s: %s") : format ( where ( line ) , kind , tostring ( name ) , detail or reason )
end
end




for _ , declaration in ipairs ( parsed . structs ) do
local name = declaration . name
local line = lineOf ( declaration . unit )
local unitStatement = declaration . unit and unitStatements [ declaration . unit ] or nil
local fields = { }
local reason , detail , warn = nil , nil , false
if not ( name and name : match ( "^[%a_][%w_]*$" ) and not RESERVED [ name ] ) then
reason , detail = "reserved-name" , "its name is not a Nupp identifier"
else
knownStructs [ name ] = true
knownStructs [ declaration . id ] = name
end
if not reason and declaration . anonymous > 0 then
reason , detail , warn = "anonymous-member" , "an anonymous member's fields would promote into it" , true
end
if not reason and declaration . unnamed > 0 then
reason , detail , warn = "unnamed-member" , "an unnamed member or bitfield pads it" , true
end
if not reason and declaration . size == nil and # declaration . fields > 0 then
reason , detail = "incomplete" , "C gives it no size"
end
if not reason then
for _ , field in ipairs ( declaration . fields ) do
local rendered , why = renderType ( field . type , knownStructs )
if not identifier ( field . name ) then
reason , detail = "reserved-name" , ("member %s is not a Nupp identifier") : format ( field . name )
elseif not rendered then
reason , detail = "unsupported-field-type" , ("member %s is %s") : format ( field . name , tostring ( why ) )
elseif field . bitWidth and field . type and field . type . kind == "boolean" then
reason , detail = "unsupported-field-type" , ("member %s is a bool bitfield") : format ( field . name )
end
if reason then
do break end
end
fields [
# fields + 1
] = "   " .. field . name .. ": " .. (
rendered
) .. ( field . bitWidth and " : " .. tostring ( field . bitWidth ) or "" )
end
end
if not reason and unitStatement and unitStatement . packed then
reason , detail , warn = "pragma-pack" , "it is laid out under #pragma pack" , true
end
if not reason and declaration . size ~= nil then
local problem = layoutProblem ( declaration , knownStructs )
if problem then
reason , detail , warn = "layout-mismatch" , problem , true
end
end
if not reason then
if declaration . size == nil then


emit ( ("-- import-c: %s is incomplete in C: use it only behind a pointer") : format ( name ) )
end
emit ( "cdef " .. declaration . kind .. " " .. name )
for _ , field in ipairs ( fields ) do
emit ( field )
end
emit ( "end" )
emit ( "" )
exports [ # exports + 1 ] = name
details . dispositions [
# details . dispositions + 1
] = { name = name , kind = "type-only" , detail = declaration . size == nil and "incomplete" or nil , }
else
knownStructs [ name ] = nil
knownStructs [ declaration . id ] = nil
skip ( declaration . kind , name , reason , detail , line , warn )
end
end

for _ , fn in ipairs ( parsed . functions ) do
local params = { }
local ok = identifier ( fn . name ) and true or false
local why = not ok and "its name is not a Nupp identifier" or nil
local takes = { }
for _ , position in ipairs ( takenParameters [ fn . name ] or { } ) do
takes [ position ] = true
end
for index , param in ipairs ( ok and fn . params or { } ) do
local rendered , renderWhy = renderType ( param . type , knownStructs )
if not rendered then
ok = false
why = ("parameter %d is %s") : format ( index , tostring ( renderWhy ) )
do break end
end
if takes [ index ] and cleanupTerminals [ fn . name ] then
rendered = ownedPointer ( rendered )
end
local name = identifier ( param . name ) and param . name or "arg" .. index
params [ # params + 1 ] = ( takes [ index ] and "takes " or "" ) .. name .. ": " .. rendered
end
if fn . vararg then
params [ # params + 1 ] = "..."
end
local ret
if ok and fn . returns and fn . returns . kind ~= "void" then
local renderWhy
ret , renderWhy = renderType ( fn . returns , knownStructs )
if not ret then
ok = false
why = "its result is " .. tostring ( renderWhy )
else
local cleanup = returnedOwned [ fn . name ]
if cleanup then
ret = "affine(" .. ownedPointer ( ret ) .. ", " .. ( cleanup ) .. ")"
end
end
end
if ok then
local sig = "cdef function " .. fn . name .. "(" .. table . concat ( params , ", " ) .. ")"
if ret then
sig = sig .. ": " .. ret
end
if opts . lib then
sig = sig .. (" from %q") : format ( opts . lib )
end
emit ( sig )
exports [ # exports + 1 ] = fn . name
details . direct = details . direct + 1
details . dispositions [ # details . dispositions + 1 ] = { name = fn . name , kind = "direct" }
else
local reason = identifier ( fn . name ) and "unsupported-c-type" or "reserved-name"
skip ( "function" , fn . name , reason , why , lineOf ( fn . unit ) )
end
end

local bridgeLines = { }
local bridgeAliases = { }

local function bridgePreamble ( ) 
if # bridgeLines > 0 then
return
end
bridgeLines [ # bridgeLines + 1 ] = "#include <stdint.h>"
bridgeLines [ # bridgeLines + 1 ] = "#if defined(_WIN32)"
bridgeLines [ # bridgeLines + 1 ] = "#define NUPP_BRIDGE_EXPORT __declspec(dllexport)"
bridgeLines [ # bridgeLines + 1 ] = "#else"
bridgeLines [ # bridgeLines + 1 ] = "#define NUPP_BRIDGE_EXPORT __attribute__((visibility(\"default\")))"
bridgeLines [ # bridgeLines + 1 ] = "#endif"
bridgeLines [ # bridgeLines + 1 ] = "#include " .. cString ( opts . bridgeInclude or headerPath )
bridgeLines [ # bridgeLines + 1 ] = ""
end

local function addBridge ( fn , logicalName , cDeclaration , callExpression ) 
local params = { }
local callArgs = { }
local ok = ( logicalName and logicalName : match ( "^[%a_][%w_]*$" ) and not RESERVED [ logicalName ] ) and true or false
for index , param in ipairs ( fn . params or { } ) do
local rendered = renderType ( param . type , knownStructs )
if not rendered then
ok = false
do break end
end
local name = identifier ( param . name ) and param . name or "arg" .. tostring ( index )
params [ # params + 1 ] = name .. ": " .. rendered
callArgs [ # callArgs + 1 ] = name
end
local ret = nil
if fn . returns and fn . returns . kind ~= "void" then
ret = renderType ( fn . returns , knownStructs )
ok = ok and ret ~= nil
end
if not ok then
warnings [ # warnings + 1 ] = "bridge skipped " .. logicalName .. ": unsupported C type"
details . skipped = details . skipped + 1
details . dispositions [
# details . dispositions + 1
] = { name = logicalName , kind = "skipped" , reason = "unsupported-bridge-type" , }
return
end
local identity = table . concat ( { "c-bridge-v1" , headerBase , logicalName , cDeclaration } , "\0" )
local symbol = "__nupp_bridge_" .. hash . sha256 ( identity ) : sub ( 1 , 24 )
bridgePreamble ( )


local wrapperDeclaration = cDeclaration : gsub ( "%f[%w_]" .. logicalName .. "%f[^%w_]" , symbol , 1 )
bridgeLines [ # bridgeLines + 1 ] = "NUPP_BRIDGE_EXPORT " .. wrapperDeclaration .. " {"
local call = callExpression or ( logicalName .. "(" .. table . concat ( callArgs , ", " ) .. ")" )
bridgeLines [ # bridgeLines + 1 ] = ( ret and "    return " or "    " ) .. call .. ";"
bridgeLines [ # bridgeLines + 1 ] = "}"
bridgeLines [ # bridgeLines + 1 ] = ""

local sig = "cdef function " .. symbol .. "(" .. table . concat ( params , ", " ) .. ")"
if ret then
sig = sig .. ": " .. ret
end
if opts . lib then
sig = sig .. (" from %q") : format ( opts . lib )
end
emit ( sig )
emit ( "local " .. logicalName .. " = " .. symbol )
bridgeAliases [ # bridgeAliases + 1 ] = logicalName
exports [ # exports + 1 ] = logicalName
details . bridged = details . bridged + 1
details . dispositions [
# details . dispositions + 1
] = { name = logicalName , kind = callExpression and "bridge-macro" or "bridge-inline" , symbol = symbol , }
end

local candidates = staticInlineSignatures ( targetText )
if opts . bridge then
local prototypes = { }
for _ , candidate in ipairs ( candidates ) do
prototypes [ # prototypes + 1 ] = candidate . signature .. ";"
end
local inlineParsed = # prototypes > 0 and cdecl . inspect ( prototypes , typedefText ) or nil
local byName = { }
for _ , fn in ipairs ( inlineParsed and inlineParsed . functions or { } ) do
byName [ fn . name ] = fn
end
for _ , candidate in ipairs ( candidates ) do
local fn = byName [ candidate . name ]
if fn then
addBridge ( fn , candidate . name , candidate . signature )
else
warnings [
# warnings + 1
] = "bridge skipped " .. candidate . name .. ": signature was not accepted by LuaJIT"
details . skipped = details . skipped + 1
end
end
else
for _ , candidate in ipairs ( candidates ) do
emit (
"-- import-c: skipped function "
.. candidate . name
.. " (static inline needs --bridge-out or bindings.bridge)"
)
warnings [ # warnings + 1 ] = "static inline " .. candidate . name .. " needs a configured C bridge"
details . skipped = details . skipped + 1
details . dispositions [
# details . dispositions + 1
] = { name = candidate . name , kind = "skipped" , reason = "bridge-required" , }
end
end

local macroArities = functionMacroArities ( raw )
local macroNames = { }
local configuredMacros = opts . macros or { }
for name in pairs ( configuredMacros ) do
macroNames [ # macroNames + 1 ] = name
end
table . sort ( macroNames )
for _ , name in ipairs ( macroNames ) do
local recipe = configuredMacros [ name ]
local parameters = type ( recipe ) == "table" and recipe . parameters or nil
local result = type ( recipe ) == "table" and recipe . result or nil
local arity = macroArities [ name ]
local valid = ( name and name : match ( "^[%a_][%w_]*$" ) and not RESERVED [ name ] ) and type ( parameters ) == "table" and arity and arity >= 0 and # parameters == arity
local cparams , nparams , args = { } , { } , { }
if valid then
for index , spec in ipairs ( parameters ) do
local ctype = recipeCType ( spec )
if not ctype then
valid = false
do break end
end
local arg = "arg" .. tostring ( index - 1 )
cparams [ # cparams + 1 ] = ctype .. " " .. arg
nparams [ # nparams + 1 ] = { name = arg , type = assert ( cdecl . typeFromString ( ctype ) ) }
args [ # args + 1 ] = arg
end
end
local cresult = result and recipeCType ( result ) or "void"
if result and not cresult then
valid = false
end
if valid then
local fn = {
params = nparams ,
returns = result and assert ( cdecl . typeFromString ( cresult ) ) or { kind = "void" } ,
}
local declaration = cresult .. " " .. name .. "(" .. (
# cparams > 0 and table . concat ( cparams , ", " ) or "void"
) .. ")"
addBridge ( fn , name , declaration , name .. "(" .. table . concat ( args , ", " ) .. ")" )
else
warnings [ # warnings + 1 ] = "bridge skipped macro " .. name .. ": invalid or mismatched signature"
details . skipped = details . skipped + 1
details . dispositions [
# details . dispositions + 1
] = { name = name , kind = "skipped" , reason = "invalid-macro-signature" , }
end
end
if # bridgeAliases > 0 then
emit ( "" )
end


local constLines = { }
local taken = { }

local function constant ( name , typeName , expr ) 
if not ( name and name : match ( "^[%a_][%w_]*$" ) and not RESERVED [ name ] ) or taken [ name ] then
return
end
taken [ name ] = true
constLines [ # constLines + 1 ] = ("local %s: %s = %s") : format ( name , typeName , expr )
exports [ # exports + 1 ] = name
end





for _ , declaration in ipairs ( parsed . enums or { } ) do
for _ , member in ipairs ( declaration . values ) do
constant ( member . name , "int32" , tostring ( member . value ) )
end
end




local values = macroValues ( dm )
local seenMacros = { }
for _ , name in ipairs ( headerMacroNames ( raw ) ) do
local value = values [ name ]
if value and value ~= "" and not seenMacros [ name ] and not taken [ name ] and ( name and name : match ( "^[%a_][%w_]*$" ) and not RESERVED [ name ] ) then
seenMacros [ name ] = true
local expr , typeOrWhy = macroConstant ( value , values , name )
if expr then
constant ( name , typeOrWhy , expr )
else
skip ( "macro" , name , "untranslatable-macro" , typeOrWhy )
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
emit ( "export = { " .. table . concat ( pairsOut , ", " ) .. " }" )
emit ( "" )

if # bridgeLines > 0 then
details . bridgeSource = table . concat ( bridgeLines , "\n" ) .. "\n"
end

return table . concat ( out , "\n" ) , warnings , details
end

local __nuppExportValue= importc ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.cinterop.importc"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.cinterop.importc"]=__nuppExports;return __nuppExports