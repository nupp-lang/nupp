_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.test"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local assert;__nuppExports["assert"]=function(...) return assert(...) end;local cases;__nuppExports["cases"]=function(...) return cases(...) end;local deepEqual;__nuppExports["deepEqual"]=function(...) return deepEqual(...) end;local equal;__nuppExports["equal"]=function(...) return equal(...) end;local fact;__nuppExports["fact"]=function(...) return fact(...) end;local fixture;__nuppExports["fixture"]=function(...) return fixture(...) end;local isNotExecuted;__nuppExports["isNotExecuted"]=function(...) return isNotExecuted(...) end;local isSkip;__nuppExports["isSkip"]=function(...) return isSkip(...) end;local matches;__nuppExports["matches"]=function(...) return matches(...) end;local metric;__nuppExports["metric"]=function(...) return metric(...) end;local notEqual;__nuppExports["notEqual"]=function(...) return notEqual(...) end;local notExecuted;__nuppExports["notExecuted"]=function(...) return notExecuted(...) end;local notExecutedReason;__nuppExports["notExecutedReason"]=function(...) return notExecutedReason(...) end;local raises;__nuppExports["raises"]=function(...) return raises(...) end;local requireCapability;__nuppExports["requireCapability"]=function(...) return requireCapability(...) end;local skip;__nuppExports["skip"]=function(...) return skip(...) end;local skipReason;__nuppExports["skipReason"]=function(...) return skipReason(...) end;local work;__nuppExports["work"]=function(...) return work(...) end;






















local DISPLAY_BUDGET = 512
local MISSING = { }

local function clipped ( text , budget ) 
if budget . left == 0 then
if not budget . truncated then
budget . truncated = true
return "..."
end
return ""
end
if # text <= budget . left then
budget . left = budget . left - # text
return text
end
local out = text : sub ( 1 , math . max ( 0 , budget . left - 3 ) ) .. "..."
budget . left = 0
budget . truncated = true

return out
end

