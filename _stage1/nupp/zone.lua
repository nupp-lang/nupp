_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);
























local zone = { }


local stack = require ( "jit.zone" )



local references = 0
local generation = 0




zone . __nuppActive = false
zone . __nuppDepth = 0
zone . __nuppStack = stack
zone . __nuppVersion = 0



local pathVersion = - 1
local pathText = ""
local pathBuffer = { }


function zone . isActive ( )
return zone . __nuppActive
end


function zone . depth ( )
return zone . __nuppDepth
end




function zone . acquire ( )
references = references + 1
if references > 1 then
return
end

for index = # stack , 1 , - 1 do
stack [ index ] = nil
end
zone . __nuppDepth = 0
zone . __nuppVersion = ( zone . __nuppVersion + 1 )
generation = generation + 1
zone . __nuppActive = true
end



function zone . release ( )
if references == 0 then
return
end

references = references - 1
if references > 0 then
return
end

for index = # stack , 1 , - 1 do
stack [ index ] = nil
end
zone . __nuppDepth = 0
zone . __nuppVersion = ( zone . __nuppVersion + 1 )
zone . __nuppActive = false
end






function zone . push ( name )
if not zone . __nuppActive then
return
end

zone . __nuppDepth = ( zone . __nuppDepth + 1 )
stack [ zone . __nuppDepth ] = name
zone . __nuppVersion = ( zone . __nuppVersion + 1 )
end








function zone . pop ( )
if not zone . __nuppActive or zone . __nuppDepth == 0 then
return nil
end

local name = stack [ zone . __nuppDepth ]
stack [ zone . __nuppDepth ] = nil
zone . __nuppDepth = ( zone . __nuppDepth - 1 )
zone . __nuppVersion = ( zone . __nuppVersion + 1 )

return name
end


function zone . current ( )
if zone . __nuppDepth == 0 then
return nil
end
return stack [ zone . __nuppDepth ]
end








function zone . path ( )
if zone . __nuppVersion == pathVersion then
return pathText
end

if zone . __nuppDepth == 0 then
pathText = ""
else
for index = 1 , zone . __nuppDepth do
pathBuffer [ index ] = stack [ index ]
end
pathText = table . concat ( pathBuffer , "/" , 1 , zone . __nuppDepth )
end
pathVersion = zone . __nuppVersion

return pathText
end






function zone . enter ( name )
if not zone . __nuppActive then
return 0
end

zone . __nuppDepth = ( zone . __nuppDepth + 1 )
stack [ zone . __nuppDepth ] = name
zone . __nuppVersion = ( zone . __nuppVersion + 1 )

return generation
end



function zone . leave ( token )
if token == 0 or not zone . __nuppActive or token ~= generation then
return
end
if zone . __nuppDepth == 0 then
return
end

stack [ zone . __nuppDepth ] = nil
zone . __nuppDepth = ( zone . __nuppDepth - 1 )
zone . __nuppVersion = ( zone . __nuppVersion + 1 )
end

return zone
