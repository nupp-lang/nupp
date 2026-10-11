_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.relations\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.relations\0runtime\0002") };













local scalarIR = require ( "nupp.compiler.aot.scalar" )

local relations = __nuppNew(0,3)







relations . INFINITE = 1073741824






relations . MAX_OFFSET = 1048576






relations . BUDGET = 128


relations.Closure = {} relations.Closure.__index = relations.Closure ;_G.nupp.__reflect.link(relations.Closure,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00080","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00081","nupp.compiler.aot.scalar") })
































function relations . key ( term ) 
if term . kind == "zero" then
return "0"
elseif term . kind == "count" then
local count = "#" .. tostring ( term . name )

return term . factor ~= nil and tostring ( term . factor ) .. "*" .. count or count
else
return "u:" .. tostring ( term . name )
end
end


function relations . termText ( term ) 
if term . kind == "zero" then
return "0"
elseif term . kind == "count" then
local count = "#" .. tostring ( term . name )

return term . factor ~= nil and tostring ( term . factor ) .. " * " .. count or count
else
return tostring ( term . name )
end
end


function relations . zero ( ) 
return ( _G.setmetatable({ kind =  "zero" }, scalarIR.Term) )
end


function relations . uniform ( name ) 
return ( _G.setmetatable({ kind =  "uniform" ,  name =  name }, scalarIR.Term) )
end


function relations . count ( name ) 
return ( _G.setmetatable({ kind =  "count" ,  name =  name }, scalarIR.Term) )
end



function relations . scaledCount ( name , factor ) 
if factor == 1 then
return relations . count ( name )
end

return ( _G.setmetatable({ kind =  "count" ,  name =  name ,  factor =  factor }, scalarIR.Term) )
end


function relations . relation (
left ,
right ,
offset ,
source
) 
return ( _G.setmetatable({ left =  left ,  right =  right ,  offset =  offset ,  source =  source }, scalarIR.Relation) )
end



function relations . withSoaCounts ( pool , params ) 
local result = { }
for _ , relation in ipairs ( pool ) do
result [ # result + 1 ] = relation
end
for _ , param in ipairs ( params ) do
if param . soa ~= nil and param . soa . ordinal > 1 then
local view = relations . count ( param . soa . view )
local column = relations . count ( param . name )
result [ # result + 1 ] = relations . relation ( view , column , 0 )
result [ # result + 1 ] = relations . relation ( column , view , 0 )
end
end

return result
end


function relations . text ( relation ) 
local left = relations . termText ( relation . left )
local right = relations . termText ( relation . right )
if relation . left . kind == "zero" then



return tostring ( - relation . offset ) .. " <= " .. right
elseif relation . offset == 0 then
return left .. " <= " .. right
end
if relation . offset > 0 then
return left .. " <= " .. right .. " + " .. tostring ( relation . offset )
end

return left .. " <= " .. right .. " - " .. tostring ( - relation . offset )
end









relations.Keyed = {} relations.Keyed.__index = relations.Keyed ;_G.nupp.__reflect.link(relations.Keyed,__nuppT1[2],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00081","nupp.compiler.aot.scalar") })











function relations . canonical ( pool ) 
local keyed = { }
for _ , relation in ipairs ( pool ) do
keyed [
# keyed + 1
] = _G.setmetatable({ left =
relations . key ( relation . left ) ,  right =
relations . key ( relation . right ) ,  offset =
relation . offset ,  relation =
relation }, relations.Keyed)

end
table . sort ( keyed , function ( a , b ) 
if a . left ~= b . left then
return a . left < b . left
end
if a . right ~= b . right then
return a . right < b . right
end

return a . offset < b . offset
end )

local unique = { }
local seen = { }
for _ , entry in ipairs ( keyed ) do
local key = entry . left .. "|" .. entry . right .. "|" .. tostring ( entry . offset )





local tautology = entry . left == entry . right and entry . offset >= 0
if not tautology and seen [ key ] == nil then
seen [ key ] = true
unique [ # unique + 1 ] = entry . relation
end
end

return unique
end






function relations . add ( a , b ) 
if a >= relations . INFINITE or b >= relations . INFINITE then
return relations . INFINITE
end
local sum = a + b
if sum >= relations . INFINITE then
return relations . INFINITE
end
if sum <= - relations . INFINITE then
return - relations . INFINITE
end

return sum
end






function relations . closure ( pool , terms ) 
local indexOf = { }
for position , term in ipairs ( terms ) do
indexOf [ relations . key ( term ) ] = position
end

local count = # terms
local dist = { }
local edge = { }
local mid = { }
for i = 1 , count do
local row = { }
local edgeRow = { }
local midRow = { }
for j = 1 , count do
row [ j ] = i == j and 0 or relations . INFINITE
edgeRow [ j ] = 0
midRow [ j ] = 0
end
dist [ i ] = row
edge [ i ] = edgeRow
mid [ i ] = midRow
end

for position , relation in ipairs ( pool ) do
local from = indexOf [ relations . key ( relation . right ) ]
local to = indexOf [ relations . key ( relation . left ) ]
if from ~= nil and to ~= nil then
local i , j = from , to
if relation . offset < dist [ i ] [ j ] then
dist [ i ] [ j ] = relation . offset
edge [ i ] [ j ] = position
mid [ i ] [ j ] = 0
end
end
end

for k = 1 , count do
for i = 1 , count do
local throughLeft = dist [ i ] [ k ]
if throughLeft < relations . INFINITE then
for j = 1 , count do
local through = relations . add ( throughLeft , dist [ k ] [ j ] )
if through < dist [ i ] [ j ] then
dist [ i ] [ j ] = through
edge [ i ] [ j ] = 0
mid [ i ] [ j ] = k
end
end
end
end
end

local contradiction = nil
for i = 1 , count do
if dist [ i ] [ i ] < 0 then
contradiction = terms [ i ]
do break end
end
end

return ( _G.setmetatable({ terms =
terms ,  indexOf =
indexOf ,  pool =
pool ,  dist =
dist ,  edge =
edge ,  mid =
mid ,  contradiction =
contradiction }, relations.Closure) )

end









function relations . axioms ( spans ) 
local pool = { }
for _ , name in ipairs ( spans ) do
pool [ # pool + 1 ] = relations . relation ( relations . zero ( ) , relations . count ( name ) , 0 , nil )
end

return pool
end


local function scaledTerms ( pool ) 
local seen = { }
local keyed = { }
for _ , relation in ipairs ( pool ) do
for _ , term in ipairs ( { relation . left , relation . right } ) do
local key = relations . key ( term )
if term . kind == "count" and term . factor ~= nil and seen [ key ] == nil then
seen [ key ] = true
keyed [ # keyed + 1 ] = _G.setmetatable({ left =  key ,  right =  "" ,  offset =  0 ,  relation =  relation }, relations.Keyed)
keyed [ # keyed ] . relation = relations . relation ( term , term , 0 )
end
end
end
table . sort ( keyed , function ( a , b ) 
return a . left < b . left
end )
local terms = { }
for _ , entry in ipairs ( keyed ) do
terms [ # terms + 1 ] = entry . relation . left
end

return terms
end





function relations . scaledAxioms ( scaled ) 
local pool = { }
for _ , term in ipairs ( scaled ) do
local name = tostring ( term . name )
pool [ # pool + 1 ] = relations . relation ( relations . count ( name ) , term , 0 , nil )
pool [ # pool + 1 ] = relations . relation ( relations . zero ( ) , term , 0 , nil )
for _ , smaller in ipairs ( scaled ) do
if smaller . name == term . name and ( smaller . factor ) < ( term . factor ) then
pool [ # pool + 1 ] = relations . relation ( smaller , term , 0 , nil )
end
end
end

return pool
end



function relations . solve ( written , spans , terms ) 
local pool = { }
for _ , relation in ipairs ( written ) do
pool [ # pool + 1 ] = relation
end
for _ , relation in ipairs ( relations . axioms ( spans ) ) do
pool [ # pool + 1 ] = relation
end
local scaled = scaledTerms ( written )
for _ , relation in ipairs ( relations . scaledAxioms ( scaled ) ) do
pool [ # pool + 1 ] = relation
end
local universe = { }
for _ , term in ipairs ( terms ) do
universe [ # universe + 1 ] = term
end
for _ , term in ipairs ( scaled ) do
universe [ # universe + 1 ] = term
end

return relations . closure ( pool , universe )
end





function relations . transfers ( closure , spans ) 
local transfers = { }
for _ , from in ipairs ( spans ) do
local carried = { }
for _ , to in ipairs ( spans ) do
local into = closure . indexOf [ relations . key ( relations . count ( to ) ) ]
local found = { }
for position , term in ipairs ( closure . terms ) do
if term . kind == "count" and term . name == from and into ~= nil then
local offset = closure . dist [ into ] [ position ]
if offset < relations . INFINITE and offset > - relations . INFINITE then
found [ # found + 1 ] = _G.setmetatable({ factor =  term . factor or 1 ,  offset =  offset }, scalarIR.RoomTransfer)
end
end
end
if # found > 0 then
carried [ to ] = found
end
end
transfers [ from ] = carried
end

return transfers
end






local function contributing ( closure , i , j , out ) 
local through = closure . mid [ i ] [ j ]
if through ~= 0 then
contributing ( closure , i , through , out )
contributing ( closure , through , j , out )

return
end
local used = closure . edge [ i ] [ j ]
if used ~= 0 then
out [ # out + 1 ] = used
end
end





function relations . proves (
closure ,
left ,
right ,
offset
) 
local from = closure . indexOf [ relations . key ( right ) ]
local to = closure . indexOf [ relations . key ( left ) ]
if from == nil or to == nil then
return nil
end
local i , j = from , to
if closure . dist [ i ] [ j ] > offset then
return nil
end

local indices = { }
contributing ( closure , i , j , indices )
local used = { }
local seen = { }
for _ , position in ipairs ( indices ) do
if seen [ position ] == nil then
seen [ position ] = true
used [ # used + 1 ] = closure . pool [ position ]
end
end

return used
end


function relations . equalCounts ( closure , left , right ) 
local a , b = relations . count ( left ) , relations . count ( right )

return relations . proves ( closure , a , b , 0 ) ~= nil and relations . proves ( closure , b , a , 0 ) ~= nil
end

local __nuppExportValue= relations ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.relations"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.relations"]=__nuppExports;return __nuppExports