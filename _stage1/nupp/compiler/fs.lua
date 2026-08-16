_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local __nuppNativeValue;local function __nuppNative()if __nuppNativeValue then return __nuppNativeValue end;local ffi=require("ffi");ffi.cdef[[const char*nuppNativeError(void);typedef struct NuppBytes NuppBytes;const uint8_t*nuppBytesData(const NuppBytes*);size_t nuppBytesLength(const NuppBytes*);void nuppBytesDestroy(NuppBytes*);typedef struct{uint32_t kind;bool readOnly;uint64_t size;double modified;}NuppFileInfo;bool nuppFilesInfo(const uint8_t*,size_t,bool,NuppFileInfo*);NuppBytes*nuppFilesReadLink(const uint8_t*,size_t);bool nuppFilesCreateSymlink(const uint8_t*,size_t,const uint8_t*,size_t,bool);bool nuppFilesSetReadOnly(const uint8_t*,size_t,bool);bool nuppFilesCreateDirectory(const uint8_t*,size_t);bool nuppFilesRemove(const uint8_t*,size_t,bool);bool nuppFilesRename(const uint8_t*,size_t,const uint8_t*,size_t);NuppBytes*nuppFilesList(const uint8_t*,size_t);NuppBytes*nuppFilesCreateTemporary(const uint8_t*,size_t,const uint8_t*,size_t,const uint8_t*,size_t,bool);NuppBytes*nuppFilesCurrentDirectory(void);NuppBytes*nuppFilesUserFolder(uint32_t);typedef struct NuppFile NuppFile;NuppFile*nuppFileOpen(const uint8_t*,size_t,uint32_t);int64_t nuppFileRead(NuppFile*,uint8_t*,size_t);int64_t nuppFileWrite(NuppFile*,const uint8_t*,size_t);int64_t nuppFileSeek(NuppFile*,int64_t,uint32_t);int64_t nuppFileSize(NuppFile*);bool nuppFileFlush(NuppFile*);bool nuppFileClose(NuppFile*);typedef struct NuppRequest NuppRequest;NuppRequest*nuppFsSubmitRead(const uint8_t*,size_t);NuppRequest*nuppFsSubmitWrite(const uint8_t*,size_t,const uint8_t*,size_t,uint32_t);NuppRequest*nuppFsSubmitCopy(const uint8_t*,size_t,const uint8_t*,size_t);int32_t nuppFsStatus(const NuppRequest*);const uint8_t*nuppFsData(const NuppRequest*);size_t nuppFsLength(const NuppRequest*);const char*nuppFsError(const NuppRequest*);bool nuppFsCancel(NuppRequest*);void nuppFsDestroy(NuppRequest*);size_t nuppFsPoll(void);size_t nuppFsWait(uint64_t);size_t nuppFsPending(void);]];local source=debug.getinfo(1,"S").source;local root=source:match("^@(.+)/[^/]+%.lua$")or".";local wanted=os.getenv("NUPP_NATIVE_LIBRARY");local C;if wanted then C=ffi.load(wanted)else local linked=pcall(function()return ffi.C.nuppNativeError end);if linked then C=ffi.C else local library=ffi.os=="Windows"and"/lib/nupp_native.dll"or"/lib/nupp_native";local ok,lib=pcall(ffi.load,root..library);if ok then C=lib else C=ffi.load(root.."/.."..library)end end end;local function errorText()return ffi.string(C.nuppNativeError())end;local function bytes(value,optional)if value==nil then if optional then return nil end;error("nupp: native operation failed: "..errorText(),3)end;local out=ffi.string(C.nuppBytesData(value),tonumber(C.nuppBytesLength(value)));C.nuppBytesDestroy(value);return out end;__nuppNativeValue={ffi=ffi,C=C,error=errorText,bytes=bytes};return __nuppNativeValue end __nuppLazy(__nuppIO,"files",function() local native=__nuppNative();local ffi,C=native.ffi,native.C;ffi.cdef[[NuppBytes*nuppFilesGlob(const uint8_t*,size_t);]];local files={};local record=ffi.new("NuppFileInfo[1]") local KINDS={[1]="file",[2]="directory",[3]="other",[4]="symlink"} local ENTRIES={f="file",d="directory",l="symlink",o="other"} local FOLDERS={home=0,documents=1,downloads=2,desktop=3,pictures=4,music=5,videos=6} local MODES={r=0,w=1,a=2,["r+"]=3,["w+"]=4,["a+"]=5} local ORIGINS={set=0,current=1,["end"]=2} local READ_SIZE=65536 local PENDING,READY=0,1 local SOURCE,PRIORITY="nupp-files",20 local waits={};local suspending local File={};File.__index=File;local Reader={};Reader.__index=Reader;local Writer={};Writer.__index=Writer local function named(value,what,level)if type(value)=="string"then return value end;if type(value)=="table"and value.toString then return value:toString()end;error("nupp: io.files "..what.." must be a path or a string",level)end local function done(answered)if answered then return true end;return false,native.error()end local function answer(handle)if handle==nil then return nil,native.error()end;return native.bytes(handle)end local function described(path,follow,level)local text=named(path,"path",level+1);if not C.nuppFilesInfo(text,#text,follow,record)then return nil end;return record[0]end local function optional(options,field,level)local value=options and options[field];if value==nil then return""end;if type(value)~="string"then error("nupp: io.files temporary "..field.." must be a string",level)end;return value end local function temporary(options,directory,level)local root=options and options.directory and named(options.directory,"temporary directory",level+1)or"";local prefix=optional(options,"prefix",level+1);local suffix=optional(options,"suffix",level+1);return answer(C.nuppFilesCreateTemporary(root,#root,prefix,#prefix,suffix,#suffix,directory))end local function payload(value,what,level)if type(value)=="string"then return value end;if type(value)=="table"and value.getString then return value:getString()end;error("nupp: io.files "..what.." must be bytes or a byte view",level)end local function harvest()local moved=0;local index=#waits;while index>0 do local entry=waits[index];if C.nuppFsStatus(entry.handle)~=PENDING then waits[index]=waits[#waits];waits[#waits]=nil;moved=moved+1;entry.resume(true)end;index=index-1 end;return moved end local function polled()C.nuppFsPoll();return harvest()end local function slept(waitMs)C.nuppFsWait(waitMs);return harvest()end local function forget(entry)for index=1,#waits do if waits[index]==entry then waits[index]=waits[#waits];waits[#waits]=nil;return end end end local function runtime()if suspending==nil then suspending=require("nupp.suspension")end;return suspending end local function await(handle)if C.nuppFsStatus(handle)~=PENDING then return end;local suspension=runtime();suspension.suspend("file transfer",function(resume,context)local entry={handle=handle,resume=resume};context:source(SOURCE,PRIORITY,polled,slept);waits[#waits+1]=entry;if C.nuppFsStatus(handle)~=PENDING then forget(entry);resume(true);return nil end;return function()forget(entry);C.nuppFsCancel(handle)end end)end local function settled(handle)if handle==nil then return nil,native.error()end;await(handle);if C.nuppFsStatus(handle)~=READY then local reason=ffi.string(C.nuppFsError(handle));C.nuppFsDestroy(handle);return nil,reason end;return handle end local function transferred(handle)local done,reason=settled(handle);if not done then return false,reason end;C.nuppFsDestroy(done);return true end local function fetched(handle)local done,reason=settled(handle);if not done then return nil,reason end;local out=ffi.string(C.nuppFsData(done),tonumber(C.nuppFsLength(done)));C.nuppFsDestroy(done);return out end local function whole(value,what,level)if type(value)~="number"or value~=math.floor(value)then error("nupp: io.files "..what.." must be an integer",level)end;return value end local function counted(value,what,level)if whole(value,what,level)<0 then error("nupp: io.files "..what.." must not be negative",level)end;return value end local function live(self,what,level)if self._closed then error("nupp: io.files "..what.." is closed",level)end;return self end function File:isReleased()return self._closed end function File:close()if self._closed then return true end;self._closed=true;local handle=self._handle;self._handle=nil;C.nuppFileClose(handle);return true end function File:size()live(self,"File",2);local size=tonumber(C.nuppFileSize(self._handle));if size<0 then return nil,native.error()end;return size end function File:seek(offset,origin)live(self,"File",2);local whence=ORIGINS[origin or"set"];if whence==nil then error("nupp: io.files has no seek origin named "..tostring(origin),2)end;local at=tonumber(C.nuppFileSeek(self._handle,whole(offset or 0,"seek offset",2),whence));if at<0 then return nil,native.error()end;return at end function File:position()live(self,"File",2);return self:seek(0,"current")end function File:flush()live(self,"File",2);if C.nuppFileFlush(self._handle)then return true end;return false,native.error()end function File:newReader()live(self,"File",2);return setmetatable({_file=self,_scratch=nil,_capacity=0,_closed=false},Reader)end function File:newWriter()live(self,"File",2);return setmetatable({_file=self,_closed=false},Writer)end local function scratch(self,count)if count>self._capacity then local size=self._capacity*2;if size<count then size=count end;if size<READ_SIZE then size=READ_SIZE end;self._scratch=ffi.new("uint8_t[?]",size);self._capacity=size end;return self._scratch end local function usable(self)if self._closed then return nil,"the reader is closed"end;if self._file._closed then return nil,"the file is closed"end;return self._file end function Reader:read(count)local file,reason=usable(self);if not file then return nil,reason end;count=whole(count,"Reader:read count",2);if count<1 then count=1 end;local into=scratch(self,count);local got=tonumber(C.nuppFileRead(file._handle,into,count));if got<0 then return nil,native.error()end;if got==0 then return""end;return ffi.string(into,got)end function Reader:readInto(destination,offset,count)local file,reason=usable(self);if not file then return nil,reason end;offset=counted(offset or 0,"Reader:readInto offset",2);count=counted(count or READ_SIZE,"Reader:readInto count",2);if count==0 then return 0 end;local data=rawget(destination,"_data");local capacity=rawget(destination,"_capacity");if data==nil and capacity==nil then local chunk,why=self:read(count);if chunk==nil then return nil,why end;if #chunk==0 then return 0 end;destination:setString(chunk,offset);return #chunk end;destination:ensureCapacity(offset+count);data=rawget(destination,"_data");local length=rawget(destination,"_length");if offset>length then ffi.fill(data+length,offset-length,0)end;local got=tonumber(C.nuppFileRead(file._handle,data+offset,count));if got<0 then return nil,native.error()end;if offset+got>length then rawset(destination,"_length",offset+got)end;return got end function Reader:transferTo(destination)local file,reason=usable(self);if not file then return nil,reason end;local total=0;while true do local chunk,why=self:read(READ_SIZE);if chunk==nil then return nil,why end;if chunk==""then return total end;local wrote,failure=destination:write(chunk);if not wrote then return nil,failure end;total=total+#chunk end end function Reader:close()self._closed=true;self._scratch=nil;self._capacity=0;return true end local function writable(self)if self._closed then return nil,"the writer is closed"end;if self._file._closed then return nil,"the file is closed"end;return self._file end function Writer:write(bytes)local file,reason=writable(self);if not file then return false,reason end;if type(bytes)~="string"then error("nupp: io.files Writer:write needs a string",2)end;if C.nuppFileWrite(file._handle,bytes,#bytes)<0 then return false,native.error()end;return true end function Writer:writeFrom(source,offset,count)local file,reason=writable(self);if not file then return nil,reason end;local length=source:length();offset=counted(offset or 0,"Writer:writeFrom offset",2);count=counted(count==nil and length-offset or count,"Writer:writeFrom count",2);if offset+count>length then error("nupp: io.files Writer:writeFrom range is past the end",2)end;if count==0 then return 0 end;local data=rawget(source,"_data");if data==nil then local wrote,failure=self:write(source:getString(offset,count));if not wrote then return nil,failure end;return count end;if C.nuppFileWrite(file._handle,data+offset,count)<0 then return nil,native.error()end;return count end function Writer:writeView(source,offset,count)local file,reason=writable(self);if not file then return nil,reason end;local length=source:length();offset=counted(offset or 0,"Writer:writeView offset",2);count=counted(count==nil and length-offset or count,"Writer:writeView count",2);if offset+count>length then error("nupp: io.files Writer:writeView range is past the end",2)end;local wrote,failure=self:write(source:getString():sub(offset+1,offset+count));if not wrote then return nil,failure end;return count end function Writer:flush()local file,reason=writable(self);if not file then return false,reason end;return file:flush()end function Writer:close()self._closed=true;return true end function files.info(path)local found=described(path,true,2);if not found then return nil,native.error()end;return{kind=KINDS[tonumber(found.kind)]or"other",size=tonumber(found.size),modified=found.modified,readOnly=found.readOnly}end function files.exists(path)return described(path,true,2)~=nil end function files.isFile(path)local found=described(path,true,2);return found~=nil and found.kind==1 end function files.isDirectory(path)local found=described(path,true,2);return found~=nil and found.kind==2 end function files.isSymlink(path)local found=described(path,false,2);return found~=nil and found.kind==4 end function files.readLink(path)local text=named(path,"path",2);return answer(C.nuppFilesReadLink(text,#text))end function files.createSymlink(target,link,kind)local to=named(target,"symlink target",2);local at=named(link,"symlink path",2);if kind~=nil and kind~="file"and kind~="directory"then error("nupp: io.files symlink kind must be 'file' or 'directory'",2)end;return done(C.nuppFilesCreateSymlink(to,#to,at,#at,kind=="directory"))end function files.setReadOnly(path,readOnly)local text=named(path,"path",2);return done(C.nuppFilesSetReadOnly(text,#text,readOnly and true or false))end function files.createDirectory(path)local text=named(path,"path",2);return done(C.nuppFilesCreateDirectory(text,#text))end function files.remove(path,recursive)local text=named(path,"path",2);return done(C.nuppFilesRemove(text,#text,recursive and true or false))end function files.rename(from,to)local source=named(from,"source path",2);local destination=named(to,"destination path",2);return done(C.nuppFilesRename(source,#source,destination,#destination))end function files.list(path)local text=named(path,"path",2);local handle=C.nuppFilesList(text,#text);if handle==nil then return nil,native.error()end;local blob=native.bytes(handle);local entries,at={},1;while at<=#blob do local stop=blob:find("\0",at+1,true);entries[#entries+1]={kind=ENTRIES[blob:sub(at,at)]or"other",name=blob:sub(at+1,stop-1)};at=stop+1 end;return entries end function files.glob(pattern)local text=named(pattern,"glob pattern",2);local handle=C.nuppFilesGlob(text,#text);if handle==nil then return nil,native.error()end;local blob=native.bytes(handle);local matches,at={},1;while at<=#blob do local stop=blob:find("\0",at,true);if not stop then matches[#matches+1]=blob:sub(at);break end;matches[#matches+1]=blob:sub(at,stop-1);at=stop+1 end;return matches end local Temporary={};Temporary.__index=Temporary;Temporary.__tostring=function(self)return self._text end function Temporary:toString()return self._text end function Temporary:isReleased()return self._closed end function Temporary:persist(destination)if self._closed then return false,"the temporary path is released"end;local to=named(destination,"destination path",2);local moved,reason=done(C.nuppFilesRename(self._text,#self._text,to,#to));if not moved then return false,reason end;self._closed=true;return true end function Temporary:close()if self._closed then return true end;self._closed=true;return done(C.nuppFilesRemove(self._text,#self._text,self._directory))end File.drop=File.close;Reader.drop=Reader.close;Writer.drop=Writer.close;Temporary.drop=Temporary.close function files.createTemporaryFile(options)local text,reason=temporary(options,false,2);if not text then return nil,reason end;return setmetatable({_text=text,_directory=false,_closed=false},Temporary)end function files.createTemporaryDirectory(options)local text,reason=temporary(options,true,2);if not text then return nil,reason end;return setmetatable({_text=text,_directory=true,_closed=false},Temporary)end function files.read(path)local text=named(path,"path",2);return fetched(C.nuppFsSubmitRead(text,#text))end function files.write(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,0))end function files.append(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,1))end function files.writeAtomic(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,2))end function files.copy(from,to)local source=named(from,"source path",2);local destination=named(to,"destination path",2);return transferred(C.nuppFsSubmitCopy(source,#source,destination,#destination))end function files.pendingTransfers()return tonumber(C.nuppFsPending())end function files.open(path,mode)local text=named(path,"path",2);local selected=MODES[mode or"r"];if selected==nil then error("nupp: io.files has no mode named "..tostring(mode),2)end;local handle=C.nuppFileOpen(text,#text,selected);if handle==nil then return nil,native.error()end;return setmetatable({_handle=handle,_closed=false},File)end function files.lines(path)local file,reason=files.open(path,"r");if not file then return nil,reason end;local reader=file:newReader();local held,finished="",false;local function trimmed(line)if line:sub(-1)=="\r"then return line:sub(1,-2)end;return line end;return function()if finished then return nil end;while true do local stop=held:find("\n",1,true);if stop then local line=held:sub(1,stop-1);held=held:sub(stop+1);return trimmed(line)end;local chunk=reader:read(READ_SIZE);if chunk==nil or chunk==""then finished=true;file:close();if #held>0 then local line=held;held="";return trimmed(line)end;return nil end;held=held..chunk end end end function files.currentDirectory()return answer(C.nuppFilesCurrentDirectory())end function files.userFolder(which)local index=FOLDERS[which];if index==nil then error("nupp: io.files has no user folder named "..tostring(which),2)end;return answer(C.nuppFilesUserFolder(index))end return files end);


















local fs = { }

local function normalize ( path )
path = path : gsub ( "\\" , "/" ) : gsub ( "/+" , "/" )
path = path : gsub ( "^%./" , "" ) : gsub ( "/%./" , "/" )
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
return normalize ( path ) : match ( "^(.*)/[^/]+$" ) or "."
end

local function basename ( path )
return normalize ( path ) : match ( "([^/]+)$" ) or path
end




local function absolute ( path )
path = normalize ( path )
if path : sub ( 1 , 1 ) ~= "/" and not path : match ( "^[A-Za-z]:/" ) then
local cwd = nupp . io . files . currentDirectory ( )
path = join ( cwd or "." , path )
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
local separator = prefix == "/" and "" or ( # parts > 0 and "/" or "" )

return prefix .. separator .. table . concat ( parts , "/" )
end



local function canonical ( path )
local fallback = absolute ( path )
if package . config : sub ( 1 , 1 ) ~= "\\" then
local code , output = require ( "nupp.compiler.build.process" ) . capture ( { "realpath" , fallback } )
if code == 0 then
local resolved = output : match ( "([^\r\n]+)" )
if resolved then
return normalize ( resolved )
end
end
end

return fallback
end

local function readFile ( path )
local f , err = io . open ( path , "rb" )
if not f then





if nupp . io . files . isDirectory ( path ) then
return nil , path .. " is a directory"
end

return nil , err
end
local text = f : read ( "*a" )
f : close ( )
if not text then
if nupp . io . files . isDirectory ( path ) then
return nil , path .. " is a directory"
end

return nil , path .. " cannot be read"
end

return text
end

local function exists ( path )
local f = io . open ( path , "rb" )
if not f then
return false
end
f : close ( )

return true
end

local function mkdir ( path )
if path == "" or path == "." then
return true
end

return ( nupp . io . files . createDirectory ( path ) )
end

local function writeFile ( path , text )
if not mkdir ( dirname ( path ) ) then
return nil , "cannot create " .. dirname ( path )
end
local tmp = path .. ".tmp"
local f , err = io . open ( tmp , "wb" )
if not f then
return nil , err
end
f : write ( text )
f : close ( )
local ok , renameErr = os . rename ( tmp , path )
if not ok and exists ( path ) then
local backup = path .. ".old"
os . remove ( backup )
local moved , moveErr = os . rename ( path , backup )
if not moved then
os . remove ( tmp ) ;
return nil , moveErr
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
return nil , renameErr
end

return true
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
while # pending > 0 do
local directory = table . remove ( pending )
for _ , entry in ipairs ( nupp . io . files . list ( directory ) or { } ) do
local child = join ( directory , entry . name )
local kind = entry . kind
if kind == "symlink" then
local resolved = nupp . io . files . info ( child )
kind = resolved and resolved . kind or "other"
end
if kind == "directory" then
if not ( skipDirectory and skipDirectory ( entry . name ) ) then
pending [ # pending + 1 ] = child
end
elseif kind == "file" then
files [ # files + 1 ] = normalize ( child )
end
end
end
table . sort ( files )

return files
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
fs . writeFile = writeFile
fs . writeFileIfChanged = writeFileIfChanged
fs . copyFile = copyFile
fs . listFiles = listFiles

return fs
