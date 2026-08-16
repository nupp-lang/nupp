_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local m=__nuppMath;local pi,tau=math.pi,2*math.pi function m.lerp(from,to,t)if t==0 then return from elseif t==1 then return to end;return from+(to-from)*t end function m.wrapAngle(radians)return(radians+pi)%tau-pi end function m.deltaAngle(from,to)return m.wrapAngle(to-from)end local b=bit;local function ui32(x)x=b.tobit(x);return x<0 and x+4294967296 or x end local function mul32(a,c)local al,cl=a%65536,c%65536;local ah,ch=math.floor(a/65536),math.floor(c/65536);return b.tobit(al*cl+((ah*cl+al*ch)%65536)*65536)end local i32,u32={},{};m.i32=i32;m.u32=u32 function i32.wrap(a)return b.tobit(a)end;function u32.wrap(a)return ui32(a)end function i32.add(a,c)return b.tobit(a+c)end;function i32.sub(a,c)return b.tobit(a-c)end;function i32.mul(a,c)return mul32(ui32(a),ui32(c))end function i32.andBits(a,c)return b.band(a,c)end;function i32.orBits(a,c)return b.bor(a,c)end;function i32.xorBits(a,c)return b.bxor(a,c)end;function i32.notBits(a)return b.bnot(a)end function i32.shiftLeft(a,c)return b.lshift(a,b.band(c,31))end;function i32.shiftRightArithmetic(a,c)return b.arshift(a,b.band(c,31))end function i32.rotateLeft(a,c)return b.rol(a,b.band(c,31))end;function i32.rotateRight(a,c)return b.ror(a,b.band(c,31))end function i32.lessThan(a,c)return b.tobit(a)<b.tobit(c)end;function i32.lessOrEqual(a,c)return b.tobit(a)<=b.tobit(c)end function i32.fromU32(a)return b.tobit(a)end;function i32.toU32(a)return ui32(a)end function u32.add(a,c)return ui32(a+c)end;function u32.sub(a,c)return ui32(a-c)end;function u32.mul(a,c)return ui32(mul32(ui32(a),ui32(c)))end function u32.andBits(a,c)return ui32(b.band(a,c))end;function u32.orBits(a,c)return ui32(b.bor(a,c))end;function u32.xorBits(a,c)return ui32(b.bxor(a,c))end;function u32.notBits(a)return ui32(b.bnot(a))end function u32.shiftLeft(a,c)return ui32(b.lshift(a,b.band(c,31)))end;function u32.shiftRightLogical(a,c)return ui32(b.rshift(a,b.band(c,31)))end function u32.rotateLeft(a,c)return ui32(b.rol(a,b.band(c,31)))end;function u32.rotateRight(a,c)return ui32(b.ror(a,b.band(c,31)))end function u32.lessThan(a,c)return ui32(a)<ui32(c)end;function u32.lessOrEqual(a,c)return ui32(a)<=ui32(c)end function u32.fromI32(a)return ui32(a)end;function u32.toI32(a)return b.tobit(a)end local ffi=require("ffi");local fh=ffi.new("union {float f;uint32_t u;}[1]");local f32={};m.f32=f32 local CANON=2143289344;local PINF=2139095040;local NINF=4286578688;local MAX=2139095039;local NMAX=4286578687 local function nanbits(bits)return b.band(bits,2139095040)==2139095040 and b.band(bits,8388607)~=0 end local function putbits(bits)if nanbits(bits)then bits=CANON end;fh[0].u=bits;return tonumber(fh[0].f)end local function bits32(value)fh[0].f=value;local bits=tonumber(fh[0].u);if nanbits(bits)then bits=CANON;fh[0].u=bits end;return bits end local function round32(value)fh[0].f=value;local bits=tonumber(fh[0].u);if nanbits(bits)then fh[0].u=CANON end;return tonumber(fh[0].f)end local function narrow32(value)fh[0].f=value;return tonumber(fh[0].f)end local function comparedd(hi,lo,value)local d=hi-value;if d>-lo then return 1 elseif d<-lo then return-1 end;return 0 end local function nextup(value,bits)if bits==PINF then return value,bits end;if bits==NINF then return putbits(NMAX),NMAX end;if b.band(bits,2147483648)~=0 then if bits==2147483648 then return putbits(1),1 end;bits=bits-1 else bits=bits+1 end;return putbits(bits),bits end local function nextdown(value,bits)if bits==NINF then return value,bits end;if bits==PINF then return putbits(MAX),MAX end;if b.band(bits,2147483648)~=0 then bits=bits+1 else if bits==0 then return putbits(2147483649),2147483649 end;bits=bits-1 end;return putbits(bits),bits end local function rounddd(hi,lo)local value=round32(hi);local bits=bits32(value);if nanbits(bits)then return putbits(CANON)end;if bits==PINF then local threshold=3.4028235677973366e38;if comparedd(hi,lo,threshold)<0 then return putbits(MAX)end;return value elseif bits==NINF then local threshold=-3.4028235677973366e38;if comparedd(hi,lo,threshold)>0 then return putbits(NMAX)end;return value end;local side=comparedd(hi,lo,value);if side==0 then return value end;local other,otherbits;if side>0 then other,otherbits=nextup(value,bits)else other,otherbits=nextdown(value,bits)end;local midpoint=(value+other)*0.5;local toward=comparedd(hi,lo,midpoint);if side<0 then toward=-toward end;if toward>0 or toward==0 and b.band(bits,1)~=0 then return putbits(otherbits)end;return value end function f32.narrow(a)return narrow32(a)end;function f32.round(a)return round32(a)end;function f32.add(a,c)return round32(round32(a)+round32(c))end;function f32.sub(a,c)return round32(round32(a)-round32(c))end;function f32.mul(a,c)return round32(round32(a)*round32(c))end;function f32.div(a,c)return round32(round32(a)/round32(c))end;function f32.sqrt(a)return round32(math.sqrt(round32(a)))end function f32.min(a,c)a,c=round32(a),round32(c);if a~=a or c~=c then return putbits(CANON)end;if a==c then local ab,cb=bits32(a),bits32(c);if a==0 and(b.band(ab,2147483648)~=0 or b.band(cb,2147483648)~=0)then return putbits(2147483648)end;return a end;return a<c and a or c end function f32.max(a,c)a,c=round32(a),round32(c);if a~=a or c~=c then return putbits(CANON)end;if a==c then local ab,cb=bits32(a),bits32(c);if a==0 and b.band(ab,2147483648)~=0 and b.band(cb,2147483648)~=0 then return putbits(2147483648)elseif a==0 then return putbits(0)end;return a end;return a>c and a or c end function f32.fma(a,c,d)a,c,d=round32(a),round32(c),round32(d);local product=a*c;if product~=product or product==math.huge or product==-math.huge then return round32(product+d)end;local sum=product+d;local carry=sum-product;local error=(product-(sum-carry))+(d-carry);return rounddd(sum,error)end function f32.fromBits(bits)return putbits(ui32(bits))end;function f32.toBits(value)return bits32(round32(value))end local v={};m.vec2=v function v.add(ax,ay,bx,by)return ax+bx,ay+by end function v.subtract(ax,ay,bx,by)return ax-bx,ay-by end function v.scale(x,y,f)return x*f,y*f end function v.dot(ax,ay,bx,by)return ax*bx+ay*by end function v.cross(ax,ay,bx,by)return ax*by-ay*bx end function v.lengthSquared(x,y)return x*x+y*y end function v.length(x,y)return math.sqrt(x*x+y*y)end function v.distanceSquared(ax,ay,bx,by)local x,y=bx-ax,by-ay;return x*x+y*y end function v.distance(ax,ay,bx,by)return math.sqrt(v.distanceSquared(ax,ay,bx,by))end function v.normalize(x,y)local length=v.length(x,y);if length==0 then return 0,0 end;return x/length,y/length end function v.lerp(ax,ay,bx,by,t)if t==0 then return ax,ay elseif t==1 then return bx,by end;return ax+(bx-ax)*t,ay+(by-ay)*t end function v.moveTowards(ax,ay,bx,by,d)if d<=0 then return ax,ay end;local x,y=bx-ax,by-ay;local squared=x*x+y*y;if squared==0 or squared<=d*d then return bx,by end;local f=d/math.sqrt(squared);return ax+x*f,ay+y*f end function v.rotate(x,y,r)local c,s=math.cos(r),math.sin(r);return x*c-y*s,x*s+y*c end function v.angle(x,y)if x==0 and y==0 then return 0 end;return math.atan2(y,x)end function v.angleBetween(ax,ay,bx,by)if(ax==0 and ay==0)or(bx==0 and by==0)then return 0 end;return math.atan2(math.abs(v.cross(ax,ay,bx,by)),v.dot(ax,ay,bx,by))end function v.signedAngleBetween(ax,ay,bx,by)if(ax==0 and ay==0)or(bx==0 and by==0)then return 0 end;local a=math.atan2(v.cross(ax,ay,bx,by),v.dot(ax,ay,bx,by));return a==pi and-pi or a end function v.project(x,y,ox,oy)local d=ox*ox+oy*oy;if d==0 then return 0,0 end;local f=(x*ox+y*oy)/d;return ox*f,oy*f end function v.reflect(x,y,nx,ny)local d=nx*nx+ny*ny;if d==0 then return x,y end;local f=2*(x*nx+y*ny)/d;return x-nx*f,y-ny*f end;


















