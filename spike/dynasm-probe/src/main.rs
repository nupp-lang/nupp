//! Can dynasm-rs encode the NEON forms the direct backend selects, with
//! registers chosen at run time by the allocator?
use dynasmrt::{dynasm, DynasmApi, aarch64::Assembler};

fn main() {
    let mut ops = Assembler::new().unwrap();
    let (d, n, m, x): (u32, u32, u32, u32) = (1, 2, 3, 4);
    dynasm!(ops
        ; .arch aarch64
        ; fadd V(d).D2, V(n).D2, V(m).D2
        ; fmul V(d).D2, V(n).D2, V(m).D2
        ; fcmgt V(d).D2, V(n).D2, V(m).D2
        ; cmhi V(d).D2, V(n).D2, V(m).D2
        ; bsl V(d).B16, V(n).B16, V(m).B16
        ; dup V(d).D2, V(n).D[0]
        ; dup V(d).D2, X(x)
        ; addp D(d), V(n).D2
        ; faddp D(d), V(n).D2
        ; umov X(x), V(n).D[1]
        ; ins V(d).D[1], V(n).D[0]
        ; ldp Q(d), Q(n), [X(x), 32]
        ; stp Q(d), Q(n), [X(x), -32]
        ; fccmp D(n), D(m), 4, gt
        ; ccmp X(x), X(x), 2, ls
    );
    let buf = ops.finalize().unwrap();
    for w in buf.chunks(4) {
        println!("{:08x}", u32::from_le_bytes([w[0], w[1], w[2], w[3]]));
    }
}
