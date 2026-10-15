//! The library the compiler's own modules call: strings with Lua patterns,
//! tables, math, iteration, errors. Each builtin is a value with a tag and an
//! id; a dynamic call on one lands here and returns its results.

use crate::heap::{KIND_BYTES, KIND_CLOSURE, KIND_ITER, KIND_RECORD, KIND_SLICE, KIND_STORAGE, KIND_STR, KIND_TABLE};
use crate::interp::Interp;
use crate::value::Value;

pub const NAMES: &[&str] = &[
    "string.byte", "string.sub", "string.find", "string.char", "string.rep", "string.format", "string.gsub", "string.gmatch", "string.len", "string.upper", "string.lower", "string.match",
    "table.concat", "table.insert", "table.remove", "table.unpack",
    "math.floor", "math.min", "math.max", "math.abs", "math.huge",
    "pcall", "pairs", "ipairs", "next", "type", "tostring", "tonumber", "error", "assert", "select", "print", "rawequal", "rawget", "rawset", "setmetatable", "getmetatable", "unpack",
    "bit.band", "bit.bor", "bit.bxor", "bit.bnot", "bit.lshift", "bit.rshift", "bit.arshift", "bit.tobit", "os.getenv", "os.clock", "os.time", "io.write", "loadstring", "require", "debug.getinfo",
    "table.sort", "string.reverse", "bit.rol", "bit.ror", "bit.bswap", "bit.tohex", "math.ceil", "math.sqrt", "math.log", "math.fmod", "math.modf", "math.frexp", "io.open", "io.stderr.write", "io.stdout.write", "os.remove", "os.tmpname", "os.execute", "os.rename", "io.read", "file.read", "file.close", "file.lines", "file.write",
    // The fixed-width scalar intrinsics the checker names on a call (`nupp.math.u32.add`),
    // dispatched by name.
    "scalar.i32.add", "scalar.i32.sub", "scalar.i32.mul", "scalar.i32.andBits", "scalar.i32.orBits", "scalar.i32.xorBits", "scalar.i32.notBits", "scalar.i32.shiftLeft", "scalar.i32.rotateLeft", "scalar.i32.rotateRight", "scalar.i32.lessThan", "scalar.i32.lessOrEqual", "scalar.i32.shiftRightArithmetic", "scalar.i32.wrap", "scalar.i32.fromU32", "scalar.i32.toU32",
    "scalar.u32.add", "scalar.u32.sub", "scalar.u32.mul", "scalar.u32.andBits", "scalar.u32.orBits", "scalar.u32.xorBits", "scalar.u32.notBits", "scalar.u32.shiftLeft", "scalar.u32.rotateLeft", "scalar.u32.rotateRight", "scalar.u32.lessThan", "scalar.u32.lessOrEqual", "scalar.u32.shiftRightLogical", "scalar.u32.wrap", "scalar.u32.fromI32", "scalar.u32.toI32", "scalar.u32.popcount", "scalar.u32.trailingZeros", "scalar.u32.leadingZeros", "scalar.u32.div", "scalar.u32.mod",
    "files.info", "files.isDirectory", "files.list", "files.createDirectory", "files.exists", "files.isFile", "path.currentDirectory", "path.newPath", "path.toString", "path.canonicalize",
    "scalar.f32.narrow", "scalar.f32.round", "scalar.f32.add", "scalar.f32.sub", "scalar.f32.mul", "scalar.f32.div", "scalar.f32.sqrt", "scalar.f32.min", "scalar.f32.max", "scalar.f32.fma", "scalar.f32.exp", "scalar.f32.fromBits", "scalar.f32.toBits",
    "vm.loadImage", "vm.processId", "vm.sha256", "vm.saveValue", "vm.loadValue", "vm.loadInto",
    "tasks.open", "tasks.checkpoint", "tasks.deadline", "tasks.spawn", "tasks.spawnNamed", "tasks.await", "tasks.status", "tasks.isDone", "tasks.cancel", "tasks.cancelScope", "tasks.close", "tasks.isCancelled", "tasks.familyOpen", "tasks.familyAwait", "affine.release", "tasks.fork", "tasks.channel", "tasks.channelSend", "tasks.channelReceive", "tasks.channelClose", "tasks.coCreate", "tasks.coResume", "tasks.coYield", "tasks.coStatus", "tasks.coRunning", "tasks.coClose", "tasks.coWrap", "tasks.coIsYieldable", "tasks.channelShare", "tasks.coDispose",
    "terminal.isTerminal", "terminal.columns", "clock.now",
    "files.remove", "vm.cacheDigest", "vm.cDeclarations",
    "vm.clockNow", "vm.clockWall", "vm.clockSleep",
    "table.maxn", "vm.tableAppendResults", "tasks.pollWorkers", "tasks.workerOpen",
    "wide.i64.cast", "wide.i64.not", "wide.i64.neg", "wide.i64.add", "wide.i64.sub", "wide.i64.mul", "wide.i64.div", "wide.i64.idiv", "wide.i64.mod", "wide.i64.pow", "wide.i64.and", "wide.i64.or", "wide.i64.xor", "wide.i64.shl", "wide.i64.shr", "wide.i64.eq", "wide.i64.ne", "wide.i64.lt", "wide.i64.le", "wide.u64.cast", "wide.u64.not", "wide.u64.neg", "wide.u64.add", "wide.u64.sub", "wide.u64.mul", "wide.u64.div", "wide.u64.idiv", "wide.u64.mod", "wide.u64.pow", "wide.u64.and", "wide.u64.or", "wide.u64.xor", "wide.u64.shl", "wide.u64.shr", "wide.u64.eq", "wide.u64.ne", "wide.u64.lt", "wide.u64.le", "scalar.u64.andBits", "scalar.u64.sub", "scalar.u64.rotateLeft", "scalar.u64.rotateRight", "scalar.u64.popcount", "scalar.u64.leadingZeros", "scalar.u64.trailingZeros", "scalar.u64.prefixXor", "math.sin", "math.cos", "math.tan", "math.asin", "math.acos", "math.atan", "math.atan2", "math.exp", "math.ldexp",
    "wide.i64.sar", "wide.u64.sar", "wide.i64.is", "wide.u64.is",
    "storage.allocateBytes", "storage.borrowString", "storage.copy", "storage.fill", "storage.sizeOf", "storage.string", "storage.decodeUint8", "storage.encodeUint8", "storage.decodeInt8", "storage.encodeInt8", "storage.decodeUint16", "storage.encodeUint16", "storage.decodeInt16", "storage.encodeInt16", "storage.decodeUint32", "storage.encodeUint32", "storage.decodeInt32", "storage.encodeInt32", "storage.decodeUint64", "storage.encodeUint64", "storage.decodeInt64", "storage.encodeInt64", "storage.decodeFloat32", "storage.encodeFloat32", "storage.decodeFloat64", "storage.encodeFloat64", "storage.castBytes", "storage.castElements", "storage.scalar", "storage.descriptor", "storage.allocateArray", "storage.boundedCount", "storage.index", "storage.write", "storage.add", "storage.sub",
    "simd.reducer.orderedSum", "simd.reducer.pairwiseSum", "simd.reducer.compensatedSum", "simd.reducer.algebraicSum", "simd.reducer.orderedProduct", "simd.reducer.pairwiseProduct", "simd.reducer.algebraicProduct", "simd.reducer.orderedDot", "simd.reducer.pairwiseDot", "simd.reducer.algebraicDot", "simd.reducer.wrappingSum", "simd.reducer.wrappingProduct", "simd.reducer.andBits", "simd.reducer.orBits", "simd.reducer.xorBits", "simd.reducer.any", "simd.reducer.all", "simd.reducer.count", "simd.reducer.integerMin", "simd.reducer.integerMax", "simd.reducer.integerArgMin", "simd.reducer.integerArgMax", "simd.reducer.propagatingMin", "simd.reducer.propagatingMax", "simd.reducer.propagatingArgMin", "simd.reducer.propagatingArgMax", "simd.reducer.numberMin", "simd.reducer.numberMax", "simd.reducer.numberArgMin", "simd.reducer.numberArgMax",
    "simd.reducerAdd", "simd.reducerValue", "simd.indirect",
    "uuid.uuid4", "uuid.uuid7", "crc.update",
    "io.stdin.read", "io.stdout.flush", "io.stderr.flush", "io.flush", "io.stdout.setvbuf", "io.stderr.setvbuf",
    "io.popen", "process.spawn", "process.poll", "process.kill", "process.read", "process.write", "process.closeStream", "process.reap", "process.waitReady", "process.pipeRead", "process.pipeWrite", "process.pipeClose",
    "crypto.randomBytes", "system.availableParallelism", "collectgarbage", "os.date", "xpcall", "io.type", "io.lines", "vm.encodePlain", "vm.decodePlain",
    "package.preloadLoader", "package.imageLoader", "vm.withInstructionBudget",
    "files.glob", "files.read", "files.createTemporaryFile", "files.createTemporaryDirectory", "temporary.toString", "temporary.close", "temporary.isReleased", "temporary.persist",
    "tasks.vmSpawn", "tasks.vmCapture", "tasks.vmPrepare", "tasks.vmReplace", "tasks.vmFork", "tasks.vmStep", "tasks.vmPoll", "tasks.vmGeneration", "tasks.vmClose", "tasks.vmDiscard",
    "storage.layout",
    "storage.structDefine", "storage.arrayType", "storage.valueNew", "storage.valueOf", "storage.valueCopy", "storage.valueIsa", "storage.structIs",
    "foreign.bind", "foreign.call", "foreign.close", "foreign.errno", "foreign.callback", "foreign.setCallback",
    "storage.castWritableElements", "storage.isBorrowed",
    "files.write",
    "vm.saveData", "vm.loadData",
    "table.clone",
    "table.clear",
    "simd.absent",
    "os.exit",
    "debug.traceback",
    "files.lines",
    "files.readerRead", "files.readerClose",
    "error.site",
    "utf8.char", "utf8.lower", "utf8.upper", "utf8.len", "utf8.codepoint", "utf8.sub",
    "nfiles.info", "nfiles.readLink", "nfiles.createSymlink", "nfiles.setReadOnly", "nfiles.createDirectory", "nfiles.remove", "nfiles.rename", "nfiles.list", "nfiles.glob", "nfiles.read", "nfiles.write", "nfiles.append", "nfiles.writeAtomic", "nfiles.copy", "nfiles.open", "nfiles.fileRead", "nfiles.fileWrite", "nfiles.fileSeek", "nfiles.filePosition", "nfiles.fileSize", "nfiles.fileFlush", "nfiles.fileClose", "nfiles.currentDirectory", "nfiles.canonicalize", "nfiles.userFolder", "nfiles.applicationBase", "nfiles.executablePath", "nfiles.createTemporary",
    // LPeg (`crate::lpeg::BUILTINS`, in that order).
    "lpeg.ptree", "lpeg.pcode", "lpeg.match", "lpeg.B", "lpeg.V", "lpeg.C", "lpeg.Cc", "lpeg.Cmt", "lpeg.Cb", "lpeg.Carg", "lpeg.Cp", "lpeg.Cs", "lpeg.Ct", "lpeg.Cf", "lpeg.Cg",
    "lpeg.P", "lpeg.S", "lpeg.R", "lpeg.utfR", "lpeg.locale", "lpeg.setmaxstack", "lpeg.type",
    "lpeg.__mul", "lpeg.__add", "lpeg.__pow", "lpeg.__len", "lpeg.__div", "lpeg.__mod", "lpeg.__unm", "lpeg.__sub",
    // Provider primitives, installed as `nupp.vm.<family>` (`crate::interp::PROVIDER_FAMILIES`).
    "ncompression.encoderCreate", "ncompression.encoderWrite", "ncompression.encoderFlush", "ncompression.encoderFinish", "ncompression.encoderRelease",
    "ncompression.decoderCreate", "ncompression.decoderRead", "ncompression.decoderFinishInput", "ncompression.decoderRelease",
    "nnet.snapshot", "nnet.sleep",
    "nnet.listen", "nnet.listenPath", "nnet.listenerPort", "nnet.accept", "nnet.closeListener",
    "nnet.connect", "nnet.connectPath", "nnet.connectPoll", "nnet.closeConnect",
    "nnet.read", "nnet.write", "nnet.pending", "nnet.ended", "nnet.writeFailed", "nnet.shuttingDown", "nnet.shutdownWrite",
    "nnet.address", "nnet.noDelay", "nnet.keepAlive", "nnet.closeStream",
    "nnet.bindDatagram", "nnet.datagramPort", "nnet.receive", "nnet.sendTo", "nnet.broadcast", "nnet.multicastTtl", "nnet.multicastLoop", "nnet.membership", "nnet.closeDatagram",
    "nnet.tlsWrap", "nnet.tlsHandshake", "nnet.tlsRead", "nnet.tlsWrite", "nnet.tlsFlushed", "nnet.tlsCloseNotify", "nnet.tlsConnected", "nnet.tlsVerified", "nnet.tlsResumed", "nnet.tlsProtocol", "nnet.tlsDestroy",
    "nhttp.clientCreate", "nhttp.clientRelease", "nhttp.clientPending", "nhttp.clientSend", "nhttp.clientPoll",
    "nhttp.transferCancel", "nhttp.transferRelease", "nhttp.transferOffer", "nhttp.transferHead", "nhttp.transferTakeBody", "nhttp.bodyArm", "nhttp.bodyRead",
    "nuri.parse",
    // LuaJIT's string.buffer (`crate::strbuf::BUILTINS`, in that order).
    "sbuf.new", "sbuf.encode", "sbuf.decode",
    "sbuf.put", "sbuf.putf", "sbuf.get", "sbuf.tostring", "sbuf.reset", "sbuf.free", "sbuf.skip", "sbuf.set",
    "sbuf.bencode", "sbuf.bdecode", "sbuf.putcdata", "sbuf.ref", "sbuf.reserve", "sbuf.commit",
    "sbuf.__len", "sbuf.__tostring", "sbuf.__concat",
    // Appended last so every earlier id, which linked objects carry, keeps its value.
    "vm.imageIdentity",
];

