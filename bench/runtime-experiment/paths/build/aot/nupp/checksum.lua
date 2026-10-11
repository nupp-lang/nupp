_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT19={}; local function __nuppT16(...) return {n=select("#",...),...} end; local __nuppT20,__nuppT21,__nuppT22,__nuppT23,__nuppT24,__nuppT25,__nuppT26,__nuppT27=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT17(value) return value end; local function __nuppT18(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT25({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT26(v.primary) for _,reason in __nuppT27(v.suppressed) do text=text.."\ncleanup: "..__nuppT26(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()local algorithm;__nuppExports["algorithm"]=function(...) return algorithm(...) end;local algorithms;__nuppExports["algorithms"]=function(...) return algorithms(...) end;local lookup;__nuppExports["lookup"]=function(...) return lookup(...) end;local newChecksum;__nuppExports["newChecksum"]=function(...) return newChecksum(...) end;local value;__nuppExports["value"]=function(...) return value(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.checksum\0runtime\0002") };
















































local spi = require ( "nupp.spi" )

const span = require ( "nupp.mem.span" )
const provider = require ( "nupp.checksum.spi" )



local Checksum = {}
























local Context = {} Context.__index = Context




function Context:algorithm() 
return self . name
end

function Context:width() 
return self . bits
end

function Context:write(bytes) 
if type ( bytes ) ~= "string" then
error ( "nupp: Checksum:write bytes must be a string" , 2 )
end
local view = span . fromString ( bytes )
self . state : update ( view )

return true , nil
end

function Context:writeSpan(bytes) 
self . state : update ( bytes )

return bytes .count , nil
end

function Context:flush() 
return true , nil
end

function Context:value() 
return self . state : value ( )
end

function Context:close() 
self . state : close ( )
end



local Algorithm = {} Algorithm.__index = Algorithm









function Algorithm:newChecksum() 
return ( _G.setmetatable({ state =  self . implementation : create ( ) ,  name =  self . name ,  bits =  self . width }, Context) )
end ;_G.nupp.__reflect.link(Algorithm,__nuppT1[1],{ _G.nupp.__reflect.reference("../../../src/nupp/checksum/spi.nupp\0Algorithm\0interface\0module\0001","nupp.checksum.spi") }) ;__nuppExports["Algorithm"]=Algorithm


local standard = require ( "nupp.runtime.provider.checksum" )

local function validate ( selected ) 
for name , implementation in pairs ( selected . algorithms ) do
if type ( name ) ~= "string"
or name == ""
or type ( implementation ) ~= "table"
or implementation . name ~= name
or type ( implementation . width ) ~= "number"
or implementation . width < 1
or implementation . width > 64
or implementation . width % 1 ~= 0
or type ( implementation . create ) ~= "function"
then
error ( "invalid checksum algorithm descriptor " .. tostring ( name ) , 2 )
end
local expected = standard . algorithms [ name ]
if expected ~= nil and implementation . width ~= expected . width then
error ( "checksum provider has the wrong width for " .. name , 2 )
end
end
end

local selected = spi . select ( spi . load ("nupp.checksum.spi.Provider") ) ?? standard
validate ( selected )
local available = { }
for name , implementation in pairs ( standard . algorithms ) do
available [ name ] = _G.setmetatable({ name =  name ,  width =  implementation . width ,  implementation =  implementation }, Algorithm)
end
for name , implementation in pairs ( selected . algorithms ) do
available [ name ] = _G.setmetatable({ name =  name ,  width =  implementation . width ,  implementation =  implementation }, Algorithm)
end
local names = { }
for name in pairs ( available ) do
names [ # names + 1 ] = name
end
table . sort ( names )




lookup=function ( name ) 
return available [ name ]
end ;__nuppExports["lookup"]=lookup





algorithm=function ( name ) 
local found = lookup ( name )
if found == nil then
error ( "unknown checksum algorithm " .. name , 2 )
end

return found
end ;__nuppExports["algorithm"]=algorithm




newChecksum=function ( name ) 
return algorithm ( name ) : newChecksum ( )
end ;__nuppExports["newChecksum"]=newChecksum



algorithms=function ( ) 
local result = { }
for index , name in ipairs ( names ) do
result [ index ] = name
end

return result
end ;__nuppExports["algorithms"]=algorithms





value=function ( name , bytes ) local __nuppT15;
do const  __nuppT34= newChecksum ( name ) ; __nuppT15=__nuppT15 or {} ; local __nuppT35=__nuppT15[1]; if not __nuppT35 then __nuppT35=function(context) do
context : write ( bytes )
return "return",__nuppT16( context : value ( ) ) end; return "normal" end; __nuppT15[1]=__nuppT35 end; const __nuppT29,__nuppT30,__nuppT31=__nuppT21(__nuppT35,__nuppT17,__nuppT34); const __nuppT28=1; local __nuppT32={}; local __nuppT33=0; if __nuppT28>=1 then  local __nuppT36,__nuppT37=__nuppT20(__nuppCleanup1,__nuppT34);  if not __nuppT36 then __nuppT33=__nuppT33+1; __nuppT32[__nuppT33]=__nuppT37 end; end; if not __nuppT29 then if __nuppT33>0 then __nuppT22(__nuppT18(__nuppT30,__nuppT32,1),0) else __nuppT22(__nuppT30,0) end end; if __nuppT33>0 then if __nuppT33>1 then __nuppT22(__nuppT18(__nuppT32[1],__nuppT32,2),0) else __nuppT22(__nuppT32[1],0) end end; if __nuppT30=="return" then  return __nuppT23(__nuppT31,1,__nuppT31.n)  end; end
end ;__nuppExports["value"]=value
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[Algorithm]="nupp.checksum\0Algorithm"; end);if not __nuppOk then package.loaded["nupp.checksum"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.checksum"]=__nuppExports;return __nuppExports