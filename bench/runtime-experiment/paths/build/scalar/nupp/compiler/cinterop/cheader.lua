_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


















local T = require ( "nupp.compiler.types" )
local cdecl = require ( "nupp.compiler.cinterop.cdecl" )
local hash = require ( "nupp.compiler.hash" )

local cheader = { }



local function hostService ( name ) 
return require ( "nupp.compiler." .. name )
end











































local INT_BY_BITS = {
[ 8 ] = { T . int8 , T . uint8 } ,
[ 16 ] = { T . int16 , T . uint16 } ,
[ 32 ] = { T . int32 , T . uint32 } ,
[ 64 ] = { T . int64 , T . uint64 } ,
}

local modelFunction
local adoptStruct





local function cDeclarationKey ( aggregateKind , namespace , name ) 
return "c\0" .. namespace .. "\0" .. aggregateKind .. "\0" .. name
end






local adoptedById = { }


local function nuppType ( model , structs , resolver ) 
local kind = model and model . kind or "unknown"
if kind == "void" then
return nil
elseif kind == "boolean" then
return T . boolean
elseif kind == "float" then
return model . bits == 32 and T . float or T . number
elseif kind == "integer" then
local pair = INT_BY_BITS [ model . bits ]
if not pair then
return T . number
end
return model . unsigned and pair [ 2 ] or pair [ 1 ]
elseif kind == "pointer" then
local pointee = model . to
local readOnly = model . const
if pointee and pointee . kind == "integer" and pointee . bits == 8 and not pointee . unsigned and readOnly then




return T . optional ( T . cstring )
end



if pointee and pointee . kind == "function" then

return T . optional ( modelFunction ( pointee , structs , resolver ) )
end
if pointee and ( pointee . kind == "struct" or pointee . kind == "union" ) then
local named = structs and structs [ pointee . id ]
if not named and resolver and pointee . name then
named = resolver ( pointee . name )
end
if not named and pointee . id then
named = adoptedById [ pointee . id ]
end
if not named and pointee . name then
named = adoptStruct ( pointee . name , pointee . kind )
end
if named then

if readOnly then
named = T . constOf ( named )
end
return T . optional ( T . ptr ( named ) )
end
end
if pointee and pointee . kind ~= "void" then
local element = nuppType ( pointee , structs , resolver )
if element and element ~= T . any then
if readOnly then
element = T . constOf ( element )
end
return T . optional ( T . ptr ( element ) )
end
end
if readOnly then
return T . optional ( T . constOf ( T . voidptr ) )
end
return T . optional ( T . voidptr )
elseif kind == "struct" or kind == "union" then
local named = structs and structs [ model . id ]
if not named and resolver and model . name then
named = resolver ( model . name )
end
if not named and model . id then
named = adoptedById [ model . id ]
end
if not named and model . name then
named = adoptStruct ( model . name , kind )
end
if named then
return named
end
return T . voidptr
elseif kind == "enum" then
local pair = INT_BY_BITS [ model . bits ]
if not pair then
return T . any
end
return model . unsigned and pair [ 2 ] or pair [ 1 ]
elseif kind == "array" then
local element = nuppType ( model . of , structs , resolver )
if element and model . count then
return T . carray ( element , model . count )
end
return T . any
end

return T . any
end

