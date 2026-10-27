#![cfg(feature = "native-runtime")]

use std::process::Command;

#[test]
fn function_arguments_keep_decimal_integers_exact_and_float_spellings_float() {
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "nupp-cli-numeric-{}-{nonce}.image",
        std::process::id()
    ));
    std::fs::write(
        &path,
        r#"function echo 0 1 4 1 v:v
Ret 1
end
function float 1 1 4 1 f:f
FRet 0
end
function integer 2 1 4 1 v:v
IUnbox 0 1
IBox 2 0
Ret 2
end
function module:arguments 3 0 8 1 :v
const 0 func 0
const 1 str "echo"
const 2 func 1
const 3 str "float"
const 4 func 2
const 5 str "integer"
NewTableN 1 0 3
NewClosure 2 0 3 0
SetField 1 1 2
NewClosure 2 1 3 0
SetField 1 3 2
NewClosure 2 2 3 0
SetField 1 5 2
Ret 1
end
module arguments 3
entry 3
"#,
    )
    .unwrap();
    let mut cases = vec![
        ("21", "21".to_owned()),
        ("+21", "21".to_owned()),
        ("-0", "0".to_owned()),
        ("9007199254740993", "9007199254740993".to_owned()),
        ("9223372036854775807", "9223372036854775807".to_owned()),
        ("-9223372036854775808", "-9223372036854775808".to_owned()),
        ("21.0", "21.0".to_owned()),
        ("1e0", "1.0".to_owned()),
        ("-0.0", "-0.0".to_owned()),
        ("not-a-number", "\"not-a-number\"".to_owned()),
    ];
    for text in [
        "9223372036854775808",
        "-9223372036854775809",
        "NaN",
        "inf",
        "-inf",
    ] {
        cases.push((
            text,
            nupp_vm::builtins::num_text(text.parse::<f64>().unwrap()),
        ));
    }
    for scheduled in [false, true] {
        for (argument, expected) in &cases {
            let mut command = Command::new(env!("CARGO_BIN_EXE_nupp-vm"));
            command
                .args(["run", path.to_str().unwrap(), "arguments", "echo", argument])
                .env("NO_JIT", "1")
                .env("NO_AOT", "1")
                .env_remove("NO_THREADED");
            if scheduled {
                command.arg("--tasks");
            }
            let output = command.output().unwrap();
            assert!(
                output.status.success(),
                "argument={argument}, scheduled={scheduled}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert_eq!(
                String::from_utf8(output.stdout).unwrap(),
                format!("{expected}\n"),
                "argument={argument}, scheduled={scheduled}"
            );
        }
    }
    for scheduled in [false, true] {
        for (function, argument, expected) in [
            ("float", "21", "21.0"),
            ("float", "21.0", "21.0"),
            ("float", "-0.0", "-0.0"),
            ("integer", "9007199254740993", "9007199254740993"),
        ] {
            let mut command = Command::new(env!("CARGO_BIN_EXE_nupp-vm"));
            command
                .args([
                    "run",
                    path.to_str().unwrap(),
                    "arguments",
                    function,
                    argument,
                ])
                .env("NO_JIT", "1")
                .env("NO_AOT", "1")
                .env_remove("NO_THREADED");
            if scheduled {
                command.arg("--tasks");
            }
            let output = command.output().unwrap();
            assert!(
                output.status.success(),
                "function={function}, argument={argument}, scheduled={scheduled}: {}",
                String::from_utf8_lossy(&output.stderr)
            );
            assert_eq!(
                String::from_utf8(output.stdout).unwrap(),
                format!("{expected}\n"),
                "function={function}, argument={argument}, scheduled={scheduled}"
            );
        }
    }
    std::fs::remove_file(path).unwrap();
}
