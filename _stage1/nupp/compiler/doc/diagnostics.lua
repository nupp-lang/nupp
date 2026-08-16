_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);




















local explainMod = require ( "nupp.compiler.explain" )
local htmlMod = require ( "nupp.compiler.doc.html" )
local lintsMod = require ( "nupp.compiler.lints" )

local diagnostics = { }




















local function anchor ( code )
return "#" .. code : lower ( )
end

local function lintFor ( code )
for _ , candidate in ipairs ( lintsMod . all ) do
if candidate . code == code then
return candidate
end
end

return nil
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
local out = { "### " .. code , "" , entry . summary .. "." , "" }
if entry . wrong then
out [ # out + 1 ] = fence ( "Reported" , entry . wrong )
out [ # out + 1 ] = ""
end
out [ # out + 1 ] = entry . rule
out [ # out + 1 ] = ""
if entry . strict then
out [ # out + 1 ] = "This applies only under `--strict`, or in a `.nupp` file."
out [ # out + 1 ] = ""
end
if entry . right then
out [ # out + 1 ] = fence ( "Accepted" , entry . right )
out [ # out + 1 ] = ""
elseif entry . family then
out [
# out + 1
] = "This code has no example pair of its own. The rule above is "
.. "its family's, which is what the compiler knows about it."
out [ # out + 1 ] = ""
end
local lint = lintFor ( code )
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
names [
# names + 1
] = listed [ other ] and ( "[**" .. other .. "**](" .. anchor ( other ) .. ")" ) or ( "**" .. other .. "**" )
end
trail [ # trail + 1 ] = "Related: " .. table . concat ( names , ", " ) .. "."
end
local target = entry . docs : match ( "^([^#]+)" ) or entry . docs
if published [ target ] then
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

local out = {
"# " .. title ,
"" ,
"Every code the compiler reports specifically, with the rule it enforces "
.. "and, where one is known, the program that reports it beside the same "
.. "program corrected. `nupp explain <code>` prints the same thing in a "
.. "terminal." ,
"" ,
"A code that resolves only through its family is not here. The families "
.. "are the leading digit, and each one answers for every code under it." ,
"" ,
}
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
out [ # out + 1 ] = "## " .. family
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

return { path = settings . path or "diagnostics" , title = title , markdown = table . concat ( out , "\n" ) }
end

return diagnostics
