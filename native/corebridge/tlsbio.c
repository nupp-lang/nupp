/**
 * @file
 * @brief Drives the pinned OpenSSL engine using bounded memory BIOs.
 */

#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#else
#define WIN32_LEAN_AND_MEAN
#endif

#include "tlsbio.h"
#include <uv.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/ssl.h>
#include <openssl/x509v3.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#elif defined(_WIN32)
#include <wincrypt.h>
#ifndef S_ISDIR
#define S_ISDIR(mode) (((mode) & _S_IFMT) == _S_IFDIR)
#define S_ISREG(mode) (((mode) & _S_IFMT) == _S_IFREG)
#endif
#endif

enum { WIRE_WINDOW = 32768, ERROR_ROOM = 256, ALPN_LIMIT = UINT16_MAX };

enum { CACHE_ROOM = 24, CONFIG_DIGEST = 32 };

typedef struct TlsConfig {
  unsigned char digest[CONFIG_DIGEST];
  SSL_CTX *context;
  SSL_SESSION *session;
} TlsConfig;

static _Thread_local TlsConfig configurations[CACHE_ROOM];
static _Thread_local size_t replacement;

struct NuppTls {
  SSL *ssl;
  BIO *network;
  unsigned char *protocols;
  unsigned int protocol_size;
  size_t writing;
  int verify, failed, input_closed, alert_queued;
  char plaintext[NUPP_TLS_WINDOW];
  char failure[ERROR_ROOM];
};

static size_t smaller (size_t left, size_t right) {
  return left < right ? left : right;
}

static int fail (NuppTls *tls, const char *reason) {
  if (!tls->failed) {
    unsigned long claim = ERR_peek_last_error();
    tls->failed = 1;

    if (claim) {
      ERR_error_string_n(claim, tls->failure, sizeof(tls->failure));
    }
    else {
      snprintf(tls->failure, sizeof(tls->failure), "%s", reason);
    }
  }

  return NUPP_TLS_ERROR;
}

static int stepstatus (NuppTls *tls, int result, const char *reason) {
  switch (SSL_get_error(tls->ssl, result)) {
    case SSL_ERROR_WANT_READ:
    case SSL_ERROR_WANT_WRITE:
      return NUPP_TLS_AGAIN;
    case SSL_ERROR_ZERO_RETURN:
      return 0;
    default:
      return fail(tls, reason);
  }
}

/* Encrypted private keys cannot ask for a password on the reactor thread. */
static int nopassword (char *out, int room, int writing, void *context) {
  (void)out;
  (void)room;
  (void)writing;
  (void)context;

  return 0;
}

static BIO *pem (NuppTlsBytes bytes) {
  return bytes.data && bytes.size && bytes.size <= INT_MAX
             ? BIO_new_mem_buf(bytes.data, (int)bytes.size)
             : NULL;
}

static int load_certificates (SSL_CTX *ctx, BIO *bio, int server) {
  if (!bio) {
    return -1;
  }

  STACK_OF(X509_INFO) *items =
      PEM_X509_INFO_read_bio(bio, NULL, nopassword, NULL);
  BIO_free(bio);

  if (!items) {
    return -1;
  }

  int ok = 1, count = 0;

  for (int i = 0; ok && i < sk_X509_INFO_num(items); i++) {
    X509 *certificate = sk_X509_INFO_value(items, i)->x509;

    if (!certificate) {
      continue;
    }

    if (server) {
      ok = count ? SSL_CTX_add1_chain_cert(ctx, certificate)
                 : SSL_CTX_use_certificate(ctx, certificate);
    }
    else {
      ok = X509_STORE_add_cert(SSL_CTX_get_cert_store(ctx), certificate);
    }

    count++;
  }

  sk_X509_INFO_pop_free(items, X509_INFO_free);

  return ok ? count : -1;
}

static int certificates (SSL_CTX *ctx, NuppTlsBytes bytes, int server) {
  return load_certificates(ctx, pem(bytes), server) > 0;
}

static int identity (SSL_CTX *ctx, const NuppTlsOptions *options) {
  if (!certificates(ctx, options->certificate, 1)) {
    return 0;
  }

  BIO *bio = pem(options->private_key);

  if (!bio) {
    return 0;
  }

  EVP_PKEY *key = PEM_read_bio_PrivateKey(bio, NULL, nopassword, NULL);
  BIO_free(bio);
  int ok =
      key && SSL_CTX_use_PrivateKey(ctx, key) && SSL_CTX_check_private_key(ctx);
  EVP_PKEY_free(key);

  return ok;
}

