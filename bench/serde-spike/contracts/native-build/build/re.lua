_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


















local tonumber , type , error = tonumber , type , error
local setmetatable = setmetatable
local m = require ( "lpeg" )
local mm = m
local mt = getmetatable ( mm . P ( 0 ) )
local any = m . P ( 1 )
local Predef = { nl = m . P "\n" }
local mem ;
local fmem ;
local gmem
local re = { }








function re . updatelocale ( ) 
mm . locale ( Predef )
Predef . a = Predef . alpha ;
Predef . c = Predef . cntrl ;
Predef . d = Predef . digit
Predef . g = Predef . graph ;
Predef . l = Predef . lower ;
Predef . p = Predef . punct
Predef . s = Predef . space ;
Predef . u = Predef . upper ;
Predef . w = Predef . alnum
Predef . x = Predef . xdigit
Predef . A = any - Predef . a ;
Predef . C = any - Predef . c ;
Predef . D = any - Predef . d
Predef . G = any - Predef . g ;
Predef . L = any - Predef . l ;
Predef . P = any - Predef . p
Predef . S = any - Predef . s ;
Predef . U = any - Predef . u ;
Predef . W = any - Predef . w
Predef . X = any - Predef . x
mem = { } ;
fmem = { } ;
gmem = { } ;
local weak = { __mode = "v" }
setmetatable ( mem , weak ) ;
setmetatable ( fmem , weak ) ;
setmetatable ( gmem , weak )
end

re . updatelocale ( )

