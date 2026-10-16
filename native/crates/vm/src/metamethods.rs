//! Metamethod lookup and the dispatch the runtime does itself: equality,
//! the names a metatable can hold, and the caches that keep a program that
//! never uses one from paying for the question.
//!
//! Two guards answer "no handler" without a table probe. `Heap::mm_seen`
//! has a bit per name whose string was ever interned: a key that was never a
//! string is in no table. And a record's shape caches which metamethods its
//! declaration holds (`Shape::mm_cache`), dropped by any store that can change
//! the answer (`Interp::redeclare`, `Interp::set_method`). A table or a record
//! with a metatable of its own probes that metatable with the name's interned
//! key, kept rooted in `Heap::mm_keys` so no lookup hashes the name's bytes.
use crate::heap::{self, KIND_RECORD, KIND_TABLE, KIND_USERDATA};
use crate::interp::Interp;
use crate::value::Value;

/// The metamethods the runtime consults, in `NAMES` order. `__gc` is not
/// among them: ownership and `with` are the close path (contracts 9), so a
/// metatable's `__gc`, like `__close` and `__name`, is an ordinary field.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
#[repr(u8)]
pub enum MM { Index, NewIndex, Call, Eq, Lt, Le, Add, Sub, Mul, Div, Mod, Pow, IDiv, Unm, Len, Concat, ToString, Pairs, Metatable }
pub const NAMES: [&str; COUNT] = [
    "__index", "__newindex", "__call", "__eq", "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__idiv",
    "__unm", "__len", "__concat", "__tostring", "__pairs", "__metatable",
];
pub const COUNT: usize = 19;
/// `Shape::mm_cache` holds this bit once its metamethod bits are computed.
pub const CACHED: u32 = 1 << 31;

impl MM {
    pub fn name(self) -> &'static str { NAMES[self as usize] }
    pub fn bit(self) -> u32 { 1 << self as u32 }
    pub fn of(name: &str) -> Option<MM> {
        const ALL: [MM; COUNT] = [MM::Index, MM::NewIndex, MM::Call, MM::Eq, MM::Lt, MM::Le, MM::Add, MM::Sub, MM::Mul, MM::Div, MM::Mod, MM::Pow, MM::IDiv, MM::Unm, MM::Len, MM::Concat, MM::ToString, MM::Pairs, MM::Metatable];
        NAMES.iter().position(|n| *n == name).map(|i| ALL[i])
    }
}

/// The `Heap::mm_seen` bit for an interned string's bytes, or zero.
pub fn bit_of(bytes: &[u8]) -> u32 {
    NAMES.iter().position(|n| n.as_bytes() == bytes).map_or(0, |i| 1 << i)
}

