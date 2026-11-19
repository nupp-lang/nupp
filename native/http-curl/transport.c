#define _POSIX_C_SOURCE 200809L
#include "transport.h"
#include "reactor.h"

#include <curl/curl.h>
#include <uv.h>

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
  HEAD_LIMIT = 256 * 1024,
  BODY_WINDOW = 1024 * 1024,
  UPLOAD_OFFER = 512 * 1024,
  UPLOAD_WINDOW = 1024 * 1024
};

typedef struct {
  unsigned char *bytes;
  size_t start, used, room;
} Buffer;

typedef struct Watch {
  struct Watch *next;
  curl_socket_t socket;
  uint64_t token, interest;
} Watch;

typedef struct Reply {
  struct Reply *next;
  size_t name, value;
  char text[];
} Reply;

struct NuppCurlClient {
  NuppCurlClient *next;
  uintptr_t scope;
  uint64_t token;
  uv_loop_t *loop;
  uint64_t timer;
  CURLM *multi;
  Watch *watches;
  NuppCurlRequest *requests;
  size_t pending, limit;
  uint64_t connect_ms, curl_deadline;
  char *proxy, *no_proxy, *credentials;
  int compressed, proxy_mode, closing, watching;
  const char *failure;
};

struct NuppCurlRequest {
  NuppCurlClient *client;
  NuppCurlRequest *next;
  uint64_t token;
  CURL *easy;
  struct curl_slist *headers;
  Reply *reply, **reply_tail;
  Buffer body, upload;
  unsigned char *head;
  size_t head_length, reply_count, reply_bytes;
  uint64_t deadline, stall_ms, stall_deadline, max_bytes, received, offered;
  int64_t length;
  unsigned ready;
  int status, version, head_ready, done, attached;
  int streaming, upload_eof, upload_closed, paused, body_armed;
  int decode, strip_encoding;
  char error[CURL_ERROR_SIZE];
};

static _Thread_local NuppCurlClient *clients;
static _Thread_local uint64_t next_token;

static uint64_t issue_token (void) {
  return next_token == INT64_MAX ? 0 : ++next_token;
}

static uint64_t now (void) {
  return uv_hrtime() / 1000000;
}

static uint64_t after (uint64_t time, uint64_t delay) {
  return delay >= UINT64_MAX - time ? UINT64_MAX - 1 : time + delay;
}

static char *copy_text (const char *value) {
  return value ? strdup(value) : NULL;
}

static int append (Buffer *buffer, const void *bytes, size_t count) {
  if (count == 0) {
    return 1;
  }

  if (!buffer->bytes) {
    buffer->bytes = malloc(buffer->room);

    if (!buffer->bytes) {
      return 0;
    }
  }

  size_t at = (buffer->start + buffer->used) % buffer->room;
  size_t first = buffer->room - at;

  if (first > count) {
    first = count;
  }

  memcpy(buffer->bytes + at, bytes, first);
  memcpy(buffer->bytes, (const unsigned char *)bytes + first, count - first);
  buffer->used += count;

  return 1;
}

static size_t take (Buffer *buffer, void *bytes, size_t count) {
  if (count > buffer->used) {
    count = buffer->used;
  }

  if (count == 0) {
    return 0;
  }

  size_t first = buffer->room - buffer->start;

  if (first > count) {
    first = count;
  }

  memcpy(bytes, buffer->bytes + buffer->start, first);
  memcpy((unsigned char *)bytes + first, buffer->bytes, count - first);
  buffer->start = (buffer->start + count) % buffer->room;
  buffer->used -= count;

  return count;
}

static int schedule (NuppCurlClient *client) {
  if (client->closing) {
    return 0;
  }

  uint64_t deadline = client->curl_deadline;

  for (NuppCurlRequest *r = client->requests; r; r = r->next) {
    if (r->done) {
      continue;
    }

    if (r->deadline < deadline) {
      deadline = r->deadline;
    }

    if (r->stall_deadline < deadline) {
      deadline = r->stall_deadline;
    }
  }

  if (deadline == UINT64_MAX) {
    return nupp_uv_timer_replace(client->timer, -1);
  }

  uint64_t time = now();
  uint64_t delay = deadline > time ? deadline - time : 0;

  return nupp_uv_timer_replace(client->timer,
                               delay > INT64_MAX ? INT64_MAX : (int64_t)delay);
}

static void free_reply (NuppCurlRequest *request) {
  while (request->reply) {
    Reply *header = request->reply;
    request->reply = header->next;
    free(header);
  }
}