modelFunction = function ( fn , structs , resolver ) 
local params = { }
for _ , param in ipairs ( fn . params or { } ) do
params [ # params + 1 ] = nuppType ( param . type , structs , resolver ) or T . any
end
local rets = { }
local ret = nuppType ( fn . returns , structs , resolver )
if ret then
rets [ 1 ] = ret
end

return T . func (
params ,
rets ,
fn . vararg ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
true
)
end

local function newlinesOf ( text ) 
return ( text : gsub ( "[^\n]" , "" ) )
end

local function linesOf ( text ) 
local lines = { }
for line in ( text .. "\n" ) : gmatch ( "(.-)\n" ) do
lines [ # lines + 1 ] = line
end

return lines
end




local function cplusplusBranch ( line ) 
local compact = line : gsub ( "%s+" , "" )
if compact == "#ifdef__cplusplus" or compact == "#ifdefined(__cplusplus)" or compact == "#ifdefined__cplusplus" then
return false
end
if compact == "#ifndef__cplusplus"
or compact == "#if!defined(__cplusplus)"
or compact == "#if!defined__cplusplus"
then
return true
end

return nil
end


local function guardName ( line ) 
return line : match ( "^%s*#%s*ifndef%s+([%a_][%w_]*)%s*$" )
or line : match ( "^%s*#%s*if%s*!%s*defined%s*%(%s*([%a_][%w_]*)%s*%)%s*$" )
or line : match ( "^%s*#%s*if%s*!%s*defined%s+([%a_][%w_]*)%s*$" )
end










local function unpreprocessedLines ( text , display ) 
text = text : gsub ( "/%*.-%*/" , function ( comment ) 
return " " .. ( ( comment : gsub ( "[^\n]" , "" ) ) )
end )
local lines = linesOf ( text )
for index , line in ipairs ( lines ) do
lines [ index ] = line : gsub ( "//.*$" , "" )
end



local significant = { }
for index , line in ipairs ( lines ) do
if line : match ( "%S" ) then
significant [ # significant + 1 ] = index
end
end
local guardAt = nil
local name = significant [ 1 ] and guardName ( lines [ significant [ 1 ] ] ) or nil
local define = significant [ 2 ] and lines [ significant [ 2 ] ] : match ( "^%s*#%s*define%s+([%a_][%w_]*)" ) or nil
local last = significant [ # significant ]
if name and name == define and last and lines [ last ] : match ( "^%s*#%s*endif" ) then
guardAt = significant [ 1 ]
end

local out = { }
local stack



= { }

local function live ( ) 
for _ , frame in ipairs ( stack ) do
if not frame . taken then
return false
end
end

return true
end

local function refuse ( index , why ) 
return nil , ("%s:%d: %s") : format ( display , index , why )
end

for index , line in ipairs ( lines ) do
local directive = line : match ( "^%s*#%s*(%a*)" )
if directive then
out [ index ] = ""
local head = line : match ( "^%s*(#%s*%a*[^\n]*)" ) or line
head = head : gsub ( "%s+$" , "" )
if directive == "if" or directive == "ifdef" or directive == "ifndef" then
local branch = cplusplusBranch ( line )
if index == guardAt then
stack [ # stack + 1 ] = { kind = "guard" , taken = true , sawElse = false }
elseif branch ~= nil then
stack [ # stack + 1 ] = { kind = "cplusplus" , taken = branch , sawElse = false }
else
return refuse (
index ,
head
.. " needs cheader's \"preprocess\" argument, since only the preprocessor can pick its branch"
)
end
elseif directive == "elif" or directive == "elifdef" or directive == "elifndef" then
return refuse (
index ,
head .. " needs cheader's \"preprocess\" argument, since only the preprocessor can pick its branch"
)
elseif directive == "else" then
local top = stack [ # stack ]
if not top or top . kind ~= "cplusplus" or top . sawElse then
return refuse (
index ,
"#else needs cheader's \"preprocess\" argument, since only the preprocessor can pick its branch"
)
end
top . taken = not top . taken
top . sawElse = true
elseif directive == "endif" then
if # stack == 0 then
return refuse ( index , "#endif closes no conditional" )
end
stack [ # stack ] = nil
end
else
out [ index ] = live ( ) and line or ""
end
end
if # stack > 0 then
return nil , display .. ": a conditional is never closed"
end

return out
end



local function preprocessedLines ( text ) 



local lines = linesOf ( text )
local origins


= { }
local file = "?"
local number = 0
for index , line in ipairs ( lines ) do
local marker , markerFile = line : match ( "^%s*#%s*(%d+)%s+\"([^\"]*)\"" )
if marker then
file , number = markerFile , ( tonumber ( marker ) ) - 1
lines [ index ] = ""
elseif line : match ( "^%s*#" ) then
number = number + 1
lines [ index ] = ""
else
number = number + 1
origins [ index ] = { file = file , line = number }
end
end

return lines , origins
end



local function nulLine ( text ) 
local at = text : find ( "%z" )
if not at then
return nil
end
local _ , newlines = text : sub ( 1 , at ) : gsub ( "\n" , "" )

return newlines + 1
end


local toolchainCache = { }

local function toolchainTag ( opts ) 
if not opts . preprocess then
return "-"
end
local argv = { opts . cc or "cc" }
for _ , arg in ipairs ( opts . ccArgs or { } ) do
argv [ # argv + 1 ] = arg
end
argv [ # argv + 1 ] = "--version"
local key = table . concat ( argv , "\0" )
local hit = toolchainCache [ key ]
if hit then
return hit
end
local code , output = ( require ( "nupp.compiler." .. "process" ) ) . capture ( argv )
local version = code == 0 and output : match ( "[^\13\n]+" ) or "unknown"
toolchainCache [ key ] = version

return version
end

local function toolchainIdentity ( opts ) 
local parts = { opts . cc or "cc" }
for _ , arg in ipairs ( opts . ccArgs or { } ) do
parts [ # parts + 1 ] = arg
end
parts [ # parts + 1 ] = toolchainTag ( opts )

return table . concat ( parts , "\0" )
end

local function compilerArgv ( opts , ... ) 
local argv = { opts . cc or "cc" }
for _ , arg in ipairs ( opts . ccArgs or { } ) do
argv [ # argv + 1 ] = arg
end
for _ , arg in ipairs ( { ... } ) do
argv [ # argv + 1 ] = arg
end

return argv
end

local function dependencyPaths ( text , sourcePath ) 
local paths = ( require ( "nupp.compiler." .. "shellsyntax" ) ) . depfile : match ( text ) or { }
if # paths == 0 then
paths [ 1 ] = sourcePath
end
local unique , out = { } , { }
for _ , path in ipairs ( paths ) do
path = ( require ( "nupp.compiler." .. "fs" ) ) . canonical ( path )
if not unique [ path ] then
unique [ path ] = true
out [ # out + 1 ] = path
end
end
table . sort ( out )

return out
end

local function preprocessHeader ( path , opts ) 
local depPath = os . tmpname ( )
local argv = compilerArgv ( opts , "-E" , "-MD" , "-MF" , depPath , "-MT" , "nupp_header" , "-xc" , path )
local code , expanded = ( require ( "nupp.compiler." .. "process" ) ) . capture ( argv )
local depText = ( require ( "nupp.compiler." .. "fs" ) ) . readFile ( depPath )
os . remove ( depPath )
if code ~= 0 then
return nil , nil , expanded ~= "" and expanded or ( "cannot preprocess " .. path )
end
if not depText then
return nil , nil , "compiler did not report dependencies for " .. path
end
if # expanded == 0 then
return nil , nil , "cc -E produced no output for " .. path
end

return expanded , dependencyPaths ( depText , path )
end

local function semanticText ( text ) 
text = text : gsub ( "%s+" , " " )
text = text : gsub ( "%s*([{}%(%)%[%],;%*])%s*" , "%1" )
return text : match ( "^%s*(.-)%s*$" ) or text
end

local cache = { }

local function provenance ( path , opts ) 
opts = opts or { }
local display = opts . display or path
path = ( require ( "nupp.compiler." .. "fs" ) ) . canonical ( path )
local source = opts . read and opts . read ( path ) or ( require ( "nupp.compiler." .. "fs" ) ) . readFile ( path )
if not source then
return nil , "cannot read " .. path , true
end
local nul = nulLine ( source )
if nul then
return nil , ("%s:%d: the header holds a NUL byte, and LuaJIT would read nothing past it") : format ( display , nul )
end
local dependencies = { path }
local lines , origins
if opts . preprocess then
local expanded , discovered , problem = preprocessHeader ( path , opts )
if not expanded then
return nil , problem
end
dependencies = discovered
lines , origins = preprocessedLines ( expanded )
else
local read , problem = unpreprocessedLines ( source , display )
if not read then
return nil , problem
end
lines = read
end
local parseText = table . concat ( lines , "\n" )


local kept = { }
for _ , line in ipairs ( lines ) do
if line : match ( "%S" ) then
kept [ # kept + 1 ] = line
end
end
local text = table . concat ( kept , "\n" )
local semanticFingerprint = hash . digest (
table . concat ( { "cheader-v2" , cdecl . abiTag ( ) , toolchainIdentity ( opts ) , semanticText ( text ) } , "\0" )
)

return {
cdef = text ,
sourcePath = path ,
dependencies = dependencies ,
semanticFingerprint = semanticFingerprint ,
parseText = parseText ,
origins = origins ,
}
end

cheader . provenance = provenance





local declaredBlocks = { }
local declaredNames = { }







function cheader . declare ( text ) 
if declaredBlocks [ text ] ~= nil then
return declaredBlocks [ text ] , nil , declaredNames [ text ]
end
local ok , err , names = cdecl . declare ( text )
declaredBlocks [ text ] = ok
declaredNames [ text ] = names or { }
if not ok then
return false , err
end

return true , nil , declaredNames [ text ]
end






local adopted = { }

local function adoptingResolver ( resolver ) 
return function ( tag ) 
if resolver then
local known = resolver ( tag )
if known then
return known
end
end

return adoptStruct ( tag , "struct" ) or adoptStruct ( tag , "union" )
end
end

adoptStruct = function ( tag , aggregateKind ) 
aggregateKind = aggregateKind or "struct"
local key = aggregateKind .. " " .. tag
local hit = adopted [ key ]
if hit then
return hit
end
local model = cdecl . typeFromString ( key )
if not model or model . kind ~= aggregateKind then
return nil
end
local known = model . id and adoptedById [ model . id ] or nil
if known then
adopted [ key ] = known
return known
end
local declaration = cdecl . structById ( model . id )
if not declaration then
return nil
end
local nominal = T . nominal ( tag , "struct" , ( "c\0" .. "tag" .. "\0" .. aggregateKind .. "\0" .. tag ) )
nominal . cdefName = tag
nominal . cdefKind = aggregateKind
nominal . fieldOrder = { }

adopted [ key ] = nominal
adoptedById [ declaration . id ] = nominal
for _ , field in ipairs ( declaration . fields ) do
local fieldType = nuppType ( field . type , nil , adoptingResolver ( nil ) ) or T . any
nominal . byname [ field . name ] = fieldType
nominal . writeByname [ field . name ] = fieldType
nominal . fieldOrder [ # nominal . fieldOrder + 1 ] = field . name
end

return nominal
end

function cheader . typeFromString ( spec , resolver ) 
local model , err = cdecl . typeFromString ( spec )
if not model then
return nil , err
end

return nuppType ( model , nil , adoptingResolver ( resolver ) )
end





function cheader . declaredFunctions ( resolver , only ) 
local out = { }
local r = adoptingResolver ( resolver )
for name , fn in pairs ( cdecl . declaredFunctions ( only ) ) do
out [ name ] = modelFunction ( fn , nil , r )
end

return out
end








function cheader . load ( path , opts ) 
opts = opts or { }
local observed , problem , missing = provenance ( path , opts )
if not observed then
return nil , problem , missing
end
local text = observed . cdef
local dependencies = observed . dependencies
local semanticFingerprint = observed . semanticFingerprint


local key = table . concat ( { semanticFingerprint , table . concat ( dependencies , "\0" ) } , "\0" )
local hit = cache [ key ]
if hit then
return {
exports = hit . exports ,
cdef = hit . cdef ,
sourcePath = observed . sourcePath ,
dependencies = dependencies ,
semanticFingerprint = semanticFingerprint ,
}
end

local parsed , err = cdecl . inspect ( observed . parseText or text )
if not parsed then



local message = tostring ( err )
local line = ( tonumber ( message : match ( "at line (%d+)$" ) or "" ) or 1 )
message = message : gsub ( "%s*at line %d+$" , "" )
local where = opts . display or path
local origin = observed . origins and observed . origins [ line ] or nil
if origin then
where = origin . file .. ":" .. tostring ( origin . line )
elseif not observed . origins then
where = where .. ":" .. tostring ( line )
end
return nil , ("LuaJIT could not parse %s: %s") : format ( where , message )
end



local structs , exports = { } , { }
local fresh = { }
for _ , declaration in ipairs ( parsed . structs ) do
local nominal = adoptedById [ declaration . id ]
if not nominal then
nominal = T . nominal (
declaration . name ,
"struct" ,
cDeclarationKey ( declaration . kind , declaration . typedefName and "typedef" or "tag" , declaration . name )
)
nominal . cdefName = declaration . name
nominal . cdefKind = declaration . kind
nominal . fieldOrder = { }
adoptedById [ declaration . id ] = nominal
if not declaration . typedefName then
adopted [ declaration . kind .. " " .. declaration . name ] = nominal
end
fresh [ declaration . id ] = true
end
structs [ declaration . id ] = nominal
end
for _ , declaration in ipairs ( parsed . structs ) do
local nominal = structs [ declaration . id ]
for _ , field in ipairs ( fresh [ declaration . id ] and declaration . fields or { } ) do
local fieldType = nuppType ( field . type , structs ) or T . any
nominal . byname [ field . name ] = fieldType
nominal . writeByname [ field . name ] = fieldType
nominal . fieldOrder [ # nominal . fieldOrder + 1 ] = field . name
end
end
for _ , fn in ipairs ( parsed . functions ) do
exports [ fn . name ] = modelFunction ( fn , structs )
end


for _ , declaration in ipairs ( parsed . enums ) do
for _ , member in ipairs ( declaration . values ) do
if exports [ member . name ] == nil then
exports [ member . name ] = T . int32
end
end
end

local result = {
exports = exports ,
cdef = text ,
sourcePath = observed . sourcePath ,
dependencies = dependencies ,
semanticFingerprint = semanticFingerprint ,
}
cache [ key ] = result

return result
end

local __nuppExportValue= cheader ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.cinterop.cheader"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.cinterop.cheader"]=__nuppExports;return __nuppExports