//! The opcode table (contracts 3.2): the compiler's definition of every
//! opcode, carried in an image's header as `opcode` lines and read here to
//! drive the verifier's structural checks and its liveness pass. The table
//! exists once, in `nupp.compiler.vm.opcodes`; this module parses it and
//! holds nothing about any opcode that the table does not say.
//!
//! `Op` stays the interpreter's and the JIT's form of an instruction. The
//! `opcodes!` macro defines it together with the conversions between an `Op`
//! and the operand list the image spells, which is what a table row describes:
//! `Op::operands` flattens an instruction to that list and `Op::from_operands`
//! rebuilds one from it.
//!
//! An image that carries no table (a hand-written one) is read against the
//! built-in copy, `opcodes.table`, which the compiler's suite holds equal to
//! what it emits. Every image loaded into a process must carry the same table
//! as the first: an image compiled against another definition is refused.

use std::sync::OnceLock;

use crate::interp::Op;
use crate::storage::PhysicalField;
use crate::verify::C;

/// A field of an instruction as the image spells it: one operand for each
/// number, five for a physical field plan.
pub trait Operand: Copy {
    fn put(self, out: &mut Vec<i64>);
    fn take(values: &mut std::slice::Iter<'_, i64>) -> Option<Self>;
}

macro_rules! numeric_operand {
    ($($t:ty),*) => { $(
        impl Operand for $t {
            fn put(self, out: &mut Vec<i64>) { out.push(self as i64); }
            fn take(values: &mut std::slice::Iter<'_, i64>) -> Option<Self> { <$t>::try_from(*values.next()?).ok() }
        }
    )* };
}
numeric_operand!(u8, u16, u32, i32, i64);

impl Operand for bool {
    fn put(self, out: &mut Vec<i64>) { out.push(self as i64); }
    fn take(values: &mut std::slice::Iter<'_, i64>) -> Option<Self> { values.next().map(|v| *v != 0) }
}

/// A float immediate travels as its bits.
impl Operand for f64 {
    fn put(self, out: &mut Vec<i64>) { out.push(self.to_bits() as i64); }
    fn take(values: &mut std::slice::Iter<'_, i64>) -> Option<Self> { values.next().map(|v| f64::from_bits(*v as u64)) }
}

impl Operand for PhysicalField {
    fn put(self, out: &mut Vec<i64>) {
        self.identity.put(out);
        self.name.put(out);
        self.ordinal.put(out);
        self.offset.put(out);
        self.kind.put(out);
    }
    fn take(values: &mut std::slice::Iter<'_, i64>) -> Option<Self> {
        Some(PhysicalField { identity: u16::take(values)?, name: u16::take(values)?, ordinal: u16::take(values)?, offset: u32::take(values)?, kind: u8::take(values)? })
    }
}

/// Defines `Op` from a list of variants whose fields are named, so that each
/// instruction converts to and from the operand list the image spells. A
/// variant whose image spelling orders its fields differently says so with
/// `as (...)`, naming the fields in image order.
macro_rules! opcodes {
    (@put $out:ident) => {};
    (@put $out:ident ( $($f:ident),* )) => { $( $crate::opcodes::Operand::put($f, &mut $out); )* };
    (@put $out:ident ( $($f:ident),* ) as ( $($o:ident),* )) => { $( $crate::opcodes::Operand::put($o, &mut $out); )* };
    (@take $it:ident $v:ident) => { Op::$v };
    (@take $it:ident $v:ident ( $($f:ident : $t:ty),* )) => {{ $( let $f = <$t as $crate::opcodes::Operand>::take(&mut $it)?; )* Op::$v( $($f),* ) }};
    (@take $it:ident $v:ident ( $($f:ident : $t:ty),* ) as ( $($o:ident : $ot:ty),* )) => {{ $( let $o = <$ot as $crate::opcodes::Operand>::take(&mut $it)?; )* Op::$v( $($f),* ) }};
    ( $( $(#[$meta:meta])* $name:ident $( ( $( $field:ident : $ty:ty ),* ) )? $( as ( $( $text:ident : $tty:ty ),* ) )? ),* $(,)? ) => {
        #[derive(Clone, Copy, Debug)]
        pub enum Op { $( $(#[$meta])* $name $( ( $($ty),* ) )? ),* }

        /// The opcodes without their operands, in `Op`'s order.
        #[derive(Clone, Copy, Debug, PartialEq, Eq)]
        #[repr(u8)]
        pub enum OpKind { $( $name ),* }

        impl Op {
            /// Every opcode's name, in declaration order.
            pub const NAMES: &'static [&'static str] = &[ $( stringify!($name) ),* ];

            pub fn kind(&self) -> OpKind { match self { $( Op::$name { .. } => OpKind::$name ),* } }

            /// Its position in `NAMES`.
            pub fn index(&self) -> usize { self.kind() as usize }

            pub fn name(&self) -> &'static str { Op::NAMES[self.index()] }

            /// The instruction's operands as the image spells them.
            pub fn operands(&self) -> Vec<i64> {
                let mut out = Vec::new();
                match *self { $( Op::$name $( ( $($field),* ) )? => { opcodes!(@put out $( ( $($field),* ) )? $( as ( $($text),* ) )? ); } ),* }
                out
            }

            /// The instruction an opcode name and its spelled operands make, or
            /// nothing when the name is unknown or the operands do not fit.
            pub fn from_operands(name: &str, values: &[i64]) -> Option<Op> {
                let mut it = values.iter();
                let op = match name { $( stringify!($name) => opcodes!(@take it $name $( ( $($field : $ty),* ) )? $( as ( $($text : $tty),* ) )? ), )* _ => return None };
                if it.next().is_some() { return None; }
                Some(op)
            }
        }
    };
}

/// What an operand is.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Class {
    /// A register of the class.
    Reg(C),
    /// A scalar register whose class the operand at this position (1-based)
    /// decides: float at a kind of 8 or above, integer below.
    ScalarByKind(usize),
    /// An index into the function's constant pool.
    Const,
    /// A jump offset, relative to the next instruction.
    Jump,
    /// An immediate the verifier does not interpret.
    Imm,
    /// A shape index.
    Shape,
    /// A function id.
    Func,
    /// A jump table index.
    Table,
    /// A symbolic immediate: a SIMD operation or element kind.
    Name,
}

/// How an instruction treats a register operand.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    Def,
    Use,
    Both,
    /// Named for the class check, neither read nor written for liveness.
    Check,
    /// Not named: a window names it.
    None,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct OperandSpec {
    pub class: Class,
    pub mode: Mode,
    pub optional: bool,
}

/// How many registers a window covers, from its count operand.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Formula {
    N,
    Minus1,
    Fixed,
    FixedMax1,
    CallArgs,
    CallArgs1,
    RetN,
    SimdSpan,
    SimdResults,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WindowMode {
    /// Named for the class check only.
    Check,
    /// Named, and written.
    Def,
    /// Named, and read.
    Use,
    /// Written, but not named for the class check.
    Defs,
    /// Read, but not named for the class check.
    Uses,
}

impl WindowMode {
    pub fn named(self) -> bool { matches!(self, WindowMode::Check | WindowMode::Def | WindowMode::Use) }
}

/// A run of registers an operand count decides.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Window {
    pub class: C,
    pub mode: WindowMode,
    /// The 1-based position of the base register operand.
    pub base: usize,
    pub offset: u8,
    /// The 1-based position of the count operand.
    pub count: usize,
    pub formula: Formula,
}

/// The fixed arguments a flagged count names: 128 appends the frame's
/// varargs; 64 appends the last call's results in the argument registers.
pub fn fixed_args(nargs: u8) -> u8 { if nargs >= 128 { nargs & 127 } else { nargs & 63 } }

/// The argument registers a call reads: the fixed ones, and the eight result
/// registers a 64 flag appends.
pub fn call_args(nargs: u8) -> u8 { fixed_args(nargs) + if nargs < 128 && nargs & 64 != 0 { 8 } else { 0 } }

impl Window {
    /// The registers the window covers for an instruction's operands.
    pub fn registers(&self, values: &[i64]) -> impl Iterator<Item = u8> {
        let base = values.get(self.base - 1).copied().unwrap_or(0) as u8;
        let n = values.get(self.count - 1).copied().unwrap_or(0) as u8;
        let count = match self.formula {
            Formula::N => n as usize,
            Formula::Minus1 => (n as usize).saturating_sub(1),
            Formula::Fixed => fixed_args(n) as usize,
            Formula::FixedMax1 => fixed_args(n).max(1) as usize,
            Formula::CallArgs => call_args(n) as usize,
            Formula::CallArgs1 => call_args(n) as usize + 1,
            Formula::RetN => { let n = if n >= 128 { (n & 127).saturating_add(8) } else { n }; n.max(1) as usize }
            Formula::SimdSpan => { let results = crate::simd::result_count(values[0] as u8, n as usize); (n as usize).max(results.saturating_sub(1)) + 1 }
            Formula::SimdResults => crate::simd::result_count(values[0] as u8, n as usize),
        };
        let first = base as usize + self.offset as usize;
        (first..first + count).filter_map(|r| u8::try_from(r).ok())
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Flow {
    Next,
    Branch,
    Jump,
    Table,
    Stop,
}

impl Flow {
    /// Whether the next instruction is a successor.
    pub fn falls(self) -> bool { matches!(self, Flow::Next | Flow::Branch) }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Opcode {
    pub name: String,
    pub flow: Flow,
    pub operands: Vec<OperandSpec>,
    pub windows: Vec<Window>,
    /// Liveness treats every register as read: the operands do not show them.
    pub frame: bool,
}

impl Opcode {
    /// The class of the register operand at `at` (0-based), given all the operands.
    pub fn register_class(&self, at: usize, values: &[i64]) -> Option<C> {
        match self.operands.get(at)?.class {
            Class::Reg(c) => Some(c),
            Class::ScalarByKind(k) => Some(if values.get(k - 1).copied().unwrap_or(0) >= 8 { C::F } else { C::I }),
            _ => None,
        }
    }
}

/// The table: one row per opcode, in `Op::NAMES` order.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Table {
    rows: Vec<Opcode>,
}

impl Table {
    pub fn row(&self, op: &Op) -> &Opcode { &self.rows[op.index()] }

    pub fn by_name(&self, name: &str) -> Option<&Opcode> { Op::NAMES.iter().position(|n| *n == name).map(|i| &self.rows[i]) }

    pub fn rows(&self) -> &[Opcode] { &self.rows }

    /// A table from rows in any order: every opcode once, nothing else.
    pub fn from_rows(rows: Vec<Opcode>) -> Result<Table, String> {
        let mut slots: Vec<Option<Opcode>> = vec![None; Op::NAMES.len()];
        for row in rows {
            let i = Op::NAMES.iter().position(|n| *n == row.name).ok_or_else(|| format!("opcode table names {}, which this runtime does not have", row.name))?;
            if slots[i].is_some() { return Err(format!("opcode table lists {} twice", row.name)); }
            slots[i] = Some(row);
        }
        let mut out = Vec::with_capacity(slots.len());
        for (i, slot) in slots.into_iter().enumerate() {
            out.push(slot.ok_or_else(|| format!("opcode table does not list {}", Op::NAMES[i]))?);
        }
        Ok(Table { rows: out })
    }
}

/// One `opcode` line's words after the keyword: name, flow, the operands, and
/// after `;` the windows and flags.
pub fn parse_row(parts: &[&str]) -> Result<Opcode, String> {
    let name = parts.first().ok_or("opcode line without a name")?.to_string();
    let flow = match parts.get(1).copied() {
        Some("next") => Flow::Next,
        Some("branch") => Flow::Branch,
        Some("jump") => Flow::Jump,
        Some("table") => Flow::Table,
        Some("stop") => Flow::Stop,
        other => return Err(format!("opcode {name}: unknown flow {}", other.unwrap_or(""))),
    };
    let mut operands = Vec::new();
    let mut windows = Vec::new();
    let mut frame = false;
    let mut rest = parts[2.min(parts.len())..].iter();
    for word in rest.by_ref() {
        if *word == ";" { break; }
        operands.push(parse_operand(&name, word)?);
    }
    for word in rest {
        if *word == "frame" { frame = true; } else { windows.push(parse_window(&name, word)?); }
    }
    for w in &windows {
        let register = |at: usize| matches!(operands.get(at - 1).map(|o| o.class), Some(Class::Reg(_)));
        if !register(w.base) || !matches!(operands.get(w.count - 1).map(|o| o.class), Some(Class::Imm)) { return Err(format!("opcode {name}: a window names an operand it cannot")); }
    }
    Ok(Opcode { name, flow, operands, windows, frame })
}

fn register_class(text: &str) -> Option<C> {
    match text { "v" => Some(C::V), "i" => Some(C::I), "f" => Some(C::F), "x" => Some(C::X), _ => None }
}

fn parse_operand(name: &str, word: &str) -> Result<OperandSpec, String> {
    let (word, optional) = match word.strip_suffix('?') { Some(w) => (w, true), None => (word, false) };
    let (class, mode) = word.split_once(':').map(|(c, m)| (c, Some(m))).unwrap_or((word, None));
    let class = if let Some(c) = register_class(class) { Class::Reg(c) } else if let Some(k) = class.strip_prefix("sk") {
        Class::ScalarByKind(k.parse().map_err(|_| format!("opcode {name}: operand {word}"))?)
    } else {
        match class { "k" => Class::Const, "j" => Class::Jump, "n" => Class::Imm, "s" => Class::Shape, "fn" => Class::Func, "t" => Class::Table, "name" => Class::Name, _ => return Err(format!("opcode {name}: unknown operand class {class}")) }
    };
    let mode = match mode {
        None => Mode::Use,
        Some("def") => Mode::Def,
        Some("use") => Mode::Use,
        Some("both") => Mode::Both,
        Some("check") => Mode::Check,
        Some("none") => Mode::None,
        Some(m) => return Err(format!("opcode {name}: unknown operand mode {m}")),
    };
    if !matches!(class, Class::Reg(_) | Class::ScalarByKind(_)) && mode != Mode::Use { return Err(format!("opcode {name}: {word} is not a register")); }
    Ok(OperandSpec { class, mode, optional })
}

fn parse_window(name: &str, word: &str) -> Result<Window, String> {
    let bad = || format!("opcode {name}: malformed window {word}");
    let (class, rest) = word.split_once(':').ok_or_else(bad)?;
    let class = register_class(class).ok_or_else(bad)?;
    let (mode, rest) = rest.split_once('@').ok_or_else(bad)?;
    let mode = match mode { "check" => WindowMode::Check, "def" => WindowMode::Def, "use" => WindowMode::Use, "defs" => WindowMode::Defs, "uses" => WindowMode::Uses, _ => return Err(bad()) };
    let (place, rest) = rest.split_once(':').ok_or_else(bad)?;
    let (base, offset) = place.split_once('+').ok_or_else(bad)?;
    let (count, formula) = rest.split_once(':').ok_or_else(bad)?;
    let formula = match formula {
        "n" => Formula::N,
        "minus1" => Formula::Minus1,
        "fixed" => Formula::Fixed,
        "fixedmax1" => Formula::FixedMax1,
        "callargs" => Formula::CallArgs,
        "callargs1" => Formula::CallArgs1,
        "retn" => Formula::RetN,
        "simdspan" => Formula::SimdSpan,
        "simdresults" => Formula::SimdResults,
        _ => return Err(bad()),
    };
    let number = |s: &str| s.parse::<usize>().map_err(|_| bad());
    let (base, count) = (number(base)?, number(count)?);
    if base == 0 || count == 0 { return Err(bad()); }
    Ok(Window { class, mode, base, offset: offset.parse().map_err(|_| bad())?, count, formula })
}

/// A whole table from its text, one `opcode` line per row.
pub fn parse_text(text: &str) -> Result<Table, String> {
    let mut rows = Vec::new();
    for line in text.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        match parts.first() {
            None => continue,
            Some(&"opcode") => rows.push(parse_row(&parts[1..])?),
            Some(other) => return Err(format!("opcode table: unexpected {other}")),
        }
    }
    Table::from_rows(rows)
}

/// The compiler's table as this crate was built with it, for images that
/// carry none. `tests/vmopcodetabletest.lua` holds it equal to the emitted one.
pub const DEFAULT: &str = include_str!("opcodes.table");

static INSTALLED: OnceLock<Table> = OnceLock::new();

/// The table this process reads code against.
pub fn table() -> &'static Table {
    INSTALLED.get_or_init(|| parse_text(DEFAULT).expect("the built-in opcode table is well formed"))
}

/// Installs the table an image carries. The first image's table is the
/// process's; a later image must carry the same one.
pub fn install(rows: Vec<Opcode>) -> Result<(), String> {
    let table = Table::from_rows(rows)?;
    let installed = INSTALLED.get_or_init(|| table.clone());
    if *installed != table {
        let differs = installed.rows.iter().zip(&table.rows).find(|(a, b)| a != b).map(|(a, _)| a.name.as_str()).unwrap_or("?");
        return Err(format!("the image's opcode table differs from the one this process loaded first (at {differs})"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_built_in_table_lists_every_opcode_once() {
        let table = parse_text(DEFAULT).unwrap();
        assert_eq!(table.rows.len(), Op::NAMES.len());
        for (name, row) in Op::NAMES.iter().zip(&table.rows) { assert_eq!(*name, row.name); }
    }

    #[test]
    fn operands_round_trip_through_the_enum() {
        let op = Op::Simd(3, 9, 8, 10, 2);
        assert_eq!(op.operands(), vec![3, 9, 10, 2, 8]);
        assert_eq!(Op::from_operands("Simd", &op.operands()).unwrap().operands(), op.operands());
        let plan = PhysicalField { identity: 1, name: 2, ordinal: 3, offset: 4, kind: 5 };
        assert_eq!(Op::SetPhysF(7, plan, 9).operands(), vec![7, 1, 2, 3, 4, 5, 9]);
        assert!(Op::from_operands("SetPhysF", &[7, 1, 2, 3, 4, 5]).is_none());
        assert!(Op::from_operands("RetNil", &[]).is_some());
        assert!(Op::from_operands("RetNil", &[1]).is_none());
        assert!(Op::from_operands("Nope", &[]).is_none());
        assert_eq!(Op::FK(2, 1.5).operands()[1], 1.5f64.to_bits() as i64);
    }
}
