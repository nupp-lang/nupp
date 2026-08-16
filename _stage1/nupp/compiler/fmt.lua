_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);























































local parser = require ( "nupp.compiler.parser" )
local lexer = require ( "nupp.compiler.lexer" )
local cst = require ( "nupp.compiler.cst" )
local displayWidth = require ( "nupp.compiler.fmt.displaywidth" )
local docSyntax = require ( "nupp.compiler.doc.syntax" )

local fmt = { }

local INDENT = "    "
local WIDTH = 120
local DOC_WIDTH = 88
local MAX_PASSES = 24

local NO_SPACE_BEFORE = {
[ "," ] = true ,
[ ";" ] = true ,
[ ")" ] = true ,
[ "]" ] = true ,
[ "}" ] = true ,
[ "." ] = true ,
[ ":" ] = true ,
[ "?." ] = true ,
[ "istringMid" ] = true ,
[ "istringClose" ] = true ,
}

local NO_SPACE_AFTER = {
[ "(" ] = true ,
[ "[" ] = true ,
[ "{" ] = true ,
[ "." ] = true ,
[ ":" ] = true ,
[ "::" ] = true ,
[ "?." ] = true ,
[ "#" ] = true ,
[ "@" ] = true ,
[ "istringOpen" ] = true ,
[ "istringMid" ] = true ,
}


local CALLEE_KINDS = { [ "name" ] = true , [ ")" ] = true , [ "]" ] = true , [ "string" ] = true , [ "function" ] = true , }


local CLOSERS = {
[ "end" ] = true ,
[ "until" ] = true ,
[ "else" ] = true ,
[ "elseif" ] = true ,
[ "then" ] = true ,
[ "}" ] = true ,
[ ")" ] = true ,
[ "]" ] = true ,


[ ">" ] = true ,
}
local BRACKET_PAIR = { [ "(" ] = ")" , [ "[" ] = "]" , [ "{" ] = "}" , [ "<" ] = ">" }




local SPREADING_GROUPS = { [ "args" ] = "hug" , [ "tableExpr" ] = "spread" }



local BLOCK_CLOSERS = { [ "end" ] = true , [ "}" ] = true }

local BREAK_OPS = {
[ "and" ] = true ,
[ "or" ] = true ,
[ ".." ] = true ,
[ "+" ] = true ,
[ "-" ] = true ,
[ "*" ] = true ,
[ "/" ] = true ,
[ "&" ] = true ,
[ "|" ] = true ,
}





local function firstToken ( n )
if cst . isToken ( n ) then
return ( not n . missing and n . kind ~= "eof" ) and n or nil
end
for _ , child in ipairs ( n ) do
local t = firstToken ( child )
if t then
return t
end
end

return nil
end

local function lastToken ( n )
if cst . isToken ( n ) then
return ( not n . missing and n . kind ~= "eof" ) and n or nil
end
for j = # n , 1 , - 1 do
local t = lastToken ( n [ j ] )
if t then
return t
end
end

return nil
end



local function groupBounds ( n )
local openIdx , closer
for idx , child in ipairs ( n ) do
if cst . isToken ( child ) and not child . missing then
if not openIdx then
local pair = BRACKET_PAIR [ child . kind ]
if pair then
openIdx , closer = idx , pair
end
elseif child . kind == closer then
if idx > openIdx + 1 then
return openIdx , idx
end
return nil
end
end
end

return nil
end



local function breakIfArms ( n )
local function breakBefore ( node )
local tok = node and firstToken ( node )
if tok then
tok . forceBreak = true
end
end

for idx , clause in ipairs ( n . clauses or { } ) do
if idx > 1 then
breakBefore ( clause )
end
breakBefore ( clause . body )
end
if n . elseClause then
breakBefore ( n . elseClause )
breakBefore ( n . elseClause . body )
end
local close = lastToken ( n )
if close and close . kind == "end" then
close . forceBreak = true
end
end



