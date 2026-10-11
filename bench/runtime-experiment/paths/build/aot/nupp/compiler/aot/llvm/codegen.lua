_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.codegen\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.codegen\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.aot.llvm.codegen\0runtime\0003") };











local native = require ( "nupp.runtime.native" )

local codegen = { }


const CODEGEN_FEATURE = 2048

local declared = false

local function declare ( ) 
if declared then
return
end
declared = true
local ffi = native . ffi
ffi . cdef [[
uint32_t nuppCodegenAvailable(void);
int32_t nuppCodegenVersion(uint64_t *result);
int32_t nuppCodegenCompile(
    const char *ir, size_t irLength,
    const char *name, size_t nameLength,
    const char *options, size_t optionsLength,
    uint64_t *object, uint64_t *report, uint64_t *assembly, uint64_t *optimizedIr);
int32_t nuppCodegenLink(const char *argv, size_t length, uint64_t *messages);
int32_t nuppCodegenUnexitable(void);
void nuppCodegenEndProcess(int32_t code);
int32_t nuppCodegenImportLibrary(
    const char *dll, size_t dllLength,
    const char *path, size_t pathLength,
    const char *names, size_t namesLength);
int32_t nuppCodegenCompileFiles(const char *jobs, size_t length, uint32_t width, uint64_t *results);
int32_t nuppCodegenArchive(
    const char *path, size_t pathLength,
    const char *members, size_t membersLength,
    int32_t kind);
int32_t nuppCodegenKitFetch(
    const char *url, size_t urlLength,
    const char *path, size_t pathLength,
    const char *sha256, size_t sha256Length,
    uint64_t size);
int32_t nuppCodegenKitUnpack(
    const char *archive, size_t archiveLength,
    const char *sha256, size_t sha256Length,
    uint64_t size,
    const char *root, size_t rootLength);
]]
end


function codegen . available ( ) 
local ok , answer = pcall ( function ( ) 
declare ( )
local C = native . C
if ( C . nuppNativeFeatures ( ) ) % 4096 < 2048 then
return false
end

return C . nuppCodegenAvailable ( ) ~= 0
end )
if not ok then
return false , "the native provider could not be loaded: " .. tostring ( answer )
end
if answer ~= true then
return false , "this nupp was built without the LLVM code generator; run scripts/toolchain llvm and rebuild"
end

return true , nil
end



function codegen . version ( ) 
declare ( )
local ffi = native . ffi
local C = native . C
local handle = ffi . new ( "uint64_t[1]" )
native . succeeded ( C . nuppCodegenVersion ( handle ) , 2 )

return native . bytes ( handle [ 0 ] )
end


local function take ( handle ) 
local ffi = native . ffi
if ffi . cast ( "uint64_t" , handle ) == 0 then
return nil
end

return native . bytes ( handle )
end


codegen.Compiled = {} codegen.Compiled.__index = codegen.Compiled ;_G.nupp.__reflect.link(codegen.Compiled,__nuppT1[1],{ })







