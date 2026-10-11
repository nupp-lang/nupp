_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.tools.build.progress\0runtime\0001") };




























local ansi = require ( "nupp.cli" )

local progress = { }























































































progress . SLOWEST = 5








local function makeClock ( ) 
local coarse = function ( ) 
return os . clock ( ) * 1000
end
local loaded , ffi = pcall ( require , "ffi" )
if not loaded then
return coarse
end





pcall ( ffi . cdef , "int gettimeofday(void *, void *);" )
local holder = ffi . new ( "int64_t[2]" )




local buffer = ffi . cast ( "void *" , holder )

local function read ( ) 


do
ffi . C . gettimeofday ( buffer , nil )
end

return ( tonumber ( holder [ 0 ] ) or 0 ) * 1000 + ( tonumber ( holder [ 1 ] ) or 0 ) / 1000
end






local sampled , sample = pcall ( read )
if not sampled or type ( sample ) ~= "number" or sample < 1400000000000 or sample > 4000000000000 then
return coarse
end

return read
end

local clock = makeClock ( )




function progress . now ( ) 
return clock ( )
end



function progress . duration ( milliseconds ) 
if milliseconds < 1000 then
return string . format ( "%dms" , math . floor ( milliseconds + 0.5 ) )
end

return string . format ( "%.1fs" , milliseconds / 1000 )
end



local function resolve ( mode , stream ) 
local wanted = mode or os . getenv ( "NUPP_PROGRESS" ) or "auto"
if wanted == "never" or wanted == "0" then
return false
end
if wanted == "always" or wanted == "1" then
return true
end

return ansi . isTerminal ( stream )
end




local function width ( ) 
local columns = tonumber ( os . getenv ( "COLUMNS" ) or "" ) or 80
if columns < 20 then
columns = 20
end

return math . floor ( columns ) - 1
end





progress.Reporter = {} progress.Reporter.__index = progress.Reporter



























































