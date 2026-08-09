//! Batched native lexer used only by `experiments/regex-lexer/benchmark.lua`.

use regex::bytes::Regex;
use std::{ptr, slice, sync::OnceLock};

const BOM: u32 = 1;
const HASHBANG: u32 = 2;
const WHITESPACE: u32 = 3;
const COMMENT: u32 = 4;
const NAME: u32 = 5;
const NUMBER: u32 = 6;
const STRING: u32 = 7;
const ERROR: u32 = 8;
const OPERATOR: u32 = 9;
const ISTRING_OPEN: u32 = 10;
const ISTRING_MID: u32 = 11;
const ISTRING_CLOSE: u32 = 12;
const EOF: u32 = 13;

const UNTERMINATED_LONG_COMMENT: u32 = 1;
const MALFORMED_NUMBER: u32 = 2;
const UNTERMINATED_STRING: u32 = 3;
const UNTERMINATED_INTERPOLATED_STRING: u32 = 4;
const UNTERMINATED_LONG_STRING: u32 = 5;
const UNEXPECTED_CHARACTER: u32 = 6;

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct NuppLexerSpan {
    start: usize,
    end: usize,
    line: usize,
    col: usize,
    kind: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct NuppLexerError {
    start: usize,
    end: usize,
    line: usize,
    col: usize,
    kind: u32,
}

pub struct NuppLexerResult {
    spans: Box<[NuppLexerSpan]>,
    errors: Box<[NuppLexerError]>,
}

struct Scanner<'a> {
    source: &'a [u8],
    pos: usize,
    line: usize,
    line_start: usize,
    interpolation: Vec<usize>,
    spans: Vec<NuppLexerSpan>,
    errors: Vec<NuppLexerError>,
}

fn matcher() -> &'static Regex {
    static MATCHER: OnceLock<Regex> = OnceLock::new();
    MATCHER.get_or_init(|| {
        Regex::new(concat!(
            r#"(?P<whitespace>[ \t\r\n\x0B\x0C]+)"#,
            r#"|(?P<long_comment>--\[=*\[)"#,
            r#"|(?P<comment>--(?-u:[^\n])*)"#,
            r#"|(?P<string>\"(?:\\(?s-u:.)|(?-u:[^\"\\\n]))*\"|'(?:\\(?s-u:.)|(?-u:[^'\\\n]))*')"#,
            r#"|(?P<unterminated>\"(?:\\(?s-u:.)|(?-u:[^\"\\\n]))*\\?|'(?:\\(?s-u:.)|(?-u:[^'\\\n]))*\\?)"#,
            r#"|(?P<name>[A-Za-z_][A-Za-z0-9_]*)"#,
            r#"|(?P<long_string>\[=*\[)"#,
            r#"|(?P<operator>~>>=|\.\.\.|<<=|>>=|//=|\.\.=|\?\?=|~>>|<<|>>|==|~=|<=|>=|\?\.|::|//|\.\.|->|\?\?|\+=|-=|\*=|/=|%=|&=|\|=|&&|\|\||!=|[+\-*/%^#&~|<>=(){}\[\];:,.?@!])"#,
            r#"|(?P<error>(?s-u:.))"#,
        ))
        .expect("the lexer regex is static and valid")
    })
}

impl<'a> Scanner<'a> {
    fn new(source: &'a [u8]) -> Self {
        Self {
            source,
            pos: 0,
            line: 1,
            line_start: 0,
            interpolation: Vec::new(),
            spans: Vec::new(),
            errors: Vec::new(),
        }
    }

    fn location(&self, offset: usize) -> (usize, usize) {
        (self.line, offset.saturating_sub(self.line_start) + 1)
    }

    fn error(&mut self, start: usize, end: usize, line: usize, col: usize, kind: u32) {
        self.errors.push(NuppLexerError {
            start,
            end: end.max(start + 1),
            line,
            col,
            kind,
        });
    }

    fn span(&mut self, start: usize, end: usize, line: usize, col: usize, kind: u32) {
        self.spans.push(NuppLexerSpan {
            start,
            end,
            line,
            col,
            kind,
        });
        for (relative, byte) in self.source
            [start.min(self.source.len())..end.min(self.source.len())]
            .iter()
            .enumerate()
        {
            if *byte == b'\n' {
                self.line += 1;
                self.line_start = start + relative + 1;
            }
        }
    }

