_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
















local lexer = require ( "nupp.compiler.lexer" )

local cst = { }
















































































































































































































































































































































































































































































































cst.Chunk = {} cst.Chunk.__index = cst.Chunk




















cst.Block = {} cst.Block.__index = cst.Block










cst.EmptyStmt = {} cst.EmptyStmt.__index = cst.EmptyStmt












cst.HandleStmt = {} cst.HandleStmt.__index = cst.HandleStmt






















cst.IfStmt = {} cst.IfStmt.__index = cst.IfStmt













cst.IfClause = {} cst.IfClause.__index = cst.IfClause













cst.ElseifClause = {} cst.ElseifClause.__index = cst.ElseifClause













cst.ElseClause = {} cst.ElseClause.__index = cst.ElseClause










cst.WhileStmt = {} cst.WhileStmt.__index = cst.WhileStmt













cst.DoStmt = {} cst.DoStmt.__index = cst.DoStmt














cst.NoSuspendStmt = {} cst.NoSuspendStmt.__index = cst.NoSuspendStmt





















cst.EffectRegionStmt = {} cst.EffectRegionStmt.__index = cst.EffectRegionStmt










cst.UnsafeStmt = {} cst.UnsafeStmt.__index = cst.UnsafeStmt



















cst.FornumStmt = {} cst.FornumStmt.__index = cst.FornumStmt






















cst.ForinStmt = {} cst.ForinStmt.__index = cst.ForinStmt
















cst.RepeatStmt = {} cst.RepeatStmt.__index = cst.RepeatStmt













cst.FuncStmt = {} cst.FuncStmt.__index = cst.FuncStmt
























cst.Funcname = {} cst.Funcname.__index = cst.Funcname














cst.LocalFuncStmt = {} cst.LocalFuncStmt.__index = cst.LocalFuncStmt






















cst.LocalStmt = {} cst.LocalStmt.__index = cst.LocalStmt




















cst.LabelStmt = {} cst.LabelStmt.__index = cst.LabelStmt










cst.GotoStmt = {} cst.GotoStmt.__index = cst.GotoStmt










cst.BreakStmt = {} cst.BreakStmt.__index = cst.BreakStmt







cst.ContinueStmt = {} cst.ContinueStmt.__index = cst.ContinueStmt







cst.ReturnStmt = {} cst.ReturnStmt.__index = cst.ReturnStmt










cst.CompoundAssign = {} cst.CompoundAssign.__index = cst.CompoundAssign
















cst.AssignStmt = {} cst.AssignStmt.__index = cst.AssignStmt



















cst.CallStmt = {} cst.CallStmt.__index = cst.CallStmt










cst.ErrorStmt = {} cst.ErrorStmt.__index = cst.ErrorStmt










cst.PragmaStmt = {} cst.PragmaStmt.__index = cst.PragmaStmt






















cst.AnnotationApply = {} cst.AnnotationApply.__index = cst.AnnotationApply



















cst.AnnotationArg = {} cst.AnnotationArg.__index = cst.AnnotationArg





















cst.AssociatedDecl = {} cst.AssociatedDecl.__index = cst.AssociatedDecl































cst.TypeAlias = {} cst.TypeAlias.__index = cst.TypeAlias










































cst.RecordDecl = {} cst.RecordDecl.__index = cst.RecordDecl














































cst.WhereClause = {} cst.WhereClause.__index = cst.WhereClause










cst.FieldDecl = {} cst.FieldDecl.__index = cst.FieldDecl




























cst.IndexerDecl = {} cst.IndexerDecl.__index = cst.IndexerDecl














cst.ArrayPart = {} cst.ArrayPart.__index = cst.ArrayPart













cst.InlineMethod = {} cst.InlineMethod.__index = cst.InlineMethod
















cst.MetamethodDecl = {} cst.MetamethodDecl.__index = cst.MetamethodDecl
















cst.CdefFunc = {} cst.CdefFunc.__index = cst.CdefFunc




































cst.CdefStruct = {} cst.CdefStruct.__index = cst.CdefStruct





















cst.Generics = {} cst.Generics.__index = cst.Generics


























cst.Param = {} cst.Param.__index = cst.Param

































cst.Funcbody = {} cst.Funcbody.__index = cst.Funcbody













































cst.CaptureClause = {} cst.CaptureClause.__index = cst.CaptureClause













cst.NameExpr = {} cst.NameExpr.__index = cst.NameExpr










cst.NumberLit = {} cst.NumberLit.__index = cst.NumberLit










cst.StringLit = {} cst.StringLit.__index = cst.StringLit










cst.DedentString = {} cst.DedentString.__index = cst.DedentString












cst.NilExpr = {} cst.NilExpr.__index = cst.NilExpr










cst.TrueExpr = {} cst.TrueExpr.__index = cst.TrueExpr










cst.FalseExpr = {} cst.FalseExpr.__index = cst.FalseExpr










