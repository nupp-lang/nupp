_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.log\0runtime\0001") };












































































































































































































































local log = { }









































log.Logger = {} log.Logger.__index = log.Logger ;_G.nupp.__reflect.link(log.Logger,__nuppT1[1],{ })



















local NAMES = { "error" , "warn" , "info" , "debug" , }
local INDEX = { off = 0 , error = 1 , warn = 2 , info = 3 , debug = 4 , }

local ffi = require ( "ffi" )
pcall ( ffi . cdef , "typedef int64_t nupp_time_t; nupp_time_t time(nupp_time_t *t);" )





local clock = os . time
do
local resolved , fn = pcall ( function ( ) 
return ffi . C . time
end )
if resolved and fn then
local null = ffi . cast ( "nupp_time_t*" , 0 )
local valid , answered = pcall ( fn , null )
local drift = valid and ( ( tonumber ( answered ) or 0 ) - os . time ( ) ) or math . huge
if drift > -2 and drift < 2 then
clock = function ( ) 
return tonumber ( fn ( null ) ) or 0
end
end
end
end

local threshold = 2
local on = { false , false , false , false , }
local target = io . stderr
local targetIsSink = false
local formatter = nil
local dateFormat = "%Y-%m-%d %H:%M:%S "
local cachedTick = -1
local cachedStamp = ""
local cachedFormat = ""
local registry = { }
local moduleViews = { }
local scopedOn = { }
local overrides = { }

local function setOn ( flags , index ) 
for i = 1 , 4 do
flags [ i ] = i <= index
end
end

local function admit ( index ) 
setOn ( on , index )
threshold = index
for name , flags in pairs ( scopedOn ) do
if overrides [ name ] == nil then
setOn ( flags , index )
end
end
end

admit ( threshold )

local function stamp ( ) 
if dateFormat == "" then
return ""
end
local tick = clock ( )
if tick ~= cachedTick or dateFormat ~= cachedFormat then
cachedTick = tick
cachedFormat = dateFormat
cachedStamp = os . date ( dateFormat )
end

return cachedStamp
end

local function emit ( severity , module , line , message ) 
if targetIsSink then
return target ( severity , module , line , message )
end
local at = stamp ( )
if formatter then
return target : write ( formatter ( severity , module , line , message , at ) , "\n" )
end
if line > 0 then
return target : write ( at , NAMES [ severity ] , " " , module , ":" , line , ": " , message , "\n" )
end

return target : write ( at , NAMES [ severity ] , " " , module , ": " , message , "\n" )
end




log . on = on



log . emit = emit

local function onFor ( name ) 
local flags = scopedOn [ name ]
if not flags then
flags = { false , false , false , false , }
setOn ( flags , overrides [ name ] or threshold )
scopedOn [ name ] = flags
end

return flags
end










function log . forModule ( module ) 
local view = moduleViews [ module ]
if not view then
view = {
on = onFor ( module ) ,
emit = function ( severity , line , message ) 
return emit ( severity , module , line , message )
end ,
}
moduleViews [ module ] = view
end

return view
end

local function named ( severity ) 
local index = INDEX [ severity ]
if index == nil then
error ( "nupp: log has no level named " .. tostring ( severity ) , 3 )
end

return index
end




