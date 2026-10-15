_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);const __nuppNew = require("table.new"); local __nuppT14={}; local function __nuppT11(...) return {n=select("#",...),...} end; local __nuppT15,__nuppT16,__nuppT17,__nuppT18,__nuppT19,__nuppT20,__nuppT21,__nuppT22=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT12(value) return value end; local function __nuppT13(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT20({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT21(v.primary) for _,reason in __nuppT22(v.suppressed) do text=text.."\ncleanup: "..__nuppT21(reason) end return text end}) end; local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:lua.d.nupp#__nuppCloseFile") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()














const files2 = require ( "nupp.io.files" )
const path2 = require ( "nupp.io.path" )

local fs = __nuppNew(0,16)




local workingDirectory = nil

local function currentDirectory ( ) 
if workingDirectory == nil then
local cwd = path2 . currentDirectory ( )
workingDirectory = cwd and cwd : toString ( ) or "."
end

return workingDirectory
end

local function normalize ( path ) 
path = path : gsub ( "\\" , "/" ) : gsub ( "/+" , "/" )
path = path : gsub ( "^%./" , "" ) : gsub ( "/%./" , "/" )
if path == "/" or path : match ( "^[A-Za-z]:/$" ) then
return path
end

return ( path : gsub ( "/$" , "" ) )
end

local function join ( left , right ) 
if not right then
return normalize ( left or "" )
end
right = normalize ( right )
if not left or left == "" or left == "." then
return right
end
if not right or right == "" then
return normalize ( left )
end
if right : sub ( 1 , 1 ) == "/" or right : match ( "^[A-Za-z]:/" ) then
return right
end

return normalize ( left .. "/" .. right )
end

local function dirname ( path ) 
local normalized = normalize ( path )
if normalized == "/" or normalized : match ( "^[A-Za-z]:/$" ) then
return normalized
end
local parent = normalized : match ( "^(.*)/[^/]+$" )
if parent == "" then
return "/"
end
if parent and parent : match ( "^[A-Za-z]:$" ) then
return parent .. "/"
end

return parent or "."
end

local function basename ( path ) 
return normalize ( path ) : match ( "([^/]+)$" ) or path
end




local function absolute ( path ) 
path = normalize ( path )
if path : sub ( 1 , 1 ) ~= "/" and not path : match ( "^[A-Za-z]:/" ) then
path = join ( currentDirectory ( ) , path )
end
local prefix = path : match ( "^([A-Za-z]:)/" ) or ( path : sub ( 1 , 1 ) == "/" and "/" or "" )
local rest = prefix == "/" and path : sub ( 2 ) or path : gsub ( "^[A-Za-z]:/" , "" )
local parts = { }
for part in rest : gmatch ( "[^/]+" ) do
if part == ".." then
if # parts > 0 then
table . remove ( parts )
end
elseif part ~= "." and part ~= "" then
parts [ # parts + 1 ] = part
end
end
local suffix = table . concat ( parts , "/" )
if prefix == "/" then
return prefix .. suffix
end
if prefix ~= "" then
return prefix .. "/" .. suffix
end

return suffix
end












local function unverbatim ( path ) 
local slashed = path : gsub ( "\\" , "/" )
if slashed : sub ( 1 , 4 ) ~= "//?/" then
return path
end

return slashed : match ( "^//%?/([A-Za-z]:/.*)$" )
end














local function canonical ( path ) 
local fallback = absolute ( path )
local ok , resolved = pcall ( function ( ) 
local real = path2 . newPath ( fallback ) : canonicalize ( )

return real and real : toString ( ) or nil
end )
if ok and resolved then
local ordinary = unverbatim ( resolved )
if ordinary then
return normalize ( ordinary )
end
end

return fallback
end

local function readFile ( path ) 
do local __nuppT23=0; local  __nuppT29 ; local __nuppT24,__nuppT25,__nuppT26=__nuppT16(function() do local __nuppT30=__nuppT11( io . open ( path , "rb" ) ); __nuppT29= __nuppT30[1] ; __nuppT23=1;  local  f , err = __nuppT30[1] , __nuppT30[2] ;
if not f then





if files2 . isDirectory ( path ) then
return "return",__nuppT11( nil , path .. " is a directory" )
end

return "return",__nuppT11( nil , err )
end
local text = f : read ( "*a" )
f : close ( )
if not text then
if files2 . isDirectory ( path ) then
return "return",__nuppT11( nil , path .. " is a directory" )
end

return "return",__nuppT11( nil , path .. " cannot be read" )
end

return "return",__nuppT11( text ) end; return "normal" end,__nuppT12); local __nuppT27={}; local __nuppT28=0; if __nuppT23>=1 and __nuppT29~=nil then  local __nuppT31,__nuppT32=__nuppT15(__nuppCleanup1,__nuppT29);  if not __nuppT31 then __nuppT28=__nuppT28+1; __nuppT27[__nuppT28]=__nuppT32 end; end; if not __nuppT24 then if __nuppT28>0 then __nuppT17(__nuppT13(__nuppT25,__nuppT27,1),0) else __nuppT17(__nuppT25,0) end end; if __nuppT28>0 then if __nuppT28>1 then __nuppT17(__nuppT13(__nuppT27[1],__nuppT27,2),0) else __nuppT17(__nuppT27[1],0) end end; if __nuppT25=="return" then  return __nuppT18(__nuppT26,1,__nuppT26.n)  end; end
end









local function exists ( path ) 
return files2 . info ( path ) ~= nil
end

local function mkdir ( path ) 
if path == "" or path == "." then
return true
end

return ( files2 . createDirectory ( path ) )
end
















local hostpid = require ( "nupp.compiler.hostpid" )

local stagingToken = tostring ( hostpid . get ( ) or 0 )


local function processId ( ) 
if stagingToken == "0" then
return nil
end

return tonumber ( stagingToken )
end

local staged = 0


local function stagingSuffix ( ) 
staged = staged + 1
return stagingToken .. "-" .. tostring ( staged )
end

local function writeFile ( path , text ) 
if not mkdir ( dirname ( path ) ) then
return nil , "cannot create " .. dirname ( path )
end



local tmp = ("%s.%s.tmp") : format ( path , stagingSuffix ( ) )
do local __nuppT38=0; local  __nuppT44 ; local __nuppT39,__nuppT40,__nuppT41=__nuppT16(function() do local __nuppT45=__nuppT11( io . open ( tmp , "wb" ) ); __nuppT44= __nuppT45[1] ; __nuppT38=1;  local  f , err = __nuppT45[1] , __nuppT45[2] ;
if not f then
return "return",__nuppT11( nil , err )
end
local wrote , writeErr = f : write ( text )
if not wrote then
f : close ( )
os . remove ( tmp )
return "return",__nuppT11( nil , writeErr )
end
local closed , closeErr = f : close ( )
if not closed then
os . remove ( tmp )
return "return",__nuppT11( nil , closeErr )
end
local ok , renameErr = os . rename ( tmp , path )





if not ok and ( files2 . info ( path ) ~= nil ) then
local backup = ("%s.%s-%d.old") : format ( path , stagingToken , staged )
os . remove ( backup )
local moved , moveErr = os . rename ( path , backup )
if not moved then
os . remove ( tmp ) ;
return "return",__nuppT11( nil , moveErr )
end
ok , renameErr = os . rename ( tmp , path )
if ok then
os . remove ( backup )
else
os . rename ( backup , path )
end
end
if not ok then
os . remove ( tmp ) ;
return "return",__nuppT11( nil , renameErr )
end

return "return",__nuppT11( true ) end; return "normal" end,__nuppT12); local __nuppT42={}; local __nuppT43=0; if __nuppT38>=1 and __nuppT44~=nil then  local __nuppT46,__nuppT47=__nuppT15(__nuppCleanup1,__nuppT44);  if not __nuppT46 then __nuppT43=__nuppT43+1; __nuppT42[__nuppT43]=__nuppT47 end; end; if not __nuppT39 then if __nuppT43>0 then __nuppT17(__nuppT13(__nuppT40,__nuppT42,1),0) else __nuppT17(__nuppT40,0) end end; if __nuppT43>0 then if __nuppT43>1 then __nuppT17(__nuppT13(__nuppT42[1],__nuppT42,2),0) else __nuppT17(__nuppT42[1],0) end end; if __nuppT40=="return" then  return __nuppT18(__nuppT41,1,__nuppT41.n)  end; end
end

local function copyFile ( source , destination ) 
local text , err = readFile ( source )
if not text then
return nil , err
end

return writeFile ( destination , text )
end




















local function listFiles ( path , skipDirectory ) 
local files = { }
local pending = { path }
local parent = { }
while # pending > 0 do
local directory = table . remove ( pending )
for _ , entry in ipairs ( files2 . list ( directory ) or { } ) do
local child = join ( directory , entry . name )
local kind = entry . kind
local link = kind == "symlink"
if kind == "symlink" then
local resolved = files2 . info ( child )
kind = resolved and resolved . kind or "other"
end
if kind == "directory" then
if not ( skipDirectory and skipDirectory ( entry . name , child ) ) then
local cycle = false
if link then
local identity = canonical ( child )
local ancestor = directory
while ancestor do
if canonical ( ancestor ) == identity then
cycle = true
do break end
end
ancestor = parent [ ancestor ]
end
end
if not cycle then
parent [ child ] = directory
pending [ # pending + 1 ] = child
end
end
elseif kind == "file" then
files [ # files + 1 ] = normalize ( child )
end
end
end
table . sort ( files )

return files
end





local function installStaged ( staged , output ) 
local bytes , readErr = readFile ( staged )
os . remove ( staged )
if bytes == nil then
return false , readErr
end
local wrote , writeErr = writeFile ( output , bytes )
if not wrote then
return false , writeErr
end

return true , nil
end



local function writeFileIfChanged ( path , text ) 
if readFile ( path ) == text then
return true
end
return writeFile ( path , text )
end

fs . normalize = normalize
fs . join = join
fs . dirname = dirname
fs . basename = basename
fs . absolute = absolute
fs . canonical = canonical
fs . readFile = readFile
fs . exists = exists
fs . mkdir = mkdir
fs . stagingSuffix = stagingSuffix
fs . writeFile = writeFile
fs . installStaged = installStaged
fs . writeFileIfChanged = writeFileIfChanged
fs . copyFile = copyFile
fs . listFiles = listFiles
fs . processId = processId

local __nuppExportValue= fs ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.fs"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.fs"]=__nuppExports;return __nuppExports