//! Feature-gated native implementation for `nupp.data` and `nupp.io`.

use std::ffi::c_char;





/// The public name for one C entry point, forwarding into it.
///
/// Cargo builds this crate's shared library with an export list naming the
/// crate's own symbols and nothing else, so a C symbol linked into it is dropped
/// rather than exported. The name the ABI promises is therefore defined on this
/// side and the implementation stays in C. Every use of this goes when the Rust
/// half does.
macro_rules! forward {
    ($($name:ident = $target:ident($($argument:ident: $type:ty),* $(,)?) -> $answer:ty;)*) => {
        extern "C" {
            $(fn $target($($argument: $type),*) -> $answer;)*
        }

        $(
            #[no_mangle]
            pub unsafe extern "C" fn $name($($argument: $type),*) -> $answer {
                unsafe { $target($($argument),*) }
            }
        )*
    };
}

#[cfg(feature = "files")]
mod files;
#[cfg(any(feature = "sha256", feature = "uuid"))]
mod digest;
#[cfg(feature = "path")]
mod path;
#[cfg(feature = "http")]
mod http;
#[cfg(feature = "process")]
mod process;
#[cfg(feature = "uri")]
mod uri;

// The shared surface, which lives in `c/common.c`.
//
// The error slot and the returned byte buffer are what every facility answers
// through, and both halves of a half-ported provider have to answer through the
// same one. Defining them here as well would give the linker two of each and a
// caller whichever it resolved -- an error written by the Rust half and read
// through the C half is an error nobody sees.
#[allow(dead_code)]
extern "C" {
    fn nupp_fail(message: *const c_char);
}

forward! {
    nuppNativeError = nuppcNativeError() -> *const c_char;
    nuppBytesData = nuppcBytesData(bytes: *const NuppBytes) -> *const u8;
    nuppBytesLength = nuppcBytesLength(bytes: *const NuppBytes) -> usize;
    nuppBytesDestroy = nuppcBytesDestroy(bytes: *mut NuppBytes) -> ();
}

/// The returned byte buffer, opaque on this side. Its contents are C's.
#[repr(C)]
pub struct NuppBytes {
    _private: [u8; 0],
}


/// Roots the selected C ABI in a statically linked host.
///
/// Linker `-u` flags can extract symbols from an ordinary archive, but Rust's
/// release LTO sees this crate as bitcode and removes entry points that Rust
/// itself never names. The host calls this once before starting LuaJIT. Taking
/// each address gives LTO a real reference; the host's linker flags then expose
/// the retained symbols to `ffi.C`.
#[doc(hidden)]
pub fn retain_c_abi_exports() {
    #[allow(unused_macros)]
    macro_rules! retain {
        ($($symbol:path),+ $(,)?) => {
            std::hint::black_box([$($symbol as *const ()),+]);
        };
    }

    retain!(
        nuppNativeError,
        nuppBytesData,
        nuppBytesLength,
        nuppBytesDestroy,
    );

    // The implementations are C, but the names are the forwarders above them,
    // and a forwarder is Rust the release build sees as bitcode with no caller.
    #[cfg(feature = "files")]
    retain!(
        files::nuppFilesInfo,
        files::nuppFilesReadLink,
        files::nuppFilesCreateSymlink,
        files::nuppFilesSetReadOnly,
        files::nuppFilesCreateDirectory,
        files::nuppFilesRemove,
        files::nuppFilesRename,
        files::nuppFilesList,
        files::nuppFilesGlob,
        files::nuppFilesCreateTemporary,
        files::nuppFilesCurrentDirectory,
        files::nuppFilesUserFolder,
        files::nuppFileOpen,
        files::nuppFileRead,
        files::nuppFileWrite,
        files::nuppFileSeek,
        files::nuppFileSize,
        files::nuppFileFlush,
        files::nuppFileClose,
        files::nuppFsSubmitRead,
        files::nuppFsSubmitWrite,
        files::nuppFsSubmitCopy,
        files::nuppFsStatus,
        files::nuppFsData,
        files::nuppFsLength,
        files::nuppFsError,
        files::nuppFsCancel,
        files::nuppFsDestroy,
        files::nuppFsPoll,
        files::nuppFsWait,
        files::nuppFsPending,
    );

    #[cfg(feature = "path")]
    retain!(
        path::nuppPathJoin,
        path::nuppPathNormalize,
        path::nuppPathAbsolute,
        path::nuppPathCanonicalize,
        path::nuppPathRelative,
        path::nuppPathPart,
        path::nuppPathWith,
        path::nuppPathIsAbsolute,
    );

    #[cfg(feature = "uri")]
    retain!(
        uri::nuppUriParse,
        uri::nuppUriPart,
        uri::nuppUriPort,
        uri::nuppUriWithText,
        uri::nuppUriWithPort,
        uri::nuppUriConcatPath,
        uri::nuppUriResolve,
        uri::nuppUriWithEndpoint,
        uri::nuppUriDestroy,
    );

    #[cfg(feature = "sha256")]
    retain!(digest::nuppSha256);

    #[cfg(feature = "uuid")]
    retain!(digest::nuppUuid4, digest::nuppUuid7);

    #[cfg(feature = "http")]
    retain!(
        http::nuppHttpClientCreate,
        http::nuppHttpClientDestroy,
        http::nuppHttpClientSend,
        http::nuppHttpClientPending,
        http::nuppHttpMonotonicMs,
        http::nuppHttpTransferCancel,
        http::nuppHttpTransferDestroy,
        http::nuppHttpTransferOffer,
        http::nuppHttpTransferPollHeaders,
        http::nuppHttpTransferError,
        http::nuppHttpTransferTakeBody,
        http::nuppHttpBodyArm,
        http::nuppHttpBodyPeek,
        http::nuppHttpBodyConsume,
        http::nuppHttpBodyError,
        http::nuppHttpBodyDestroy,
        http::nuppHttpClientPoll,
        http::nuppHttpClientWait,
        http::nuppHttpReadyRelease,
    );

    #[cfg(feature = "process")]
    retain!(
        process::nuppProcessMonotonicMs,
        process::nuppProcessSpawnBegin,
        process::nuppProcessSpawnArg,
        process::nuppProcessSpawnEnv,
        process::nuppProcessSpawnClearEnv,
        process::nuppProcessSpawnCwd,
        process::nuppProcessSpawnStdio,
        process::nuppProcessSpawnCancel,
        process::nuppProcessSpawnRun,
        process::nuppProcessTakeStream,
        process::nuppProcessTryRead,
        process::nuppProcessTryWrite,
        process::nuppProcessCloseStream,
        process::nuppProcessStreamDestroy,
        process::nuppProcessPollExit,
        process::nuppProcessId,
        process::nuppProcessKill,
        process::nuppProcessReap,
        process::nuppProcessUncollectedTotal,
        process::nuppProcessDestroy,
        process::nuppProcessWaitReady,
    );
}


