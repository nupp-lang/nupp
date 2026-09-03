//! Rustls sessions over Rust-owned Nupp network streams.
//!
//! A session exclusively owns the `Arc<Stream>` passed at construction. The
//! facade removes the plain-stream handle before publishing a TLS handle, so
//! plaintext and encrypted operations can never race over one transport.

#![forbid(unsafe_code)]

use nupp_native_net::{Read as NetRead, Stream, Write as NetWrite};
use ring::digest::{Context as Digest, SHA256};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{CryptoProvider, WebPkiSupportedAlgorithms};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime, pem::PemObject};
use rustls::{
    ClientConfig, ClientConnection, Connection, DigitallySignedStruct, HandshakeKind,
    RootCertStore, ServerConfig, ServerConnection, SignatureScheme,
};
use std::collections::VecDeque;
use std::io::{self, Cursor, Read as _, Write as _};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

const CLIENT_CONFIGS_MAX: usize = 128;
const SERVER_CONFIGS_MAX: usize = 32;
const TLS_READ_CHUNK: usize = 64 * 1024;

/// Client policy copied into a Rustls configuration before this call returns.
pub struct ClientOptions<'a> {
    pub hostname: &'a str,
    /// `None` loads system roots. `Some` replaces them with exactly this PEM.
    pub authority: Option<&'a [u8]>,
    pub protocols: &'a [Vec<u8>],
    pub verify: bool,
}

/// Server policy copied into a Rustls configuration before this call returns.
pub struct ServerOptions<'a> {
    pub certificate: &'a [u8],
    pub private_key: &'a [u8],
    pub protocols: &'a [Vec<u8>],
}

#[derive(Debug, Eq, PartialEq)]
pub enum Read {
    Data(Vec<u8>),
    Pending,
    Eof,
    Failed(String),
}

#[derive(Debug, Eq, PartialEq)]
pub enum Write {
    Accepted(usize),
    Pending,
    Closed,
    Failed(String),
}

#[derive(Debug)]
struct InsecureVerifier {
    algorithms: WebPkiSupportedAlgorithms,
}

impl ServerCertVerifier for InsecureVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(message, cert, dss, &self.algorithms)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(message, cert, dss, &self.algorithms)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algorithms.supported_schemes()
    }
}

struct ConfigCache<T> {
    entries: VecDeque<([u8; 32], Arc<T>)>,
    capacity: usize,
}

impl<T> ConfigCache<T> {
    fn new(capacity: usize) -> Self {
        Self {
            entries: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    fn get(&mut self, key: &[u8; 32]) -> Option<Arc<T>> {
        let index = self.entries.iter().position(|(found, _)| found == key)?;
        let entry = self.entries.remove(index)?;
        let value = Arc::clone(&entry.1);
        self.entries.push_back(entry);
        Some(value)
    }

    fn insert(&mut self, key: [u8; 32], value: Arc<T>) {
        if self.entries.len() == self.capacity {
            self.entries.pop_front();
        }
        self.entries.push_back((key, value));
    }
}

fn client_configs() -> &'static Mutex<ConfigCache<ClientConfig>> {
    static CACHE: OnceLock<Mutex<ConfigCache<ClientConfig>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(ConfigCache::new(CLIENT_CONFIGS_MAX)))
}

fn server_configs() -> &'static Mutex<ConfigCache<ServerConfig>> {
    static CACHE: OnceLock<Mutex<ConfigCache<ServerConfig>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(ConfigCache::new(SERVER_CONFIGS_MAX)))
}

fn provider() -> Arc<CryptoProvider> {
    static PROVIDER: OnceLock<Arc<CryptoProvider>> = OnceLock::new();
    Arc::clone(PROVIDER.get_or_init(|| {
        let provider = rustls::crypto::ring::default_provider();
        let _ = provider.clone().install_default();
        Arc::new(provider)
    }))
}

fn digest(parts: &[&[u8]]) -> [u8; 32] {
    let mut digest = Digest::new(&SHA256);
    for part in parts {
        digest.update(&part.len().to_be_bytes());
        digest.update(part);
    }
    let value = digest.finish();
    let mut output = [0; 32];
    output.copy_from_slice(value.as_ref());
    output
}

fn packed_protocols(protocols: &[Vec<u8>]) -> Vec<u8> {
    let mut packed = Vec::new();
    for protocol in protocols {
        packed.extend_from_slice(&protocol.len().to_be_bytes());
        packed.extend_from_slice(protocol);
    }
    packed
}

