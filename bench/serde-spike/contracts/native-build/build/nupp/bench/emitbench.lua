_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local parser = require ( "nupp.compiler.syntax.parser" )
local checkMod = require ( "nupp.compiler.check" )
local envMod = require ( "nupp.compiler.project.env" )
local triviaarena = require ( "nupp.compiler.syntax.triviaarena" )
local tableProvider = require ( "nupp.compiler.syntax.triviaarena.table" )
local lower = require ( "nupp.compiler.vm.lower" )

local bench = { }




function bench . emit ( source , moduleName ) 
triviaarena . install ( tableProvider )
local entry = moduleName or "vm.input"
local path = entry : gsub ( "%." , "/" ) .. ".nupp"
local result = parser . parse ( source , path )
assert ( # result . errors == 0 , "input did not parse" )
local env = envMod . new ( "." , { memoryOnly = true , cache = false , nativeCompilerServices = false } )
local diags = checkMod . check ( result , path , env , { } )
for _ , d in ipairs ( diags ) do
if d . severity == "error" or not d . severity then
error ( tostring ( d . code ) .. ": " .. tostring ( d . msg ) )
end
end

return lower . emit (
entry ,
{ } ,
function ( name ) 
if name == entry then
return path
end
return nil
end ,
function ( name , sourcePath ) 
assert ( name == entry and sourcePath == path , "unexpected dependency" )
return result . root
end
)
end


function bench . repeatable ( source ) 
return bench . emit ( source ) == bench . emit ( source )
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.emitbench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.emitbench"]=__nuppExports;return __nuppExports