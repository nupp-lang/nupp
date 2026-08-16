_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local strings = { }
local function trim ( text )
return ( text : gsub ( "^%s+" , "" ) : gsub ( "%s+$" , "" ) )
end



local function markdownEscape ( text )
return text : gsub ( "([\\`*_%[%]<>])" , "\\%1" )
end




local function markdownCell ( text )
return ( text : gsub ( "([\\|])" , "\\%1" ) : gsub ( "\n" , " " ) )
end

local function htmlEscape ( text )
return tostring ( text or "" )
: gsub ( "&" , "&amp;" )
: gsub ( "<" , "&lt;" )
: gsub ( ">" , "&gt;" )
: gsub ( '"' , "&quot;" )
: gsub ( "'" , "&#39;" )
end

local function headingId ( text )
local id = text : lower ( )
: gsub ( "`" , "" )
: gsub ( "<[^>]+>" , "" )
: gsub ( "[^%w%s_-]" , "" )
: gsub ( "[%s_]+" , "-" )
: gsub ( "%-+" , "-" )
: gsub ( "^%-" , "" )
: gsub ( "%-$" , "" )

return id ~= "" and id or "section"
end

local function summaryText ( text )
text = tostring ( text or "" ) : gsub ( "```[%s%S]-```" , " " ) : gsub (



"%[%]%(([^%)]+)%)" ,
"%1"
)
: gsub ( "%[([^%]]+)%]%([^%)]+%)" , "%1" )
: gsub ( "`([^`]*)`" , "%1" )
: gsub ( "[*_~#]" , "" )
: gsub ( "%s+" , " " )
: gsub ( "^%s+" , "" )
: gsub ( "%s+$" , "" )
local sentence = text : match ( "^(.-[.!?])%s" )
text = sentence or text
if # text > 120 then
text = text : sub ( 1 , 117 ) : match ( "^(.*)%s+%S*$" ) or text : sub ( 1 , 117 )
text = text .. "..."
end

return text ~= "" and text or "—"
end

local function escapeJs ( text )
return (
tostring ( text or "" ) : gsub ( "\\" , "\\\\" ) : gsub ( '"' , '\\"' ) : gsub ( "\r" , "\\r" ) : gsub ( "\n" , "\\n" ) : gsub ( "</" , "<\\/" )
)
end

strings . trim = trim
strings . markdownEscape = markdownEscape
strings . markdownCell = markdownCell
strings . htmlEscape = htmlEscape
strings . headingId = headingId
strings . summaryText = summaryText
strings . escapeJs = escapeJs

return strings