enum Lit { Num(f64), Str(Vec<u8>), Bool(bool), Nil }
/// `return <literal>` with Lua's number and string syntax; None for anything else.
fn literal_chunk(src: &[u8]) -> Option<Lit> {
    let s = std::str::from_utf8(src).ok()?;
    let s = s.trim_start();
    let rest = s.strip_prefix("return")?;
    if rest.chars().next().map(|c| c.is_alphanumeric() || c == '_').unwrap_or(false) { return None; }
    let rest = rest.trim();
    let rest = rest.strip_suffix(';').unwrap_or(rest).trim_end();
    if rest == "nil" { return Some(Lit::Nil); } if rest == "true" { return Some(Lit::Bool(true)); } if rest == "false" { return Some(Lit::Bool(false)); }
    let (neg, body) = match rest.strip_prefix('-') { Some(r) => (true, r.trim_start()), None => (false, rest) };
    if let Some(n) = lua_number(body) { return Some(Lit::Num(if neg { -n } else { n })); }
    if neg { return None; }
    lua_string(rest).map(Lit::Str)
}
/// A numeric string as Lua's arithmetic reads it, or None.
pub(crate) fn coerce_number(it: &Interp, v: Value) -> Option<f64> {
    if !it.is_stringish(v) { return None; }
    let s = String::from_utf8_lossy(it.bytes_of(v)).trim().to_string();
    let (negative, body) = match s.strip_prefix('-') { Some(rest) => (true, rest), None => (false, s.strip_prefix('+').unwrap_or(&s)) };
    lua_number(body).map(|x| if negative { -x } else { x })
}
fn lua_number(s: &str) -> Option<f64> {
    if s.is_empty() { return None; }
    if let Some(h) = s.strip_prefix("0x").or_else(|| s.strip_prefix("0X")) {
        // Hex with an optional fraction and binary exponent.
        let (mant, exp) = match h.find(|c| c == 'p' || c == 'P') { Some(i) => (&h[..i], Some(&h[i + 1..])), None => (h, None) };
        let (ip, fp) = match mant.find('.') { Some(i) => (&mant[..i], &mant[i + 1..]), None => (mant, "") };
        if ip.is_empty() && fp.is_empty() { return None; }
        let mut v = 0f64; for c in ip.chars() { v = v * 16.0 + c.to_digit(16)? as f64; }
        let mut scale = 1.0 / 16.0; for c in fp.chars() { v += c.to_digit(16)? as f64 * scale; scale /= 16.0; }
        if let Some(e) = exp { let e: i32 = e.parse().ok()?; v *= 2f64.powi(e); }
        return Some(v);
    }
    if !s.chars().all(|c| c.is_ascii_digit() || c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') { return None; }
    s.parse::<f64>().ok()
}
fn lua_string(s: &str) -> Option<Vec<u8>> {
    let b = s.as_bytes();
    if b.first() == Some(&b'[') {
        let level = b[1..].iter().take_while(|&&c| c == b'=').count();
        if b.get(1 + level) != Some(&b'[') { return None; }
        let close = format!("]{}]", "=".repeat(level));
        let inner = &s[2 + level..]; let inner = inner.strip_suffix(close.as_str())?;
        let inner = inner.strip_prefix('\n').unwrap_or(inner);
        return Some(inner.as_bytes().to_vec());
    }
    let q = *b.first()?; if q != b'"' && q != b'\'' { return None; }
    if b.len() < 2 || *b.last()? != q { return None; }
    let inner = &b[1..b.len() - 1];
    let mut out = Vec::new(); let mut i = 0;
    while i < inner.len() {
        let c = inner[i];
        // An unescaped newline ends the line, not the string: Lua refuses it.
        if c == q || c == b'\n' || c == b'\r' { return None; }
        if c != b'\\' { out.push(c); i += 1; continue; }
        i += 1; let e = *inner.get(i)?;
        match e {
            b'n' => out.push(b'\n'), b't' => out.push(b'\t'), b'r' => out.push(b'\r'), b'a' => out.push(7), b'b' => out.push(8), b'f' => out.push(12), b'v' => out.push(11),
            b'\\' | b'"' | b'\'' => out.push(e), b'\n' => out.push(b'\n'),
            b'x' => { let h = std::str::from_utf8(inner.get(i + 1..i + 3)?).ok()?; out.push(u8::from_str_radix(h, 16).ok()?); i += 2; }
            b'z' => { while i + 1 < inner.len() && (inner[i + 1] as char).is_whitespace() { i += 1; } }
            b'0'..=b'9' => { let mut n: u32 = 0; let mut k = 0; while k < 3 && i + k < inner.len() && inner[i + k].is_ascii_digit() { n = n * 10 + (inner[i + k] - b'0') as u32; k += 1; } if n > 255 { return None; } out.push(n as u8); i += k - 1; }
            b'u' => { if inner.get(i + 1) != Some(&b'{') { return None; } let end = i + 2 + inner[i + 2..].iter().position(|&c| c == b'}')?; let h = std::str::from_utf8(&inner[i + 2..end]).ok()?; let cp = u32::from_str_radix(h, 16).ok()?; let ch = char::from_u32(cp)?; let mut buf = [0u8; 4]; out.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes()); i = end; }
            _ => return None,
        }
        i += 1;
    }
    Some(out)
}

pub static STATS: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
/// `string.sub` answers with a slice of its subject instead of an interned
/// copy: the plan's `StringSlice` in its boxed form, for the A/B on the lexer.
pub static SLICES: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
const N_0: u32 = 0; // string.byte
const N_1: u32 = 1; // string.sub
const N_2: u32 = 2; // string.find
const N_3: u32 = 3; // string.char
const N_4: u32 = 4; // string.rep
const N_5: u32 = 5; // string.format
const N_6: u32 = 6; // string.gsub
const N_7: u32 = 7; // string.gmatch
const N_8: u32 = 8; // string.len
const N_9: u32 = 9; // string.upper
const N_10: u32 = 10; // string.lower
const N_11: u32 = 11; // string.match
const N_12: u32 = 12; // table.concat
const N_13: u32 = 13; // table.insert
const N_14: u32 = 14; // table.remove
const N_15: u32 = 15; // table.unpack
const N_16: u32 = 16; // math.floor
const N_17: u32 = 17; // math.min
const N_18: u32 = 18; // math.max
const N_19: u32 = 19; // math.abs
const N_20: u32 = 20; // math.huge
const N_21: u32 = 21; // pcall
const N_22: u32 = 22; // pairs
const N_23: u32 = 23; // ipairs
const N_24: u32 = 24; // next
const N_25: u32 = 25; // type
const N_26: u32 = 26; // tostring
const N_27: u32 = 27; // tonumber
const N_28: u32 = 28; // error
const N_29: u32 = 29; // assert
const N_30: u32 = 30; // select
const N_31: u32 = 31; // print
const N_32: u32 = 32; // rawequal
const N_33: u32 = 33; // rawget
const N_34: u32 = 34; // rawset
const N_35: u32 = 35; // setmetatable
const N_36: u32 = 36; // getmetatable
pub(crate) const PCALL: u32 = N_21;
const N_37: u32 = 37; // unpack

/// A builtin's id at compile time, for names past the numbered constants.
pub(crate) const fn const_id(name: &str) -> u32 {
    let mut i = 0;
    while i < NAMES.len() {
        let (a, b) = (NAMES[i].as_bytes(), name.as_bytes());
        if a.len() == b.len() {
            let mut j = 0;
            while j < a.len() && a[j] == b[j] { j += 1; }
            if j == a.len() { return i as u32; }
        }
        i += 1;
    }
    panic!("no such builtin")
}
pub(crate) const XPCALL: u32 = const_id("xpcall");
pub(crate) const STRING_FORMAT: u32 = const_id("string.format");
pub fn id_of(name: &str) -> Option<u32> { NAMES.iter().position(|n| *n == name).map(|i| i as u32) }

/// An error raised by `error`: the value travels as the panic payload.
pub struct LuaError(pub u64);

/// Common result packs stay inline; larger tuples retain every value.
#[derive(Clone)]
pub struct Outs { n: usize, v: [Value; 8], wide: Vec<Value> }
impl Outs {
    pub fn new() -> Outs { Outs { n: 0, v: [Value::NIL; 8], wide: Vec::new() } }
    pub fn push(&mut self, x: Value) {
        if self.n < 8 { self.v[self.n] = x; }
        else { if self.n == 8 { self.wide.extend_from_slice(&self.v); } self.wide.push(x); }
        self.n += 1;
    }
    pub fn len(&self) -> usize { self.n }
    pub fn is_empty(&self) -> bool { self.n == 0 }
    pub fn first(&self) -> Option<&Value> { self.as_slice().first() }
    pub fn iter(&self) -> std::slice::Iter<'_, Value> { self.as_slice().iter() }
    pub fn as_slice(&self) -> &[Value] { if self.n > 8 { &self.wide } else { &self.v[..self.n] } }
    pub fn to_vec(&self) -> Vec<Value> { self.as_slice().to_vec() }
}
impl std::iter::FromIterator<Value> for Outs { fn from_iter<I: IntoIterator<Item = Value>>(it: I) -> Outs { let mut o = Outs::new(); for x in it { o.push(x); } o } }
impl std::ops::Index<usize> for Outs { type Output = Value; fn index(&self, i: usize) -> &Value { &self.as_slice()[i] } }
macro_rules! outs { ($($x:expr),* $(,)?) => {{ let mut o = Outs::new(); $( o.push($x); )* o }} }