fn certificates(pem: &[u8], what: &str) -> Result<Vec<CertificateDer<'static>>, String> {
    let certificates = CertificateDer::pem_slice_iter(pem)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("{what} could not be read: {error}"))?;
    if certificates.is_empty() {
        return Err(format!("{what} contains no certificates"));
    }
    Ok(certificates)
}

fn roots_from_pem(pem: &[u8]) -> Result<RootCertStore, String> {
    let mut roots = RootCertStore::empty();
    for certificate in certificates(pem, "the trusted certificates")? {
        roots
            .add(certificate)
            .map_err(|error| format!("the trusted certificate was rejected: {error}"))?;
    }
    Ok(roots)
}

fn configured_roots() -> Result<Option<RootCertStore>, String> {
    let certificate_file = std::env::var_os("SSL_CERT_FILE").filter(|value| !value.is_empty());
    let certificate_directory = std::env::var_os("SSL_CERT_DIR").filter(|value| !value.is_empty());
    if certificate_file.is_none() && certificate_directory.is_none() {
        return Ok(None);
    }

    let mut pem = Vec::new();
    let mut sources = Vec::new();
    if let Some(path) = certificate_file {
        let bytes = std::fs::read(&path).map_err(|error| {
            format!(
                "the configured certificate file {} could not be read: {error}",
                std::path::Path::new(&path).display()
            )
        })?;
        pem.extend_from_slice(&bytes);
        pem.push(b'\n');
        sources.push(std::path::PathBuf::from(path));
    }
    if let Some(path) = certificate_directory {
        let directory = std::path::Path::new(&path);
        let mut entries = std::fs::read_dir(directory)
            .map_err(|error| {
                format!(
                    "the configured certificate directory {} could not be read: {error}",
                    directory.display()
                )
            })?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|error| {
                format!(
                    "the configured certificate directory {} could not be read: {error}",
                    directory.display()
                )
            })?;
        entries.sort_by_key(std::fs::DirEntry::file_name);
        for entry in entries {
            let entry_path = entry.path();
            if entry_path.is_dir() {
                continue;
            }
            let bytes = std::fs::read(&entry_path).map_err(|error| {
                format!(
                    "the configured certificate {} could not be read: {error}",
                    entry_path.display()
                )
            })?;
            pem.extend_from_slice(&bytes);
            pem.push(b'\n');
            sources.push(entry_path);
        }
    }

    roots_from_pem(&pem).map(Some).map_err(|error| {
        let sources = sources
            .iter()
            .map(|path| path.display().to_string())
            .collect::<Vec<_>>()
            .join(", ");
        format!("{error} (loaded {} bytes from {sources})", pem.len())
    })
}

fn system_roots() -> Result<RootCertStore, String> {
    static ROOTS: OnceLock<Result<RootCertStore, String>> = OnceLock::new();
    ROOTS
        .get_or_init(|| {
            if let Some(roots) = configured_roots()? {
                return Ok(roots);
            }
            let result = rustls_native_certs::load_native_certs();
            if result.certs.is_empty() {
                let detail = result
                    .errors
                    .first()
                    .map(ToString::to_string)
                    .unwrap_or_else(|| "no certificates were found".to_owned());
                return Err(format!(
                    "the system certificate store could not be loaded: {detail}"
                ));
            }
            let mut roots = RootCertStore::empty();
            let (accepted, _ignored) = roots.add_parsable_certificates(result.certs);
            if accepted == 0 {
                return Err(
                    "the system certificate store contains no usable certificates".to_owned(),
                );
            }
            Ok(roots)
        })
        .clone()
}