local function patt_error ( s , i ) 
local msg = ( # s < i + 20 ) and s : sub ( i ) or s : sub ( i , i + 20 ) .. "..." ;
error ( ("pattern error near '%s'") : format ( msg ) , 2 )
end

local function mult ( p , n ) 
local np = mm . P ( true ) ;
while n >= 1 do
if n % 2 >= 1 then
np = np * p
end ;
p = p * p ;
n = n / 2
end ;

return np
end

local function equalcap ( s , i , c ) 
if type ( c ) ~= "string" then
return false
end ;
local e = # c + i ;
if s : sub ( i , e - 1 ) == c then
return e
end ;

return false
end

local S = ( Predef . space + "--" * ( any - Predef . nl ) ^ 0 ) ^ 0
local name = m . R ( "AZ" , "az" , "__" ) * m . R ( "AZ" , "az" , "__" , "09" ) ^ 0
local arrow = S * "<-"
local seq_follow = m . P "/" + ")" + "}" + ":}" + "~}" + "|}" + ( name * arrow ) + -1
name = m . C ( name )
local Def = name * m . Carg ( 1 )

local function getdef ( id , defs ) 
local c = defs and defs [ id ] ;
if not c then
error ( "undefined name: " .. id )
end ;

return c
end

local function defwithfunc ( f ) 
return ( m . Cg ) ( Def / getdef * m . Cc ( f ) , nil )
end

local num = m . C ( m . R "09" ^ 1 ) * S / tonumber
local String = "'" * m . C ( ( any - "'" ) ^ 0 ) * "'" + "\"" * m . C ( ( any - "\"" ) ^ 0 ) * "\""
local defined = "%" * Def / function ( c , Defs ) 
local cat = Defs and Defs [ c ] or Predef [ c ] ;
if not cat then
error ( "name '" .. c .. "' undefined" )
end ;

return cat
end
local Range = m . Cs ( any * ( m . P "-" / "" ) * ( any - "]" ) ) / mm . R
local item = ( defined + Range + m . C ( any ) ) / m . P
local Class = "[" * ( m . C ( m . P "^" ^ -1 ) ) * ( item * ( ( item % mt . __add ) - "]" ) ^ 0 ) / function ( c , p ) 
return c == "^" and any - p or p
end * "]"

local function adddef ( t , k , exp ) 
if t [ k ] then
error ( "'" .. k .. "' already defined as a rule" )
else
t [ k ] = exp
end ;

return t
end

local function firstdef ( n , r ) 
return adddef ( { n } , n , r )
end

local function NT ( n , b ) 
if not b then
error ( "rule '" .. n .. "' used outside a grammar" )
else
return mm . V ( n )
end
end

local exp = m . P {
"Exp" ,
Exp = S * ( m . V "Grammar" + m . V "Seq" * ( "/" * S * m . V "Seq" % mt . __add ) ^ 0 ) ,
Seq = ( m . Cc ( m . P "" ) * ( m . V "Prefix" % mt . __mul ) ^ 0 ) * ( # seq_follow + patt_error ) ,
Prefix = "&" * S * m . V "Prefix" / mt . __len + "!" * S * m . V "Prefix" / mt . __unm + m . V "Suffix" ,
Suffix = m . V "Primary" * S * ( (
m . P "+" * m . Cc (
1 ,
mt . __pow
) + m . P "*" * m . Cc (
0 ,
mt . __pow
) + m . P "?" * m . Cc (
- 1 ,
mt . __pow
) + m . P "^" * (
( m . Cg ) ( num * m . Cc ( mult ) ) + ( m . Cg ) ( m . C ( m . S "+-" * m . R "09" ^ 1 ) * m . Cc ( mt . __pow ) )
) + "->" * S * (
( m . Cg ) ( ( String + num ) * m . Cc ( mt . __div ) ) + m . P "{}" * m . Cc ( nil , m . Ct ) + defwithfunc ( mt . __div )
) + "=>" * S * defwithfunc ( mm . Cmt ) + ">>" * S * defwithfunc ( mt . __mod ) + "~>" * S * defwithfunc ( mm . Cf )
) % function ( a , b , f ) 
return f ( a , b )
end * S ) ^ 0 ,
Primary = "(" * m . V "Exp" * ")" + String / mm . P + Class + defined + "{:" * (
name * ":" + m . Cc ( nil )
) * m . V "Exp" * ":}" / function ( n , p ) 
return ( mm . Cg ) ( p , n )
end + "=" * name / function ( n ) 
return ( mm . Cmt ) ( mm . Cb ( n ) , equalcap )
end + m . P "{}" / mm . Cp + "{~" * m . V "Exp" * "~}" / mm . Cs + "{|" * m . V "Exp" * "|}" / mm . Ct + "{" * m . V "Exp" * "}" / (
mm . C
) + m . P "." * m . Cc ( any ) + ( name * - arrow + "<" * name * ">" ) * m . Cb ( "G" ) / NT ,
Definition = name * arrow * m . V "Exp" ,
Grammar = ( m . Cg ) ( m . Cc ( true ) , "G" ) * ( ( m . V "Definition" / firstdef ) * ( m . V "Definition" % adddef ) ^ 0 ) / mm . P
}
local pattern = S * ( m . Cg ) ( m . Cc ( false ) , "G" ) * exp / mm . P * ( - any + patt_error )















function re . compile ( p , defs ) 
if mm . type ( p ) == "pattern" then
return p
end ;
local cp = pattern : match ( p , 1 , defs ) ;
if not cp then
error ( "incorrect pattern" , 3 )
end ;

return cp
end
















function re . match ( s , p , i ) 
local cp = mem [ p ] ;
if not cp then
cp = re . compile ( p ) ;
mem [ p ] = cp
end ;

return cp : match ( s , i or 1 )
end














function re . find ( s , p , i ) 
local cp = fmem [ p ] ;
if not cp then
cp = re . compile ( p ) / 0 ;
cp = mm . P { mm . Cp ( ) * cp * mm . Cp ( ) + 1 * mm . V ( 1 ) } ;
fmem [ p ] = cp
end ;
local first , ending = cp : match ( s , i or 1 ) ;
if first then
return first , ending - 1
end ;

return first
end










function re . gsub ( s , p , rep ) 
local g = gmem [ p ] or { } ;
gmem [ p ] = g ;
local cp = g [ rep ] ;
if not cp then
cp = re . compile ( p ) ;
cp = ( mm . Cs ) ( ( cp / rep + 1 ) ^ 0 ) ;
g [ rep ] = cp
end ;

return cp : match ( s )
end

local __nuppExportValue= re ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["re"]=nil;error(__nuppWhy,0) end;package.loaded["re"]=__nuppExports;return __nuppExports