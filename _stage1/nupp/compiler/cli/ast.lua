_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON);








local spec = require ( "nupp.compiler.cli.spec" )
local lexer = require ( "nupp.compiler.lexer" )
local optionsMod = require ( "nupp.compiler.cli.options" )

local command = spec . command {
name = "ast" ,
summary = "Dump a Nupp file's parsed syntax tree" ,
usage = { "nupp ast [--format text|json] <file>" } ,
options = optionsMod . format ( ) ,
schema = {
type = "object" ,
properties = {
file = { type = "string" } ,
root = { [ "$ref" ] = "#/definitions/node" } ,
errors = {
type = "array" ,
items = {
type = "object" ,
properties = {
code = { type = "string" } ,
message = { type = "string" } ,
offset = { type = "integer" } ,
length = { type = "integer" } ,
line = { type = "integer" } ,
col = { type = "integer" } ,
help = { type = "string" }
} ,
} ,
} ,
} ,
required = { "file" , "root" , "errors" } ,
definitions = {
node = {
description = "A structural node, or a token with the trivia "
.. "attached to it. The tree is lossless: every byte of the "
.. "source is in exactly one token or one piece of trivia." ,
type = "object" ,
properties = {
tag = { type = "string" , enum = { "node" , "token" } } ,
kind = { type = "string" } ,
children = { type = "array" , items = { [ "$ref" ] = "#/definitions/node" } } ,
text = { type = "string" } ,
offset = { type = "integer" } ,
line = { type = "integer" } ,
col = { type = "integer" } ,
missing = { type = "boolean" , description = "Inserted by error recovery; not in the " .. "source." } ,
trivia = {
type = "array" ,
items = {
type = "object" ,
properties = {
kind = { type = "string" } ,
text = { type = "string" } ,
offset = { type = "integer" } ,
line = { type = "integer" } ,
col = { type = "integer" }
}
} ,
} ,
} ,
required = { "tag" , "kind" } ,
} ,
} ,
} ,
detail = [[The parser produces a lossless concrete syntax tree. Text output is an indented
outline with quoted tokens; JSON includes structural children, tokens, trivia,
locations, and parse errors. A recovered tree is still printed when parsing
fails.]] ,
}


local function syntaxTreeValue ( cst , value )
if cst . isToken ( value ) then
local trivia = { }
for index = 1 , value . triviaCount do
trivia [ # trivia + 1 ] = lexer . triviaRecord ( value , index )
end
return {
tag = "token" ,
kind = value . kind ,
text = value . text ,
offset = value . offset ,
line = value . line ,
col = value . col ,
missing = value . missing and true or nil ,
trivia = trivia ,
}
end
local children = { }
for _ , child in ipairs ( value ) do
children [ # children + 1 ] = syntaxTreeValue ( cst , child )
end

return { tag = "node" , kind = value . kind , children = children }
end

local function run ( parsed )
local paths = parsed . positional
if # paths ~= 1 then
return command : usageError ( "exactly one source file is required" )
end
local path = paths [ 1 ]
local fs = require ( "nupp.compiler.fs" )
local source , readErr = fs . readFile ( path )
if not source then
io . stderr : write ( "nupp: " .. tostring ( readErr ) .. "\n" )
return 1
end
local parser = require ( "nupp.compiler.parser" )
local cst = require ( "nupp.compiler.cst" )
local result = parser . parse ( source , path )
if ( parsed . values . format or "text" ) == "text" then
io . write ( cst . pretty ( result . root ) .. "\n" )
else
local errors = { }
for _ , err in ipairs ( result . errors ) do
errors [
# errors + 1
] = {
code = err . code ,
message = err . msg ,
offset = err . offset ,
length = err . length ,
line = err . line ,
col = err . col ,
help = err . help
}
end
local json = require ( "cjson" ) . new ( )
json . encode_empty_table_as_object ( false )
json . encode_invalid_numbers ( false )
io . write ( json . encode ( { file = path , root = syntaxTreeValue ( cst , result . root ) , errors = errors } ) .. "\n" )
end

return require ( "nupp.compiler.diagnostics" ) . report ( result . errors ) and 1 or 0
end

return setmetatable({ spec =  command ,  run =  run }, spec.Handler)
