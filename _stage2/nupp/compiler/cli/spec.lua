_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);




















local ansi = require ( "nupp.compiler.ansi" )

local spec = { }










spec.Option = {} spec.Option.__index = spec.Option
















































spec.Result = {} spec.Result.__index = spec.Result










spec.Positional = {} spec.Positional.__index = spec.Positional





spec.Command = {} spec.Command.__index = spec.Command























































































spec.Handler = {} spec.Handler.__index = spec.Handler













local WIDTH = 79
local INDENT = "  "



local LABEL_LIMIT = 20

local function isOption ( value )
return value : sub ( 1 , 1 ) == "-" and value ~= "-"
end



local function derivedKey ( name )
local bare = name : gsub ( "^%-+" , "" )
return ( bare : gsub ( "%-(%w)" , function ( ch )
return ch : upper ( )
end ) )
end



local function wrap ( text , width )
local lines , line = { } , ""
for word in text : gmatch ( "%S+" ) do
if line == "" then
line = word
elseif # line + 1 + # word <= width then
line = line .. " " .. word
else
lines [ # lines + 1 ] = line
line = word
end
end
if line ~= "" then
lines [ # lines + 1 ] = line
end

return lines
end


local function label ( option )
local display = option . display
if display then
return display
end
local names = table . concat ( option . names , ", " )
local placeholder = option . value
if not placeholder then
return names
end
local form = option . form
if form == "value" then
return names .. " " .. placeholder
elseif form == "attached" then
return names .. "=" .. placeholder
else
return names .. "[=" .. placeholder .. "]"
end
end



local function normalize ( raw )
local names = type ( raw . names ) == "table" and raw . names or { raw . name }
local form = raw . form or ( raw . value and "value" or "flag" )


local longest = names [ 1 ]
for _ , name in ipairs ( names ) do
if # name > # longest then
longest = name
end
end

return setmetatable({ names =
names ,  key =
raw . key or derivedKey ( longest ) ,  value =
raw . value ,  form =
form ,  pattern =
raw . pattern ,  choices =
raw . choices ,  constant =
raw . constant ,  repeats =
raw . repeats ,  set =
raw . set ,  display =
raw . display ,  duplicate =
raw . duplicate ,  invalid =
raw . invalid ,  help =
raw . help or "" }, spec.Option)

end





local UNIVERSAL

= {
{
name = "--color" ,
value = "WHEN" ,
form = "optional" ,
constant = "always" ,
choices = { "always" , "never" , "auto" } ,
help = "When to colour output: always, never, or auto (default)"
} ,
{
name = "--no-color" ,
key = "color" ,
constant = "never" ,
duplicate = "colour was both asked for and refused" ,
help = "Never colour output; the same as --color=never"
} ,
{ names = { "-h" , "--help" } , help = "Show this help" } ,
}



spec . helpOption = UNIVERSAL [ 3 ]



local SCHEMA_OPTION = { name = "--schema" , help = "Print the JSON Schema of --json output and exit" , }





function spec . command ( raw )
local options = { }
local byName = { }
local patterned = { }
local declared = { }
for _ , entry in ipairs ( raw . options or { } ) do
declared [ # declared + 1 ] = entry
end
if raw . schema then
declared [ # declared + 1 ] = SCHEMA_OPTION
end
if raw . universal ~= false then
for _ , entry in ipairs ( UNIVERSAL ) do
declared [ # declared + 1 ] = entry
end
end
for _ , entry in ipairs ( declared ) do
local option = normalize ( entry )
options [ # options + 1 ] = option
if option . pattern then
patterned [ # patterned + 1 ] = option
end
for _ , name in ipairs ( option . names ) do
byName [ name ] = option
end
end

return setmetatable({ name =
raw . name ,  helpName =
raw . helpName or raw . name ,  summary =
raw . summary ,  usage =
raw . usage or { } ,  positionals =
( raw . positionals or { } ) ,  options =
options ,  intro =
raw . intro ,  detail =
raw . detail ,  schema =
raw . schema ,  stopAtPositional =
raw . stopAtPositional ,  byName =
byName ,  patterned =
patterned }, spec.Command)

end


local function store ( values , seen , option , value )
local key = option . key
if option . repeats then
local list = values [ key ]
if not list then
list = { }
values [ key ] = list
end
if option . set then
list [ value ] = true
else
list [ # list + 1 ] = value
end
return nil
end
local already = seen [ key ]
if already then


return already . duplicate or option . duplicate or (
"option " .. option . names [ 1 ] .. " was specified more than once"
)
end
seen [ key ] = option
values [ key ] = value

return nil
end

local function checkChoice ( option , value )
local choices = option . choices
if not choices then
return nil
end
for _ , choice in ipairs ( choices ) do
if value == choice then
return nil
end
end

return option . invalid or (
"option " .. option . names [ 1 ] .. " does not take " .. value .. "; expected " .. table . concat ( choices , ", " )
)
end



function spec . Command : parse ( args )
local values = { }
local seen = { }
local positional = { }
local literal = false
local index = 1
while index <= # args do
local current = args [ index ]
if literal then
positional [ # positional + 1 ] = current
index = index + 1
elseif current == "--" then
literal = true
index = index + 1
else
local option = self . byName [ current ]
local value = nil
local consumed = 1
local failure = nil
if option then
local form = option . form
if form == "value" then
local given = args [ index + 1 ]
if not given or given == "" or isOption ( given ) then
failure = "option " .. current .. " requires a value"
else
value , consumed = given , 2
end
elseif form == "attached" then
failure = "option " .. current .. " requires a value; write " .. current .. "=" .. (
option . value or "VALUE"
)
else


value = option . constant
if value == nil then
value = true
end
end
else


local name , attached = current : match ( "^(%-%-?[^=]+)=(.*)$" )
if name and attached then
local named = self . byName [ name ]
if named and named . form == "flag" then
failure = "option " .. name .. " does not take a value"
elseif named and attached == "" and named . form ~= "optional" then
failure = "option " .. name .. " requires a value"
elseif named then




option , value = named , attached
end
end
if not option and not failure then
for _ , candidate in ipairs ( self . patterned ) do
local pattern = candidate . pattern
local captured = pattern and current : match ( pattern )
if captured then
option , value = candidate , captured
break
end
end
end
end
if failure then
return nil , failure
end
if option then
if type ( value ) == "string" then
local wrong = checkChoice ( option , value )
if wrong then
return nil , wrong
end
end
local repeated = store ( values , seen , option , value )
if repeated then
return nil , repeated
end
index = index + consumed
elseif isOption ( current ) then
return nil , "unknown option " .. current
elseif self . stopAtPositional then
for rest = index , # args do
positional [ # positional + 1 ] = args [ rest ]
end
break
else
positional [ # positional + 1 ] = current
index = index + 1
end
end
end

return setmetatable({ values =  values ,  positional =  positional }, spec.Result)
end



function spec . Command : help ( )
local style = ansi . style ( io . stdout )
local paint = ansi . forSeverity ( style , "note" )
local out = { self . summary , "" , style . strong ( "Usage:" ) }
for _ , line in ipairs ( self . usage ) do
out [ # out + 1 ] = INDENT .. line
end
local intro = self . intro
if intro then
out [ # out + 1 ] = "" ;
out [ # out + 1 ] = intro
end
if # self . options > 0 then
local labels = { }
local width = 0
for position , option in ipairs ( self . options ) do
local text = label ( option )
labels [ position ] = text
if # text > width and # text <= LABEL_LIMIT then
width = # text
end
end
out [ # out + 1 ] = ""
out [ # out + 1 ] = style . strong ( "Options:" )
local gap = # INDENT + width + 2
local padding = ( " " ) : rep ( gap )
for position , option in ipairs ( self . options ) do
local text = labels [ position ]
local lines = wrap ( option . help , WIDTH - gap )


local head = INDENT .. paint ( text )
if # text > width then
out [ # out + 1 ] = head
for _ , line in ipairs ( lines ) do
out [ # out + 1 ] = padding .. line
end
else
out [ # out + 1 ] = head .. ( " " ) : rep ( width - # text + 2 ) .. ( lines [ 1 ] or "" )
for line = 2 , # lines do
out [ # out + 1 ] = padding .. lines [ line ]
end
end
end
end
local detail = self . detail
if detail then
out [ # out + 1 ] = "" ;
out [ # out + 1 ] = detail
end

return table . concat ( out , "\n" ) .. "\n"
end




function spec . Command : usageError ( message )
local style = ansi . style ( io . stderr )
io . stderr : write (
ansi . forSeverity (
style ,
"error"
) (
"nupp:"
) .. " " .. tostring (
message
) .. "\nTry '" .. style . strong ( "nupp help " .. self . helpName ) .. "' for more information.\n"
)

return 2
end

spec . isOption = isOption
spec . wrap = wrap

return spec
