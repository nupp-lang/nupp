/**
 * @file
 * @brief CBMC proof of the TCP read, write and close contracts.
 *
 * Models libuv on one owner loop, with outstanding writes completing before
 * close drains. Four-byte slots bound the model.
 */

#include "proofintrinsics.h"
#define NUPP_TCP_WINDOW_BYTES 4
#include "../../native/core-bridge/tcp.c" /* NOLINT(bugprone-suspicious-include) */

enum { SAMPLE = NUPP_TCP_WINDOW_BYTES };

static uv_stream_t *reading;
static uv_alloc_cb allocate;
static uv_read_cb receive;
static uv_write_t *writing;
static uv_buf_t borrowed;
static uv_write_cb writtenback;
static int writeerror;
static uv_handle_t *closing;
static uv_close_cb closedback;

int uv_tcp_init (uv_loop_t *loop, uv_tcp_t *handle) {
  __CPROVER_assert(loop && handle, "initialization gets live objects");

  return 0;
}

uv_buf_t uv_buf_init (char *base, unsigned int len) {
  return (uv_buf_t){.base = base, .len = len};
}

int uv_read_start (uv_stream_t *handle, uv_alloc_cb allocator, uv_read_cb cb) {
  __CPROVER_assert(!reading && !closing, "reads start only on an idle stream");
  reading = handle;
  allocate = allocator;
  receive = cb;

  return 0;
}

int uv_read_stop (uv_stream_t *handle) {
  __CPROVER_assert(reading == handle, "only the running read is stopped");
  reading = NULL;

  return 0;
}

int uv_write (uv_write_t *request, uv_stream_t *handle,
              const uv_buf_t buffers[], unsigned int count, uv_write_cb cb) {
  (void)handle;
  __CPROVER_assert(!writing && !closing && count == 1,
                   "only one write owns the slot at a time");

  if (writeerror) {
    return writeerror;
  }

  writing = request;
  borrowed = buffers[0];
  writtenback = cb;

  return 0;
}

void uv_close (uv_handle_t *handle, uv_close_cb cb) {
  __CPROVER_assert(!closing, "native close is initiated only once");
  reading = NULL;
  closing = handle;
  closedback = cb;
}

/** Supplies one native read result, with bytes only for a positive result. */
static void deliver (const char *bytes, int count) {
  __CPROVER_assert(reading != NULL, "a read callback requires a pending read");
  uv_buf_t buffer;
  allocate((uv_handle_t *)reading, SAMPLE, &buffer);

  if (count > 0) {
    __CPROVER_assert((size_t)count <= buffer.len,
                     "the supplied read buffer can fit the event");
    memcpy(buffer.base, bytes, (size_t)count);
  }

  receive(reading, count, &buffer);
}

/** Checks that exactly the requested bytes are drained from a sample read. */
static void checkreads (NuppTcp *tcp) {
  char input[SAMPLE];
  char output[SAMPLE + 1] = {0};

  for (unsigned i = 0; i < SAMPLE; ++i) {
    input[i] = (char)nondet_byte();
  }

  size_t first = nondet_byte();
  __CPROVER_assume(0 < first && first < SAMPLE);
  int result = nupptcpreceive(tcp, output, 0);
  __CPROVER_assert(result == 0 && !reading, "an empty read starts no request");
  result = nupptcpreceive(tcp, output, first);
  __CPROVER_assert(result == UV_EAGAIN, "read waits for the owner loop");
  deliver(NULL, 0);
  result = nupptcpreceive(tcp, output, first);
  __CPROVER_assert(result == UV_EAGAIN && reading,
                   "a zero-byte callback leaves the read active");
  deliver(input, SAMPLE);
  result = nupptcpreceive(tcp, output, first);
  __CPROVER_assert(result == (int)first && !reading,
                   "a partial read drains only its requested prefix");
  result = nupptcpreceive(tcp, output + first, sizeof(output) - first);
  __CPROVER_assert(result == (int)(SAMPLE - first) && !reading &&
                       !memcmp(input, output, SAMPLE) && output[SAMPLE] == 0,
                   "the next read returns the preserved suffix in order");
  result = nupptcpreceive(tcp, output, sizeof(output));
  __CPROVER_assert(result == UV_EAGAIN && reading,
                   "a drained slot can start another read");
  int status = (nondet_byte() & 1) ? UV_EOF : UV_EIO;
  deliver(NULL, status);
  result = nupptcpreceive(tcp, output, sizeof(output));
  __CPROVER_assert(result == (status == UV_EOF ? 0 : status) && !reading,
                   "EOF and read errors are reported without rearming");
}

