_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT8={}; local function __nuppT5(...) return {n=select("#",...),...} end; local __nuppT9,__nuppT10,__nuppT11,__nuppT12,__nuppT13,__nuppT14,__nuppT15,__nuppT16=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT6(value) return value end; local function __nuppT7(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT14({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT15(v.primary) for _,reason in __nuppT16(v.suppressed) do text=text.."\ncleanup: "..__nuppT15(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()














local toolruns = { }

local windows = package . config : sub ( 1 , 1 ) == "\\"





local counted = 0


function toolruns . reset ( ) 
counted = 0
end


function toolruns . count ( ) 
return counted
end

local processorMemo = nil
local MAX_SAFE_INTEGER = 9007199254740991

local function finite ( value ) 
if value == nil or value ~= value or value == math . huge or value == - math . huge then
return nil
end

return value
end








function toolruns . processors ( ) local __nuppT4;
if processorMemo ~= nil then
return processorMemo
end
local found = nil
if windows then
found = finite ( tonumber ( os . getenv ( "NUMBER_OF_PROCESSORS" ) or "" ) )
else
do const  __nuppT23= io . popen ( "getconf _NPROCESSORS_ONLN 2>/dev/null" ) ; __nuppT4=__nuppT4 or {} ; local __nuppT24=__nuppT4[1]; if not __nuppT24 then __nuppT24=function(handle) do
if handle ~= nil then
local line = ( handle ) : read ( "*l" ) ;
( handle ) : close ( )
found = finite ( tonumber ( line or "" ) )
end end; return "normal" end; __nuppT4[1]=__nuppT24 end; const __nuppT18,__nuppT19,__nuppT20=__nuppT10(__nuppT24,__nuppT6,__nuppT23); const __nuppT17=1; local __nuppT21={}; local __nuppT22=0; if __nuppT17>=1 and __nuppT23~=nil then  local __nuppT25,__nuppT26=__nuppT9(__nuppCleanup1,__nuppT23);  if not __nuppT25 then __nuppT22=__nuppT22+1; __nuppT21[__nuppT22]=__nuppT26 end; end; if not __nuppT18 then if __nuppT22>0 then __nuppT11(__nuppT7(__nuppT19,__nuppT21,1),0) else __nuppT11(__nuppT19,0) end end; if __nuppT22>0 then if __nuppT22>1 then __nuppT11(__nuppT7(__nuppT21[1],__nuppT21,2),0) else __nuppT11(__nuppT21[1],0) end end; if __nuppT19=="return" then  return __nuppT12(__nuppT20,1,__nuppT20.n)  end; end
end
if found == nil or ( found ) < 1 or ( found ) > 9007199254740991 then
found = 4
end
processorMemo = math . floor ( found )

return processorMemo
end





function toolruns . width ( jobs ) 
if windows or jobs <= 1 then
return 1
end
local asked = finite ( tonumber ( os . getenv ( "NUPP_AOT_JOBS" ) or "" ) )
local bound = asked ~= nil and math . floor ( asked ) or toolruns . processors ( )
if bound < 1 then
bound = 1
end

return jobs < bound and jobs or bound
end

local __nuppExportValue= toolruns ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.build.toolruns"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.build.toolruns"]=__nuppExports;return __nuppExports