_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






















local T = require ( "nupp.compiler.types" )
local cst = require ( "nupp.compiler.syntax.cst" )
local state = require ( "nupp.compiler.check.state" )
local targetLayout = require ( "nupp.compiler.targetlayout" )

local nativeonly = { }










local function vectorOrMask ( t ) 
if t == nil then
return false
end
local raw = T . unwrapOwnership ( t )
while raw ~= nil and raw . tag == "genericAlias" do
raw = raw . body
end
if raw == nil or raw . tag ~= "nominal" then
return false
end
local origin = raw . origin or raw
if origin . declKind == "struct" and origin . nativeOnly == true then
return true
end

return origin . moduleName == "nupp.simd" and ( origin . name == "Vector" or origin . name == "Mask" )
end



function nativeonly . carriesNativeOnly ( t ) 
return vectorOrMask ( t )
end



function nativeonly . storageVector ( t ) 
local element = targetLayout . storageVector ( t )

return element ~= nil
end





function nativeonly . fieldMakesNativeOnly ( t ) 
return vectorOrMask ( t ) and not nativeonly . storageVector ( t )
end


function nativeonly . signatureIsNativeOnly ( signature ) 
if signature == nil or signature . tag ~= "func" then
return false
end
for _ , param in ipairs ( signature . params or { } ) do
if vectorOrMask ( param ) then
return true
end
end
for _ , result in ipairs ( signature . rets or { } ) do
if vectorOrMask ( result ) then
return true
end
end

return false
end




function nativeonly . install ( c ) 
local ops = { }




local function compiles ( ) 
local selected = c . env ~= nil and c . env . config ~= nil and c . env . config . _target or nil
local policy = selected ~= nil and selected . aot or nil

return policy == "require" or policy == "emit-wasm" or policy == "require-wasm"
end


local function exported ( module , member ) 
if module == nil or member == nil or c . env == nil or c . env . resolveModuleExports == nil then
return nil
end
local exports = c . env . resolveModuleExports ( c . env , module )

return exports ~= nil and exports . valueDefs ~= nil and exports . valueDefs [ member ] or nil
end




function ops . resolve ( node ) 
if node == nil then
return nil
end
local def = node . kind == "name" and node . token ~= nil and node . token . definition
or node . kind == "dotIndex" and node . name ~= nil and node . name . definition
or nil
if def ~= nil and ( def . aotOrigin ~= nil or def . exactCallExport == nil ) then
return def
end
local export = node . exactCallExport or def ~= nil and def . exactCallExport or nil
if export ~= nil then
return exported ( export . module , export . member ) or def
end

return def
end





function ops . alias ( target , source , export ) 
if target == nil then
return
end
local origin = source ~= nil and source . aotOrigin ~= nil and source or nil
if origin == nil and export ~= nil then
origin = exported ( export . module , export . member )
end
if origin == nil or origin . aotOrigin == nil then
return
end
target . aotOrigin = origin . aotOrigin
target . aotNativeOnly = origin . aotNativeOnly
end

function ops . mark ( stat , body ) 
local nameTok = stat ~= nil and stat . kind == "localFuncStmt" and stat . name or nil
local def = nameTok ~= nil and nameTok . definition or nil
if def == nil then
return
end
def . aotOrigin = { filename = def . filename , name = def . name }
if nativeonly . signatureIsNativeOnly ( body . signatureType ) then
def . aotNativeOnly = true
body . aotNativeOnly = true
end
end

local function report ( token , def ) 
local message = def . aotOrigin ~= nil
and def . aotOrigin . aggregate == true
and "%s is a native-only aggregate: it holds a vector and is constructed and read only inside an @aot function"
or "%s is a native-only AOT entry: it takes or answers a vector and is called only from another @aot function"
c . diag ( "NUPP2910" , token , message : format ( tostring ( def . name or token . text ) ) )
end







local refusing = false

local function visit ( node , insideAot , allowed , topLevel ) 
if node == nil or cst . isToken ( node ) then
return
end
local kind = node . kind
if kind == "name" and node . token ~= nil then
local def = ops . resolve ( node )
if def ~= nil and def . aotOrigin ~= nil then
node . aotOrigin = def . aotOrigin
end
if def ~= nil and def . aotNativeOnly == true and refusing and not insideAot and not allowed [ node ] then
report ( node . token , def )
end
return
end
if kind == "dotIndex" and node . name ~= nil then
local def = ops . resolve ( node )
if def ~= nil and def . aotOrigin ~= nil then
node . aotOrigin = def . aotOrigin
end
if def ~= nil and def . aotNativeOnly == true and refusing and not insideAot and not allowed [ node ] then
report ( node . name , def )
end
visit ( node . obj , insideAot , allowed , false )
return
end
local inner = insideAot or kind == "funcbody" and node . aotRequired == true
if topLevel then

local exported = kind == "returnStmt" and node . exprs
or kind == "exportStmt" and node . value ~= nil and { node . value }
or nil
if exported ~= nil then
for _ , expr in ipairs ( exported ) do
if expr . kind == "tableExpr" then
for _ , field in ipairs ( expr . fields or { } ) do
if field . value ~= nil then
allowed [ field . value ] = true
end
end
else
allowed [ expr ] = true
end
end
elseif kind == "localStmt" then
for _ , expr in ipairs ( node . exprs or { } ) do
allowed [ expr ] = true
end
elseif kind == "assignStmt" then
for position , target in ipairs ( node . targets or { } ) do
local expr = ( node . exprs or { } ) [ position ]
if target . kind == "dotIndex" and expr ~= nil then
allowed [ expr ] = true
allowed [ target ] = true
end
end
end
end
local statements = kind == "block" and node . stats or nil
for _ , child in ipairs ( node ) do
visit ( child , inner , allowed , statements ~= nil and topLevel )
end
end





function ops . sweep ( root ) 
if root == nil then
return
end
refusing = compiles ( )
for _ , block in ipairs ( root . blocks or { } ) do
visit ( block , false , { } , true )
end
end

return ops
end

local __nuppExportValue= nativeonly ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.nativeonly"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.nativeonly"]=__nuppExports;return __nuppExports