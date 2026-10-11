_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local parser = require ( "nupp.compiler.syntax.parser" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local cst = require ( "nupp.compiler.syntax.cst" )
local text = require ( "nupp.tools.lsp.text" )
local wire = require ( "nupp.tools.lsp.wire" )
local tree = require ( "nupp.tools.lsp.tree" )
local fs = require ( "nupp.compiler.fs" )
local bundled = require ( "nupp.compiler.bundled" )
local json = require ( "nupp.codec.json" )
local spi = { }

local function declaration ( inc , name ) 
local path = inc . modulePath ( name )
if path ~= nil then
return inc . checkFile ( path ) , path
end
local record = inc . env . bundled [ name ]
if not record or record . source == nil or record . resource == nil then
return nil , nil
end
local original = bundled . sourcePathFor ( record . resource )
if original ~= nil and text . readFile ( original ) == record . source then
path = original
else
path = fs . join ( inc . env . rootDir , ".nupp-cache/lsp-sources" .. record . resource )
if text . readFile ( path ) ~= record . source then
if not fs . writeFile ( path , record . source ) then
return nil , nil
end
end
end

return { moduleType = record . type , exports = record . exports } , path
end

local function entries ( inc ) 
local out , seen = { } , { }

local function add ( interface , implementation ) 
local key = interface .. "\0" .. implementation
if not seen [ key ] then
seen [ key ] = true
out [ # out + 1 ] = { interface = interface , implementation = implementation }
end
end

local source = text . readFile ( fs . join ( inc . env . rootDir , "nupp/spi.json" ) )
if source then
local document = json . decode ( source )
if type ( document ) == "table" then
for interface , modules in pairs ( document ) do
if type ( interface ) == "string" and interface : sub ( 1 , 1 ) ~= "$" and type ( modules ) == "table" then
for _ , implementation in ipairs ( modules ) do
if type ( implementation ) == "string" then
add ( interface , implementation )
end
end
end
end
end
end
local config = require ( "nupp.tools.build.manifest" ) . load ( inc . env . rootDir )
local build = config and config . build or { }
local paths = { fs . join ( inc . env . rootDir , ( build . outDir or "build" ) .. "/generated/nupp/spi/index.g.nupp" ) }
for _ , target in pairs ( build . targets or { } ) do
paths [
# paths + 1
] = fs . join ( inc . env . rootDir , ( target . outDir or build . outDir or "build" ) .. "/generated/nupp/spi/index.g.nupp" )
end
local direct = inc . modulePath ( "nupp.spi.index" )
if direct then
paths [ # paths + 1 ] = direct
end
for _ , path in ipairs ( paths ) do
local code = text . readFile ( path )
if code then
local parsed = parser . parse ( code , path )
local assignment = cst . exportAssignment ( parsed . root )
local value = assignment and assignment . value
for _ , field in ipairs ( value and value . kind == "tableExpr" and value . fields or { } ) do
if field . kind == "fieldBracket"
and field . key ~= nil
and field . key . kind == "string"
and field . key . token ~= nil
and field . value ~= nil
and field . value . kind == "tableExpr"
then
local interface = lexer . stringValue ( field . key . token . text )
for _ , entry in ipairs ( field . value . fields ) do
local item = entry . kind == "fieldItem" and entry . value or nil
if interface and item and item . kind == "string" and item . token ~= nil then
local implementation = lexer . stringValue ( item . token . text )
if implementation then
add ( interface , implementation )
end
end
end
end
end
end
end

return out
end

local function sameDefinition ( left , right ) 
return left ~= nil
and right ~= nil
and left . filename == right . filename
and left . token ~= nil
and right . token ~= nil
and left . token . offset == right . token . offset
end


function spi . implementations ( inc , member , token ) 
local locations , seen , interfaces = wire . array ( { } ) , { } , { }
local name = member and member . name or token and token . text
local definition = token and token . definition
if name == nil then
return locations
end
if member and member . moduleName then
local checked = declaration ( inc , member . moduleName )
tree . walkNodes ( checked and checked . result and checked . result . root , function ( node ) 
if node . spiInterface then
interfaces [ node . spiInterface ] = true
end
end )
end
for _ , entry in ipairs ( entries ( inc ) ) do
local moduleName , typeName = entry . interface : match ( "^(.*)%.([^.]+)$" )
local contract = moduleName and declaration ( inc , moduleName )
local interface = contract and contract . exports and contract . exports . types [ typeName ]
local origin = interface and ( interface . origin or interface )
local canonical = origin
and origin . moduleName
and origin . moduleName .. "." .. ( origin . name : match ( "[^.]+$" ) or origin . name )
local field = interface and interface . fieldDefs and interface . fieldDefs [ name ]
if interfaces [ canonical ]
or ( definition ~= nil and field ~= nil and definition . filename == field . filename and definition . token ~= nil and field . token ~= nil and definition . token . offset == field . token . offset )
or sameDefinition ( definition , origin and origin . definition )
then
local implementation , path = declaration ( inc , entry . implementation )
local exported = implementation and implementation . exports
local found = exported and exported . valueDefs and exported . valueDefs [ name ]
local at = found and found . token
or cst . firstToken ( implementation and implementation . result and implementation . result . root )
local code = path and text . readFile ( path )
if at and path and code then
local key = path .. ":" .. at . offset
if not seen [ key ] then
seen [ key ] = true
locations [ # locations + 1 ] = { uri = text . pathToUri ( path ) , range = text . tokenRange ( code , at ) }
end
end
end
end
table . sort ( locations , function ( left , right ) 
return left . uri == right . uri and left . range . start . line < right . range . start . line or left . uri < right . uri
end )

return locations
end

local __nuppExportValue= spi ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.lsp.spi"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.lsp.spi"]=__nuppExports;return __nuppExports