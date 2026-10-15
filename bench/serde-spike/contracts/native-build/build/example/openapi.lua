_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT16={}; local function __nuppT13(...) return {n=select("#",...),...} end; local __nuppT17,__nuppT18,__nuppT19,__nuppT20,__nuppT21,__nuppT22,__nuppT23,__nuppT24=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT14(value) return value end; local function __nuppT15(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT22({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT23(v.primary) for _,reason in __nuppT24(v.suppressed) do text=text.."\ncleanup: "..__nuppT23(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["example.openapi"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local binding;__nuppExports["binding"]=function(...) return binding(...) end;local documentBinding;__nuppExports["documentBinding"]=function(...) return documentBinding(...) end;local model;__nuppExports["model"]=function(...) return model(...) end;local policy;__nuppExports["policy"]=function(...) return policy(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.openapi\0runtime\0001") , _G.nupp.__reflect.declaration("example.openapi\0runtime\0002") , _G.nupp.__reflect.declaration("example.openapi\0runtime\0003") , _G.nupp.__reflect.declaration("example.openapi\0runtime\0004") };

local __serdeJson = require ( "nupp.serde.json" )

local core = require ( "nupp.serde" )
local structures = require ( "nupp.serde.adapters" )
local plans = require ( "nupp.serde.json" )
local json = require ( "nupp.codec.json" )
local documents = require ( "nupp.serde.document" )
local jsonDocument = require ( "nupp.serde.json" )


local Property = {} Property.__index = Property ;_G.nupp.__reflect.link(Property,__nuppT1[1],{ }) ;__nuppExports["Property"]=Property





local Choice = {} Choice.__index = Choice ;_G.nupp.__reflect.link(Choice,__nuppT1[2],{ _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") }) ;__nuppExports["Choice"]=Choice



local Value = {} Value.__index = Value ;_G.nupp.__reflect.link(Value,__nuppT1[3],{ __nuppT1[2] , _G.nupp.__reflect.reference("nupp.serde.internal.document\0runtime\0005","nupp.serde.internal.document") }) ;__nuppExports["Value"]=Value






local Model = {} Model.__index = Model ;_G.nupp.__reflect.link(Model,__nuppT1[4],{ __nuppT1[1] }) ;__nuppExports["Model"]=Model







model=function ( positiveAlternative ) 
return ( _G.setmetatable({ root =
_G.setmetatable({ name =  "Response" ,  readOnly =  false ,  writeOnly =  false }, Property) ,  name =
_G.setmetatable({ name =  "name" ,  index =  1 ,  readOnly =  false ,  writeOnly =  false }, Property) ,  secret =
_G.setmetatable({ name =  "secret" ,  index =  2 ,  writeOnly =  true ,  readOnly =  false }, Property) ,  identifier =
_G.setmetatable({ name =  "id" ,  index =  3 ,  readOnly =  true ,  writeOnly =  false }, Property) ,  payload =
_G.setmetatable({ name =  "payload" ,  index =  4 ,  readOnly =  false ,  writeOnly =  false }, Property) ,  positiveAlternative =
positiveAlternative == true }, Model) )

end ;__nuppExports["model"]=model

local Description = {} Description.__index = Description








local Text = {} Text.__index = Text

function Text:describe(direction) 
return ( _G.setmetatable({ kind =  "string" ,  member =  self . member ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) )
end

function Text:write(value, writer) 
writer : writeString ( self . member , tostring ( value ) )
end

function Text:read(reader) 
return reader : readString ( self . member )
end


local function choose ( schema , value ) 
if value . kind == "string" then
return ( _G.setmetatable({ alternative =  "text" ,  value =  value }, Choice) )
else
assert ( value . kind == "numberToken" , "oneOf accepts text or an integer" )
local token = value : numberToken ( )
assert ( token : match ( "^%-?%d+$" ) ~= nil , "oneOf integer branch refused a fraction" )
local parsed = assert ( tonumber ( token ) , "invalid integer" )
assert ( parsed >= -2147483648 and parsed <= 2147483647 , "oneOf integer overflow" )
assert ( not schema . positiveAlternative or parsed <= 0 , "ambiguous oneOf: two integer alternatives match" )
return ( _G.setmetatable({ alternative =  "integer" ,  value =  value }, Choice) )
end
end

local Alternatives = {} Alternatives.__index = Alternatives

function Alternatives:describe(direction) 
return ( _G.setmetatable({ kind =  "dynamic" ,  member =  self . schema . payload ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) )
end

function Alternatives:write(value, writer) 
local selected = choose ( self . schema , value . value )
assert ( selected . alternative == value . alternative , "wrong oneOf selection" )
if selected . alternative == "text" then
writer : writeString ( self . schema . payload , selected . value : string ( ) )
else
writer : writeNumberToken ( self . schema . payload , selected . value : numberToken ( ) )
end
end

function Alternatives:read(reader) 
local value = reader : readDocument ( self . schema . payload , documents . adapter ( ) )
return choose ( self . schema , value )
end

local Builder = {} Builder.__index = Builder





function Builder:close() 
end

local Construction = {} Construction.__index = Construction
function Construction:begin() 
return ( _G.setmetatable({ secret =  "" ,  identifier =  "" ,  additional =  {} }, Builder) )
end

function Construction:finish(state) 
do local __nuppT25=0; local  __nuppT31 ; local __nuppT32=false ; local __nuppT26,__nuppT27,__nuppT28=__nuppT18(function() do local __nuppT33= state ; __nuppT31= __nuppT33 ; __nuppT25=1;  __nuppT32=true;  local owned=__nuppT31;
local result = _G.setmetatable({ name =
assert ( owned . name , "required name" ) ,  secret =
owned . secret ,  identifier =
owned . identifier ,  payload =
assert ( owned . payload , "required payload" ) ,  additional =
owned . additional }, Value)

do (function(__nuppT34,...)  __nuppT32=false; return __nuppT34:close(...)  end)( owned ) end

return "return",__nuppT13( result ) end; return "normal" end,__nuppT14); local __nuppT29={}; local __nuppT30=0; if __nuppT25>=1 and __nuppT32 then  local __nuppT35,__nuppT36=__nuppT17(__nuppCleanup1,__nuppT31);  if not __nuppT35 then __nuppT30=__nuppT30+1; __nuppT29[__nuppT30]=__nuppT36 end; end; if not __nuppT26 then if __nuppT30>0 then __nuppT19(__nuppT15(__nuppT27,__nuppT29,1),0) else __nuppT19(__nuppT27,0) end end; if __nuppT30>0 then if __nuppT30>1 then __nuppT19(__nuppT15(__nuppT29[1],__nuppT29,2),0) else __nuppT19(__nuppT29[1],0) end end; if __nuppT27=="return" then  return __nuppT20(__nuppT28,1,__nuppT28.n)  end; end
end

local Unknown = {} Unknown.__index = Unknown
function Unknown:apply(state, field, reader) 







local name = jsonDocument . fieldName ( field )
state . additional [ name ] = reader : captureValue ( documents . adapter ( ) )
end

local Additional = {} Additional.__index = Additional
function Additional:apply(value, writer) 
local names = { }
for name in pairs ( value . additional ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
writer : writeUnknown (
_G.setmetatable({ name =  name }, jsonDocument.FieldName) ,
assert ( value . additional [ name ] ) ,
documents . adapter ( )
)
end
end

binding=function ( schema ) 
local fields = {
structures . field (
schema . name ,
function ( value ) 
return value . name
end ,
function ( state , value ) 
state . name = value
end ,
_G.setmetatable({ member =  schema . name }, Text) ,
true ,
false
) ,
structures . field (
schema . secret ,
function ( value ) 
return value . secret
end ,
function ( state , value ) 
state . secret = value
end ,
_G.setmetatable({ member =  schema . secret }, Text) ,
false ,
true
) ,
structures . field (
schema . identifier ,
function ( value ) 
return value . identifier
end ,
function ( state , value ) 
state . identifier = value
end ,
_G.setmetatable({ member =  schema . identifier }, Text) ,
false ,
true
) ,
structures . field (
schema . payload ,
function ( value ) 
return value . payload
end ,
function ( state , value ) 
state . payload = value
end ,
_G.setmetatable({ schema =  schema }, Alternatives) ,
true ,
false
)
}

return ( _G.setmetatable({ adapter =
structures . structure ( schema . root , fields , _G.setmetatable({ }, Construction) , _G.setmetatable({ }, Unknown) , _G.setmetatable({ }, Additional) ) }, core.Bound) )

end ;__nuppExports["binding"]=binding

local DocumentBuilder = {} DocumentBuilder.__index = DocumentBuilder

function DocumentBuilder:close() 
end

local DocumentConstruction = {} DocumentConstruction.__index = DocumentConstruction
function DocumentConstruction:begin() 
return ( _G.setmetatable({ fields =  {} }, DocumentBuilder) )
end

function DocumentConstruction:finish(state) 
do local __nuppT51=0; local  __nuppT57 ; local __nuppT58=false ; local __nuppT52,__nuppT53,__nuppT54=__nuppT18(function() do local __nuppT59= state ; __nuppT57= __nuppT59 ; __nuppT51=1;  __nuppT58=true;  local owned=__nuppT57;
local value = documents . object ( owned . fields )
assert ( value : get ( "name" ) ~= nil and value : get ( "payload" ) ~= nil , "missing required OpenAPI property" )
for _ , name in ipairs ( { "secret" , "id" } ) do
if value : get ( name ) == nil then
owned . fields [ # owned . fields + 1 ] = _G.setmetatable({ name =  name ,  value =  documents . string ( "" ) }, documents.Entry)
end
end
value = documents . object ( owned . fields )
do (function(__nuppT60,...)  __nuppT58=false; return __nuppT60:close(...)  end)( owned ) end

return "return",__nuppT13( value ) end; return "normal" end,__nuppT14); local __nuppT55={}; local __nuppT56=0; if __nuppT51>=1 and __nuppT58 then  local __nuppT61,__nuppT62=__nuppT17(__nuppCleanup1,__nuppT57);  if not __nuppT61 then __nuppT56=__nuppT56+1; __nuppT55[__nuppT56]=__nuppT62 end; end; if not __nuppT52 then if __nuppT56>0 then __nuppT19(__nuppT15(__nuppT53,__nuppT55,1),0) else __nuppT19(__nuppT53,0) end end; if __nuppT56>0 then if __nuppT56>1 then __nuppT19(__nuppT15(__nuppT55[1],__nuppT55,2),0) else __nuppT19(__nuppT55[1],0) end end; if __nuppT53=="return" then  return __nuppT20(__nuppT54,1,__nuppT54.n)  end; end
end

local DocumentField = {} DocumentField.__index = DocumentField




function DocumentField:describe(direction) 
return self . adapter : describe ( direction )
end

function DocumentField:write(source, writer) 
local value = source : get ( self . member . name )
assert ( value ~= nil or not self . required , "missing required OpenAPI property" )
if value ~= nil then
self . adapter : write ( value , writer )
end
end

function DocumentField:read(state, reader) 
state . fields [
# state . fields + 1
] = _G.setmetatable({ name =  self . member . name ,  value =  self . adapter : read ( reader ) }, documents.Entry)
end

function DocumentField:accept(consumer) 
local name = self . member . name
return consumer : apply (
self . member ,
function ( source ) 
return source : get ( name ) ~= nil
end ,
structures . copiedGet ( function (
source
) 
return assert ( source : get ( name ) , "absent property" )
end ) ,
function ( state , value ) 
state . fields [ # state . fields + 1 ] = _G.setmetatable({ name =  name ,  value =  value }, documents.Entry)
end ,
self . adapter ,
nil
)
end

local DocumentScalar = {} DocumentScalar.__index = DocumentScalar


function DocumentScalar:describe(direction) 
return ( _G.setmetatable({ member =
self . member ,  kind =
self . member == self . schema . payload and "dynamic" or "string" ,  nullable =  false ,  canRead =  true ,  children =  {} }, Description) )

end

function DocumentScalar:write(value, writer) 
if self . member == self . schema . payload then
local copied = value . kind == "string" and documents . string ( value : string ( ) )
or documents . numberToken ( value : numberToken ( ) )
local selected = choose ( self . schema , copied )
if selected . alternative == "text" then
writer : writeString ( self . member , selected . value : string ( ) )
else
writer : writeNumberToken ( self . member , selected . value : numberToken ( ) )
end
else
writer : writeString ( self . member , value : string ( ) )
end
end

function DocumentScalar:read(reader) 
if self . member == self . schema . payload then
local value = reader : readDocument ( self . member , documents . adapter ( ) )
return choose ( self . schema , value ) . value
else
return documents . string ( reader : readString ( self . member ) )
end
end

local DocumentUnknown = {} DocumentUnknown.__index = DocumentUnknown
function DocumentUnknown:apply(state, field, reader) 





state . fields [
# state . fields + 1
] = _G.setmetatable({ name =  jsonDocument . fieldName ( field ) ,  value =  reader : captureValue ( documents . adapter ( ) ) }, documents.Entry)
end

local DocumentAdditional = {} DocumentAdditional.__index = DocumentAdditional

function DocumentAdditional:apply(value, writer) 
local names = { }
for index = 1 , value : size ( ) do
local field = value : field ( index )
if not self . names [ field . name ] then
names [ # names + 1 ] = field . name
end
end
table . sort ( names )
for _ , name in ipairs ( names ) do
writer : writeUnknown ( _G.setmetatable({ name =  name }, jsonDocument.FieldName) , assert ( value : get ( name ) ) , documents . adapter ( ) )
end
end

documentBinding=function ( schema ) 
local fields = { }
local names = { }
for _ , member in ipairs ( { schema . name , schema . secret , schema . identifier , schema . payload } ) do
local required = member == schema . name or member == schema . payload
fields [
# fields + 1
] = _G.setmetatable({ member =
member ,  required =
required ,  hasDefault =
not required ,  adapter =
_G.setmetatable({ schema =  schema ,  member =  member }, DocumentScalar) }, DocumentField)

names [ member . name ] = true
end

return ( _G.setmetatable({ adapter =
structures . structure (
schema . root ,
fields ,
_G.setmetatable({ }, DocumentConstruction) ,
_G.setmetatable({ }, DocumentUnknown) ,
_G.setmetatable({ names =  names }, DocumentAdditional)
) }, core.Bound) )

end ;__nuppExports["documentBinding"]=documentBinding

local Policy = {} Policy.__index = Policy

function Policy:name(member) 
return member . name
end

function Policy:select(member, direction) 
assert ( getmetatable ( member ) == Property , "OpenAPI policy needs its own property handles" )
local property = member
if self . view == "request" and property . readOnly or self . view == "response" and property . writeOnly then
return "omit"
end

return "traverse"
end

function Policy:timestamp(member, value) 
error ( "OpenAPI fixture has no timestamp mapping" )
end

function Policy:parseTimestamp(member, text, kind) 
error ( "OpenAPI fixture has no timestamp mapping" )
end

local Factory = {} Factory.__index = Factory

function Factory:policy(member) 
local documentPolicy = __serdeJson . documentPolicy ( member , true )
if documentPolicy ~= nil then
return documentPolicy
end
assert ( getmetatable ( member ) == Property , "OpenAPI policy needs its own model" )

return ( _G.setmetatable({ view =  self . view }, Policy) )
end

policy=function ( view ) 
return ( _G.setmetatable({ view =  view }, Factory) )
end ;__nuppExports["policy"]=policy
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Choice]="example.openapi\0Choice";__nuppWorkerRecords[Model]="example.openapi\0Model";__nuppWorkerRecords[Property]="example.openapi\0Property";__nuppWorkerRecords[Value]="example.openapi\0Value"; end);if not __nuppOk then package.loaded["example.openapi"]=nil;error(__nuppWhy,0) end;package.loaded["example.openapi"]=__nuppExports;return __nuppExports