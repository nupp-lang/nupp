_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports={};package.loaded["nupp.serde.document"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()












































local documents = require ( "nupp.serde.internal.document" )
local readers = require ( "nupp.serde.internal.documentreader" )
local writers = require ( "nupp.serde.internal.documentwriter" )
local reconstruction = require ( "nupp.serde.internal.documentcodec" )
local views = require ( "nupp.serde.internal.view" )
local persistence = require ( "nupp.serde.internal.persistence" )









const Document = documents . Document ;__nuppExports["Document"]=Document




const Entry = documents . Entry ;__nuppExports["Entry"]=Entry




const MapEntry = documents . MapEntry ;__nuppExports["MapEntry"]=MapEntry







const adapter = documents . documentAdapter ;__nuppExports["adapter"]=adapter


const null = documents . null ;__nuppExports["null"]=null


const boolean = documents . boolean ;__nuppExports["boolean"]=boolean


const string = documents . string ;__nuppExports["string"]=string



const numberToken = documents . numberToken ;__nuppExports["numberToken"]=numberToken


const integer = documents . integer ;__nuppExports["integer"]=integer


const float = documents . float ;__nuppExports["float"]=float


const decimal = documents . decimal ;__nuppExports["decimal"]=decimal



const bigInteger = documents . bigInteger ;__nuppExports["bigInteger"]=bigInteger


const bytes = documents . bytes ;__nuppExports["bytes"]=bytes


const timestamp = documents . timestamp ;__nuppExports["timestamp"]=timestamp


const atom = documents . atom ;__nuppExports["atom"]=atom


const list = documents . list ;__nuppExports["list"]=list


const tuple = documents . tuple ;__nuppExports["tuple"]=tuple














const object = documents . object ;__nuppExports["object"]=object


const union = documents . union ;__nuppExports["union"]=union



const map = documents . map ;__nuppExports["map"]=map


const boundary = documents . document ;__nuppExports["boundary"]=boundary


const withContext = documents . withContext ;__nuppExports["withContext"]=withContext







const from = writers . fromBinding ;__nuppExports["from"]=from










const into = reconstruction . into ;__nuppExports["into"]=into










const decoder = reconstruction . decoder ;__nuppExports["decoder"]=decoder



const clear = reconstruction . clear ;__nuppExports["clear"]=clear


const cachedBindings = reconstruction . cachedBindings ;__nuppExports["cachedBindings"]=cachedBindings



const reader = readers . reader ;__nuppExports["reader"]=reader


const snapshot = readers . snapshot ;__nuppExports["snapshot"]=snapshot

























const View = views . View ;__nuppExports["View"]=View







const view = views . of ;__nuppExports["view"]=view





const viewAdapter = views . adapter ;__nuppExports["viewAdapter"]=viewAdapter





























const storeRegistry = persistence . registry ;__nuppExports["storeRegistry"]=storeRegistry




const StoreSnapshot = persistence . Snapshot ;__nuppExports["StoreSnapshot"]=StoreSnapshot




const StoreEntry = persistence . Entry ;__nuppExports["StoreEntry"]=StoreEntry





const storeBinding = persistence . binding ;__nuppExports["storeBinding"]=storeBinding
 end);if not __nuppOk then package.loaded["nupp.serde.document"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.document"]=__nuppExports;return __nuppExports