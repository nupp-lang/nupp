//! The graph image: the typed closed-block control-flow graph the compiler
//! emits for every function, with its constants, positions, certificates and
//! region tree, beside shapes, modules and extension declarations. This is
//! the decoder into dense arrays, the verifier over the opcode signature
//! table, and the derivation of the interpreter's `Op` stream, which is
//! never persisted. `src/nupp/compiler/vm/graphimage.nupp` is the encoder
//! and `graph.nupp` holds the same signature table; the three move together.
//!
//! Decoding refuses hostile input before anything is derived: every count is
//! bounded by what remains, every id by its table, every truncated prefix by
//! the read that runs out, and the verifier then holds the graph to closed
//! blocks, classes, edge arity, reachability, region consistency and
//! certificate classes.

use crate::interp::{Function, GpuArtifact, Interp, Op};
use crate::value::Value;
use crate::verify::C;
use std::collections::VecDeque;

pub const NONE: u32 = u32::MAX;
pub const MAGIC: &[u8; 8] = b"NUPPGRAF";
pub const VERSION: u32 = 5;
/// No image is this large; a count past it is hostile rather than big.
const LIMIT: usize = 1 << 30;

/// Operand classes, as the slot columns and `graph.nupp` number them.
pub const V: u8 = 0;
pub const I: u8 = 1;
pub const F: u8 = 2;
pub const X: u8 = 3;

/// One signature per opcode, `graph.nupp`'s table: the uppercase letter is
/// the result at the position the VM's operand order gives it; the rest are
/// operands. `v i f x` are register values; `#` a small immediate; `k` a
/// constant; `n` a function; `h` a shape; `s` a named SIMD operation or
/// element kind; `w` a value-slot immediate (a window base); `L` and `D` a
/// wide integer or float literal; `j` and `t` jump offsets and tables, only
/// on the terminator opcodes, which never appear inside a block. The last
/// seven are graph-only macros the derivation expands.
/// The graph-only macros the derivation expands, after the opcode table's
/// own rows.
const MACROS: &[(&str, &str)] = &[("U32Load", "Ivi"), ("U32Store", "vii"), ("U32Add", "Iii"), ("U32Sub", "Iii"), ("SpanEqual", "vvk"), ("VSplatI", "Xi#"), ("VExtractI", "Ix##")];

/// What the table cannot say: which immediates are a wide integer or a
/// double (1-based positions), and the two SIMD scalar opcodes whose kind
/// operand decides a class a graph value has to fix.
const PAYLOADS: &[(&str, &[(usize, char)])] = &[("IK", &[(2, 'L')]), ("IAddK", &[(3, 'L')]), ("FK", &[(2, 'D')]), ("VLoadM", &[(4, 'L')]), ("VStoreM", &[(4, 'L')]), ("VLoad", &[(4, 'L')]), ("VStore", &[(4, 'L')]), ("LoopFact", &[(2, 'L')])];
const PINNED: &[(&str, &str)] = &[("VSplatN", "Xf#"), ("VExtractN", "Fx##")];

/// The signature letters of every opcode, derived from the opcode table by
/// the rule `graph.nupp` applies to the same table: a defined register is
/// its class in uppercase, a register both read and written is a use (no
/// kernel's graph holds one; register form names registers), a window's base
/// is `w`, and the other classes map to their letters.
fn derived_signatures() -> Vec<(&'static str, &'static str)> {
    use crate::opcodes::{Class, Mode};
    let leak = |s: &str| -> &'static str { Box::leak(s.to_string().into_boxed_str()) };
    let mut out = Vec::new();
    for row in crate::opcodes::table().rows() {
        if let Some((_, pinned)) = PINNED.iter().find(|(n, _)| *n == row.name) { out.push((leak(&row.name), *pinned)); continue; }
        let payload = PAYLOADS.iter().find(|(n, _)| *n == row.name).map(|(_, p)| *p).unwrap_or(&[]);
        let mut letters = String::with_capacity(row.operands.len());
        for (i, spec) in row.operands.iter().enumerate() {
            let position = i + 1;
            let letter = match spec.class {
                Class::Reg(c) => {
                    let lower = match c { C::V => 'v', C::I => 'i', C::F => 'f', C::X => 'x' };
                    if spec.mode == Mode::Def { lower.to_ascii_uppercase() } else if row.windows.iter().any(|w| w.base == position) { 'w' } else { lower }
                }
                Class::ScalarByKind(_) => if spec.mode == Mode::Def { 'S' } else { 's' },
                Class::Const => 'k', Class::Jump => 'j', Class::Imm => '#', Class::Shape => 'h', Class::Func => 'n', Class::Table => 't', Class::Name => 's',
            };
            letters.push(payload.iter().find(|(p, _)| *p == position).map(|(_, l)| *l).unwrap_or(letter));
        }
        out.push((leak(&row.name), leak(&letters)));
    }
    out.extend(MACROS.iter().copied());
    out
}
const TERMINATORS: &[&str] = &["Jmp", "JmpIf", "JmpIfNot", "JmpIfIZero", "IJmpIfUle", "IJmpIfUlt", "Switch", "Ret", "RetNil", "RetN", "FRet", "Raise", "Park"];

/// Terminator kinds, as the image numbers them.
pub const JUMP: u32 = 0;
pub const BRANCH: u32 = 1;
pub const SWITCH: u32 = 2;
pub const RETURN: u32 = 3;
pub const RAISE: u32 = 4;
pub const PARK: u32 = 5;
pub const RETURNS: u32 = 6;
/// Region kinds.
pub const BODY: u32 = 0;
pub const LOOP: u32 = 1;
pub const THEN: u32 = 2;
pub const ELSE: u32 = 3;

fn class_of(letter: u8) -> Option<u8> {
    match letter { b'v' | b'V' => Some(V), b'i' | b'I' => Some(I), b'f' | b'F' => Some(F), b'x' | b'X' => Some(X), _ => None }
}

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Span { pub start: u32, pub len: u32 }
impl Span {
    pub fn get<T>(self, pool: &[T]) -> &[T] { &pool[self.start as usize..(self.start + self.len) as usize] }
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Edge { pub target: u32, pub args: Span }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Block { pub params: Span, pub insts: Span, pub term: u32, pub value: u32, pub constant: u32, pub count: u32, pub edges: Span }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Region { pub kind: u32, pub parent: u32, pub head: u32, pub entry: u32, pub continuing: u32, pub merge: u32 }
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Constant { pub kind: u32, pub payload: u32 }
#[derive(Clone, Debug, PartialEq)]
pub struct Shape { pub name: u32, pub identity: u32, pub slots: Vec<(u32, u32, u32)>, pub methods: Vec<(u32, u32)> }

/// One function's graph: instructions are `[opcode, operands...]` in the
/// VM's operand order, eight words each; parameter and argument lists are
/// spans into one pool.
#[derive(Clone, Debug, PartialEq, Default)]
pub struct Graph {
    pub name: u32,
    pub module: u32,
    pub path: u32,
    pub nparams: u32,
    pub vararg: bool,
    pub sig: u32,
    pub ret: u32,
    pub map: bool,
    /// A lowered function in register form: instruction operands are the
    /// frame's registers, an ending names a `class << 8 | register` key,
    /// blocks have no parameters and edges no arguments, there are no values
    /// or regions, and the frame's register counts are `registers`.
    pub register_form: bool,
    pub registers: [u32; 3],
    pub constants: Vec<Constant>,
    pub positions: Vec<(u32, u32)>,
    pub certificates: Vec<[u32; 3]>,
    pub classes: Vec<u8>,
    pub slots: Vec<u32>,
    pub blocks: Vec<Block>,
    pub insts: Vec<[u32; 8]>,
    pub pos: Vec<u32>,
    pub cert: Vec<u32>,
    pub edges: Vec<Edge>,
    pub values: Vec<u32>,
    pub regions: Vec<Region>,
    pub block_region: Vec<u32>,
    pub gpu: Option<Box<GpuArtifact>>,
}

impl Graph {
    /// Empties the graph for the next function, keeping every vector's
    /// capacity: a loader decodes thousands of functions into one buffer.
    fn clear(&mut self) {
        self.constants.clear(); self.positions.clear(); self.certificates.clear(); self.classes.clear(); self.slots.clear();
        self.blocks.clear(); self.insts.clear(); self.pos.clear(); self.cert.clear(); self.edges.clear(); self.values.clear();
        self.regions.clear(); self.block_region.clear(); self.gpu = None;
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Image {
    pub strings: Vec<Vec<u8>>,
    pub wides: Vec<i64>,
    pub floats: Vec<f64>,
    pub shapes: Vec<Shape>,
    pub modules: Vec<(u32, u32, u32)>,
    pub extensions: Vec<(u32, u32)>,
    pub entry: u32,
    pub functions: Vec<Graph>,
}

impl Image {
    pub fn text(&self, index: u32) -> &str { std::str::from_utf8(&self.strings[index as usize]).unwrap_or("") }
    pub fn name(&self, g: &Graph) -> &str { self.text(g.name) }
}

/// The parsed signature table: result class and position, operand letters.
pub struct Signature { pub name: &'static str, pub result: Option<u8>, pub result_at: usize, pub operands: &'static str, pub terminator: bool, pub hot: u8 }

/// The opcodes that are most of any image, in frequency order: the
/// derivation dispatches these by index and the rest by name.
const HOT: &[&str] = &["Move", "K", "SetIdx", "GetField", "GetCell", "PadResults", "CallDyn", "NewTableN", "Nil", "Eq", "GetIdx", "SetSlot", "GetUpval", "CallK", "GetSlot", "Concat", "SetField", "NewCell", "NewClosure", "Len", "Not", "Add", "NewRecord", "Ne", "Require", "CallMethod", "SetCell"];
pub struct Table { pub entries: Vec<Signature>, result_letters: Vec<Option<u8>> }
impl Table {
    pub fn new() -> Self {
        let signatures = derived_signatures();
        let mut entries = Vec::with_capacity(signatures.len());
        for (name, sig) in signatures {
            let result_at = sig.bytes().position(|c| c.is_ascii_uppercase()).unwrap_or(usize::MAX);
            let result = sig.bytes().find(|c| c.is_ascii_uppercase()).and_then(class_of);
            let hot = HOT.iter().position(|h| *h == name).map(|i| i as u8 + 1).unwrap_or(0);
            entries.push(Signature { name, result, result_at, operands: sig, terminator: TERMINATORS.contains(&name), hot });
        }
        let result_letters = entries.iter().map(|s| s.result).collect();
        Table { entries, result_letters }
    }
    pub fn index(&self, name: &str) -> Option<u32> { self.entries.iter().position(|s| s.name == name).map(|i| i as u32) }
    #[inline] pub fn result(&self, op: u32) -> Option<u8> { self.result_letters[op as usize] }
}
impl Default for Table { fn default() -> Self { Self::new() } }

thread_local! { static TABLE: Table = Table::new(); }
pub fn with_table<R>(f: impl FnOnce(&Table) -> R) -> R { TABLE.with(f) }

struct Reader<'a> { data: &'a [u8], at: usize }
impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], String> {
        if n > self.data.len() - self.at { return Err("truncated graph image".into()); }
        let head = &self.data[self.at..self.at + n];
        self.at += n;
        Ok(head)
    }
    /// A word: stored shifted by one so NONE is a single zero byte, seven
    /// bits per byte, low bits first, the high bit marking more.
    #[inline(always)]
    fn word(&mut self) -> Result<u32, String> {
        // Nearly every word is one byte.
        if let Some(&b) = self.data.get(self.at) { if b < 0x80 { self.at += 1; return Ok((b as u32).wrapping_sub(1)); } }
        self.word_long()
    }
    #[inline(never)]
    fn word_long(&mut self) -> Result<u32, String> {
        let mut value: u32 = 0;
        let mut shift = 0;
        loop {
            let b = *self.data.get(self.at).ok_or("truncated graph image")?;
            self.at += 1;
            if shift == 28 && b > 0x0f { return Err("graph image word overflows".into()); }
            value |= ((b & 0x7f) as u32) << shift;
            if b < 0x80 { break; }
            shift += 7;
            if shift > 28 { return Err("graph image word overflows".into()); }
        }
        Ok(value.wrapping_sub(1))
    }
    /// A count of items at least one byte each: bounded by what remains.
    fn count(&mut self, _unit: usize) -> Result<usize, String> {
        let n = self.word()? as usize;
        if n > self.data.len() - self.at || n > LIMIT { return Err("graph image count exceeds its remaining bytes".into()); }
        Ok(n)
    }
    fn index(&mut self, limit: usize, what: &str) -> Result<u32, String> {
        let n = self.word()?;
        if n as usize >= limit { return Err(format!("graph image {what} {n} outside its table of {limit}")); }
        Ok(n)
    }
    fn optional(&mut self, limit: usize, what: &str) -> Result<u32, String> {
        let n = self.word()?;
        if n != NONE && n as usize >= limit { return Err(format!("graph image {what} {n} outside its table of {limit}")); }
        Ok(n)
    }
}