#[cfg(all(
    test,
    any(
        feature = "files",
        feature = "sha256",
        feature = "uuid",
        feature = "path",
        feature = "uri"
    )
))]
mod tests {
    use super::*;
    use std::ffi::CStr;

    /// The ported half of the provider is C, so its tests reach it the way every
    /// other caller does: through the ABI, by name.
    #[cfg(feature = "files")]
    #[allow(non_snake_case)]
    mod ported {
        use super::NuppBytes;
        
        pub const STATUS_PENDING: i32 = 0;
        pub const STATUS_READY: i32 = 1;
        pub const STATUS_FAILED: i32 = 2;
        pub const STATUS_CANCELED: i32 = 3;

        #[repr(C)]
        pub struct NuppRequest {
            _private: [u8; 0],
        }

        extern "C" {
            pub fn nuppFilesGlob(data: *const u8, length: usize) -> *mut NuppBytes;
            pub fn nuppFsSubmitRead(data: *const u8, length: usize) -> *mut NuppRequest;
            pub fn nuppFsSubmitWrite(
                data: *const u8,
                length: usize,
                bytes: *const u8,
                bytes_length: usize,
                mode: u32,
            ) -> *mut NuppRequest;
            pub fn nuppFsStatus(request: *const NuppRequest) -> i32;
            pub fn nuppFsData(request: *const NuppRequest) -> *const u8;
            pub fn nuppFsLength(request: *const NuppRequest) -> usize;
            pub fn nuppFsError(request: *const NuppRequest) -> *const c_char;
            pub fn nuppFsCancel(request: *mut NuppRequest) -> bool;
            pub fn nuppFsDestroy(request: *mut NuppRequest);
            #[link_name = "nuppFsWait"]
            fn wait_for(milliseconds: u64) -> usize;
            #[link_name = "nuppFsPending"]
            fn pending() -> usize;
        }

        /// The two the lane offers without a handle to get wrong, so a test that
        /// only waits and counts reads like the safe calls they replaced.
        pub fn nuppFsWait(milliseconds: u64) -> usize {
            unsafe { wait_for(milliseconds) }
        }

        pub fn nuppFsPending() -> usize {
            unsafe { pending() }
        }
    }

    #[cfg(feature = "files")]
    #[test]
    fn globs_recurse_sort_and_report_invalid_patterns() {
        use std::hash::{BuildHasher, Hasher, RandomState};

        let stamp = RandomState::new().build_hasher().finish();
        let root = std::env::temp_dir().join(format!("nupp-glob-{stamp:016x}"));
        std::fs::create_dir_all(root.join("nested/deep")).expect("test directories");
        for name in ["root.nupp", "nested/child.nupp", "nested/deep/leaf.nupp"] {
            std::fs::write(root.join(name), name).expect("test file");
        }
        std::fs::write(root.join("nested/deep/ignored.lua"), "ignored").expect("other file");

        let pattern = root.join("**/*.nupp").into_os_string().into_string().expect("UTF-8 path");
        let handle = unsafe { ported::nuppFilesGlob(pattern.as_ptr(), pattern.len()) };
        assert!(!handle.is_null(), "the pattern expanded");
        let result = unsafe {
            String::from_utf8(slice::from_raw_parts(nuppBytesData(handle), nuppBytesLength(handle)).to_vec())
                .expect("UTF-8 matches")
        };
        unsafe { nuppBytesDestroy(handle) };
        let expected = [
            root.join("nested").join("child.nupp"),
            root.join("nested").join("deep").join("leaf.nupp"),
            root.join("root.nupp"),
        ]
        .into_iter()
        .map(|path| path.into_os_string().into_string().expect("UTF-8 path"))
        .collect::<Vec<_>>();
        assert_eq!(result.split('\0').collect::<Vec<_>>(), expected);

        let flat = root.join("*.nupp").into_os_string().into_string().expect("UTF-8 path");
        let handle = unsafe { ported::nuppFilesGlob(flat.as_ptr(), flat.len()) };
        assert!(!handle.is_null(), "the flat pattern expanded");
        let result = unsafe {
            String::from_utf8(slice::from_raw_parts(nuppBytesData(handle), nuppBytesLength(handle)).to_vec())
                .expect("UTF-8 matches")
        };
        unsafe { nuppBytesDestroy(handle) };
        assert_eq!(result, root.join("root.nupp").to_string_lossy());

        let invalid = root.join("[").into_os_string().into_string().expect("UTF-8 path");
        assert!(unsafe { ported::nuppFilesGlob(invalid.as_ptr(), invalid.len()) }.is_null());
        assert!(!unsafe { CStr::from_ptr(nuppNativeError()) }.to_bytes().is_empty());
        std::fs::remove_dir_all(root).expect("remove test directory");
    }