/// The path a `nupp.io.files` call names: a string, or a path object (`_text`).
fn path_text(it: &mut Interp, v: Value) -> String {
    if it.is_stringish(v) { return String::from_utf8_lossy(&bytes_of(it, v)).into_owned(); }
    let k = it.intern("_text"); let t = it.get_index_any(v, k);
    if it.is_stringish(t) { String::from_utf8_lossy(&bytes_of(it, t)).into_owned() } else { String::new() }
}
fn kind_name(m: &std::fs::Metadata) -> &'static str { if m.is_dir() { "directory" } else if m.is_file() { "file" } else if m.file_type().is_symlink() { "symlink" } else { "other" } }
/// A path object as `nupp.io.path` makes one: the text behind `_text`, the
/// methods as fields.
fn path_object(it: &mut Interp, text: &str) -> Value {
    let t = it.new_table(); let h = it.register(t);
    let s = it.heap_new_string(text); let k = it.intern("_text"); it.set_index(t, k, s);
    for (name, b) in [("toString", "path.toString"), ("canonicalize", "path.canonicalize")] { let k = it.intern(name); it.set_index(t, k, Value::builtin(id_of(b).unwrap())); }
    it.release(h); t
}
/// The file-system minimum the compiler reads through `nupp.io.files` and
/// `nupp.io.path`, answered by the host directly.
fn files(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    match name {
        "files.createTemporaryFile" | "files.createTemporaryDirectory" => crate::temporary::create(it, name.ends_with("Directory"), arg(args, 0)),
        // The stdlib's line reader over a file this opens: `newLines` takes
        // the handle and closes it with itself.
        "files.lines" => {
            let scope = it.open_scope(); it.handles.extend_from_slice(args);
            let path = path_text(it, arg(args, 0));
            let path = it.heap_new_string(&path); it.handles.push(path);
            let mode = it.intern("r");
            let opened = call(it, id_of("io.open").unwrap(), &[path, mode]);
            if opened[0] == Value::NIL { let why = opened[1]; it.close_scope(scope); return outs![Value::NIL, why]; }
            it.handles.push(opened[0]);
            // An io.Reader answers "" at the end, where a Lua handle answers nil.
            let reader = it.new_table(); it.handles.push(reader);
            let key = it.intern("_file"); it.set_index(reader, key, opened[0]);
            for (name, b) in [("read", "files.readerRead"), ("close", "files.readerClose")] { let k = it.intern(name); it.set_index(reader, k, Value::builtin(id_of(b).unwrap())); }
            let io = it.require("nupp.io"); it.handles.push(io);
            let key = it.intern("newLines");
            let new_lines = it.get_index(io, key);
            let lines = it.call_value(new_lines, &[reader, arg(args, 1)]).first().copied().unwrap_or(Value::NIL);
            it.close_scope(scope);
            outs![lines, Value::NIL]
        }
        "files.readerRead" | "files.readerClose" => {
            let key = it.intern("_file");
            let file = it.get_index(arg(args, 0), key);
            if name == "files.readerClose" { call(it, id_of("file.close").unwrap(), &[file]); return Outs::new(); }
            let read = call(it, id_of("file.read").unwrap(), &[file, arg(args, 1)]);
            if read[0] != Value::NIL { return outs![read[0]]; }
            let why = if read.len() > 1 { read[1] } else { Value::NIL };
            if why == Value::NIL { outs![it.intern("")] } else { outs![Value::NIL, why] }
        }
        "files.read" => {
            let path = path_text(it, arg(args, 0));
            match std::fs::read(path) { Ok(bytes) => outs![it.new_string_bytes(&bytes)], Err(e) => outs![Value::NIL, it.heap_new_string(&e.to_string())] }
        }
        "files.write" => {
            let path = path_text(it, arg(args, 0));
            let mut bytes = arg(args, 1);
            if !it.is_stringish(bytes) {
                let key = it.intern("getString");
                let getter = it.index(bytes, key);
                bytes = it.call_value(getter, &[bytes]).first().copied().unwrap_or(Value::NIL);
            }
            if !it.is_stringish(bytes) { it.err("files.write expects a string or ByteView"); }
            match std::fs::write(path, it.bytes_of(bytes)) {
                Ok(()) => outs![Value::TRUE],
                Err(e) => outs![Value::FALSE, it.heap_new_string(&e.to_string())],
            }
        }
        "files.glob" => {
            let pattern = path_text(it, arg(args, 0));
            match nupp_native_files::glob(&pattern) {
                Ok(paths) => {
                    let result = it.new_table(); let root = it.register(result);
                    for (index, bytes) in paths.into_iter().enumerate() {
                        let path = path_object(it, &String::from_utf8_lossy(&bytes));
                        it.set_index(result, Value::num((index + 1) as f64), path);
                    }
                    it.release(root); outs![result]
                }
                Err(error) => outs![Value::NIL, it.heap_new_string(&error.to_string())],
            }
        }
        "files.info" => {
            let p = path_text(it, arg(args, 0));
            match std::fs::symlink_metadata(&p).and_then(|m| if m.file_type().is_symlink() { std::fs::metadata(&p) } else { Ok(m) }) {
                Ok(m) => { let t = it.new_table(); let h = it.register(t); for (k, v) in [("kind", Value::NIL), ("size", Value::num(m.len() as f64))] { let kv = it.intern(k); let vv = if k == "kind" { it.intern(kind_name(&m)) } else { v }; it.set_index(t, kv, vv); } let mk = it.intern("modified"); let ms = m.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_millis() as f64).unwrap_or(0.0); it.set_index(t, mk, Value::num(ms)); it.release(h); outs![t] }
                Err(e) => { let msg = it.heap_new_string(&format!("{p}: {e}")); outs![Value::NIL, msg] }
            }
        }
        "files.isDirectory" => { let p = path_text(it, arg(args, 0)); outs![Value::boolean(std::fs::metadata(&p).map(|m| m.is_dir()).unwrap_or(false))] }
        "files.isFile" => { let p = path_text(it, arg(args, 0)); outs![Value::boolean(std::fs::metadata(&p).map(|m| m.is_file()).unwrap_or(false))] }
        "files.exists" => { let p = path_text(it, arg(args, 0)); outs![Value::boolean(std::fs::symlink_metadata(&p).is_ok())] }
        "files.list" => {
            let p = path_text(it, arg(args, 0));
            match std::fs::read_dir(&p) {
                Ok(rd) => {
                    let mut names: Vec<(String, &'static str)> = rd.filter_map(|e| e.ok()).map(|e| { let k = e.file_type().map(|t| if t.is_dir() { "directory" } else if t.is_file() { "file" } else if t.is_symlink() { "symlink" } else { "other" }).unwrap_or("other"); (e.file_name().to_string_lossy().into_owned(), k) }).collect();
                    names.sort();
                    let list = it.new_table(); let h = it.register(list);
                    for (i, (n, k)) in names.iter().enumerate() { let e = it.new_table(); let eh = it.register(e); let nk = it.intern("name"); let nv = it.heap_new_string(n); it.set_index(e, nk, nv); let kk = it.intern("kind"); let kv = it.intern(k); it.set_index(e, kk, kv); it.set_index(list, Value::num((i + 1) as f64), e); it.release(eh); }
                    it.release(h); outs![list]
                }
                Err(e) => { let msg = it.heap_new_string(&format!("{p}: {e}")); outs![Value::NIL, msg] }
            }
        }
        "files.createDirectory" | "files.remove" => {
            let p = path_text(it, arg(args, 0));
            if name == "files.remove" && !matches!(arg(args, 1), Value::NIL | Value::TRUE | Value::FALSE) {
                it.err("nupp: io.files recursive must be a boolean");
            }
            let result = if name == "files.createDirectory" {
                std::fs::create_dir_all(&p)
            } else {
                std::fs::symlink_metadata(&p).and_then(|m| {
                    if m.file_type().is_symlink() {
                        // Windows directory links require remove_dir. Neither
                        // operation follows the link into the target tree.
                        #[cfg(windows)]
                        { use std::os::windows::fs::FileTypeExt; if m.file_type().is_symlink_dir() { return std::fs::remove_dir(&p); } }
                        std::fs::remove_file(&p)
                    } else if m.is_dir() {
                        if arg(args, 1).truthy() { std::fs::remove_dir_all(&p) } else { std::fs::remove_dir(&p) }
                    } else {
                        std::fs::remove_file(&p)
                    }
                })
            };
            match result {
                Ok(()) => outs![Value::boolean(true)],
                Err(e) => { let msg = it.heap_new_string(&format!("{p}: {e}")); outs![Value::boolean(false), msg] }
            }
        }
        "path.currentDirectory" => { let cwd = std::env::current_dir().map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| ".".to_string()); outs![path_object(it, &cwd)] }
        "path.newPath" => { let p = path_text(it, arg(args, 0)); outs![path_object(it, &p)] }
        "path.toString" => { let p = path_text(it, arg(args, 0)); outs![str_of(it, p.as_bytes())] }
        "path.canonicalize" => { let p = path_text(it, arg(args, 0)); match std::fs::canonicalize(&p) { Ok(c) => outs![path_object(it, &c.to_string_lossy())], Err(e) => { let msg = it.heap_new_string(&format!("{p}: {e}")); outs![Value::NIL, msg] } } }
        _ => it.err(&format!("{name} is not in this runtime")),
    }
}

fn terminal(name: &str, args: &[Value]) -> Outs {
    use std::io::IsTerminal;
    let fd = int(args, 0, 1) as i32;
    if name == "terminal.isTerminal" {
        let answer = match fd {
            0 => std::io::stdin().is_terminal(),
            1 => std::io::stdout().is_terminal(),
            2 => std::io::stderr().is_terminal(),
            _ => false,
        };
        return outs![Value::boolean(answer)];
    }
    #[cfg(unix)]
    {
        let mut size: libc::winsize = unsafe { std::mem::zeroed() };
        let status = unsafe { libc::ioctl(fd, libc::TIOCGWINSZ, &mut size) };
        if status == 0 && size.ws_col > 0 { return outs![Value::num(size.ws_col as f64)]; }
    }
    outs![Value::NIL]
}

/// The fixed-width intrinsics the `Scalar` opcode carries, by kind; the typed
/// tier lowers them inline, the interpreter calls `scalar_op`.
pub const SCALAR_OPS: [&str; 25] = ["u32.wrap", "u32.add", "u32.sub", "u32.andBits", "u32.orBits", "u32.xorBits", "u32.shiftLeft", "u32.shiftRightLogical", "u32.fromI32", "u32.toI32", "i32.wrap", "i32.add", "i32.sub", "i32.andBits", "i32.orBits", "i32.xorBits", "i32.fromU32", "i32.toU32", "u32.mul", "i32.mul", "u32.notBits", "i32.notBits", "u32.rotateLeft", "u32.rotateRight", "i32.shiftRightArithmetic"];
pub fn scalar_op(kind: u8, a: f64, b: f64) -> f64 {
    let x = (a as i64) as i32; let y = (b as i64) as i32; let sh = (b as i64 as u32) & 31;
    let u = |v: i32| (v as u32) as f64; let s = |v: i32| v as f64;
    match kind {
        0 | 8 => u(x), 9 | 10 | 16 => s(x), 17 => u(x),
        1 => u(x.wrapping_add(y)), 2 => u(x.wrapping_sub(y)), 3 => u(x & y), 4 => u(x | y), 5 => u(x ^ y), 6 => u(x.wrapping_shl(sh)), 7 => u(((x as u32) >> sh) as i32),
        11 => s(x.wrapping_add(y)), 12 => s(x.wrapping_sub(y)), 13 => s(x & y), 14 => s(x | y), 15 => s(x ^ y),
        18 => u(x.wrapping_mul(y)), 19 => s(x.wrapping_mul(y)), 20 => u(!x), 21 => s(!x), 22 => u(x.rotate_left(sh)), 23 => u(x.rotate_right(sh)), 24 => s(x >> sh),
        _ => f64::NAN,
    }
}
/// The i32/u32/f32 intrinsics, with the folder's semantics (`nupp.compiler.scalarintrinsics`).
fn scalar(it: &mut Interp, name: &str, args: &[Value]) -> Outs {
    let (family, op) = name.split_once('.').unwrap();
    let a = crate::numeric::double(it, arg(args, 0));
    let bb = args.get(1).map_or(0.0, |value| crate::numeric::double(it, *value));
    let i32_of = |x: f64| -> i32 { (x as i64) as i32 };
    let u32_of = |x: f64| -> u32 { (x as i64) as u32 };
    let num = |x: f64| Value::num(x);
    if family == "f32" {
        let r = match op {
            "narrow" | "round" => (a as f32) as f64,
            "add" => ((a as f32) + (bb as f32)) as f64, "sub" => ((a as f32) - (bb as f32)) as f64, "mul" => ((a as f32) * (bb as f32)) as f64, "div" => ((a as f32) / (bb as f32)) as f64,
            "sqrt" => (a as f32).sqrt() as f64, "min" | "max" => {
                let (a, b) = (a as f32, bb as f32);
                if a.is_nan() || b.is_nan() { f64::NAN }
                else if a == 0.0 && b == 0.0 { let negative = if op == "min" { a.is_sign_negative() || b.is_sign_negative() } else { a.is_sign_negative() && b.is_sign_negative() }; if negative { -0.0 } else { 0.0 } }
                else if op == "min" { a.min(b) as f64 } else { a.max(b) as f64 }
            },
            "fma" => (a as f32).mul_add(bb as f32, crate::numeric::double(it, arg(args, 2)) as f32) as f64, "exp" => {
                let x = a as f32;
                if x.is_nan() { f64::NAN } else {
                    let y = x.clamp(-104.0, 88.0) * 0.0078125f32;
                    let mut out = 0.0000000020876757f32;
                    for c in [0.000000025052108f32, 0.00000027557319, 0.0000027557319, 0.000024801587, 0.0001984127, 0.0013888889, 0.0083333333, 0.041666667, 0.16666667, 0.5, 1.0, 1.0] { out = out.mul_add(y, c); }
                    for _ in 0..7 { out *= out; } out as f64
                }
            },
            "fromBits" => f32::from_bits(u32_of(a)) as f64, "toBits" => (a as f32).to_bits() as f64,
            _ => it.err(&format!("scalar intrinsic f32.{op} is not in this runtime")),
        };
        return outs![num(r)];
    }
    let signed = family == "i32";
    let out = |x: i32| -> Value { if signed { num(x as f64) } else { num((x as u32) as f64) } };
    let r = match op {
        "wrap" | "fromU32" | "toI32" | "fromI32" | "toU32" => out(i32_of(a)),
        "add" => out(i32_of(a).wrapping_add(i32_of(bb))), "sub" => out(i32_of(a).wrapping_sub(i32_of(bb))), "mul" => out(i32_of(a).wrapping_mul(i32_of(bb))),
        "andBits" => out(i32_of(a) & i32_of(bb)), "orBits" => out(i32_of(a) | i32_of(bb)), "xorBits" => out(i32_of(a) ^ i32_of(bb)), "notBits" => out(!i32_of(a)),
        "shiftLeft" => out(i32_of(a).wrapping_shl(u32_of(bb) & 31)), "shiftRightArithmetic" => out(i32_of(a) >> (u32_of(bb) & 31)), "shiftRightLogical" => out((u32_of(a) >> (u32_of(bb) & 31)) as i32),
        "rotateLeft" => out(i32_of(a).rotate_left(u32_of(bb) & 31)), "rotateRight" => out(i32_of(a).rotate_right(u32_of(bb) & 31)),
        "lessThan" => Value::boolean(if signed { i32_of(a) < i32_of(bb) } else { u32_of(a) < u32_of(bb) }), "lessOrEqual" => Value::boolean(if signed { i32_of(a) <= i32_of(bb) } else { u32_of(a) <= u32_of(bb) }),
        "popcount" => num(u32_of(a).count_ones() as f64), "trailingZeros" => num(u32_of(a).trailing_zeros() as f64), "leadingZeros" => num(u32_of(a).leading_zeros() as f64),
        "div" => num(if u32_of(bb) == 0 { 0.0 } else { (u32_of(a) / u32_of(bb)) as f64 }), "mod" => num(if u32_of(bb) == 0 { 0.0 } else { (u32_of(a) % u32_of(bb)) as f64 }),
        _ => it.err(&format!("scalar intrinsic {family}.{op} is not in this runtime")),
    };
    outs![r]
}


