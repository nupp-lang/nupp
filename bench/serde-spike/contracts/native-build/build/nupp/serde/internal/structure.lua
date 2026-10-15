_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppT19={}; local function __nuppT16(...) return {n=select("#",...),...} end; local __nuppT20,__nuppT21,__nuppT22,__nuppT23,__nuppT24,__nuppT25,__nuppT26,__nuppT27=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT17(value) return value end; local function __nuppT18(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT25({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT26(v.primary) for _,reason in __nuppT27(v.suppressed) do text=text.."\ncleanup: "..__nuppT26(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};package.loaded["nupp.serde.internal.structure"]=__nuppExports;local __nuppOk,__nuppWhy=pcall(function()local adapter;__nuppExports["adapter"]=function(...) return adapter(...) end;local borrowedGet;__nuppExports["borrowedGet"]=function(...) return borrowedGet(...) end;local canDefer;__nuppExports["canDefer"]=function(...) return canDefer(...) end;local copiedGet;__nuppExports["copiedGet"]=function(...) return copiedGet(...) end;local field;__nuppExports["field"]=function(...) return field(...) end;local inspect;__nuppExports["inspect"]=function(...) return inspect(...) end;local rejectsUnknown;__nuppExports["rejectsUnknown"]=function(...) return rejectsUnknown(...) end;local __nuppT1={ _G.nupp.__reflect.declaration("nupp.serde.internal.structure\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.serde.internal.structure\0runtime\0002") };

local core = require ( "nupp.serde.internal.value" )




local BorrowedGet = {} BorrowedGet.__index = BorrowedGet ;_G.nupp.__reflect.link(BorrowedGet,__nuppT1[1],{ }) ;__nuppExports["BorrowedGet"]=BorrowedGet






local CopiedGet = {} CopiedGet.__index = CopiedGet ;_G.nupp.__reflect.link(CopiedGet,__nuppT1[2],{ }) ;__nuppExports["CopiedGet"]=CopiedGet







borrowedGet=function ( read ) 
return ( _G.setmetatable({ read =  read ,  kind =  "borrowed" }, BorrowedGet) )
end ;__nuppExports["borrowedGet"]=borrowedGet

copiedGet=function ( read ) 
return ( _G.setmetatable({ read =  read ,  kind =  "copied" }, CopiedGet) )
end ;__nuppExports["copiedGet"]=copiedGet











































local Field = {}























local Projected = {} Projected.__index = Projected







function Projected:describe(direction) 
return self . adapter : describe ( direction )
end

function Projected:write(source, writer) 
local present = self . present
if present ~= nil and not present ( source ) then
return
end
local get = self . get
if get . kind == "borrowed" then
self . adapter : write ( get . read ( source ) , writer )
else
self . adapter : write ( get . read ( source ) , writer )
end
end

function Projected:read(state, reader) 
self . set ( state , self . adapter : read ( reader ) )
end

function Projected:accept(consumer) 
return consumer : apply (
self . member ,
self . present or function ( source ) 
return true
end ,
self . get ,
self . set ,
self . adapter ,
nil
)
end


field=function (
member ,
get ,
set ,
adapter ,
required ,
hasDefault ,
present
) 
return ( _G.setmetatable({ member =
member ,  get =
borrowedGet ( get ) ,  present =
present ,  set =
set ,  adapter =
adapter ,  required =
required ,  hasDefault =
hasDefault }, Projected) )

end ;__nuppExports["field"]=field

























local Description = {} Description.__index = Description









local Emit = {} Emit.__index = Emit


function Emit:apply(source, writer) 
for _ , item in ipairs ( self . fields ) do
if writer : include ( item . member ) then
item : write ( source , writer )
end
end
local additional = self . additional
if additional ~= nil then
additional : apply ( source , writer )
end
end


local Read = {} Read.__index = Read

function Read:apply(state, member, reader) 
assert ( self . byMember [ member ] , "foreign structure member" ) : read ( state , reader )
end


local Reject = {} Reject.__index = Reject
function Reject:apply(state, identity, reader) 





error ( "unknown member: " .. identity : diagnosticLabel ( ) , 2 )
end


local Adapter = {} Adapter.__index = Adapter







function Adapter:describe(direction) 
return self . description
end

function Adapter:write(source, writer) 
writer : writeStruct ( self . description . member , source , self . emit )
end

function Adapter:read(reader) 
do local __nuppT28=0; local  __nuppT34 ; local __nuppT35=false ; local __nuppT29,__nuppT30,__nuppT31=__nuppT21(function() do local __nuppT36= self . construction : begin ( ) ; __nuppT34= __nuppT36 ; __nuppT28=1;  __nuppT35=true;  local state=__nuppT34;
reader : readStruct ( self . description . member , state , self . consume , self . unknown )
return "return",__nuppT16( (function(__nuppT37,...)  __nuppT35=false; return __nuppT37:finish(...)  end)( self . construction , state ) ) end; return "normal" end,__nuppT17); local __nuppT32={}; local __nuppT33=0; if __nuppT28>=1 and __nuppT35 then  local __nuppT38,__nuppT39=__nuppT20(__nuppCleanup1,__nuppT34);  if not __nuppT38 then __nuppT33=__nuppT33+1; __nuppT32[__nuppT33]=__nuppT39 end; end; if not __nuppT29 then if __nuppT33>0 then __nuppT22(__nuppT18(__nuppT30,__nuppT32,1),0) else __nuppT22(__nuppT30,0) end end; if __nuppT33>0 then if __nuppT33>1 then __nuppT22(__nuppT18(__nuppT32[1],__nuppT32,2),0) else __nuppT22(__nuppT32[1],0) end end; if __nuppT30=="return" then  return __nuppT23(__nuppT31,1,__nuppT31.n)  end; end
end

function Adapter:inspect(consumer) 
return consumer : apply (
self . description . member ,
self . fields ,
self . construction ,
self . unknown ,
self . emit . additional
)
end


adapter=function (
member ,
fields ,
construction ,
unknown ,
additional ,
deferredConstruction
) 
local ordered = { }
local byMember = { }
local children = { }
for index , item in ipairs ( fields ) do
assert ( byMember [ item . member ] == nil , "duplicate structure member" )
ordered [ index ] = item
byMember [ item . member ] = item
children [ index ] = item
end

return ( _G.setmetatable({ description =
_G.setmetatable({ member =  member ,  children =  children ,  kind =  "structure" ,  nullable =  false ,  canRead =  true }, Description) ,  deferredConstruction =
deferredConstruction == true ,  fields =
ordered ,  construction =
construction ,  emit =
_G.setmetatable({ fields =  ordered ,  additional =  additional }, Emit) ,  consume =
_G.setmetatable({ byMember =  byMember }, Read) ,  unknown =
unknown or _G.setmetatable({ }, Reject) }, Adapter) )

end ;__nuppExports["adapter"]=adapter

inspect=function ( selected , consumer ) 
if getmetatable ( selected ) ~= Adapter then
return nil
end
return ( selected ) : inspect ( consumer )
end ;__nuppExports["inspect"]=inspect



canDefer=function ( selected ) 
return getmetatable ( selected ) == Adapter and ( selected ) . deferredConstruction
end ;__nuppExports["canDefer"]=canDefer

rejectsUnknown=function ( consumer ) 
return getmetatable ( consumer ) == Reject
end ;__nuppExports["rejectsUnknown"]=rejectsUnknown
local __nuppWorkerRecords=_G.rawget(_G.nupp,"__workerRecords");if _G.type(__nuppWorkerRecords)~="table" then __nuppWorkerRecords=_G.setmetatable({},{__mode="k"});_G.rawset(_G.nupp,"__workerRecords",__nuppWorkerRecords) end;__nuppWorkerRecords[BorrowedGet]="nupp.serde.internal.structure\0BorrowedGet";__nuppWorkerRecords[CopiedGet]="nupp.serde.internal.structure\0CopiedGet"; end);if not __nuppOk then package.loaded["nupp.serde.internal.structure"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.serde.internal.structure"]=__nuppExports;return __nuppExports