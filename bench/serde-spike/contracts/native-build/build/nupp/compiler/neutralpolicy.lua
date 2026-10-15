_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.compiler.neutralpolicy"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()










const relations = "reduce at entry; relate identical blocked terms only" ;__nuppExports["relations"]=relations
const substitution = "preserve under rebind; reduce after closed substitution" ;__nuppExports["substitution"]=substitution
const rendering = "preserve as bounded source-like text" ;__nuppExports["rendering"]=rendering
const fingerprints = "preserve canonical semantic structure" ;__nuppExports["fingerprints"]=fingerprints
const ownership = "reject as an unclosed boundary type" ;__nuppExports["ownership"]=ownership
const narrowing = "preserve until a relation requests reduction" ;__nuppExports["narrowing"]=narrowing
const methodSlots = "reduce before member enumeration" ;__nuppExports["methodSlots"]=methodSlots
const documentation = "show the written alias and shortened reduced form" ;__nuppExports["documentation"]=documentation
const lsp = "reduce with the checker-revision memo before semantic answers" ;__nuppExports["lsp"]=lsp
const optimization = "reject before runtime lowering" ;__nuppExports["optimization"]=optimization
const codegen = "reject before runtime lowering" ;__nuppExports["codegen"]=codegen

const required = {
"relations" ,
"substitution" ,
"rendering" ,
"fingerprints" ,
"ownership" ,
"narrowing" ,
"methodSlots" ,
"documentation" ,
"lsp" ,
"optimization" ,
"codegen" ,
} ;__nuppExports["required"]=required
 end);if not __nuppOk then package.loaded["nupp.compiler.neutralpolicy"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.neutralpolicy"]=__nuppExports;return __nuppExports