fn client_config(
    stream: &Stream,
    options: &ClientOptions<'_>,
) -> Result<Arc<ClientConfig>, String> {
    let peer = stream.peer_addr()?;
    let port = peer.port().to_be_bytes();
    let fallback_hostname;
    let hostname = if options.hostname.is_empty() {
        fallback_hostname = peer.ip().to_string();
        fallback_hostname.as_str()
    } else {
        options.hostname
    };
    let protocols = packed_protocols(options.protocols);
    let verify = [u8::from(options.verify)];
    let authority_marker = [u8::from(options.authority.is_none())];
    let authority = options.authority.unwrap_or_default();
    let key = digest(&[
        hostname.as_bytes(),
        &port,
        &protocols,
        &verify,
        &authority_marker,
        authority,
    ]);
    let mut cache = client_configs()
        .lock()
        .map_err(|_| "the TLS client configuration cache is poisoned".to_owned())?;
    if let Some(config) = cache.get(&key) {
        return Ok(config);
    }

    let builder = ClientConfig::builder_with_provider(provider())
        .with_protocol_versions(&[&rustls::version::TLS13, &rustls::version::TLS12])
        .map_err(|error| format!("the TLS protocol versions are unavailable: {error}"))?;
    let mut config = if options.verify {
        let roots = match options.authority {
            Some(authority) => roots_from_pem(authority)?,
            None => system_roots()?,
        };
        builder.with_root_certificates(roots).with_no_client_auth()
    } else {
        let algorithms = provider().signature_verification_algorithms;
        builder
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(InsecureVerifier { algorithms }))
            .with_no_client_auth()
    };
    config.alpn_protocols = options.protocols.to_vec();
    let config = Arc::new(config);
    cache.insert(key, Arc::clone(&config));
    Ok(config)
}

fn server_config(options: &ServerOptions<'_>) -> Result<Arc<ServerConfig>, String> {
    let protocols = packed_protocols(options.protocols);
    let key = digest(&[options.certificate, options.private_key, &protocols]);
    let mut cache = server_configs()
        .lock()
        .map_err(|_| "the TLS server configuration cache is poisoned".to_owned())?;
    if let Some(config) = cache.get(&key) {
        return Ok(config);
    }
    let certificate = certificates(options.certificate, "the server certificate")?;
    let private_key = PrivateKeyDer::from_pem_slice(options.private_key)
        .map_err(|error| format!("the server private key could not be read: {error}"))?;
    let mut config = ServerConfig::builder_with_provider(provider())
        .with_protocol_versions(&[&rustls::version::TLS13, &rustls::version::TLS12])
        .map_err(|error| format!("the TLS protocol versions are unavailable: {error}"))?
        .with_no_client_auth()
        .with_single_cert(certificate, private_key)
        .map_err(|error| format!("the server certificate and key were rejected: {error}"))?;
    config.alpn_protocols = options.protocols.to_vec();
    let config = Arc::new(config);
    cache.insert(key, Arc::clone(&config));
    Ok(config)
}

struct State {
    connection: Connection,
    pending_tls: VecDeque<u8>,
    /// Transport bytes rustls has not taken yet. `read_tls` takes at most one
    /// record buffer per call and none while decrypted plaintext waits to be
    /// read, so what one transport read returned outlives one call to it.
    inbound: VecDeque<u8>,
    failed: Option<String>,
    closed: bool,
    verified: bool,
    require_alpn: bool,
    close_notify_sent: bool,
    transport_eof: bool,
}

/// One TLS session with exclusive access to its underlying network stream.
pub struct Session {
    stream: Arc<Stream>,
    state: Mutex<State>,
}

impl Session {
    pub fn client(stream: Arc<Stream>, options: ClientOptions<'_>) -> Result<Arc<Self>, String> {
        if options.verify && options.hostname.is_empty() {
            return Err("a verified TLS client needs a hostname".to_owned());
        }
        validate_protocols(options.protocols)?;
        let config = client_config(&stream, &options)?;
        let hostname = if options.hostname.is_empty() {
            stream.peer_addr()?.ip().to_string()
        } else {
            options.hostname.to_owned()
        };
        let name =
            ServerName::try_from(hostname).map_err(|_| "the TLS hostname is invalid".to_owned())?;
        let connection = ClientConnection::new(config, name)
            .map_err(|error| format!("the TLS client could not be created: {error}"))?;
        Ok(Arc::new(Self {
            stream,
            state: Mutex::new(State {
                connection: Connection::Client(connection),
                pending_tls: VecDeque::new(),
                inbound: VecDeque::new(),
                failed: None,
                closed: false,
                verified: options.verify,
                require_alpn: false,
                close_notify_sent: false,
                transport_eof: false,
            }),
        }))
    }

