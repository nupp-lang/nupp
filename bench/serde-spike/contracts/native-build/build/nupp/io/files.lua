_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppT33={}; local function __nuppT30(...) return {n=select("#",...),...} end; local __nuppT34,__nuppT35,__nuppT36,__nuppT37,__nuppT38,__nuppT39,__nuppT40,__nuppT41=pcall,xpcall,error,(unpack or table.unpack),select,setmetatable,tostring,ipairs; local function __nuppT31(value) return value end; local function __nuppT32(primary,errors,start) local secondary={} for i=start,#errors do if errors[i]~=primary then secondary[#secondary+1]=errors[i] end end if #secondary==0 then return primary end return __nuppT39({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT40(v.primary) for _,reason in __nuppT41(v.suppressed) do text=text.."\ncleanup: "..__nuppT40(reason) end return text end}) end; local __nuppCleanup1 = function(__nuppV) return __nuppV:close() end;local __nuppExports={};local __nuppOk,__nuppWhy=pcall(function()local append;__nuppExports["append"]=function(...) return append(...) end;local applicationIdentity;__nuppExports["applicationIdentity"]=function(...) return applicationIdentity(...) end;local cachePath;__nuppExports["cachePath"]=function(...) return cachePath(...) end;local configurationPath;__nuppExports["configurationPath"]=function(...) return configurationPath(...) end;local copy;__nuppExports["copy"]=function(...) return copy(...) end;local createDirectory;__nuppExports["createDirectory"]=function(...) return createDirectory(...) end;local createSymlink;__nuppExports["createSymlink"]=function(...) return createSymlink(...) end;local createTemporaryDirectory;__nuppExports["createTemporaryDirectory"]=function(...) return createTemporaryDirectory(...) end;local createTemporaryFile;__nuppExports["createTemporaryFile"]=function(...) return createTemporaryFile(...) end;local dataPath;__nuppExports["dataPath"]=function(...) return dataPath(...) end;local executableDirectory;__nuppExports["executableDirectory"]=function(...) return executableDirectory(...) end;local exists;__nuppExports["exists"]=function(...) return exists(...) end;local glob;__nuppExports["glob"]=function(...) return glob(...) end;local info;__nuppExports["info"]=function(...) return info(...) end;local isDirectory;__nuppExports["isDirectory"]=function(...) return isDirectory(...) end;local isFile;__nuppExports["isFile"]=function(...) return isFile(...) end;local isSymlink;__nuppExports["isSymlink"]=function(...) return isSymlink(...) end;local lines;__nuppExports["lines"]=function(...) return lines(...) end;local list;__nuppExports["list"]=function(...) return list(...) end;local open;__nuppExports["open"]=function(...) return open(...) end;local read;__nuppExports["read"]=function(...) return read(...) end;local readLink;__nuppExports["readLink"]=function(...) return readLink(...) end;local remove;__nuppExports["remove"]=function(...) return remove(...) end;local rename;__nuppExports["rename"]=function(...) return rename(...) end;local requestPersistentStorage;__nuppExports["requestPersistentStorage"]=function(...) return requestPersistentStorage(...) end;local setApplicationIdentity;__nuppExports["setApplicationIdentity"]=function(...) return setApplicationIdentity(...) end;local setReadOnly;__nuppExports["setReadOnly"]=function(...) return setReadOnly(...) end;local userFolder;__nuppExports["userFolder"]=function(...) return userFolder(...) end;local write;__nuppExports["write"]=function(...) return write(...) end;local writeAtomic;__nuppExports["writeAtomic"]=function(...) return writeAtomic(...) end;
























const spi = require ( "nupp.spi" )
const target = require ( "nupp.runtime.target" )
const io = require ( "nupp.io" )
const paths = require ( "nupp.io.path" )
const contracts = require ( "nupp.io.files.spi" )
const messages = require ( "nupp.io.files.messages" )
const appPaths = require ( "nupp.io.files.path" )