#if defined(__APPLE__) || defined(_WIN32)
static int verified_name (X509_STORE_CTX *store, X509 *certificate) {
  X509_VERIFY_PARAM *parameters = X509_STORE_CTX_get0_param(store);
  const char *hostname = X509_VERIFY_PARAM_get0_host(parameters, 0);

  if (hostname) {
    return X509_check_host(certificate, hostname, 0,
                           X509_CHECK_FLAG_NEVER_CHECK_SUBJECT |
                               X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS,
                           NULL) == 1;
  }

  char *address = X509_VERIFY_PARAM_get1_ip_asc(parameters);
  int accepted = address && X509_check_ip_asc(certificate, address, 0) == 1;
  OPENSSL_free(address);

  return accepted;
}

#ifdef __APPLE__
static int add_certificate (CFMutableArrayRef chain, X509 *certificate) {
  unsigned char *der = NULL;
  int size = i2d_X509(certificate, &der);
  CFDataRef bytes = size > 0 ? CFDataCreate(NULL, der, size) : NULL;
  OPENSSL_free(der);

  if (!bytes) {
    return 0;
  }

  SecCertificateRef entry = SecCertificateCreateWithData(NULL, bytes);
  CFRelease(bytes);

  if (!entry) {
    return 0;
  }

  CFArrayAppendValue(chain, entry);
  CFRelease(entry);

  return 1;
}

static int verify_platform_chain (X509_STORE_CTX *store, X509 *certificate) {
  CFMutableArrayRef chain =
      CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);

  if (!chain) {
    return 0;
  }

  int ok = add_certificate(chain, certificate);
  STACK_OF(X509) *untrusted = X509_STORE_CTX_get0_untrusted(store);

  for (int i = 0; ok && i < sk_X509_num(untrusted); i++) {
    X509 *entry = sk_X509_value(untrusted, i);

    if (entry != certificate) {
      ok = add_certificate(chain, entry);
    }
  }

  SecPolicyRef policy = ok ? SecPolicyCreateSSL(true, NULL) : NULL;
  SecTrustRef trust = NULL;
  ok = policy &&
       SecTrustCreateWithCertificates(chain, policy, &trust) == errSecSuccess &&
       SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess &&
       SecTrustEvaluateWithError(trust, NULL);

  if (trust) {
    CFRelease(trust);
  }

  if (policy) {
    CFRelease(policy);
  }

  CFRelease(chain);

  return ok;
}
#else
static int verify_platform_chain (X509_STORE_CTX *store, X509 *certificate) {
  HCERTSTORE intermediate =
      CertOpenStore(CERT_STORE_PROV_MEMORY, 0, 0, 0, NULL);

  if (!intermediate) {
    return 0;
  }

  unsigned char *der = NULL;
  int size = i2d_X509(certificate, &der);
  PCCERT_CONTEXT leaf =
      size > 0
          ? CertCreateCertificateContext(X509_ASN_ENCODING, der, (DWORD)size)
          : NULL;
  OPENSSL_free(der);
  int ok = leaf != NULL;
  STACK_OF(X509) *untrusted = X509_STORE_CTX_get0_untrusted(store);

  for (int i = 0; ok && i < sk_X509_num(untrusted); i++) {
    X509 *entry = sk_X509_value(untrusted, i);

    if (certificate != entry) {
      der = NULL;
      size = i2d_X509(entry, &der);
      ok = size > 0 && CertAddEncodedCertificateToStore(
                           intermediate, X509_ASN_ENCODING, der, (DWORD)size,
                           CERT_STORE_ADD_USE_EXISTING, NULL);
      OPENSSL_free(der);
    }
  }

  LPSTR server = szOID_PKIX_KP_SERVER_AUTH;
  CERT_CHAIN_PARA parameters = {
      .cbSize = sizeof(parameters),
      .RequestedUsage = {.dwType = USAGE_MATCH_TYPE_AND,
                         .Usage = {1, &server}}};
  PCCERT_CHAIN_CONTEXT chain = NULL;
  ok = ok && CertGetCertificateChain(
                 NULL, leaf, NULL, intermediate, &parameters,
                 CERT_CHAIN_CACHE_ONLY_URL_RETRIEVAL, NULL, &chain);

  if (ok) {
    SSL_EXTRA_CERT_CHAIN_POLICY_PARA ssl = {.cbSize = sizeof(ssl),
                                            .dwAuthType = AUTHTYPE_SERVER};
    CERT_CHAIN_POLICY_PARA rules = {.cbSize = sizeof(rules),
                                    .pvExtraPolicyPara = &ssl};
    CERT_CHAIN_POLICY_STATUS result = {.cbSize = sizeof(result)};
    ok = CertVerifyCertificateChainPolicy(CERT_CHAIN_POLICY_SSL, chain, &rules,
                                          &result) &&
         !result.dwError;
  }

  if (chain) {
    CertFreeCertificateChain(chain);
  }

  if (leaf) {
    CertFreeCertificateContext(leaf);
  }

  CertCloseStore(intermediate, 0);

  return ok;
}
#endif

