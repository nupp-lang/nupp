//! The `.d.nupp` declarations native modules are checked against.
//!
//! A host module, whether an embedder registers it or a program loads it from
//! a native extension, declares its functions in Nupp: the `.d.nupp` file
//! typed callers were checked with. This reads the part of that file the
//! boundary needs -- the record the module returns, its function fields and
//! their types -- and spells each type canonically, without parameter names,
//! so a signature a library registers can be compared with the declaration.
//! It is not a checker: anything it does not understand in a record body it
//! skips, and named types stay names.
use std::collections::BTreeMap;
use std::fmt;

#[derive(Clone, Debug, PartialEq)]
pub enum Ty {
    Nil,
    Boolean,
    Integer,
    Int32,
    Uint32,
    Int64,
    Number,
    String,
    Any,
    Optional(Box<Ty>),
    Function(Box<Signature>),
    /// `{T}`, `{[K]: V}` or `{name: T, ...}`, spelled canonically.
    Table(std::string::String),
    /// A named type, possibly generic, spelled canonically.
    Named(std::string::String),
    Union(Vec<Ty>),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Signature {
    pub params: Vec<Ty>,
    pub vararg: Option<Ty>,
    pub results: Vec<Ty>,
}

/// A module's declaration: its function fields by name.
#[derive(Clone, Debug, PartialEq)]
pub struct Declaration {
    /// The library an `@extension NAME` marker names, as `foreign.load` takes it.
    pub library: Option<std::string::String>,
    pub functions: BTreeMap<std::string::String, Signature>,
}

impl fmt::Display for Ty {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Ty::Nil => f.write_str("nil"),
            Ty::Boolean => f.write_str("boolean"),
            Ty::Integer => f.write_str("integer"),
            Ty::Int32 => f.write_str("int32"),
            Ty::Uint32 => f.write_str("uint32"),
            Ty::Int64 => f.write_str("int64"),
            Ty::Number => f.write_str("number"),
            Ty::String => f.write_str("string"),
            Ty::Any => f.write_str("any"),
            Ty::Optional(t) => match **t {
                Ty::Union(_) | Ty::Function(_) => write!(f, "({t})?"),
                _ => write!(f, "{t}?"),
            },
            Ty::Function(s) => write!(f, "{s}"),
            Ty::Table(t) | Ty::Named(t) => f.write_str(t),
            Ty::Union(ts) => {
                for (i, t) in ts.iter().enumerate() {
                    if i > 0 {
                        f.write_str(" | ")?;
                    }
                    match t {
                        Ty::Function(_) => write!(f, "({t})")?,
                        _ => write!(f, "{t}")?,
                    }
                }
                Ok(())
            }
        }
    }
}

