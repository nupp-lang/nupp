//! A parser for `nupp aot --emit ir` text, the compiler's verified kernel IR.
//! Only the parts a kernel body uses are modelled: params, the block, and the
//! structured statements and call-shaped expressions inside it.

#[derive(Debug, Clone)]
pub enum Expr {
    Call { op: String, ty: Option<String>, args: Vec<Expr> },
    Local { ty: String, name: String },
    Uniform { ty: String, name: String },
    Constant { ty: String, value: String },
    Span(String),
    Count(String),
    /// `lua.string "..."`: a string literal.
    Str(String),
}

#[derive(Debug, Clone)]
pub enum Stmt {
    Let { name: String, ty: String, value: Expr, mutable: bool },
    Set { name: String, value: Expr },
    While { cond: Expr, body: Vec<Stmt>, carried: Vec<(String, String)> },
    If { cond: Expr, body: Vec<Stmt>, else_body: Vec<Stmt> },
    Expr(Expr),
    Return(Vec<Expr>),
    /// `op local:T target[index] = value`: a store into a scratch buffer.
    Store { op: String, target: String, index: Expr, value: Expr },
    /// `for var = start .. stop`: a numeric loop, inclusive.
    For { var: String, start: Expr, stop: Expr, body: Vec<Stmt> },
    Break,
}

#[derive(Debug, Clone)]
pub struct Param { pub kind: String, pub name: String, pub ty: String }

#[derive(Debug, Clone)]
pub struct Function { pub name: String, pub params: Vec<Param>, pub results: Vec<String>, pub body: Vec<Stmt>, pub relations: Vec<(String, String)> }

pub fn parse(text: &str) -> Result<Vec<Function>, String> {
    let lines: Vec<&str> = text.lines().collect();
    let mut i = 0;
    let mut out = Vec::new();
    while i < lines.len() {
        if let Some(name) = lines[i].strip_prefix("function ") {
            let mut f = Function { name: name.trim().to_string(), params: Vec::new(), results: Vec::new(), body: Vec::new(), relations: Vec::new() };
            i += 1;
            let mut section = "";
            while i < lines.len() && !lines[i].starts_with("function ") && !lines[i].starts_with("native-ir") {
                let line = lines[i];
                if !line.starts_with(' ') {
                    let head = line.split_whitespace().next().unwrap_or("");
                    section = head;
                    if head == "results" { f.results = line.split_whitespace().skip(1).filter(|s| *s != "nil").map(|s| s.to_string()).collect(); }
                    if head == "block" {
                        let (body, next) = parse_block(&lines, i + 1, 2)?;
                        f.body = body;
                        i = next;
                        continue;
                    }
                } else if section == "relations" {
                    // `#a <= #b @pos`: an entry guard the body may rely on.
                    let mut it = line.split_whitespace();
                    let a = it.next().unwrap().trim_start_matches('#').to_string();
                    let op = it.next().unwrap();
                    let b = it.next().unwrap().trim_start_matches('#').to_string();
                    if op == "<=" { f.relations.push((a, b)); }
                } else if section == "params" {
                    let mut it = line.split_whitespace();
                    let kind = it.next().unwrap().to_string();
                    let nt = it.next().unwrap();
                    let (name, ty) = nt.split_once(':').ok_or("param without type")?;
                    f.params.push(Param { kind, name: name.to_string(), ty: ty.to_string() });
                }
                i += 1;
            }
            out.push(f);
        } else {
            i += 1;
        }
    }
    Ok(out)
}

fn indent(line: &str) -> usize { line.len() - line.trim_start().len() }

