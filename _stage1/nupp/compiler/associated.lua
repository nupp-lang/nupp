_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);














local T = require ( "nupp.compiler.types" )
local generics = require ( "nupp.compiler.generics" )

local associated = { }













local function resolvedType ( answer , head )
if not answer . selfBinder then
return answer . type
end

return generics . rebind ( answer . type , { [ answer . selfBinder ] = head } )
end





local function reachRequirements ( head , name , into , seen )
if head . tag ~= "nominal" or seen [ head ] then
return
end
seen [ head ] = true
for _ , requirement in ipairs ( ( head ) . associatedRequirements or { } ) do
if requirement . name == name and not seen [ requirement ] then
seen [ requirement ] = true
into [ # into + 1 ] = setmetatable({ requirement =  requirement ,  from =  head }, T.AssociatedReached)
end
end
for _ , super in ipairs ( ( head ) . supertypes or { } ) do
reachRequirements ( super , name , into , seen )
end
end


local function reachAnswers (
head ,
name ,
explicit ,
defaults ,
fixed ,
seen
)
if head . tag ~= "nominal" or seen [ head ] then
return
end
seen [ head ] = true
local answers = ( head ) . associatedAnswers
local entry = answers and answers [ name ] or nil
if entry and not seen [ entry ] then
seen [ entry ] = true
if entry . kind == "default" then
defaults [ # defaults + 1 ] = entry
elseif entry . kind == "fixed" then
fixed [ # fixed + 1 ] = entry
explicit [ # explicit + 1 ] = entry
else
explicit [ # explicit + 1 ] = entry
end
end
for _ , super in ipairs ( ( head ) . supertypes or { } ) do
reachAnswers ( super , name , explicit , defaults , fixed , seen )
end
end



local function intersectBounds ( reached , head )
local bounds = { }
for _ , one in ipairs ( reached ) do
local bound = one . requirement . bound
if bound then
if one . requirement . selfBinder then
bound = generics . rebind ( bound , { [ one . requirement . selfBinder ] = head } )
end
bounds [ # bounds + 1 ] = bound
end
end
if # bounds == 0 then
return nil
end
if # bounds == 1 then
return bounds [ 1 ]
end

return T . intersection ( bounds )
end

local lookupInto









local function concreteDeclaration ( head )
return head . tag == "nominal" and ( head ) . declKind ~= "interface"
end


local function settle ( result , head )
if # result . requirements == 0 then
result . reason = "unknown"

return result
end
if not concreteDeclaration ( head ) then





if result . answer and result . answer . kind == "fixed" then
result . resolved = resolvedType ( result . answer , head )

return result
end

return result
end
local answer = result . answer
if not answer then
if # result . defaults == 0 then
result . reason = "missing"

return result
end



local first = resolvedType ( result . defaults [ 1 ] , head )
for j = 2 , # result . defaults do
if resolvedType ( result . defaults [ j ] , head ) ~= first then
result . reason = "conflict"

return result
end
end
answer = result . defaults [ 1 ]
result . answer = answer
end
for _ , promise in ipairs ( result . fixed ) do
if resolvedType ( promise , head ) ~= resolvedType ( answer , head ) then
result . reason = "contradicted"

return result
end
end




result . resolved = resolvedType ( answer , head )

return result
end





function associated . lookup ( head , name )
return lookupInto ( head , name )
end

lookupInto = function ( head , name )
local result = setmetatable({ requirements =  { } ,  defaults =  { } ,  fixed =  { } }, T.AssociatedLookup)
if head == T . any then


result . gradual = true

return result
end
if head . tag == "typevar" then
local bound = ( head ) . bound
if not bound then


result . reason = "unprojectable"

return result
end

return lookupInto ( bound , name )
end
if head . tag == "projection" then


local inner = lookupInto ( ( head ) . of , ( head ) . name )
if inner . resolved then
return lookupInto ( inner . resolved , name )
end
if inner . bound then
return lookupInto ( inner . bound , name )
end
result . reason = inner . reason or "unprojectable"

return result
end
if head . tag == "intersection" then


local seen = { }
local explicit = { }
for _ , member in ipairs ( ( head ) . members ) do
reachRequirements ( member , name , result . requirements , seen )
end
local answerSeen = { }
for _ , member in ipairs ( ( head ) . members ) do
reachAnswers ( member , name , explicit , result . defaults , result . fixed , answerSeen )
end
result . answer = explicit [ 1 ]
result . bound = intersectBounds ( result . requirements , head )

return settle ( result , head )
end
if head . tag == "union" then







local bounds = { }
local resolvedArms = { }
local settled = true
for _ , member in ipairs ( ( head ) . members ) do
local arm = lookupInto ( member , name )
if # arm . requirements == 0 and not arm . gradual then
result . reason = "incomplete"

return result
end
if arm . reason then


result . reason = arm . reason

return result
end
for _ , one in ipairs ( arm . requirements ) do
result . requirements [ # result . requirements + 1 ] = one
end
if arm . bound then
bounds [ # bounds + 1 ] = arm . bound
end
if arm . gradual then
result . gradual = true
settled = false
elseif arm . resolved then
resolvedArms [ # resolvedArms + 1 ] = arm . resolved
else
settled = false
end
end
if # bounds > 0 then
result . bound = T . union ( bounds )
end
if result . gradual then
return result
end
if settled and # resolvedArms > 0 then
result . resolved = T . union ( resolvedArms )
elseif not settled then


result . answer = nil
end

return result
end
if head . tag ~= "nominal" then
result . reason = "unprojectable"

return result
end
local seen = { }
reachRequirements ( head , name , result . requirements , seen )
local explicit = { }
reachAnswers ( head , name , explicit , result . defaults , result . fixed , { } )
result . answer = explicit [ 1 ]
result . bound = intersectBounds ( result . requirements , head )

return settle ( result , head )
end







function associated . requirementNames ( head )
local names = { }
local seen = { }
local visit
visit = function ( current )
if current . tag ~= "nominal" then
return
end
for _ , requirement in ipairs ( ( current ) . associatedRequirements or { } ) do
if not seen [ requirement . name ] then
seen [ requirement . name ] = true
names [ # names + 1 ] = requirement . name
end
end
for _ , super in ipairs ( ( current ) . supertypes or { } ) do
visit ( super )
end
end
visit ( head )

return names
end


local function declares ( head , contract , seen )
if head == contract then
return true
end
if head . tag ~= "nominal" or seen [ head ] then
return false
end
seen [ head ] = true
for _ , super in ipairs ( ( head ) . supertypes or { } ) do
if declares ( super , contract , seen ) then
return true
end
end

return false
end


function associated . declares ( head , contract )
return declares ( head , contract , { } )
end








function associated . projectable ( head , name )
local result = lookupInto ( head , name )

return result . gradual == true or # result . requirements > 0
end

return associated