    pub fn server(stream: Arc<Stream>, options: ServerOptions<'_>) -> Result<Arc<Self>, String> {
        validate_protocols(options.protocols)?;
        let config = server_config(&options)?;
        let connection = ServerConnection::new(config)
            .map_err(|error| format!("the TLS server could not be created: {error}"))?;
        Ok(Arc::new(Self {
            stream,
            state: Mutex::new(State {
                connection: Connection::Server(connection),
                pending_tls: VecDeque::new(),
                inbound: VecDeque::new(),
                failed: None,
                closed: false,
                verified: false,
                require_alpn: !options.protocols.is_empty(),
                close_notify_sent: false,
                transport_eof: false,
            }),
        }))
    }

    pub fn handshake(&self) -> Result<bool, String> {
        let mut state = self.lock()?;
        state.drive(&self.stream)?;
        let complete = !state.connection.is_handshaking();
        if !complete && state.transport_eof {
            return Err(
                state.failed("the peer closed the connection during the TLS handshake".to_owned())
            );
        }
        if complete && state.require_alpn && state.connection.alpn_protocol().is_none() {
            return Err(state.failed(
                "the TLS peer shares none of the required application protocols".to_owned(),
            ));
        }
        Ok(complete)
    }

    pub fn try_read(&self, maximum: usize) -> Read {
        if maximum == 0 {
            return Read::Failed("a TLS read needs room for at least one byte".to_owned());
        }
        let mut state = match self.lock() {
            Ok(state) => state,
            Err(error) => return Read::Failed(error),
        };
        if state.connection.is_handshaking() {
            return Read::Failed("the TLS handshake has not finished".to_owned());
        }
        if let Err(error) = state.drive(&self.stream) {
            return Read::Failed(error);
        }
        let mut output = vec![0; maximum];
        match state.connection.reader().read(&mut output) {
            Ok(0) => Read::Eof,
            Ok(length) => {
                output.truncate(length);
                Read::Data(output)
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => Read::Pending,
            Err(error) => {
                let error = if error.kind() == io::ErrorKind::UnexpectedEof {
                    "the peer closed the connection without close_notify".to_owned()
                } else {
                    format!("could not read TLS plaintext: {error}")
                };
                state.fail(error.clone());
                Read::Failed(error)
            }
        }
    }

    pub fn try_write(&self, bytes: &[u8]) -> Write {
        let mut state = match self.lock() {
            Ok(state) => state,
            Err(error) => return Write::Failed(error),
        };
        if state.connection.is_handshaking() {
            return Write::Failed("the TLS handshake has not finished".to_owned());
        }
        if state.closed {
            return Write::Closed;
        }
        if let Err(error) = state.drive(&self.stream) {
            return Write::Failed(error);
        }
        let accepted = match state.connection.writer().write(bytes) {
            // rustls answers zero rather than WouldBlock once its outbound
            // record buffer is full. Nothing was taken, so this is a wait for
            // the transport to drain, not progress.
            Ok(0) if !bytes.is_empty() => {
                if let Err(error) = state.drive(&self.stream) {
                    return Write::Failed(error);
                }
                return Write::Pending;
            }
            Ok(accepted) => accepted,
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => return Write::Pending,
            Err(error) => {
                let error = format!("could not write TLS plaintext: {error}");
                state.fail(error.clone());
                return Write::Failed(error);
            }
        };
        if let Err(error) = state.drive(&self.stream) {
            return Write::Failed(error);
        }
        Write::Accepted(accepted)
    }

    /// Queues close_notify and drives it into the transport write queue.
    pub fn close_notify(&self) -> Result<bool, String> {
        let mut state = self.lock()?;
        if state.closed {
            return Ok(false);
        }
        if !state.close_notify_sent {
            state.connection.send_close_notify();
            state.close_notify_sent = true;
        }
        state.drive(&self.stream)?;
        Ok(!state.connection.wants_write()
            && state.pending_tls.is_empty()
            && self.stream.pending_write() == 0)
    }

    /// Whether all encrypted output has reached the operating-system socket.
    pub fn flushed(&self) -> Result<bool, String> {
        let mut state = self.lock()?;
        state.drive(&self.stream)?;
        Ok(!state.connection.wants_write()
            && state.pending_tls.is_empty()
            && self.stream.pending_write() == 0)
    }

    pub fn close(&self) {
        let close_immediately = if let Ok(mut state) = self.state.lock() {
            if state.closed {
                return;
            }
            state.closed = true;
            // `close` is the cancellation/release operation. Only a caller
            // that already queued close_notify selected authenticated graceful
            // shutdown; an ordinary close must retire handshake and transport
            // work immediately.
            !state.close_notify_sent
        } else {
            true
        };
        if close_immediately {
            self.stream.close();
        } else {
            self.stream.close_gracefully(Duration::from_secs(1));
        }
    }

    pub fn is_connected(&self) -> bool {
        let Ok(state) = self.state.lock() else {
            return false;
        };
        !state.closed && state.failed.is_none() && !self.stream.snapshot().closed
    }

    pub fn is_verified(&self) -> bool {
        let Ok(state) = self.state.lock() else {
            return false;
        };
        state.verified && !state.connection.is_handshaking() && state.failed.is_none()
    }

    pub fn is_resumed(&self) -> bool {
        let Ok(state) = self.state.lock() else {
            return false;
        };
        state.connection.handshake_kind() == Some(HandshakeKind::Resumed)
    }

    pub fn protocol(&self) -> Option<Vec<u8>> {
        let state = self.state.lock().ok()?;
        state.connection.alpn_protocol().map(<[u8]>::to_vec)
    }

    pub fn pending_write(&self) -> usize {
        let Ok(state) = self.state.lock() else {
            return 0;
        };
        state.pending_tls.len() + self.stream.pending_write()
    }

    fn lock(&self) -> Result<std::sync::MutexGuard<'_, State>, String> {
        let state = self
            .state
            .lock()
            .map_err(|_| "the TLS session state is poisoned".to_owned())?;
        if state.closed {
            return Err("the TLS session is closed".to_owned());
        }
        if let Some(error) = &state.failed {
            return Err(error.clone());
        }
        Ok(state)
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        let explicitly_closed = self.state.lock().map(|state| state.closed).unwrap_or(false);
        if !explicitly_closed {
            self.stream.close();
        }
    }
}

