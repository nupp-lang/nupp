_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.services"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local define;__nuppExports["define"]=function(...) return define(...) end;local dialect;__nuppExports["dialect"]=function(...) return dialect(...) end;local setupWorkers;__nuppExports["setupWorkers"]=function(...) return setupWorkers(...) end;local workerConfiguration;__nuppExports["workerConfiguration"]=function(...) return workerConfiguration(...) end;



















































const _DYNAMIC_PROVIDERS = "@requires-dynamically nupp.runtime.services.* @requires-dynamically nupp.runtime.provider.* @requires-dynamically nupp.runtime.browser.* @requires-dynamically nupp.codec.json.aot"
local builtin = require ( "nupp.runtime.services.catalog" )
local catalog = { }
local foundCatalog , loadedCatalog = pcall ( require , "nupp.runtime.services.artifact" )
if foundCatalog then
catalog = loadedCatalog
elseif not tostring ( loadedCatalog ) : find ( "module 'nupp.runtime.services.artifact' not found" , 1 , true ) then
error ( "nupp.services: cannot read provider catalog: " .. tostring ( loadedCatalog ) , 0 )
end
local targetDialect = catalog . dialect or ( rawget ( _G , "jit" ) ~= nil and "luajit" or "lua51" )

local definitions = { }
local loading = { }
local workerSetups = { }
local workerSetupNames = { }
local workerInitialization








local function validate ( id , members , value ) 
if members == nil then
return
end
if type ( value ) ~= "table" then
error ( "nupp.services: " .. id .. " must return a provider table" , 2 )
end
for _ , member in ipairs ( members ) do
local actual = type ( value [ member . name ] )
local accepted = false
for _ , kind in ipairs ( member . kinds ) do
accepted = accepted
or kind == "any"
or kind == "unknown"
or kind == actual
or kind == "func" and actual == "function"
or (
kind == "interface"
or kind == "record"
or kind == "nominal"
or kind == "shape"
or kind == "map"
or kind == "array"
)
and actual == "table"
or ( kind == "integer" or kind == "fixedwidth" or kind == "literalnumber" ) and actual == "number"
end
if not accepted then
error ( "nupp.services: " .. id .. "." .. member . name .. " has type " .. actual , 2 )
end
end
end







const Service = {} Service.__index = Service























function Service:register(name, loader) 
if name == "" then
error ( "nupp.services: empty provider name for " .. self . id , 2 )
end
if self . loaders [ name ] ~= nil then
error ( "nupp.services: duplicate provider " .. self . id .. "/" .. name , 2 )
end
self . loaders [ name ] = loader
end








function Service:select(name) 
if self . resolved or self . resolving then
error ( "nupp.services: " .. self . id .. " is already resolved" , 2 )
end
if name == "" then
error ( "nupp.services: empty provider name for " .. self . id , 2 )
end
self . selected = name
end





