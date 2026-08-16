_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








local lexer = require ( "nupp.compiler.lexer" )

local text = { }























function text . uriToPath ( uri )
local path = uri : gsub ( "^file://" , "" )
path = path : gsub ( "%%(%x%x)" , function ( hex )
return string . char ( tonumber ( hex , 16 ) or 0 )
end )

return path
end

function text . pathToUri ( path )
return "file://" .. path : gsub ( "[^%w%-%._~/:]" , function ( ch )
return ( "%%%02X" ) : format ( ch : byte ( ) )
end )
end

function text . readFile ( path )
local f = io . open ( path , "rb" )
if not f then
return nil
end
local source = f : read ( "*a" )
f : close ( )

return source
end


function text . utf8Char ( source , offset )
local first = source : byte ( offset )
if not first or first < 0x80 then
return 1 , 1
end
local len = first < 0xE0 and 2 or first < 0xF0 and 3 or 4

return len , len == 4 and 2 or 1
end

function text . positionAtOffset ( source , offset )
local line , character , pos = 0 , 0 , 1
while pos < offset and pos <= # source do
if source : byte ( pos ) == 10 then
line , character , pos = line + 1 , 0 , pos + 1
else
local bytes , units = text . utf8Char ( source , pos )
character , pos = character + units , pos + bytes
end
end

return { line = line , character = character }
end

function text . offsetAtPosition ( source , target )
local line , character , pos = 0 , 0 , 1
while pos <= # source and line < target . line do
if source : byte ( pos ) == 10 then
line = line + 1
end
pos = pos + 1
end
if line ~= target . line then
return nil
end
while pos <= # source and source : byte ( pos ) ~= 10 and character < target . character do
local bytes , units = text . utf8Char ( source , pos )
character , pos = character + units , pos + bytes
end

return pos
end

function text . tokenRange ( source , tok )
return {
start = text . positionAtOffset ( source , tok . offset ) ,
[ "end" ] = text . positionAtOffset ( source , tok . offset + # tok . text ) ,
}
end



function text . splitLines ( source )
local lines = { }
local pos = 1
while pos <= # source do
local stop = source : find ( "\n" , pos , true )
if stop then
lines [ # lines + 1 ] = source : sub ( pos , stop )
pos = stop + 1
else
lines [ # lines + 1 ] = source : sub ( pos )
break
end
end

return lines
end



function text . lineStarts ( source )
local starts = { 1 }
for pos = 1 , # source do
if source : byte ( pos ) == 10 then
starts [ # starts + 1 ] = pos + 1
end
end

return starts
end




local RESYNC = 64



function text . lineHunks ( before , after )
local hunks = { }
local i , j = 1 , 1
while i <= # before or j <= # after do
if before [ i ] ~= nil and before [ i ] == after [ j ] then
i , j = i + 1 , j + 1
else
local skipBefore , skipAfter = nil , nil
for distance = 1 , RESYNC do
for di = 0 , distance do
local dj = distance - di
if before [ i + di ] ~= nil and before [ i + di ] == after [ j + dj ] then
skipBefore , skipAfter = di , dj
break
end
end
if skipBefore then
break
end
end
if not skipBefore then
skipBefore , skipAfter = # before - i + 1 , # after - j + 1
end
local lines = { }


for index = j , j + ( skipAfter ) - 1 do
lines [ # lines + 1 ] = after [ index ]
end
hunks [ # hunks + 1 ] = { from = i , to = i + skipBefore , lines = lines }
i , j = i + skipBefore , j + ( skipAfter )
end
end

return hunks
end

return text
