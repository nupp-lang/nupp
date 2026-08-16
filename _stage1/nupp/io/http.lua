_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();const __nuppT4={}; const __nuppT5,__nuppT6,__nuppT7,__nuppT8,__nuppT9,__nuppT10,__nuppT11,__nuppT12=pcall,xpcall,error,unpack,select,setmetatable,tostring,ipairs; const function __nuppT1(...) return {n=__nuppT9("#",...),...} end; const function __nuppT2(value) return value end; const function __nuppT3(primary,errors,start) const secondary={} for i=start,#errors do secondary[#secondary+1]=errors[i] end return __nuppT10({primary=primary,suppressed=secondary},{__tostring=function(v) local text=__nuppT11(v.primary) for _,reason in __nuppT12(v.suppressed) do text=text.."\ncleanup: "..__nuppT11(reason) end return text end}) end; local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppLazy(target,name,loader)local meta=getmetatable(target)or{};local loaders=meta.__nuppLoaders;if not loaders then loaders={};local prior=meta.__index;meta.__nuppLoaders=loaders;meta.__index=function(t,k)local load=loaders[k];if load then local value=load(k);loaders[k]=nil;if value==nil then value=rawget(t,k)else rawset(t,k,value)end;return value end;if type(prior)=="function"then return prior(t,k)elseif prior then return prior[k]end end;setmetatable(target,meta)end;if name~=nil and rawget(target,name)==nil and loaders[name]==nil then loaders[name]=loader end end local function __nuppInstallIO()local ffi=require("ffi");local Buffer,View,Reader,Writer={},{},{},{};Buffer.__index=Buffer;View.__index=View;Reader.__index=Reader;Writer.__index=Writer local __nuppBytes=ffi.typeof("uint8_t[?]");local SMALLEST=32 local function integer(value,what,level)if type(value)~="number"or value~=math.floor(value)or value<0 then error("nupp: "..what.." must be a non-negative integer",level)end;return value end local function whole(value,what,level)if type(value)~="number"or value~=math.floor(value)then error("nupp: "..what.." must be an integer",level)end;return value end local function opened(self,what,level)if self._closed then error("nupp: "..what.." is closed",level)end end local function range(length,offset,count,what,level)offset=integer(offset or 0,what.." offset",level);if offset>length then error("nupp: "..what.." offset is past the end",level)end;count=integer(count==nil and length-offset or count,what.." count",level);if offset+count>length then error("nupp: "..what.." range is past the end",level)end;return offset,count end local function reserve(self,minimum)if minimum<=self._capacity then return end;local capacity=self._capacity*2;if capacity<minimum then capacity=minimum end;if capacity<SMALLEST then capacity=SMALLEST end;local data=__nuppBytes(capacity);if self._length>0 then ffi.copy(data,self._data,self._length)end;self._data=data;self._capacity=capacity end local function bytesAt(self,offset,count)if count==0 then return""end;return ffi.string(self._data+offset,count)end function View:length()opened(self,"io.ByteView",2);return #self._bytes end;function View:getString()opened(self,"io.ByteView",2);return self._bytes end;function View:newReader()opened(self,"io.ByteView",2);return setmetatable({_bytes=self._bytes,_at=1,_closed=false},Reader)end;function View:view(offset,count)opened(self,"io.ByteView",2);offset,count=range(#self._bytes,offset,count,"io.ByteView",2);return setmetatable({_bytes=self._bytes:sub(offset+1,offset+count),_closed=false},View)end;function View:isReleased()return self._closed end;function View:close()self._closed=true;self._bytes="";return true end function Buffer:length()opened(self,"io.Buffer",2);return self._length end;function Buffer:capacity()opened(self,"io.Buffer",2);return self._capacity end;function Buffer:clear()opened(self,"io.Buffer",2);self._length=0 end;function Buffer:ensureCapacity(minimum)opened(self,"io.Buffer",2);reserve(self,integer(minimum,"io.Buffer capacity",2))end function Buffer:resize(length)opened(self,"io.Buffer",2);length=integer(length,"io.Buffer length",2);if length>self._length then reserve(self,length);ffi.fill(self._data+self._length,length-self._length,0)end;self._length=length end function Buffer:getString(offset,count)opened(self,"io.Buffer",2);offset,count=range(self._length,offset,count,"io.Buffer",2);return bytesAt(self,offset,count)end function Buffer:setString(bytes,offset)opened(self,"io.Buffer",2);if type(bytes)~="string"then error("nupp: io.Buffer bytes must be a string",2)end;offset=integer(offset or 0,"io.Buffer offset",2);local ending=offset+#bytes;reserve(self,ending);if offset>self._length then ffi.fill(self._data+self._length,offset-self._length,0)end;if #bytes>0 then ffi.copy(self._data+offset,bytes,#bytes)end;if ending>self._length then self._length=ending end end function Buffer:view(offset,count)opened(self,"io.Buffer",2);offset,count=range(self._length,offset,count,"io.Buffer",2);return setmetatable({_bytes=bytesAt(self,offset,count),_closed=false},View)end;function Buffer:isReleased()return self._closed end;function Buffer:close()self._closed=true;self._data=nil;self._length=0;self._capacity=0;return true end function Reader:read(count)if self._closed then return nil,"the reader is closed"end;count=whole(count,"Reader:read count",2);if self._at>#self._bytes then return ""end;local taking=math.min(math.max(1,count),#self._bytes-self._at+1);local out=self._bytes:sub(self._at,self._at+taking-1);self._at=self._at+taking;return out end function Reader:readInto(destination,offset,count)if self._closed then return nil,"the reader is closed"end;offset=integer(offset or 0,"Reader:readInto offset",2);count=integer(count or 65536,"Reader:readInto count",2);if self._at>#self._bytes or count==0 then return 0 end;local taking=math.min(count,#self._bytes-self._at+1);destination:setString(self._bytes:sub(self._at,self._at+taking-1),offset);self._at=self._at+taking;return taking end function Reader:transferTo(destination)if self._closed then return nil,"the reader is closed"end;local remaining=self._bytes:sub(self._at);local ok,reason=destination:write(remaining);if not ok then return nil,reason end;self._at=#self._bytes+1;return #remaining end;function Reader:close()self._closed=true;self._bytes="";return true end local function slice(source,offset,count,what)offset,count=range(source:length(),offset,count,what,3);return source:getString(offset,count),count end function Writer:write(bytes)if self._closed then return false,"the writer is closed"end;if self._buffer:isReleased()then return false,"the destination buffer is closed"end;self._buffer:setString(bytes,self._at);self._at=self._at+#bytes;return true end function Writer:writeFrom(source,offset,count)if self._closed then return nil,"the writer is closed"end;if source==self._buffer then return nil,"cannot write a buffer into itself"end;local bytes,n=slice(source,offset,count,"io.Buffer");local ok,reason=self:write(bytes);if not ok then return nil,reason end;return n end function Writer:writeView(source,offset,count)if self._closed then return nil,"the writer is closed"end;offset,count=range(source:length(),offset,count,"io.ByteView",2);local ok,reason=self:write(source:getString():sub(offset+1,offset+count));if not ok then return nil,reason end;return count end;function Writer:flush()if self._closed then return false,"the writer is closed"end;return true end;function Writer:close()self._closed=true;return not self._buffer:isReleased(),self._buffer:isReleased()and"the destination buffer is closed"or nil end function Buffer:newReader()opened(self,"io.Buffer",2);return setmetatable({_bytes=bytesAt(self,0,self._length),_at=1,_closed=false},Reader)end;function Buffer:newWriter()opened(self,"io.Buffer",2);self:clear();return setmetatable({_buffer=self,_at=0,_closed=false},Writer)end local function newBuffer(initial)if initial~=nil and type(initial)~="number"and type(initial)~="string"then error("nupp: io.newBuffer initial value must be bytes or a capacity",2)end;local bytes=type(initial)=="string"and initial or"";local capacity=type(initial)=="number"and integer(initial,"io.newBuffer capacity",2)or#bytes;local self=setmetatable({_data=capacity>0 and __nuppBytes(capacity)or nil,_length=0,_capacity=capacity,_closed=false},Buffer);if#bytes>0 then ffi.copy(self._data,bytes,#bytes);self._length=#bytes end;return self end local ByteQueue,ScalarReader,ScalarWriter={},{},{};ByteQueue.__index=ByteQueue;ScalarReader.__index=ScalarReader;ScalarWriter.__index=ScalarWriter function ByteQueue:read(count)if self._closed then return nil,"the reader is closed"end;count=whole(count,"Reader:read count",2);local have=#self._source;if have==0 then return""end;return self._source:get(math.min(math.max(1,count),have))end function ByteQueue:readInto(destination,offset,count)if self._closed then return nil,"the reader is closed"end;offset=integer(offset or 0,"Reader:readInto offset",2);count=integer(count or 65536,"Reader:readInto count",2);local have=#self._source;if have==0 or count==0 then return 0 end;local taking=math.min(count,have);destination:setString(self._source:get(taking),offset);return taking end function ByteQueue:transferTo(destination)if self._closed then return nil,"the reader is closed"end;local rest=self._source:get();local ok,reason=destination:write(rest);if not ok then return nil,reason end;return #rest end function ByteQueue:close()self._closed=true;self._source=nil;return true end local function fill(self,need)local failure;if self._reader then while #self._pending<need do local chunk,reason=self._reader:read(need-#self._pending);if chunk==nil then failure=reason;break end;if chunk==""then break end;self._pending=self._pending..chunk end elseif self._queue then local want=need-#self._pending;local have=want>0 and #self._queue or 0;if have>0 then self._pending=self._pending..self._queue:get(math.min(want,have))end end;return #self._pending,failure end local function taken(self,need)if self._closed then error("nupp: io.ScalarReader is closed",3)end;local have,failure=fill(self,need);if failure then error("nupp: io.ScalarReader source failed: "..tostring(failure),3)end;if have<need then error(("nupp: io.ScalarReader needs %d bytes, has %d"):format(need,have),3)end;local out=self._pending:sub(1,need);self._pending=self._pending:sub(need+1);return out end function ScalarReader:remaining()if self._closed then error("nupp: io.ScalarReader is closed",2)end;if self._reader then return nil end;if self._queue then return #self._pending+#self._queue end;return #self._pending end function ScalarReader:atEnd()if self._closed then error("nupp: io.ScalarReader is closed",2)end;local have,failure=fill(self,1);if failure then error("nupp: io.ScalarReader source failed: "..tostring(failure),2)end;return have<1 end function ScalarReader:skip(count)taken(self,integer(count,"io.ScalarReader count",2));return self end function ScalarReader:readBytes(count)return taken(self,integer(count,"io.ScalarReader count",2))end function ScalarReader:close()self._closed=true;self._pending="";self._queue=nil;local reader=self._reader;self._reader=nil;if reader then return reader:close()end;return true end local function scalarRead(ctype,size)local pointer=ffi.typeof(ctype);return function(self)local raw=taken(self,size);return ffi.cast(pointer,raw)[0]end end ScalarReader.readUint8=scalarRead("uint8_t*",1);ScalarReader.readInt8=scalarRead("int8_t*",1);ScalarReader.readUint16=scalarRead("uint16_t*",2);ScalarReader.readInt16=scalarRead("int16_t*",2);ScalarReader.readUint32=scalarRead("uint32_t*",4);ScalarReader.readInt32=scalarRead("int32_t*",4);ScalarReader.readUint64=scalarRead("uint64_t*",8);ScalarReader.readInt64=scalarRead("int64_t*",8);ScalarReader.readFloat32=scalarRead("float*",4);ScalarReader.readFloat64=scalarRead("double*",8) local function put(self,bytes)if self._closed then error("nupp: io.ScalarWriter is closed",3)end;if self._buffer then self._buffer:setString(bytes,self._buffer:length());return self end;local ok,reason=self._writer:write(bytes);if not ok then error("nupp: io.ScalarWriter destination failed: "..tostring(reason),3)end;return self end function ScalarWriter:writeBytes(bytes)if type(bytes)~="string"then error("nupp: io.ScalarWriter bytes must be a string",2)end;return put(self,bytes)end function ScalarWriter:buffer()return self._buffer end function ScalarWriter:flush()if self._closed then return false,"the writer is closed"end;if self._writer then return self._writer:flush()end;return true end function ScalarWriter:close()self._closed=true;local writer=self._writer;self._writer=nil;if writer then return writer:close()end;return true end local function scalarWrite(ctype,size)local holder=ffi.new(ctype);return function(self,value)holder[0]=value;return put(self,ffi.string(holder,size))end end ScalarWriter.writeUint8=scalarWrite("uint8_t[1]",1);ScalarWriter.writeInt8=scalarWrite("int8_t[1]",1);ScalarWriter.writeUint16=scalarWrite("uint16_t[1]",2);ScalarWriter.writeInt16=scalarWrite("int16_t[1]",2);ScalarWriter.writeUint32=scalarWrite("uint32_t[1]",4);ScalarWriter.writeInt32=scalarWrite("int32_t[1]",4);ScalarWriter.writeUint64=scalarWrite("uint64_t[1]",8);ScalarWriter.writeInt64=scalarWrite("int64_t[1]",8);ScalarWriter.writeFloat32=scalarWrite("float[1]",4);ScalarWriter.writeFloat64=scalarWrite("double[1]",8) local BADSOURCE="nupp: io.newScalarReader needs bytes, a snapshot, a buffer, a reader or a byte queue" local function queueLike(value)local kind=type(value);if kind=="table"then return value.get~=nil end;if kind~="userdata"and kind~="cdata"then return false end;local ok,getter=pcall(function()return value.get end);return ok and getter~=nil end local function newQueueReader(source)if not queueLike(source)then error("nupp: io.newQueueReader needs a byte queue",2)end;return setmetatable({_source=source,_closed=false},ByteQueue)end local function newScalarReader(source)local self=setmetatable({_pending="",_closed=false},ScalarReader);local kind=type(source);if kind=="string"then self._pending=source elseif kind=="table"and source.read~=nil then self._reader=source elseif kind=="table"and source.getString~=nil then self._pending=source:getString()elseif queueLike(source)then self._queue=source else error(BADSOURCE,2)end;return self end local function newScalarWriter(destination)local self=setmetatable({_closed=false},ScalarWriter);if destination==nil then self._buffer=newBuffer()elseif type(destination)=="table"and destination.write~=nil then self._writer=destination elseif type(destination)=="table"and destination.setString~=nil then self._buffer=destination else error("nupp: io.newScalarWriter needs a buffer, a writer, or nothing",2)end;return self end View.drop=View.close;Buffer.drop=Buffer.close;Reader.drop=Reader.close;Writer.drop=Writer.close;ByteQueue.drop=ByteQueue.close;ScalarReader.drop=ScalarReader.close;ScalarWriter.drop=ScalarWriter.close __nuppIO.newBuffer=newBuffer;__nuppIO.newQueueReader=newQueueReader;__nuppIO.newScalarReader=newScalarReader;__nuppIO.newScalarWriter=newScalarWriter;__nuppIO.newStringReader=function(text)if type(text)~="string"then error("nupp: io.newStringReader needs a string",2)end;return setmetatable({_bytes=text,_at=1,_closed=false},Reader)end;return __nuppIO end for _,__name in ipairs({"newBuffer","newQueueReader","newScalarReader","newScalarWriter","newStringReader"})do __nuppLazy(__nuppIO,__name,function(name)__nuppInstallIO();return rawget(__nuppIO,name)end)end local __nuppNativeValue;local function __nuppNative()if __nuppNativeValue then return __nuppNativeValue end;local ffi=require("ffi");ffi.cdef[[const char*nuppNativeError(void);typedef struct NuppUri NuppUri;NuppUri*nuppUriParse(const uint8_t*,size_t);const uint8_t*nuppUriPart(const NuppUri*,uint32_t,size_t*);bool nuppUriPort(const NuppUri*,uint16_t*);NuppUri*nuppUriWithText(const NuppUri*,uint32_t,const uint8_t*,size_t,bool);NuppUri*nuppUriWithPort(const NuppUri*,int32_t);NuppUri*nuppUriConcatPath(const NuppUri*,const uint8_t*,size_t);NuppUri*nuppUriResolve(const NuppUri*,const uint8_t*,size_t);NuppUri*nuppUriWithEndpoint(const NuppUri*,const NuppUri*);void nuppUriDestroy(NuppUri*);]];local source=debug.getinfo(1,"S").source;local root=source:match("^@(.+)/[^/]+%.lua$")or".";local wanted=os.getenv("NUPP_NATIVE_LIBRARY");local C;if wanted then C=ffi.load(wanted)else local linked=pcall(function()return ffi.C.nuppNativeError end);if linked then C=ffi.C else local library=ffi.os=="Windows"and"/lib/nupp_native.dll"or"/lib/nupp_native";local ok,lib=pcall(ffi.load,root..library);if ok then C=lib else C=ffi.load(root.."/.."..library)end end end;local function errorText()return ffi.string(C.nuppNativeError())end;__nuppNativeValue={ffi=ffi,C=C,error=errorText};return __nuppNativeValue end local function __nuppInstallURI() local native=__nuppNative();local ffi,C=native.ffi,native.C;local URI={};URI.__index=URI;URI.__tostring=function(self)return self:toString()end;URI.__eq=function(a,b)return a:toString()==b:toString()end local function wrap(handle)if handle==nil then return nil,native.error()end;return setmetatable({_handle=ffi.gc(handle,C.nuppUriDestroy)},URI)end local function changed(handle)if handle==nil then error("nupp: cannot modify URI: "..native.error(),3)end;return setmetatable({_handle=ffi.gc(handle,C.nuppUriDestroy)},URI)end local function part(self,kind)local length=ffi.new("size_t[1]");local data=C.nuppUriPart(self._handle,kind,length);if data==nil then return nil end;return ffi.string(data,tonumber(length[0]))end function URI:toString()return part(self,0)end;function URI:scheme()return part(self,1)end;function URI:authority()return part(self,2)end;function URI:username()return part(self,3)end;function URI:password()return part(self,4)end;function URI:host()return part(self,5)end;function URI:path()return part(self,6)end;function URI:query()return part(self,7)end;function URI:fragment()return part(self,8)end function URI:userInfo()local username=self:username();local password=self:password();if username==""and password==nil then return nil end;return password and(username..":"..password)or username end function URI:port()local value=ffi.new("uint16_t[1]");return C.nuppUriPort(self._handle,value)and tonumber(value[0])or nil end local function required(value,what)if type(value)~="string"then error("nupp: "..what.." needs a string",3)end;return value end local kinds={withScheme={0,"scheme",true},withUserInfo={1,"userInfo"},withHost={2,"host"},withPath={3,"path",true},withQuery={4,"query"},withFragment={5,"fragment"}};for name,spec in pairs(kinds)do URI[name]=function(self,value)if spec[3]then value=required(value,"URI "..spec[2])elseif value~=nil then value=required(value,"URI "..spec[2])end;if value==self[spec[2]](self)then return self end;return changed(C.nuppUriWithText(self._handle,spec[1],value or"",value and#value or 0,value~=nil))end end function URI:withPort(port)if port~=nil and(type(port)~="number"or port~=math.floor(port)or port<0 or port>65535)then error("nupp: URI port must be an integer from 0 through 65535 or nil",2)end;if port==self:port()then return self end;return changed(C.nuppUriWithPort(self._handle,port or-1))end function URI:concatPath(path)path=required(path,"URI path");if path==""then return self end;return changed(C.nuppUriConcatPath(self._handle,path,#path))end function URI:resolve(reference)if type(reference)~="string"then return nil,"nupp: URI reference needs a string"end;return wrap(C.nuppUriResolve(self._handle,reference,#reference))end function URI:withEndpoint(endpoint)if type(endpoint)~="table"or getmetatable(endpoint)~=URI then error("nupp: URI endpoint must be an io.URI",2)end;return changed(C.nuppUriWithEndpoint(self._handle,endpoint._handle))end local function compose(c)if type(c)~="table"then return nil,"nupp: io.URI.new needs absolute text or URI components"end;if type(c.scheme)~="string"or c.scheme==""then return nil,"nupp: URI components need a non-empty scheme"end;for _,name in ipairs({"userInfo","host","path","query","fragment"})do if c[name]~=nil and type(c[name])~="string"then return nil,"nupp: URI component "..name.." must be a string or nil"end end;if c.port~=nil and(type(c.port)~="number"or c.port~=math.floor(c.port)or c.port<0 or c.port>65535)then return nil,"nupp: URI component port must be an integer from 0 through 65535 or nil"end;local out=c.scheme..":";if c.host or c.userInfo or c.port then out=out.."//";if c.userInfo then out=out..c.userInfo.."@"end;out=out..(c.host or"");if c.port then out=out..":"..c.port end end;out=out..(c.path or"");if c.query then out=out.."?"..c.query end;if c.fragment then out=out.."#"..c.fragment end;return out end URI.new=function(value)local text,problem;if type(value)=="string"then text=value else text,problem=compose(value);if not text then return nil,problem end end;return wrap(C.nuppUriParse(text,#text))end URI.validate=function(text)if type(text)~="string"then return false,"nupp: io.URI.validate needs a string"end;local handle=C.nuppUriParse(text,#text);if handle==nil then return false,native.error()end;C.nuppUriDestroy(handle);return true end URI.isURI=function(value)return type(value)=="table"and getmetatable(value)==URI end __nuppIO.URI=URI return __nuppIO end __nuppLazy(__nuppIO,"URI",function()__nuppInstallURI();return rawget(__nuppIO,"URI")end);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;local __nuppCleanup1;__nuppCleanup1=function(value) local cleanup=__nuppCleanups["nupp:prelude.d.nupp#__nuppDestroyBuffer"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp:prelude.d.nupp#__nuppDestroyBuffer") end;__nuppCleanup1=cleanup;return cleanup(value) end;local __nuppCleanup2;__nuppCleanup2=function(value) local cleanup=__nuppCleanups["nupp.io.http#destroyBody"];if cleanup==nil then return _G.error("Nupp cleanup provider is not loaded: nupp.io.http#destroyBody") end;__nuppCleanup2=cleanup;return cleanup(value) end;const __nuppClosureCleanup1 = function(__nuppV) return __nuppV:__nuppRelease() end;









