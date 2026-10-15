_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.xmlsyntax"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local identity;__nuppExports["identity"]=function(...) return identity(...) end;local reader;__nuppExports["reader"]=function(...) return reader(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.xmlsyntax\0runtime\0001") , _G.nupp.__reflect.declaration("example.xmlsyntax\0runtime\0002") , _G.nupp.__reflect.declaration("example.xmlsyntax\0runtime\0003") , _G.nupp.__reflect.declaration("example.xmlsyntax\0runtime\0004") , _G.nupp.__reflect.declaration("example.xmlsyntax\0runtime\0006") };

local core = require ( "nupp.serde" )
local utf8 = require ( "nupp.text.utf8" )



local Field = {} Field.__index = Field



function Field:diagnosticLabel() 
return "XML field"
end ;_G.nupp.__reflect.link(Field,__nuppT1[1],{ }) ;__nuppExports["Field"]=Field

local Attribute = {} Attribute.__index = Attribute ;_G.nupp.__reflect.link(Attribute,__nuppT1[2],{ __nuppT1[1] }) ;__nuppExports["Attribute"]=Attribute



local Event = {} Event.__index = Event ;_G.nupp.__reflect.link(Event,__nuppT1[3],{ __nuppT1[1] , __nuppT1[2] }) ;__nuppExports["Event"]=Event





local Frame = {} Frame.__index = Frame ;_G.nupp.__reflect.link(Frame,__nuppT1[4],{ __nuppT1[1] })




local RawAttribute = {} RawAttribute.__index = RawAttribute




local entities = { amp = "&" , lt = "<" , gt = ">" , quot = "\"" , apos = "'" }