static int verify_platform (X509_STORE_CTX *store, void *context) {
  (void)context;
  X509 *certificate = X509_STORE_CTX_get0_cert(store);
  int accepted = certificate && verified_name(store, certificate) &&
                 verify_platform_chain(store, certificate);
  X509_STORE_CTX_set_error(store,
                           accepted ? X509_V_OK : X509_V_ERR_CERT_REJECTED);

  return accepted;
}
#endif

static int load_root_file (SSL_CTX *ctx, const char *path, int skip_directory) {
  uv_fs_t file = {0};
  int status = uv_fs_stat(NULL, &file, path, NULL);
  uint64_t mode = file.statbuf.st_mode;
  uv_fs_req_cleanup(&file);

  if (status < 0) {
    return -1;
  }

  if (skip_directory && S_ISDIR(mode)) {
    return 0;
  }

  return S_ISREG(mode) ? load_certificates(ctx, BIO_new_file(path, "rb"), 0)
                       : -1;
}

static int load_root_directory (SSL_CTX *ctx, const char *directory) {
  uv_fs_t scan = {0};
  int status = uv_fs_scandir(NULL, &scan, directory, 0, NULL);
  int found = 0;
  size_t base = strlen(directory);
  uv_dirent_t entry;

  while (status >= 0 && (status = uv_fs_scandir_next(&scan, &entry)) == 0) {
    size_t name = strlen(entry.name);
    char *path = base <= SIZE_MAX - name - 2 ? malloc(base + name + 2) : NULL;

    if (!path) {
      status = UV_ENOMEM;
      break;
    }

    memcpy(path, directory, base + 1);
    path[base] = '/';
    memcpy(path + base + 1, entry.name, name + 1);
    int loaded = load_root_file(ctx, path, 1);
    free(path);

    if (loaded < 0) {
      status = UV_EINVAL;
      break;
    }

    found |= loaded > 0;
  }

  uv_fs_req_cleanup(&scan);

  return status == UV_EOF ? found : -1;
}

static int platform_roots (SSL_CTX *ctx) {
  const char *file = getenv("SSL_CERT_FILE"),
             *directory = getenv("SSL_CERT_DIR");

  if ((file && *file) || (directory && *directory)) {
    int roots = file && *file ? load_root_file(ctx, file, 0) : 0;
    int more = roots >= 0 && directory && *directory
                   ? load_root_directory(ctx, directory)
                   : 0;

    return roots >= 0 && more >= 0 && (roots > 0 || more > 0);
  }

#if defined(__APPLE__) || defined(_WIN32)
  SSL_CTX_set_cert_verify_callback(ctx, verify_platform, NULL);

  return 1;
#elif defined(__linux__)
  const char *candidates[] = {"/etc/ssl/certs/ca-certificates.crt",
                              "/etc/pki/tls/certs/ca-bundle.crt",
                              "/etc/ssl/cert.pem"};

  for (size_t i = 0; i < sizeof(candidates) / sizeof(*candidates); i++) {
    if (SSL_CTX_load_verify_file(ctx, candidates[i])) {
      ERR_clear_error();

      return 1;
    }
  }

  return 0;
#else

  return 0;
#endif
}

static int valid_protocols (NuppTlsBytes list) {
  if (list.size > ALPN_LIMIT || (!list.data && list.size)) {
    return 0;
  }

  size_t at = 0;

  while (at < list.size) {
    size_t size = (unsigned char)list.data[at++];

    if (!size || size > list.size - at) {
      return 0;
    }

    at += size;
  }

  return 1;
}

static int select_protocol (SSL *ssl, const unsigned char **out,
                            unsigned char *count, const unsigned char *list,
                            unsigned int size, void *unused) {
  (void)unused;
  NuppTls *tls = SSL_get_app_data(ssl);
  unsigned char *selected;
  int reply = SSL_select_next_proto(&selected, count, tls->protocols,
                                    tls->protocol_size, list, size);

  if (reply != OPENSSL_NPN_NEGOTIATED) {
    return SSL_TLSEXT_ERR_ALERT_FATAL;
  }

  *out = selected;

  return SSL_TLSEXT_ERR_OK;
}