impl fmt::Display for Signature {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("function(")?;
        for (i, p) in self.params.iter().enumerate() {
            if i > 0 {
                f.write_str(", ")?;
            }
            write!(f, "{p}")?;
        }
        if let Some(v) = &self.vararg {
            if !self.params.is_empty() {
                f.write_str(", ")?;
            }
            write!(f, "...: {v}")?;
        }
        f.write_str(")")?;
        match self.results.len() {
            0 => Ok(()),
            1 => write!(f, ": {}", self.results[0]),
            _ => {
                f.write_str(": (")?;
                for (i, r) in self.results.iter().enumerate() {
                    if i > 0 {
                        f.write_str(", ")?;
                    }
                    write!(f, "{r}")?;
                }
                f.write_str(")")
            }
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    Name(std::string::String),
    Str(std::string::String),
    Num(std::string::String),
    Sym(&'static str),
}

struct Lexer<'a> {
    text: &'a [u8],
    at: usize,
    marker: Option<std::string::String>,
}

const SYMBOLS: &[&str] = &["...", "(", ")", "{", "}", "[", "]", ":", ",", "?", "|", ".", "=", "<", ">", ";", "-", "#", "+", "*", "/", "%", "^", "~", "&"];

impl<'a> Lexer<'a> {
    /// The text of a comment, for the `@extension` marker.
    fn comment(&mut self, body: &str) {
        let mut words = body.split_whitespace();
        while let Some(w) = words.next() {
            if w == "@extension" {
                if let Some(name) = words.next() {
                    self.marker.get_or_insert_with(|| name.trim_matches('"').to_string());
                }
            }
        }
    }
    /// `[[`, `[=[`... at `at`: the level, or None.
    fn long_open(&self, at: usize) -> Option<usize> {
        if self.text.get(at) != Some(&b'[') {
            return None;
        }
        let mut level = 0;
        while self.text.get(at + 1 + level) == Some(&b'=') {
            level += 1;
        }
        (self.text.get(at + 1 + level) == Some(&b'[')).then_some(level)
    }
    fn long_body(&mut self, level: usize) -> Result<std::string::String, std::string::String> {
        let close = format!("]{}]", "=".repeat(level));
        let start = self.at;
        let rest = std::str::from_utf8(&self.text[start..]).map_err(|_| "declaration is not UTF-8")?;
        let end = rest.find(&close).ok_or("unterminated long bracket")?;
        self.at = start + end + close.len();
        Ok(rest[..end].to_string())
    }
    fn next(&mut self) -> Result<Option<Tok>, std::string::String> {
        loop {
            while self.at < self.text.len() && self.text[self.at].is_ascii_whitespace() {
                self.at += 1;
            }
            if self.at >= self.text.len() {
                return Ok(None);
            }
            if self.text[self.at..].starts_with(b"--") {
                self.at += 2;
                if let Some(level) = self.long_open(self.at) {
                    self.at += level + 2;
                    let body = self.long_body(level)?;
                    self.comment(&body);
                } else {
                    let start = self.at;
                    while self.at < self.text.len() && self.text[self.at] != b'\n' {
                        self.at += 1;
                    }
                    let body = std::string::String::from_utf8_lossy(&self.text[start..self.at]).into_owned();
                    self.comment(&body);
                }
                continue;
            }
            break;
        }
        let c = self.text[self.at];
        if c.is_ascii_alphabetic() || c == b'_' {
            let start = self.at;
            while self.at < self.text.len() && (self.text[self.at].is_ascii_alphanumeric() || self.text[self.at] == b'_') {
                self.at += 1;
            }
            return Ok(Some(Tok::Name(std::string::String::from_utf8_lossy(&self.text[start..self.at]).into_owned())));
        }
        if c.is_ascii_digit() {
            let start = self.at;
            while self.at < self.text.len() && (self.text[self.at].is_ascii_alphanumeric() || self.text[self.at] == b'.') {
                self.at += 1;
            }
            return Ok(Some(Tok::Num(std::string::String::from_utf8_lossy(&self.text[start..self.at]).into_owned())));
        }
        if c == b'"' || c == b'\'' {
            let start = self.at;
            self.at += 1;
            while self.at < self.text.len() && self.text[self.at] != c {
                if self.text[self.at] == b'\\' {
                    self.at += 1;
                }
                self.at += 1;
            }
            self.at += 1;
            let end = self.at.min(self.text.len());
            return Ok(Some(Tok::Str(std::string::String::from_utf8_lossy(&self.text[start..end]).into_owned())));
        }
        if let Some(level) = self.long_open(self.at) {
            self.at += level + 2;
            let body = self.long_body(level)?;
            return Ok(Some(Tok::Str(format!("[[{body}]]"))));
        }
        for s in SYMBOLS {
            if self.text[self.at..].starts_with(s.as_bytes()) {
                self.at += s.len();
                return Ok(Some(Tok::Sym(s)));
            }
        }
        self.at += 1;
        Ok(Some(Tok::Sym("?other")))
    }
}

struct Parser {
    toks: Vec<Tok>,
    at: usize,
}

type Res<T> = Result<T, std::string::String>;

impl Parser {
    fn peek(&self) -> Option<&Tok> {
        self.toks.get(self.at)
    }
    fn peek_at(&self, n: usize) -> Option<&Tok> {
        self.toks.get(self.at + n)
    }
    fn is_sym(&self, s: &str) -> bool {
        matches!(self.peek(), Some(Tok::Sym(x)) if *x == s)
    }
    fn is_name(&self, s: &str) -> bool {
        matches!(self.peek(), Some(Tok::Name(x)) if x == s)
    }
    fn bump(&mut self) -> Option<Tok> {
        let t = self.toks.get(self.at).cloned();
        self.at += 1;
        t
    }
    fn expect(&mut self, s: &str) -> Res<()> {
        if self.is_sym(s) {
            self.at += 1;
            Ok(())
        } else {
            Err(format!("expected `{s}` in a declaration, found {}", self.describe()))
        }
    }
    fn describe(&self) -> std::string::String {
        match self.peek() {
            None => "the end".into(),
            Some(Tok::Name(n)) | Some(Tok::Num(n)) | Some(Tok::Str(n)) => format!("`{n}`"),
            Some(Tok::Sym(s)) => format!("`{s}`"),
        }
    }
    fn name(&mut self) -> Res<std::string::String> {
        match self.bump() {
            Some(Tok::Name(n)) => Ok(n),
            _ => {
                self.at -= 1;
                Err(format!("expected a name in a declaration, found {}", self.describe()))
            }
        }
    }

