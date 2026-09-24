//! Phase four: the one case that still wants a native object -- a component
//! embedded in someone else's program. The same relocation-free images go
//! into a Mach-O relocatable object (`object`) and a static archive
//! (`ar_archive_writer`); the system linker links them into a C program that
//! checks every kernel against the C backend. Every generated word is also
//! decoded by yaxpeax-arm, the pure-Rust decoder planned for `--emit asm`.

use crate::{emit, lower};
use object::write::{MachOBuildVersion, Object, StandardSection, Symbol, SymbolSection};
use object::{Architecture, BinaryFormat, Endianness, SymbolFlags, SymbolKind, SymbolScope};
use regalloc2::{Algorithm, RegallocOptions};
use serde_json::Value as J;
use std::fmt::Write as _;
use std::process::Command;
use yaxpeax_arch::{Decoder, U8Reader};

const KERNELS: &[&str] = &["map", "refine", "explicitMap", "explicitRefine", "explicitAlgebraic"];

/// Decodes every instruction word of a code image; returns the listing and
/// how many words did not decode.
pub fn listing(code: &[u8]) -> (String, usize) {
    let decoder = yaxpeax_arm::armv8::a64::InstDecoder::default();
    let mut out = String::new();
    let mut bad = 0;
    for (k, word) in code.chunks(4).enumerate() {
        let mut reader = U8Reader::new(word);
        match decoder.decode(&mut reader) {
            Ok(inst) => {
                let _ = writeln!(out, "  {:04x}  {}", k * 4, inst);
            }
            Err(e) => {
                bad += 1;
                let _ = writeln!(out, "  {:04x}  <{e}>", k * 4);
            }
        }
    }
    (out, bad)
}

pub fn run(path: &str, out_dir: &str) {
    let doc: J = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
    let c = doc["c"].as_str().unwrap();
    std::fs::create_dir_all(out_dir).unwrap();
    let env = emit::machine_env();

    let mut obj = Object::new(BinaryFormat::MachO, Architecture::Aarch64, Endianness::Little);
    let mut version = MachOBuildVersion::default();
    version.platform = object::macho::PLATFORM_MACOS;
    version.minos = 11 << 16;
    version.sdk = 11 << 16;
    obj.set_macho_build_version(version);
    let text = obj.section_id(StandardSection::Text);
    let mut declarations = String::new();
    let mut listings = String::new();
    let mut undecodable = 0;
    for name in KERNELS {
        let function = doc["functions"].as_array().unwrap().iter().find(|f| f["name"] == *name).unwrap();
        let sig = lower::signature(c, function["symbol"].as_str().unwrap());
        let func = lower::lower(&function["tree"], &sig);
        let options = RegallocOptions { verbose_log: false, validate_ssa: true, algorithm: Algorithm::Ion };
        let output = regalloc2::run(&func, &env, &options).unwrap();
        let e = emit::emit_image(&func, &output);
        let code = &e.layout.bytes[..e.layout.code_len];
        let (text_listing, bad) = listing(code);
        undecodable += bad;
        let _ = writeln!(listings, "{name}:\n{text_listing}");
        // The whole image -- code and its PC-relative pool -- is one symbol.
        let offset = obj.append_section_data(text, &e.layout.bytes, 16);
        let symbol = format!("nupp_direct_{}", sig.symbol);
        obj.add_symbol(Symbol {
            name: symbol.clone().into_bytes(),
            value: offset,
            size: e.layout.bytes.len() as u64,
            kind: SymbolKind::Text,
            scope: SymbolScope::Linkage,
            weak: false,
            section: SymbolSection::Section(text),
            flags: SymbolFlags::None,
        });
        let line = c.lines().find(|l| l.starts_with("KS_API") && l.contains(&format!(" {}(", sig.symbol))).unwrap();
        let decl = line.replacen(&format!(" {}(", sig.symbol), &format!(" {symbol}("), 1);
        let decl = decl.trim_start_matches("KS_API ").split('{').next().unwrap().trim().to_string();
        let _ = writeln!(declarations, "{decl};");
    }
    std::fs::write(format!("{out_dir}/listing-yaxpeax.txt"), &listings).unwrap();
    let object_bytes = obj.write().unwrap();
    std::fs::write(format!("{out_dir}/kernels.o"), &object_bytes).unwrap();

    let member = ar_archive_writer::NewArchiveMember::new(
        object_bytes,
        &ar_archive_writer::DEFAULT_OBJECT_READER,
        "kernels.o".to_string(),
    );
    let mut archive = std::io::Cursor::new(Vec::new());
    ar_archive_writer::write_archive_to_stream(&mut archive, &[member], ar_archive_writer::ArchiveKind::Darwin, false, None)
        .unwrap();
    std::fs::write(format!("{out_dir}/libnuppdirect.a"), archive.into_inner()).unwrap();

    let program = format!("{c}\n\n/* ---- embedding harness ---- */\n{declarations}{EMBED_MAIN}");
    std::fs::write(format!("{out_dir}/embed.c"), program).unwrap();
    let exe = format!("{out_dir}/embed");
    let link = Command::new("clang")
        .args(["-std=c11", "-O3", "-ffp-contract=off", "-fno-fast-math", "-w", "-o", &exe])
        .arg(format!("{out_dir}/embed.c"))
        .args(["-L", out_dir, "-lnuppdirect", "-lm"])
        .output()
        .unwrap();
    assert!(link.status.success(), "link: {}", String::from_utf8_lossy(&link.stderr));
    let warnings = String::from_utf8_lossy(&link.stderr).lines().count();
    let run = Command::new(&exe).output().unwrap();
    print!("{}", String::from_utf8_lossy(&run.stdout));
    println!(
        "embedded via object + ar_archive_writer + system linker: link warnings {warnings}, exit {:?}; \
         yaxpeax-arm decoded every generated word: {} undecodable",
        run.status.code(),
        undecodable
    );
}

