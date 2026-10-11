_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.bench.internal.statistics\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.bench.internal.statistics\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.bench.internal.statistics\0runtime\0003") };




















local statistics = {







MIN_INTERVAL_SAMPLES= 10 ,


TARGET_COVERAGE= 0.95 ,


ALPHA= 0.05 ,


CONCENTRATION_TOLERANCE= 0.10 ,







MIN_CONCENTRATION= 0.5 ,









TREND_MIN_DRIFT= 0.03 , }








local TREND_BLOCKS = 64


local TREND_MIN_SAMPLES = 32



local EXACT_LIMIT = 200


statistics.Interval = {} statistics.Interval.__index = statistics.Interval ;_G.nupp.__reflect.link(statistics.Interval,__nuppT1[1],{ })














statistics.Trend = {} statistics.Trend.__index = statistics.Trend ;_G.nupp.__reflect.link(statistics.Trend,__nuppT1[2],{ })


























statistics.Outliers = {} statistics.Outliers.__index = statistics.Outliers ;_G.nupp.__reflect.link(statistics.Outliers,__nuppT1[3],{ })


















function statistics . sorted ( values ) 
local copy = { }
for index = 1 , # values do
copy [ index ] = values [ index ]
end
table . sort ( copy )

return copy
end





function statistics . quantile ( sorted , fraction ) 
if # sorted == 0 then
return 0
end
local rank = math . ceil ( fraction * # sorted )
if rank < 1 then
rank = 1
end
if rank > # sorted then
rank = # sorted
end

return sorted [ rank ]
end


function statistics . median ( values ) 
if # values == 0 then
return 0
end

return statistics . quantile ( statistics . sorted ( values ) , 0.5 )
end


function statistics . iqr ( values ) 
if # values == 0 then
return 0
end
local sorted = statistics . sorted ( values )

return statistics . quantile ( sorted , 0.75 ) - statistics . quantile ( sorted , 0.25 )
end









local function binomialAtMost ( n , m ) 
if m < 0 then
return 0
end
if m >= n then
return 1
end
local term = 0.5 ^ n
if term == 0 then

return 0
end
local total = term
for index = 1 , m do
term = term * ( ( n - index + 1 ) / index )
total = total + term
end
if total > 1 then
return 1
end

return total
end






function statistics . medianCoverage ( n , k ) 
if n < 2 or k < 1 or k > n / 2 then
return 0
end
local coverage = 1 - 2 * binomialAtMost ( n , ( k - 1 ) )
if coverage < 0 then
return 0
end

return coverage
end





function statistics . selectK ( n , target ) 
local best = 0
local limit = math . floor ( n / 2 )
for k = 1 , limit do
if statistics . medianCoverage ( n , k ) >= target then
best = k
end
end

return best
end







function statistics . medianInterval ( values ) 
local n = # values
if n < statistics . MIN_INTERVAL_SAMPLES then
return nil
end
local k = statistics . selectK ( n , statistics . TARGET_COVERAGE )
if k < 1 then
return nil
end
local sorted = statistics . sorted ( values )

return ( _G.setmetatable({ low =
sorted [ k ] ,  upper =
sorted [ n - k + 1 ] ,  k =
k ,  attainedCoverage =
statistics . medianCoverage ( n , k ) }, statistics.Interval) )

end











function statistics . outliers ( values ) 
if # values == 0 then
return ( _G.setmetatable({ severe =  0 ,  maxRatio =  1.0 ,  lowFence =  0.0 ,  upperFence =  0.0 }, statistics.Outliers) )
end
local sorted = statistics . sorted ( values )
local lowerQuartile = statistics . quantile ( sorted , 0.25 )
local upperQuartile = statistics . quantile ( sorted , 0.75 )
local spread = upperQuartile - lowerQuartile
local lowFence = lowerQuartile - 3 * spread
local upperFence = upperQuartile + 3 * spread
local middle = statistics . quantile ( sorted , 0.5 )
local severe = 0
local worst = 1
for _ , value in ipairs ( sorted ) do
if value < lowFence or value > upperFence then
severe = ( severe + 1 )
if middle > 0 then
local ratio = value / middle
if ratio > worst then
worst = ratio
end
end
end
end

return ( _G.setmetatable({ severe =  severe ,  maxRatio =  worst ,  lowFence =  lowFence ,  upperFence =  upperFence }, statistics.Outliers) )
end













function statistics . concentration ( values , tolerance ) 
if # values == 0 then
return 1
end
local middle = statistics . median ( values )
if middle <= 0 then
return 1
end
local band = tolerance * middle
local near = 0
for _ , value in ipairs ( values ) do
if math . abs ( value - middle ) <= band then
near = ( near + 1 )
end
end

return near / # values
end







local function erf ( x ) 
local sign = x < 0 and -1 or 1
local value = math . abs ( x )
local t = 1 / ( 1 + 0.3275911 * value )
local poly = t * ( 0.254829592 + t * ( - 0.284496736 + t * ( 1.421413741 + t * ( - 1.453152027 + t * 1.061405429 ) ) ) )

return sign * ( 1 - poly * math . exp ( - value * value ) )
end


local function normalTwoSided ( z ) 
local tail = 1 - erf ( math . abs ( z ) / math . sqrt ( 2 ) )
if tail < 0 then
return 0
end
if tail > 1 then
return 1
end

return tail
end






local function blockMedians ( series ) 
local count = # series
local blocks = count < 64 and count or 64
if blocks < 1 then
return { }
end
local reduced = { }
for index = 1 , blocks do
local from = math . floor ( ( index - 1 ) * count / blocks ) + 1
local to = math . floor ( index * count / blocks )
if to < from then
to = from
end
local block = { }
for position = from , to do
block [ # block + 1 ] = series [ position ]
end
reduced [ # reduced + 1 ] = statistics . median ( block )
end

return reduced
end











function statistics . trend ( series ) 
if # series < 32 then
return ( _G.setmetatable({ verdict =  "unknown" ,  tau =  0.0 ,  pValue =  1.0 ,  drift =  0.0 ,  blocks =  0 }, statistics.Trend) )
end
local reduced = blockMedians ( series )
local n = # reduced
if n < 4 then
return ( _G.setmetatable({ verdict =  "unknown" ,  tau =  0.0 ,  pValue =  1.0 ,  drift =  0.0 ,  blocks =  n }, statistics.Trend) )
end


local quarter = math . floor ( n / 4 )
if quarter < 1 then
quarter = 1
end
local head = { }
local tail = { }
for index = 1 , quarter do
head [ # head + 1 ] = reduced [ index ]
tail [ # tail + 1 ] = reduced [ n - quarter + index ]
end
local from = statistics . median ( head )
local drift = from > 0 and ( statistics . median ( tail ) - from ) / from or 0
local score = 0
for i = 1 , n - 1 do
for j = i + 1 , n do
local delta = reduced [ j ] - reduced [ i ]
if delta > 0 then
score = score + 1
elseif delta < 0 then
score = score - 1
end
end
end
local comparisons = n * ( n - 1 ) / 2
local tau = comparisons > 0 and score / comparisons or 0
local variance = n * ( n - 1 ) * ( 2 * n + 5 ) / 18
local pValue = 1
if variance > 0 then
local adjusted = 0
if score > 0 then
adjusted = score - 1
elseif score < 0 then
adjusted = score + 1
end
pValue = normalTwoSided ( adjusted / math . sqrt ( variance ) )
end



local detected = pValue < statistics . ALPHA and math . abs ( drift ) >= statistics . TREND_MIN_DRIFT
local verdict = detected and "trend" or "no-trend-detected"

return ( _G.setmetatable({ verdict =  verdict ,  tau =  tau ,  pValue =  pValue ,  drift =  drift ,  blocks =  n }, statistics.Trend) )
end







local function signedRankCounts ( n ) 
local total = ( n * ( n + 1 ) / 2 )
local counts = { }
for index = 0 , total do
counts [ index + 1 ] = 0
end
counts [ 1 ] = 1
for rank = 1 , n do
for sum = total , rank , -1 do
counts [ sum + 1 ] = counts [ sum + 1 ] + counts [ sum - rank + 1 ]
end
end

return counts
end


local function signedRankAtMost ( n , m ) 
if m < 0 then
return 0
end
local total = ( n * ( n + 1 ) / 2 )
if m >= total then
return 1
end
local counts = signedRankCounts ( n )
local accumulated = 0
for sum = 0 , m do
accumulated = accumulated + counts [ sum + 1 ]
end

return accumulated / 2 ^ n
end



local function walshAverages ( values ) 
local averages = { }
for i = 1 , # values do
for j = i , # values do
averages [ # averages + 1 ] = ( values [ i ] + values [ j ] ) / 2
end
end
table . sort ( averages )

return averages
end







function statistics . pairedShift ( differences ) 
local n = # differences
if n < statistics . MIN_INTERVAL_SAMPLES then
return nil
end
if n > 200 then
return nil
end
local averages = walshAverages ( differences )
local total = # averages
local best = 0
local coverage = 0
for k = 1 , math . floor ( total / 2 ) do
local attained = 1 - 2 * signedRankAtMost ( n , ( k - 2 ) )
if attained >= statistics . TARGET_COVERAGE then
best = k
coverage = attained
end
end
if best < 1 then
return nil
end

return ( _G.setmetatable({ low =
averages [ best ] ,  upper =
averages [ total - best + 1 ] ,  k =
best ,  attainedCoverage =
coverage }, statistics.Interval) )

end


function statistics . pairedPValue ( differences ) 



local values = { }
for _ , value in ipairs ( differences ) do
if value ~= 0 then
values [ # values + 1 ] = value
end
end
local n = # values
if n < 4 then
return 1
end
table . sort ( values , function ( left , right ) 
return math . abs ( left ) < math . abs ( right )
end )
local ranks = { }
local positive , squared = 0 , 0
local first = 1
while first <= n do
local last = first
while last < n and math . abs ( values [ last + 1 ] ) == math . abs ( values [ first ] ) do
last = last + 1
end
local rank = ( first + last )
for index = first , last do
ranks [ index ] = rank
squared = squared + rank * rank
if values [ index ] > 0 then
positive = positive + rank
end
end
first = last + 1
end
local total = ( n * ( n + 1 ) )
if n > 200 then
return normalTwoSided ( ( positive - total / 2 ) / math . sqrt ( squared / 4 ) )
end
local lower = math . floor ( math . min ( positive , total - positive ) )
local counts = { }
for sum = 0 , lower do
counts [ sum + 1 ] = 0
end
counts [ 1 ] = 1
for _ , rank in ipairs ( ranks ) do
for sum = lower , rank , -1 do
counts [ sum + 1 ] = counts [ sum + 1 ] + counts [ sum - rank + 1 ]
end
end
local accumulated = 0
for sum = 0 , lower do
accumulated = accumulated + counts [ sum + 1 ]
end

return math . min ( 1 , 2 * accumulated / 2 ^ n )

end






local function rankSumVariance ( candidate , baseline ) 
local n , m = # candidate , # baseline
local pooled = { }
for _ , value in ipairs ( candidate ) do
pooled [ # pooled + 1 ] = value
end
for _ , value in ipairs ( baseline ) do
pooled [ # pooled + 1 ] = value
end
table . sort ( pooled )
local correction = 0
local first = 1
while first <= # pooled do
local last = first
while last < # pooled and pooled [ last + 1 ] == pooled [ first ] do
last = last + 1
end
local tied = last - first + 1
correction = correction + tied * tied * tied - tied
first = last + 1
end
local total = n + m
if total < 2 then
return 0
end

return n * m / 12 * ( total + 1 - correction / ( total * ( total - 1 ) ) )
end






function statistics . unpairedShift ( candidate , baseline ) 
local differences = { }
for _ , right in ipairs ( baseline ) do
for _ , left in ipairs ( candidate ) do
differences [ # differences + 1 ] = left - right
end
end
if # differences == 0 then
return 0 , nil
end
local estimate = statistics . median ( differences )
if # candidate < statistics . MIN_INTERVAL_SAMPLES or # baseline < statistics . MIN_INTERVAL_SAMPLES then
return estimate , nil
end









local n = # candidate
local m = # baseline
local mean = n * m / 2
local variance = rankSumVariance ( candidate , baseline )
if variance <= 0 then
return estimate , nil
end
local offset = 1.959964 * math . sqrt ( variance )
local sorted = statistics . sorted ( differences )




local lowIndex = math . floor ( mean - offset )
if lowIndex < 1 then
lowIndex = 1
end
local upperIndex = # sorted + 1 - lowIndex
if upperIndex > # sorted then
upperIndex = # sorted
end
if lowIndex > upperIndex then
return estimate , nil
end

return estimate , _G.setmetatable({ low =
sorted [ lowIndex ] ,  upper =
sorted [ upperIndex ] ,  k =
lowIndex ,  attainedCoverage =
0.95 }, statistics.Interval)

end


function statistics . unpairedPValue ( candidate , baseline ) 
local n = # candidate
local m = # baseline
if n < 3 or m < 3 then
return 1
end
local greater = 0
for _ , left in ipairs ( candidate ) do
for _ , right in ipairs ( baseline ) do
if left > right then
greater = greater + 1
elseif left == right then
greater = greater + 0.5
end
end
end
local mean = n * m / 2
local variance = rankSumVariance ( candidate , baseline )
if variance <= 0 then
return 1
end

return normalTwoSided ( ( greater - mean ) / math . sqrt ( variance ) )
end











function statistics . benjaminiHochberg ( pValues ) 
local count = # pValues
if count == 0 then
return { }
end
local order = { }
for index = 1 , count do
order [ index ] = index
end
table . sort ( order , function ( left , right ) 
return pValues [ left ] < pValues [ right ]
end )
local adjusted = { }
local running = 1
for rank = count , 1 , -1 do
local source = order [ rank ]
local scaled = pValues [ source ] * count / rank
if scaled < running then
running = scaled
end
if running > 1 then
running = 1
end
adjusted [ source ] = running
end

return adjusted
end





















function statistics . verdict ( interval , margin , adjustedPValue ) 
if not interval then
return "inconclusive"
end
local low = interval . low
local upper = interval . upper
if low > - margin and upper < margin then
return "unchanged"
end
if adjustedPValue >= statistics . ALPHA then
return "inconclusive"
end
if low >= margin then
return "regressed"
end
if upper <= - margin then
return "improved"
end

return "inconclusive"
end












function statistics . forksForPrecision ( coefficientOfVariation , precision ) 
if precision <= 0 or coefficientOfVariation <= 0 then
return statistics . MIN_INTERVAL_SAMPLES
end


local needed = math . ceil ( 1.5708 * ( 1.959964 * coefficientOfVariation / precision ) ^ 2 )
if needed < statistics . MIN_INTERVAL_SAMPLES then
return statistics . MIN_INTERVAL_SAMPLES
end

return needed
end


function statistics . coefficientOfVariation ( values ) 
local count = # values
if count < 2 then
return 0
end
local total = 0
for _ , value in ipairs ( values ) do
total = total + value
end
local mean = total / count
if mean <= 0 then
return 0
end
local squared = 0
for _ , value in ipairs ( values ) do
local delta = value - mean
squared = squared + delta * delta
end

return math . sqrt ( squared / ( count - 1 ) ) / mean
end

local __nuppExportValue= statistics ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.internal.statistics"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.internal.statistics"]=__nuppExports;return __nuppExports