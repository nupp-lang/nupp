_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("re");local __nuppExports={};package.loaded["nupp.compiler.runtime.peg"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local codegen;__nuppExports["codegen"]=function(...) return codegen(...) end;local compile;__nuppExports["compile"]=function(...) return compile(...) end;local fromPattern;__nuppExports["fromPattern"]=function(...) return fromPattern(...) end;local graphPattern;__nuppExports["graphPattern"]=function(...) return graphPattern(...) end;local lpegBackend;__nuppExports["lpegBackend"]=function(...) return lpegBackend(...) end;local matcher;__nuppExports["matcher"]=function(...) return matcher(...) end;local start;__nuppExports["start"]=function(...) return start(...) end;

























local lpeg = require ( "lpeg" )
lpeg . setmaxstack ( 10000 )













start=function ( subject , init , level ) 
if type ( subject ) ~= "string" then
error ( "nupp: PEG subject must be a string" , level )
end
local at = 1
if init == nil then
at = 1
elseif type ( init ) ~= "number" or init ~= math . floor ( init ) or init == math . huge or init == - math . huge then
error ( "nupp: PEG init must be an integer" , level )
elseif ( init ) < 0 then
at = # subject + ( init ) + 1
else
at = init
end
if at < 1 then
at = 1
end
if at > # subject + 1 then
return nil
end

return at
end ;__nuppExports["start"]=start




local function findFrom (
run ,
take ,
captureful ,
subject ,
init ,
search
) 
if search ~= nil and search . direct ~= nil then
local first , last = subject : find ( search . direct , init , search . directPlain )
if first == nil then
return nil
end
local nextPosition = ( last ) + 1
if search . result == "string" then
return first , nextPosition , subject : sub ( first , last )
end

return first , nextPosition , nextPosition
end
local position = init
while ( position ) <= # subject + 1 do
if search ~= nil then
position = subject : find ( search . value , position , search . plain )
if position == nil then
return nil
end
end
local nextPosition = run ( subject , position )
if nextPosition ~= nil then
if captureful then
return position , nextPosition , take ( )
end

return position , nextPosition , nextPosition
end
position = ( position ) + 1
end

return nil
end


local function replaced ( replacement , first , nextPosition , ... ) 
local out = replacement ( first , nextPosition , ... )
if type ( out ) ~= "string" then
error ( "nupp: PEG replacement callback must return a string" , 3 )
end

return out
end

local function visited ( visitor , first , nextPosition , ... ) 
if first ~= nil then
visitor ( first , nextPosition , ... )

return first , nextPosition
end

return nil
end

local function replacementAt (
replacement ,
first ,
nextPosition ,
...
) 
if first ~= nil then
return first , nextPosition , replaced ( replacement , first , nextPosition , ... )
end

return nil
end

















matcher=function (
run ,
take ,
captureful ,
search ,
generatedFind ,
directReplaceAll ,
generatedTraverse
) 
local Matcher = { }
Matcher . __index = Matcher

local function findAt ( subject , init ) 
if generatedFind ~= nil then
return generatedFind ( subject , init )
end

return findFrom ( run , take , captureful , subject , init , search )
end

Matcher . match = function ( self , subject , init ) 
local at = start ( subject , init , 2 )
if at == nil then
return nil
end
local nextPosition = run ( subject , at )
if nextPosition == nil then
return nil
end
if captureful then
return take ( )
end

return nextPosition
end
Matcher . find = function ( self , subject , init ) 
local at = start ( subject , init , 2 )
if at == nil then
return nil
end

return findAt ( subject , at )
end
Matcher . isMatch = function ( self , subject , init ) 
local at = start ( subject , init , 2 )

return at ~= nil and findAt ( subject , at ) ~= nil
end
Matcher . forEachMatch = function ( self , subject , visitor , init ) 
if type ( visitor ) ~= "function" then
error ( "nupp: PEG match visitor must be a function" , 2 )
end
local cursor = start ( subject , init , 2 )
if cursor == nil then
return 0
end
if generatedTraverse ~= nil then
return generatedTraverse ( subject , visitor , cursor )
end
local count = 0
while ( cursor ) <= # subject + 1 do
local first , nextPosition = visited ( visitor , findAt ( subject , cursor ) )
if first == nil then
do break end
end
count = count + 1
cursor = ( nextPosition ) > ( first ) and nextPosition or ( first ) + 1
end

return count
end



Matcher . __nuppPegReplaceLiteral = function ( self , subject , replacement , init ) 
local at = start ( subject , init , 2 )
if at == nil then
return subject
end
local first , nextPosition = findAt ( subject , at )
if first == nil then
return subject
end

return subject : sub ( 1 , ( first ) - 1 ) .. replacement .. subject : sub ( nextPosition )
end
Matcher . __nuppPegReplaceCallback = function ( self , subject , replacement , init ) 
local at = start ( subject , init , 2 )
if at == nil then
return subject
end
local first , nextPosition , value = replacementAt ( replacement , findAt ( subject , at ) )
if first == nil then
return subject
end

return subject : sub ( 1 , ( first ) - 1 ) .. ( value ) .. subject : sub ( nextPosition )
end
Matcher . replace = function ( self , subject , replacement , init ) 
if type ( replacement ) == "string" then
return self : __nuppPegReplaceLiteral ( subject , replacement , init )
elseif type ( replacement ) == "function" then
return self : __nuppPegReplaceCallback ( subject , replacement , init )
end
error ( "nupp: PEG replacement must be a string or function" , 2 )
end





local function replaceAllFrom ( subject , at , produce ) 
local parts = { }
local count = 0
local cursor , copyAt = at , 1
while cursor <= # subject + 1 do
local first , nextPosition , value = produce ( cursor )
if first == nil then
do break end
end
count = count + 1
parts [ # parts + 1 ] = subject : sub ( copyAt , ( first ) - 1 )
parts [ # parts + 1 ] = value
copyAt = nextPosition
if ( nextPosition ) > ( first ) then
cursor = nextPosition
elseif ( first ) <= # subject then
parts [ # parts + 1 ] = subject : sub ( first , first )
copyAt = ( first ) + 1
cursor = ( first ) + 1
else
cursor = ( first ) + 1
end
end
if count == 0 then
return subject
end
parts [ # parts + 1 ] = subject : sub ( copyAt )

return table . concat ( parts )
end

Matcher . __nuppPegReplaceAllLiteral = function (
self ,
subject ,
replacement ,
init
) 
local at = start ( subject , init , 2 )
if at == nil then
return subject
end
if directReplaceAll ~= nil then
return directReplaceAll ( subject , replacement , at )
end

return replaceAllFrom ( subject , at , function ( cursor ) 
local first , nextPosition = findAt ( subject , cursor )

return first , nextPosition , replacement
end )
end
Matcher . __nuppPegReplaceAllCallback = function ( self , subject , replacement , init ) 
local at = start ( subject , init , 2 )
if at == nil then
return subject
end

return replaceAllFrom ( subject , at , function ( cursor ) 
return replacementAt ( replacement , findAt ( subject , cursor ) )
end )
end
Matcher . replaceAll = function ( self , subject , replacement , init ) 
if type ( replacement ) == "string" then
return self : __nuppPegReplaceAllLiteral ( subject , replacement , init )
elseif type ( replacement ) == "function" then
return self : __nuppPegReplaceAllCallback ( subject , replacement , init )
end
error ( "nupp: PEG replacement must be a string or function" , 2 )
end
Matcher . __call = Matcher . match

return setmetatable ( { } , Matcher )
end ;__nuppExports["matcher"]=matcher













graphPattern=function ( program , definitions ) 
local given = definitions or { }
for _ , name in ipairs ( program . actions or { } ) do
if rawget ( given , name ) == nil then
error ( "nupp: missing PEG definition " .. tostring ( name ) , 3 )
end
end
local P , S , V = lpeg . P , lpeg . S , lpeg . V
local C , Ct , Cg , Cb , Cp , Cs , Cmt , Cf = lpeg . C , lpeg . Ct , lpeg . Cg , lpeg . Cb , lpeg . Cp , lpeg . Cs , lpeg . Cmt , lpeg . Cf



local unkeyedGroup = lpeg . Cg
local nodes = program . graph . nodes
local memo = { }
local targets = { }





local function equalcap ( subject , position , captured ) 
if type ( captured ) ~= "string" then
return false
end
local ending = position + # ( captured )
if subject : sub ( position , ending - 1 ) == captured then
return ending
end

return false
end

local build
build = function ( index ) 
local prior = memo [ index ]
if prior then
return prior
end
local node = nodes [ index ]
local op = node [ 1 ]
local pattern
if op == "literal" then
pattern = P ( node [ 2 ] )
elseif op == "set" then
pattern = S ( node [ 2 ] )
elseif op == "any" then
pattern = P ( 1 )
elseif op == "eof" then
pattern = - P ( 1 )
elseif op == "sequence" then
pattern = P ( true )
for child = 2 , # node do
pattern = pattern * build ( node [ child ] )
end
elseif op == "choice" then
pattern = P ( false )
for child = 2 , # node do
pattern = pattern + build ( node [ child ] )
end
elseif op == "zeroOrMore" then
pattern = build ( node [ 2 ] ) ^ 0
elseif op == "oneOrMore" then
pattern = build ( node [ 2 ] ) ^ 1
elseif op == "optional" then
pattern = build ( node [ 2 ] ) ^ - 1
elseif op == "and" then
pattern = # build ( node [ 2 ] )
elseif op == "not" then
pattern = - build ( node [ 2 ] )
elseif op == "capture" then
pattern = C ( build ( node [ 2 ] ) )
elseif op == "collect" or op == "tableCapture" then
pattern = Ct ( build ( node [ 2 ] ) )
elseif op == "group" then
local grouped = build ( node [ 2 ] )
if node [ 3 ] ~= nil then
pattern = Cg ( grouped , node [ 3 ] )
else
pattern = unkeyedGroup ( grouped )
end
elseif op == "substitution" then
pattern = Cs ( build ( node [ 2 ] ) )
elseif op == "position" then
pattern = Cp ( )
elseif op == "backReference" then
pattern = Cmt ( Cb ( node [ 2 ] ) , equalcap )
elseif op == "external" then
pattern = P ( given [ node [ 2 ] ] )
elseif op == "transform" then
local spec = node [ 3 ]
local target = spec [ 1 ] == "definition" and given [ spec [ 2 ] ] or spec [ 2 ]
pattern = build ( node [ 2 ] ) / target
elseif op == "matchTime" then
pattern = Cmt ( build ( node [ 2 ] ) , given [ node [ 3 ] ] )
elseif op == "accumulate" then
pattern = build ( node [ 2 ] ) % given [ node [ 3 ] ]
elseif op == "fold" then
pattern = Cf ( build ( node [ 2 ] ) , given [ node [ 3 ] ] )
elseif op == "reference" then
targets [ node [ 2 ] ] = true
pattern = V ( "n" .. tostring ( node [ 2 ] ) )
else
error ( "nupp: unknown PEG graph operation " .. tostring ( op ) , 3 )
end
memo [ index ] = pattern

return pattern
end

local pattern = build ( program . graph . root )
if next ( targets ) ~= nil then


local grammar = { pattern }
local done = { }
while true do
local target = nil
for candidate in pairs ( targets ) do
if not done [ candidate ] then
target = candidate
do break end
end
end
if target == nil then
do break end
end
done [ target ] = true
grammar [ "n" .. tostring ( target ) ] = build ( target )
end
pattern = P ( grammar )
end

return pattern
end ;__nuppExports["graphPattern"]=graphPattern











fromPattern=function ( pattern ) 




local resultValue = nil
local resultValues = nil
local execution = ( pattern ) * lpeg . Cp ( )

local function keep ( ... ) 
local count = select ( "#" , ... )
if count <= 1 then


local nextPosition = ...
resultValue , resultValues = nextPosition , nil

return nextPosition
elseif count == 2 then
local value , nextPosition = ...
resultValue , resultValues = value , nil

return nextPosition
end
local values = { ... }
local nextPosition = values [ count ]
values [ count ] = nil
values . n = count - 1
resultValue , resultValues = nil , values

return nextPosition
end

local function run ( subject , position ) 
return keep ( lpeg . match ( execution , subject , position ) )
end

local function take ( ) 
local values = resultValues
if values == nil then
local value = resultValue
resultValue = nil

return value
end
resultValues = nil

return unpack ( values , 1 , values . n )
end

return matcher ( run , take , true , nil , nil , nil , nil )
end ;__nuppExports["fromPattern"]=fromPattern






lpegBackend=function ( program , definitions ) 
return fromPattern ( graphPattern ( program , definitions ) )
end ;__nuppExports["lpegBackend"]=lpegBackend






local function fastScan9Run ( plan , sets ) 
local keys = plan . packedKeys
local k1 , k2 , k3 , k4 = keys [ 1 ] , keys [ 2 ] , keys [ 3 ] , keys [ 4 ]
local k5 , k6 , k7 , k8 = keys [ 5 ] , keys [ 6 ] , keys [ 7 ] , keys [ 8 ]
local delimiter , separatorLength = ( plan . separator ) : byte ( ) , # ( plan . separator )
local scanByte = nil
local scanClass = nil
if ( plan . scan ) < 256 then
scanByte = plan . scan
else
scanClass = sets [ ( plan . scan ) - 255 ]
end
local suffix , minimum = plan . suffix , plan . minimum
local suffixHead = ( ( suffix [ 1 ] * 256 + suffix [ 2 ] ) * 256 + suffix [ 3 ] ) * 256 + suffix [ 4 ]
local suffixTail = ( ( suffix [ 5 ] * 256 + suffix [ 6 ] ) * 256 + suffix [ 7 ] ) * 256 + suffix [ 8 ]
local lastByte = nil
local lastClass = nil
if ( suffix [ 9 ] ) < 256 then
lastByte = suffix [ 9 ]
else
lastClass = sets [ ( suffix [ 9 ] ) - 255 ]
end

return function ( subject , position ) 
local a , b , c , d , e , f , g = subject : byte ( position , position + 6 )
if not a then
return nil
end
local key = nil
local prefixLength = 0
if b == delimiter then
prefixLength = 1
key = a * 8 + 1
elseif c == delimiter then
prefixLength = 2
key = ( a * 256 + b ) * 8 + 2
elseif d == delimiter then
prefixLength = 3
key = ( ( a * 256 + b ) * 256 + c ) * 8 + 3
elseif e == delimiter then
prefixLength = 4
key = ( ( ( a * 256 + b ) * 256 + c ) * 256 + d ) * 8 + 4
elseif f == delimiter then
prefixLength = 5
key = ( ( ( ( a * 256 + b ) * 256 + c ) * 256 + d ) * 256 + e ) * 8 + 5
elseif g == delimiter then
prefixLength = 6
key = ( ( ( ( ( a * 256 + b ) * 256 + c ) * 256 + d ) * 256 + e ) * 256 + f ) * 8 + 6
else
return nil
end
if not (
key == k1 or key == k2 or key == k3 or key == k4 or key == k5 or key == k6 or key == k7 or key == k8
) then
return nil
end
local at = position + prefixLength + separatorLength
local suffixStart = # subject - 8
if suffixStart - at < ( minimum ) then
return nil
end
if scanClass ~= nil then
for index = at , suffixStart - 1 do
local byte = subject : byte ( index )
if ( scanClass ) : byte ( ( byte ) + 1 ) == 0 then
return nil
end
end
else
for index = at , suffixStart - 1 do
if subject : byte ( index ) ~= scanByte then
return nil
end
end
end
local q , r , s , t , u , v , w , x , y = subject : byte ( suffixStart , # subject )
if ( ( q * 256 + r ) * 256 + s ) * 256 + t == suffixHead
and ( ( u * 256 + v ) * 256 + w ) * 256 + x == suffixTail
and ( ( lastByte ~= nil and y == lastByte ) or ( lastClass ~= nil and ( lastClass ) : byte ( y + 1 ) ~= 0 ) )
then
return # subject + 1
end

return nil
end
end



local function checkSource ( encoded , expression ) 
if encoded < 256 then
return expression .. "==" .. tostring ( encoded )
end

return "sets[" .. tostring ( encoded - 255 ) .. "]:byte(" .. expression .. "+1)~=0"
end




local function repeatSource ( plan ) 
local head = checkSource ( plan . head , "byte" )
local tail = checkSource ( plan . tail , "byte" )
local accept = plan . eof and "if position~=#subject+1 then return nil end;" or ""
local result = plan . result == "string" and "lastSubject,lastFirst,lastNext=subject,first,position;return position"
or "return position"
local visitValue = plan . result == "string" and "subject:sub(first,position-1)" or "position"
local visit = plan . eof
and "if position==length+1 then count=count+1;visitor(first,position," .. visitValue .. ");return count end"
or "count=count+1;visitor(first,position," .. visitValue .. ")"
local state = plan . result == "string"
and "local lastSubject,lastFirst,lastNext;local function take()return lastSubject:sub(lastFirst,lastNext-1)end;"

or ""
local take = plan . result == "string" and "take" or "nil"

return "return function(sets)"
.. state
.. "local function run(subject,position)local first=position;local byte=subject:byte(position);"
.. "if not byte or not("
.. head
.. ")then return nil end;position=position+1;"
.. "while true do byte=subject:byte(position);if not byte or not("
.. tail
.. ")then break end;"
.. "position=position+1 end;"
.. accept
.. result
.. " end;"
.. "local function traverse(subject,visitor,position)local count,length=0,#subject;"
.. "while position<=length do local byte=subject:byte(position);if "
.. head
.. " then local first=position;position=position+1;"
.. "while true do byte=subject:byte(position);if not byte or not("
.. tail
.. ")then break end;"
.. "position=position+1 end;"
.. visit
.. " else position=position+1 end end;return count end;"
.. "return run,"
.. take
.. ",traverse end"
end



local function fixedSource ( checks ) 
local conditions = { "position+" .. tostring ( # checks ) .. "==#subject+1" , }
for index , encoded in ipairs ( checks ) do
local expression = "subject:byte(position+" .. tostring ( index - 1 ) .. ")"
conditions [ # conditions + 1 ] = checkSource ( encoded , expression )
end

return "return function(sets)return function(subject,position)if " .. table . concat (
conditions ,
" and "
) .. " then return position+" .. tostring ( # checks ) .. " end end end"
end












codegen=function ( program , definitions ) 
local scan = program . fastScan
if scan ~= nil and scan . packedKeys ~= nil and ( scan . maximum ) <= 6 and # scan . keys <= 8 then
local suffix = scan . suffix
if # suffix == 9
and suffix [ 1 ] < 256
and suffix [ 2 ] < 256
and suffix [ 3 ] < 256
and suffix [ 4 ] < 256
and suffix [ 5 ] < 256
and suffix [ 6 ] < 256
and suffix [ 7 ] < 256
and suffix [ 8 ] < 256
then
return matcher ( fastScan9Run ( scan , program . sets ) , nil , false , program . search , nil , nil , nil )
end
end
local source = nil
if program . fastRepeat ~= nil then
source = repeatSource ( program . fastRepeat )
elseif program . fastFixed ~= nil then
source = fixedSource ( program . fastFixed )
else
return lpegBackend ( program , definitions )
end
local chunk , why = loadstring ( source , "=nupp PEG specialization" )
if not chunk then
error ( "nupp: PEG specialization failed: " .. tostring ( why ) , 2 )
end
local run , take , traverse = ( chunk ) ( ) ( program . sets )

return matcher ( run , take , program . captureful , program . search , nil , nil , traverse )
end ;__nuppExports["codegen"]=codegen




local patternCache = setmetatable ( { } , { __mode = "v" , } )












compile=function ( source , options ) 
if type ( source ) ~= "string" then
error ( "nupp: PEG compile source must be a string" , 2 )
end
if options ~= nil and type ( options ) ~= "table" then
error ( "nupp: PEG compile options must be a table" , 2 )
end
local given = options or { }
local backend = given . backend or "auto"
if backend ~= "auto" and backend ~= "lpeg" then
error ( "nupp: PEG compile backend must be 'auto' or 'lpeg'" , 2 )
end
local definitions = given . definitions
local pattern = nil
if definitions == nil then
pattern = patternCache [ source ]
if not pattern then
pattern = require ( "re" ) . compile ( source )
patternCache [ source ] = pattern
end
else
pattern = require ( "re" ) . compile ( source , definitions )
end

return fromPattern ( pattern )
end ;__nuppExports["compile"]=compile
 end);if not __nuppOk then package.loaded["nupp.compiler.runtime.peg"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.runtime.peg"]=__nuppExports;return __nuppExports