_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





















local bundled = { }



local function moduleDir ( ) 
local hostDebug = debug
if hostDebug == nil then
return "."
end
local source = hostDebug . getinfo ( 1 , "S" ) . source

return source : match ( "^@(.*)[/\\]" ) or "."
end




local function readFile ( path ) 
local hostIo = io
if hostIo == nil then
return nil
end
local file = hostIo . open ( path , "rb" )
if not file then
return nil
end
local content = file : read ( "*a" )
file : close ( )

return content
end

local embedded = nil




const NAMESPACE_KEY = "/compiler"




const MODULE_KEY = "/nupp/compiler"


local function embeddedFile ( files , relative ) 
return files [ "/compiler" .. relative ] or files [ "/nupp/compiler" .. relative ]
end






local function checkoutRoot ( ) 
local dir = moduleDir ( ) : gsub ( "\\" , "/" )
if dir : match ( "/src/nupp/compiler$" ) then
return nil
end

local hostOs = rawget ( _G , "os" )

return dir : match ( "^(.*)/build/nupp/compiler$" ) or hostOs and hostOs . getenv ( "NUPP_COMPILER_ROOT" ) or nil
end








local function sourcePath ( root , relative ) 
if relative : sub ( 1 , 7 ) == "/decls/" then
return root .. "/src/nupp/compiler" .. relative
end

return root .. "/src" .. relative
end









function bundled . sourcePathFor ( relative ) 
local root = checkoutRoot ( )
if root == nil then
return nil
end

return sourcePath ( root , relative )
end

local staleRelative = { }
local staleSeen = { }


local function noteStale ( relative , carried ) 
if staleSeen [ relative ] then
return
end
local root = checkoutRoot ( )
if root == nil then
return
end
local current = readFile ( sourcePath ( root , relative ) )
if current ~= nil and current ~= carried then
staleSeen [ relative ] = true
staleRelative [ # staleRelative + 1 ] = relative
end
end









function bundled . staleDeclarations ( ) 
return staleRelative
end









function bundled . source ( relative ) 
if embedded == nil then
local preloaded = package . preload [ "nupp.embedded" ]
embedded = preloaded and preloaded ( ) or false
end
local carried = embedded and ( embedded [ "/compiler" .. relative ] or embedded [ "/nupp/compiler" .. relative ] ) or nil
if carried ~= nil then
return carried
end
carried = readFile ( moduleDir ( ) .. relative )
if carried ~= nil then
noteStale ( relative , carried )
end

return carried
end




function bundled . moduleDir ( ) 
return moduleDir ( )
end







function bundled . embeddedUnder ( files , prefix ) 
local found = { }
local seen = { }
for path in pairs ( files ) do
local relative = path
if path : sub ( 1 , 10 ) == "/compiler/" then
relative = path : sub ( 10 )
elseif path : sub ( 1 , 15 ) == "/nupp/compiler/" then
relative = path : sub ( 15 )
end
if relative : sub ( 1 , # prefix + 1 ) == prefix .. "/" and not seen [ relative ] then
seen [ relative ] = true
found [ # found + 1 ] = relative
end
end

return found
end

local __nuppExportValue= bundled ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.bundled"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.bundled"]=__nuppExports;return __nuppExports