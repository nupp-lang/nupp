_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local cst = require ( "nupp.compiler.cst" )
local lexer = require ( "nupp.compiler.lexer" )
local syntax = require ( "nupp.compiler.doc.syntax" )

local docblock = { }


docblock.Doc = {} docblock.Doc.__index = docblock.Doc






















local function trim ( text )
return ( text : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) )
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
pending [ # pending + 1 ] = body : gsub ( "\r$" , "" )
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
local listed = { [ "return" ] = returns , returns = returns , raises = raises }

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
if into then
local name , description = syntax . nameValue : match ( text )
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
local continuation = trim ( line )
local into , list = named [ active ] , listed [ active ]
if list then
local index = # list
list [ index ] = trim ( ( list [ index ] or "" ) .. " " .. continuation )
elseif into and activeName then
into [ activeName ] = trim ( ( into [ activeName ] or "" ) .. " " .. continuation )
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

return setmetatable({ text =
table . concat ( body , "\n" ) ,  params =
params ,  returns =
returns ,  raises =
raises ,  fields =
fields ,  typeargs =
typeargs ,  tags =
tags }, docblock.Doc)

end







function docblock . of ( node )
local lines = docblock . linesOf ( node )
return docblock . parse ( lines ) , # lines > 0
end

return docblock