local __nuppT1;do local __nuppT2,__nuppT3;repeat
const chosen = spi . select ( spi . load ("nupp.io.files.spi.Provider") )
if chosen ~= nil then
do  __nuppT1= chosen ;__nuppT2=true;break end
end
if target . host == "native" then
do  __nuppT1= _G . require ( "nupp.runtime.provider.nativefiles" ) ;__nuppT2=true;break end
end
do  __nuppT1= _G . require ( "nupp.runtime.browser.files" ) ;__nuppT2=true;break end
 until true; end; local provider = __nuppT1






































const Info = messages . Info ;__nuppExports["Info"]=Info


const Entry = messages . Entry ;__nuppExports["Entry"]=Entry


const TemporaryOptions = messages . TemporaryOptions ;__nuppExports["TemporaryOptions"]=TemporaryOptions


const Capabilities = messages . Capabilities ;__nuppExports["Capabilities"]=Capabilities

local organization
local application
local roots = { }





setApplicationIdentity=function ( newOrganization , newApplication ) 
const __nupp_call_1= appPaths . encodeIdentity ; __nupp_call_1 ( newOrganization , "organization" )
__nupp_call_1 ( newApplication , "application" )
organization = newOrganization
application = newApplication
end ;__nuppExports["setApplicationIdentity"]=setApplicationIdentity




applicationIdentity=function ( ) 
return organization , application
end ;__nuppExports["applicationIdentity"]=applicationIdentity


local function answered ( value , why ) 
return value , io . toError ( why )
end

local function applicationPath ( kind ) 
if organization == nil or application == nil then
return nil , io . toError ( "application identity is unset; call files.setApplicationIdentity first" , "invalid" )
end
local key = kind .. "\0" .. organization .. "\0" .. application
local remembered = roots [ key ]
if remembered ~= nil then
local created , reason = provider . createDirectory ( remembered )
if not created then
return nil , io . toError ( reason )
end
return remembered , nil
end
local value , reason = provider . applicationPath ( kind , organization , application )
if value ~= nil then
roots [ key ] = value
end

return value , io . toError ( reason )
end







configurationPath=function ( ) 
return applicationPath ( "configuration" )
end ;__nuppExports["configurationPath"]=configurationPath




dataPath=function ( ) 
return applicationPath ( "data" )
end ;__nuppExports["dataPath"]=dataPath




cachePath=function ( ) 
return applicationPath ( "cache" )
end ;__nuppExports["cachePath"]=cachePath



const capabilities = provider . capabilities ;__nuppExports["capabilities"]=capabilities





info=function ( path ) 
return answered ( provider . info ( path ) )
end ;__nuppExports["info"]=info







exists=function ( path ) 
return provider . exists ( path )
end ;__nuppExports["exists"]=exists






isFile=function ( path ) 
return provider . isFile ( path )
end ;__nuppExports["isFile"]=isFile






isDirectory=function ( path ) 
return provider . isDirectory ( path )
end ;__nuppExports["isDirectory"]=isDirectory







isSymlink=function ( path ) 
return provider . isSymlink ( path )
end ;__nuppExports["isSymlink"]=isSymlink





readLink=function ( path ) 
return answered ( provider . readLink ( path ) )
end ;__nuppExports["readLink"]=readLink







createSymlink=function ( targetPath , link , kind ) 
return answered ( provider . createSymlink ( targetPath , link , kind ) )
end ;__nuppExports["createSymlink"]=createSymlink






setReadOnly=function ( path , readOnly ) 
return answered ( provider . setReadOnly ( path , readOnly ) )
end ;__nuppExports["setReadOnly"]=setReadOnly





createDirectory=function ( path ) 
return answered ( provider . createDirectory ( path ) )
end ;__nuppExports["createDirectory"]=createDirectory






remove=function ( path , recursive ) 
return answered ( provider . remove ( path , recursive ) )
end ;__nuppExports["remove"]=remove






rename=function ( from , to ) 
return answered ( provider . rename ( from , to ) )
end ;__nuppExports["rename"]=rename





list=function ( path ) 
return answered ( provider . list ( path ) )
end ;__nuppExports["list"]=list





