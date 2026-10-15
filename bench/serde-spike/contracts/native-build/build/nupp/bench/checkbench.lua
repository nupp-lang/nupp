_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()





local parser = require ( "nupp.compiler.syntax.parser" )

local checkMod = require ( "nupp.compiler.check" )
local envMod = require ( "nupp.compiler.project.env" )
local triviaarena = require ( "nupp.compiler.syntax.triviaarena" )
local tableProvider = require ( "nupp.compiler.syntax.triviaarena.table" )

local bench = { }

function bench . setup ( ) 
triviaarena . install ( tableProvider )
return true
end



local function walk ( node , sum , count ) 
local kind = node . kind
if kind == nil then
return sum , count
end
local t = node . inferredType
if t ~= nil and type ( t ) == "table" and type ( t . tag ) == "string" then
const tag = t . tag
for i = 1 , # tag do
sum = ( sum * 31 + string . byte ( tag , i ) ) % 1000000007
end
count = count + 1
end
for _ , child in ipairs ( node ) do
sum , count = walk ( child , sum , count )
end

return sum , count
end



function bench . check ( source ) 
local result = parser . parse ( source , "bench.nupp" )
if # result . errors > 0 then
return -1 , # result . errors , 0
end
local env = envMod . new ( "." , { memoryOnly = true , cache = false , nativeCompilerServices = false } )
local diags = checkMod . check ( result , "bench.nupp" , env , { } )
local sum , count = walk ( result . root , 0 , 0 )
for _ , d in ipairs ( diags ) do
const code = tostring ( d . code )
for i = 1 , # code do
sum = ( sum * 31 + string . byte ( code , i ) ) % 1000000007
end
end

return # diags , count , sum
end


function bench . dump ( source ) 
local result = parser . parse ( source , "bench.nupp" )
local env = envMod . new ( "." , { memoryOnly = true , cache = false , nativeCompilerServices = false } )
local diags = checkMod . check ( result , "bench.nupp" , env , { } )
local out = { }
for _ , d in ipairs ( diags ) do
out [ # out + 1 ] = tostring ( d . code ) .. " " .. tostring ( d . line ) .. ":" .. tostring ( d . col ) .. " " .. tostring ( d . msg )
end

return table . concat ( out , "\n" )
end


function bench . probe ( name ) 
local env = envMod . new ( "." , { memoryOnly = true , cache = false , nativeCompilerServices = false } )
local bundledMod = require ( "nupp.compiler.bundled" )
local parts = { }
parts [ # parts + 1 ] = "moduleDir=" .. tostring ( bundledMod . moduleDir ( ) )
parts [ # parts + 1 ] = "compilerRoot=" .. tostring ( envMod . compilerRoot ( ) )
parts [ # parts + 1 ] = "implementation=" .. tostring ( ( env ) . bundledImplementation ( name ) )
local source = bundledMod . source ( "/" .. name : gsub ( "%." , "/" ) .. "/init.nupp" )
parts [ # parts + 1 ] = "source=" .. tostring ( source and # source or nil )
local ok , loaded = pcall ( ( env ) . loadBundledModule , name )
parts [ # parts + 1 ] = "loaded=" .. tostring ( ok ) .. "/" .. type ( loaded ) .. ( ok and "" or ( "/" .. tostring ( loaded ) ) )
local viaIndex = ( env ) . bundled [ name ]
parts [ # parts + 1 ] = "viaIndex=" .. type ( viaIndex )

return table . concat ( parts , "\n" )
end

local __nuppExportValue= bench ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.bench.checkbench"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.bench.checkbench"]=__nuppExports;return __nuppExports