static void finish (NuppCurlRequest *request, const char *error) {
  if (request->done) {
    return;
  }

  request->done = 1;

  if (error && request->error[0] == 0) {
    snprintf(request->error, sizeof(request->error), "%s", error);
  }

  if (request->attached) {
    curl_multi_remove_handle(request->client->multi, request->easy);
    request->attached = 0;
    request->client->pending--;
  }

  curl_easy_cleanup(request->easy);
  request->easy = NULL;
  curl_slist_free_all(request->headers);
  request->headers = NULL;
  free_reply(request);
  free(request->upload.bytes);
  request->upload.bytes = NULL;
  request->upload.used = 0;
  request->upload_closed = 1;
  request->ready |= NUPP_CURL_BODY | NUPP_CURL_UPLOAD;

  if (!request->head_ready) {
    request->ready |= NUPP_CURL_FAILED;

    if (request->error[0] == 0) {
      snprintf(request->error, sizeof(request->error), "missing HTTP response");
    }
  }
}

static void advance (NuppCurlClient *client, curl_socket_t socket, int events) {
  int running;
  CURLMcode code =
      curl_multi_socket_action(client->multi, socket, events, &running);

  if (code != CURLM_OK && code != CURLM_BAD_SOCKET && !client->failure) {
    client->failure = curl_multi_strerror(code);
  }

  if (client->failure) {
    for (NuppCurlRequest *r = client->requests; r; r = r->next) {
      finish(r, client->failure);
    }
  }
  else {
    int remaining;
    CURLMsg *msg;

    while ((msg = curl_multi_info_read(client->multi, &remaining)) != NULL) {
      if (msg->msg == CURLMSG_DONE) {
        NuppCurlRequest *request = NULL;
        curl_easy_getinfo(msg->easy_handle, CURLINFO_PRIVATE, &request);
        CURLcode result = msg->data.result;
        finish(request, result == CURLE_OK ? NULL : curl_easy_strerror(result));
      }
    }
  }

  schedule(client);
}

static void step_timer (NuppCurlClient *client) {
  uint64_t time = now();

  for (NuppCurlRequest *r = client->requests; r; r = r->next) {
    if (!r->done && r->deadline <= time) {
      finish(r, "HTTP request timed out");
    }
    else if (!r->done && r->stall_deadline <= time) {
      finish(r, "HTTP response stalled");
    }
  }

  if (client->curl_deadline <= time) {
    client->curl_deadline = UINT64_MAX;
    advance(client, CURL_SOCKET_TIMEOUT, 0);
  }
  else {
    schedule(client);
  }
}

static int curl_timer (CURLM *multi, long timeout, void *data) {
  NuppCurlClient *client = data;
  (void)multi;
  client->curl_deadline =
      timeout < 0 ? UINT64_MAX : after(now(), (uint64_t)timeout);

  return schedule(client) < 0 ? -1 : 0;
}

static void close_watch (NuppCurlClient *client, Watch *watch) {
  Watch **slot = &client->watches;

  while (*slot != watch) {
    slot = &(*slot)->next;
  }

  *slot = watch->next;
  /* libcurl can close and reuse the socket once REMOVE returns. */
  nupp_uv_socket_retire(watch->token);
  free(watch);
}

static int curl_socket (CURL *easy, curl_socket_t socket, int action,
                        void *data, void *assigned) {
  NuppCurlClient *client = data;
  Watch *watch = assigned;
  (void)easy;

  if (action == CURL_POLL_REMOVE) {
    if (watch) {
      curl_multi_assign(client->multi, socket, NULL);
      close_watch(client, watch);
    }

    return 0;
  }

  if (client->closing) {
    return 0;
  }

  if (!watch) {
    if (action == CURL_POLL_NONE) {
      return 0;
    }

    watch = calloc(1, sizeof(*watch));

    if (!watch) {
      client->failure = "out of memory for HTTP socket watch";

      return -1;
    }

    if ((uintmax_t)socket > INT_MAX) {
      free(watch);
      client->failure = "HTTP socket is outside the reactor's descriptor range";

      return -1;
    }

    int64_t token = nupp_uv_descriptor_open((int64_t)socket);

    if (token < 0) {
      free(watch);
      client->failure = "could not register the HTTP socket with the reactor";

      return -1;
    }

    watch->socket = socket;
    watch->token = (uint64_t)token;
    watch->next = client->watches;
    client->watches = watch;

    if (curl_multi_assign(client->multi, socket, watch) != CURLM_OK) {
      close_watch(client, watch);
      client->failure = "could not assign HTTP socket watch";

      return -1;
    }
  }

  uint64_t events = 0;

  if (action & CURL_POLL_IN) {
    events |= 1;
  }

  if (action & CURL_POLL_OUT) {
    events |= 2;
  }

  watch->interest = events;

  if (nupp_uv_socket_arm(watch->token, events) < 0) {
    client->failure = "could not arm the HTTP socket";

    return -1;
  }

  return 0;
}

