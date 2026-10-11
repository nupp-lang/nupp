_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT7={}; local function __nuppT4(...) return {n=select("#",...),...} end; local __nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT5(value) return value end; local function __nuppT6(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT13({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT14(v.primary) for _,reason in __nuppT15(v.suppressed) do text=text.."\ncleanup: "..__nuppT14(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()local select;__nuppExports["select"]=function(...) return select(...) end;local supports;__nuppExports["supports"]=function(...) return supports(...) end;


local core = require ( "nupp.serde.internal.value" )
local plans = require ( "nupp.serde.internal.json.plan" )
local lowering = require ( "nupp.serde.internal.json.lower" )
local declarations = require ( "nupp.serde.internal.declaration" )
local scalars = require ( "nupp.serde.internal.scalar" )
local structures = require ( "nupp.serde.internal.structure" )
local spi = require ( "nupp.spi" )
local contracts = require ( "nupp.codec.json.spi" )
local provider = spi . select ( spi . load ("nupp.codec.json.spi.Provider") )
local errors = require ( "nupp.serde.internal.errors" )
local diagnostic = require ( "nupp.serde.internal.json.diagnostic" )
local json = require ( "nupp.codec.json" )
local text = require ( "nupp.text" )




local Set = {} Set.__index = Set

function Set:apply(state, value) 

self . set ( state , value )
end

local Field = {} Field.__index = Field






function Field:apply(member, has, get, set, adapter, fallback) 








if self . plan : action ( member ) ~= "traverse" then
return false
end
local child = self . plan : child ( member )
if child == nil then
return false
end
local recipe = self . resolver : resolve ( adapter , child , self . path .. "[" .. json . encode ( member . name ) .. "]" )
if recipe == nil then
return false
end
self . syntax [
# self . syntax + 1
] = {
name = member . name ,
wire = assert ( self . plan : wireName ( member ) ) ,
target = recipe . syntax ,
required = self . required ,
hasDefault = false
}
self . setters [ # self . setters + 1 ] = _G.setmetatable({ set =  set }, Set)

return true
end

local Construct = {} Construct.__index = Construct


function Construct:apply(values) 
do local __nuppT16=0; local  __nuppT22 ; local __nuppT23=false ; local __nuppT17,__nuppT18,__nuppT19=__nuppT9(function() do local __nuppT24= self . construction : begin ( ) ; __nuppT22= __nuppT24 ; __nuppT16=1;  __nuppT23=true;  local state=__nuppT22;
for index , setter in ipairs ( self . setters ) do
local value = values [ index ]
if value ~= nil then
setter : apply ( state , value )
end
end

return "return",__nuppT4( (function(__nuppT25,...)  __nuppT23=false; return __nuppT25:finish(...)  end)( self . construction , state ) ) end; return "normal" end,__nuppT5); local __nuppT20={}; local __nuppT21=0; if __nuppT16>=1 and __nuppT23 then  local __nuppT26,__nuppT27=__nuppT8(__nuppCleanup1,__nuppT22);  if not __nuppT26 then __nuppT21=__nuppT21+1; __nuppT20[__nuppT21]=__nuppT27 end; end; if not __nuppT17 then if __nuppT21>0 then __nuppT10(__nuppT6(__nuppT18,__nuppT20,1),0) else __nuppT10(__nuppT18,0) end end; if __nuppT21>0 then if __nuppT21>1 then __nuppT10(__nuppT6(__nuppT20[1],__nuppT20,2),0) else __nuppT10(__nuppT20[1],0) end end; if __nuppT18=="return" then  return __nuppT11(__nuppT19,1,__nuppT19.n)  end; end
end

local Structure = {} Structure.__index = Structure



function Structure:apply(member, fields, construction, unknown, additional) 







if additional ~= nil or not structures . rejectsUnknown ( unknown ) or # fields > 64 then
return nil
end
local syntax = { }
local setters = { }
for _ , field in ipairs ( fields ) do
if not field : accept (
_G.setmetatable({ resolver =
self . resolver ,  plan =
self . plan ,  path =
self . path ,  syntax =
syntax ,  setters =
setters ,  required =
field . required }, Field)

) then
return nil
end
end
local constructor = _G.setmetatable({ construction =  construction ,  setters =  setters }, Construct)
local invoke = function ( values ) 
return constructor : apply ( values )
end

return ( _G.setmetatable({ syntax =  {
kind = "structure" ,
access = "dynamic" ,
fields = syntax ,
factory = function ( values ) 
local ok , result = pcall ( invoke , values )
if not ok then
error ( errors . wrap ( result , self . path , nil ) , 0 )
end

return result
end
} }, lowering.Recipe) )
end

local Resolver = {} Resolver.__index = Resolver


function Resolver:resolve(adapter, plan, path) 
if self . active [ adapter ] or plan . description . nullable or self . depth >= 128 then
return nil
end
self . active [ adapter ] = true
self . depth += 1
local recipe = declarations . nativeRecipe ( adapter , plan , self , path )
if recipe == nil then
local scalar = scalars . nativeScalar ( adapter )
if scalar ~= nil then
recipe = _G.setmetatable({ syntax =  { kind = scalar } }, lowering.Recipe)
elseif structures . canDefer ( adapter ) then
recipe = structures . inspect ( adapter , _G.setmetatable({ resolver =  self ,  plan =  plan ,  path =  path }, Structure) )
end
end
self . active [ adapter ] = nil
self . depth -= 1

return recipe
end








local Native = {} Native.__index = Native




function Native:acceptsBuffer(input) 
return self . invokeBuffer ~= nil and # input <= 1000000
end

function Native:decodeBuffer(input) 
assert ( self : acceptsBuffer ( input ) , "compiled buffer input exceeds its execution capability" )
local invoke = assert ( self . invokeBuffer )
local ok , value , problem = pcall ( invoke , self . schema , input )
if not ok then
error ( diagnostic . explain ( self . syntax , input : tostring ( ) , value ) , 0 )
end
if problem ~= nil then
error ( diagnostic . explain ( self . syntax , input : tostring ( ) , problem ) , 0 )
end

return value
end

function Native:accepts(bytes) 



return # bytes <= 1000000
end

function Native:decode(bytes) 
assert ( self : accepts ( bytes ) , "compiled input exceeds its execution capability" )
local ok , value , problem = pcall ( self . invoke , self . schema , bytes )
if not ok then
error ( diagnostic . explain ( self . syntax , bytes , value ) , 0 )
end
if problem ~= nil then
error ( diagnostic . explain ( self . syntax , bytes , problem ) , 0 )
end

return value
end


select=function (
adapter ,
plan ,
backend
) 
local selected = backend or provider
if selected == nil then
return nil
end
local compile , decode = selected . compileSerde , selected . decodeSerde
if compile == nil or decode == nil then
return nil
end
local recipe = ( _G.setmetatable({ active =  {} ,  depth =  0 }, Resolver) ) : resolve ( adapter , plan , "$" )
if recipe == nil then
return nil
end
recipe . syntax . deferRoot = true
local schema = compile ( recipe . syntax , "reject" )
if not schema . complete then
return nil
end

return ( _G.setmetatable({ schema =
schema ,  syntax =
recipe . syntax ,  invoke =
decode ,  invokeBuffer =
selected . decodeSerdeBuffer }, Native) )

end ;__nuppExports["select"]=select


supports=function ( adapter , plan ) 
return ( _G.setmetatable({ active =  {} ,  depth =  0 }, Resolver) ) : resolve ( adapter , plan , "$" ) ~= nil
end ;__nuppExports["supports"]=supports
 end);if not __nuppOk then package.loaded["nupp.serde.internal.json.compiled"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.json.compiled"]=__nuppExports;return __nuppExports