    fn scan_long_bracket(&self, start: usize) -> Option<(usize, bool)> {
        if self.source.get(start) != Some(&b'[') {
            return None;
        }
        let mut at = start + 1;
        while self.source.get(at) == Some(&b'=') {
            at += 1;
        }
        if self.source.get(at) != Some(&b'[') {
            return None;
        }
        let level = at - start - 1;
        let body = at + 1;
        let close_len = level + 2;
        let mut candidate = body;
        while candidate + close_len <= self.source.len() {
            if self.source[candidate] == b']'
                && self.source[candidate + 1..candidate + 1 + level]
                    .iter()
                    .all(|byte| *byte == b'=')
                && self.source[candidate + 1 + level] == b']'
            {
                return Some((candidate + close_len, true));
            }
            candidate += 1;
        }
        Some((self.source.len(), false))
    }

    fn skip_underscores(&self, mut at: usize) -> usize {
        while self.source.get(at) == Some(&b'_') {
            at += 1;
        }
        at
    }

    fn scan_digits(&self, mut at: usize, predicate: fn(u8) -> bool) -> (usize, usize) {
        let mut digits = 0;
        while self.source.get(at).copied().is_some_and(predicate) {
            digits += 1;
            at = self.skip_underscores(at + 1);
        }
        (at, digits)
    }

    fn suffix(&self, start: usize, word: &[u8]) -> Option<usize> {
        let mut at = start;
        for wanted in word {
            let found = self.source.get(at).copied()?.to_ascii_lowercase();
            if found != *wanted {
                return None;
            }
            at = self.skip_underscores(at + 1);
        }
        Some(at)
    }

    fn scan_number(&self) -> (usize, bool) {
        let mut at = self.pos;
        let mut well_formed = true;
        let marker = if self.source.get(at) == Some(&b'0') {
            self.skip_underscores(at + 1)
        } else {
            at + 1
        };

        if self.source.get(at) == Some(&b'0')
            && matches!(self.source.get(marker), Some(b'x' | b'X'))
        {
            at = self.skip_underscores(marker + 1);
            let (next, mut digits) = self.scan_digits(at, is_hex);
            at = next;
            if self.source.get(at) == Some(&b'.') && self.source.get(at + 1) != Some(&b'.') {
                at = self.skip_underscores(at + 1);
                let (next, more) = self.scan_digits(at, is_hex);
                at = next;
                digits += more;
            }
            if digits == 0 {
                well_formed = false;
            }
            if matches!(self.source.get(at), Some(b'p' | b'P')) {
                at = self.skip_underscores(at + 1);
                if matches!(self.source.get(at), Some(b'+' | b'-')) {
                    at = self.skip_underscores(at + 1);
                }
                if !self.source.get(at).copied().is_some_and(is_digit) {
                    well_formed = false;
                }
                at = self.scan_digits(at, is_digit).0;
            }
        } else {
            if self.source.get(at) == Some(&b'.') {
                at += 1;
            }
            at = self.scan_digits(at, is_digit).0;
            if self.source.get(at) == Some(&b'.') && self.source.get(at + 1) != Some(&b'.') {
                at = self.skip_underscores(at + 1);
                at = self.scan_digits(at, is_digit).0;
            }
            if matches!(self.source.get(at), Some(b'e' | b'E')) {
                at = self.skip_underscores(at + 1);
                if matches!(self.source.get(at), Some(b'+' | b'-')) {
                    at = self.skip_underscores(at + 1);
                }
                if !self.source.get(at).copied().is_some_and(is_digit) {
                    well_formed = false;
                }
                at = self.scan_digits(at, is_digit).0;
            }
        }

        at = self
            .suffix(at, b"ull")
            .or_else(|| self.suffix(at, b"ll"))
            .or_else(|| self.suffix(at, b"i"))
            .unwrap_or(at);
        if self.source.get(at).copied().is_some_and(is_name_char) {
            at += 1;
            while self.source.get(at).copied().is_some_and(is_name_char) {
                at += 1;
            }
            well_formed = false;
        }
        (at, well_formed)
    }

