_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.syntax.docblock\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.syntax.docblock\0runtime\0002") };















local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local syntax = require ( "nupp.compiler.syntax.docsyntax" )

local docblock = { }






docblock.Raise = {} docblock.Raise.__index = docblock.Raise ;_G.nupp.__reflect.link(docblock.Raise,__nuppT1[1],{ })








docblock.Doc = {} docblock.Doc.__index = docblock.Doc ;_G.nupp.__reflect.link(docblock.Doc,__nuppT1[2],{ __nuppT1[1] })






















local function trim ( text ) 
return ( text : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) )
end





local function splitRaise ( text ) 
local written = ( ( text : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) ) )
local name , rest = written : match ( "^(%S+)%s*(.*)$" )

return ( _G.setmetatable({ type =  name or "" ,  text =  trim ( rest or "" ) }, docblock.Raise) )
end



local function firstToken ( node ) 
if not node then
return nil
end
if cst . isToken ( node ) then
return node
end
for _ , child in ipairs ( node ) do
local token = firstToken ( child )
if token then
return token
end
end

return nil
end









function docblock . linesOf ( node ) 
local token = firstToken ( node )
local lines = { }
local pending = { }
for index = 1 , token and token . triviaCount or 0 do
local kind = lexer . triviaKind ( token , index )
local text = lexer . triviaText ( token , index )
local body = kind == "comment" and syntax . docComment : match ( text ) or nil
if body ~= nil then
pending [ # pending + 1 ] = body : gsub ( "\13$" , "" )
elseif kind == "comment" then
pending = { }
elseif kind == "whitespace" then
local _ , newlines = text : gsub ( "\n" , "" )
if newlines > 1 then
pending = { }
end
end
end
for _ , line in ipairs ( pending ) do
lines [ # lines + 1 ] = line
end

return lines
end










function docblock . parse ( lines ) 
local params = { }
local fields = { }
local typeargs = { }
local returns = { }
local raises = { }
local tags = { }



local named = { param = params , field = fields , typearg = typeargs }
local listed = { [ "return" ] = returns , returns = returns }

local body = { }
local active = nil
local activeName = nil



local fence = nil
for _ , line in ipairs ( lines ) do
local marker , rest
fence , marker , rest = syntax . fenceState ( line , fence )
local tag , value = nil , nil
if not marker and not fence then
tag , value = syntax . tag : match ( line )
end
if marker then
active , activeName = nil , nil
body [ # body + 1 ] = line
elseif fence then
active , activeName = nil , nil
body [ # body + 1 ] = line
elseif tag then
local text = value or ""
active , activeName = tag , nil
local into , list = named [ tag ] , listed [ tag ]
if tag == "raises" then
raises [ # raises + 1 ] = splitRaise ( text )
elseif into then
local name , description = syntax . nameValue : match ( text )





if name and # name > 1 and name : sub ( -1 ) == "?" then
name = name : sub ( 1 , -2 )
end
if name then
activeName = name
into [ name ] = description or ""
end
elseif list then
list [ # list + 1 ] = text
else
tags [ tag ] = text ~= "" and text or true
end
elseif active and syntax . indented : match ( line ) then
local continuation = ( ( line : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) ) )
local into , list = named [ active ] , listed [ active ]
if active == "raises" then




local raise = raises [ # raises ]
if raise then
raise . text = trim ( raise . text .. " " .. continuation )
end
elseif list then
local index = # list
list [ index ] = trim ( ( list [ index ] or "" ) .. " " .. continuation )
elseif into and activeName then
into [ activeName ] = trim ( ( into [ activeName ] or "" ) .. " " .. continuation )
elseif tags [ active ] ~= nil then
local prior = tags [ active ]
tags [ active ] = trim ( ( prior == true and "" or tostring ( prior ) ) .. " " .. continuation )
else
body [ # body + 1 ] = line
end
else
active , activeName = nil , nil
body [ # body + 1 ] = line
end
end
while # body > 0 and trim ( body [ 1 ] ) == "" do
table . remove ( body , 1 )
end
while # body > 0 and trim ( body [ # body ] ) == "" do
table . remove ( body )
end

return ( _G.setmetatable({ text =
table . concat ( body , "\n" ) ,  params =
params ,  returns =
returns ,  raises =
raises ,  fields =
fields ,  typeargs =
typeargs ,  tags =
tags }, docblock.Doc) )

end







function docblock . of ( node ) 
local lines = docblock . linesOf ( node )
return docblock . parse ( lines ) , # lines > 0
end

local __nuppExportValue= docblock ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.syntax.docblock"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.syntax.docblock"]=__nuppExports;return __nuppExports