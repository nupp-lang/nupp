_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()














local T = require ( "nupp.compiler.types" )
local predicate = require ( "nupp.compiler.types.predicate" )

local constrain = { }

local MAX_EXACT_INTEGER = 9007199254740991






local RANGE_DOMAIN

= { integer = { -9007199254740991 , 9007199254740991 } , int32 = { -2147483648 , 2147483647 } , uint32 = { 0 , 4294967295 } , }




function constrain . admits ( base , lengthwise ) 
local underlying = T . unconstrained ( base )
if lengthwise then
if underlying ~= T . string then
return false , ("a length constraint needs a string base, got %s") : format ( T . tostring ( base ) )
end
return true
end
if not RANGE_DOMAIN [ underlying . tag ] then
return false , ("a range constraint needs an integer, int32 or uint32 base, got %s") : format ( T . tostring ( base ) )
end

return true
end













function constrain . build ( base , low , high , lengthwise ) 
local admissible , why = constrain . admits ( base , lengthwise )
if not admissible then
return nil , why
end
local underlying = T . unconstrained ( base )
if low % 1 ~= 0 or high % 1 ~= 0 or math . abs ( low ) > 9007199254740991 or math . abs ( high ) > 9007199254740991 then
return nil , "a bound must be an exact integer"
end
if low > high then
return nil , ("the bounds %d..%d are in descending order") : format ( low , high )
end
local limits = RANGE_DOMAIN [ underlying . tag ]
local floor = lengthwise and 0 or ( limits ) [ 1 ]
local ceiling = lengthwise and math . huge or ( limits ) [ 2 ]
if low < floor or high > ceiling then
return nil , ("the bounds %d..%d leave what %s admits") : format ( low , high , T . tostring ( underlying ) )
end
local comparison = _G.setmetatable({ op =
"and" ,  a =
_G.setmetatable({ op =  "cmp" ,  cmp =  ">=" ,  path =  { } ,  literal =  tostring ( low ) ,  constant =  low }, predicate.Node) ,  b =
_G.setmetatable({ op =  "cmp" ,  cmp =  "<=" ,  path =  { } ,  literal =  tostring ( high ) ,  constant =  high }, predicate.Node) }, predicate.Node)

local node = lengthwise and _G.setmetatable({ op =  "len" ,  path =  { } ,  a =  comparison }, predicate.Node) or comparison
if not lengthwise then



node = _G.setmetatable({ op =  "and" ,  a =  _G.setmetatable({ op =  "integral" ,  path =  { } }, predicate.Node) ,  b =  node }, predicate.Node)
end
local existing = T . constraintOf ( base )
if existing then
if predicate . disjoint ( existing , node ) then
return nil , ("%d..%d admits nothing %s does") : format ( low , high , T . tostring ( base ) )
end
node = _G.setmetatable({ op =  "and" ,  a =  existing ,  b =  node }, predicate.Node)
end
local normalized = predicate . normalize ( node )

return T . constrained ( underlying , normalized , predicate . key ( normalized ) )
end

local __nuppExportValue= constrain ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.types.constrain"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.types.constrain"]=__nuppExports;return __nuppExports