/// Decodes and verifies a whole image. Nothing is derived from an image a
/// check refused.
pub fn decode(bytes: &[u8]) -> Result<Image, String> {
    with_table(|table| decode_with(table, bytes))
}

fn decode_header<'a>(table: &Table, bytes: &'a [u8]) -> Result<Header<'a>, String> {
    let _ = table;
    let mut r = Reader { data: bytes, at: 0 };
    if r.take(8)? != MAGIC { return Err("not a graph image".into()); }
    if r.word()? != VERSION { return Err("unsupported graph image version".into()); }
    let mut strings = Vec::new();
    for _ in 0..r.count(4)? {
        let n = r.count(1)?;
        strings.push(r.take(n)?.to_vec());
    }
    let mut wides = Vec::new();
    for _ in 0..r.count(8)? { wides.push(i64::from_le_bytes(r.take(8)?.try_into().unwrap())); }
    let mut floats = Vec::new();
    for _ in 0..r.count(8)? { floats.push(f64::from_le_bytes(r.take(8)?.try_into().unwrap())); }
    let nstrings = strings.len();
    let mut shapes = Vec::new();
    for _ in 0..r.count(16)? {
        let name = r.index(nstrings, "shape name")?;
        let identity = r.optional(nstrings, "shape identity")?;
        let mut slots = Vec::new();
        let nslots = r.count(12)?;
        for _ in 0..nslots {
            let slot = r.index(nstrings, "slot name")?;
            let ty = r.word()?;
            if ty > 4 { return Err("graph image slot type".into()); }
            // May name a later shape; it installs untyped, as the text loader does.
            let record = r.word()?;
            slots.push((slot, ty, record));
        }
        let mut methods = Vec::new();
        for _ in 0..r.count(8)? { methods.push((r.index(nstrings, "method name")?, r.word()?)); }
        shapes.push(Shape { name, identity, slots, methods });
    }
    for s in &shapes {
        for &(_, _, record) in &s.slots {
            if record != NONE && record as usize >= shapes.len() { return Err(format!("graph image slot record shape {record} outside its table of {}", shapes.len())); }
        }
    }
    let mut modules = Vec::new();
    for _ in 0..r.count(12)? { modules.push((r.index(nstrings, "module name")?, r.word()?, r.optional(nstrings, "module path")?)); }
    let mut extensions = Vec::new();
    for _ in 0..r.count(8)? { extensions.push((r.index(nstrings, "extension name")?, r.index(nstrings, "extension declaration")?)); }
    let entry = r.word()?;
    let nfunctions = r.count(40)?;
    let image = Image { strings, wides, floats, shapes, modules, extensions, entry, functions: Vec::new() };
    for s in &image.shapes { for &(_, f) in &s.methods { if f as usize >= nfunctions { return Err("shape method outside the functions".into()); } } }
    for &(_, chunk, _) in &image.modules { if chunk as usize >= nfunctions { return Err("module chunk outside the functions".into()); } }
    if entry != NONE && entry as usize >= nfunctions { return Err("entry outside the functions".into()); }
    // Opcode names resolve once per string, not once per instruction.
    let opcode_of: Vec<u32> = vec![NONE; nstrings];
    Ok(Header { image, nfunctions, opcode_of, reader: r, scratch: Scratch::default() })
}

/// An image decoded up to its functions, which `next_function` then yields
/// one at a time, verified, so a loader never holds every graph at once.
struct Header<'a> { image: Image, nfunctions: usize, opcode_of: Vec<u32>, reader: Reader<'a>, scratch: Scratch }

impl Header<'_> {
    fn next_function(&mut self, table: &Table, fi: usize, g: &mut Graph) -> Result<(), String> {
        decode_graph(table, &mut self.reader, &self.image, self.nfunctions, &mut self.opcode_of, g).map_err(|e| format!("graph image function {fi}: {e}"))?;
        verify_with(table, &self.image, g, self.nfunctions, &mut self.scratch).map_err(|e| format!("function {}: {e}", self.image.text(g.name)))?;
        Ok(())
    }
    fn finish(self) -> Result<Image, String> {
        if self.reader.at != self.reader.data.len() { return Err("trailing graph image bytes".into()); }
        Ok(self.image)
    }
}

fn decode_with(table: &Table, bytes: &[u8]) -> Result<Image, String> {
    let mut header = decode_header(table, bytes)?;
    let mut functions = Vec::with_capacity(header.nfunctions);
    for fi in 0..header.nfunctions { let mut g = Graph::default(); header.next_function(table, fi, &mut g)?; functions.push(g); }
    let mut image = header.finish()?;
    image.functions = functions;
    Ok(image)
}

fn decode_graph(table: &Table, r: &mut Reader, image: &Image, nfunctions: usize, opcode_of: &mut [u32], g: &mut Graph) -> Result<(), String> {
    g.clear();
    let nstrings = image.strings.len();
    let name = r.index(nstrings, "function name")?;
    let module = r.index(nstrings, "module name")?;
    let path = r.optional(nstrings, "source path")?;
    let nparams = r.word()?;
    if nparams >= 240 { return Err("parameter count".into()); }
    let vararg = match r.word()? { 0 => false, 1 => true, _ => return Err("vararg flag".into()) };
    let sig = r.index(nstrings, "signature")?;
    if image.strings[sig as usize].len() != nparams as usize || image.strings[sig as usize].iter().any(|c| !matches!(c, b'v' | b'f')) { return Err("signature does not match the parameters".into()); }
    let ret = r.word()?;
    if ret != b'v' as u32 && ret != b'f' as u32 { return Err("return class".into()); }
    let flags = r.word()?;
    if flags > 3 { return Err("function flags".into()); }
    let (map, register_form) = (flags & 1 != 0, flags & 2 != 0);
    let registers = [r.word()?, r.word()?, r.word()?];
    if register_form && (registers[0] == 0 || registers[0] > 255 || registers[1] > 255 || registers[2] > 255) { return Err("register counts".into()); }
    let mut constants = std::mem::take(&mut g.constants);
    for _ in 0..r.count(8)? {
        let kind = r.word()?;
        let payload = match kind {
            0..=2 => { r.word()?; 0 }
            3 => r.index(image.floats.len(), "numeric constant")?,
            4 | 5 | 6 | 7 => r.index(nstrings, "constant text")?,
            8 => r.index(nfunctions, "function constant")?,
            _ => return Err("constant kind".into()),
        };
        constants.push(Constant { kind, payload });
    }
    let mut positions = std::mem::take(&mut g.positions);
    for _ in 0..r.count(8)? { positions.push((r.word()?, r.word()?)); }
    if register_form {
        g.name = name; g.module = module; g.path = path; g.nparams = nparams; g.vararg = vararg; g.sig = sig; g.ret = ret; g.map = map; g.register_form = true; g.registers = registers;
        g.constants = constants; g.positions = positions;
        return decode_registers(table, r, image, nfunctions, opcode_of, g);
    }
    let mut certificates = std::mem::take(&mut g.certificates);
    let ncerts = r.count(12)?;
    for _ in 0..ncerts { certificates.push([r.word()?, r.word()?, r.word()?]); }
    let nvalues = r.count(8)?;
    let mut classes = std::mem::take(&mut g.classes);
    for _ in 0..nvalues { let c = r.word()?; if c > 3 { return Err("value class".into()); } classes.push(c as u8); }
    let mut slots = std::mem::take(&mut g.slots);
    for _ in 0..nvalues { let s = r.word()?; if s >= 256 { return Err("slot hint".into()); } slots.push(s); }
    for c in &mut certificates { for v in c.iter_mut() { if *v as usize >= nvalues { return Err("certificate value".into()); } } }
    let nblocks = r.count(16)?;
    if nblocks == 0 || nblocks > 100_000 { return Err("block count".into()); }
    g.name = name; g.module = module; g.path = path; g.nparams = nparams; g.vararg = vararg; g.sig = sig; g.ret = ret; g.map = map; g.register_form = false; g.registers = registers;
    g.constants = constants; g.positions = positions; g.certificates = certificates; g.classes = classes; g.slots = slots;
    g.blocks.reserve(nblocks);
    for _ in 0..nblocks {
        let start = g.values.len() as u32;
        let len = r.count(4)? as u32;
        for _ in 0..len { g.values.push(r.index(nvalues, "block parameter")?); }
        let params = Span { start, len };
        let start = g.insts.len() as u32;
        let len = r.count(12)? as u32;
        g.insts.reserve(len as usize);
        g.pos.reserve(len as usize);
        g.cert.reserve(len as usize);
        for _ in 0..len {
            let name = r.index(nstrings, "opcode")?;
            let mut op = opcode_of[name as usize];
            if op == NONE {
                op = table.index(image.text(name)).ok_or_else(|| format!("unknown opcode {}", image.text(name)))?;
                opcode_of[name as usize] = op;
            }
            let sig = &table.entries[op as usize];
            if sig.terminator { return Err(format!("terminator {} inside a block", sig.name)); }
            let mut words = [0u32; 8];
            words[0] = op;
            for (i, letter) in sig.operands.bytes().enumerate() {
                words[i + 1] = match letter {
                    b'v' | b'i' | b'f' | b'x' | b'V' | b'I' | b'F' | b'X' => r.index(nvalues, "operand value")?,
                    b'k' => r.index(g.constants.len(), "constant operand")?,
                    b'n' => r.index(nfunctions, "function operand")?,
                    b'h' => r.index(image.shapes.len(), "shape operand")?,
                    b's' => r.index(nstrings, "named operand")?,
                    b'L' => r.index(image.wides.len(), "wide literal")?,
                    b'D' => r.index(image.floats.len(), "float literal")?,
                    _ => r.word()?,
                };
            }
            g.insts.push(words);
            g.pos.push(r.optional(g.positions.len(), "position")?);
            g.cert.push(r.optional(ncerts, "certificate")?);
        }
        let insts = Span { start, len };
        let term = r.word()?;
        if term > RETURNS { return Err("terminator kind".into()); }
        let value = r.optional(nvalues, "terminator value")?;
        let constant = r.optional(g.constants.len(), "raise constant")?;
        let count = r.word()?;
        if term == RETURNS && (value == NONE || count == NONE || count > 255) { return Err("returns terminator".into()); }
        let nedges = r.count(8)?;
        let expected = match term { JUMP | PARK => 1, BRANCH => 2, RETURN | RAISE | RETURNS => 0, _ => nedges.max(1) };
        if nedges != expected { return Err("edge count".into()); }
        let start = g.edges.len() as u32;
        for _ in 0..nedges {
            let target = r.index(nblocks, "edge target")?;
            if target == 0 { return Err("edge into the entry block".into()); }
            let len = r.count(4)? as u32;
            let args = Span { start: g.values.len() as u32, len };
            for _ in 0..len { g.values.push(r.index(nvalues, "edge argument")?); }
            g.edges.push(Edge { target, args });
        }
        g.blocks.push(Block { params, insts, term, value, constant, count, edges: Span { start, len: nedges as u32 } });
    }
    let nregions = r.count(24)?;
    if nregions == 0 { return Err("no region tree".into()); }
    for _ in 0..nregions {
        let kind = r.word()?;
        if kind > ELSE { return Err("region kind".into()); }
        let parent = r.optional(nregions, "region parent")?;
        let head = r.index(nblocks, "region head")?;
        let entry = r.optional(nblocks, "region entry")?;
        let continuing = r.optional(nblocks, "region continue block")?;
        let merge = r.optional(nblocks, "region merge")?;
        g.regions.push(Region { kind, parent, head, entry, continuing, merge });
    }
    for _ in 0..nblocks { g.block_region.push(r.index(nregions, "block region")?); }
    match r.word()? {
        0 => {}
        1 => {
            let entrypoint = image.text(r.index(nstrings, "gpu entrypoint")?).to_string();
            let threads = r.word()?;
            let uniform_bytes = r.word()?;
            let count_span = image.text(r.index(nstrings, "gpu count span")?).to_string();
            let names = |r: &mut Reader| -> Result<Vec<String>, String> { let mut out = Vec::new(); for _ in 0..r.count(4)? { out.push(image.text(r.index(nstrings, "gpu name")?).to_string()); } Ok(out) };
            let readonly = names(r)?;
            let writable = names(r)?;
            let uniforms = names(r)?;
            let wgsl = image.text(r.index(nstrings, "gpu wgsl")?).to_string();
            let spirv = image.strings[r.index(nstrings, "gpu spirv")? as usize].clone();
            g.gpu = Some(Box::new(GpuArtifact { entrypoint, threads, uniform_bytes, count_span, readonly, writable, uniforms, wgsl, spirv }));
        }
        _ => return Err("gpu flag".into()),
    }
    Ok(())
}

