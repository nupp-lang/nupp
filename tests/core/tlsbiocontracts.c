/**
 * @file
 * @brief Exercises the TLS engine through fragmented memory-only transfers.
 */

#include "tlsbio.h"
#include <openssl/pem.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static NuppTlsBytes read_fixture (const char *path) {
  FILE *file = fopen(path, "rb");
  assert(file);
  assert(fseek(file, 0, SEEK_END) == 0);
  long length = ftell(file);
  assert(length > 0);
  assert(fseek(file, 0, SEEK_SET) == 0);
  char *bytes = malloc((size_t)length);
  assert(bytes && fread(bytes, 1, (size_t)length, file) == (size_t)length);
  assert(!fclose(file));

  return (NuppTlsBytes){bytes, (size_t)length};
}

static NuppTlsBytes expired_certificate (NuppTlsBytes cert, NuppTlsBytes key) {
  BIO *cert_input = BIO_new_mem_buf(cert.data, (int)cert.size);
  BIO *key_input = BIO_new_mem_buf(key.data, (int)key.size);
  X509 *certificate = PEM_read_bio_X509(cert_input, NULL, NULL, NULL);
  EVP_PKEY *private_key = PEM_read_bio_PrivateKey(key_input, NULL, NULL, NULL);
  assert(certificate && private_key);
  assert(X509_gmtime_adj(X509_getm_notBefore(certificate), -172800));
  assert(X509_gmtime_adj(X509_getm_notAfter(certificate), -86400));
  assert(X509_sign(certificate, private_key, EVP_sha256()) > 0);
  BIO *output = BIO_new(BIO_s_mem());
  assert(output && PEM_write_bio_X509(output, certificate));
  char *borrowed;
  long count = BIO_get_mem_data(output, &borrowed);
  assert(count > 0);
  char *copy = malloc((size_t)count);
  assert(copy);
  memcpy(copy, borrowed, (size_t)count);
  BIO_free(output);
  BIO_free(cert_input);
  BIO_free(key_input);
  X509_free(certificate);
  EVP_PKEY_free(private_key);

  return (NuppTlsBytes){copy, (size_t)count};
}

static void transfer (NuppTls *source, NuppTls *target) {
  const char *bytes;
  size_t count = nupptlsoutput(source, &bytes);

  if (count > 379) {
    count = 379;
  }

  if (count) {
    int taken = nupptlsfeed(target, bytes, count);

    if (taken == NUPP_TLS_AGAIN) {
      return;
    }

    assert(taken > 0 && (size_t)taken <= count);
    assert(nupptlsconsumed(source, (size_t)taken));
  }
}

static int handshake (NuppTls *client, NuppTls *server) {
  for (int turn = 0; turn < 300; turn++) {
    int left = nupptlshandshake(client), right = nupptlshandshake(server);

    if (left == NUPP_TLS_ERROR || right == NUPP_TLS_ERROR) {
      return 0;
    }

    assert((left == 1 || left == NUPP_TLS_AGAIN) &&
           (right == 1 || right == NUPP_TLS_AGAIN));
    transfer(client, server);
    transfer(server, client);

    if (left == 1 && right == 1) {
      return 1;
    }
  }

  return 0;
}

static void close_cleanly (NuppTls *client, NuppTls *server) {
  char bytes[8];

  for (int turn = 0; turn < 300; turn++) {
    int written = nupptlsclose(client);
    assert(written == 0 || written == NUPP_TLS_AGAIN || written == 1);
    transfer(client, server);
    int seen = nupptlsread(server, bytes, sizeof(bytes));

    if (!seen) {
      assert(nupptlsclose(client) == 1);

      return;
    }

    assert(seen == NUPP_TLS_AGAIN);
  }

  assert(0 && "close_notify reached the peer");
}

static void exchange (NuppTls *client, NuppTls *server) {
  unsigned char data[40000], received[sizeof(data)], copy[sizeof(data)];

  for (size_t i = 0; i < sizeof(data); i++) {
    copy[i] = data[i] = (unsigned char)(i % 199);
  }

  size_t sent = 0, got = 0;

  for (int turn = 0; turn < 3000 && got < sizeof(data); turn++) {
    if (sent < sizeof(data)) {
      int count = nupptlswrite(client, data + sent, sizeof(data) - sent);
      assert(count == NUPP_TLS_AGAIN ||
             (count > 0 && count <= NUPP_TLS_WINDOW));

      if (count > 0) {
        memset(data + sent, 0, (size_t)count);
        sent += (size_t)count;
      }
    }
    else {
      assert(nupptlsflushed(client) >= 0);
    }

    transfer(client, server);
    transfer(server, client);
    int count = nupptlsread(server, received + got, sizeof(received) - got);
    assert(count == NUPP_TLS_AGAIN || count > 0);

    if (count > 0) {
      got += (size_t)count;
    }
  }

  assert(sent == sizeof(data) && got == sizeof(data));
  assert(!memcmp(received, copy, sizeof(data)));
  assert(nupptlsflushed(client) == 1);
}

