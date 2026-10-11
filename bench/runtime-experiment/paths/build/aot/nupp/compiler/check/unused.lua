_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






























local state = require ( "nupp.compiler.check.state" )

local unused = { }














function unused . install ( c ) 
local ops = { }





c . reads = { }


local candidates





= { }







function ops . declared ( tok , entry , kind ) 
if not tok or not entry or not entry . definition then
return
end


if c . declarationFile then
return
end


if tok . text : sub ( 1 , 1 ) == "_" then
return
end



if c . ownershipKind ( entry . t ) then
return
end
candidates [ # candidates + 1 ] = {
tok = tok ,
definition = entry . definition ,
kind = kind ,
module = entry . requiredModule ,


allowed = c . suppressed ( "unused-binding" ) ,
}
end



function ops . sweep ( ) 
for _ , candidate in ipairs ( candidates ) do
if not candidate . allowed and not c . reads [ candidate . definition ] then
local name = candidate . tok . text
local message , help
if candidate . kind == "require" and candidate . module then
message = ("nothing reads %s after requiring %q") : format ( name , candidate . module )
help = "delete the require, or call require without binding its result when loading it is intentional"
elseif candidate . kind == "function" then
message = ("nothing uses %s") : format ( name )
help = "delete it, or return it from the module"
else
message = ("nothing uses %s") : format ( name )
help = "delete the binding, or name it _ if it is deliberately unused"
end
c . diag ( "unused-binding" , candidate . tok , message , nil , { help = help } )
end
end
end

return ops
end

local __nuppExportValue= unused ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.unused"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.unused"]=__nuppExports;return __nuppExports