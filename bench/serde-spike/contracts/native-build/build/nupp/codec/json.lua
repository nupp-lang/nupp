_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports={};package.loaded["nupp.codec.json"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local arrayOf;__nuppExports["arrayOf"]=function(...) return arrayOf(...) end;local asArray;__nuppExports["asArray"]=function(...) return asArray(...) end;local asObject;__nuppExports["asObject"]=function(...) return asObject(...) end;local decode;__nuppExports["decode"]=function(...) return decode(...) end;local encode;__nuppExports["encode"]=function(...) return encode(...) end;local encoded;__nuppExports["encoded"]=function(...) return encoded(...) end;local encodedString;__nuppExports["encodedString"]=function(...) return encodedString(...) end;local isArray;__nuppExports["isArray"]=function(...) return isArray(...) end;local newWriter;__nuppExports["newWriter"]=function(...) return newWriter(...) end;local numberToken;__nuppExports["numberToken"]=function(...) return numberToken(...) end;local pull;__nuppExports["pull"]=function(...) return pull(...) end;local verified;__nuppExports["verified"]=function(...) return verified(...) end;local verifiedString;__nuppExports["verifiedString"]=function(...) return verifiedString(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.codec.json\0runtime\0001") };






































































































































const native = require ( "nupp.codec.json.provider" )

const contracts = require ( "nupp.codec.json.spi" )













































local WriterImpl = {} WriterImpl.__index = WriterImpl


function WriterImpl:startArray() 
self . raw : startArray ( )
return self
end

function WriterImpl:startObject() 
self . raw : startObject ( )
return self
end

function WriterImpl:__nupp_m_d9930e4662ee507090a52ff19d65f1844d2ce3c0cfdf6a56bcf88945d7356737(name) 
self . raw : key ( name )
return self
end

function WriterImpl:__nupp_m_c0a8d47c0983c3150b410efc4887655d05ff375642ad698506d923a11726a9cc(name) 
self . raw : key ( name )
return self
end

function WriterImpl:__nupp_m_a608c245994e30c585a4f2ccf7304f7636da88fc15037e1894f104eb2e664a71(value) 
self . raw : write ( value )
return self
end

function WriterImpl:__nupp_m_1cebaf002b62e0bdc22fbaea12bf370fec7802f40c430b313765deae871bafc0(value) 
self . raw : write ( value )
return self
end

function WriterImpl:null() 
self . raw : null ( )
return self
end

function WriterImpl:endArray() 
self . raw : endArray ( )
return self
end

function WriterImpl:endObject() 
self . raw : endObject ( )
return self
end

function WriterImpl:flush() 
self . raw : flush ( )
end

function WriterImpl:abort() 
self . raw : abort ( )
end

function WriterImpl:close() 
self . raw : close ( )
end ;_G.nupp.__reflect.link(WriterImpl,__nuppT1[1],{ })




local function writerKey ( self , name ) 
self . raw : key ( name )
return self
end

local function writerWrite ( self , value ) 
self . raw : write ( value )
return self
end

rawset ( (_G.nupp.__reflect.known( WriterImpl ) and  WriterImpl  or  _G.nupp.__reflect.ensure( WriterImpl ,function() return {["annotations"]={},["fields"]={{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="abort",["readable"]=true,["stored"]=false,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="close",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="endArray",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="endObject",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="flush",["readable"]=true,["stored"]=false,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="intersection",["name"]="key",["readable"]=true,["stored"]=false,["type"]=46,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="null",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="startArray",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="startObject",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="intersection",["name"]="write",["readable"]=true,["stored"]=false,["type"]=52,["writable"]=true}},["fingerprint"]="bb118d7af41f27bfc14f87d7617ead759e114e708760024a57e5f286e536c65c",["kind"]="record",["name"]="WriterImpl",["qualifiedName"]="WriterImpl",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={},["requiresFactory"]=true},["copyable"]=false,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="abort",["read"]=2,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="close",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6},{["annotations"]={},["hasDefault"]=false,["name"]="endArray",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="endObject",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="flush",["read"]=2,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="key",["read"]=46,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=46},{["annotations"]={},["hasDefault"]=false,["name"]="null",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="startArray",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="startObject",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="write",["read"]=52,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=52}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.codec.json",["name"]="WriterImpl",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={10},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=4,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="nil"},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=3}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=7,["parameters"]={{["mode"]="takes",["name"]="self",["type"]=1}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="takes",["type"]=1}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=4,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=10,["kind"]="borrowed"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=false,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="startArray",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="startObject",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="key",["read"]=14,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=14},{["annotations"]={},["hasDefault"]=false,["name"]="write",["read"]=21,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=21},{["annotations"]={},["hasDefault"]=false,["name"]="null",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="endArray",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="endObject",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="flush",["read"]=34,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=34},{["annotations"]={},["hasDefault"]=false,["name"]="abort",["read"]=34,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=34},{["annotations"]={},["hasDefault"]=false,["name"]="close",["read"]=35,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=35}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.codec.json.spi",["name"]="Writer",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={38},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=9}},["kind"]="pack"},{["kind"]="intersection",["members"]={15,18}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=17,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10},{["mode"]="plain",["name"]="name",["type"]=16}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="string"},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10},{["mode"]="plain",["type"]=16}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=20,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10},{["mode"]="plain",["name"]="name",["type"]=19}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={},["requiresFactory"]=true},["copyable"]=true,["fields"]={},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.codec.json.spi",["name"]="EncodedString",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10},{["mode"]="plain",["type"]=19}},["kind"]="pack"},{["kind"]="intersection",["members"]={22,30}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=29,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10},{["mode"]="plain",["name"]="value",["type"]=23}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={24,26,27,28,16}},{["element"]=25,["kind"]="array"},{["kind"]="any"},{["kind"]="boolean"},{["kind"]="map",["readKey"]=16,["readValue"]=25,["writeKey"]=16,["writeValue"]=25},{["kind"]="number"},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10},{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=33,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10},{["mode"]="plain",["name"]="value",["type"]=31}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={19,32}},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={},["requiresFactory"]=true},["copyable"]=true,["fields"]={},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.codec.json.spi",["name"]="EncodedValue",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10},{["mode"]="plain",["type"]=31}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=37,["parameters"]={{["mode"]="takes",["name"]="self",["type"]=36}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["cleanups"]={{["kind"]="method",["name"]="close"}},["element"]=10,["kind"]="affine",["transferOnly"]=false},{["alternatives"]={},["head"]={{["mode"]="takes",["type"]=36}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=false,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="close",["read"]=39,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=39}},["index"]={},["kind"]="interface",["metamethods"]={},["name"]="Closeable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={42},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=41,["parameters"]={{["mode"]="takes",["name"]="self",["type"]=40}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["cleanups"]={{["kind"]="method",["name"]="close"}},["element"]=38,["kind"]="affine",["transferOnly"]=false},{["alternatives"]={},["head"]={{["mode"]="takes",["type"]=40}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={43},["constParameters"]={},["copyable"]=false,["fields"]={},["index"]={},["kind"]="interface",["metamethods"]={},["name"]="Affine",["nestedTypes"]={},["nominal"]=true,["origin"]=44,["packArguments"]={},["packParameters"]={},["parameterKinds"]={"const"},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["domain"]="function",["kind"]="constLiteral",["value"]="self.close"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={45},["copyable"]=true,["fields"]={},["index"]={},["kind"]="interface",["metamethods"]={},["name"]="Affine",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={"const"},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["domain"]="function",["kind"]="constVar",["name"]="cleanup"},{["kind"]="intersection",["members"]={47,50}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=48,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1},{["mode"]="plain",["name"]="name",["type"]=16}},["returnPack"]=49,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1},{["mode"]="plain",["type"]=16}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=10}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=51,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1},{["mode"]="plain",["name"]="name",["type"]=19}},["returnPack"]=49,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1},{["mode"]="plain",["type"]=19}},["kind"]="pack"},{["kind"]="intersection",["members"]={53,55}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=54,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1},{["mode"]="plain",["name"]="value",["type"]=23}},["returnPack"]=49,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1},{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=56,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1},{["mode"]="plain",["name"]="value",["type"]=31}},["returnPack"]=49,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1},{["mode"]="plain",["type"]=31}},["kind"]="pack"}}},{["1"]="nupp.codec.json\0runtime\0001",["10"]="../../../../src/nupp/codec/json/spi.nupp\0Writer\0interface\0module\0001",["19"]="nupp.codec.json.spi\0runtime\0002",["32"]="nupp.codec.json.spi\0runtime\0001",["38"]="nupp:prelude.d.nupp\0001424\0interface",["42"]="nupp:prelude.d.nupp\0001048\0interface",["44"]="nupp:prelude.d.nupp\0001048\0interface"} end) ) , "key" , writerKey )
rawset ( (_G.nupp.__reflect.known( WriterImpl ) and  WriterImpl  or  _G.nupp.__reflect.ensure( WriterImpl ,function() return {["annotations"]={},["fields"]={{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="abort",["readable"]=true,["stored"]=false,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="close",["readable"]=true,["stored"]=false,["type"]=6,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="endArray",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="endObject",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="flush",["readable"]=true,["stored"]=false,["type"]=2,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="intersection",["name"]="key",["readable"]=true,["stored"]=false,["type"]=46,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="null",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="startArray",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="func",["name"]="startObject",["readable"]=true,["stored"]=false,["type"]=8,["writable"]=true},{["annotations"]={},["hasDefault"]=false,["kind"]="intersection",["name"]="write",["readable"]=true,["stored"]=false,["type"]=52,["writable"]=true}},["fingerprint"]="bb118d7af41f27bfc14f87d7617ead759e114e708760024a57e5f286e536c65c",["kind"]="record",["name"]="WriterImpl",["qualifiedName"]="WriterImpl",["root"]=1,["schema"]=6,["soa"]={["eligible"]=false,["fields"]={},["reason"]="record is not a struct",["schema"]=1},["types"]={{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={},["requiresFactory"]=true},["copyable"]=false,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="abort",["read"]=2,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="close",["read"]=6,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=6},{["annotations"]={},["hasDefault"]=false,["name"]="endArray",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="endObject",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="flush",["read"]=2,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=2},{["annotations"]={},["hasDefault"]=false,["name"]="key",["read"]=46,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=46},{["annotations"]={},["hasDefault"]=false,["name"]="null",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="startArray",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="startObject",["read"]=8,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=8},{["annotations"]={},["hasDefault"]=false,["name"]="write",["read"]=52,["readable"]=true,["stored"]=false,["writable"]=true,["write"]=52}},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.codec.json",["name"]="WriterImpl",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={10},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=4,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="nil"},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=3}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=7,["parameters"]={{["mode"]="takes",["name"]="self",["type"]=1}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="takes",["type"]=1}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=4,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["element"]=10,["kind"]="borrowed"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=false,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="startArray",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="startObject",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="key",["read"]=14,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=14},{["annotations"]={},["hasDefault"]=false,["name"]="write",["read"]=21,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=21},{["annotations"]={},["hasDefault"]=false,["name"]="null",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="endArray",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="endObject",["read"]=11,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=11},{["annotations"]={},["hasDefault"]=false,["name"]="flush",["read"]=34,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=34},{["annotations"]={},["hasDefault"]=false,["name"]="abort",["read"]=34,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=34},{["annotations"]={},["hasDefault"]=false,["name"]="close",["read"]=35,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=35}},["index"]={},["kind"]="interface",["metamethods"]={},["moduleName"]="nupp.codec.json.spi",["name"]="Writer",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={38},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=9}},["kind"]="pack"},{["kind"]="intersection",["members"]={15,18}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=17,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10},{["mode"]="plain",["name"]="name",["type"]=16}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="string"},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10},{["mode"]="plain",["type"]=16}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=20,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10},{["mode"]="plain",["name"]="name",["type"]=19}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={},["requiresFactory"]=true},["copyable"]=true,["fields"]={},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.codec.json.spi",["name"]="EncodedString",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10},{["mode"]="plain",["type"]=19}},["kind"]="pack"},{["kind"]="intersection",["members"]={22,30}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=29,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10},{["mode"]="plain",["name"]="value",["type"]=23}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={24,26,27,28,16}},{["element"]=25,["kind"]="array"},{["kind"]="any"},{["kind"]="boolean"},{["kind"]="map",["readKey"]=16,["readValue"]=25,["writeKey"]=16,["writeValue"]=25},{["kind"]="number"},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10},{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=33,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10},{["mode"]="plain",["name"]="value",["type"]=31}},["returnPack"]=13,["returns"]={9},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["kind"]="union",["members"]={19,32}},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["construction"]={["declared"]=false,["params"]={},["requiresFactory"]=true},["copyable"]=true,["fields"]={},["index"]={},["kind"]="record",["metamethods"]={},["moduleName"]="nupp.codec.json.spi",["name"]="EncodedValue",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=10},{["mode"]="plain",["type"]=31}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=12,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=10}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=true,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=37,["parameters"]={{["mode"]="takes",["name"]="self",["type"]=36}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["cleanups"]={{["kind"]="method",["name"]="close"}},["element"]=10,["kind"]="affine",["transferOnly"]=false},{["alternatives"]={},["head"]={{["mode"]="takes",["type"]=36}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={},["copyable"]=false,["fields"]={{["annotations"]={},["hasDefault"]=false,["name"]="close",["read"]=39,["readable"]=true,["stored"]=true,["writable"]=true,["write"]=39}},["index"]={},["kind"]="interface",["metamethods"]={},["name"]="Closeable",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={},["staticFields"]={},["supertypes"]={42},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=41,["parameters"]={{["mode"]="takes",["name"]="self",["type"]=40}},["returnPack"]=5,["returns"]={3},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["cleanups"]={{["kind"]="method",["name"]="close"}},["element"]=38,["kind"]="affine",["transferOnly"]=false},{["alternatives"]={},["head"]={{["mode"]="takes",["type"]=40}},["kind"]="pack"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={43},["constParameters"]={},["copyable"]=false,["fields"]={},["index"]={},["kind"]="interface",["metamethods"]={},["name"]="Affine",["nestedTypes"]={},["nominal"]=true,["origin"]=44,["packArguments"]={},["packParameters"]={},["parameterKinds"]={"const"},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["domain"]="function",["kind"]="constLiteral",["value"]="self.close"},{["annotations"]={},["associatedTypes"]={},["constArguments"]={},["constParameters"]={45},["copyable"]=true,["fields"]={},["index"]={},["kind"]="interface",["metamethods"]={},["name"]="Affine",["nestedTypes"]={},["nominal"]=true,["packArguments"]={},["packParameters"]={},["parameterKinds"]={"const"},["staticFields"]={},["supertypes"]={},["typeArguments"]={},["typeBounds"]={},["typeParameters"]={}},{["domain"]="function",["kind"]="constVar",["name"]="cleanup"},{["kind"]="intersection",["members"]={47,50}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=48,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1},{["mode"]="plain",["name"]="name",["type"]=16}},["returnPack"]=49,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1},{["mode"]="plain",["type"]=16}},["kind"]="pack"},{["alternatives"]={},["head"]={{["mode"]="plain",["type"]=10}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=51,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1},{["mode"]="plain",["name"]="name",["type"]=19}},["returnPack"]=49,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1},{["mode"]="plain",["type"]=19}},["kind"]="pack"},{["kind"]="intersection",["members"]={53,55}},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=54,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1},{["mode"]="plain",["name"]="value",["type"]=23}},["returnPack"]=49,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1},{["mode"]="plain",["type"]=23}},["kind"]="pack"},{["borrowedFromMany"]={},["borrowedResult"]=1,["constParameters"]={},["kind"]="func",["noReturn"]=false,["noYield"]=false,["packParameters"]={},["parameterKinds"]={},["parameterPack"]=56,["parameters"]={{["mode"]="exclusive",["name"]="self",["type"]=1},{["mode"]="plain",["name"]="value",["type"]=31}},["returnPack"]=49,["returns"]={10},["typeBounds"]={},["typeParameters"]={},["vararg"]=false},{["alternatives"]={},["head"]={{["mode"]="exclusive",["type"]=1},{["mode"]="plain",["type"]=31}},["kind"]="pack"}}},{["1"]="nupp.codec.json\0runtime\0001",["10"]="../../../../src/nupp/codec/json/spi.nupp\0Writer\0interface\0module\0001",["19"]="nupp.codec.json.spi\0runtime\0002",["32"]="nupp.codec.json.spi\0runtime\0001",["38"]="nupp:prelude.d.nupp\0001424\0interface",["42"]="nupp:prelude.d.nupp\0001048\0interface",["44"]="nupp:prelude.d.nupp\0001048\0interface"} end) ) , "write" , writerWrite )



















