_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT9={}; local function __nuppT6(...) return {n=select("#",...),...} end; local __nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT7(value) return value end; local function __nuppT8(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT15({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT16(v.primary) for _,reason in __nuppT17(v.suppressed) do text=text.."\ncleanup: "..__nuppT16(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()














local text = { }
































function text . uriToPath ( uri ) 
local rest = uri : match ( "^[Ff][Ii][Ll][Ee]:(.*)$" )
local path = rest or uri
if rest then
local authority , after = rest : match ( "^//([^/]*)(.*)$" )
if authority then
local host = authority : lower ( )
path = ( host == "" or host == "localhost" ) and after or "//" .. authority .. after
end
end
path = path : gsub ( "%%(%x%x)" , function ( hex ) 
return string . char ( tonumber ( hex , 16 ) or 0 )
end )
if path : match ( "^/[A-Za-z]:[/\\]" ) or path : match ( "^/[A-Za-z]:$" ) then
path = path : sub ( 2 )
end

return path
end









function text . pathToUri ( path ) 
if path : match ( "^[A-Za-z]:[/\\]" ) or path : match ( "^\\\\" ) then
path = path : gsub ( "\\" , "/" )
end
local prefix = path : match ( "^[A-Za-z]:/" ) and "/" or ""
local host , rest = path : match ( "^//([^/]+)(/.*)$" )
if host then
prefix , path = "//" .. host , rest
end
local encoded = path : gsub ( "[^%w%-%._~/:]" , function ( ch ) 
return ("%%%02X") : format ( ch : byte ( ) )
end )

local absolute = host or path : sub ( 1 , 1 ) == "/" or prefix ~= ""

return ( absolute and not host and "file://" or "file:" ) .. prefix .. encoded
end

function text . readFile ( path ) 
do const  __nuppT24= io . open ( path , "rb" ) ; local __nuppT25=__nuppT9[1]; if not __nuppT25 then __nuppT25=function(f) do
if not f then
return "return",__nuppT6( nil )
end
local source = f : read ( "*a" )
f : close ( )

return "return",__nuppT6( source ) end; return "normal" end; __nuppT9[1]=__nuppT25 end; const __nuppT19,__nuppT20,__nuppT21=__nuppT11(__nuppT25,__nuppT7,__nuppT24); const __nuppT18=1; local __nuppT22={}; local __nuppT23=0; if __nuppT18>=1 and __nuppT24~=nil then  local __nuppT26,__nuppT27=__nuppT10(__nuppCleanup1,__nuppT24);  if not __nuppT26 then __nuppT23=__nuppT23+1; __nuppT22[__nuppT23]=__nuppT27 end; end; if not __nuppT19 then if __nuppT23>0 then __nuppT12(__nuppT8(__nuppT20,__nuppT22,1),0) else __nuppT12(__nuppT20,0) end end; if __nuppT23>0 then if __nuppT23>1 then __nuppT12(__nuppT8(__nuppT22[1],__nuppT22,2),0) else __nuppT12(__nuppT22[1],0) end end; if __nuppT20=="return" then  return __nuppT13(__nuppT21,1,__nuppT21.n)  end; end
end


function text . utf8Char ( source , offset ) 
local first = source : byte ( offset )
if not first or first < 128 then
return 1 , 1
end
local len = first < 224 and 2 or first < 240 and 3 or 4

return len , len == 4 and 2 or 1
end





local cachedSource = nil
local cachedStarts = { }

local function startsOf ( source ) 
if source ~= cachedSource then
cachedSource , cachedStarts = source , text . lineStarts ( source )
end

return cachedStarts
end


local function lineOf ( starts , offset ) 
local low , high = 1 , # starts
while low < high do
local middle = _G.math.floor(( ( low + high + 1 ) ) / ( 2 ))
if starts [ middle ] <= offset then
low = middle
else
high = middle - 1
end
end

return low - 1 , starts [ low ]
end

function text . positionAtOffset ( source , offset ) 
local line , pos = lineOf ( startsOf ( source ) , offset )
local character = 0
while pos < offset and pos <= # source do
local bytes , units = text . utf8Char ( source , pos )
character , pos = character + units , pos + bytes
end

return { line = line , character = character }
end

function text . offsetAtPosition ( source , target ) 
local pos = startsOf ( source ) [ target . line + 1 ]
if not pos then
return nil
end
local character = 0
while pos <= # source and source : byte ( pos ) ~= 10 and source : byte ( pos ) ~= 13 and character < target . character do
local bytes , units = text . utf8Char ( source , pos )
character , pos = character + units , pos + bytes
end

return pos
end


function text . spanRange ( source , from , to ) 
return { start = text . positionAtOffset ( source , from ) , [ "end" ] = text . positionAtOffset ( source , to ) }
end

function text . tokenRange ( source , tok ) 
return text . spanRange ( source , tok . offset , tok . offset + # tok . text )
end






function text . splitLines ( source ) 
local lines = { }
local starts = text . lineStarts ( source )
for index = 1 , # starts - 1 do
lines [ # lines + 1 ] = source : sub ( starts [ index ] , starts [ index + 1 ] - 1 )
end
if starts [ # starts ] <= # source then
lines [ # lines + 1 ] = source : sub ( starts [ # starts ] )
end

return lines
end




function text . lineStarts ( source ) 
local starts = { 1 }
local pos = 1
while pos <= # source do
local byte = source : byte ( pos )
if byte == 10 then
starts [ # starts + 1 ] = pos + 1
elseif byte == 13 then
if source : byte ( pos + 1 ) == 10 then
pos = pos + 1
end
starts [ # starts + 1 ] = pos + 1
end
pos = pos + 1
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
for distance = 1 , 64 do
for di = 0 , distance do
local dj = distance - di
if before [ i + di ] ~= nil and before [ i + di ] == after [ j + dj ] then
skipBefore , skipAfter = di , dj
do break end
end
end
if skipBefore then
do break end
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

local __nuppExportValue= text ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.lsp.text"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.lsp.text"]=__nuppExports;return __nuppExports