//! Harness: builds the kernels with Cranelift, checks them against reference
//! implementations and the LLVM and hand-written artifacts, and times them
//! paired in one process. Output is TSV: size name round calls elapsed_ns.

mod jit;
mod kernels;

use jit::{Jit, Ty};
use std::hint::black_box;

type MapFn = unsafe extern "C" fn(*mut f64, u64, *const f64, u64, f64, f64) -> u32;
type DotFn = unsafe extern "C" fn(*const f64, u64, *const f64, u64) -> f64;
type CompressFn = unsafe extern "C" fn(*mut u32, *const u8, u64, *const u32);
type ChunkFn = unsafe extern "C" fn(*const f64, *const f64, u64, u64, *mut f64) -> u64;
type LlvmMapFn = unsafe extern "C" fn(*mut f64, *const f64, f64, f64, u64, u64);
type LlvmDotFn = unsafe extern "C" fn(*const f64, *const f64, u64, u64) -> f64;
type HandMapFn = unsafe extern "C" fn(*mut f64, *const f64, f64, f64, usize);
type HandDotFn = unsafe extern "C" fn(*const f64, *const f64, usize) -> f64;
type CShaFn = unsafe extern "C" fn(*const u8, usize, *mut u8) -> bool;

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];
const H0: [u32; 8] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];

fn cpu_now() -> f64 {
    let mut ts = libc::timespec { tv_sec: 0, tv_nsec: 0 };
    unsafe { libc::clock_gettime(libc::CLOCK_THREAD_CPUTIME_ID, &mut ts) };
    ts.tv_sec as f64 + ts.tv_nsec as f64 * 1e-9
}

/// SHA-256 over `bytes` with any compress function; the padding is done here
/// so the compiled kernel sees only whole blocks, as the C control's does.
fn sha256_with(compress: CompressFn, bytes: &[u8]) -> [u8; 32] {
    let mut state = H0;
    let full = bytes.len() / 64;
    unsafe { compress(state.as_mut_ptr(), bytes.as_ptr(), full as u64, K.as_ptr()) };
    let rest = &bytes[full * 64..];
    let mut tail = [0u8; 128];
    tail[..rest.len()].copy_from_slice(rest);
    tail[rest.len()] = 0x80;
    let blocks = if rest.len() + 9 <= 64 { 1 } else { 2 };
    let bits = (bytes.len() as u64) * 8;
    tail[blocks * 64 - 8..blocks * 64].copy_from_slice(&bits.to_be_bytes());
    unsafe { compress(state.as_mut_ptr(), tail.as_ptr(), blocks as u64, K.as_ptr()) };
    let mut out = [0u8; 32];
    for (i, w) in state.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&w.to_be_bytes());
    }
    out
}

fn hex(d: &[u8]) -> String {
    d.iter().map(|b| format!("{b:02x}")).collect()
}

fn close(a: f64, b: f64, what: &str) {
    let tol = 1e-9 * f64::max(1.0, f64::max(a.abs(), b.abs()));
    assert!((a - b).abs() <= tol, "{what}: {a} vs {b}");
}

fn fill(n: usize) -> (Vec<f64>, Vec<f64>) {
    let a: Vec<f64> = (0..n).map(|i| ((i % 61) as f64 - 30.0) / 16.0).collect();
    let b: Vec<f64> = (0..n).map(|i| ((i % 37) as f64 - 18.0) / 32.0).collect();
    (a, b)
}

struct Runner {
    size: usize,
    name: String,
    run: Box<dyn FnMut() -> f64>,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let seconds: f64 = std::env::var("SAMPLE_SECONDS").ok().and_then(|s| s.parse().ok()).unwrap_or(0.02);
    let rounds: usize = std::env::var("ROUNDS").ok().and_then(|s| s.parse().ok()).unwrap_or(9);
    let opt = std::env::var("OPT_LEVEL").unwrap_or_else(|_| "speed".to_string());
    let check_only = args.iter().any(|a| a == "--check");
    let llvm_path = std::env::var("LLVM_KERNELS").unwrap_or_else(|_| "/private/tmp/nupp-luajit-simd-replacement/bench/luajit-simd-replacement/integrated/build/lib/libkernels_aot.dylib".into());
    let hand_path = std::env::var("HAND_KERNELS").unwrap_or_else(|_| "libhand.dylib".into());
    let sha_path = std::env::var("SHA_CONTROL").unwrap_or_else(|_| "/private/tmp/nupp-luajit-simd-replacement/bench/sha256/build/aot/lib/libsha256_control.dylib".into());