decode=function ( text , nullValue ) 
local ok , value = pcall ( native . decode , text , nullValue )
if not ok then
return nil , tostring ( value )
end

return value , nil
end ;__nuppExports["decode"]=decode





















pull=function ( text , shape , nullValue ) 
local ok , value = pcall ( native . pull , text , shape , nullValue )
if not ok then
return nil , tostring ( value )
end

return value , nil
end ;__nuppExports["pull"]=pull















arrayOf=function ( shape ) 
if shape == nil then
return native . arrayOf ( )
end
return native . arrayOf ( shape )
end ;__nuppExports["arrayOf"]=arrayOf










asArray=function ( value ) 
return native . asArray ( value )
end ;__nuppExports["asArray"]=asArray











asObject=function ( value ) 
return native . asObject ( value )
end ;__nuppExports["asObject"]=asObject
















isArray=function ( value ) 
return native . isArray ( value )
end ;__nuppExports["isArray"]=isArray











encode=function ( value , nullValue ) 
if nullValue == nil then
return native . encode ( value )
end
return native . encode ( value , nullValue )
end ;__nuppExports["encode"]=encode













encoded=function ( value , nullValue ) 
if nullValue == nil then
return native . encoded ( value )
end
return native . encoded ( value , nullValue )
end ;__nuppExports["encoded"]=encoded











