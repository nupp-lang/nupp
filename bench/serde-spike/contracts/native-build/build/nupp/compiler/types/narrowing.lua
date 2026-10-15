_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()











local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.types.relations" )

local narrowing = { }





local isA = ( relations ) . isA























function narrowing . subtract ( t , rem ) 
if t . tag == "affine" then
local inner = narrowing . subtract ( t . inner , rem )
return inner == t . inner and t or T . affine ( inner , t . cleanups , t . transferOnly , t . obligation )
elseif t . tag == "borrowed" then
local inner = narrowing . subtract ( t . inner , rem )
return inner == t . inner and t or T . borrowed ( inner )
elseif t . tag == "pinned" then
local inner = narrowing . subtract ( t . inner , rem )
return inner == t . inner and t or T . pinned ( inner )
end

local function without ( m ) 
if m == T . any or m == T . unknown or m . tag == "typevar" then
return m
end
if isA ( m , rem ) then
return nil
end
if m == T . boolean then
if isA ( T . literal ( false , T . boolean ) , rem ) then
return T . literal ( true , T . boolean )
end
if isA ( T . literal ( true , T . boolean ) , rem ) then
return T . literal ( false , T . boolean )
end
end

return m
end

if t . tag ~= "union" then
return without ( t ) or t
end
local out = { }
local changed = false
for _ , m in ipairs ( t . members ) do
local kept = without ( m )
if kept ~= m then
changed = true
end
if kept then
out [ # out + 1 ] = kept
end
end

if # out == 0 then
return T . never
end
if not changed then
return t
end

return T . union ( out )
end








local RUNTIME_KIND

= {
[ "nil" ] = "nil" ,
string = "string" ,
number = "number" ,
integer = "number" ,
float = "number" ,
int8 = "number" ,
int16 = "number" ,
int32 = "number" ,
int64 = "number" ,
uint8 = "number" ,
uint16 = "number" ,
uint32 = "number" ,
uint64 = "number" ,
boolean = "boolean" ,
thread = "thread" ,
userdata = "userdata" ,
table = "table" ,
array = "table" ,
map = "table" ,
shape = "table" ,
tuple = "table" ,
func = "function" ,
ctype = "cdata" ,
carray = "cdata" ,
ptr = "cdata" ,
}

local function runtimeKind ( t ) 
local bare = T . unwrapOwnership ( t )
if bare . tag == "const" then
bare = ( bare ) . inner
end
if bare . tag == "constrained" then
bare = ( bare ) . base or bare
end
if bare . tag == "literal" then
return bare . base and runtimeKind ( bare . base ) or nil
end
if bare . tag == "nominal" then
local kind = ( bare ) . declKind


return kind == "record" and "table" or kind == "struct" and "cdata" or nil
end

return RUNTIME_KIND [ bare . tag ]
end














function narrowing . overlaps ( a , b ) 
local function alternatives ( t ) 
local bare = T . unwrapOwnership ( t )
return bare . tag == "union" and ( bare ) . members or { bare }
end

local function opaque ( t ) 
local bare = T . unwrapOwnership ( t )
return bare == T . any
or bare == T . unknown
or bare == T . never
or bare . tag == "typevar"
or bare . tag == "neutral"
or bare . tag == "projection"
or bare . tag == "intersection"
or bare . tag == "typeobject"
or bare . tag == "metatable"
or bare . tag == "genericAlias"
end

local function stamped ( t ) 
local bare = T . unwrapOwnership ( t )
return bare . tag == "nominal"
and ( ( bare ) . declKind == "record" or ( bare ) . declKind == "struct" )
and ( bare ) . predicate == nil
end

for _ , m in ipairs ( alternatives ( a ) ) do
for _ , t in ipairs ( alternatives ( b ) ) do
if opaque ( m ) or opaque ( t ) then
return true
end
local mKind , tKind = runtimeKind ( m ) , runtimeKind ( t )
local ruledOutByKind = mKind ~= nil and tKind ~= nil and mKind ~= tKind
if not ruledOutByKind then
if isA ( m , t ) or isA ( t , m ) then
return true
end
if not ( stamped ( m ) and stamped ( t ) ) then
return true
end
end
end
end

return false
end







function narrowing . memberSet ( t ) 
if not t then
return nil
end
if t . tag == "literal" then
return { t }
end
if t . tag == "union" then
local out = { }
for _ , m in ipairs ( t . members ) do
if m . tag ~= "literal" then
return nil
end
out [ # out + 1 ] = m
end
return out
end

return nil
end









function narrowing . withoutMember ( t , litT ) 
local members = narrowing . memberSet ( t )
if not members then
return nil
end
local rest = { }
for _ , m in ipairs ( members ) do
if m ~= litT then
rest [ # rest + 1 ] = m
end
end
if # rest == 0 then
return nil , true
end

return T . union ( rest ) , false
end









function narrowing . truthiness ( vt ) 
if vt == T . any then
return nil , nil
end
if vt == T . nil_ or ( vt . tag == "literal" and vt . constant == false ) then
return nil , vt
end
if vt . tag == "literal" and vt . constant == true then
return vt , nil
end
local FALSE_T = T . literal ( false , T . boolean )


local rest = narrowing . subtract ( vt , T . nil_ )
local truthy = isA ( rest , FALSE_T ) and T . never or narrowing . subtract ( rest , FALSE_T )
local falsy = { }
if vt . tag == "union" and vt . hasNil then
falsy [ # falsy + 1 ] = T . nil_
end
if isA ( FALSE_T , vt ) then
falsy [ # falsy + 1 ] = FALSE_T
end
if # falsy == 0 then
return truthy , nil
end

return truthy , T . union ( falsy )
end

local __nuppExportValue= narrowing ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types.narrowing"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types.narrowing"]=__nuppExports;return __nuppExports