impl Interp {
    /// The interned key for a metamethod name, interned and rooted on first use.
    pub(crate) fn mm_key(&mut self, mm: MM) -> Value {
        let k = self.heap.mm_keys[mm as usize];
        if k != heap::VT_EMPTY { return Value(k); }
        let v = self.intern(mm.name());
        self.heap.mm_keys[mm as usize] = v.0;
        v
    }
    /// Whether any table can hold this metamethod at all.
    #[inline]
    pub(crate) fn mm_possible(&self, mm: MM) -> bool { self.heap.mm_seen & mm.bit() != 0 }
    /// A record's declaration (its shape's `\0nupp:recordType` entry), which
    /// answers for its metatable when it has none of its own.
    pub(crate) fn shape_declaration(&self, shape: u32) -> Value {
        match self.heap.interned_key("\0nupp:recordType") {
            Some(key) => self.heap.shapes[shape as usize].methods.get(&key).copied().unwrap_or(Value::NIL),
            None => Value::NIL,
        }
    }
    /// The metamethod bits of a shape's declaration, cached while the
    /// declaration is a table whose stores reach `redeclare`.
    fn shape_mm(&mut self, shape: u32) -> u32 {
        let cached = self.heap.shapes[shape as usize].mm_cache;
        if cached & CACHED != 0 { return cached; }
        let decl = self.shape_declaration(shape);
        let mut bits = 0;
        if decl != Value::NIL {
            for i in 0..COUNT {
                if self.heap.mm_seen & (1 << i) == 0 { continue; }
                let key = self.heap.mm_keys[i];
                let key = if key != heap::VT_EMPTY { Value(key) } else { match self.heap.interned_key(NAMES[i]) { Some(k) => k, None => continue } };
                if self.get_index(decl, key) != Value::NIL { bits |= 1 << i; }
            }
        }
        // A declaration that is not a plain table has no store hook: its
        // answer is recomputed at each question.
        if decl == Value::NIL || self.kind_of(decl) == Some(KIND_TABLE) { bits |= CACHED; self.heap.shapes[shape as usize].mm_cache = bits; }
        bits
    }
    /// The table `v`'s metamethods are read from: its own metatable, or a
    /// record's declaration. Nil for anything else.
    #[inline]
    pub(crate) fn mm_table(&self, v: Value) -> Value {
        let Some(p) = v.as_obj() else { return Value::NIL };
        let h = unsafe { p.as_ref() };
        match h.kind {
            KIND_TABLE => h.table_ref().meta,
            KIND_RECORD if h.flags & heap::F_METATABLE != 0 => self.metatable_of(v),
            KIND_RECORD => self.shape_declaration(h.shape()),
            KIND_USERDATA => h.userdata().meta,
            _ => Value::NIL,
        }
    }
    /// `v`'s handler for `mm`, or nil: the cheap guards first, then the
    /// probe.
    pub fn metamethod(&mut self, v: Value, mm: MM) -> Value {
        if !self.mm_possible(mm) { return Value::NIL; }
        let Some(p) = v.as_obj() else { return Value::NIL };
        let h = unsafe { p.as_ref() };
        match h.kind {
            KIND_RECORD if h.flags & heap::F_METATABLE == 0 => {
                let shape = h.shape();
                if self.shape_mm(shape) & mm.bit() == 0 { return Value::NIL; }
                let decl = self.shape_declaration(shape);
                let key = self.mm_key(mm);
                self.get_index(decl, key)
            }
            KIND_TABLE | KIND_RECORD | KIND_USERDATA => {
                let meta = self.mm_table(v);
                if meta == Value::NIL { return Value::NIL; }
                if let Some(value) = crate::storage::metamethod(self, v, meta, mm.name()) { return value; }
                let key = self.mm_key(mm);
                self.get_index(meta, key)
            }
            // Strings answer from the string metatable through `index`.
            _ => Value::NIL,
        }
    }
    /// A store into a declaration may add or drop a metamethod: its shapes
    /// recompute their bits at the next question.
    pub(crate) fn redeclared_metamethods(&mut self, shapes: &[u32], key: Value) {
        if self.is_stringish(key) && self.bytes_of(key).starts_with(b"__") {
            for &shape in shapes { self.heap.shapes[shape as usize].mm_cache = 0; }
        }
    }
    /// The `__eq` handler Lua 5.1 consults for `x == y` once they are not
    /// raw-equal: both tables (records are tables) or both userdata, and the
    /// same handler on each side (LuaJIT's `lj_meta_equal`). Nil when none.
    pub fn eq_handler(&mut self, x: Value, y: Value) -> Value {
        if !self.mm_possible(MM::Eq) { return Value::NIL; }
        let (Some(p), Some(q)) = (x.as_obj(), y.as_obj()) else { return Value::NIL };
        let (a, b) = unsafe { (p.as_ref().kind, q.as_ref().kind) };
        let tables = matches!(a, KIND_TABLE | KIND_RECORD) && matches!(b, KIND_TABLE | KIND_RECORD);
        if !tables && !(a == KIND_USERDATA && b == KIND_USERDATA) { return Value::NIL; }
        let left = self.metamethod(x, MM::Eq);
        if left == Value::NIL { return Value::NIL; }
        if self.mm_table(x) == self.mm_table(y) { return left; }
        let right = self.metamethod(y, MM::Eq);
        if right != left { return Value::NIL; }
        left
    }
    /// `x == y` as Lua evaluates it: raw equality, then `__eq`.
    pub fn equals(&mut self, x: Value, y: Value) -> bool {
        if self.values_equal(x, y) { return true; }
        let handler = self.eq_handler(x, y);
        if handler == Value::NIL { return false; }
        let scope = self.open_scope();
        self.handles.extend_from_slice(&[x, y, handler]);
        let result = self.call_value(handler, &[x, y]).first().is_some_and(|v| v.truthy());
        self.close_scope(scope);
        result
    }
    /// What a table with a metatable of its own answers for an absent `key`
    /// through its `__index` chain, from the cache when nothing the chain
    /// walked was written since. Every metatable and `__index` table walked
    /// is flagged `F_PROTO`, whose stores bump the epoch. None when the chain
    /// reaches a function, which the caller then calls.
    pub(crate) fn index_through_metatable(&mut self, t: Value, key: Value) -> Option<Value> {
        let p = t.as_obj()?;
        let h = unsafe { p.as_ref() };
        let own = match h.kind { KIND_TABLE => h.table_ref().meta != Value::NIL, KIND_RECORD => h.flags & heap::F_METATABLE != 0, _ => false };
        if !own { return None; }
        let meta = self.mm_table(t);
        if let Some(&(v, epoch)) = self.heap.proto_cache.get(&(meta.0, key.0)) {
            if epoch == self.heap.proto_epoch { return Some(Value(v)); }
        }
        let mut object = t;
        let mut answer = Value::NIL;
        let mut settled = false;
        for _ in 0..100 {
            Self::flag_proto(self.mm_table(object));
            let handler = self.metamethod(object, MM::Index);
            if handler == Value::NIL { settled = true; break; }
            if !matches!(self.kind_of(handler), Some(KIND_TABLE | KIND_RECORD)) { return None; }
            Self::flag_proto(handler);
            let v = self.get_index(handler, key);
            if v != Value::NIL { answer = v; settled = true; break; }
            let hh = unsafe { handler.as_obj().unwrap().as_ref() };
            if hh.kind == KIND_RECORD {
                if let Some(&method) = self.heap.shapes[hh.shape() as usize].methods.get(&key) { answer = method; settled = true; break; }
            }
            object = handler;
        }
        // A chain that never ends raises where the caller walks it.
        if !settled { return None; }
        if self.heap.proto_cache.len() >= 4096 { self.heap.proto_cache.clear(); }
        self.heap.proto_cache.insert((meta.0, key.0), (answer.0, self.heap.proto_epoch));
        Some(answer)
    }
    fn flag_proto(v: Value) {
        if let Some(p) = v.as_obj() {
            let h = unsafe { &mut *p.as_ptr() };
            if matches!(h.kind, KIND_TABLE | KIND_RECORD) { h.flags |= heap::F_PROTO; }
        }
    }
}
