_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.io.internal.lines"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local newLines;__nuppExports["newLines"]=function(...) return newLines(...) end;



const bytes = require ( "nupp.io.internal.bytes" )

local DEFAULT_READ = 65536
local positive = bytes . validatePositive








local Lines = {}
















local LineReader = {} LineReader.__index = LineReader







function LineReader:isReleased() 
return self . _closed
end

function LineReader:read() 
if self . _closed then
return nil , "the line reader is closed"
end
while true do
const found = self . _held : find ( "\n" , self . _at + 1 , true )
if found ~= nil then
local line = self . _held : sub ( self . _at + 1 , found - 1 )
if line : sub ( - 1 ) == "\r" then
line = line : sub ( 1 , - 2 )
end







if # line > self . _limit then
return nil , "a line was longer than the limit"
end
self . _at = found
if self . _at >= # self . _held then
self . _held = ""
self . _at = 0
end

return line
end







local grace = self . _held : sub ( - 1 ) == "\r" and 1 or 0
if # self . _held - self . _at > self . _limit + grace then
return nil , "a line was longer than the limit"
end
if self . _ended then
if self . _at >= # self . _held then
return nil
end
const rest = self . _held : sub ( self . _at + 1 )



if # rest > self . _limit then
return nil , "a line was longer than the limit"
end
self . _held = ""
self . _at = 0

return rest
end
local held = # self . _held - self . _at
local room = self . _limit - held
local wanted = ( room < DEFAULT_READ - 2 and room + 2 or DEFAULT_READ )
const chunk , why = self . _source : read ( wanted )
if chunk == nil then
return nil , why
end
if # chunk > wanted then
error ( "nupp: io.Reader returned more bytes than requested" , 2 )
end
if # chunk == 0 then
self . _ended = true
else
if self . _at > 0 then
self . _held = self . _held : sub ( self . _at + 1 )
self . _at = 0
end
self . _held = self . _held .. chunk
end
end
end

function LineReader:close() 
self . _closed = true
self . _source : close ( )
end












newLines=function ( source , limit ) 
const bound = positive ( limit or 65536 , "io.newLines limit" , 2 )

return ( _G.setmetatable({ _source =  source ,  _held =  "" ,  _at =  0 ,  _limit =  bound ,  _closed =  false ,  _ended =  false }, LineReader) )
end ;__nuppExports["newLines"]=newLines
 end);if not __nuppOk then package.loaded["nupp.io.internal.lines"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.internal.lines"]=__nuppExports;return __nuppExports