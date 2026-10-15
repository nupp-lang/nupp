_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT8={}; local function __nuppT5(...) return {n=select("#",...),...} end; local __nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT6(value) return value end; local function __nuppT7(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT14({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT15(v.primary) for _,reason in __nuppT16(v.suppressed) do text=text.."\ncleanup: "..__nuppT15(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppT58 = function(__nuppV) return __nuppV:close() end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


















const _DYNAMIC_REQUIRES = "@requires-dynamically nupp.io.process"
local loadProcess = require

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
if arg == "" then
return "\"\""
end
if not arg : find ( "[%s\"]" ) then
return arg
end
return "\"" .. arg : gsub ( "(\\*)\"" , "%1%1\\\"" ) : gsub ( "(\\+)$" , "%1%1" ) .. "\""
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
do const  __nuppT23= io . open ( path , "rb" ) ; local __nuppT24=__nuppT8[1]; if not __nuppT24 then __nuppT24=function(file) do
if not file then
return "return",__nuppT5( false )
end
file : close ( )

return "return",__nuppT5( true ) end; return "normal" end; __nuppT8[1]=__nuppT24 end; const __nuppT18,__nuppT19,__nuppT20=__nuppT10(__nuppT24,__nuppT6,__nuppT23); const __nuppT17=1; local __nuppT21={}; local __nuppT22=0; if __nuppT17>=1 and __nuppT23~=nil then  local __nuppT25,__nuppT26=__nuppT9(__nuppCleanup1,__nuppT23);  if not __nuppT25 then __nuppT22=__nuppT22+1; __nuppT21[__nuppT22]=__nuppT26 end; end; if not __nuppT18 then if __nuppT22>0 then __nuppT11(__nuppT7(__nuppT19,__nuppT21,1),0) else __nuppT11(__nuppT19,0) end end; if __nuppT22>0 then if __nuppT22>1 then __nuppT11(__nuppT7(__nuppT21[1],__nuppT21,2),0) else __nuppT11(__nuppT21[1],0) end end; if __nuppT19=="return" then  return __nuppT12(__nuppT20,1,__nuppT20.n)  end; end
end












local function isolatedArgs ( argv ) 
if windows then
local executable = tostring ( argv [ 1 ] ) : gsub ( "\\" , "/" )
local root = executable : match ( "^(.*)/bin/nupp$" )
if root then
local built = root .. "/build/nupp/tools/main.lua"
local compiler = exists ( built ) and built or os . getenv ( "NUPP_STAGE0" )
if compiler then
local path = ("package.path=%q .. package.path") : format ( root .. "/build/?.lua;" )
local launched = { "luajit" , "-e" , path , compiler }
for index = 2 , # argv do
launched [ # launched + 1 ] = argv [ index ]
end
return launched
end
end
end

return launchArgs ( argv )
end






function process . isolatedArguments ( argv ) 
return isolatedArgs ( argv )
end



local function assertUnbounded ( opts , entry ) 
assert (
opts . timeoutMs == nil and opts . memoryMb == nil and opts . pump == nil and opts . cancelled == nil ,
"process." .. entry .. " honors only cwd and env; use captureIsolated for a bounded child"
)
end

function process . command ( argv , opts ) 
assert ( type ( argv ) == "table" and # argv > 0 , "argv must not be empty" )
opts = ( opts or { } )
assertUnbounded ( opts , "command" )
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


parts [ # parts + 1 ] = "set \"" .. name .. "=" .. tostring ( opts . env [ name ] ) .. "\""
parts [ # parts + 1 ] = "&&"
else
parts [ # parts + 1 ] = name .. "=" .. quote ( opts . env [ name ] )
end
end
end
if opts . replaceShell and not windows then
parts [ # parts + 1 ] = "exec"
end
for index , arg in ipairs ( argv ) do








parts [ # parts + 1 ] = quote ( windows and index == 1 and ( arg : gsub ( "/" , "\\" ) ) or arg )
end
local command = table . concat ( parts , " " )
if opts . cwd then
command = windows and ( "cd /d " .. quote ( opts . cwd ) .. " && " .. command )
or ( "cd " .. quote ( opts . cwd ) .. " && " .. command )
end





local testMarker = windows and rawget ( _G , "__NUPP_TEST_CMD_MARKER" ) or nil

return testMarker and ( testMarker .. command ) or command
end






function process . quote ( argument ) 
return quote ( argument )
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

function process . capture ( argv , opts ) local __nuppT35;
opts = ( opts or { } )
local tmp = nativePath ( os . tmpname ( ) )
local command = process . command ( argv , opts ) .. " >" .. quote ( tmp ) .. " 2>&1"
local code = exitCode ( os . execute ( command ) )
do const  __nuppT42= io . open ( tmp , "rb" ) ; __nuppT35=__nuppT35 or {} ; local __nuppT43=__nuppT35[2]; if not __nuppT43 then __nuppT43=function(f) do
local output = ""
if f then
output = f : read ( "*a" )
f : close ( )
end
os . remove ( tmp )

return "return",__nuppT5( code , output ) end; return "normal" end; __nuppT35[2]=__nuppT43 end; const __nuppT37,__nuppT38,__nuppT39=__nuppT10(__nuppT43,__nuppT6,__nuppT42); const __nuppT36=1; local __nuppT40={}; local __nuppT41=0; if __nuppT36>=1 and __nuppT42~=nil then  local __nuppT44,__nuppT45=__nuppT9(__nuppCleanup1,__nuppT42);  if not __nuppT44 then __nuppT41=__nuppT41+1; __nuppT40[__nuppT41]=__nuppT45 end; end; if not __nuppT37 then if __nuppT41>0 then __nuppT11(__nuppT7(__nuppT38,__nuppT40,1),0) else __nuppT11(__nuppT38,0) end end; if __nuppT41>0 then if __nuppT41>1 then __nuppT11(__nuppT7(__nuppT40[1],__nuppT40,2),0) else __nuppT11(__nuppT40[1],0) end end; if __nuppT38=="return" then  return __nuppT12(__nuppT39,1,__nuppT39.n)  end; end
end



local function boundedArgs ( argv , opts ) 
local args = process . isolatedArguments ( argv )
if opts . memoryMb and not windows then
local kilobytes = math . max ( 1 , math . floor ( opts . memoryMb * 1024 ) )
args = {
"/bin/sh" ,
"-c" ,
"ulimit -v " .. tostring ( kilobytes ) .. " 2>/dev/null || true; exec " .. process . command ( argv ) ,
}
end

return args
end





function process . captureIsolated ( argv , opts ) 
opts = ( opts or { } )
local args = boundedArgs ( argv , opts )
local native = loadProcess ( "nupp.io.process" )
local nativeOptions = {
args = args ,
cwd = opts . cwd ,
env = opts . env ,
stdin = "null" ,
stdout = "pipe" ,
stderr = "stdout" ,
timeoutMs = opts . timeoutMs ,
}
do local __nuppT48=0; local  __nuppT54 ; local __nuppT55=false ; local __nuppT49,__nuppT50,__nuppT51=__nuppT10(function() do local __nuppT56=__nuppT5( native . spawn ( nativeOptions ) ); __nuppT54= __nuppT56[1] ; __nuppT48=1;  __nuppT55=true;  local  child , problem = __nuppT56[1] , __nuppT56[2] ;
if child == nil then
error ( tostring ( problem ) , 0 )
end


local reader = child . stdout
assert ( reader ~= nil )
local chunks = { }
local cancelled = false
while true do
local moved = false
while true do
local chunk = reader : poll ( )
if chunk == nil then
do break end
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
if not running and reader : isEnded ( ) then
do break end
end
if not moved and not reader : isEnded ( ) then


local chunk = reader : poll ( 65536 , 5 )
if chunk ~= nil then
chunks [ # chunks + 1 ] = chunk
end
end
end
local exit = child : wait ( )
do (function(__nuppT57,...)  __nuppT55=false; return __nuppT57:close(...)  end)( child ) end
if cancelled then
return "return",__nuppT5( 125 , table . concat ( chunks ) )
end
if exit . timedOut then
return "return",__nuppT5( 124 , table . concat ( chunks ) )
end

return "return",__nuppT5( exit . exitCode , table . concat ( chunks ) ) end; return "normal" end,__nuppT6); local __nuppT52={}; local __nuppT53=0; if __nuppT48>=1 and __nuppT55 and __nuppT54~=nil then  local __nuppT59,__nuppT60=__nuppT9(__nuppT58,__nuppT54);  if not __nuppT59 then __nuppT53=__nuppT53+1; __nuppT52[__nuppT53]=__nuppT60 end; end; if not __nuppT49 then if __nuppT53>0 then __nuppT11(__nuppT7(__nuppT50,__nuppT52,1),0) else __nuppT11(__nuppT50,0) end end; if __nuppT53>0 then if __nuppT53>1 then __nuppT11(__nuppT7(__nuppT52[1],__nuppT52,2),0) else __nuppT11(__nuppT52[1],0) end end; if __nuppT50=="return" then  return __nuppT12(__nuppT51,1,__nuppT51.n)  end; end
end











function process . startIsolated ( argv , opts ) 
opts = ( opts or { } )
assert (
opts . timeoutMs == nil and opts . pump == nil and opts . cancelled == nil ,
"process.startIsolated leaves deadlines and cancellation to the session caller"
)
local args = boundedArgs ( argv , opts )
local native = loadProcess ( "nupp.io.process" )
local nativeOptions = {
args = args ,
cwd = opts . cwd ,
env = opts . env ,
stdin = "pipe" ,
stdout = "pipe" ,
stderr = "pipe" ,
}

return native . spawn ( nativeOptions )
end

local __nuppExportValue= process ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.process"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.process"]=__nuppExports;return __nuppExports