numberToken=function ( text ) 
return native . numberToken ( text )
end ;__nuppExports["numberToken"]=numberToken









encodedString=function ( value ) 
return native . encodedString ( value )
end ;__nuppExports["encodedString"]=encodedString









verified=function ( text ) 
return native . verified ( text )
end ;__nuppExports["verified"]=verified









verifiedString=function ( text ) 
return native . verifiedString ( text )
end ;__nuppExports["verifiedString"]=verifiedString














newWriter=function ( out , nullValue ) 
if nullValue == nil then
return ( _G.setmetatable({ raw =  native . newWriter ( out ) }, WriterImpl) )
end
return ( _G.setmetatable({ raw =  native . newWriter ( out , nullValue ) }, WriterImpl) )
end ;__nuppExports["newWriter"]=newWriter




const NULL = native . NULL ;__nuppExports["NULL"]=NULL



const EMPTY_ARRAY = native . EMPTY_ARRAY ;__nuppExports["EMPTY_ARRAY"]=EMPTY_ARRAY



const EMPTY_OBJECT = native . EMPTY_OBJECT ;__nuppExports["EMPTY_OBJECT"]=EMPTY_OBJECT
 end);if not __nuppOk then package.loaded["nupp.codec.json"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.codec.json"]=__nuppExports;return __nuppExports