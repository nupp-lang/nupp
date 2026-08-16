_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);




































local state = require ( "nupp.compiler.check.state" )

local loopclosure = { }
























local function leavesFirstPass ( body )
local stats = body and body . kind == "block" and body . stats or { }
local last = stats [ # stats ]
if not last then
return false
end

return last . kind == "returnStmt" or last . kind == "breakStmt"
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
for i = # c . captureWatches , 1 , - 1 do
if c . captureWatches [ i ] == watch then
table . remove ( c . captureWatches , i )
break
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
message = "this function is built once per iteration and reads the "
.. "iteration, so it cannot be declared above the loop, and LuaJIT "
.. "does not record building a function, so this loop never compiles" ,
help = "hand what varies to a function declared outside the loop, so "
.. "the loop calls one rather than builds one" ,
suppressed = not (
watch . enclosingBody and watch . enclosingBody . jitRequired
) and c . suppressed ( "jit-loop-closure" ) ,
}

return
end
c . diag (
"NUPP2505" ,
at ,
"this function is built once per iteration but does not use the "
.. "iteration, so every one of them is the same function, and "
.. "building one is what keeps the loop from compiling" ,
nil ,
{ help = "declare it once above the loop and pass the name" }
)
end

return ops
end

return loopclosure
