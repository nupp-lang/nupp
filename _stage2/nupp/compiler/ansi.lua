_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);





















local ansi = { }



ansi.Style = {} ansi.Style.__index = ansi.Style





















local SGR = { strong = "1" , faint = "2" , red = "1;31" , yellow = "1;33" , cyan = "1;36" , green = "1;32" , blue = "1;34" , }

local RESET = "\27[0m"



local function plain ( text )
return text
end



local function styler ( code )
local prefix = "\27[" .. code .. "m"
return function ( text )
return prefix .. text .. RESET
end
end




local SEVERITY_COLOUR = { error = "red" , warning = "yellow" , note = "cyan" , help = "green" , }

local PLAIN_SEVERITY = { }
for name in pairs ( SEVERITY_COLOUR ) do
PLAIN_SEVERITY [ name ] = plain
end

local PLAIN = setmetatable({ strong =
plain ,  faint =
plain ,  path =
plain ,  gutter =
plain ,  severity =
PLAIN_SEVERITY }, ansi.Style)


local COLOURED = setmetatable({ strong =
styler ( SGR . strong ) ,  faint =
styler ( SGR . faint ) ,  path =
styler ( SGR . strong ) ,  gutter =
styler ( SGR . blue ) ,  severity =
{ } }, ansi.Style)

for name , colour in pairs ( SEVERITY_COLOUR ) do
COLOURED . severity [ name ] = styler ( SGR [ colour ] )
end

local windows = package . config : sub ( 1 , 1 ) == "\\"




local function requested ( name )
local value = os . getenv ( name )
return value ~= nil and value ~= "" and value ~= "0"
end







local function isatty ( fd )
local loaded , ffi = pcall ( require , "ffi" )
if not loaded then
return false
end



pcall ( ffi . cdef , "int isatty(int);" )
local ok , result = pcall ( function ( )
return ffi . C . isatty ( fd )
end )
if ok then
return result ~= 0
end

pcall ( ffi . cdef , "int _isatty(int);" )
local retried , retriedResult = pcall ( function ( )
return ffi . C . _isatty ( fd )
end )

return retried and retriedResult ~= 0
end





local function capable ( fd )
if os . getenv ( "TERM" ) == "dumb" then
return false
end
if windows and not (
requested ( "WT_SESSION" ) or requested ( "ANSICON" ) or requested ( "ConEmuANSI" ) or os . getenv ( "TERM" )
) then
return false
end

return isatty ( fd )
end


local mode = "auto"



local decided = { }



local DESCRIPTOR = { [ io . stdin ] = 0 , [ io . stdout ] = 1 , [ io . stderr ] = 2 }




function ansi . setMode ( wanted )
if wanted ~= mode then
mode = wanted
decided = { }
end
end





function ansi . withMode ( wanted , body )
local before = mode
ansi . setMode ( wanted )
local ok , err = pcall ( body )
ansi . setMode ( before )
if not ok then
error ( err , 0 )
end
end


function ansi . enabled ( stream )
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
end






local terminals = { }

function ansi . isTerminal ( stream )
local known = terminals [ stream ]
if known == nil then
known = isatty ( DESCRIPTOR [ stream ] or 1 )
terminals [ stream ] = known
end

return known
end



function ansi . style ( stream )
return ansi . enabled ( stream ) and COLOURED or PLAIN
end




function ansi . forSeverity ( style , name )
return style . severity [ name or "error" ] or style . severity . error or PLAIN . strong
end

return ansi