/// The closed-block verifier: every use is a parameter of its block, an
/// earlier definition in it, or a function parameter; classes match the
/// signature table; edges carry the target's parameters; every block is
/// reachable; the region tree describes the blocks; certificates cite
/// integer values.
pub fn verify(table: &Table, image: &Image, g: &Graph, nfunctions: usize) -> Result<(), String> {
    verify_with(table, image, g, nfunctions, &mut Scratch::default())
}

/// The blocks of a register-form function: per block its instructions, with
/// registers for register operands, its ending, and the blocks it may go to.
fn decode_registers(table: &Table, r: &mut Reader, image: &Image, nfunctions: usize, opcode_of: &mut [u32], g: &mut Graph) -> Result<(), String> {
    let nstrings = image.strings.len();
    let nblocks = r.count(5)?;
    if nblocks == 0 || nblocks > 100_000 { return Err("block count".into()); }
    let register = |w: u32| -> Result<u32, String> { if w > 255 { Err("register operand".into()) } else { Ok(w) } };
    let key = |w: u32| -> Result<u32, String> { if w > 0x3ff { Err("ending register".into()) } else { Ok(w) } };
    g.blocks.reserve(nblocks);
    for _ in 0..nblocks {
        let params = Span { start: 0, len: 0 };
        let start = g.insts.len() as u32;
        let len = r.count(2)? as u32;
        g.insts.reserve(len as usize);
        g.pos.reserve(len as usize);
        g.cert.reserve(len as usize);
        for _ in 0..len {
            let name = r.index(nstrings, "opcode")?;
            let mut op = opcode_of[name as usize];
            if op == NONE {
                op = table.index(image.text(name)).ok_or_else(|| format!("unknown opcode {}", image.text(name)))?;
                opcode_of[name as usize] = op;
            }
            let sig = &table.entries[op as usize];
            if sig.terminator { return Err(format!("terminator {} inside a block", sig.name)); }
            let mut words = [0u32; 8];
            words[0] = op;
            for (i, letter) in sig.operands.bytes().enumerate() {
                words[i + 1] = match letter {
                    b'v' | b'i' | b'f' | b'x' | b'V' | b'I' | b'F' | b'X' | b'w' => register(r.word()?)?,
                    b'k' => r.index(g.constants.len(), "constant operand")?,
                    b'n' => r.index(nfunctions, "function operand")?,
                    b'h' => r.index(image.shapes.len(), "shape operand")?,
                    b's' => r.index(nstrings, "named operand")?,
                    b'L' => r.index(image.wides.len(), "wide literal")?,
                    b'D' => r.index(image.floats.len(), "float literal")?,
                    _ => r.word()?,
                };
            }
            g.insts.push(words);
            g.pos.push(r.optional(g.positions.len(), "position")?);
            g.cert.push(NONE);
        }
        let insts = Span { start, len };
        let term = r.word()?;
        if term > RETURNS || term == SWITCH || term == PARK { return Err("terminator kind".into()); }
        let value = r.word()?;
        if value != NONE { key(value)?; }
        let constant = r.optional(g.constants.len(), "raise constant")?;
        let count = r.word()?;
        if term == RETURNS && (value == NONE || count == NONE || count > 255) { return Err("returns terminator".into()); }
        let ntargets = r.count(1)?;
        let expected = match term { JUMP => 1, BRANCH => 2, _ => 0 };
        if ntargets != expected { return Err("edge count".into()); }
        let start = g.edges.len() as u32;
        for _ in 0..ntargets {
            let target = r.index(nblocks, "edge target")?;
            if target == 0 { return Err("edge into the entry block".into()); }
            g.edges.push(Edge { target, args: Span { start: 0, len: 0 } });
        }
        g.blocks.push(Block { params, insts, term, value, constant, count, edges: Span { start, len: ntargets as u32 } });
    }
    Ok(())
}

/// A register-form function's checks, which make the stream derived from it
/// safe without checking that stream again: every block reached, every
/// register within the frame (windows sized by the opcode table included),
/// physical field plans and SIMD descriptors valid, and endings of the class
/// they need.
fn verify_registers(table: &Table, image: &Image, g: &Graph, scratch: &mut Scratch) -> Result<(), String> {
    use crate::opcodes::{Class, Mode};
    use crate::verify::C;
    let limit = |class: u8| -> usize { (match class { V => g.registers[0] + 1, I | F => g.registers[1], _ => g.registers[2] }) as usize };
    let class_of = |c: C| match c { C::V => V, C::I => I, C::F => F, C::X => X };
    // The boxing register a float return uses sits above the parameters.
    if g.registers[0] < g.nparams + 1 { return Err("frame smaller than its parameters".into()); }
    let seen = &mut scratch.seen;
    let queue = &mut scratch.queue;
    seen.clear(); seen.resize(g.blocks.len(), false);
    queue.clear(); queue.push_back(0usize);
    while let Some(b) = queue.pop_front() {
        if std::mem::replace(&mut seen[b], true) { continue; }
        for e in g.blocks[b].edges.get(&g.edges) { queue.push_back(e.target as usize); }
    }
    if let Some(b) = seen.iter().position(|v| !v) { return Err(format!("block {b} is unreachable")); }
    let rows = crate::opcodes::table().rows();
    for (bid, b) in g.blocks.iter().enumerate() {
        let within = |class: u8, reg: usize| -> Result<(), String> {
            if reg >= limit(class) { Err(format!("block {bid}: register {reg} outside the frame")) } else { Ok(()) }
        };
        for words in b.insts.get(&g.insts) {
            let op = words[0] as usize;
            let sig = &table.entries[op];
            let row = rows.get(op).filter(|r| r.name == sig.name).ok_or_else(|| format!("{} is not an instruction register form holds", sig.name))?;
            // The operands as the derived instruction holds them.
            let mut values = [0i64; 8];
            for (i, letter) in sig.operands.bytes().enumerate() {
                let w = words[i + 1];
                values[i] = match letter {
                    b's' if i == 0 => crate::simd::operation(image.text(w)).map(i64::from).unwrap_or(-1),
                    b's' => crate::simd::ELEMENTS.iter().position(|k| *k == image.text(w)).map(|k| k as i64).unwrap_or(-1),
                    b'L' => image.wides[w as usize],
                    _ => w as i64,
                };
            }
            for (at, spec) in row.operands.iter().enumerate() {
                if spec.mode == Mode::None { continue; }
                if let Some(class) = match spec.class { Class::Reg(_) | Class::ScalarByKind(_) => row.register_class(at, &values).map(class_of), _ => None } {
                    within(class, values[at] as usize)?;
                }
            }
            for window in &row.windows {
                let (first, count) = window.span(&values);
                if count > 0 { within(class_of(window.class), first + count - 1)?; }
            }
            if sig.name == "Simd" {
                let (code, kind, base, argc, source) = (values[0], values[1], values[2], values[3], values[4]);
                let last = (argc as usize).max(crate::simd::result_count(code as u8, argc as usize).saturating_sub(1));
                if code < 0 || kind < 0 || source < 0 || !crate::simd::valid_descriptor(code as u8, kind as u8, source as u8, argc as usize) || base as usize + last > u8::MAX as usize {
                    return Err("invalid SIMD descriptor or argument window".into());
                }
            }
            if sig.name.contains("Phys") {
                // identity and name constants, then ordinal, offset and kind.
                let at = row.operands.iter().position(|o| o.class == Class::Const).unwrap_or(0);
                crate::verify::physical_plan(sig.name, values[at + 4] as u8, values[at + 3] as u32)?;
            }
        }
        if b.value != NONE {
            let (class, reg) = ((b.value >> 8) as u8, (b.value & 0xff) as usize);
            let ok = match b.term { BRANCH => matches!(class, V | I), RETURN => matches!(class, V | I | F), RETURNS => class == V, _ => false };
            if !ok { return Err(format!("block {bid}: ending value class")); }
            let n = if b.term == RETURNS { let n = b.count as u8; if n >= 128 { (n & 127) as usize + 8 } else { n as usize }.max(1) } else { 1 };
            within(class, reg + n - 1)?;
        } else if matches!(b.term, BRANCH | RETURNS) {
            return Err(format!("block {bid}: ending without a value"));
        }
        if b.term == RAISE && b.constant == NONE { return Err(format!("block {bid}: raise without a constant")); }
    }
    Ok(())
}

/// The verifier's working vectors, kept across functions by a loader.
#[derive(Default)]
pub struct Scratch { owner: Vec<u32>, defined: Vec<bool>, seen: Vec<bool>, queue: VecDeque<usize>, occupied: Vec<u32> }