local lane = require ( "nupp.compiler.aot.lane" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )

local rewrite = { }





rewrite.State = {} rewrite.State.__index = rewrite.State































rewrite . ELEMENTS = { [ "f64" ] = true , [ "f32" ] = true , [ "i32" ] = true , [ "u32" ] = true , [ "bool" ] = true , }


function rewrite . asElement ( scalarType )
if rewrite . ELEMENTS [ scalarType ] == true then
return scalarType
end

return nil
end







function rewrite . constantFits ( node , element )
if node . op ~= "constant" then
return false
end
local number = tonumber ( ( node ) . value )
if number == nil then
return false
elseif element == "i32" then
return number % 1 == 0 and number >= - 2147483648 and number <= 2147483647
elseif element == "f32" then



return nupp . math . f32 . narrow ( number ) == number
end

return element == "f64"
end



function rewrite . vectorFor ( state , element )
return state . shape . vectorFor [ element ]
end






function rewrite . carriesExactly ( state , element )
return state . shape . vectorFor [ element ] == element .. "x" .. tostring ( state . shape . lanes )
end







function rewrite . comparisonElement ( left , right )
local leftElement = rewrite . asElement ( left . type )
local rightElement = rewrite . asElement ( right . type )
if leftElement == nil or rightElement == nil then
return "f64"
elseif leftElement == rightElement then
return leftElement
elseif rewrite . constantFits ( right , leftElement ) then
return leftElement
elseif rewrite . constantFits ( left , rightElement ) then
return rightElement
end