static int step_client (NuppCurlClient *client) {
  if (nupp_uv_timer_take(client->timer) > 0) {
    step_timer(client);

    return 1;
  }

  for (Watch *watch = client->watches; watch; watch = watch->next) {
    int ready = nupp_uv_socket_take(watch->token);

    if (ready <= 0) {
      continue;
    }

    uint64_t token = watch->token;
    int events = (ready & 1 ? CURL_CSELECT_IN : 0) |
                 (ready & 2 ? CURL_CSELECT_OUT : 0) |
                 (ready & 12 ? CURL_CSELECT_ERR : 0);
    advance(client, watch->socket, events);

    /* CURLM may remove this watch or reuse its fd during advance. */
    for (Watch *current = client->watches; current; current = current->next) {
      if (current->token == token) {
        if (nupp_uv_socket_arm(token, current->interest) < 0) {
          client->failure = "could not rearm the HTTP socket";
          advance(client, CURL_SOCKET_TIMEOUT, 0);
        }

        break;
      }
    }

    return 1;
  }

  return 0;
}

void nupp_http_owner_step (void *context, uint32_t budget) {
  uintptr_t scope = (uintptr_t)context;

  while (budget) {
    int moved = 0;

    for (NuppCurlClient *c = clients; c && budget; c = c->next) {
      if (c->scope != scope) {
        continue;
      }

      if (step_client(c)) {
        moved = 1;
        budget--;
      }
    }

    if (!moved) {
      return;
    }
  }
}

uint32_t nupp_http_owner_ready (void *context) {
  uintptr_t scope = (uintptr_t)context;
  uint32_t flags = 0;

  for (NuppCurlClient *c = clients; c; c = c->next) {
    if (c->scope != scope) {
      continue;
    }

    if (c->pending) {
      flags |= NUPP_HTTP_ACTIVE;
    }

    if (nupp_uv_timer_ready(c->timer) > 0) {
      flags |= NUPP_HTTP_NATIVE_READY;
    }

    if (!(flags & NUPP_HTTP_NATIVE_READY)) {
      for (Watch *watch = c->watches; watch; watch = watch->next) {
        if (nupp_uv_socket_ready(watch->token) > 0) {
          flags |= NUPP_HTTP_NATIVE_READY;
          break;
        }
      }
    }

    if (c->watching) {
      for (NuppCurlRequest *r = c->requests; r; r = r->next) {
        if (r->ready) {
          flags |= NUPP_HTTP_MANAGED_READY;
          break;
        }
      }
    }
  }

  return flags;
}

static void free_client (NuppCurlClient *client) {
  free(client->proxy);
  free(client->no_proxy);
  free(client->credentials);
  free(client);
}

NuppCurlClient *nupp_curl_open (uv_loop_t *loop, uintptr_t scope,
                                const NuppCurlOptions *options,
                                const char **error) {
#ifdef _WIN32
  /* shortcut: the POSIX broker has int descriptors, upgrade once the reactor
   * supplies full-width Winsock registration. */
  *error = "Windows HTTP requires a full-width reactor socket broker";

  return NULL;
#endif
  *error = "invalid HTTP client options";

  if (!loop || loop != nupp_uv_loop() || !scope || !options ||
      !options->pending || !options->connections || !options->per_host ||
      options->connect_ms == 0 || options->connect_ms > LONG_MAX ||
      options->proxy_mode < 0 || options->proxy_mode > 2 ||
      (options->proxy_mode == 2 && !options->proxy)) {
    return NULL;
  }

#if UINT_MAX > LONG_MAX

  if (options->connections > LONG_MAX || options->per_host > LONG_MAX) {
    return NULL;
  }

#endif
  const curl_version_info_data *version = curl_version_info(CURLVERSION_NOW);

  if (!(version->features & CURL_VERSION_ASYNCHDNS)) {
    *error = "the pinned HTTP transport requires asynchronous DNS";

    return NULL;
  }

  *error = "could not initialize the HTTP transport";
  NuppCurlClient *client = calloc(1, sizeof(*client));

  if (!client) {
    return NULL;
  }

  client->scope = scope;
  client->token = issue_token();
  int64_t timer = client->token ? nupp_uv_timer_open() : -1;

  if (timer < 0) {
    free(client);

    return NULL;
  }

  client->loop = loop;
  client->timer = (uint64_t)timer;
  client->next = clients;
  clients = client;
  client->limit = options->pending;
  client->connect_ms = options->connect_ms;
  client->curl_deadline = UINT64_MAX;
  client->compressed = options->compressed;
  client->proxy_mode = options->proxy_mode;
  client->proxy = copy_text(options->proxy);
  client->no_proxy = copy_text(options->no_proxy);
  client->credentials = copy_text(options->credentials);
  client->multi = curl_multi_init();

  if (!client->multi || (options->proxy && !client->proxy) ||
      (options->no_proxy && !client->no_proxy) ||
      (options->credentials && !client->credentials) ||
      curl_multi_setopt(client->multi, CURLMOPT_SOCKETFUNCTION, curl_socket) ||
      curl_multi_setopt(client->multi, CURLMOPT_SOCKETDATA, client) ||
      curl_multi_setopt(client->multi, CURLMOPT_TIMERFUNCTION, curl_timer) ||
      curl_multi_setopt(client->multi, CURLMOPT_TIMERDATA, client) ||
      curl_multi_setopt(client->multi, CURLMOPT_MAX_TOTAL_CONNECTIONS,
                        (long)options->connections) ||
      curl_multi_setopt(client->multi, CURLMOPT_MAX_HOST_CONNECTIONS,
                        (long)options->per_host)) {
    nupp_curl_close(&client);

    return NULL;
  }

  *error = NULL;

  return client;
}

