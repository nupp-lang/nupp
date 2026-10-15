_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp); require("nupp.compiler.runtime.reflect").install(__nupp);local __nuppT46={}; local function __nuppT43(...) return {n=select("#",...),...} end; local __nuppT47,__nuppT48,__nuppT49,__nuppT50,__nuppT51,__nuppT52,__nuppT53,__nuppT54=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT44(value) return value end; local function __nuppT45(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT52({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT53(v.primary) for _,reason in __nuppT54(v.suppressed) do text=text.."\ncleanup: "..__nuppT53(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.debug"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local binding;__nuppExports["binding"]=function(...) return binding(...) end;local derived;__nuppExports["derived"]=function(...) return derived(...) end;local render;__nuppExports["render"]=function(...) return render(...) end;local renderer;__nuppExports["renderer"]=function(...) return renderer(...) end;local write;__nuppExports["write"]=function(...) return write(...) end;
























local core = require ( "nupp.serde.internal.value" )
local declarations = require ( "nupp.serde.internal.declaration" )
local text = require ( "nupp.text" )
local memos = require ( "nupp.serde.internal.memo" )
local identity = require ( "nupp.serde.internal.identity" )

local customFamily = { }
local CustomText = {} CustomText.__index = CustomText


function CustomText:snapshot() 
return ( _G.setmetatable({ family =  customFamily ,  text =  self . text : sub ( 1 ) }, CustomText) )
end

local CustomDescription = {} CustomDescription.__index = CustomDescription








local Custom = {} Custom.__index = Custom

function Custom:describe(direction) 
assert ( direction == "write" , "a Debug view cannot decode values" )
return self . description
end

function Custom:write(value, writer) 
local printable = value
writer : writeAtom ( self . description . member , _G.setmetatable({ family =  customFamily ,  text =  printable : debug ( ) }, CustomText) )
end

function Custom:read(reader) 
error ( "a Debug view cannot decode values" , 2 )
end


local function customDebug ( info , index , seen ) 
if seen [ index ] then
return false
end
seen [ index ] = true
local node = info . types [ index ]


if ( node . kind == "record" or node . kind == "struct" ) and node . deriveKey ~= nil then
return false
end
for _ , field in ipairs ( node . fields or { } ) do
if field . name == "debug" and field . read ~= nil then
local method = info . types [ field . read ]
local receiver = method . parameters ~= nil
and method . parameters [ 1 ] ~= nil
and info . types [ method . parameters [ 1 ] . type ]
or nil
local selfType = method . parameters ~= nil
and method . parameters [ 1 ] ~= nil
and ( method . parameters [ 1 ] . type == index or receiver . kind == "typevar" and receiver . bound == index )
if method . kind == "func"
and # ( method . parameters or { } ) == 1
and # ( method . returns or { } ) == 1
and selfType
and method . parameters [ 1 ] . mode == "plain"
and info . types [ method . returns [ 1 ] ] . kind == "string"
then
return true
end
end
end
if node . kind == "typevar" and node . bound ~= nil then
return customDebug ( info , node . bound , seen )
end

return false
end

local View = {} View.__index = View
function View:resolve(info, index, member) 





if customDebug ( info , index , { } ) then
return ( _G.setmetatable({ description =  _G.setmetatable({ member =  member ,  kind =  "atom" ,  nullable =  false ,  canRead =  false ,  children =  {} }, CustomDescription) }, Custom) )
end
return nil
end

local bindingKey = { }









binding=function ( target ) 
local info = nupp . reflect . runtime ( target )
local prior = rawget ( info , bindingKey )
if prior ~= nil then
return prior
end
local result = declarations . binding ( target , _G.setmetatable({ view =  _G.setmetatable({ }, View) ,  naming =  "identity" ,  unknownMembers =  "reject" }, declarations.Options) )
rawset ( info , bindingKey , result )

return result
end ;__nuppExports["binding"]=binding



local function action ( member ) 
local annotations = declarations . annotations ( member ) or { }
local skip , redact = false , false
for _ , annotation in ipairs ( annotations ) do
if annotation . name == "debug" then
for _ , argument in ipairs ( annotation . arguments ) do
if argument . name == "skip" then
skip = argument . value == true
elseif argument . name == "redact" then
redact = argument . value == true
end
end
end
end
assert ( not ( skip and redact ) , "a debug field cannot be both skipped and redacted" )

return skip and "skip" or redact and "redact" or "traverse"
end

local Plan = {} Plan.__index = Plan





local function plan ( description , seen ) 
local previous = seen [ description ]
if previous ~= nil then
return previous
end
assert ( description . kind ~= "opaque" , "debug field requires an explicit binding" )
local result = _G.setmetatable({ description =  description ,  actions =  {} ,  children =  {} }, Plan)
seen [ description ] = result
for _ , child in ipairs ( description . children ) do
local selected = action ( child . member )
result . actions [ child . member ] = selected
if selected == "traverse" then
result . children [ child . member ] = plan ( child : describe ( "write" ) , seen )
end
end

return result
end

local function planFor ( adapter ) 
return plan ( adapter : describe ( "write" ) , { } )
end

local Cache = {} Cache.__index = Cache

function Cache:clear() 
self . memo : clear ( )
end

function Cache:resolve(adapter) 
local found , cached = self . memo : find ( adapter , "write" )
if found then
return cached
end
local slot = self . memo : start ( adapter , "write" )
local ok , result = pcall ( planFor , adapter )

return self . memo : finish ( slot , ok , result )
end

local State = {} State.__index = State




local MapEntry = {} MapEntry.__index = MapEntry




local function compareEntries ( left , right ) 
return left . key < right . key
end

local Frame = {} Frame.__index = Frame






local contents
local Output = {} Output.__index = Output






function Output:live() 
assert ( not self . closed , "debug writer has expired" )
end

function Output:add(value) 
self . state . parts [ # self . state . parts + 1 ] = value
end

function Output:selected(member) 
self : live ( )
local frame = self . frames [ # self . frames ]
if frame == nil then
return self . root
end

return frame . plan . children [ member ] or frame . plan
end

function Output:position(member) 
self : live ( )
local frame = self . frames [ # self . frames ]
if frame == nil then
assert ( not self . rootWritten , "debug root was written twice" )
self . rootWritten = true
elseif frame . kind == "map" then
assert ( frame . entry , "debug map value outside entry" )
else
if frame . count > 0 then
self : add ( ", " )
end
frame . count += 1
if frame . kind == "structure" or frame . kind == "union" then
self : add ( member . name .. " = " )
end
end
end

function Output:token(member, value) 
self : position ( member )
self : add ( value )
end

function Output:include(member) 
self : live ( )
local frame = self . frames [ # self . frames ]
local selected = frame ~= nil and frame . plan . actions [ member ] or "traverse"
if selected == "skip" then
return false
elseif selected == "redact" then
self : token ( member , "<redacted>" ) ;
return false
else
return true
end
end

function Output:writeNull(member) 
self : token ( member , "nil" )
end

function Output:writeBoolean(member, value) 
self : token ( member , value and "true" or "false" )
end

function Output:writeInteger(member, value) 
self : token ( member , value . decimal .. ( value . width == 64 and ( value . signed and "LL" or "ULL" ) or "" ) )
end

function Output:writeFloat(member, value, width) 
self : token ( member , tostring ( value ) )
end

function Output:writeNumberToken(member, value) 
self : token ( member , value )
end

function Output:writeString(member, value) 
self : token ( member , ( "%q" ) : format ( value ) )
end

function Output:writeBytes(member, value) 
self : token ( member , "bytes(" .. # value .. ")" )
end

function Output:writeBigInteger(member, value) 
self : token ( member , value )
end

function Output:writeDecimal(member, value) 
self : token ( member , value . coefficient .. "e" .. value . exponent )
end

function Output:writeTimestamp(member, value) 
self : token ( member , "timestamp(" .. value . seconds .. ", " .. value . nanos .. ")" )
end

function Output:writeAtom(member, value) 
if value . family == customFamily then
self : token ( member , ( value ) . text : sub ( 1 ) )
else
self : token ( member , "<atom>" )
end
end

function Output:writeDocument(member, value, adapter) 
self : position ( member )
contents ( adapter , value , self . state , self . depth + # self . frames + 1 )
end

function Output:aggregate(member, kind, source, emit) 
self : live ( )
assert ( self . depth + # self . frames < 128 , "debug nesting limit exceeded" )
self : position ( member )
local id = identity ( source )
if id ~= nil and self . state . active [ id ] then
self : add ( "<cycle>" ) ;
return
end
if id ~= nil then
self . state . active [ id ] = true
end
local label = kind == "structure" and declarations . label ( member ) or nil
self : add ( label ~= nil and label .. " { " or "{" )
local frame = _G.setmetatable({ plan =  self : selected ( member ) ,  kind =  kind ,  count =  0 ,  entry =  false ,  entries =  {} }, Frame)
self . frames [ # self . frames + 1 ] = frame
emit : apply ( source , self )
if kind == "map" then
table . sort ( frame . entries , compareEntries )
for index , entry in ipairs ( frame . entries ) do
if index > 1 then
self : add ( ", " )
end
for _ , part in ipairs ( entry . parts ) do
self : add ( part )
end
end
end
self . frames [ # self . frames ] = nil
self : add ( label ~= nil and " }" or "}" )
if id ~= nil then
self . state . active [ id ] = nil
end
end

function Output:writeStruct(member, source, emit) 
self : aggregate ( member , "structure" , source , emit )
end

function Output:writeUnion(member, source, emit) 
self : aggregate ( member , "union" , source , emit )
end

function Output:writeList(member, size, source, emit) 
self : aggregate ( member , "list" , source , emit )
end

function Output:writeTuple(member, size, source, emit) 
self : aggregate ( member , "tuple" , source , emit )
end

function Output:writeMap(member, size, source, emit) 
self : aggregate ( member , "map" , source , emit )
end

function Output:writeEntry(key, keyEmit, value, valueEmit) 






self : live ( )
local frame = assert ( self . frames [ # self . frames ] , "debug entry outside map" )
assert ( frame . kind == "map" and not frame . entry , "debug entry outside map" )
local start = # self . state . parts + 1
frame . count += 1
frame . entry = true
self : add ( "[" )
keyEmit : apply ( key , self )
self : add ( "] = " )
valueEmit : apply ( value , self )
frame . entry = false
local parts = { }
for index = start , # self . state . parts do
parts [ # parts + 1 ] = self . state . parts [ index ]
end
for index = # self . state . parts , start , - 1 do
self . state . parts [ index ] = nil
end
frame . entries [ # frame . entries + 1 ] = _G.setmetatable({ key =  tostring ( key ) ,  parts =  parts }, MapEntry)
end

function Output:writeUnknown(field, value, adapter) 





self : live ( )
local frame = assert ( self . frames [ # self . frames ] , "unknown debug field outside structure" )
if frame . count > 0 then
self : add ( ", " )
end
frame . count += 1
self : add ( "unknown(" .. field : diagnosticLabel ( ) .. ") = " )
contents ( adapter , value , self . state , self . depth + # self . frames )
end

function Output:close() 
self . closed = true
end


local function output ( selected , state , depth ) 
return ( _G.setmetatable({ root =  selected ,  state =  state ,  depth =  depth ,  frames =  {} ,  rootWritten =  false ,  closed =  false }, Output) )
end

local Render = {} Render.__index = Render


function Render:apply(adapter, value) local __nuppT42;
local selected = self . state . cache : resolve ( adapter )
do const  __nuppT61= output ( selected , self . state , self . depth ) ; __nuppT42=__nuppT42 or {} ; local __nuppT62=__nuppT42[1]; if not __nuppT62 then __nuppT62=function(writer) do
adapter : write ( value , writer )
assert ( writer . rootWritten , "debug binding did not emit a value" ) end; return "normal" end; __nuppT42[1]=__nuppT62 end; const __nuppT56,__nuppT57,__nuppT58=__nuppT48(__nuppT62,__nuppT44,__nuppT61); const __nuppT55=1; local __nuppT59={}; local __nuppT60=0; if __nuppT55>=1 then  local __nuppT63,__nuppT64=__nuppT47(__nuppCleanup1,__nuppT61);  if not __nuppT63 then __nuppT60=__nuppT60+1; __nuppT59[__nuppT60]=__nuppT64 end; end; if not __nuppT56 then if __nuppT60>0 then __nuppT49(__nuppT45(__nuppT57,__nuppT59,1),0) else __nuppT49(__nuppT57,0) end end; if __nuppT60>0 then if __nuppT60>1 then __nuppT49(__nuppT45(__nuppT59[1],__nuppT59,2),0) else __nuppT49(__nuppT59[1],0) end end; if __nuppT57=="return" then  return __nuppT50(__nuppT58,1,__nuppT58.n)  end; end
end

contents = function ( adapter , value , state , depth ) 
assert ( depth <= 128 , "debug nesting limit exceeded" )
adapter : contents ( ) : accept ( _G.setmetatable({ state =  state ,  depth =  depth }, Render) , value )
end



















local Implementation = {} Implementation.__index = Implementation

function Implementation:render(selectedBinding, value) 
local state = _G.setmetatable({ cache =  self . cache ,  parts =  {} ,  active =  {} }, State)
selectedBinding : accept ( _G.setmetatable({ state =  state ,  depth =  0 }, Render) , value )
return table . concat ( state . parts )
end

function Implementation:write(selectedBinding, value, buffer) 
local state = _G.setmetatable({ cache =  self . cache ,  parts =  {} ,  active =  {} }, State)
selectedBinding : accept ( _G.setmetatable({ state =  state ,  depth =  0 }, Render) , value )
for _ , part in ipairs ( state . parts ) do
buffer : put ( part )
end
end

function Implementation:clear() 
self . cache : clear ( )
end

function Implementation:cachedBindings() 
return self . cache . memo : size ( )
end







renderer=function ( capacity ) 
return ( _G.setmetatable({ cache =  _G.setmetatable({ memo =  memos . new ( "Debug extension" , capacity ) }, Cache) }, Implementation) )
end ;__nuppExports["renderer"]=renderer

local defaultRenderer = renderer ( )






render=function ( selectedBinding , value ) 
return defaultRenderer : render ( selectedBinding , value )
end ;__nuppExports["render"]=render


















write=function ( selectedBinding , value , buffer ) 
defaultRenderer : write ( selectedBinding , value , buffer )
end ;__nuppExports["write"]=write










derived=function ( target , value ) 
return defaultRenderer : render ( binding ( target ) , value )
end ;__nuppExports["derived"]=derived
 end);if not __nuppOk then package.loaded["nupp.serde.debug"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.debug"]=__nuppExports;return __nuppExports