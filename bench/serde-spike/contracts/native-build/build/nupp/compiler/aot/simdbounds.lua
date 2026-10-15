_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local scalarIR = require ( "nupp.compiler.aot.scalar" )
local simdbounds = { }


function simdbounds . lanes ( value ) 
if value . op == "simd_lanes_generic" then
return ( value ) . args [ 1 ] , 1
elseif value . op == "u32_mul" then
local product = value
local lane , factor = product . left , product . right
if factor . op == "simd_lanes_generic" then
lane , factor = factor , lane
end
local count = factor . op == "constant_i32"
and factor . type == "u32"
and tonumber ( ( factor ) . value )
or nil
if lane . op == "simd_lanes_generic"
and count ~= nil
and count >= 1
and count <= 4294967295
and count % 1 == 0
then
return ( lane ) . args [ 1 ] , count
end
end

return nil , nil
end

function simdbounds . room ( species , count ) 
return count == 1 and species or species .. "@" .. tostring ( count )
end

function simdbounds . covers ( room , species , count ) 
if room == nil then
return false
end
local held , multiple = ( room ) : match ( "^(.+)@(%d+)$" )
held = held or room
local available = tonumber ( multiple ) or 1
local lanes = held : match ( "_fixed(%d+)$" )

return ( held == species or lanes ~= nil and species : match ( "_fixed(%d+)$" ) == lanes ) and available >= ( count or 1 )
end


function simdbounds . elementRoom ( room ) 
return room : match ( "^%d+$" ) ~= nil
end





function simdbounds . elements ( room ) 
if room == nil then
return 0
end
local held = room
if simdbounds . elementRoom ( held ) then
return tonumber ( held ) or 0
end
local species , multiple = held : match ( "^(.+)@(%d+)$" )
species = species or held
local lanes = tonumber ( species : match ( "_fixed(%d+)$" ) ) or 1

return lanes * ( tonumber ( multiple ) or 1 )
end






function simdbounds . widen ( existing , room ) 
if existing == nil then
return room
end
local held = existing
local heldElements , roomElements = simdbounds . elements ( held ) , simdbounds . elements ( room )
local heldVector , roomVector = not simdbounds . elementRoom ( held ) , not simdbounds . elementRoom ( room )
if heldVector and roomVector then
return room
elseif heldVector then
return heldElements >= roomElements and held or room
elseif roomVector then
return roomElements >= heldElements and room or held
end

return roomElements >= heldElements and room or held
end






function simdbounds . reach (
bounds ,
cursor ,
counted ,
related ,
transfers
) 
local spans = bounds [ cursor ]
if spans == nil or counted == nil then
return 0
end
local most = simdbounds . elements ( spans [ counted ] )
for root , room in pairs ( spans ) do
local held = simdbounds . elements ( room )
local reaches = related ~= nil and ( related ) [ root ] or nil
if reaches ~= nil and reaches [ counted ] == true then
most = math . max ( most , held )
end
local carried = transfers ~= nil and ( transfers ) [ root ] or nil
for _ , transfer in ipairs ( carried ~= nil and carried [ counted ] or { } ) do
most = math . max ( most , transfer . factor * held - transfer . offset )
end
end

return most
end



function simdbounds . boundedThrough (
bounds ,
cursor ,
counted ,
related ,
count ,
transfers
) 
return simdbounds . reach ( bounds , cursor , counted , related , transfers ) >= ( count or 1 )
end






function simdbounds . coveredThrough (
bounds ,
cursor ,
counted ,
related ,
species ,
count
) 
local spans = bounds [ cursor ]
if spans == nil or counted == nil then
return false
end
if simdbounds . covers ( spans [ counted ] , species , count ) then
return true
end
for root , room in pairs ( spans ) do
local reaches = related ~= nil and ( related ) [ root ] or nil
if reaches ~= nil and reaches [ counted ] == true and simdbounds . covers ( room , species , count ) then
return true
end
end

return false
end

local WAYS

= { load_pairs = 2 , load_triples = 3 , load_quads = 4 , store_pairs = 2 , store_triples = 3 , store_quads = 4 , }



function simdbounds . ways ( intrinsic ) 
return intrinsic ~= nil and WAYS [ intrinsic ] or 1
end


function simdbounds . interleaved ( intrinsic ) 
return intrinsic ~= nil and WAYS [ intrinsic ] ~= nil
end


function simdbounds . cursor ( value ) 
if value . type == "u32" and ( value . op == "local" or value . op == "uniform" or value . op == "helper_param" ) then
return value
end
return nil
end


function simdbounds . offset ( value ) 
if value . op == "int_to_f64" then
value = ( value ) . value
end
if value . op ~= "u32_add" then
return nil , nil , nil
end
local added = value
local one = added . right
if one . op ~= "constant_i32" or one . type ~= "u32" or tonumber ( ( one ) . value ) ~= 1 then
return nil , nil , nil
end
local base = added . left
local named = simdbounds . cursor ( base )
if named ~= nil then
return named , nil , 0
elseif base . op == "u32_add" then
local displaced = base
local species , count = simdbounds . lanes ( displaced . right )
local cursor = simdbounds . cursor ( displaced . left )
if cursor ~= nil and species ~= nil then
return cursor , ( species ) . type , count
end
end

return nil , nil , nil
end

local __nuppExportValue= simdbounds ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.simdbounds"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.simdbounds"]=__nuppExports;return __nuppExports