    let llvm = unsafe { libloading::Library::new(&llvm_path) }.expect("LLVM kernels dylib");
    let hand = unsafe { libloading::Library::new(&hand_path) }.expect("hand-written dylib");
    let shac = unsafe { libloading::Library::new(&sha_path) }.expect("sha256 control dylib");
    let llvm_map: LlvmMapFn = unsafe { *llvm.get(b"ks_166cb74ff622b797_explicit_map__neon\0").unwrap() };
    let llvm_dot: LlvmDotFn = unsafe { *llvm.get(b"ks_166cb74ff622b797_explicit_algebraic__neon\0").unwrap() };
    let hand_map: HandMapFn = unsafe { *hand.get(b"hand_map\0").unwrap() };
    let hand_dot: HandDotFn = unsafe { *hand.get(b"hand_algebraic\0").unwrap() };
    let c_sha: CShaFn = unsafe { *shac.get(b"nuppSha256\0").unwrap() };

    // Build every kernel. Compile times go to stderr.
    let mut j = Jit::new(&[("hand_algebraic", hand_dot as *const u8)], &opt);
    let hand_import = j.import("hand_algebraic", &[Ty::Ptr, Ty::Ptr, Ty::U64], Some(Ty::F64));
    let map_id = kernels::map(&mut j, "map", 1);
    let map2_id = kernels::map(&mut j, "map_u2", 2);
    let dot_id = kernels::dot(&mut j, "dot", 1);
    let dot2_id = kernels::dot(&mut j, "dot_u2", 2);
    let sha_id = kernels::sha256_compress(&mut j, "sha256_compress");
    let chunk_direct_id = kernels::chunked(&mut j, "chunk_direct", dot_id, false);
    let chunk_extern_id = kernels::chunked(&mut j, "chunk_extern", hand_import, true);
    j.finish();
    for (name, us) in &j.compile_micros {
        eprintln!("compile\t{name}\t{us}");
    }
    for (name, id) in [("map", map_id), ("map_u2", map2_id), ("dot", dot_id), ("dot_u2", dot2_id), ("sha", sha_id), ("chunk_direct", chunk_direct_id), ("chunk_extern", chunk_extern_id)] {
        eprintln!("addr\t{name}\t{:p}", j.ptr(id));
    }
    let map: MapFn = unsafe { std::mem::transmute(j.ptr(map_id)) };
    let map2: MapFn = unsafe { std::mem::transmute(j.ptr(map2_id)) };
    let dot: DotFn = unsafe { std::mem::transmute(j.ptr(dot_id)) };
    let dot2: DotFn = unsafe { std::mem::transmute(j.ptr(dot2_id)) };
    let compress: CompressFn = unsafe { std::mem::transmute(j.ptr(sha_id)) };
    let chunk_direct: ChunkFn = unsafe { std::mem::transmute(j.ptr(chunk_direct_id)) };
    let chunk_extern: ChunkFn = unsafe { std::mem::transmute(j.ptr(chunk_extern_id)) };

