_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.check.mutation\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.compiler.check.mutation\0runtime\0002") };

























local cst = require ( "nupp.compiler.syntax.cst" )

local mutation = { }





mutation.Summary = {} mutation.Summary.__index = mutation.Summary ;_G.nupp.__reflect.link(mutation.Summary,__nuppT1[1],{ })






















mutation.Summaries = {} mutation.Summaries.__index = mutation.Summaries ;_G.nupp.__reflect.link(mutation.Summaries,__nuppT1[2],{ __nuppT1[1] })


















local INVOKERS

= { pcall = 1 , xpcall = 1 , [ "coroutine.wrap" ] = 1 , [ "coroutine.create" ] = 1 , [ "table.sort" ] = 2 , [ "string.gsub" ] = 3 , }

local function newSummary ( ) 
return ( _G.setmetatable({ params =
{ } ,  paramNames =
{ } ,  self =
false ,  selfPaths =
{ } ,  captured =
{ } ,  capturedBelow =
{ } ,  unknown =
false }, mutation.Summary) )

end


local ARITHMETIC = { [ "+" ] = true , [ "-" ] = true , [ "*" ] = true , [ "//" ] = true , [ "%" ] = true , }









function mutation . indexShape ( expr , integers ) 
while expr and not cst . isToken ( expr ) and ( expr . kind == "paren" or expr . kind == "castExpr" ) do
expr = expr . expr
end
if not expr or cst . isToken ( expr ) then
return "any" , nil
end
local kind = expr . kind
if kind == "string" then
local literal = expr . token and expr . token . value or nil
if type ( literal ) == "string" then
return "field" , literal
end
return "any" , nil
elseif kind == "number" then
return "integer" , nil
elseif kind == "unop" then
return expr . op and expr . op . kind == "#" and "integer" or "any" , nil
elseif kind == "binop" then
return expr . op and ARITHMETIC [ expr . op . kind ] and "integer" or "any" , nil
elseif kind == "name" then
local name = expr . token and expr . token . text or nil
return name and integers and integers [ name ] and "integer" or "any" , nil
end

return "any" , nil
end