local function markFinalFunctionReturn ( n )
local body = n . body
if not body or body . kind ~= "block" then
return
end
local stats = body . stats
local final = stats [ # stats ]
if not final or final . kind ~= "returnStmt" then
return
end
local first , returnTok = firstToken ( stats [ 1 ] ) , firstToken ( final )
if first and returnTok then
returnTok . finalFunctionReturn = true
returnTok . functionBodyFirstTok = first
end
end



local function breakFunctionBody ( n )
local body = n . body
local first = body and firstToken ( body )
if first then
first . forceBreak = true
end
local close = lastToken ( n )
if close and close . kind == "end" then
close . forceBreak = true
end
end




local function isChainedReceiver ( n )
while n and not cst . isToken ( n ) do
local kind = n . kind
if kind == "call" or kind == "methodCall" or kind == "safeCall" then
return true
end
if kind ~= "dotIndex" and kind ~= "bracketIndex" and kind ~= "safeIndex" and kind ~= "safeBracket" then
return false
end
n = n . obj
end

return false
end






local function markChainStep ( n )
if not isChainedReceiver ( n . obj ) then
return
end
local tok = n . safeObj
if not tok then
for _ , child in ipairs ( n ) do
if cst . isToken ( child ) and child . kind == ":" then
tok = child
break
end
end
end
if tok then
tok . chainStep = true
end
end



local function markFunctionEnd ( n )
local close = lastToken ( n )
if close and close . kind == "end" then
close . blankAfter = true
end
end



local function annotate ( root )
local markStart = false
local walk

walk = function ( n , block , group )
local kind = n . kind
if kind == "ternary" then
for _ , child in ipairs ( n ) do
if cst . isToken ( child ) and ( child . kind == "?" or child . kind == ":" ) then
child . spacedTok = true
child . breakOp = true
end
end
elseif kind == "unop" then


local op = n . op
if op and ( op . kind ~= "not" or op . text == "!" ) then
op . unaryTok = true
end
elseif kind == "binop" then
if n . op and BREAK_OPS [ n . op . kind ] then
n . op . breakOp = true
end
elseif kind == "tunion" or kind == "tintersection" then



for _ , child in ipairs ( n ) do
if cst . isToken ( child ) and ( child . kind == "|" or child . kind == "&" ) then
child . breakOp = true
child . typeOp = true
end
end
elseif kind == "tborrows" or kind == "captureClause" then




local clause = n . mode
if not clause then
for _ , child in ipairs ( n ) do
if cst . isToken ( child ) and child . text == "borrows" then
clause = child
break
end
end
end
if clause then
clause . spacedTok = true
end
elseif kind == "methodCall" then
markChainStep ( n )
elseif kind == "ifStmt" then
breakIfArms ( n )
elseif kind == "funcbody" then
markFinalFunctionReturn ( n )
breakFunctionBody ( n )
elseif kind == "funcStmt" or kind == "localFuncStmt" or kind == "inlineMethod" then
markFunctionEnd ( n )
end

local openIdx , closeIdx = groupBounds ( n )
local inner = group
if openIdx then
local openTok , closeTok = n [ openIdx ] , n [ closeIdx ]
inner = {
kind = kind ,
open = openTok ,
close = closeTok ,
seps = { } ,
elements = { } ,
last = nil ,
parent = group ,
}
openTok . opensGroup = inner
local atElement = true
for idx = openIdx + 1 , closeIdx - 1 do
local child = n [ idx ]
if cst . isToken ( child ) and ( child . kind == "," or child . kind == ";" ) then
inner . seps [ # inner . seps + 1 ] = child
atElement = true
else
local first , final = firstToken ( child ) , lastToken ( child )
if atElement then
if first then
inner . elements [ # inner . elements + 1 ] = { first = first , final = final }
atElement = false
end
elseif final then
inner . elements [ # inner . elements ] . final = final
end
end
end
inner . last = lastToken ( n [ closeIdx - 1 ] )
if kind == "tshape" and inner . last == inner . seps [ # inner . seps ] then
inner . last . formatOmit = true
end




if kind == "tshape" and # ( n . fields or { } ) > 1 then
for _ , field in ipairs ( n . fields or { } ) do
local first = firstToken ( field )
if first then
first . forceBreak = true
end
end
closeTok . forceBreak = true
end
end

local declish = kind == "recordDecl" or kind == "cdefStruct"





local headerPart = { }
for _ , super in ipairs ( n . supertypes or { } ) do
headerPart [ super ] = true
end
if n . whereClause then
headerPart [ n . whereClause ] = true
end





local documented = { }
for _ , entry in ipairs ( n . entries or { } ) do
for _ , application in ipairs ( entry . annotations or { } ) do
documented [ application ] = entry
end
end
for idx , child in ipairs ( n ) do
local childGroup = group
if openIdx and idx > openIdx and idx < closeIdx then
childGroup = inner
end
if cst . isToken ( child ) then
child . blockDepth = block
child . groupRef = childGroup
if child . kind == "end" or child . kind == "until" then
child . forceBreak = true
end
if markStart then
child . startsStat = true
child . forceBreak = true
markStart = false
end
elseif child . kind == "block" then
for _ , stat in ipairs ( child . stats or { } ) do



markStart = stat . kind ~= "emptyStmt"
walk ( stat , block + 1 , childGroup )
markStart = false
local first , last = firstToken ( stat ) , lastToken ( stat )
if first then
first . stmtLastTok = last
end
end
elseif declish and child ~= n . generics and not headerPart [ child ] then
markStart = true
walk ( child , block + 1 , childGroup )
markStart = false
local first , last = firstToken ( child ) , lastToken ( documented [ child ] or child )
if first then
first . stmtLastTok = last
end
elseif kind == "pragmaStmt" and child == n . stat then


markStart = true
walk ( child , block , childGroup )
markStart = false
else
walk ( child , block , childGroup )
end
end
end

for _ , child in ipairs ( root ) do
if cst . isToken ( child ) then
child . blockDepth = 0
elseif child . kind == "block" then
for _ , stat in ipairs ( child . stats or { } ) do
markStart = stat . kind ~= "emptyStmt"
walk ( stat , 0 , nil )
markStart = false
local first , last = firstToken ( stat ) , lastToken ( stat )
if first then
first . stmtLastTok = last
end
end
else
walk ( child , 0 , nil )
end
end
root . eof . blockDepth = 0
end






local function sep ( prev , tok )
if prev . spacedTok or tok . spacedTok then
return " "
end
if prev . unaryTok then
return ""
end

if prev . _shortfnOpen or tok . _shortfnClose then
return ""
end
if prev . kind == "..." and tok . namedVararg then
return ""
end


if prev . typeColon then
return " "
end
if tok . typePostfix then
return ""
end
if tok . generic then
return ""
end
if prev . generic then
if prev . kind == "<" then
return ""
end
if tok . kind == "(" then
return ""
end
if prev . homogeneousPack then
return ""
end
end
if NO_SPACE_AFTER [ prev . kind ] then
return ""
end
local k = tok . kind
if NO_SPACE_BEFORE [ k ] then
return ""
end
if k == "::" then
return prev . kind == "name" and "" or " "
end
if k == "(" or k == "[" then
if k == "[" and prev . propertyCapability then
return " "
end
return CALLEE_KINDS [ prev . kind ] and "" or " "
end
if k == "{" or k == "string" then


if prev . contextualOp then
return " "
end


if prev . constructTarget then
return " "
end
return prev . kind == "name" and "" or " "
end

return " "
end





local function isDocComment ( text )
return text : sub ( 1 , 3 ) == "---" and text : sub ( 1 , 4 ) ~= "----"
end





local function isSafeProse ( text )
if text : sub ( 1 , 1 ) == " " or text : sub ( - 1 ) == " " then
return false
end
if text : find ( "  " ) or text : find ( "[^%S ]" ) then
return false
end

return text : find ( " " ) ~= nil
end

local function breakWordsToFit ( text , firstWidth , restWidth )
if displayWidth ( text ) <= firstWidth or not isSafeProse ( text ) then
return { text }
end

local lines , line = { } , ""
local width = firstWidth
for word in text : gmatch ( "%S+" ) do
if line == "" then
line = word
elseif displayWidth ( line ) + 1 + displayWidth ( word ) <= width then
line = line .. " " .. word
else
lines [ # lines + 1 ] = line
line = word
width = restWidth
end
end
if line ~= "" then
lines [ # lines + 1 ] = line
end
if # lines == 0 then
lines [ 1 ] = ""
end

return lines
end





local MARKDOWN_BLOCK_STARTS = { "^[-*+] " , "^%d+[.)] " , "^[>#|]" , "^=+%s*$" , "^%-%-+%s*$" , }

local function opensMarkdownBlock ( text )
for _ , pattern in ipairs ( MARKDOWN_BLOCK_STARTS ) do
if text : match ( pattern ) then
return true
end
end

return false
end







local function refillParagraph ( texts , width )
local fits = true
for _ , text in ipairs ( texts ) do
if displayWidth ( text ) > width then
fits = false
end
if text : sub ( 1 , 1 ) == " " or text : sub ( - 1 ) == " " or text : find ( "  " ) then
return nil
end
if text : find ( "[^%S ]" ) or opensMarkdownBlock ( text ) then
return nil
end
end
if fits then
return nil
end

return breakWordsToFit ( table . concat ( texts , " " ) , width , width )
end



local function parseDoc ( rawLines )
local blocks = { }
local fenced = nil
for _ , raw in ipairs ( rawLines ) do
local body = docSyntax . comment : match ( raw ) or raw
local wasFenced = fenced ~= nil
local marker
fenced , marker = docSyntax . fenceState ( body , fenced )
local annotation = not wasFenced and not marker and docSyntax . tag : match ( body ) ~= nil
if wasFenced or marker or ( not fenced and docSyntax . codeIndented : match ( body ) ) then
blocks [ # blocks + 1 ] = { kind = "verbatim" , text = body }
elseif docSyntax . blank : match ( body ) then
blocks [ # blocks + 1 ] = { kind = "blank" }
elseif annotation then
blocks [ # blocks + 1 ] = { kind = "annot" , text = body }
else
blocks [ # blocks + 1 ] = { kind = "text" , text = body }
end
end

while blocks [ 1 ] and blocks [ 1 ] . kind == "blank" do
table . remove ( blocks , 1 )
end
while blocks [ # blocks ] and blocks [ # blocks ] . kind == "blank" do
table . remove ( blocks )
end

return blocks
end

local function renderComment ( rawLines , indentStr , marker )
local prefix = indentStr .. marker
local width = DOC_WIDTH - displayWidth ( prefix ) - 1
if width < 24 then
width = 24
end
local out = { }
local blocks = parseDoc ( rawLines )
local index = 1
while index <= # blocks do
local block = blocks [ index ]
if block . kind == "blank" then
out [ # out + 1 ] = prefix
index = index + 1
elseif block . kind == "verbatim" then
out [ # out + 1 ] = ( prefix .. " " .. block . text ) : gsub ( "%s+$" , "" )
index = index + 1
elseif block . kind == "annot" then
local lines = breakWordsToFit ( block . text , width , width - 4 )
for j , line in ipairs ( lines ) do
local pad = j == 1 and " " or "     "
out [ # out + 1 ] = ( prefix .. pad .. line ) : gsub ( "%s+$" , "" )
end
index = index + 1
else



local texts = { }
while blocks [ index ] and blocks [ index ] . kind == "text" do
texts [ # texts + 1 ] = blocks [ index ] . text
index = index + 1
end
local lines = refillParagraph ( texts , width )
if not lines then
lines = { }
for _ , text in ipairs ( texts ) do
for _ , line in ipairs ( breakWordsToFit ( text , width , width ) ) do
lines [ # lines + 1 ] = line
end
end
end
for _ , line in ipairs ( lines ) do
out [ # out + 1 ] = ( prefix .. " " .. line ) : gsub ( "%s+$" , "" )
end
end
end
if # out == 0 then
out [ 1 ] = prefix
end

return out
end

local function renderDoc ( rawLines , indentStr )
return renderComment ( rawLines , indentStr , "---" )
end

local function isPlainComment ( text )
return text : sub ( 1 , 2 ) == "--" and text : sub ( 3 , 3 ) ~= "-" and not text : match ( "^%-%-%[=*%[" )
end







local function collectItems ( tokens )
local items = { }
local pending = 0
local function push ( item )
item . nl = pending
pending = 0
items [ # items + 1 ] = item
end

for _ , tok in ipairs ( tokens ) do
for triviaIndex = 1 , tok . triviaCount do
local tr = lexer . triviaRecord ( tok , triviaIndex )
if tr . kind == "whitespace" then
local _ , n = tr . text : gsub ( "\n" , "" )
pending = pending + n
elseif tr . kind == "comment" then
local prev = items [ # items ]
if prev and prev . kind == "doc" and pending == 1 and isDocComment ( tr . text ) then
prev . rawLines [ # prev . rawLines + 1 ] = tr . text
pending = 0
elseif prev and prev . kind == "plain" and pending == 1 and isPlainComment ( tr . text ) then
prev . rawLines [ # prev . rawLines + 1 ] = tr . text
pending = 0
elseif isDocComment ( tr . text ) and ( pending > 0 or # items == 0 ) then
push ( { kind = "doc" , rawLines = { tr . text } } )
elseif isPlainComment ( tr . text ) and ( pending > 0 or # items == 0 ) then
push ( { kind = "plain" , rawLines = { tr . text } } )
else
push ( { kind = "comment" , text = tr . text } )
end
else
local text = tr . text
local _ , n = text : gsub ( "\n" , "" )
push ( { kind = "raw" , text = ( text : gsub ( "\n+$" , "" ) ) } )
pending = pending + n
end
end
if tok . kind ~= "eof" and not tok . missing and not tok . formatOmit then
push ( { kind = "token" , token = tok } )
end
end

return items
end



local function markDocumented ( items )
for idx , item in ipairs ( items ) do
if item . kind == "doc" then
local next_ = items [ idx + 1 ]
if next_ and next_ . kind == "token" and next_ . token . stmtLastTok then
next_ . token . stmtLastTok . blankAfter = true
end
end
end
end

local function buildLines ( items )
local lines = { }
local cur = nil
for _ , item in ipairs ( items ) do
local forced = item . kind == "token" and item . token . forceBreak
local standalone = item . kind == "doc" or item . kind == "plain" or item . kind == "raw" or (
item . kind == "comment" and item . nl > 0
)
local previous = cur and cur . items [ # cur . items ]
local afterComment = item . nl > 0 and previous and (
previous . kind == "comment" or previous . kind == "doc" or previous . kind == "plain" or previous . kind == "raw"
)
if not cur or item . nl >= 2 or forced or standalone or afterComment then
cur = { items = { } , indent = 0 , blankBefore = item . nl >= 2 and # lines > 0 }
lines [ # lines + 1 ] = cur
end
cur . items [ # cur . items + 1 ] = item
end

return lines
end

local function lineFirstToken ( line )
for _ , item in ipairs ( line . items ) do
if item . kind == "token" and not item . token . formatOmit then
return item . token
end
end

return nil
end

local function renderItems ( items )
local parts , prevTok = { } , nil
for _ , item in ipairs ( items ) do
if item . kind == "token" then
if prevTok then
parts [ # parts + 1 ] = sep ( prevTok , item . token )
elseif # parts > 0 then
parts [ # parts + 1 ] = " "
end
parts [ # parts + 1 ] = item . token . text
prevTok = item . token
elseif item . kind == "comment" or item . kind == "raw" then
if # parts > 0 then
parts [ # parts + 1 ] = " "
end
parts [ # parts + 1 ] = item . text
prevTok = nil
end
end

return table . concat ( parts )
end




local function computeIndents ( lines )
for idx , line in ipairs ( lines ) do
for _ , item in ipairs ( line . items ) do
if item . kind == "token" then
item . token . lineIdx = idx
end
end
end
for _ , line in ipairs ( lines ) do
for _ , item in ipairs ( line . items ) do
if item . kind == "token" and item . token . opensGroup then
local g = item . token . opensGroup
local firstInner = nil


for _ , other in ipairs ( lines ) do
for _ , it2 in ipairs ( other . items ) do
if it2 . kind == "token" and it2 . token . groupRef == g then
firstInner = it2 . token
break
end
end
if firstInner then
break
end
end
g . broken = firstInner ~= nil and firstInner . lineIdx > item . token . lineIdx
if g . broken and g . kind == "tshape" then
g . close . forceBreak = true
end
end
end
end
for idx , line in ipairs ( lines ) do
local tok = lineFirstToken ( line )
if tok then
local depth = tok . blockDepth or 0
local hang = 0
local g = tok . groupRef
while g do
if g . broken then
hang = hang + 1
end
g = g . parent
end
depth = depth + hang



if ( hang == 0 or tok . chainStep ) and not tok . startsStat and not CLOSERS [ tok . kind ] then
depth = depth + 1
end
line . indent = depth
else





local nextIndent = 0
for j = idx + 1 , # lines do
local t = lineFirstToken ( lines [ j ] )
if t then
nextIndent = lines [ j ] . indent + ( CLOSERS [ t . kind ] and 1 or 0 )
break
end
end
line . indent = nextIndent
end
end
end

local function lineWidth ( line )
return line . indent * displayWidth ( INDENT ) + displayWidth ( renderItems ( line . items ) )
end

local function indexOfToken ( items , tok )
for idx , item in ipairs ( items ) do
if item . kind == "token" and item . token == tok then
return idx
end
end

return nil
end








local function breakPoints ( line , accepts )
local points , open = { } , { }
for idx , item in ipairs ( line . items ) do
if item . kind == "token" then
local tok = item . token
if open [ # open ] == tok then
open [ # open ] = nil
elseif tok . opensGroup and BRACKET_PAIR [ tok . kind ] then
open [ # open + 1 ] = tok . opensGroup . close
elseif # open == 0 and idx > 1 and accepts ( tok ) then
points [ # points + 1 ] = idx
end
end
end

return points
end






local function splitLine ( line )
local out = { }
local function emit ( items , indent )
if # items > 0 then
out [ # out + 1 ] = { items = items , indent = indent }
end
end

local function slice ( from , to )
local part = { }
for j = from , to do
part [ # part + 1 ] = line . items [ j ]
end

return part
end


local function breakBefore ( points )
local start = 1
for _ , at in ipairs ( points ) do
emit ( slice ( start , at - 1 ) , start == 1 and line . indent or line . indent + 1 )
start = at
end
emit ( slice ( start , # line . items ) , line . indent + 1 )
if # out > 1 then
return out
end

return nil
end




local ops = breakPoints ( line , function ( tok )
return tok . breakOp
end )
local chain = breakPoints ( line , function ( tok )
return tok . chainStep
end )
if # chain > 0 then
return breakBefore ( # ops > 0 and ops or chain )
end





local typeOps = breakPoints ( line , function ( tok )
return tok . typeOp
end )
if # typeOps > 0 then
return breakBefore ( typeOps )
end

local openIdx , closeIdx , group





local genericOpen , genericClose , generic
for idx , item in ipairs ( line . items ) do
if item . kind == "token" and item . token . opensGroup then
local g = item . token . opensGroup
local cIdx = indexOfToken ( line . items , g . close )
if cIdx and cIdx > idx + 1 then
local nextItem = line . items [ idx + 1 ]
local wrapsTable = item . token . kind == "("
and nextItem
and nextItem . kind == "token"
and nextItem . token . kind == "{"
and nextItem . token . opensGroup
and indexOfToken (
line . items ,
nextItem . token . opensGroup . close
) == cIdx - 1
if wrapsTable then

elseif item . token . kind == "<" then
genericOpen , genericClose , generic = genericOpen or idx , genericClose or cIdx , generic or g
else
openIdx , closeIdx , group = idx , cIdx , g
break
end
end
end
end
if not group and generic then
openIdx , closeIdx , group = genericOpen , genericClose , generic
end

if group then
emit ( slice ( 1 , openIdx ) , line . indent )
local isSep = { }
for _ , s in ipairs ( group . seps ) do
isSep [ s ] = true
end
local start = openIdx + 1
for j = openIdx + 1 , closeIdx - 1 do
local item = line . items [ j ]
local sepHere = item . kind == "token" and isSep [ item . token ]
local trailing = line . items [ j + 1 ]

if sepHere and trailing and trailing . kind == "comment" then
emit ( slice ( start , j + 1 ) , line . indent + 1 )
start = j + 2
elseif sepHere then
emit ( slice ( start , j ) , line . indent + 1 )
start = j + 1
end
end
if start <= closeIdx - 1 then
emit ( slice ( start , closeIdx - 1 ) , line . indent + 1 )
end
emit ( slice ( closeIdx , # line . items ) , line . indent )
if # out > 1 then
return out
end
return nil
end


if # ops == 0 then
return nil
end
local header = lineFirstToken ( line )
if header and ( header . kind == "if" or header . kind == "elseif" ) then
for idx , item in ipairs ( line . items ) do
if item . kind == "token" and item . token . kind == "then" then
ops [ # ops + 1 ] = idx
break
end
end
end

return breakBefore ( ops )
end




local function splitForcedLines ( lines )
local out , changed = { } , false



local function emit ( line , from , to , first )
if from <= to then
local items = { }
for idx = from , to do
items [ # items + 1 ] = line . items [ idx ]
end
out [ # out + 1 ] = { items = items , indent = line . indent , blankBefore = first and line . blankBefore or false , }
end
end

for _ , line in ipairs ( lines ) do
local start = 1
for idx , item in ipairs ( line . items ) do
if idx > start and item . kind == "token" and item . token . forceBreak then
emit ( line , start , idx - 1 , start == 1 )
start = idx
changed = true
end
end
emit ( line , start , # line . items , start == 1 )
end

return changed and out or nil
end













local function spreadListGroups ( lines , width )
local changed = false
local function mark ( tok )
if tok and not tok . forceBreak then
tok . forceBreak = true
changed = true
end
end



local function prefixWidth ( line , through )
local part = { }
for idx = 1 , through do
part [ # part + 1 ] = line . items [ idx ]
end

return line . indent * displayWidth ( INDENT ) + displayWidth ( renderItems ( part ) )
end

for lineIdx , line in ipairs ( lines ) do
for _ , item in ipairs ( line . items ) do
local g = item . kind == "token" and item . token . opensGroup or nil
local mode = g and SPREADING_GROUPS [ g . kind ] or nil
if mode and # g . elements > 0 then
local tail = g . elements [ # g . elements ]
local block = tail . final ~= nil and BLOCK_CLOSERS [ tail . final . kind ] or false
if g . open . lineIdx ~= g . close . lineIdx then
local opening = lines [ g . open . lineIdx ]
local hugs = mode == "hug"
and block
and tail . first . lineIdx == g . open . lineIdx
and opening ~= nil
and lineWidth (
opening
) <= width
if not hugs then
for _ , element in ipairs ( g . elements ) do
mark ( element . first )
end
mark ( g . close )
end
elseif mode == "hug" and block and lineWidth ( line ) > width then





local at = indexOfToken ( line . items , tail . first )
local body = tail . first . opensGroup
if at and body and prefixWidth ( line , at ) <= width then
for _ , element in ipairs ( body . elements ) do
mark ( element . first )
end
mark ( body . close )
end
end
end
end
end

return changed
end

local function breakLines ( lines , width )
for _ = 1 , MAX_PASSES do
computeIndents ( lines )
local changed = spreadListGroups ( lines , width )
local forced = splitForcedLines ( lines )
if forced then
lines = forced
changed = true
else
local next_ = { }
for _ , line in ipairs ( lines ) do
local pieces = nil
if lineWidth ( line ) > width and not line . noBreak then
pieces = splitLine ( line )
end
if pieces then
changed = true
for j , piece in ipairs ( pieces ) do
piece . blankBefore = j == 1 and line . blankBefore or false
next_ [ # next_ + 1 ] = piece
end
else
line . noBreak = lineWidth ( line ) > width
next_ [ # next_ + 1 ] = line
end
end
lines = next_
end
if not changed then
break
end
end
computeIndents ( lines )
for _ , line in ipairs ( lines ) do
local tok = lineFirstToken ( line )
local first = tok and tok . functionBodyFirstTok
if tok and tok . finalFunctionReturn and first and tok . lineIdx - first . lineIdx >= 4 then
line . blankBefore = true
end
end

return lines
end





local function render ( lines )
local out = { }
local prevIndent = 0
local function push ( text )
out [ # out + 1 ] = text
end

for idx , line in ipairs ( lines ) do
local indentStr = INDENT : rep ( line . indent )
local flowed = line . items [ 1 ]
local doc = flowed and flowed . kind == "doc" and flowed or nil
local plain = flowed and flowed . kind == "plain" and flowed or nil
local wantBlank = line . blankBefore


if doc and # out > 0 and out [ # out ] ~= "" and line . indent <= prevIndent then
wantBlank = true
end
if wantBlank and # out > 0 then
push ( "" )
end
if doc or plain then
local commentLines = doc and renderDoc (
doc . rawLines ,
indentStr
) or renderComment ( plain . rawLines , indentStr , "--" )
for _ , commentLine in ipairs ( commentLines ) do
push ( commentLine )
end
local rest = { }
for j = 2 , # line . items do
rest [ # rest + 1 ] = line . items [ j ]
end
if # rest > 0 then
push ( ( ( indentStr .. renderItems ( rest ) ) : gsub ( "%s+$" , "" ) ) )
end
else
local body = renderItems ( line . items )
if body ~= "" then
push ( ( ( indentStr .. body ) : gsub ( "%s+$" , "" ) ) )
end
end


local last = line . items [ # line . items ]
local next_ = lines [ idx + 1 ]
if last and last . kind == "token" and last . token . blankAfter and next_ and next_ . indent >= line . indent then
push ( "" )
end
prevIndent = line . indent
end

local text = table . concat ( out , "\n" )
text = text : gsub ( "\n\n\n+" , "\n\n" )
text = text : gsub ( "^\n+" , "" ) : gsub ( "%s+$" , "" )
if # text > 0 then
text = text .. "\n"
end

return text
end





local function fingerprintTokens ( tokens , omitMarked )
local parts = { }
for _ , tok in ipairs ( tokens ) do
if tok . kind ~= "eof" and not ( omitMarked and tok . formatOmit ) then
if tok . kind == ">>" then




parts [ # parts + 1 ] = ">\1>"
parts [ # parts + 1 ] = ">\1>"
else
parts [ # parts + 1 ] = tok . kind .. "\1" .. tok . text
end
end
end

return table . concat ( parts , "\2" )
end

local function canonicalizeSingleValueAnnotations ( result , opts )
local singleValues = { }
local localDefinitions = { }
local registry = opts and opts . annotations
if registry then
for name , definition in pairs ( registry . byname or { } ) do
if definition . singleValue then
singleValues [ name ] = definition . singleValue
end
end
end

local applications = { }
local function walk ( node )
if not node or cst . isToken ( node ) then
return
end
if node . kind == "pragmaStmt" or node . kind == "annotationApply" then
applications [ # applications + 1 ] = node
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
walk ( child )
end
end
end

walk ( result . root )



for _ , application in ipairs ( applications ) do
if application . kind == "pragmaStmt" and application . name . text == "annotation" then
local target = application . stat
while target and target . kind == "pragmaStmt" do
target = target . stat
end
if target and target . kind == "recordDecl" then
local marked = nil
local duplicate = false
for _ , entry in ipairs ( target . entries or { } ) do
for _ , attached in ipairs ( entry . annotations or { } ) do
if attached . name . text == "annotationValue" then
if marked then
duplicate = true
else
marked = entry . name . text
end
end
end
end
if marked and not duplicate then
singleValues [ target . name . text ] = marked
localDefinitions [ target . name . text ] = true
end
end
end
end

local function triviaIsWhitespace ( tok )
for index = 1 , tok and tok . triviaCount or 0 do
if lexer . triviaKind ( tok , index ) ~= "whitespace" then
return false
end
end

return true
end

for _ , application in ipairs ( applications ) do
local name = application . name . text
local member = singleValues [ name ]
if opts and opts . resolveAnnotation and not localDefinitions [ name ] then
local definition = opts . resolveAnnotation ( name )
if definition then
member = definition . singleValue
end
end
local args = application . annotationArgs or { }
local arg = # args == 1 and args [ 1 ] or nil
if member and arg and arg . name and arg . name . text == member and triviaIsWhitespace (
arg . name
) and triviaIsWhitespace ( arg . eq ) then
arg . name . formatOmit = true
arg . eq . formatOmit = true
end
end
end










local function parenthesizeMethodCalls ( result , opts )
if opts and opts . methodParens == false then
return
end
local before , after = { } , { }
local function walk ( node )
if not node or cst . isToken ( node ) then
return
end
if node . kind == "methodCall" then
local args = node . args
if args and not args . exprs and ( args . table or args . str ) then
local sugar = args . table or args . str
local first , last = cst . firstToken ( sugar ) , cst . lastToken ( sugar )
if first and last then
local open = {
kind = "(" ,
text = "(" ,
offset = first . offset ,
line = first . line ,
col = first . col ,
trivia = first . trivia ,
triviaFirst = first . triviaFirst ,
triviaCount = first . triviaCount
}
local close = {
kind = ")" ,
text = ")" ,
offset = last . offset ,
line = last . line ,
col = last . col ,
trivia = last . trivia ,
triviaFirst = 1 ,
triviaCount = 0
}
first . triviaCount = 0
args [ 1 ] , args [ 2 ] , args [ 3 ] = open , sugar , close
before [ first ] , after [ last ] = open , close
end
end
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
walk ( child )
end
end
end

walk ( result . root )
if not next ( before ) then
return
end
local tokens = { }
for _ , tok in ipairs ( result . tokens ) do
if before [ tok ] then
tokens [ # tokens + 1 ] = before [ tok ]
end
tokens [ # tokens + 1 ] = tok
if after [ tok ] then
tokens [ # tokens + 1 ] = after [ tok ]
end
end
result . tokens = tokens
end
















fmt.Formatter = {} fmt.Formatter.__index = fmt.Formatter








function fmt . new ( opts )
return setmetatable({ width =
( opts and opts . width ) or WIDTH ,  methodParens =
opts and opts . methodParens ,  annotations =
opts and opts . annotations ,  resolveAnnotation =
opts and opts . resolveAnnotation }, fmt.Formatter)

end



function fmt . Formatter : format ( source , filename )
local result = parser . parse ( source , filename )
if # result . errors > 0 then
return source , result . errors
end
if result . root . formatDisabled then
return source , { }
end
canonicalizeSingleValueAnnotations ( result , self )
parenthesizeMethodCalls ( result , self )
annotate ( result . root )
local items = collectItems ( result . tokens )
markDocumented ( items )
local lines = breakLines ( buildLines ( items ) , self . width )
local text = render ( lines )




local outputTokens = lexer . lex ( text )
if fingerprintTokens ( outputTokens ) ~= fingerprintTokens ( result . tokens , true ) then
return source , {
{
code = "NUPP4001" ,
msg = "internal error: formatting would change the token stream; "
.. "the file was left unchanged (please report this input)" ,
filename = filename ,
line = 1 ,
col = 1 ,
offset = 1 ,
length = 1 ,
}
}
end

return text , { }
end




function fmt . format ( source , filename , opts )
return fmt . new ( opts ) : format ( source , filename )
end

return fmt