impl State {
    fn fail(&mut self, error: String) {
        self.failed = Some(error);
    }

    fn drive(&mut self, stream: &Stream) -> Result<(), String> {
        for _ in 0..64 {
            let mut progressed = self.flush_tls(stream)?;
            // rustls stops wanting transport bytes while plaintext it already
            // decrypted waits to be read. That is backpressure on the peer,
            // not a failure, so the transport is left alone until it wants
            // more, and bytes it has not taken stay buffered here.
            if self.connection.wants_read() {
                if self.inbound.is_empty() && !self.transport_eof {
                    match stream.try_read(TLS_READ_CHUNK) {
                        NetRead::Data(bytes) => self.inbound.extend(bytes),
                        NetRead::Pending => {}
                        NetRead::Eof => {
                            let mut input = Cursor::new(&[]);
                            self.connection.read_tls(&mut input).map_err(|error| {
                                self.failed(format!("could not finish TLS input: {error}"))
                            })?;
                            self.transport_eof = true;
                        }
                        NetRead::Failed(error) => {
                            return Err(self.failed(format!("the TLS transport failed: {error}")));
                        }
                    }
                }
                progressed |= self.consume_inbound()?;
            }
            progressed |= self.flush_tls(stream)?;
            if !progressed {
                return Ok(());
            }
        }
        Ok(())
    }

    /// Feeds buffered transport bytes to rustls until it takes no more, which
    /// is when the buffer is empty or decrypted plaintext is waiting.
    fn consume_inbound(&mut self) -> Result<bool, String> {
        let mut progressed = false;
        while !self.inbound.is_empty() && self.connection.wants_read() {
            let taken = {
                let mut input = Cursor::new(&*self.inbound.make_contiguous());
                self.connection.read_tls(&mut input)
            };
            let taken = match taken {
                Ok(count) => count,
                // The received-plaintext buffer is full: a reader will make room.
                Err(error) if error.kind() == io::ErrorKind::Other => break,
                Err(error) => {
                    return Err(self.failed(format!("could not read TLS records: {error}")));
                }
            };
            if taken == 0 {
                break;
            }
            self.inbound.drain(..taken);
            self.connection
                .process_new_packets()
                .map_err(|error| self.failed(format!("could not process TLS records: {error}")))?;
            progressed = true;
        }
        Ok(progressed)
    }