local function unescape ( text ) 
local parts = { }
local position = 1
while true do
local first = text : find ( "&" , position , true )
if first == nil then
parts [ # parts + 1 ] = text : sub ( position ) ;
do break end
end
parts [ # parts + 1 ] = text : sub ( position , first - 1 )
local last = text : find ( ";" , first + 1 , true )
if last == nil then
error ( "unterminated XML entity" , 2 )
end
local entity = text : sub ( first + 1 , last - 1 )
local value = entities [ entity ]
if value == nil then
local decimal = entity : match ( "^#(%d+)$" )
local hex = entity : match ( "^#x([%da-fA-F]+)$" )
local number = decimal ~= nil and tonumber ( decimal ) or hex ~= nil and tonumber ( hex , 16 ) or nil
if number == nil
or number > 1114111
or number >= 55296 and number <= 57343
or number == 65534
or number == 65535
or number < 32 and number ~= 9 and number ~= 10 and number ~= 13
then
error ( "unsupported XML entity" , 2 )
end
value = utf8 . encode ( number )
end
parts [ # parts + 1 ] = value
position = last + 1
end

return table . concat ( parts )
end

local function field ( qualified , role , bindings ) 
local prefix , name = qualified : match ( "^([^:]+):([^:]+)$" )
local uri = ""
if prefix ~= nil then
local found = bindings [ prefix ]
if found == nil or found == "" then
error ( "unbound XML namespace prefix" , 2 )
end
uri = found
else
if qualified : find ( ":" , 1 , true ) then
error ( "invalid XML qualified name" , 2 )
end
name = qualified
if role == "element" then
uri = bindings [ "" ] or ""
end
end

return ( _G.setmetatable({ namespaceUri =  uri ,  localName =  name ,  role =  role }, Field) )
end

local Reader = {} Reader.__index = Reader







function Reader:space() 
while self . input : sub ( self . position , self . position ) : match ( "%s" ) do
self . position += 1
end
end

function Reader:name() 
local value = self . input : sub ( self . position ) : match ( "^([A-Za-z_][A-Za-z0-9_.:-]*)" )
if value == nil then
error ( "expected an ASCII XML qualified name" , 2 )
end
self . position += # value

return value
end

function Reader:next() 
self . events += 1
if self . events > 1000000 then
error ( "XML event budget exceeded" , 2 )
end
if self . pendingEnd then
self . pendingEnd = false
local frame = table . remove ( self . frames )
return ( _G.setmetatable({ kind =  "end" ,  field =  frame . field ,  attributes =  { } }, Event) )
end
while true do
local position = self . position
if position > # self . input then
if # self . frames ~= 0 or self . roots ~= 1 then
error ( "incomplete XML root" , 2 )
end
return nil
end
if self . input : sub ( position , position + 3 ) == "<!--" then
local last = self . input : find ( "-->" , position + 4 , true )
if last == nil or self . input : sub ( position + 4 , last - 1 ) : find ( "--" , 1 , true ) then
error ( "invalid XML comment" , 2 )
end
self . position = last + 3
elseif self . input : sub ( position , position ) ~= "<" then
local last = self . input : find ( "<" , position , true ) or # self . input + 1
local text = self . input : sub ( position , last - 1 )
self . position = last
if # self . frames == 0 then
if text : find ( "%S" ) then
error ( "text outside XML root" , 2 )
end
else
if text : find ( "]]>" , 1 , true ) then
error ( "invalid XML text" , 2 )
end
return ( _G.setmetatable({ kind =  "text" ,  attributes =  { } ,  text =  unescape ( text ) }, Event) )
end
elseif self . input : sub ( position , position + 1 ) == "</" then
self . position += 2
local qualified = self : name ( )
self : space ( )
if self . input : sub ( self . position , self . position ) ~= ">" then
error ( "invalid XML end tag" , 2 )
end
self . position += 1
local frame = table . remove ( self . frames )
if frame == nil or frame . qualified ~= qualified then
error ( "mismatched XML end tag" , 2 )
end
return ( _G.setmetatable({ kind =  "end" ,  field =  frame . field ,  attributes =  { } }, Event) )
else
if self . input : sub ( position , position + 1 ) == "<!" or self . input : sub ( position , position + 1 ) == "<?" then
error ( "unsupported XML declaration" , 2 )
end
self . position += 1
local qualified = self : name ( )
local raw = { }
local bindings = { xml = "http://www.w3.org/XML/1998/namespace" }
local parent = self . frames [ # self . frames ]
if parent ~= nil then
for key , value in pairs ( parent . bindings ) do
bindings [ key ] = value
end
end
local names = { }
while true do
local before = self . position
self : space ( )
local mark = self . input : sub ( self . position , self . position )
if mark == ">" or mark == "/" then
do break end
end
if before == self . position then
error ( "missing XML attribute separator" , 2 )
end
local name = self : name ( )
if names [ name ] then
error ( "duplicate XML attribute" , 2 )
end
names [ name ] = true
self : space ( )
if self . input : sub ( self . position , self . position ) ~= "=" then
error ( "expected XML attribute equals" , 2 )
end
self . position += 1
self : space ( )
local quote = self . input : sub ( self . position , self . position )
if quote ~= '"' and quote ~= "'" then
error ( "expected quoted XML attribute" , 2 )
end
local last = self . input : find ( quote , self . position + 1 , true )
if last == nil then
error ( "unterminated XML attribute" , 2 )
end
local text = self . input : sub ( self . position + 1 , last - 1 )
if text : find ( "<" , 1 , true ) then
error ( "invalid XML attribute value" , 2 )
end
local value = unescape ( ( text : gsub ( "[\t\n]" , " " ) ) )
self . position = last + 1
local prefix = name : match ( "^xmlns:(.+)$" )
if name == "xmlns" then
bindings [ "" ] = value
elseif prefix ~= nil then
if prefix == "xmlns"
or prefix == "xml" and value ~= bindings . xml
or value == ""
or value == "http://www.w3.org/2000/xmlns/"
or value == bindings . xml and prefix ~= "xml"
then
error ( "reserved XML namespace" , 2 )
end
bindings [ prefix ] = value
else
raw [ # raw + 1 ] = _G.setmetatable({ name =  name ,  value =  value }, RawAttribute)
end
end
self . pendingEnd = self . input : sub ( self . position , self . position ) == "/"
if self . pendingEnd then
self . position += 1
end
if self . input : sub ( self . position , self . position ) ~= ">" then
error ( "invalid XML start tag" , 2 )
end
self . position += 1
if # self . frames == 0 then
self . roots += 1
if self . roots ~= 1 then
error ( "multiple XML roots" , 2 )
end
end
if # self . frames >= 128 then
error ( "XML depth limit exceeded" , 2 )
end
local identity = field ( qualified , "element" , bindings )
local attributes = { }
local expanded = { }
for _ , attribute in ipairs ( raw ) do
local name = field ( attribute . name , "attribute" , bindings )
local key = # name . namespaceUri .. ":" .. name . namespaceUri .. name . localName
if expanded [ key ] then
error ( "duplicate expanded XML attribute" , 2 )
end
expanded [ key ] = true
attributes [ # attributes + 1 ] = _G.setmetatable({ field =  name ,  value =  attribute . value }, Attribute)
end
self . frames [ # self . frames + 1 ] = _G.setmetatable({ qualified =  qualified ,  field =  identity ,  bindings =  bindings }, Frame)
return ( _G.setmetatable({ kind =  "start" ,  field =  identity ,  attributes =  attributes }, Event) )
end
end
end ;_G.nupp.__reflect.link(Reader,__nuppT1[5],{ __nuppT1[4] }) ;__nuppExports["Reader"]=Reader


reader=function ( input ) 
if # input > 16777216
or not utf8 . isValid ( input )
or input : find ( "[%z\1-\8\11\12\14-\31]" )
or input : find ( "\239\191[\190\191]" )
then
error ( "invalid XML input" , 2 )
end
input = input : gsub ( "\r\n" , "\n" ) : gsub ( "\r" , "\n" )

return ( _G.setmetatable({ input =  input ,  position =  1 ,  frames =  { } ,  pendingEnd =  false ,  roots =  0 ,  events =  0 }, Reader) )
end ;__nuppExports["reader"]=reader

identity=function ( value ) 
if getmetatable ( value ) ~= Field then
error ( "not an XML field identity" , 2 )
end
return value
end ;__nuppExports["identity"]=identity
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Attribute]="example.xmlsyntax\0Attribute";__nuppWorkerRecords[Event]="example.xmlsyntax\0Event";__nuppWorkerRecords[Field]="example.xmlsyntax\0Field";__nuppWorkerRecords[Reader]="example.xmlsyntax\0Reader"; end);if not __nuppOk then package.loaded["example.xmlsyntax"]=nil;error(__nuppWhy,0) end;package.loaded["example.xmlsyntax"]=__nuppExports;return __nuppExports