glob=function ( pattern ) 
return answered ( provider . glob ( pattern ) )
end ;__nuppExports["glob"]=glob





read=function ( path ) 
return answered ( provider . read ( path ) )
end ;__nuppExports["read"]=read






write=function ( path , bytes ) 
return answered ( provider . write ( path , bytes ) )
end ;__nuppExports["write"]=write






append=function ( path , bytes ) 
return answered ( provider . append ( path , bytes ) )
end ;__nuppExports["append"]=append






writeAtomic=function ( path , bytes ) 
return answered ( provider . writeAtomic ( path , bytes ) )
end ;__nuppExports["writeAtomic"]=writeAtomic






copy=function ( from , to ) 
return answered ( provider . copy ( from , to ) )
end ;__nuppExports["copy"]=copy



const pendingTransfers = provider . pendingTransfers ;__nuppExports["pendingTransfers"]=pendingTransfers






open=function ( path , mode ) 
do local __nuppT42=0; local  __nuppT48 ; local __nuppT49=false ; local __nuppT43,__nuppT44,__nuppT45=__nuppT35(function() do local __nuppT50=__nuppT30( provider . open ( path , mode ) ); __nuppT48= __nuppT50[1] ; __nuppT42=1;  __nuppT49=true;  local  file , why = __nuppT50[1] , __nuppT50[2] ;
if file == nil then
return "return",__nuppT30( nil , io . toError ( why ) )
end

do local __nuppT51=__nuppT30( file , nil ) ; __nuppT49=false ; return "return",__nuppT51 end end; return "normal" end,__nuppT31); local __nuppT46={}; local __nuppT47=0; if __nuppT42>=1 and __nuppT49 and __nuppT48~=nil then  local __nuppT52,__nuppT53=__nuppT34(__nuppCleanup1,__nuppT48);  if not __nuppT52 then __nuppT47=__nuppT47+1; __nuppT46[__nuppT47]=__nuppT53 end; end; if not __nuppT43 then if __nuppT47>0 then __nuppT36(__nuppT32(__nuppT44,__nuppT46,1),0) else __nuppT36(__nuppT44,0) end end; if __nuppT47>0 then if __nuppT47>1 then __nuppT36(__nuppT32(__nuppT46[1],__nuppT46,2),0) else __nuppT36(__nuppT46[1],0) end end; if __nuppT44=="return" then  return __nuppT37(__nuppT45,1,__nuppT45.n)  end; end
end ;__nuppExports["open"]=open























lines=function ( path , limit ) 
do local __nuppT55=0; local  __nuppT61 ; local __nuppT62=false ; local __nuppT56,__nuppT57,__nuppT58=__nuppT35(function() do local __nuppT63=__nuppT30( provider . open ( path , "r" ) ); __nuppT61= __nuppT63[1] ; __nuppT55=1;  __nuppT62=true;  local  file , reason = __nuppT63[1] , __nuppT63[2] ;
if file == nil then
return "return",__nuppT30( nil , io . toError ( reason ) )
end

return "return",__nuppT30( (function(__nuppT64,...)  __nuppT62=false; return __nuppT64(...)  end)( io . newLines , file , limit ) , nil ) end; return "normal" end,__nuppT31); local __nuppT59={}; local __nuppT60=0; if __nuppT55>=1 and __nuppT62 and __nuppT61~=nil then  local __nuppT65,__nuppT66=__nuppT34(__nuppCleanup1,__nuppT61);  if not __nuppT65 then __nuppT60=__nuppT60+1; __nuppT59[__nuppT60]=__nuppT66 end; end; if not __nuppT56 then if __nuppT60>0 then __nuppT36(__nuppT32(__nuppT57,__nuppT59,1),0) else __nuppT36(__nuppT57,0) end end; if __nuppT60>0 then if __nuppT60>1 then __nuppT36(__nuppT32(__nuppT59[1],__nuppT59,2),0) else __nuppT36(__nuppT59[1],0) end end; if __nuppT57=="return" then  return __nuppT37(__nuppT58,1,__nuppT58.n)  end; end
end ;__nuppExports["lines"]=lines





