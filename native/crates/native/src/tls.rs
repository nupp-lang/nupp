//! ABI-v2 translation for Rustls sessions over Rust-owned network streams.

use super::net::NetSlice;
use nupp_native_abi::{Arena, Handle, Status};
use nupp_native_tls as transport;
use std::ptr;
use std::sync::{Arc, Mutex, OnceLock};

const PENDING: u32 = 0;
const READY: u32 = 1;
const READ_DATA: u32 = 0;
const READ_PENDING: u32 = 1;
const READ_EOF: u32 = 2;
const WRITE_ACCEPTED: u32 = 0;
const WRITE_PENDING: u32 = 1;
const WRITE_CLOSED: u32 = 2;
const PROTOCOL_MAX: usize = 255;

#[repr(C)]
pub struct TlsOptions {
    pub hostname: NetSlice,
    pub certificate: NetSlice,
    pub private_key: NetSlice,
    pub authority: NetSlice,
    pub protocols: NetSlice,
    pub authority_present: i32,
    pub server: i32,
    pub verify: i32,
}

fn sessions() -> &'static Mutex<Arena<Arc<transport::Session>>> {
    static SESSIONS: OnceLock<Mutex<Arena<Arc<transport::Session>>>> = OnceLock::new();
    SESSIONS.get_or_init(|| Mutex::new(Arena::new()))
}

fn session(raw: u64) -> Result<(Handle, Arc<transport::Session>), i32> {
    let handle = Handle::from_raw(raw);
    let arena = sessions()
        .lock()
        .map_err(|_| super::failed(Status::Internal, "TLS session store is poisoned"))?;
    arena
        .get(handle)
        .map(|value| (handle, Arc::clone(value)))
        .map_err(|status| super::failed(status, "TLS session handle is stale"))
}

unsafe fn bytes<'a>(slice: NetSlice, what: &str) -> Result<&'a [u8], i32> {
    super::input(slice.data, slice.length)
        .map_err(|_| super::failed(Status::InvalidArgument, &format!("{what} is null")))
}

unsafe fn text<'a>(slice: NetSlice, what: &str) -> Result<&'a str, i32> {
    // SAFETY: bytes validates the nested caller-owned slice.
    let value = unsafe { bytes(slice, what) }?;
    if value.contains(&0) {
        return Err(super::failed(
            Status::InvalidArgument,
            &format!("{what} contains an embedded NUL"),
        ));
    }
    std::str::from_utf8(value).map_err(|_| {
        super::failed(
            Status::InvalidArgument,
            &format!("{what} is not valid UTF-8"),
        )
    })
}

fn protocols(packed: &[u8]) -> Result<Vec<Vec<u8>>, i32> {
    if packed.is_empty() {
        return Ok(Vec::new());
    }
    if packed.last() != Some(&0) {
        return Err(super::failed(
            Status::InvalidArgument,
            "TLS protocol list is not NUL terminated",
        ));
    }
    let mut output = Vec::new();
    for protocol in packed[..packed.len() - 1].split(|byte| *byte == 0) {
        if protocol.is_empty() || protocol.len() > PROTOCOL_MAX {
            return Err(super::failed(
                Status::InvalidArgument,
                "TLS protocols must be 1 through 255 bytes",
            ));
        }
        output.push(protocol.to_vec());
    }
    Ok(output)
}

