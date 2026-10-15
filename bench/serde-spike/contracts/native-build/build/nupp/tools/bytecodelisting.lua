_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()















local listing = { }

























































listing . BOUNDARY = "__nupp_bc_preamble_boundary_v1__"

local function asis ( text ) 
return text
end




listing . TRUNCATED = "~"

local function fit ( text , column ) 
local measure = require ( "nupp.tools.fmt.displaywidth" )
local kept = measure . clip ( text , column )
if kept == text then
return text
end

return measure . clip ( text , column - # listing . TRUNCATED ) .. listing . TRUNCATED
end

local PLAIN = {
source = function ( _ , text , column ) 
return fit ( text , column )
end ,
gutter = asis ,
instruction = asis ,
note = function ( text , _ ) 
return text
end ,
header = asis ,
}










function listing . boundary ( functions ) 
for _ , fn in ipairs ( functions ) do
for _ , ins in ipairs ( fn . instructions ) do
if ins . text : find ( listing . BOUNDARY , 1 , true ) then
return fn , ins . pc
end
end
end

return nil , nil
end



local DIVIDER = " | "




local MIN_SOURCE = 24




local DEFAULT_WIDTH = 100



local CODE_RESERVE = 44

local function split ( source ) 
local lines = { }
for line in ( source .. "\n" ) : gmatch ( "(.-)\n" ) do
lines [ # lines + 1 ] = line
end

return lines
end



local function earlier ( left , right ) 
if left . order ~= right . order then
return left . order < right . order
end

return ( left . ins . pc or 0 ) < ( right . ins . pc or 0 )
end














function listing . group (
functions ,
boundaryFunction ,
boundaryPc
) 
local generatedSlots = { }
if boundaryFunction ~= nil and boundaryPc ~= nil then
for _ , ins in ipairs ( boundaryFunction . instructions ) do
if ins . pc < ( boundaryPc ) and ins . op == "FNEW" then
local slot = tonumber ( ins . text : match ( "FNEW%s+%d+%s+(%d+)" ) )
if slot then
generatedSlots [ math . floor ( slot ) ] = true
end
end
end
end






local hidden = { }
local boundaryIndex , boundaryDepth = nil , 0
for index , fn in ipairs ( functions ) do
if fn == boundaryFunction then
boundaryIndex = index
boundaryDepth = math . floor ( tonumber ( fn . depth ) or 0 )
do break end
end
end
if boundaryIndex ~= nil then
local hidingBranch = false
for index = ( boundaryIndex ) + 1 , # functions do
local fn = functions [ index ]
local depth = math . floor ( tonumber ( fn . depth ) or 0 )
if depth <= boundaryDepth then
do break end
elseif depth == boundaryDepth + 1 then
local slot = math . floor ( tonumber ( fn . slot ) or -1 )
hidingBranch = generatedSlots [ slot ] == true
end
if hidingBranch then
hidden [ fn ] = true
end
end
end

local byLine = { }
local preamble = { }
local built = 0
local order = 0
for _ , fn in ipairs ( functions ) do
order = order + 1
local generated = hidden [ fn ] == true
if generated then
built = built + 1
end
for _ , ins in ipairs ( fn . instructions ) do
local isBoundary = fn == boundaryFunction and boundaryPc ~= nil and ins . pc == boundaryPc
local isPreamble = fn == boundaryFunction and boundaryPc ~= nil and ins . pc < ( boundaryPc )
if isBoundary then

elseif isPreamble or generated then
preamble [ # preamble + 1 ] = ins
else
local at = math . floor ( tonumber ( ins . line ) or 0 )
if at >= 1 then
local bucket = byLine [ at ] or { }
bucket [ # bucket + 1 ] = { ins = ins , order = order }
byLine [ at ] = bucket
end
end
end
end

return byLine , preamble , built
end


























function listing . render ( functions , source , opts ) 
local settings = opts or { }
local palette = settings . palette or PLAIN
local sourceLines = split ( source )
local byLine , preamble , built = listing . group ( functions , settings . boundaryFunction , settings . boundaryPc )

local out = { }
local mappings = { }

local function write ( text , from , role ) 
out [ # out + 1 ] = text
if from ~= nil and role ~= nil and from >= 1 then
mappings [ # mappings + 1 ] = { generatedLine = # out , sourceLine = from , role = role }
end
end

local last = # sourceLines
for at in pairs ( byLine ) do
if at > last then
last = at
end
end



while last > 1 and # ( byLine [ last ] or { } ) == 0 and not ( sourceLines [ last ] or "" ) : match ( "%S" ) do
last = last - 1
end





local width = require ( "nupp.tools.fmt.displaywidth" ) . displayWidth
local numbers = math . max ( # tostring ( last ) , 3 )
local widest , widestCode = 0 , 0
for at = 1 , last do
local text = sourceLines [ at ]
if text ~= nil then
widest = math . max ( widest , math . floor ( width ( text ) ) )
end
for _ , held in ipairs ( byLine [ at ] or { } ) do
widestCode = math . max ( widestCode , math . floor ( width ( held . ins . text ) ) )
end
end











local reserve = math . min ( widestCode , 44 )
local available = ( settings . width or 100 ) - numbers - 6 - reserve
local column = math . floor ( math . min ( widest , math . max ( 24 , available ) ) )

local function gutter ( at , trailing ) 
local label = at ~= nil and ( "%" .. tostring ( numbers ) .. "d" ) : format ( at ) or (" ") : rep ( numbers )

return palette . gutter ( label .. ( trailing and " | " or ( (" | ") : gsub ( "%s+$" , "" ) ) ) )
end

local function code ( ins ) 
if ins == nil then
return ""
end



local text = palette . instruction ( ( ins . text : gsub ( "%s+$" , "" ) ) )
if ins . traceReason and settings . check then
if ins . unrecordable then
local note = "  <-- this loop never compiles: " .. ins . unrecordable
text = text .. palette . note ( note .. (" [%s, must-reach]") : format ( ins . traceReason ) , true )
else
text = text .. palette . note (
("  <-- %s: %s [may-reach]")

: format (
ins . traceClass == "risk" and "recording risk" or "this path aborts recording" ,
ins . traceReason
) ,
false
)
end
end

return text
end






local function row ( at , text , ins ) 
local shown = text or ""
local right = code ( ins )




if shown == "" and right == "" then
return gutter ( at , false )
end
local fitted = palette . source ( at or 0 , shown , column )
if right == "" then
return gutter ( at , true ) .. fitted
end
local occupied = math . min ( math . floor ( width ( shown ) ) , column )

return gutter ( at , true ) .. fitted .. (" ") : rep ( column - occupied ) .. palette . gutter ( " | " ) .. right
end

for at = 1 , last do
local bucket = byLine [ at ] or { }
table . sort ( bucket , earlier )
write ( row ( at , sourceLines [ at ] , bucket [ 1 ] and bucket [ 1 ] . ins or nil ) , at , "source" )
for index = 2 , # bucket do
write ( row ( nil , nil , bucket [ index ] . ins ) , at , "exact" )
end
end




if # preamble > 0 then
local summary = ("-- %d instructions of runtime preamble") : format ( # preamble )
if built > 0 then
summary = summary .. (", in %d function%s") : format ( built , built == 1 and "" or "s" )
end
write ( "" )
write ( palette . header ( summary ) , 1 , "synthetic" )
end

return table . concat ( out , "\n" ) .. "\n" , mappings
end





















function listing . aligned ( functions , source , opts ) 
local settings = opts or { }
local sourceLines = split ( source )
local byLine , preamble = listing . group ( functions , settings . boundaryFunction , settings . boundaryPc )

local out = { }
local mappings = { }

local function write ( text , from , role ) 
out [ # out + 1 ] = text
if from ~= nil and role ~= nil and from >= 1 then
mappings [ # mappings + 1 ] = { generatedLine = # out , sourceLine = from , role = role }
end
end

local function textOf ( ins ) 
local text = ins . text
if ins . traceReason and settings . check then
if ins . unrecordable then
text = text .. "   <-- this loop never compiles: " .. ins . unrecordable
text = text .. (" [%s, must-reach]") : format ( ins . traceReason )
else
text = text .. ("   <-- %s: %s [may-reach]")

: format ( ins . traceClass == "risk" and "recording risk" or "this path aborts recording" , ins . traceReason )
end
end

return text
end

local last = # sourceLines
for at in pairs ( byLine ) do
if at > last then
last = at
end
end

for at = 1 , last do
local bucket = byLine [ at ] or { }
table . sort ( bucket , earlier )
if # bucket == 0 then
write ( "" )
elseif # bucket == 1 then
write ( textOf ( bucket [ 1 ] . ins ) , at , "exact" )
else
write ( textOf ( bucket [ 1 ] . ins ) .. ("   -- +%d more") : format ( # bucket - 1 ) , at , "exact" )
for index = 2 , # bucket do
write ( "  " .. textOf ( bucket [ index ] . ins ) , at , "exact" )
end
end
end





if # preamble > 0 then
write ( "" )
write ( ("-- %d instructions of runtime preamble") : format ( # preamble ) , 1 , "synthetic" )
for _ , ins in ipairs ( preamble ) do
write ( "  " .. textOf ( ins ) , 1 , "synthetic" )
end
end

return table . concat ( out , "\n" ) .. "\n" , mappings
end

local __nuppExportValue= listing ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.bytecodelisting"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.bytecodelisting"]=__nuppExports;return __nuppExports