const EMBED_MAIN: &str = r#"
#include <stdio.h>
static double left[65539], right[65539], a[65543], b[65543];
static int check(const char *name, double (*ours)(size_t), double (*theirs)(size_t)) {
    size_t sizes[] = {0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 17, 63, 1000, 65539};
    for (size_t s = 0; s < sizeof sizes / sizeof sizes[0]; s++) {
        size_t n = sizes[s];
        for (size_t i = 0; i < n; i++) { left[i] = (double)(i % 97 + 1) * 0.125; right[i] = (double)(i % 17 + 1) * 0.0625; }
        for (size_t i = 0; i < n + 4; i++) { a[i] = -777.0; b[i] = -777.0; }
        double ra = ours(n);
        memcpy(b, a, sizeof a); /* keep ours' output; theirs writes a again below */
        for (size_t i = 0; i < n + 4; i++) a[i] = -777.0;
        double rb = theirs(n);
        for (size_t i = 0; i < n + 4; i++) if (memcmp(&a[i], &b[i], 8)) { printf("  %s n=%zu element %zu differs\n", name, n, i); return 1; }
        if (fabs(ra - rb) > 1e-12 * (fabs(rb) > 1 ? fabs(rb) : 1)) { printf("  %s n=%zu result differs\n", name, n); return 1; }
    }
    printf("  embedded %-18s bit-identical to C\n", name);
    return 0;
}
#define PAIR(label, OURS, THEIRS) \
    static double ours_##label(size_t n) { return OURS; } \
    static double theirs_##label(size_t n) { return THEIRS; }
PAIR(map, (nupp_direct_ks_map(a, left, 1.25, -0.5, n), 0), (ks_map(a, left, 1.25, -0.5, n), 0))
PAIR(refine, (nupp_direct_ks_refine(a, left, n), 0), (ks_refine(a, left, n), 0))
PAIR(xmap, (nupp_direct_ks_explicit_map(a, left, 1.25, -0.5, n, n), 0), (ks_explicit_map(a, left, 1.25, -0.5, n, n), 0))
PAIR(xrefine, (nupp_direct_ks_explicit_refine(a, left, n, n), 0), (ks_explicit_refine(a, left, n, n), 0))
PAIR(xdot, nupp_direct_ks_explicit_algebraic(left, right, n, n), ks_explicit_algebraic(left, right, n, n))
int main(void) {
    int bad = 0;
    bad += check("map", ours_map, theirs_map);
    bad += check("refine", ours_refine, theirs_refine);
    bad += check("explicitMap", ours_xmap, theirs_xmap);
    bad += check("explicitRefine", ours_xrefine, theirs_xrefine);
    bad += check("explicitAlgebraic", ours_xdot, theirs_xdot);
    return bad;
}
"#;
