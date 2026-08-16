_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);









local T = require ( "nupp.compiler.types" )
local relations = require ( "nupp.compiler.relations" )

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
if m . tag == "typevar" then
return m
end
if m == T . boolean then
if isA ( T . literal ( false , T . boolean ) , rem ) then
return T . literal ( true , T . boolean )
end
if isA ( T . literal ( true , T . boolean ) , rem ) then
return T . literal ( false , T . boolean )
end
end
if isA ( m , rem ) then
return nil
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
local truthy = narrowing . subtract ( narrowing . subtract ( vt , T . nil_ ) , FALSE_T )
local falsy = { }
if vt == T . nil_ or ( vt . tag == "union" and vt . hasNil ) then
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

return narrowing
