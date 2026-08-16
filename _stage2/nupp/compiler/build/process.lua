_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();const __nuppT4={}; const __nuppT5,__nuppT6,__nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12=pcall,xpcall,error,unpack,select,setmetatable,tostring,ipairs; const function __nuppT1(...) return {n=__nuppT9("#",...),...} end; const function __nuppT2(value) return value end; const function __nuppT3(primary,errors,start) const secondary={} for i=start,#errors do secondary[#secondary+1]=errors[i] end return __nuppT10({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT11(v.primary) for _,reason in __nuppT12(v.suppressed) do text=text.."\ncleanup: "..__nuppT11(reason) end return text end}) end; local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local __nuppNativeValue;local function __nuppNative()if __nuppNativeValue then return __nuppNativeValue end;local ffi=require("ffi");ffi.cdef[[const char*nuppNativeError(void);typedef struct NuppSpawn NuppSpawn;typedef struct NuppChild NuppChild;typedef struct NuppStream NuppStream;NuppSpawn*nuppProcessSpawnBegin(void);bool nuppProcessSpawnArg(NuppSpawn*,const uint8_t*,size_t);bool nuppProcessSpawnEnv(NuppSpawn*,const uint8_t*,size_t);bool nuppProcessSpawnClearEnv(NuppSpawn*,bool);bool nuppProcessSpawnCwd(NuppSpawn*,const uint8_t*,size_t);bool nuppProcessSpawnStdio(NuppSpawn*,uint8_t,uint8_t);void nuppProcessSpawnCancel(NuppSpawn*);NuppChild*nuppProcessSpawnRun(NuppSpawn*);NuppStream*nuppProcessTakeStream(NuppChild*,uint8_t);intptr_t nuppProcessTryRead(NuppStream*,uint8_t*,size_t);intptr_t nuppProcessTryWrite(NuppStream*,const uint8_t*,size_t);uint8_t nuppProcessCloseStream(NuppStream*);void nuppProcessStreamDestroy(NuppStream*);int32_t nuppProcessPollExit(NuppChild*,int32_t*,bool*);uint32_t nuppProcessId(NuppChild*);bool nuppProcessKill(NuppChild*,bool);uint8_t nuppProcessReap(NuppChild*);void nuppProcessDestroy(NuppChild*);int32_t nuppProcessWaitReady(NuppStream*const*,size_t,NuppStream*const*,size_t,int32_t);size_t nuppProcessUncollectedTotal(void);]];local source=debug.getinfo(1,"S").source;local root=source:match("^@(.+)/[^/]+%.lua$")or".";local wanted=os.getenv("NUPP_NATIVE_LIBRARY");local C;if wanted then C=ffi.load(wanted)else local linked=pcall(function()return ffi.C.nuppNativeError end);if linked then C=ffi.C else local library=ffi.os=="Windows"and"/lib/nupp_native.dll"or"/lib/nupp_native";local ok,lib=pcall(ffi.load,root..library);if ok then C=lib else C=ffi.load(root.."/.."..library)end end end;local function errorText()return ffi.string(C.nuppNativeError())end;__nuppNativeValue={ffi=ffi,C=C,error=errorText};return __nuppNativeValue end package.preload["nupp.io.processnative"]=function() local native=__nuppNative();local ffi,C=native.ffi,native.C ffi.cdef[[double nuppProcessMonotonicMs(void);]] local MODE={pipe=0,inherit=1,["null"]=2,stdout=3} local WOULD_BLOCK,GONE,FAILED=-1,-2,-3 local RELEASED,RELEASED_WITH_REASON,NOT_RELEASED=0,1,2 local READ_SIZE,INT32_MAX=65536,2147483647 local function reason(prefix)local said=native.error();if said==nil or said==""then said="native process operation failed"end;return prefix..": "..said end local function maybeDestroy(owner)if owner.destroyed or not owner.released then return end;for _,stream in ipairs(owner.streams)do if not stream.released then return end end;owner.destroyed=true;for _,stream in ipairs(owner.streams)do local handle=stream.handle;stream.handle=nil;if handle~=nil then C.nuppProcessStreamDestroy(handle)end end;local child=owner.handle;owner.handle=nil;if child~=nil then C.nuppProcessDestroy(child)end end local function abandon(owner,message)for _,stream in ipairs(owner.streams)do if not stream.released then C.nuppProcessCloseStream(stream.handle);stream.released=true end;C.nuppProcessStreamDestroy(stream.handle);stream.handle=nil end;if owner.handle~=nil then C.nuppProcessKill(owner.handle,true);C.nuppProcessDestroy(owner.handle);owner.handle=nil end;owner.destroyed=true;error(message,0)end local function configured(ok,request,what)if ok then return end;local why=reason("nupp: could not configure process "..what);C.nuppProcessSpawnCancel(request);error(why,0)end local function wrap(owner,which,expected)local handle=C.nuppProcessTakeStream(owner.handle,which);if handle==nil then if expected then abandon(owner,reason("nupp: could not take process stream"))end;return nil end;local stream={owner=owner,handle=handle,released=false,scratch=nil,capacity=0};owner.streams[#owner.streams+1]=stream;return stream end local function makeArray(streams)local count=#streams;if count==0 then return nil,0 end;local out=ffi.new("NuppStream*[?]",count);for index,stream in ipairs(streams)do local handle=stream and stream.handle;if handle==nil then error("nupp: readiness interest named a destroyed process stream",0)end;out[index-1]=handle end;return out,count end local function whole(value)local number=tonumber(value)or 0;if number~=number then return 0 end;return math.floor(number)end return{new=function(exited) local backend={} function backend:spawn(options) local inputMode=options.stdin or"pipe";local outputMode=options.stdout or"pipe";local errorMode=options.stderr or"pipe" if MODE[inputMode]==nil then error("nupp: process has no stdin mode named "..tostring(inputMode),0)end if MODE[outputMode]==nil or outputMode=="stdout"then error("nupp: process has no stdout mode named "..tostring(outputMode),0)end if MODE[errorMode]==nil then error("nupp: process has no stderr mode named "..tostring(errorMode),0)end local request=C.nuppProcessSpawnBegin();if request==nil then error(reason("nupp: could not begin process spawn"),0)end for _,argument in ipairs(options.args or{})do configured(C.nuppProcessSpawnArg(request,argument,#argument),request,"argument")end configured(C.nuppProcessSpawnClearEnv(request,options.clearEnv==true),request,"environment mode") for key,value in pairs(options.env or{})do local entry=key.."="..value;configured(C.nuppProcessSpawnEnv(request,entry,#entry),request,"environment")end if options.cwd~=nil then local cwd=type(options.cwd)=="string"and options.cwd or options.cwd:toString();configured(C.nuppProcessSpawnCwd(request,cwd,#cwd),request,"working directory")end configured(C.nuppProcessSpawnStdio(request,0,MODE[inputMode]),request,"stdin") configured(C.nuppProcessSpawnStdio(request,1,MODE[outputMode]),request,"stdout") configured(C.nuppProcessSpawnStdio(request,2,MODE[errorMode]),request,"stderr") local child=C.nuppProcessSpawnRun(request);if child==nil then return nil,nil,nil,nil,0,reason("nupp: could not start process")end local owner={handle=child,streams={},released=false,destroyed=false} local input=wrap(owner,0,inputMode=="pipe");local output=wrap(owner,1,outputMode=="pipe");local err=wrap(owner,2,errorMode=="pipe") return owner,input,output,err,tonumber(C.nuppProcessId(child)) end function backend:poll(owner)local code=ffi.new("int32_t[1]");local killed=ffi.new("bool[1]");local status=C.nuppProcessPollExit(owner.handle,code,killed);if status<0 then error(reason("nupp: could not poll process"),0)end;if status==0 then return nil end;return exited(tonumber(code[0]),killed[0],false)end function backend:kill(owner,force)if not C.nuppProcessKill(owner.handle,force)then error(reason("nupp: could not kill process"),0)end end function backend:read(stream,limit)local wanted=whole(limit);if wanted<1 then wanted=1 elseif wanted>READ_SIZE then wanted=READ_SIZE end;if stream.capacity<wanted then stream.scratch=ffi.new("uint8_t[?]",wanted);stream.capacity=wanted end;local got=tonumber(C.nuppProcessTryRead(stream.handle,stream.scratch,wanted));if got>=0 then return ffi.string(stream.scratch,got)end;if got==WOULD_BLOCK then return""end;if got==GONE then return nil end;error(reason("nupp: could not read process stream"),0)end function backend:write(stream,bytes)local sent=tonumber(C.nuppProcessTryWrite(stream.handle,bytes,#bytes));if sent>=0 then return sent,false end;if sent==WOULD_BLOCK then return 0,false end;if sent==GONE then return 0,true end;error(reason("nupp: could not write process stream"),0)end function backend:closeStream(stream)if stream.released then return true end;local status=C.nuppProcessCloseStream(stream.handle);local why=nil;if status~=RELEASED then why=reason("nupp: could not close process stream")end;if status==RELEASED or status==RELEASED_WITH_REASON then stream.released=true;maybeDestroy(stream.owner);return true,why end;return false,why end function backend:reap(owner)if owner.released then return true end;local status=C.nuppProcessReap(owner.handle);local why=nil;if status~=RELEASED then why=reason("nupp: could not release process")end;if status==RELEASED or status==RELEASED_WITH_REASON then owner.released=true;maybeDestroy(owner);return true,why end;return false,why end function backend:now()return C.nuppProcessMonotonicMs()end function backend:waitReady(interest,timeoutMs)local readable,readCount=makeArray(interest.read);local writable,writeCount=makeArray(interest.write);local timeout=whole(timeoutMs);if timeout<0 then timeout=0 elseif timeout>INT32_MAX then timeout=INT32_MAX end;local answered=C.nuppProcessWaitReady(readable,readCount,writable,writeCount,timeout);if answered<0 then error(reason("nupp: process readiness wait failed"),0)end;return tonumber(answered)end return backend end} end;local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp.io.process#process.destroyProcess"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.process#process.destroyProcess") end;__nuppCleanup1=cleanup;return cleanup(value) end;