static void collect_ticket (NuppTls *client, NuppTls *server) {
  assert(nupptlswrite(server, "t", 1) == 1);

  for (int turn = 0; turn < 300; turn++) {
    transfer(server, client);
    char byte;
    int count = nupptlsread(client, &byte, 1);

    if (count == 1) {
      assert(byte == 't');

      return;
    }

    assert(count == NUPP_TLS_AGAIN);
  }

  assert(0 && "the post-handshake ticket and data reached the client");
}

int main (int argc, char **argv) {
  assert(argc == 3);
  NuppTlsBytes cert = read_fixture(argv[1]), key = read_fixture(argv[2]);
  NuppTlsOptions serveropts = {.certificate = cert,
                               .private_key = key,
                               .protocols = {"\x08"
                                             "http/1.1\x02"
                                             "h2",
                                             12},
                               .server = 1};
  NuppTlsOptions clientopts = {.hostname = "localhost",
                               .authority = cert,
                               .protocols = {"\x02"
                                             "h2\x08"
                                             "http/1.1",
                                             12},
                               .verify = 1};
  char error[256];
  NuppTls *server = nupptlsopen(&serveropts, error, sizeof(error));
  NuppTls *client = nupptlsopen(&clientopts, error, sizeof(error));
  assert(server && client && handshake(client, server));
  assert(nupptlsverified(client) && !nupptlsverified(server));
  assert(!nupptlsresumed(client));
  NuppTlsBytes protocol = nupptlsprotocol(client);
  assert(protocol.size == 8 && !memcmp(protocol.data, "http/1.1", 8));
  exchange(client, server);
  collect_ticket(client, server);
  close_cleanly(client, server);
  close_cleanly(server, client);
  nupptlsfree(client);
  nupptlsfree(server);

  server = nupptlsopen(&serveropts, error, sizeof(error));
  client = nupptlsopen(&clientopts, error, sizeof(error));
  assert(server && client && handshake(client, server));
  assert(nupptlsresumed(client) && nupptlsverified(client));
  collect_ticket(client, server);
  close_cleanly(client, server);
  close_cleanly(server, client);
  nupptlsfree(client);
  nupptlsfree(server);

  clientopts.port = 3421;
  server = nupptlsopen(&serveropts, error, sizeof(error));
  client = nupptlsopen(&clientopts, error, sizeof(error));
  assert(server && client && handshake(client, server));
  assert(!nupptlsresumed(client));
  close_cleanly(client, server);
  close_cleanly(server, client);
  nupptlsfree(client);
  nupptlsfree(server);

  clientopts.hostname = "wrong.invalid";
  server = nupptlsopen(&serveropts, error, sizeof(error));
  client = nupptlsopen(&clientopts, error, sizeof(error));
  assert(server && client && !handshake(client, server));
  assert(!nupptlsverified(client) && *nupptlswhy(client));
  nupptlsfree(client);
  nupptlsfree(server);

  clientopts.hostname = "localhost";
  NuppTlsBytes expired = expired_certificate(cert, key);
  serveropts.certificate = expired;
  clientopts.authority = expired;
  server = nupptlsopen(&serveropts, error, sizeof(error));
  client = nupptlsopen(&clientopts, error, sizeof(error));
  assert(server && client && !handshake(client, server));
  assert(!nupptlsverified(client) && *nupptlswhy(client));
  nupptlsfree(client);
  nupptlsfree(server);
  free((void *)expired.data);

  serveropts.certificate = cert;
  clientopts.authority = (NuppTlsBytes){"", 0};
  assert(!nupptlsopen(&clientopts, error, sizeof(error)) && *error);
  clientopts.authority = (NuppTlsBytes){NULL, 0};
  server = nupptlsopen(&serveropts, error, sizeof(error));
  client = nupptlsopen(&clientopts, error, sizeof(error));
  assert(server && client && !handshake(client, server));
  assert(!nupptlsverified(client) && *nupptlswhy(client));
  nupptlsfree(client);
  nupptlsfree(server);

  clientopts.verify = 0;
  server = nupptlsopen(&serveropts, error, sizeof(error));
  client = nupptlsopen(&clientopts, error, sizeof(error));
  assert(server && client && handshake(client, server) &&
         !nupptlsverified(client));
  nupptlseof(client);
  char byte;
  int status;

  for (int turn = 0; turn < 300; turn++) {
    status = nupptlsread(client, &byte, 1);

    if (status != NUPP_TLS_AGAIN) {
      break;
    }
  }

  assert(status == NUPP_TLS_ERROR && *nupptlswhy(client));
  nupptlsfree(client);
  nupptlsfree(server);
  nupptlsclear();
  free((void *)cert.data);
  free((void *)key.data);
  puts("OpenSSL memory BIO contracts passed");

  return 0;
}