fn bytes_of(it: &Interp, v: Value) -> Vec<u8> {
    if let Some(i) = crate::numeric::integer(v) { return i.magnitude().to_string().into_bytes(); }
    if v.is_num() { return num_text(v.as_num()).into_bytes(); }
    it.bytes_of(v).to_vec()
}
/// The bytes of a string value without a copy; a number is formatted.
fn bytes_ref<'a>(it: &'a Interp, v: Value, scratch: &'a mut Vec<u8>) -> &'a [u8] {
    if let Some(i) = crate::numeric::integer(v) { *scratch = i.magnitude().to_string().into_bytes(); return scratch; }
    if v.is_num() { *scratch = num_text(v.as_num()).into_bytes(); return scratch; }
    it.bytes_of(v)
}
/// Lua's number text: `%.14g`, which integers below 1e14 print as written.
pub fn num_text(n: f64) -> String {
    if n.fract() == 0.0 && n.abs() < 1e14 && !(n == 0.0 && n.is_sign_negative()) { return format!("{}", n as i64); }
    String::from_utf8(c_format(".14", b'g', CArg::F(n))).unwrap_or_default()
}
/// One C conversion, as LuaJIT's `string.format` makes it: `spec` is the
/// flags, width and precision between `%` and the conversion.
#[derive(Clone, Copy)]
pub enum CArg { F(f64), I(i64), U(u64) }
pub fn c_format(spec: &str, conv: u8, value: CArg) -> Vec<u8> {
    let length = match value { CArg::F(_) => "", _ => "ll" };
    let format = std::ffi::CString::new(format!("%{spec}{length}{}", conv as char)).unwrap();
    let mut buffer = vec![0u8; 128];
    loop {
        let written = unsafe { match value {
            CArg::F(x) => libc::snprintf(buffer.as_mut_ptr() as *mut libc::c_char, buffer.len(), format.as_ptr(), x),
            CArg::I(x) => libc::snprintf(buffer.as_mut_ptr() as *mut libc::c_char, buffer.len(), format.as_ptr(), x as libc::c_longlong),
            CArg::U(x) => libc::snprintf(buffer.as_mut_ptr() as *mut libc::c_char, buffer.len(), format.as_ptr(), x as libc::c_ulonglong),
        } };
        if written < 0 { return Vec::new(); }
        if (written as usize) < buffer.len() { buffer.truncate(written as usize); return buffer; }
        buffer.resize(written as usize + 1, 0);
    }
}
// `%g` selects fixed or scientific notation from the rounded exponent.
// Explicit precision is also the portable image writer's round-trip format.
fn str_of(it: &mut Interp, b: &[u8]) -> Value { it.string_of(b) }
fn arg(args: &[Value], i: usize) -> Value { args.get(i).copied().unwrap_or(Value::NIL) }
fn int(args: &[Value], i: usize, default: i64) -> i64 { let v = arg(args, i); if v.is_num() { v.as_num() as i64 } else { default } }
pub(crate) fn type_name(it: &Interp, v: Value) -> &'static str {
    if crate::coroutines::is_coroutine(it,v) {return "thread";}
    if crate::numeric::is_numeric(v) { return "number"; }
    if crate::storage::is_native(v) { return "cdata"; }
    if v == Value::NIL { return "nil"; }
    if v == Value::TRUE || v == Value::FALSE { return "boolean"; }
    if v.as_func().is_some() || v.as_builtin().is_some() { return "function"; }
    match it.kind_of(v) { Some(KIND_STR) | Some(KIND_SLICE) => "string", Some(KIND_TABLE) | Some(KIND_RECORD) => "table", Some(KIND_CLOSURE) | Some(KIND_ITER) => "function", Some(KIND_BYTES) | Some(KIND_STORAGE) => "userdata", Some(_) => "userdata", None => "nil" }
}

/// Lua's `tostring`.
/// Lua's `tostring`, byte for byte: a string's bytes are its text whether or
/// not they are UTF-8.
pub fn tostring(it: &mut Interp, v: Value) -> Vec<u8> {
    if let Some(i) = crate::numeric::integer(v) { return i.magnitude().to_string().into_bytes(); }
    if v.is_num() { return num_text(v.as_num()).into_bytes(); }
    if v == Value::NIL { return b"nil".to_vec(); }
    if v == Value::TRUE { return b"true".to_vec(); }
    if v == Value::FALSE { return b"false".to_vec(); }
    if it.is_stringish(v) { return it.bytes_of(v).to_vec(); }
    let handler = it.meta_field(v, "__tostring");
    if handler != Value::NIL {
        let values = it.call_value(handler, &[v]);
        let text = values.first().copied().unwrap_or(Value::NIL);
        if !it.is_stringish(text) { it.err("__tostring must return a string"); }
        return it.bytes_of(text).to_vec();
    }
    format!("{}: {:#x}", type_name(it, v), v.0).into_bytes()
}

pub static CALLS: std::sync::Mutex<Vec<u64>> = std::sync::Mutex::new(Vec::new());

/// How a builtin id is dispatched, computed once from `NAMES` so a call
/// does no string comparison before its own work.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Special {
    Plain,
    Lpeg,
    Sbuf,
    OsExit,
    DebugTraceback,
    ErrorSite,
    Foreign,
    TasksVm,
    IoStdinRead,
    IoPopen,
    Process,
    Temporary,
    TableMaxn,
    TableClone,
    VmTableappendresults,
    VmClocknow,
    AffineRelease,
    VmEncodeplain,
    VmSavedata,
    VmLoaddata,
    VmDecodeplain,
    VmSavevalue,
    VmLoadvalue,
    VmLoadinto,
    VmSha256,
    VmCdeclarations,
    VmCachedigest,
    VmProcessid,
    UuidUuid4,
    CrcUpdate,
    ClockNow,
    Xpcall,
    IoLines,
    IoType,
    OsDate,
    Collectgarbage,
    SystemAvailableparallelism,
    CryptoRandombytes,
    VmWithinstructionbudget,
    PackagePreloadloader,
    PackageImageloader,
    VmLoadimage,
    VmImageidentity,
    Tail,
}
static SPECIAL: std::sync::OnceLock<Vec<Special>> = std::sync::OnceLock::new();
fn special_of(id: u32) -> Special {
    let table = SPECIAL.get_or_init(|| NAMES.iter().map(|name| classify(*name)).collect());
    table.get(id as usize).copied().unwrap_or(Special::Plain)
}
fn classify(name: &str) -> Special {
    if name.starts_with("foreign.") { return Special::Foreign; }
    if name.starts_with("lpeg.") { return Special::Lpeg; }
    if name.starts_with("sbuf.") { return Special::Sbuf; }
    if name.starts_with("tasks.vm") { return Special::TasksVm; }
    if name == "io.stdin.read" || name == "io.stdout.flush" || name == "io.stderr.flush" || name == "io.flush" || name == "io.stdout.setvbuf" || name == "io.stderr.setvbuf" { return Special::IoStdinRead; }
    if name == "io.popen" { return Special::IoPopen; }
    if name == "os.exit" { return Special::OsExit; }
    if name == "debug.traceback" { return Special::DebugTraceback; }
    if name == "error.site" { return Special::ErrorSite; }
    if name.starts_with("process.") { return Special::Process; }
    if name.starts_with("temporary.") { return Special::Temporary; }
    if name == "table.maxn" { return Special::TableMaxn; }
    if name == "table.clone" || name == "table.clear" { return Special::TableClone; }
    if name == "vm.tableAppendResults" { return Special::VmTableappendresults; }
    if name == "vm.clockNow" || name == "vm.clockWall" || name == "vm.clockSleep" { return Special::VmClocknow; }
    if name == "affine.release" { return Special::AffineRelease; }
    if name == "vm.encodePlain" { return Special::VmEncodeplain; }
    if name == "vm.saveData" { return Special::VmSavedata; }
    if name == "vm.loadData" { return Special::VmLoaddata; }
    if name == "vm.decodePlain" { return Special::VmDecodeplain; }
    if name == "vm.saveValue" { return Special::VmSavevalue; }
    if name == "vm.loadValue" { return Special::VmLoadvalue; }
    if name == "vm.loadInto" { return Special::VmLoadinto; }
    if name == "vm.sha256" { return Special::VmSha256; }
    if name == "vm.cDeclarations" { return Special::VmCdeclarations; }
    if name == "vm.cacheDigest" { return Special::VmCachedigest; }
    if name == "vm.processId" { return Special::VmProcessid; }
    if name == "uuid.uuid4" || name == "uuid.uuid7" { return Special::UuidUuid4; }
    if name == "crc.update" { return Special::CrcUpdate; }
    if name == "clock.now" { return Special::ClockNow; }
    if name == "xpcall" { return Special::Xpcall; }
    if name == "io.lines" { return Special::IoLines; }
    if name == "io.type" { return Special::IoType; }
    if name == "os.date" { return Special::OsDate; }
    if name == "collectgarbage" { return Special::Collectgarbage; }
    if name == "system.availableParallelism" { return Special::SystemAvailableparallelism; }
    if name == "crypto.randomBytes" { return Special::CryptoRandombytes; }
    if name == "vm.withInstructionBudget" { return Special::VmWithinstructionbudget; }
    if name == "package.preloadLoader" { return Special::PackagePreloadloader; }
    if name == "package.imageLoader" { return Special::PackageImageloader; }
    if name == "vm.loadImage" { return Special::VmLoadimage; }
    if name == "vm.imageIdentity" { return Special::VmImageidentity; }
    if name.starts_with("simd.") || name.starts_with("storage.") || name.starts_with("wide.") || name.starts_with("scalar.u64.")
        || matches!(name, "math.sin" | "math.cos" | "math.tan" | "math.asin" | "math.acos" | "math.atan" | "math.atan2" | "math.exp" | "math.ldexp")
        || name.starts_with("files.") || name.starts_with("path.") || name.starts_with("nfiles.") || name.starts_with("ncompression.") || name.starts_with("nnet.") || name.starts_with("nhttp.") || name == "nuri.parse" || name.starts_with("utf8.") || name.starts_with("terminal.") || name.starts_with("scalar.") { return Special::Tail; }
    Special::Plain
}

