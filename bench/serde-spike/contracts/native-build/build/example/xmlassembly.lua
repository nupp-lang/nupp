_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["example.xmlassembly"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local copy;__nuppExports["copy"]=function(...) return copy(...) end;local encode;__nuppExports["encode"]=function(...) return encode(...) end;local parse;__nuppExports["parse"]=function(...) return parse(...) end;local read;__nuppExports["read"]=function(...) return read(...) end;local text;__nuppExports["text"]=function(...) return text(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("example.xmlassembly\0runtime\0001") , _G.nupp.__reflect.declaration("example.xmlassembly\0runtime\0002") };

local core = require ( "nupp.serde" )
local syntax = require ( "example.xmlsyntax" )

local Node = {} Node.__index = Node ;_G.nupp.__reflect.link(Node,__nuppT1[1],{ _G.nupp.__reflect.reference("example.xmlsyntax\0runtime\0001","example.xmlsyntax") , _G.nupp.__reflect.reference("example.xmlsyntax\0runtime\0002","example.xmlsyntax") , __nuppT1[1] }) ;__nuppExports["Node"]=Node





local function element ( reader , start ) 
local content = { }
while true do
local event = assert ( reader : next ( ) , "incomplete XML element" )
if event . kind == "end" then
return ( _G.setmetatable({ field =  assert ( start . field ) ,  attributes =  start . attributes ,  content =  content }, Node) )
elseif event . kind == "text" then
content [ # content + 1 ] = assert ( event . text )
else
content [ # content + 1 ] = element ( reader , event )
end
end
end

parse=function ( bytes ) 
local reader = syntax . reader ( bytes )
local start = assert ( reader : next ( ) , "missing XML root" )
assert ( start . kind == "start" , "expected XML root" )
local result = element ( reader , start )
assert ( reader : next ( ) == nil , "trailing XML content" )

return result
end ;__nuppExports["parse"]=parse

text=function ( node ) 
assert ( # node . attributes == 0 , "scalar XML value has attributes" )
local parts = { }
for _ , item in ipairs ( node . content ) do
assert ( type ( item ) == "string" , "scalar XML value has a nested element" )
parts [ # parts + 1 ] = item
end

return table . concat ( parts )
end ;__nuppExports["text"]=text

local Mapping = {} Mapping.__index = Mapping ;_G.nupp.__reflect.link(Mapping,__nuppT1[2],{ _G.nupp.__reflect.reference("example.xmlsyntax\0runtime\0001","example.xmlsyntax") }) ;__nuppExports["Mapping"]=Mapping









local function identity ( field ) 
return field . role .. ":" .. # field . namespaceUri .. ":" .. field . namespaceUri .. field . localName
end

local Group = {} Group.__index = Group




read=function (
root ,
mappings ,
state ,
consumer
) 
local byIdentity = { }
local ordered = { }
for _ , mapping in ipairs ( mappings ) do
local key = identity ( mapping . field )
assert ( byIdentity [ key ] == nil , "duplicate expanded XML binding" )
assert ( not mapping . repeated or mapping . field . role == "element" , "XML attributes cannot repeat" )
local group = _G.setmetatable({ mapping =  mapping ,  values =  { } }, Group)
byIdentity [ key ] = group
ordered [ # ordered + 1 ] = group
end
local values = { }
for _ , attribute in ipairs ( root . attributes ) do
values [ # values + 1 ] = _G.setmetatable({ field =  attribute . field ,  attributes =  { } ,  content =  { attribute . value } }, Node)
end
for _ , item in ipairs ( root . content ) do
if type ( item ) == "string" then
assert ( ( item ) : match ( "^%s*$" ) ~= nil , "mixed content is not a modeled XML structure" )
else
values [ # values + 1 ] = item
end
end
local unknown = { }
for _ , value in ipairs ( values ) do
local group = byIdentity [ identity ( value . field ) ]
if group == nil then
unknown [ # unknown + 1 ] = value
else
assert ( group . mapping . repeated or # group . values == 0 , "duplicate scalar XML member" )
group . values [ # group . values + 1 ] = value
end
end


for _ , group in ipairs ( ordered ) do
if # group . values > 0 then
consumer : apply ( state , group . mapping . member , group . values )
end
end
for _ , value in ipairs ( unknown ) do
consumer : unknown ( state , value )
end
end ;__nuppExports["read"]=read

copy=function ( node , depth ) 
local current = depth or 0
assert ( current <= 128 , "XML nesting limit exceeded" )
local attributes = { }
for _ , attribute in ipairs ( node . attributes ) do
attributes [
# attributes + 1
] = _G.setmetatable({ field =
_G.setmetatable({ namespaceUri =
attribute . field . namespaceUri ,  localName =
attribute . field . localName ,  role =
attribute . field . role }, syntax.Field) ,  value =

attribute . value }, syntax.Attribute)

end
local content = { }
for _ , value in ipairs ( node . content ) do
content [ # content + 1 ] = type ( value ) == "string" and value or copy ( value , current + 1 )
end

return ( _G.setmetatable({ field =
_G.setmetatable({ namespaceUri =
node . field . namespaceUri ,  localName =
node . field . localName ,  role =
node . field . role }, syntax.Field) ,  attributes =

attributes ,  content =
content }, Node) )

end ;__nuppExports["copy"]=copy

local function escaped ( value ) 
local utf8 = require ( "nupp.text.utf8" )
assert (
utf8 . isValid ( value ) and not value : find ( "[%z\1-\8\11\12\14-\31]" ) and not value : find ( "ï¿[¾¿]" ) ,
"invalid XML text"
)

return (
value : gsub ( "&" , "&amp;" )
: gsub ( "<" , "&lt;" )
: gsub ( ">" , "&gt;" )
: gsub ( "\"" , "&quot;" )
: gsub ( "\13" , "&#13;" )
: gsub ( "\n" , "&#10;" )
: gsub ( "\9" , "&#9;" )
)
end

local function name ( field ) 
assert ( field . localName : match ( "^[A-Za-z_][A-Za-z0-9_.-]*$" ) ~= nil , "invalid XML local name" )
assert ( field . namespaceUri ~= "http://www.w3.org/2000/xmlns/" , "reserved XML namespace" )
return field . localName
end

local function emit ( node , parts , depth ) 
assert ( depth <= 128 , "XML nesting limit exceeded" )
assert ( node . field . role == "element" , "XML root must be an element" )
local localName = name ( node . field )
local qualified = localName
if node . field . namespaceUri ~= "" then
if node . field . namespaceUri == "http://www.w3.org/XML/1998/namespace" then
qualified = "xml:" .. localName
else
qualified = "n:" .. localName
end
end
parts [ # parts + 1 ] = "<" .. qualified
if node . field . namespaceUri ~= "" and qualified : sub ( 1 , 2 ) == "n:" then
parts [ # parts + 1 ] = " xmlns:n=\"" .. escaped ( node . field . namespaceUri ) .. "\""
end
local seen = { }
for index , attribute in ipairs ( node . attributes ) do
assert ( attribute . field . role == "attribute" , "invalid XML attribute identity" )
local key = identity ( attribute . field )
assert ( not seen [ key ] , "duplicate expanded XML attribute" )
seen [ key ] = true
local attributeName = name ( attribute . field )
assert ( attributeName ~= "xmlns" , "namespace declaration is not a value attribute" )
if attribute . field . namespaceUri == "http://www.w3.org/XML/1998/namespace" then
attributeName = "xml:" .. attributeName
elseif attribute . field . namespaceUri ~= "" then
local prefix = "a" .. index
parts [ # parts + 1 ] = " xmlns:" .. prefix .. "=\"" .. escaped ( attribute . field . namespaceUri ) .. "\""
attributeName = prefix .. ":" .. attributeName
end
parts [ # parts + 1 ] = " " .. attributeName .. "=\"" .. escaped ( attribute . value ) .. "\""
end
parts [ # parts + 1 ] = ">"
for _ , value in ipairs ( node . content ) do
if type ( value ) == "string" then
parts [ # parts + 1 ] = escaped ( value )
else
emit ( value , parts , depth + 1 )
end
end
parts [ # parts + 1 ] = "</" .. qualified .. ">"
end

encode=function ( node ) 
local parts = { }
emit ( node , parts , 0 )
local result = table . concat ( parts )
assert ( # result <= 16777216 , "XML output exceeds byte limit" )

return result
end ;__nuppExports["encode"]=encode
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Mapping]="example.xmlassembly\0Mapping";__nuppWorkerRecords[Node]="example.xmlassembly\0Node"; end);if not __nuppOk then package.loaded["example.xmlassembly"]=nil;error(__nuppWhy,0) end;package.loaded["example.xmlassembly"]=__nuppExports;return __nuppExports