return "f64"
end









rewrite . ARITHMETIC = { [ "add" ] = "add" , [ "sub" ] = "sub" , [ "mul" ] = "mul" , [ "div" ] = "div" , }

rewrite . COMPARISON = { [ "lt" ] = "lt" , [ "le" ] = "le" , [ "gt" ] = "gt" , [ "ge" ] = "ge" , [ "eq" ] = "eq" , [ "ne" ] = "ne" , }


rewrite . BITWISE = {
[ "band" ] = "and" ,
[ "bor" ] = "or" ,
[ "bxor" ] = "xor" ,
[ "bnot" ] = "not" ,
[ "lshift" ] = "shl" ,
[ "rshift" ] = "shr" ,
[ "arshift" ] = "sar" ,
}


rewrite . FIXED = {
[ "f32_add" ] = { verb = "add" , element = "f32" } ,
[ "f32_sub" ] = { verb = "sub" , element = "f32" } ,
[ "f32_mul" ] = { verb = "mul" , element = "f32" } ,
[ "f32_div" ] = { verb = "div" , element = "f32" } ,
[ "i32_add" ] = { verb = "add" , element = "i32" } ,
[ "i32_sub" ] = { verb = "sub" , element = "i32" } ,
[ "i32_mul" ] = { verb = "mul" , element = "i32" } ,
}



rewrite . CORRECTED = {
[ "f32_min" ] = { helper = "nupp_f32_min" , arity = 2 } ,
[ "f32_max" ] = { helper = "nupp_f32_max" , arity = 2 } ,
[ "f32_fma" ] = { helper = "nupp_f32_fma" , arity = 3 } ,
}






function rewrite . varying ( node , state )
if node == nil then
return false
end
local operation = node . op
if operation == "element_ref" or operation == "load" then
return ( node ) . index == state . index
elseif operation == "local" then
local name = ( node ) . name

return state . varyingLocals [ name ] == true or state . refBindings [ name ] ~= nil
elseif operation == "helper_param" then
return state . helperBindings [ ( node ) . name ] ~= nil
elseif operation == "uniform" or operation == "constant" or operation == "constant_i32" or operation == "bool" then
return false
elseif operation == "field_load" then
return rewrite . varying ( ( node ) . object , state )
end


