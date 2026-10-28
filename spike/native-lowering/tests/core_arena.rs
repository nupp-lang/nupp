//! E2-only tests know the Nupp descriptor layout; the bridge stays opaque.
#![cfg(all(target_arch = "aarch64", target_vendor = "apple"))]
use nupp_vm::native_core_provider::nupp_raw_thread_slot;
use std::os::unix::process::ExitStatusExt;

fn mapped(address: usize) -> bool {
    unsafe extern "C" {
        fn mach_vm_region(
            task: u32,
            base: *mut u64,
            bytes: *mut u64,
            flavor: i32,
            info: *mut i32,
            count: *mut u32,
            object: *mut u32,
        ) -> i32;
        fn mach_port_deallocate(task: u32, object: u32) -> i32;
    }
    let (mut base, mut bytes, mut info, mut count, mut object) =
        (address as u64, 0, [0i32; 16], 16, 0);
    #[allow(deprecated)]
    let task = unsafe { libc::mach_task_self() };
    let result = unsafe {
        mach_vm_region(
            task,
            &mut base,
            &mut bytes,
            9,
            info.as_mut_ptr(),
            &mut count,
            &mut object,
        )
    };
    if object != 0 {
        assert_eq!(unsafe { mach_port_deallocate(task, object) }, 0);
    }
    assert!(result == 0 || result == libc::KERN_INVALID_ADDRESS);
    result == 0 && base <= address as u64 && address as u64 - base < bytes
}
fn invoke() {
    let bits = 0x7ffb_0123_4567_89a0u64;
    assert_eq!(
        nupp_vm::heap::slot_hash(bits),
        (bits >> 4).wrapping_mul(0x9e37_79b9_7f4a_7c15) >> 32
    );
}
fn child(name: &str) -> bool {
    if std::env::var("S0_ARENA_CHILD").ok().as_deref() == Some(name) {
        return false;
    }
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .args(["--exact", name, "--test-threads=1", "--nocapture"])
        .env("S0_ARENA_CHILD", name)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("1 passed; 0 failed;"));
    true
}
#[test]
fn reuse_nested_segments_and_thread_teardown() {
    if child("reuse_nested_segments_and_thread_teardown") {
        return;
    }
    assert!(std::env::var_os("NUPP_RAW_CORE").is_some());
    let addresses = std::thread::spawn(|| unsafe {
        assert_eq!(*nupp_raw_thread_slot(), 0);
        invoke();
        let descriptor = *nupp_raw_thread_slot() as *mut u64;
        assert!(!descriptor.is_null());
        assert_eq!(*descriptor, 0);
        let first = *descriptor.add(2);
        assert_ne!(first, 0);
        for _ in 0..1000 {
            invoke();
            assert_eq!(*descriptor.add(2), first);
        }
        let mut addresses = vec![descriptor as usize];
        // Simulate suspended outer entries while entering every supported depth.
        // Canaries at each live frame's end must survive every deeper C entry.
        for depth in 0..1024 {
            *descriptor = depth as u64;
            invoke();
            assert_eq!(*descriptor, depth as u64);
            let segment = *descriptor.add(2 + depth) as usize;
            assert_ne!(segment, 0);
            assert!(!addresses.contains(&segment));
            addresses.push(segment);
            *((segment + 4088) as *mut u64) = 0xabc000 + depth as u64;
            for (index, &previous) in addresses.iter().skip(1).enumerate() {
                assert_eq!(*((previous + 4088) as *const u64), 0xabc000 + index as u64);
            }
        }
        *descriptor = 0;
        for &address in &addresses {
            assert!(mapped(address));
        }
        addresses
    })
    .join()
    .unwrap();
    for address in addresses {
        assert!(
            !mapped(address),
            "mapping retained after TLS finalizer: {address:#x}"
        );
    }
}
#[test]
fn depth_exhaustion_is_an_explicit_spike_trap() {
    const FLAG: &str = "S0_ARENA_TRAP";
    if std::env::var_os(FLAG).is_some() {
        invoke();
        unsafe {
            *(*nupp_raw_thread_slot() as *mut u64) = 1024;
        }
        invoke();
        panic!("depth cap did not trap");
    }
    let output = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "depth_exhaustion_is_an_explicit_spike_trap",
            "--test-threads=1",
        ])
        .env(FLAG, "1")
        .output()
        .unwrap();
    assert_eq!(
        output.status.signal(),
        Some(libc::SIGTRAP),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
}