local function showWithin ( value , seen , budget ) 
if value == MISSING then
return clipped ( "<missing>" , budget )
end
local kind = type ( value )
if kind ~= "table" then
if kind == "string" then
return clipped ( string . format ( "%q" , value ) , budget )
else
return clipped ( tostring ( value ) , budget )
end
end
if seen [ value ] then
return clipped ( "<cycle>" , budget )
end
seen [ value ] = true
local keys = { }
for key in pairs ( value ) do
keys [ # keys + 1 ] = key
end
table . sort ( keys , function ( left , right ) 
local leftKind , rightKind = type ( left ) , type ( right )
if leftKind ~= rightKind then
return leftKind < rightKind
end

return tostring ( left ) < tostring ( right )
end )
local parts = { clipped ( "{" , budget ) }
for index , key in ipairs ( keys ) do
if budget . left == 0 then
do break end
end
if index > 1 then
parts [ # parts + 1 ] = clipped ( ", " , budget )
end
parts [ # parts + 1 ] = clipped ( "[" , budget )
parts [ # parts + 1 ] = showWithin ( key , seen , budget )
parts [ # parts + 1 ] = clipped ( "]=" , budget )
parts [ # parts + 1 ] = showWithin ( value [ key ] , seen , budget )
end
parts [ # parts + 1 ] = clipped ( "}" , budget )
seen [ value ] = nil

return table . concat ( parts )
end

local function show ( value ) 
return showWithin ( value , { } , { left = 512 } )
end

local function indented ( text , prefix ) 
local out = text : gsub ( "\n" , "\n" .. prefix )

return out
end

local function difference ( expected , actual , message , where ) 
local wanted , got = ( showWithin ( expected , { } , { left = 512 } ) ) , ( showWithin ( actual , { } , { left = 512 } ) )
local location = where and ( "at " .. where .. ": " ) or ""
if not wanted : find ( "\n" , 1 , true ) and not got : find ( "\n" , 1 , true ) and # location + # wanted + # got <= 80 then
local detail = location .. "want " .. wanted .. ", got " .. got
if where == nil then
detail = "expected " .. wanted .. ", got " .. got
end
if message ~= nil then
detail = detail .. ": " .. message
end

return detail
end
local title = message or "values differ"
local path = where and ( "\n  at " .. where ) or ""

return title .. ":" .. path .. "\n  want: " .. indented (
wanted ,
"        "
) .. "\n  got:  " .. indented ( got , "        " )
end

local function fail ( message , level ) 
error ( message , ( level or 1 ) + 1 )
end

local function serializationSafe ( value , seen ) 
local kind = type ( value )
if kind == "nil" or kind == "boolean" or kind == "string" then
return true
elseif kind == "number" then
return value == value and value ~= math . huge and value ~= - math . huge
elseif kind ~= "table" then
return false
end
seen = seen or { }
if seen [ value ] then
return false
end
seen [ value ] = true
local numericKeys = 0
local stringKeys = 0
local largestIndex = 0
for key , item in pairs ( value ) do
local keyKind = type ( key )
if keyKind == "string" then
stringKeys = stringKeys + 1
elseif keyKind == "number" and key == math . floor ( key ) and key >= 1 and key < math . huge then
numericKeys = numericKeys + 1
largestIndex = math . max ( largestIndex , key )
else
seen [ value ] = nil
return false
end
if not serializationSafe ( item , seen ) then
seen [ value ] = nil
return false
end
end
seen [ value ] = nil






return numericKeys == 0 or ( stringKeys == 0 and largestIndex == numericKeys )
end



assert=function ( value , ... ) 
if value then
return value , ...
end
local message = ...
local detail = "expected a truthy value, got " .. ( showWithin ( value , { } , { left = 512 } ) )
if message ~= nil then
detail = detail .. ": " .. tostring ( message )
end
fail ( detail , 2 )
end ;__nuppExports["assert"]=assert



equal=function ( actual , expected , message ) 
if actual == expected then
return actual
end
fail ( difference ( expected , actual , message ) , 2 )
end ;__nuppExports["equal"]=equal

local function keyRank ( key ) 
local kind = type ( key )
if kind == "boolean" then
return 1
elseif kind == "number" then
return 2
elseif kind == "string" then
return 3
else
return nil
end
end

local function structuralKeys ( value ) 
local keys = { }
for key in pairs ( value ) do
if keyRank ( key ) == nil then
return nil , type ( key )
end
keys [ # keys + 1 ] = key
end
table . sort ( keys , function ( left , right ) 
local leftRank , rightRank = keyRank ( left ) , keyRank ( right )
if leftRank ~= rightRank then
return leftRank < rightRank
elseif leftRank == 1 then
return left == false and right == true
end

return left < right
end )

return keys , nil
end

local function childPath ( path , key ) 
if type ( key ) == "string" and key : find ( "^[%a_][%w_]*$" ) then
return path .. "." .. key
end

return path .. "[" .. ( showWithin ( key , { } , { left = 512 } ) ) .. "]"
end

local function structuralDifference ( actual , expected , path , seen ) 
if rawequal ( actual , expected ) then
return nil , nil , nil
end
local actualKind , expectedKind = type ( actual ) , type ( expected )
if actualKind ~= "table" or expectedKind ~= "table" then
if actual == expected then
return nil , nil , nil
end

return path , expected , actual
end
local actualMeta , expectedMeta = getmetatable ( actual ) , getmetatable ( expected )
if actualMeta ~= expectedMeta then
return path .. ".<metatable>" , expectedMeta , actualMeta
elseif type ( actualMeta ) == "table" and rawget ( actualMeta , "__eq" ) ~= nil then
if actual == expected then
return nil , nil , nil
end

return path , expected , actual
end
local paired = seen [ actual ]
if paired ~= nil and paired [ expected ] then
return nil , nil , nil
end
if paired == nil then
paired = { }
seen [ actual ] = paired
end
paired [ expected ] = true

local expectedKeys , expectedKeyProblem = structuralKeys ( expected )
if expectedKeys == nil then
return path .. ".<key>" , "boolean, number, or string key" , ( expectedKeyProblem ) .. " key"
end
local actualKeys , actualKeyProblem = structuralKeys ( actual )
if actualKeys == nil then
return path .. ".<key>" , "boolean, number, or string key" , ( actualKeyProblem ) .. " key"
end
for _ , key in ipairs ( expectedKeys ) do
local nestedPath = childPath ( path , key )
local actualValue = rawget ( actual , key )
if actualValue == nil then
return nestedPath , expected [ key ] , MISSING
end
local differingPath , wanted , got = structuralDifference ( actualValue , expected [ key ] , nestedPath , seen )
if differingPath ~= nil then
return differingPath , wanted , got
end
end
for _ , key in ipairs ( actualKeys ) do
if rawget ( expected , key ) == nil then
return childPath ( path , key ) , MISSING , actual [ key ]
end
end

return nil , nil , nil
end










deepEqual=function ( actual , expected , message ) 
local path , wanted , got = structuralDifference ( actual , expected , "value" , { } )
if path ~= nil then
fail ( difference ( wanted , got , message , path ) , 2 )
end

return actual
end ;__nuppExports["deepEqual"]=deepEqual



notEqual=function ( actual , unwanted , message ) 
if actual ~= unwanted then
return actual
end
local detail = "did not expect " .. ( showWithin ( unwanted , { } , { left = 512 } ) )
if message ~= nil then
detail = detail .. ": " .. message
end
fail ( detail , 2 )
end ;__nuppExports["notEqual"]=notEqual



matches=function ( value , pattern , message ) 
if type ( value ) == "string" and value : find ( pattern ) then
return value
end
local detail = "expected " .. ( showWithin ( value , { } , { left = 512 } ) ) .. " to match " .. ( showWithin ( pattern , { } , { left = 512 } ) )
if message ~= nil then
detail = detail .. ": " .. message
end
fail ( detail , 2 )
end ;__nuppExports["matches"]=matches



raises=function ( fn , pattern ) 
local ok , problem = pcall ( fn )
if ok then
fail ( "expected function to raise an error" , 2 )
end
if pattern ~= nil and not tostring ( problem ) : find ( pattern ) then
fail ( "expected error " .. ( showWithin ( problem , { } , { left = 512 } ) ) .. " to match " .. ( showWithin ( pattern , { } , { left = 512 } ) ) , 2 )
end

return problem
end ;__nuppExports["raises"]=raises

local skipped = { }
local notExecutedTag = { }
local lifecycleNames = { beforeAll = true , afterAll = true , beforeEach = true , afterEach = true , }
local runnerCaseNames = { [ "<shard>" ] = true , [ "<unrun>" ] = true , }

local function caseContext ( ) 
return rawget ( _G , "__NUPP_TEST_CASE_CONTEXT" )
end


skip=function ( reason ) 
error ( { skip = skipped , reason = reason } , 0 )
end ;__nuppExports["skip"]=skip


isSkip=function ( value ) 
return type ( value ) == "table" and value . skip == skipped
end ;__nuppExports["isSkip"]=isSkip


skipReason=function ( value ) 
if isSkip ( value ) then
return value . reason
end

return nil
end ;__nuppExports["skipReason"]=skipReason










cases=function ( rows , name , run ) 
local rowCount = 0
local lastRow = 0
if type ( rows ) == "table" then
for key in pairs ( rows ) do
if type ( key ) ~= "number" or key ~= math . floor ( key ) or key < 1 or key == math . huge then
fail ( "parameterized case rows must be a dense JSON-compatible sequence" , 2 )
end
rowCount = rowCount + 1
lastRow = math . max ( lastRow , key )
end
end
if type ( rows ) ~= "table" or lastRow ~= rowCount then
fail ( "parameterized case rows must be a dense JSON-compatible sequence" , 2 )
end
local expanded = { }
for index , item in ipairs ( rows ) do
if not serializationSafe ( item ) then
fail ( "parameterized case row " .. index .. " is not serialization-safe" , 2 )
end
local caseName = name ( item , index )
if type ( caseName ) ~= "string" or caseName == "" then
fail ( "parameterized case names must be non-empty strings" , 2 )
elseif caseName : find ( "[%c]" ) then
fail ( "parameterized case names must not contain control characters" , 2 )
elseif lifecycleNames [ caseName ] then
fail ( "parameterized case name " .. ( showWithin ( caseName , { } , { left = 512 } ) ) .. " is reserved for a lifecycle hook" , 2 )
elseif runnerCaseNames [ caseName ] then
fail ( "parameterized case name " .. ( showWithin ( caseName , { } , { left = 512 } ) ) .. " is reserved by the test runner" , 2 )
elseif expanded [ caseName ] ~= nil then
fail ( "duplicate parameterized case name " .. ( showWithin ( caseName , { } , { left = 512 } ) ) , 2 )
end
local row = item
local rowIndex = index
local expandedCase = function ( ) 
return run ( row , rowIndex )
end
expanded [ caseName ] = expandedCase
local definitions = rawget ( _G , "__NUPP_TEST_CASE_DEFINITIONS" )
local hostDebug = debug
if type ( definitions ) == "table" and hostDebug ~= nil then
local definition = hostDebug . getinfo ( run , "S" )
if definition ~= nil then
definitions [
expandedCase
] = { file = ( definition . source or "" ) : gsub ( "^@" , "" ) , line = definition . linedefined , }
end
end
end

return expanded
end ;__nuppExports["cases"]=cases



notExecuted=function ( reason ) 
if ( rawget ( _G , "__NUPP_TEST_CASE_CONTEXT" ) ) == nil then
fail ( "notExecuted must be called while a test case is running" , 2 )
elseif type ( reason ) ~= "string" or reason == "" then
fail ( "not-executed reasons must be non-empty strings" , 2 )
end
error ( { notExecuted = notExecutedTag , reason = reason } , 0 )
end ;__nuppExports["notExecuted"]=notExecuted









requireCapability=function ( name , available , evidence ) 
local activeCase = ( rawget ( _G , "__NUPP_TEST_CASE_CONTEXT" ) )
if activeCase == nil then
fail ( "requireCapability must be called while a test case is running" , 2 )
elseif type ( name ) ~= "string" or name == "" then
fail ( "capability names must be non-empty strings" , 2 )
elseif type ( available ) ~= "boolean" then
fail ( "capability availability must be a boolean" , 2 )
elseif evidence ~= nil and not serializationSafe ( evidence ) then
fail ( "capability evidence must be JSON-compatible" , 2 )
end
activeCase . capabilities [ # activeCase . capabilities + 1 ] = { name = name , available = available , evidence = evidence , }
if not available then
notExecuted ( "missing capability " .. name )
end
end ;__nuppExports["requireCapability"]=requireCapability




fact=function ( name , value ) 
local activeCase = ( rawget ( _G , "__NUPP_TEST_CASE_CONTEXT" ) )
if activeCase == nil then
fail ( "fact must be called while a test case is running" , 2 )
elseif type ( name ) ~= "string" or name == "" then
fail ( "fact names must be non-empty strings" , 2 )
elseif value == nil then
fail ( "fact values must not be nil" , 2 )
elseif not serializationSafe ( value ) then
fail ( "fact values must be JSON-compatible" , 2 )
end
activeCase . facts [ # activeCase . facts + 1 ] = { name = name , value = value }
end ;__nuppExports["fact"]=fact





metric=function ( name , value , unit ) 
local activeCase = ( rawget ( _G , "__NUPP_TEST_CASE_CONTEXT" ) )
if activeCase == nil then
fail ( "metric must be called while a test case is running" , 2 )
elseif type ( name ) ~= "string" or name == "" then
fail ( "metric names must be non-empty strings" , 2 )
elseif type ( value ) ~= "number" or value ~= value or value == math . huge or value == - math . huge then
fail ( "metric values must be finite numbers" , 2 )
elseif unit ~= nil and type ( unit ) ~= "string" then
fail ( "metric units must be strings" , 2 )
end
local key = name .. "\0" .. ( unit or "" )
local existing = activeCase . metrics [ key ]
if existing == nil then
activeCase . metrics [ key ] = { name = name , value = value , unit = unit }
else
existing . value = existing . value + value
end
end ;__nuppExports["metric"]=metric




work=function ( name , count ) 
if type ( count ) ~= "number" or count ~= math . floor ( count ) or count == math . huge or count < 0 then
fail ( "work counts must be non-negative integers" , 2 )
end
metric ( name , count , "count" )
end ;__nuppExports["work"]=work











fixture=function ( key , produce ) 
local activeCase = ( rawget ( _G , "__NUPP_TEST_CASE_CONTEXT" ) )
if activeCase == nil then
fail ( "fixture must be called while a test case is running" , 2 )
end

local path , value , reused = activeCase . fixture ( key , produce )
activeCase . fixtures [ # activeCase . fixtures + 1 ] = { key = key , path = path , reused = reused }

return path , value , reused
end ;__nuppExports["fixture"]=fixture


isNotExecuted=function ( value ) 
return type ( value ) == "table" and value . notExecuted == notExecutedTag
end ;__nuppExports["isNotExecuted"]=isNotExecuted


notExecutedReason=function ( value ) 
if isNotExecuted ( value ) then
return value . reason
end

return nil
end ;__nuppExports["notExecutedReason"]=notExecutedReason
 end);if not __nuppOk then package.loaded["nupp.test"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.test"]=__nuppExports;return __nuppExports