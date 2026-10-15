_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.util"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()




































local bitset = require ( "nupp.util.internal.bitset" )
local hash = require ( "nupp.util.internal.hash" )
local pool = require ( "nupp.util.internal.pool" )
local uuid = require ( "nupp.util.internal.uuid" )
local store = require ( "nupp.util.internal.store" )
local protected = require ( "nupp.util.internal.protected" )




const Bitset = bitset . Bitset ;__nuppExports["Bitset"]=Bitset


const WORD_BITS = bitset . WORD_BITS ;__nuppExports["WORD_BITS"]=WORD_BITS




const Pool = pool . Pool ;__nuppExports["Pool"]=Pool


const newPool = pool . new ;__nuppExports["newPool"]=newPool




const Key = store . Key ;__nuppExports["Key"]=Key





const newKey = store . newKey ;__nuppExports["newKey"]=newKey


const newStore = store . newStore ;__nuppExports["newStore"]=newStore


const fnv1a64 = hash . fnv1a64 ;__nuppExports["fnv1a64"]=fnv1a64



const try = protected . try ;__nuppExports["try"]=try



const tryWith = protected . tryWith ;__nuppExports["tryWith"]=tryWith


const uuid4 = uuid . uuid4 ;__nuppExports["uuid4"]=uuid4






const uuid7 = uuid . uuid7 ;__nuppExports["uuid7"]=uuid7
 end);if not __nuppOk then package.loaded["nupp.util"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.util"]=__nuppExports;return __nuppExports