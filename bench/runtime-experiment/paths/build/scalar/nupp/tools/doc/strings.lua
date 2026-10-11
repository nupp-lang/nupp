_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()









local strings = __nuppNew(0,7)

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
: gsub ( "\"" , "&quot;" )
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

return text
end

local function escapeJs ( text ) 
return (
tostring ( text or "" ) : gsub ( "\\" , "\\\\" ) : gsub ( "\"" , "\\\"" ) : gsub ( "\13" , "\\r" ) : gsub ( "\n" , "\\n" ) : gsub ( "</" , "<\\/" )
)
end

strings . trim = trim
strings . markdownEscape = markdownEscape
strings . markdownCell = markdownCell
strings . htmlEscape = htmlEscape
strings . headingId = headingId
strings . summaryText = summaryText
strings . escapeJs = escapeJs

local __nuppExportValue= strings ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.strings"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.strings"]=__nuppExports;return __nuppExports