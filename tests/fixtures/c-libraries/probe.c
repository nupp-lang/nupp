/* The C-library probe: a test-only program that checks the pinned zlib,
 * OpenSSL and curl the C-library lane builds. Each header must match the
 * library it is linked against and the version scripts/toolchain.pins names,
 * curl must carry exactly the features the runtime relies on, and each
 * library must do real work: compress and inflate, digest and sign, refuse a
 * protocol it was built without.
 *
 * .github/scripts/test-c-libraries.sh builds it with CMakeLists.txt beside
 * it and reads the one line of JSON it prints: the versions found, and the
 * layouts of z_stream and OSSL_PARAM, which the runtime's bindings declare
 * for themselves and must agree with. Every check is an assert, so the
 * build keeps assertions on in release builds too. */

#include <curl/curl.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/params.h>
#include <openssl/ssl.h>
#include <zlib.h>

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* The versions scripts/toolchain.pins pins; a pin bump changes these too. */
#define EXPECTED_ZLIB_VERSION "1.4"
#define EXPECTED_OPENSSL_VERSION_NUMBER UINT64_C(0x30500090)
#define EXPECTED_OPENSSL_NAME "OpenSSL/3.5.9"
#define EXPECTED_CURL_VERSION "8.23.0"

/* The protocols curl is built with, http and https, and nothing else. */
#define EXPECTED_PROTOCOL_COUNT 2

/* The three framings deflate's window bits select: 31 is gzip, 15 is zlib,
 * and -15 is raw deflate. Only the first two carry a checksum, so only they
 * can notice a corrupted stream. */
#define WINDOW_GZIP 31
#define WINDOW_ZLIB 15
#define WINDOW_RAW (-15)
#define FRAMINGS 3
#define CHECKED_FRAMINGS 2

/* deflate's default compression level and memory level. */
#define COMPRESSION_LEVEL 6
#define MEMORY_LEVEL 8

/* Room for the probe's input, compressed or not. */
#define CODEC_BUFFER_BYTES 256

/* Writes size bytes as lowercase hexadecimal into out, which has room for
 * twice that and a terminating NUL. */
static void hexadecimal (const unsigned char *bytes, size_t size, char *out) {
  static const char digits[] = "0123456789abcdef";

  for (size_t i = 0; i < size; ++i) {
    out[i * 2] = digits[bytes[i] >> 4];
    out[i * 2 + 1] = digits[bytes[i] & 15];
  }

  out[size * 2] = 0;
}

/* Round-trips an input with an embedded NUL and a high byte through each
 * framing, then flips a bit in the last byte, the checksum's, and expects
 * the framings that have one to refuse the stream. */
static void codecs (void) {
  static const unsigned char input[] = "native codec\0binary\xffnative codec";
  const int windows[] = {WINDOW_GZIP, WINDOW_ZLIB, WINDOW_RAW};

  for (unsigned i = 0; i < FRAMINGS; ++i) {
    unsigned char compressed[CODEC_BUFFER_BYTES], output[CODEC_BUFFER_BYTES];
    z_stream encode = {0}, decode = {0};
    assert(deflateInit2(&encode, COMPRESSION_LEVEL, Z_DEFLATED, windows[i],
                        MEMORY_LEVEL, Z_DEFAULT_STRATEGY) == Z_OK);
    encode.next_in = (Bytef *)input;
    encode.avail_in = sizeof(input);
    encode.next_out = compressed;
    encode.avail_out = sizeof(compressed);
    assert(deflate(&encode, Z_FINISH) == Z_STREAM_END);
    unsigned size = (unsigned)encode.total_out;
    assert(deflateEnd(&encode) == Z_OK);
    assert(inflateInit2(&decode, windows[i]) == Z_OK);
    decode.next_in = compressed;
    decode.avail_in = size;
    decode.next_out = output;
    decode.avail_out = sizeof(output);
    assert(inflate(&decode, Z_FINISH) == Z_STREAM_END);
    assert(decode.total_out == sizeof(input) &&
           !memcmp(input, output, sizeof(input)));
    assert(inflateEnd(&decode) == Z_OK);

    if (i < CHECKED_FRAMINGS) {
      compressed[size - 1] ^= 1;
      memset(&decode, 0, sizeof(decode));
      assert(inflateInit2(&decode, windows[i]) == Z_OK);
      decode.next_in = compressed;
      decode.avail_in = size;
      decode.next_out = output;
      decode.avail_out = sizeof(output);
      assert(inflate(&decode, Z_FINISH) == Z_DATA_ERROR);
      assert(inflateEnd(&decode) == Z_OK);
    }
  }
}

/* A SHA-256 digest and an HMAC-SHA256, against their published test
 * vectors, and a TLS context, which needs the SSL library proper. */