local binary = node
if binary . left ~= nil or binary . right ~= nil then
return rewrite . varying ( binary . left , state ) or rewrite . varying ( binary . right , state )
end
local unary = node
if unary . value ~= nil then
return rewrite . varying ( unary . value , state )
end
for _ , argument in ipairs ( ( node ) . args or { } ) do
if rewrite . varying ( argument , state ) then
return true
end
end

return false
end







local function asElement ( node , element , state )
if node . type == element then
return node
end
if element == "f64" then
if node . type == "f32" then
return setmetatable({ op =  "widen_f32_f64" ,  value =  node ,  type =  "f64" ,  source =  node . source }, scalarIR.Convert)
elseif node . type == "i32" or node . type == "u32" then
return setmetatable({ op =  "int_to_f64" ,  value =  node ,  type =  "f64" ,  source =  node . source }, scalarIR.Convert)
end
end
if element == "i32" and node . type == "u32" then
return node
end

if rewrite . constantFits ( node , element ) then
if element == "i32" then
return setmetatable({ op =
"constant_i32" ,  value =
( node ) . value ,  type =
"i32" ,  source =
node . source }, scalarIR.IntConstant)

else
return setmetatable({ op =  "narrow_f64_f32" ,  value =  node ,  type =  "f32" ,  source =  node . source }, scalarIR.Convert)
end
end
state . reject ( "a uniform " .. tostring ( node . type ) .. " cannot enter " .. state . shape . name )

return node
end


local function elementOf ( vector )
return ( vector : match ( "^(%a%d+)x" ) or "f64" )
end


function rewrite . splat ( node , scalarType , state )
local vector = state . shape . vectorFor [ scalarType ]
if vector == nil or vector == state . shape . mask then
state . reject ( "a uniform " .. tostring ( node . type ) .. " cannot enter " .. state . shape . name )
end
local element = elementOf ( vector )

return setmetatable({ op =
"vsplat" ,  args =
{ asElement ( node , element , state ) } ,  element =
element ,  type =
vector ,  source =
node . source }, lane.Splat)

end





local function resolveRef ( node , state )
if node == nil then
return nil
elseif node . op == "element_ref" then
return node
elseif node . op == "local" then
return state . refBindings [ ( node ) . name ]
end

return nil
end


local expression

local numericVector
local conditionMask
local inlineHelper


numericVector = function ( node , want , state )
local vector = state . shape . vectorFor [ want ]
if rewrite . varying ( node , state ) then
local value = expression ( node , state )
if value . type ~= vector then
state . reject ( "a varying " .. tostring ( node . type ) .. " cannot enter " .. tostring ( vector ) .. " SIMD" )
end

return value
end

return rewrite . splat ( node , want , state )
end


conditionMask = function ( node , state )
if rewrite . varying ( node , state ) then
local value = expression ( node , state )
if value . type ~= state . shape . mask then
state . reject ( "a varying condition did not produce a mask" )
end

return value
end

return setmetatable({ op =  "vbool_splat" ,  args =  { node } ,  type =  state . shape . mask ,  source =  node . source }, lane.BoolSplat)
end








inlineHelper = function ( node , state )
local helper = state . helpers [ node . helper ]
if helper == nil then
state . reject ( "a lane-parallel call has no visible helper" )

return { }
end
if # node . args ~= # helper . params then
state . reject ( "a lane-parallel helper call has the wrong argument count" )
end
local bound , saved = { } , { }
for position , parameter in ipairs ( helper . params ) do
bound [ parameter . name ] = numericVector ( node . args [ position ] , parameter . type , state )
end
for name , value in pairs ( bound ) do
saved [ name ] = state . helperBindings [ name ]
state . helperBindings [ name ] = value
end
local values = { }
for position , value in ipairs ( helper . values ) do
values [ position ] = expression ( value , state )
end
for name in pairs ( bound ) do
state . helperBindings [ name ] = saved [ name ]
end

return values
end


expression = function ( node , state )
if not rewrite . varying ( node , state ) then
return node
end
local shape = state . shape
local mask = shape . mask
local operation = node . op

if operation == "local" then
local name = node
local vector = shape . vectorFor [ rewrite . asElement ( node . type ) or "bool" ]
if vector == nil then
state . reject ( "a varying local of a type no lane carries" )
end

return setmetatable({ op =
"local" ,  name =
name . name ,  cName =
name . cName or "" ,  type =
vector ,  source =
node . source }, lane.Local)