createTemporaryFile=function ( options ) 
do local __nuppT68=0; local  __nuppT74 ; local __nuppT75=false ; local __nuppT69,__nuppT70,__nuppT71=__nuppT35(function() do local __nuppT76=__nuppT30( provider . createTemporaryFile ( options ) ); __nuppT74= __nuppT76[1] ; __nuppT68=1;  __nuppT75=true;  local  owner , why = __nuppT76[1] , __nuppT76[2] ;
if owner == nil then
return "return",__nuppT30( nil , io . toError ( why ) )
end

do local __nuppT77=__nuppT30( owner , nil ) ; __nuppT75=false ; return "return",__nuppT77 end end; return "normal" end,__nuppT31); local __nuppT72={}; local __nuppT73=0; if __nuppT68>=1 and __nuppT75 and __nuppT74~=nil then  local __nuppT78,__nuppT79=__nuppT34(__nuppCleanup1,__nuppT74);  if not __nuppT78 then __nuppT73=__nuppT73+1; __nuppT72[__nuppT73]=__nuppT79 end; end; if not __nuppT69 then if __nuppT73>0 then __nuppT36(__nuppT32(__nuppT70,__nuppT72,1),0) else __nuppT36(__nuppT70,0) end end; if __nuppT73>0 then if __nuppT73>1 then __nuppT36(__nuppT32(__nuppT72[1],__nuppT72,2),0) else __nuppT36(__nuppT72[1],0) end end; if __nuppT70=="return" then  return __nuppT37(__nuppT71,1,__nuppT71.n)  end; end
end ;__nuppExports["createTemporaryFile"]=createTemporaryFile





createTemporaryDirectory=function (
options
) 
do local __nuppT81=0; local  __nuppT87 ; local __nuppT88=false ; local __nuppT82,__nuppT83,__nuppT84=__nuppT35(function() do local __nuppT89=__nuppT30( provider . createTemporaryDirectory ( options ) ); __nuppT87= __nuppT89[1] ; __nuppT81=1;  __nuppT88=true;  local  owner , why = __nuppT89[1] , __nuppT89[2] ;
if owner == nil then
return "return",__nuppT30( nil , io . toError ( why ) )
end

do local __nuppT90=__nuppT30( owner , nil ) ; __nuppT88=false ; return "return",__nuppT90 end end; return "normal" end,__nuppT31); local __nuppT85={}; local __nuppT86=0; if __nuppT81>=1 and __nuppT88 and __nuppT87~=nil then  local __nuppT91,__nuppT92=__nuppT34(__nuppCleanup1,__nuppT87);  if not __nuppT91 then __nuppT86=__nuppT86+1; __nuppT85[__nuppT86]=__nuppT92 end; end; if not __nuppT82 then if __nuppT86>0 then __nuppT36(__nuppT32(__nuppT83,__nuppT85,1),0) else __nuppT36(__nuppT83,0) end end; if __nuppT86>0 then if __nuppT86>1 then __nuppT36(__nuppT32(__nuppT85[1],__nuppT85,2),0) else __nuppT36(__nuppT85[1],0) end end; if __nuppT83=="return" then  return __nuppT37(__nuppT84,1,__nuppT84.n)  end; end
end ;__nuppExports["createTemporaryDirectory"]=createTemporaryDirectory





userFolder=function ( which ) 
return answered ( provider . userFolder ( which ) )
end ;__nuppExports["userFolder"]=userFolder




executableDirectory=function ( ) 
return answered ( provider . executableDirectory ( ) )
end ;__nuppExports["executableDirectory"]=executableDirectory




requestPersistentStorage=function ( ) 
return answered ( provider . requestPersistentStorage ( ) )
end ;__nuppExports["requestPersistentStorage"]=requestPersistentStorage
 end);if not __nuppOk then package.loaded["nupp.io.files"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.files"]=__nuppExports;return __nuppExports