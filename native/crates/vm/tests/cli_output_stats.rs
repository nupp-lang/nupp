#![cfg(feature = "jit")]

use std::process::Command;

#[test]
fn output_keeps_exact_bytes_and_reports_specialization_only_when_requested() {
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let directory = std::env::temp_dir().join(format!(
        "nupp-vm-output-stats-{}-{nonce}",
        std::process::id()
    ));
    std::fs::create_dir(&directory).unwrap();
    let image = directory.join("source.image");
    std::fs::write(
        &image,
        r#"function emit 0 0 4 1 :v
const 0 str "one\000two\010\255"
K 1 0
Ret 1
end
function module:outputstats 1 0 12 2 :v
const 0 func 0
const 1 str "emit"
NewTableN 1 0 1
NewClosure 2 0 3 0
SetField 1 1 2
Ret 1
end
module outputstats 1
entry 1
"#,
    )
    .unwrap();
    for enabled in [false, true] {
        let output_path = directory.join(if enabled { "on.bin" } else { "off.bin" });
        let mut command = Command::new(env!("CARGO_BIN_EXE_nupp-vm"));
        command
            .arg("run")
            .arg(&image)
            .args(["outputstats", "emit", "--output"])
            .arg(&output_path)
            .env_remove("NO_JIT")
            .env_remove("JIT_SPEC_STATS")
            .env("JIT_OPT", "none")
            .env("JIT_SPECIALIZE", "0")
            .env("JIT_SPEC_FRAMES", "0")
            .env("JIT_FEEDBACK", "0");
        if enabled {
            command.env("JIT_SPEC_STATS", "1");
        }
        let output = command.output().unwrap();
        assert!(
            output.status.success(),
            "{}",
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(output.stdout.is_empty());
        assert_eq!(std::fs::read(output_path).unwrap(), b"one\0two\n\xff");
        let stderr = String::from_utf8_lossy(&output.stderr);
        assert_eq!(
            stderr
                .lines()
                .filter(|line| line.starts_with("spec: "))
                .count(),
            usize::from(enabled),
            "{stderr}"
        );
        if enabled {
            assert!(
                stderr.contains("0 versions specializing 0 sites"),
                "{stderr}"
            );
        }
    }
    std::fs::remove_dir_all(directory).unwrap();
}