    fn ty(&mut self) -> Res<Ty> {
        let first = self.postfix()?;
        if !self.is_sym("|") {
            return Ok(first);
        }
        let mut members = vec![first];
        while self.is_sym("|") {
            self.at += 1;
            members.push(self.postfix()?);
        }
        Ok(Ty::Union(members))
    }
    fn postfix(&mut self) -> Res<Ty> {
        let mut t = self.primary()?;
        while self.is_sym("?") {
            self.at += 1;
            if !matches!(t, Ty::Optional(_)) {
                t = Ty::Optional(Box::new(t));
            }
        }
        Ok(t)
    }
    fn primary(&mut self) -> Res<Ty> {
        match self.peek().cloned() {
            Some(Tok::Name(n)) if n == "function" => {
                self.at += 1;
                Ok(Ty::Function(Box::new(self.signature_rest()?)))
            }
            Some(Tok::Sym("{")) => {
                self.at += 1;
                self.table()
            }
            Some(Tok::Sym("(")) => {
                self.at += 1;
                let t = self.ty()?;
                self.expect(")")?;
                Ok(t)
            }
            Some(Tok::Str(s)) => {
                self.at += 1;
                Ok(Ty::Named(s))
            }
            Some(Tok::Name(n)) => {
                self.at += 1;
                let mut name = n;
                while self.is_sym(".") {
                    self.at += 1;
                    name.push('.');
                    name.push_str(&self.name()?);
                }
                if self.is_sym("<") {
                    self.at += 1;
                    let mut args = vec![self.ty()?];
                    while self.is_sym(",") {
                        self.at += 1;
                        args.push(self.ty()?);
                    }
                    self.expect(">")?;
                    let args: Vec<_> = args.iter().map(|a| a.to_string()).collect();
                    return Ok(Ty::Named(format!("{name}<{}>", args.join(", "))));
                }
                Ok(match name.as_str() {
                    "nil" => Ty::Nil,
                    "boolean" => Ty::Boolean,
                    "integer" => Ty::Integer,
                    "int32" => Ty::Int32,
                    "uint32" => Ty::Uint32,
                    "int64" => Ty::Int64,
                    "number" => Ty::Number,
                    "string" => Ty::String,
                    "any" | "unknown" => Ty::Any,
                    _ => Ty::Named(name),
                })
            }
            _ => Err(format!("expected a type in a declaration, found {}", self.describe())),
        }
    }
    /// After `{`: an array, a map or a structural record type.
    fn table(&mut self) -> Res<Ty> {
        if self.is_sym("}") {
            self.at += 1;
            return Ok(Ty::Table("{}".into()));
        }
        if self.is_sym("[") {
            self.at += 1;
            let k = self.ty()?;
            self.expect("]")?;
            self.expect(":")?;
            let v = self.ty()?;
            self.expect("}")?;
            return Ok(Ty::Table(format!("{{[{k}]: {v}}}")));
        }
        let named_field = matches!(self.peek(), Some(Tok::Name(_)))
            && (matches!(self.peek_at(1), Some(Tok::Sym(":")))
                || matches!(self.peek_at(1), Some(Tok::Sym("?"))) && matches!(self.peek_at(2), Some(Tok::Sym(":"))));
        if !named_field {
            let t = self.ty()?;
            self.expect("}")?;
            return Ok(Ty::Table(format!("{{{t}}}")));
        }
        let mut fields = Vec::new();
        while !self.is_sym("}") {
            let n = self.name()?;
            let optional = self.is_sym("?");
            if optional {
                self.at += 1;
            }
            self.expect(":")?;
            let t = self.ty()?;
            fields.push(format!("{n}{}: {t}", if optional { "?" } else { "" }));
            if self.is_sym(",") || self.is_sym(";") {
                self.at += 1;
            }
        }
        self.at += 1;
        Ok(Ty::Table(format!("{{{}}}", fields.join(", "))))
    }
    /// After `function`: `(params)` and optional `: results`.
    fn signature_rest(&mut self) -> Res<Signature> {
        if self.is_sym("<") {
            return Err("generic host functions cannot be declared at a native boundary".into());
        }
        self.expect("(")?;
        let mut params = Vec::new();
        let mut vararg = None;
        while !self.is_sym(")") {
            if self.is_sym("...") {
                self.at += 1;
                vararg = Some(if self.is_sym(":") {
                    self.at += 1;
                    self.ty()?
                } else {
                    Ty::Any
                });
            } else {
                let named = matches!(self.peek(), Some(Tok::Name(_)))
                    && (matches!(self.peek_at(1), Some(Tok::Sym(":")))
                        || matches!(self.peek_at(1), Some(Tok::Sym("?"))) && matches!(self.peek_at(2), Some(Tok::Sym(":"))));
                let mut optional = false;
                if named {
                    self.at += 1;
                    if self.is_sym("?") {
                        self.at += 1;
                        optional = true;
                    }
                    self.expect(":")?;
                }
                let t = self.ty()?;
                params.push(if optional && !matches!(t, Ty::Optional(_)) { Ty::Optional(Box::new(t)) } else { t });
            }
            if self.is_sym(",") {
                self.at += 1;
            } else {
                break;
            }
        }
        self.expect(")")?;
        let mut results = Vec::new();
        if self.is_sym(":") {
            self.at += 1;
            if self.is_sym("(") {
                // A parenthesized result list, or one parenthesized type.
                self.at += 1;
                let mut list = vec![self.ty()?];
                while self.is_sym(",") {
                    self.at += 1;
                    list.push(self.ty()?);
                }
                self.expect(")")?;
                if list.len() == 1 && self.is_sym("?") {
                    self.at += 1;
                    let t = list.pop().unwrap();
                    list.push(Ty::Optional(Box::new(t)));
                }
                results = list;
            } else {
                results.push(self.ty()?);
            }
        }
        // `: nil` returns nothing a caller can tell from no results.
        if results == [Ty::Nil] {
            results.clear();
        }
        Ok(Signature { params, vararg, results })
    }

