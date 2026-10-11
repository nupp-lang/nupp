_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


















local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local parser = require ( "nupp.compiler.syntax.parser" )

local header = { }





































local function declarationKind ( stat ) 
if stat . kind == "recordDecl" then
return stat . declKind
end

return "type"
end

local function annotationString ( expr ) 
if not expr or expr . kind ~= "string" or not expr . token then
return nil
end
local text = expr . token . text
local chunk = loadstring ( "return " .. text )
if chunk then
local ok , value = pcall ( chunk )
if ok and type ( value ) == "string" then
return value
end
end

return nil
end

local function syntacticDeprecation ( application ) 
local deprecated = { }
for _ , argument in ipairs ( application . annotationArgs or { } ) do
local name = argument . name and argument . name . text or "reason"
local value = annotationString ( argument . expr )
if ( name == "reason" or name == "replacement" ) and value then
deprecated [ name ] = value
end
end

return deprecated
end

local function annotatedDeclaration ( stat ) 
local annotationDefinition = false
local deprecated = nil
local exported = false



local function recordPragmas ( ) 
while stat and stat . kind == "pragmaStmt" do
if stat . name and stat . name . text == "annotation" then
annotationDefinition = true
elseif stat . name and stat . name . text == "deprecated" then
deprecated = syntacticDeprecation ( stat )
end
stat = stat . stat
end
end

recordPragmas ( )
if stat and stat . kind == "exportStmt" then
exported = true
stat = stat . stat
recordPragmas ( )
end

return stat , annotationDefinition , deprecated , exported
end



local function declarationSignature ( stat , declaration ) 
local parts = { }
local skippedBody = declaration
and ( declaration . kind == "localFuncStmt" or declaration . kind == "funcStmt" )
and declaration . body
and declaration . body . body
or nil

local function walk ( value ) 
if value == skippedBody then
return
end
if cst . isToken ( value ) then
if value . kind ~= "eof" and not value . missing then
parts [ # parts + 1 ] = value . kind .. "\1" .. value . text
end
else
for _ , child in ipairs ( value ) do
walk ( child )
end
end
end

walk ( stat )

return table . concat ( parts , "\2" )
end








local function declarationToken ( tok ) 



local trivia = { }
for index = 1 , tok and tok . triviaCount or 0 do
trivia [ index ] = lexer . triviaRecord ( tok , index )
end

return { kind = tok . kind , text = tok . text , offset = tok . offset , line = tok . line , col = tok . col , trivia = trivia }
end










function header . of ( path , moduleName , parsed ) 
local produced = { path = path , moduleName = moduleName , declarations = { } , dependencies = { } }
if not parsed or # parsed . errors > 0 then
return produced
end
local declaredModuleName , moduleNode = cst . declaredModule ( parsed . root )
produced . internal = parsed . root . documentationInternal == true
produced . declaredModuleName = declaredModuleName
produced . moduleToken = moduleNode and declarationToken ( moduleNode . keyword )
local moduleLocal = declaredModuleName and ( cst . exportedLocal ( parsed . root ) or "__nuppExports" )
or cst . returnedLocal ( parsed . root )
produced . moduleLocal = moduleLocal
local dependencySet = { }

local function dependencies ( node ) 
if not node or cst . isToken ( node ) then
return
end
if node . kind == "call"
and node . obj
and node . obj . kind == "name"
and node . obj . token
and node . obj . token . text == "require"
then
local argument = node . args and node . args . exprs and node . args . exprs [ 1 ]
local name = argument and annotationString ( argument )
if name then
dependencySet [ name ] = true
end
end
for _ , child in ipairs ( node ) do
dependencies ( child )
end
end

dependencies ( parsed . root )
for name in pairs ( dependencySet ) do
produced . dependencies [ # produced . dependencies + 1 ] = name
end
table . sort ( produced . dependencies )
for _ , block in ipairs ( parsed . root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
local declaration , isAnnotation , deprecated , exported = annotatedDeclaration ( stat )
local visibility = declaration
and (
exported and "module"
or (
( declaration . kind == "typeAlias" or declaration . kind == "recordDecl" )
and cst . declVisibility ( declaration , moduleLocal )
or "local"
)
)
if declaration
and ( declaration . kind == "typeAlias" or declaration . kind == "recordDecl" )
and ( visibility == "module" or visibility == "global" )
then
produced . declarations [
# produced . declarations + 1
] = {
name = declaration . name . text ,
kind = declarationKind ( declaration ) ,
statKind = declaration . kind ,
visibility = visibility ,
token = declarationToken ( declaration . name ) ,
signature = declarationSignature ( stat , declaration ) ,
isAnnotation = isAnnotation ,
comptimeOnly = declaration . comptimeOnly ,
deprecated = deprecated ,
}
elseif declaration and exported then
local names = { }
local kind = nil
if declaration . kind == "localFuncStmt" then
names [ 1 ] , kind = declaration . name , "function"
elseif declaration . kind == "funcStmt" and declaration . name and # declaration . name == 1 then
names [ 1 ] , kind = declaration . name . base , "function"
elseif declaration . kind == "localStmt" and declaration . isConst then
names , kind = declaration . names or { } , "constant"
end
for _ , name in ipairs ( names ) do
produced . declarations [
# produced . declarations + 1
] = {
name = name . text ,
kind = kind ,
statKind = declaration . kind ,
visibility = "module" ,
token = declarationToken ( name ) ,
signature = declarationSignature ( stat , declaration ) ,
isAnnotation = isAnnotation ,
deprecated = deprecated ,
}
end
end
end
end

return produced
end

local __nuppExportValue= header ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.project.header"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.project.header"]=__nuppExports;return __nuppExports