void nupp_curl_close (NuppCurlClient **owner) {
  NuppCurlClient *client = *owner;
  *owner = NULL;

  if (!client || client->closing) {
    return;
  }

  client->closing = 1;
  NuppCurlClient **slot = &clients;

  while (*slot != client) {
    slot = &(*slot)->next;
  }

  *slot = client->next;

  while (client->requests) {
    nupp_curl_release(client->requests);
  }

  if (client->multi) {
    curl_multi_cleanup(client->multi);
    client->multi = NULL;
  }

  while (client->watches) {
    close_watch(client, client->watches);
  }

  nupp_uv_timer_close(client->timer);
  free_client(client);
}

void nupp_curl_shutdown (uv_loop_t *loop) {
  NuppCurlClient *client = clients;

  while (client) {
    NuppCurlClient *next = client->next;

    if (client->loop == loop) {
      nupp_curl_close(&client);
    }

    client = next;
  }
}

uint64_t nupp_curl_client_token (const NuppCurlClient *client) {
  return client->token;
}

NuppCurlClient *nupp_curl_find_client (uintptr_t scope, uint64_t token) {
  for (NuppCurlClient *c = clients; c; c = c->next) {
    if (c->scope == scope && c->token == token) {
      return c;
    }
  }

  return NULL;
}

uint64_t nupp_curl_request_token (const NuppCurlRequest *request) {
  return request->token;
}

NuppCurlRequest *nupp_curl_find_request (uintptr_t scope, uint64_t token) {
  for (NuppCurlClient *c = clients; c; c = c->next) {
    if (c->scope != scope) {
      continue;
    }

    for (NuppCurlRequest *r = c->requests; r; r = r->next) {
      if (r->token == token) {
        return r;
      }
    }
  }

  return NULL;
}

void nupp_curl_close_scope (uintptr_t scope) {
  NuppCurlClient *client = clients;

  while (client) {
    NuppCurlClient *next = client->next;

    if (client->scope == scope) {
      nupp_curl_close(&client);
    }

    client = next;
  }
}

size_t nupp_curl_pending (const NuppCurlClient *client) {
  return client->pending;
}

void nupp_curl_watch_client (NuppCurlClient *client, int watching) {
  client->watching = watching;
}

static int lower (unsigned char value) {
  return value >= 'A' && value <= 'Z' ? value + ('a' - 'A') : value;
}

static int matches (const char *bytes, size_t length, const char *name) {
  if (length != strlen(name)) {
    return 0;
  }

  for (size_t i = 0; i < length; i++) {
    if (lower((unsigned char)bytes[i]) != name[i]) {
      return 0;
    }
  }

  return 1;
}

