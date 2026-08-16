_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);






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

return filename : sub (
1 ,
1
) == "_" or filename == "internal.nupp" or relative : match (
"^internal/"
) ~= nil or relative : match ( "/internal/" ) ~= nil
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
files . copyPublicFiles = copyPublicFiles

return files
