_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT9={}; local function __nuppT6(...) return {n=select("#",...),...} end; local __nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT7(value) return value end; local function __nuppT8(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT15({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT16(v.primary) for _,reason in __nuppT17(v.suppressed) do text=text.."\ncleanup: "..__nuppT16(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






























local bytecodecache = { }



local FORMAT = "nupp-bytecode 3"
local INDEX = "index"




local MULTIPLIER = 1000003




local okBit , bitLibrary = pcall ( require , "bit" )
local bit = okBit and bitLibrary or nil




local okFfi , ffiLibrary = pcall ( require , "ffi" )
local ffi = okFfi and ffiLibrary or nil
local words = nil
if ffi ~= nil and ffi . abi ( "le" ) then
words = ffi . typeof ( "const uint32_t *" )
end











local function checksum ( bytes ) 
if bit == nil then
return nil
end
local tobit , bxor , rol , rshift = bit . tobit , bit . bxor , bit . rol , bit . rshift
local length = # bytes
local count = rshift ( length , 2 )
local a , b , c , d = tobit ( length ) , 1 , 2 , 3
local index = 0
if words ~= nil then
local word = ffi . cast ( words , bytes )
local last = count - 4
while index <= last do
a = tobit ( a * 1000003 + word [ index ] )
b = tobit ( b * 1000003 + word [ index + 1 ] )
c = tobit ( c * 1000003 + word [ index + 2 ] )
d = tobit ( d * 1000003 + word [ index + 3 ] )
index = index + 4
end
while index < count do
a = tobit ( a * 1000003 + word [ index ] )
index = index + 1
end
else
local byte = string . byte

local function word ( at ) 
local p = at * 4 + 1
local b1 , b2 , b3 , b4 = byte ( bytes , p , p + 3 )
return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local last = count - 4
while index <= last do
a = tobit ( a * 1000003 + word ( index ) )
b = tobit ( b * 1000003 + word ( index + 1 ) )
c = tobit ( c * 1000003 + word ( index + 2 ) )
d = tobit ( d * 1000003 + word ( index + 3 ) )
index = index + 4
end
while index < count do
a = tobit ( a * 1000003 + word ( index ) )
index = index + 1
end
end
for at = count * 4 + 1 , length do
a = tobit ( a * 1000003 + string . byte ( bytes , at ) )
end

return bit . tohex ( bxor ( a , rol ( b , 8 ) , rol ( c , 16 ) , rol ( d , 24 ) ) )
end















local function vmDirectory ( ) 
return ( tostring ( jit . version ) : gsub ( "[^%w%.]" , "-" ) )
end







local function outputRoot ( ) 
local source = debug . getinfo ( 1 , "S" ) . source
local dir = ( source : match ( "^@(.*)[/\\]" ) or "" ) : gsub ( "\\" , "/" )

return dir : match ( "^(.*)/nupp/tools$" )
end









local function readIndex ( root ) local __nuppT5;
do const  __nuppT24= io . open ( root .. "/.bytecode/" .. ( ( tostring ( jit . version ) : gsub ( "[^%w%.]" , "-" ) ) ) .. "/index" , "rb" ) ; __nuppT5=__nuppT5 or {} ; local __nuppT25=__nuppT5[1]; if not __nuppT25 then __nuppT25=function(file) do
if not file then
return "return",__nuppT6( nil )
end
local text = file : read ( "*a" )
file : close ( )
if not text then
return "return",__nuppT6( nil )
end
local lines = { }
for line in text : gmatch ( "[^\n]+" ) do
lines [ # lines + 1 ] = line
end
if lines [ 1 ] ~= "nupp-bytecode 3" or lines [ 2 ] ~= "root " .. root then
return "return",__nuppT6( nil )
end
local found = { }
for index = 3 , # lines do
local digest , name , length , sum = lines [ index ] : match ( "^(%x+) (%S+) (%d+) (%x+)$" )
if digest and name and length and sum then
found [ name ] = { digest = digest , length = tonumber ( length ) , sum = sum }
end
end

return "return",__nuppT6( found ) end; return "normal" end; __nuppT5[1]=__nuppT25 end; const __nuppT19,__nuppT20,__nuppT21=__nuppT11(__nuppT25,__nuppT7,__nuppT24); const __nuppT18=1; local __nuppT22={}; local __nuppT23=0; if __nuppT18>=1 and __nuppT24~=nil then  local __nuppT26,__nuppT27=__nuppT10(__nuppCleanup1,__nuppT24);  if not __nuppT26 then __nuppT23=__nuppT23+1; __nuppT22[__nuppT23]=__nuppT27 end; end; if not __nuppT19 then if __nuppT23>0 then __nuppT12(__nuppT8(__nuppT20,__nuppT22,1),0) else __nuppT12(__nuppT20,0) end end; if __nuppT23>0 then if __nuppT23>1 then __nuppT12(__nuppT8(__nuppT22[1],__nuppT22,2),0) else __nuppT12(__nuppT22[1],0) end end; if __nuppT20=="return" then  return __nuppT13(__nuppT21,1,__nuppT21.n)  end; end
end





function bytecodecache . indexPath ( root ) 
return root .. "/.bytecode/" .. ( ( tostring ( jit . version ) : gsub ( "[^%w%.]" , "-" ) ) ) .. "/index"
end






function bytecodecache . searcher ( root ) 
local found = readIndex ( root )
if found == nil then
return nil
end
local where = root .. "/.bytecode/" .. ( ( tostring ( jit . version ) : gsub ( "[^%w%.]" , "-" ) ) )

return function ( name ) local __nuppT30;
local entry = found [ name ]
if entry == nil then
return nil
end
local path = where .. "/" .. entry . digest .. ".bc"
do const  __nuppT37= io . open ( path , "rb" ) ; __nuppT30=__nuppT30 or {} ; local __nuppT38=__nuppT30[2]; if not __nuppT38 then __nuppT38=function(file) do
if not file then
return "return",__nuppT6( nil )
end
local bytes = file : read ( "*a" )
file : close ( )
if not bytes then
return "return",__nuppT6( nil )
end




local sum = # bytes == entry . length and checksum ( bytes ) or nil
if sum ~= entry . sum then


if sum ~= nil or # bytes ~= entry . length then
os . remove ( path )
end
return "return",__nuppT6( nil )
end



local ok , chunk = pcall ( loadstring , bytes )

return "return",__nuppT6( ok and chunk or nil ) end; return "normal" end; __nuppT30[2]=__nuppT38 end; const __nuppT32,__nuppT33,__nuppT34=__nuppT11(__nuppT38,__nuppT7,__nuppT37); const __nuppT31=1; local __nuppT35={}; local __nuppT36=0; if __nuppT31>=1 and __nuppT37~=nil then  local __nuppT39,__nuppT40=__nuppT10(__nuppCleanup1,__nuppT37);  if not __nuppT39 then __nuppT36=__nuppT36+1; __nuppT35[__nuppT36]=__nuppT40 end; end; if not __nuppT32 then if __nuppT36>0 then __nuppT12(__nuppT8(__nuppT33,__nuppT35,1),0) else __nuppT12(__nuppT33,0) end end; if __nuppT36>0 then if __nuppT36>1 then __nuppT12(__nuppT8(__nuppT35[1],__nuppT35,2),0) else __nuppT12(__nuppT35[1],0) end end; if __nuppT33=="return" then  return __nuppT13(__nuppT34,1,__nuppT34.n)  end; end
end
end






function bytecodecache . install ( ) 
local root = outputRoot ( )
if root == nil then
return
end
local search = bytecodecache . searcher ( root )
if search == nil then
return
end
table . insert ( package . loaders , 2 , search )
end








function bytecodecache . refresh ( outDir , modules ) 
local fs = require ( "nupp.compiler.fs" )
local hash = require ( "nupp.compiler.hash" )




local root = fs . absolute ( outDir )
local where = root .. "/.bytecode/" .. ( ( tostring ( jit . version ) : gsub ( "[^%w%.]" , "-" ) ) )





local previous = readIndex ( root )


local recorded = { }
for _ , entry in pairs ( previous or { } ) do
recorded [ entry . digest ] = entry
end
local lines = { "nupp-bytecode 3" , "root " .. root }
local live = { }
local names = { }
for name in pairs ( modules ) do
names [ # names + 1 ] = name
end
table . sort ( names )
for _ , name in ipairs ( names ) do
local record = modules [ name ]
local output , digest = record . output , record . artifactHash
if type ( output ) == "string" and type ( digest ) == "string" and digest : match ( "^%x+$" ) then




local entryDigest = hash . digest ( name .. "\0" .. digest )
local entry = where .. "/" .. entryDigest .. ".bc"
local known = recorded [ entryDigest ]
local line = known
and fs . exists ( entry )
and ( entryDigest .. " " .. name .. " " .. known . length .. " " .. known . sum )
or nil
if line == nil then
local text = fs . readFile ( output )





local chunk = text and loadstring ( text , "@" .. root .. "/" .. name : gsub ( "%." , "/" ) .. ".lua" )
if chunk then



local dump = string . dump ( chunk , "d" )
local sum = checksum ( dump )
if sum ~= nil and fs . writeFile ( entry , dump ) == true then
line = entryDigest .. " " .. name .. " " .. # dump .. " " .. sum
end
end
end
if line ~= nil then
lines [ # lines + 1 ] = line
live [ entryDigest ] = true
end
end
end
lines [ # lines + 1 ] = ""
fs . writeFileIfChanged ( where .. "/index" , table . concat ( lines , "\n" ) )






for _ , path in ipairs ( fs . listFiles ( where ) ) do
local digest = path : match ( "([^/\\]+)%.bc$" )
if digest ~= nil and not live [ digest ] then
os . remove ( path )
end
end
end

local __nuppExportValue= bytecodecache ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.bytecodecache"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.bytecodecache"]=__nuppExports;return __nuppExports