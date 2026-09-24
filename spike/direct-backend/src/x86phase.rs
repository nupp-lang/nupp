//! Phase three: the same five kernels lowered for x86-64 AVX2 (one ymm per
//! `fixed4` f64 species), encoded by iced-x86, and packaged with the C
//! backend's own AVX2 output as the oracle in a Linux test program. This Mac
//! cannot execute AVX2, so `spike/x86-guest/run.sh` boots it in QEMU (TCG,
//! `-cpu max`) running as WebAssembly in headless Chrome.

use crate::{emit_x86, lower};
use iced_x86::{Decoder, DecoderOptions, Formatter, IntelFormatter};
use regalloc2::{Algorithm, RegallocOptions};
use serde_json::Value as J;
use std::fmt::Write as _;
use std::time::Instant;

const KERNELS: &[(&str, &str)] = &[
    ("map", "void (*)(double *, const double *, double, double, size_t)"),
    ("refine", "void (*)(double *, const double *, size_t)"),
    ("explicitMap", "void (*)(double *, const double *, double, double, size_t, size_t)"),
    ("explicitRefine", "void (*)(double *, const double *, size_t, size_t)"),
    ("explicitAlgebraic", "double (*)(const double *, const double *, size_t, size_t)"),
];

fn disassemble(bytes: &[u8], code_len: usize) -> String {
    let mut decoder = Decoder::with_ip(64, &bytes[..code_len], 0, DecoderOptions::NONE);
    let mut formatter = IntelFormatter::new();
    let mut out = String::new();
    let mut text = String::new();
    for instruction in &mut decoder {
        text.clear();
        formatter.format(&instruction, &mut text);
        let _ = writeln!(out, "  {:04x}  {}", instruction.ip(), text);
    }
    out
}

/// AVX-512: encode, then decode through both iced and the system's
/// llvm-objdump, since nothing on this machine can execute it.
pub fn avx512(path: &str, out_dir: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let c = doc["c"].as_str().unwrap();
    std::fs::create_dir_all(out_dir).unwrap();
    let env = emit_x86::machine_env_for(true);
    let mut listing = String::new();
    for (name, _) in KERNELS {
        let function = doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap();
        let sig = lower::signature(c, function["symbol"].as_str().unwrap());
        let func = lower::lower_for(&function["tree"], &sig, lower::Target::X86Avx512);
        let options = RegallocOptions { verbose_log: false, validate_ssa: true, algorithm: Algorithm::Ion };
        let output = regalloc2::run(&func, &env, &options).unwrap_or_else(|e| panic!("{name}: {e:?}"));
        let e = emit_x86::emit(&func, &output);
        println!("{name} (avx512): {} bytes, {} spill slots, {} moves", e.words, e.spill_slots, e.moves);
        let _ = writeln!(listing, "{name}:\n{}", disassemble(&e.bytes, e.bytes.len()));
        std::fs::write(format!("{out_dir}/{name}.avx512.bin"), &e.bytes).unwrap();
    }
    std::fs::write(format!("{out_dir}/listing-avx512.txt"), &listing).unwrap();
}

pub fn run(path: &str, out_dir: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let c = doc["c"].as_str().unwrap();
    std::fs::create_dir_all(out_dir).unwrap();
    let env = emit_x86::machine_env();
    let mut images = String::new();
    let mut table = String::from("static const struct kernel kernels[] = {\n");
    let mut listing = String::new();
    for (name, ty) in KERNELS {
        let function = doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap();
        let sig = lower::signature(c, function["symbol"].as_str().unwrap());
        let started = Instant::now();
        let func = lower::lower_for(&function["tree"], &sig, lower::Target::X86Avx2);
        let options = RegallocOptions { verbose_log: false, validate_ssa: true, algorithm: Algorithm::Ion };
        let output = regalloc2::run(&func, &env, &options).unwrap_or_else(|e| panic!("{name}: {e:?}"));
        let e = emit_x86::emit(&func, &output);
        let us = started.elapsed().as_secs_f64() * 1e6;
        // Code ends at the first int3 padding or pool; the listing decodes it all.
        let code_len = e.bytes.len();
        println!("{name}: {} bytes, {} spill slots, {} moves, compile {:.0}us", e.words, e.spill_slots, e.moves, us);
        let _ = writeln!(listing, "{name}:\n{}", disassemble(&e.bytes, code_len));
        std::fs::write(format!("{out_dir}/{name}.avx2.bin"), &e.bytes).unwrap();
        let _ = write!(images, "static const unsigned char image_{name}[] = {{");
        for (k, b) in e.bytes.iter().enumerate() {
            if k % 24 == 0 {
                images.push_str("\n   ");
            }
            let _ = write!(images, " {b},");
        }
        images.push_str("\n};\n");
        let _ = writeln!(
            table,
            "    {{\"{name}\", image_{name}, sizeof image_{name}, (void *){}, \"{ty}\"}},",
            sig.symbol
        );
    }
    table.push_str("};\n");
    std::fs::write(format!("{out_dir}/listing.txt"), &listing).unwrap();
    let harness = format!("{c}\n\n/* ---- spike harness ---- */\n{images}\n{HARNESS_TYPES}{table}{HARNESS_MAIN}");
    std::fs::write(format!("{out_dir}/x86test.c"), harness).unwrap();
    println!("wrote {out_dir}/x86test.c and listing.txt");
}