static int client_parameters (NuppTls *tls, const NuppTlsOptions *options) {
  const char *hostname = options->hostname;
  X509_VERIFY_PARAM *parameters = SSL_get0_param(tls->ssl);
  X509_VERIFY_PARAM_set_hostflags(parameters,
                                  X509_CHECK_FLAG_NEVER_CHECK_SUBJECT |
                                      X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);

  if (hostname && *hostname) {
    ASN1_OCTET_STRING *address = a2i_IPADDRESS(hostname);

    if (address) {
      int accepted = !options->verify ||
                     X509_VERIFY_PARAM_set1_ip_asc(parameters, hostname);
      ASN1_OCTET_STRING_free(address);

      if (!accepted) {
        return 0;
      }
    }
    else if (!SSL_set_tlsext_host_name(tls->ssl, hostname) ||
             (options->verify && !SSL_set1_host(tls->ssl, hostname))) {
      return 0;
    }
  }
  else if (options->verify) {
    return 0;
  }

  return !options->protocols.size ||
         SSL_set_alpn_protos(tls->ssl,
                             (const unsigned char *)options->protocols.data,
                             (unsigned int)options->protocols.size) == 0;
}

static int configure (SSL_CTX *ctx, const NuppTlsOptions *options,
                      const unsigned char digest[CONFIG_DIGEST]) {
  if (!SSL_CTX_set_min_proto_version(ctx, TLS1_2_VERSION) ||
      !SSL_CTX_set_max_proto_version(ctx, TLS1_3_VERSION) ||
      !valid_protocols(options->protocols)) {
    return 0;
  }

  if (options->server) {
    if (!identity(ctx, options) ||
        !SSL_CTX_set_session_id_context(ctx, digest, CONFIG_DIGEST)) {
      return 0;
    }

    if (options->protocols.size) {
      SSL_CTX_set_alpn_select_cb(ctx, select_protocol, NULL);
    }
  }
  else if (options->verify) {
    if (!(options->authority.data ? certificates(ctx, options->authority, 0)
                                  : platform_roots(ctx))) {
      return 0;
    }

    SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
    X509_VERIFY_PARAM_set_flags(SSL_CTX_get0_param(ctx),
                                X509_V_FLAG_PARTIAL_CHAIN);
  }

  return 1;
}

static int config_digest (const NuppTlsOptions *options,
                          unsigned char digest[CONFIG_DIGEST]) {
  const char *host = options->hostname;
  NuppTlsBytes fields[] = {{host, host ? strlen(host) : 0},
                           options->certificate,
                           options->private_key,
                           options->authority,
                           options->protocols};
  unsigned int policy[] = {
      (unsigned)(options->server != 0), (unsigned)(options->verify != 0),
      (unsigned)(options->authority.data != NULL), options->port};
  EVP_MD_CTX *hash = EVP_MD_CTX_new();
  int ok = hash && EVP_DigestInit_ex(hash, EVP_sha256(), NULL) &&
           EVP_DigestUpdate(hash, policy, sizeof(policy));

  for (size_t i = 0; ok && i < sizeof(fields) / sizeof(*fields); i++) {
    const NuppTlsBytes bytes = fields[i];
    ok = EVP_DigestUpdate(hash, &bytes.size, sizeof(bytes.size)) &&
         (!bytes.size ||
          (bytes.data && EVP_DigestUpdate(hash, bytes.data, bytes.size)));
  }

  unsigned int size = 0;
  ok = ok && EVP_DigestFinal_ex(hash, digest, &size) && size == CONFIG_DIGEST;
  EVP_MD_CTX_free(hash);

  return ok;
}

static void release_config (TlsConfig *config) {
  SSL_SESSION_free(config->session);
  SSL_CTX_free(config->context);
  memset(config, 0, sizeof(*config));
}

static int save_session (SSL *connection, SSL_SESSION *session) {
  SSL_CTX *context = SSL_get_SSL_CTX(connection);

  for (size_t i = 0; i < CACHE_ROOM; i++) {
    TlsConfig *config = &configurations[i];

    if (config->context == context) {
      SSL_SESSION_free(config->session);
      config->session = session;

      return 1;
    }
  }

  return 0;
}

