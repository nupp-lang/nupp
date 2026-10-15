_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()




local host = { }



function host . readFile ( path ) 
error ( "host service" )
end


function host . writeFile ( path , text ) 
error ( "host service" )
end



function host . sleep ( ms ) 
error ( "host service" )
end



function host . run ( cmd , arg ) 
error ( "host service" )
end


function host . listDir ( path ) 
error ( "host service" )
end



function host . now ( ) 
error ( "host service" )
end


function host . getenv ( name ) 
error ( "host service" )
end

local __nuppExportValue= host ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.host"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.host"]=__nuppExports;return __nuppExports