local suspension = require ( "nupp.suspension" )
local http = { }








































local native = require ( "nupp.io.httpnative" )



http.Options = {} http.Options.__index = http.Options

















http.ReaderBody = {} http.ReaderBody.__index = http.ReaderBody





http.FileBody = {} http.FileBody.__index = http.FileBody






http.Request = {} http.Request.__index = http.Request









local READ_SIZE = 64 * 1024
local UPLOAD_SIZE = 512 * 1024
local UPLOAD_PAGE = 64 * 1024
local COALESCE_BELOW = 8 * 1024
local COPY_TURN = 16 * 1024 * 1024
local BODY_INLINE , BODY_UPLOAD , BODY_FILE = 1 , 2 , 3

local function whole ( value , what , minimum , maximum )
if type (
value
) ~= "number" or value ~= math . floor ( value ) or value < minimum or maximum ~= nil and value > maximum then
error (
(
"nupp: HTTP %s must be an integer%s"
) : format (
what ,
maximum ~= nil and ( " from " .. minimum .. " through " .. maximum ) or " of at least " .. minimum
) ,
3
)
end

return value
end

local function optionInteger ( options , name , fallback , minimum )
local value = options and options [ name ]
if value == nil then
return fallback
end

return whole ( value , name , minimum )
end

local function canonicalHost ( text , level )
if text == "" or text : find ( "[/?#@*]" ) ~= nil then
error ( "nupp: HTTP insecureHosts entries must be exact host names or IP literals" , level )
end
local spelling = text : sub ( - 1 ) == "." and text : sub ( 1 , - 2 ) or text
local uri = nupp . io . URI . new ( "https://" .. spelling .. "/" )
if uri == nil or uri : username ( ) ~= "" or uri : password ( ) ~= nil or uri : port ( ) ~= nil or uri : path ( ) ~= "/" then
error ( "nupp: HTTP insecureHosts entries must not contain a scheme, port, path, or user information" , level )
end
local host = uri : host ( )
if host == nil or host == "" then
error ( "nupp: HTTP insecureHosts entry is not a host" , level )
end

