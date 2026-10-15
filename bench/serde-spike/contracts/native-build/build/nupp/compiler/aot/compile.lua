_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.aot.compile\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.aot.compile\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.compiler.aot.compile\0runtime\0003") };







local bindingRules = require ( "nupp.compiler.aot.binding" )
local hash = require ( "nupp.compiler.hash" )
local cst = require ( "nupp.compiler.syntax.cst" )
local lexer = require ( "nupp.compiler.syntax.lexer" )
local gpuartifact = require ( "nupp.compiler.aot.gpuartifact" )
local gpuBinding = require ( "nupp.compiler.aot.gpubinding" )
local lower = require ( "nupp.compiler.aot.lower" )
local loopAnalysis = require ( "nupp.compiler.aot.loops" )
local parser = require ( "nupp.compiler.syntax.parser" )
local scalarIR = require ( "nupp.compiler.aot.scalar" )
local shapes = require ( "nupp.compiler.aot.simdshape" )
local targets = require ( "nupp.compiler.aot.target" )
local text = require ( "nupp.compiler.aot.text" )
local types = require ( "nupp.compiler.types" )
local verify = require ( "nupp.compiler.aot.verify" )
local visit = require ( "nupp.compiler.aot.visit" )

local compile = { }


compile.Diagnostic = {} compile.Diagnostic.__index = compile.Diagnostic ;_G.nupp.__reflect.link(compile.Diagnostic,__nuppT1[1],{ })












compile . REFUSED_BODY = "NUPP2905"

compile . REFUSED_TIER = "NUPP2906"
compile . REFUSED_GPU = "NUPP2907"
compile . REFUSED_SPECIALIZATION = "NUPP2908"
compile . NO_AOT_FUNCTION = "NUPP2909"









compile.Site = {} compile.Site.__index = compile.Site ;_G.nupp.__reflect.link(compile.Site,__nuppT1[2],{ })













compile.Artifacts = {} compile.Artifacts.__index = compile.Artifacts ;_G.nupp.__reflect.link(compile.Artifacts,__nuppT1[3],{ _G.nupp.__reflect.reference("nupp.compiler.aot.scalar\0runtime\00092","nupp.compiler.aot.scalar") , _G.nupp.__reflect.reference("nupp.compiler.aot.loops\0runtime\0001","nupp.compiler.aot.loops") , _G.nupp.__reflect.reference("nupp.compiler.aot.gpuartifact\0runtime\0001","nupp.compiler.aot.gpuartifact") , __nuppT1[2] })



























function compile . renderDiagnostic ( problem ) 
return ("%s:%d:%d: aot: %s: %s") : format ( problem . file , problem . line , problem . column , problem . code , problem . message )
end



local REFUSED = { }




local function qualifySymbols ( programs , filename ) 
local identity = hash . digest ( filename ) : sub ( 1 , 16 )
local registrars = { }
local prefix = scalarIR . symbolPrefix ( filename )
for _ , program in ipairs ( programs ) do
program . symbol = prefix .. program . symbol : sub ( 4 )


