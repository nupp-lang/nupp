_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




















local hostreload = { }














































local function formatDiagnostics ( values ) 
local parts = { }
for _ , value in ipairs ( values or { } ) do
local record = value
local where = ""
if record . filename then
where = ("%s:%d:%d: ") : format ( tostring ( record . filename ) , record . line or 1 , record . col or 1 )
end
local code = record . code and ( tostring ( record . code ) .. ": " ) or ""
parts [ # parts + 1 ] = where .. code .. tostring ( record . msg or "" )
end
if # parts == 0 then
return nil
end

return table . concat ( parts , "\n" )
end




local function verdictOf ( result , staging ) 
local kind = tostring ( result . kind )
local verdict = "no-change"
if kind == "prepared" then
verdict = staging and "prepared" or "committed"
elseif kind == "diagnostics" then
verdict = "rejected"
elseif kind == "restart-required" then
verdict = "restart-required"
end

return verdict , require ( "nupp.runtime.hotreload" ) . generation ( ) , formatDiagnostics ( result . diagnostics )
end


local function steps (
driver
) 
local function prepare ( ) 
return verdictOf ( driver . prepare ( ) , true )
end

local function apply ( ) 
return verdictOf ( driver . apply ( ) , false )
end

local function poll ( ) 
local verdict , generation , message = prepare ( )
if verdict == "prepared" then
return apply ( )
else


return verdict , generation , message
end
end

return prepare , apply , poll
end





local active = false

local function isAbsolute ( path ) 
return path : sub ( 1 , 1 ) == "/" or path : sub ( 1 , 1 ) == "\\" or path : match ( "^%a:[/\\]" ) ~= nil
end











function hostreload . open ( entry , root , strict ) 
if active then
return nil , "a hot reload session is already open in this process"
end
local fs = require ( "nupp.compiler.fs" )
local envMod = require ( "nupp.compiler.project.env" )
local compile = require ( "nupp.tools.cli.compile" )
local watch = require ( "nupp.tools.cli.watch" )
local projectRoot = root or "."
local path = ( entry : sub ( 1 , 1 ) == "/" or entry : sub ( 1 , 1 ) == "\\" or entry : match ( "^%a:[/\\]" ) ~= nil ) and entry or fs . join ( projectRoot , entry )



local built , session , diagnostics = pcall ( watch . open , path , strict , projectRoot )
if not built then
return nil , tostring ( session )
end
if not session then
return nil , formatDiagnostics ( diagnostics ) or ( "nupp: " .. path .. " has no watch build" )
end
local opened = session
local chunk , loadError = loadstring ( opened . entryCode , "@" .. path )
if not chunk then
opened . finish ( false )

return nil , tostring ( loadError )
end
local projectEnv = envMod . new ( projectRoot )

local function checkPlain ( modulePath , env ) 
return compile . check ( modulePath , env , { strict = strict } ) ~= nil
end




local remove = require ( "nupp.compiler.runtime" ) . install ( projectEnv , opened . compileLoaded , opened . loaded , checkPlain )
local ok , value = pcall ( chunk )
if not ok then
opened . finish ( false )
remove ( )

return nil , tostring ( value )
end





local hot = _G . nupp . hotreload
if opened . prepare ( ) . kind == "prepared" then
opened . apply ( )
end
active = true

local function member ( name ) 
local current = value
for part in tostring ( name ) : gmatch ( "[^%.]+" ) do
if type ( current ) ~= "table" then
return nil
end
current = current [ part ]
end

return current
end

local prepare , apply , poll = steps ( opened )

local closed = false

local function close ( finishedWell ) 
if closed then
return
end
closed = true
active = false
opened . finish ( finishedWell ~= false )
remove ( )



require ( "nupp.runtime.hotreload" ) . retire ( )
end

return { entry = value , member = member , prepare = prepare , apply = apply , poll = poll , close = close } , nil
end







local function loadedMember ( name ) 
local parts = { }
for part in tostring ( name ) : gmatch ( "[^%.]+" ) do
parts [ # parts + 1 ] = part
end
for count = # parts - 1 , 1 , -1 do
local moduleName = table . concat ( parts , "." , 1 , count )
local loaded = package . loaded [ moduleName ]
if loaded == nil and package . preload [ moduleName ] ~= nil then
local required , value = pcall ( require , moduleName )
loaded = required and value or nil
end
if type ( loaded ) == "table" then
local current = loaded
for index = count + 1 , # parts do
if type ( current ) ~= "table" then
return nil
end
current = current [ parts [ index ] ]
end

return current
end
end

return nil
end












function hostreload . attach ( root , strict ) 
if active then
return nil , "a hot reload session is already open in this process"
end
local recorded = _G . __nuppComponentReload
if type ( recorded ) ~= "table" or next ( recorded ) == nil then
return nil , "no component in this runtime was built with reload = true"
end
local hotRuntime = require ( "nupp.runtime.hotreload" )
local hash = require ( "nupp.compiler.hash" )
local watch = require ( "nupp.tools.cli.watch" )
local session = require ( "nupp.tools.hotsession" ) . new ( root or "." , { strict = strict } )
local driver = nil





local function adopt ( name ) 
local digest = recorded [ name ]
if digest == nil then
return nil
end
local path = session . inc . modulePath ( name )
if not path then
return ("%s is running from this component, but this project has no source for it") : format ( name )
end
local built , failure = session : compile ( path , "initial" , name )
if not built then
return formatDiagnostics ( failure and failure . diagnostics ) or ("%s no longer compiles") : format ( name )
end
if hash . digest ( built . code ) ~= digest then
return ("%s has changed since this component was built; rebuild the component before attaching")

: format ( name )
end
watch . reportNotices ( session : loaded ( name , session . generation , built . manifest ) )

return nil
end

for name in pairs ( recorded ) do
if hotRuntime . loaded ( name ) then
local failure = adopt ( name )
if failure then
return nil , failure
end
end
end



local removeObserver = hotRuntime . observe ( function ( name ) 
local failure = adopt ( name )
if failure then
io . stderr : write ( "nupp: " .. failure .. "\n" )
elseif driver then
driver . resetInputs ( )
end
end )
driver = watch . driver ( session )
local prepare , apply , poll = steps ( driver )
active = true
local closed = false

local function close ( finishedWell ) 
local _ = finishedWell
if closed then
return
end
closed = true
active = false
removeObserver ( )


session : persist ( )
end

return { entry = nil , member = loadedMember , prepare = prepare , apply = apply , poll = poll , close = close } , nil
end

local __nuppExportValue= hostreload ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.hostreload"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.hostreload"]=__nuppExports;return __nuppExports