cst.Vararg = {} cst.Vararg.__index = cst.Vararg










cst.Paren = {} cst.Paren.__index = cst.Paren















cst.ComptimeExpr = {} cst.ComptimeExpr.__index = cst.ComptimeExpr
















cst.NewExpr = {} cst.NewExpr.__index = cst.NewExpr














cst.UnsafeOwnershipExpr = {} cst.UnsafeOwnershipExpr.__index = cst.UnsafeOwnershipExpr
























cst.SatisfiesDecl = {} cst.SatisfiesDecl.__index = cst.SatisfiesDecl





















cst.ConstructorDecl = {} cst.ConstructorDecl.__index = cst.ConstructorDecl
















cst.ErrorExpr = {} cst.ErrorExpr.__index = cst.ErrorExpr










cst.DotIndex = {} cst.DotIndex.__index = cst.DotIndex
















cst.BracketIndex = {} cst.BracketIndex.__index = cst.BracketIndex













cst.MethodCall = {} cst.MethodCall.__index = cst.MethodCall




























cst.SafeIndex = {} cst.SafeIndex.__index = cst.SafeIndex













cst.SafeBracket = {} cst.SafeBracket.__index = cst.SafeBracket













cst.SafeCall = {} cst.SafeCall.__index = cst.SafeCall













cst.Call = {} cst.Call.__index = cst.Call













cst.Args = {} cst.Args.__index = cst.Args



















cst.NamedArg = {} cst.NamedArg.__index = cst.NamedArg









cst.PluckArg = {} cst.PluckArg.__index = cst.PluckArg












cst.TableExpr = {} cst.TableExpr.__index = cst.TableExpr










cst.FieldBracket = {} cst.FieldBracket.__index = cst.FieldBracket













cst.FieldNamed = {} cst.FieldNamed.__index = cst.FieldNamed
















cst.FieldItem = {} cst.FieldItem.__index = cst.FieldItem










cst.Shortfn = {} cst.Shortfn.__index = cst.Shortfn



















cst.Istring = {} cst.Istring.__index = cst.Istring










cst.FuncExpr = {} cst.FuncExpr.__index = cst.FuncExpr










cst.Unop = {} cst.Unop.__index = cst.Unop













cst.Binop = {} cst.Binop.__index = cst.Binop
















cst.CastExpr = {} cst.CastExpr.__index = cst.CastExpr













cst.IsExpr = {} cst.IsExpr.__index = cst.IsExpr













cst.Ternary = {} cst.Ternary.__index = cst.Ternary
















cst.Tconst = {} cst.Tconst.__index = cst.Tconst










cst.Tkeyof = {} cst.Tkeyof.__index = cst.Tkeyof











cst.Twriteof = {} cst.Twriteof.__index = cst.Twriteof








cst.Tliteral = {} cst.Tliteral.__index = cst.Tliteral










cst.Tname = {} cst.Tname.__index = cst.Tname

















cst.Ttypecall = {} cst.Ttypecall.__index = cst.Ttypecall










cst.Tparen = {} cst.Tparen.__index = cst.Tparen










cst.Tmap = {} cst.Tmap.__index = cst.Tmap
















cst.Tshape = {} cst.Tshape.__index = cst.Tshape










cst.TshapeField = {} cst.TshapeField.__index = cst.TshapeField
















cst.Ttuple = {} cst.Ttuple.__index = cst.Ttuple













cst.Tpack = {} cst.Tpack.__index = cst.Tpack















cst.TpackUnion = {} cst.TpackUnion.__index = cst.TpackUnion








cst.Tarray = {} cst.Tarray.__index = cst.Tarray










cst.Tfunc = {} cst.Tfunc.__index = cst.Tfunc








































cst.TfuncParam = {} cst.TfuncParam.__index = cst.TfuncParam

























cst.Topt = {} cst.Topt.__index = cst.Topt










cst.Tptr = {} cst.Tptr.__index = cst.Tptr










cst.Tcarray = {} cst.Tcarray.__index = cst.Tcarray













cst.Tmember = {} cst.Tmember.__index = cst.Tmember










cst.Tmapped = {} cst.Tmapped.__index = cst.Tmapped
















cst.Tunion = {} cst.Tunion.__index = cst.Tunion










cst.Tintersection = {} cst.Tintersection.__index = cst.Tintersection










cst.ErrorType = {} cst.ErrorType.__index = cst.ErrorType







cst.Tpredicate = {} cst.Tpredicate.__index = cst.Tpredicate













cst.Tborrows = {} cst.Tborrows.__index = cst.Tborrows

















cst.Tpreserves = {} cst.Tpreserves.__index = cst.Tpreserves


























































































































































local function isToken ( x )
return ( x ) . trivia ~= nil
end

cst . isToken = isToken







local OWNERSHIP_INTRINSICS

= { attemptAll = true , borrow = true , borrowFrom = true , partition = true , region = true , pin = true , }















