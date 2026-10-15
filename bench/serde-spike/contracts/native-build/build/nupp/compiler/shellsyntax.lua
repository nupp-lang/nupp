_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local function space ( character ) 
return character ~= "" and (" \9\13\n\11\12") : find ( character , 1 , true ) ~= nil
end

local function globTokens ( source ) 
local tokens = { }
local index = 1
while index <= # source do
local token = source : sub ( index , index )
if source : sub ( index , index + 2 ) == "**/" then
token = "**/"
elseif source : sub ( index , index + 1 ) == "**" then
token = "**"
elseif token ~= "*" and token ~= "?" then
local finish = index
while finish < # source and not source : sub ( finish + 1 , finish + 1 ) : find ( "[*?]" ) do
finish = finish + 1
end
token = source : sub ( index , finish )
end
tokens [ # tokens + 1 ] = token
index = index + # token
end

return tokens
end

local function shellWords ( source ) 
local words = { }
local index = 1
while index <= # source do
while space ( source : sub ( index , index ) ) do
index = index + 1
end
if index > # source then
do break end
end
local parts = { }
while index <= # source and not space ( source : sub ( index , index ) ) do
local character = source : sub ( index , index )
if character == "'" or character == "\"" then
local quote = character
index = index + 1
while index <= # source and source : sub ( index , index ) ~= quote do
character = source : sub ( index , index )
if quote == "\"" and character == "\\" then
index = index + 1
if index > # source then
return nil
end
character = source : sub ( index , index )
end
parts [ # parts + 1 ] = character
index = index + 1
end
if index > # source then
return nil
end
else
if character == "\\" then
index = index + 1
if index > # source then
return nil
end
character = source : sub ( index , index )
end
parts [ # parts + 1 ] = character
end
index = index + 1
end
words [ # words + 1 ] = table . concat ( parts )
end

return words
end

local function depfile ( source ) 
local index = 1
while index <= # source and source : sub ( index , index ) ~= ":" do
if source : sub ( index , index ) == "\\" then
index = index + 1
end
index = index + 1
end
if index > # source then
return nil
end
index = index + 1
local paths = { }
while index <= # source do
while index <= # source do
if space ( source : sub ( index , index ) ) then
index = index + 1
elseif source : sub ( index , index + 1 ) == "\\\n" then
index = index + 2
elseif source : sub ( index , index + 2 ) == "\\\13\n" then
index = index + 3
else
do break end
end
end
if index > # source then
do break end
end
if source : sub ( index , index ) == "#" then
local newline = source : find ( "\n" , index , true )
if newline and newline ~= # source then
return nil
end
return paths
end
local parts = { }
while index <= # source do
local character = source : sub ( index , index )
if space ( character ) or character == "#" then
do break end
end
if character == "\\" then
if source : sub ( index + 1 , index + 1 ) == "\n" then
do break end
end
index = index + 1
if index > # source then
return nil
end
character = source : sub ( index , index )
end
parts [ # parts + 1 ] = character
index = index + 1
end
paths [ # paths + 1 ] = table . concat ( parts )
end

return paths
end



local function compileGlob ( glob ) 
local tokens = globTokens ( glob )
return function ( path ) 
local match
match = function ( tokenIndex , pathIndex ) 
local token , ch = tokens [ tokenIndex ] , path : sub ( pathIndex , pathIndex )
if not token then
return pathIndex > # path
elseif token == "**/" then
local slash = path : find ( "/" , pathIndex , true )
return match ( tokenIndex + 1 , pathIndex )
or ( slash ~= nil and slash > pathIndex and match ( tokenIndex , slash + 1 ) )
elseif token == "**" then
return match ( tokenIndex + 1 , pathIndex ) or ( ch ~= "" and match ( tokenIndex , pathIndex + 1 ) )
elseif token == "*" then
return match ( tokenIndex + 1 , pathIndex ) or ( ch ~= "" and ch ~= "/" and match ( tokenIndex , pathIndex + 1 ) )
elseif token == "?" then
return ch ~= "" and ch ~= "/" and match ( tokenIndex + 1 , pathIndex + 1 )
end

return path : sub ( pathIndex , pathIndex + # token - 1 ) == token and match ( tokenIndex + 1 , pathIndex + # token )
end

return match ( 1 , 1 )
end
end

local __nuppExportValue= { glob = compileGlob , shellWords = shellWords , depfile = depfile } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.shellsyntax"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.shellsyntax"]=__nuppExports;return __nuppExports