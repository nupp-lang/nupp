#ifndef NUPP_HTTP_CURL_TRANSPORT_H
#define NUPP_HTTP_CURL_TRANSPORT_H

#include <stddef.h>
#include <stdint.h>

struct uv_loop_s;
typedef struct NuppCurlClient NuppCurlClient;
typedef struct NuppCurlRequest NuppCurlRequest;

enum {
  NUPP_CURL_HEADERS = 1,
  NUPP_CURL_BODY = 2,
  NUPP_CURL_UPLOAD = 4,
  NUPP_CURL_FAILED = 8
};

enum {
  NUPP_HTTP_ACTIVE = 1,
  NUPP_HTTP_NATIVE_READY = 2,
  NUPP_HTTP_MANAGED_READY = 4
};

typedef struct {
  uint64_t connect_ms;
  unsigned pending, connections, per_host;
  int compressed, proxy_mode;
  const char *proxy, *no_proxy, *credentials;
} NuppCurlOptions;

typedef struct {
  const char *name, *value;
  size_t name_length, value_length;
} NuppCurlHeader;

typedef struct {
  const char *url, *method;
  const NuppCurlHeader *headers;
  size_t header_count;
  const void *bytes;
  int64_t length;
  uint64_t timeout_ms, stall_ms, max_bytes;
  int body, insecure;
} NuppCurlSend;

typedef struct {
  const void *bytes;
  size_t length;
  int status, version;
  const char *error;
} NuppCurlHead;

/* Owner thread only. The caller initializes libcurl globally and drives the
 * borrowed loop. Callbacks publish flags only. The client and transfer own
 * copies of all inputs. Returned byte and error views live until release. */
NuppCurlClient *nupp_curl_open (struct uv_loop_s *, uintptr_t scope,
                                const NuppCurlOptions *, const char **error);
/* Withdraws transfers and stops watchers. The owner drains close callbacks
 * with its normal loop shutdown. A cleared slot can be closed again. */
void nupp_curl_close (NuppCurlClient **);
/* Withdraw clients left open on this owner thread before closing the loop. */
void nupp_curl_shutdown (struct uv_loop_s *);
/* The host uses scoped tokens between calls. Close and shutdown invalidate
 * tokens before releasing native objects. Never store a lookup result. */
uint64_t nupp_curl_client_token (const NuppCurlClient *);
NuppCurlClient *nupp_curl_find_client (uintptr_t scope, uint64_t token);
uint64_t nupp_curl_request_token (const NuppCurlRequest *);
NuppCurlRequest *nupp_curl_find_request (uintptr_t scope, uint64_t token);
void nupp_curl_close_scope (uintptr_t scope);
/* After an owner-loop turn, advance at most budget socket/timer events. The
 * context is the service scope used to open the clients. The ready query
 * is nonmutating and returns the NUPP_HTTP_* flags. */
void nupp_http_owner_step (void *context, uint32_t budget);
uint32_t nupp_http_owner_ready (void *context);
size_t nupp_curl_pending (const NuppCurlClient *);
void nupp_curl_watch_client (NuppCurlClient *, int watching);
NuppCurlRequest *nupp_curl_send (NuppCurlClient *, const NuppCurlSend *,
                                 const char **error);
unsigned nupp_curl_ready (NuppCurlRequest *);
int nupp_curl_head (const NuppCurlRequest *, NuppCurlHead *);
const char *nupp_curl_error (const NuppCurlRequest *);
/* Offer returns 1 for accepted, 0 for backpressure or -1 for closed.
 * Count zero supplies EOF. */
int nupp_curl_offer (NuppCurlRequest *, const void *, size_t);
void nupp_curl_arm (NuppCurlRequest *);
/* Read returns a byte count, 0 for EOF, -1 for pending or -2 for failure. */
int64_t nupp_curl_read (NuppCurlRequest *, void *, size_t, const char **error);
void nupp_curl_cancel (NuppCurlRequest *);
void nupp_curl_release (NuppCurlRequest *);

#endif
