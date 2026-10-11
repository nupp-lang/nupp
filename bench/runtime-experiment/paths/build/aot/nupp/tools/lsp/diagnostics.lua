_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()















local text = require ( "nupp.tools.lsp.text" )
local wire = require ( "nupp.tools.lsp.wire" )

local fs = require ( "nupp.compiler.fs" )
local isFatal = require ( "nupp.compiler.diagnostics" ) . isFatal

local uriToPath , pathToUri = text . uriToPath , text . pathToUri
local positionAtOffset = text . positionAtOffset
local readFile = text . readFile

local diagnostics = { }






































local EDITOR_ADVICE = {
[ "NUPP2120" ] = "warning" ,
[ "NUPP2507" ] = "note" ,
}

local PROTOCOL_SEVERITY = {
error = 1 ,
warning = 2 ,
note = 3 ,
}




function diagnostics . install ( s ) 
local notify = s . notify

local function toLspDiagnostics ( errors , source ) 
local out = wire . array ( { } )
for _ , e in ipairs ( errors ) do
local start = source and positionAtOffset ( source , e . offset or 1 )
or { line = math . max ( 0 , ( e . line or 1 ) - 1 ) , character = math . max ( 0 , ( e . col or 1 ) - 1 ) }
local finish = source and positionAtOffset ( source , ( e . offset or 1 ) + ( e . length or 0 ) )
or { line = start . line , character = start . character + ( e . length or 1 ) }
local related = wire . array ( { } )
for _ , item in ipairs ( e . related or { } ) do
local path = item . filename or e . filename
local uri = path and pathToUri ( path ) or nil
local relatedDoc = uri and s . documents [ uri ] or nil
local relatedSource = relatedDoc and relatedDoc . text
or ( path and s . inc . fileText ( path ) )
or ( path and readFile ( path ) )
local relatedStart = relatedSource and positionAtOffset ( relatedSource , item . offset or 1 )
or { line = math . max ( 0 , ( item . line or 1 ) - 1 ) , character = math . max ( 0 , ( item . col or 1 ) - 1 ) }
local relatedFinish = relatedSource
and positionAtOffset ( relatedSource , ( item . offset or 1 ) + ( item . length or 0 ) )
or { line = relatedStart . line , character = relatedStart . character + ( item . length or 1 ) }
if uri then
related [
# related + 1
] = {
location = { uri = uri , range = { start = relatedStart , [ "end" ] = relatedFinish } } ,
message = item . message or item . msg or "related location" ,
}
end
end
local message = e . msg
for _ , note in ipairs ( e . notes or { } ) do
message = message .. "\n\nnote: " .. note
end
if e . help then
message = message .. "\n\nhelp: " .. e . help
end
out [
# out + 1
] = {
range = { start = start , [ "end" ] = finish , } ,
severity = PROTOCOL_SEVERITY [ EDITOR_ADVICE [ e . code ] or e . severity ] or 1 ,
code = e . code or "NUPP1001" ,
source = "nupp" ,
message = message ,
relatedInformation = # related > 0 and related or nil ,
data = ( e . help or e . notes or e . lint ) and { help = e . help , notes = e . notes , lint = e . lint , } or nil ,
}
end

return out
end








local function aotRefusals ( doc , path , root , r ) 
if doc . aotFor == r then
return doc . aotRefusals
end
local found = { }
local text = s . inc . fileText ( path ) or doc . text
local fatal = false
for _ , e in ipairs ( r . diags or { } ) do
fatal = fatal or isFatal ( e )
end
if r . result ~= nil and not r . syntax and not fatal and text ~= nil and text : find ( "@aot" , 1 , true ) ~= nil then
local aotcheck = require ( "nupp.tools.build.aotcheck" )
local config = s . inc . env . config or { }
local target = config . _target or ( require ( "nupp.tools.build.tasks" ) ) . targetConfig ( config )
if target ~= nil
and aotcheck . applies ( target . aot )
and aotcheck . projectSource ( root , config . include , target . outDir or "build" , path )
then


local scope = ( require ( "nupp.tools.build.modules" ) ) . targetScope ( root , target , {
inc = s . inc ,
stageBundled = function ( _ ) 
return nil
end ,
} )
local reached = scope == nil
if not reached then
local canonical = fs . canonical ( path )
for member in pairs ( scope ) do
reached = reached or fs . canonical ( member ) == canonical
end
end
if reached then
found = aotcheck . refusals ( text , path , r . result , target )
end
end
end
doc . aotFor = r
doc . aotRefusals = found

return found
end




local function checkAndPublish ( uri , force ) 
local doc = s . documents [ uri ]
if not doc then
return false
end
local path = uriToPath ( uri )



local root = s . useRoot ( path )
local r = s . inc . checkFile ( path )
local changed = r ~= doc . checkResult
doc . checkResult = r
doc . path = path
doc . result = r . result



if r . result and not r . syntax then
doc . checked = r . result
end
if force or changed then



local published = r . diags
local refused = aotRefusals ( doc , path , root , r )
if # refused > 0 then
published = { }
for _ , e in ipairs ( r . diags or { } ) do
published [ # published + 1 ] = e
end
for _ , e in ipairs ( refused ) do
published [ # published + 1 ] = e
end
end
notify ( "textDocument/publishDiagnostics" , {
uri = uri ,
version = doc . version ,
diagnostics = toLspDiagnostics ( published , doc . text ) ,
} )
end

return changed
end




local function refreshOpenDocuments ( changedUri ) 
if changedUri then
checkAndPublish ( changedUri , true )
end
local uris = { }
for uri in pairs ( s . documents ) do
if uri ~= changedUri then
uris [ # uris + 1 ] = uri
end
end
table . sort ( uris )
for _ , uri in ipairs ( uris ) do
checkAndPublish ( uri , false )
end
end

return {
toLspDiagnostics = toLspDiagnostics ,
checkAndPublish = checkAndPublish ,
refreshOpenDocuments = refreshOpenDocuments ,
}
end

local __nuppExportValue= diagnostics ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.lsp.diagnostics"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.lsp.diagnostics"]=__nuppExports;return __nuppExports