for _ , helper in ipairs ( program . helpers or { } ) do
if helper . native == true and helper . qualified ~= true and helper . uniqueName : sub ( 1 , # prefix ) ~= prefix then
helper . uniqueName = prefix .. helper . uniqueName : sub ( 4 )
end
end
if program . registrar ~= nil then
local registrar = program . registrar
local qualified = registrars [ registrar ]
if qualified == nil then
qualified = "ks_register_" .. identity .. "_" .. registrar : sub ( 13 )
registrars [ registrar ] = qualified
end
program . registrar = qualified
end
end
end







function compile . site ( application ) 
local first = cst . firstToken ( application . at )
local last = cst . lastToken ( application . tail )
local from = first ~= nil and ( first ) . offset or 1
local to = last ~= nil and ( ( last ) . offset + # ( last ) . text - 1 ) or from

return ( _G.setmetatable({ from =  from ,  to =  to }, compile.Site) )
end



function compile . header ( source , declaration ) 
if declaration == nil or declaration . body == nil then
return nil
end
local first = cst . firstToken ( declaration )
local bodyFirst = cst . firstToken ( ( declaration . body ) . body )
local headerFrom = first ~= nil and first . offset or 1
local headerTo = bodyFirst ~= nil and bodyFirst . offset - 1 or headerFrom

return source : sub ( headerFrom , headerTo )
end

local function sitePosition ( source , offset ) 
local before = source : sub ( 1 , offset - 1 )
local _ , newlines = before : gsub ( "\n" , "" )
local lineStart = before : match ( ".*\n()" ) or 1
return newlines + 1 , offset - lineStart + 1
end



local function rejection ( filename , diagnostics ) 
return function ( at , message ) 
diagnostics [
# diagnostics + 1
] = _G.setmetatable({ file =
filename ,  line =
at ~= nil and ( at ) . line or 1 ,  column =
at ~= nil and ( at ) . column or 1 ,  message =
message ,  code =
compile . REFUSED_BODY }, compile.Diagnostic)

error ( REFUSED , 0 )
end
end



local function nameRegistrar ( programs ) 
local builderSymbols = { }
for _ , program in ipairs ( programs ) do
if program . entryMode == "lua-builder" then
builderSymbols [ # builderSymbols + 1 ] = program . symbol
end
end
if # builderSymbols == 0 then
return
end
local registrar = "ks_register_" .. hash . digest ( table . concat ( builderSymbols , "\0" ) ) : sub ( 1 , 16 )
for _ , program in ipairs ( programs ) do
if program . entryMode == "lua-builder" then
program . registrar = registrar
end
end
end




function compile . vectors ( selected ) 
return selected == nil or ( targets . TIERS [ ( selected ) . tier ] or 0 ) > 0
end












function compile . lower (
source ,
filename ,
parsed ,
selected
) 
local tree = parsed or parser . parse ( source , filename )
local diagnostics = { }
if # tree . errors > 0 then
for _ , problem in ipairs ( tree . errors ) do
diagnostics [
# diagnostics + 1
] = _G.setmetatable({ file =
filename ,  line =
problem . line or 1 ,  column =
problem . col or 1 ,  message =
"syntax error: " .. problem . msg ,  code =
problem . code or "NUPP1005" }, compile.Diagnostic)

end

return { } , diagnostics , { }
end

local context = _G.setmetatable({ checked =
parsed ~= nil ,  vectors =
compile . vectors ( selected ) ,  nativeCpu =
selected == nil or selected . architecture ~= "wasm32" ,  constantNames =
{ } ,  constantValues =
{ } ,  reject =
rejection ( filename , diagnostics ) ,  unreachableValues =  {} }, lower.Context)





local wasChecked = parsed ~= nil
local sites = { }
local ok , lowered = pcall ( function ( ) 
local found = lower . scan ( tree . root , wasChecked )
if # found . applications == 0 then
diagnostics [
# diagnostics + 1
] = _G.setmetatable({ file =
filename ,  line =
1 ,  column =
1 ,  message =
"no @aot function was found" ,  code =
compile . NO_AOT_FUNCTION }, compile.Diagnostic)

error ( REFUSED , 0 )
end

local programs = { }
for _ , application in ipairs ( found . applications ) do
local declaration = application . tail
local body = declaration ~= nil and declaration . body or nil
if body == nil or ( body ) . generics == nil then
programs [ # programs + 1 ] = lower . program ( found , application , wasChecked , context )
local site = compile . site ( application )
site . header = compile . header ( source , declaration )
sites [ # sites + 1 ] = site
end
end

nameRegistrar ( programs )
for position , program in ipairs ( programs ) do
programs [ position ] = verify . program ( program )
end

return programs
end )

if not ok then
if lowered ~= REFUSED then
error ( lowered , 0 )
end

return { } , diagnostics , { }
end

return lowered , diagnostics , sites
end

local function numericForRuntime ( program , selected ) 
program . numericForRuntime = targets . numericForRuntime ( selected )
if program . numericForRuntimeRequired == nil then
local counted = program . loop ~= nil
visit . program (
program ,
_G.setmetatable({ scalarStatement =  function ( statement ) 
counted = counted or statement . op == "fornum"
end }, visit.Visitor)
)
program . numericForRuntimeRequired = counted
end
end









function compile . constSpecializations (
source ,
filename ,
parsed ,
selected ,
symbolTier ,
plans
) 
const maxPerModule = 8
local diagnostics = { }
local laneRefusals = nil
local context = _G.setmetatable({ checked =
true ,  vectors =
compile . vectors ( selected ) ,  nativeCpu =
selected . architecture ~= "wasm32" ,  reject =
rejection ( filename , diagnostics ) ,  unreachableValues =  {} ,  constantNames =  {} ,  constantValues =  {} }, lower.Context)




if # parsed . errors > 0 then
return nil , {
_G.setmetatable({ file =
filename ,  line =
1 ,  column =
1 ,  message =
"const specialization needs a checked source" ,  code =
compile . REFUSED_SPECIALIZATION }, compile.Diagnostic)
,
}
end

local found = lower . scan ( parsed . root , true )
local candidates = { }
local candidatesByDefinition = { }
for _ , application in ipairs ( found . applications ) do
local declaration = application . tail
local body = declaration ~= nil
and declaration . kind == "localFuncStmt"
and ( declaration ) . body
or nil
local generics = body ~= nil and ( body ) . generics or nil
if generics ~= nil then
local clause = generics
local binders = { }
local onlyConst = # clause . names > 0
for position , token in ipairs ( clause . names ) do
onlyConst = onlyConst and clause . consts [ position ] == true
if clause . consts [ position ] == true then
binders [
# binders + 1
] = {
name = token . text ,
domain = clause . domains [ position ] ~= nil and clause . domains [ position ] . text or "" ,
carriers = { } ,
}
end
end
if onlyConst and # binders > 0 then
local byBinder = { }
for _ , binder in ipairs ( binders ) do
byBinder [ binder . name ] = binder
end
for position , raw in ipairs ( ( body ) . params or { } ) do
local param = raw
local annotation = param . type
local binder = annotation ~= nil
and annotation . kind == "tname"
and ( annotation ) . typeArgs == nil
and ( annotation ) . base ~= nil
and byBinder [ ( ( annotation ) . base ) . text ]
or nil
if binder ~= nil and param . name ~= nil then
binder . carriers [ # binder . carriers + 1 ] = { position = position , name = param . name . text , }
end
end
local complete = true
for _ , binder in ipairs ( binders ) do
complete = complete and # binder . carriers > 0
end
local name = ( declaration ) . name
if complete and name ~= nil then
local candidate = {
application = application ,
definition = name . definition ,
binders = binders ,
seen = { } ,
specializations = { } ,
dispatches = { } ,
classIndex = { } ,
}
candidates [ name . text ] = candidate
candidatesByDefinition [ name . definition ] = candidate
end
end
end
end

local function literal ( parameter , source ) 
if parameter == nil or parameter . tag ~= "literal" or parameter . base == nil then
return nil , nil
end
local domain = parameter . base . tag
if domain == "integer" then
local written = tostring ( parameter . constant )
return "integer:" .. written , _G.setmetatable({ op =
"constant" ,  value =
written ,  type =
"f64" ,  source =
source }, scalarIR.Constant)

elseif domain == "boolean" then
local value = parameter . constant == true
return "boolean:" .. tostring (
value
) , _G.setmetatable({ op =  "bool" ,  value =  value ,  type =  "bool" ,  source =  source }, scalarIR.Bool)
elseif domain == "string" then
local value = tostring ( parameter . constant )
return "string:" .. tostring (
# value
) .. ":" .. value , _G.setmetatable({ op =
"lua_string" ,  value =
value ,  type =
"lua_string" ,  source =
source }, scalarIR.LuaString)

end

return nil , nil
end

local specializationLines = { }
local specializationSites = { }

local function walk ( node ) 
if node == nil or cst . isToken ( node ) then
return
end
if node . kind == "call" then
local call = node
local callee = call . obj
local token = callee ~= nil and callee . kind == "name" and ( callee ) . token or nil
local candidate = token ~= nil and candidates [ ( token ) . text ] or nil
if candidate ~= nil and ( token ) . definition == candidate . definition then
local signature = ( call ) . signatureType
local values = { }
local omitted = { }
local tuple = { }
local sourceSite = lower . site ( call )
local complete = signature ~= nil and signature . tag == "func"
for _ , binder in ipairs ( candidate . binders ) do
local binderKey = nil
for _ , carrier in ipairs ( binder . carriers ) do
local key = nil
local value = nil
if complete then
key , value = literal ( signature . params [ carrier . position ] , sourceSite )
end
if key == nil or value == nil or binderKey ~= nil and binderKey ~= key then
complete = false
do break end
end
binderKey = key
values [ carrier . name ] = value
omitted [ carrier . position ] = true
end
if not complete or binderKey == nil then
do break end
end
tuple [ # tuple + 1 ] = binder . domain .. ":" .. binder . name .. "=" .. binderKey
end
if complete then
local canonical = filename .. "\0" .. (
token
) . text .. "\0" .. types . tostring ( signature ) .. "\0" .. table . concat ( tuple , "\0" )
local key = hash . digest ( canonical )
if not candidate . seen [ key ] then
candidate . seen [ key ] = true
specializationLines [ # specializationLines + 1 ] = sourceSite . line
specializationSites [ # specializationSites + 1 ] = { file = filename , line = sourceSite . line , }
local lowered = _G.setmetatable({ name =
"__nuppConst_" .. (
token
) . text : gsub ( "[^%w_]" , "_" ) .. "_" .. key : sub ( 1 , 16 ) ,  signature =
signature ,  values =
values ,  omitted =
omitted }, lower.Specialization)

candidate . specializations [ # candidate . specializations + 1 ] = lowered
candidate . dispatches [
# candidate . dispatches + 1
] = { specialization = lowered , index = # candidate . specializations , }
end
end
end
end
for _ , child in ipairs ( node ) do
walk ( child )
end
end

if plans ~= nil then
for _ , plan in ipairs ( plans ) do
local candidate = candidatesByDefinition [ plan . definition ]
if candidate ~= nil then
for _ , specialization in ipairs ( plan . specializations ) do
if not candidate . seen [ specialization . key ] then
candidate . seen [ specialization . key ] = true
local values = { }
local complete = true
for _ , binder in ipairs ( candidate . binders ) do
for _ , carrier in ipairs ( binder . carriers ) do
local _ , value = literal ( specialization . signature . params [ carrier . position ] , nil )
if value == nil then
complete = false
do break end
end
values [ carrier . name ] = value
end
if not complete then
do break end
end
end
if complete then
local physical = specialization . physical or specialization
local lowered = _G.setmetatable({ name =
physical . name ,  signature =
specialization . signature ,  values =
values ,  omitted =
specialization . omitted }, lower.Specialization)

local class = specialization . bodyClass or specialization . key
local index = candidate . classIndex [ class ]
if index == nil then
candidate . specializations [ # candidate . specializations + 1 ] = lowered
index = # candidate . specializations
candidate . classIndex [ class ] = index
end
candidate . dispatches [ # candidate . dispatches + 1 ] = { specialization = lowered , index = index , }
for _ , call in ipairs ( specialization . calls ) do
local line = lower . site ( call ) . line
specializationLines [ # specializationLines + 1 ] = line
specializationSites [
# specializationSites + 1
] = { file = specialization . callFiles [ call ] or filename , line = line , }
end
end
end
end
end
end
else
walk ( parsed . root )
end

local function bySpecializationName ( a , b ) 
return a . name < b . name
end

for _ , candidate in pairs ( candidates ) do
if plans == nil then
table . sort ( candidate . specializations , bySpecializationName )
candidate . dispatches = { }
for index , specialization in ipairs ( candidate . specializations ) do
candidate . dispatches [ # candidate . dispatches + 1 ] = { specialization = specialization , index = index , }
end
end
end

local specializationCount = 0
for _ , candidate in pairs ( candidates ) do
specializationCount = specializationCount + # candidate . specializations
end
if specializationCount > 8 then
local sites = { }
for _ , site in ipairs ( specializationSites ) do
sites [ # sites + 1 ] = site . file .. ":" .. tostring ( site . line )
end
diagnostics [
# diagnostics + 1
] = _G.setmetatable({ file =
filename ,  line =
specializationLines [ maxPerModule + 1 ] or specializationLines [ 1 ] or 1 ,  column =
1 ,  message =
(
"const specialization requires %d body classes in this module, over the cap of %d; demanding call sites: %s"
) : format ( specializationCount , maxPerModule , table . concat ( sites , ", " ) ) ,  code =
compile . REFUSED_SPECIALIZATION }, compile.Diagnostic)

return nil , diagnostics
end

local ok , answer = pcall ( function ( ) 
local programs = { }
local families = { }
for _ , application in ipairs ( found . applications ) do
local declaration = application . tail
local name = declaration ~= nil and declaration . name ~= nil and declaration . name . text or ""
local candidate = candidates [ name ]
local familyPrograms = { }
local familySpecializations = { }
local familyDispatchPrograms = { }
for _ , specialization in ipairs ( candidate ~= nil and candidate . specializations or { } ) do



local program = lower . program ( found , application , true , context , specialization )
programs [ # programs + 1 ] = program
familyPrograms [ # familyPrograms + 1 ] = program
end
for _ , dispatch in ipairs ( candidate ~= nil and candidate . dispatches or { } ) do
familySpecializations [ # familySpecializations + 1 ] = dispatch . specialization
familyDispatchPrograms [ # familyDispatchPrograms + 1 ] = familyPrograms [ dispatch . index ]
end
if # familyPrograms > 0 and declaration ~= nil and declaration . body ~= nil then
families [
# families + 1
] = {
site = compile . site ( application ) ,
header = compile . header ( source , declaration ) ,
name = name ,
binders = candidate . binders ,
programs = familyPrograms ,
specializations = familySpecializations ,
dispatchPrograms = familyDispatchPrograms ,
}
end
end
if # programs == 0 then
context . reject ( nil , "no closed const-generic AOT applications were found" )
end

nameRegistrar ( programs )
for _ , program in ipairs ( programs ) do
verify . program ( program )
end

local loopReports = { }
for position , program in ipairs ( programs ) do
numericForRuntime ( program , selected )
verify . program ( program )
local refusals = compile . legalizeVectors ( program , filename , selected )
if refusals ~= nil then
laneRefusals = refusals
error ( REFUSED , 0 )
end
loopReports [ position ] = loopAnalysis . program ( program )
end

return ( _G.setmetatable({ programs =
programs ,  loops =
loopReports ,  irText =
text . programs ( programs ) ,  binding =
"" ,  gpu =
{ } ,  sites =
{ } ,  constFamilies =
families }, compile.Artifacts) )

end )
if not ok then
if answer ~= REFUSED then
error ( answer , 0 )
end
return nil , laneRefusals or diagnostics
end

return answer , diagnostics
end








function compile . legalizeVectors (
program ,
filename ,
selected
) 
numericForRuntime ( program , selected )
local resolvedWidth = targets . simdWidth ( selected )
local indexRefusals = { }

local function lanesOf ( speciesType ) 
local _ , element , shape = shapes . parts ( speciesType )
if element == nil then
return nil
end

return shapes . lanes ( resolvedWidth , element , shape )
end

local function refuse ( node , message ) 
local at = node . source
indexRefusals [
# indexRefusals + 1
] = _G.setmetatable({ file =
filename ,  line =
at ~= nil and ( at ) . line or 1 ,  column =
at ~= nil and ( at ) . column or 1 ,  message =
message ,  code =
compile . REFUSED_TIER }, compile.Diagnostic)

end

if program . usesSimd == true then
visit . program (
program ,
_G.setmetatable({ scalarExpression =  function ( node ) 
local operation = node
local position = 0
local least = 1
if node . op == "simd_extract" or node . op == "simd_insert" then
position = 2
elseif node . op == "simd_permute" and operation . intrinsic == "align" then
position , least = 3 , 0
end
if position == 0 then
return
end
local index = operation . args [ position ]
local value = shapes . laneValue ( index , lanesOf )
if value == nil then
refuse ( node , "SIMD lane index is not a compile-time constant on the selected tier" )

return
end
local lane = value
local lanes = lanesOf ( operation . args [ position == 2 and 1 or 2 ] . type ) or 0
if lane < least or lane % 1 ~= 0 or least > 0 and lane > lanes then
refuse (
node ,
lane >= least
and lane % 1 == 0
and "SIMD lane index exceeds the logical species lanes for the selected tier"
or "SIMD lane index names no lane on the selected tier"
)

return
end
operation . args [ position ] = shapes . laneConstant ( lane , index . source )
end }, visit.Visitor)
)
end
if # indexRefusals > 0 then
return indexRefusals
end
if program . usesSimd == true then
program . simdWidth = targets . simdWidth ( selected )
program . vectorCeiling = targets . vectorCeiling ( selected )
end

return nil
end











function compile . artifacts (
source ,
filename ,
parsed ,
library ,
selected ,
symbolTier ,
constPlans ,
qualifyLinkage ,
at
) 
local step = at or function ( _ ) 
end
step ( "lower" )
local programs , diagnostics , sites = compile . lower ( source , filename , parsed , selected )
if # diagnostics > 0 then
return nil , diagnostics
end
local constArtifacts = nil
if parsed ~= nil then
local specialized , specializationDiagnostics = compile . constSpecializations (
source ,
filename ,
parsed ,
selected ,
symbolTier ,
constPlans
)
if specialized ~= nil then
constArtifacts = specialized
elseif specializationDiagnostics [ 1 ] ~= nil
and specializationDiagnostics [ 1 ] . message ~= "no closed const-generic AOT applications were found"
then
return nil , specializationDiagnostics
end
end
if # programs == 0 and constArtifacts == nil then
return nil , {
_G.setmetatable({ file =
filename ,  line =
1 ,  column =
1 ,  message =
"no @aot function was found" ,  code =
compile . NO_AOT_FUNCTION }, compile.Diagnostic)

}
end

local loopReports = { }
local gpu = { }
local cpuPrograms = { }
local declaredModule = parsed ~= nil and cst . declaredModule ( ( parsed ) . root ) ~= nil
local browser = selected . triple : match ( "^wasm" ) ~= nil
step ( "verify" )
for position , program in ipairs ( programs ) do
numericForRuntime ( program , selected )


verify . program ( program )
if program . executionTarget == "gpu" then
local artifact , rule = gpuartifact . program ( program , browser )
if artifact == nil then
local site = sites [ position ]
local line , column = sitePosition ( source , site ~= nil and ( site ) . from or 1 )
return nil , {
_G.setmetatable({ file =
filename ,  line =
line ,  column =
column ,  message =
rule ,  code =
compile . REFUSED_GPU }, compile.Diagnostic)

}
end
local checkedArtifact = artifact
checkedArtifact . exportTypes = declaredModule
local site = sites [ position ]
local line , column = sitePosition ( source , site ~= nil and ( site ) . from or 1 )
checkedArtifact . sourceFile = require ( "nupp.compiler.fs" ) . absolute ( filename )
checkedArtifact . sourceLine = line
checkedArtifact . sourceColumn = column
checkedArtifact . artifactId = hash . digest ( checkedArtifact . spirv )
gpu [ program . symbol ] = artifact
else
local refusals = compile . legalizeVectors ( program , filename , selected )
if refusals ~= nil then
return nil , refusals
end
cpuPrograms [ # cpuPrograms + 1 ] = program
end
loopReports [ position ] = loopAnalysis . program ( program )
end
if constArtifacts ~= nil then
for position , program in ipairs ( ( constArtifacts ) . programs ) do
if program . executionTarget == "gpu" then
return nil , {
_G.setmetatable({ file =
filename ,  line =
1 ,  column =
1 ,  message =
"const-specialized GPU kernels are not yet supported" ,  code =
compile . REFUSED_GPU }, compile.Diagnostic)

}
end
programs [ # programs + 1 ] = program
cpuPrograms [ # cpuPrograms + 1 ] = program
loopReports [ # loopReports + 1 ] = ( constArtifacts ) . loops [ position ]
end
end






if qualifyLinkage then
qualifySymbols ( cpuPrograms , filename )
end





step ( "emit" )
local generatedBinding = bindingRules . module ( cpuPrograms , library )
if # cpuPrograms == 0 then
local generatedGpuBindings = { }
for _ , program in ipairs ( programs ) do
local artifact = gpu [ program . symbol ]
if artifact ~= nil then
generatedGpuBindings [ # generatedGpuBindings + 1 ] = gpuBinding . replacement ( program , artifact , browser )
end
end
if # generatedGpuBindings > 0 then
generatedBinding = table . concat ( generatedGpuBindings , "\n\n" ) .. "\n"
end
end

return _G.setmetatable({ programs =
programs ,  loops =
loopReports ,  irText =
text . programs ( programs ) ,  binding =
generatedBinding ,  gpu =
gpu ,  sites =
sites ,  constFamilies =
constArtifacts ~= nil and ( constArtifacts ) . constFamilies or nil }, compile.Artifacts)
, diagnostics
end

local __nuppExportValue= compile ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.aot.compile"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.aot.compile"]=__nuppExports;return __nuppExports