pub fn verify_with(table: &Table, image: &Image, g: &Graph, nfunctions: usize, scratch: &mut Scratch) -> Result<(), String> {
    if g.register_form { return verify_registers(table, image, g, scratch); }
    let nvalues = g.classes.len();
    let nparams = g.nparams as usize;
    if nvalues < nparams { return Err("fewer values than parameters".into()); }
    for p in 0..nparams { if g.classes[p] != V || g.slots[p] != p as u32 + 1 { return Err("function parameters are the first value ids".into()); } }
    let Scratch { owner, defined, seen, queue, occupied } = scratch;
    owner.clear(); owner.resize(nvalues, NONE);
    defined.clear(); defined.resize(nvalues, false);
    for p in 0..nparams { defined[p] = true; }
    // Reachability over the edges from the entry.
    seen.clear(); seen.resize(g.blocks.len(), false);
    queue.clear(); queue.push_back(0usize);
    while let Some(b) = queue.pop_front() {
        if std::mem::replace(&mut seen[b], true) { continue; }
        for e in g.blocks[b].edges.get(&g.edges) { queue.push_back(e.target as usize); }
    }
    if let Some(b) = seen.iter().position(|v| !v) { return Err(format!("block {b} is unreachable")); }
    let (mut owner, mut defined, mut occupied) = (owner, defined, occupied);
    for (bid, b) in g.blocks.iter().enumerate() {
        let bid = bid as u32;
        occupied.clear();
        let define = |v: u32, owner: &mut [u32], defined: &mut [bool], occupied: &mut Vec<u32>| -> Result<(), String> {
            if (v as usize) < nparams { return Err("function parameter defined again".into()); }
            if defined[v as usize] { return Err(format!("value {v} defined twice")); }
            let key = (g.classes[v as usize] as u32) << 8 | g.slots[v as usize];
            if occupied.contains(&key) { return Err(format!("overlapping slot hints in block {bid}")); }
            occupied.push(key);
            defined[v as usize] = true;
            owner[v as usize] = bid;
            Ok(())
        };
        let usable = |v: u32, owner: &[u32]| (v as usize) < nparams || owner[v as usize] == bid;
        let use_value = |v: u32, class: u8, owner: &[u32]| -> Result<(), String> {
            if !usable(v, owner) { return Err(format!("block {bid} uses value {v} outside its closed block")); }
            if g.classes[v as usize] != class { return Err(format!("block {bid}: value {v} is not of class {class}")); }
            Ok(())
        };
        if bid == 0 && b.params.len != 0 { return Err("entry parameters come from the frame".into()); }
        for &p in b.params.get(&g.values) { define(p, &mut owner, &mut defined, &mut occupied)?; }
        for (k, words) in b.insts.get(&g.insts).iter().enumerate() {
            let sig = &table.entries[words[0] as usize];
            let mut result = None;
            for (i, letter) in sig.operands.bytes().enumerate() {
                let w = words[i + 1];
                match letter {
                    b'v' | b'i' | b'f' | b'x' => use_value(w, class_of(letter).unwrap(), &owner)?,
                    b'V' | b'I' | b'F' | b'X' => {
                        if g.classes[w as usize] != class_of(letter).unwrap() { return Err(format!("{}: result class", sig.name)); }
                        result = Some(w);
                    }
                    b's' => {
                        let name = image.text(w);
                        let ok = match (sig.name, i) { ("VOp", 0) | ("Simd", 0) => crate::simd::operation(name).is_some(), _ => crate::simd::ELEMENTS.contains(&name) };
                        if !ok { return Err(format!("{}: unknown name {name}", sig.name)); }
                    }
                    _ => {}
                }
            }
            if let Some(d) = result { define(d, &mut owner, &mut defined, &mut occupied)?; }
            let at = b.insts.start as usize + k;
            if g.cert[at] != NONE { if !matches!(sig.name, "SpanLoad" | "SpanStore" | "VLoad" | "VStore" | "FLoad" | "FStore" | "VLoadM" | "VStoreM") { return Err(format!("{}: certificate on an instruction that is not a span access", sig.name)); } }
        }
        let value_class = |v: u32| g.classes[v as usize];
        match b.term {
            BRANCH => { if b.value == NONE || !usable(b.value, &owner) || !matches!(value_class(b.value), I | V) { return Err(format!("block {bid}: branch condition")); } }
            SWITCH => { if b.value == NONE || !usable(b.value, &owner) || value_class(b.value) != I { return Err(format!("block {bid}: switch index")); } }
            RETURN => { if b.value != NONE && (!usable(b.value, &owner) || !matches!(value_class(b.value), F | V | I)) { return Err(format!("block {bid}: return value")); } }
            PARK => { if b.value == NONE || !usable(b.value, &owner) || !matches!(value_class(b.value), F | V) { return Err(format!("block {bid}: park value")); } }
            RAISE => { if b.constant == NONE { return Err(format!("block {bid}: raise without a constant")); } }
            RETURNS => { if b.value == NONE || !usable(b.value, &owner) || value_class(b.value) != V { return Err(format!("block {bid}: returns window")); } }
            _ => {}
        }
        for e in b.edges.get(&g.edges) {
            let target = &g.blocks[e.target as usize];
            if e.args.len != target.params.len { return Err(format!("block {bid}: edge to {} carries {} of {} parameters", e.target, e.args.len, target.params.len)); }
            for (&a, &p) in e.args.get(&g.values).iter().zip(target.params.get(&g.values)) { use_value(a, g.classes[p as usize], &owner)?; }
        }
    }
    if let Some(v) = defined.iter().position(|d| !d) { return Err(format!("value {v} is never defined")); }
    for c in &g.certificates { if c.iter().any(|&v| g.classes[v as usize] != I) { return Err("certificate cites values outside the integer class".into()); } }
    for &k in &g.constants { if k.kind == 8 && k.payload as usize >= nfunctions { return Err("function constant outside the image".into()); } }
    verify_regions(g)
}

/// The region tree is verified, never inferred: parents precede children,
/// a loop's header branches to its merge and its continue block jumps back,
/// an arm starts at its branch's edge, and every edge stays in its region,
/// enters a child at its entry, or leaves to the merge of the region it is
/// in.
fn verify_regions(g: &Graph) -> Result<(), String> {
    let regions = &g.regions;
    let root = &regions[0];
    if root.kind != BODY || root.parent != NONE || root.head != 0 || root.entry != 0 || root.merge != NONE { return Err("region 0 is not the function body".into()); }
    for (r, region) in regions.iter().enumerate().skip(1) {
        if region.kind == BODY || region.parent == NONE || region.parent as usize >= r { return Err(format!("region {r} is not below its parent")); }
    }
    let region_of = |b: u32| g.block_region[b as usize];
    let branch_target = |b: u32, which: usize| -> Option<u32> { let block = &g.blocks[b as usize]; if block.term != BRANCH { return None; } Some(block.edges.get(&g.edges)[which].target) };
    for (r, region) in regions.iter().enumerate().skip(1) {
        let r = r as u32;
        match region.kind {
            LOOP => {
                let (header, continuing, merge) = (region.head, region.continuing, region.merge);
                if continuing == NONE || merge == NONE || region.entry == NONE { return Err(format!("loop region {r} is incomplete")); }
                if region_of(header) != r || region_of(continuing) != r || region_of(region.entry) != r { return Err(format!("loop region {r}: its header, entry or continue block lies elsewhere")); }
                if region_of(merge) != region.parent { return Err(format!("loop region {r}: its merge is not in the parent region")); }
                if branch_target(header, 0) != Some(region.entry) || branch_target(header, 1) != Some(merge) { return Err(format!("loop region {r}: header does not branch to its body and merge")); }
                let c = &g.blocks[continuing as usize];
                if c.term != JUMP || c.edges.get(&g.edges)[0].target != header { return Err(format!("loop region {r}: continue block does not jump to the header")); }
            }
            THEN | ELSE => {
                let merge = region.merge;
                if merge == NONE || region_of(region.head) != region.parent { return Err(format!("arm region {r}: its branch is not in the parent region")); }
                let which = if region.kind == THEN { 0 } else { 1 };
                let target = branch_target(region.head, which).ok_or_else(|| format!("arm region {r}: head is not a branch"))?;
                if region.entry == NONE { if target != merge { return Err(format!("arm region {r}: an empty arm must reach the merge")); } }
                else if target != region.entry || region_of(region.entry) != r { return Err(format!("arm region {r}: the branch does not enter it")); }
            }
            _ => return Err(format!("region {r} kind")),
        }
    }
    for (bid, b) in g.blocks.iter().enumerate() {
        let from = region_of(bid as u32);
        for e in b.edges.get(&g.edges) {
            let to = region_of(e.target);
            let same = to == from;
            let child = to != from && regions[to as usize].parent == from && (regions[to as usize].entry == e.target || regions[to as usize].kind == LOOP && regions[to as usize].head == e.target);
            let back = regions[from as usize].kind == LOOP && regions[from as usize].head == e.target;
            let exit = (|| { let mut r = from; loop { let region = &regions[r as usize]; if region.merge == e.target && region.parent == to { return true; } if r == 0 || region.kind == LOOP { return false; } r = region.parent; } })();
            if !(same || child || back || exit) { return Err(format!("edge from block {bid} to {} crosses regions", e.target)); }
        }
    }
    // Every region holds a block, except an arm the branch skips to the merge.
    let mut reached = vec![false; regions.len()];
    for &r in &g.block_region { reached[r as usize] = true; }
    for (r, region) in regions.iter().enumerate() {
        let empty_arm = matches!(region.kind, THEN | ELSE) && region.entry == NONE;
        if !reached[r] && !empty_arm { return Err(format!("region {r} holds no block")); }
        if reached[r] && empty_arm { return Err(format!("region {r} is an empty arm holding a block")); }
    }
    Ok(())
}

/// What a derivation needs from the VM: interned constants, and where this
/// image's functions and shapes land.
pub struct Derivation<'a> { pub it: &'a mut Interp, pub base: u32, pub shape_ids: &'a [u32] }

