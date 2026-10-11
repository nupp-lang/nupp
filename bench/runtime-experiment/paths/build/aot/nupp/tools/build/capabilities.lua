_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





local fs = require ( "nupp.compiler.fs" )
local json = require ( "nupp.codec.json" )

local capabilities = { }








local ENTRY_KEYS = { api = true , entry = true , kind = true , name = true }

local function identifier ( value ) 
return type ( value ) == "string" and value : match ( "^[A-Za-z0-9][A-Za-z0-9_.-]*$" ) ~= nil
end

local function readDescriptor ( record , dependencyName ) 
if not record or not record . typeRoot then
return nil , "dependency " .. dependencyName .. " does not install Nupp capability metadata"
end
local path = fs . join ( record . typeRoot , "capabilities.json" )
local text = fs . readFile ( path )
if not text then
return nil , "dependency " .. dependencyName .. " has no nupp/capabilities.json"
end
local document = json . decode ( text , json . NULL )
if type ( document ) ~= "table" then
return nil , path .. " is not valid JSON"
end
for key in pairs ( document ) do
if key ~= "schema" and key ~= "capabilities" then
return nil , path .. " has unknown key " .. tostring ( key )
end
end
if document . schema ~= 2 then
return nil , path .. ".schema must be 2"
end
if type ( document . capabilities ) ~= "table" or not json . isArray ( document . capabilities ) then
return nil , path .. ".capabilities must be an array"
end
local entries = { }
local seen = { }
for index , raw in ipairs ( document . capabilities ) do
local label = path .. ".capabilities[" .. index .. "]"
if type ( raw ) ~= "table" then
return nil , label .. " must be a table"
end
for key in pairs ( raw ) do
if not ENTRY_KEYS [ key ] then
return nil , label .. " has unknown key " .. tostring ( key )
end
end
if raw . kind ~= "generator" then
return nil , label .. ".kind must be generator"
end
if not identifier ( raw . name ) then
return nil , label .. ".name must be an identifier"
end
if type ( raw . api ) ~= "number" or raw . api < 1 or raw . api ~= math . floor ( raw . api ) then
return nil , label .. ".api must be a positive integer"
end
if not identifier ( raw . entry ) then
return nil , label .. ".entry must be a module name"
end
local identity = raw . name
if seen [ identity ] then
return nil , label .. " duplicates capability " .. raw . name
end
seen [ identity ] = true
entries [ # entries + 1 ] = raw
end
if # entries ~= # document . capabilities then
return nil , path .. ".capabilities must be a dense array"
end

return entries
end

function capabilities . find ( record , dependencyName , kind , name ) 
local entries , err = readDescriptor ( record , dependencyName )
if not entries then
return nil , err
end
for _ , entry in ipairs ( entries ) do
if entry . kind == kind and entry . name == name then
return entry
end
end

return nil , "dependency " .. dependencyName .. " provides no " .. kind .. " named " .. name
end

local __nuppExportValue= capabilities ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.capabilities"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.capabilities"]=__nuppExports;return __nuppExports