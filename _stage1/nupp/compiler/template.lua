_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local __nuppNativeValue;local function __nuppNative()if __nuppNativeValue then return __nuppNativeValue end;local ffi=require("ffi");ffi.cdef[[const char*nuppNativeError(void);typedef struct NuppBytes NuppBytes;const uint8_t*nuppBytesData(const NuppBytes*);size_t nuppBytesLength(const NuppBytes*);void nuppBytesDestroy(NuppBytes*);typedef struct{uint32_t kind;bool readOnly;uint64_t size;double modified;}NuppFileInfo;bool nuppFilesInfo(const uint8_t*,size_t,bool,NuppFileInfo*);NuppBytes*nuppFilesReadLink(const uint8_t*,size_t);bool nuppFilesCreateSymlink(const uint8_t*,size_t,const uint8_t*,size_t,bool);bool nuppFilesSetReadOnly(const uint8_t*,size_t,bool);bool nuppFilesCreateDirectory(const uint8_t*,size_t);bool nuppFilesRemove(const uint8_t*,size_t,bool);bool nuppFilesRename(const uint8_t*,size_t,const uint8_t*,size_t);NuppBytes*nuppFilesList(const uint8_t*,size_t);NuppBytes*nuppFilesCreateTemporary(const uint8_t*,size_t,const uint8_t*,size_t,const uint8_t*,size_t,bool);NuppBytes*nuppFilesCurrentDirectory(void);NuppBytes*nuppFilesUserFolder(uint32_t);typedef struct NuppFile NuppFile;NuppFile*nuppFileOpen(const uint8_t*,size_t,uint32_t);int64_t nuppFileRead(NuppFile*,uint8_t*,size_t);int64_t nuppFileWrite(NuppFile*,const uint8_t*,size_t);int64_t nuppFileSeek(NuppFile*,int64_t,uint32_t);int64_t nuppFileSize(NuppFile*);bool nuppFileFlush(NuppFile*);bool nuppFileClose(NuppFile*);typedef struct NuppRequest NuppRequest;NuppRequest*nuppFsSubmitRead(const uint8_t*,size_t);NuppRequest*nuppFsSubmitWrite(const uint8_t*,size_t,const uint8_t*,size_t,uint32_t);NuppRequest*nuppFsSubmitCopy(const uint8_t*,size_t,const uint8_t*,size_t);int32_t nuppFsStatus(const NuppRequest*);const uint8_t*nuppFsData(const NuppRequest*);size_t nuppFsLength(const NuppRequest*);const char*nuppFsError(const NuppRequest*);bool nuppFsCancel(NuppRequest*);void nuppFsDestroy(NuppRequest*);size_t nuppFsPoll(void);size_t nuppFsWait(uint64_t);size_t nuppFsPending(void);]];local source=debug.getinfo(1,"S").source;local root=source:match("^@(.+)/[^/]+%.lua$")or".";local wanted=os.getenv("NUPP_NATIVE_LIBRARY");local C;if wanted then C=ffi.load(wanted)else local linked=pcall(function()return ffi.C.nuppNativeError end);if linked then C=ffi.C else local library=ffi.os=="Windows"and"/lib/nupp_native.dll"or"/lib/nupp_native";local ok,lib=pcall(ffi.load,root..library);if ok then C=lib else C=ffi.load(root.."/.."..library)end end end;local function errorText()return ffi.string(C.nuppNativeError())end;local function bytes(value,optional)if value==nil then if optional then return nil end;error("nupp: native operation failed: "..errorText(),3)end;local out=ffi.string(C.nuppBytesData(value),tonumber(C.nuppBytesLength(value)));C.nuppBytesDestroy(value);return out end;__nuppNativeValue={ffi=ffi,C=C,error=errorText,bytes=bytes};return __nuppNativeValue end __nuppLazy(__nuppIO,"files",function() local native=__nuppNative();local ffi,C=native.ffi,native.C;ffi.cdef[[NuppBytes*nuppFilesGlob(const uint8_t*,size_t);]];local files={};local record=ffi.new("NuppFileInfo[1]") local KINDS={[1]="file",[2]="directory",[3]="other",[4]="symlink"} local ENTRIES={f="file",d="directory",l="symlink",o="other"} local FOLDERS={home=0,documents=1,downloads=2,desktop=3,pictures=4,music=5,videos=6} local MODES={r=0,w=1,a=2,["r+"]=3,["w+"]=4,["a+"]=5} local ORIGINS={set=0,current=1,["end"]=2} local READ_SIZE=65536 local PENDING,READY=0,1 local SOURCE,PRIORITY="nupp-files",20 local waits={};local suspending local File={};File.__index=File;local Reader={};Reader.__index=Reader;local Writer={};Writer.__index=Writer local function named(value,what,level)if type(value)=="string"then return value end;if type(value)=="table"and value.toString then return value:toString()end;error("nupp: io.files "..what.." must be a path or a string",level)end local function done(answered)if answered then return true end;return false,native.error()end local function answer(handle)if handle==nil then return nil,native.error()end;return native.bytes(handle)end local function described(path,follow,level)local text=named(path,"path",level+1);if not C.nuppFilesInfo(text,#text,follow,record)then return nil end;return record[0]end local function optional(options,field,level)local value=options and options[field];if value==nil then return""end;if type(value)~="string"then error("nupp: io.files temporary "..field.." must be a string",level)end;return value end local function temporary(options,directory,level)local root=options and options.directory and named(options.directory,"temporary directory",level+1)or"";local prefix=optional(options,"prefix",level+1);local suffix=optional(options,"suffix",level+1);return answer(C.nuppFilesCreateTemporary(root,#root,prefix,#prefix,suffix,#suffix,directory))end local function payload(value,what,level)if type(value)=="string"then return value end;if type(value)=="table"and value.getString then return value:getString()end;error("nupp: io.files "..what.." must be bytes or a byte view",level)end local function harvest()local moved=0;local index=#waits;while index>0 do local entry=waits[index];if C.nuppFsStatus(entry.handle)~=PENDING then waits[index]=waits[#waits];waits[#waits]=nil;moved=moved+1;entry.resume(true)end;index=index-1 end;return moved end local function polled()C.nuppFsPoll();return harvest()end local function slept(waitMs)C.nuppFsWait(waitMs);return harvest()end local function forget(entry)for index=1,#waits do if waits[index]==entry then waits[index]=waits[#waits];waits[#waits]=nil;return end end end local function runtime()if suspending==nil then suspending=require("nupp.suspension")end;return suspending end local function await(handle)if C.nuppFsStatus(handle)~=PENDING then return end;local suspension=runtime();suspension.suspend("file transfer",function(resume,context)local entry={handle=handle,resume=resume};context:source(SOURCE,PRIORITY,polled,slept);waits[#waits+1]=entry;if C.nuppFsStatus(handle)~=PENDING then forget(entry);resume(true);return nil end;return function()forget(entry);C.nuppFsCancel(handle)end end)end local function settled(handle)if handle==nil then return nil,native.error()end;await(handle);if C.nuppFsStatus(handle)~=READY then local reason=ffi.string(C.nuppFsError(handle));C.nuppFsDestroy(handle);return nil,reason end;return handle end local function transferred(handle)local done,reason=settled(handle);if not done then return false,reason end;C.nuppFsDestroy(done);return true end local function fetched(handle)local done,reason=settled(handle);if not done then return nil,reason end;local out=ffi.string(C.nuppFsData(done),tonumber(C.nuppFsLength(done)));C.nuppFsDestroy(done);return out end local function whole(value,what,level)if type(value)~="number"or value~=math.floor(value)then error("nupp: io.files "..what.." must be an integer",level)end;return value end local function counted(value,what,level)if whole(value,what,level)<0 then error("nupp: io.files "..what.." must not be negative",level)end;return value end local function live(self,what,level)if self._closed then error("nupp: io.files "..what.." is closed",level)end;return self end function File:isReleased()return self._closed end function File:close()if self._closed then return true end;self._closed=true;local handle=self._handle;self._handle=nil;C.nuppFileClose(handle);return true end function File:size()live(self,"File",2);local size=tonumber(C.nuppFileSize(self._handle));if size<0 then return nil,native.error()end;return size end function File:seek(offset,origin)live(self,"File",2);local whence=ORIGINS[origin or"set"];if whence==nil then error("nupp: io.files has no seek origin named "..tostring(origin),2)end;local at=tonumber(C.nuppFileSeek(self._handle,whole(offset or 0,"seek offset",2),whence));if at<0 then return nil,native.error()end;return at end function File:position()live(self,"File",2);return self:seek(0,"current")end function File:flush()live(self,"File",2);if C.nuppFileFlush(self._handle)then return true end;return false,native.error()end function File:newReader()live(self,"File",2);return setmetatable({_file=self,_scratch=nil,_capacity=0,_closed=false},Reader)end function File:newWriter()live(self,"File",2);return setmetatable({_file=self,_closed=false},Writer)end local function scratch(self,count)if count>self._capacity then local size=self._capacity*2;if size<count then size=count end;if size<READ_SIZE then size=READ_SIZE end;self._scratch=ffi.new("uint8_t[?]",size);self._capacity=size end;return self._scratch end local function usable(self)if self._closed then return nil,"the reader is closed"end;if self._file._closed then return nil,"the file is closed"end;return self._file end function Reader:read(count)local file,reason=usable(self);if not file then return nil,reason end;count=whole(count,"Reader:read count",2);if count<1 then count=1 end;local into=scratch(self,count);local got=tonumber(C.nuppFileRead(file._handle,into,count));if got<0 then return nil,native.error()end;if got==0 then return""end;return ffi.string(into,got)end function Reader:readInto(destination,offset,count)local file,reason=usable(self);if not file then return nil,reason end;offset=counted(offset or 0,"Reader:readInto offset",2);count=counted(count or READ_SIZE,"Reader:readInto count",2);if count==0 then return 0 end;local data=rawget(destination,"_data");local capacity=rawget(destination,"_capacity");if data==nil and capacity==nil then local chunk,why=self:read(count);if chunk==nil then return nil,why end;if #chunk==0 then return 0 end;destination:setString(chunk,offset);return #chunk end;destination:ensureCapacity(offset+count);data=rawget(destination,"_data");local length=rawget(destination,"_length");if offset>length then ffi.fill(data+length,offset-length,0)end;local got=tonumber(C.nuppFileRead(file._handle,data+offset,count));if got<0 then return nil,native.error()end;if offset+got>length then rawset(destination,"_length",offset+got)end;return got end function Reader:transferTo(destination)local file,reason=usable(self);if not file then return nil,reason end;local total=0;while true do local chunk,why=self:read(READ_SIZE);if chunk==nil then return nil,why end;if chunk==""then return total end;local wrote,failure=destination:write(chunk);if not wrote then return nil,failure end;total=total+#chunk end end function Reader:close()self._closed=true;self._scratch=nil;self._capacity=0;return true end local function writable(self)if self._closed then return nil,"the writer is closed"end;if self._file._closed then return nil,"the file is closed"end;return self._file end function Writer:write(bytes)local file,reason=writable(self);if not file then return false,reason end;if type(bytes)~="string"then error("nupp: io.files Writer:write needs a string",2)end;if C.nuppFileWrite(file._handle,bytes,#bytes)<0 then return false,native.error()end;return true end function Writer:writeFrom(source,offset,count)local file,reason=writable(self);if not file then return nil,reason end;local length=source:length();offset=counted(offset or 0,"Writer:writeFrom offset",2);count=counted(count==nil and length-offset or count,"Writer:writeFrom count",2);if offset+count>length then error("nupp: io.files Writer:writeFrom range is past the end",2)end;if count==0 then return 0 end;local data=rawget(source,"_data");if data==nil then local wrote,failure=self:write(source:getString(offset,count));if not wrote then return nil,failure end;return count end;if C.nuppFileWrite(file._handle,data+offset,count)<0 then return nil,native.error()end;return count end function Writer:writeView(source,offset,count)local file,reason=writable(self);if not file then return nil,reason end;local length=source:length();offset=counted(offset or 0,"Writer:writeView offset",2);count=counted(count==nil and length-offset or count,"Writer:writeView count",2);if offset+count>length then error("nupp: io.files Writer:writeView range is past the end",2)end;local wrote,failure=self:write(source:getString():sub(offset+1,offset+count));if not wrote then return nil,failure end;return count end function Writer:flush()local file,reason=writable(self);if not file then return false,reason end;return file:flush()end function Writer:close()self._closed=true;return true end function files.info(path)local found=described(path,true,2);if not found then return nil,native.error()end;return{kind=KINDS[tonumber(found.kind)]or"other",size=tonumber(found.size),modified=found.modified,readOnly=found.readOnly}end function files.exists(path)return described(path,true,2)~=nil end function files.isFile(path)local found=described(path,true,2);return found~=nil and found.kind==1 end function files.isDirectory(path)local found=described(path,true,2);return found~=nil and found.kind==2 end function files.isSymlink(path)local found=described(path,false,2);return found~=nil and found.kind==4 end function files.readLink(path)local text=named(path,"path",2);return answer(C.nuppFilesReadLink(text,#text))end function files.createSymlink(target,link,kind)local to=named(target,"symlink target",2);local at=named(link,"symlink path",2);if kind~=nil and kind~="file"and kind~="directory"then error("nupp: io.files symlink kind must be 'file' or 'directory'",2)end;return done(C.nuppFilesCreateSymlink(to,#to,at,#at,kind=="directory"))end function files.setReadOnly(path,readOnly)local text=named(path,"path",2);return done(C.nuppFilesSetReadOnly(text,#text,readOnly and true or false))end function files.createDirectory(path)local text=named(path,"path",2);return done(C.nuppFilesCreateDirectory(text,#text))end function files.remove(path,recursive)local text=named(path,"path",2);return done(C.nuppFilesRemove(text,#text,recursive and true or false))end function files.rename(from,to)local source=named(from,"source path",2);local destination=named(to,"destination path",2);return done(C.nuppFilesRename(source,#source,destination,#destination))end function files.list(path)local text=named(path,"path",2);local handle=C.nuppFilesList(text,#text);if handle==nil then return nil,native.error()end;local blob=native.bytes(handle);local entries,at={},1;while at<=#blob do local stop=blob:find("\0",at+1,true);entries[#entries+1]={kind=ENTRIES[blob:sub(at,at)]or"other",name=blob:sub(at+1,stop-1)};at=stop+1 end;return entries end function files.glob(pattern)local text=named(pattern,"glob pattern",2);local handle=C.nuppFilesGlob(text,#text);if handle==nil then return nil,native.error()end;local blob=native.bytes(handle);local matches,at={},1;while at<=#blob do local stop=blob:find("\0",at,true);if not stop then matches[#matches+1]=blob:sub(at);break end;matches[#matches+1]=blob:sub(at,stop-1);at=stop+1 end;return matches end local Temporary={};Temporary.__index=Temporary;Temporary.__tostring=function(self)return self._text end function Temporary:toString()return self._text end function Temporary:isReleased()return self._closed end function Temporary:persist(destination)if self._closed then return false,"the temporary path is released"end;local to=named(destination,"destination path",2);local moved,reason=done(C.nuppFilesRename(self._text,#self._text,to,#to));if not moved then return false,reason end;self._closed=true;return true end function Temporary:close()if self._closed then return true end;self._closed=true;return done(C.nuppFilesRemove(self._text,#self._text,self._directory))end File.drop=File.close;Reader.drop=Reader.close;Writer.drop=Writer.close;Temporary.drop=Temporary.close function files.createTemporaryFile(options)local text,reason=temporary(options,false,2);if not text then return nil,reason end;return setmetatable({_text=text,_directory=false,_closed=false},Temporary)end function files.createTemporaryDirectory(options)local text,reason=temporary(options,true,2);if not text then return nil,reason end;return setmetatable({_text=text,_directory=true,_closed=false},Temporary)end function files.read(path)local text=named(path,"path",2);return fetched(C.nuppFsSubmitRead(text,#text))end function files.write(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,0))end function files.append(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,1))end function files.writeAtomic(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,2))end function files.copy(from,to)local source=named(from,"source path",2);local destination=named(to,"destination path",2);return transferred(C.nuppFsSubmitCopy(source,#source,destination,#destination))end function files.pendingTransfers()return tonumber(C.nuppFsPending())end function files.open(path,mode)local text=named(path,"path",2);local selected=MODES[mode or"r"];if selected==nil then error("nupp: io.files has no mode named "..tostring(mode),2)end;local handle=C.nuppFileOpen(text,#text,selected);if handle==nil then return nil,native.error()end;return setmetatable({_handle=handle,_closed=false},File)end function files.lines(path)local file,reason=files.open(path,"r");if not file then return nil,reason end;local reader=file:newReader();local held,finished="",false;local function trimmed(line)if line:sub(-1)=="\r"then return line:sub(1,-2)end;return line end;return function()if finished then return nil end;while true do local stop=held:find("\n",1,true);if stop then local line=held:sub(1,stop-1);held=held:sub(stop+1);return trimmed(line)end;local chunk=reader:read(READ_SIZE);if chunk==nil or chunk==""then finished=true;file:close();if #held>0 then local line=held;held="";return trimmed(line)end;return nil end;held=held..chunk end end end function files.currentDirectory()return answer(C.nuppFilesCurrentDirectory())end function files.userFolder(which)local index=FOLDERS[which];if index==nil then error("nupp: io.files has no user folder named "..tostring(which),2)end;return answer(C.nuppFilesUserFolder(index))end return files end);































local bundled = require ( "nupp.compiler.bundled" )
local fs = require ( "nupp.compiler.fs" )
local process = require ( "nupp.compiler.build.process" )
local syntax = require ( "nupp.compiler.build.syntax" )

local join , normalize = fs . join , fs . normalize
local basename = fs . basename
local readFile , writeFile , exists = fs . readFile , fs . writeFile , fs . exists

local template = { }


const BUILTIN_PREFIX = "/templates"






const STEPS = { git = true , check = true , build = true , test = true }


const REMOTE_STEPS = { git = true }






const FORBIDDEN_IN_VALUE = "[/\\%z]"


template.Source = {} template.Source.__index = template.Source

























template.Variable = {} template.Variable.__index = template.Variable














template.Manifest = {} template.Manifest.__index = template.Manifest







template.File = {} template.File.__index = template.File













template.Plan = {} template.Plan.__index = template.Plan




























local function isPathSpelling ( spelling )
return spelling : sub (
1 ,
1
) == "." or spelling : sub ( 1 , 1 ) == "/" or spelling : sub ( 1 , 1 ) == "~" or spelling : match ( "^[A-Za-z]:[/\\]" ) ~= nil
end

local function isUrlSpelling ( spelling )
return spelling : match (
"^[a-z][a-z0-9+.-]*://"
) ~= nil or spelling : match ( "^git@" ) ~= nil or spelling : match ( "^ssh://" ) ~= nil
end







function template . builtins ( )
local seen = { }
local names = { }
for _ , path in ipairs ( bundled . list ( BUILTIN_PREFIX ) ) do
local name = path : sub ( # BUILTIN_PREFIX + 2 ) : match ( "^([^/]+)/" )
if name and not seen [ name ] then
seen [ name ] = true
names [ # names + 1 ] = name
end
end
table . sort ( names )

return names
end








function template . builtinDescription ( name )
local text = bundled . source ( BUILTIN_PREFIX .. "/" .. name .. "/template.lua" )
if not text then
return ""
end
local manifest = template . manifest ( text , name .. "/template.lua" )

return manifest and manifest . description or ""
end








function template . resolve ( spelling , from , rev )
if from then
if spelling then
return nil , "--from names the template, so a template argument is one too many"
end
if rev then
return nil , "--rev has no meaning for a template directory"
end

return setmetatable({ kind =  "directory" ,  path =  normalize ( from ) }, template.Source)
end
spelling = spelling or "app"
if isPathSpelling ( spelling ) then
if rev then
return nil , "--rev has no meaning for a template directory"
end

return setmetatable({ kind =  "directory" ,  path =  normalize ( spelling ) }, template.Source)
end
local asked , attached = spelling , nil
local base , suffix = spelling : match ( "^(.-)@([^@/]+)$" )
if base and not isUrlSpelling ( spelling ) then
asked , attached = base , suffix
end
if attached and rev then
return nil , "the revision is given twice, once as @" .. attached .. " and once as --rev"
end
local wanted = attached or rev
if isUrlSpelling ( asked ) then
return setmetatable({ kind =  "remote" ,  url =  asked ,  rev =  wanted }, template.Source)
end
if not asked : find ( "/" , 1 , true ) then
if wanted then
return nil , "a built-in template has no revisions to choose between"
end
for _ , name in ipairs ( template . builtins ( ) ) do
if name == asked then
return setmetatable({ kind =  "builtin" ,  name =  name }, template.Source)
end
end

return nil , "no built-in template is called " .. asked .. "\nAvailable: " .. table . concat (
template . builtins ( ) ,
", "
)
end
local owner , repo , subdir = asked : match ( "^([^/]+)/([^/]+)/?(.*)$" )
if not owner or owner == "" or repo == "" then
return nil , "a repository template is spelled owner/repo, optionally followed by a path"
end

return setmetatable({ kind =
"remote" ,  url =
"https://github.com/" .. owner .. "/" .. repo ,  subdir =
subdir ~= "" and subdir or nil ,  rev =
wanted }, template.Source)

end





function template . describe ( source )
if source . kind == "builtin" then
return "built-in template " .. tostring ( source . name )
end
if source . kind == "directory" then
return tostring ( source . path )
end
local where = tostring ( source . url )
if source . subdir then
where = where .. " (" .. source . subdir .. ")"
end
if source . commit then
return where .. " at " .. source . commit
end

return where .. ( source . rev and ( " at " .. source . rev ) or "" )
end










local function walk ( root )
local found = { }
local pending = { "" }
while # pending > 0 do
local relative = table . remove ( pending )
local entries , listErr = nupp . io . files . list ( join ( root , relative ) )
if not entries then
return nil , "cannot read " .. join ( root , relative ) .. ": " .. tostring ( listErr )
end
for _ , entry in ipairs ( entries ) do
local child = relative == "" and entry . name or relative .. "/" .. entry . name
if entry . kind == "symlink" then
return nil , child .. " is a symbolic link, which a template may not contain"

elseif entry . kind == "directory" then



if entry . name ~= ".git" then
pending [ # pending + 1 ] = child
end

elseif entry . kind == "file" then
if child ~= "template.lua" then
found [ # found + 1 ] = child
end
end
end
end
table . sort ( found )

return found
end










local function sandbox ( )
return {
pairs = pairs ,
ipairs = ipairs ,
type = type ,
tostring = tostring ,
tonumber = tonumber ,
select = select ,
error = error ,
string = string ,
table = table ,
math = math ,
}
end



const INSTRUCTION_BUDGET = 200000

local function loadSandboxed ( text , where )
local chunk , loadErr = loadstring ( text , "=" .. where )
if not chunk then
return nil , where .. " does not parse: " .. tostring ( loadErr )
end
setfenv ( chunk , sandbox ( ) )






pcall ( jit . off , chunk , true )
local hooked = false
debug . sethook (
function ( )
hooked = true
error ( where .. " did not finish loading" , 0 )
end ,
"" ,
INSTRUCTION_BUDGET
)
local ok , result = pcall ( chunk )
debug . sethook ( )
if not ok then
if hooked then
return nil , where .. " runs too long to be a data literal"
end

return nil , where .. ": " .. tostring ( result )
end
if type ( result ) ~= "table" then
return nil , where .. " must return a table"
end

return result
end

local function stringList ( value , label )
if value == nil then
return { }
end
if type ( value ) ~= "table" then
return nil , label .. " must be a list of strings"
end
local list = { }
for index , entry in ipairs ( value ) do
if type ( entry ) ~= "string" then
return nil , label .. "[" .. index .. "] must be a string"
end
list [ # list + 1 ] = entry
end

return list
end



const DERIVED = { moduleName = true , directory = true }

local function readVariables ( value )
if value == nil then
return { }
end
if type ( value ) ~= "table" then
return nil , "variables must be a table"
end
local variables = { }
for name , declared in pairs ( value ) do
local label = "variables." .. tostring ( name )
if type ( name ) ~= "string" then
return nil , "variables must be keyed by name"
end
if DERIVED [ name ] then
return nil , label .. " is derived from the project name and cannot be declared"
end
if type ( declared ) ~= "table" then
return nil , label .. " must be a table"
end
local entry = declared
for key in pairs ( entry ) do
if key ~= "description"
and key ~= "default"
and key ~= "required"
and key ~= "pattern"
and key ~= "invalid"
then
return nil , label .. "." .. tostring ( key ) .. " is not a variable field"
end
end
if name == "name" and entry . default ~= nil then
return nil , label
.. " cannot have a default, since the project name"
.. " comes from --name or the directory"
end
if entry . pattern ~= nil and type ( entry . pattern ) ~= "string" then
return nil , label .. ".pattern must be a string"
end
variables [
name
] = setmetatable({ description =
entry . description ,  default =
entry . default ,  required =
entry . required ,  pattern =
entry . pattern ,  invalid =
entry . invalid }, template.Variable)

end

return variables
end







function template . manifest ( text , where )
local loaded , loadErr = loadSandboxed ( text , where )
if not loaded then
return nil , loadErr
end
local table_ = loaded
for key in pairs ( table_ ) do
if key ~= "description" and key ~= "variables" and key ~= "raw" and key ~= "after" then
return nil , where .. ": " .. tostring ( key ) .. " is not a template field"
end
end
local variables , variablesErr = readVariables ( table_ . variables )
if not variables then
return nil , where .. ": " .. tostring ( variablesErr )
end
local raw , rawErr = stringList ( table_ . raw , "raw" )
if not raw then
return nil , where .. ": " .. tostring ( rawErr )
end
local after , afterErr = stringList ( table_ . after , "after" )
if not after then
return nil , where .. ": " .. tostring ( afterErr )
end
for _ , step in ipairs ( after ) do
if not STEPS [ step ] then
local known = { }
for name in pairs ( STEPS ) do
known [ # known + 1 ] = name
end
table . sort ( known )

return nil , where .. ": " .. step .. " is not a post-init step" .. "\nAvailable: " .. table . concat (
known ,
", "
)
end
end

return setmetatable({ description =
table_ . description ,  variables =
variables ,  raw =
raw ,  after =
after }, template.Manifest)

end






local function substitute ( text , values , where )
local failure = nil

local parts = { }
local index = 1
while index <= # text do
local at = text : find ( "$${" , index , true )
if not at then
parts [ # parts + 1 ] = text : sub ( index )
break
end
parts [ # parts + 1 ] = text : sub ( index , at - 1 )
parts [ # parts + 1 ] = "\0ESCAPED\0"
index = at + 3
end
local joined = table . concat ( parts )
local expanded = joined : gsub ( "%${([^}]*)}" , function ( name )
if failure then
return ""
end
local replacement = values [ name ]
if replacement == nil then
failure = where .. " uses ${" .. name .. "}, which the template does not declare"
return ""
end

return replacement
end )
if failure then
return nil , failure
end

return ( expanded : gsub ( "%z" .. "ESCAPED" .. "%z" , "${" ) )
end

template . substitute = substitute










function template . values (
manifest ,
name ,
directory ,
supplied
)
local given = supplied or { }
for key in pairs ( given ) do




if key == "name" or DERIVED [ key ] then
return nil , key
.. " is derived from the project name"
.. "\nName the project with --name, or by naming the directory."
end
if not manifest . variables [ key ] then
local declared = { }
for declaredName in pairs ( manifest . variables ) do
if declaredName ~= "name" then
declared [ # declared + 1 ] = declaredName
end
end
table . sort ( declared )
local hint = # declared > 0 and (
"\nDeclared: " .. table . concat ( declared , ", " )
) or "\nThis template declares no variables to set."

return nil , key .. " is not a variable of this template" .. hint
end
end
local values = { name = name , moduleName = ( name : gsub ( "%-" , "_" ) ) , directory = directory , }
for key , declared in pairs ( manifest . variables ) do
if key ~= "name" then
local value = given [ key ] or declared . default
if value == nil then
return nil , "this template needs a value for " .. key .. (
declared . description and ( ": " .. declared . description ) or ""
) .. "\nGive one with --set " .. key .. "=VALUE."
end
values [ key ] = value
end
end
for key , value in pairs ( values ) do
local declared = manifest . variables [ key ]





if key ~= "directory" and value : find ( FORBIDDEN_IN_VALUE ) then
return nil , key .. " may not contain a path separator"
end
if declared and declared . pattern and not value : match ( declared . pattern ) then
return nil , declared . invalid or ( key .. " does not match " .. declared . pattern )
end
end

return values
end



local function readTree ( source )
if source . kind == "builtin" then
local prefix = BUILTIN_PREFIX .. "/" .. tostring ( source . name )
local files = { }
local any = false
for _ , path in ipairs ( bundled . list ( prefix ) ) do
local relative = path : sub ( # prefix + 2 )
local text = bundled . source ( path )
if not text then
return nil , "this compiler carries no " .. path
end
files [ relative ] = text
any = true
end
if not any then
return nil , "this compiler carries no template called " .. tostring ( source . name )
end

return files
end
local root = tostring ( source . path )
if not exists ( join ( root , "template.lua" ) ) then
return nil , root .. " has no template.lua, so it is not a template"
end
local paths , walkErr = walk ( root )
if not paths then
return nil , walkErr
end
local files = { }
for _ , relative in ipairs ( paths ) do
local text , readErr = readFile ( join ( root , relative ) )
if not text then
return nil , tostring ( readErr )
end
files [ relative ] = text
end
files [ "template.lua" ] = readFile ( join ( root , "template.lua" ) )

return files
end

local function componentsAreSafe ( path )
if path : sub ( 1 , 1 ) == "/" or path : match ( "^[A-Za-z]:" ) then
return false , path .. " is absolute, and a template writes only under its destination"
end
for component in path : gmatch ( "[^/]+" ) do
if component == ".." then
return false , path .. " leaves the destination directory"

elseif component == "." then
return false , path .. " has an empty path component"
end
end
if path : find ( "//" , 1 , true ) or path : sub ( - 1 ) == "/" then
return false , path .. " has an empty path component"
end

return true
end

local function destinationIsFree ( destination , policy )
local entries = nupp . io . files . list ( destination )
if not entries then
return true
end
if policy == "absent" then
return false , destination .. " already exists"
else

for _ , entry in ipairs ( entries ) do
if entry . name ~= ".git" then
return false , destination .. " is not empty"
end
end

return true
end
end









function template . plan ( source , destination , opts



)
local asked = opts or { }
destination = normalize ( destination )
local free , freeErr = destinationIsFree ( destination , asked . policy or "emptyOrGitOnly" )
if not free then
return nil , freeErr
end
local tree , treeErr = readTree ( source )
if not tree then
return nil , treeErr
end
local manifestText = tree [ "template.lua" ]
if not manifestText then
return nil , template . describe ( source ) .. " has no template.lua, so it is not a template"
end
local manifest , manifestErr = template . manifest ( manifestText , "template.lua" )
if not manifest then
return nil , manifestErr
end
local name = asked . name or basename ( destination )
local values , valuesErr = template . values ( manifest , name , destination , asked . set )
if not values then
return nil , valuesErr
end
local isRaw = { }
for _ , glob in ipairs ( manifest . raw ) do
isRaw [ # isRaw + 1 ] = syntax . glob ( glob )
end
local files = { }
local sources = { }
for relative in pairs ( tree ) do
if relative ~= "template.lua" then
sources [ # sources + 1 ] = relative
end
end
table . sort ( sources )
local claimed = { }
for _ , relative in ipairs ( sources ) do
local verbatim = false
for _ , matches in ipairs ( isRaw ) do
if matches ( relative ) then
verbatim = true
break
end
end
local output , outputErr = substitute ( relative , values , "the path " .. relative )
if not output then
return nil , outputErr
end
local safe , safeErr = componentsAreSafe ( output )
if not safe then
return nil , safeErr
end
local collision = claimed [ output ]
if collision then
return nil , collision .. " and " .. relative .. " both become " .. output
end
claimed [ output ] = relative
local text = tree [ relative ]
if not verbatim then
local substituted , textErr = substitute ( text , values , relative )
if not substituted then
return nil , textErr
end
text = substituted
end
files [ # files + 1 ] = setmetatable({ source =  relative ,  output =  output ,  text =  text ,  verbatim =  verbatim }, template.File)
end
if # files == 0 then
return nil , template . describe ( source ) .. " contains no files to write"
end
local steps = { }
local dropped = { }
local allowed = source . kind == "remote" and REMOTE_STEPS or STEPS
for _ , step in ipairs ( manifest . after ) do
if allowed [ step ] then
steps [ # steps + 1 ] = step
else
dropped [ # dropped + 1 ] = step
end
end

return setmetatable({ source =
source ,  destination =
destination ,  files =
files ,  values =
values ,  steps =
steps ,  dropped =
dropped }, template.Plan)

end










function template . write ( plan )
local written = { }
for _ , file in ipairs ( plan . files ) do
local path = join ( plan . destination , file . output )
local ok , err = writeFile ( path , file . text )
if not ok then
return nil , tostring ( err )
end
written [ # written + 1 ] = path
end

return written
end













function template . fetch ( source , into )
local url = tostring ( source . url )
local checkout = join ( into , "checkout" )




local clone = { "git" , "-c" , "advice.detachedHead=false" , "clone" , "--quiet" , "--depth" , "1" }
if source . rev then


clone [ # clone + 1 ] = "--branch"
clone [ # clone + 1 ] = source . rev
end
clone [ # clone + 1 ] = url
clone [ # clone + 1 ] = checkout
local code , output = process . capture ( clone )
if code ~= 0 and source . rev then
nupp . io . files . remove ( checkout , true )
local fullCode , fullOutput = process . capture ( {
"git" ,
"-c" ,
"advice.detachedHead=false" ,
"clone" ,
"--quiet" ,
url ,
checkout
} )
if fullCode ~= 0 then
return nil , "cannot clone " .. url .. "\n" .. fullOutput
end



local verifyCode , verified = process . capture (
{ "git" , "rev-parse" , "--verify" , "--quiet" , source . rev .. "^{commit}" } ,
{ cwd = checkout }
)
if verifyCode ~= 0 then
return nil , url .. " has no revision " .. tostring ( source . rev )
end
local outCode , outOutput = process . capture (
{ "git" , "-c" , "advice.detachedHead=false" , "checkout" , "--quiet" , "--detach" , ( verified : gsub ( "%s+$" , "" ) ) } ,
{ cwd = checkout }
)
if outCode ~= 0 then
return nil , "cannot check out " .. tostring ( source . rev ) .. " of " .. url .. "\n" .. outOutput
end
elseif code ~= 0 then
return nil , "cannot clone " .. url .. "\n" .. output
end
local revCode , head = process . capture ( { "git" , "rev-parse" , "HEAD" } , { cwd = checkout } )
if revCode ~= 0 then
return nil , "cannot read the commit " .. url .. " resolved to"
end
source . commit = ( head : gsub ( "%s+$" , "" ) )
source . path = source . subdir and join ( checkout , source . subdir ) or checkout
if not exists ( join ( source . path , "template.lua" ) ) then
return nil , template . describe ( source ) .. " has no template.lua, so it is not a template"
end

return source
end













function template . step ( step , destination , nupp )
if step == "git" then
if exists ( join ( destination , ".git" ) ) then
return true
end

return process . run ( { "git" , "init" , "--quiet" , destination } ) == 0
end
local argv = { nupp , step }

return process . run ( argv , { cwd = destination } ) == 0
end

template . STEPS = STEPS
template . REMOTE_STEPS = REMOTE_STEPS

return template