static int token (const char *bytes, size_t count) {
  if (count == 0) {
    return 0;
  }

  for (size_t i = 0; i < count; i++) {
    unsigned char ch = (unsigned char)bytes[i];
    int c = lower(ch);

    if (!(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') &&
        (ch == 0 || !strchr("!#$%&'*+-.^_`|~", ch))) {
      return 0;
    }
  }

  return 1;
}

static int append_header (NuppCurlRequest *r, const char *line) {
  struct curl_slist *head = curl_slist_append(r->headers, line);

  if (!head) {
    return 0;
  }

  r->headers = head;

  return 1;
}

static const char *request_headers (NuppCurlRequest *r,
                                    const NuppCurlSend *send) {
  int64_t declared = -1;
  int expect = 0;
  size_t total = 0;

  for (size_t i = 0; i < send->header_count; i++) {
    const NuppCurlHeader *header = &send->headers[i];
    size_t n = header->name_length, v = header->value_length;

    if (n > HEAD_LIMIT - total || v > HEAD_LIMIT - total - n ||
        HEAD_LIMIT - total - n - v < 2) {
      return "request headers exceeded 262144 bytes";
    }

    total += n + v + 2;

    if (!token(header->name, n)) {
      return "invalid HTTP header name";
    }

    for (size_t j = 0; j < v; j++) {
      unsigned char ch = (unsigned char)header->value[j];

      if ((ch < 32 && ch != '\t') || ch == 127) {
        return "invalid HTTP header value";
      }
    }

    const char *name = header->name;

    if (matches(name, n, "transfer-encoding")) {
      return "Transfer-Encoding is chosen by the transport";
    }

    if (matches(name, n, "content-length")) {
      if (declared >= 0 || v == 0) {
        return "invalid HTTP Content-Length";
      }

      declared = 0;

      for (size_t j = 0; j < v; j++) {
        int digit = header->value[j] - '0';

        if (digit < 0 || digit > 9 || declared > (INT64_MAX - digit) / 10) {
          return "Content-Length must contain decimal digits";
        }

        declared = declared * 10 + digit;
      }

      if (r->length >= 0 && r->length != declared) {
        return "Content-Length does not match the request body";
      }

      r->length = declared;
    }

    if (matches(name, n, "accept-encoding") || matches(name, n, "range")) {
      r->decode = 0;
    }

    expect |= matches(name, n, "expect");
    char *line = malloc(n + v + 3);

    if (!line) {
      return "out of memory for HTTP request headers";
    }

    memcpy(line, name, n);
    line[n] = v ? ':' : ';';
    line[n + 1] = ' ';

    if (v) {
      memcpy(line + n + 2, header->value, v);
    }

    line[n + (v ? v + 2 : 1)] = 0;
    int ok = append_header(r, line);
    free(line);

    if (!ok) {
      return "out of memory for HTTP request headers";
    }
  }

  if (!expect && !append_header(r, "Expect:")) {
    return "out of memory for HTTP request headers";
  }

  return NULL;
}

static void encode32 (unsigned char *out, size_t value) {
  for (unsigned i = 0; i < 4; i++) {
    out[i] = (unsigned char)(value >> (i * 8));
  }
}

static int omit_header (const NuppCurlRequest *r, const char *name, size_t n) {
  return r->strip_encoding && (matches(name, n, "content-encoding") ||
                               matches(name, n, "content-length"));
}

static int pack_head (NuppCurlRequest *r) {
  size_t room = 4 + 16 * r->reply_count + r->reply_bytes;
  r->head = malloc(room);

  if (!r->head) {
    return 0;
  }

  size_t count = 0;

  for (Reply *h = r->reply; h; h = h->next) {
    count += !omit_header(r, h->text, h->name);
  }

  encode32(r->head, count);
  size_t index = 4, offset = 4 + 16 * count;

  for (Reply *h = r->reply; h; h = h->next) {
    if (omit_header(r, h->text, h->name)) {
      continue;
    }

    size_t n = h->name, v = h->value;
    encode32(r->head + index, offset);
    encode32(r->head + index + 4, n);

    for (size_t i = 0; i < n; i++) {
      r->head[offset + i] = (unsigned char)lower((unsigned char)h->text[i]);
    }

    offset += n;
    encode32(r->head + index + 8, offset);
    encode32(r->head + index + 12, v);
    memcpy(r->head + offset, h->text + n, v);
    offset += v;
    index += 16;
  }

  r->head_length = offset;

  return 1;
}

static int status_version (const char *text, size_t length) {
  if (length == 8 && memcmp(text, "HTTP/1.", 7) == 0) {
    if (text[7] == '0' || text[7] == '1') {
      return 10 + text[7] - '0';
    }
  }

  return length == 6 && text[5] == '2' ? 20 : 0;
}

static size_t on_header (char *input, size_t size, size_t count, void *data) {
  NuppCurlRequest *r = data;
  size_t bytes = size * count;

  if (r->head_ready) {
    return bytes; /* Trailers are not part of the response head. */
  }

  size_t n = bytes;

  while (n > 0 && (input[n - 1] == '\r' || input[n - 1] == '\n')) {
    n--;
  }

  if (n >= 5 && memcmp(input, "HTTP/", 5) == 0) {
    const char *space = memchr(input, ' ', n);

    if (!space || input + n - space < 4 || space[1] < '1' || space[1] > '5' ||
        space[2] < '0' || space[2] > '9' || space[3] < '0' || space[3] > '9') {
      return 0;
    }

    r->status = (space[1] - '0') * 100 + (space[2] - '0') * 10 + space[3] - '0';
    r->version = status_version(input, (size_t)(space - input));

    return r->version ? bytes : 0;
  }

  if (r->status < 200) {
    return bytes; /* Ignore informational heads. */
  }

  if (n == 0) {
    if (!pack_head(r)) {
      return 0;
    }

    free_reply(r);
    r->head_ready = 1;
    r->upload_closed = 1;
    r->ready |= NUPP_CURL_HEADERS | NUPP_CURL_UPLOAD;

    if (r->stall_ms) {
      r->stall_deadline = after(now(), r->stall_ms);
    }

    return bytes;
  }

  const char *colon = memchr(input, ':', n);

  if (!colon || colon == input || memchr(input, 0, n)) {
    return 0;
  }

  size_t name = (size_t)(colon - input);
  const char *value = colon + 1;
  const char *end = input + n;

  while (value < end && (*value == ' ' || *value == '\t')) {
    value++;
  }

  while (value < end && (end[-1] == ' ' || end[-1] == '\t')) {
    end--;
  }

  size_t v = (size_t)(end - value);

  if (4 + 16 * (r->reply_count + 1) + r->reply_bytes + name + v > HEAD_LIMIT) {
    snprintf(r->error, sizeof(r->error),
             "response headers exceeded 262144 bytes");

    return 0;
  }

  Reply *header = malloc(sizeof(*header) + name + v);

  if (!header) {
    return 0;
  }

  header->next = NULL;
  header->name = name;
  header->value = v;
  memcpy(header->text, input, name);
  memcpy(header->text + name, value, v);
  *r->reply_tail = header;
  r->reply_tail = &header->next;
  r->reply_count++;
  r->reply_bytes += name + v;

  if (r->decode && matches(input, name, "content-encoding") &&
      (matches(value, v, "gzip") || matches(value, v, "deflate"))) {
    r->strip_encoding = 1;
  }

  return bytes;
}

static size_t on_body (char *bytes, size_t size, size_t count, void *data) {
  NuppCurlRequest *r = data;
  size_t n = size * count;

  if (n > UINT64_MAX - r->received ||
      (r->max_bytes && n > r->max_bytes - r->received)) {
    snprintf(r->error, sizeof(r->error), "response body exceeded %llu bytes",
             (unsigned long long)r->max_bytes);

    return CURL_WRITEFUNC_ERROR;
  }

  if (n > r->body.room - r->body.used) {
    r->paused |= CURLPAUSE_RECV;

    return CURL_WRITEFUNC_PAUSE;
  }

  if (!append(&r->body, bytes, n)) {
    return CURL_WRITEFUNC_ERROR;
  }

  r->received += n;

  if (r->stall_ms) {
    r->stall_deadline = after(now(), r->stall_ms);
  }

  if (r->body_armed) {
    r->body_armed = 0;
    r->ready |= NUPP_CURL_BODY;
  }

  return n;
}

static size_t on_upload (char *bytes, size_t size, size_t count, void *data) {
  NuppCurlRequest *r = data;

  if (r->upload.used) {
    size_t n = take(&r->upload, bytes, size * count);

    if (r->streaming && r->upload.room - r->upload.used >= UPLOAD_OFFER) {
      r->ready |= NUPP_CURL_UPLOAD;
    }

    return n;
  }

  if (r->upload_eof || r->upload_closed) {
    return 0;
  }

  r->paused |= CURLPAUSE_SEND;

  return CURL_READFUNC_PAUSE;
}

static const char *env_proxy (const char *upper, const char *lower) {
  const char *value = getenv(upper);

  return value ? value : getenv(lower);
}

static const char *request_proxy (NuppCurlClient *client, const char *url) {
  if (client->proxy_mode == 2) {
    return client->proxy;
  }

  if (client->proxy_mode == 1 || getenv("REQUEST_METHOD")) {
    return "";
  }

  const char *value = strncmp(url, "https:", 6) == 0
                          ? env_proxy("HTTPS_PROXY", "https_proxy")
                          : env_proxy("HTTP_PROXY", "http_proxy");

  if (!value || !*value) {
    value = env_proxy("ALL_PROXY", "all_proxy");
  }

  return value ? value : "";
}

static const char *configure (NuppCurlRequest *r, const NuppCurlSend *send) {
  NuppCurlClient *client = r->client;
  CURLcode code;
#define SET(option, value)                                                     \
  do {                                                                         \
    code = curl_easy_setopt(r->easy, option, value);                           \
    if (code != CURLE_OK) {                                                    \
      return curl_easy_strerror(code);                                         \
    }                                                                          \
  } while (0)

  SET(CURLOPT_ERRORBUFFER, r->error);
  SET(CURLOPT_PRIVATE, r);
  SET(CURLOPT_URL, send->url);
  SET(CURLOPT_PROTOCOLS_STR, "http,https");
  SET(CURLOPT_PATH_AS_IS, 1L);
  SET(CURLOPT_NOSIGNAL, 1L);
  SET(CURLOPT_FOLLOWLOCATION, 0L);
  SET(CURLOPT_CONNECTTIMEOUT_MS, (long)client->connect_ms);
  SET(CURLOPT_SSL_VERIFYPEER, send->insecure ? 0L : 1L);
  SET(CURLOPT_SSL_VERIFYHOST, send->insecure ? 0L : 2L);
  SET(CURLOPT_SSLVERSION, (long)CURL_SSLVERSION_TLSv1_2);
  SET(CURLOPT_PROXY_SSLVERSION, (long)CURL_SSLVERSION_TLSv1_2);
  SET(CURLOPT_SSL_OPTIONS, (long)CURLSSLOPT_NATIVE_CA);
  SET(CURLOPT_PROXY_SSL_OPTIONS, (long)CURLSSLOPT_NATIVE_CA);

  if (send->insecure) {
    SET(CURLOPT_FRESH_CONNECT, 1L);
    SET(CURLOPT_FORBID_REUSE, 1L);
  }

  SET(CURLOPT_PROXY, request_proxy(client, send->url));
  SET(CURLOPT_SUPPRESS_CONNECT_HEADERS, 1L);

  if (client->no_proxy) {
    SET(CURLOPT_NOPROXY, client->no_proxy);
  }

  if (client->proxy_mode == 2 && client->credentials) {
    SET(CURLOPT_PROXYUSERPWD, client->credentials);
    SET(CURLOPT_PROXYAUTH, (long)CURLAUTH_BASIC);
  }

  if (r->decode) {
    SET(CURLOPT_ACCEPT_ENCODING, "gzip, deflate");
  }

  SET(CURLOPT_HTTPHEADER, r->headers);
  SET(CURLOPT_HEADERFUNCTION, on_header);
  SET(CURLOPT_HEADERDATA, r);
  SET(CURLOPT_WRITEFUNCTION, on_body);
  SET(CURLOPT_WRITEDATA, r);

  if (send->body) {
    SET(CURLOPT_UPLOAD, 1L);
    SET(CURLOPT_READFUNCTION, on_upload);
    SET(CURLOPT_READDATA, r);
    SET(CURLOPT_INFILESIZE_LARGE, (curl_off_t)r->length);

    if (r->streaming) {
      SET(CURLOPT_NUPP_STOP_UPLOAD_ON_RESPONSE, 1L);
    }
  }
  else if (strcmp(send->method, "HEAD") == 0) {
    SET(CURLOPT_NOBODY, 1L);
  }

  SET(CURLOPT_CUSTOMREQUEST, send->method);
#undef SET

  return NULL;
}

NuppCurlRequest *nupp_curl_send (NuppCurlClient *client,
                                 const NuppCurlSend *send, const char **error) {
  *error = client->failure;

  if (client->failure || client->pending >= client->limit) {
    return NULL;
  }

  *error = "invalid HTTP request";

  if (!send || !send->url || !send->method ||
      !token(send->method, strlen(send->method)) || !send->timeout_ms ||
      send->body < 0 || send->body > 2 || send->length < -1 ||
      (send->body == 1 &&
       (send->length < 0 || (uint64_t)send->length > SIZE_MAX ||
        (send->length != 0 && !send->bytes))) ||
      (send->header_count && !send->headers)) {
    return NULL;
  }

  *error = "could not allocate HTTP request";
  NuppCurlRequest *r = calloc(1, sizeof(*r));

  if (!r) {
    return NULL;
  }

  r->token = issue_token();

  if (!r->token) {
    *error = "HTTP handle space is exhausted";
    free(r);

    return NULL;
  }

  r->client = client;
  r->next = client->requests;
  client->requests = r;
  r->reply_tail = &r->reply;
  r->decode = client->compressed;
  r->body.room = BODY_WINDOW;
  r->upload.room = send->body == 1 ? (size_t)send->length : UPLOAD_WINDOW;
  r->upload_eof = send->body != 2;
  r->streaming = send->body == 2;
  r->length = send->body ? send->length : 0;
  r->deadline = after(now(), send->timeout_ms);
  r->stall_ms = send->stall_ms;
  r->stall_deadline = UINT64_MAX;
  r->max_bytes = send->max_bytes;
  r->easy = curl_easy_init();

  if (!r->easy ||
      (send->body == 1 && !append(&r->upload, send->bytes, r->upload.room))) {
    goto fail;
  }

  *error = request_headers(r, send);

  if (!*error) {
    *error = configure(r, send);
  }

  if (*error) {
    goto fail;
  }

  CURLMcode code = curl_multi_add_handle(client->multi, r->easy);

  if (code != CURLM_OK) {
    *error = curl_multi_strerror(code);
    goto fail;
  }

  r->attached = 1;
  client->pending++;

  if (schedule(client) < 0) {
    *error = "could not arm HTTP timer";
    goto fail;
  }

  return r;

fail:
  nupp_curl_release(r);

  return NULL;
}

unsigned nupp_curl_ready (NuppCurlRequest *r) {
  unsigned result = r->ready;
  r->ready = 0;

  return result;
}

int nupp_curl_head (const NuppCurlRequest *r, NuppCurlHead *out) {
  if (r->head_ready) {
    *out = (NuppCurlHead){r->head, r->head_length, r->status, r->version, NULL};

    return 1;
  }

  if (r->done) {
    *out = (NuppCurlHead){NULL, 0, 0, 0, r->error};

    return -1;
  }

  return 0;
}

const char *nupp_curl_error (const NuppCurlRequest *r) {
  return r->error[0] ? r->error : NULL;
}

static void unpause (NuppCurlRequest *r, int direction) {
  if (r->paused & direction) {
    r->paused &= ~direction;
    CURLcode code = curl_easy_pause(r->easy, r->paused);

    if (code != CURLE_OK) {
      finish(r, curl_easy_strerror(code));
    }

    schedule(r->client);
  }
}

int nupp_curl_offer (NuppCurlRequest *r, const void *bytes, size_t count) {
  if (r->done || !r->streaming || r->upload_closed || r->upload_eof) {
    return -1;
  }

  if (count > UPLOAD_OFFER || (count && !bytes) ||
      count > UINT64_MAX - r->offered) {
    finish(r, "invalid HTTP upload chunk");
    schedule(r->client);

    return -1;
  }

  if (r->length >= 0 && (r->offered + count > (uint64_t)r->length ||
                         (!count && r->offered != (uint64_t)r->length))) {
    char reason[CURL_ERROR_SIZE];

    if (count) {
      snprintf(reason, sizeof(reason),
               "the upload is longer than its declared %llu bytes",
               (unsigned long long)r->length);
    }
    else {
      snprintf(reason, sizeof(reason),
               "the upload ended after %llu of its declared %llu bytes",
               (unsigned long long)r->offered, (unsigned long long)r->length);
    }

    finish(r, reason);
    schedule(r->client);

    return -1;
  }

  if (count > r->upload.room - r->upload.used) {
    return 0;
  }

  if (!append(&r->upload, bytes, count)) {
    finish(r, "out of memory for HTTP upload");
    schedule(r->client);

    return -1;
  }

  r->offered += count;
  r->upload_eof = count == 0;
  unpause(r, CURLPAUSE_SEND);

  return 1;
}

void nupp_curl_arm (NuppCurlRequest *r) {
  if (r->body.used || r->done) {
    r->ready |= NUPP_CURL_BODY;
  }
  else {
    r->body_armed = 1;
  }
}

int64_t nupp_curl_read (NuppCurlRequest *r, void *bytes, size_t count,
                        const char **error) {
  size_t n = take(&r->body, bytes, count);

  if (n) {
    if (!r->done && r->body.room - r->body.used >= CURL_MAX_WRITE_SIZE) {
      unpause(r, CURLPAUSE_RECV);
    }

    return (int64_t)n;
  }

  if (!r->done) {
    return -1;
  }

  if (r->error[0]) {
    *error = r->error;

    return -2;
  }

  return 0;
}

void nupp_curl_cancel (NuppCurlRequest *r) {
  r->body.used = 0;
  finish(r, "HTTP request cancelled");
  schedule(r->client);
}

void nupp_curl_release (NuppCurlRequest *r) {
  NuppCurlClient *client = r->client;
  finish(r, "HTTP request released");
  NuppCurlRequest **slot = &client->requests;

  while (*slot != r) {
    slot = &(*slot)->next;
  }

  *slot = r->next;
  free(r->head);
  free(r->body.bytes);
  free(r);
  schedule(client);
}
