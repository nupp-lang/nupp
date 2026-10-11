_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



























local syntaxstyle = require ( "nupp.tools.syntaxstyle" )

local terminalhighlight = { }











local CODES

= {
muted = "90" ,
comment = "90" ,
keyword = "35" ,
meta = "95" ,
type = "36" ,
[ "function" ] = "94" ,
string = "32" ,
number = "33" ,
boolean = "33" ,
warning = "33" ,
error = "31" ,
}

local RESET = "\27[0m"

local function styler ( code ) 
local prefix = "\27[" .. code .. "m"
return function ( text ) 
return prefix .. text .. "\27[0m"
end
end

local COLORED = { }
for name , code in pairs ( CODES ) do
COLORED [ name ] = styler ( code )
end

local EMPTY = { }






function terminalhighlight . palette ( colored ) 
return colored and COLORED or EMPTY
end









function terminalhighlight . paint ( palette , style , text ) 
local paint = palette [ style ]


if paint == nil or text == "" then
return text
end

return paint ( text )
end





















function terminalhighlight . rows ( source ) 
local rows = { { } }

local function append ( text , style ) 
local start = 1
while true do
local finish = text : find ( "\n" , start , true )
local piece = finish and text : sub ( start , finish - 1 ) or text : sub ( start )
if piece ~= "" then
local row = rows [ # rows ]
row [ # row + 1 ] = { text = piece , style = style }
end
if not finish then
do break end
end
rows [ # rows + 1 ] = { }
start = finish + 1
end
end

local spans = syntaxstyle . spans ( source , "bytecode-listing.nupp" )
if spans == nil then
return { }
end
for _ , span in ipairs ( spans ) do
append ( span . text , span . style )
end

return rows
end














function terminalhighlight . paintRow (
row ,
text ,
palette ,
column ,
marker
) 
local measure = require ( "nupp.tools.fmt.displaywidth" )
if row == nil then
local clipped = measure . clip ( text , column )
return clipped == text and text or ( measure . clip ( text , column - # marker ) .. marker )
end
local out = { }
local remaining = column
for _ , span in ipairs ( row ) do
local wide = measure . displayWidth ( span . text )
if wide <= remaining then
out [ # out + 1 ] = terminalhighlight . paint ( palette , span . style or "" , span . text )
remaining = remaining - wide
else
local kept = measure . clip ( span . text , remaining - # marker )
out [ # out + 1 ] = terminalhighlight . paint ( palette , span . style or "" , kept )
out [ # out + 1 ] = marker

return table . concat ( out )
end
end

return table . concat ( out )
end







local function hint ( text , palette ) 
local paint = terminalhighlight . paint
local out = { }
local cursor = 1
while true do
local opens , closes = text : find ( "\"[^\"]*\"" , cursor )
if opens == nil then
do break end
end
out [ # out + 1 ] = paint ( palette , "comment" , text : sub ( cursor , ( opens ) - 1 ) )
out [ # out + 1 ] = paint ( palette , "string" , text : sub ( opens , closes ) )
cursor = ( closes ) + 1
end
out [ # out + 1 ] = paint ( palette , "comment" , text : sub ( cursor ) )

return table . concat ( out )
end













function terminalhighlight . bytecode ( text , palette ) 
local paint = terminalhighlight . paint
local body , comment = text : match ( "^([^;]*)(;.*)$" )
if body == nil then
return paint ( palette , "muted" , text )
end

return paint ( palette , "muted" , body ) .. hint ( comment , palette )
end

local __nuppExportValue= terminalhighlight ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.terminalhighlight"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.terminalhighlight"]=__nuppExports;return __nuppExports