    /// Skips a nested declaration to its matching `end`.
    fn skip_block(&mut self) -> Res<()> {
        let mut depth = 1;
        while depth > 0 {
            match self.bump() {
                None => return Err("a record in the declaration has no `end`".into()),
                Some(Tok::Name(n)) if n == "end" => depth -= 1,
                Some(Tok::Name(n)) if matches!(n.as_str(), "record" | "enum" | "interface") => depth += 1,
                _ => {}
            }
        }
        Ok(())
    }
    /// A record body after its name, through `end`: its fields.
    fn record(&mut self) -> Res<Vec<(std::string::String, Ty)>> {
        if self.is_sym("<") {
            while !self.is_sym(">") && self.peek().is_some() {
                self.at += 1;
            }
            self.at += 1;
        }
        let mut fields = Vec::new();
        loop {
            match self.peek().cloned() {
                None => return Err("a record in the declaration has no `end`".into()),
                Some(Tok::Name(n)) if n == "end" => {
                    self.at += 1;
                    return Ok(fields);
                }
                Some(Tok::Name(n)) if matches!(n.as_str(), "record" | "enum" | "interface") => {
                    self.at += 1;
                    self.skip_block()?;
                }
                Some(Tok::Name(n)) if n == "type" && matches!(self.peek_at(1), Some(Tok::Name(_))) && matches!(self.peek_at(2), Some(Tok::Sym("=" | "<"))) => {
                    self.at += 2;
                    while !self.is_sym("=") {
                        self.at += 1;
                    }
                    self.at += 1;
                    self.ty()?;
                }
                Some(Tok::Name(n))
                    if matches!(self.peek_at(1), Some(Tok::Sym(":")))
                        || matches!(self.peek_at(1), Some(Tok::Sym("?"))) && matches!(self.peek_at(2), Some(Tok::Sym(":"))) =>
                {
                    self.at += 1;
                    let optional = self.is_sym("?");
                    if optional {
                        self.at += 1;
                    }
                    self.expect(":")?;
                    let t = self.ty()?;
                    fields.push((n, if optional { Ty::Optional(Box::new(t)) } else { t }));
                }
                _ => {
                    self.at += 1;
                }
            }
        }
    }
}

fn tokens(text: &str) -> Res<(Vec<Tok>, Option<std::string::String>)> {
    let mut lexer = Lexer { text: text.as_bytes(), at: 0, marker: None };
    let mut toks = Vec::new();
    while let Some(t) = lexer.next()? {
        toks.push(t);
    }
    Ok((toks, lexer.marker))
}

/// A Nupp function type: `function(a: integer, b: integer): integer`.
pub fn parse_signature(text: &str) -> Res<Signature> {
    let (toks, _) = tokens(text)?;
    let mut p = Parser { toks, at: 0 };
    if !p.is_name("function") {
        return Err(format!("signature {text:?} is not a function type"));
    }
    p.at += 1;
    let s = p.signature_rest()?;
    if p.peek().is_some() {
        return Err(format!("signature {text:?} has text after its type: {}", p.describe()));
    }
    Ok(s)
}

/// The module a `.d.nupp` declares: the record it returns (or exports), and
/// that record's function fields. A field that is not a function is refused:
/// a native module answers calls, it holds no fields of its own.
pub fn parse(text: &str) -> Res<Declaration> {
    let (toks, library) = tokens(text)?;
    let mut p = Parser { toks, at: 0 };
    let mut records: BTreeMap<std::string::String, Vec<(std::string::String, Ty)>> = BTreeMap::new();
    let mut order = Vec::new();
    let mut returned = None;
    while let Some(t) = p.peek().cloned() {
        match t {
            Tok::Name(n) if n == "record" => {
                p.at += 1;
                let name = p.name()?;
                let fields = p.record()?;
                order.push(name.clone());
                records.insert(name, fields);
            }
            Tok::Name(n) if matches!(n.as_str(), "enum" | "interface") => {
                p.at += 1;
                p.skip_block()?;
            }
            Tok::Name(n) if n == "return" => {
                p.at += 1;
                returned = Some(p.name()?);
            }
            Tok::Name(n) if n == "export" && matches!(p.peek_at(1), Some(Tok::Sym("="))) => {
                p.at += 2;
                returned = Some(p.name()?);
            }
            _ => p.at += 1,
        }
    }
    let name = match returned {
        Some(name) => name,
        None if order.len() == 1 => order[0].clone(),
        None => return Err("the declaration returns no record".into()),
    };
    let fields = records.remove(&name).ok_or_else(|| format!("the declaration returns {name}, which is not a record it declares"))?;
    let mut functions = BTreeMap::new();
    for (field, t) in fields {
        match t {
            Ty::Function(s) => {
                functions.insert(field, *s);
            }
            other => return Err(format!("{field} is declared {other}; a native module declares only functions")),
        }
    }
    Ok(Declaration { library, functions })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn canonical_signatures_drop_names_and_keep_types() {
        let s = parse_signature("function(a: integer, b?: string, f: function(x: number): boolean): (integer, string?)").unwrap();
        assert_eq!(s.to_string(), "function(integer, string?, function(number): boolean): (integer, string?)");
        assert_eq!(parse_signature("function(): nil").unwrap().to_string(), "function()");
        assert_eq!(parse_signature("function(t: {[string]: integer}, ...: any)").unwrap().to_string(), "function({[string]: integer}, ...: any)");
        assert!(parse_signature("function(a: integer) extra").is_err());
    }
    #[test]
    fn module_declarations_read_the_returned_record() {
        let d = parse(
            "--- @extension counter\n--[[ long\n comment ]]\nlocal record Counter\n    --- Adds.\n    add: function(a: integer, b: integer): integer\n    record Nested\n        x: number\n    end\n    wait: function(ms: integer): string\nend\nreturn Counter\n",
        )
        .unwrap();
        assert_eq!(d.library.as_deref(), Some("counter"));
        assert_eq!(d.functions["add"].to_string(), "function(integer, integer): integer");
        assert_eq!(d.functions.len(), 2);
        assert!(parse("local record M\n  x: number\nend\nreturn M").unwrap_err().contains("only functions"));
    }
}
