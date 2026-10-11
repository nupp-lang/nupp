_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



local raw = require ( "nupp.runtime.bitops" )
local bitops = { }

function bitops . tobit ( value ) 
return raw . tobit ( value )
end

function bitops . tohex ( value , digits ) 
return raw . tohex ( value , digits )
end

function bitops . bnot ( value ) 
return raw . bnot ( value )
end

function bitops . band ( first , ... ) 
return raw . band ( first , ... )
end

function bitops . bor ( first , ... ) 
return raw . bor ( first , ... )
end

function bitops . bxor ( first , ... ) 
return raw . bxor ( first , ... )
end

function bitops . lshift ( value , count ) 
return raw . lshift ( value , count )
end

function bitops . rshift ( value , count ) 
return raw . rshift ( value , count )
end

function bitops . arshift ( value , count ) 
return raw . arshift ( value , count )
end

function bitops . rol ( value , count ) 
return raw . rol ( value , count )
end

function bitops . ror ( value , count ) 
return raw . ror ( value , count )
end

function bitops . bswap ( value ) 
return raw . bswap ( value )
end

local __nuppExportValue= bitops ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.bitops"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.bitops"]=__nuppExports;return __nuppExports