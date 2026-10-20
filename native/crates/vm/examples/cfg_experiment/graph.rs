use std::collections::VecDeque;

pub const F64: u32 = 1;
pub const BOOL: u32 = 2;
pub const TEXT: u32 = 3;
pub const NONE: u32 = u32::MAX;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Span {
    pub start: u32,
    pub len: u32,
}
impl Span {
    pub fn get<T>(self, pool: &[T]) -> &[T] {
        &pool[self.start as usize..(self.start + self.len) as usize]
    }
}
fn append<T>(pool: &mut Vec<T>, items: impl IntoIterator<Item = T>) -> Span {
    let start = pool.len() as u32;
    pool.extend(items);
    Span {
        start,
        len: pool.len() as u32 - start,
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Edge {
    pub target: u32,
    pub args: Span,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Block {
    pub params: Span,
    /// One preferred lexical slot per parameter, indexing `Graph::hints`.
    pub hints: Span,
    pub nodes: Span,
    pub term: u32,
    pub value: u32,
    pub edges: Span,
}
#[derive(Clone, Debug, PartialEq)]
pub struct Graph {
    pub name: String,
    pub types: Vec<u32>,
    pub constants: Vec<f64>,
    /// Lexical slots named by parameter hints: every hint is below this.
    pub slot_count: u32,
    pub blocks: Vec<Block>,
    pub nodes: Vec<[u32; 4]>,
    pub edges: Vec<Edge>,
    pub values: Vec<u32>,
    pub hints: Vec<u32>,
}
impl Graph {
    pub fn params(&self, b: &Block) -> &[u32] {
        b.params.get(&self.values)
    }
    pub fn hints(&self, b: &Block) -> &[u32] {
        b.hints.get(&self.hints)
    }
    pub fn args(&self, e: &Edge) -> &[u32] {
        e.args.get(&self.values)
    }
    pub fn successors(&self, b: &Block) -> &[Edge] {
        b.edges.get(&self.edges)
    }
    pub fn size(&self) -> usize {
        self.types.len() * 4
            + self.constants.len() * 8
            + self.blocks.len() * std::mem::size_of::<Block>()
            + self.nodes.len() * 16
            + self.edges.len() * 12
            + self.values.len() * 4
            + self.hints.len() * 4
            + 4
            + self.name.len()
    }
    // This closed, block-argument form needs no dominator reconstruction:
    // every use must be a parameter or an earlier definition in its block.
    pub fn verify(&self) -> Result<(), String> {
        let fail = || format!("{}: invalid graph", self.name);
        if self.blocks.is_empty() || self.types.iter().any(|t| !matches!(*t, F64 | BOOL | TEXT)) {
            return Err(fail());
        }
        // A slot names at least one value, so the count is bounded by the
        // values and the per-block distinctness check allocates no more.
        if self.slot_count as usize > self.types.len() {
            return Err(format!("{}: slot count exceeds values", self.name));
        }
        let mut owner = vec![NONE; self.types.len()];
        let mut defined = vec![false; self.types.len()];
        let mut seen = vec![false; self.blocks.len()];
        let mut queue = VecDeque::from([0]);
        while let Some(bid) = queue.pop_front() {
            if seen[bid] {
                continue;
            }
            seen[bid] = true;
            for e in self.successors(&self.blocks[bid]) {
                if e.target == 0 || e.target as usize >= seen.len() {
                    return Err(fail());
                }
                queue.push_back(e.target as usize);
            }
        }
        if seen.iter().any(|v| !v) {
            return Err(format!("{}: unreachable block", self.name));
        }
        for (bid, b) in self.blocks.iter().enumerate() {
            let bid = bid as u32;
            let define = |v: u32, owner: &mut [u32], defined: &mut [bool]| -> Result<(), String> {
                let d = defined.get_mut(v as usize).ok_or_else(fail)?;
                if *d {
                    return Err(fail());
                }
                *d = true;
                owner[v as usize] = bid;
                Ok(())
            };
            let use_value = |v: u32, ty: Option<u32>, owner: &[u32]| -> Result<(), String> {
                if owner.get(v as usize) != Some(&bid)
                    || ty.is_some_and(|t| self.types[v as usize] != t)
                {
                    return Err(fail());
                }
                Ok(())
            };
            if b.hints.len != b.params.len {
                return Err(fail());
            }
            let mut taken = vec![false; self.slot_count as usize];
            for &hint in self.hints(b) {
                let slot = taken
                    .get_mut(hint as usize)
                    .ok_or_else(|| format!("{}: hint outside slots", self.name))?;
                if std::mem::replace(slot, true) {
                    return Err(format!("{}: duplicate hint in block", self.name));
                }
            }
            for &v in self.params(b) {
                define(v, &mut owner, &mut defined)?;
            }
            for &[op, d, a, c] in b.nodes.get(&self.nodes) {
                let ty = match op {
                    0 => {
                        if a as usize >= self.constants.len() || c != 0 {
                            return Err(fail());
                        }
                        F64
                    }
                    1..=6 => {
                        use_value(a, Some(F64), &owner)?;
                        use_value(c, Some(F64), &owner)?;
                        if op >= 4 { BOOL } else { F64 }
                    }
                    7 => {
                        use_value(a, Some(TEXT), &owner)?;
                        if c != 0 {
                            return Err(fail());
                        }
                        F64
                    }
                    8 => {
                        use_value(a, Some(TEXT), &owner)?;
                        use_value(c, Some(F64), &owner)?;
                        F64
                    }
                    _ => return Err(fail()),
                };
                if self.types.get(d as usize) != Some(&ty) {
                    return Err(fail());
                }
                define(d, &mut owner, &mut defined)?;
            }
            let edges = match b.term {
                0 => {
                    use_value(b.value, Some(F64), &owner)?;
                    0
                }
                1 => {
                    if b.value != 0 {
                        return Err(fail());
                    }
                    1
                }
                2 => {
                    use_value(b.value, Some(BOOL), &owner)?;
                    2
                }
                3 => {
                    use_value(b.value, Some(F64), &owner)?;
                    1
                }
                _ => return Err(fail()),
            };
            if b.edges.len != edges {
                return Err(fail());
            }
            for e in self.successors(b) {
                let target = &self.blocks[e.target as usize];
                if e.args.len != target.params.len {
                    return Err(fail());
                }
                for (&arg, &param) in self.args(e).iter().zip(self.params(target)) {
                    let ty = *self.types.get(param as usize).ok_or_else(fail)?;
                    use_value(arg, Some(ty), &owner)?;
                }
            }
        }
        if defined.iter().any(|v| !v) {
            return Err(fail());
        }
        Ok(())
    }
    // One mark worklist over value dependencies. A live block parameter
    // makes the corresponding incoming arguments live. This also computes
    // the exact scalar state carried by yield/resume edges in this subset.
    pub fn prune(&self) -> Self {
        let mut dependencies = vec![Vec::new(); self.types.len()];
        let mut roots = self.params(&self.blocks[0]).to_vec();
        for b in &self.blocks {
            if b.term != 1 {
                roots.push(b.value);
            }
            for &[op, d, a, c] in b.nodes.get(&self.nodes) {
                if op != 0 {
                    dependencies[d as usize].push(a);
                }
                if matches!(op, 1..=6 | 8) {
                    dependencies[d as usize].push(c);
                }
            }
            for e in self.successors(b) {
                for (&p, &a) in self
                    .params(&self.blocks[e.target as usize])
                    .iter()
                    .zip(self.args(e))
                {
                    dependencies[p as usize].push(a);
                }
            }
        }
        let mut live = vec![false; self.types.len()];
        while let Some(v) = roots.pop() {
            if std::mem::replace(&mut live[v as usize], true) {
                continue;
            }
            roots.extend_from_slice(&dependencies[v as usize]);
        }
        let mut remap = vec![NONE; live.len()];
        let mut slots = vec![NONE; self.slot_count as usize];
        let mut g = Self {
            name: self.name.clone(),
            types: vec![],
            constants: self.constants.clone(),
            slot_count: 0,
            blocks: vec![],
            nodes: vec![],
            edges: vec![],
            values: vec![],
            hints: vec![],
        };
        for (v, &used) in live.iter().enumerate() {
            if used {
                remap[v] = g.types.len() as u32;
                g.types.push(self.types[v]);
            }
        }
        for b in &self.blocks {
            let params = append(
                &mut g.values,
                self.params(b)
                    .iter()
                    .filter(|&&v| live[v as usize])
                    .map(|&v| remap[v as usize]),
            );
            // Slots are renumbered by first surviving appearance, entry
            // parameters first, so the count stays dense and positional.
            let hints = append(
                &mut g.hints,
                self.params(b)
                    .iter()
                    .zip(self.hints(b))
                    .filter(|(v, _)| live[**v as usize])
                    .map(|(_, &hint)| {
                        let slot = &mut slots[hint as usize];
                        if *slot == NONE {
                            *slot = g.slot_count;
                            g.slot_count += 1;
                        }
                        *slot
                    }),
            );
            let nodes = append(
                &mut g.nodes,
                b.nodes
                    .get(&self.nodes)
                    .iter()
                    .filter(|n| live[n[1] as usize])
                    .map(|&[op, d, a, c]| {
                        [
                            op,
                            remap[d as usize],
                            if op == 0 { a } else { remap[a as usize] },
                            if matches!(op, 1..=6 | 8) {
                                remap[c as usize]
                            } else {
                                c
                            },
                        ]
                    }),
            );
            let start = g.edges.len() as u32;
            for e in self.successors(b) {
                let args = append(
                    &mut g.values,
                    self.args(e)
                        .iter()
                        .zip(self.params(&self.blocks[e.target as usize]))
                        .filter(|(_, p)| live[**p as usize])
                        .map(|(&a, _)| remap[a as usize]),
                );
                g.edges.push(Edge {
                    target: e.target,
                    args,
                });
            }
            g.blocks.push(Block {
                params,
                hints,
                nodes,
                term: b.term,
                value: if b.term == 1 {
                    0
                } else {
                    remap[b.value as usize]
                },
                edges: Span {
                    start,
                    len: b.edges.len,
                },
            });
        }
        g
    }
}

struct Reader<'a> {
    data: &'a [u8],
}
impl<'a> Reader<'a> {
    fn take(&mut self, n: usize) -> Result<&'a [u8], String> {
        if n > self.data.len() {
            return Err("truncated graph".into());
        }
        let (head, rest) = self.data.split_at(n);
        self.data = rest;
        Ok(head)
    }
    fn word(&mut self) -> Result<u32, String> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn count(&mut self) -> Result<usize, String> {
        let n = self.word()? as usize;
        if n > self.data.len() / 4 {
            return Err("invalid graph count".into());
        }
        Ok(n)
    }
    fn string(&mut self) -> Result<String, String> {
        let n = self.word()? as usize;
        String::from_utf8(self.take(n)?.to_vec()).map_err(|e| e.to_string())
    }
}
pub fn decode(bytes: &[u8]) -> Result<Vec<Graph>, String> {
    if bytes.len() > 64 * 1024 * 1024 {
        return Err("graph image exceeds experiment limit".into());
    }
    let mut r = Reader { data: bytes };
    if r.take(8)? != b"NCFG0002" {
        return Err("unsupported graph version".into());
    }
    let count = r.count()?;
    let mut graphs = Vec::new();
    for _ in 0..count {
        let mut g = Graph {
            name: r.string()?,
            types: vec![],
            constants: vec![],
            slot_count: 0,
            blocks: vec![],
            nodes: vec![],
            edges: vec![],
            values: vec![],
            hints: vec![],
        };
        for _ in 0..r.count()? {
            g.types.push(r.word()?);
        }
        for _ in 0..r.count()? {
            let k: f64 = r.string()?.parse().map_err(|_| "bad number")?;
            if !k.is_finite() {
                return Err("nonfinite constant".into());
            }
            g.constants.push(k);
        }
        g.slot_count = r.word()?;
        for _ in 0..r.count()? {
            let start = g.values.len() as u32;
            let hint_start = g.hints.len() as u32;
            let len = r.count()? as u32;
            for _ in 0..len {
                g.values.push(r.word()?);
                g.hints.push(r.word()?);
            }
            let params = Span { start, len };
            let hints = Span {
                start: hint_start,
                len,
            };
            let start = g.nodes.len() as u32;
            let len = r.count()? as u32;
            for _ in 0..len {
                g.nodes.push([r.word()?, r.word()?, r.word()?, r.word()?]);
            }
            let nodes = Span { start, len };
            let term = r.word()?;
            let value = r.word()?;
            let len = match term {
                0 => 0,
                1 | 3 => 1,
                2 => 2,
                _ => return Err("unknown terminator".into()),
            };
            let edges = Span {
                start: g.edges.len() as u32,
                len,
            };
            for _ in 0..len {
                let target = r.word()?;
                let len = r.count()? as u32;
                let start = g.values.len() as u32;
                for _ in 0..len {
                    g.values.push(r.word()?);
                }
                g.edges.push(Edge {
                    target,
                    args: Span { start, len },
                });
            }
            g.blocks.push(Block {
                params,
                hints,
                nodes,
                term,
                value,
                edges,
            });
        }
        g.verify()?;
        graphs.push(g);
    }
    if !r.data.is_empty() {
        return Err("trailing graph bytes".into());
    }
    Ok(graphs)
}
pub fn encode(graphs: &[Graph]) -> Vec<u8> {
    fn word(out: &mut Vec<u8>, v: u32) {
        out.extend(v.to_le_bytes());
    }
    fn string(out: &mut Vec<u8>, v: &str) {
        word(out, v.len() as u32);
        out.extend(v.as_bytes());
    }
    let mut out = b"NCFG0002".to_vec();
    word(&mut out, graphs.len() as u32);
    for g in graphs {
        string(&mut out, &g.name);
        word(&mut out, g.types.len() as u32);
        for &ty in &g.types {
            word(&mut out, ty);
        }
        word(&mut out, g.constants.len() as u32);
        for k in &g.constants {
            string(&mut out, &k.to_string());
        }
        word(&mut out, g.slot_count);
        word(&mut out, g.blocks.len() as u32);
        for b in &g.blocks {
            word(&mut out, b.params.len);
            for (&v, &hint) in g.params(b).iter().zip(g.hints(b)) {
                word(&mut out, v);
                word(&mut out, hint);
            }
            word(&mut out, b.nodes.len);
            for n in b.nodes.get(&g.nodes) {
                for &v in n {
                    word(&mut out, v);
                }
            }
            word(&mut out, b.term);
            word(&mut out, b.value);
            for e in g.successors(b) {
                word(&mut out, e.target);
                word(&mut out, e.args.len);
                for &a in g.args(e) {
                    word(&mut out, a);
                }
            }
        }
    }
    out
}
