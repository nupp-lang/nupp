_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()
























local explainMod = require ( "nupp.tools.explain" )
local htmlMod = require ( "nupp.tools.doc.html" )
local lintsMod = require ( "nupp.compiler.lints" )

local diagnostics = { }






























local function anchor ( code ) 
return "#" .. code : lower ( )
end

local function fence ( caption , source ) 
return "```nupp [" .. caption .. "]\n" .. source : gsub ( "%s+$" , "" ) .. "\n```"
end

local function section (
code ,
entry ,
listed ,
published
) 
local out = { "#### " .. code , "" , entry . summary .. "." , "" }
if entry . wrong then
out [ # out + 1 ] = fence ( "Reported" , entry . wrong )
out [ # out + 1 ] = ""
end
out [ # out + 1 ] = entry . rule
out [ # out + 1 ] = ""
if entry . aot then
out [
# out + 1
] = "This applies only to a build target whose `aot` policy compiles `@aot` functions, which is every policy but `off`."

out [ # out + 1 ] = ""
end
if entry . right then
out [ # out + 1 ] = fence ( "Accepted" , entry . right )
out [ # out + 1 ] = ""
elseif entry . family then
out [
# out + 1
] = "This code has no example pair of its own. The rule above is its family's, which is what the compiler knows about it."

out [ # out + 1 ] = ""
end
local lint = lintsMod . get ( code )
if lint then
out [
# out + 1
] = "Reported by the `"
.. lint . name
.. "` lint, category `"
.. lint . category
.. "`, at `"
.. lint . level
.. "` by default. Configure it by name or by category."
out [ # out + 1 ] = ""
end
local trail = { }
if # entry . related > 0 then
local names = { }
for _ , other in ipairs ( entry . related ) do
names [ # names + 1 ] = listed [ other ] and ( "[**" .. other .. "**](" .. ( "#" .. other : lower ( ) ) .. ")" )
or ( "**" .. other .. "**" )
end
trail [ # trail + 1 ] = "Related: " .. table . concat ( names , ", " ) .. "."
end
local target = entry . docs : match ( "^([^#]+)" ) or entry . docs
if entry . docs == "docs/reference/diagnostics.md" .. ( "#" .. code : lower ( ) ) then


elseif published [ target ] then
trail [ # trail + 1 ] = "Reference: [" .. entry . docs .. "](" .. entry . docs .. ")."
else
trail [ # trail + 1 ] = "Reference: `" .. entry . docs .. "` in the repository."
end
if entry . wrong then
trail [
# trail + 1
] = "[Open the reported program in the playground](/playground/#source=" .. htmlMod . urlFragmentEscape (
( entry . wrong : gsub ( "%s+$" , "" ) )
) .. ")."
end
out [ # out + 1 ] = table . concat ( trail , " " )
out [ # out + 1 ] = ""

return out
end


function diagnostics . page ( settings , published ) 
if not settings then
return nil
end
local known = published or { }
local title = settings . title or "Diagnostic index"
local codes = explainMod . documented ( )
local listed = { }
for _ , code in ipairs ( codes ) do
listed [ code ] = true
end

local out = { }
if settings . prose then
out [ # out + 1 ] = ( settings . prose : gsub ( "%s+$" , "" ) )
out [ # out + 1 ] = ""
else
out [ # out + 1 ] = "# " .. title
out [ # out + 1 ] = ""
end
out [ # out + 1 ] = "## Diagnostic index"
out [ # out + 1 ] = ""
out [
# out + 1
] = "Every code the compiler reports specifically, with the rule it enforces and, where one is known, the program that reports it beside the same program corrected. `nupp explain <code>` prints the same thing in a terminal."



out [ # out + 1 ] = ""
out [
# out + 1
] = "A code that resolves only through its family is not here. The families are the leading digit, and each one answers for every code under it."

out [ # out + 1 ] = ""
local byFamily = { }
local order = { }
for _ , code in ipairs ( codes ) do
local family = explainMod . familyTitle ( code ) or "Other"
local bucket = byFamily [ family ]
if not bucket then
bucket = { }
byFamily [ family ] , order [ # order + 1 ] = bucket , family
end
bucket [ # bucket + 1 ] = code
end
for _ , family in ipairs ( order ) do
out [ # out + 1 ] = "### " .. family
out [ # out + 1 ] = ""
for _ , code in ipairs ( byFamily [ family ] or { } ) do
local entry = explainMod . lookup ( code )
if entry then
for _ , line in ipairs ( section ( code , entry , listed , known ) ) do
out [ # out + 1 ] = line
end
end
end
end

return {
path = settings . path or "diagnostics" ,
title = title ,
source = settings . source ,
redirects = settings . redirects ,
markdown = table . concat ( out , "\n" ) ,
symbols = nil
}
end

local __nuppExportValue= diagnostics ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.tools.doc.diagnostics"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.tools.doc.diagnostics"]=__nuppExports;return __nuppExports