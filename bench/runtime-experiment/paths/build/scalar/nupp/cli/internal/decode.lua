_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.cli.internal.decode"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local fromCLI;__nuppExports["fromCLI"]=function(...) return fromCLI(...) end;local groupRun;__nuppExports["groupRun"]=function(...) return groupRun(...) end;local strings;__nuppExports["strings"]=function(...) return strings(...) end;local text;__nuppExports["text"]=function(...) return text(...) end;



local parser = require ( "nupp.cli.internal.optparser" )
local derive = require ( "nupp.derive" )











local function failure ( kind , message , token , field ) 
local option = nil
if token ~= nil then
local tokenKind = token : kind ( )
if tokenKind == parser . shortOption or tokenKind == parser . longOption then
option = token : key ( )
end
end

return {
kind = kind ,
message = message ,
index = token and token : index ( ) or nil ,
raw = token and token : raw ( ) or nil ,
option = option ,
field = field and field . field or nil ,
destination = field and field . destination or nil ,
}
end

local PREPARED = setmetatable ( { } , { __mode = "k" } )

local function prepared ( entry ) 
local schema = entry . schema . data . cli
local existing = PREPARED [ entry ]
if existing ~= nil then
return existing
end
local byName , byPattern , arity , patterns = { } , { } , { } , { }
for _ , field in ipairs ( schema . fields ) do
if field . role == "option" then
for _ , name in ipairs ( field . names ) do
byName [ name ] = field
arity [ name ] = field . constants [ name ] ~= nil and "none" or field . arity
end
if field . pattern ~= nil then
byPattern [ field . matchKey ] = field
patterns [ # patterns + 1 ] = { pattern = field . pattern , key = field . matchKey }
end
end
end
local plan = { schema = schema , byName = byName , byPattern = byPattern , arity = arity , patterns = patterns }
PREPARED [ entry ] = plan

return plan
end

local function converted ( text , field , token ) 
local kind = field . conversion
if kind == "string" then
return text , nil
elseif kind == "integer" then
local number = tonumber ( text )
if number == nil
or number % 1 ~= 0
or field . minimum ~= nil and number < field . minimum
or field . maximum ~= nil and number > field . maximum
then
return nil , failure (
"invalidValue" ,
field . invalid or text .. " is not a valid " .. field . destination .. " for " .. field . display ,
token ,
field
)
end
return number , nil
elseif kind == "number" then
local number = tonumber ( text )
if number == nil then
return nil , failure ( "invalidValue" , text .. " is not a valid number for " .. field . display , token , field )
end
return number , nil
elseif kind == "choice" then
for _ , choice in ipairs ( field . choices ) do
if choice == text then
return text , nil
end
end
return nil , failure (
"invalidChoice" ,
field . invalid
or "option " .. field . display .. " does not take " .. text .. "; expected " .. table . concat (
field . choices ,
", "
) ,
token ,
field
)
end

return nil , failure ( "invalidValue" , "unsupported value for " .. field . display , token , field )
end

local function assign (
values ,
seen ,
field ,
text ,
token
) 
local value , problem = converted ( text , field , token )
if problem ~= nil then
return problem
end
local index = field . index
if field . repeated then
local accumulated = values [ index ]
if accumulated == nil then
accumulated = { }
values [ index ] = accumulated
end
if field . set then
accumulated [ value ] = true
else
accumulated [ # accumulated + 1 ] = value
end
elseif seen [ index ] then
return failure ( "duplicateOption" , field . display .. " was specified more than once" , token , field )
else
values [ index ] = value
end
seen [ index ] = true

return nil
end


fromCLI=function ( argv , entry ) 
local plan = prepared ( entry )
local schema = plan . schema
local values = { }
local seen = { }
local positionals = schema . positionals
local positionalIndex = 1
local stream = parser . optParser ( argv , {
arity = plan . arity ,
patterns = plan . patterns ,
stopAtFirstArgument = schema . stopAtFirstArgument ,
} )

while true do
local tokenKind , syntax = stream : next ( )
if syntax ~= nil then
return nil , {
kind = syntax . kind ,
message = syntax . message ,
index = syntax . index ,
raw = syntax . raw ,
option = syntax . key ,
}
elseif tokenKind == nil then
do break end
elseif tokenKind == parser . terminator then
elseif tokenKind == parser . shortOption or tokenKind == parser . longOption then
local key = stream : key ( )
local field = stream : pattern ( ) and plan . byPattern [ key ] or plan . byName [ key ]
if field == nil then
if schema . preserveUnknown then
local problem = assign ( values , seen , schema . remainder , stream : raw ( ) , stream )
if problem ~= nil then
return nil , problem
end
else
return nil , failure ( "unknownOption" , "unknown option " .. stream : raw ( ) , stream , nil )
end
elseif field . conversion == "boolean" then
if stream : value ( ) ~= nil then
return nil , failure ( "unexpectedValue" , field . display .. " takes no value" , stream , field )
elseif seen [ field . index ] then
return nil , failure (
"duplicateOption" ,
field . display .. " was specified more than once" ,
stream ,
field
)
end
if field . constant ~= nil then
values [ field . index ] = field . constant
else
values [ field . index ] = true
end
seen [ field . index ] = true
elseif field . constants [ key ] ~= nil then
if stream : value ( ) ~= nil then
return nil , failure ( "unexpectedValue" , stream : raw ( ) .. " takes no value" , stream , field )
end
local problem = assign ( values , seen , field , field . constants [ key ] , stream )
if problem ~= nil then
return nil , problem
end
elseif stream : value ( ) == nil and field . constant ~= nil then
if seen [ field . index ] then
return nil , failure (
"duplicateOption" ,
field . display .. " was specified more than once" ,
stream ,
field
)
end
values [ field . index ] = field . constant
seen [ field . index ] = true
else
local text = stream : value ( )
if text == nil then
return nil , failure ( "missingValue" , field . display .. " needs " .. field . value , stream , field )
end
local problem = assign ( values , seen , field , text , stream )
if problem ~= nil then
return nil , problem
end
end
else
local field = positionals [ positionalIndex ]
while field ~= nil and field . optional and field . choices ~= nil do
local matches = false
for _ , choice in ipairs ( field . choices ) do
if choice == stream : raw ( ) then
matches = true
end
end
if matches then
do break end
end
positionalIndex = positionalIndex + 1
field = positionals [ positionalIndex ]
end
if field == nil then
return nil , failure ( "unexpectedArgument" , "unexpected argument " .. stream : raw ( ) , stream , nil )
end
local problem = assign ( values , seen , field , stream : raw ( ) , stream )
if problem ~= nil then
return nil , problem
end
if not field . repeated then
positionalIndex = positionalIndex + 1
end
end
end

for _ , field in ipairs ( schema . fields ) do
if field . required and not seen [ field . index ] then
return nil , failure ( "missingRequired" , field . display .. " is required" , nil , field )
end
end

local initializer = derive . initializer ( entry . mt )
if initializer == nil then
return nil , failure ( "invalidSchema" , "CLI initializer is unavailable" , nil , nil )
end
local storage = setmetatable ( { } , entry . mt )

return initializer ( storage , unpack ( values , 1 , schema . fieldCount ) ) , nil
end ;__nuppExports["fromCLI"]=fromCLI


text=function ( value ) 
return value
end ;__nuppExports["text"]=text


strings=function ( value ) 
return value
end ;__nuppExports["strings"]=strings


groupRun=function ( self ) 
return 0
end ;__nuppExports["groupRun"]=groupRun
local __nuppWorkerSendables=_G.rawget(_G.nupp,"__workerSendables");if _G.type(__nuppWorkerSendables)~="table" then __nuppWorkerSendables=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerSendables",__nuppWorkerSendables) end;__nuppWorkerSendables[__nuppExports["text"]]={module="nupp.cli.internal.decode",member="text",captures={values={},count=0},input="string",output="string"}; end);if not __nuppOk then package.loaded["nupp.cli.internal.decode"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.cli.internal.decode"]=__nuppExports;return __nuppExports