pub fn call(it: &mut Interp, id: u32, args: &[Value]) -> Outs {
    // Supervision is synchronous, including affine cleanup invoked directly
    // through the builtin path rather than a scheduled bytecode call.
    let special = special_of(id);
    match special {
        Special::Foreign => {
            let name = NAMES[id as usize];
            return crate::foreign::call(it, name, args);
        }
        Special::Lpeg => return crate::lpeg::call(it, NAMES[id as usize], args),
        Special::Sbuf => return crate::strbuf::call(it, NAMES[id as usize], args),
        Special::TasksVm => {
            let name = NAMES[id as usize];
            return match crate::task_api::call(it, 0, name, args) {
                crate::task_api::Answer::Values(values) => values.into_iter().collect(),
                _ => unreachable!("supervision cannot suspend its caller"),
            };
        }
        Special::IoStdinRead => {
            return crate::stdio::call(it, NAMES[id as usize], args);
        }
        Special::IoPopen => {
            return crate::process::popen(it, args);
        }
        Special::ErrorSite => {
            // `error(message, level)` as the lowering spells it: the error
            // function the call named, the call's line, then the arguments.
            // A replaced `error` is called as written.
            let callee = arg(args, 0);
            if callee != Value::builtin(id_of("error").unwrap()) { return it.call_outs(callee, &args[2.min(args.len())..]); }
            let message = arg(args, 2);
            let level = match arg(args, 3) { v if v == Value::NIL => 1, v if v.is_num() => v.as_num() as i64, _ => 1 };
            let mut raised = message;
            if level > 0 && (it.is_stringish(message) || message.is_num()) {
                let site = if level == 1 { it.caller_function().map(|fid| (fid, arg(args, 1).as_num() as u32)) } else { it.caller_line(level as usize - 1) };
                if let Some((fid, line)) = site.filter(|&(_, line)| line != 0) {
                    let mut text = format!("{}:{}: ", it.chunk_id(fid), line).into_bytes();
                    text.extend(tostring(it, message));
                    raised = it.string_of(&text);
                }
            }
            std::panic::panic_any(LuaError(raised.0))
        }
        Special::DebugTraceback => {
            // `debug.traceback([thread,] [message [, level]])`. A message that is
            // neither a string nor nil is answered unchanged, as Lua does. The
            // frames are the calling task's; a handler of `xpcall` runs after
            // the unwind, so it sees the protected call's caller.
            let first = arg(args, 0);
            let plain = |it: &Interp, v: Value| v == Value::NIL || v.is_num() || it.is_stringish(v);
            let message = if args.len() >= 2 && !plain(it, first) && plain(it, arg(args, 1)) { arg(args, 1) } else { first };
            if message != Value::NIL && !it.is_stringish(message) && !message.is_num() { return outs![message]; }
            let mut text = if message == Value::NIL { String::new() } else if message.is_num() { num_text(message.as_num()) } else { String::from_utf8_lossy(it.bytes_of(message)).into_owned() };
            if !text.is_empty() { text.push('\n'); }
            text.push_str("stack traceback:");
            if let Some(tid) = it.caller_task() {
                for line in it.backtrace(tid).lines() { text.push_str("\n\t"); text.push_str(line.trim_start()); }
            }
            return outs![it.heap_new_string(&text)];
        }
        Special::OsExit => {
            // Lua's spelling: true or nothing succeeds, false fails, a number is
            // the status. Every write has already been flushed.
            let code = arg(args, 0);
            let status = if code == Value::NIL || code == Value::TRUE { 0 }
                else if code == Value::FALSE { 1 }
                else if code.is_num() { code.as_num() as i32 }
                else { it.err("bad argument #1 to 'exit' (number expected)") };
            std::process::exit(status);
        }
        Special::Process => {
            let name = NAMES[id as usize];
            return crate::process::call(it, name, args);
        }
        Special::Temporary => {
            let name = NAMES[id as usize];
            return crate::temporary::call(it, name, args);
        }
        Special::TableMaxn => {
            let table = arg(args, 0);
            let max = it.table_keys(table).into_iter().filter(|k| k.is_num() && it.get_index(table, *k) != Value::NIL).map(Value::as_num).fold(0.0, f64::max);
            return outs![Value::num(max)];
        }
        Special::TableClone => {
            let source = arg(args, 0);
            if !matches!(it.kind_of(source), Some(KIND_TABLE | KIND_RECORD)) || crate::storage::is_native(source) {
                it.err("table operation expects a table");
            }
            if NAMES[id as usize] == "table.clear" {
                for key in it.table_keys(source) { it.set_index(source, key, Value::NIL); }
                return Outs::new();
            }
            let copy = it.new_table();
            let root = it.register(copy);
            for key in it.table_keys(source) {
                it.set_index(copy, key, it.get_index(source, key));
            }
            let mut meta = it.metatable_of(source);
            if meta != Value::NIL {
                if let Some(key) = it.heap.intern_lookup("__metatable") {
                    let protected = it.get_index(meta, key);
                    if protected != Value::NIL { meta = protected; }
                }
            }
            if matches!(it.kind_of(meta), Some(KIND_TABLE | KIND_RECORD)) && !crate::storage::is_native(meta) {
                it.set_metatable(copy, meta);
            }
            it.release(root);
            return outs![copy];
        }
        Special::VmTableappendresults => {
            let table = arg(args, 0);
            let start = arg(args, 1).as_num();
            for (offset, value) in args.iter().skip(2).enumerate() { it.set_index(table, Value::num(start + offset as f64), *value); }
            return Outs::new();
        }
        Special::VmClocknow => {
            return crate::clock::call(it, NAMES[id as usize], args);
        }
        Special::AffineRelease => {
            let body=it.affine_take_drop(arg(args,0)); if body!=Value::NIL { return it.call_outs(body,args); } return Outs::new();
        }
        _ => {}
    }
    // A host service reached from a frame that cannot park: compiled code
    // without a frame record, or a native caller. Contracts 6.2 and 6.4.
    if id >= crate::host::HOST_BASE {it.err("host service called from a frame that cannot park"); }
    if STATS.load(std::sync::atomic::Ordering::Relaxed) {let mut c = CALLS.lock().unwrap(); if c.len() < NAMES.len() { c.resize(NAMES.len(), 0); } c[id as usize] += 1; }
    match special {
        Special::VmEncodeplain => {
            let bytes = crate::persist::save_plain(it, arg(args, 0)).unwrap_or_else(|e| it.err(&e));
            return outs![it.new_string_bytes(&bytes)];
        }
        Special::VmSavedata => {
            let bytes = crate::persist::save_data(it, arg(args, 0)).unwrap_or_else(|e| it.err(&e));
            return outs![it.new_string_bytes(&bytes)];
        }
        Special::VmLoaddata => {
            let bytes = bytes_of(it, arg(args, 0));
            let value = crate::persist::load_data(it, &bytes).unwrap_or_else(|e| it.err(&e));
            return outs![value];
        }
        Special::VmDecodeplain => {
            let bytes = bytes_of(it, arg(args, 0));
            let value = crate::persist::load_plain(it, &bytes).unwrap_or_else(|e| it.err(&e));
            return outs![value];
        }
        Special::VmSavevalue => {
            let policies = crate::persist::policies_from_value(it, arg(args, 1)).unwrap_or_else(|e| it.err(&e));
            let bytes = crate::persist::save_graph(it, &[arg(args, 0)], &policies).unwrap_or_else(|e| it.err(&e));
            return outs![it.new_string_bytes(&bytes)];
        }
        Special::VmLoadvalue => {
            let data = bytes_of(it, arg(args, 0));
            let expected = if arg(args, 1) != Value::NIL {
                let name = String::from_utf8_lossy(&bytes_of(it, arg(args, 1))).into_owned();
                Some(crate::heap::SlotTy::Record(it.heap.shapes.iter().position(|s| s.name == name).unwrap_or_else(|| it.err("unknown requested shape")) as u32))
            } else { None };
            let policies = crate::persist::policies_from_value(it, arg(args, 2)).unwrap_or_else(|e| it.err(&e));
            let roots = crate::persist::load_graph(it, &data, &policies, expected).unwrap_or_else(|e| it.err(&e));
            if roots.len() != 1 { it.err("saveValue payload must have exactly one root"); }
            return outs![roots[0]];
        }
        Special::VmLoadinto => {
            let data = bytes_of(it, arg(args, 0));
            let policies = crate::persist::policies_from_value(it, arg(args, 2)).unwrap_or_else(|e| it.err(&e));
            let value = crate::persist::load_into(it, &data, arg(args, 1), &policies).unwrap_or_else(|e| it.err(&e));
            return outs![value];
        }
        Special::VmSha256 => {
            use sha2::Digest;
            let bytes = bytes_of(it, arg(args, 0));
            if bytes.len() > 0x7fff_ffff { it.err("nupp: SHA-256 input is too long"); }
            let digest = sha2::Sha256::digest(&bytes);
            let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
            return outs![it.heap_new_string(&hex)];
        }
        Special::VmCdeclarations => {
            #[cfg(feature = "c-headers")]
            {
                let request = String::from_utf8_lossy(it.bytes_of(arg(args, 0))).into_owned();
                let response = crate::cdecl::request(&mut it.c_declarations, &request);
                if it.c_declarations.is_some() {
                    if let Some(&module) = it.loaded.get("nupp.compiler.nativecdecl") { it.resources.insert(module, "nupp.compiler.c-declarations".into()); }
                }
                return outs![it.heap_new_string(&response)];
            }
            #[cfg(not(feature = "c-headers"))]
            { it.err("C declaration inspection requires the c-headers runtime feature") }
        }
        Special::VmCachedigest => {
            let digest = nupp_native_platform::cache_digest(it.bytes_of(arg(args, 0))); return outs![it.new_string_bytes(&digest)];
        }
        Special::VmProcessid => {
            return outs![Value::num(std::process::id() as f64)];
        }
        Special::VmImageidentity => {
            // The digest of the image this VM was started from, which is the code
            // a cache stamp has to name: the sources it was lowered from may have
            // moved on since. Images `vm.loadImage` adds later are not part of it.
            let digest = match it.code_events.first() {
                Some(crate::persist::CodeEvent::Image(text)) => Some(nupp_native_platform::cache_digest(text.as_bytes())),
                _ => None,
            };
            return match digest { Some(digest) => outs![it.new_string_bytes(&digest)], None => outs![Value::NIL] };
        }
        Special::UuidUuid4 => {
            let name = NAMES[id as usize];
            let value = if name == "uuid.uuid4" { nupp_native_platform::uuid4() } else { nupp_native_platform::uuid7() };
            return outs![it.heap_new_string(&value.unwrap_or_else(|e| it.err(&e)))];
        }
        Special::CrcUpdate => {
            let id = crate::numeric::double(it, arg(args, 0));
            if !(1.0..=4.0).contains(&id) || id.fract() != 0.0 { it.err("unknown CRC algorithm"); }
            let state = if arg(args, 1) == Value::NIL { None } else { Some(crate::numeric::bits(it, arg(args, 1), true)) };
            let bytes = crate::storage::borrowed_bytes(it, arg(args, 2), arg(args, 3));
            let [state, snapshot] = nupp_crc::update(id as u32, state, bytes).unwrap_or_else(|e| it.err(e));
            let scope = it.open_scope();
            let state = it.box_integer(crate::numeric::Integer { bits: state, unsigned: true }); it.handles.push(state);
            let snapshot = it.box_integer(crate::numeric::Integer { bits: snapshot, unsigned: true });
            let result = outs![state, snapshot];
            it.close_scope(scope);
            return result;
        }
        Special::ClockNow => {
            let millis = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default().as_secs_f64() * 1000.0;
            return outs![Value::num(millis)];
        }
        Special::Xpcall => {
            let scope = it.open_scope(); it.handles.extend_from_slice(args);
            let values = it.pcall_values(arg(args, 0), &args[2.min(args.len())..]);
            it.handles.extend_from_slice(&values);
            let result = if values[0].truthy() { values.into_iter().collect() } else {
                let handled = it.pcall_values(arg(args, 1), &[values[1]]);
                if handled[0].truthy() { outs![Value::FALSE, handled.get(1).copied().unwrap_or(Value::NIL)] }
                else { outs![Value::FALSE, it.intern("error in error handling")] }
            };
            it.close_scope(scope);
            return result;
        }
        Special::IoLines => {
            let scope = it.open_scope(); it.handles.extend_from_slice(args);
            let path = arg(args, 0);
            let file = if path == Value::NIL { Value::NIL } else {
                let opened = call(it, id_of("io.open").unwrap(), &[path]);
                if opened[0] == Value::NIL { let error = String::from_utf8_lossy(it.bytes_of(opened[1])).into_owned(); it.err(&error); }
                opened[0]
            };
            it.handles.push(file);
            let format = if arg(args, 1) == Value::NIL { it.intern("*l") } else { arg(args, 1) };
            let iter = it.new_iter(if file == Value::NIL { 6 } else { 5 }, file, format);
            it.close_scope(scope);
            return outs![iter];
        }
        Special::IoType => {
            let value = arg(args, 0);
            if !matches!(it.kind_of(value), Some(KIND_TABLE | KIND_RECORD)) { return outs![Value::NIL]; }
            let scope = it.open_scope(); it.handles.push(value);
            let mut known = false;
            let io = it.loaded["io"];
            for name in ["stdin", "stdout", "stderr"] { let key = it.intern(name); known |= it.get_index(io, key) == value; }
            let key = it.intern("_data"); known |= it.is_stringish(it.get_index(value, key));
            let native = crate::fileio::is_native(it, value); known |= native;
            let key = it.intern("_processPipe"); let pipe = it.get_index(value, key) == Value::TRUE; known |= pipe;
            let key = it.intern("_closed");
            let closed = it.get_index(value, key) == Value::TRUE || native && !it.native_files.contains_key(&value) || pipe && !it.resources.contains_key(&value);
            let result = if known { it.intern(if closed { "closed file" } else { "file" }) } else { Value::NIL };
            it.close_scope(scope);
            return outs![result];
        }
        Special::OsDate => {
            return crate::datetime::date(it, args);
        }
        Special::Collectgarbage => {
            let mode = arg(args, 0);
            let mode = if mode == Value::NIL { "collect" } else {
                if !it.is_stringish(mode) { it.err("collector option must be a string"); }
                std::str::from_utf8(it.bytes_of(mode)).unwrap_or("")
            };
            return match mode {
                "collect" => { let scope = it.open_scope(); it.handles.extend_from_slice(args); it.clear_dead_registers(); it.full_cycle(); it.close_scope(scope); outs![Value::num(0.0)] }
                "count" => outs![Value::num(it.heap.live_bytes as f64 / 1024.0)],
                "stop" => { it.heap.automatic_collection = false; outs![Value::num(0.0)] }
                "restart" => { it.heap.automatic_collection = true; outs![Value::num(0.0)] }
                "isrunning" => outs![Value::boolean(it.heap.automatic_collection)],
                _ => it.err("unsupported collector option"),
            };
        }
        Special::SystemAvailableparallelism => {
            return outs![Value::num(std::thread::available_parallelism().map_or(1, usize::from) as f64)];
        }
        Special::CryptoRandombytes => {
            let value = arg(args, 0);
            if !value.is_num() || !value.as_num().is_finite() || value.as_num().fract() != 0.0 || !(0.0..=1048576.0).contains(&value.as_num()) { it.err("random byte count must be an integer between 0 and 1048576"); }
            let mut bytes = vec![0; value.as_num() as usize];
            if !bytes.is_empty() { nupp_native_platform::random_bytes(&mut bytes).unwrap_or_else(|e| it.err(&e)); }
            return outs![it.new_string_bytes(&bytes)];
        }
        Special::VmWithinstructionbudget => {
            let limit = arg(args, 1);
            if !limit.is_num() || !limit.as_num().is_finite() || limit.as_num() < 1.0 || limit.as_num().fract() != 0.0 { it.err("instruction limit must be a positive integer"); }
            let previous = it.execution_limit;
            it.execution_limit = Some(previous.unwrap_or(usize::MAX).min(limit.as_num() as usize));
            let before = it.execution_limit.unwrap();
            let scope = it.open_scope(); it.handles.extend_from_slice(args);
            let ntasks = it.tasks.len();
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| it.call_value(arg(args, 0), &args[2..])));
            let remaining = it.execution_limit.unwrap();
            it.execution_limit = previous.map(|n| n.saturating_sub(before - remaining));
            it.tasks.truncate(ntasks);
            it.close_scope(scope);
            return match result { Ok(values) => values.into_iter().collect(), Err(error) => std::panic::resume_unwind(error) };
        }
        Special::PackagePreloadloader => {
            let package = it.loaded["package"]; let k = it.intern("preload"); let preload = it.get_index(package, k);
            return outs![it.get_index(preload, arg(args, 0))];
        }
        Special::PackageImageloader => {
            let name = String::from_utf8_lossy(it.bytes_of(arg(args, 0))).into_owned();
            if let Some(fid) = it.modules.get(&name) { return outs![Value::func(*fid)]; }
            if let Some(value) = it.loaded.get(&name).copied() {
                let cell = it.new_cell(value); let root = it.register(cell);
                let closure = it.new_closure(it.literal_fid, &[cell]); it.release(root);
                return outs![closure];
            }
            return outs![Value::NIL];
        }
        Special::VmLoadimage => {
            if it.jit_threshold != 0 || it.entries.iter().any(|&p| p != 0) { it.err("dynamic image loading currently requires the interpreter"); }
            let bytes = bytes_of(it, arg(args, 0));
            let text = std::str::from_utf8(&bytes).unwrap_or_else(|_| it.err("image is not UTF-8"));
            let entry = crate::image::load(it, text).unwrap_or_else(|e| it.err(&e));
            it.entries.resize(it.funcs.len(), 0);
            if it.threaded { it.prepare_threaded(); }
            return outs![Value::func(entry)];
        }
        Special::Tail => {
            let name = &NAMES[id as usize];
            if let Some(op) = name.strip_prefix("simd.") { return outs![crate::simd::call(it, op, args)]; }
            if let Some(op) = name.strip_prefix("storage.") { return outs![crate::storage::call(it, op, args)]; }
            if let Some(op) = name.strip_prefix("wide.") { return outs![crate::numeric::wide_call(it, op, args)]; }
            if let Some(op) = name.strip_prefix("scalar.u64.") {
                let op = match op { "andBits" => "and", "rotateLeft" => "rol", "rotateRight" => "ror", other => other };
                return outs![crate::numeric::wide_call(it, &format!("u64.{op}"), args)];
            }
            if matches!(*name, "math.sin" | "math.cos" | "math.tan" | "math.asin" | "math.acos" | "math.atan" | "math.atan2" | "math.exp" | "math.ldexp") {
                let a = crate::numeric::double(it, arg(args, 0));
                let v = match *name {
                    "math.sin" => a.sin(), "math.cos" => a.cos(), "math.tan" => a.tan(),
                    "math.asin" => a.asin(), "math.acos" => a.acos(), "math.atan" => a.atan(),
                    "math.atan2" => a.atan2(crate::numeric::double(it, arg(args, 1))), "math.exp" => a.exp(),
                    _ => crate::numeric::scale_power_of_two(a, crate::numeric::double(it, arg(args, 1)) as i32),
                };
                return outs![Value::num(v)];
            }
            if name.starts_with("files.") || name.starts_with("path.") { return files(it, name, args); }
            if name.starts_with("nfiles.") { return crate::nfiles::call(it, name, args); }
            if name.starts_with("ncompression.") { return crate::ncompression::call(it, name, args); }
            if name.starts_with("nnet.") { return crate::nnet::call(it, name, args); }
            if name.starts_with("nhttp.") { return crate::nhttp::call(it, name, args); }
            if *name == "nuri.parse" { return crate::nhttp::parse_uri(it, args); }
            if name.starts_with("utf8.") { return crate::utf8lib::call(it, name, args); }
            if name.starts_with("terminal.") { return terminal(name, args); }
            if let Some(op) = name.strip_prefix("scalar.") { return scalar(it, op, args); }
        }
        _ => {}
    }
    match id {
        N_0 => {
            let mut scratch = Vec::new(); let s = bytes_ref(it, arg(args, 0), &mut scratch); let n = s.len() as i64;
            let mut i = int(args, 1, 1); let mut j = int(args, 2, i);
            if i < 0 { i += n + 1; } if j < 0 { j += n + 1; }
            if i < 1 { i = 1; } if j > n { j = n; }
            if i > j { return Outs::new(); }
            (i..=j).map(|k| Value::num(s[(k - 1) as usize] as f64)).collect()
        }
        N_1 => {
            let out = { let mut scratch = Vec::new(); let s = bytes_ref(it, arg(args, 0), &mut scratch); let n = s.len() as i64;
            let mut i = int(args, 1, 1); let mut j = int(args, 2, -1);
            if i < 0 { i += n + 1; } if j < 0 { j += n + 1; }
            if i < 1 { i = 1; } if j > n { j = n; }
            if SLICES.load(std::sync::atomic::Ordering::Relaxed) && i <= j && !arg(args, 0).is_num() { let src = arg(args, 0); let v = it.new_slice(src, (i - 1) as u32, (j - i + 1) as u32); return outs![v]; }
            if i > j { Vec::new() } else { s[(i - 1) as usize..j as usize].to_vec() } };
            outs![str_of(it, &out)]
        }
        N_8 => { let mut scratch = Vec::new(); let n = bytes_ref(it, arg(args, 0), &mut scratch).len(); outs![Value::num(n as f64)] }
        N_3 => { let b: Vec<u8> = args.iter().map(|v| v.as_num() as i64 as u8).collect(); outs![str_of(it, &b)] }
        N_4 => { let s = bytes_of(it, arg(args, 0)); let n = int(args, 1, 0).max(0) as usize; let sep = if args.len() > 2 { bytes_of(it, arg(args, 2)) } else { Vec::new() }; let mut out = Vec::new(); for k in 0..n { if k > 0 { out.extend_from_slice(&sep); } out.extend_from_slice(&s); } outs![str_of(it, &out)] }
        N_9 => { let s = bytes_of(it, arg(args, 0)); let o: Vec<u8> = s.iter().map(|b| b.to_ascii_uppercase()).collect(); outs![str_of(it, &o)] }
        N_10 => { let s = bytes_of(it, arg(args, 0)); let o: Vec<u8> = s.iter().map(|b| b.to_ascii_lowercase()).collect(); outs![str_of(it, &o)] }
        N_2 | N_11 => {
            let find = id == N_2;
            let pat = bytes_of(it, arg(args, 1));
            let plain = arg(args, 3).truthy();
            if find && (plain || !pat.iter().any(|c| b"^$*+?.([%-".contains(c))) {
                // A plain search borrows the subject; nothing is copied.
                let mut scratch = Vec::new(); let s = bytes_ref(it, arg(args, 0), &mut scratch); let n = s.len() as i64;
                let mut init = int(args, 2, 1); if init < 0 { init += n + 1; } if init < 1 { init = 1; }
                if init > n + 1 { init = n + 1; }
                let start = (init - 1) as usize;
                if pat.is_empty() { return outs![Value::num(init as f64), Value::num((init - 1) as f64)]; }
                let hit = if pat.len() == 1 { s[start..].iter().position(|&c| c == pat[0]) } else { s[start..].windows(pat.len()).position(|w| w == &pat[..]) };
                match hit { Some(k) => outs![Value::num((start + k + 1) as f64), Value::num((start + k + pat.len()) as f64)], None => outs![Value::NIL] }
            } else {
                let s = bytes_of(it, arg(args, 0)); let n = s.len() as i64;
                let mut init = int(args, 2, 1); if init < 0 { init += n + 1; } if init < 1 { init = 1; }
                if init > n + 1 { init = n + 1; }
                match pattern::find(&s, &pat, (init - 1) as usize) {
                    Some((a, b, caps)) => {
                        let scope = it.open_scope();
                        let mut out = Outs::new();
                        if find { out.push(Value::num((a + 1) as f64)); out.push(Value::num(b as f64)); }
                        if caps.is_empty() && !find { out.push(str_of(it, &s[a..b])); }
                        for c in caps { let value = match c { pattern::Cap::Pos(p) => Value::num((p + 1) as f64), pattern::Cap::Span(x, y) => str_of(it, &s[x..y]) }; it.handles.push(value); out.push(value); }
                        it.close_scope(scope);
                        out
                    }
                    None => outs![Value::NIL],
                }
            }
        }
        N_7 => { let s = arg(args, 0); let p = arg(args, 1); outs![it.new_iter(3, s, p)] }
        N_6 => {
            let s = bytes_of(it, arg(args, 0)); let pat = bytes_of(it, arg(args, 1)); let repl = arg(args, 2);
            let max = if args.len() > 3 && arg(args, 3).is_num() { int(args, 3, i64::MAX) } else { i64::MAX };
            let anchored = pat.first() == Some(&b'^');
            let mut out = Vec::new(); let mut pos = 0usize; let mut count = 0i64;
            while pos <= s.len() && count < max {
                match pattern::match_at(&s, &pat, pos) {
                    Some((end, caps)) => {
                        count += 1;
                        let whole = &s[pos..end];
                        let scope = it.open_scope();
                        let mut cap_values = Vec::new();
                        if caps.is_empty() { let value = str_of(it, whole); it.handles.push(value); cap_values.push(value); }
                        else { for c in &caps { let value = match c { pattern::Cap::Pos(p) => Value::num((*p + 1) as f64), pattern::Cap::Span(x, y) => str_of(it, &s[*x..*y]) }; it.handles.push(value); cap_values.push(value); } }
                        let replacement = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| -> Option<Vec<u8>> { if repl.is_num() || it.is_stringish(repl) {
                            let r = bytes_of(it, repl); let mut o = Vec::new(); let mut i = 0;
                            while i < r.len() { if r[i] == b'%' && i + 1 < r.len() { let c = r[i + 1]; if c == b'%' { o.push(b'%'); } else if c.is_ascii_digit() { let k = (c - b'0') as usize; if k == 0 { o.extend_from_slice(whole); } else if let Some(v) = cap_values.get(k - 1) { o.extend_from_slice(&bytes_of(it, *v)); } } i += 2; } else { o.push(r[i]); i += 1; } }
                            Some(o)
                        } else if matches!(it.kind_of(repl), Some(KIND_TABLE | KIND_RECORD)) {
                            let v = it.index(repl, cap_values[0]); if v == Value::NIL || v == Value::FALSE { None } else { Some(bytes_of(it, v)) }
                        } else {
                            let res = it.call_value(repl, &cap_values); let v = res.first().copied().unwrap_or(Value::NIL); if v == Value::NIL || v == Value::FALSE { None } else { Some(bytes_of(it, v)) }
                        } }));
                        it.close_scope(scope);
                        let replacement = match replacement { Ok(value) => value, Err(error) => std::panic::resume_unwind(error) };
                        match replacement { Some(r) => out.extend_from_slice(&r), None => out.extend_from_slice(whole) }
                        if end > pos { pos = end; } else { if pos < s.len() { out.push(s[pos]); } pos += 1; }
                    }
                    None => { if pos < s.len() { out.push(s[pos]); } pos += 1; }
                }
                if anchored { break; }
            }
            if pos < s.len() { out.extend_from_slice(&s[pos..]); }
            outs![str_of(it, &out), Value::num(count as f64)]
        }
        N_5 => {
            let fmt = bytes_of(it, arg(args, 0)); let mut out = Vec::new(); let mut ai = 1; let mut i = 0;
            while i < fmt.len() {
                if fmt[i] != b'%' { out.push(fmt[i]); i += 1; continue; }
                i += 1; if i >= fmt.len() { break; }
                if fmt[i] == b'%' { out.push(b'%'); i += 1; continue; }
                let start = i; while i < fmt.len() && b"-+ #0123456789.".contains(&fmt[i]) { i += 1; }
                let spec = String::from_utf8_lossy(&fmt[start..i]).to_string(); let conv = fmt[i]; i += 1;
                let v = arg(args, ai); ai += 1;
                let (width, zero, left, prec) = parse_spec(&spec);
                // Numeric conversions are C's, flags and all; the rest pad here.
                let integer = |it: &mut Interp, v: Value| crate::numeric::integer(v).map(|i| i.bits as i64).unwrap_or_else(|| crate::numeric::double(it, v) as i64);
                let numeric: Option<Vec<u8>> = match conv {
                    b'd' | b'i' => Some(match crate::numeric::integer(v) { Some(i) if i.unsigned => c_format(&spec, b'u', CArg::U(i.bits)), _ => c_format(&spec, b'd', CArg::I(integer(it, v))) }),
                    b'u' | b'x' | b'X' | b'o' => Some(c_format(&spec, conv, CArg::U(crate::numeric::integer(v).map(|i| i.bits).unwrap_or_else(|| crate::numeric::double(it, v) as i64 as u64)))),
                    b'f' | b'F' | b'e' | b'E' | b'g' | b'G' | b'a' | b'A' => Some(c_format(&spec, conv, CArg::F(crate::numeric::double(it, v)))),
                    _ => None,
                };
                if let Some(text) = numeric { out.extend_from_slice(&text); continue; }
                let body: Vec<u8> = match conv {
                    b's' => { let t = tostring(it, v); match prec { Some(p) => t[..t.len().min(p)].to_vec(), None => t } }
                    // LuaJIT's spelling: a newline continues the literal, a
                    // control byte is its decimal code, three digits before a digit.
                    b'q' => {
                        let t = bytes_of(it, v); let mut q = vec![b'"'];
                        for (k, &c) in t.iter().enumerate() {
                            match c {
                                b'"' => q.extend_from_slice(b"\\\""), b'\\' => q.extend_from_slice(b"\\\\"), b'\n' => q.extend_from_slice(b"\\\n"),
                                c if c < 32 || c == 127 => { let digit = t.get(k + 1).is_some_and(|d| d.is_ascii_digit()); q.extend_from_slice(if digit { format!("\\{c:03}") } else { format!("\\{c}") }.as_bytes()) }
                                c => q.push(c),
                            }
                        }
                        q.push(b'"'); q
                    }
                    b'c' => vec![v.as_num() as u8],
                    other => panic!("runtime error: invalid option '%{}' to 'format'", other as char),
                };
                let pad = width.saturating_sub(body.len());
                if left { out.extend_from_slice(&body); out.extend(std::iter::repeat(b' ').take(pad)); }
                else { out.extend(std::iter::repeat(if zero { b'0' } else { b' ' }).take(pad)); out.extend_from_slice(&body); }
            }
            outs![str_of(it, &out)]
        }
        N_12 => {
            let t = arg(args, 0); let sep = if args.len() > 1 && arg(args, 1) != Value::NIL { bytes_of(it, arg(args, 1)) } else { Vec::new() };
            let n = it.array_len(t) as i64; let i = int(args, 2, 1); let j = int(args, 3, n);
            let mut out = Vec::new();
            for k in i..=j { if k > i { out.extend_from_slice(&sep); } let v = it.get_index(t, Value::num(k as f64)); if !(crate::numeric::is_numeric(v) || type_name(it, v) == "string") { panic!("runtime error: invalid value (at index {k}) in table for 'concat'"); } out.extend_from_slice(&bytes_of(it, v)); }
            outs![str_of(it, &out)]
        }
        N_13 => {
            let t = arg(args, 0); let n = it.array_len(t) as i64;
            if args.len() >= 3 { let pos = int(args, 1, n + 1); let v = arg(args, 2); for k in (pos..=n).rev() { let x = it.get_index(t, Value::num(k as f64)); it.set_index(t, Value::num((k + 1) as f64), x); } it.set_index(t, Value::num(pos as f64), v); }
            else { it.set_index(t, Value::num((n + 1) as f64), arg(args, 1)); }
            Outs::new()
        }
        N_14 => {
            let t = arg(args, 0); let n = it.array_len(t) as i64; if n == 0 { return Outs::new(); }
            let pos = int(args, 1, n); let v = it.get_index(t, Value::num(pos as f64));
            for k in pos..n { let x = it.get_index(t, Value::num((k + 1) as f64)); it.set_index(t, Value::num(k as f64), x); }
            it.set_index(t, Value::num(n as f64), Value::NIL); it.pop_array(t);
            outs![v]
        }
        N_15 | N_37 => { let t = arg(args, 0); let n = it.array_len(t) as i64; let i = int(args, 1, 1); let j = int(args, 2, n); (i..=j).map(|k| it.get_index(t, Value::num(k as f64))).collect() }
        N_16 => { let v = arg(args, 0); outs![if crate::numeric::integer(v).is_some() { v } else { Value::num(crate::numeric::double(it, v).floor()) }] }
        N_19 => { let v = arg(args, 0); outs![if let Some(i) = crate::numeric::integer(v) { if i.magnitude() < 0 { it.box_integer(crate::numeric::Integer { bits: i.bits.wrapping_neg(), unsigned: i.unsigned }) } else { v } } else { Value::num(crate::numeric::double(it, v).abs()) }] }
        N_17 => { let mut m = arg(args, 0); for &a in &args[1..] { if crate::numeric::compare(a, m) == Some(std::cmp::Ordering::Less) { m = a; } } outs![m] }
        N_18 => { let mut m = arg(args, 0); for &a in &args[1..] { if crate::numeric::compare(a, m) == Some(std::cmp::Ordering::Greater) { m = a; } } outs![m] }
        N_20 => outs![Value::num(f64::INFINITY)],
        N_21 => {
            let callee = arg(args, 0); let rest = &args[1.min(args.len())..];
            let hook = std::panic::take_hook(); std::panic::set_hook(Box::new(|_| {}));
            let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| it.call_value(callee, rest)));
            std::panic::set_hook(hook);
            match outcome {
                Ok(vals) => { let mut o = outs![Value::TRUE]; for v in vals { o.push(v); } o }
                Err(payload) => { let v = if let Some(e) = payload.downcast_ref::<LuaError>() { Value(e.0) } else { let msg = payload.downcast_ref::<String>().cloned().or_else(|| payload.downcast_ref::<&str>().map(|s| s.to_string())).unwrap_or_default(); it.intern(&msg) }; outs![Value::FALSE, v] }
            }
        }
        N_22 => { let t = arg(args, 0); let keys = it.table_keys(t); let itv = it.new_iter_keys(1, t, keys); outs![itv, t, Value::NIL] }
        N_23 => { let t = arg(args, 0); let itv = it.new_iter(2, t, Value::NIL); outs![itv, t, Value::num(0.0)] }
        N_24 => { let t = arg(args, 0); let k = arg(args, 1); let keys = it.table_keys(t); let pos = if k == Value::NIL { 0 } else { keys.iter().position(|x| it.values_equal(*x, k)).map(|p| p + 1).unwrap_or(keys.len()) }; if pos < keys.len() { let key = keys[pos]; let v = it.get_index(t, key); outs![key, v] } else { outs![Value::NIL] } }
        N_25 => { let v = arg(args, 0); let n = type_name(it, v); outs![it.intern(n)] }
        N_26 => { let v = arg(args, 0); if it.kind_of(v) == Some(crate::heap::KIND_STR) { return outs![v]; } let s = tostring(it, v); outs![it.string_of(&s)] }
        N_27 => { let v = arg(args, 0); if crate::numeric::is_numeric(v) { return outs![Value::num(crate::numeric::double(it, v))]; } if !it.is_stringish(v) { return outs![Value::NIL]; } let s = String::from_utf8_lossy(&bytes_of(it, v)).trim().to_string(); let base = int(args, 1, 10); let n = if base == 10 { let (negative, body) = match s.strip_prefix('-') { Some(rest) => (true, rest), None => (false, s.strip_prefix('+').unwrap_or(&s)) }; lua_number(body).map(|x| if negative { -x } else { x }) } else { i64::from_str_radix(&s, base as u32).ok().map(|x| x as f64) }; outs![n.map(Value::num).unwrap_or(Value::NIL)] }
        N_28 => { let v = arg(args, 0); std::panic::panic_any(LuaError(v.0)) }
        N_29 => { let v = arg(args, 0); if !v.truthy() { let msg = if args.len() > 1 { arg(args, 1) } else { it.intern("assertion failed!") }; std::panic::panic_any(LuaError(msg.0)); } args.iter().copied().collect() }
        N_30 => { let n = arg(args, 0); if !n.is_num() { return outs![Value::num((args.len() - 1) as f64)]; } let i = n.as_num() as i64; if i < 0 { args[(args.len() as i64 + i) as usize..].iter().copied().collect() } else { args[(i as usize).min(args.len())..].iter().copied().collect() } }
        N_31 => {
            use std::io::Write;
            let mut line = Vec::new();
            for (i, &v) in args.iter().enumerate() { if i > 0 { line.push(b'\t'); } line.extend(tostring(it, v)); }
            line.push(b'\n');
            let mut out = std::io::stdout().lock(); out.write_all(&line).unwrap(); out.flush().unwrap();
            Outs::new()
        }
        N_32 => outs![Value::boolean(arg(args, 0) == arg(args, 1))],
        N_33 => { let v = it.get_index(arg(args, 0), arg(args, 1)); outs![v] }
        N_34 => { it.set_index(arg(args, 0), arg(args, 1), arg(args, 2)); outs![arg(args, 0)] }
        N_35 => { let t = arg(args, 0); it.set_metatable(t, arg(args, 1)); outs![t] }
        N_36 => outs![it.getmetatable_value(arg(args, 0))],
        // The bit library: 32-bit two's complement, as LuaJIT's.
        38 => { let mut r: i32 = -1; for a in args { r &= a.as_num() as i64 as i32; } outs![Value::num(r as f64)] }
        39 => { let mut r: i32 = 0; for a in args { r |= a.as_num() as i64 as i32; } outs![Value::num(r as f64)] }
        40 => { let mut r: i32 = 0; for a in args { r ^= a.as_num() as i64 as i32; } outs![Value::num(r as f64)] }
        41 => outs![Value::num(!(arg(args, 0).as_num() as i64 as i32) as f64)],
        42 => outs![Value::num(((arg(args, 0).as_num() as i64 as i32).wrapping_shl(arg(args, 1).as_num() as u32)) as f64)],
        43 => outs![Value::num(((arg(args, 0).as_num() as i64 as u32).wrapping_shr(arg(args, 1).as_num() as u32) as i32) as f64)],
        44 => outs![Value::num(((arg(args, 0).as_num() as i64 as i32).wrapping_shr(arg(args, 1).as_num() as u32)) as f64)],
        45 => outs![Value::num((arg(args, 0).as_num() as i64 as i32) as f64)],
        46 => { let name = String::from_utf8_lossy(&bytes_of(it, arg(args, 0))).into_owned(); match std::env::var(&name) { Ok(v) => outs![it.heap_new_string(&v)], Err(_) => outs![Value::NIL] } }
        47 => { let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64(); outs![Value::num(t)] }
        48 => { let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64(); outs![Value::num(t.floor())] }
        49 => { use std::io::Write; let mut o = std::io::stdout(); for a in args { o.write_all(&bytes_of(it, *a)).unwrap(); } o.flush().unwrap(); Outs::new() }
        // `loadstring("return <literal>")`: every use in the compiler decodes a
        // number or string literal this way. The answer is a closure over the
        // value; other chunks go to the installed Nupp source loader.
        50 => {
            let src = bytes_of(it, arg(args, 0));
            match literal_chunk(&src) {
                Some(Lit::Num(n)) => { let cell = it.new_cell(Value::num(n)); let h = it.register(cell); let c = it.new_closure(it.literal_fid, &[cell]); it.release(h); outs![c] }
                Some(Lit::Str(b)) => { let s = it.new_string_bytes(&b); let h = it.register(s); let cell = it.new_cell(s); let h2 = it.register(cell); let c = it.new_closure(it.literal_fid, &[cell]); it.release(h2); it.release(h); outs![c] }
                Some(Lit::Bool(x)) => { let cell = it.new_cell(Value::boolean(x)); let h = it.register(cell); let c = it.new_closure(it.literal_fid, &[cell]); it.release(h); outs![c] }
                Some(Lit::Nil) => { let cell = it.new_cell(Value::NIL); let h = it.register(cell); let c = it.new_closure(it.literal_fid, &[cell]); it.release(h); outs![c] }
                // The project compiler installs a validating source loader.
                // Older closed-input harnesses retain their unavailable thunk.
                None => {
                    let globals = it.require("_G");
                    let key = it.intern("__nupp_compile_chunk");
                    let hook = it.get_index(globals, key);
                    if hook != Value::NIL { return it.call_outs(hook, args); }
                    let c = it.new_closure(it.unavailable_fid, &[]); outs![c]
                }
            }
        }
        51 => { let name = String::from_utf8_lossy(&bytes_of(it, arg(args, 0))).into_owned(); outs![it.require(&name)] }
        // table.sort: the array part, by `<` or the comparator. The table
        // stays rooted in the caller's register; the sorted copy is written back.
        53 => {
            let t = arg(args, 0); let cmp = arg(args, 1); let n = it.array_len(t);
            let mut v: Vec<Value> = (1..=n).map(|k| it.get_index(t, Value::num(k as f64))).collect();
            if cmp == Value::NIL {
                v.sort_by(|a, b| { if crate::numeric::is_numeric(*a) && crate::numeric::is_numeric(*b) { crate::numeric::compare(*a, *b).unwrap_or(std::cmp::Ordering::Equal) } else { it.bytes_of(*a).cmp(it.bytes_of(*b)) } });
            } else {
                // Values under comparison live in `v`, which the collector cannot see:
                // every one is rooted for the duration.
                let mark = it.open_scope(); for x in &v { it.handles.push(*x); }
                v.sort_by(|a, b| { let r = it.call_value(cmp, &[*a, *b]); if r.first().map(|x| x.truthy()).unwrap_or(false) { std::cmp::Ordering::Less } else { let r2 = it.call_value(cmp, &[*b, *a]); if r2.first().map(|x| x.truthy()).unwrap_or(false) { std::cmp::Ordering::Greater } else { std::cmp::Ordering::Equal } } });
                it.close_scope(mark);
            }
            for (k, x) in v.into_iter().enumerate() { it.set_index(t, Value::num((k + 1) as f64), x); }
            Outs::new()
        }
        54 => { let mut b = bytes_of(it, arg(args, 0)); b.reverse(); outs![str_of(it, &b)] }
        55 => { let x = arg(args, 0).as_num() as i64 as u32; let n = (arg(args, 1).as_num() as i64 & 31) as u32; outs![Value::num(x.rotate_left(n) as i32 as f64)] }
        56 => { let x = arg(args, 0).as_num() as i64 as u32; let n = (arg(args, 1).as_num() as i64 & 31) as u32; outs![Value::num(x.rotate_right(n) as i32 as f64)] }
        57 => { let x = arg(args, 0).as_num() as i64 as u32; outs![Value::num(x.swap_bytes() as i32 as f64)] }
        58 => { let x = arg(args, 0).as_num() as i64 as u32; let n = int(args, 1, 8); let s = if n < 0 { format!("{:0width$X}", x, width = (-n) as usize) } else { format!("{:0width$x}", x, width = n as usize) }; let s = &s[s.len().saturating_sub(n.unsigned_abs() as usize)..]; outs![str_of(it, s.as_bytes())] }
        59 => outs![Value::num(arg(args, 0).as_num().ceil())],
        60 => outs![Value::num(arg(args, 0).as_num().sqrt())],
        61 => { let x = arg(args, 0).as_num(); if args.len() > 1 { outs![Value::num(x.ln() / arg(args, 1).as_num().ln())] } else { outs![Value::num(x.ln())] } }
        62 => outs![Value::num(arg(args, 0).as_num() % arg(args, 1).as_num())],
        63 => { let x = arg(args, 0).as_num(); let i = x.trunc(); outs![Value::num(i), Value::num(x - i)] }
        64 => { let x = arg(args, 0).as_num(); if x == 0.0 || !x.is_finite() { outs![Value::num(x), Value::num(0.0)] } else { let e = x.abs().log2().floor() as i32 + 1; let m = x / (2f64).powi(e); outs![Value::num(m), Value::num(e as f64)] } }
        // io.open for reading: the whole file now, as a string behind a file
        // object whose `read`, `lines` and `close` are fields (a method call
        // falls back to them). Writable modes hold a native file resource.
        65 => {
            let path = String::from_utf8_lossy(&bytes_of(it, arg(args, 0))).into_owned();
            let mode = if args.len() > 1 && arg(args, 1) != Value::NIL { String::from_utf8_lossy(&bytes_of(it, arg(args, 1))).into_owned() } else { "r".to_string() };
            if mode != "r" && mode != "rb" { return crate::fileio::open(it, &path, &mode); }
            match std::fs::read(&path) {
                Ok(data) => {
                    let f = it.new_table(); let fh = it.register(f);
                    let d = it.new_string_bytes(&data); let dh = it.register(d);
                    for (k, v) in [("read", 73u32), ("close", 74), ("lines", 75), ("write", 76)] { let kv = it.intern(k); it.set_index(f, kv, Value::builtin(v)); }
                    let kv = it.intern("_data"); it.set_index(f, kv, d);
                    let kv = it.intern("_at"); it.set_index(f, kv, Value::num(0.0));
                    it.release(dh); it.release(fh);
                    outs![f]
                }
                Err(e) => { let msg = it.heap_new_string(&format!("{path}: {e}")); outs![Value::NIL, msg] }
            }
        }
        // file:read(fmt): "*a"/"a" the rest, "*l"/"l" a line, a number that many bytes.
        73 => {
            let f = arg(args, 0);
            let key = it.intern("_closed"); if it.get_index(f, key) == Value::TRUE { it.err("attempt to read a closed file"); }
            let key = it.intern("_processPipe"); if it.get_index(f, key) == Value::TRUE { return crate::process::call(it, "process.pipeRead", args); }
            if crate::fileio::is_native(it, f) { return crate::fileio::read(it, f, arg(args, 1)); }
            let kd = it.intern("_data"); let ka = it.intern("_at");
            let data = bytes_of(it, it.get_index(f, kd)); let at = it.get_index(f, ka).as_num() as usize;
            if at >= data.len() { let fmt = arg(args, 1); let all = !fmt.is_num() && { let b = bytes_of(it, fmt); b == b"*a" || b == b"a" }; return if all { outs![str_of(it, b"")] } else { outs![Value::NIL] }; }
            let fmt = arg(args, 1);
            let (chunk, next) = if fmt.is_num() { let n = fmt.as_num() as usize; let e = (at + n).min(data.len()); (data[at..e].to_vec(), e) }
                else { let b = bytes_of(it, fmt); if b == b"*a" || b == b"a" { (data[at..].to_vec(), data.len()) } else { let e = data[at..].iter().position(|&c| c == b'\n').map(|p| at + p).unwrap_or(data.len()); (data[at..e].to_vec(), (e + 1).min(data.len()).max(e)) } };
            it.set_index(f, ka, Value::num(next as f64));
            outs![str_of(it, &chunk)]
        }
        74 => { let file = arg(args, 0); if crate::fileio::is_native(it, file) { crate::fileio::close(it, file) } else { let key = it.intern("_closed"); it.set_index(file, key, Value::TRUE); outs![Value::TRUE] } },
        75 => { let file = arg(args, 0); let format = arg(args, 1); let format = if format == Value::NIL { it.intern("*l") } else { format }; outs![it.new_iter(4, file, format)] },
        76 => crate::fileio::write(it, args),
        66 => { use std::io::Write; let mut o = std::io::stderr(); for a in &args[1.min(args.len())..] { o.write_all(&bytes_of(it, *a)).unwrap(); } o.flush().unwrap(); outs![arg(args, 0)] }
        67 => { use std::io::Write; let mut o = std::io::stdout(); for a in &args[1.min(args.len())..] { o.write_all(&bytes_of(it, *a)).unwrap(); } o.flush().unwrap(); outs![arg(args, 0)] }
        // Filesystem mutations report operating-system failures as Lua results.
        68 | 71 => {
            let path = String::from_utf8_lossy(it.bytes_of(arg(args, 0))).into_owned();
            let result = if id == 68 { if std::fs::symlink_metadata(&path).map(|m| m.is_dir()).unwrap_or(false) { std::fs::remove_dir(path) } else { std::fs::remove_file(path) } } else { let to = String::from_utf8_lossy(it.bytes_of(arg(args, 1))).into_owned(); std::fs::rename(path, to) };
            match result { Ok(()) => outs![Value::TRUE], Err(error) => { let msg = it.heap_new_string(&error.to_string()); outs![Value::NIL, msg, Value::num(error.raw_os_error().unwrap_or(0) as f64)] } }
        }
        69 => crate::fileio::temporary_name(it),
        70 => crate::process::execute(it, args),
        72 => crate::stdio::read(it, arg(args, 0)),
        52 => {
            // A builtin pushes no frame; resolve its scoped task or native caller.
            let source = { let fid = it.caller_function(); let module = fid.map(|f| it.funcs[f].module.clone()).unwrap_or_default(); it.module_paths.get(&module).map(|p| if p.starts_with('=') || p.starts_with('@') { p.clone() } else { format!("@{p}") }).unwrap_or_else(|| "=nupp-vm".to_string()) };
            let t = it.new_table(); let h = it.register(t); for (k, v) in [("source", source.as_str()), ("short_src", "nupp-vm"), ("what", "Lua")] { let kv = it.intern(k); let kh = it.register(kv); let vv = it.heap_new_string(v); it.set_index(t, kv, vv); it.release(kh); } it.release(h); outs![t]
        }
        other => panic!("runtime error: builtin {} not implemented", NAMES[other as usize]),
    }
}