    fn flush_tls(&mut self, stream: &Stream) -> Result<bool, String> {
        let mut progressed = false;
        if !self.pending_tls.is_empty() {
            let pending = self.pending_tls.make_contiguous();
            match stream.try_write(pending) {
                NetWrite::Accepted(count) => {
                    self.pending_tls.drain(..count);
                    progressed = count != 0;
                }
                NetWrite::Pending => return Ok(false),
                NetWrite::Closed => {
                    return Err(self.failed("the TLS transport is closed".to_owned()));
                }
                NetWrite::Failed(error) => {
                    return Err(self.failed(format!("could not write TLS records: {error}")));
                }
            }
        }
        if self.pending_tls.is_empty() && self.connection.wants_write() {
            let mut output = Vec::new();
            self.connection
                .write_tls(&mut output)
                .map_err(|error| self.failed(format!("could not encode TLS records: {error}")))?;
            self.pending_tls.extend(output);
            progressed = true;
        }
        Ok(progressed)
    }

    fn failed(&mut self, error: String) -> String {
        self.fail(error.clone());
        error
    }
}

fn validate_protocols(protocols: &[Vec<u8>]) -> Result<(), String> {
    for (index, protocol) in protocols.iter().enumerate() {
        if protocol.is_empty() || protocol.len() > 255 {
            return Err(format!(
                "TLS protocol {} must be 1 through 255 bytes",
                index + 1
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use nupp_native_net::{
        ConnectPoll, connect_tcp, listen_tcp, poll_activity, wait_activity, wait_activity_since,
    };
    use std::time::{Duration, Instant};

    const CERTIFICATE: &[u8] = include_bytes!("../../../../tests/data/localhost-cert.pem");
    const PRIVATE_KEY: &[u8] = include_bytes!("../../../../tests/data/localhost-key.pem");

    fn pair(listener: &Arc<nupp_native_net::Listener>) -> (Arc<Stream>, Arc<Stream>) {
        let connect = connect_tcp("127.0.0.1", listener.port(), Duration::from_secs(5)).unwrap();
        let mut client = None;
        let mut server = None;
        for _ in 0..5000 {
            if client.is_none() {
                match connect.poll() {
                    ConnectPoll::Pending => {}
                    ConnectPoll::Connected(stream) => client = Some(stream),
                    ConnectPoll::Failed(error) => panic!("connect failed: {error}"),
                }
            }
            if server.is_none() {
                server = listener.try_accept().unwrap();
            }
            if client.is_some() && server.is_some() {
                let Some(client) = client.take() else {
                    unreachable!()
                };
                let Some(server) = server.take() else {
                    unreachable!()
                };
                return (client, server);
            }
            wait_activity(Duration::from_millis(1));
        }
        panic!("the loopback connection did not finish")
    }

    fn sessions(
        listener: &Arc<nupp_native_net::Listener>,
        client_protocols: &[Vec<u8>],
        server_protocols: &[Vec<u8>],
        hostname: &str,
        verify: bool,
    ) -> (Arc<Session>, Arc<Session>) {
        let (client_stream, server_stream) = pair(listener);
        let server = Session::server(
            server_stream,
            ServerOptions {
                certificate: CERTIFICATE,
                private_key: PRIVATE_KEY,
                protocols: server_protocols,
            },
        )
        .unwrap();
        let client = Session::client(
            client_stream,
            ClientOptions {
                hostname,
                authority: verify.then_some(CERTIFICATE),
                protocols: client_protocols,
                verify,
            },
        )
        .unwrap();
        (client, server)
    }

    fn shake(client: &Session, server: &Session) -> Result<(), String> {
        let mut client_done = false;
        let mut server_done = false;
        for _ in 0..10000 {
            if !client_done {
                client_done = client.handshake()?;
            }
            if !server_done {
                server_done = server.handshake()?;
            }
            if client_done && server_done {
                return Ok(());
            }
            wait_activity(Duration::from_millis(1));
        }
        Err("the TLS handshake did not finish".to_owned())
    }

    fn read_eventually(session: &Session, maximum: usize) -> Read {
        for _ in 0..5000 {
            let result = session.try_read(maximum);
            if result != Read::Pending {
                return result;
            }
            wait_activity(Duration::from_millis(1));
        }
        Read::Failed("the TLS read did not finish".to_owned())
    }

    fn write_all(session: &Session, bytes: &[u8]) {
        let mut at = 0;
        for _ in 0..50000 {
            if at == bytes.len() {
                return;
            }
            match session.try_write(&bytes[at..]) {
                Write::Accepted(count) => at += count,
                Write::Pending => {
                    wait_activity(Duration::from_millis(1));
                }
                other => panic!("the TLS write did not finish: {other:?}"),
            }
        }
        panic!("the TLS write did not finish")
    }

    fn read_all(session: &Session, total: usize, maximum: usize) -> Vec<u8> {
        let mut received = Vec::with_capacity(total);
        while received.len() < total {
            match read_eventually(session, maximum) {
                Read::Data(bytes) => received.extend(bytes),
                other => panic!("the TLS read did not finish: {other:?}"),
            }
        }
        received
    }

    #[test]
    fn one_transport_read_may_carry_many_records() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();
        let (client, server) = sessions(&listener, &[], &[], "localhost", true);
        shake(&client, &server).unwrap();
        let payload: Vec<u8> = (0..20_480u32).map(|value| (value % 251) as u8).collect();
        write_all(&server, &payload);
        // Let the whole flight reach the client's transport before it is
        // driven once, so one transport read carries every record.
        wait_until(|| server.pending_write() == 0, "the server flush");
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(read_all(&client, payload.len(), 64 * 1024), payload);
    }

    #[test]
    fn a_reader_slower_than_the_records_is_backpressure_not_failure() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();
        let (client, server) = sessions(&listener, &[], &[], "localhost", true);
        shake(&client, &server).unwrap();
        let mut payload = Vec::new();
        for round in 0..64u8 {
            let record = vec![round; 1000];
            write_all(&server, &record);
            payload.extend(record);
        }
        wait_until(|| server.pending_write() == 0, "the server flush");
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(read_all(&client, payload.len(), 16), payload);
    }

    #[test]
    fn a_full_outbound_buffer_is_pending_rather_than_zero_progress() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();
        let (client, server) = sessions(&listener, &[], &[], "localhost", true);
        shake(&client, &server).unwrap();
        let chunk = vec![7u8; 64 * 1024];
        for _ in 0..4096 {
            match client.try_write(&chunk) {
                Write::Accepted(0) => panic!("a full buffer reported zero bytes as progress"),
                Write::Accepted(_) => {}
                Write::Pending => {
                    drop(server);
                    return;
                }
                other => panic!("the TLS write failed: {other:?}"),
            }
        }
        panic!("a peer that never reads did not make the writer pend");
    }

    fn wait_until(mut condition: impl FnMut() -> bool, what: &str) {
        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if condition() {
                return;
            }
            let seen = poll_activity();
            if condition() {
                return;
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            assert!(!remaining.is_zero(), "timed out waiting for {what}");
            wait_activity_since(seen, remaining);
        }
    }

    fn assert_cancelled(session: &Session, peer: &Session) {
        session.close();
        let snapshot = session.stream.snapshot();
        assert!(
            snapshot.closed,
            "cancellation closes the transport immediately"
        );
        assert_eq!(snapshot.pending_write, 0);
        assert!(!session.is_connected());
        assert_eq!(
            session.handshake().unwrap_err(),
            "the TLS session is closed"
        );

        peer.close();
        assert!(peer.stream.snapshot().closed);
        assert_eq!(peer.pending_write(), 0);
    }

    #[test]
    fn verified_handshake_carries_bytes_and_negotiates_alpn() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();
        let client_protocols = vec![b"h2".to_vec(), b"http/1.1".to_vec()];
        let server_protocols = vec![b"http/1.1".to_vec(), b"h2".to_vec()];
        let (client, server) = sessions(
            &listener,
            &client_protocols,
            &server_protocols,
            "localhost",
            true,
        );
        shake(&client, &server).unwrap();
        assert!(client.is_verified());
        assert_eq!(client.protocol().as_deref(), Some(b"http/1.1".as_slice()));
        assert_eq!(client.try_write(b"secret"), Write::Accepted(6));
        assert_eq!(read_eventually(&server, 64), Read::Data(b"secret".to_vec()));
        client.close();
        server.close();
        listener.close();
    }

    #[test]
    fn wrong_hostname_is_rejected_but_insecure_mode_is_explicit() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();
        let (client, server) = sessions(&listener, &[], &[], "example.com", true);
        assert!(shake(&client, &server).is_err());
        client.close();
        server.close();

        let (client, server) = sessions(&listener, &[], &[], "", false);
        shake(&client, &server).unwrap();
        assert!(!client.is_verified());
        assert_eq!(
            client.try_write(b"accepted deliberately"),
            Write::Accepted(21)
        );
        assert_eq!(
            read_eventually(&server, 64),
            Read::Data(b"accepted deliberately".to_vec())
        );
        client.close();
        server.close();
        listener.close();
    }

    #[test]
    fn close_notify_is_clean_but_transport_eof_is_truncation() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();
        let (client, server) = sessions(&listener, &[], &[], "localhost", true);
        shake(&client, &server).unwrap();
        for _ in 0..5000 {
            if client.close_notify().unwrap() {
                break;
            }
            server.handshake().unwrap();
            wait_activity(Duration::from_millis(1));
        }
        assert_eq!(read_eventually(&server, 64), Read::Eof);
        client.close();
        server.close();

        let (client, server) = sessions(&listener, &[], &[], "localhost", true);
        shake(&client, &server).unwrap();
        server.stream.close();
        match read_eventually(&client, 64) {
            Read::Failed(error) => {
                assert!(error.contains("without close_notify"), "{error}")
            }
            other => panic!("truncated TLS returned {other:?}"),
        }
        client.close();
        server.close();
        listener.close();
    }

    #[test]
    fn a_client_resumes_a_cached_session() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();
        let protocols = vec![b"h2".to_vec()];
        let (first_client, first_server) =
            sessions(&listener, &protocols, &protocols, "localhost", true);
        shake(&first_client, &first_server).unwrap();
        assert_eq!(first_server.try_write(b"ticket"), Write::Accepted(6));
        assert_eq!(
            read_eventually(&first_client, 64),
            Read::Data(b"ticket".to_vec())
        );
        for _ in 0..50 {
            first_client.handshake().unwrap();
            first_server.handshake().unwrap();
            wait_activity(Duration::from_millis(1));
        }
        first_client.close();
        first_server.close();

        let (second_client, second_server) =
            sessions(&listener, &protocols, &protocols, "localhost", true);
        shake(&second_client, &second_server).unwrap();
        assert!(second_client.is_resumed());
        second_client.close();
        second_server.close();
        listener.close();
    }

    #[test]
    fn invalid_configuration_is_rejected_before_transport_use() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();
        let (client, _) = pair(&listener);
        assert!(
            Session::client(
                Arc::clone(&client),
                ClientOptions {
                    hostname: "localhost",
                    authority: Some(b""),
                    protocols: &[],
                    verify: true,
                },
            )
            .is_err()
        );
        assert!(!client.snapshot().closed);
        listener.close();
        client.close();
    }

    #[test]
    fn cancellation_retires_every_meaningful_handshake_phase() {
        let listener = listen_tcp("127.0.0.1", 0, 16, false).unwrap();

        // Before either endpoint has emitted a handshake flight.
        let (client, server) = sessions(&listener, &[], &[], "", false);
        assert_cancelled(&client, &server);

        // After the client has emitted ClientHello and is awaiting the server.
        let (client, server) = sessions(&listener, &[], &[], "", false);
        assert!(!client.handshake().unwrap());
        assert_cancelled(&client, &server);

        // After the server has consumed ClientHello and emitted its response.
        let (client, server) = sessions(&listener, &[], &[], "", false);
        assert!(!client.handshake().unwrap());
        wait_until(
            || server.stream.snapshot().buffered_read != 0,
            "the client handshake flight",
        );
        assert!(!server.handshake().unwrap());
        assert_cancelled(&client, &server);

        // After the client has authenticated the server flight and emitted its
        // Finished, while the server still has to consume that final flight.
        let (client, server) = sessions(&listener, &[], &[], "", false);
        assert!(!client.handshake().unwrap());
        wait_until(
            || server.stream.snapshot().buffered_read != 0,
            "the client handshake flight",
        );
        assert!(!server.handshake().unwrap());
        wait_until(
            || client.stream.snapshot().buffered_read != 0,
            "the server handshake flight",
        );
        assert!(client.handshake().unwrap());
        assert_cancelled(&client, &server);

        listener.close();
    }

    #[test]
    fn configured_certificate_file_is_a_root_store() {
        let mut roots = Vec::new();
        roots.extend_from_slice(CERTIFICATE);
        roots.push(b'\n');
        assert!(!roots_from_pem(&roots).unwrap().is_empty());
    }
}
