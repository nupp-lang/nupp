_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);


















local bundledMod = require ( "nupp.compiler.bundled" )
local extractMod = require ( "nupp.compiler.doc.extract" )
local markdownMod = require ( "nupp.compiler.doc.markdown" )

local stdlib = { }


















const Source = {} Source.__index = Source







local SOURCES

= { setmetatable({ file =
"/decls/prelude.d.nupp" }, Source) , setmetatable({ file =
"/decls/ffi.d.nupp" ,  required =  "ffi" }, Source) , setmetatable({ file =
"/decls/stringbuffer.d.nupp" ,  required =  "string.buffer" }, Source) , setmetatable({ file =
"/decls/jit/util.d.nupp" ,  required =  "jit.util" }, Source) , setmetatable({ file =
"/decls/jit/profile.d.nupp" ,  required =  "jit.profile" }, Source) , setmetatable({ file =
"/decls/jit/zone.d.nupp" ,  required =  "jit.zone" }, Source) ,
}

local INTRO = "Every name a checked program can use without declaring it, and every "
.. "module LuaJIT loads by name, as the compiler itself declares them. `nupp` "
.. "reads these files to decide what a call means, so a signature here is the "
.. "signature the checker enforces."

local GLOBALS = "The functions and values a program can name anywhere. Their "
.. "declarations are loaded before any source is checked, so nothing requires them "
.. "and nothing can shadow them by accident."

local TYPES = "The types the declarations above name in their signatures. They are "
.. "written by the prelude rather than by a program, which is why they have no "
.. "module of their own to be documented from."

local REFLECTION = "What the compiler hands a program about a reified `struct`'s "
.. "memory. `layoutof` answers with a [](Layout); semantic descriptors instead "
.. "live with the callable `nupp.reflect` namespace. Layout types sit apart from "
.. "the types above because reading them is metaprogramming rather than calling "
.. "a library."






local REFLECTION_TYPES = { Layout = true , LayoutField = true , }





local function isGlobal ( item )
return not item . module and ( item . kind == "function" or item . kind == "variable" )
end

local function isType ( item )
return not item . module and item . kind ~= "function" and item . kind ~= "variable"
end

local function isReflection ( item )
return REFLECTION_TYPES [ item . name ] == true
end

local function only ( items , wanted )
local kept = { }
for _ , item in ipairs ( items ) do
if wanted ( item ) then
kept [ # kept + 1 ] = item
end
end

return kept
end





local function anchorByName ( items )
for _ , item in ipairs ( items ) do
item . path = item . name
for _ , member in ipairs ( item . members ) do
member . path = item . path .. "." .. member . name
end
end
end





local function qualifyNames ( library , items )
for _ , item in ipairs ( items ) do
item . name = library .. "." .. item . name
end
end




local function withoutRedeclaredBindings ( items )
local types = { }
for _ , item in ipairs ( items ) do
if isType ( item ) then
types [ item . name ] = true
end
end

return only ( items , function ( item )
return not ( item . kind == "variable" and types [ item . signature : match ( ": ([%w_]+)$" ) or "" ] )
end )
end

local function section ( out , title , text , items )
if items and # items == 0 then
return
end
out [ # out + 1 ] = "## " .. title
out [ # out + 1 ] = ""
if text and text ~= "" then
out [ # out + 1 ] = text
out [ # out + 1 ] = ""
end
if items then
out [ # out + 1 ] = markdownMod . items ( items )
end
end









function stdlib . page ( settings )
if not settings then
return nil
end
local title = settings . title or "LuaJIT standard library"
local out = { "# " .. title , "" , INTRO , "" }
local types = { }
for _ , source in ipairs ( SOURCES ) do
local text = bundledMod . source ( source . file )
if text then
local path = source . file : gsub ( "^/" , "" )
local module , _ , libraries = extractMod . extract ( text , path , source . required or "globals" , {
shapesAsModules = source . required == nil
} )
if module then
if source . required then
local items = withoutRedeclaredBindings ( module . items )
qualifyNames ( source . required , items )
section ( out , "`" .. source . required .. "`" , module . text , items )
else
local globals = only ( module . items , isGlobal )
anchorByName ( globals )
section ( out , "Globals" , GLOBALS , globals )
for _ , item in ipairs ( only ( module . items , isType ) ) do
types [ # types + 1 ] = item
end
end
end


for _ , library in ipairs ( libraries or { } ) do
qualifyNames ( library . name , library . items )
section ( out , "`" .. library . name .. "`" , library . text , library . items )
end
end
end
anchorByName ( types )
section (
out ,
"Types" ,
TYPES ,
only ( types , function ( item )
return not isReflection ( item )
end )
)
section ( out , "Reflection" , REFLECTION , only ( types , isReflection ) )

return {
path = settings . path or "luajit" ,
title = title ,




markdown = table . concat ( out , "\n" )
}
end

return stdlib
