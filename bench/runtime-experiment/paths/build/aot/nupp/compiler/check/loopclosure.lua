_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()







































local state = require ( "nupp.compiler.check.state" )

local loopclosure = { }






















local function leavesFirstPass ( body ) 
local stats = body and body . kind == "block" and body . stats or { }
local last = stats [ # stats ]
while last and ( last . kind == "pragmaStmt" or last . kind == "exportStmt" ) do
last = last . stat
end
if not last then
return false
end
local kind = last . kind
if kind == "returnStmt" or kind == "breakStmt" then
return true
elseif kind == "doStmt" or kind == "withStmt" then
return leavesFirstPass ( last . body )
elseif kind == "ifStmt" and last . elseClause then
for _ , clause in ipairs ( last . clauses or { } ) do
if not leavesFirstPass ( clause . body ) then
return false
end
end

return leavesFirstPass ( last . elseClause . body )
end

return false
end





function loopclosure . install ( c ) 
local ops = { }



local loops = { }


local returning = false






local judged = { }




function ops . push ( body ) 
local loop = { depth = c . scope . depth , functionDepth = c . functionDepth , once = leavesFirstPass ( body ) , }



loop . enclosingBody = c . functionBodies [ # c . functionBodies ]
loops [ # loops + 1 ] = loop
end


function ops . pop ( ) 
loops [ # loops ] = nil
end







function ops . setReturning ( value ) 
local was = returning
returning = value
return was
end












function ops . begin ( enclosing ) 
if returning then
return nil
end
local loop = loops [ # loops ]
if not loop or loop . once or loop . functionDepth ~= enclosing then
return nil
end
local watch = { depth = c . scope . depth , floor = loop . depth , captured = false , enclosingBody = loop . enclosingBody , }
c . captureWatches [ # c . captureWatches + 1 ] = watch

return watch
end






function ops . finish ( watch , at ) 
if not watch then
return
end
for i = # c . captureWatches , 1 , -1 do
if c . captureWatches [ i ] == watch then
table . remove ( c . captureWatches , i )
do break end
end
end
if judged [ at ] then
return
end
judged [ at ] = true
if watch . captured then




c . jitHazards [
# c . jitHazards + 1
] = {
code = "jit-loop-closure" ,
at = at ,
body = watch . enclosingBody ,
message = "this function is built once per iteration and reads the iteration, so it cannot be declared above the loop, and LuaJIT does not record building a function, so this loop never compiles"

,
help = "hand what varies to a function declared outside the loop, so the loop calls one rather than builds one"
,
suppressed = not ( watch . enclosingBody and watch . enclosingBody . jitRequired )
and c . suppressed ( "jit-loop-closure" ) ,
}

return
end







c . jitHazards [
# c . jitHazards + 1
] = {
code = "loop-invariant-closure" ,
at = at ,
body = watch . enclosingBody ,
message = "this function is built once per iteration but does not use the iteration, so every one of them is the same function, and building one is what keeps the loop from compiling" ,
help = "declare it once above the loop and pass the name" ,
suppressed = not ( watch . enclosingBody and watch . enclosingBody . jitRequired ) ,
}
if not ( watch . enclosingBody and watch . enclosingBody . jitRequired ) then
c . diag ( "NUPP2505" , at , "this function is built once per iteration but does not use the iteration, so every one of them is the same function, and building one is what keeps the loop from compiling" , nil , { help = "declare it once above the loop and pass the name" } )
end
end

return ops
end

local __nuppExportValue= loopclosure ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.loopclosure"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.loopclosure"]=__nuppExports;return __nuppExports