_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.cli.internal.terminal"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local colorEnabled;__nuppExports["colorEnabled"]=function(...) return colorEnabled(...) end;local columns;__nuppExports["columns"]=function(...) return columns(...) end;local forSeverity;__nuppExports["forSeverity"]=function(...) return forSeverity(...) end;local isTerminal;__nuppExports["isTerminal"]=function(...) return isTerminal(...) end;local setColorMode;__nuppExports["setColorMode"]=function(...) return setColorMode(...) end;local style;__nuppExports["style"]=function(...) return style(...) end;local withColorMode;__nuppExports["withColorMode"]=function(...) return withColorMode(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.cli.internal.terminal\0runtime\0001") };





local Style = {} Style.__index = Style ;_G.nupp.__reflect.link(Style,__nuppT1[1],{ }) ;__nuppExports["Style"]=Style























local CODES = {
strong = "1" ,
faint = "2" ,
red = "1;31" ,
yellow = "1;33" ,
green = "1;32" ,
cyan = "1;36" ,
blue = "1;34" ,
magenta = "1;35" ,
white = "1;37" ,
gray = "1;90" ,
heading = "1;35" ,
}
local RESET = "\27[0m"

local terminalHost = require ( "nupp.cli.internal.terminalhost" )

local function plain ( text ) 
return text
end

local function styler ( code ) 
local prefix = "\27[" .. code .. "m"
return function ( text ) 
return prefix .. text .. "\27[0m"
end
end

local SEVERITY_COLOR = { error = "red" , warning = "yellow" , note = "cyan" , help = "green" }
local plainSeverity = { }
for name in pairs ( SEVERITY_COLOR ) do
plainSeverity [ name ] = plain
end

local PLAIN = _G.setmetatable({ strong =
plain ,  faint =
plain ,  heading =
plain ,  red =
plain ,  yellow =
plain ,  green =
plain ,  cyan =
plain ,  blue =
plain ,  magenta =
plain ,  white =
plain ,  gray =
plain ,  path =
plain ,  gutter =
plain ,  severity =
plainSeverity }, Style)


local COLORED = _G.setmetatable({ strong =
styler ( CODES . strong ) ,  faint =
styler ( CODES . faint ) ,  heading =
styler ( CODES . heading ) ,  red =
styler ( CODES . red ) ,  yellow =
styler ( CODES . yellow ) ,  green =
styler ( CODES . green ) ,  cyan =
styler ( CODES . cyan ) ,  blue =
styler ( CODES . blue ) ,  magenta =
styler ( CODES . magenta ) ,  white =
styler ( CODES . white ) ,  gray =
styler ( CODES . gray ) ,  path =
styler ( CODES . strong ) ,  gutter =
styler ( CODES . blue ) ,  severity =
{ } }, Style)

for name , color in pairs ( SEVERITY_COLOR ) do
COLORED . severity [ name ] = styler ( CODES [ color ] )
end

local windows = package . config : sub ( 1 , 1 ) == "\\"

local function requested ( name ) 
local value = os . getenv ( name )
return value ~= nil and value ~= "" and value ~= "0"
end

local function capable ( fd ) 
if os . getenv ( "TERM" ) == "dumb" then
return false
end
if windows
and not ( requested ( "WT_SESSION" ) or requested ( "ANSICON" ) or requested ( "ConEmuANSI" ) or os . getenv ( "TERM" ) )
then
return false
end

return terminalHost . isTerminal ( fd )
end

local mode = "auto"
local decided = { }
local terminals = { }
local DESCRIPTOR = { [ io . stdin ] = 0 , [ io . stdout ] = 1 , [ io . stderr ] = 2 }


setColorMode=function ( wanted ) 
if wanted ~= mode then
mode = wanted
decided = { }
end
end ;__nuppExports["setColorMode"]=setColorMode


withColorMode=function ( wanted , body ) 
local before = mode
setColorMode ( wanted )
local ok , problem = pcall ( body )
setColorMode ( before )
if not ok then
error ( problem , 0 )
end
end ;__nuppExports["withColorMode"]=withColorMode


colorEnabled=function ( stream ) 
local known = decided [ stream ]
if known ~= nil then
return known
end
local answer
if mode == "always" then
answer = true
elseif mode == "never" then
answer = false
elseif requested ( "NO_COLOR" ) then
answer = false
elseif requested ( "CLICOLOR_FORCE" ) then
answer = true
else
answer = capable ( DESCRIPTOR [ stream ] or 1 )
end
decided [ stream ] = answer

return answer
end ;__nuppExports["colorEnabled"]=colorEnabled


isTerminal=function ( stream ) 
local known = terminals [ stream ]
if known == nil then
known = terminalHost . isTerminal ( DESCRIPTOR [ stream ] or 1 )
terminals [ stream ] = known
end

return known
end ;__nuppExports["isTerminal"]=isTerminal






columns=function ( stream ) 
local measured = terminalHost . columns ( DESCRIPTOR [ stream ] or 1 )
if measured ~= nil then
return measured
end
local declared = tonumber ( os . getenv ( "COLUMNS" ) or "" )

return declared ~= nil and declared > 0 and math . floor ( declared ) or nil
end ;__nuppExports["columns"]=columns


style=function ( stream ) 
return colorEnabled ( stream ) and COLORED or PLAIN
end ;__nuppExports["style"]=style


forSeverity=function ( styles , name ) 
return styles . severity [ name or "error" ] or styles . severity . error or PLAIN . strong
end ;__nuppExports["forSeverity"]=forSeverity
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Style]="nupp.cli.internal.terminal\0Style"; end);if not __nuppOk then package.loaded["nupp.cli.internal.terminal"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.cli.internal.terminal"]=__nuppExports;return __nuppExports