fn parse_spec(spec: &str) -> (usize, bool, bool, Option<usize>) {
    let left = spec.contains('-'); let zero = spec.starts_with('0') || spec.contains("-0");
    let digits: String = spec.chars().skip_while(|c| "-+ #0".contains(*c)).collect();
    let (w, p) = match digits.split_once('.') { Some((w, p)) => (w.to_string(), Some(p.parse::<usize>().unwrap_or(0))), None => (digits, None) };
    (w.parse().unwrap_or(0), zero, left, p)
}

/// One step of an iterator object: `pairs`, `ipairs` or `gmatch` state.
pub fn iter_next(it: &mut Interp, iter: Value) -> Outs {
    let (kind, obj, pos, keys_len) = it.iter_state(iter);
    match kind {
        1 => { for index in pos..keys_len { let k = it.iter_key(iter, index); it.iter_advance(iter); let v = it.get_index(obj, k); if v != Value::NIL { return outs![k, v]; } } outs![Value::NIL] }
        2 => { let i = pos + 1; let v = it.get_index(obj, Value::num(i as f64)); if v == Value::NIL { return outs![Value::NIL]; } it.iter_advance(iter); outs![Value::num(i as f64), v] }
        3 => {
            let s = bytes_of(it, obj); let pat = bytes_of(it, it.iter_pattern(iter));
            if pos > s.len() { return outs![Value::NIL]; }
            match pattern::find(&s, &pat, pos) {
                Some((a, b, caps)) => { it.iter_set_pos(iter, if b > a { b } else { b + 1 }); if caps.is_empty() { outs![str_of(it, &s[a..b])] } else { let scope = it.open_scope(); let mut out = Outs::new(); for c in caps { let value = match c { pattern::Cap::Pos(p) => Value::num((p + 1) as f64), pattern::Cap::Span(x, y) => str_of(it, &s[x..y]) }; it.handles.push(value); out.push(value); } it.close_scope(scope); out } }
                None => { it.iter_set_pos(iter, s.len() + 1); outs![Value::NIL] }
            }
        }
        4 | 5 => {
            if kind == 5 && pos != 0 { return outs![Value::NIL]; }
            let format = it.iter_pattern(iter);
            let result = call(it, id_of("file.read").unwrap(), &[obj, format]);
            if kind == 5 && result.first() == Some(&Value::NIL) {
                call(it, id_of("file.close").unwrap(), &[obj]);
                it.iter_advance(iter);
            }
            result
        }
        6 => { let format = it.iter_pattern(iter); crate::stdio::read(it, format) }
        _ => outs![Value::NIL],
    }
}

