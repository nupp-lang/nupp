_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.math").install(rawget(__nupp,"math")) require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.compiler.runtime.reflect").install(__nupp);local __nuppT17={}; local function __nuppT14(...) return {n=select("#",...),...} end; local __nuppT18,__nuppT19,__nuppT20,__nuppT21,__nuppT22,__nuppT23,__nuppT24,__nuppT25=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT15(value) return value end; local function __nuppT16(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT23({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT24(v.primary) for _,reason in __nuppT25(v.suppressed) do text=text.."\ncleanup: "..__nuppT24(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.internal.accessors"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local of;__nuppExports["of"]=function(...) return of(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.accessors\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.accessors\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.serde.internal.accessors\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.serde.internal.accessors\0runtime\0004") };




local cacheKey = { }
local create

local function fail ( path , expected ) 
error ( "nupp: " .. path .. " expects " .. expected , 3 )
end

local function witness ( info , index ) 
return assert ( nupp . reflect . runtimeType ( info , index ) , "runtime declaration is not available" )
end

local function checkValue ( info , index , value , path , seen ) 
local node = info . types [ index ]
local kind = node . kind
if kind == "nil" then
return value == nil
elseif kind == "any" or kind == "unknown" then
return true
elseif kind == "string" or kind == "boolean" or kind == "table" then
return type ( value ) == kind
elseif kind == "number" then
return type ( value ) == "number"
elseif kind == "float" then
return type ( value ) == "number" and ( value ~= value or nupp . math . f32 . narrow ( value ) == value )
elseif kind == "integer"
or kind == "int32"
or kind == "uint32"
or kind == "int8"
or kind == "uint8"
or kind == "int16"
or kind == "uint16"
then
if type ( value ) ~= "number" or value ~= value or value == math . huge or value == - math . huge or value % 1 ~= 0 then
return false
end
if kind == "integer" then
return true
end
local width = assert ( tonumber ( kind : match ( "%d+" ) ) )
local signed = kind : sub ( 1 , 1 ) == "i"
local limit = 2 ^ ( width - ( signed and 1 or 0 ) )
return value >= ( signed and - limit or 0 ) and value < limit
elseif kind == "int64" or kind == "uint64" then
local ffi = _G . require ( "ffi" )
return ffi . istype ( kind == "int64" and "int64_t" or "uint64_t" , value )
elseif kind == "literal" then
return value == node . value
elseif kind == "const" then
return checkValue ( info , node . element , value , path , seen )
elseif kind == "record" then
return type ( value ) == "table" and getmetatable ( value ) == ( assert ( nupp . reflect . runtimeType ( info , index ) , "runtime declaration is not available" ) )
elseif kind == "struct" then
local ffi = _G . require ( "ffi" )
return ffi . istype ( ( assert ( nupp . reflect . runtimeType ( info , index ) , "runtime declaration is not available" ) ) , value )
elseif kind == "union" then
for _ , member in ipairs ( node . members ) do
if checkValue ( info , member , value , path , seen ) then
return true
end
end
return false
elseif kind == "intersection" then
for _ , member in ipairs ( node . members ) do
if not checkValue ( info , member , value , path , seen ) then
return false
end
end
return true
end
if type ( value ) ~= "table" then
return false
end
local prior = seen [ value ]
if prior and prior [ index ] then
return true
end
if prior == nil then
prior = { }
seen [ value ] = prior
end
prior [ index ] = true
local valid = true
if kind == "array" then
local count = 0
for key , item in pairs ( value ) do
if type ( key ) ~= "number" or key < 1 or key % 1 ~= 0 then
valid = false
do break end
end
count += 1
if not checkValue ( info , node . element , item , path , seen ) then
valid = false
do break end
end
end
if valid then
for position = 1 , count do
if rawget ( value , position ) == nil then
valid = false
do break end
end
end
end
elseif kind == "tuple" then
for position , member in ipairs ( node . members ) do
if not checkValue ( info , member , value [ position ] , path , seen ) then
valid = false
do break end
end
end
for key in pairs ( value ) do
if type ( key ) ~= "number" or key % 1 ~= 0 or key < 1 or key > # node . members then
valid = false
do break end
end
end
elseif kind == "map" then
for key , item in pairs ( value ) do
if not checkValue ( info , node . readKey , key , path , seen )
or not checkValue ( info , node . readValue , item , path , seen )
then
valid = false
do break end
end
end
elseif kind == "shape" then
for _ , field in ipairs ( node . fields ) do
if not checkValue ( info , field . read , value [ field . name ] , path , seen ) then
valid = false
do break end
end
end
else
valid = false
end
prior [ index ] = nil

return valid
end

local function copyDefault ( value ) 
if type ( value ) ~= "table" then
return value
end
local result = { }
for key , item in pairs ( value ) do
result [ key ] = copyDefault ( item )
end

return result
end



local function checkable ( info , index , seen ) 
if seen [ index ] then
return true
end
seen [ index ] = true
local node = info . types [ index ]
local kind = node . kind
if kind == "nil"
or kind == "any"
or kind == "unknown"
or kind == "string"
or kind == "boolean"
or kind == "number"
or kind == "float"
or kind == "integer"
or kind == "literal"
or kind == "table"
or kind == "int8"
or kind == "uint8"
or kind == "int16"
or kind == "uint16"
or kind == "int32"
or kind == "uint32"
or kind == "int64"
or kind == "uint64"
then
return true
elseif kind == "record" or kind == "struct" then
return # ( node . typeParameters or { } ) == 0
elseif kind == "const" or kind == "array" then
return checkable ( info , node . element , seen )
elseif kind == "map" then
return node . readKey ~= nil
and node . readValue ~= nil
and checkable ( info , node . readKey , seen )
and checkable ( info , node . readValue , seen )
elseif kind == "tuple" or kind == "union" or kind == "intersection" then
for _ , member in ipairs ( node . members ) do
if not checkable ( info , member , seen ) then
return false
end
end
return true
elseif kind == "shape" then
if node . index and next ( node . index ) ~= nil then
return false
end
for _ , field in ipairs ( node . fields ) do
if field . read == nil or not checkable ( info , field . read , seen ) then
return false
end
end
return true
end

return false
end




local Field = {} Field.__index = Field ;_G.nupp.__reflect.link(Field,__nuppT1[1],{ }) ;__nuppExports["Field"]=Field





















local Parameter = {} Parameter.__index = Parameter ;_G.nupp.__reflect.link(Parameter,__nuppT1[2],{ }) ;__nuppExports["Parameter"]=Parameter





















local Builder = {} Builder.__index = Builder

















function Builder:set(parameter, value) 
assert ( not self . closed , "construction is closed" )
assert ( parameter . owner == self . owner , "foreign construction parameter" )
assert ( not self . present [ parameter . index ] , "duplicate construction parameter" )
if not checkValue ( self . info , parameter . typeIndex , value , parameter . name , { } ) then
fail ( parameter . name , self . info . types [ parameter . typeIndex ] . kind )
end
self . values [ parameter . index ] = value
self . present [ parameter . index ] = true
end




function Builder:close() 
self . closed = true
self . values = { }
self . present = { }
end ;_G.nupp.__reflect.link(Builder,__nuppT1[3],{ }) ;__nuppExports["Builder"]=Builder


local Access = {} Access.__index = Access






























function Access:get(value, field) 
assert ( field . owner == self . owner , "foreign access field" )
return ( value ) [ field . name ]
end









function Access:begin() 
assert ( self . constructionProblem == nil , self . constructionProblem )
return ( _G.setmetatable({ owner =  self . owner ,  info =  self . info ,  values =  { } ,  present =  { } ,  closed =  false }, Builder) )
end











function Access:constructionError() 
return self . constructionProblem
end










function Access:nested(index) 
assert ( self . accessible [ index ] , "type is not reachable through readable storage" )
local cached = self . nestedCache [ index ]
if cached ~= nil then
return cached
end
local target = assert ( nupp . reflect . runtimeType ( self . info , index ) , "nested declaration is not available" )
local result = create ( target , self . info , index )
self . nestedCache [ index ] = result

return result
end














function Access:finish(builder) 
do local __nuppT26=0; local  __nuppT32 ; local __nuppT33=false ; local __nuppT27,__nuppT28,__nuppT29=__nuppT19(function() do local __nuppT34= builder ; __nuppT32= __nuppT34 ; __nuppT26=1;  __nuppT33=true;  local state=__nuppT32;
assert ( state . owner == self . owner , "foreign construction state" )
assert ( not state . closed , "construction is closed" )
local arguments = { }
for _ , parameter in ipairs ( self . parameters ) do
if not state . present [ parameter . index ] and not parameter . optional then
error ( "missing construction parameter: " .. parameter . name , 2 )
end
local value = state . values [ parameter . index ]
if not state . present [ parameter . index ] and self . constructor == nil then
value = copyDefault ( self . defaults [ parameter . name ] )
end
if not checkValue ( self . info , parameter . typeIndex , value , parameter . name , { } ) then
fail ( parameter . name , self . info . types [ parameter . typeIndex ] . kind )
end
arguments [ parameter . index ] = value
end
local target = self . target
local value
if self . constructor ~= nil then
local construct = target [ "__nuppCtor" .. tostring ( self . constructor ) ]
value = construct ( unpack ( arguments , 1 , # self . parameters ) )
else
value = self . info . types [ self . typeIndex ] . kind == "struct" and target ( ) or setmetatable ( { } , target )
for _ , parameter in ipairs ( self . parameters ) do
value [ parameter . name ] = arguments [ parameter . index ]
end
end
if not checkValue ( self . info , self . typeIndex , value , self . info . name , { } ) then
fail ( self . info . name , "a constructed " .. self . info . types [ self . typeIndex ] . kind )
end
do (function(__nuppT35,...)  __nuppT33=false; return __nuppT35:close(...)  end)( state ) end

return "return",__nuppT14( value ) end; return "normal" end,__nuppT15); local __nuppT30={}; local __nuppT31=0; if __nuppT26>=1 and __nuppT33 then  local __nuppT36,__nuppT37=__nuppT18(__nuppCleanup1,__nuppT32);  if not __nuppT36 then __nuppT31=__nuppT31+1; __nuppT30[__nuppT31]=__nuppT37 end; end; if not __nuppT27 then if __nuppT31>0 then __nuppT20(__nuppT16(__nuppT28,__nuppT30,1),0) else __nuppT20(__nuppT28,0) end end; if __nuppT31>0 then if __nuppT31>1 then __nuppT20(__nuppT16(__nuppT30[1],__nuppT30,2),0) else __nuppT20(__nuppT30[1],0) end end; if __nuppT28=="return" then  return __nuppT21(__nuppT29,1,__nuppT29.n)  end; end
end ;_G.nupp.__reflect.link(Access,__nuppT1[4],{ __nuppT1[1] , __nuppT1[2] , __nuppT1[4] }) ;__nuppExports["Access"]=Access


create = function ( target , info , index ) 
local root = info . types [ index ]
assert ( root . kind == "record" or root . kind == "struct" , "access requires a record or struct" )
local owner = { }
local fields = { }
local parameters = { }
local defaults = { }
for _ , entry in ipairs ( root . fields ) do
if entry . stored and entry . readable then
fields [
# fields + 1
] = _G.setmetatable({ name =
entry . name ,  annotations =
entry . annotations or { } ,  index =
# fields + 1 ,  typeIndex =
entry . read ,  hasDefault =
entry . hasDefault == true ,  owner =
owner }, Field)

if entry . hasDefault then
defaults [ entry . name ] = entry . defaultValue
end
end
end
local construction = root . construction
local problem
if root . copyable == nil then
problem = "declaration metadata has no ownership attestation; rebuild it with this compiler"
elseif not root . copyable then
problem = "an owning declaration requires an explicit construction and disposal adapter"
elseif construction == nil or construction . requiresFactory then
problem = "this declaration requires an explicit construction adapter"
elseif # ( root . typeParameters or { } ) > 0 then
problem = "a generic declaration requires a concrete construction adapter"
else
for index , entry in ipairs ( construction . params ) do
if entry . mode ~= "plain" or not checkable ( info , entry . type , { } ) then
problem = "parameter " .. entry . name .. " requires a typed construction adapter"
end
parameters [
index
] = _G.setmetatable({ name =
entry . name ,  index =
index ,  typeIndex =
entry . type ,  optional =
entry . optional == true ,  owner =
owner }, Parameter)

end
end
local accessible = { }

local function visit ( current ) 
if accessible [ current ] then
return
end
accessible [ current ] = true
local node = info . types [ current ]
if node . kind == "record" or node . kind == "struct" or node . kind == "shape" then
for _ , field in ipairs ( node . fields ) do
if field . read and ( node . kind == "shape" or field . stored ) then
visit ( field . read )
end
end
elseif node . kind == "const" or node . kind == "array" then
visit ( node . element )
elseif node . kind == "tuple" or node . kind == "union" or node . kind == "intersection" then
for _ , member in ipairs ( node . members ) do
visit ( member )
end
elseif node . kind == "map" then
if node . readKey then
visit ( node . readKey )
end
if node . readValue then
visit ( node . readValue )
end
end
end

visit ( index )
local result = _G.setmetatable({ info =
info ,  typeIndex =
index ,  fields =
fields ,  parameters =
parameters ,  owner =
owner ,  target =
target ,  defaults =
defaults ,  constructor =
construction and construction . declared and construction . index or nil ,  constructionProblem =
problem ,  accessible =
accessible ,  nestedCache =
{ } }, Access)


return result
end

of=function ( target ) 
local info = nupp . reflect . runtime ( target )
local cached = rawget ( info , cacheKey )
if cached ~= nil then
return cached
end
local result = create ( target , info , info . root )
rawset ( info , cacheKey , result )

return result
end ;__nuppExports["of"]=of
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Access]="nupp.serde.internal.accessors\0Access";__nuppWorkerRecords[Builder]="nupp.serde.internal.accessors\0Builder";__nuppWorkerRecords[Field]="nupp.serde.internal.accessors\0Field";__nuppWorkerRecords[Parameter]="nupp.serde.internal.accessors\0Parameter"; end);if not __nuppOk then package.loaded["nupp.serde.internal.accessors"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.accessors"]=__nuppExports;return __nuppExports