    // Correctness against references, LLVM and the hand-written kernels.
    let mut cases = 0usize;
    for &n in &[0usize, 1, 2, 3, 4, 5, 7, 8, 15, 16, 17, 63, 64, 65, 1024, 1027, 65539] {
        let (a, b) = fill(n);
        let mut out = vec![0.0; n.max(1)];
        let mut out_llvm = vec![0.0; n.max(1)];
        let mut out_hand = vec![0.0; n.max(1)];
        for (name, f) in [("map", map), ("map_u2", map2)] {
            assert_eq!(unsafe { f(out.as_mut_ptr(), n as u64, a.as_ptr(), n as u64, 1.25, -0.5) }, 0);
            unsafe { llvm_map(out_llvm.as_mut_ptr(), a.as_ptr(), 1.25, -0.5, n as u64, n as u64) };
            unsafe { hand_map(out_hand.as_mut_ptr(), a.as_ptr(), 1.25, -0.5, n) };
            for i in 0..n {
                close(out[i], a[i] * 1.25 - 0.5, name);
                close(out[i], out_llvm[i], name);
                close(out[i], out_hand[i], name);
                cases += 1;
            }
            if n > 0 {
                assert_eq!(unsafe { f(out.as_mut_ptr(), n as u64, a.as_ptr(), (n - 1) as u64, 1.0, 0.0) }, 1, "length mismatch is reported");
            }
        }
        let reference: f64 = a.iter().zip(&b).map(|(x, y)| x * y).sum();
        let got = unsafe { dot(a.as_ptr(), n as u64, b.as_ptr(), n as u64) };
        close(got, reference, "dot");
        close(unsafe { dot2(a.as_ptr(), n as u64, b.as_ptr(), n as u64) }, reference, "dot_u2");
        close(got, unsafe { llvm_dot(a.as_ptr(), b.as_ptr(), n as u64, n as u64) }, "dot vs llvm");
        close(got, unsafe { hand_dot(a.as_ptr(), b.as_ptr(), n) }, "dot vs hand");
        cases += 1;
        for width in [1usize, 3, 4, 7, 16, 64] {
            let chunks = n.div_ceil(width);
            let mut o1 = vec![0.0; chunks.max(1)];
            let mut o2 = vec![0.0; chunks.max(1)];
            let c1 = unsafe { chunk_direct(a.as_ptr(), b.as_ptr(), n as u64, width as u64, o1.as_mut_ptr()) };
            let c2 = unsafe { chunk_extern(a.as_ptr(), b.as_ptr(), n as u64, width as u64, o2.as_mut_ptr()) };
            assert_eq!(c1 as usize, chunks);
            assert_eq!(c2 as usize, chunks);
            for c in 0..chunks {
                let lo = c * width;
                let hi = (lo + width).min(n);
                let r: f64 = a[lo..hi].iter().zip(&b[lo..hi]).map(|(x, y)| x * y).sum();
                close(o1[c], r, "chunk_direct");
                close(o2[c], r, "chunk_extern");
                cases += 1;
            }
        }
    }
    assert_eq!(hex(&sha256_with(compress, b"")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    assert_eq!(hex(&sha256_with(compress, b"abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    for n in [0usize, 1, 55, 56, 63, 64, 65, 119, 120, 1000, 1 << 16, 1 << 20] {
        let bytes: Vec<u8> = (0..n).map(|i| (i * 7 + 3) as u8).collect();
        let mut hexout = [0u8; 65];
        assert!(unsafe { c_sha(bytes.as_ptr(), n, hexout.as_mut_ptr()) });
        let want = std::str::from_utf8(&hexout[..64]).unwrap();
        assert_eq!(hex(&sha256_with(compress, &bytes)), want, "sha256 at {n}");
        cases += 1;
    }
    eprintln!("PASS codegen-experiment {cases}");
    if check_only {
        return;
    }

    // Timed runners, paired per size.
    let mut runners: Vec<Runner> = Vec::new();
    for &n in &[63usize, 1024, 65539] {
        let (a, b) = fill(n);
        let a = std::sync::Arc::new(a);
        let b = std::sync::Arc::new(b);
        let mk = |name: &str, run: Box<dyn FnMut() -> f64>| Runner { size: n, name: name.to_string(), run };
        let (a1, mut o) = (a.clone(), vec![0.0; n]);
        runners.push(mk("map_jit", Box::new(move || { unsafe { map(o.as_mut_ptr(), n as u64, a1.as_ptr(), n as u64, 1.25, 0.5) }; o[n - 1] })));
        let (a1, mut o) = (a.clone(), vec![0.0; n]);
        runners.push(mk("map_jit_u2", Box::new(move || { unsafe { map2(o.as_mut_ptr(), n as u64, a1.as_ptr(), n as u64, 1.25, 0.5) }; o[n - 1] })));
        let (a1, mut o) = (a.clone(), vec![0.0; n]);
        runners.push(mk("map_llvm", Box::new(move || { unsafe { llvm_map(o.as_mut_ptr(), a1.as_ptr(), 1.25, 0.5, n as u64, n as u64) }; o[n - 1] })));
        let (a1, mut o) = (a.clone(), vec![0.0; n]);
        runners.push(mk("map_hand", Box::new(move || { unsafe { hand_map(o.as_mut_ptr(), a1.as_ptr(), 1.25, 0.5, n) }; o[n - 1] })));
        let (a1, b1) = (a.clone(), b.clone());
        runners.push(mk("dot_jit", Box::new(move || unsafe { dot(a1.as_ptr(), n as u64, b1.as_ptr(), n as u64) })));
        let (a1, b1) = (a.clone(), b.clone());
        runners.push(mk("dot_jit_u2", Box::new(move || unsafe { dot2(a1.as_ptr(), n as u64, b1.as_ptr(), n as u64) })));
        let (a1, b1) = (a.clone(), b.clone());
        runners.push(mk("dot_llvm", Box::new(move || unsafe { llvm_dot(a1.as_ptr(), b1.as_ptr(), n as u64, n as u64) })));
        let (a1, b1) = (a.clone(), b.clone());
        runners.push(mk("dot_hand", Box::new(move || unsafe { hand_dot(a1.as_ptr(), b1.as_ptr(), n) })));
        if n > 1024 {
            let chunks = n.div_ceil(64);
            let (a1, b1, mut o) = (a.clone(), b.clone(), vec![0.0; chunks]);
            runners.push(mk("chunk_jit_direct", Box::new(move || { unsafe { chunk_direct(a1.as_ptr(), b1.as_ptr(), n as u64, 64, o.as_mut_ptr()) }; o[chunks - 1] })));
            let (a1, b1, mut o) = (a.clone(), b.clone(), vec![0.0; chunks]);
            runners.push(mk("chunk_jit_extern", Box::new(move || { unsafe { chunk_extern(a1.as_ptr(), b1.as_ptr(), n as u64, 64, o.as_mut_ptr()) }; o[chunks - 1] })));
            let (a1, b1, mut o) = (a.clone(), b.clone(), vec![0.0; chunks]);
            runners.push(mk("chunk_rust_jit", Box::new(move || {
                let mut first = 0;
                let mut c = 0;
                while first < n { let last = (first + 64).min(n); let w = (last - first) as u64; o[c] = unsafe { dot(a1.as_ptr().add(first), w, b1.as_ptr().add(first), w) }; c += 1; first = last; }
                o[chunks - 1]
            })));
            let (a1, b1, mut o) = (a.clone(), b.clone(), vec![0.0; chunks]);
            runners.push(mk("chunk_rust_llvm", Box::new(move || {
                let mut first = 0;
                let mut c = 0;
                while first < n { let last = (first + 64).min(n); let w = (last - first) as u64; o[c] = unsafe { llvm_dot(a1.as_ptr().add(first), b1.as_ptr().add(first), w, w) }; c += 1; first = last; }
                o[chunks - 1]
            })));
        }
    }
    for &n in &[32usize, 1024, 65536, 1 << 20] {
        let bytes: std::sync::Arc<Vec<u8>> = std::sync::Arc::new((0..n).map(|i| (i * 7 + 3) as u8).collect());
        let b1 = bytes.clone();
        runners.push(Runner { size: n, name: "sha_jit".into(), run: Box::new(move || sha256_with(compress, &b1)[0] as f64) });
        let b1 = bytes.clone();
        runners.push(Runner { size: n, name: "sha_c".into(), run: Box::new(move || { let mut h = [0u8; 65]; unsafe { c_sha(b1.as_ptr(), n, h.as_mut_ptr()) }; h[0] as f64 }) });
    }

    // Calibrate each runner to the sample length, warm up, then rotate.
    let mut calls = Vec::new();
    let mut sink = 0.0;
    for r in runners.iter_mut() {
        let mut count = 1usize;
        loop {
            let start = cpu_now();
            for _ in 0..count { sink += black_box((r.run)()); }
            let elapsed = cpu_now() - start;
            if elapsed >= seconds { break; }
            count = (count * 2).max((count as f64 * seconds / elapsed.max(1e-7)).ceil() as usize);
        }
        calls.push(count);
        for _ in 0..4 { for _ in 0..count { sink += black_box((r.run)()); } }
    }
    let groups: Vec<Vec<usize>> = {
        let mut g: Vec<Vec<usize>> = Vec::new();
        for (i, r) in runners.iter().enumerate() {
            if let Some(last) = g.last_mut() { if runners[last[0]].size == r.size && runners[last[0]].name.split('_').next() == r.name.split('_').next() || runners[last[0]].size == r.size { last.push(i); continue; } }
            g.push(vec![i]);
        }
        g
    };
    for group in &groups {
        for round in 0..rounds {
            for k in 0..group.len() {
                let idx = group[(k + round) % group.len()];
                let count = calls[idx];
                let r = &mut runners[idx];
                let start = cpu_now();
                for _ in 0..count { sink += black_box((r.run)()); }
                let elapsed = cpu_now() - start;
                println!("{}\t{}\t{}\t{}\t{:.0}", r.size, r.name, round + 1, count, elapsed * 1e9);
            }
        }
    }
    eprintln!("consumed {sink}");
}