/// Lua patterns: classes, sets, captures, anchors, the four quantifiers.
pub mod pattern {
    #[derive(Clone, Copy, Debug)]
    pub enum Cap { Span(usize, usize), Pos(usize) }
    #[derive(Clone)]
    struct State<'a> { s: &'a [u8], p: &'a [u8], caps: Vec<(usize, Option<usize>)>, depth: u32 }

    fn class_matches(c: u8, cl: u8) -> bool {
        let r = match cl.to_ascii_lowercase() { b'a' => c.is_ascii_alphabetic(), b'd' => c.is_ascii_digit(), b's' => c.is_ascii_whitespace() || c == 11, b'w' => c.is_ascii_alphanumeric(), b'x' => c.is_ascii_hexdigit(), b'p' => c.is_ascii_punctuation(), b'l' => c.is_ascii_lowercase(), b'u' => c.is_ascii_uppercase(), b'c' => c.is_ascii_control(), b'g' => c.is_ascii_graphic(), b'z' => c == 0, other => return c == other };
        if cl.is_ascii_uppercase() { !r } else { r }
    }
    /// The end of the single-character item starting at `pi`.
    fn item_end(p: &[u8], pi: usize) -> usize {
        match p[pi] { b'%' => (pi + 2).min(p.len()), b'[' => { let mut i = pi + 1; if i < p.len() && p[i] == b'^' { i += 1; } loop { if i >= p.len() { return p.len(); } if p[i] == b']' && i > pi + 1 { return i + 1; } if p[i] == b'%' { i += 2; } else { i += 1; } } } _ => pi + 1 }
    }
    fn single(c: u8, p: &[u8], pi: usize, end: usize) -> bool {
        match p[pi] {
            b'.' => true,
            b'%' => class_matches(c, p[pi + 1]),
            b'[' => { let mut i = pi + 1; let neg = p[i] == b'^'; if neg { i += 1; } let mut found = false; while i < end - 1 { if p[i] == b'%' { if class_matches(c, p[i + 1]) { found = true; } i += 2; } else if i + 2 < end - 1 && p[i + 1] == b'-' { if c >= p[i] && c <= p[i + 2] { found = true; } i += 3; } else { if c == p[i] { found = true; } i += 1; } } found != neg }
            other => c == other,
        }
    }
    fn do_match(st: &mut State, si: usize, pi: usize) -> Option<usize> {
        st.depth += 1; if st.depth > 10_000 { panic!("runtime error: pattern too complex"); }
        let r = match_inner(st, si, pi);
        st.depth -= 1; r
    }
    fn match_inner(st: &mut State, mut si: usize, mut pi: usize) -> Option<usize> {
        let p = st.p; let s = st.s;
        loop {
            if pi >= p.len() { return Some(si); }
            match p[pi] {
                b'(' => {
                    if pi + 1 < p.len() && p[pi + 1] == b')' { st.caps.push((si, Some(si))); let idx = st.caps.len() - 1; st.caps[idx] = (si, None); let r = do_match(st, si, pi + 2); if r.is_none() { st.caps.pop(); } else { st.caps[idx].1 = Some(usize::MAX); } return r; }
                    st.caps.push((si, None)); let idx = st.caps.len() - 1;
                    let r = do_match(st, si, pi + 1); if r.is_none() { st.caps.truncate(idx); } return r;
                }
                b')' => { let idx = st.caps.iter().rposition(|c| c.1.is_none()).expect("unmatched )"); st.caps[idx].1 = Some(si); let r = do_match(st, si, pi + 1); if r.is_none() { st.caps[idx].1 = None; } return r; }
                b'$' if pi + 1 == p.len() => return if si == s.len() { Some(si) } else { None },
                // `%bxy`: a balanced run from x to its matching y.
                b'%' if p.get(pi + 1) == Some(&b'b') => {
                    let (open, close) = match (p.get(pi + 2), p.get(pi + 3)) { (Some(&o), Some(&c)) => (o, c), _ => panic!("runtime error: missing arguments to '%b'") };
                    if si >= s.len() || s[si] != open { return None; }
                    let mut depth = 1; let mut i = si + 1;
                    while i < s.len() { if s[i] == close { depth -= 1; if depth == 0 { break; } } else if s[i] == open { depth += 1; } i += 1; }
                    if i >= s.len() { return None; }
                    si = i + 1; pi += 4; continue;
                }
                // `%f[set]`: the position where the previous byte is outside
                // the set and the next is inside it; the ends read as `\0`.
                b'%' if p.get(pi + 1) == Some(&b'f') => {
                    if p.get(pi + 2) != Some(&b'[') { panic!("runtime error: missing '[' after '%f' in pattern"); }
                    let end = item_end(p, pi + 2);
                    let prev = if si == 0 { 0 } else { s[si - 1] };
                    let next = if si < s.len() { s[si] } else { 0 };
                    if single(prev, p, pi + 2, end) || !single(next, p, pi + 2, end) { return None; }
                    pi = end; continue;
                }
                // `%1`..`%9`: the text a closed capture matched, again.
                b'%' if p.get(pi + 1).is_some_and(|c| (b'1'..=b'9').contains(c)) => {
                    let k = (p[pi + 1] - b'1') as usize;
                    let (a, e) = match st.caps.get(k) { Some(&(a, Some(e))) if e != usize::MAX => (a, e), _ => panic!("runtime error: invalid capture index %{}", k + 1) };
                    let len = e - a;
                    if si + len > s.len() || s[si..si + len] != s[a..e] { return None; }
                    si += len; pi += 2; continue;
                }
                _ => {
                    let end = item_end(p, pi);
                    let m = si < s.len() && single(s[si], p, pi, end);
                    let q = if end < p.len() { p[end] } else { 0 };
                    match q {
                        b'?' => { if m { if let Some(r) = do_match(st, si + 1, end + 1) { return Some(r); } } pi = end + 1; continue; }
                        b'+' => { if !m { return None; } return max_expand(st, si + 1, pi, end); }
                        b'*' => return max_expand(st, si, pi, end),
                        b'-' => { let mut i = si; loop { if let Some(r) = do_match(st, i, end + 1) { return Some(r); } if i < s.len() && single(s[i], p, pi, end) { i += 1; } else { return None; } } }
                        _ => { if !m { return None; } si += 1; pi = end; continue; }
                    }
                }
            }
        }
    }
    fn max_expand(st: &mut State, si: usize, pi: usize, end: usize) -> Option<usize> {
        let s = st.s; let p = st.p;
        let mut i = si; while i < s.len() && single(s[i], p, pi, end) { i += 1; }
        loop { if let Some(r) = do_match(st, i, end + 1) { return Some(r); } if i == si { return None; } i -= 1; }
    }
    fn captures(st: &State) -> Vec<Cap> { st.caps.iter().map(|&(a, b)| match b { Some(usize::MAX) => Cap::Pos(a), Some(e) => Cap::Span(a, e), None => Cap::Span(a, a) }).collect() }
    /// Matches anchored at `si`; returns the end and the captures.
    pub fn match_at(s: &[u8], p: &[u8], si: usize) -> Option<(usize, Vec<Cap>)> {
        let p = if p.first() == Some(&b'^') { &p[1..] } else { p };
        let mut st = State { s, p, caps: Vec::new(), depth: 0 };
        do_match(&mut st, si, 0).map(|e| (e, captures(&st)))
    }
    /// The first match at or after `init`: (start, end, captures).
    pub fn find(s: &[u8], p: &[u8], init: usize) -> Option<(usize, usize, Vec<Cap>)> {
        let anchored = p.first() == Some(&b'^');
        let body = if anchored { &p[1..] } else { p };
        let mut si = init;
        loop {
            let mut st = State { s, p: body, caps: Vec::new(), depth: 0 };
            if let Some(e) = do_match(&mut st, si, 0) { return Some((si, e, captures(&st))); }
            if anchored || si >= s.len() { return None; }
            si += 1;
        }
    }
}
