_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local testrunner = { }



local function shellQuote ( text ) 
return "'" .. text : gsub ( "'" , "'\\''" ) .. "'"
end

function testrunner . run ( args ) 
local compilerRoot = os . getenv ( "NUPP_COMPILER_ROOT" )
local executable = compilerRoot and compilerRoot .. "/bin/nupp" or tostring ( arg [ 0 ] or "nupp" )
local forwarded = { [ 0 ] = executable }
for index , argument in ipairs ( args ) do
forwarded [ index ] = argument
end
arg = forwarded




rawset ( _G , "__NUPP_TEST_DIR" , "tests" )
rawset ( _G , "__NUPP_TEST_RUNNER_COMMAND" , ( "'" .. executable : gsub ( "'" , "'\\''" ) .. "'" ) .. " test --internal-runner" )




package . loaded [ "nupp.test" ] = require ( "nupp.test" )

local source = assert ( require ( "nupp.compiler.bundled" ) . source ( "/nupp/test/runner.lua" ) )
local execute , problem = loadstring ( source , "@nupp:test-runner" )
if execute == nil then
io . stderr : write ( "nupp: cannot load the bundled test runner: " .. tostring ( problem ) .. "\n" )
return 1
end
local result = execute ( )

return type ( result ) == "number" and result or 0
end

local __nuppExportValue= testrunner ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.cli.testrunner"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.cli.testrunner"]=__nuppExports;return __nuppExports