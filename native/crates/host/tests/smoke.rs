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

#[test]
fn states_keep_more_traces_than_luajits_default_limit() {
    // LuaJIT flushes every trace once 1000 are live; a host state raises the limit
    // before its first trace, so 1500 live loops compile without a flush.
    let mut runtime = HostRuntime::owned(true, None).expect("runtime");
    runtime
        .run_buffer(
            br#"
            local flushes = 0
            local function watch(what) if what == "flush" then flushes = flushes + 1 end end
            jit.attach(watch, "trace")
            jit.opt.start("hotloop=1")
            local keep = {}
            for k = 1, 1500 do
                local source = "return function(n) local s = 0 for i = 1, n do s = s + i * %d end return s end"
                keep[k] = loadstring(source:format(k))()
                keep[k](50)
            end
            jit.attach(watch)
            assert(flushes == 0, "the state flushed its traces " .. flushes .. " times")
            "#,
            "=jit-limits-test",
            &[],
        )
        .expect("no flush");
    runtime.shutdown().expect("shutdown");
}