/// The interpreter stream of one graph: slot layout from the hints, parallel
/// edge copies through one scratch register per class, blocks in order with
/// the jump to the next block elided. `graph.lower` in Nupp is the same
/// algorithm; the two streams are held equal instruction for instruction.
pub fn derive(table: &Table, image: &Image, g: &Graph, d: &mut Derivation) -> Result<Function, String> {
    let nparams = g.nparams as u32;
    let value_base = nparams + 2;
    let counts = {
        let mut counts = [0u32; 4];
        for (v, &class) in g.classes.iter().enumerate() { if v >= nparams as usize { counts[class as usize] = counts[class as usize].max(g.slots[v] + 1); } }
        counts
    };
    // A register-form operand is its register; an SSA value has the register
    // its slot lays out, and an ending names a key in register form.
    let form = g.register_form;
    let physical = |v: u32| -> u32 { if form { v } else if g.classes[v as usize] == V { if v < nparams { v + 1 } else { value_base + g.slots[v as usize] } } else { g.slots[v as usize] } };
    let end_reg = |v: u32| -> u32 { if form { v & 0xff } else { physical(v) } };
    let end_class = |v: u32| -> u8 { if form { (v >> 8) as u8 } else { g.classes[v as usize] } };
    let scratch = |class: u8| -> u32 { if class == V { value_base + counts[0] } else { counts[class as usize] } };
    if !form && (counts[1] >= 237 || counts[2] >= 237 || counts[3] >= 249 || value_base + counts[0] >= 241) { return Err("graph register capacity".into()); }
    let r8 = |n: u32, what: &str| -> Result<u8, String> { u8::try_from(n).map_err(|_| format!("{what} {n} does not fit a register")) };
    let r16 = |n: u32, what: &str| -> Result<u16, String> { u16::try_from(n).map_err(|_| format!("{what} {n} does not fit sixteen bits")) };
    let wide = |n: u32| image.wides[n as usize];
    let i32_of = |n: u32| -> Result<i32, String> { i32::try_from(image.wides[n as usize]).map_err(|_| "offset literal does not fit".to_string()) };
    let simd_op = |n: u32| crate::simd::operation(image.text(n)).unwrap();
    let element = |n: u32| crate::simd::ELEMENTS.iter().position(|k| *k == image.text(n)).unwrap() as u8;
    let shape = |n: u32| -> Result<u32, String> { d.shape_ids.get(n as usize).copied().ok_or_else(|| "shape outside the loaded shapes".to_string()) };
    let mut consts = Vec::with_capacity(g.constants.len());
    for k in &g.constants {
        consts.push(match k.kind {
            0 => Value::NIL, 1 => Value::TRUE, 2 => Value::FALSE,
            3 => Value::num(image.floats[k.payload as usize]),
            4 | 5 => {
                let text = image.text(k.payload);
                let negative = text.starts_with('-');
                let digits = text.strip_prefix('-').unwrap_or(text);
                let bits = if let Some(hex) = digits.strip_prefix("0x").or_else(|| digits.strip_prefix("0X")) { u64::from_str_radix(hex, 16) } else { digits.parse::<u64>() }.map_err(|_| "invalid wide integer constant".to_string())?;
                if negative && (k.kind == 5 || bits > 1u64 << 63) { return Err("wide integer constant out of range".into()); }
                let v = d.it.box_integer(crate::numeric::Integer { bits: if negative { bits.wrapping_neg() } else { bits }, unsigned: k.kind == 5 });
                d.it.handles.push(v); v
            }
            6 => { let v = d.it.string_of(&image.strings[k.payload as usize]); d.it.handles.push(v); v }
            7 => Value::builtin(crate::builtins::id_of(image.text(k.payload)).ok_or_else(|| format!("unknown builtin {}", image.text(k.payload)))?),
            _ => Value::func(d.base + k.payload),
        });
    }
    let mut code: Vec<Op> = Vec::with_capacity(g.insts.len() + 2 * g.blocks.len());
    let mut debug: Vec<(u32, u32)> = Vec::with_capacity(g.insts.len() + 2 * g.blocks.len());
    let mut jump_tables: Vec<(i32, Vec<i32>)> = Vec::new();
    let mut starts = vec![0usize; g.blocks.len()];
    // (pc, target block, which offset field: 0 the only one, 1 the second)
    let mut patches: Vec<(usize, u32)> = Vec::new();
    let mut table_patches: Vec<(usize, usize, Vec<Result<u32, usize>>)> = Vec::new();
    let mut length_slots: Vec<(u32, u8)> = Vec::new();
    for words in g.blocks[0].insts.get(&g.insts) { if table.entries[words[0] as usize].name == "SpanLen" { length_slots.push((words[2], physical(words[1]) as u8)); } }
    let move_op = |class: u8, to: u8, from: u8| match class { V => Op::Move(to, from), I => Op::IMov(to, from), F => Op::FMov(to, from), _ => Op::VMov(to, from) };
    let copies = |code: &mut Vec<Op>, debug: &mut Vec<(u32, u32)>, patches: &mut Vec<(usize, u32)>, e: &Edge, fallthrough: Option<u32>| -> Result<(), String> {
        let target = &g.blocks[e.target as usize];
        for class in [V, I, F, X] {
            let mut pending: Vec<(u32, u32)> = Vec::new();
            for (&dst, &src) in target.params.get(&g.values).iter().zip(e.args.get(&g.values)) {
                if g.classes[dst as usize] != class { continue; }
                let (to, from) = (physical(dst), physical(src));
                if to == from { continue; }
                if pending.iter().any(|&(d, _)| d == to) { return Err("conflicting preferred slots".into()); }
                pending.push((to, from));
            }
            pending.sort_by_key(|&(to, _)| to);
            let mut remaining = pending.len();
            while remaining > 0 {
                let mut progress = false;
                for i in 0..pending.len() {
                    let (to, from) = pending[i];
                    if from == NONE { continue; }
                    let read = pending.iter().any(|&(_, f)| f != NONE && f == to);
                    if read { continue; }
                    code.push(move_op(class, r8(to, "copy")?, r8(from, "copy")?));
                    debug.push((0, 0));
                    pending[i].1 = NONE;
                    remaining -= 1;
                    progress = true;
                }
                if !progress {
                    let first = pending.iter().find(|&&(_, f)| f != NONE).unwrap().0;
                    let temp = scratch(class);
                    code.push(move_op(class, r8(temp, "scratch")?, r8(first, "copy")?));
                    debug.push((0, 0));
                    for p in pending.iter_mut() { if p.1 == first { p.1 = temp; } }
                }
            }
        }
        if fallthrough != Some(e.target) { patches.push((code.len(), e.target)); code.push(Op::Jmp(0)); debug.push((0, 0)); }
        Ok(())
    };
    for (bid, b) in g.blocks.iter().enumerate() {
        starts[bid] = code.len();
        for (k, words) in b.insts.get(&g.insts).iter().enumerate() {
            let at = b.insts.start as usize + k;
            let from = code.len();
            let sig = &table.entries[words[0] as usize];
            // Operands in VM order, registers made physical, window bases offset.
            let mut o = [0u32; 7];
            for (i, letter) in sig.operands.bytes().enumerate() {
                o[i] = match letter { b'v' | b'i' | b'f' | b'x' | b'V' | b'I' | b'F' | b'X' => physical(words[i + 1]), b'w' => if form { words[i + 1] } else { value_base + words[i + 1] }, _ => words[i + 1] };
            }
            let a = |i: usize| -> Result<u8, String> { r8(o[i], sig.name) };
            let h = |i: usize| -> Result<u16, String> { r16(o[i], sig.name) };
            let flag = |i: usize| -> Result<bool, String> { match o[i] { 0 => Ok(false), 1 => Ok(true), _ => Err(format!("{}: flag operand", sig.name)) } };
            let physical_field = |start: usize| -> Result<crate::storage::PhysicalField, String> { Ok(crate::storage::PhysicalField { identity: h(start)?, name: h(start + 1)?, ordinal: h(start + 2)?, offset: o[start + 3], kind: a(start + 4)? }) };
            let hot = match sig.hot {
                1 => Some(Op::Move(a(0)?, a(1)?)), 2 => Some(Op::K(a(0)?, h(1)?)), 3 => Some(Op::SetIdx(a(0)?, a(1)?, a(2)?)), 4 => Some(Op::GetField(a(0)?, a(1)?, h(2)?)),
                5 => Some(Op::GetCell(a(0)?, a(1)?)), 6 => Some(Op::PadResults(a(0)?, a(1)?)), 7 => Some(Op::CallDyn(a(0)?, a(1)?, a(2)?)), 8 => Some(Op::NewTableN(a(0)?, a(1)?, a(2)?)),
                9 => Some(Op::Nil(a(0)?)), 10 => Some(Op::Eq(a(0)?, a(1)?, a(2)?)), 11 => Some(Op::GetIdx(a(0)?, a(1)?, a(2)?)), 12 => Some(Op::SetSlot(a(0)?, h(1)?, a(2)?, shape(o[3])?)),
                13 => Some(Op::GetUpval(a(0)?, a(1)?)), 14 => Some(Op::CallK(r16(d.base + o[0], "known callee")?, a(1)?, a(2)?, a(3)?, a(4)?)), 15 => Some(Op::GetSlot(a(0)?, a(1)?, h(2)?, shape(o[3])?)),
                16 => Some(Op::Concat(a(0)?, a(1)?, a(2)?)), 17 => Some(Op::SetField(a(0)?, h(1)?, a(2)?)), 18 => Some(Op::NewCell(a(0)?, a(1)?)), 19 => Some(Op::NewClosure(a(0)?, d.base + o[1], a(2)?, a(3)?)),
                20 => Some(Op::Len(a(0)?, a(1)?)), 21 => Some(Op::Not(a(0)?, a(1)?)), 22 => Some(Op::Add(a(0)?, a(1)?, a(2)?)), 23 => Some(Op::NewRecord(a(0)?, shape(o[1])?)),
                24 => Some(Op::Ne(a(0)?, a(1)?, a(2)?)), 25 => Some(Op::Require(a(0)?, h(1)?)), 26 => Some(Op::CallMethod(h(0)?, a(1)?, a(2)?)), 27 => Some(Op::SetCell(a(0)?, a(1)?)),
                _ => None,
            };
            if let Some(op) = hot { code.push(op); } else { match sig.name {
                "U32Add" | "U32Sub" => { code.push(if sig.name == "U32Add" { Op::IAdd(a(0)?, a(1)?, a(2)?) } else { Op::ISub(a(0)?, a(1)?, a(2)?) }); code.push(Op::IMaskU32(a(0)?, a(0)?)); }
                "U32Load" | "U32Store" => {
                    let store = sig.name == "U32Store";
                    let (param, index) = if store { (a(0)?, a(1)?) } else { (a(1)?, a(2)?) };
                    let (one, vector) = (r8(scratch(I), "scratch")?, r8(scratch(X), "scratch")?);
                    code.push(Op::IK(one, 1));
                    code.push(Op::SpanBounds(param, index, one, 4, store));
                    if store { code.push(Op::VSplatN(vector, a(2)?, 4)); code.push(Op::SpanStore(param, index, vector, one, 4, 0, 1)); }
                    else { code.push(Op::SpanLoad(vector, param, index, one, 4, 0, 1)); code.push(Op::VExtractN(a(0)?, vector, 4, 0)); }
                }
                "SpanEqual" => {
                    let flag = r8(scratch(I), "scratch")?;
                    let len = |v: u32| length_slots.iter().find(|&&(p, _)| p == v).map(|&(_, s)| s).ok_or_else(|| "span equality on a span without a length".to_string());
                    code.push(Op::ICmpNe(flag, len(words[1])?, len(words[2])?));
                    code.push(Op::JmpIfIZero(flag, 1));
                    code.push(Op::Raise(h(2)?));
                }
                "VSplatI" => code.push(Op::VSplatN(a(0)?, a(1)?, a(2)?)),
                "VExtractI" => code.push(Op::VExtractN(a(0)?, a(1)?, a(2)?, a(3)?)),
                "K" => code.push(Op::K(a(0)?, h(1)?)), "Move" => code.push(Op::Move(a(0)?, a(1)?)), "Nil" => code.push(Op::Nil(a(0)?)),
                "Add" => code.push(Op::Add(a(0)?, a(1)?, a(2)?)), "Sub" => code.push(Op::Sub(a(0)?, a(1)?, a(2)?)), "Mul" => code.push(Op::Mul(a(0)?, a(1)?, a(2)?)),
                "Lt" => code.push(Op::Lt(a(0)?, a(1)?, a(2)?)), "Le" => code.push(Op::Le(a(0)?, a(1)?, a(2)?)), "Eq" => code.push(Op::Eq(a(0)?, a(1)?, a(2)?)), "Ne" => code.push(Op::Ne(a(0)?, a(1)?, a(2)?)),
                "GetIdxI" => code.push(Op::GetIdxI(a(0)?, a(1)?, a(2)?)), "SetIdxI" => code.push(Op::SetIdxI(a(0)?, a(1)?, a(2)?)),
                "IUnbox" => code.push(Op::IUnbox(a(0)?, a(1)?)), "UUnbox" => code.push(Op::UUnbox(a(0)?, a(1)?)),
                "ICmpSLt" => code.push(Op::ICmpSLt(a(0)?, a(1)?, a(2)?)), "ICmpSLe" => code.push(Op::ICmpSLe(a(0)?, a(1)?, a(2)?)), "IShl" => code.push(Op::IShl(a(0)?, a(1)?, a(2)?)), "IShrU" => code.push(Op::IShrU(a(0)?, a(1)?, a(2)?)),
                "IOr" => code.push(Op::IOr(a(0)?, a(1)?, a(2)?)), "IBswap32" => code.push(Op::IBswap32(a(0)?, a(1)?)), "ICmpEq" => code.push(Op::ICmpEq(a(0)?, a(1)?, a(2)?)), "ICmpNe" => code.push(Op::ICmpNe(a(0)?, a(1)?, a(2)?)),
                "BytesLen" => code.push(Op::BytesLen(a(0)?, a(1)?)), "LoadU8" => code.push(Op::LoadU8(a(0)?, a(1)?, a(2)?)), "LoadU8K" => code.push(Op::LoadU8K(a(0)?, a(1)?, a(2)?)), "LoadU32W" => code.push(Op::LoadU32W(a(0)?, a(1)?, a(2)?)),
                "StoreU8" => code.push(Op::StoreU8(a(0)?, a(1)?, a(2)?)), "StoreU32" => code.push(Op::StoreU32(a(0)?, a(1)?, a(2)?)), "NewBytes" => code.push(Op::NewBytes(a(0)?, a(1)?)), "BytesToStr" => code.push(Op::BytesToStr(a(0)?, a(1)?, a(2)?)),
                "Mod" => code.push(Op::Mod(a(0)?, a(1)?, a(2)?)), "Div" => code.push(Op::Div(a(0)?, a(1)?, a(2)?)), "FMod" => code.push(Op::FMod(a(0)?, a(1)?, a(2)?)),
                "Require" => code.push(Op::Require(a(0)?, h(1)?)), "SetMethod" => code.push(Op::SetMethod(shape(o[0])?, h(1)?, a(2)?)), "RequireV" => code.push(Op::RequireV(a(0)?, a(1)?)), "NewTableN" => code.push(Op::NewTableN(a(0)?, a(1)?, a(2)?)),
                "Truthy" => code.push(Op::Truthy(a(0)?, a(1)?)), "NewBuffer" => code.push(Op::NewBuffer(a(0)?)), "BufAppend" => code.push(Op::BufAppend(a(0)?, a(1)?)), "BufAppendSub" => code.push(Op::BufAppendSub(a(0)?, a(1)?, a(2)?, a(3)?)),
                "Substring" => code.push(Op::Substring(a(0)?, a(1)?, a(2)?, a(3)?)), "BufFinish" => code.push(Op::BufFinish(a(0)?, a(1)?)),
                "Call" => code.push(Op::Call(d.base + o[0], a(1)?, a(2)?)), "CallT" => code.push(Op::CallT(d.base + o[0], a(1)?, a(2)?, a(3)?)), "CallDyn" => code.push(Op::CallDyn(a(0)?, a(1)?, a(2)?)),
                "CallK" => code.push(Op::CallK(r16(d.base + o[0], "known callee")?, a(1)?, a(2)?, a(3)?, a(4)?)), "StrByte" => code.push(Op::StrByte(a(0)?, a(1)?, a(2)?)),
                "Pow" => code.push(Op::Pow(a(0)?, a(1)?, a(2)?)), "IDiv" => code.push(Op::IDiv(a(0)?, a(1)?, a(2)?)), "IXor" => code.push(Op::IXor(a(0)?, a(1)?, a(2)?)), "INot" => code.push(Op::INot(a(0)?, a(1)?)),
                "NewTable" => code.push(Op::NewTable(a(0)?)), "GetIdx" => code.push(Op::GetIdx(a(0)?, a(1)?, a(2)?)), "SetIdx" => code.push(Op::SetIdx(a(0)?, a(1)?, a(2)?)), "GetField" => code.push(Op::GetField(a(0)?, a(1)?, h(2)?)),
                "GetPhys" => code.push(Op::GetPhys(a(0)?, a(1)?, physical_field(2)?)), "GetPhysF" => code.push(Op::GetPhysF(a(0)?, a(1)?, physical_field(2)?)), "GetPhysI" => code.push(Op::GetPhysI(a(0)?, a(1)?, physical_field(2)?)), "GetPhysU" => code.push(Op::GetPhysU(a(0)?, a(1)?, physical_field(2)?)),
                "SetPhys" => code.push(Op::SetPhys(a(0)?, physical_field(1)?, a(6)?)), "SetPhysF" => code.push(Op::SetPhysF(a(0)?, physical_field(1)?, a(6)?)), "SetPhysI" => code.push(Op::SetPhysI(a(0)?, physical_field(1)?, a(6)?)),
                "SetField" => code.push(Op::SetField(a(0)?, h(1)?, a(2)?)), "NewRecord" => code.push(Op::NewRecord(a(0)?, shape(o[1])?)), "GetSlot" => code.push(Op::GetSlot(a(0)?, a(1)?, h(2)?, shape(o[3])?)), "SetSlot" => code.push(Op::SetSlot(a(0)?, h(1)?, a(2)?, shape(o[3])?)),
                "Defer" => code.push(Op::Defer(a(0)?, a(1)?)), "DeferMethod" => code.push(Op::DeferMethod(a(0)?, h(1)?)), "Disarm" => code.push(Op::Disarm(a(0)?)), "DisarmAt" => code.push(Op::DisarmAt(h(0)?)), "RearmAt" => code.push(Op::RearmAt(h(0)?, a(1)?, a(2)?)),
                "CleanupLive" => code.push(Op::CleanupLive(a(0)?, h(1)?)), "AffineMark" => code.push(Op::AffineMark(a(0)?, a(1)?)), "AffineEnter" => code.push(Op::AffineEnter), "Unwind" => code.push(Op::Unwind(h(0)?)), "Checkpoint" => code.push(Op::Checkpoint),
                "Concat" => code.push(Op::Concat(a(0)?, a(1)?, a(2)?)), "Not" => code.push(Op::Not(a(0)?, a(1)?)), "Neg" => code.push(Op::Neg(a(0)?, a(1)?)), "Len" => code.push(Op::Len(a(0)?, a(1)?)),
                "CallMethod" => code.push(Op::CallMethod(h(0)?, a(1)?, a(2)?)), "PCall" => code.push(Op::PCall(a(0)?, a(1)?)),
                "TagCheckRec" => code.push(Op::TagCheckRec(a(0)?, a(1)?, shape(o[2])?)), "TagCheckNum" => code.push(Op::TagCheckNum(a(0)?, a(1)?)), "TagCheckInt" => code.push(Op::TagCheckInt(a(0)?, a(1)?, flag(2)?)), "TagCheckStr" => code.push(Op::TagCheckStr(a(0)?, a(1)?)),
                "IsRec" => code.push(Op::IsRec(a(0)?, a(1)?, shape(o[2])?)), "PadResults" => code.push(Op::PadResults(a(0)?, a(1)?)), "Scalar" => code.push(Op::Scalar(a(0)?, a(1)?, a(2)?, a(3)?)), "VarargN" => code.push(Op::VarargN(a(0)?, a(1)?)), "VarargTable" => code.push(Op::VarargTable(a(0)?)),
                "NewClosure" => code.push(Op::NewClosure(a(0)?, d.base + o[1], a(2)?, a(3)?)), "NewCell" => code.push(Op::NewCell(a(0)?, a(1)?)), "GetCell" => code.push(Op::GetCell(a(0)?, a(1)?)), "SetCell" => code.push(Op::SetCell(a(0)?, a(1)?)), "GetUpval" => code.push(Op::GetUpval(a(0)?, a(1)?)),
                "FBox" => code.push(Op::FBox(a(0)?, a(1)?)), "IBox" => code.push(Op::IBox(a(0)?, a(1)?)), "UBox" => code.push(Op::UBox(a(0)?, a(1)?)),
                "GetSlotF" => code.push(Op::GetSlotF(a(0)?, a(1)?, h(2)?, shape(o[3])?)), "SetSlotF" => code.push(Op::SetSlotF(a(0)?, h(1)?, a(2)?, shape(o[3])?)),
                "FDiv" => code.push(Op::FDiv(a(0)?, a(1)?, a(2)?)), "FNeg" => code.push(Op::FNeg(a(0)?, a(1)?)), "LenF" => code.push(Op::LenF(a(0)?, a(1)?)), "GetIdxF" => code.push(Op::GetIdxF(a(0)?, a(1)?, a(2)?)), "SetIdxF" => code.push(Op::SetIdxF(a(0)?, a(1)?, a(2)?)),
                "FCmpEq" => code.push(Op::FCmpEq(a(0)?, a(1)?, a(2)?)), "FCmpNe" => code.push(Op::FCmpNe(a(0)?, a(1)?, a(2)?)), "BoolFromI" => code.push(Op::BoolFromI(a(0)?, a(1)?)),
                "IK" => code.push(Op::IK(a(0)?, wide(o[1]))), "IAdd" => code.push(Op::IAdd(a(0)?, a(1)?, a(2)?)), "IAddK" => code.push(Op::IAddK(a(0)?, a(1)?, wide(o[2]))), "FK" => code.push(Op::FK(a(0)?, image.floats[o[1] as usize])),
                "FUnbox" => code.push(Op::FUnbox(a(0)?, a(1)?)), "ISub" => code.push(Op::ISub(a(0)?, a(1)?, a(2)?)), "IMaskU32" => code.push(Op::IMaskU32(a(0)?, a(1)?)), "IToF" => code.push(Op::IToF(a(0)?, a(1)?)), "FToI" => code.push(Op::FToI(a(0)?, a(1)?)),
                "FSub" => code.push(Op::FSub(a(0)?, a(1)?, a(2)?)), "FMul" => code.push(Op::FMul(a(0)?, a(1)?, a(2)?)), "ICmpLe" => code.push(Op::ICmpLe(a(0)?, a(1)?, a(2)?)), "ICmpLt" => code.push(Op::ICmpLt(a(0)?, a(1)?, a(2)?)),
                "FCmpLe" => code.push(Op::FCmpLe(a(0)?, a(1)?, a(2)?)), "FCmpLt" => code.push(Op::FCmpLt(a(0)?, a(1)?, a(2)?)), "IAnd" => code.push(Op::IAnd(a(0)?, a(1)?, a(2)?)), "VAdd" => code.push(Op::VAdd(a(0)?, a(1)?, a(2)?)),
                "Simd" => code.push(Op::Simd(simd_op(o[0]), element(o[1]), element(o[4]), a(2)?, a(3)?)),
                "SpanLen" => code.push(Op::SpanLen(a(0)?, a(1)?, a(2)?)), "SpanBounds" => code.push(Op::SpanBounds(a(0)?, a(1)?, a(2)?, a(3)?, flag(4)?)),
                "SpanLoad" => code.push(Op::SpanLoad(a(0)?, a(1)?, a(2)?, a(3)?, a(4)?, a(5)?, a(6)?)), "SpanStore" => code.push(Op::SpanStore(a(0)?, a(1)?, a(2)?, a(3)?, a(4)?, a(5)?, a(6)?)),
                "VOp" => code.push(Op::VOp(simd_op(o[0]), a(1)?, a(2)?, a(3)?, a(4)?, a(5)?)), "VSplatN" => code.push(Op::VSplatN(a(0)?, a(1)?, a(2)?)), "VExtractN" => code.push(Op::VExtractN(a(0)?, a(1)?, a(2)?, a(3)?)),
                "VAny" => code.push(Op::VAny(a(0)?, a(1)?)), "VPrefix" => code.push(Op::VPrefix(a(0)?, a(1)?, a(2)?, a(3)?, a(4)?)), "VMul" => code.push(Op::VMul(a(0)?, a(1)?, a(2)?)),
                "VLoadM" => code.push(Op::VLoadM(a(0)?, a(1)?, a(2)?, i32_of(o[3])?, a(4)?)), "VStoreM" => code.push(Op::VStoreM(a(0)?, a(1)?, a(2)?, i32_of(o[3])?, a(4)?)),
                "LoopFact" => code.push(Op::LoopFact(a(0)?, wide(o[1]), a(2)?)), "GuardLenLe" => code.push(Op::GuardLenLe(a(0)?, a(1)?)), "IMov" => code.push(Op::IMov(a(0)?, a(1)?)), "FMov" => code.push(Op::FMov(a(0)?, a(1)?)), "VMov" => code.push(Op::VMov(a(0)?, a(1)?)),
                "FAdd" => code.push(Op::FAdd(a(0)?, a(1)?, a(2)?)), "FFma" => code.push(Op::FFma(a(0)?, a(1)?, a(2)?, a(3)?)), "StorageLen" => code.push(Op::StorageLen(a(0)?, a(1)?)), "FLoad" => code.push(Op::FLoad(a(0)?, a(1)?, a(2)?)), "FStore" => code.push(Op::FStore(a(0)?, a(1)?, a(2)?)),
                "VSplat" => code.push(Op::VSplat(a(0)?, a(1)?)), "VLoad" => code.push(Op::VLoad(a(0)?, a(1)?, a(2)?, i32_of(o[3])?)), "VStore" => code.push(Op::VStore(a(0)?, a(1)?, a(2)?, i32_of(o[3])?)), "VFma" => code.push(Op::VFma(a(0)?, a(1)?, a(2)?, a(3)?)), "VLane" => code.push(Op::VLane(a(0)?, a(1)?, a(2)?)),
                other => return Err(format!("opcode {other} has no derivation")),
            } }
            let position = if g.pos[at] == NONE { (0, 0) } else { g.positions[g.pos[at] as usize] };
            while debug.len() < code.len() { debug.push(position); }
            let _ = from;
        }
        let edges = b.edges.get(&g.edges);
        let next = bid as u32 + 1;
        match b.term {
            JUMP => copies(&mut code, &mut debug, &mut patches, &edges[0], Some(next))?,
            BRANCH => {
                let cond = r8(end_reg(b.value), "branch condition")?;
                let test = |off: i32| if end_class(b.value) == V { Op::JmpIfNot(cond, off) } else { Op::JmpIfIZero(cond, off) };
                let same = |e: &Edge| g.blocks[e.target as usize].params.get(&g.values).iter().zip(e.args.get(&g.values)).all(|(&p, &a)| physical(p) == physical(a));
                let identity = same(&edges[1]);
                if end_class(b.value) == V && edges[0].target != next && edges[1].target == next && identity && same(&edges[0]) {
                    // The false edge falls through: one jump on the true edge.
                    patches.push((code.len(), edges[0].target));
                    code.push(Op::JmpIf(cond, 0)); debug.push((0, 0));
                } else if identity {
                    patches.push((code.len(), edges[1].target));
                    code.push(test(0)); debug.push((0, 0));
                    copies(&mut code, &mut debug, &mut patches, &edges[0], Some(next))?;
                } else {
                    let branch = code.len();
                    code.push(test(0)); debug.push((0, 0));
                    copies(&mut code, &mut debug, &mut patches, &edges[0], None)?;
                    code[branch] = test((code.len() - branch - 1) as i32);
                    copies(&mut code, &mut debug, &mut patches, &edges[1], Some(next))?;
                }
            }
            SWITCH => {
                let at = code.len();
                code.push(Op::Switch(r8(physical(b.value), "switch index")?, r16(jump_tables.len() as u32, "jump table")?)); debug.push((0, 0));
                jump_tables.push((0, vec![0; edges.len() - 1]));
                let mut targets: Vec<Result<u32, usize>> = Vec::with_capacity(edges.len());
                let mut trampolines = Vec::new();
                for (ei, e) in edges.iter().enumerate() {
                    let target = &g.blocks[e.target as usize];
                    let identity = target.params.get(&g.values).iter().zip(e.args.get(&g.values)).all(|(&p, &a)| physical(p) == physical(a));
                    if identity { targets.push(Ok(e.target)); } else { trampolines.push(ei); targets.push(Err(0)); }
                }
                for ei in trampolines { targets[ei] = Err(code.len()); copies(&mut code, &mut debug, &mut patches, &edges[ei], None)?; }
                table_patches.push((at, jump_tables.len() - 1, targets));
            }
            RETURNS => { code.push(Op::RetN(r8(end_reg(b.value), "returns window")?, b.count as u8)); debug.push((0, 0)); }
            RAISE => { code.push(Op::Raise(r16(b.constant, "raise constant")?)); debug.push((0, 0)); }
            PARK => {
                let mut reg = r8(physical(b.value), "park value")?;
                if g.classes[b.value as usize] == F { let boxed = r8(nparams + 1, "box")?; code.push(Op::FBox(boxed, reg)); debug.push((0, 0)); reg = boxed; }
                copies(&mut code, &mut debug, &mut patches, &edges[0], Some(edges[0].target))?;
                code.push(Op::Park(reg)); debug.push((0, 0));
                if edges[0].target != next { patches.push((code.len(), edges[0].target)); code.push(Op::Jmp(0)); debug.push((0, 0)); }
            }
            _ => {
                if b.value == NONE { code.push(Op::RetNil); debug.push((0, 0)); }
                else {
                    let reg = r8(end_reg(b.value), "return value")?;
                    match end_class(b.value) {
                        F if g.ret == b'f' as u32 => { code.push(Op::FRet(reg)); debug.push((0, 0)); }
                        F => { let boxed = r8(nparams + 1, "box")?; code.push(Op::FBox(boxed, reg)); code.push(Op::Ret(boxed)); debug.push((0, 0)); debug.push((0, 0)); }
                        I => { let boxed = r8(nparams + 1, "box")?; code.push(Op::IBox(boxed, reg)); code.push(Op::Ret(boxed)); debug.push((0, 0)); debug.push((0, 0)); }
                        _ => { if g.ret == b'f' as u32 { return Err("float-returning function returns another class".into()); } code.push(Op::Ret(reg)); debug.push((0, 0)); }
                    }
                }
            }
        }
    }
    for (pc, target) in patches {
        let off = starts[target as usize] as i32 - pc as i32 - 1;
        code[pc] = match code[pc] { Op::Jmp(_) => Op::Jmp(off), Op::JmpIf(c, _) => Op::JmpIf(c, off), Op::JmpIfNot(c, _) => Op::JmpIfNot(c, off), Op::JmpIfIZero(c, _) => Op::JmpIfIZero(c, off), _ => unreachable!() };
    }
    for (pc, t, targets) in table_patches {
        let offsets: Vec<i32> = targets.iter().map(|t| match *t { Ok(block) => starts[block as usize], Err(at) => at } as i32 - pc as i32 - 1).collect();
        jump_tables[t] = (offsets[0], offsets[1..].to_vec());
    }
    // The text writer gives every function the same headroom above its
    // counts (nine value registers, two typed ones); the derived frame keeps
    // it so a program's frames are the ones it has today.
    let nf = (counts[1].max(counts[2]) + if g.map { 2 } else { 1 } + 2) as u8;
    let sig: Vec<u8> = image.strings[g.sig as usize].clone();
    let nfp = sig.iter().filter(|&&c| c == b'f').count() as u8;
    let f = Function {
        name: image.text(g.name).to_string(),
        module: image.text(g.module).to_string(),
        path: if g.path == NONE { None } else { Some(image.text(g.path).into()) },
        nv_params: sig.len() as u8 - nfp,
        nf_params: nfp,
        sig,
        ret: g.ret as u8,
        code,
        consts,
        nparams: nparams as u8,
        nregs: if form { g.registers[0] as u8 } else { (value_base + if counts[0] > 0 { counts[0] + 1 } else { 0 } + 9) as u8 },
        nireg: if form { g.registers[1] as u8 } else { nf },
        nfreg: if form { g.registers[1] as u8 } else { nf },
        nvreg: if form { g.registers[2] as u8 } else { (counts[3] + 1) as u8 },
        jump_tables,
        debug,
        vararg: g.vararg,
        gpu: g.gpu.clone(),
        ins: Vec::new(),
    };
    // The resume entries a park leaves must be block starts, which the layout
    // guarantees; the verifier of the derived stream holds the rest.
    for (pc, op) in f.code.iter().enumerate() { if matches!(op, Op::Park(_)) && !starts.contains(&(pc + 1)) && !matches!(f.code.get(pc + 1), Some(Op::Jmp(_))) { return Err(format!("pc {pc}: resume entry is not a block start")); } }
    Ok(f)
}

