_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);

























local ansi = require ( "nupp.compiler.ansi" )

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
if not sampled or type ( sample ) ~= "number" or sample < 1.4e12 or sample > 4.0e12 then
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
local counted = self . total > 0 and ( "[%d/%d] " ) : format ( math . min ( self . done + 1 , self . total ) , self . total ) or ""
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
phases = phases ,
slowest = slowest ,
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
self . stream : write (
( "%s%s in %s: %s\n" ) : format ( verb , subject , style . strong ( progress . duration ( measured . totalMs ) ) , counts )
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
local widest = 0
for _ , span in ipairs ( measured . slowest ) do
if # span . module > widest then
widest = # span . module
end
end
self . stream : write ( style . faint ( "  slowest" ) .. "\n" )
for _ , span in ipairs ( measured . slowest ) do
self . stream : write (
style . faint (
( "    %-" .. widest .. "s  %s" ) : format ( span . module , progress . duration ( span . durationMs ) )
) .. "\n"
)
end
end





function progress . new ( mode , stream )
local target = stream or io . stderr
local showing = resolve ( mode , target )
local started = clock ( )

return setmetatable({ stream =
target ,  showing =
showing ,  rewriting =


showing and ansi . enabled ( target ) ,  style =
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
0 ,  paintedAt =
0 ,  onScreen =
false ,  columns =
width ( ) }, progress.Reporter)

end

return progress