return host : lower ( )
end

local function mergedHeaders ( first , second , contentType )
local byLower , merged = { } , { }
local function add ( headers )
for name , value in pairs ( headers or { } ) do
if type (
name
) ~= "string" or type (
value
) ~= "string" or name == "" or name : find ( "[\r\n:]" ) ~= nil or value : find ( "[\r\n]" ) ~= nil then
error ( "nupp: HTTP headers need valid string names and values" , 3 )
end
local lower = name : lower ( )
local previous = byLower [ lower ]
if previous ~= nil then
merged [ previous ] = nil
end
merged [ name ] = value
byLower [ lower ] = name
end
end

add ( first )
add ( second )
if contentType ~= nil and byLower [ "content-type" ] == nil then
merged [ "content-type" ] = contentType
byLower [ "content-type" ] = "content-type"
end
local packed = { }
for name , value in pairs ( merged ) do
packed [ # packed + 1 ] = { name , value }
end

return byLower , merged , packed
end

local function copiedOptions ( options )
local given = options or { }
local headers = { }
for name , value in pairs ( given . headers or { } ) do
if type ( name ) ~= "string" or type ( value ) ~= "string" then
error ( "nupp: HTTP default headers must have string names and values" , 3 )
end
headers [ name ] = value
end
if given . userAgent ~= nil then
if type ( given . userAgent ) ~= "string" then
error ( "nupp: HTTP userAgent must be a string" , 3 )
end
headers [ "user-agent" ] = given . userAgent
end
local insecure = { }
for _ , host in ipairs ( given . insecureHosts or { } ) do
if type ( host ) ~= "string" then
error ( "nupp: HTTP insecureHosts entries must be strings" , 3 )
end
insecure [ canonicalHost ( host , 3 ) ] = true
end
for _ , name in ipairs ( { "proxy" , "noProxy" , "proxyCredentials" } ) do
if given [ name ] ~= nil and type ( given [ name ] ) ~= "string" then
error ( "nupp: HTTP " .. name .. " must be a string" , 3 )
end
end
if given . compressed ~= nil and type ( given . compressed ) ~= "boolean" then
error ( "nupp: HTTP compressed must be a boolean" , 3 )
end
local _ , _ , packedHeaders = mergedHeaders ( nil , headers , nil )
local manualRedirects = next ( insecure ) ~= nil

return {
headers = headers ,
packedHeaders = packedHeaders ,
timeoutMs = optionInteger ( given , "timeoutMs" , 30000 , 1 ) ,
connectTimeoutMs = optionInteger ( given , "connectTimeoutMs" , 10000 , 1 ) ,
stallTimeoutMs = optionInteger ( given , "stallTimeoutMs" , 0 , 0 ) ,
maxRedirects = optionInteger ( given , "maxRedirects" , 5 , 0 ) ,
maxPendingRequests = optionInteger ( given , "maxPendingRequests" , 256 , 1 ) ,
maxConnections = optionInteger ( given , "maxConnections" , 16 , 1 ) ,
maxConnectionsPerHost = optionInteger ( given , "maxConnectionsPerHost" , 16 , 1 ) ,
maxBytes = optionInteger ( given , "maxBytes" , 0 , 0 ) ,
compressed = given . compressed ~= false ,
insecureHosts = insecure ,
manualRedirects = manualRedirects ,
proxy = given . proxy ,
noProxy = given . noProxy ,
proxyCredentials = given . proxyCredentials ,
}
end

local function appendWaiter ( client , transfer , which , cancelNative )
suspension . suspend ( "HTTP " .. which , function ( resume , context )
local active = true
client : _retainSource ( context )
local forget
local function finish ( )
if not active then
return
end
active = false
if forget ~= nil then
forget ( )
end
client : _releaseSource ( )
resume ( true )
end

if which == "response headers" then
forget = transfer : onHead ( finish )
elseif which == "response body" then
forget = transfer : onBody ( finish )
else
forget = transfer : onUpload ( finish )
end

return function ( )
if active then
active = false
forget ( )
client : _releaseSource ( )
if cancelNative then
transfer : cancel ( )
end
end
end
end )
end

local function waitAdmission ( client )
suspension . suspend (
"HTTP request admission" ,
function ( resume , context )
local active = true
client : _retainSource ( context )
local forget
local function finish ( )
if not active then
return
end
active = false
if forget ~= nil then
forget ( )
end
client : _releaseSource ( )
resume ( true )
end

forget = client . _native : onAdmission ( finish )

return function ( )
if active then
active = false
forget ( )
client : _releaseSource ( )
end
end
end
)
end

local function waitHead ( client , transfer , cancelNative )
while true do
local state , status , version , url , headers , reason = transfer : head ( )
if state == "ready" then
return { status = status , version = version , url = url , headers = headers }
elseif state == "failed" then
return { reason = reason }
end
appendWaiter ( client , transfer , "response headers" , cancelNative )
end
end

local function fairnessYield ( )
suspension . suspend (
"HTTP response copy fairness" ,
function ( resume , context )
local active = true
context : source ( "nupp-http-fairness" , 20 , function ( )
if not active then
return 0
end
active = false
resume ( true )

return 1
end )

return function ( )
active = false
end
end
)
end

http.Body = {} http.Body.__index = http.Body






function http.Body:_next(count, destination, offset)
if self . _closed then
return nil , "the body is closed"
end
if self . _reading then
error ( "nupp: an HTTP response body may only have one reader" , 3 )
end
self . _reading = true
while true do
local state , value , reason = self . _transfer : bodyRead ( count , destination , offset )
if state == "data" then
self . _reading = false
return value
elseif state == "eof" then
self . _reading = false
return destination ~= nil and 0 or ""
elseif state == "failed" or state == "closed" then
self . _reading = false
return nil , reason
end
local ok , problem = pcall ( appendWaiter , self . _client , self . _transfer , "response body" , true )
if not ok then
self . _reading = false
error ( problem , 0 )
end
end
end

function http.Body:read(count)
local wanted = whole ( count , "body read count" , - 9007199254740991 )
return self : _next ( wanted < 1 and 1 or wanted , nil , 0 )
end

function http.Body:readInto(destination, offset, count)
local at = whole ( offset or 0 , "body destination offset" , 0 )
local wanted = whole ( count or READ_SIZE , "body read count" , 0 )
if wanted == 0 then
return 0
end
local value , reason = self : _next ( wanted , destination , at )
if type ( value ) == "string" then
destination : setString ( value , at )
return # value
end

return value , reason
end

function http.Body:transferTo(destination)
local total = 0
local turn = 0
if self . _transfer : directDestination ( destination ) then
while true do
if self . _closed then
return nil , "the body is closed"
end
if self . _reading then
error ( "nupp: an HTTP response body may only have one reader" , 2 )
end
self . _reading = true
local state , count , reason = self . _transfer : bodyWrite ( destination , READ_SIZE )
if state == "pending" then
local ok , problem = pcall ( appendWaiter , self . _client , self . _transfer , "response body" , true )
self . _reading = false
if not ok then
error ( problem , 0 )
end
elseif state == "eof" then
self . _reading = false
return total
elseif state == "failed" or state == "closed" then
self . _reading = false
return nil , reason
else
self . _reading = false
total = total + ( count )
turn = turn + ( count )
if turn >= COPY_TURN then
fairnessYield ( )
turn = 0
end
end
end
end
while true do
local chunk , reason = self : read ( READ_SIZE )
if chunk == nil then
return nil , reason
elseif chunk == "" then
return total
end
local wrote , failure = destination : write ( chunk )
if not wrote then
return nil , failure
end
total = total + # chunk
turn = turn + # chunk
if turn >= COPY_TURN then
fairnessYield ( )
turn = 0
end
end
end

function http.Body:close()
self : release ( )
return true
end

function http.Body:release()
if self . _closed then
return
end
self . _closed = true
self . _transfer : close ( )
end


function http . Body . drop ( self )
do
if not self . _closed then
self . _closed = true
self . _transfer : close ( )
end
end
end

local function destroyBody ( body )
if not body . _closed then
body . _closed = true
body . _transfer : close ( )
end
end ;__nuppCleanups["nupp.io.http#destroyBody"]=destroyBody

local function makeBody ( client , transfer ) __nuppCleanups["nupp.io.http#destroyBody"]=destroyBody;
return setmetatable({ _client =  client ,  _transfer =  transfer ,  _closed =  false ,  _reading =  false }, http.Body)
end

local function u32 ( bytes , at )
local a , b , c , d = bytes : byte ( at , at + 3 )
if d == nil then
error ( "nupp: malformed packed HTTP response headers" , 0 )
end

return ( ( a or 0 ) + ( b or 0 ) * 256 + ( c or 0 ) * 65536 + ( d or 0 ) * 16777216 )
end

local function packedHeader ( bytes , wanted )
local count = u32 ( bytes , 1 )
local tableEnd = 4 + count * 16
if tableEnd > # bytes then
return nil
end
for index = 0 , count - 1 do
local at = 5 + index * 16
local nameAt , nameLength = u32 ( bytes , at ) , u32 ( bytes , at + 4 )
local valueAt , valueLength = u32 ( bytes , at + 8 ) , u32 ( bytes , at + 12 )
if nameAt < tableEnd
or valueAt < tableEnd
or nameAt
+ nameLength > # bytes
or valueAt
+ valueLength > # bytes
then
return nil
end
if bytes : sub ( nameAt + 1 , nameAt + nameLength ) : lower ( ) == wanted then
return bytes : sub ( valueAt + 1 , valueAt + valueLength )
end
end

return nil
end

local function origin ( uri )
local scheme = uri : scheme ( )
local port = uri : port ( ) or ( scheme == "https" and 443 or 80 )
return scheme .. "://" .. ( uri : host ( ) or "" ) : lower ( ) .. ":" .. port
end

http.Response = {} http.Response.__index = http.Response










function http.Response:_decode()
if self . _values ~= nil then
return
end
local values = { }
local count = u32 ( self . _packed , 1 )
local tableEnd = 4 + count * 16
if tableEnd > # self . _packed then
error ( "nupp: malformed packed HTTP response headers" , 0 )
end
for index = 0 , count - 1 do
local at = 5 + index * 16
local nameAt , nameLength = u32 ( self . _packed , at ) , u32 ( self . _packed , at + 4 )
local valueAt , valueLength = u32 ( self . _packed , at + 8 ) , u32 ( self . _packed , at + 12 )
if nameAt < tableEnd
or valueAt < tableEnd
or nameAt
+ nameLength > # self . _packed
or valueAt
+ valueLength > # self . _packed
then
error ( "nupp: malformed packed HTTP response headers" , 0 )
end
local name = self . _packed : sub ( nameAt + 1 , nameAt + nameLength ) : lower ( )
local value = self . _packed : sub ( valueAt + 1 , valueAt + valueLength )
local list = values [ name ]
if list == nil then
list = { }
values [ name ] = list
end
list [ # list + 1 ] = value
end
self . _values = values
end

function http.Response:ok()
return self . status >= 200 and self . status < 300
end

function http.Response:header(name)
if type ( name ) ~= "string" then
error ( "nupp: HTTP header name must be a string" , 2 )
end
self : _decode ( )
local values = ( self . _values ) [ name : lower ( ) ]
if values == nil then
return nil
end

return name : lower ( ) == "set-cookie" and values [ 1 ] or table . concat ( values , ", " )
end

function http.Response:getAll(name)
if type ( name ) ~= "string" then
error ( "nupp: HTTP header name must be a string" , 2 )
end
self : _decode ( )
local found = ( self . _values ) [ name : lower ( ) ] or { }
local out = { }
for index = 1 , # found do
out [ index ] = found [ index ]
end

return out
end

function http.Response:headers()
if self . _headers == nil then
self : _decode ( )
local out = { }
for name , values in pairs ( self . _values ) do
out [ name ] = name == "set-cookie" and values [ 1 ] or table . concat ( values , ", " )
end
self . _headers = out
end
local copy = { }
for name , value in pairs ( self . _headers ) do
copy [ name ] = value
end

return copy
end

function http.Response:close()
if self . _closed then
return true
end
self . _closed = true
local body = self . body
destroyBody ( body )

return true
end


function http . Response . drop ( self )
do
if not self . _closed then
self . _closed = true
self . body : drop ( )
end
end
end

local function destroyResponse ( self )
do
if not self . _closed then
self . _closed = true
self . body : drop ( )
end
end
end ;__nuppCleanups["nupp.io.http#destroyResponse"]=destroyResponse

local function makeResponse (
status ,
version ,
url ,
body ,
packed
) __nuppCleanups["nupp.io.http#destroyResponse"]=destroyResponse;
return setmetatable({ status =
status ,  version =
version ,  url =
url ,  body =
body ,  _packed =
packed ,  _values =
nil ,  _headers =
nil ,  _closed =
false }, http.Response)

end

http.Client = {} http.Client.__index = http.Client







function http.Client:_retainSource(context)
if self . _source == nil then
local backend = self . _native
self . _source = suspension . source (
"nupp-http" ,
20 ,
function ( )
return backend : poll ( 0 )
end ,
function ( waitMs )
return backend : poll ( waitMs )
end
)
end
self . _sourceUsers = self . _sourceUsers + 1
context : uses ( self . _source )
end

function http.Client:_releaseSource()
self . _sourceUsers = self . _sourceUsers - 1
if self . _sourceUsers == 0 and self . _source ~= nil then
self . _source : release ( )
self . _source = nil
end
end


function http . Client : send ( request ) __nuppCleanups["nupp.io.http#destroyResponse"]=destroyResponse;
if self . _closed then
return nil , "the HTTP client is closed"
end
local given = request
if given == nil or given . url == nil or type ( given . url . toString ) ~= "function" then
error ( "nupp: HTTP request url must be a URI" , 2 )
end
local scheme = given . url : scheme ( )
if scheme ~= "http" and scheme ~= "https" then
error ( "nupp: HTTP request URL must use http or https" , 2 )
end
local method = given . method
if method == nil then
method = "GET"
elseif type ( method ) ~= "string" or method == "" or method : find ( "[^!#$%%&'*+%.^_`|~%w%-]" ) ~= nil then
error ( "nupp: HTTP method is not a valid token" , 2 )
end
local requestBody = given . body
local body , bodyKind , bodyLength = requestBody , 0 , nil
local reader = nil
local contentType = nil
if body ~= nil then
local concrete = body
if concrete . reader ~= nil then
reader = concrete . reader
bodyKind = BODY_UPLOAD
bodyLength = concrete . length
contentType = concrete . contentType
if bodyLength ~= nil then
whole ( bodyLength , "reader body length" , 0 )
end
elseif concrete . path ~= nil then
bodyKind = BODY_FILE
body = type ( concrete . path ) == "string" and concrete . path or concrete . path : toString ( )
bodyLength = - 1
contentType = concrete . contentType
elseif type ( body ) == "string" then
bodyKind = BODY_INLINE
bodyLength = # body
elseif type ( concrete . length ) == "function" and type ( concrete . getString ) == "function" then
bodyKind = BODY_INLINE
bodyLength = concrete : length ( )
else
error ( "nupp: HTTP request body is not bytes, a Buffer, ReaderBody, or FileBody" , 2 )
end
end
local manualRedirects = self . _options . manualRedirects
local byLower , merged , packed
if given . headers == nil and not given . _redirected and contentType == nil and not manualRedirects then
packed = self . _options . packedHeaders
else
byLower , merged , packed = mergedHeaders (
not given . _redirected and self . _options . headers or nil ,
given . headers ,
contentType
)
end
local insecure = false
if manualRedirects then
local host = ( given . url : host ( ) or "" ) : lower ( )
insecure = self . _options . insecureHosts [ host ] == true
end
local requestTimeout = given . timeoutMs ~= nil and whole ( given . timeoutMs , "timeoutMs" , 1 ) or self . _options . timeoutMs
local now = self . _native : now ( )
local deadline = given . _deadline or ( now + requestTimeout )
local remaining = math . floor ( deadline - now )
if remaining < 1 then
return nil , "HTTP request timed out"
end
local descriptor = {
uri = given . url ,
method = method ,
headers = packed ,
body = body ,
bodyKind = bodyKind ,
bodyLength = bodyLength ,
timeoutMs = remaining ,
stallTimeoutMs = given . stallTimeoutMs ~= nil and whole (
given . stallTimeoutMs ,
"stallTimeoutMs" ,
0
) or self . _options . stallTimeoutMs ,
maxBytes = given . maxBytes ~= nil and whole ( given . maxBytes , "maxBytes" , 0 ) or self . _options . maxBytes ,
insecure = insecure ,
}
if not suspension . canSuspend ( ) then
error ( "nupp: HTTP request cannot suspend here" , 2 )
end
local transfer , reason
while transfer == nil do
remaining = math . floor ( deadline - self . _native : now ( ) )
if remaining < 1 then
return nil , "HTTP request timed out waiting for admission"
end
descriptor . timeoutMs = remaining
local full
transfer , reason , full = self . _native : send ( descriptor )
if transfer == nil and not full then
return nil , reason
elseif transfer == nil then
waitAdmission ( self )
if self . _closed then
return nil , "the HTTP client is closed"
end
end
end
local head , problem
if reader ~= nil then
do local __nuppT13=0; local  __nuppT19,__nuppT21 ; local __nuppT20=false ; local __nuppT22=false ; const __nuppT14,__nuppT15,__nuppT16=__nuppT6(function() do const __nuppT23= nupp . io . newBuffer ( UPLOAD_SIZE ) ; __nuppT19= __nuppT23 ; __nuppT13=1;  __nuppT20=true;  local scratch=__nuppT19;
local uploadTransfer = transfer const __nuppT24= (function(scratch) local __nuppT25=true;  __nuppT20=false;  local __nuppT26=function


( ) do local __nuppT28=0; local  __nuppT34 ; const __nuppT29,__nuppT30,__nuppT31=__nuppT6(function() do const __nuppT35= scratch ; __nuppT34= __nuppT35 ; __nuppT28=1;  local scratch=__nuppT34;
local transferred = 0
while true do
scratch : clear ( )
local got , failure = reader : readInto ( scratch , 0 , UPLOAD_SIZE )
if got == nil then
transfer : cancel ( )
error ( failure or "HTTP request reader failed" , 0 )
end
local finished = got == 0
if not finished and ( got ) < COALESCE_BELOW then
while scratch : length ( ) < UPLOAD_PAGE do
local more , moreFailure = reader : readInto (
scratch ,
scratch : length ( ) ,
UPLOAD_PAGE - scratch : length ( )
)
if more == nil then
transfer : cancel ( )
error ( moreFailure or "HTTP request reader failed" , 0 )
elseif more == 0 then
finished = true
break
end
end
end
local offered = scratch : length ( )
if offered > 0 then
while true do
local accepted = uploadTransfer : offer ( scratch , false , offered )
if accepted == "accepted" then
break
elseif accepted == "closed" then
return "return",__nuppT1( waitHead ( self , transfer , false ) )
end
appendWaiter ( self , transfer , "upload space" , false )
end
transferred = transferred + offered
end
if finished then
if bodyLength ~= nil and transferred ~= bodyLength then
transfer : cancel ( )
error (
( "HTTP request reader ended after %d bytes; expected %d" ) : format ( transferred , bodyLength ) ,
0
)
end
if transfer : offer ( nil , true ) == "closed" then
return "return",__nuppT1( waitHead ( self , transfer , false ) )
end
return "return",__nuppT1( waitHead ( self , transfer , false ) )
end
end end; return "normal" end,__nuppT2); const __nuppT32={}; local __nuppT33=0; if __nuppT28>=1 then  const __nuppT36,__nuppT37=__nuppT5(__nuppCleanup1,__nuppT34);  if not __nuppT36 then __nuppT33=__nuppT33+1; __nuppT32[__nuppT33]=__nuppT37 end; end; if not __nuppT29 then if __nuppT33>0 then __nuppT7(__nuppT3(__nuppT30,__nuppT32,1),0) else __nuppT7(__nuppT30,0) end end; if __nuppT33>0 then if __nuppT33>1 then __nuppT7(__nuppT3(__nuppT32[1],__nuppT32,2),0) else __nuppT7(__nuppT32[1],0) end end; if __nuppT30=="return" then  return __nuppT8(__nuppT31,1,__nuppT31.n)  end; end
end ; local __nuppT27={};  __nuppT27.__nuppRelease=function() if not __nuppT25 then return end; __nuppT25=false;  local __nuppT38={}; local __nuppT39=0;  local __nuppT40,__nuppT41=__nuppT5(__nuppCleanup1,scratch); if not __nuppT40 then __nuppT39=__nuppT39+1; __nuppT38[__nuppT39]=__nuppT41 end;  if __nuppT39>0 then if __nuppT39>1 then __nuppT7(__nuppT3(__nuppT38[1],__nuppT38,2),0) else __nuppT7(__nuppT38[1],0) end end end;  return setmetatable(__nuppT27,{__call=function(_,...) if not __nuppT25 then __nuppT7("nupp: affine closure was already called or dropped",2) end;  __nuppT25=false; return __nuppT26(...) end}) end)( scratch ) ; __nuppT21= __nuppT24 ; __nuppT13=2;  __nuppT22=true;  local uploadAndWait=__nuppT21;

local ok , value = pcall ( (function(uploadAndWait) local __nuppT42=true;  __nuppT22=false;  local __nuppT43=function ( ) do local __nuppT45=0; local  __nuppT51 ; local __nuppT52=false ; const __nuppT46,__nuppT47,__nuppT48=__nuppT6(function() do const __nuppT53= uploadAndWait ; __nuppT51= __nuppT53 ; __nuppT45=1;  __nuppT52=true;  local uploadAndWait=__nuppT51;
local answer = (function(__nuppT54,...)  __nuppT52=false;  return __nuppT54(...)  end)( suspension . race , {
uploadAndWait ,
function ( )
return waitHead ( self , transfer , false )
end
} )

return "return",__nuppT1( answer ) end; return "normal" end,__nuppT2); const __nuppT49={}; local __nuppT50=0; if __nuppT45>=1 and __nuppT52 then  const __nuppT55,__nuppT56=__nuppT5(__nuppClosureCleanup1,__nuppT51);  if not __nuppT55 then __nuppT50=__nuppT50+1; __nuppT49[__nuppT50]=__nuppT56 end; end; if not __nuppT46 then if __nuppT50>0 then __nuppT7(__nuppT3(__nuppT47,__nuppT49,1),0) else __nuppT7(__nuppT47,0) end end; if __nuppT50>0 then if __nuppT50>1 then __nuppT7(__nuppT3(__nuppT49[1],__nuppT49,2),0) else __nuppT7(__nuppT49[1],0) end end; if __nuppT47=="return" then  return __nuppT8(__nuppT48,1,__nuppT48.n)  end; end
end ; local __nuppT44={};  __nuppT44.__nuppRelease=function() if not __nuppT42 then return end; __nuppT42=false;  local __nuppT57={}; local __nuppT58=0;  local __nuppT59,__nuppT60=__nuppT5(__nuppClosureCleanup1,uploadAndWait); if not __nuppT59 then __nuppT58=__nuppT58+1; __nuppT57[__nuppT58]=__nuppT60 end;  if __nuppT58>0 then if __nuppT58>1 then __nuppT7(__nuppT3(__nuppT57[1],__nuppT57,2),0) else __nuppT7(__nuppT57[1],0) end end end;  return setmetatable(__nuppT44,{__call=function(_,...) if not __nuppT42 then __nuppT7("nupp: affine closure was already called or dropped",2) end;  __nuppT42=false; return __nuppT43(...) end}) end)( uploadAndWait ) )
if not ok then
transfer : cancel ( )
transfer : close ( )
error ( value , 0 )
end
head = value end; return "normal" end,__nuppT2); const __nuppT17={}; local __nuppT18=0; if __nuppT13>=2 and __nuppT22 then  const __nuppT61,__nuppT62=__nuppT5(__nuppClosureCleanup1,__nuppT21);  if not __nuppT61 then __nuppT18=__nuppT18+1; __nuppT17[__nuppT18]=__nuppT62 end; end; if __nuppT13>=1 and __nuppT20 then  const __nuppT63,__nuppT64=__nuppT5(__nuppCleanup1,__nuppT19);  if not __nuppT63 then __nuppT18=__nuppT18+1; __nuppT17[__nuppT18]=__nuppT64 end; end; if not __nuppT14 then if __nuppT18>0 then __nuppT7(__nuppT3(__nuppT15,__nuppT17,1),0) else __nuppT7(__nuppT15,0) end end; if __nuppT18>0 then if __nuppT18>1 then __nuppT7(__nuppT3(__nuppT17[1],__nuppT17,2),0) else __nuppT7(__nuppT17[1],0) end end; if __nuppT15=="return" then  return __nuppT8(__nuppT16,1,__nuppT16.n)  end; end
else
head = waitHead ( self , transfer , true )
end
if head == nil or head . reason ~= nil then
problem = head and head . reason or "HTTP transfer failed"
transfer : close ( )
return nil , problem
end
local status = head . status
local location = manualRedirects and packedHeader ( head . headers , "location" ) or nil
if manualRedirects and location ~= nil and (
status == 301 or status == 302 or status == 303 or status == 307 or status == 308
) then
local followed = ( given . _redirects or 0 )
if followed >= self . _options . maxRedirects then
if self . _options . maxRedirects == 0 then
location = nil
else
transfer : close ( )
return nil , "HTTP request exceeded maxRedirects"
end
end
if location ~= nil then
local target , targetReason = given . url : resolve ( location )
if target == nil then
transfer : close ( )
return nil , targetReason or "HTTP redirect has an invalid location"
end
if target : scheme ( ) ~= "http" and target : scheme ( ) ~= "https" then
transfer : close ( )
return nil , "HTTP redirect must use http or https"
end
local nextMethod , nextBody = method , requestBody
local dropsBody = status == 303 and method ~= "HEAD" or (
status == 301 or status == 302
) and method == "POST"
if dropsBody then
nextMethod = "GET"
nextBody = nil
for _ , name in ipairs ( { "content-length" , "content-type" , "transfer-encoding" } ) do
local spelling = byLower [ name ]
if spelling ~= nil then
merged [ spelling ] = nil
end
end
elseif reader ~= nil then
transfer : close ( )
return nil , "HTTP redirect cannot replay a ReaderBody"
end
if origin ( given . url ) ~= origin ( target ) then
for _ , name in ipairs ( { "authorization" , "proxy-authorization" , "cookie" , "host" } ) do
local spelling = byLower [ name ]
if spelling ~= nil then
merged [ spelling ] = nil
end
end
end
transfer : close ( )
local redirected = {
url = target ,
method = nextMethod ,
headers = merged ,
body = nextBody ,
timeoutMs = given . timeoutMs ,
stallTimeoutMs = given . stallTimeoutMs ,
maxBytes = given . maxBytes ,
_redirected = true ,
_redirects = followed + 1 ,
_deadline = deadline ,
}
return self : send ( redirected )
end
end
local bodyReady , bodyReason = transfer : takeBody ( )
if not bodyReady then
transfer : close ( )
return nil , bodyReason
end
local effective = head . url == nil and given . url or nupp . io . URI . new ( head . url )
if effective == nil then
transfer : close ( )
return nil , "the HTTP provider returned an invalid effective URL"
end
local version = head . version == 10 and "1.0" or head . version == 20 and "2" or "1.1"
do local __nuppT65=0; local  __nuppT71 ; local __nuppT72=false ; const __nuppT66,__nuppT67,__nuppT68=__nuppT6(function() do const __nuppT73= makeBody ( self , transfer ) ; __nuppT71= __nuppT73 ; __nuppT65=1;  __nuppT72=true;  local responseBody=__nuppT71;

return "return",__nuppT1( (function(__nuppT74,...)  __nuppT72=false;  return __nuppT74(...)  end)( makeResponse , head . status , version , effective , responseBody , head . headers ) ) end; return "normal" end,__nuppT2); const __nuppT69={}; local __nuppT70=0; if __nuppT65>=1 and __nuppT72 then  const __nuppT75,__nuppT76=__nuppT5(__nuppCleanup2,__nuppT71);  if not __nuppT75 then __nuppT70=__nuppT70+1; __nuppT69[__nuppT70]=__nuppT76 end; end; if not __nuppT66 then if __nuppT70>0 then __nuppT7(__nuppT3(__nuppT67,__nuppT69,1),0) else __nuppT7(__nuppT67,0) end end; if __nuppT70>0 then if __nuppT70>1 then __nuppT7(__nuppT3(__nuppT69[1],__nuppT69,2),0) else __nuppT7(__nuppT69[1],0) end end; if __nuppT67=="return" then  return __nuppT8(__nuppT68,1,__nuppT68.n)  end; end
end

function http . Client : pending ( )
return self . _closed and 0 or self . _native : pending ( )
end

function http . Client . close ( self )
if self . _closed then
return true
end
self . _closed = true
if self . _source ~= nil then
self . _source : release ( )
self . _source = nil
self . _sourceUsers = 0
end
self . _native : close ( )

return true
end

function http . Client . drop ( self )
do
if not self . _closed then
self . _closed = true
if self . _source ~= nil then
self . _source : release ( )
self . _source = nil
self . _sourceUsers = 0
end
local native = self . _native
native : close ( )
end
end
end

local function destroyClient ( self )
self : drop ( )
end ;__nuppCleanups["nupp.io.http#destroyClient"]=destroyClient

function http . reader ( reader , length , contentType )
if length ~= nil then
whole ( length , "reader body length" , 0 )
end
if contentType ~= nil and type ( contentType ) ~= "string" then
error ( "nupp: HTTP content type must be a string" , 2 )
end

return setmetatable({ reader =  reader ,  length =  length ,  contentType =  contentType }, http.ReaderBody)
end

function http . file ( path , contentType )
if type ( path ) ~= "string" and type ( ( path ) . toString ) ~= "function" then
error ( "nupp: HTTP file body needs a path" , 2 )
end
if contentType ~= nil and type ( contentType ) ~= "string" then
error ( "nupp: HTTP content type must be a string" , 2 )
end

return setmetatable({ path =  path ,  contentType =  contentType }, http.FileBody)
end

function http . newClient ( options ) __nuppCleanups["nupp.io.http#destroyClient"]=destroyClient;
local copied = copiedOptions ( options )
local backend , reason = native . newClient ( copied )
if backend == nil then
return nil , reason
end

return setmetatable({ _native =  backend ,  _options =  copied ,  _source =  nil ,  _sourceUsers =  0 ,  _closed =  false }, http.Client)
end

return http