    // The lane's accounting is process-global, so its cases share one test
    // rather than racing each other for the budget they are each about.
    #[cfg(feature = "files")]
    #[test]
    fn the_lane_settles_bounds_and_refunds_transfers() {
        use ported::*;
        use std::hash::{BuildHasher, Hasher, RandomState};

        let stamp = RandomState::new().build_hasher().finish();
        let root = std::env::temp_dir().join(format!("nupp-lane-{stamp:016x}"));
        std::fs::create_dir_all(&root).expect("test directory");
        let submit = |name: &str, contents: &[u8], mode: u32| {
            let path = root.join(name);
            let text = path.to_str().expect("utf-8 path").to_owned();
            unsafe {
                nuppFsSubmitWrite(
                    text.as_ptr(),
                    text.len(),
                    contents.as_ptr(),
                    contents.len(),
                    mode,
                )
            }
        };
        let await_settled = |request: *mut NuppRequest| {
            while unsafe { nuppFsStatus(request) } == STATUS_PENDING {
                nuppFsWait(200);
            }
            unsafe { nuppFsStatus(request) }
        };

        // Many transfers settle concurrently, and the budget comes back.
        let before = nuppFsPending();
        let mut writes = Vec::new();
        for index in 0..32 {
            let request = submit(&format!("file-{index}.bin"), b"payload", 0);
            assert!(!request.is_null(), "the lane accepted the transfer");
            writes.push(request);
        }
        for request in &writes {
            assert_eq!(await_settled(*request), STATUS_READY);
        }
        for request in writes {
            unsafe { nuppFsDestroy(request) };
        }
        assert_eq!(nuppFsPending(), before, "settled transfers return their slot");

        // Releasing the instant the result appears returns the budget then, not
        // whenever the worker gets around to letting go of the state it shares
        // with the caller. Repeated, because the window this closes is narrow.
        for round in 0..64 {
            let request = submit(&format!("tight-{round}.bin"), b"payload", 0);
            assert!(!request.is_null());
            while unsafe { nuppFsStatus(request) } == STATUS_PENDING {
                std::thread::yield_now();
            }
            unsafe { nuppFsDestroy(request) };
            assert_eq!(
                nuppFsPending(),
                before,
                "a transfer released on sight is accounted for on sight"
            );
        }

        // A read carries the bytes the worker found.
        let path = root.join("file-0.bin");
        let text = path.to_str().expect("utf-8 path").to_owned();
        let read = unsafe { nuppFsSubmitRead(text.as_ptr(), text.len()) };
        assert!(!read.is_null());
        assert_eq!(await_settled(read), STATUS_READY);
        let bytes = unsafe {
            slice::from_raw_parts(nuppFsData(read), nuppFsLength(read))
        };
        assert_eq!(bytes, b"payload");
        unsafe { nuppFsDestroy(read) };

        // A failure carries a reason rather than an empty success.
        let missing = root.join("absent").join("deep.bin");
        let text = missing.to_str().expect("utf-8 path").to_owned();
        let failed = unsafe {
            nuppFsSubmitWrite(text.as_ptr(), text.len(), b"x".as_ptr(), 1, 0)
        };
        assert!(!failed.is_null(), "a write to a missing directory is submitted");
        assert_eq!(await_settled(failed), STATUS_FAILED);
        let reason = unsafe { CStr::from_ptr(nuppFsError(failed)) };
        assert!(!reason.to_bytes().is_empty(), "a failure names itself");
        unsafe { nuppFsDestroy(failed) };

        // A cancelled transfer stops being the caller's, and gives the slot
        // back when the handle goes.
        let cancelled = submit("cancelled.bin", b"payload", 0);
        assert!(!cancelled.is_null());
        unsafe { nuppFsCancel(cancelled) };
        while nuppFsWait(50) == 0 && unsafe { nuppFsStatus(cancelled) } == STATUS_PENDING {}
        assert_eq!(unsafe { nuppFsStatus(cancelled) }, STATUS_CANCELED);
        unsafe { nuppFsDestroy(cancelled) };
        assert_eq!(nuppFsPending(), before, "a cancelled transfer is refunded");

        // The request cap refuses rather than queueing without limit.
        let mut held = Vec::new();
        let mut refused = false;
        for index in 0..200 {
            let request = submit(&format!("held-{index}.bin"), b"x", 0);
            if request.is_null() {
                refused = true;
                break;
            }
            held.push(request);
        }
        assert!(refused, "the lane refuses past its request cap");
        for request in held {
            while unsafe { nuppFsStatus(request) } == STATUS_PENDING {
                nuppFsWait(200);
            }
            unsafe { nuppFsDestroy(request) };
        }
        assert_eq!(nuppFsPending(), before, "the refused run leaks no slots");

        std::fs::remove_dir_all(&root).expect("test cleanup");
    }