/// Derives every function of a decoded image into `it`'s function table,
/// returning them in image order. `base` is where they would land; the
/// caller installs them.
pub fn derive_all(it: &mut Interp, image: &Image, base: u32, shape_ids: &[u32]) -> Result<Vec<Function>, String> {
    with_table(|table| {
        let nfuncs = base as usize + image.functions.len();
        let mut out = Vec::with_capacity(image.functions.len());
        let mut d = Derivation { it, base, shape_ids };
        for g in &image.functions {
            let f = derive(table, image, g, &mut d).map_err(|e| format!("function {}: {e}", image.text(g.name)))?;
            crate::verify::verify_classes(&f, nfuncs).map_err(|e| format!("function {}: {e}", f.name))?;
            out.push(f);
        }
        Ok(out)
    })
}

/// Loads a graph image into the VM as `image::load` loads a text one: shapes
/// by identity where the heap already holds the layout, modules, extension
/// declarations, then every function derived and verified, and the image
/// recorded as a code event for checkpoints. Returns the entry function.
pub fn load(it: &mut Interp, bytes: &[u8]) -> Result<u32, String> { load_with(it, bytes, false) }

/// `load` for a buffer the caller gives up, which the code event keeps rather
/// than a copy of it.
pub fn load_owned(it: &mut Interp, bytes: Vec<u8>) -> Result<u32, String> {
    let scope = it.open_scope();
    let r = with_table(|table| install(table, it, &bytes, false));
    it.close_scope(scope);
    let (entry, functions) = r?;
    it.code_events.push(crate::persist::CodeEvent::Graph { bytes, functions });
    Ok(entry)
}

