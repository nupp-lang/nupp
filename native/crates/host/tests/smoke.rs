use nupp::HostRuntime;

#[test]
fn file_payload_runs_on_the_owned_lane() {
    let temporary = std::env::temp_dir().join(format!(
        "nupp-rust-host-smoke-{}-{}.lua",
        std::process::id(),
        std::thread::current().name().unwrap_or("test")
    ));
    std::fs::write(
        &temporary,
        b"assert(__nuppHost.hostAbi == 1); assert(arg[1] == 'from-test')",
    )
    .expect("write fixture");
    let executable = std::env::current_exe().expect("test executable");
    let mut runtime = HostRuntime::new(&executable).expect("runtime");
    runtime
        .run_file(&temporary, &[b"from-test".to_vec()])
        .expect("file payload");
    runtime.shutdown().expect("shutdown");
    std::fs::remove_file(&temporary).expect("remove fixture");
}