local function render ( message , ... ) 
local count = select ( "#" , ... )
if count == 0 then
return message
end
local values = { ... }
if message : find ( "?" , 1 , true ) then
local pieces = { }
local index = 1
local argument = 0
while index <= # message do
local percent = message : find ( "%" , index , true )
if not percent then
pieces [ # pieces + 1 ] = message : sub ( index )
do break end
end
pieces [ # pieces + 1 ] = message : sub ( index , percent - 1 )
if message : sub ( percent + 1 , percent + 1 ) == "%" then
pieces [ # pieces + 1 ] = "%%"
index = percent + 2
else
local finish = percent + 1
local current = message : sub ( finish , finish )
while current ~= "" and ("-+ #0") : find ( current , 1 , true ) do
finish = finish + 1
current = message : sub ( finish , finish )
end
while current : find ( "[0-9]" ) do
finish = finish + 1
current = message : sub ( finish , finish )
end
if current == "." then
finish = finish + 1
current = message : sub ( finish , finish )
while current : find ( "[0-9]" ) do
finish = finish + 1
current = message : sub ( finish , finish )
end
end
argument = argument + 1
if current == "?" then
values [ argument ] = values [ argument ] : debug ( )
current = "s"
end
pieces [ # pieces + 1 ] = message : sub ( percent , finish - 1 ) .. current
index = finish + 1
end
end
message = table . concat ( pieces )
end

return string . format ( message , unpack ( values , 1 , count ) )
end







function log . error ( fmt , ... ) 
if not on [ 1 ] then
return
end
emit ( 1 , "?" , 0 , render ( fmt , ... ) )
end



function log . warn ( fmt , ... ) 
if not on [ 2 ] then
return
end
emit ( 2 , "?" , 0 , render ( fmt , ... ) )
end



function log . info ( fmt , ... ) 
if not on [ 3 ] then
return
end
emit ( 3 , "?" , 0 , render ( fmt , ... ) )
end



function log . debug ( fmt , ... ) 
if not on [ 4 ] then
return
end
emit ( 4 , "?" , 0 , render ( fmt , ... ) )
end

local NO_OP = function ( ) 
end

local function writer ( severity ) 
return function ( self , message , ... ) 
return emit ( severity , self . name , 0 , render ( message , ... ) )
end
end

local WRITE = { writer ( 1 ) , writer ( 2 ) , writer ( 3 ) , writer ( 4 ) , }

local function loggerEnabled ( self , level ) 
local index = named ( level )

return index > 0 and self . on [ index ] or false
end

local function stampLogger ( logger ) 
logger . error = logger . on [ 1 ] and WRITE [ 1 ] or NO_OP
logger . warn = logger . on [ 2 ] and WRITE [ 2 ] or NO_OP
logger . info = logger . on [ 3 ] and WRITE [ 3 ] or NO_OP
logger . debug = logger . on [ 4 ] and WRITE [ 4 ] or NO_OP
end

local function restamp ( ) 
for _ , logger in pairs ( registry ) do
stampLogger ( logger )
end
end
















function log . named ( name ) 
if type ( name ) ~= "string" then
error ( "nupp: log name must be a string" , 2 )
end
local logger = registry [ name ]
if not logger then
logger = { name = name , on = onFor ( name ) , enabled = loggerEnabled , }
stampLogger ( logger )
registry [ name ] = logger
end

return logger
end




function log . level ( ) 
return ( NAMES [ threshold ] or "off" )
end






function log . setLevel ( level ) 
local previous = ( NAMES [ threshold ] or "off" )
admit ( named ( level ) )
restamp ( )

return previous
end

local function moduleName ( name ) 
if type ( name ) ~= "string" then
error ( "nupp: log module name must be a string" , 3 )
end

return name
end







function log . moduleLevel ( name ) 
return ( NAMES [ overrides [ moduleName ( name ) ] or threshold ] or "off" )
end












function log . setModuleLevel ( name , level ) 
local previous = log . moduleLevel ( moduleName ( name ) )
if level == "inherit" then
overrides [ name ] = nil
setOn ( onFor ( name ) , threshold )
else
local index = named ( level )
overrides [ name ] = index
setOn ( onFor ( name ) , index )
end
local logger = registry [ name ]
if logger then
stampLogger ( logger )
end

return previous
end





function log . enabled ( level ) 
local index = named ( level )

return index > 0 and on [ index ] or false
end




function log . sink ( ) 
return target
end






function log . setSink ( next ) 


local taken = next
local previous = target
if type ( taken ) == "function" then
target = taken
targetIsSink = true
elseif ( type ( taken ) == "table" or type ( taken ) == "userdata" ) and type ( taken . write ) == "function" then
target = taken
targetIsSink = false
else
error ( "nupp: log target must be a sink function or a file" , 2 )
end
restamp ( )

return previous
end




function log . formatter ( ) 
return formatter
end






function log . setFormatter ( next ) 
if next ~= nil and type ( next ) ~= "function" then
error ( "nupp: log formatter must be a function" , 2 )
end
local previous = formatter
formatter = next

return previous
end




function log . timestamp ( ) 
return stamp ( )
end




function log . timestampFormat ( ) 
return dateFormat
end






function log . setTimestampFormat ( next ) 
if type ( next ) ~= "string" then
error ( "nupp: log timestamp format must be a string" , 2 )
end
local previous = dateFormat
dateFormat = next
cachedTick = -1

return previous
end





function log . levelName ( severity ) 
return ( NAMES [ severity ] or "off" )
end

local __nuppExportValue= log ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.log"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.log"]=__nuppExports;return __nuppExports