static void cryptography (void) {
  unsigned char output[EVP_MAX_MD_SIZE];
  unsigned size = 0;
  char hex[EVP_MAX_MD_SIZE * 2 + 1];
  assert(EVP_Digest("abc", 3, output, &size, EVP_sha256(), NULL) == 1);
  hexadecimal(output, size, hex);
  assert(!strcmp(
      hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
  const char message[] = "The quick brown fox jumps over the lazy dog";
  size_t length = 0;
  assert(EVP_Q_mac(NULL, "HMAC", NULL, "SHA256", NULL, "key", 3,
                   (const unsigned char *)message, strlen(message), output,
                   sizeof(output), &length));
  hexadecimal(output, length, hex);
  assert(!strcmp(
      hex, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"));
  SSL_CTX *context = SSL_CTX_new(TLS_method());
  assert(context);
  SSL_CTX_free(context);
}

/* The target this program was compiled for, in the spelling the build
 * passes as NUPP_EXPECT_TARGET. */
static const char *compiledtarget (void) {
#if defined(__APPLE__) && defined(__aarch64__)

  return "aarch64-apple-darwin";
#elif defined(__APPLE__) && defined(__x86_64__)

  return "x86_64-apple-darwin";
#elif defined(_WIN32) && defined(_M_X64)

  return "x86_64-pc-windows-msvc";
#elif defined(__linux__) && defined(__aarch64__)

  return "aarch64-unknown-linux-gnu";
#elif defined(__linux__) && defined(__x86_64__)

  return "x86_64-unknown-linux-gnu";
#else
#error unverified C-library target
#endif
}

/* The line test-c-libraries.sh reads: what was found, and the layouts the
 * runtime's bindings must agree with. */
static void report (const char *target, const curl_version_info_data *version) {
  printf("{\"schemaVersion\":1,\"target\":\"%s\",\"zlib\":\"%s\",\"openssl\":"
         "\"%s\",\"curl\":\"%s\",\"protocols\":[\"http\",\"https\"],",
         target, zlibVersion(), version->ssl_version, version->version);
  printf("\"zStream\":{\"size\":%zu,\"alignment\":%zu,\"nextIn\":%zu,"
         "\"availIn\":%zu,\"totalIn\":%zu,\"nextOut\":%zu,\"availOut\":%zu,"
         "\"totalOut\":%zu,\"state\":%zu},",
         sizeof(z_stream), _Alignof(z_stream), offsetof(z_stream, next_in),
         offsetof(z_stream, avail_in), offsetof(z_stream, total_in),
         offsetof(z_stream, next_out), offsetof(z_stream, avail_out),
         offsetof(z_stream, total_out), offsetof(z_stream, state));
  printf("\"opensslParameter\":{\"size\":%zu,\"alignment\":%zu,\"key\":%zu,"
         "\"dataType\":%zu,\"data\":%zu,\"dataSize\":%zu,\"returnSize\":%zu},"
         "\"passed\":true}\n",
         sizeof(OSSL_PARAM), _Alignof(OSSL_PARAM), offsetof(OSSL_PARAM, key),
         offsetof(OSSL_PARAM, data_type), offsetof(OSSL_PARAM, data),
         offsetof(OSSL_PARAM, data_size), offsetof(OSSL_PARAM, return_size));
}

/* Checks the versions and curl's features, then has each library do its
 * work, and reports. The checks stay inline here because each is an assert
 * whose condition is the call itself. */
int main (void) {
  const char *target = compiledtarget();
  assert(!strcmp(target, NUPP_EXPECT_TARGET));
  assert(!strcmp(zlibVersion(), ZLIB_VERSION) &&
         !strcmp(ZLIB_VERSION, EXPECTED_ZLIB_VERSION));
  assert(OpenSSL_version_num() == OPENSSL_VERSION_NUMBER);
  assert(OPENSSL_VERSION_NUMBER == EXPECTED_OPENSSL_VERSION_NUMBER);
  assert(curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK);
  const curl_version_info_data *version = curl_version_info(CURLVERSION_NOW);
  assert(version && version->version_num == LIBCURL_VERSION_NUM);
  assert(!strcmp(version->version, EXPECTED_CURL_VERSION));
  assert(version->ssl_version &&
         !strcmp(version->ssl_version, EXPECTED_OPENSSL_NAME));
  assert(version->libz_version &&
         !strcmp(version->libz_version, EXPECTED_ZLIB_VERSION));
  assert((version->features & (CURL_VERSION_SSL | CURL_VERSION_LIBZ)) ==
         (CURL_VERSION_SSL | CURL_VERSION_LIBZ));
  assert(!(version->features & (CURL_VERSION_HTTP2 | CURL_VERSION_HTTP3 |
                                CURL_VERSION_BROTLI | CURL_VERSION_ZSTD)));
  unsigned protocols = 0;

  for (const char *const *name = version->protocols; *name; ++name) {
    assert(!strcmp(*name, "http") || !strcmp(*name, "https"));
    ++protocols;
  }

  assert(protocols == EXPECTED_PROTOCOL_COUNT);
  CURL *easy = curl_easy_init();
  assert(easy);
  assert(curl_easy_setopt(easy, CURLOPT_URL,
                          "file:///nupp-disabled-protocol") == CURLE_OK);
  assert(curl_easy_perform(easy) == CURLE_UNSUPPORTED_PROTOCOL);
  curl_easy_cleanup(easy);
  codecs();
  cryptography();
  report(target, version);
  curl_global_cleanup();

  return 0;
}