local function splitPath ( node , integers ) 
local segments = { }
local deep = false
while node and not cst . isToken ( node ) do
local kind = node . kind
if kind == "name" then
local root = node . token and node . token . text or nil
if not root then
return nil , ""
end
local suffix = ""
for index = # segments , 1 , -1 do
suffix = suffix .. "." .. segments [ index ]
end
if deep then
suffix = suffix .. "*"
end
return root , suffix
elseif kind == "paren" or kind == "castExpr" then
node = node . expr
elseif kind == "dotIndex" or kind == "safeIndex" then
if not node . name then
return nil , ""
end
segments [ # segments + 1 ] = node . name . text
node = node . obj
elseif kind == "bracketIndex" or kind == "safeBracket" then
local shape , literal = mutation . indexShape ( node . expr , integers )
if shape == "field" then
segments [ # segments + 1 ] = literal
elseif shape == "integer" then
return nil , ""
else


segments = { }
deep = true
end
node = node . obj
else
return nil , ""
end
end

return nil , ""
end






local MAX_PATH_DEPTH = 3



local function joinPaths ( prefix , suffix ) 
if prefix : sub ( -1 ) == "*" then
return prefix
end
local joined = suffix == "*" and prefix .. "*" or prefix .. suffix
local depth = 0
local cut = nil
for position in joined : gmatch ( "()%." ) do
depth = depth + 1
if depth > 3 then
cut = position
do break end
end
end
if cut then
return joined : sub ( 1 , cut - 1 ) .. "*"
end

return joined
end



local function covered ( paths , suffix ) 
if paths [ suffix ] then
return true
end
local above = suffix : sub ( -1 ) == "*" and suffix : sub ( 1 , -2 ) or suffix
while true do
if paths [ above .. "*" ] then
return true
end
local shorter = above : match ( "^(.*)%.[^.]*$" )
if not shorter then
return false
end
above = shorter
end
end





local function keyOf ( node ) 
while node and not cst . isToken ( node ) and ( node . kind == "paren" or node . kind == "castExpr" ) do
node = node . expr
end
if not node or cst . isToken ( node ) then
return nil
end
if node . kind == "name" then
return node . token and node . token . text or nil
end
if node . kind == "dotIndex" and node . name then
local base = keyOf ( node . obj )
return base and ( base .. "." .. node . name . text ) or nil
end

return nil
end


local function bodyOf ( node ) 
while node and not cst . isToken ( node ) and ( node . kind == "paren" or node . kind == "castExpr" ) do
node = node . expr
end
if not node or cst . isToken ( node ) then
return nil
end
if node . kind == "funcExpr" then
return node . body
end
if node . kind == "shortfn" then
return node
end

return nil
end

mutation . splitPath = splitPath
mutation . joinPaths = joinPaths
mutation . keyOf = keyOf
mutation . bodyOf = bodyOf







































local function declare ( ctx , name , token ) 
local top = ctx . scopes [ # ctx . scopes ]
if top then
top [ name ] = token
end
end


local function declarationOf ( ctx , name ) 
for index = # ctx . scopes , 1 , -1 do
local token = ctx . scopes [ index ] [ name ]
if token then
return token
end
end

return nil
end




local function markBinding ( ctx , target , root , suffix ) 
if not root then
return
end
local token = declarationOf ( ctx , root )
if not token then
return
end
local at = cst . firstToken ( target )
local loop = ctx . loops [ # ctx . loops ]
local writes = token . writes or { }
token . writes = writes
writes [
# writes + 1
] = {
offset = at and at . offset or 0 ,
loopFrom = loop and loop . from or nil ,
loopTo = loop and loop . to or nil ,
path = root .. suffix ,
}
end



local function resolveAlias ( ctx , name ) 
local resolved = name
local prefix = ""
local copied = false
local seen = { }
while not seen [ resolved ] do
seen [ resolved ] = true
local origin = ctx . aliases [ resolved ]
if not origin then
do break end
end
resolved = origin . root
prefix = joinPaths ( origin . path , prefix )
copied = true
end

return resolved , prefix , copied
end







local function noteWrite ( ctx , root , suffix ) 
if not root then
return false
end
local resolved , prefix , copied = resolveAlias ( ctx , root )
if copied then
if suffix == "" then
return false
end
suffix = joinPaths ( prefix , suffix )
end
local summary = ctx . summary
local index = ctx . paramIndex [ resolved ]
if index then
if suffix == "" then
return false
end
local paths = summary . params [ index ] or { }
summary . params [ index ] = paths
if covered ( paths , suffix ) then
return false
end
paths [ suffix ] = true
return true
elseif resolved == "self" and ctx . hasSelf then
if suffix == "" or covered ( summary . selfPaths , suffix ) then
return false
end
summary . self = true
summary . selfPaths [ suffix ] = true
return true
elseif not ctx . locals [ resolved ] then
if suffix == "" then
if summary . captured [ resolved ] then
return false
end
summary . captured [ resolved ] = true
return true
end
local paths = summary . capturedBelow [ resolved ] or { }
summary . capturedBelow [ resolved ] = paths
if covered ( paths , suffix ) then
return false
end
paths [ suffix ] = true
return true
end

return false
end




local function fold ( ctx , call , callee ) 
local summary = ctx . summary
local changed = false

local function through ( root , prefix , paths ) 
if not root then
return
end
for suffix in pairs ( paths ) do
if noteWrite ( ctx , root , joinPaths ( prefix , suffix ) ) then
changed = true
end
end
end

for name in pairs ( callee . captured ) do
if not summary . captured [ name ] and not ctx . locals [ name ] then
summary . captured [ name ] = true
changed = true
end
end
for name , paths in pairs ( callee . capturedBelow ) do
if not ctx . locals [ name ] then
local mine = summary . capturedBelow [ name ] or { }
summary . capturedBelow [ name ] = mine
for suffix in pairs ( paths ) do
if not mine [ suffix ] then
mine [ suffix ] = true
changed = true
end
end
end
end
if callee . unknown and not summary . unknown then
summary . unknown = true
changed = true
end
if call . merge then

for index , paths in pairs ( callee . params ) do
local mine = summary . params [ index ] or { }
summary . params [ index ] = mine
for suffix in pairs ( paths ) do
if not mine [ suffix ] then
mine [ suffix ] = true
changed = true
end
end
end
for suffix in pairs ( callee . selfPaths ) do
if not summary . selfPaths [ suffix ] then
summary . self = true
summary . selfPaths [ suffix ] = true
changed = true
end
end
return changed
end
if callee . self and call . receiver then
through ( call . receiver , call . receiverPath , callee . selfPaths )
end
for _ , argument in ipairs ( call . args ) do
local position = argument . position
if argument . name then
position = nil
for j , paramName in ipairs ( callee . paramNames ) do
if paramName == argument . name then
position = j
do break end
end
end
end

if call . receiver == nil and call . method and position then
if position == 1 and callee . self then
through ( argument . root , argument . path , callee . selfPaths )
end
position = position - 1
end
local paths = position and callee . params [ position ] or nil
if paths then
through ( argument . root , argument . path , paths )
end
end

return changed
end





function mutation . prescan ( root ) 
local byKey = { }
local byMethod = { }
local byBody = { }
local assignedAnywhere = { }
local contexts = { }

local merges = { }

local function file ( summary , key , method ) 
if key then
local existing = byKey [ key ]
if existing and existing ~= summary then
merges [ # merges + 1 ] = { into = existing , from = summary }
elseif not existing then
byKey [ key ] = summary
end
end
if method then
local existing = byMethod [ method ]
if existing and existing ~= summary then
merges [ # merges + 1 ] = { into = existing , from = summary }
elseif not existing then
byMethod [ method ] = summary
end
end
end

local walk

local function scanCall ( ctx , node ) 
local kind = node . kind
local args = node . args
local exprs = args and args . kind == "args" and args . exprs or { }
local call = { args = { } }
if kind == "methodCall" then
call . method = node . name and node . name . text or nil
call . receiver , call . receiverPath = splitPath ( node . obj )
else
local callee = node . obj
call . key = keyOf ( callee )
call . body = bodyOf ( callee )
if callee and not cst . isToken ( callee ) and callee . kind == "dotIndex" and callee . name then
call . method = callee . name . text
end
if not call . key and not call . body then
ctx . summary . unknown = true
end
end
local position = 0
for _ , argument in ipairs ( exprs ) do
if not cst . isToken ( argument ) then
local value = argument
local name = nil
if argument . kind == "namedArg" then
name = argument . name and argument . name . text or nil
value = argument . value
elseif argument . kind == "pluckArg" then
value = argument . value
end
position = position + 1
local argRoot , argPath = splitPath ( value , ctx . integers )
call . args [
# call . args + 1
] = { position = position , name = name , root = argRoot , path = argPath , node = value }


if bodyOf ( value ) or keyOf ( value ) then
ctx . calls [ # ctx . calls + 1 ] = { args = { } , body = bodyOf ( value ) , key = keyOf ( value ) , handed = true }
end
end
end
ctx . calls [ # ctx . calls + 1 ] = call

local invoker = call . key and INVOKERS [ call . key ] or nil
if invoker then
local handed = call . args [ invoker ]
if handed and handed . node and ( bodyOf ( handed . node ) or keyOf ( handed . node ) ) then
local inner = { args = { } , key = keyOf ( handed . node ) , body = bodyOf ( handed . node ) }
for j = invoker + 1 , # call . args do
local argument = call . args [ j ]
inner . args [
# inner . args + 1
] = { position = j - invoker , root = argument . root , path = argument . path , node = argument . node }
end
ctx . calls [ # ctx . calls + 1 ] = inner
elseif handed then
ctx . summary . unknown = true
end
end
end


local function scanFunction ( outer , body , key , method , hasSelf ) 
if not body or cst . isToken ( body ) then
return
end
local summary = byBody [ body ] or newSummary ( )
byBody [ body ] = summary
file ( summary , key , method )
local inherited = { }
for index , scope in ipairs ( outer and outer . scopes or { } ) do
inherited [ index ] = scope
end
inherited [ # inherited + 1 ] = { }
local ctx = {
summary = summary ,
locals = { } ,
paramIndex = { } ,
hasSelf = hasSelf ,
aliases = { } ,
calls = { } ,
scopes = inherited ,
loops = { } ,
integers = { } ,
}
local position = 0
for _ , p in ipairs ( body . params or { } ) do
if not cst . isToken ( p ) and p . name then
local name = p . name . text
ctx . locals [ name ] = true
declare ( ctx , name , p . name )
if name == "self" and position == 0 then
ctx . hasSelf = true
elseif not p . namedVararg then
position = position + 1
ctx . paramIndex [ name ] = position
summary . paramNames [ position ] = name
end
end
end
contexts [ # contexts + 1 ] = ctx
if body . kind == "shortfn" then
walk ( ctx , body . body or body . expr )
else
walk ( ctx , body . body )
end
end


local function literalUnder ( ctx , value , key , method ) 
local body = bodyOf ( value )
if not body then
return false
end
scanFunction ( ctx , body , key , method , false )

return true
end


local function written ( ctx , target ) 
local root , suffix = splitPath ( target , ctx . integers )
noteWrite ( ctx , root , suffix )
markBinding ( ctx , target , root , suffix )
if root then
assignedAnywhere [ root ] = true
end
end

walk = function ( ctx , node ) 
if not node or cst . isToken ( node ) then
return
end
local kind = node . kind
if kind == "localFuncStmt" then
local name = node . name and node . name . text or nil
if name then
ctx . locals [ name ] = true
declare ( ctx , name , node . name )
end
scanFunction ( ctx , node . body , name , nil , false )
return
elseif kind == "funcStmt" then
local fname = node . name
local key , method , hasSelf = nil , nil , false
if fname and fname . kind == "funcname" then
local parts = { }
for _ , child in ipairs ( fname ) do
if cst . isToken ( child ) and child . kind == "name" then
parts [ # parts + 1 ] = child . text
end
end
if fname . method then
method = fname . method . text
hasSelf = true

parts [ # parts ] = nil
key = table . concat ( parts , "." ) .. ":" .. method
else
key = table . concat ( parts , "." )
if # parts > 1 then

method = parts [ # parts ]
elseif # parts == 1 then
assignedAnywhere [ parts [ 1 ] ] = true
markBinding ( ctx , fname , parts [ 1 ] , "" )
end
end
end
scanFunction ( ctx , node . body , key , method , hasSelf )
return
elseif kind == "inlineMethod" then
scanFunction ( ctx , node . body , nil , node . name and node . name . text or nil , true )
return
elseif kind == "funcExpr" then
scanFunction ( ctx , node . body , nil , nil , false )
return
elseif kind == "shortfn" then
scanFunction ( ctx , node , nil , nil , false )
return
elseif kind == "fieldNamed" or kind == "namedArg" then


local name = node . name and node . name . text or nil
if name and literalUnder ( ctx , node . value , nil , name ) then
return
end
elseif kind == "localStmt" then
for _ , nameTok in ipairs ( node . names or { } ) do
ctx . locals [ nameTok . text ] = true
declare ( ctx , nameTok . text , nameTok )
end
for _ , entry in ipairs ( node . pattern or { } ) do
local nameTok = entry . alias or entry . sourceName
if nameTok then
ctx . locals [ nameTok . text ] = true
declare ( ctx , nameTok . text , nameTok )
end
end
local exprs = node . exprs or { }
local single = # ( node . names or { } ) == 1 and node . names [ 1 ] or nil
local init = exprs [ 1 ]
if single and init and # exprs == 1 and not cst . isToken ( init ) then
if literalUnder ( ctx , init , single . text , nil ) then
return
end
local root , path = splitPath ( init , ctx . integers )
if root and root ~= single . text then
ctx . aliases [ single . text ] = { root = root , path = path }
end
end
for _ , expr in ipairs ( exprs ) do
walk ( ctx , expr )
end
if node . patternSource then
walk ( ctx , node . patternSource )
end
return
elseif kind == "assignStmt" then
local targets , exprs = node . targets or { } , node . exprs or { }
local handled = { }
for j , target in ipairs ( targets ) do
written ( ctx , target )

local value = exprs [ j ]
local key = value and keyOf ( target ) or nil
if key and literalUnder ( ctx , value , key , key : match ( "%.([^.]+)$" ) ) then
handled [ value ] = true
end
walk ( ctx , target )
end
for _ , expr in ipairs ( exprs ) do
if not handled [ expr ] then
walk ( ctx , expr )
end
end
return
elseif kind == "compoundAssign" then
written ( ctx , node . target )
elseif kind == "call" or kind == "methodCall" or kind == "safeCall" then
scanCall ( ctx , node )
end

local opened = false
local looped = false
if kind == "whileStmt" or kind == "repeatStmt" or kind == "fornumStmt" or kind == "forinStmt" then
local first , last = cst . firstToken ( node ) , cst . lastToken ( node )
ctx . loops [ # ctx . loops + 1 ] = { from = first and first . offset or 0 , to = last and last . offset or 0 }
looped = true
end
if kind == "block" then
ctx . scopes [ # ctx . scopes + 1 ] = { }
opened = true
elseif kind == "fornumStmt" or kind == "forinStmt" then
ctx . scopes [ # ctx . scopes + 1 ] = { }
opened = true
local var = node . var
if var and cst . isToken ( var ) then
ctx . locals [ var . text ] = true
ctx . integers [ var . text ] = true
declare ( ctx , var . text , var )
end
local iterator = node . exprs and node . exprs [ 1 ] or nil
local counts = iterator ~= nil and iterator . kind == "call" and keyOf ( iterator . obj ) == "ipairs"
for index , nameTok in ipairs ( node . names or { } ) do
if cst . isToken ( nameTok ) then
ctx . locals [ nameTok . text ] = true
if index == 1 and counts then
ctx . integers [ nameTok . text ] = true
end
declare ( ctx , nameTok . text , nameTok )
end
end
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
walk ( ctx , child )
end
end
if opened then
ctx . scopes [ # ctx . scopes ] = nil
end
if looped then
ctx . loops [ # ctx . loops ] = nil
end
end



local top = {
summary = newSummary ( ) ,
locals = { } ,
paramIndex = { } ,
hasSelf = false ,
aliases = { } ,
calls = { } ,
scopes = { { } } ,
loops = { } ,
integers = { } ,
}
contexts [ # contexts + 1 ] = top
for _ , block in ipairs ( root and root . blocks or { } ) do
walk ( top , block )
end
for _ , merge in ipairs ( merges ) do
for _ , ctx in ipairs ( contexts ) do
if ctx . summary == merge . into then
ctx . calls [ # ctx . calls + 1 ] = { args = { } , merge = merge . from }
end
end
end


local changed = true
while changed do
changed = false
for _ , ctx in ipairs ( contexts ) do
for _ , call in ipairs ( ctx . calls ) do
local callee = call . merge or call . body and byBody [ call . body ] or call . key and byKey [ call . key ] or nil
if not callee and call . method then
callee = byMethod [ call . method ]
end
if callee then
if callee ~= ctx . summary and fold ( ctx , call , callee ) then
changed = true
end
elseif call . key and ctx . locals [ call . key ] and not call . handed then

if not ctx . summary . unknown then
ctx . summary . unknown = true
changed = true
end
end
end
end
end

local capturedAnywhere = { }
for _ , ctx in ipairs ( contexts ) do
if ctx ~= top then
for name in pairs ( ctx . summary . captured ) do
capturedAnywhere [ name ] = true
end
for name in pairs ( ctx . summary . capturedBelow ) do
capturedAnywhere [ name ] = true
end
end
end

return ( _G.setmetatable({ byKey =
byKey ,  byMethod =
byMethod ,  byBody =
byBody ,  capturedAnywhere =
capturedAnywhere ,  assignedAnywhere =
assignedAnywhere }, mutation.Summaries) )

end










function mutation . writtenAfter ( token , offset , path ) 
for _ , write in ipairs ( token and token . writes or { } ) do
local later = write . offset > offset
or ( write . loopFrom ~= nil and write . loopFrom <= offset and offset <= write . loopTo )
if later then
local wrote = write . path
local reaches
if wrote : sub ( -1 ) == "*" then
local above = wrote : sub ( 1 , -2 )
reaches = path == above or path : sub ( 1 , # above + 1 ) == above .. "."
else
reaches = wrote == path or path : sub ( 1 , # wrote + 1 ) == wrote .. "."
end
if reaches then
return true
end
end
end

return false
end








function mutation . calleeSummary ( summaries , node ) 
if node . kind == "methodCall" then
local name = node . name and node . name . text or nil
return name and summaries . byMethod [ name ] or nil
end
local callee = node . obj
local body = bodyOf ( callee )
if body and summaries . byBody [ body ] then
return summaries . byBody [ body ]
end
local key = keyOf ( callee )
if key and summaries . byKey [ key ] then
return summaries . byKey [ key ]
end
if callee and not cst . isToken ( callee ) and callee . kind == "dotIndex" and callee . name then
return summaries . byMethod [ callee . name . text ]
end

return nil
end








function mutation . callEffects ( summaries , node ) 
local callee = mutation . calleeSummary ( summaries , node )
local args = node . args
local exprs = args and args . kind == "args" and args . exprs or { }
local handed = { }
for _ , argument in ipairs ( exprs ) do
if not cst . isToken ( argument ) then
local value = ( argument . kind == "namedArg" or argument . kind == "pluckArg" ) and argument . value or argument
local body = bodyOf ( value )
local summary = body and summaries . byBody [ body ] or nil
if not summary then
local key = keyOf ( value )
summary = key and summaries . byKey [ key ] or nil
end
if summary then
handed [ # handed + 1 ] = summary
end
end
end
if # handed == 0 then
return callee , callee ~= nil
end
local merged = newSummary ( )
if callee then
merged . params = callee . params
merged . paramNames = callee . paramNames
merged . self = callee . self
merged . selfPaths = callee . selfPaths
merged . unknown = callee . unknown
for name in pairs ( callee . captured ) do
merged . captured [ name ] = true
end
for name , paths in pairs ( callee . capturedBelow ) do
merged . capturedBelow [ name ] = paths
end
end
for _ , summary in ipairs ( handed ) do
for name in pairs ( summary . captured ) do
merged . captured [ name ] = true
end
for name , paths in pairs ( summary . capturedBelow ) do
local mine = merged . capturedBelow [ name ] or { }
merged . capturedBelow [ name ] = mine
for suffix in pairs ( paths ) do
mine [ suffix ] = true
end
end
if summary . unknown then
merged . unknown = true
end
end

return merged , callee ~= nil
end










function mutation . eachWrite (
summaries ,
node ,
note
) 
local callee = mutation . callEffects ( summaries , node )
if not callee then
return false
end

local function each ( root , prefix , paths ) 
if not root then
return
end
for suffix in pairs ( paths ) do
local full = joinPaths ( prefix , suffix )
if full : sub ( -1 ) == "*" then
note ( root .. full : sub ( 1 , -2 ) , true )
else
note ( root .. full , false )
end
end
end

for name in pairs ( callee . captured ) do
note ( name , false )
end
for name , paths in pairs ( callee . capturedBelow ) do
each ( name , "" , paths )
end
local isMethod = node . kind == "methodCall"
if callee . self and isMethod then
local root , prefix = splitPath ( node . obj )
each ( root , prefix , callee . selfPaths )
end
local called = node . obj
local viaOwner = not isMethod and called and not cst . isToken ( called ) and called . kind == "dotIndex"
local args = node . args
local exprs = args and args . kind == "args" and args . exprs or { }
local position = 0
for _ , argument in ipairs ( exprs ) do
if not cst . isToken ( argument ) then
position = position + 1
local value = ( argument . kind == "namedArg" or argument . kind == "pluckArg" ) and argument . value or argument
local at = position
if argument . kind == "namedArg" and argument . name then
at = 0
for j , paramName in ipairs ( callee . paramNames ) do
if paramName == argument . name . text then
at = j
end
end
end
local root , prefix = splitPath ( value )
if viaOwner and callee . self then
if at == 1 then
each ( root , prefix , callee . selfPaths )
end
at = at - 1
end
local paths = callee . params [ at ]
if paths then
each ( root , prefix , paths )
end
end
end

return true
end







function mutation . writtenRoots ( summaries , block ) 
local whole = { }
local below = { }

local function note ( key , under ) 
if under then
below [ key ] = true
else
whole [ key ] = true
end
end

local integers = { }

local function direct ( target ) 
local root , suffix = splitPath ( target , integers )
if not root then
return
end
if suffix : sub ( -1 ) == "*" then
note ( root .. suffix : sub ( 1 , -2 ) , true )
else
note ( root .. suffix , false )
end
end

local function walk ( node ) 
if not node or cst . isToken ( node ) then
return
end
local kind = node . kind
if kind == "funcExpr" or kind == "shortfn" or kind == "localFuncStmt" or kind == "funcStmt" then
return
elseif kind == "fornumStmt" and node . var and cst . isToken ( node . var ) then
integers [ node . var . text ] = true
elseif kind == "forinStmt" then
local iterator = node . exprs and node . exprs [ 1 ] or nil
local first = node . names and node . names [ 1 ] or nil
if first and iterator ~= nil and iterator . kind == "call" and keyOf ( iterator . obj ) == "ipairs" then
integers [ first . text ] = true
end
elseif kind == "assignStmt" then
for _ , target in ipairs ( node . targets or { } ) do
direct ( target )
end
elseif kind == "compoundAssign" then
direct ( node . target )
elseif kind == "call" or kind == "methodCall" or kind == "safeCall" then
mutation . eachWrite ( summaries , node , note )
end
for _ , child in ipairs ( node ) do
if not cst . isToken ( child ) then
walk ( child )
end
end
end

walk ( block )

return whole , below
end

local __nuppExportValue= mutation ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.check.mutation"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.check.mutation"]=__nuppExports;return __nuppExports