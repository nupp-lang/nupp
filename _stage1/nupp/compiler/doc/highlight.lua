_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local __nuppNativeValue;local function __nuppNative()if __nuppNativeValue then return __nuppNativeValue end;local ffi=require("ffi");ffi.cdef[[const char*nuppNativeError(void);typedef struct NuppBytes NuppBytes;const uint8_t*nuppBytesData(const NuppBytes*);size_t nuppBytesLength(const NuppBytes*);void nuppBytesDestroy(NuppBytes*);typedef struct{uint32_t kind;bool readOnly;uint64_t size;double modified;}NuppFileInfo;bool nuppFilesInfo(const uint8_t*,size_t,bool,NuppFileInfo*);NuppBytes*nuppFilesReadLink(const uint8_t*,size_t);bool nuppFilesCreateSymlink(const uint8_t*,size_t,const uint8_t*,size_t,bool);bool nuppFilesSetReadOnly(const uint8_t*,size_t,bool);bool nuppFilesCreateDirectory(const uint8_t*,size_t);bool nuppFilesRemove(const uint8_t*,size_t,bool);bool nuppFilesRename(const uint8_t*,size_t,const uint8_t*,size_t);NuppBytes*nuppFilesList(const uint8_t*,size_t);NuppBytes*nuppFilesCreateTemporary(const uint8_t*,size_t,const uint8_t*,size_t,const uint8_t*,size_t,bool);NuppBytes*nuppFilesCurrentDirectory(void);NuppBytes*nuppFilesUserFolder(uint32_t);typedef struct NuppFile NuppFile;NuppFile*nuppFileOpen(const uint8_t*,size_t,uint32_t);int64_t nuppFileRead(NuppFile*,uint8_t*,size_t);int64_t nuppFileWrite(NuppFile*,const uint8_t*,size_t);int64_t nuppFileSeek(NuppFile*,int64_t,uint32_t);int64_t nuppFileSize(NuppFile*);bool nuppFileFlush(NuppFile*);bool nuppFileClose(NuppFile*);typedef struct NuppRequest NuppRequest;NuppRequest*nuppFsSubmitRead(const uint8_t*,size_t);NuppRequest*nuppFsSubmitWrite(const uint8_t*,size_t,const uint8_t*,size_t,uint32_t);NuppRequest*nuppFsSubmitCopy(const uint8_t*,size_t,const uint8_t*,size_t);int32_t nuppFsStatus(const NuppRequest*);const uint8_t*nuppFsData(const NuppRequest*);size_t nuppFsLength(const NuppRequest*);const char*nuppFsError(const NuppRequest*);bool nuppFsCancel(NuppRequest*);void nuppFsDestroy(NuppRequest*);size_t nuppFsPoll(void);size_t nuppFsWait(uint64_t);size_t nuppFsPending(void);]];local source=debug.getinfo(1,"S").source;local root=source:match("^@(.+)/[^/]+%.lua$")or".";local wanted=os.getenv("NUPP_NATIVE_LIBRARY");local C;if wanted then C=ffi.load(wanted)else local linked=pcall(function()return ffi.C.nuppNativeError end);if linked then C=ffi.C else local library=ffi.os=="Windows"and"/lib/nupp_native.dll"or"/lib/nupp_native";local ok,lib=pcall(ffi.load,root..library);if ok then C=lib else C=ffi.load(root.."/.."..library)end end end;local function errorText()return ffi.string(C.nuppNativeError())end;local function bytes(value,optional)if value==nil then if optional then return nil end;error("nupp: native operation failed: "..errorText(),3)end;local out=ffi.string(C.nuppBytesData(value),tonumber(C.nuppBytesLength(value)));C.nuppBytesDestroy(value);return out end;__nuppNativeValue={ffi=ffi,C=C,error=errorText,bytes=bytes};return __nuppNativeValue end __nuppLazy(__nuppIO,"files",function() local native=__nuppNative();local ffi,C=native.ffi,native.C;ffi.cdef[[NuppBytes*nuppFilesGlob(const uint8_t*,size_t);]];local files={};local record=ffi.new("NuppFileInfo[1]") local KINDS={[1]="file",[2]="directory",[3]="other",[4]="symlink"} local ENTRIES={f="file",d="directory",l="symlink",o="other"} local FOLDERS={home=0,documents=1,downloads=2,desktop=3,pictures=4,music=5,videos=6} local MODES={r=0,w=1,a=2,["r+"]=3,["w+"]=4,["a+"]=5} local ORIGINS={set=0,current=1,["end"]=2} local READ_SIZE=65536 local PENDING,READY=0,1 local SOURCE,PRIORITY="nupp-files",20 local waits={};local suspending local File={};File.__index=File;local Reader={};Reader.__index=Reader;local Writer={};Writer.__index=Writer local function named(value,what,level)if type(value)=="string"then return value end;if type(value)=="table"and value.toString then return value:toString()end;error("nupp: io.files "..what.." must be a path or a string",level)end local function done(answered)if answered then return true end;return false,native.error()end local function answer(handle)if handle==nil then return nil,native.error()end;return native.bytes(handle)end local function described(path,follow,level)local text=named(path,"path",level+1);if not C.nuppFilesInfo(text,#text,follow,record)then return nil end;return record[0]end local function optional(options,field,level)local value=options and options[field];if value==nil then return""end;if type(value)~="string"then error("nupp: io.files temporary "..field.." must be a string",level)end;return value end local function temporary(options,directory,level)local root=options and options.directory and named(options.directory,"temporary directory",level+1)or"";local prefix=optional(options,"prefix",level+1);local suffix=optional(options,"suffix",level+1);return answer(C.nuppFilesCreateTemporary(root,#root,prefix,#prefix,suffix,#suffix,directory))end local function payload(value,what,level)if type(value)=="string"then return value end;if type(value)=="table"and value.getString then return value:getString()end;error("nupp: io.files "..what.." must be bytes or a byte view",level)end local function harvest()local moved=0;local index=#waits;while index>0 do local entry=waits[index];if C.nuppFsStatus(entry.handle)~=PENDING then waits[index]=waits[#waits];waits[#waits]=nil;moved=moved+1;entry.resume(true)end;index=index-1 end;return moved end local function polled()C.nuppFsPoll();return harvest()end local function slept(waitMs)C.nuppFsWait(waitMs);return harvest()end local function forget(entry)for index=1,#waits do if waits[index]==entry then waits[index]=waits[#waits];waits[#waits]=nil;return end end end local function runtime()if suspending==nil then suspending=require("nupp.suspension")end;return suspending end local function await(handle)if C.nuppFsStatus(handle)~=PENDING then return end;local suspension=runtime();suspension.suspend("file transfer",function(resume,context)local entry={handle=handle,resume=resume};context:source(SOURCE,PRIORITY,polled,slept);waits[#waits+1]=entry;if C.nuppFsStatus(handle)~=PENDING then forget(entry);resume(true);return nil end;return function()forget(entry);C.nuppFsCancel(handle)end end)end local function settled(handle)if handle==nil then return nil,native.error()end;await(handle);if C.nuppFsStatus(handle)~=READY then local reason=ffi.string(C.nuppFsError(handle));C.nuppFsDestroy(handle);return nil,reason end;return handle end local function transferred(handle)local done,reason=settled(handle);if not done then return false,reason end;C.nuppFsDestroy(done);return true end local function fetched(handle)local done,reason=settled(handle);if not done then return nil,reason end;local out=ffi.string(C.nuppFsData(done),tonumber(C.nuppFsLength(done)));C.nuppFsDestroy(done);return out end local function whole(value,what,level)if type(value)~="number"or value~=math.floor(value)then error("nupp: io.files "..what.." must be an integer",level)end;return value end local function counted(value,what,level)if whole(value,what,level)<0 then error("nupp: io.files "..what.." must not be negative",level)end;return value end local function live(self,what,level)if self._closed then error("nupp: io.files "..what.." is closed",level)end;return self end function File:isReleased()return self._closed end function File:close()if self._closed then return true end;self._closed=true;local handle=self._handle;self._handle=nil;C.nuppFileClose(handle);return true end function File:size()live(self,"File",2);local size=tonumber(C.nuppFileSize(self._handle));if size<0 then return nil,native.error()end;return size end function File:seek(offset,origin)live(self,"File",2);local whence=ORIGINS[origin or"set"];if whence==nil then error("nupp: io.files has no seek origin named "..tostring(origin),2)end;local at=tonumber(C.nuppFileSeek(self._handle,whole(offset or 0,"seek offset",2),whence));if at<0 then return nil,native.error()end;return at end function File:position()live(self,"File",2);return self:seek(0,"current")end function File:flush()live(self,"File",2);if C.nuppFileFlush(self._handle)then return true end;return false,native.error()end function File:newReader()live(self,"File",2);return setmetatable({_file=self,_scratch=nil,_capacity=0,_closed=false},Reader)end function File:newWriter()live(self,"File",2);return setmetatable({_file=self,_closed=false},Writer)end local function scratch(self,count)if count>self._capacity then local size=self._capacity*2;if size<count then size=count end;if size<READ_SIZE then size=READ_SIZE end;self._scratch=ffi.new("uint8_t[?]",size);self._capacity=size end;return self._scratch end local function usable(self)if self._closed then return nil,"the reader is closed"end;if self._file._closed then return nil,"the file is closed"end;return self._file end function Reader:read(count)local file,reason=usable(self);if not file then return nil,reason end;count=whole(count,"Reader:read count",2);if count<1 then count=1 end;local into=scratch(self,count);local got=tonumber(C.nuppFileRead(file._handle,into,count));if got<0 then return nil,native.error()end;if got==0 then return""end;return ffi.string(into,got)end function Reader:readInto(destination,offset,count)local file,reason=usable(self);if not file then return nil,reason end;offset=counted(offset or 0,"Reader:readInto offset",2);count=counted(count or READ_SIZE,"Reader:readInto count",2);if count==0 then return 0 end;local data=rawget(destination,"_data");local capacity=rawget(destination,"_capacity");if data==nil and capacity==nil then local chunk,why=self:read(count);if chunk==nil then return nil,why end;if #chunk==0 then return 0 end;destination:setString(chunk,offset);return #chunk end;destination:ensureCapacity(offset+count);data=rawget(destination,"_data");local length=rawget(destination,"_length");if offset>length then ffi.fill(data+length,offset-length,0)end;local got=tonumber(C.nuppFileRead(file._handle,data+offset,count));if got<0 then return nil,native.error()end;if offset+got>length then rawset(destination,"_length",offset+got)end;return got end function Reader:transferTo(destination)local file,reason=usable(self);if not file then return nil,reason end;local total=0;while true do local chunk,why=self:read(READ_SIZE);if chunk==nil then return nil,why end;if chunk==""then return total end;local wrote,failure=destination:write(chunk);if not wrote then return nil,failure end;total=total+#chunk end end function Reader:close()self._closed=true;self._scratch=nil;self._capacity=0;return true end local function writable(self)if self._closed then return nil,"the writer is closed"end;if self._file._closed then return nil,"the file is closed"end;return self._file end function Writer:write(bytes)local file,reason=writable(self);if not file then return false,reason end;if type(bytes)~="string"then error("nupp: io.files Writer:write needs a string",2)end;if C.nuppFileWrite(file._handle,bytes,#bytes)<0 then return false,native.error()end;return true end function Writer:writeFrom(source,offset,count)local file,reason=writable(self);if not file then return nil,reason end;local length=source:length();offset=counted(offset or 0,"Writer:writeFrom offset",2);count=counted(count==nil and length-offset or count,"Writer:writeFrom count",2);if offset+count>length then error("nupp: io.files Writer:writeFrom range is past the end",2)end;if count==0 then return 0 end;local data=rawget(source,"_data");if data==nil then local wrote,failure=self:write(source:getString(offset,count));if not wrote then return nil,failure end;return count end;if C.nuppFileWrite(file._handle,data+offset,count)<0 then return nil,native.error()end;return count end function Writer:writeView(source,offset,count)local file,reason=writable(self);if not file then return nil,reason end;local length=source:length();offset=counted(offset or 0,"Writer:writeView offset",2);count=counted(count==nil and length-offset or count,"Writer:writeView count",2);if offset+count>length then error("nupp: io.files Writer:writeView range is past the end",2)end;local wrote,failure=self:write(source:getString():sub(offset+1,offset+count));if not wrote then return nil,failure end;return count end function Writer:flush()local file,reason=writable(self);if not file then return false,reason end;return file:flush()end function Writer:close()self._closed=true;return true end function files.info(path)local found=described(path,true,2);if not found then return nil,native.error()end;return{kind=KINDS[tonumber(found.kind)]or"other",size=tonumber(found.size),modified=found.modified,readOnly=found.readOnly}end function files.exists(path)return described(path,true,2)~=nil end function files.isFile(path)local found=described(path,true,2);return found~=nil and found.kind==1 end function files.isDirectory(path)local found=described(path,true,2);return found~=nil and found.kind==2 end function files.isSymlink(path)local found=described(path,false,2);return found~=nil and found.kind==4 end function files.readLink(path)local text=named(path,"path",2);return answer(C.nuppFilesReadLink(text,#text))end function files.createSymlink(target,link,kind)local to=named(target,"symlink target",2);local at=named(link,"symlink path",2);if kind~=nil and kind~="file"and kind~="directory"then error("nupp: io.files symlink kind must be 'file' or 'directory'",2)end;return done(C.nuppFilesCreateSymlink(to,#to,at,#at,kind=="directory"))end function files.setReadOnly(path,readOnly)local text=named(path,"path",2);return done(C.nuppFilesSetReadOnly(text,#text,readOnly and true or false))end function files.createDirectory(path)local text=named(path,"path",2);return done(C.nuppFilesCreateDirectory(text,#text))end function files.remove(path,recursive)local text=named(path,"path",2);return done(C.nuppFilesRemove(text,#text,recursive and true or false))end function files.rename(from,to)local source=named(from,"source path",2);local destination=named(to,"destination path",2);return done(C.nuppFilesRename(source,#source,destination,#destination))end function files.list(path)local text=named(path,"path",2);local handle=C.nuppFilesList(text,#text);if handle==nil then return nil,native.error()end;local blob=native.bytes(handle);local entries,at={},1;while at<=#blob do local stop=blob:find("\0",at+1,true);entries[#entries+1]={kind=ENTRIES[blob:sub(at,at)]or"other",name=blob:sub(at+1,stop-1)};at=stop+1 end;return entries end function files.glob(pattern)local text=named(pattern,"glob pattern",2);local handle=C.nuppFilesGlob(text,#text);if handle==nil then return nil,native.error()end;local blob=native.bytes(handle);local matches,at={},1;while at<=#blob do local stop=blob:find("\0",at,true);if not stop then matches[#matches+1]=blob:sub(at);break end;matches[#matches+1]=blob:sub(at,stop-1);at=stop+1 end;return matches end local Temporary={};Temporary.__index=Temporary;Temporary.__tostring=function(self)return self._text end function Temporary:toString()return self._text end function Temporary:isReleased()return self._closed end function Temporary:persist(destination)if self._closed then return false,"the temporary path is released"end;local to=named(destination,"destination path",2);local moved,reason=done(C.nuppFilesRename(self._text,#self._text,to,#to));if not moved then return false,reason end;self._closed=true;return true end function Temporary:close()if self._closed then return true end;self._closed=true;return done(C.nuppFilesRemove(self._text,#self._text,self._directory))end File.drop=File.close;Reader.drop=Reader.close;Writer.drop=Writer.close;Temporary.drop=Temporary.close function files.createTemporaryFile(options)local text,reason=temporary(options,false,2);if not text then return nil,reason end;return setmetatable({_text=text,_directory=false,_closed=false},Temporary)end function files.createTemporaryDirectory(options)local text,reason=temporary(options,true,2);if not text then return nil,reason end;return setmetatable({_text=text,_directory=true,_closed=false},Temporary)end function files.read(path)local text=named(path,"path",2);return fetched(C.nuppFsSubmitRead(text,#text))end function files.write(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,0))end function files.append(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,1))end function files.writeAtomic(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,2))end function files.copy(from,to)local source=named(from,"source path",2);local destination=named(to,"destination path",2);return transferred(C.nuppFsSubmitCopy(source,#source,destination,#destination))end function files.pendingTransfers()return tonumber(C.nuppFsPending())end function files.open(path,mode)local text=named(path,"path",2);local selected=MODES[mode or"r"];if selected==nil then error("nupp: io.files has no mode named "..tostring(mode),2)end;local handle=C.nuppFileOpen(text,#text,selected);if handle==nil then return nil,native.error()end;return setmetatable({_handle=handle,_closed=false},File)end function files.lines(path)local file,reason=files.open(path,"r");if not file then return nil,reason end;local reader=file:newReader();local held,finished="",false;local function trimmed(line)if line:sub(-1)=="\r"then return line:sub(1,-2)end;return line end;return function()if finished then return nil end;while true do local stop=held:find("\n",1,true);if stop then local line=held:sub(1,stop-1);held=held:sub(stop+1);return trimmed(line)end;local chunk=reader:read(READ_SIZE);if chunk==nil or chunk==""then finished=true;file:close();if #held>0 then local line=held;held="";return trimmed(line)end;return nil end;held=held..chunk end end end function files.currentDirectory()return answer(C.nuppFilesCurrentDirectory())end function files.userFolder(which)local index=FOLDERS[which];if index==nil then error("nupp: io.files has no user folder named "..tostring(which),2)end;return answer(C.nuppFilesUserFolder(index))end return files end);




























local lexer = require ( "nupp.compiler.lexer" )
local parser = require ( "nupp.compiler.parser" )
local semantic = require ( "nupp.compiler.lsp.semantic" )
local types = require ( "nupp.compiler.types" )
local stringsMod = require ( "nupp.compiler.doc.strings" )
local filesMod = require ( "nupp.compiler.doc.files" )

local htmlEscape = stringsMod . htmlEscape
local join , dirname , exists = filesMod . join , filesMod . dirname , filesMod . exists

local highlight = { }





local TYPE_NAMES = { borrowed = true , ctype = true , metatable = true , owned = true , pinned = true , }
for name in pairs ( types . builtins ) do
TYPE_NAMES [ name ] = true
end

local CONTEXTUAL_KEYWORDS = {
[ "as" ] = true ,
associated = true ,
borrows = true ,
cdef = true ,
comptime = true ,
constructor = true ,
continue = true ,
exclusive = true ,
from = true ,
takes = true ,
const = true ,
global = true ,
interface = true ,
handle = true ,
[ "is" ] = true ,
keyof = true ,
satisfies = true ,
[ "new" ] = true ,
nosuspend = true ,
out = true ,
preserves = true ,
record = true ,
metamethod = true ,
scoped = true ,
[ "sealed" ] = true ,
suspension = true ,
unpackof = true ,
where = true ,
with = true ,
writekeyof = true ,
writeof = true ,
readonly = true ,
releases = true ,
retains = true ,
resumes = true ,
struct = true ,
type = true ,
unsafe = true ,
writeonly = true ,
yields = true ,
}

local LITERAL_KEYWORDS = { [ "false" ] = true , [ "nil" ] = true , [ "true" ] = true }




local DIRECTIVE_KEYWORDS = { comptime = true , nosuspend = true }

local PUNCTUATION = {
[ "(" ] = true ,
[ ")" ] = true ,
[ "[" ] = true ,
[ "]" ] = true ,
[ "{" ] = true ,
[ "}" ] = true ,
[ "," ] = true ,
[ ";" ] = true ,
[ ":" ] = true ,
[ "." ] = true ,
[ "@" ] = true ,
}

local TYPE_DECLARATIONS = { interface = true , record = true , struct = true , type = true , }

local function qualifiedName ( tokens , index )
local name = tokens [ index ] . text
local cursor = index - 1
while cursor > 1 and tokens [ cursor ] . text == "." and tokens [ cursor - 1 ] . kind == "name" do
name = tokens [ cursor - 1 ] . text .. "." .. name
cursor = cursor - 2
end

return name
end

local SYNTAX_STYLES = {
decorator = "meta" ,
keyword = "keyword" ,
type = "type" ,
struct = "type" ,
interface = "type" ,
typeParameter = "type" ,
[ "function" ] = "function" ,
method = "function" ,
property = "property" ,
parameter = "variable" ,
variable = "variable" ,
}

local function tokenStyle ( tokens , index , syntaxKinds )
local token = tokens [ index ]
local previous = tokens [ index - 1 ]
local following = tokens [ index + 1 ]
if token . kind == "name" then
local syntaxKind = syntaxKinds [ token ]




if syntaxKind == "keyword" and DIRECTIVE_KEYWORDS [ token . text ] then
return "meta"
end
local syntaxStyle = SYNTAX_STYLES [ syntaxKind ]
if syntaxStyle then
return syntaxStyle
end
if DIRECTIVE_KEYWORDS [ token . text ] then
return "meta"
end
if CONTEXTUAL_KEYWORDS [ token . text ] then
return "keyword"
end
if TYPE_NAMES [ token . text ] or token . text : match ( "^%u" ) then
return "type"
end
if previous and previous . text == "@" then
return "meta"
end
if previous and previous . kind == "function" then
return "function"
end
if previous and previous . text == "metamethod" then
return "function"
end
if previous and TYPE_DECLARATIONS [ previous . text ] then
return "type"
end
if following and following . text == "(" then
return "function"
end
if previous and ( previous . text == "." or previous . text == ":" ) then
return "property"
end
return "variable"
elseif lexer . KEYWORDS [ token . kind ] then
return LITERAL_KEYWORDS [ token . text ] and "boolean" or "keyword"
elseif token . kind == "string"
or token . kind == "istringOpen"
or token . kind == "istringMid"
or token . kind == "istringClose"
then
return "string"
elseif token . kind == "number" then
return "number"
elseif PUNCTUATION [ token . text ] then
return token . text == "@" and "meta" or "punctuation"
end

return "operator"
end

local function tokenClasses ( style , text )
if style == "type" then
return "token class-name nuppdoc-token-type"

elseif style == "meta" then
return "token directive nuppdoc-token-meta"

elseif style == "keyword" then
return "token keyword keyword-" .. text : gsub ( "[^%w%-]" , "-" ) .. " nuppdoc-token-keyword"
end

return "token " .. style .. " nuppdoc-token-" .. style
end

local function declarationName ( tokens , index )
local previous = tokens [ index - 1 ]
return previous and (
previous . kind == "function" or previous . text == "metamethod" or TYPE_DECLARATIONS [ previous . text ]
)
end




local function lineWriter ( source )
if source == "" then
return {
lines = { } ,
append = function ( )
end
}
end
local lines = { "" }
local function append ( text , class , href )
local start = 1
while true do
local finish = text : find ( "\n" , start , true )
local piece = finish and text : sub ( start , finish - 1 ) or text : sub ( start )
local rendered = htmlEscape ( piece )
if class and piece ~= "" then
rendered = '<span class="' .. class .. '">' .. rendered .. "</span>"
if href then
rendered = '<a class="nuppdoc-code-link nuppdoc-code-link-'
.. href . style
.. '" href="'
.. htmlEscape (
href . url
) .. '">' .. rendered .. "</a>"
end
end
lines [ # lines ] = lines [ # lines ] .. rendered
if not finish then
break
end
lines [ # lines + 1 ] = ""
start = finish + 1
end
end

return { lines = lines , append = append }
end




local function containerMemberUrls ( parsed , memberLinks )
local urls = { }
if not memberLinks then
return urls
end
for _ , block in ipairs ( parsed . root . blocks or { } ) do
for _ , outer in ipairs ( block . stats or { } ) do
local declaration = outer
while declaration . kind == "pragmaStmt" and declaration . stat do
declaration = declaration . stat
end
if declaration . kind == "recordDecl" then
for _ , entry in ipairs ( declaration . entries or { } ) do
local name = entry . name
local url = name and memberLinks [ name . text ]
if url then
urls [ name ] = url
end
end
end
end
end

return urls
end

local function highlightNuppLines ( source , links , memberLinks )
local out = lineWriter ( source )
local parsed = parser . parse ( source , "documentation-code-block.nupp" )
local tokens = parsed . tokens
local syntaxKinds = semantic . syntaxKinds ( parsed )
local memberUrls = containerMemberUrls ( parsed , memberLinks )
for index , token in ipairs ( tokens ) do
for index = 1 , token . triviaCount do
local kind = lexer . triviaKind ( token , index )
local text = lexer . triviaText ( token , index )
if kind == "comment" or kind == "hashbang" then
out . append ( text , "token comment nuppdoc-token-comment" )
else
out . append ( text )
end
end
if token . kind ~= "eof" then
local style = tokenStyle ( tokens , index , syntaxKinds )
local url = memberUrls [ token ]
if not url and links and token . kind == "name" and not declarationName ( tokens , index ) then
url = links [ qualifiedName ( tokens , index ) ] or links [ token . text ]
end
out . append ( token . text , tokenClasses ( style , token . text ) , url and { url = url , style = style } or nil )
end
end
if source : sub ( - 1 ) == "\n" then
out . lines [ # out . lines ] = nil
end

return out . lines
end

local function highlightNupp (
source ,
links ,
memberLinks
)
return table . concat ( highlightNuppLines ( source , links , memberLinks ) , "\n" )
end

local SCINTILLUA_ALIASES = {
[ "c++" ] = "cpp" ,
html = "hypertext" ,
js = "javascript" ,
md = "markdown" ,
sh = "bash" ,
shell = "bash" ,
ts = "typescript" ,
}
local scintilluaDirectory , scintilluaSearchPath , scintilluaLibrary = nil , nil , nil
local scintilluaBundled = false
local scintilluaLexers = { }





local BUNDLED_MODULE = "scintillua.lexers."
local BUNDLED_DIRECTORY = "@bundled/scintillua/lexers"

local function bundledName ( path )
if type ( path ) ~= "string" then
return nil
end
local prefix = BUNDLED_DIRECTORY .. "/"
if path : sub ( 1 , # prefix ) ~= prefix then
return nil
end

return path : sub ( # prefix + 1 ) : match ( "^([%w_+-]+)%.lua$" )
end







local function bundledLoadfile ( path , mode , env )
local chunk , err
local name = bundledName ( path )
if name then
chunk = package . preload [ BUNDLED_MODULE .. name ]


if not chunk then
return nil , "cannot open " .. path
end
else
chunk , err = loadfile ( path )
if not chunk then
return nil , err
end
end


if env then
setfenv ( chunk , env )
end

return chunk
end





local LEXER_MODULE = "scintillua/lexers/lexer"

local function installedLexers ( )
for template in package . path : gmatch ( "[^;]+" ) do
local candidate = template : gsub ( "%?" , LEXER_MODULE )
if exists ( candidate ) then
return dirname ( candidate )
end
end

return nil
end

local function configureScintillua ( root , settings )




local installed = installedLexers ( )
if installed and not exists ( join ( installed , "lexer.lua" ) ) then
installed = nil
end
local bundled = not installed and package . preload [ BUNDLED_MODULE .. "lexer" ] ~= nil
if not installed and not bundled then
scintilluaDirectory , scintilluaSearchPath , scintilluaLibrary , scintilluaLexers = nil , nil , nil , { }
scintilluaBundled = false
return
end
local base = installed or BUNDLED_DIRECTORY
local searchPath = base
local lexerDir = settings and settings . lexers
if lexerDir then
local custom = join ( root , lexerDir )


if nupp . io . files . isDirectory ( custom ) then
searchPath = custom .. ";" .. base
end
end
if scintilluaSearchPath ~= searchPath then
scintilluaDirectory , scintilluaSearchPath , scintilluaLibrary , scintilluaLexers = base , searchPath , nil , { }
end
scintilluaBundled = bundled
end

local function loadScintillua ( language )
if not scintilluaDirectory then
return nil
end
language = tostring ( language or "" ) : lower ( )
language = SCINTILLUA_ALIASES [ language ] or language
if not language : match ( "^[%w_+-]+$" ) then
return nil
end
if scintilluaLexers [ language ] ~= nil then
return scintilluaLexers [ language ] or nil
end
if not scintilluaLibrary then
local chunk
if scintilluaBundled then
chunk = package . preload [ BUNDLED_MODULE .. "lexer" ]




if chunk then
setfenv ( chunk , setmetatable ( { loadfile = bundledLoadfile } , { __index = _G } ) )
end
else
chunk = loadfile ( join ( scintilluaDirectory , "lexer.lua" ) )
end
if not chunk then
return nil
end
local ok , library = pcall ( chunk )
if not ok or type ( library ) ~= "table" then
return nil
end
library . property = setmetatable ( { [ "scintillua.lexers" ] = scintilluaSearchPath , } , {
__index = function ( )
return ""
end ,
__newindex = function ( t , key , value )
rawset ( t , key , tostring ( value ) )
end ,
} )
scintilluaLibrary = library
end
local ok , loaded = pcall ( scintilluaLibrary . load , language )
scintilluaLexers [ language ] = ok and loaded or false

return ok and loaded or nil
end

local function scintilluaStyle ( tag )
local base = tostring ( tag or "default" ) : match ( "^[^%.]+" )
if base == "whitespace" or base == "default" then
return nil
end
if base == "comment" then
return "comment"

elseif base == "keyword" then
return "keyword"
end
if base == "string" or base == "regex" then
return "string"
end
if base == "number" then
return "number"
end
if base == "function" or base == "label" then
return "function"
end
if base == "type" or base == "class" then
return "type"
end
if base == "preprocessor" or base == "annotation" then
return "meta"
end
if base == "operator" then
return "operator"

elseif base == "constant" then
return "boolean"

elseif base == "property" then
return "property"
end
if base == "identifier" or base == "variable" then
return "variable"
end

return nil
end

local function highlightScintilluaLines ( source , language )
local loaded = loadScintillua ( language )
if not loaded then
return nil
end
local ok , tags = pcall ( loaded . lex , loaded , source )
if not ok or type ( tags ) ~= "table" then
return nil
end
local out , start = lineWriter ( source ) , 1
for index = 1 , # tags , 2 do
local finish = tonumber ( tags [ index + 1 ] )
if not finish then
return nil
end
local text = source : sub ( start , finish - 1 )
local style = scintilluaStyle ( tags [ index ] )
if style then
out . append ( text , tokenClasses ( style , text ) )
else
out . append ( text )
end
start = finish
end
if start <= # source then
out . append ( source : sub ( start ) )
end
if source : sub ( - 1 ) == "\n" then
out . lines [ # out . lines ] = nil
end

return out . lines
end




local function highlightScintillua ( source , language )
local lines = highlightScintilluaLines ( source , language )
return lines and table . concat ( lines , "\n" ) or nil
end

local function codeLines ( source , language , links )
if language == "nupp" then
return highlightNuppLines ( source , links )
end
local highlighted = highlightScintilluaLines ( source , language )
if highlighted then
return highlighted
end
local out = lineWriter ( source )
out . append ( source )
if source : sub ( - 1 ) == "\n" then
out . lines [ # out . lines ] = nil
end

return out . lines
end

local function codeHtml ( source , language , links )
return table . concat ( codeLines ( source , language , links ) , "\n" )
end

highlight . nuppSource = highlightNupp
highlight . scintilluaSource = highlightScintillua
highlight . codeHtml = codeHtml
highlight . codeLines = codeLines
highlight . configureScintillua = configureScintillua

return highlight
