_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);









































local __nuppT1={ _G.nupp.__reflect.declaration("nupp.cli\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.cli\0runtime\0002") }; local cliModule = { }


const parser = require ( "nupp.cli.internal.optparser" )



































cliModule.CompletionCandidate = {} cliModule.CompletionCandidate.__index = cliModule.CompletionCandidate ;_G.nupp.__reflect.link(cliModule.CompletionCandidate,__nuppT1[1],{ })






cliModule.CompletionRequest = {} cliModule.CompletionRequest.__index = cliModule.CompletionRequest ;_G.nupp.__reflect.link(cliModule.CompletionRequest,__nuppT1[2],{ })















cliModule . none = "none"


cliModule . required = "required"


cliModule . optionalAttached = "optionalAttached"


cliModule . attachedOnly = "attachedOnly"


cliModule . shortOption = parser . shortOption


cliModule . longOption = parser . longOption


cliModule . argument = parser . argument


cliModule . terminator = parser . terminator


cliModule . optParser = parser . optParser


cliModule . getopt = parser . getopt


function cliModule . setColorMode ( wanted ) 
return require ( "nupp.cli.internal.terminal" ) . setColorMode ( wanted )
end


function cliModule . withColorMode ( wanted , body ) 
return require ( "nupp.cli.internal.terminal" ) . withColorMode ( wanted , body )
end


function cliModule . colorEnabled ( stream ) 
return require ( "nupp.cli.internal.terminal" ) . colorEnabled ( stream )
end


function cliModule . isTerminal ( stream ) 
return require ( "nupp.cli.internal.terminal" ) . isTerminal ( stream )
end


function cliModule . columns ( stream ) 
return require ( "nupp.cli.internal.terminal" ) . columns ( stream )
end


function cliModule . style ( stream ) 
return require ( "nupp.cli.internal.terminal" ) . style ( stream )
end


function cliModule . table ( options ) 
return require ( "nupp.cli.internal.table" ) . render ( options )
end


function cliModule . writeTable ( stream , options ) 
return require ( "nupp.cli.internal.table" ) . write ( stream , options )
end


function cliModule . cell ( value ) 
return require ( "nupp.cli.internal.table" ) . text ( value )
end


function cliModule . paintedCell ( value , paint ) 
return require ( "nupp.cli.internal.table" ) . painted ( value , paint )
end



function cliModule . annotatedCell ( value , note , paint ) 
return require ( "nupp.cli.internal.table" ) . annotated ( value , note , paint )
end


function cliModule . severity ( styles , name ) 
return require ( "nupp.cli.internal.terminal" ) . forSeverity ( styles , name )
end


function cliModule . command ( subject ) 
return require ( "nupp.cli.internal.application" ) . command ( subject )
end


function cliModule . application (
rootType ,
options
) 
return require ( "nupp.cli.internal.application" ) . application ( rootType , options )
end


function cliModule . derivedFromCLI ( argv , entry ) 
return require ( "nupp.cli.internal.decode" ) . fromCLI ( argv , entry )
end


function cliModule . derivedText ( value ) 
return value
end


function cliModule . derivedStrings ( value ) 
return value
end


function cliModule . derivedCompleter ( subject ) 
return subject
end


function cliModule . derivedGroupRun ( self ) 
return 0
end
















































































































































































































































































































































































































































































































































































function cliModule . decodeAs ( subject , argv ) 
local entry = require ( "nupp.derive" ) . entry ( subject )
if entry == nil or entry . schema . data . cli == nil then
return nil , { kind = "notDerived" , message = "the requested type does not derive CLI arguments" }
end

return require ( "nupp.cli.internal.decode" ) . fromCLI ( argv , entry )
end


function cliModule . schema ( subject ) 
local entry = require ( "nupp.derive" ) . entry ( subject )
return entry and entry . schema . data . cli or nil
end

return cliModule