    #[cfg(feature = "sha256")]
    #[test]
    fn sha256_matches_a_published_vector() {
        let mut output = [0 as c_char; 65];
        assert!(unsafe { digest::nuppSha256(b"abc".as_ptr(), 3, output.as_mut_ptr()) });
        let text = unsafe { CStr::from_ptr(output.as_ptr()) }.to_str().unwrap();
        assert_eq!(
            text,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[cfg(feature = "uuid")]
    #[test]
    fn uuid_generators_write_the_requested_versions() {
        // The shape is `8-4-4-4-12` lowercase hex, the version is the first
        // digit of the third group, and the variant is the first of the fourth.
        fn checked(text: &str, version: char) {
            let groups: Vec<&str> = text.split('-').collect();
            assert_eq!(
                groups.iter().map(|group| group.len()).collect::<Vec<_>>(),
                vec![8, 4, 4, 4, 12],
                "{text} is not shaped like a UUID"
            );
            assert!(
                text.chars().all(|c| c == '-' || c.is_ascii_hexdigit() && !c.is_uppercase()),
                "{text} is not lowercase hex"
            );
            assert_eq!(groups[2].chars().next(), Some(version), "{text} version");
            assert!(
                matches!(groups[3].chars().next(), Some('8' | '9' | 'a' | 'b')),
                "{text} is not the RFC 4122 variant"
            );
        }

        let mut output = [0 as c_char; 37];
        assert!(unsafe { digest::nuppUuid4(output.as_mut_ptr()) });
        let text = unsafe { CStr::from_ptr(output.as_ptr()) }.to_str().unwrap();
        checked(text, '4');
        assert!(unsafe { digest::nuppUuid7(output.as_mut_ptr()) });
        let text = unsafe { CStr::from_ptr(output.as_ptr()) }.to_str().unwrap();
        checked(text, '7');
    }

    #[cfg(feature = "path")]
    #[test]
    fn paths_answer_the_documented_parts() {
        // Reading a path is text, and the answers are the ones the standard
        // library this replaced gave: `.` is normalised away where a path is
        // rebuilt, and kept where one is sliced, because asking for a path's
        // parent asks about that path rather than about a tidier one.
        fn answered(bytes: *mut std::ffi::c_void) -> Option<String> {
            let bytes = bytes as *mut NuppBytes;
            if bytes.is_null() {
                return None;
            }
            let text = unsafe {
                String::from_utf8(
                    slice::from_raw_parts(nuppBytesData(bytes), nuppBytesLength(bytes)).to_vec(),
                )
                .expect("UTF-8")
            };
            unsafe { nuppBytesDestroy(bytes) };
            Some(text)
        }
        fn part(input: &str, kind: u32) -> Option<String> {
            answered(unsafe { path::nuppPathPart(input.as_ptr(), input.len(), kind) })
        }
        fn normalized(input: &str) -> Option<String> {
            answered(unsafe { path::nuppPathNormalize(input.as_ptr(), input.len()) })
        }
        fn with(input: &str, value: &str, extension: bool) -> Option<String> {
            answered(unsafe {
                path::nuppPathWith(
                    input.as_ptr(), input.len(), value.as_ptr(), value.len(), extension,
                )
            })
        }
        fn relative(input: &str, base: &str) -> Option<String> {
            answered(unsafe {
                path::nuppPathRelative(input.as_ptr(), input.len(), base.as_ptr(), base.len())
            })
        }

        let messy = "alpha/./beta/../file.tar.gz";
        assert_eq!(normalized(messy).as_deref(), Some("alpha/file.tar.gz"));
        assert_eq!(normalized("a/..").as_deref(), Some("."));
        assert_eq!(normalized("../../a").as_deref(), Some("../../a"));
        assert_eq!(normalized("/../a").as_deref(), Some("/a"));

        assert_eq!(part(messy, 0).as_deref(), Some("alpha/./beta/.."));
        assert_eq!(part(messy, 1).as_deref(), Some("file.tar.gz"));
        assert_eq!(part(messy, 2).as_deref(), Some("file.tar"));
        assert_eq!(part(messy, 3).as_deref(), Some("gz"));
        assert_eq!(part("/", 0), None, "a root has no parent");
        assert_eq!(part("foo", 0).as_deref(), Some(""));
        assert_eq!(part("/foo", 0).as_deref(), Some("/"));
        assert_eq!(part(".bashrc", 2).as_deref(), Some(".bashrc"));
        assert_eq!(part(".bashrc", 3), None, "a leading dot is a name, not an extension");
        assert_eq!(part("a.", 3).as_deref(), Some(""));
        assert_eq!(part("noext", 3), None);
        assert_eq!(part("a/..", 1), None, "`..` is not a file name");

        assert_eq!(with(messy, "other.txt", false).as_deref(), Some("alpha/./beta/../other.txt"));
        assert_eq!(with(messy, "bz2", true).as_deref(), Some("alpha/./beta/../file.tar.bz2"));
        assert_eq!(with(messy, "", true).as_deref(), Some("alpha/./beta/../file.tar"));
        assert_eq!(with("a/..", "c", false).as_deref(), Some("a/../c"));

        assert_eq!(relative("/a/b/c", "/a/d").as_deref(), Some("../b/c"));
        assert_eq!(relative("/a/b", "/a/b").as_deref(), Some(""));
        // One anchored and one not do not share a coordinate system. An
        // absolute target is still an answer -- it names where it is without
        // reference to the base -- and a relative one against an absolute base
        // is not.
        assert_eq!(relative("/a/b", "a/b").as_deref(), Some("/a/b"));
        assert_eq!(relative("a/b", "/a/b"), None);

        assert!(unsafe { path::nuppPathIsAbsolute("/a".as_ptr(), 2) });
        assert!(!unsafe { path::nuppPathIsAbsolute("a".as_ptr(), 1) });

        let parts = [
            (b"/a".as_ptr(), 2usize),
            (b"/b".as_ptr(), 2usize),
        ];
        let views: Vec<(*const u8, usize)> = parts.to_vec();
        let joined = answered(unsafe {
            path::nuppPathJoin(views.as_ptr() as *const std::ffi::c_void, views.len())
        });
        assert_eq!(joined.as_deref(), Some("/b"), "an absolute part replaces what came before");
    }

    #[cfg(feature = "uri")]
    #[test]
    fn uris_parse_and_normalize() {
        let input = b"https://EXAMPLE.com/a/../b?q=1";
        let uri = unsafe { uri::nuppUriParse(input.as_ptr(), input.len()) };
        assert!(!uri.is_null());
        let mut length = 0;
        let data = unsafe { uri::nuppUriPart(uri, 0, &mut length) };
        let output = unsafe { slice::from_raw_parts(data, length) };
        assert_eq!(output, b"https://example.com/b?q=1");
        assert!(unsafe { uri::nuppUriWithPort(uri, 70_000) }.is_null());
        unsafe { uri::nuppUriDestroy(uri) };
    }
}

#[cfg(all(test, feature = "process", unix))]
mod process_tests {
        use crate::process::*;
        use std::os::fd::AsRawFd;

        fn arg(request: *mut NuppSpawn, text: &str) {
            assert!(unsafe { nuppProcessSpawnArg(request, text.as_ptr(), text.len()) });
        }

        /// Spawns `sh -c script` with everything piped, and every environment entry the
        /// test asks for.
        fn spawn(script: &str, env: &[&str]) -> *mut NuppChild {
            spawn_with(script, env, false, false)
        }

        fn spawn_with(
            script: &str,
            env: &[&str],
            clear: bool,
            join_stderr: bool,
        ) -> *mut NuppChild {
            let request = nuppProcessSpawnBegin();
            arg(request, "sh");
            arg(request, "-c");
            arg(request, script);
            if clear {
                assert!(unsafe { nuppProcessSpawnClearEnv(request, true) });
            }
            if join_stderr {
                assert!(unsafe { nuppProcessSpawnStdio(request, 2, MODE_STDOUT) });
            }
            for entry in env {
                assert!(unsafe {
                    nuppProcessSpawnEnv(request, entry.as_ptr(), entry.len())
                });
            }
            let child = unsafe { nuppProcessSpawnRun(request) };
            assert!(!child.is_null(), "the child did not start");

            child
        }

        /// Drains a stream to end, waiting on it rather than spinning.
        fn drain(stream: *mut NuppStream) -> String {
            let mut collected = Vec::new();
            let mut room = [0u8; 4096];
            loop {
                let got = unsafe { nuppProcessTryRead(stream, room.as_mut_ptr(), room.len()) };
                match got {
                    GONE => break,
                    WOULD_BLOCK => {
                        unsafe { nuppProcessWaitReady(&stream, 1, std::ptr::null(), 0, 250) };
                    }
                    FAILED => panic!("the read failed"),
                    count => collected.extend_from_slice(&room[..count as usize]),
                }
            }

            String::from_utf8(collected).expect("the child wrote text")
        }

        fn settle(child: *mut NuppChild) -> (i32, bool) {
            let mut code = -1;
            let mut killed = false;
            for _ in 0..2000 {
                let answer = unsafe { nuppProcessPollExit(child, &mut code, &mut killed) };
                assert!(answer >= 0, "polling the child failed");
                if answer == 1 {
                    return (code, killed);
                }
                unsafe { nuppProcessWaitReady(std::ptr::null(), 0, std::ptr::null(), 0, 5) };
            }
            panic!("the child never ended");
        }

        #[test]
        fn a_child_speaks_and_exits() {
            let child = spawn("printf 'hello from a child'; exit 3", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            assert!(!out.is_null());
            let said = drain(out);
            let (code, killed) = settle(child);
            assert_eq!(said, "hello from a child");
            assert_eq!(code, 3);
            assert!(!killed);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED);
            assert_eq!(unsafe { nuppProcessReap(child) }, RELEASED);
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn stdout_and_stderr_stay_apart() {
            let child = spawn("printf out; printf err >&2", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            let err = unsafe { nuppProcessTakeStream(child, 2) };
            assert_eq!(drain(out), "out");
            assert_eq!(drain(err), "err");
            settle(child);
            unsafe { nuppProcessCloseStream(out) };
            unsafe { nuppProcessCloseStream(err) };
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessStreamDestroy(err) };
            unsafe { nuppProcessDestroy(child) };
        }

        /// Reports what a script printed, once the child has finished.
        fn say(child: *mut NuppChild) -> String {
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            assert!(!out.is_null());
            let said = drain(out);
            settle(child);
            unsafe { nuppProcessCloseStream(out) };
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessDestroy(child) };

            said
        }

        // The environment has three shapes and they are asked for separately, because
        // the interesting one used to be inexpressible: with clearing implied by adding
        // an entry, "cleared and empty" and "inherit" were the same request.
        //
        // The marker is a variable only this process could have supplied. `PATH` would
        // not do -- a shell inheriting no `PATH` invents one, so its presence says
        // nothing about what was passed in.

        #[test]
        fn an_untouched_environment_is_inherited() {
            std::env::set_var("NUPP_MARK_INHERIT", "from the parent");
            let said = say(spawn("printf '%s' \"$NUPP_MARK_INHERIT\"", &[]));
            assert_eq!(said, "from the parent");
        }

        #[test]
        fn entries_overlay_an_inherited_environment() {
            std::env::set_var("NUPP_MARK_OVERLAY", "from the parent");
            let said = say(spawn(
                "printf '%s %s' \"$NUPP_MARK_OVERLAY\" \"$NUPP_ADDED\"",
                &["NUPP_ADDED=added"],
            ));
            assert_eq!(said, "from the parent added", "both the inherited and the added");
        }

        #[test]
        fn a_cleared_environment_keeps_only_what_it_was_given() {
            std::env::set_var("NUPP_MARK_CLEARED", "from the parent");
            let said = say(spawn_with(
                "printf '%s' \"$NUPP_ONLY${NUPP_MARK_CLEARED:+ leaked}\"",
                &["NUPP_ONLY=set"],
                true,
                false,
            ));
            assert_eq!(said, "set", "the entry given arrived and the parent's did not");
        }

        #[test]
        fn a_cleared_environment_can_be_empty() {
            // The request that had no representation at all: with clearing implied by
            // adding an entry, asking for an empty environment was asking to inherit.
            std::env::set_var("NUPP_MARK_EMPTY", "from the parent");
            let said = say(spawn_with(
                "printf '%s' \"${NUPP_MARK_EMPTY:-none}\"",
                &[],
                true,
                false,
            ));
            assert_eq!(said, "none", "nothing was inherited and nothing was added");
        }

        #[test]
        fn stderr_can_join_stdout_on_one_pipe() {
            // Arranged before the spawn, because the child's two descriptors have to be
            // the same pipe when it starts. Ordering within the child's output is the
            // child's business; that both arrived on one stream is this module's.
            let child = spawn_with("printf out; printf err >&2", &[], false, true);
            assert!(
                unsafe { nuppProcessTakeStream(child, 2) }.is_null(),
                "stderr has no stream of its own, and says so rather than handing back a
                 second owner of stdout's"
            );
            let said = say(child);
            assert!(said.contains("out") && said.contains("err"),
                "both streams arrived on the one pipe, got: {said}");
            assert_eq!(said.len(), 6, "and nothing else did");
        }

        /// The environment variable that turns a test run into the helper below.
        const JOIN_HELPER: &str = "NUPP_JOIN_HELPER_OUTPUT";

        #[test]
        fn stderr_joins_stdout_wherever_stdout_went() {
            // Checked by where the bytes land, not by whether a pipe exists. Absence of
            // a pipe is equally true of a stderr that inherited descriptor 2 and went
            // somewhere else entirely, which is the bug this is about.
            //
            // Which means pointing this process's own stdout at a file -- and that is
            // process-wide state, in a runner that runs its tests on threads. Doing it
            // here would redirect whatever else happened to spawn at that moment, and
            // strand stdout entirely if an assertion unwound before it was put back. So
            // the scenario runs in a copy of this binary, told by an environment
            // variable to be the helper and to run this one test, where descriptor 1 is
            // nobody else's business.
            if let Ok(destination) = std::env::var(JOIN_HELPER) {
                join_helper(&destination);

                return;
            }

            let directory = std::env::temp_dir().join(format!(
                "nupp-join-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|since| since.as_nanos())
                    .unwrap_or(0)
            ));
            let helper = std::process::Command::new(
                std::env::current_exe().expect("this test binary"),
            )
            .args([
                "--exact",
                "process_tests::stderr_joins_stdout_wherever_stdout_went",
                "--nocapture",
            ])
            .env(JOIN_HELPER, &directory)
            .output()
            .expect("the helper ran");

            let landed = std::fs::read_to_string(&directory).unwrap_or_default();
            let _ = std::fs::remove_file(&directory);
            assert!(
                helper.status.success(),
                "the helper finished: {}",
                String::from_utf8_lossy(&helper.stderr)
            );
            // Distinctive markers, because the helper's own descriptor 1 is this file
            // and its test harness prints to it too. That output names the test being
            // run -- and this test's name has "err" in it, which made a `contains("err")`
            // check pass no matter where the child's stderr actually went.
            assert!(
                landed.contains("STDOUT-LANDED"),
                "stdout went where this process's does; got {landed:?}"
            );
            assert!(
                landed.contains("STDERR-LANDED"),
                "and so did stderr, rather than to descriptor 2's own destination; got {landed:?}"
            );
        }

        /// The scenario, in a process of its own.
        ///
        /// Points descriptor 1 at `destination`, starts a child that inherits stdout and
        /// joins stderr to it, and lets both halves land wherever descriptor 1 now goes.
        /// Nothing here is put back, because nothing else in this process cares.
        fn join_helper(destination: &str) {
            let file = std::fs::File::create(destination).expect("a scratch file");
            unsafe {
                assert!(libc::dup2(file.as_raw_fd(), libc::STDOUT_FILENO) >= 0);
            }

            let request = nuppProcessSpawnBegin();
            arg(request, "sh");
            arg(request, "-c");
            arg(request, "printf STDOUT-LANDED; printf STDERR-LANDED >&2");
            assert!(unsafe { nuppProcessSpawnStdio(request, 1, MODE_INHERIT) });
            assert!(unsafe { nuppProcessSpawnStdio(request, 2, MODE_STDOUT) });
            let child = unsafe { nuppProcessSpawnRun(request) };
            assert!(!child.is_null(), "the child started");
            assert!(
                unsafe { nuppProcessTakeStream(child, 1) }.is_null(),
                "no pipe was made, so there is nothing to take"
            );
            assert!(unsafe { nuppProcessTakeStream(child, 2) }.is_null());
            assert_eq!(settle(child).0, 0);
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn stderr_joined_to_a_discarded_stdout_needs_no_pipe() {
            // The other destination worth checking, and one that needs no descriptor
            // games: both really are the same place.
            let request = nuppProcessSpawnBegin();
            arg(request, "sh");
            arg(request, "-c");
            arg(request, "printf out; printf err >&2");
            assert!(unsafe { nuppProcessSpawnStdio(request, 1, MODE_NULL) });
            assert!(unsafe { nuppProcessSpawnStdio(request, 2, MODE_STDOUT) });
            let quiet = unsafe { nuppProcessSpawnRun(request) };
            assert!(!quiet.is_null());
            assert!(unsafe { nuppProcessTakeStream(quiet, 1) }.is_null());
            assert_eq!(settle(quiet).0, 0);
            unsafe { nuppProcessReap(quiet) };
            unsafe { nuppProcessDestroy(quiet) };
        }

        /// The invariant the whole masking sequence turns on, and it cannot be checked
        /// on a platform that quiets the descriptor instead: there, no mask is taken and
        /// nothing is ever consumed.
        ///
        /// Standard signals are not queued. If a `SIGPIPE` was already pending when a
        /// write began, the one waiting afterwards may be that one rather than the
        /// write's, and consuming it steals a signal the host was going to handle. So
        /// the rule is: when it was already there, leave it. This raises one, blocks it
        /// so it stays pending, provokes a broken pipe, and checks it survived.
        #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "netbsd")))]
        #[test]
        fn a_sigpipe_already_pending_is_left_alone() {
            unsafe {
                let mut blocked: libc::sigset_t = std::mem::zeroed();
                libc::sigemptyset(&mut blocked);
                libc::sigaddset(&mut blocked, libc::SIGPIPE);
                let mut previous: libc::sigset_t = std::mem::zeroed();
                assert_eq!(
                    libc::pthread_sigmask(libc::SIG_BLOCK, &blocked, &mut previous),
                    0
                );

                // Pending, and staying that way because this thread has it blocked.
                assert_eq!(libc::raise(libc::SIGPIPE), 0);
                let mut pending: libc::sigset_t = std::mem::zeroed();
                libc::sigemptyset(&mut pending);
                assert_eq!(libc::sigpending(&mut pending), 0);
                assert_eq!(
                    libc::sigismember(&pending, libc::SIGPIPE),
                    1,
                    "the host's own signal is waiting before the write"
                );

                let input = broken_input_for_test();
                let payload = vec![b'x'; 4096];
                assert!(
                    nuppProcessTryWrite(input, payload.as_ptr(), payload.len()) == GONE,
                    "the write really did break a pipe -- without that this proves only
                     that a signal nobody touched stayed put"
                );

                libc::sigemptyset(&mut pending);
                assert_eq!(libc::sigpending(&mut pending), 0);
                assert_eq!(
                    libc::sigismember(&pending, libc::SIGPIPE),
                    1,
                    "and it is still waiting afterwards, rather than having been taken"
                );

                nuppProcessCloseStream(input);
                nuppProcessStreamDestroy(input);

                // Consume the one this test raised, so it does not outlive the test.
                let timeout = libc::timespec { tv_sec: 0, tv_nsec: 0 };
                libc::sigtimedwait(&blocked, std::ptr::null_mut(), &timeout);
                libc::pthread_sigmask(libc::SIG_SETMASK, &previous, std::ptr::null_mut());
            }
        }

        /// Turns a test run into the auto-reaping helper below.
        const ECHILD_HELPER: &str = "NUPP_ECHILD_HELPER";

        #[test]
        fn a_child_the_host_reaped_is_not_reported_as_left() {
            // `SIGCHLD` set to `SIG_IGN` makes the system reap children itself, so
            // `try_wait` answers `ECHILD`: gone, and nothing here will ever see it exit.
            // Read as "still running", every abandoned handle on such a host would be
            // counted as a leak that never happened.
            //
            // The disposition is process-wide and the runner uses threads, so this runs
            // in a copy of the binary rather than changing signal handling under
            // whatever else is going on.
            let _counter = counter_lock();
            if std::env::var(ECHILD_HELPER).is_ok() {
                unsafe {
                    assert_ne!(libc::signal(libc::SIGCHLD, libc::SIG_IGN), libc::SIG_ERR);
                }
                let before = nuppProcessUncollectedTotal();
                let child = spawn("exit 0", &[]);
                let pid = unsafe { nuppProcessId(child) } as libc::pid_t;
                // Waited for rather than slept through: on a loaded runner the child may
                // not have been scheduled yet, and a fixed pause would destroy the handle
                // while it was still running -- testing the ordinary path by accident and
                // saying nothing about `ECHILD` at all.
                let mut gone = false;
                for _ in 0..500 {
                    if unsafe { libc::kill(pid, 0) } == -1 {
                        // Only "no such process" proves it. `kill` can fail for other
                        // reasons -- `EPERM` says the pid exists and belongs to somebody
                        // else -- and treating any failure as proof would let the test
                        // pass on a pid that was very much alive.
                        let failure = std::io::Error::last_os_error();
                        assert_eq!(
                            failure.raw_os_error(),
                            Some(libc::ESRCH),
                            "the pid is gone, rather than merely unsignalable: {failure}"
                        );
                        gone = true;
                        break;
                    }
                    std::thread::sleep(std::time::Duration::from_millis(10));
                }
                assert!(gone, "the host reaped the child, so its pid is no longer ours");
                unsafe { nuppProcessDestroy(child) };
                assert_eq!(
                    nuppProcessUncollectedTotal(),
                    before,
                    "a child the host reaped is gone, not left behind"
                );

                return;
            }

            let helper = std::process::Command::new(
                std::env::current_exe().expect("this test binary"),
            )
            .args([
                "--exact",
                "process_tests::a_child_the_host_reaped_is_not_reported_as_left",
                "--nocapture",
            ])
            .env(ECHILD_HELPER, "1")
            .output()
            .expect("the helper ran");
            assert!(
                helper.status.success(),
                "the helper finished: {}{}",
                String::from_utf8_lossy(&helper.stdout),
                String::from_utf8_lossy(&helper.stderr)
            );
        }

        #[test]
        fn an_ended_child_is_resolved_and_a_running_one_is_not() {
            // The one classification the fallback makes, and the only place `ECHILD`
            // can be handed to it without arranging a host that reaps its own children.
            assert!(
                !resolved_for_test(Ok(None)),
                "still running is not resolved"
            );
            assert!(
                resolved_for_test(Err(std::io::Error::from_raw_os_error(libc::ECHILD))),
                "collected by the host itself is resolved"
            );
            assert!(
                !resolved_for_test(Err(std::io::Error::from_raw_os_error(libc::EIO))),
                "an unexplained failure says nothing, so it is not resolved"
            );
        }

        #[test]
        fn a_child_dropped_without_being_closed_is_signalled_and_counted() {
            // Taken because this drop may itself increment the count, and a test
            // comparing that number before and after its own work must not have this
            // one running alongside it.
            let _counter = counter_lock();
            // Rust does not kill or wait when a `Child` is dropped, so without this the
            // handle would leave a live process behind with nobody owning it.
            //
            // What the fallback promises is narrow and deliberately so: the child is
            // signalled, it is looked at once, and if that look does not find it ended
            // the count says so. It does not wait -- this runs during whatever the host
            // was doing -- and it does not chase. Closing the handle properly is the
            // guarantee; this only makes failing to do so cheap and visible.
            let before = nuppProcessUncollectedTotal();
            let child = spawn("sleep 30", &[]);
            let pid = unsafe { nuppProcessId(child) };
            unsafe { nuppProcessDestroy(child) };

            // The signal landed, which is the part that matters: reaping it here proves
            // it ended rather than running out its thirty seconds.
            let mut status = 0;
            let mut ended = false;
            for _ in 0..200 {
                let answered =
                    unsafe { libc::waitpid(pid as libc::pid_t, &mut status, libc::WNOHANG) };
                if answered == pid as libc::pid_t {
                    ended = true;
                    break;
                }
                if answered == -1 {
                    let failure = std::io::Error::last_os_error();
                    match failure.raw_os_error() {
                        // Somebody else has it, which is as good as this needs.
                        Some(libc::ECHILD) => {
                            ended = true;
                            break;
                        }
                        Some(libc::EINTR) => continue,
                        other => panic!("waiting on the child failed: {other:?}"),
                    }
                }
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
            assert!(ended, "the child was signalled rather than left to run");
            // Whether this one was *counted* is deliberately not asserted. The drop
            // signals and then looks, and `SIGKILL` landing before that look is the
            // kernel's business -- a child found already ended is correctly not counted.
            // The counting rule is tested where it can be asked a settled question.
            let _ = before;
        }

        /// Taken by the tests that read `nuppProcessUncollectedTotal`.
        ///
        /// It is one number for the whole process and the runner uses threads, so two
        /// tests comparing it before and after their own work will see each other's and
        /// fail on whichever order they happened to run in.
        static COUNTER_TESTS: std::sync::Mutex<()> = std::sync::Mutex::new(());

        fn counter_lock() -> std::sync::MutexGuard<'static, ()> {
            COUNTER_TESTS.lock().unwrap_or_else(|held| held.into_inner())
        }

        #[test]
        fn only_an_unresolved_child_is_counted() {
            let _counter = counter_lock();
            // The accounting rule, handed answers rather than racing for them.
            let before = nuppProcessUncollectedTotal();
            assert!(
                !account_for_test(Ok(Some(exited())), false),
                "a child known to have ended is not a leak"
            );
            assert!(
                !account_for_test(Err(std::io::Error::from_raw_os_error(libc::ECHILD)), false),
                "nor is one the host reaped itself"
            );
            assert_eq!(
                nuppProcessUncollectedTotal(),
                before,
                "and neither moved the count"
            );

            assert!(
                account_for_test(Ok(None), false),
                "a child still running when it was let go is counted"
            );
            assert_eq!(nuppProcessUncollectedTotal(), before + 1);
            let said = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(
                said.contains("signalled but had not ended"),
                "and reported as signalled; got {said:?}"
            );

            assert!(account_for_test(Ok(None), true), "as is one never signalled");
            assert_eq!(nuppProcessUncollectedTotal(), before + 2);
            let worse = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(
                worse.contains("still running"),
                "and reported apart, because nothing asked it to stop; got {worse:?}"
            );
        }

        /// A real exit status, which cannot be constructed directly.
        fn exited() -> std::process::ExitStatus {
            std::process::Command::new("sh")
                .args(["-c", "exit 0"])
                .status()
                .expect("a child that exits")
        }

        #[test]
        fn a_child_seen_to_exit_is_not_counted_when_it_is_let_go() {
            let _counter = counter_lock();
            // The ordinary resolved path, end to end: a caller that watched its child
            // finish and then dropped the handle without reaping has leaked nothing the
            // fallback can see, and must not be reported as though it had.
            let before = nuppProcessUncollectedTotal();
            let child = spawn("exit 0", &[]);
            let (code, _) = settle(child);
            assert_eq!(code, 0, "it exited on its own");
            // Destroyed without `nuppProcessReap`, which is the case being tested.
            unsafe { nuppProcessDestroy(child) };
            assert_eq!(
                nuppProcessUncollectedTotal(),
                before,
                "a child already seen to end is not a leak"
            );
        }

        #[test]
        fn a_write_to_a_child_that_stopped_reading_reports_gone() {
            // The case that kills the host when SIGPIPE is not contained. Reaching the
            // assertion at all is most of the test.
            let input = unsafe { broken_input_for_test() };
            let payload = vec![b'x'; 4096];
            let sent = unsafe { nuppProcessTryWrite(input, payload.as_ptr(), payload.len()) };
            assert_eq!(sent, GONE, "the far end going was reported, and the host survived");
            unsafe { nuppProcessCloseStream(input) };
            unsafe { nuppProcessStreamDestroy(input) };
        }

        #[test]
        fn a_killed_child_says_so() {
            let child = spawn("sleep 30", &[]);
            assert!(unsafe { nuppProcessKill(child, true) });
            let (code, killed) = settle(child);
            assert!(killed, "the child was ended rather than exiting");
            assert_eq!(code, 128 + 9, "and by the signal that was sent");
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn a_release_is_idempotent_and_never_unwinds() {
            let child = spawn("exit 0", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            settle(child);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED,
                "a released descriptor is released, and asking again is not an error");
            assert_eq!(unsafe { nuppProcessReap(child) }, RELEASED);
            assert_eq!(unsafe { nuppProcessReap(child) }, RELEASED);
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn reaping_a_running_child_is_refused_rather_than_guessed() {
            let child = spawn("sleep 30", &[]);
            assert_eq!(unsafe { nuppProcessReap(child) }, NOT_RELEASED,
                "it has not ended, so there is nothing to release");
            unsafe { nuppProcessKill(child, true) };
            settle(child);
            assert_eq!(unsafe { nuppProcessReap(child) }, RELEASED);
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn a_readiness_wait_refuses_a_null_it_was_told_to_watch() {
            // Skipping it would turn a binding that built its array wrongly into a wait
            // that watched fewer things than asked and returned on the timeout -- which
            // is indistinguishable from a quiet child, and would be chased for a long
            // time before anyone suspected the array.
            let empty: *mut NuppStream = std::ptr::null_mut();
            let answered = unsafe {
                nuppProcessWaitReady(&empty, 1, std::ptr::null(), 0, 10)
            };
            assert_eq!(answered, -1, "a null inside the count is refused");
            let said = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(said.contains("null stream"), "and says so; got {said:?}");
        }

        #[test]
        fn a_negative_timeout_does_not_wait_forever() {
            // `poll` reads a negative timeout as "no deadline". Every caller above is
            // bounded, and the usual way to arrive here negative is a deadline already
            // passed -- which asks for no wait at all.
            let started = std::time::Instant::now();
            let answered = unsafe {
                nuppProcessWaitReady(std::ptr::null(), 0, std::ptr::null(), 0, -1)
            };
            assert_eq!(answered, 0, "nothing was ready");
            assert!(
                started.elapsed() < std::time::Duration::from_millis(500),
                "and it returned rather than waiting for an event that cannot come"
            );
        }

        #[test]
        fn a_closed_stream_answers_but_does_not_carry_bytes() {
            // What "valid but no longer usable" actually amounts to, checked rather than
            // asserted -- a binding is about to be written against this sentence.
            let child = spawn("printf done", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            let input = unsafe { nuppProcessTakeStream(child, 0) };
            let _ = drain(out);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED);
            assert_eq!(unsafe { nuppProcessCloseStream(input) }, RELEASED);

            let mut room = [0u8; 16];
            assert_eq!(
                unsafe { nuppProcessTryRead(out, room.as_mut_ptr(), room.len()) },
                FAILED,
                "reading a closed stream is a failure, not an end of stream: there is a
                 difference between a child that finished and a caller that let go"
            );
            let payload = b"bytes";
            assert_eq!(
                unsafe { nuppProcessTryWrite(input, payload.as_ptr(), payload.len()) },
                FAILED,
                "and so is writing to one: `GONE` would claim the child's end had gone,
                 which closing this end says nothing about"
            );
            let closed_said = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(
                closed_said.contains("has been closed"),
                "and says it was closed rather than never writable, since those are
                 different mistakes to have made; got {closed_said:?}"
            );

            // The other way to reach the same mistake: a readable stream handed to a
            // write. That is a caller bug, and used to arrive as a synthesised broken
            // pipe -- indistinguishable from the real thing.
            let second = spawn("printf again", &[]);
            let readable = unsafe { nuppProcessTakeStream(second, 1) };
            assert_eq!(
                unsafe { nuppProcessTryWrite(readable, payload.as_ptr(), payload.len()) },
                FAILED,
                "a stream that cannot be written is a failure, not a broken pipe"
            );
            let said = unsafe { std::ffi::CStr::from_ptr(crate::nuppNativeError()) }
                .to_string_lossy()
                .into_owned();
            assert!(said.contains("not writable"), "and says which; got {said:?}");
            let _ = drain(readable);
            settle(second);
            unsafe { nuppProcessCloseStream(readable) };
            unsafe { nuppProcessReap(second) };
            unsafe { nuppProcessStreamDestroy(readable) };
            unsafe { nuppProcessDestroy(second) };

            settle(child);
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessStreamDestroy(input) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn a_closed_stream_may_still_be_named() {
            // Closing releases the descriptor and leaves the handle alive, so a drain
            // loop that names a stream it has finished with is asking a fair question.
            // Destroying is what makes a handle unnameable, and that is the caller's to
            // avoid -- a freed pointer cannot be told from a live one here.
            let child = spawn("printf done", &[]);
            let out = unsafe { nuppProcessTakeStream(child, 1) };
            assert!(!out.is_null());
            let _ = drain(out);
            assert_eq!(unsafe { nuppProcessCloseStream(out) }, RELEASED);
            let answered = unsafe { nuppProcessWaitReady(&out, 1, std::ptr::null(), 0, 10) };
            assert_eq!(answered, 0, "a closed stream is skipped, not an error");
            settle(child);
            unsafe { nuppProcessReap(child) };
            unsafe { nuppProcessStreamDestroy(out) };
            unsafe { nuppProcessDestroy(child) };
        }

        #[test]
        fn an_empty_readiness_wait_is_a_bounded_sleep() {
            let started = std::time::Instant::now();
            let ready = unsafe {
                nuppProcessWaitReady(std::ptr::null(), 0, std::ptr::null(), 0, 40)
            };
            assert_eq!(ready, 0, "nothing became ready, because nothing was named");
            assert!(started.elapsed().as_millis() >= 30, "and it really waited");
        }

        #[test]
        fn the_process_clock_is_monotonic() {
            let first = nuppProcessMonotonicMs();
            std::thread::yield_now();
            let second = nuppProcessMonotonicMs();
            assert!(first >= 0.0);
            assert!(second >= first);
        }
    }
