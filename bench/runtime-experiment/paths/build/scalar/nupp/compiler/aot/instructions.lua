_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.instructions\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.instructions\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.aot.instructions\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.compiler.aot.instructions\0runtime\0004") };






























local instructions = __nuppNew(0,2)






instructions . ARCHITECTURES = { "aarch64" , "x86_64" }









instructions . ROLES = { "kernel" , "oracle" , "wrapper" , "registrar" , "reporter" , "helper" }


instructions.Claim = {} instructions.Claim.__index = instructions.Claim ;_G.nupp.__reflect.link(instructions.Claim,__nuppT1[1],{ })








instructions.Instruction = {} instructions.Instruction.__index = instructions.Instruction ;_G.nupp.__reflect.link(instructions.Instruction,__nuppT1[2],{ })

























instructions.Counts = {} instructions.Counts.__index = instructions.Counts ;_G.nupp.__reflect.link(instructions.Counts,__nuppT1[3],{ })
















instructions.Listing = {} instructions.Listing.__index = instructions.Listing ;_G.nupp.__reflect.link(instructions.Listing,__nuppT1[4],{ __nuppT1[2] , __nuppT1[3] })

















function instructions . reads ( architecture ) 
for _ , named in ipairs ( instructions . ARCHITECTURES ) do
if named == architecture then
return true
end
end

return false
end

local function trim ( text ) 
return ( text : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) )
end







local function uncomment ( line , architecture ) 
if architecture == "x86_64" then
return ( line : gsub ( "#.*$" , "" ) )
end

return ( line : gsub ( ";.*$" , "" ) : gsub ( "//.*$" , "" ) )
end







local function isLocalLabel ( name ) 
return name : sub ( 1 , 1 ) == "L" or name : sub ( 1 , 1 ) == "."
end






