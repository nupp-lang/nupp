/* C-only artifact check. Nupp's scheduling and cancellation need their own tests. */
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <uv.h>

#if defined(_WIN32) && defined(_M_X64)
#define HOST_TARGET "x86_64-pc-windows-msvc"
#elif defined(__APPLE__) && defined(__aarch64__)
#define HOST_TARGET "aarch64-apple-darwin"
#elif defined(__APPLE__) && defined(__x86_64__)
#define HOST_TARGET "x86_64-apple-darwin"
#elif defined(__linux__) && defined(__GLIBC__) && defined(__aarch64__)
#define HOST_TARGET "aarch64-unknown-linux-gnu"
#elif defined(__linux__) && defined(__GLIBC__) && defined(__x86_64__)
#define HOST_TARGET "x86_64-unknown-linux-gnu"
#else
#error Unsupported libuv consumer target
#endif

static unsigned fired, closed;

static void on_close(uv_handle_t* handle) {
  (void) handle;
  closed++;
}

static void on_timer(uv_timer_t* timer) {
  fired++;
  uv_close((uv_handle_t*) timer, on_close);
}

int main(void) {
  uv_loop_t loop;
  uv_timer_t timer;
  assert(strcmp(HOST_TARGET, NUPP_EXPECT_TARGET) == 0);
  assert(strcmp(uv_version_string(), NUPP_EXPECT_VERSION) == 0);
  assert(uv_version() == UV_VERSION_HEX);
  assert(uv_loop_size() == sizeof(loop));
  assert(uv_handle_size(UV_TIMER) == sizeof(timer));
  assert(uv_req_size(UV_FS) == sizeof(uv_fs_t));
  assert(uv_loop_init(&loop) == 0);
  assert(uv_timer_init(&loop, &timer) == 0);
  assert(uv_timer_start(&timer, on_timer, 0, 0) == 0);
  assert(uv_run(&loop, UV_RUN_DEFAULT) == 0);
  assert(fired == 1 && closed == 1);
  assert(uv_loop_close(&loop) == 0);
  /* The loaded module must be the moved sidecar, never a system libuv. */
  uv_lib_t library;
#ifdef _WIN32
  const char* sidecar = "bin/uv.dll";
#elif defined(__APPLE__)
  const char* sidecar = "lib/libuv.1.dylib";
#else
  const char* sidecar = "lib/libuv.so.1";
#endif
  void* symbol = NULL;
  assert(uv_dlopen(sidecar, &library) == 0);
  assert(uv_dlsym(&library, "uv_version", &symbol) == 0);
  assert(symbol == (void*) uv_version);
  uv_dlclose(&library);
  printf("{\"target\":\"%s\",\"libuv\":\"%s\",\"loopSize\":%zu,"
         "\"timerSize\":%zu,\"fsSize\":%zu,\"timerFired\":%u,"
         "\"closeDrained\":%u,\"relocatedSidecar\":true,\"passed\":true}\n",
         HOST_TARGET, uv_version_string(), sizeof(loop), sizeof(timer),
         sizeof(uv_fs_t), fired, closed);
  return 0;
}
