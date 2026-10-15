_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local lexer = require ( "nupp.compiler.syntax.lexer" )

local triviaarena = require ( "nupp.compiler.syntax.triviaarena" )
local tableProvider = require ( "nupp.compiler.syntax.triviaarena.table" )

local bench = { }

function bench . setup ( ) 
triviaarena . install ( tableProvider )
return true
end



function bench . lex ( source ) 
local tokens , errors = lexer . lex ( source , "bench.nupp" )
local sum = 0
for i , tok in ipairs ( tokens ) do
sum = ( sum * 31 + # tok . text + tok . line * 7 + tok . col ) % 1000000007
end

return # tokens , # errors , sum
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.lexbench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.lexbench"]=__nuppExports;return __nuppExports