local function operandList ( operands ) 
local parts = { }
local depth = 0
local current = { }
for index = 1 , # operands do
local character = operands : sub ( index , index )
if character == "(" then
depth = depth + 1
current [ # current + 1 ] = character
elseif character == ")" then
depth = depth - 1
current [ # current + 1 ] = character
elseif character == "," and depth == 0 then
parts [ # parts + 1 ] = trim ( table . concat ( current ) )
current = { }
else
current [ # current + 1 ] = character
end
end
local last = trim ( table . concat ( current ) )
if last ~= "" then
parts [ # parts + 1 ] = last
end

return parts
end











local function classifyArm ( mnemonic , operands ) 
local kinds = { }
local base = mnemonic : match ( "^[^%.]+" ) or mnemonic
local padded = " " .. operands
if mnemonic : find ( "%.%d+[bhsd]" ) ~= nil
or operands : find ( "%.%d+[bhsd]" ) ~= nil
or padded : find ( "[^%w_%.]v%d" ) ~= nil
or padded : find ( "[^%w_%.]q%d" ) ~= nil
then
kinds [ # kinds + 1 ] = "vector"
end
if base : find ( "^ld" ) ~= nil then
kinds [ # kinds + 1 ] = "load"
elseif base : find ( "^st" ) ~= nil then
kinds [ # kinds + 1 ] = "store"
end
if base == "bl" or base == "blr" then
kinds [ # kinds + 1 ] = "call"
elseif base == "b" or base == "br" or base : find ( "^cbn?z$" ) ~= nil or base : find ( "^tbn?z$" ) ~= nil then
kinds [ # kinds + 1 ] = "branch"
end
if operands : find ( "%[sp" , 1 ) ~= nil or operands : find ( "%[x29" , 1 ) ~= nil then
kinds [ # kinds + 1 ] = "stack"
end

return kinds
end






local function readsMemory ( operand ) 
return operand : find ( "%(%%" ) ~= nil
end




local function comparesOnly ( mnemonic ) 
return mnemonic : match ( "^cmp[bwlq]?$" ) ~= nil
or mnemonic : match ( "^test[bwlq]?$" ) ~= nil
or mnemonic : match ( "^bt[bwlq]?$" ) ~= nil
or mnemonic : match ( "^v?u?comis[sd]$" ) ~= nil
or mnemonic : match ( "^v?ptest$" ) ~= nil
end



local function readsOnly ( mnemonic ) 
return ( mnemonic : match ( "^cmp[bwlq]?$" ) ~= nil or mnemonic : match ( "^test[bwlq]?$" ) ~= nil or mnemonic : match ( "^bt[bwlq]?$" ) ~= nil or mnemonic : match ( "^v?u?comis[sd]$" ) ~= nil or mnemonic : match ( "^v?ptest$" ) ~= nil ) or mnemonic : find ( "^call" ) ~= nil or mnemonic : find ( "^j" ) ~= nil
end

















local function classifyX86 ( mnemonic , operands ) 
local kinds = { }
local parts = operandList ( operands )
local packed = operands : find ( "%%[xyz]mm%d" ) ~= nil or operands : find ( "%%k%d" ) ~= nil
local scalar = mnemonic : find ( "s[sd]$" ) ~= nil and mnemonic : find ( "broadcast" , 1 , true ) == nil
if packed and not scalar then
kinds [ # kinds + 1 ] = "vector"
end
if mnemonic : find ( "^push" ) ~= nil then
kinds [ # kinds + 1 ] = "store"
elseif mnemonic : find ( "^pop" ) ~= nil then
kinds [ # kinds + 1 ] = "load"
elseif mnemonic : find ( "^lea" ) == nil then
local last = # parts > 0 and parts [ # parts ] or ""
if ( last : find ( "%(%%" ) ~= nil ) and not ( ( mnemonic : match ( "^cmp[bwlq]?$" ) ~= nil or mnemonic : match ( "^test[bwlq]?$" ) ~= nil or mnemonic : match ( "^bt[bwlq]?$" ) ~= nil or mnemonic : match ( "^v?u?comis[sd]$" ) ~= nil or mnemonic : match ( "^v?ptest$" ) ~= nil ) or mnemonic : find ( "^call" ) ~= nil or mnemonic : find ( "^j" ) ~= nil ) then
kinds [ # kinds + 1 ] = "store"
else
for _ , part in ipairs ( parts ) do
if ( part : find ( "%(%%" ) ~= nil ) then
kinds [ # kinds + 1 ] = "load"

do break end
end
end
end
end
if mnemonic : find ( "^call" ) ~= nil then
kinds [ # kinds + 1 ] = "call"
elseif mnemonic : find ( "^j" ) ~= nil then
kinds [ # kinds + 1 ] = "branch"
end
local stacked = mnemonic : find ( "^push" ) ~= nil or mnemonic : find ( "^pop" ) ~= nil
for _ , part in ipairs ( parts ) do
stacked = stacked or part : find ( "%(%%rsp" , 1 ) ~= nil or part : find ( "%(%%rbp" , 1 ) ~= nil
end
if stacked then
kinds [ # kinds + 1 ] = "stack"
end

return kinds
end


function instructions . count ( listed ) 
local counts = _G.setmetatable({ total =
# listed ,  vector =
0 ,  loads =
0 ,  stores =
0 ,  branches =
0 ,  calls =
0 ,  stack =
0 }, instructions.Counts)

for _ , one in ipairs ( listed ) do
for _ , kind in ipairs ( one . kinds ) do
if kind == "vector" then
counts . vector = counts . vector + 1
elseif kind == "load" then
counts . loads = counts . loads + 1
elseif kind == "store" then
counts . stores = counts . stores + 1
elseif kind == "branch" then
counts . branches = counts . branches + 1
elseif kind == "call" then
counts . calls = counts . calls + 1
elseif kind == "stack" then
counts . stack = counts . stack + 1
end
end
end

return counts
end












function instructions . parse ( assembly , architecture , system ) 
local listings = { }
local current = nil
local pending = nil
local files = { }
local sourceFile = nil
local sourceLine = nil
local sourceColumn = nil
local underscored = system == "darwin" or system == "windows"
for raw in ( assembly .. "\n" ) : gmatch ( "([^\n]*)\n" ) do
local line = trim ( uncomment ( raw , architecture ) )
local label = line : match ( "^([%w_%$%.][%w_%$%.]*):$" )



local fileId , fileName = line : match ( "^%.file%s+(%d+)%s+\"([^\"]+)\"" )
local locFile , locLine , locColumn = line : match ( "^%.loc%s+(%d+)%s+(%d+)%s+(%d+)" )
if fileId ~= nil then
local second = line : match ( "^%.file%s+%d+%s+\"[^\"]+\"%s+\"([^\"]+)\"" )
files [ tonumber ( fileId ) ] = second ~= nil
and ( second : sub ( 1 , 1 ) == "/" and second or fileName .. "/" .. second )
or fileName
elseif locFile ~= nil then
sourceLine = tonumber ( locLine )
sourceFile = sourceLine > 0 and files [ tonumber ( locFile ) ] or nil
sourceColumn = sourceLine > 0 and tonumber ( locColumn ) or nil
sourceLine = sourceLine > 0 and sourceLine or nil
elseif line == "" then

elseif label ~= nil then
if isLocalLabel ( label ) then
pending = label
else
local symbol = label
if underscored and symbol : sub ( 1 , 1 ) == "_" then
symbol = symbol : sub ( 2 )
end
current = _G.setmetatable({ symbol =
symbol ,  role =
"helper" ,  instructions =
{ } ,  counts =
instructions . count ( { } ) }, instructions.Listing)

listings [ # listings + 1 ] = current
pending = nil
sourceFile , sourceLine , sourceColumn = nil , nil , nil
end
elseif line : sub ( 1 , 1 ) == "." then



elseif current ~= nil then
local mnemonic = line : match ( "^([%w_%.][%w_%.]*)" ) or line
local operands = trim ( line : sub ( # mnemonic + 1 ) )
local kinds = architecture == "x86_64" and classifyX86 ( mnemonic , operands )
or classifyArm ( mnemonic , operands )
local held = ( current ) . instructions
held [ # held + 1 ] = _G.setmetatable({ label =
pending ,  sourceFile =
sourceFile ,  sourceLine =
sourceLine ,  generatedColumn =
sourceColumn ,  text =



operands ~= "" and ( mnemonic .. " " .. operands ) or mnemonic ,  mnemonic =
mnemonic ,  operands =
operands ,  kinds =
kinds }, instructions.Instruction)

pending = nil
end
end

local kept = { }
for _ , listing in ipairs ( listings ) do
if # listing . instructions > 0 then
listing . counts = instructions . count ( listing . instructions )
kept [ # kept + 1 ] = listing
end
end

return kept
end






function instructions . claim ( listings , claims ) 
for _ , listing in ipairs ( listings ) do
local claim = claims [ listing . symbol ]
if claim ~= nil then
listing . name = ( claim ) . name
listing . role = ( claim ) . role
else





local owner = listing . symbol : match ( "^(.+)_layout_[%w_]+$" )
local reported = owner ~= nil and claims [ owner ] or nil
if reported ~= nil then
listing . name = ( reported ) . name
listing . role = "reporter"
end
end
end
end






function instructions . order ( listings ) 
local ordered = { }
for _ , role in ipairs ( instructions . ROLES ) do
for _ , listing in ipairs ( listings ) do
if listing . role == role then
ordered [ # ordered + 1 ] = listing
end
end
end


for _ , listing in ipairs ( listings ) do
local known = false
for _ , role in ipairs ( instructions . ROLES ) do
known = known or listing . role == role
end
if not known then
ordered [ # ordered + 1 ] = listing
end
end

return ordered
end






function instructions . select ( listings , wanted ) 
local chosen = { }
for _ , listing in ipairs ( listings ) do
if listing . symbol == wanted or listing . name == wanted then
chosen [ # chosen + 1 ] = listing
end
end

return chosen
end







function instructions . names ( listings ) 
local named = { }
local seen = { }

local function add ( spelling ) 
if not seen [ spelling ] then
seen [ spelling ] = true
named [ # named + 1 ] = spelling
end
end

for _ , listing in ipairs ( listings ) do
if listing . name ~= nil then
add ( tostring ( listing . name ) )
end
add ( listing . symbol )
end

return named
end

local __nuppExportValue= instructions ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.instructions"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.instructions"]=__nuppExports;return __nuppExports