/// Parses statements at exactly `depth` spaces of indent, returning them and the
/// index of the first line that is not part of this block.
fn parse_block(lines: &[&str], mut i: usize, depth: usize) -> Result<(Vec<Stmt>, usize), String> {
    let mut body = Vec::new();
    while i < lines.len() {
        let line = lines[i];
        if line.trim().is_empty() { i += 1; continue; }
        if indent(line) < depth || line.trim() == "end" || line.trim() == "else" || line.trim().starts_with("elseif ") { break; }
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("let ").or_else(|| t.strip_prefix("var ")) {
            let mutable = t.starts_with("var ");
            let (lhs, rhs) = rest.split_once(" = ").ok_or_else(|| format!("let without value: {t}"))?;
            let (name, ty) = lhs.split_once(':').ok_or("let without type")?;
            body.push(Stmt::Let { name: name.to_string(), ty: ty.to_string(), value: parse_expr(rhs)?, mutable });
            i += 1;
        } else if let Some(rest) = t.strip_prefix("set ") {
            let (name, rhs) = rest.split_once(" = ").ok_or("set without value")?;
            body.push(Stmt::Set { name: name.to_string(), value: parse_expr(rhs)? });
            i += 1;
        } else if let Some(rest) = t.strip_prefix("while ") {
            let (cond_text, carried_text) = match rest.split_once(" carrying ") { Some((c, k)) => (c, k), None => (rest, "") };
            let carried = carried_text.split(',').filter(|s| !s.trim().is_empty()).map(|s| { let (n, ty) = s.trim().split_once(':').unwrap(); (n.to_string(), ty.to_string()) }).collect();
            let cond = parse_expr(cond_text)?;
            let (inner, next) = parse_block(lines, i + 1, depth + 2)?;
            i = next;
            if lines.get(i).map(|l| l.trim()) != Some("end") { return Err(format!("while without end at line {i}")); }
            i += 1;
            body.push(Stmt::While { cond, body: inner, carried });
        } else if let Some(rest) = t.strip_prefix("if ") {
            let cond = parse_expr(rest)?;
            let (inner, next) = parse_block(lines, i + 1, depth + 2)?;
            let (else_body, next) = parse_else(lines, next, depth)?;
            i = next;
            if lines.get(i).map(|l| l.trim()) != Some("end") { return Err(format!("if without end at line {i}")); }
            i += 1;
            body.push(Stmt::If { cond, body: inner, else_body });
        } else if t == "break" {
            body.push(Stmt::Break);
            i += 1;
        } else if let Some(rest) = t.strip_prefix("for ") {
            let (var, range) = rest.split_once(" = ").ok_or("for without range")?;
            let range = match range.split_once(" carrying ") { Some((r, _)) => r, None => range };
            let (start, stop) = range.split_once(" .. ").ok_or("for without ..")?;
            let (inner, next) = parse_block(lines, i + 1, depth + 2)?;
            i = next;
            if lines.get(i).map(|l| l.trim()) != Some("end") { return Err(format!("for without end at line {i}")); }
            i += 1;
            body.push(Stmt::For { var: var.trim().to_string(), start: parse_expr(start)?, stop: parse_expr(stop)?, body: inner });
        } else if t.starts_with("lua.scratch_u8_set") || t.starts_with("lua_set_index ") {
            let (lhs, rhs) = t.split_once(" = ").ok_or_else(|| format!("store without value: {t}"))?;
            let (op, target) = lhs.split_once(' ').ok_or("store without target")?;
            let open = target.find('[').ok_or("store without index")?;
            let name = target[..open].rsplit(' ').next().unwrap().to_string();
            let index = parse_expr(&target[open + 1..target.len() - 1])?;
            body.push(Stmt::Store { op: op.to_string(), target: name, index, value: parse_expr(rhs)? });
            i += 1;
        } else if let Some(rest) = t.strip_prefix("return") {
            let rest = rest.trim();
            let values = if rest.is_empty() || rest == "nil" { Vec::new() } else { split_top(rest).into_iter().map(|s| parse_expr(s.trim())).collect::<Result<_, _>>()? };
            body.push(Stmt::Return(values));
            i += 1;
        } else {
            body.push(Stmt::Expr(parse_expr(t)?));
            i += 1;
        }
    }
    Ok((body, i))
}

/// The else part of an if: `else` with a block, `elseif` with a condition and
/// a block nested as an if inside the else, or nothing.
fn parse_else(lines: &[&str], i: usize, depth: usize) -> Result<(Vec<Stmt>, usize), String> {
    let t = lines.get(i).map(|l| l.trim()).unwrap_or("");
    if t == "else" { return parse_block(lines, i + 1, depth + 2); }
    if let Some(rest) = t.strip_prefix("elseif ") {
        let cond = parse_expr(rest)?;
        let (inner, next) = parse_block(lines, i + 1, depth + 2)?;
        let (else_body, next) = parse_else(lines, next, depth)?;
        return Ok((vec![Stmt::If { cond, body: inner, else_body }], next));
    }
    Ok((Vec::new(), i))
}

/// Splits on top-level commas.
fn split_top(s: &str) -> Vec<&str> {
    let mut parts = Vec::new();
    let mut depth = 0;
    let mut start = 0;
    for (idx, c) in s.char_indices() {
        match c { '(' => depth += 1, ')' => depth -= 1, ',' if depth == 0 => { parts.push(&s[start..idx]); start = idx + 1; } _ => {} }
    }
    if !s[start..].trim().is_empty() { parts.push(&s[start..]); }
    parts
}

pub fn parse_expr(s: &str) -> Result<Expr, String> {
    let s = s.trim();
    if let Some(rest) = s.strip_prefix("lua.string \"") { return Ok(Expr::Str(rest.trim_end_matches('"').replace("\\n", "\n"))); }
    if let Some(rest) = s.strip_prefix("bool ") { return Ok(Expr::Constant { ty: "bool".into(), value: rest.trim().into() }); }
    let s = s.strip_suffix("{}").unwrap_or(s);
    if let Some(rest) = s.strip_prefix("local:") { let (ty, name) = rest.split_once(' ').ok_or("local")?; return Ok(Expr::Local { ty: ty.into(), name: name.trim().into() }); }
    if let Some(rest) = s.strip_prefix("uniform:") { let (ty, name) = rest.split_once(' ').ok_or("uniform")?; return Ok(Expr::Uniform { ty: ty.into(), name: name.trim().into() }); }
    if let Some(rest) = s.strip_prefix("constant:") { let (ty, value) = rest.split_once(' ').ok_or("constant")?; return Ok(Expr::Constant { ty: ty.into(), value: value.trim().into() }); }
    if let Some(rest) = s.strip_prefix("span:") { return Ok(Expr::Span(rest.trim().into())); }
    if let Some(rest) = s.strip_prefix("count ") { return Ok(Expr::Count(rest.trim().into())); }
    // A bare symbol, such as the `eager` mode of a builder.
    if !s.contains('(') && s.chars().all(|c| c.is_alphanumeric() || c == '_') { return Ok(Expr::Local { ty: "sym".into(), name: s.into() }); }
    let open = s.find('(').ok_or_else(|| format!("unrecognised expression: {s}"))?;
    if !s.ends_with(')') { return Err(format!("call without close: {s}")); }
    let head = &s[..open];
    let (op, ty) = match head.split_once(':') { Some((o, t)) => (o.to_string(), Some(t.to_string())), None => (head.to_string(), None) };
    let inner = &s[open + 1..s.len() - 1];
    let args = split_top(inner).into_iter().map(|a| parse_expr(a)).collect::<Result<Vec<_>, _>>()?;
    Ok(Expr::Call { op, ty, args })
}
