_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT11={}; local function __nuppT8(...) return {n=select("#",...),...} end; local __nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT9(value) return value end; local function __nuppT10(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT17({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT18(v.primary) for _,reason in __nuppT19(v.suppressed) do text=text.."\ncleanup: "..__nuppT18(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local parser = require ( "nupp.compiler.syntax.parser" )
local lower = require ( "nupp.compiler.vm.lower" )
local chunks = { }



function chunks . image ( source , filename ) 
local path = filename or "=(loadstring)"
local tree = parser . parse ( source , path )
assert ( # tree . errors == 0 , "chunk did not parse: " .. path )
return lower . emit (
"vm.chunk" ,
{ } ,
function ( name ) 
return name == "vm.chunk" and path or nil
end ,
function ( _ , _ ) 
return tree . root
end
)
end


function chunks . install ( ) 
local loadImage = rawget ( _G , "__nupp_load_image" )
if not loadImage then
return false
end

local function compileChunk ( source , filename ) 
local path = filename or "=(loadstring)"
local tree = parser . parse ( source , path )
if # tree . errors > 0 then
return nil , "chunk did not parse: " .. path
end


local compiled = nil

return function ( ... ) 
if not compiled then
compiled = loadImage ( chunks . image ( source , path ) )
end
return compiled ( ... )
end , nil
end

rawset ( _G , "__nupp_compile_chunk" , compileChunk )
rawset ( _G , "loadfile" , function ( path ) 
do local __nuppT20=0; local  __nuppT26 ; local __nuppT21,__nuppT22,__nuppT23=__nuppT13(function() do local __nuppT27=__nuppT8( io . open ( path , "rb" ) ); __nuppT26= __nuppT27[1] ; __nuppT20=1;  local  file , problem = __nuppT27[1] , __nuppT27[2] ;
if not file then
return "return",__nuppT8( nil , problem )
end
local source = file : read ( "*a" )
file : close ( )

return "return",__nuppT8( compileChunk ( source , path ) ) end; return "normal" end,__nuppT9); local __nuppT24={}; local __nuppT25=0; if __nuppT20>=1 and __nuppT26~=nil then  local __nuppT28,__nuppT29=__nuppT12(__nuppCleanup1,__nuppT26);  if not __nuppT28 then __nuppT25=__nuppT25+1; __nuppT24[__nuppT25]=__nuppT29 end; end; if not __nuppT21 then if __nuppT25>0 then __nuppT14(__nuppT10(__nuppT22,__nuppT24,1),0) else __nuppT14(__nuppT22,0) end end; if __nuppT25>0 then if __nuppT25>1 then __nuppT14(__nuppT10(__nuppT24[1],__nuppT24,2),0) else __nuppT14(__nuppT24[1],0) end end; if __nuppT22=="return" then  return __nuppT15(__nuppT23,1,__nuppT23.n)  end; end
end )

return true
end

local __nuppExportValue= chunks ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.vm.chunks"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.vm.chunks"]=__nuppExports;return __nuppExports