function cst . ownershipIntrinsicSpelling ( callee )
if not callee then
return nil
end
if callee . kind == "name" then
local bare = callee . token and callee . token . text or ""
if bare == "pin" then
return nil , false
end
return OWNERSHIP_INTRINSICS [ bare ] and bare or nil , false
end
if callee . kind ~= "dotIndex" then
return nil
end
local base = callee . obj
local member = callee . name and callee . name . text or ""
if not base or base . kind ~= "name" or not OWNERSHIP_INTRINSICS [ member ] then
return nil
end
local baseToken = base . token

return baseToken and baseToken . text == "nupp" and member or nil , true
end

local COMPTIME_TYPE_INTRINSICS = { reflect = true , sizeof = true , alignof = true , offsetof = true , }






function cst . comptimeTypeIntrinsicSpelling ( callee )
if not callee then
return nil
end
if callee . kind ~= "dotIndex" then
return nil
end
local base = callee . obj
local member = callee . name and callee . name . text or ""
local baseToken = base and base . kind == "name" and base . token or nil
if not baseToken or baseToken . text ~= "nupp" or not COMPTIME_TYPE_INTRINSICS [ member ] then
return nil
end

return member , true
end












function cst . add ( n , child )
if child ~= nil then
n [ # n + 1 ] = child
end
return child
end








function cst . identifier ( name )
return not lexer . KEYWORDS [ name ] and name : match ( "^[%a_][%w_]*$" ) ~= nil
end














function cst . resultValueType ( node )
if not node or cst . isToken ( node ) then
return nil
end
local written = node
if written . kind == "tborrows" then
return ( written ) . type
end

return written
end





function cst . firstToken ( x )
local at = x
while at and not isToken ( at ) do
at = at [ 1 ]
end

return at
end




function cst . lastToken ( x )
local at = x
while at and not isToken ( at ) do
at = at [ # at ]
end

return at
end





function cst . textOf ( x )
local parts = { }
local function walk ( y )
if isToken ( y ) then
for index = 1 , y . triviaCount do
parts [ # parts + 1 ] = lexer . triviaText ( y , index )
end
parts [ # parts + 1 ] = y . text
else
for _ , child in ipairs ( y ) do
walk ( child )
end
end
end

walk ( x )

return table . concat ( parts )
end



function cst . lastName ( x )
local found = nil
if not x or cst . isToken ( x ) then
return x and x . kind == "name" and x . text or nil
end
for _ , child in ipairs ( x ) do
if cst . isToken ( child ) and child . kind == "name" then
found = child . text
end
end

return found
end










function cst . returnedLocal ( root )
local returned = nil
for _ , block in ipairs ( root . blocks ) do
if block . kind == "block" then
for _ , stat in ipairs ( block . stats ) do
if stat . kind == "returnStmt" then
local exprs = stat . exprs
returned = # exprs == 1 and exprs [ 1 ] or nil
end
end
end
end
if not returned then
return nil
end


if returned . kind == "call" then
local callee = returned . obj
if not callee or callee . kind ~= "name" then
return nil
end
local calleeName = callee . token
if not calleeName or calleeName . text ~= "setmetatable" then
return nil
end
local argsNode = returned . args
local args = argsNode and argsNode . kind == "args" and argsNode . exprs or { }
returned = args [ 1 ]
if not returned then
return nil
end
end
if returned . kind ~= "name" then
return nil
end
local token = returned . token
if not token then
return nil
end

return token . text
end








function cst . declVisibility ( declaration , moduleLocal )
local written = declaration . visibility
if written == "local" or written == "global" or written == "nested" then
return written
end
local qualifiers = declaration . qualifiers
if qualifiers then
local only = # qualifiers == 1 and qualifiers [ 1 ] or nil
if only and moduleLocal and only . text == moduleLocal then
return "module"
end
return "local"
end

return written or "local"
end





function cst . dump ( x )
if isToken ( x ) then
if x . missing then
return "\194\171" .. x . kind .. "\194\187"
end
return x . text
end
local parts = { "(" , x . kind }
for _ , child in ipairs ( x ) do
parts [ # parts + 1 ] = " "
parts [ # parts + 1 ] = cst . dump ( child )
end
parts [ # parts + 1 ] = ")"

return table . concat ( parts )
end





function cst . pretty ( x )
local lines = { }
local function walk ( y , depth )
local indent = string . rep ( "  " , depth )
if isToken ( y ) then
if y . missing then
lines [ # lines + 1 ] = indent .. y . kind .. " «missing»"
else
lines [ # lines + 1 ] = indent .. y . kind .. " " .. ( "%q" ) : format ( y . text )
end
return
end
lines [ # lines + 1 ] = indent .. y . kind
for _ , child in ipairs ( y ) do
walk ( child , depth + 1 )
end
end

walk ( x , 0 )

return table . concat ( lines , "\n" )
end

return cst