fn insert(value: Arc<transport::Session>, output: *mut u64) -> i32 {
    let handle = match sessions().lock() {
        Ok(mut arena) => match arena.insert(value) {
            Ok(handle) => handle,
            Err(status) => return super::failed(status, "TLS handle capacity is exhausted"),
        },
        Err(_) => return super::failed(Status::Internal, "TLS session store is poisoned"),
    };
    // SAFETY: Create checked output before calling insert.
    unsafe { output.write(handle.raw()) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// Consumes a plain network stream and creates a TLS session over it.
///
/// Once the outer pointers are validated, the stream handle is removed even
/// when nested options or TLS configuration are invalid. This makes ownership
/// transfer unambiguous at every failure point.
///
/// # Safety
/// `options` and `output` must point to caller-owned initialized storage. Every
/// nested slice must remain readable for this call.
pub unsafe extern "C" fn nuppNativeV2TlsCreate(
    raw_stream: u64,
    options: *const TlsOptions,
    output: *mut u64,
) -> i32 {
    if options.is_null() || output.is_null() {
        return super::failed(
            Status::InvalidArgument,
            "TLS create input or output is null",
        );
    }
    // SAFETY: output was checked above.
    unsafe { output.write(0) };
    let stream = match super::net::take_stream(raw_stream) {
        Ok(stream) => stream,
        Err(status) => return status,
    };
    // SAFETY: options was checked above.
    let options = unsafe { &*options };
    // SAFETY: the ABI promises nested slices remain readable for this call.
    let hostname = match unsafe { text(options.hostname, "TLS hostname") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: the ABI promises nested slices remain readable for this call.
    let certificate = match unsafe { bytes(options.certificate, "TLS certificate") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: the ABI promises nested slices remain readable for this call.
    let private_key = match unsafe { bytes(options.private_key, "TLS private key") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: the ABI promises nested slices remain readable for this call.
    let authority = match unsafe { bytes(options.authority, "TLS authority") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: the ABI promises nested slices remain readable for this call.
    let packed_protocols = match unsafe { bytes(options.protocols, "TLS protocols") } {
        Ok(value) => value,
        Err(status) => return status,
    };
    let protocols = match protocols(packed_protocols) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let value = if options.server != 0 {
        if options.verify != 0 || options.authority_present != 0 {
            return super::failed(
                Status::InvalidArgument,
                "TLS client-certificate verification is not supported",
            );
        }
        transport::Session::server(
            stream,
            transport::ServerOptions {
                certificate,
                private_key,
                protocols: &protocols,
            },
        )
    } else {
        if !certificate.is_empty() || !private_key.is_empty() {
            return super::failed(
                Status::InvalidArgument,
                "TLS client certificates are not supported",
            );
        }
        transport::Session::client(
            stream,
            transport::ClientOptions {
                hostname,
                authority: (options.authority_present != 0).then_some(authority),
                protocols: &protocols,
                verify: options.verify != 0,
            },
        )
    };
    match value {
        Ok(value) => insert(value, output),
        Err(error) => super::failed(Status::InvalidArgument, &error),
    }
}

#[unsafe(no_mangle)]
/// # Safety
/// `state` must be writable for one `u32`.
pub unsafe extern "C" fn nuppNativeV2TlsHandshake(raw: u64, state: *mut u32) -> i32 {
    if state.is_null() {
        return super::failed(Status::InvalidArgument, "TLS handshake output is null");
    }
    let (_, session) = match session(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let value = match session.handshake() {
        Ok(true) => READY,
        Ok(false) => PENDING,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    // SAFETY: state was checked above.
    unsafe { state.write(value) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// # Safety
/// Scalar outputs must be writable and output must have `capacity` bytes.
pub unsafe extern "C" fn nuppNativeV2TlsRead(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    state: *mut u32,
    length: *mut usize,
) -> i32 {
    if state.is_null() || length.is_null() || capacity == 0 || output.is_null() {
        return super::failed(Status::InvalidArgument, "TLS read output is invalid");
    }
    let (_, session) = match session(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (kind, bytes) = match session.try_read(capacity) {
        transport::Read::Data(bytes) => (READ_DATA, bytes),
        transport::Read::Pending => (READ_PENDING, Vec::new()),
        transport::Read::Eof => (READ_EOF, Vec::new()),
        transport::Read::Failed(error) => return super::failed(Status::Internal, &error),
    };
    if !bytes.is_empty() {
        // SAFETY: output has capacity bytes and the core respected that bound.
        unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len()) };
    }
    // SAFETY: scalar outputs were checked above.
    unsafe {
        state.write(kind);
        length.write(bytes.len());
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
/// # Safety
/// Input must remain readable and scalar outputs must be writable for this call.
pub unsafe extern "C" fn nuppNativeV2TlsWrite(
    raw: u64,
    input_data: *const u8,
    input_length: usize,
    state: *mut u32,
    accepted: *mut usize,
) -> i32 {
    if state.is_null() || accepted.is_null() {
        return super::failed(Status::InvalidArgument, "TLS write output is null");
    }
    let input = match super::input(input_data, input_length) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (_, session) = match session(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let (kind, count) = match session.try_write(input) {
        transport::Write::Accepted(count) => (WRITE_ACCEPTED, count),
        transport::Write::Pending => (WRITE_PENDING, 0),
        transport::Write::Closed => (WRITE_CLOSED, 0),
        transport::Write::Failed(error) => return super::failed(Status::Internal, &error),
    };
    // SAFETY: outputs were checked above.
    unsafe {
        state.write(kind);
        accepted.write(count);
    }
    Status::Ok.code()
}

fn boolean(raw: u64, output: *mut i32, operation: impl FnOnce(&transport::Session) -> bool) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "TLS boolean output is null");
    }
    let (_, session) = match session(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    // SAFETY: output was checked above.
    unsafe { output.write(i32::from(operation(&session))) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2TlsFlushed(raw: u64, output: *mut i32) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "TLS flushed output is null");
    }
    let (_, session) = match session(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let value = match session.flushed() {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    // SAFETY: output was checked above.
    unsafe { output.write(i32::from(value)) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2TlsCloseNotify(raw: u64, output: *mut i32) -> i32 {
    if output.is_null() {
        return super::failed(Status::InvalidArgument, "TLS close-notify output is null");
    }
    let (_, session) = match session(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let value = match session.close_notify() {
        Ok(value) => value,
        Err(error) => return super::failed(Status::Internal, &error),
    };
    // SAFETY: output was checked above.
    unsafe { output.write(i32::from(value)) };
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2TlsConnected(raw: u64, output: *mut i32) -> i32 {
    boolean(raw, output, transport::Session::is_connected)
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2TlsVerified(raw: u64, output: *mut i32) -> i32 {
    boolean(raw, output, transport::Session::is_verified)
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2TlsResumed(raw: u64, output: *mut i32) -> i32 {
    boolean(raw, output, transport::Session::is_resumed)
}

#[unsafe(no_mangle)]
/// Copies the negotiated ALPN protocol without a trailing NUL.
///
/// # Safety
/// `length` and `present` must be writable. A nonzero capacity requires a
/// writable output buffer.
pub unsafe extern "C" fn nuppNativeV2TlsProtocol(
    raw: u64,
    output: *mut u8,
    capacity: usize,
    length: *mut usize,
    present: *mut i32,
) -> i32 {
    if length.is_null() || present.is_null() || (capacity != 0 && output.is_null()) {
        return super::failed(Status::InvalidArgument, "TLS protocol output is invalid");
    }
    let (_, session) = match session(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let protocol = session.protocol();
    let bytes = protocol.as_deref().unwrap_or_default();
    // SAFETY: scalar outputs were checked above.
    unsafe {
        length.write(bytes.len());
        present.write(i32::from(protocol.is_some()));
    }
    if bytes.len() > capacity {
        return super::failed(Status::Capacity, "TLS protocol output is too small");
    }
    if !bytes.is_empty() {
        // SAFETY: the capacity check above proves the protocol fits.
        unsafe { ptr::copy_nonoverlapping(bytes.as_ptr(), output, bytes.len()) };
    }
    Status::Ok.code()
}

#[unsafe(no_mangle)]
pub extern "C" fn nuppNativeV2TlsRelease(raw: u64) -> i32 {
    let (handle, session) = match session(raw) {
        Ok(value) => value,
        Err(status) => return status,
    };
    session.close();
    match sessions().lock() {
        Ok(mut arena) => match arena.remove(handle) {
            Ok(_) => Status::Ok.code(),
            Err(status) => super::failed(status, "TLS session handle is stale"),
        },
        Err(_) => super::failed(Status::Internal, "TLS session store is poisoned"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn protocol_packing_is_strict() {
        assert_eq!(protocols(b"").unwrap(), Vec::<Vec<u8>>::new());
        assert_eq!(protocols(b"h2\0http/1.1\0").unwrap().len(), 2);
        assert!(protocols(b"h2").is_err());
        assert!(protocols(b"h2\0\0").is_err());
    }

    #[test]
    fn stale_tls_handles_are_rejected() {
        let mut output = 0;
        assert_eq!(
            boolean(0, &mut output, transport::Session::is_connected),
            Status::StaleHandle.code()
        );
    }

    #[test]
    fn failed_tls_creation_consumes_the_stream_handle() {
        let host = b"127.0.0.1";
        let listen = super::super::net::NetListenOptions {
            host: NetSlice {
                data: host.as_ptr(),
                length: host.len(),
            },
            port: 0,
            backlog: 4,
            reuse_port: 0,
        };
        let mut listener = 0;
        assert_eq!(
            unsafe { super::super::net::nuppNativeV2NetListenerCreate(&listen, &mut listener) },
            Status::Ok.code()
        );
        let mut port = 0;
        assert_eq!(
            unsafe { super::super::net::nuppNativeV2NetListenerPort(listener, &mut port) },
            Status::Ok.code()
        );
        let connect_options = super::super::net::NetConnectOptions {
            host: listen.host,
            port,
            timeout_ms: 5000,
        };
        let mut connect = 0;
        assert_eq!(
            unsafe {
                super::super::net::nuppNativeV2NetConnectCreate(&connect_options, &mut connect)
            },
            Status::Ok.code()
        );
        let mut client = 0;
        let mut server = 0;
        for _ in 0..5000 {
            let mut state = 0;
            let mut output = 0;
            if client == 0 {
                assert_eq!(
                    unsafe {
                        super::super::net::nuppNativeV2NetConnectPoll(
                            connect,
                            &mut state,
                            &mut output,
                        )
                    },
                    Status::Ok.code()
                );
                if state == 1 {
                    client = output;
                }
            }
            if server == 0 {
                assert_eq!(
                    unsafe {
                        super::super::net::nuppNativeV2NetListenerAccept(
                            listener,
                            &mut state,
                            &mut output,
                        )
                    },
                    Status::Ok.code()
                );
                if state == 0 {
                    server = output;
                }
            }
            if client != 0 && server != 0 {
                break;
            }
            nupp_native_net::wait_activity(Duration::from_millis(1));
        }
        assert_ne!(client, 0);
        assert_ne!(server, 0);

        let hostname = b"localhost";
        let options = TlsOptions {
            hostname: NetSlice {
                data: hostname.as_ptr(),
                length: hostname.len(),
            },
            certificate: NetSlice {
                data: ptr::null(),
                length: 0,
            },
            private_key: NetSlice {
                data: ptr::null(),
                length: 0,
            },
            authority: NetSlice {
                data: ptr::null(),
                length: 0,
            },
            protocols: NetSlice {
                data: ptr::null(),
                length: 0,
            },
            authority_present: 1,
            server: 0,
            verify: 1,
        };
        let mut tls = 123;
        assert_eq!(
            unsafe { nuppNativeV2TlsCreate(client, &options, &mut tls) },
            Status::InvalidArgument.code()
        );
        assert_eq!(tls, 0);
        assert_eq!(
            super::super::net::nuppNativeV2NetStreamRelease(client),
            Status::StaleHandle.code()
        );
        assert_eq!(
            super::super::net::nuppNativeV2NetStreamRelease(server),
            Status::Ok.code()
        );
        assert_eq!(
            super::super::net::nuppNativeV2NetConnectRelease(connect),
            Status::Ok.code()
        );
        assert_eq!(
            super::super::net::nuppNativeV2NetListenerRelease(listener),
            Status::Ok.code()
        );
    }
}