local function optionText ( options ) 
local keys = { }
for key in pairs ( options ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys )
local lines = { }
for _ , key in ipairs ( keys ) do
lines [ # lines + 1 ] = key .. "=" .. ( options [ key ] )
end

return table . concat ( lines , "\n" )
end




function codegen . compile ( ir , name , options ) 
local ok , result = pcall ( function ( ) 
declare ( )
local ffi = native . ffi
local C = native . C
local text = optionText ( options )
local object = ffi . new ( "uint64_t[1]" )
local report = ffi . new ( "uint64_t[1]" )
local assembly = ffi . new ( "uint64_t[1]" )
local optimized = ffi . new ( "uint64_t[1]" )
native . succeeded (
C . nuppCodegenCompile ( ir , # ir , name , # name , text , # text , object , report , assembly , optimized ) ,
2
)

return ( _G.setmetatable({ object =
take ( object [ 0 ] ) or "" ,  report =
take ( report [ 0 ] ) or "" ,  assembly =
take ( assembly [ 0 ] ) ,  optimizedIr =
take ( optimized [ 0 ] ) }, codegen.Compiled) )

end )
if not ok then
return nil , tostring ( result )
end

return result , nil
end


codegen.Job = {} codegen.Job.__index = codegen.Job ;_G.nupp.__reflect.link(codegen.Job,__nuppT1[2],{ })






codegen.Outcome = {} codegen.Outcome.__index = codegen.Outcome ;_G.nupp.__reflect.link(codegen.Outcome,__nuppT1[3],{ })








function codegen . compileFiles ( jobs , width ) 
local ok , result = pcall ( function ( ) 
declare ( )
local ffi = native . ffi
local C = native . C
local records = { }
for position , job in ipairs ( jobs ) do
records [ position ] = job . ir .. "\31" .. job . object .. "\31" .. optionText ( job . options )
end
local joined = table . concat ( records , "\0" ) .. "\0"
local handle = ffi . new ( "uint64_t[1]" )
native . succeeded ( C . nuppCodegenCompileFiles ( joined , # joined , width , handle ) , 2 )
local text = take ( handle [ 0 ] ) or ""
local outcomes = { }
for record in text : gmatch ( "([^%z]*)%z" ) do
local kind , body = record : match ( "^(%a+)\31(.*)$" )
outcomes [ # outcomes + 1 ] = kind == "ok" and _G.setmetatable({ report =  body ,  error =  nil }, codegen.Outcome)
or _G.setmetatable({ report =  nil ,  error =  body or record }, codegen.Outcome)
end

return outcomes
end )
if not ok then
return nil , tostring ( result )
end

return result , nil
end





function codegen . endIfUnexitable ( code ) 
if not declared then
return
end
local C = native . C
local ok , unexitable = pcall ( function ( ) 
return C . nuppCodegenUnexitable ( ) ~= 0
end )
if ok and unexitable then
io . stdout : flush ( )
io . stderr : flush ( )
C . nuppCodegenEndProcess ( code )
end
end




function codegen . link ( argv ) 
local ok , result = pcall ( function ( ) 
declare ( )
local ffi = native . ffi
local C = native . C
local joined = table . concat ( argv , "\0" ) .. "\0"
local messages = ffi . new ( "uint64_t[1]" )
native . succeeded ( C . nuppCodegenLink ( joined , # joined , messages ) , 2 )

return take ( messages [ 0 ] ) or ""
end )
if not ok then
return nil , tostring ( result )
end

return result , nil
end




function codegen . importLibrary ( dll , path , names ) 
local ok , err = pcall ( function ( ) 
declare ( )
local C = native . C
local entries = { }
for position , entry in ipairs ( names ) do
entries [ position ] = entry [ 2 ] ~= nil and entry [ 1 ] .. "\9" .. entry [ 2 ] or entry [ 1 ]
end
local joined = table . concat ( entries , "\0" ) .. "\0"
native . succeeded ( C . nuppCodegenImportLibrary ( dll , # dll , path , # path , joined , # joined ) , 2 )
end )
if not ok then
return tostring ( err )
end

return nil
end


const ARCHIVE = { gnu = 0 , bsd = 1 , darwin = 2 , coff = 3 }




function codegen . archive ( path , members , format ) 
local ok , err = pcall ( function ( ) 
declare ( )
local C = native . C
local joined = table . concat ( members , "\0" ) .. "\0"
native . succeeded ( C . nuppCodegenArchive ( path , # path , joined , # joined , ARCHIVE [ format ] or 0 ) , 2 )
end )
if not ok then
return tostring ( err )
end

return nil
end




function codegen . fetchKit ( url , path , sha256 , size ) 
local ok , err = pcall ( function ( ) 
declare ( )
local C = native . C
native . succeeded ( C . nuppCodegenKitFetch ( url , # url , path , # path , sha256 , # sha256 , size ) , 2 )
end )
if not ok then
return tostring ( err )
end

return nil
end




function codegen . unpackKit ( archive , sha256 , size , root ) 
local ok , err = pcall ( function ( ) 
declare ( )
local C = native . C
native . succeeded ( C . nuppCodegenKitUnpack ( archive , # archive , sha256 , # sha256 , size , root , # root ) , 2 )
end )
if not ok then
return tostring ( err )
end

return nil
end

local __nuppExportValue= codegen ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.llvm.codegen"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.llvm.codegen"]=__nuppExports;return __nuppExports