/// `load` for an image added to a running VM: one with vector instructions is
/// refused where the runtime cannot compile them, as `image::load_plugin`
/// refuses the text.
pub fn load_plugin(it: &mut Interp, bytes: &[u8]) -> Result<u32, String> { let refuse = !it.simd_interpret; load_with(it, bytes, refuse) }

fn load_with(it: &mut Interp, bytes: &[u8], refuse_native: bool) -> Result<u32, String> {
    let scope = it.open_scope();
    let r = with_table(|table| install(table, it, bytes, refuse_native));
    it.close_scope(scope);
    if let Ok((entry, functions)) = r { it.code_events.push(crate::persist::CodeEvent::Graph { bytes: bytes.to_vec(), functions }); return Ok(entry); }
    r.map(|(entry, _)| entry)
}

/// The heap shapes an image's shape table resolves to, in order. With
/// `patch`, the shapes the running module was loaded with: a patch may name
/// only those layouts, by identity or by position, and never adds one.
fn install_shapes(it: &mut Interp, image: &Image, patch: Option<&[u32]>) -> Result<Vec<u32>, String> {
    use crate::heap::SlotTy;
    let mut shape_ids: Vec<u32> = Vec::with_capacity(image.shapes.len());
    for s in &image.shapes {
        let mut names = Vec::with_capacity(s.slots.len());
        let mut types = Vec::with_capacity(s.slots.len());
        for &(slot, ty, record) in &s.slots {
            let v = it.intern(image.text(slot)); it.handles.push(v); names.push(v);
            types.push(match ty { 0 => SlotTy::Num, 1 => SlotTy::Str, 2 => SlotTy::Bool, 3 => match shape_ids.get(record as usize) { Some(&id) => SlotTy::Record(id), None => SlotTy::Any }, _ => SlotTy::Any });
        }
        let name = image.text(s.name);
        let identity = if s.identity == NONE { None } else { Some(image.text(s.identity).to_string()) };
        // Slot types are hints two images can infer differently; the layout
        // is the names, in order.
        let existing = identity.as_ref().and_then(|key| it.heap.shape_identities.get(key).copied()).filter(|&id| it.heap.shapes[id as usize].names == names);
        if let Some(old) = patch {
            let same = |id: u32| it.heap.shapes[id as usize].names == names && it.heap.shapes[id as usize].name == name;
            let id = existing.or_else(|| old.get(shape_ids.len()).copied().filter(|&id| same(id))).ok_or_else(|| format!("record layout changed or added: {name}"))?;
            shape_ids.push(id);
            continue;
        }
        let id = existing.unwrap_or_else(|| it.heap.shape(name, &names, &types));
        if let (None, Some(key)) = (existing, identity) { it.heap.shape_identities.insert(key, id); }
        shape_ids.push(id);
    }
    Ok(shape_ids)
}

/// Every function of a decoded header derived in order, each verified
/// against the table and, when asked, refused for native code.
fn derive_functions(table: &Table, header: &mut Header, it: &mut Interp, base: u32, shape_ids: &[u32], refuse_native: bool, verify_stream: bool) -> Result<Vec<Function>, String> {
    let nfuncs = base as usize + header.nfunctions;
    let mut funcs = Vec::with_capacity(header.nfunctions);
    let mut g = Graph::default();
    for fi in 0..header.nfunctions {
        header.next_function(table, fi, &mut g)?;
        let mut d = Derivation { it, base, shape_ids };
        let f = derive(table, &header.image, &g, &mut d).map_err(|e| format!("function {}: {e}", header.image.text(g.name)))?;
        // A lowered graph's frame was bounded as it was verified; a kernel's,
        // and anything native code must prove, is checked on the stream.
        if verify_stream && (!g.register_form || crate::image::needs_native(&f)) { crate::verify::verify_classes(&f, nfuncs).map_err(|e| format!("function {}: {e}", f.name))?; }
        if refuse_native && crate::image::needs_native(&f) { return Err(crate::image::uncompiled_native_message("image refused", &f.name, &f.module)); }
        funcs.push(f);
    }
    Ok(funcs)
}