const HARNESS_TYPES: &str = r#"
#include <sys/mman.h>
#include <time.h>
struct kernel { const char *name; const unsigned char *image; size_t size; void *oracle; const char *type; };
"#;

const HARNESS_MAIN: &str = r#"
typedef void (*map_fn)(double *, const double *, double, double, size_t);
typedef void (*xmap_fn)(double *, const double *, double, double, size_t, size_t);
typedef void (*refine_fn)(double *, const double *, size_t);
typedef void (*xrefine_fn)(double *, const double *, size_t, size_t);
typedef double (*dot_fn)(const double *, const double *, size_t, size_t);

static void *load(const unsigned char *code, size_t n) {
    size_t len = (n + 4095) & ~(size_t)4095;
    void *p = mmap(0, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED) return 0;
    memcpy(p, code, n);
    if (mprotect(p, len, PROT_READ | PROT_EXEC) != 0) return 0;
    return p;
}

static double call(const char *name, void *f, double *out, const double *left, const double *right, size_t n) {
    if (!strcmp(name, "map")) { ((map_fn)f)(out, left, 1.25, -0.5, n); return 0; }
    if (!strcmp(name, "explicitMap")) { ((xmap_fn)f)(out, left, 1.25, -0.5, n, n); return 0; }
    if (!strcmp(name, "refine")) { ((refine_fn)f)(out, left, n); return 0; }
    if (!strcmp(name, "explicitRefine")) { ((xrefine_fn)f)(out, left, n, n); return 0; }
    return ((dot_fn)f)(left, right, n, n);
}

static double now_ns(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e9 + t.tv_nsec; }

int main(void) {
    static double left[65539], right[65539], a[65543], b[65543];
    size_t sizes[21]; int ns = 0;
    for (size_t n = 0; n < 18; n++) sizes[ns++] = n;
    sizes[ns++] = 63; sizes[ns++] = 1000; sizes[ns++] = 65539;
    int failures = 0;
    for (size_t k = 0; k < sizeof kernels / sizeof kernels[0]; k++) {
        const struct kernel *kn = &kernels[k];
        void *ours = load(kn->image, kn->size);
        if (!ours) { printf("@@X86@@\tFAIL\t%s\tload\n", kn->name); failures++; continue; }
        int bad = 0;
        for (int s = 0; s < ns && !bad; s++) {
            size_t n = sizes[s];
            for (size_t i = 0; i < n; i++) { left[i] = (double)(i % 97 + 1) * 0.125; right[i] = (double)(i % 17 + 1) * 0.0625; }
            for (size_t i = 0; i < n + 4; i++) { a[i] = -777.0; b[i] = -777.0; }
            double ra = call(kn->name, ours, a, left, right, n);
            double rb = call(kn->name, kn->oracle, b, left, right, n);
            for (size_t i = 0; i < n + 4; i++) {
                if (memcmp(&a[i], &b[i], sizeof a[i]) != 0) {
                    printf("@@X86@@\tFAIL\t%s\tn=%zu element %zu: ours %.17g C %.17g\n", kn->name, n, i, a[i], b[i]);
                    bad = 1; break;
                }
            }
            double tol = 1e-12 * (fabs(rb) > 1 ? fabs(rb) : 1);
            if (!bad && fabs(ra - rb) > tol) { printf("@@X86@@\tFAIL\t%s\tn=%zu result ours %.17g C %.17g\n", kn->name, n, ra, rb); bad = 1; }
        }
        if (bad) { failures++; continue; }
        /* Emulated time: TCG translation dominates, so this is a sanity figure only. */
        size_t n = 1000;
        double best_o = 1e30, best_c = 1e30;
        for (int rep = 0; rep < 5; rep++) {
            double t = now_ns(); for (int j = 0; j < 20; j++) call(kn->name, ours, a, left, right, n); t = now_ns() - t; if (t < best_o) best_o = t;
            t = now_ns(); for (int j = 0; j < 20; j++) call(kn->name, kn->oracle, b, left, right, n); t = now_ns() - t; if (t < best_c) best_c = t;
        }
        printf("@@X86@@\tPASS\t%s\tbit-identical n=0..17,63,1000,65539; emulated n=1000 ours/C %.2f\n", kn->name, best_o / best_c);
    }
    printf("@@X86@@\tDONE\tfailures\t%d\n", failures);
    return failures != 0;
}
"#;
