/* Test-only: verify matched upstream headers, shared libraries and features. */
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <zlib.h>
#include <openssl/crypto.h>
#include <openssl/evp.h>
#include <openssl/params.h>
#include <openssl/ssl.h>
#include <curl/curl.h>
static void hexadecimal(const unsigned char *bytes, size_t size, char *out) {
    static const char digits[] = "0123456789abcdef";
    for (size_t i = 0; i < size; ++i) { out[i * 2] = digits[bytes[i] >> 4]; out[i * 2 + 1] = digits[bytes[i] & 15]; }
    out[size * 2] = 0;
}
static void codecs(void) {
    static const unsigned char input[] = "native codec\0binary\xffnative codec";
    const int windows[] = {31, 15, -15};
    for (unsigned i = 0; i < 3; ++i) {
        unsigned char compressed[256], output[256];
        z_stream encode = {0}, decode = {0};
        assert(deflateInit2(&encode, 6, Z_DEFLATED, windows[i], 8, Z_DEFAULT_STRATEGY) == Z_OK);
        encode.next_in = (Bytef *)input; encode.avail_in = sizeof(input);
        encode.next_out = compressed; encode.avail_out = sizeof(compressed);
        assert(deflate(&encode, Z_FINISH) == Z_STREAM_END);
        unsigned size = (unsigned)encode.total_out;
        assert(deflateEnd(&encode) == Z_OK);
        assert(inflateInit2(&decode, windows[i]) == Z_OK);
        decode.next_in = compressed; decode.avail_in = size;
        decode.next_out = output; decode.avail_out = sizeof(output);
        assert(inflate(&decode, Z_FINISH) == Z_STREAM_END);
        assert(decode.total_out == sizeof(input) && !memcmp(input, output, sizeof(input)));
        assert(inflateEnd(&decode) == Z_OK);
        if (i < 2) {
            compressed[size - 1] ^= 1;
            memset(&decode, 0, sizeof(decode));
            assert(inflateInit2(&decode, windows[i]) == Z_OK);
            decode.next_in = compressed; decode.avail_in = size;
            decode.next_out = output; decode.avail_out = sizeof(output);
            assert(inflate(&decode, Z_FINISH) == Z_DATA_ERROR);
            assert(inflateEnd(&decode) == Z_OK);
        }
    }
}
static void cryptography(void) {
    unsigned char output[EVP_MAX_MD_SIZE];
    unsigned size = 0;
    char hex[EVP_MAX_MD_SIZE * 2 + 1];
    assert(EVP_Digest("abc", 3, output, &size, EVP_sha256(), NULL) == 1);
    hexadecimal(output, size, hex);
    assert(!strcmp(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"));
    const char message[] = "The quick brown fox jumps over the lazy dog";
    size_t length = 0;
    assert(EVP_Q_mac(NULL, "HMAC", NULL, "SHA256", NULL, "key", 3,
        (const unsigned char *)message, strlen(message), output, sizeof(output), &length));
    hexadecimal(output, length, hex);
    assert(!strcmp(hex, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"));
    SSL_CTX *context = SSL_CTX_new(TLS_method());
    assert(context); SSL_CTX_free(context);
}
int main(void) {
#if defined(__APPLE__) && defined(__aarch64__)
    const char *target = "aarch64-apple-darwin";
#elif defined(__APPLE__) && defined(__x86_64__)
    const char *target = "x86_64-apple-darwin";
#elif defined(_WIN32) && defined(_M_X64)
    const char *target = "x86_64-pc-windows-msvc";
#elif defined(__linux__) && defined(__aarch64__)
    const char *target = "aarch64-unknown-linux-gnu";
#elif defined(__linux__) && defined(__x86_64__)
    const char *target = "x86_64-unknown-linux-gnu";
#else
#error unverified C-library target
#endif
    assert(!strcmp(target, NUPP_EXPECT_TARGET));
    assert(!strcmp(zlibVersion(), ZLIB_VERSION) && !strcmp(ZLIB_VERSION, "1.4"));
    assert(OpenSSL_version_num() == OPENSSL_VERSION_NUMBER);
    assert(OPENSSL_VERSION_NUMBER == UINT64_C(0x30500090));
    assert(curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK);
    const curl_version_info_data *version = curl_version_info(CURLVERSION_NOW);
    assert(version && version->version_num == LIBCURL_VERSION_NUM);
    assert(!strcmp(version->version, "8.23.0"));
    assert(version->ssl_version && !strcmp(version->ssl_version, "OpenSSL/3.5.9"));
    assert(version->libz_version && !strcmp(version->libz_version, "1.4"));
    assert((version->features & (CURL_VERSION_SSL | CURL_VERSION_LIBZ)) == (CURL_VERSION_SSL | CURL_VERSION_LIBZ));
    assert(!(version->features & (CURL_VERSION_HTTP2 | CURL_VERSION_HTTP3 | CURL_VERSION_BROTLI | CURL_VERSION_ZSTD)));
    unsigned protocols = 0;
    for (const char *const *name = version->protocols; *name; ++name) {
        assert(!strcmp(*name, "http") || !strcmp(*name, "https")); ++protocols;
    }
    assert(protocols == 2);
    CURL *easy = curl_easy_init(); assert(easy);
    assert(curl_easy_setopt(easy, CURLOPT_URL, "file:///nupp-disabled-protocol") == CURLE_OK);
    assert(curl_easy_perform(easy) == CURLE_UNSUPPORTED_PROTOCOL);
    curl_easy_cleanup(easy);
    codecs(); cryptography();
    printf("{\"schemaVersion\":1,\"target\":\"%s\",\"zlib\":\"%s\",\"openssl\":\"%s\",\"curl\":\"%s\",\"protocols\":[\"http\",\"https\"],",
        target, zlibVersion(), version->ssl_version, version->version);
    printf("\"zStream\":{\"size\":%zu,\"alignment\":%zu,\"nextIn\":%zu,\"availIn\":%zu,\"totalIn\":%zu,\"nextOut\":%zu,\"availOut\":%zu,\"totalOut\":%zu,\"state\":%zu},",
        sizeof(z_stream), _Alignof(z_stream), offsetof(z_stream, next_in), offsetof(z_stream, avail_in), offsetof(z_stream, total_in),
        offsetof(z_stream, next_out), offsetof(z_stream, avail_out), offsetof(z_stream, total_out), offsetof(z_stream, state));
    printf("\"opensslParameter\":{\"size\":%zu,\"alignment\":%zu,\"key\":%zu,\"dataType\":%zu,\"data\":%zu,\"dataSize\":%zu,\"returnSize\":%zu},\"passed\":true}\n",
        sizeof(OSSL_PARAM), _Alignof(OSSL_PARAM), offsetof(OSSL_PARAM, key), offsetof(OSSL_PARAM, data_type), offsetof(OSSL_PARAM, data),
        offsetof(OSSL_PARAM, data_size), offsetof(OSSL_PARAM, return_size));
    curl_global_cleanup();
    return 0;
}
