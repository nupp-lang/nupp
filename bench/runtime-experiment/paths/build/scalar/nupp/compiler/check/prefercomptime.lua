_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local cst = require ( "nupp.compiler.syntax.cst" )
local lints = require ( "nupp.compiler.lints" )
local state = require ( "nupp.compiler.check.state" )

local prefercomptime = { }

local WORK = {
call = true ,
forinStmt = true ,
fornumStmt = true ,
methodCall = true ,
repeatStmt = true ,
tableExpr = true ,
whileStmt = true ,
}

local function worthwhile ( node ) 
local found = false
local valid = true

local function walk ( value ) 
if not valid or not value or cst . isToken ( value ) then
return
end
if value . kind == "comptimeExpr" then
valid = false
return
end
if WORK [ value . kind ] then
found = true
end
if value . kind == "funcbody" or value . kind == "shortfn" or value . kind == "funcExpr" then
return
end
for _ , child in ipairs ( value ) do
walk ( child )
end
end

walk ( node )

return valid and found
end

local function evaluate ( c , body ) 
local source = "comptime do\n" .. cst . textOf ( body . body ) .. "\nend"
local comptime = require (
"nupp.compiler.comptime"
)
local quoted , _ , failure , envelope = comptime . evaluateDirect ( body , body . body , { } , { } , c . comptimeFunctions )
if failure or envelope or not quoted or quoted : sub ( 1 , 1 ) == "{" then
return nil , source
end

return quoted , source
end

local function fix ( c , body ) 
local block = body . body
local first , last = cst . firstToken ( block ) , cst . lastToken ( block )
local source = c . result and c . result . source
if not first or not last or type ( source ) ~= "string" then
return nil
end
local finish = last . offset + # last . text
local original = source : sub ( first . offset , finish - 1 )
local indent = string . rep ( " " , math . max ( first . col - 1 , 0 ) )
local inner = indent .. "    "
local normalized = original : gsub ( "\n" .. indent , "\n" )
local replacement = "return comptime do\n" .. inner .. normalized : gsub (
"\n" ,
"\n" .. inner
) .. "\n" .. indent .. "end"

return {
c . edits . fix ( "evaluate the body with `comptime do`" , {
offset = first . offset ,
length = finish - first . offset ,
newText = replacement ,
} )
}
end



function prefercomptime . check ( c , declaration , body , receiver ) 
local lint = lints . get ( "prefer-comptime" )
if not lint
or lints . level ( lint , c . lintConfig ) == "off"
or c . suppressed ( lint . code )
or declaration . comptimeFunction
or receiver
or body . generics
or # ( body . params or { } ) ~= 0
or not worthwhile ( body . body )
then
return
end

local quoted , candidate = evaluate ( c , body )
if not quoted or not candidate or # candidate < # quoted + 32 then
return
end

c . diag (
lint . code ,
declaration . name or body ,
"this no-input function does closed deterministic work every time it is called" ,
fix ( c , body ) ,
{ help = ("evaluate the body with `comptime do`; it reduces to `%s`") : format ( quoted ) }
)
end

local __nuppExportValue= prefercomptime ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.prefercomptime"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.prefercomptime"]=__nuppExports;return __nuppExports