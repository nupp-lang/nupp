_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);








local spec = require ( "nupp.compiler.cli.spec" )

local completions = { }






local function words ( items )
return table . concat ( items , " " )
end



local function quoted ( value )
return "'" .. value : gsub ( "'" , "'\\''" ) .. "'"
end





local function spellings ( option )
local choices = option . choices
if option . pattern then
local out = { }
if choices then
for _ , name in ipairs ( option . names ) do
for _ , choice in ipairs ( choices ) do
out [ # out + 1 ] = name .. choice
end
end
end
return out
end

return option . names
end

local function optionWords ( command )
local out = { }
for _ , option in ipairs ( command . spec . options ) do
for _ , name in ipairs ( spellings ( option ) ) do
out [ # out + 1 ] = name
end
end

return words ( out )
end

local function firstPositionalChoices ( command )
local positional = command . spec . positionals [ 1 ]
return positional and positional . choices or nil
end

local function choiceCases ( command )
local out = { }
for _ , option in ipairs ( command . spec . options ) do
local choices = option . choices
if choices then
for _ , name in ipairs ( option . names ) do
out [ # out + 1 ] = "    " .. name .. ")"
out [ # out + 1 ] = "      COMPREPLY=( $(compgen -W '" .. words ( choices ) .. "' -- \"$cur\") )"
out [ # out + 1 ] = "      return 0;;"
end
end
end

return out
end

local function bash ( commands )
local names = { }
local lines

= {
"# Bash completion for nupp; generated from nupp.compiler.cli.spec." ,
"_nupp() {" ,
"  local cur prev command options" ,
"  cur=\"${COMP_WORDS[COMP_CWORD]}\"" ,
"  prev=\"${COMP_WORDS[COMP_CWORD - 1]}\"" ,
"  if (( COMP_CWORD == 1 )); then" ,
}
for _ , command in ipairs ( commands ) do
names [ # names + 1 ] = command . name
end
lines [ # lines + 1 ] = "    COMPREPLY=( $(compgen -W '" .. words ( names ) .. "' -- \"$cur\") )"
lines [ # lines + 1 ] = "    return 0"
lines [ # lines + 1 ] = "  fi"
lines [ # lines + 1 ] = "  command=\"${COMP_WORDS[1]}\""
lines [ # lines + 1 ] = "  case \"$command\" in"
for _ , command in ipairs ( commands ) do
lines [ # lines + 1 ] = "  " .. command . name .. ")"
local positional = firstPositionalChoices ( command )
if positional then
lines [ # lines + 1 ] = "    if (( COMP_CWORD == 2 )); then"
lines [ # lines + 1 ] = "      COMPREPLY=( $(compgen -W '" .. words ( positional ) .. "' -- \"$cur\") )"
lines [ # lines + 1 ] = "      return 0"
lines [ # lines + 1 ] = "    fi"
end
lines [ # lines + 1 ] = "    case \"$prev\" in"
for _ , line in ipairs ( choiceCases ( command ) ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = "    esac"
lines [ # lines + 1 ] = "    options='" .. optionWords ( command ) .. "'"
lines [ # lines + 1 ] = "    COMPREPLY=( $(compgen -W \"$options\" -- \"$cur\") )"
lines [ # lines + 1 ] = "    return 0;;"
end
lines [ # lines + 1 ] = "  esac"
lines [ # lines + 1 ] = "}"
lines [ # lines + 1 ] = "complete -F _nupp nupp"

return table . concat ( lines , "\n" ) .. "\n"
end

local function zsh ( commands )
local names = { }
local lines

= {
"#compdef nupp" ,
"# Zsh completion for nupp; generated from nupp.compiler.cli.spec." ,
"local -a commands" ,
"commands=(" ,
}
for _ , command in ipairs ( commands ) do
names [ # names + 1 ] = "  " .. quoted ( command . name .. ":" .. command . spec . summary )
end
for _ , line in ipairs ( names ) do
lines [ # lines + 1 ] = line
end
lines [ # lines + 1 ] = ")"
lines [ # lines + 1 ] = "_arguments -C '1:command:->command' '*::argument:->argument'"
lines [ # lines + 1 ] = "case $state in"
lines [ # lines + 1 ] = "  command) _describe -t commands 'nupp command' commands;;"
lines [ # lines + 1 ] = "  argument)"
lines [ # lines + 1 ] = "    case $words[2] in"
for _ , command in ipairs ( commands ) do
lines [ # lines + 1 ] = "    " .. command . name .. ")"
local positional = firstPositionalChoices ( command )
if positional then
lines [ # lines + 1 ] = "      if (( CURRENT == 3 )); then"
lines [ # lines + 1 ] = "        compadd -- " .. words ( positional )
lines [ # lines + 1 ] = "      else"
end
lines [ # lines + 1 ] = "      local -a options"
lines [ # lines + 1 ] = "      options=( " .. optionWords ( command ) .. " )"
lines [ # lines + 1 ] = positional and "      compadd -- $options" or "      compadd -- $options;;"
if positional then
lines [ # lines + 1 ] = "      fi;;"
end
end
lines [ # lines + 1 ] = "    esac;;"
lines [ # lines + 1 ] = "esac"

return table . concat ( lines , "\n" ) .. "\n"
end

local function fish ( commands )
local lines

= {
"# Fish completion for nupp; generated from nupp.compiler.cli.spec." ,
"function __fish_nupp_using_command" ,
"    set -l words (commandline -opc)" ,
"    test (count $words) -ge 2; and test $words[2] = $argv[1]" ,
"end" ,
"complete -c nupp -f" ,
}
for _ , command in ipairs ( commands ) do
lines [
# lines + 1
] = "complete -c nupp -n '__fish_nupp_using_command' -a " .. command . name .. " -d " .. quoted (
command . spec . summary
)
local positional = firstPositionalChoices ( command )
if positional then
lines [
# lines + 1
] = "complete -c nupp -n '__fish_nupp_using_command " .. command . name .. "' -a '" .. words (
positional
) .. "'"
end
for _ , option in ipairs ( command . spec . options ) do
local choices = option . choices
for _ , name in ipairs ( spellings ( option ) ) do
if name : sub ( 1 , 2 ) == "--" then
local line = "complete -c nupp -n '__fish_nupp_using_command "
.. command . name
.. "' -l "
.. name : sub (
3
)
if option . form ~= "flag" then
line = line .. " -r"
end
if choices then
line = line .. " -a '" .. words ( choices ) .. "'"
end
lines [ # lines + 1 ] = line
elseif # name == 2 and name : sub ( 1 , 1 ) == "-" then
local line = "complete -c nupp -n '__fish_nupp_using_command "
.. command . name
.. "' -s "
.. name : sub (
2
)
if option . form ~= "flag" then
line = line .. " -r"
end
if choices then
line = line .. " -a '" .. words ( choices ) .. "'"
end
lines [ # lines + 1 ] = line
elseif name : sub ( 1 , 1 ) == "-" then
lines [
# lines + 1
] = "complete -c nupp -n '__fish_nupp_using_command " .. command . name .. "' -a '" .. name .. "'"
end
end
end
end

return table . concat ( lines , "\n" ) .. "\n"
end


function completions . render ( shell , commands )
if shell == "bash" then
return bash ( commands )

elseif shell == "zsh" then
return zsh ( commands )
end

return fish ( commands )
end

return completions