/// Named operations use identity keys in every execution tier.
fn intern_fields(it: &mut Interp, funcs: &mut [Function]) -> Result<(), String> {
    for f in funcs.iter_mut() {
        for op in &f.code {
            let key = match *op {
                Op::GetField(_, _, k) | Op::SetField(_, k, _) | Op::CallMethod(k, _, _) | Op::SetMethod(_, k, _) | Op::DeferMethod(_, k) => k as usize,
                _ => continue,
            };
            let value = *f.consts.get(key).ok_or_else(|| format!("function {}: field constant outside pool", f.name))?;
            if !it.is_stringish(value) { return Err(format!("function {}: field name must be a string", f.name)); }
            let name = it.key_for_store(value);
            it.handles.push(name);
            f.consts[key] = name;
        }
        for op in &f.code {
            let p = match *op { Op::GetPhys(_, _, p) | Op::GetPhysF(_, _, p) | Op::GetPhysI(_, _, p) | Op::GetPhysU(_, _, p) | Op::SetPhys(_, p, _) | Op::SetPhysF(_, p, _) | Op::SetPhysI(_, p, _) => p, _ => continue };
            for key in [p.identity, p.name] {
                let v = *f.consts.get(key as usize).ok_or_else(|| format!("function {}: physical constant outside pool", f.name))?;
                if !it.is_stringish(v) { return Err(format!("function {}: physical identity/name must be strings", f.name)); }
                let v = it.key_for_store(v); it.handles.push(v); f.consts[key as usize] = v;
            }
        }
    }
    Ok(())
}

fn module_list(image: &Image) -> Vec<(String, u32, Option<String>)> {
    image.modules.iter().map(|&(name, chunk, path)| (image.text(name).to_string(), chunk, if path == NONE { None } else { Some(image.text(path).to_string()) })).collect()
}

/// A graph image read against a running module's shapes but not yet part
/// of the VM, as `image::parse` reads a text patch: the functions refer to
/// each other as `base + index`.
pub(crate) struct PatchImage { pub base: u32, pub funcs: Vec<Function>, pub shape_ids: Vec<u32>, pub modules: Vec<(String, u32, Option<String>)> }

pub(crate) fn parse_patch(it: &mut Interp, bytes: &[u8], running: &[u32]) -> Result<PatchImage, String> {
    with_table(|table| {
        let mut header = decode_header(table, bytes)?;
        let shape_ids = install_shapes(it, &header.image, Some(running))?;
        let base = it.funcs.len() as u32;
        let mut funcs = derive_functions(table, &mut header, it, base, &shape_ids, false, false)?;
        intern_fields(it, &mut funcs)?;
        let modules = module_list(&header.image);
        header.finish()?;
        Ok(PatchImage { base, funcs, shape_ids, modules })
    })
}

fn install(table: &Table, it: &mut Interp, bytes: &[u8], refuse_native: bool) -> Result<(u32, u32), String> {
    let mut header = decode_header(table, bytes)?;
    let shape_ids = install_shapes(it, &header.image, None)?;
    for &(name, declaration) in &header.image.extensions {
        crate::extension::declare(it, header.image.text(name), &header.image.strings[declaration as usize])?;
    }
    let base = it.funcs.len() as u32;
    let mut funcs = derive_functions(table, &mut header, it, base, &shape_ids, refuse_native, true)?;
    intern_fields(it, &mut funcs)?;
    let image = &header.image;
    let modules: Vec<(String, u32, Option<String>)> = image.modules.iter().map(|&(name, chunk, path)| (image.text(name).to_string(), chunk, if path == NONE { None } else { Some(image.text(path).to_string()) })).collect();
    for (name, chunk, path) in &modules {
        it.modules.insert(name.clone(), base + chunk);
        if let Some(p) = path {
            it.module_paths.insert(name.clone(), p.clone());
            // Each function keeps its own source path, as the text loader
            // gives it: a later image may load another chunk under this
            // module's name.
            let path: std::sync::Arc<str> = p.as_str().into();
            for f in funcs.iter_mut().filter(|f| f.module == *name && f.path.is_none()) { f.path = Some(path.clone()); }
        }
    }
    crate::hotpatch::record(it, base, &funcs, &shape_ids, &modules);
    it.funcs.extend(funcs);
    for (i, s) in image.shapes.iter().enumerate() {
        for &(name, fid) in &s.methods { let n = it.intern(image.text(name)); it.heap.shapes[shape_ids[i] as usize].methods.insert(n, Value::func(base + fid)); }
    }
    it.heap.proto_epoch += 1;
    let entry = if image.entry == NONE { 0 } else { base + image.entry };
    let functions = header.nfunctions as u32;
    header.finish()?;
    Ok((entry, functions))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// An image as logical items: words, and the raw payloads (string
    /// bytes, floats) between them. Tests patch words by index.
    #[derive(Clone)]
    enum Item { W(u32), Raw(Vec<u8>) }
    use Item::{Raw, W};

    fn encode(items: &[Item]) -> Vec<u8> {
        let mut out = MAGIC.to_vec();
        for item in items {
            match item {
                W(v) => {
                    let mut n = v.wrapping_add(1);
                    loop {
                        let b = (n & 0x7f) as u8;
                        n >>= 7;
                        if n == 0 { out.push(b); break; }
                        out.push(b | 0x80);
                    }
                }
                Raw(bytes) => out.extend(bytes),
            }
        }
        out
    }

    fn text(s: &[u8]) -> [Item; 2] { [W(s.len() as u32), Raw(s.to_vec())] }

    /// A one-function image: `function f(x) local y = x + 1 return y end`
    /// as a two-block graph with a jump carrying one parameter.
    fn tiny_items() -> Vec<Item> {
        let mut items = vec![W(VERSION)];
        let strings: [&[u8]; 6] = [b"f", b"m", b"v", b"K", b"Add", b"Move"];
        items.push(W(strings.len() as u32));
        for s in strings { items.extend(text(s)); }
        items.push(W(0)); // wides
        items.push(W(1)); items.push(Raw(1f64.to_le_bytes().to_vec())); // floats
        items.extend([W(0), W(0), W(0)]); // shapes, modules, extensions
        items.push(W(NONE)); // entry
        items.push(W(1)); // functions
        items.extend([W(0), W(1), W(NONE)]); // name, module, path
        items.extend([W(1), W(0), W(2), W(b'v' as u32), W(0)]); // nparams, vararg, sig, ret, flags
        items.extend([W(0), W(0), W(0)]); // registers: the slots decide
        items.extend([W(1), W(3), W(0)]); // one numeric constant
        items.extend([W(1), W(7), W(3)]); // one position
        items.push(W(0)); // certificates
        // values: 0 = x (param), 1 = k, 2 = sum, 3 = block 1's parameter
        items.push(W(4)); for c in [V, V, V, V] { items.push(W(c as u32)); } for s in [1, 0, 1, 1] { items.push(W(s)); }
        items.push(W(2)); // blocks
        items.push(W(0)); // block 0: no params
        items.push(W(2)); // two instructions
        items.extend([W(3), W(1), W(0), W(0), W(NONE)]); // K v1 k0, at position 0
        items.extend([W(4), W(2), W(0), W(1), W(NONE), W(NONE)]); // Add v2 v0 v1
        items.extend([W(JUMP), W(NONE), W(NONE), W(NONE), W(1), W(1), W(1), W(2)]); // jump 1(v2)
        items.extend([W(1), W(3)]); // block 1: param v3
        items.push(W(0)); // no instructions
        items.extend([W(RETURN), W(3), W(NONE), W(NONE), W(0)]);
        items.extend([W(1), W(BODY), W(NONE), W(0), W(0), W(NONE), W(NONE)]); // one region
        items.extend([W(0), W(0)]); // block regions
        items.push(W(0)); // no gpu
        items
    }

    fn tiny() -> Vec<u8> { encode(&tiny_items()) }

    #[test]
    fn decodes_and_derives_the_tiny_image() {
        let bytes = tiny();
        let image = decode(&bytes).unwrap();
        assert_eq!(image.functions.len(), 1);
        let mut it = Interp::new();
        let functions = derive_all(&mut it, &image, 0, &[]).unwrap();
        let f = &functions[0];
        assert_eq!(format!("{:?}", f.code), format!("{:?}", vec![Op::K(3, 0), Op::Add(4, 1, 3), Op::Ret(4)]));
        assert_eq!(f.debug[0], (7, 3));
        assert_eq!((f.nparams, f.nregs), (1, 15));
        it.funcs.push(functions.into_iter().next().unwrap());
        let tid = it.spawn(0, &[Value::num(41.)]);
        assert!(matches!(it.run_rust(tid), crate::interp::Outcome::Done(v) if v == Value::num(42.)));
    }

    #[test]
    fn loads_the_tiny_image_as_a_code_event() {
        let bytes = tiny();
        let mut it = Interp::new();
        assert_eq!(load(&mut it, &bytes).unwrap(), 0);
        assert_eq!(it.funcs.len(), 1);
        assert!(matches!(it.code_events.last(), Some(crate::persist::CodeEvent::Graph { functions: 1, .. })));
        let tid = it.spawn(0, &[Value::num(41.)]);
        assert!(matches!(it.run_rust(tid), crate::interp::Outcome::Done(v) if v == Value::num(42.)));
    }

    #[test]
    fn a_slot_may_name_a_later_shape() {
        let with_shapes = |record: u32| {
            let mut items = tiny_items();
            let at = (0..items.len()).find(|&i| matches!(items.get(i..i + 4), Some([W(0), W(0), W(0), W(NONE)]))).unwrap();
            // Shape 0 "K" has a slot "v" holding shape `record`; shape 1 "m" is empty.
            items.splice(at..at + 1, [W(2), W(3), W(NONE), W(1), W(2), W(3), W(record), W(0), W(1), W(NONE), W(0), W(0)]);
            decode(&encode(&items))
        };
        assert_eq!(with_shapes(1).unwrap().shapes[0].slots[0].2, 1);
        assert!(with_shapes(2).unwrap_err().contains("slot record shape"));
    }

    #[test]
    fn refuses_every_truncated_prefix_and_trailing_bytes() {
        let bytes = tiny();
        for len in 0..bytes.len() { assert!(decode(&bytes[..len]).is_err(), "accepted a prefix of {len} bytes"); }
        let mut extra = bytes.clone();
        extra.push(0);
        assert!(decode(&extra).is_err());
    }

    #[test]
    fn refuses_hostile_words() {
        let items = tiny_items();
        let patch = |index: usize, value: u32| { let mut bad = items.clone(); bad[index] = W(value); decode(&encode(&bad)) };
        // Every word overwritten with all ones, then with zero, in turn: no
        // panic, no acceptance past the verifier that would change a register.
        for (i, item) in items.iter().enumerate() {
            if matches!(item, W(_)) { let _ = patch(i, NONE); let _ = patch(i, 0); let _ = patch(i, 1 << 30); }
        }
        let find = |needle: &[u32]| (0..items.len()).find(|&i| needle.iter().enumerate().all(|(k, w)| matches!(items.get(i + k), Some(W(v)) if v == w))).unwrap();
        // The Add's second operand becomes its own result: a use before definition.
        let add = find(&[4, 2, 0, 1]);
        assert!(patch(add + 3, 2).unwrap_err().contains("closed block"));
        // The jump's argument names block 1's own parameter.
        let jump = find(&[JUMP, NONE, NONE, NONE, 1, 1, 1, 2]);
        assert!(patch(jump + 7, 3).unwrap_err().contains("closed block"));
        // Edge arity.
        assert!(patch(jump + 6, 0).is_err());
        // The target becomes the entry block.
        assert!(patch(jump + 5, 0).unwrap_err().contains("entry"));
        // A word past 32 bits.
        let mut overflow = encode(&items[..1]);
        overflow.extend([0xff, 0xff, 0xff, 0xff, 0x7f]);
        assert!(decode(&overflow).is_err());
    }
}
