_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);




























local cst = require ( "nupp.compiler.cst" )
local state = require ( "nupp.compiler.check.state" )

local nosuspend = { }




local MAX_CHAIN = 8













function nosuspend . install ( c )
local ops = { }


local candidates = { }




function ops . call ( call )
if c . noSuspendDepth <= 0 or not call then
return
end
candidates [
# candidates + 1
] = { call = call , calleeType = call . calleeType or call . signatureType , code = "NUPP2701" }
end


local callbackRegions = { }
local cleanupContracts = { }




function ops . cleanup ( cleanup , at )
cleanupContracts [ # cleanupContracts + 1 ] = { cleanup = cleanup , at = at }
end









function ops . callback ( body , where )
if not body then
return
end
callbackRegions [ # callbackRegions + 1 ] = { body = body , where = where }
end








local function firstSuspendingCall ( queries , body )
local found = nil
local function walk ( node )
if not node or found or cst . isToken ( node ) then
return
end
local kind = node . kind
if kind == "call" or kind == "safeCall" or kind == "methodCall" then
local reached = queries . callee and queries . callee ( node ) or nil
if reached and reached . summary and reached . summary . yields then
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

local function chain ( queries , info )
local related , seen , current = { } , { } , info
while current and # related < MAX_CHAIN do
if seen [ current ] or not current . body then
break
end
seen [ current ] = true
local step = firstSuspendingCall ( queries , current . body )
if not step then
break
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
msg = ( "%s may suspend" ) : format ( token . text ) ,
}
end
current = step . info
end

return related
end



local function callsWithin ( body , into )
if not body or cst . isToken ( body ) then
return
end
local kind = body . kind
if kind == "funcExpr" or kind == "shortfn" or kind == "localFuncStmt" or kind == "funcStmt" then
return
end
if kind == "call" or kind == "safeCall" or kind == "methodCall" then
into [ # into + 1 ] = body
end
for _ , child in ipairs ( body . stats or { } ) do
callsWithin ( child , into )
end
for _ , child in ipairs ( body ) do
callsWithin ( child , into )
end
end




function ops . sweep ( queries )
for _ , candidate in ipairs ( cleanupContracts ) do
local cleanup = candidate . cleanup
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
if mayYield then
c . diag (
"NUPP2701" ,
candidate . at ,
( "cleanup %q may suspend while an obligation is being discharged" ) : format ( cleanup . name ) ,
nil ,
{ help = "make every cleanup call non-suspending, or move the suspension before cleanup begins" }
)
end
end
for _ , region in ipairs ( callbackRegions ) do
local found = { }
callsWithin ( region . body , found )
for _ , call in ipairs ( found ) do
candidates [
# candidates + 1
] = { call = call , calleeType = call . calleeType , code = "NUPP2702" , where = region . where , }
end
end
for _ , candidate in ipairs ( candidates ) do
local call = candidate . call
local callee = call . obj
local token = callee and ( callee . token or callee . name ) or nil
local info = queries and queries . callee and queries . callee ( call ) or nil
local mayYield , why = nil , nil
if info and info . summary and not info . external then


if info . summary . top then
mayYield , why = true , "reaches code with unknown effects"
else
mayYield = info . summary . yields == true
why = "may suspend"
end
else
local target = candidate . calleeType
if target and target . tag == "func" then
mayYield = not target . noYield
why = "may suspend"
else


mayYield , why = true , "cannot be resolved, so it may suspend"
end
end
if mayYield then
local named = token and ( "`" .. token . text .. "`" ) or "this call"
local message
if candidate . code == "NUPP2702" then



message = (
"%s %s, and %s cannot yield across the C call that reaches it"
) : format ( named , why , candidate . where )
else
message = ( "%s %s, and this region forbids suspending" ) : format ( named , why )
end
c . diag ( candidate . code , callee or call , message , nil , {
help = "call something that cannot suspend, declare the callee's type "
.. "`nosuspend function(...)`, or move this out of the region" ,
related = info and chain ( queries , info ) or nil ,
} )
end
end
end

return ops
end

return nosuspend
