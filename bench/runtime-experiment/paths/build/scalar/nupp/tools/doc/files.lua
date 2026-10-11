_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()








local fs = require ( "nupp.compiler.fs" )

local files = { }




local normalize

, join

, dirname = fs . normalize , fs . join , fs . dirname
local readFile

, exists = fs . readFile , fs . exists





local collector = nil

local function writeFile ( path , contents ) 
local ok , err = fs . writeFileIfChanged ( path , contents )
if ok and collector then
collector [ # collector + 1 ] = normalize ( path )
end

return ok , err
end


function files . collect ( into ) 
collector = into
end

local function hiddenBelow ( root , candidate ) 
local relative = candidate
if candidate : sub ( 1 , # root + 1 ) == root .. "/" then
relative = candidate : sub ( # root + 2 )
end

return relative : match ( "^%.[^/]" ) ~= nil or relative : match ( "/%.[^/]" ) ~= nil
end









local function privateSource ( root , candidate ) 
local relative = candidate
if candidate : sub ( 1 , # root + 1 ) == root .. "/" then
relative = candidate : sub ( # root + 2 )
end
local filename = relative : match ( "([^/]+)$" ) or relative

return filename : sub ( 1 , 1 ) == "_"
or filename == "internal.nupp"
or relative : match ( "^internal/" ) ~= nil
or relative : match ( "/internal/" ) ~= nil
end

local function listDirectoryFiles ( path ) 
local paths = { }
for _ , candidate in ipairs ( fs . listFiles ( path ) ) do
candidate = normalize ( candidate )
if not hiddenBelow ( path , candidate ) then
paths [ # paths + 1 ] = candidate
end
end
table . sort ( paths )

return paths
end

local function listFiles ( path ) 
local paths = { }
for _ , candidate in ipairs ( listDirectoryFiles ( path ) ) do
if candidate : match ( "%.nupp$" ) then
paths [ # paths + 1 ] = candidate
end
end

return paths
end



local function listMarkdown ( path ) 
local paths = { }
for _ , candidate in ipairs ( listDirectoryFiles ( path ) ) do
if candidate : match ( "%.md$" ) then
paths [ # paths + 1 ] = candidate
end
end

return paths
end

local function copyPublicFiles ( root , outDir , public ) 
if not public or public == "" then
return true
end
local directory = join ( root , public )
for _ , source in ipairs ( listDirectoryFiles ( directory ) ) do
local relative = source : sub ( # directory + 2 )
local contents , err = readFile ( source )
if not contents then
return nil , err
end
local ok
ok , err = writeFile ( join ( outDir , relative ) , contents )
if not ok then
return nil , err
end
end

return true
end

files . normalize = normalize
files . join = join
files . dirname = dirname
files . readFile = readFile
files . exists = exists
files . writeFile = writeFile
files . privateSource = privateSource
files . listFiles = listFiles
files . listMarkdown = listMarkdown
files . copyPublicFiles = copyPublicFiles

local __nuppExportValue= files ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.files"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.files"]=__nuppExports;return __nuppExports