    fn scan_interpolated_string(&mut self, opening: bool) -> u32 {
        let start = self.pos;
        let (line, col) = self.location(start);
        self.pos += 1;
        while self.pos < self.source.len() {
            match self.source[self.pos] {
                b'\\' => self.pos += 2,
                b'`' => {
                    self.pos += 1;
                    if opening {
                        return STRING;
                    }
                    self.interpolation.pop();
                    return ISTRING_CLOSE;
                }
                b'$' if self.source.get(self.pos + 1) == Some(&b'{') => {
                    self.pos += 2;
                    if opening {
                        self.interpolation.push(0);
                    } else if let Some(depth) = self.interpolation.last_mut() {
                        *depth = 0;
                    }
                    return if opening { ISTRING_OPEN } else { ISTRING_MID };
                }
                _ => self.pos += 1,
            }
        }
        if !opening {
            self.interpolation.pop();
        }
        self.error(start, self.pos, line, col, UNTERMINATED_INTERPOLATED_STRING);
        ERROR
    }

    fn scan(mut self) -> NuppLexerResult {
        let source = self.source;
        'restart: while self.pos < source.len() {
            let base = self.pos;
            for captures in matcher().captures_iter(&source[base..]) {
                let whole = captures.get(0).expect("every capture has a whole match");
                let start = base + whole.start();
                let matched_end = base + whole.end();
                if start < self.pos {
                    assert!(
                        matched_end <= self.pos,
                        "a regex match crossed a scanned token"
                    );
                    continue;
                }
                debug_assert_eq!(start, self.pos, "the byte fallback leaves no gaps");
                let (line, col) = self.location(start);

                if start == 0 && source.starts_with(&[0xEF, 0xBB, 0xBF]) {
                    self.pos = 3;
                    self.span(start, self.pos, line, col, BOM);
                    continue 'restart;
                }
                if start == 0 && source.first() == Some(&b'#') {
                    self.pos = source[start..]
                        .iter()
                        .position(|byte| *byte == b'\n')
                        .map_or(source.len(), |relative| start + relative + 1);
                    self.span(start, self.pos, line, col, HASHBANG);
                    continue 'restart;
                }

                if captures.get(2).is_some() {
                    let (end, terminated) = self
                        .scan_long_bracket(start + 2)
                        .expect("the regex matched a long-comment opener");
                    self.pos = end;
                    if !terminated {
                        self.error(start, end, line, col, UNTERMINATED_LONG_COMMENT);
                    }
                    self.span(start, end, line, col, COMMENT);
                    continue 'restart;
                }

                let byte = source[start];
                if is_digit(byte)
                    || (byte == b'.' && source.get(start + 1).copied().is_some_and(is_digit))
                {
                    let (end, well_formed) = self.scan_number();
                    self.pos = end;
                    let kind = if well_formed { NUMBER } else { ERROR };
                    if !well_formed {
                        self.error(start, end, line, col, MALFORMED_NUMBER);
                    }
                    self.span(start, end, line, col, kind);
                    continue;
                }

                if byte == b'`' {
                    let kind = self.scan_interpolated_string(true);
                    self.span(start, self.pos, line, col, kind);
                    continue 'restart;
                }
                if byte == b'{' && !self.interpolation.is_empty() {
                    *self.interpolation.last_mut().expect("checked nonempty") += 1;
                    self.pos += 1;
                    self.span(start, self.pos, line, col, OPERATOR);
                    continue;
                }
                if byte == b'}' && self.interpolation.last() == Some(&0) {
                    let kind = self.scan_interpolated_string(false);
                    self.span(start, self.pos, line, col, kind);
                    continue 'restart;
                }
                if byte == b'}' && !self.interpolation.is_empty() {
                    *self.interpolation.last_mut().expect("checked nonempty") -= 1;
                    self.pos += 1;
                    self.span(start, self.pos, line, col, OPERATOR);
                    continue;
                }

                if captures.get(7).is_some() {
                    let (end, terminated) = self
                        .scan_long_bracket(start)
                        .expect("the regex matched a long-string opener");
                    self.pos = end;
                    let kind = if terminated { STRING } else { ERROR };
                    if !terminated {
                        self.error(start, end, line, col, UNTERMINATED_LONG_STRING);
                    }
                    self.span(start, end, line, col, kind);
                    continue 'restart;
                }

                self.pos = matched_end;
                let kind = if captures.get(1).is_some() {
                    WHITESPACE
                } else if captures.get(3).is_some() {
                    COMMENT
                } else if captures.get(4).is_some() {
                    STRING
                } else if captures.get(5).is_some() {
                    self.error(start, self.pos, line, col, UNTERMINATED_STRING);
                    ERROR
                } else if captures.get(6).is_some() {
                    NAME
                } else if captures.get(8).is_some() {
                    OPERATOR
                } else {
                    self.error(start, self.pos, line, col, UNEXPECTED_CHARACTER);
                    ERROR
                };
                self.span(start, self.pos, line, col, kind);
            }
            break;
        }