local process = { }































local windows = package . config : sub ( 1 , 1 ) == "\\"




local function nativePath ( path )
if windows then
return ( path : gsub ( "^/([A-Za-z])(/)" , "%1:%2" ) )
end
return path
end

local function quote ( arg )
arg = tostring ( arg )
if windows then
if not arg : find ( '[%s"]' ) then
return arg
end
return '"' .. arg : gsub ( '(\\*)"' , '%1%1\\"' ) : gsub ( '(\\+)$' , '%1%1' ) .. '"'
end

return "'" .. arg : gsub ( "'" , "'\\''" ) .. "'"
end

local function launchArgs ( argv )
local testBash = windows and ( rawget ( _G , "__NUPP_TEST_BASH" ) or os . getenv ( "NUPP_TEST_BASH" ) ) or nil
if not testBash or not tostring ( argv [ 1 ] ) : gsub ( "\\" , "/" ) : match ( "/bin/nupp$" ) then
return argv
end

local launched = { testBash }
for _ , arg in ipairs ( argv ) do
launched [ # launched + 1 ] = arg
end

return launched
end

local function exists ( path )
local file = io . open ( path , "rb" )
if not file then
return false
end
file : close ( )

return true
end










local function isolatedArgs ( argv )
if windows then
local executable = tostring ( argv [ 1 ] ) : gsub ( "\\" , "/" )
local root = executable : match ( "^(.*)/bin/nupp$" )
if root then
local built = root .. "/build/nupp/compiler/main.lua"
local path = ( "package.path=%q .. package.path" ) : format ( root .. "/build/?.lua;" )
local launched = { "luajit" , "-e" , path , exists ( built ) and built or root .. "/bootstrap/nupp.lua" }
for index = 2 , # argv do
launched [ # launched + 1 ] = argv [ index ]
end
return launched
end
end

return launchArgs ( argv )
end

function process . command ( argv , opts )
assert ( type ( argv ) == "table" and # argv > 0 , "argv must not be empty" )
opts = ( opts or { } )
argv = launchArgs ( argv )
local parts = { }
if opts . env then
local names = { }
for name in pairs ( opts . env ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
assert ( name : match ( "^[%a_][%w_]*$" ) , "invalid environment name" )
if windows then


parts [ # parts + 1 ] = 'set "' .. name .. "=" .. tostring ( opts . env [ name ] ) .. '"'
parts [ # parts + 1 ] = "&&"
else
parts [ # parts + 1 ] = name .. "=" .. quote ( opts . env [ name ] )
end
end
end
for _ , arg in ipairs ( argv ) do
parts [ # parts + 1 ] = quote ( arg )
end
local command = table . concat ( parts , " " )
if opts . cwd then
command = windows and (
"cd /d " .. quote ( opts . cwd ) .. " && " .. command
) or ( "cd " .. quote ( opts . cwd ) .. " && " .. command )
end





local testMarker = windows and rawget ( _G , "__NUPP_TEST_CMD_MARKER" ) or nil

return testMarker and ( testMarker .. command ) or command
end

function process . mkdirCommand ( path , forWindows )
path = tostring ( path )
if forWindows == nil then
forWindows = windows
end
if forWindows then


path = path : gsub ( "/" , "\\" )
return { "cmd" , "/d" , "/c" , "if" , "not" , "exist" , path , "mkdir" , path }
end

return { "mkdir" , "-p" , path }
end

local function exitCode ( status )
if status == true then
return 0
end
if type ( status ) ~= "number" then
return 1
end
if status > 255 then
return math . floor ( status / 256 )
end

return status
end

function process . run ( argv , opts )
return exitCode ( os . execute ( process . command ( argv , opts ) ) )
end

function process . capture ( argv , opts )
opts = ( opts or { } )
local tmp = nativePath ( os . tmpname ( ) )
local command = process . command ( argv , opts ) .. " >" .. quote ( tmp ) .. " 2>&1"
local code = exitCode ( os . execute ( command ) )
local f = io . open ( tmp , "rb" )
local output = f and f : read ( "*a" ) or ""
if f then
f : close ( )
end
os . remove ( tmp )

return code , output
end




function process . captureIsolated ( argv , opts )
opts = ( opts or { } )
local args = isolatedArgs ( argv )
if opts . memoryMb and not windows then
local kilobytes = math . max ( 1 , math . floor ( opts . memoryMb * 1024 ) )
args = {
"/bin/sh" ,
"-c" ,
"ulimit -v " .. tostring ( kilobytes ) .. " 2>/dev/null || true; exec " .. process . command ( argv ) ,
}
end
local native = require ( "nupp.io.process" )
do local __nuppT13=0; local  __nuppT19 ; const __nuppT14,__nuppT15,__nuppT16=__nuppT6(function() do const __nuppT20=__nuppT1( native . new ( {
args = args ,
cwd = opts . cwd ,
env = opts . env ,
stdin = "null" ,
stdout = "pipe" ,
stderr = "stdout" ,
timeoutMs = opts . timeoutMs ,
} ) ); __nuppT19= __nuppT20[1] ; __nuppT13=1;  local  child , problem = __nuppT20[1] , __nuppT20[2] ;
if not child then
return "return",__nuppT1( 1 , tostring ( problem or "the worker could not be started" ) )
end
local reader = assert ( child . stdout )
reader : setTimeout ( 5 )
local chunks = { }
local cancelled = false
while true do
local moved = false
while true do
local chunk = reader : poll ( )
if chunk == nil then
break
end
if # chunk == 0 then
break
end
chunks [ # chunks + 1 ] = chunk
moved = true
end
if opts . pump then
opts . pump ( )
end
if not cancelled and opts . cancelled and opts . cancelled ( ) then
cancelled = true
child : kill ( true )
end
local running = child : isRunning ( )
if not running and reader : isEOF ( ) then
break
end
if not moved and not reader : isEOF ( ) then
local chunk , reason = reader : read ( 65536 )
if chunk and # chunk > 0 then
chunks [ # chunks + 1 ] = chunk
elseif reason and not reason : find ( "timed out" , 1 , true ) then
child : kill ( true )
chunks [ # chunks + 1 ] = reason
end
end
end
local exit = child : wait ( )
child : close ( )
if cancelled then
return "return",__nuppT1( 125 , table . concat ( chunks ) )
end
if exit . timedOut then
return "return",__nuppT1( 124 , table . concat ( chunks ) )
end

return "return",__nuppT1( exit . exitCode , table . concat ( chunks ) ) end; return "normal" end,__nuppT2); const __nuppT17={}; local __nuppT18=0; if __nuppT13>=1 and __nuppT19~=nil then  const __nuppT21,__nuppT22=__nuppT5(__nuppCleanup1,__nuppT19);  if not __nuppT21 then __nuppT18=__nuppT18+1; __nuppT17[__nuppT18]=__nuppT22 end; end; if not __nuppT14 then if __nuppT18>0 then __nuppT7(__nuppT3(__nuppT15,__nuppT17,1),0) else __nuppT7(__nuppT15,0) end end; if __nuppT18>0 then if __nuppT18>1 then __nuppT7(__nuppT3(__nuppT17[1],__nuppT17,2),0) else __nuppT7(__nuppT17[1],0) end end; if __nuppT15=="return" then  return __nuppT8(__nuppT16,1,__nuppT16.n)  end; end
end



function process . startIsolated ( argv , opts )
opts = ( opts or { } )
local args = isolatedArgs ( argv )
if opts . memoryMb and not windows then
local kilobytes = math . max ( 1 , math . floor ( opts . memoryMb * 1024 ) )
args = {
"/bin/sh" ,
"-c" ,
"ulimit -v " .. tostring ( kilobytes ) .. " 2>/dev/null || true; exec " .. process . command ( argv ) ,
}
end
local native = require ( "nupp.io.process" )

return native . new ( {
args = args ,
cwd = opts . cwd ,
env = opts . env ,
stdin = "pipe" ,
stdout = "pipe" ,
stderr = "stdout" ,
} )
end

return process