function Service:list() 
local names = { }
for name in pairs ( self . loaders ) do
names [ # names + 1 ] = name
end
table . sort ( names )

return names
end












function Service:lookup(name) 
if name ~= nil then
local loaded = self . values [ name ]
if loaded ~= nil then
return loaded
end
local loader = self . loaders [ name ]
if loader == nil then
return nil
end
local identity = self . id .. "/" .. name
if self . active [ name ] then
error ( "nupp.services: provider cycle " .. table . concat ( loading , " -> " ) .. " -> " .. identity , 2 )
end
self . active [ name ] = true
loading [ # loading + 1 ] = identity

local function load ( ) 
local value = loader ( )
if value == nil then
error ( "provider returned nil" , 2 )
end
validate ( identity , self . members , value )

return value
end

local ok , value = pcall ( load )
loading [ # loading ] = nil
self . active [ name ] = nil
if not ok then
error ( "nupp.services: cannot load " .. identity .. ": " .. tostring ( value ) , 2 )
end
self . values [ name ] = value
return value
end
if self . resolved then
return self . value
end
if self . resolving then
error ( "nupp.services: default cycle " .. table . concat ( loading , " -> " ) .. " -> " .. self . id , 2 )
end
self . resolving = true
loading [ # loading + 1 ] = self . id

local function choose ( ) 
local selected = self . selected
if selected ~= nil then
local value = self : lookup ( selected )
if value == nil then
error ( "nupp.services: no provider " .. self . id .. "/" .. selected , 2 )
end
return value
end
local defaultLoader = self . defaultLoader
if defaultLoader ~= nil then
return defaultLoader ( )
end

return nil
end

local function resolve ( ) 
local value = choose ( )
if value ~= nil then
validate ( self . id , self . members , value )
local checkImplementation = self . checkImplementation
if checkImplementation ~= nil then
checkImplementation ( value )
end
end

return value
end

local ok , value = pcall ( resolve )
loading [ # loading ] = nil
self . resolving = false
if not ok then
error ( tostring ( value ) , 2 )
end
self . value = value
self . resolved = true

return value
end








function Service:assemble(defaultLoader, checkImplementation) 
self : assembleOptional ( defaultLoader , checkImplementation )
return self : require ( )
end






function Service:assembleOptional(defaultLoader, checkImplementation) 




if not self . resolved and not self . resolving then
self . defaultLoader = defaultLoader
self . checkImplementation = checkImplementation
elseif self . resolved and checkImplementation ~= nil and self . value ~= nil then
checkImplementation ( self . value )
end

return self : lookup ( )
end






function Service:require(name) 
local value = self : lookup ( name )
if value == nil then
error ( "nupp.services: no provider for " .. self . id .. ( name and "/" .. name or "" ) , 2 )
end

return value
end ;__nuppExports["Service"]=Service













define=function ( id , api , defaultLoader , members ) 
if id == "" or api < 1 or api % 1 ~= 0 then
error ( "nupp.services: a service requires an identity and positive API version" , 2 )
end
if definitions [ id ] ~= nil then
error ( "nupp.services: duplicate contract " .. id , 2 )
end
local service = setmetatable({ id =
id ,  api =
api ,  loaders =
{ } ,  values =
{ } ,  active =
{ } ,  defaultLoader =
defaultLoader ,  members =
members ,  resolved =  false ,  resolving =  false }, Service)


local function add ( entry ) 
if entry . service ~= id or not builtin . supports ( entry , targetDialect ) then
return
end
if entry . api ~= api then
error ( "nupp.services: API mismatch for " .. id .. "/" .. entry . name , 2 )
end
if service . members == nil and entry . members ~= nil then
service . members = entry . members
end
service : register ( entry . name , function ( ) 
local declaration = require ( entry . contract )
if declaration [ entry . export ] ~= service then
error ( "nupp.services: contract identity mismatch for " .. id .. "/" .. entry . name , 2 )
end
local value = require ( entry . entry )
if entry . member ~= nil then
value = value [ entry . member ]
end

return value
end )
end

for _ , entry in ipairs ( foundCatalog and catalog . providers or builtin . entries ) do
add ( entry )
end
definitions [ id ] = service

return service
end ;__nuppExports["define"]=define





dialect=function ( ) 
return targetDialect
end ;__nuppExports["dialect"]=dialect








setupWorkers=function ( moduleName ) 
if workerInitialization ~= nil then
error ( "nupp.services: worker initialization is already fixed" , 2 )
end
if moduleName == "" or not moduleName : match ( "^[A-Za-z_][A-Za-z0-9_.]*$" ) then
error ( "nupp.services: invalid worker setup module " .. moduleName , 2 )
end
if not workerSetupNames [ moduleName ] then
workerSetupNames [ moduleName ] = true
workerSetups [ # workerSetups + 1 ] = moduleName
end
end ;__nuppExports["setupWorkers"]=setupWorkers










workerConfiguration=function ( ) 
if workerInitialization ~= nil then
return workerInitialization
end
local lines = { }
for _ , moduleName in ipairs ( workerSetups ) do
lines [ # lines + 1 ] = ( "require(%q)" ) : format ( moduleName )
end
local identities = { }
for id in pairs ( definitions ) do
identities [ # identities + 1 ] = id
end
table . sort ( identities )
for _ , id in ipairs ( identities ) do
local selected = definitions [ id ] . selected
if selected ~= nil then
local found = nil
for _ , entries in ipairs ( { foundCatalog and catalog . providers or builtin . entries } ) do
for _ , entry in ipairs ( entries ) do
if entry . service == id and entry . name == selected and builtin . supports ( entry , targetDialect ) then
found = entry
end
end
end
if found ~= nil then
lines [ # lines + 1 ] = ( "require(%q)[%q]:select(%q)" ) : format ( found . contract , found . export , selected )
elseif # workerSetups == 0 then
error (
"nupp.services: runtime-only provider "
.. id
.. "/"
.. selected
.. " requires an explicit worker setup module" ,
2
)
end
end
end
workerInitialization = table . concat ( lines , "\n" )

return workerInitialization
end ;__nuppExports["workerConfiguration"]=workerConfiguration
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Service]="nupp.services\0Service"; end);if not __nuppOk then package.loaded["nupp.services"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.services"]=__nuppExports;return __nuppExports