static TlsConfig *configuration (const NuppTlsOptions *options) {
  unsigned char digest[CONFIG_DIGEST];

  if (!config_digest(options, digest)) {
    return NULL;
  }

  for (size_t i = 0; i < CACHE_ROOM; i++) {
    TlsConfig *config = &configurations[i];

    if (config->context && !memcmp(config->digest, digest, sizeof(digest))) {
      return config;
    }
  }

  SSL_CTX *context = SSL_CTX_new(TLS_method());

  if (!context || !configure(context, options, digest)) {
    SSL_CTX_free(context);

    return NULL;
  }

  if (!options->server) {
    SSL_CTX_set_session_cache_mode(
        context, SSL_SESS_CACHE_CLIENT | SSL_SESS_CACHE_NO_INTERNAL_STORE);
    SSL_CTX_sess_set_new_cb(context, save_session);
  }
  else {
    SSL_CTX_sess_set_cache_size(context, CACHE_ROOM);
  }

  TlsConfig *config = &configurations[replacement];
  replacement = (replacement + 1) % CACHE_ROOM;
  release_config(config);
  config->context = context;
  memcpy(config->digest, digest, sizeof(digest));

  return config;
}

void nupptlsclear (void) {
  for (size_t i = 0; i < CACHE_ROOM; i++) {
    release_config(&configurations[i]);
  }

  replacement = 0;
}

static int setup (NuppTls *tls, TlsConfig *config,
                  const NuppTlsOptions *options) {
  tls->ssl = SSL_new(config->context);

  if (!tls->ssl) {
    return 0;
  }

  BIO *engine = NULL;

  if (!BIO_new_bio_pair(&engine, WIRE_WINDOW, &tls->network, WIRE_WINDOW)) {
    return 0;
  }

  SSL_set_bio(tls->ssl, engine, engine);
  SSL_set_app_data(tls->ssl, tls);
  SSL_set_options(tls->ssl, SSL_OP_NO_RENEGOTIATION);
  SSL_set_mode(tls->ssl, SSL_MODE_ENABLE_PARTIAL_WRITE);

  if (options->server) {
    if (options->protocols.size) {
      tls->protocols = malloc(options->protocols.size);

      if (!tls->protocols) {
        return 0;
      }

      memcpy(tls->protocols, options->protocols.data, options->protocols.size);
      tls->protocol_size = (unsigned int)options->protocols.size;
    }

    SSL_set_accept_state(tls->ssl);

    return 1;
  }

  SSL_set_connect_state(tls->ssl);
  tls->verify = options->verify;

  if (!client_parameters(tls, options)) {
    return 0;
  }

  if (config->session) {
    int available = SSL_SESSION_is_resumable(config->session);
    int ok = !available || SSL_set_session(tls->ssl, config->session);
    SSL_SESSION_free(config->session);
    config->session = NULL;

    return ok;
  }

  return 1;
}

NuppTls *nupptlsopen (const NuppTlsOptions *options, char *why, size_t room) {
  ERR_clear_error();
  NuppTls *tls = calloc(1, sizeof(*tls));
  TlsConfig *config = tls && options ? configuration(options) : NULL;
  int ok = config && setup(tls, config, options);

  if (ok) {
    return tls;
  }

  if (tls) {
    fail(tls, "invalid or unavailable TLS configuration");
    snprintf(why, room, "%s", tls->failure);
    nupptlsfree(tls);
  }
  else {
    snprintf(why, room, "%s", "unable to allocate TLS state");
  }

  return NULL;
}

void nupptlsfree (NuppTls *tls) {
  if (tls) {
    SSL_free(tls->ssl);
    BIO_free(tls->network);
    free(tls->protocols);
    OPENSSL_cleanse(tls->plaintext, sizeof(tls->plaintext));
    free(tls);
  }
}

int nupptlshandshake (NuppTls *tls) {
  if (tls->failed) {
    return NUPP_TLS_ERROR;
  }

  ERR_clear_error();
  int result = SSL_do_handshake(tls->ssl);

  if (result != 1) {
    int status = stepstatus(tls, result, "the TLS handshake failed");

    return status ? status
                  : fail(tls, "the peer closed during the TLS handshake");
  }

  if (tls->protocol_size && !nupptlsprotocol(tls).size) {
    return fail(tls, "the TLS peer shares none of the required protocols");
  }

  return 1;
}

