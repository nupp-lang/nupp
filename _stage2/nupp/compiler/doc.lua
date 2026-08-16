_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppLoadJSON()local source=require("cjson");local aliases={EMPTY_ARRAY="empty_array",ARRAY_MT="array_mt",EMPTY_ARRAY_MT="empty_array_mt",encodeEmptyTableAsObject="encode_empty_table_as_object",decodeArrayWithArrayMt="decode_array_with_array_mt",encodeSparseArray="encode_sparse_array",encodeMaxDepth="encode_max_depth",decodeMaxDepth="decode_max_depth",encodeNumberPrecision="encode_number_precision",encodeKeepBuffer="encode_keep_buffer",encodeInvalidNumbers="encode_invalid_numbers",decodeInvalidNumbers="decode_invalid_numbers",encodeEscapeForwardSlash="encode_escape_forward_slash"};local function adopt(target,json)target.encodeJSON=json.encode;target.decodeJSON=json.decode;target.NULL=json.null;for public,name in pairs(aliases)do target[public]=json[name]end;return target end;local json=adopt({},source);json.newJSON=function()return adopt({},source.new())end;return json end __nuppLazy(__nuppData,"json",__nuppLoadJSON) local __nuppNativeValue;local function __nuppNative()if __nuppNativeValue then return __nuppNativeValue end;local ffi=require("ffi");ffi.cdef[[const char*nuppNativeError(void);typedef struct NuppBytes NuppBytes;const uint8_t*nuppBytesData(const NuppBytes*);size_t nuppBytesLength(const NuppBytes*);void nuppBytesDestroy(NuppBytes*);typedef struct{uint32_t kind;bool readOnly;uint64_t size;double modified;}NuppFileInfo;bool nuppFilesInfo(const uint8_t*,size_t,bool,NuppFileInfo*);NuppBytes*nuppFilesReadLink(const uint8_t*,size_t);bool nuppFilesCreateSymlink(const uint8_t*,size_t,const uint8_t*,size_t,bool);bool nuppFilesSetReadOnly(const uint8_t*,size_t,bool);bool nuppFilesCreateDirectory(const uint8_t*,size_t);bool nuppFilesRemove(const uint8_t*,size_t,bool);bool nuppFilesRename(const uint8_t*,size_t,const uint8_t*,size_t);NuppBytes*nuppFilesList(const uint8_t*,size_t);NuppBytes*nuppFilesCreateTemporary(const uint8_t*,size_t,const uint8_t*,size_t,const uint8_t*,size_t,bool);NuppBytes*nuppFilesCurrentDirectory(void);NuppBytes*nuppFilesUserFolder(uint32_t);typedef struct NuppFile NuppFile;NuppFile*nuppFileOpen(const uint8_t*,size_t,uint32_t);int64_t nuppFileRead(NuppFile*,uint8_t*,size_t);int64_t nuppFileWrite(NuppFile*,const uint8_t*,size_t);int64_t nuppFileSeek(NuppFile*,int64_t,uint32_t);int64_t nuppFileSize(NuppFile*);bool nuppFileFlush(NuppFile*);bool nuppFileClose(NuppFile*);typedef struct NuppRequest NuppRequest;NuppRequest*nuppFsSubmitRead(const uint8_t*,size_t);NuppRequest*nuppFsSubmitWrite(const uint8_t*,size_t,const uint8_t*,size_t,uint32_t);NuppRequest*nuppFsSubmitCopy(const uint8_t*,size_t,const uint8_t*,size_t);int32_t nuppFsStatus(const NuppRequest*);const uint8_t*nuppFsData(const NuppRequest*);size_t nuppFsLength(const NuppRequest*);const char*nuppFsError(const NuppRequest*);bool nuppFsCancel(NuppRequest*);void nuppFsDestroy(NuppRequest*);size_t nuppFsPoll(void);size_t nuppFsWait(uint64_t);size_t nuppFsPending(void);]];local source=debug.getinfo(1,"S").source;local root=source:match("^@(.+)/[^/]+%.lua$")or".";local wanted=os.getenv("NUPP_NATIVE_LIBRARY");local C;if wanted then C=ffi.load(wanted)else local linked=pcall(function()return ffi.C.nuppNativeError end);if linked then C=ffi.C else local library=ffi.os=="Windows"and"/lib/nupp_native.dll"or"/lib/nupp_native";local ok,lib=pcall(ffi.load,root..library);if ok then C=lib else C=ffi.load(root.."/.."..library)end end end;local function errorText()return ffi.string(C.nuppNativeError())end;local function bytes(value,optional)if value==nil then if optional then return nil end;error("nupp: native operation failed: "..errorText(),3)end;local out=ffi.string(C.nuppBytesData(value),tonumber(C.nuppBytesLength(value)));C.nuppBytesDestroy(value);return out end;__nuppNativeValue={ffi=ffi,C=C,error=errorText,bytes=bytes};return __nuppNativeValue end __nuppLazy(__nuppIO,"files",function() local native=__nuppNative();local ffi,C=native.ffi,native.C;ffi.cdef[[NuppBytes*nuppFilesGlob(const uint8_t*,size_t);]];local files={};local record=ffi.new("NuppFileInfo[1]") local KINDS={[1]="file",[2]="directory",[3]="other",[4]="symlink"} local ENTRIES={f="file",d="directory",l="symlink",o="other"} local FOLDERS={home=0,documents=1,downloads=2,desktop=3,pictures=4,music=5,videos=6} local MODES={r=0,w=1,a=2,["r+"]=3,["w+"]=4,["a+"]=5} local ORIGINS={set=0,current=1,["end"]=2} local READ_SIZE=65536 local PENDING,READY=0,1 local SOURCE,PRIORITY="nupp-files",20 local waits={};local suspending local File={};File.__index=File;local Reader={};Reader.__index=Reader;local Writer={};Writer.__index=Writer local function named(value,what,level)if type(value)=="string"then return value end;if type(value)=="table"and value.toString then return value:toString()end;error("nupp: io.files "..what.." must be a path or a string",level)end local function done(answered)if answered then return true end;return false,native.error()end local function answer(handle)if handle==nil then return nil,native.error()end;return native.bytes(handle)end local function described(path,follow,level)local text=named(path,"path",level+1);if not C.nuppFilesInfo(text,#text,follow,record)then return nil end;return record[0]end local function optional(options,field,level)local value=options and options[field];if value==nil then return""end;if type(value)~="string"then error("nupp: io.files temporary "..field.." must be a string",level)end;return value end local function temporary(options,directory,level)local root=options and options.directory and named(options.directory,"temporary directory",level+1)or"";local prefix=optional(options,"prefix",level+1);local suffix=optional(options,"suffix",level+1);return answer(C.nuppFilesCreateTemporary(root,#root,prefix,#prefix,suffix,#suffix,directory))end local function payload(value,what,level)if type(value)=="string"then return value end;if type(value)=="table"and value.getString then return value:getString()end;error("nupp: io.files "..what.." must be bytes or a byte view",level)end local function harvest()local moved=0;local index=#waits;while index>0 do local entry=waits[index];if C.nuppFsStatus(entry.handle)~=PENDING then waits[index]=waits[#waits];waits[#waits]=nil;moved=moved+1;entry.resume(true)end;index=index-1 end;return moved end local function polled()C.nuppFsPoll();return harvest()end local function slept(waitMs)C.nuppFsWait(waitMs);return harvest()end local function forget(entry)for index=1,#waits do if waits[index]==entry then waits[index]=waits[#waits];waits[#waits]=nil;return end end end local function runtime()if suspending==nil then suspending=require("nupp.suspension")end;return suspending end local function await(handle)if C.nuppFsStatus(handle)~=PENDING then return end;local suspension=runtime();suspension.suspend("file transfer",function(resume,context)local entry={handle=handle,resume=resume};context:source(SOURCE,PRIORITY,polled,slept);waits[#waits+1]=entry;if C.nuppFsStatus(handle)~=PENDING then forget(entry);resume(true);return nil end;return function()forget(entry);C.nuppFsCancel(handle)end end)end local function settled(handle)if handle==nil then return nil,native.error()end;await(handle);if C.nuppFsStatus(handle)~=READY then local reason=ffi.string(C.nuppFsError(handle));C.nuppFsDestroy(handle);return nil,reason end;return handle end local function transferred(handle)local done,reason=settled(handle);if not done then return false,reason end;C.nuppFsDestroy(done);return true end local function fetched(handle)local done,reason=settled(handle);if not done then return nil,reason end;local out=ffi.string(C.nuppFsData(done),tonumber(C.nuppFsLength(done)));C.nuppFsDestroy(done);return out end local function whole(value,what,level)if type(value)~="number"or value~=math.floor(value)then error("nupp: io.files "..what.." must be an integer",level)end;return value end local function counted(value,what,level)if whole(value,what,level)<0 then error("nupp: io.files "..what.." must not be negative",level)end;return value end local function live(self,what,level)if self._closed then error("nupp: io.files "..what.." is closed",level)end;return self end function File:isReleased()return self._closed end function File:close()if self._closed then return true end;self._closed=true;local handle=self._handle;self._handle=nil;C.nuppFileClose(handle);return true end function File:size()live(self,"File",2);local size=tonumber(C.nuppFileSize(self._handle));if size<0 then return nil,native.error()end;return size end function File:seek(offset,origin)live(self,"File",2);local whence=ORIGINS[origin or"set"];if whence==nil then error("nupp: io.files has no seek origin named "..tostring(origin),2)end;local at=tonumber(C.nuppFileSeek(self._handle,whole(offset or 0,"seek offset",2),whence));if at<0 then return nil,native.error()end;return at end function File:position()live(self,"File",2);return self:seek(0,"current")end function File:flush()live(self,"File",2);if C.nuppFileFlush(self._handle)then return true end;return false,native.error()end function File:newReader()live(self,"File",2);return setmetatable({_file=self,_scratch=nil,_capacity=0,_closed=false},Reader)end function File:newWriter()live(self,"File",2);return setmetatable({_file=self,_closed=false},Writer)end local function scratch(self,count)if count>self._capacity then local size=self._capacity*2;if size<count then size=count end;if size<READ_SIZE then size=READ_SIZE end;self._scratch=ffi.new("uint8_t[?]",size);self._capacity=size end;return self._scratch end local function usable(self)if self._closed then return nil,"the reader is closed"end;if self._file._closed then return nil,"the file is closed"end;return self._file end function Reader:read(count)local file,reason=usable(self);if not file then return nil,reason end;count=whole(count,"Reader:read count",2);if count<1 then count=1 end;local into=scratch(self,count);local got=tonumber(C.nuppFileRead(file._handle,into,count));if got<0 then return nil,native.error()end;if got==0 then return""end;return ffi.string(into,got)end function Reader:readInto(destination,offset,count)local file,reason=usable(self);if not file then return nil,reason end;offset=counted(offset or 0,"Reader:readInto offset",2);count=counted(count or READ_SIZE,"Reader:readInto count",2);if count==0 then return 0 end;local data=rawget(destination,"_data");local capacity=rawget(destination,"_capacity");if data==nil and capacity==nil then local chunk,why=self:read(count);if chunk==nil then return nil,why end;if #chunk==0 then return 0 end;destination:setString(chunk,offset);return #chunk end;destination:ensureCapacity(offset+count);data=rawget(destination,"_data");local length=rawget(destination,"_length");if offset>length then ffi.fill(data+length,offset-length,0)end;local got=tonumber(C.nuppFileRead(file._handle,data+offset,count));if got<0 then return nil,native.error()end;if offset+got>length then rawset(destination,"_length",offset+got)end;return got end function Reader:transferTo(destination)local file,reason=usable(self);if not file then return nil,reason end;local total=0;while true do local chunk,why=self:read(READ_SIZE);if chunk==nil then return nil,why end;if chunk==""then return total end;local wrote,failure=destination:write(chunk);if not wrote then return nil,failure end;total=total+#chunk end end function Reader:close()self._closed=true;self._scratch=nil;self._capacity=0;return true end local function writable(self)if self._closed then return nil,"the writer is closed"end;if self._file._closed then return nil,"the file is closed"end;return self._file end function Writer:write(bytes)local file,reason=writable(self);if not file then return false,reason end;if type(bytes)~="string"then error("nupp: io.files Writer:write needs a string",2)end;if C.nuppFileWrite(file._handle,bytes,#bytes)<0 then return false,native.error()end;return true end function Writer:writeFrom(source,offset,count)local file,reason=writable(self);if not file then return nil,reason end;local length=source:length();offset=counted(offset or 0,"Writer:writeFrom offset",2);count=counted(count==nil and length-offset or count,"Writer:writeFrom count",2);if offset+count>length then error("nupp: io.files Writer:writeFrom range is past the end",2)end;if count==0 then return 0 end;local data=rawget(source,"_data");if data==nil then local wrote,failure=self:write(source:getString(offset,count));if not wrote then return nil,failure end;return count end;if C.nuppFileWrite(file._handle,data+offset,count)<0 then return nil,native.error()end;return count end function Writer:writeView(source,offset,count)local file,reason=writable(self);if not file then return nil,reason end;local length=source:length();offset=counted(offset or 0,"Writer:writeView offset",2);count=counted(count==nil and length-offset or count,"Writer:writeView count",2);if offset+count>length then error("nupp: io.files Writer:writeView range is past the end",2)end;local wrote,failure=self:write(source:getString():sub(offset+1,offset+count));if not wrote then return nil,failure end;return count end function Writer:flush()local file,reason=writable(self);if not file then return false,reason end;return file:flush()end function Writer:close()self._closed=true;return true end function files.info(path)local found=described(path,true,2);if not found then return nil,native.error()end;return{kind=KINDS[tonumber(found.kind)]or"other",size=tonumber(found.size),modified=found.modified,readOnly=found.readOnly}end function files.exists(path)return described(path,true,2)~=nil end function files.isFile(path)local found=described(path,true,2);return found~=nil and found.kind==1 end function files.isDirectory(path)local found=described(path,true,2);return found~=nil and found.kind==2 end function files.isSymlink(path)local found=described(path,false,2);return found~=nil and found.kind==4 end function files.readLink(path)local text=named(path,"path",2);return answer(C.nuppFilesReadLink(text,#text))end function files.createSymlink(target,link,kind)local to=named(target,"symlink target",2);local at=named(link,"symlink path",2);if kind~=nil and kind~="file"and kind~="directory"then error("nupp: io.files symlink kind must be 'file' or 'directory'",2)end;return done(C.nuppFilesCreateSymlink(to,#to,at,#at,kind=="directory"))end function files.setReadOnly(path,readOnly)local text=named(path,"path",2);return done(C.nuppFilesSetReadOnly(text,#text,readOnly and true or false))end function files.createDirectory(path)local text=named(path,"path",2);return done(C.nuppFilesCreateDirectory(text,#text))end function files.remove(path,recursive)local text=named(path,"path",2);return done(C.nuppFilesRemove(text,#text,recursive and true or false))end function files.rename(from,to)local source=named(from,"source path",2);local destination=named(to,"destination path",2);return done(C.nuppFilesRename(source,#source,destination,#destination))end function files.list(path)local text=named(path,"path",2);local handle=C.nuppFilesList(text,#text);if handle==nil then return nil,native.error()end;local blob=native.bytes(handle);local entries,at={},1;while at<=#blob do local stop=blob:find("\0",at+1,true);entries[#entries+1]={kind=ENTRIES[blob:sub(at,at)]or"other",name=blob:sub(at+1,stop-1)};at=stop+1 end;return entries end function files.glob(pattern)local text=named(pattern,"glob pattern",2);local handle=C.nuppFilesGlob(text,#text);if handle==nil then return nil,native.error()end;local blob=native.bytes(handle);local matches,at={},1;while at<=#blob do local stop=blob:find("\0",at,true);if not stop then matches[#matches+1]=blob:sub(at);break end;matches[#matches+1]=blob:sub(at,stop-1);at=stop+1 end;return matches end local Temporary={};Temporary.__index=Temporary;Temporary.__tostring=function(self)return self._text end function Temporary:toString()return self._text end function Temporary:isReleased()return self._closed end function Temporary:persist(destination)if self._closed then return false,"the temporary path is released"end;local to=named(destination,"destination path",2);local moved,reason=done(C.nuppFilesRename(self._text,#self._text,to,#to));if not moved then return false,reason end;self._closed=true;return true end function Temporary:close()if self._closed then return true end;self._closed=true;return done(C.nuppFilesRemove(self._text,#self._text,self._directory))end File.drop=File.close;Reader.drop=Reader.close;Writer.drop=Writer.close;Temporary.drop=Temporary.close function files.createTemporaryFile(options)local text,reason=temporary(options,false,2);if not text then return nil,reason end;return setmetatable({_text=text,_directory=false,_closed=false},Temporary)end function files.createTemporaryDirectory(options)local text,reason=temporary(options,true,2);if not text then return nil,reason end;return setmetatable({_text=text,_directory=true,_closed=false},Temporary)end function files.read(path)local text=named(path,"path",2);return fetched(C.nuppFsSubmitRead(text,#text))end function files.write(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,0))end function files.append(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,1))end function files.writeAtomic(path,bytes)local text=named(path,"path",2);local out=payload(bytes,"contents",2);return transferred(C.nuppFsSubmitWrite(text,#text,out,#out,2))end function files.copy(from,to)local source=named(from,"source path",2);local destination=named(to,"destination path",2);return transferred(C.nuppFsSubmitCopy(source,#source,destination,#destination))end function files.pendingTransfers()return tonumber(C.nuppFsPending())end function files.open(path,mode)local text=named(path,"path",2);local selected=MODES[mode or"r"];if selected==nil then error("nupp: io.files has no mode named "..tostring(mode),2)end;local handle=C.nuppFileOpen(text,#text,selected);if handle==nil then return nil,native.error()end;return setmetatable({_handle=handle,_closed=false},File)end function files.lines(path)local file,reason=files.open(path,"r");if not file then return nil,reason end;local reader=file:newReader();local held,finished="",false;local function trimmed(line)if line:sub(-1)=="\r"then return line:sub(1,-2)end;return line end;return function()if finished then return nil end;while true do local stop=held:find("\n",1,true);if stop then local line=held:sub(1,stop-1);held=held:sub(stop+1);return trimmed(line)end;local chunk=reader:read(READ_SIZE);if chunk==nil or chunk==""then finished=true;file:close();if #held>0 then local line=held;held="";return trimmed(line)end;return nil end;held=held..chunk end end end function files.currentDirectory()return answer(C.nuppFilesCurrentDirectory())end function files.userFolder(which)local index=FOLDERS[which];if index==nil then error("nupp: io.files has no user folder named "..tostring(which),2)end;return answer(C.nuppFilesUserFolder(index))end return files end);










local stringsMod = require ( "nupp.compiler.doc.strings" )
local filesMod = require ( "nupp.compiler.doc.files" )
local extractMod = require ( "nupp.compiler.doc.extract" )
local markdownMod = require ( "nupp.compiler.doc.markdown" )
local highlightMod = require ( "nupp.compiler.doc.highlight" )
local htmlMod = require ( "nupp.compiler.doc.html" )
local assetsMod = require ( "nupp.compiler.doc.assets" )
local urlsMod = require ( "nupp.compiler.doc.urls" )
local apiMod = require ( "nupp.compiler.doc.api" )
local pageMod = require ( "nupp.compiler.doc.page" )
local diagnosticsMod = require ( "nupp.compiler.doc.diagnostics" )
local stdlibMod = require ( "nupp.compiler.doc.stdlib" )
local json = require ( "cjson" ) . new ( )

local trim , htmlEscape = stringsMod . trim , stringsMod . htmlEscape
local escapeJs = stringsMod . escapeJs
local normalize , join , dirname = filesMod . normalize , filesMod . join , filesMod . dirname
local readFile , writeFile = filesMod . readFile , filesMod . writeFile
local listFiles , privateSource = filesMod . listFiles , filesMod . privateSource
local copyPublicFiles = filesMod . copyPublicFiles
local moduleName , childModules = extractMod . moduleName , extractMod . children
local namespaceModules = extractMod . namespaces
local internalModuleName = extractMod . internalModuleName
local configureScintillua = highlightMod . configureScintillua
local markdownHtml , markdownOutline = htmlMod . markdownHtml , htmlMod . markdownOutline
local THEME , SCRIPT = assetsMod . THEME , assetsMod . SCRIPT
local moduleFile , routeFile = urlsMod . moduleFile , urlsMod . routeFile
local relativePrefix , cleanRoute = urlsMod . relativePrefix , urlsMod . cleanRoute
local symbolLinkIndex , symbolLinks = urlsMod . symbolLinkIndex , urlsMod . symbolLinks
local rewriteConfiguredPageLinks = urlsMod . rewriteConfiguredPageLinks
local moduleSummary , renderHtmlItem , itemGroups = apiMod . moduleSummary , apiMod . renderHtmlItem , apiMod . itemGroups
local nestedModules = apiMod . nestedModules
local renderPage , homeHero , homeFeatures = pageMod . render , pageMod . homeHero , pageMod . homeFeatures

local doc = { }

json . decode_array_with_array_mt ( true )
json . decode_invalid_numbers ( false )
json . encode_empty_table_as_object ( true )
json . encode_invalid_numbers ( false )























































































function doc . extract (
source ,
path ,
name ,
opts
)
return extractMod . extract ( source , path , name , opts )
end





function doc . markdown (
modules ,
title ,
all ,
overview ,
constructorPattern
)
return markdownMod . render ( modules , title , all , overview , constructorPattern )
end




function doc . json ( modules )
local function array ( items , convert )
local out = setmetatable ( { } , json . array_mt )
for _ , item in ipairs ( items or { } ) do
out [ # out + 1 ] = convert and convert ( item ) or item
end

return out
end

local function annotations ( items )
return items and array ( items ) or nil
end

local function param ( value )
return { name = value . name , type = value . type , mode = value . mode , text = value . text }
end

local function result ( value )
return { type = value . type , text = value . text }
end

local member
member = function ( value )
return {
name = value . name ,
type = value . type ,
text = value . text ,
path = value . path ,
params = array ( value . params , param ) ,
returns = array ( value . returns , result ) ,
raises = array ( value . raises ) ,
isFunction = value . isFunction ,
isMetamethod = value . isMetamethod ,
isType = value . isType ,
members = value . members and array ( value . members , member ) or nil ,
annotations = annotations ( value . annotations ) ,
}
end
local function item ( value )
local info = value . doc

return {
name = value . name ,
kind = value . kind ,
signature = value . signature ,
path = value . path ,
module = value . module ,
line = value . line ,
doc = {
text = info . text ,
params = info . params ,
returns = array ( info . returns ) ,
raises = array ( info . raises ) ,
fields = info . fields ,
typeargs = info . typeargs ,
tags = info . tags ,
} ,
members = array ( value . members , member ) ,
params = array ( value . params , param ) ,
returns = array ( value . returns , result ) ,
raises = array ( value . raises ) ,
typeargs = array (
value . typeargs ,
function ( typearg )
return { name = typearg . name , text = typearg . text }
end
) ,
annotations = annotations ( value . annotations ) ,
}
end

local model = array ( modules , function ( value )
return {
name = value . name ,
path = value . path ,
text = value . text ,
items = array ( value . items , item ) ,
documentationInternal = value . documentationInternal ,
namespace = value . namespace ,
}
end )

return json . encode ( { schemaVersion = 1 , modules = model } ) .. "\n"
end

local function sourceFiles ( root , config , settings , requested )
local paths , seen = { } , { }
local sources = requested and # requested > 0 and requested or settings . sources or config . include or { "." }
for _ , source in ipairs ( sources ) do
local path = join ( root , source )
local candidates = path : match ( "%.nupp$" ) and { path } or listFiles ( path )
for _ , candidate in ipairs ( candidates ) do
candidate = normalize ( candidate )
if not seen [ candidate ] and ( settings . includePrivate or not privateSource ( root , candidate ) ) then
seen [ candidate ] = true
paths [ # paths + 1 ] = candidate
end
end
end
table . sort ( paths )

return paths
end

local function byKindThenName ( left , right )
if left . kind == right . kind then
return left . name < right . name
end
return left . kind < right . kind
end

local function loadModules ( root , config , settings , requested )
local modules , errors = { } , { }
local namespaceBacked , implied = { } , { }
for _ , path in ipairs ( sourceFiles ( root , config , settings , requested ) ) do
local source , readErr = readFile ( path )
if not source then
errors [ # errors + 1 ] = { filename = path , line = 1 , col = 1 , msg = tostring ( readErr ) }
else
local name = moduleName ( path , root , config . include or { } )
local module , parseErrors , extraModules = doc . extract ( source , path , name , {
includeAll = settings . all ,
includePrivate = settings . includePrivate
} )
if module then
modules [ # modules + 1 ] = module
for _ , extra in ipairs ( extraModules or { } ) do
modules [ # modules + 1 ] = extra
namespaceBacked [ extra . name ] = true
implied [ extra ] = true
end
else
for _ , err in ipairs ( parseErrors ) do
errors [ # errors + 1 ] = err
end
end
end
end






local keeper , order = { } , { }
for _ , module in ipairs ( modules ) do
local held = keeper [ module . name ]
if not held then
keeper [ module . name ] = module
order [ # order + 1 ] = module . name
elseif implied [ held ] and not implied [ module ] then
keeper [ module . name ] = module
end
end
for _ , module in ipairs ( modules ) do
local into = keeper [ module . name ]
if into ~= module then




local byPath = { }
for _ , item in ipairs ( into . items ) do
byPath [ item . path ] = item
end
for _ , item in ipairs ( module . items ) do
local held = byPath [ item . path ]
if not held then
into . items [ # into . items + 1 ] = item
byPath [ item . path ] = item
elseif held . doc . text == "" then
held . doc = item . doc
end
end
if into . text == "" then
into . text = module . text
end
into . documentationInternal = into . documentationInternal or module . documentationInternal
end
end
if # order < # modules then
local folded = { }
for _ , name in ipairs ( order ) do
folded [ # folded + 1 ] = keeper [ name ]
end
modules = folded
end








local byName = { }
for _ , module in ipairs ( modules ) do
byName [ module . name ] = byName [ module . name ] or module
end
for _ , module in ipairs ( modules ) do
local kept = { }
for _ , item in ipairs ( module . items ) do
local target = item . module and byName [ item . module ] or nil
local nested = target and byName [ item . module .. "." .. item . name ] or nil
if not settings . includePrivate and item . module and internalModuleName ( item . module ) then




elseif nested and namespaceBacked [ nested . name ] then
if item . doc . text ~= "" then
nested . text = item . doc . text
end
elseif target and target ~= module then
item . path = item . module .. "." .. item . name
for _ , member in ipairs ( item . members ) do
member . path = item . path .. "." .. member . name
end
target . items [ # target . items + 1 ] = item
else
kept [ # kept + 1 ] = item
end
end
module . items = kept
end
for _ , module in ipairs ( modules ) do
table . sort ( module . items , byKindThenName )
end
if not settings . includePrivate then
local internalTrees = { }
for _ , module in ipairs ( modules ) do
if module . documentationInternal and module . path and module . path : match ( "[/\\]init%.nupp$" ) then
internalTrees [ # internalTrees + 1 ] = module . name
end
end
local public = { }
for _ , module in ipairs ( modules ) do
local hidden = ( module . documentationInternal or internalModuleName ( module . name ) ) and true or false
for _ , namespace in ipairs ( internalTrees ) do
if module . name == namespace or module . name : sub ( 1 , # namespace + 1 ) == namespace .. "." then
hidden = true
break
end
end
if not hidden then
public [ # public + 1 ] = module
end
end
modules = public
end


for _ , namespace in ipairs ( namespaceModules ( modules ) ) do
modules [ # modules + 1 ] = namespace
end
table . sort ( modules , function ( left , right )
return left . name < right . name
end )

return modules , errors
end










local function embedFiles ( root , markdown )
local out , fence = { } , nil
for line in ( markdown .. "\n" ) : gmatch ( "(.-)\n" ) do
local marker = line : match ( "^%s*(```+)" ) or line : match ( "^%s*(~~~+)" )
if marker then
if not fence then
fence = marker
elseif marker : sub ( 1 , 1 ) == fence : sub ( 1 , 1 ) and # marker >= # fence then
fence = nil
end
end
local path = not fence and line : match ( "^<<<%s+@(%S+)%s*$" )
if path then
local contents , err = readFile ( join ( root , path ) )
if not contents then
return nil , err
end
out [ # out + 1 ] = "```" .. ( path : match ( "%.([%w_]+)$" ) or "text" )
out [ # out + 1 ] = ( contents : gsub ( "\n$" , "" ) )
out [ # out + 1 ] = "```"
else
out [ # out + 1 ] = line
end
end

return table . concat ( out , "\n" )
end

local function configuredPages ( root , settings , title )
local pages , seen , home = { } , { } , false
for index , configured in ipairs ( settings . pages or { } ) do
if type ( configured ) ~= "table" then
return nil , "documentation page " .. index .. " must be a table"
end
local route = cleanRoute ( configured . path )
if not route then
return nil , "invalid documentation page path"
end
if seen [ route ] then
return nil , "duplicate documentation page path: " .. route
end
seen [ route ] , home = true , home or route == ""
local candidate = { }
for key , value in pairs ( configured ) do
candidate [ key ] = value
end
candidate . heroTitle = candidate . heroTitle or candidate . hero_title
candidate . heroText = candidate . heroText or candidate . hero_text
candidate . heroContent = candidate . heroContent or candidate . hero_content
candidate . heroImage = candidate . heroImage or candidate . hero_image
candidate . heroImageAlt = candidate . heroImageAlt or candidate . hero_image_alt
candidate . heroActions = candidate . heroActions or candidate . hero_actions
candidate . path = route
candidate . title = candidate . title or ( route == "" and title or route )
candidate . markdown = ""
if candidate . source then
local source , err = readFile ( join ( root , candidate . source ) )
if not source then
return nil , err
end
if source : sub ( 1 , 4 ) == "---\n" then
local ending = source : find ( "\n---\n" , 5 , true )
if ending then
source = source : sub ( ending + 5 )
end
end
source , err = embedFiles ( root , source )
if not source then
return nil , err
end
candidate . markdown = source
end
pages [ # pages + 1 ] = candidate
end


local published = { }
for _ , configured in ipairs ( settings . pages or { } ) do
if type ( configured ) == "table" and configured . source then
published [ configured . source ] = true
end
end




local function addGenerated ( generated , what )
if not generated then
return true
end
local route = cleanRoute ( generated . path )
if not route then
return nil , "invalid " .. what .. " path"
end
if seen [ route ] then
return nil , what .. " collides with a configured page: " .. route
end
seen [ route ] = true
pages [ # pages + 1 ] = { path = route , title = generated . title , markdown = generated . markdown }

return true
end

local added , addErr = addGenerated ( diagnosticsMod . page ( settings . diagnostics , published ) , "diagnostic index" )
if not added then
return nil , addErr
end
added , addErr = addGenerated ( stdlibMod . page ( settings . stdlib ) , "standard library index" )
if not added then
return nil , addErr
end
if not home then
table . insert ( pages , 1 , {
path = "" ,
title = title ,
layout = "home" ,
heroTitle = title ,
heroText = settings . description or "API reference generated directly from Nupp source." ,
markdown = ""
} )
end

return pages
end

local function redirectHtml ( target )
return '<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=' .. htmlEscape (
target
) .. '"><link rel="canonical" href="' .. htmlEscape (
target
) .. '"><a href="' .. htmlEscape ( target ) .. '">Documentation moved</a>\n'
end

local function searchIndexJs ( entries )
local out = { "window.NUPP_SEARCH_INDEX = [\n" }
for _ , entry in ipairs ( entries ) do
out [
# out + 1
] = '  {title:"' .. escapeJs (
entry . title
) .. '",url:"' .. escapeJs ( entry . url ) .. '",text:"' .. escapeJs ( entry . text ) .. '"},\n'
end
out [ # out + 1 ] = "];\n"

return table . concat ( out )
end

local function appendSearchEntries ( entries , candidate , file , markdown )
local url = "../" .. file
if candidate . module then
local module = candidate . module
entries [
# entries + 1
] = {
title = ( module . namespace and "Namespace › " or "Module › " ) .. module . name ,
url = url ,
text = module . name .. " " .. ( module . text or "" ) ,
}
for _ , item in ipairs ( module . items ) do
local itemText = { item . name , item . signature , item . doc . text or "" }
for _ , param in ipairs ( item . params ) do
itemText [ # itemText + 1 ] = param . name .. " " .. param . type .. " " .. ( param . text or "" )
end
for _ , value in ipairs ( item . returns ) do
itemText [ # itemText + 1 ] = value . type .. " " .. ( value . text or "" )
end
entries [
# entries + 1
] = { title = "API › " .. item . name , url = url .. "#" .. item . path , text = table . concat ( itemText , " " ) }
for _ , member in ipairs ( item . members ) do
entries [
# entries + 1
] = {
title = "API › " .. item . name .. "." .. member . name ,
url = url .. "#" .. member . path ,
text = member . name .. " " .. ( member . type or "" ) .. " " .. ( member . text or "" ) ,
}
end
end
else
entries [
# entries + 1
] = { title = candidate . title , url = url , text = ( candidate . heroText or "" ) .. " " .. markdown }
for _ , heading in ipairs ( markdownOutline ( markdown ) ) do
if heading . level ~= 1 then
entries [
# entries + 1
] = {
title = candidate . title .. " › " .. heading . name ,
url = url .. "#" .. heading . path ,
text = heading . name .. " " .. candidate . title ,
}
end
end
end
end





local function appendOutline ( items , markdown )
for _ , heading in ipairs ( markdownOutline ( markdown ) ) do
local parent = items [ # items ]
if heading . level > 2 and parent then
local children = parent . items or { }
children [ # children + 1 ] = { path = heading . path , name = heading . name }
parent . items = children
else
items [ # items + 1 ] = { path = heading . path , name = heading . name }
end
end
end

local function renderSite ( root , outDir , modules , title , settings )
configureScintillua ( root , settings )
local ok , err = copyPublicFiles ( root , outDir , settings . public )
if not ok then
return nil , err
end
local css = THEME
if settings . customCss then
local custom
custom , err = readFile ( join ( root , tostring ( settings . customCss ) ) )
if not custom then
return nil , err
end
css = css .. "\n" .. custom
end
ok , err = writeFile ( join ( outDir , "assets/style.css" ) , css )
if not ok then
return nil , err
end
ok , err = writeFile ( join ( outDir , "assets/site.js" ) , SCRIPT )
if not ok then
return nil , err
end
local pages
pages , err = configuredPages ( root , settings , title )
if not pages then
return nil , err
end





local configured , moduleRoutes , ordered = { } , { } , { }
for _ , candidate in ipairs ( pages ) do
configured [ candidate . path ] = candidate
end
for _ , module in ipairs ( modules ) do
local route = moduleFile ( module . name ) : gsub ( "/index%.html$" , "" )
if moduleRoutes [ route ] then
return nil , "two modules document to the same page: " .. route
end
moduleRoutes [ route ] = true
end
for _ , candidate in ipairs ( pages ) do
if not moduleRoutes [ candidate . path ] then
ordered [ # ordered + 1 ] = candidate
end
end
for _ , module in ipairs ( modules ) do
local route = moduleFile ( module . name ) : gsub ( "/index%.html$" , "" )
local overview = configured [ route ]
ordered [ # ordered + 1 ] = {
path = route ,
title = overview and overview . title or ( module . namespace and "Namespace: " or "Module: " ) .. module . name ,
module = module ,
overview = overview and overview . markdown or nil ,
source = overview and overview . source or nil ,


redirects = overview and overview . redirects or nil ,
}
end
pages = ordered

local allMarkdown , linkIndex , searchEntries = { } , symbolLinkIndex ( modules ) , { }
for _ , candidate in ipairs ( pages ) do
local file = routeFile ( candidate . path )
local markdown , body , current = candidate . markdown or "" , { } , nil
local items = { }
if candidate . module then
local module = candidate . module
local children = childModules ( modules , module . name )
current = module . name
appendOutline ( items , candidate . overview )
if # children > 0 then
items [ # items + 1 ] = { path = "modules" , name = "Submodules" }
end
if # module . items > 0 then
items [ # items + 1 ] = { path = "module-contents" , name = "Module contents" }
end
local groups = itemGroups ( module . items , settings . constructorPattern )
for _ , group in ipairs ( groups ) do
if # group . items > 0 then
local entries = { }
for _ , item in ipairs ( group . items ) do
entries [ # entries + 1 ] = { path = item . path , name = item . name }
end
items [ # items + 1 ] = { path = group . path , name = group . title , items = entries }
end
end
local overview = candidate . overview or ""
markdown = doc . markdown ( { module } , nil , modules , overview , settings . constructorPattern )
local links = symbolLinks ( linkIndex , module , relativePrefix ( file ) )
body [
# body + 1
] = '<h1>' .. (
module . namespace and "Namespace: " or "Module: "
) .. '<code>' .. htmlEscape ( module . name ) .. '</code></h1>'


if overview ~= "" then
body [ # body + 1 ] = markdownHtml ( rewriteConfiguredPageLinks ( overview , candidate , pages , file ) , links , 0 )
elseif module . namespace then
body [
# body + 1
] = '<p class="nuppdoc-namespace-note">Modules nested under <code>' .. htmlEscape (
module . name
) .. '</code>. Nothing is required by this name itself.</p>'
elseif module . text ~= "" then
body [ # body + 1 ] = markdownHtml ( module . text , links )
end
if overview ~= "" and module . text ~= "" then
body [ # body + 1 ] = markdownHtml ( module . text , links )
end
body [ # body + 1 ] = nestedModules ( children , relativePrefix ( file ) , modules )
if # module . items == 0 then



if # children == 0 and not module . namespace then
body [ # body + 1 ] = '<div class="nuppdoc-empty">No public declarations.</div>'
end
else
body [ # body + 1 ] = moduleSummary ( module , settings . constructorPattern )
for _ , group in ipairs ( groups ) do
if # group . items > 0 then
body [
# body + 1
] = '<section class="nuppdoc-api-group"><h2 id="' .. htmlEscape (
group . path
) .. '">' .. htmlEscape (
group . title
) .. '<a class="nuppdoc-header-anchor" href="#' .. htmlEscape (
group . path
) .. '" aria-label="Link to ' .. htmlEscape ( group . title ) .. '">#</a></h2>'
for _ , item in ipairs ( group . items ) do
renderHtmlItem ( body , item , links , settings . constructorPattern )
end
body [ # body + 1 ] = "</section>"
end
end
end
else
local links = symbolLinks ( linkIndex , nil , relativePrefix ( file ) )
appendOutline ( items , markdown )
body [ # body + 1 ] = homeHero ( candidate , links )
local renderedMarkdown = rewriteConfiguredPageLinks ( markdown , candidate , pages , file )
local featureStart , featureEnd
if candidate . path == "" then


featureStart , featureEnd = markdown : find ( "<!-- nupp:features -->" , 1 , true )
end
if featureStart and featureEnd then
local introduction = rewriteConfiguredPageLinks (
markdown : sub ( 1 , featureStart - 1 ) ,
candidate ,
pages ,
file
)
local remainder = rewriteConfiguredPageLinks ( markdown : sub ( featureEnd + 1 ) , candidate , pages , file )
body [ # body + 1 ] = markdownHtml ( introduction , links , 0 )
body [ # body + 1 ] = '<h2 id="nupp-features">Nupp Features</h2>'
body [ # body + 1 ] = homeFeatures ( candidate , links )
body [ # body + 1 ] = markdownHtml ( remainder , links , 0 )
else
body [ # body + 1 ] = markdownHtml ( renderedMarkdown , links , 0 )
end
if candidate . path == "" then
if not featureStart then
body [ # body + 1 ] = homeFeatures ( candidate , links )
end
end
end
local html = renderPage (
candidate . title ,
title ,
table . concat ( body , "\n" ) ,
modules ,
current ,
items ,
file ,
settings ,
pages ,
candidate . path ,
candidate . layout
)
appendSearchEntries ( searchEntries , candidate , file , markdown )
ok , err = writeFile ( join ( outDir , file ) , html )
if not ok then
return nil , err
end


for _ , former in ipairs ( candidate . redirects or { } ) do
local formerRoute = cleanRoute ( former )
if not formerRoute or formerRoute == "" then
return nil , "invalid redirect route on page " .. candidate . path
end
local formerFile = routeFile ( formerRoute )
ok , err = writeFile ( join ( outDir , formerFile ) , redirectHtml ( relativePrefix ( formerFile ) .. file ) )
if not ok then
return nil , err
end
end
local mdFile = candidate . path == "" and "index.md" or candidate . path .. ".md"
ok , err = writeFile ( join ( outDir , mdFile ) , markdown )
if not ok then
return nil , err
end
if candidate . path ~= "" then
ok , err = writeFile ( join ( outDir , candidate . path .. "/llms.txt" ) , markdown )
if not ok then
return nil , err
end
end
allMarkdown [ # allMarkdown + 1 ] = { page = candidate , text = markdown }


if candidate . module and not candidate . module . namespace then
local legacy = "modules/" .. candidate . module . name : gsub ( "[^%w._-]" , "-" ) : gsub ( "%." , "/" ) .. ".html"
ok , err = writeFile (
join ( outDir , legacy ) ,
redirectHtml (
candidate . module . name : match (
"%."
) and candidate . module . name : match (
"([^.]+)$"
) .. "/index.html" or candidate . module . name .. "/index.html"
)
)
if not ok then
return nil , err
end
end
end

local llms = { "# " .. ( settings . name or title ) , "" }
if settings . description and settings . description ~= "" then
llms [ # llms + 1 ] = "> " .. settings . description
llms [ # llms + 1 ] = ""
end
llms [ # llms + 1 ] = "## Documentation"
for _ , entry in ipairs ( allMarkdown ) do
local target = entry . page . path == "" and "index.md" or entry . page . path .. "/llms.txt"
llms [ # llms + 1 ] = "- [" .. entry . page . title .. "](" .. target .. ")"
end
llms [ # llms + 1 ] = ""
llms [ # llms + 1 ] = "- [Complete documentation](llms-full.txt)"
ok , err = writeFile ( join ( outDir , "llms.txt" ) , table . concat ( llms , "\n" ) .. "\n" )
if not ok then
return nil , err
end
local full = { "# " .. ( settings . name or title ) }
for _ , entry in ipairs ( allMarkdown ) do
full [ # full + 1 ] = "\n---\n\n## " .. entry . page . title .. "\n\n" .. trim ( entry . text ) .. "\n"
end
ok , err = writeFile ( join ( outDir , "llms-full.txt" ) , table . concat ( full , "\n" ) )
if not ok then
return nil , err
end
ok , err = writeFile ( join ( outDir , "assets/search-index.js" ) , searchIndexJs ( searchEntries ) )
if not ok then
return nil , err
end

return true
end

local function report ( errors )
for _ , err in ipairs ( errors ) do
io . stderr : write (
(
"%s:%d:%d: error: %s\n"
) : format ( err . filename or "?" , err . line or 1 , err . col or 1 , err . msg or "documentation error" )
)
end
end









function doc . defaultOutDir ( format )
if format == "markdown" then
return "docs/api.md"
elseif format == "json" then
return "build/docs.json"
end

return "build/docs"
end




local function removeReplaced ( path )
for attempt = 1 , 20 do
local removed = nupp . io . files . remove ( path )
if removed then
return
end
local deadline = os . clock ( ) + 0.1
while os . clock ( ) < deadline do
end
end
end





local function reconcileSiteFiles ( output , written )
local statePath = join ( output , ".nupp-doc-files.json" )
local previous = { }
local encoded = readFile ( statePath )
if encoded then
local ok , decoded = pcall ( json . decode , encoded )
if ok and type ( decoded ) == "table" then
previous = decoded
end
end
local current = { }
for _ , path in ipairs ( written ) do
current [ normalize ( path ) ] = true
end
for _ , path in ipairs ( previous ) do
path = normalize ( path )
if not current [ path ] and path : sub ( 1 , # output + 1 ) == output .. "/" then
removeReplaced ( path )
local directory = dirname ( path )
while directory ~= output and directory : sub ( 1 , # output + 1 ) == output .. "/" do
removeReplaced ( directory )
directory = dirname ( directory )
end
end
end
table . sort ( written )

return filesMod . writeFile ( statePath , json . encode ( written ) .. "\n" )
end











function doc . build (
root ,
config ,
settings ,
opts
)
root = root or "."
local config = config
local settings = ( settings or { } )
local opts = opts or { }
local modules , errors = loadModules ( root , config or { } , settings , opts . sources )
if # errors > 0 then
report ( errors ) ;
return 1
end
if opts . checkOnly then
return 0
end
local format = opts . format or settings . format or "site"
local title = opts . title or settings . title or config . name or "Nupp API"
local output = normalize ( opts . output or settings . outDir or doc . defaultOutDir ( format ) )
output = join ( root , output )


local written = opts . written or { }
filesMod . collect ( written )
local code , message = 0 , nil
if format == "markdown" then
local ok , err = writeFile ( output , doc . markdown ( modules , title , nil , nil , settings . constructorPattern ) )
if not ok then
code , message = 1 , tostring ( err )
end
elseif format == "site" then
local ok , err = renderSite ( root , output , modules , title , settings )
if not ok then
code , message = 1 , tostring ( err )
end
elseif format == "both" then
local ok , err = renderSite ( root , output , modules , title , settings )
if ok then
ok , err = writeFile (
join ( output , "api.md" ) ,
doc . markdown ( modules , title , nil , nil , settings . constructorPattern )
)
end
if not ok then
code , message = 1 , tostring ( err )
end
elseif format == "json" then
local ok , err = writeFile ( output , doc . json ( modules ) )
if not ok then
code , message = 1 , tostring ( err )
end
else
code = 2
message = "documentation format must be site, markdown, json, or both"
end
filesMod . collect ( nil )
if code == 0 and ( format == "site" or format == "both" ) then
local ok , err = reconcileSiteFiles ( output , written )
if not ok then
code , message = 1 , tostring ( err )
end
end
if message then
io . stderr : write ( "nupp: " .. message .. "\n" )
end

return code , output , format
end



local function withName ( target , name )
local copy = { }
for key , value in pairs ( target ) do
copy [ key ] = value
end
copy . targetName = name

return copy
end












function doc . manifestSettings ( config , requested )
local targets = config . build and config . build . targets or { }
if requested then
local target = targets [ requested ]
if not target then
return nil , "unknown build target " .. requested
end
if target . kind ~= "docs" then
return nil , (
"build target %s is a %s target, not a docs target"
) : format ( requested , tostring ( target . kind or "modules" ) )
end

return withName ( target , requested )
end
if type ( config . docs ) == "table" then
return config . docs
end
local found


= { }
for name , target in pairs ( targets ) do
if type ( target ) == "table" and target . kind == "docs" then
found [ # found + 1 ] = { name = name , target = target }
end
end
table . sort ( found , function ( a , b )
return a . name < b . name
end )
local first = found [ 1 ]
if not first then
return { }
end
if # found > 1 then
local preferred = config . build and config . build . default or nil
local target = preferred and targets [ preferred ] or nil
if preferred and target and target . kind == "docs" then
return withName ( target , preferred )
end
local names = { }
for index , entry in ipairs ( found ) do
names [ index ] = entry . name
end

return nil , (
"the manifest has %d docs targets (%s): name one with --target, "
) : format ( # found , table . concat ( names , ", " ) ) .. "or say which the build defaults to with build.default"
end

return withName ( first . target , first . name )
end



function doc . loadConfig ( root )
local manifest = loadfile ( join ( root or "." , "nupp.lua" ) )
if not manifest then
return { }
end
local ok , loaded = pcall ( manifest )
if not ok then
return nil , tostring ( loaded )
end

return type ( loaded ) == "table" and loaded or { }
end

doc . theme = THEME
doc . script = SCRIPT
doc . highlight = highlightMod . nuppSource

return doc
