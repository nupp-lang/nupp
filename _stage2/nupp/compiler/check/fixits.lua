_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);












local cst = require ( "nupp.compiler.cst" )
local state = require ( "nupp.compiler.check.state" )

local fixits = { }













































local function editDistance ( left , right )
local beforePrevious = nil
local previous = { }
for j = 0 , # right do
previous [ j ] = j
end
for i = 1 , # left do
local current = { [ 0 ] = i }
for j = 1 , # right do
local cost = left : sub ( i , i ) == right : sub ( j , j ) and 0 or 1
current [ j ] = math . min ( current [ j - 1 ] + 1 , previous [ j ] + 1 , previous [ j - 1 ] + cost )
if beforePrevious and i > 1 and j > 1 and left : sub (
i ,
i
) == right : sub ( j - 1 , j - 1 ) and left : sub ( i - 1 , i - 1 ) == right : sub ( j , j ) then
current [ j ] = math . min ( current [ j ] , beforePrevious [ j - 2 ] + 1 )
end
end
beforePrevious , previous = previous , current
end

return previous [ # right ]
end






function fixits . new ( result , env )
local self = { }

function self . fix ( title , ... )
return { title = title , edits = { ... } }
end


function self . insertBefore ( tok , text )
return { offset = tok . offset , length = 0 , newText = text }
end


function self . replaceToken ( tok , text )
return { offset = tok . offset , length = # tok . text , newText = text }
end




function self . spellingFix ( tok , candidates )
if not tok or type ( tok . text ) ~= "string" then
return nil
end
local compared = tok . text
if not compared : match ( "^__" ) then
compared = compared : sub ( 1 , 1 ) == "_" and "_" .. compared or "__" .. compared
end
local best , distance , tied = nil , nil , false
for candidate in pairs ( candidates or { } ) do
local candidateDistance = editDistance ( compared , candidate )
if not distance or candidateDistance < distance then
best , distance , tied = candidate , candidateDistance , false
elseif candidateDistance == distance then
tied = true
end
end
local stemLength = math . max ( 0 , # compared - 2 )
local threshold = stemLength >= 5 and 2 or 1
if not best or tied or distance > threshold then
return nil
end

return { self . fix ( ( "change to `%s`" ) : format ( best ) , self . replaceToken ( tok , best ) ) }
end


function self . nameSpellingFix ( tok , candidates )
if not tok or type ( tok . text ) ~= "string" then
return nil
end
local best , distance , tied = nil , nil , false
for key , value in pairs ( candidates or { } ) do
local candidate = type ( key ) == "number" and value or key
if type ( candidate ) == "string" and candidate ~= tok . text then
local candidateDistance = editDistance ( tok . text , candidate )
if not distance or candidateDistance < distance then
best , distance , tied = candidate , candidateDistance , false
elseif candidateDistance == distance then
tied = true
end
end
end
local threshold = # tok . text >= 5 and 2 or 1
if not best or tied or distance > threshold then
return nil
end

return { self . fix ( ( "change to `%s`" ) : format ( best ) , self . replaceToken ( tok , best ) ) }
end




function self . castFix ( expr , target )
local first , last = cst . firstToken ( expr ) , cst . lastToken ( expr )
local rendered = target and cst . textOf ( target ) or ""
local name = rendered : match ( "^%s*([%a_][%w_%.]*)%s*$" )
if not first or not last or not name then
return nil
end

return {
self . fix ( ( "cast to `%s`" ) : format ( name ) , self . insertBefore ( first , "(" ) , {
offset = last . offset + # last . text ,
length = 0 ,
newText = ") as " .. name
} )
}
end

function self . refinementFix ( expr , target )
local fixedWidth = require ( "nupp.compiler.fixed_width" )
local first , last = cst . firstToken ( expr ) , cst . lastToken ( expr )
local path = target and fixedWidth . conversionPath ( target ) or nil
if not first or not last or not path then
return nil
end

return {
self . fix ( ( "convert with `%s`" ) : format ( path ) , self . insertBefore ( first , path .. "(" ) , {
offset = last . offset + # last . text ,
length = 0 ,
newText = ")"
} )
}
end

function self . typeFix ( target , replacement )
local first , last = cst . firstToken ( target ) , cst . lastToken ( target )
if not first or not last then
return nil
end

return self . fix ( ( "change the type to `%s`" ) : format ( replacement ) , {
offset = first . offset ,
length = last . offset + # last . text - first . offset ,
newText = replacement ,
} )
end




local function topLevelRequires ( )
local found = { }
for _ , block in ipairs ( result . root . blocks or { } ) do
for _ , stat in ipairs ( block . stats or { } ) do
local expr = stat . kind == "localStmt" and # (
stat . names or { }
) == 1 and stat . exprs and # stat . exprs == 1 and stat . exprs [ 1 ] or nil
local callee = expr and expr . kind == "call" and expr . obj or nil
if callee and callee . kind == "name" and callee . token and callee . token . text == "require" then
local arg = expr . args and expr . args . exprs and expr . args . exprs [ 1 ]
local strTok = arg and arg . kind == "string" and arg . token or expr . args and expr . args . str or nil
local text = strTok and strTok . text or ""
found [
# found + 1
] = {
stat = stat ,
name = stat . names [ 1 ] . text ,
module = text : match ( '^"(.*)"$' ) or text : match ( "^'(.*)'$" )
}
end
end
end

return found
end




function self . requireEdit ( name , moduleName )
local line = ( "local %s = require(%q)" ) : format ( name , moduleName )
local requires = topLevelRequires ( )
local after = requires [ # requires ]
if after then
local tok = cst . lastToken ( after . stat )
if not tok then
return nil
end
return { offset = tok . offset + # tok . text , length = 0 , newText = "\n" .. line }
end
local firstBlock = ( result . root . blocks or { } ) [ 1 ]
local firstStat = firstBlock and ( firstBlock . stats or { } ) [ 1 ]
local tok = firstStat and cst . firstToken ( firstStat )
if not tok then
return nil
end

return { offset = tok . offset - ( tok . col - 1 ) , length = 0 , newText = line .. "\n\n" }
end


function self . requiredAs ( moduleName )
for _ , entry in ipairs ( topLevelRequires ( ) ) do
if entry . module == moduleName then
return entry . name
end
end

return nil
end



function self . requireBindsName ( name )
for _ , entry in ipairs ( topLevelRequires ( ) ) do
if entry . name == name then
return true
end
end

return false
end


local requireAdviceGiven = { }







function self . missingRequire ( name )
if not env or not env . modulesNamed then
return nil , false , nil
end
local candidates = { }
for _ , moduleName in ipairs ( env . modulesNamed ( env , name ) or { } ) do

if moduleName ~= result . moduleName then
candidates [ # candidates + 1 ] = moduleName
end
end
if # candidates == 0 then
return nil , false , nil
end
if requireAdviceGiven [ name ] then
return nil , true , nil
end
requireAdviceGiven [ name ] = true
local fixes = { }
for _ , moduleName in ipairs ( candidates ) do
local edit = self . requireEdit ( name , moduleName )
if edit then
fixes [ # fixes + 1 ] = self . fix ( ( "require(%q)" ) : format ( moduleName ) , edit )
end
end
local quoted = { }
for i , moduleName in ipairs ( candidates ) do
quoted [ i ] = ( "%q" ) : format ( moduleName )
end
if # candidates == 1 then
return ( "%q names a project module; require(%s) to use it" ) : format ( name , quoted [ 1 ] ) , true , fixes
end

return (
"%q names project modules %s; require the one you mean"
) : format ( name , table . concat ( quoted , ", " ) ) , true , fixes
end

return self
end









fixits . editDistance = editDistance








function fixits . nearest ( name , candidates )
local limit = # name < 5 and 1 or 2
local best , distance , tied = nil , nil , false
for _ , candidate in ipairs ( candidates ) do
local candidateDistance = editDistance ( name , candidate )
if not distance or candidateDistance < distance then
best , distance , tied = candidate , candidateDistance , false
elseif candidateDistance == distance then
tied = true
end
end
if tied or not distance or distance > limit then
return nil
end

return best
end

return fixits
