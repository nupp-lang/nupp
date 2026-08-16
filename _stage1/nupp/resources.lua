_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;



















local resources = { }






const Entry = {} Entry.__index = Entry











resources.Set = {} resources.Set.__index = resources.Set































function resources.Set:adopt(value, terminal)
assert ( not self . _closed , "resource set is closed" )
local witness = terminal
assert ( type ( witness ) == "function" , "resource adoption needs a discharge witness" )
self . _entries [ # self . _entries + 1 ] = setmetatable({ value =  value ,  cleanup =  witness }, Entry)

return self . _entries [ # self . _entries ] . value
end






function resources.Set:remove(value)
assert ( not self . _closed , "resource set is closed" )
for index = # self . _entries , 1 , - 1 do
local entry = self . _entries [ index ]
if entry . value == value then
table . remove ( self . _entries , index )
return entry . value
end
end
error ( "resource is not registered in this set" , 2 )
end










function resources . Set . close ( self )
local first = nil
local suppressed = 0
if not self . _closed then
self . _closed = true
for index = # self . _entries , 1 , - 1 do
local entry = self . _entries [ index ]
local ok , reason = pcall ( entry . cleanup , entry . value )
if not ok then
if first == nil then
first = reason
else
suppressed = suppressed + 1
end
end
end
self . _entries = { }
end


local _raw = self
if first ~= nil then
if suppressed > 0 then
error ( tostring ( first ) .. " (suppressed " .. tostring ( suppressed ) .. " cleanup failure(s))" , 0 )
end
error ( first , 0 )
end
end

function resources . Set . drop ( self )
self : close ( )
end

local function destroySet ( value )
value : drop ( )
end ;__nuppCleanups["nupp.resources#destroySet"]=destroySet









function resources . set ( label ) __nuppCleanups["nupp.resources#destroySet"]=destroySet;
return setmetatable({ label =  label or "resource" ,  _entries =  { } ,  _closed =  false }, resources.Set)
end

local function close_file ( file )
local ok , reason = file : close ( )
if not ok then
error ( reason or "file close failed" )
end
end ;__nuppCleanups["nupp.resources#close_file"]=close_file










function resources . openFile ( path , mode ) __nuppCleanups["nupp.resources#close_file"]=close_file;
local file , reason = io . open ( path , mode )
if not file then
error ( reason or "file open failed" )
end

return file
end










function resources . openProcess ( command , mode ) __nuppCleanups["nupp.resources#close_file"]=close_file;
local file , reason = io . popen ( command , mode )
if not file then
error ( reason or "process open failed" )
end

return file
end








function resources . temporaryFile ( ) __nuppCleanups["nupp.resources#close_file"]=close_file;
local file = io . tmpfile ( )
if not file then
error ( "temporary file creation failed" )
end

return file
end

return resources