elseif operation == "field_load" then
local field = node
local object = resolveRef ( field . object , state )
if object == nil or object . index ~= state . index then
state . reject ( "a lane-parallel field load reads consecutive elements only" )
end



local element = rewrite . asElement ( node . type )
local vector = element ~= nil and shape . vectorFor [ element ] or nil
if vector == nil then
state . reject ( "a " .. tostring ( node . type ) .. " field cannot enter " .. shape . name )
end

return setmetatable({ op =
"vfield_load" ,  span =
object . span ,  layout =
object . layout ,  field =
field . field ,  lanes =
shape . lanes ,  scalarType =
element ,  type =
vector ,  source =
node . source }, lane.FieldLoad)

elseif operation == "widen_f32_f64" or operation == "int_to_f64" then



return expression ( ( node ) . value , state )
elseif operation == "numeric_cast" or operation == "narrow_f64_f32" then


return expression ( ( node ) . value , state )
elseif operation == "helper_param" then
local bound = state . helperBindings [ ( node ) . name ]
if bound == nil then
state . reject ( "a helper parameter escaped its call" )
end

return bound
elseif operation == "helper_call" then
local inlined = inlineHelper ( node , state )
if # inlined ~= 1 then
state . reject ( "a multiple-result helper is not one value" )
end

return inlined [ 1 ]
elseif operation == "and" or operation == "or" then




local binary = node

return setmetatable({ op =
"vshort" ,  verb =
operation == "and" and "and" or "or" ,  args =
{ conditionMask ( binary . left , state ) , conditionMask ( binary . right , state ) } ,  effect =
"pure_total" ,  type =
mask ,  source =
node . source }, lane.ShortCircuit)

elseif operation == "not" then
return setmetatable({ op =
"vmask" ,  verb =
"not" ,  args =
{ expression ( ( node ) . value , state ) } ,  type =
mask ,  source =
node . source }, lane.MaskOp)

end

return rewrite . arithmetic ( node , state )
end





function rewrite . arithmetic ( node , state )
local shape = state . shape
local operation = node . op
local binary = node

local fixed = rewrite . FIXED [ operation ]
if fixed ~= nil then




if not rewrite . carriesExactly ( state , fixed . element ) then
state . reject (
"an explicit "
.. fixed . element
.. " operation needs "
.. fixed . element
.. " lanes, and "
.. shape . name
.. " has none"
)
end

return setmetatable({ op =
"vbinary" ,  verb =
fixed . verb ,  element =
fixed . element ,  args =
{
numericVector ( binary . left , fixed . element , state ) ,
numericVector ( binary . right , fixed . element , state ) ,
} ,  type =
shape . vectorFor [ fixed . element ] ,  source =
node . source }, lane.Binary)

end

local corrected = rewrite . CORRECTED [ operation ]
if corrected ~= nil then
if not rewrite . carriesExactly ( state , "f32" ) then
state . reject ( "an explicit f32 operation needs f32 lanes, and " .. shape . name .. " has none" )
end
local args = { }
if corrected . arity == 3 then
for position , argument in ipairs ( ( node ) . args or { } ) do
args [ position ] = numericVector ( argument , "f32" , state )
end
else
args [ 1 ] = numericVector ( binary . left , "f32" , state )
args [ 2 ] = numericVector ( binary . right , "f32" , state )
end

return setmetatable({ op =
"vcorrected" ,  helper =
corrected . helper ,  args =
args ,  element =
"f32" ,  type =
shape . vectorFor [ "f32" ] ,  source =
node . source }, lane.Corrected)

end

local bitwise = rewrite . BITWISE [ operation ]
if bitwise ~= nil then
return rewrite . bitwise ( node , bitwise , state )
end

if operation == "math" then
local args = { }
for position , argument in ipairs ( ( node ) . args ) do
args [ position ] = numericVector ( argument , "f64" , state )
end

return setmetatable({ op =
"vmath" ,  intrinsic =
( node ) . intrinsic ,  args =
args ,  type =
shape . vectorFor [ "f64" ] ,  source =
node . source }, lane.Math)

elseif operation == "neg" then
local element = rewrite . asElement ( node . type ) or "f64"

return setmetatable({ op =
"vunary" ,  verb =
"neg" ,  element =
element ,  args =
{ numericVector ( ( node ) . value , element , state ) } ,  type =
shape . vectorFor [ element ] ,  source =
node . source }, lane.Unary)