static int send_plaintext (NuppTls *tls) {
  if (!tls->writing) {
    return 1;
  }

  ERR_clear_error();
  size_t done;
  int result = SSL_write_ex(tls->ssl, tls->plaintext, tls->writing, &done);

  if (!result) {
    int status = stepstatus(tls, result, "could not write TLS plaintext");

    return status ? status : fail(tls, "the peer closed the TLS stream");
  }

  tls->writing -= done;
  memmove(tls->plaintext, tls->plaintext + done, tls->writing);

  return tls->writing ? NUPP_TLS_AGAIN : 1;
}

int nupptlsread (NuppTls *tls, void *out, size_t room) {
  if (tls->failed || !nupptlsready(tls) || !room) {
    return fail(tls, "TLS read requires an open session and room for bytes");
  }

  if (send_plaintext(tls) == NUPP_TLS_ERROR) {
    return NUPP_TLS_ERROR;
  }

  ERR_clear_error();
  size_t done;
  int result =
      SSL_read_ex(tls->ssl, out, smaller(room, NUPP_TLS_WINDOW), &done);

  return result ? (int)done
                : stepstatus(tls, result, "could not read TLS plaintext");
}

int nupptlswrite (NuppTls *tls, const void *bytes, size_t size) {
  if (tls->failed || !nupptlsready(tls) ||
      (SSL_get_shutdown(tls->ssl) & SSL_SENT_SHUTDOWN)) {
    return fail(tls, "TLS write requires an open session");
  }

  int status = send_plaintext(tls);

  if (status < 0 || !size) {
    return status < 0 ? status : 0;
  }

  size_t count = smaller(size, sizeof(tls->plaintext));
  memcpy(tls->plaintext, bytes, count);
  tls->writing = count;

  return send_plaintext(tls) == NUPP_TLS_ERROR ? NUPP_TLS_ERROR : (int)count;
}

int nupptlsflushed (NuppTls *tls) {
  if (tls->failed || send_plaintext(tls) == NUPP_TLS_ERROR) {
    return NUPP_TLS_ERROR;
  }

  return !tls->writing && BIO_ctrl_pending(tls->network) == 0;
}

int nupptlsclose (NuppTls *tls) {
  if (tls->failed) {
    return NUPP_TLS_ERROR;
  }

  int status = send_plaintext(tls);

  if (status < 0) {
    return status;
  }

  if (!tls->alert_queued) {
    ERR_clear_error();
    int result = SSL_shutdown(tls->ssl);

    if (result < 0) {
      return stepstatus(tls, result, "could not queue TLS close_notify");
    }

    tls->alert_queued = 1;
  }

  return nupptlsflushed(tls);
}

size_t nupptlsroom (NuppTls *tls) {
  return tls->input_closed ? 0 : BIO_ctrl_get_write_guarantee(tls->network);
}

int nupptlsfeed (NuppTls *tls, const void *bytes, size_t size) {
  size_t room = nupptlsroom(tls);

  if (!size || !room) {
    return size ? NUPP_TLS_AGAIN : 0;
  }

  return BIO_write(tls->network, bytes, (int)smaller(size, room));
}

void nupptlseof (NuppTls *tls) {
  (void)BIO_shutdown_wr(tls->network);
  tls->input_closed = 1;
}

size_t nupptlsoutput (NuppTls *tls, const char **bytes) {
  char *buffer = NULL;
  int count = BIO_nread0(tls->network, &buffer);
  *bytes = count > 0 ? buffer : NULL;

  return count > 0 ? (size_t)count : 0;
}

int nupptlsconsumed (NuppTls *tls, size_t size) {
  const char *available;

  if (size > nupptlsoutput(tls, &available)) {
    return 0;
  }

  char *buffer;

  return !size || BIO_nread(tls->network, &buffer, (int)size) == (int)size;
}

int nupptlsready (const NuppTls *tls) {
  return !tls->failed && SSL_is_init_finished(tls->ssl);
}

int nupptlsverified (const NuppTls *tls) {
  return nupptlsready(tls) && tls->verify &&
         SSL_get_verify_result(tls->ssl) == X509_V_OK;
}

int nupptlsresumed (const NuppTls *tls) {
  return nupptlsready(tls) && SSL_session_reused(tls->ssl);
}

NuppTlsBytes nupptlsprotocol (const NuppTls *tls) {
  const unsigned char *protocol = NULL;
  unsigned int count = 0;
  SSL_get0_alpn_selected(tls->ssl, &protocol, &count);

  return (NuppTlsBytes){(const char *)protocol, count};
}

const char *nupptlswhy (const NuppTls *tls) {
  return tls->failure;
}