function progress.Reporter:at(activity) 
local moment = clock ( )
self . spans [ self . activity ] = ( self . spans [ self . activity ] or 0 ) + ( moment - self . since )
if self . spans [ activity ] == nil then
self . spans [ activity ] = 0
self . order [ # self . order + 1 ] = activity
end
self . activity , self . since = activity , moment
end


function progress.Reporter:expect(total) 
self . total = total
end






function progress.Reporter:step(label) 
if not self . showing then
return
end
local moment = clock ( )
if moment - self . paintedAt < ( self . rewriting and 40 or 500 ) then
return
end
self . paintedAt = moment





local counted = ""
if self . total > 0 then
local at = math . min ( self . done + 1 , self . total )
counted = ( "[%3d%%] [%d/%d] " ) : format ( math . floor ( at / self . total * 100 ) , at , self . total )
end
local text = "  " .. counted .. label
if # text > self . columns then
text = text : sub ( 1 , self . columns )
end
if self . rewriting then
self . stream : write ( "\r\27[2K" .. self . style . faint ( text ) )
self . onScreen = true
else
self . stream : write ( text .. "\n" )
end
end



function progress.Reporter:clear() 
if self . onScreen then
self . stream : write ( "\r\27[2K" )
self . onScreen = false
end
end



function progress.Reporter:spent(module, milliseconds) 
if self . moduleMs [ module ] == nil then
self . moduleOrder [ # self . moduleOrder + 1 ] = module
end
self . moduleMs [ module ] = ( self . moduleMs [ module ] or 0 ) + milliseconds
end




function progress.Reporter:resolved() 
self . done = self . done + 1
end



function progress.Reporter:counted(compiled, reused) 
self . compiled , self . reused = compiled , reused
end



function progress.Reporter:addSpecialized(count) 
self . specialized = self . specialized + count
end


function progress.Reporter:aotCounted(facts) 
self . aotFacts = facts
end


function progress.Reporter:parallelCounted(facts) 
self . parallelFacts = facts
end



function progress.Reporter:charging(name) 
local previous = self . checking
self . checking = name

return previous
end


function progress.Reporter:timing() 
local phases = { }
for _ , name in ipairs ( self . order ) do
local milliseconds = self . spans [ name ] or 0
if milliseconds >= 1 then
phases [ # phases + 1 ] = { name = name , durationMs = milliseconds }
end
end
table . sort ( phases , function ( a , b ) 
return a . durationMs > b . durationMs
end )
local modules = { }
for _ , name in ipairs ( self . moduleOrder ) do
modules [ # modules + 1 ] = { module = name , durationMs = self . moduleMs [ name ] or 0 }
end
table . sort ( modules , function ( a , b ) 
return a . durationMs > b . durationMs
end )
local slowest = { }
for index = 1 , math . min ( progress . SLOWEST , # modules ) do


if modules [ index ] . durationMs >= 1 then
slowest [ # slowest + 1 ] = modules [ index ]
end
end

return {
totalMs = clock ( ) - self . startedAt ,
compiledModules = self . compiled ,
reusedModules = self . reused ,
specializedBodies = self . specialized ,
optimizerFacts = self . optimizerFacts ,
phases = phases ,
slowest = slowest ,
aot = self . aotFacts ,
parallel = self . parallelFacts ,
}
end




function progress.Reporter:finish(verb, what) 
self : at ( "other" )
if not self . showing then
return
end
self : clear ( )
local measured = self : timing ( )
local style = self . style
local subject = what and ( " " .. what ) or ""
local counts
if measured . compiledModules == 0 then
counts = ( "%d module%s reused" ) : format ( measured . reusedModules , measured . reusedModules == 1 and "" or "s" )
else
counts = ( "%d compiled, %d reused" ) : format ( measured . compiledModules , measured . reusedModules )
end
if measured . specializedBodies > 0 then
counts = counts .. ( ", %d specialized" ) : format ( measured . specializedBodies )
end
if measured . parallel ~= nil then
if measured . parallel . mode == "parallel" then
counts = counts .. ( ", %d workers" ) : format ( measured . parallel . workers )
elseif measured . parallel . mode == "serial-fallback" then
counts = counts .. ", serial fallback"
end
end
local success = ansi . severity ( style , "help" )
local detail = ansi . severity ( style , "note" )
self . stream : write (
(
"%s in %s: %s\n"
) : format ( success ( verb .. subject ) , style . strong ( progress . duration ( measured . totalMs ) ) , detail ( counts ) )
)



local parts = { }
for _ , span in ipairs ( measured . phases ) do
if span . durationMs >= 5 and span . durationMs >= measured . totalMs / 50 then
parts [ # parts + 1 ] = span . name .. " " .. progress . duration ( span . durationMs )
end
end
if # parts > 0 then
self . stream : write ( style . faint ( "  " .. table . concat ( parts , "  " ) ) .. "\n" )
end



if # measured . slowest == 0 or measured . totalMs < 1000 then
return
end
self . stream : write ( style . faint ( "  slowest" ) .. "\n" )
local rows = { }
for index , span in ipairs ( measured . slowest ) do
rows [ index ] = { ansi . cell ( span . module ) , ansi . cell ( progress . duration ( span . durationMs ) ) }
end


ansi . writeTable (
self . stream ,
{
columns = {
{ heading = "module" , paint = style . faint } ,
{ heading = "took" , align = "right" , paint = style . faint , }
} ,
rows = rows ,
showHeading = false ,
indent = "    " ,
}
)
end ;_G.nupp.__reflect.link(progress.Reporter,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.cli.internal.terminal\0runtime\0001","nupp.cli.internal.terminal") })





function progress . new ( mode , stream ) 
local target = stream or io . stderr
local showing = resolve ( mode , target )
local started = clock ( )

return ( _G.setmetatable({ stream =
target ,  showing =
showing ,  rewriting =


showing and ansi . colorEnabled ( target ) ,  style =
ansi . style ( target ) ,  startedAt =
started ,  activity =
"other" ,  since =
started ,  spans =
{ other = 0 } ,  order =
{ "other" } ,  moduleMs =
{ } ,  moduleOrder =
{ } ,  total =
0 ,  done =
0 ,  compiled =
0 ,  reused =
0 ,  specialized =
0 ,  aotFacts =
nil ,  parallelFacts =
nil ,  checking =
"check" ,  paintedAt =
0 ,  onScreen =
false ,  columns =
width ( ) }, progress.Reporter) )

end

local __nuppExportValue= progress ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.progress"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.progress"]=__nuppExports;return __nuppExports