elseif operation == "f32_sqrt" then
return setmetatable({ op =
"vunary" ,  verb =
"sqrt" ,  element =
"f32" ,  args =
{ numericVector ( ( node ) . value , "f32" , state ) } ,  type =
shape . vectorFor [ "f32" ] ,  source =
node . source }, lane.Unary)

end

local verb = rewrite . ARITHMETIC [ operation ]
if verb ~= nil then


local element = rewrite . asElement ( node . type ) or "f64"

return setmetatable({ op =
"vbinary" ,  verb =
verb ,  element =
element ,  args =
{ numericVector ( binary . left , element , state ) , numericVector ( binary . right , element , state ) , } ,  type =
shape . vectorFor [ element ] ,  source =
node . source }, lane.Binary)

end

local comparison = rewrite . COMPARISON [ operation ]
if comparison ~= nil then


local element = rewrite . comparisonElement ( binary . left , binary . right )

return setmetatable({ op =
"vbinary" ,  verb =
comparison ,  element =
element ,  args =
{ numericVector ( binary . left , element , state ) , numericVector ( binary . right , element , state ) , } ,  type =
shape . mask ,  source =
node . source }, lane.Binary)

end

state . reject ( "operation " .. tostring ( operation ) .. " has no lane-parallel form" )

return node
end






function rewrite . bitwise (
node ,
verb ,
state
)
local shape = state . shape
local bits = shape . bits
local binary = node

local function asBits ( operand )
local want = operand . type == "f64" and "f64" or "i32"
local vector = numericVector ( operand , want , state )
if vector . type == bits then
return vector
end

return setmetatable({ op =  "vbits" ,  direction =  "to" ,  args =  { vector } ,  type =  bits ,  source =  node . source }, lane.BitConvert)
end

local args = { asBits ( binary . left ) }
if binary . right ~= nil then
args [ 2 ] = asBits ( binary . right )
end
local computed = setmetatable({ op =  "vbitwise" ,  verb =  verb ,  args =  args ,  type =  bits ,  source =  node . source }, lane.Bitwise)
local carrier = shape . vectorFor [ "i32" ]
if carrier == bits then
return computed
end

return setmetatable({ op =
"vbits" ,  direction =
"from" ,  args =
{ computed } ,  type =
carrier ,  source =
node . source }, lane.BitConvert)

end










function rewrite . expression ( node , state )
return expression ( node , state )
end


rewrite.Binding = {} rewrite.Binding.__index = rewrite.Binding













rewrite.LoopContext = {} rewrite.LoopContext.__index = rewrite.LoopContext
















function rewrite . maskLocal ( binding , source , state )
return setmetatable({ op =
"local" ,  name =
binding . name ,  cName =
binding . cName ,  type =
state . shape . mask ,  source =
source }, lane.Local)

end


function rewrite . maskAnd ( left , right , source , state )
if left == nil then
return right
end

return setmetatable({ op =
"vmask" ,  verb =
"and" ,  args =
{ left , right } ,  type =
state . shape . mask ,  source =
source }, lane.MaskOp)

end


function rewrite . maskNot ( value , source , state )
return setmetatable({ op =  "vmask" ,  verb =  "not" ,  args =  { value } ,  type =  state . shape . mask ,  source =  source }, lane.MaskOp)
end







function rewrite . activeMask (
mask ,
loopContext ,
source ,
state
)
if loopContext == nil then
return mask
end
local context = loopContext
local executing = rewrite . maskLocal ( context . executing , source , state )
if mask == nil then
return executing
end
local given = mask
if given . op == "local" and ( given ) . name == context . executing . name then
return given
end

return rewrite . maskAnd ( given , executing , source , state )
end








rewrite.BlockState = {} rewrite.BlockState.__index = rewrite.BlockState
















function rewrite . internalMask (
label ,
source ,
block ,
state
)
block . serial = block . serial + 1
local serial = tostring ( block . serial )

return setmetatable({ kind =
"local" ,  name =
"$" .. label .. serial ,  cName =
"lm" .. serial .. "_" .. label ,  type =
state . shape . mask ,  source =
source }, rewrite.Binding)

end











function rewrite . maySpeculate ( targetName , mask , loopContext )
if loopContext == nil or mask == nil then
return false
end
local context = loopContext
local given = mask
if given . op ~= "local" then
return false
end

return (
given
) . name == context . executing . name and context . speculate and context . observable [ targetName ] ~= true
end

return rewrite