        if !self.interpolation.is_empty() {
            let (line, col) = self.location(self.pos);
            self.error(
                self.pos,
                self.pos + 1,
                line,
                col,
                UNTERMINATED_INTERPOLATED_STRING,
            );
        }
        let (line, col) = self.location(self.pos);
        self.span(self.pos, self.pos, line, col, EOF);
        NuppLexerResult {
            spans: self.spans.into_boxed_slice(),
            errors: self.errors.into_boxed_slice(),
        }
    }
}

fn is_digit(byte: u8) -> bool {
    byte.is_ascii_digit()
}

fn is_hex(byte: u8) -> bool {
    byte.is_ascii_hexdigit()
}

fn is_name_char(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
}

unsafe fn source<'a>(data: *const u8, length: usize) -> Option<&'a [u8]> {
    if data.is_null() {
        return (length == 0).then_some(&[]);
    }
    Some(unsafe { slice::from_raw_parts(data, length) })
}

#[no_mangle]
/// Tokenizes one byte string and returns an owned result.
///
/// # Safety
///
/// `data` must address `length` readable bytes, unless `length` is zero.
pub unsafe extern "C" fn nuppLexerTokenize(data: *const u8, length: usize) -> *mut NuppLexerResult {
    let Some(source) = (unsafe { source(data, length) }) else {
        return ptr::null_mut();
    };
    Box::into_raw(Box::new(Scanner::new(source).scan()))
}

#[no_mangle]
/// Returns the number of spans in a lexer result.
///
/// # Safety
///
/// `result` must be null or a live result returned by [`nuppLexerTokenize`].
pub unsafe extern "C" fn nuppLexerSpanCount(result: *const NuppLexerResult) -> usize {
    if result.is_null() {
        0
    } else {
        unsafe { &*result }.spans.len()
    }
}

#[no_mangle]
/// Borrows the span array held by a lexer result.
///
/// # Safety
///
/// `result` must be null or a live result returned by [`nuppLexerTokenize`]. The
/// returned pointer is valid only until that result is destroyed.
pub unsafe extern "C" fn nuppLexerSpans(result: *const NuppLexerResult) -> *const NuppLexerSpan {
    if result.is_null() {
        ptr::null()
    } else {
        unsafe { &*result }.spans.as_ptr()
    }
}

#[no_mangle]
/// Returns the number of diagnostics in a lexer result.
///
/// # Safety
///
/// `result` must be null or a live result returned by [`nuppLexerTokenize`].
pub unsafe extern "C" fn nuppLexerErrorCount(result: *const NuppLexerResult) -> usize {
    if result.is_null() {
        0
    } else {
        unsafe { &*result }.errors.len()
    }
}

#[no_mangle]
/// Borrows the diagnostic array held by a lexer result.
///
/// # Safety
///
/// `result` must be null or a live result returned by [`nuppLexerTokenize`]. The
/// returned pointer is valid only until that result is destroyed.
pub unsafe extern "C" fn nuppLexerErrors(result: *const NuppLexerResult) -> *const NuppLexerError {
    if result.is_null() {
        ptr::null()
    } else {
        unsafe { &*result }.errors.as_ptr()
    }
}

#[no_mangle]
/// Destroys a lexer result.
///
/// # Safety
///
/// `result` must be null or a live result returned by [`nuppLexerTokenize`] that
/// has not previously been destroyed.
pub unsafe extern "C" fn nuppLexerDestroy(result: *mut NuppLexerResult) {
    if !result.is_null() {
        drop(unsafe { Box::from_raw(result) });
    }
}
