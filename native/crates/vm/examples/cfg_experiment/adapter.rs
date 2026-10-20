use super::graph::{Graph, NONE};
use nupp_vm::{
    builtins,
    interp::{Function, Interp, Op, Outcome},
    value::Value,
};

// Deliberately simple slot assignment: reuse a register window per block.
// Identity moves disappear; parallel-copy cycles use one scratch register.
// No flow, predecessor, dominance or liveness reconstruction is needed.
//
// With `hinted`, a block parameter lives in the register its lexical slot
// names, and a node result that feeds such a parameter is placed in that
// register when nothing still live occupies it. The edge copy that would
// have moved it then becomes an identity and disappears. Without hints the
// window is positional, so every edge is a parallel copy.
pub fn lower(g: &Graph, hinted: bool) -> Result<Function, String> {
    if g.constants.len() > u16::MAX as usize - 1 {
        return Err("prototype VM adapter exceeds constant pool".into());
    }
    let mut regs = vec![0u8; g.types.len()];
    let window = if hinted {
        g.slot_count as usize
    } else {
        g.blocks
            .iter()
            .map(|b| b.params.len as usize)
            .max()
            .unwrap()
    };
    let mut temps = 0;
    for b in &g.blocks {
        let nodes = b.nodes.get(&g.nodes);
        if !hinted {
            for (i, &p) in g.params(b).iter().enumerate() {
                regs[p as usize] = (i + 1) as u8;
            }
            for (i, n) in nodes.iter().enumerate() {
                regs[n[1] as usize] = (b.params.len as usize + i + 1) as u8;
            }
            temps = temps.max(nodes.len());
            continue;
        }
        // Positions: node index for operand reads, nodes.len() for the
        // terminator value and every edge argument.
        let end = nodes.len();
        let mut last_use = vec![NONE as usize; g.types.len()];
        let use_at = |v: u32, at: usize, last_use: &mut [usize]| {
            let slot = &mut last_use[v as usize];
            *slot = if *slot == NONE as usize { at } else { (*slot).max(at) };
        };
        for (k, &[op, _, a, c]) in nodes.iter().enumerate() {
            if op != 0 {
                use_at(a, k, &mut last_use);
            }
            if matches!(op, 1..=6 | 8) {
                use_at(c, k, &mut last_use);
            }
        }
        if b.term != 1 {
            use_at(b.value, end, &mut last_use);
        }
        let mut preferred: Vec<Vec<u8>> = vec![Vec::new(); g.types.len()];
        for e in g.successors(b) {
            let target = &g.blocks[e.target as usize];
            for (&arg, &hint) in g.args(e).iter().zip(g.hints(target)) {
                use_at(arg, end, &mut last_use);
                preferred[arg as usize].push(hint as u8 + 1);
            }
        }
        let mut holder = vec![NONE; window + 1];
        for (&p, &hint) in g.params(b).iter().zip(g.hints(b)) {
            regs[p as usize] = hint as u8 + 1;
            holder[hint as usize + 1] = p;
        }
        let mut next_temp = 0;
        for (k, n) in nodes.iter().enumerate() {
            let d = n[1];
            let free = preferred[d as usize].iter().copied().find(|&r| {
                let o = holder[r as usize];
                o == NONE || last_use[o as usize] <= k
            });
            regs[d as usize] = match free {
                Some(r) => {
                    holder[r as usize] = d;
                    r
                }
                None => {
                    next_temp += 1;
                    (window + next_temp) as u8
                }
            };
        }
        temps = temps.max(next_temp);
    }
    if hinted {
        for (i, &p) in g.params(&g.blocks[0]).iter().enumerate() {
            if regs[p as usize] != (i + 1) as u8 {
                return Err("entry parameter hints must be positional".into());
            }
        }
    }
    let max = window + temps;
    let count = max + 7;
    if count > 250 {
        return Err("prototype VM adapter exceeds register window".into());
    }
    let scratch = (max + 1) as u8;
    let base = (max + 2) as u8;
    let mut f = Function {
        name: g.name.clone(),
        module: "cfg.adapter".into(),
        path: None,
        sig: vec![],
        ret: b'v',
        nv_params: g.blocks[0].params.len as u8,
        nf_params: 0,
        code: vec![],
        consts: g.constants.iter().map(|&n| Value::num(n)).collect(),
        nparams: g.blocks[0].params.len as u8,
        nregs: count as u8,
        nireg: 0,
        nfreg: 0,
        nvreg: 0,
        jump_tables: vec![],
        debug: vec![],
        vararg: false,
        gpu: None, ins: vec![],
    };
    let zero = f.consts.len() as u16;
    f.consts.push(Value::num(0.));
    let byte = f.consts.len() as u16;
    f.consts
        .push(Value::builtin(builtins::id_of("string.byte").unwrap()));
    let mut starts = vec![0; g.blocks.len()];
    let mut patches = Vec::new();
    let copies = |f: &mut Function, e: &super::graph::Edge| {
        let target = &g.blocks[e.target as usize];
        let mut pending: Vec<_> = g
            .args(e)
            .iter()
            .zip(g.params(target))
            .map(|(&arg, &param)| (regs[param as usize], regs[arg as usize]))
            .filter(|(dst, src)| dst != src)
            .collect();
        while !pending.is_empty() {
            if let Some(i) = pending
                .iter()
                .position(|(dst, _)| !pending.iter().any(|(_, src)| src == dst))
            {
                let (dst, src) = pending.remove(i);
                f.code.push(Op::Move(dst, src));
            } else {
                let saved = pending[0].0;
                f.code.push(Op::Move(scratch, saved));
                for (_, src) in &mut pending {
                    if *src == saved {
                        *src = scratch;
                    }
                }
            }
        }
    };
    for (bid, b) in g.blocks.iter().enumerate() {
        starts[bid] = f.code.len();
        for &[op, d, a, c] in b.nodes.get(&g.nodes) {
            let dst = regs[d as usize];
            let x = if op == 0 { 0 } else { regs[a as usize] };
            let y = if matches!(op, 1..=6 | 8) {
                regs[c as usize]
            } else {
                0
            };
            match op {
                0 => f.code.push(Op::K(dst, a as u16)),
                1 => f.code.push(Op::Add(dst, x, y)),
                2 => f.code.push(Op::Sub(dst, x, y)),
                3 => f.code.push(Op::Mul(dst, x, y)),
                4 => f.code.push(Op::Lt(dst, x, y)),
                5 => f.code.push(Op::Le(dst, x, y)),
                6 => f.code.push(Op::Eq(dst, x, y)),
                7 => f.code.push(Op::Len(dst, x)),
                8 => f.code.extend([
                    Op::K(base + 3, byte),
                    Op::Move(base + 1, x),
                    Op::Move(base + 2, y),
                    Op::CallDyn(base + 3, base, 2),
                    Op::Move(dst, base),
                    Op::JmpIf(dst, 1),
                    Op::K(dst, zero),
                ]),
                _ => unreachable!(),
            }
        }
        let edges = g.successors(b);
        match b.term {
            0 => f.code.push(Op::Ret(regs[b.value as usize])),
            1 | 3 => {
                if b.term == 3 {
                    f.code.push(Op::Move(base, regs[b.value as usize]));
                }
                copies(&mut f, &edges[0]);
                if b.term == 3 {
                    f.code.push(Op::Park(base));
                }
                patches.push((f.code.len(), edges[0].target));
                f.code.push(Op::Jmp(0));
            }
            2 => {
                let branch = f.code.len();
                f.code.push(Op::JmpIf(regs[b.value as usize], 0));
                copies(&mut f, &edges[1]);
                patches.push((f.code.len(), edges[1].target));
                f.code.push(Op::Jmp(0));
                f.code[branch] =
                    Op::JmpIf(regs[b.value as usize], (f.code.len() - branch - 1) as i32);
                copies(&mut f, &edges[0]);
                patches.push((f.code.len(), edges[0].target));
                f.code.push(Op::Jmp(0));
            }
            _ => unreachable!(),
        }
    }
    for (pc, target) in patches {
        f.code[pc] = Op::Jmp(starts[target as usize] as i32 - pc as i32 - 1);
    }
    nupp_vm::verify::verify_classes(&f, 1)?;
    Ok(f)
}
pub fn inputs(vm: &mut Interp, args: &[super::native::Input]) -> Vec<Value> {
    args.iter()
        .map(|a| match a {
            super::native::Input::Number(n) => Value::num(*n),
            super::native::Input::Text(s) => {
                let v = vm.new_string_bytes(s);
                vm.handles.push(v);
                v
            }
        })
        .collect()
}
pub fn run(g: &Graph, args: &[super::native::Input], threaded: bool, hinted: bool) -> Vec<f64> {
    let mut vm = Interp::new();
    vm.funcs.push(lower(g, hinted).unwrap());
    if threaded {
        vm.prepare_threaded();
    }
    let args = inputs(&mut vm, args);
    let tid = vm.spawn(0, &args);
    let mut trace = Vec::new();
    for _ in 0..10000 {
        let result = if threaded {
            vm.run(tid)
        } else {
            vm.run_rust(tid)
        };
        match result {
            Outcome::Done(v) => {
                trace.push(v.as_num());
                return trace;
            }
            Outcome::Parked(bits) => {
                trace.push(Value(bits).as_num());
                vm.resume(tid);
            }
        }
    }
    panic!("suspension limit exceeded")
}
