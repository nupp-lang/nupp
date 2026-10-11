_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





























local cst = require ( "nupp.compiler.syntax.cst" )
local state = require ( "nupp.compiler.check.state" )
local T = require ( "nupp.compiler.types" )

local nosuspend = { }




local MAX_CHAIN = 8

















function nosuspend . install ( c ) 
local ops = { }


local candidates = { }



local obligations = { }










function ops . obligation ( call ) 
if not call or c . unsafeDepth > 0 then
return
end
local live = c . liveSuspensionObligation ( )
if live then
obligations [ # obligations + 1 ] = { call = call , obligation = live }
end
end




function ops . call ( call ) 
ops . obligation ( call )
if c . noSuspendDepth <= 0 or not call then
return
end


candidates [ # candidates + 1 ] = { call = call , code = "NUPP2701" , construction = call . isNew == true }
end





local function signatureOf ( call ) 
local target = call . calleeType
if target and target . tag == "func" then
return target
end
local signature = call . signatureType
if signature and signature . tag == "func" then
return signature
end

return target
end











function ops . iterator ( stat , iteratorType ) 
if c . noSuspendDepth <= 0 or not stat then
return
end
candidates [
# candidates + 1
] = {
call = stat ,
calleeType = iteratorType and iteratorType . tag == "func" and iteratorType or nil ,
code = "NUPP2701" ,
iterator = true ,
}
end












function ops . contract ( site , operation ) 
if c . noSuspendDepth <= 0 or not site then
return nil
end
local candidate = { call = site , calleeType = nil , code = "NUPP2701" , operation = operation }
candidates [ # candidates + 1 ] = candidate

return candidate
end


local regions = { }








function ops . region ( stat ) 
if stat then
regions [ # regions + 1 ] = stat
end
end


local callbackRegions = { }
local cleanupContracts = { }









function ops . cleanup ( cleanup , at ) 
if c . noSuspendDepth <= 0 then
return
end
cleanupContracts [ # cleanupContracts + 1 ] = { cleanup = cleanup , at = at }
end









function ops . callback ( body , where ) 
if not body then
return
end
callbackRegions [ # callbackRegions + 1 ] = { body = body , where = where }
end








local function firstSuspendingCall ( queries , body , flag ) 
local found = nil

local function walk ( node ) 
if not node or found or cst . isToken ( node ) then
return
end
local kind = node . kind
if kind == "call" or kind == "safeCall" or kind == "methodCall" then
local reached = queries . callee and queries . callee ( node ) or nil
if reached and reached . summary and reached . summary [ flag ] then
found = { info = reached , at = node }
return
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

walk ( body )

return found
end

local function chain ( queries , info , flag ) 
local related , seen , current = { } , { } , info
while current and # related < 8 do
if seen [ current ] or not current . body then
do break end
end
seen [ current ] = true
local step = firstSuspendingCall ( queries , current . body , flag or "yields" )
if not step then
do break end
end
local callee = step . at . obj
local token = callee and ( callee . token or callee . name ) or nil
if token then
related [
# related + 1
] = {
line = token . line ,
col = token . col ,
offset = token . offset ,
length = # token . text ,
msg = ("%s may suspend") : format ( token . text ) ,
}
end
current = step . info
end

return related
end



local function callsWithin ( body , into , seen ) 
if not body or cst . isToken ( body ) then
return
end
seen = seen or { }
if seen [ body ] then
return
end
seen [ body ] = true
local kind = body . kind
if kind == "funcExpr" or kind == "shortfn" or kind == "localFuncStmt" or kind == "funcStmt" then
return
end
if kind == "call" or kind == "safeCall" or kind == "methodCall" then
into [ # into + 1 ] = body
end
for _ , child in ipairs ( body . stats or { } ) do
callsWithin ( child , into , seen )
end
for _ , child in ipairs ( body ) do
callsWithin ( child , into , seen )
end
end



local function cleanupMayYield ( cleanup , queries , ownerType ) 
if cleanup and cleanup . kind == "method" then
local owner = ownerType and T . unwrapOwnership ( ownerType ) or nil
local method = owner and owner . tag == "nominal" and owner . byname [ cleanup . name ] or nil
method = method and T . unwrapOwnership ( method ) or nil
return method == nil or method . tag ~= "func" or method . noYield ~= true
end
local token = cleanup and cleanup . token
local info = token and queries and queries . known and queries . known ( token ) or nil
local mayYield = false
if cleanup and cleanup . functionType and cleanup . functionType . foreign then
mayYield = false
elseif info and info . summary then
mayYield = info . summary . top == true or info . summary . external == true or info . summary . yields == true
if mayYield and info . body then
local calls = { }
callsWithin ( info . body , calls )
local allTypedNonYielding = # calls > 0
for _ , call in ipairs ( calls ) do
local target = call . calleeType or call . signatureType



if call . ownershipIntrinsic then
target = nil
elseif not target or target . tag ~= "func" or not target . noYield then
allTypedNonYielding = false
end
end
if allTypedNonYielding then
mayYield = false
end
end
elseif cleanup and cleanup . functionType and cleanup . functionType . tag == "func" then
mayYield = cleanup . functionType . noYield ~= true and cleanup . visibleBody == true
end

return mayYield
end



local function terminalOf ( cleanup , ownerType ) 
local operation = cleanup
while operation and operation . kind == "field" do
local owner = ownerType and T . unwrapOwnership ( ownerType ) or nil
ownerType = owner and owner . tag == "nominal" and owner . byname [ operation . field ] or nil
operation = operation . cleanup
end
if operation and ( operation . kind == "function" or operation . kind == "method" ) then
return operation , ownerType
end

return nil , nil
end





local function dischargedWithin ( body , into ) 
if not body or cst . isToken ( body ) then
return
end
local kind = body . kind
if kind == "funcExpr" or kind == "shortfn" or kind == "localFuncStmt" or kind == "funcStmt" then
return
end
for _ , owner in ipairs ( body . automaticOwners or { } ) do
for _ , cleanup in ipairs ( owner . cleanups or { } ) do
into [ # into + 1 ] = { cleanup = cleanup , at = body , ownerType = owner . entry and owner . entry . t }
end
end
if kind == "withStmt" then
for _ , binding in ipairs ( body . bindings or { } ) do
for _ , cleanup in ipairs ( binding . ownerCleanups or { } ) do
into [ # into + 1 ] = { cleanup = cleanup , at = binding . expr or body , ownerType = binding . acquiredType }
end
end
end
if body . ownershipIntrinsic == "drop" or body . ownershipIntrinsic == "attemptAll" then
for _ , cleanup in ipairs ( body . ownerCleanups or { } ) do
into [ # into + 1 ] = { cleanup = cleanup , at = body , ownerType = body . ownerType }
end
end
for _ , child in ipairs ( body . stats or { } ) do
dischargedWithin ( child , into )
end
for _ , child in ipairs ( body ) do
dischargedWithin ( child , into )
end
end




function ops . sweep ( queries ) 



for _ , region in ipairs ( regions ) do
local discharged = { }
dischargedWithin ( region . body , discharged )
local reported = { }
for _ , candidate in ipairs ( discharged ) do
local terminal , receiverType = terminalOf ( candidate . cleanup , candidate . ownerType )
if terminal and not reported [ terminal ] and cleanupMayYield ( terminal , queries , receiverType ) then
reported [ terminal ] = true
c . diag (
"NUPP2701" ,
candidate . at ,
("cleanup %q may suspend, and this region forbids suspending") : format ( terminal . name ) ,
nil ,
{ help = "discharge the owner outside the region, or give it a terminal that cannot suspend" }
)
end
end
end
for _ , candidate in ipairs ( obligations ) do
local call = candidate . call

if not call . rawYield then
local info = queries and queries . callee and queries . callee ( call ) or nil
if info and info . summary and info . summary . rawYields and not info . external then
local callee = call . obj
local token = callee and ( callee . token or callee . name ) or nil
c . diag (
"NUPP2603" ,
callee or call ,
("%s reaches a raw coroutine.yield, and temporal obligation %q is live")

: format ( token and ( "`" .. token . text .. "`" ) or "this call" , candidate . obligation ) ,
nil ,
{
help = "suspend inside a `with` installation scope, where a handler is responsible for resuming or cancelling it"
,
related = chain ( queries , info , "rawYields" ) ,
}
)
end
end
end
for _ , candidate in ipairs ( cleanupContracts ) do
local cleanup = candidate . cleanup
if cleanupMayYield ( cleanup , queries ) then
c . diag (
"NUPP2701" ,
candidate . at ,
("cleanup %q may suspend, and this region forbids suspending") : format ( cleanup . name ) ,
nil ,
{ help = "discharge the owner outside the region, or give it a terminal that cannot suspend" }
)
end
end
for _ , region in ipairs ( callbackRegions ) do
local found = { }
callsWithin ( region . body , found )
for _ , call in ipairs ( found ) do
candidates [ # candidates + 1 ] = { call = call , code = "NUPP2702" , where = region . where }
end
end
for _ , candidate in ipairs ( candidates ) do
local call = candidate . call
local callee = call . obj
local token = callee and ( callee . token or callee . name ) or nil
if candidate . iterator then
local header = call . exprs and call . exprs [ 1 ] or nil
token = header and cst . firstToken ( header ) or nil
end
local info = queries and queries . callee and queries . callee ( call ) or nil
local mayYield , why = nil , nil
if candidate . construction and not call . constructorEntry then


mayYield = false
elseif info and info . summary and not info . external then


if info . summary . top then
mayYield , why = true , "reaches code with unknown effects"
else
mayYield = info . summary . yields == true
why = "may suspend"
end
else
local target = candidate . calleeType
if target == nil and not candidate . iterator and not candidate . operation then
target = signatureOf ( call )
end
if target and target . tag == "func" then
mayYield = not target . noYield
why = "may suspend"
else


mayYield , why = true , "cannot be resolved, so it may suspend"
end
end
if mayYield then
local named = token and ( "`" .. token . text .. "`" ) or "this call"
if candidate . iterator then
named = "the iterator " .. named
elseif candidate . operation then
named = "`" .. candidate . operation .. "`"
end
local message
if candidate . code == "NUPP2702" then



message = ("%s %s, and %s cannot yield across the C call that reaches it")

: format ( named , why , candidate . where )
else
message = ("%s %s, and this region forbids suspending") : format ( named , why )
end
c . diag ( candidate . code , callee or call , message , nil , {
help = "call something that cannot suspend, declare the callee's type `@nosuspend function(...)`, or move this out of the region"
,
related = info and chain ( queries , info ) or nil ,
} )
end
end
end

return ops
end

local __nuppExportValue= nosuspend ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.nosuspend"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.nosuspend"]=__nuppExports;return __nuppExports