_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.cli.internal.table"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local annotated;__nuppExports["annotated"]=function(...) return annotated(...) end;local painted;__nuppExports["painted"]=function(...) return painted(...) end;local render;__nuppExports["render"]=function(...) return render(...) end;local text;__nuppExports["text"]=function(...) return text(...) end;local write;__nuppExports["write"]=function(...) return write(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.cli.internal.table\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.cli.internal.table\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.cli.internal.table\0runtime\0003") };


























local Cell = {} Cell.__index = Cell ;_G.nupp.__reflect.link(Cell,__nuppT1[1],{ }) ;__nuppExports["Cell"]=Cell


















local Column = {} Column.__index = Column ;_G.nupp.__reflect.link(Column,__nuppT1[2],{ }) ;__nuppExports["Column"]=Column
















local Options = {} Options.__index = Options ;_G.nupp.__reflect.link(Options,__nuppT1[3],{ __nuppT1[2] , __nuppT1[1] , _G.nupp.__reflect.reference("nupp.cli.internal.terminal\0runtime\0001","nupp.cli.internal.terminal") }) ;__nuppExports["Options"]=Options






























local FADE = 8



local MARKER = "..."



local NARROWEST = 24


text=function ( value ) 
return ( _G.setmetatable({ text =  value }, Cell) )
end ;__nuppExports["text"]=text


painted=function ( value , paint ) 
return ( _G.setmetatable({ text =  value ,  paint =  paint }, Cell) )
end ;__nuppExports["painted"]=painted


annotated=function ( value , note , paint ) 
return ( _G.setmetatable({ text =  value ,  paint =  paint ,  note =  note }, Cell) )
end ;__nuppExports["annotated"]=annotated

local function identity ( value ) 
return value
end






render=function ( options ) 
const columns = options . columns
const rows = options . rows
if # rows == 0 then
return ""
end
const gap = options . gap or "  "
const indent = options . indent or ""
const showHeading = options . showHeading ~= false
const styles = options . style
const headingPaint = options . headingPaint or ( styles ~= nil and styles . heading or identity )

local widths = { }
for index , column in ipairs ( columns ) do
local width = column . minimumWidth or 0
if showHeading and # column . heading > width then
width = # column . heading
end
widths [ index ] = width
end
for _ , row in ipairs ( rows ) do
for index = 1 , # columns do
const cell = row [ index ]
if cell ~= nil then
const measured = # cell . text + ( cell . note ~= nil and # cell . note or 0 )
if measured > widths [ index ] then
widths [ index ] = measured
end
end
end
end

const notePaint = styles ~= nil and styles . faint or identity



if options . width ~= nil and # columns > 1 then
local before = # indent
for index = 1 , # columns - 1 do
before = before + widths [ index ] + # gap
end
const room = ( options . width ) - before
if room >= NARROWEST and widths [ # columns ] > room then
widths [ # columns ] = room
end
end








local function cut ( value , room , paint ) 
if room <= # MARKER then
return paint ( value : sub ( 1 , room ) )
end
const kept = room - # MARKER
local tail = FADE
if tail > kept then
tail = kept
end

return paint ( value : sub ( 1 , kept - tail ) ) .. notePaint ( value : sub ( kept - tail + 1 , kept ) .. MARKER )
end






local function laid ( cell , index , column , paint ) 
const value = cell ~= nil and cell . text or ""
const note = cell ~= nil and cell . note or nil
const align = column . align
const noteWidth = note ~= nil and # note or 0
const missing = widths [ index ] - # value - noteWidth
if missing < 0 then



if noteWidth > 0 and noteWidth <= widths [ index ] then
return cut (
value ,
widths [ index ] - noteWidth ,
paint
) .. ( cell ~= nil and cell . notePaint or notePaint ) ( note )
end

return cut ( value , widths [ index ] , paint )
end
local padding = ""
if missing > 0 and ( index < # columns or align == "right" ) then
padding = ( " " ) : rep ( missing )
end
local body = paint ( value )
if note ~= nil then
body = body .. ( cell ~= nil and cell . notePaint or notePaint ) ( note )
end
if align == "right" then
return padding .. body
end

return body .. padding
end

local lines = { }
if showHeading then
local parts = { }
for index , column in ipairs ( columns ) do
parts [ index ] = laid ( _G.setmetatable({ text =  column . heading }, Cell) , index , column , headingPaint )
end
lines [ # lines + 1 ] = indent .. table . concat ( parts , gap )
end
for _ , row in ipairs ( rows ) do
local parts = { }
for index , column in ipairs ( columns ) do
const cell = row [ index ]
parts [ index ] = laid ( cell , index , column , cell ~= nil and cell . paint or column . paint or identity )
end
lines [ # lines + 1 ] = indent .. table . concat ( parts , gap )
end
if # lines == 0 then
return ""
end

return table . concat ( lines , "\n" ) .. "\n"
end ;__nuppExports["render"]=render





write=function ( stream , options ) 
local fitted = options
if options . width == nil then



const console = require ( "nupp.cli.internal.terminal" )
const available = console . isTerminal ( stream ) and console . columns ( stream ) or nil
if available ~= nil then
fitted = _G.setmetatable({ columns =
options . columns ,  rows =
options . rows ,  style =
options . style ,  headingPaint =
options . headingPaint ,  gap =
options . gap ,  indent =
options . indent ,  showHeading =
options . showHeading ,  width =
available }, Options)

end
end
const rendered = render ( fitted )
if rendered ~= "" then
stream : write ( rendered )
end
end ;__nuppExports["write"]=write
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Cell]="nupp.cli.internal.table\0Cell";__nuppWorkerRecords[Column]="nupp.cli.internal.table\0Column";__nuppWorkerRecords[Options]="nupp.cli.internal.table\0Options"; end);if not __nuppOk then package.loaded["nupp.cli.internal.table"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.cli.internal.table"]=__nuppExports;return __nuppExports