/** Completes one write and checks the snapshot still owned by libuv. */
static void finishwrite (const char *expected, int status) {
  __CPROVER_assert(writing && borrowed.len == SAMPLE &&
                       !memcmp(borrowed.base, expected, SAMPLE),
                   "the pending write buffer is unchanged until its callback");
  uv_write_t *request = writing;
  writing = NULL;
  writtenback(request, status);
}

/** Checks write admission and close with completion on either side of close. */
static void checkclose (NuppTcp *tcp) {
  char input[SAMPLE + 1] = {0}, expected[SAMPLE];

  for (unsigned i = 0; i < SAMPLE; ++i) {
    input[i] = expected[i] = (char)nondet_byte();
  }

  writeerror = UV_EIO;
  int result = nupptcpsend(tcp, input, SAMPLE);
  __CPROVER_assert(result == UV_EIO && !writing && !nupptcppending(tcp),
                   "a failed submit leaves the write slot available");
  writeerror = 0;
  result = nupptcpsend(tcp, input, sizeof(input));
  __CPROVER_assert(result == SAMPLE && nupptcppending(tcp) == SAMPLE,
                   "an accepted write owns one pending slot");
  memset(input, 0, sizeof(input));
  result = nupptcpsend(tcp, input, SAMPLE);
  __CPROVER_assert(result == UV_EAGAIN && nupptcppending(tcp) == SAMPLE,
                   "a second send cannot replace an outstanding write");
  result = nupptcpfree(tcp);
  __CPROVER_assert(result == UV_EBUSY, "a live endpoint cannot be freed");

  if (nondet_byte() & 1) {
    int status = (nondet_byte() & 1) ? UV_EIO : 0;
    finishwrite(expected, status);
    __CPROVER_assert(nupptcppending(tcp) == status,
                     "completion releases the slot or records its error");
  }

  nupptcpclose(tcp);
  nupptcpclose(tcp);
  result = nupptcpsend(tcp, input, SAMPLE);
  __CPROVER_assert(result == UV_EBADF, "a closing endpoint rejects writes");
  result = nupptcpfree(tcp);
  __CPROVER_assert(result == UV_EBUSY,
                   "close initiation leaves the endpoint alive");

  if (writing) {
    finishwrite(expected, UV_ECANCELED);
    __CPROVER_assert(nupptcppending(tcp) == UV_ECANCELED,
                     "the canceled write reports its terminal status");
    result = nupptcpfree(tcp);
    __CPROVER_assert(result == UV_EBUSY,
                     "the write callback alone cannot release the endpoint");
  }

  __CPROVER_assert(closing && closedback && !writing,
                   "the close callback runs after the write slot drains");
  closedback(closing);
  result = nupptcpfree(tcp);
  __CPROVER_assert(result == 0, "the drained endpoint is released");
}

int main (void) {
  uv_loop_t loop = {0};
  NuppTcp *tcp = NULL;
  int result = nupptcpopen(&loop, &tcp);

  if (result != 0) {
    __CPROVER_assert(result == UV_ENOMEM && tcp == NULL,
                     "failed allocation publishes no endpoint");

    return 0;
  }

  checkreads(tcp);
  checkclose(tcp);

  return 0;
}
