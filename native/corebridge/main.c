/**
 * @file
 * @brief Loads a native core bundle and invokes its generated entry.
 *
 * The native core's startup transport. It reads a core bundle, maps the
 * bundle's code, data and scratch regions, and enters the Nupp code the
 * bundle carries. That code is Nupp; this file knows no value, frame, task,
 * collector, instruction or optimizer layout.
 *
 * scripts/core-bridge builds it as nupp-core. guard.c and
 * tests/core/bridgecontracts.c include it whole, with main renamed, so they
 * can reach its static functions; guard.c also defines NUPP_CORE_GUARD, which
 * fences scratch and checks that the entry preserves the C ABI.
 */

#ifndef _WIN32

/* MAP_ANONYMOUS, realpath and the rest of POSIX the bridge uses. */
#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1
#endif

#include "reactor.h"
#include "transport.h"
#include "netbridge.h"
#include "../httpcurl/uriidna.h"

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <uv.h>

#include "hostwin64.h"
#else
#include <dlfcn.h>
#include <sys/mman.h>
#include <unistd.h>
#endif

#ifdef NUPP_CORE_HTTP
#include "../httpcurl/transport.h"
#include <curl/curl.h>
#endif

#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#endif

/* The number of elements in an array the compiler can see the size of. */
#define ARRAY_LENGTH(array) (sizeof(array) / sizeof(*(array)))

enum { BUNDLE_ARM64 = 1, BUNDLE_WIN64 = 2 };

#if defined(_WIN32) && (defined(_M_X64) || defined(__x86_64__))
#define HOST_SUPPORTED 1

enum { HOST_ARCH = BUNDLE_WIN64, INSTRUCTION_BYTES = 1 };
#elif !defined(_WIN32) && (defined(__aarch64__) || defined(__arm64__))
#define HOST_SUPPORTED 1

enum { HOST_ARCH = BUNDLE_ARM64, INSTRUCTION_BYTES = 4 };
#else
#define HOST_SUPPORTED 0

enum { HOST_ARCH = 0, INSTRUCTION_BYTES = 1 };
#endif

/* Every word the transport reads or writes is a little-endian uint64. */
enum { WORD_BYTES = 8 };

/* A bundle is BUNDLE_MAGIC, then BUNDLE_FIELDS header words, then the code
 * and data regions back to back. Scratch is not stored: it is mapped zeroed.
 * The guest and unit runners write this layout. */
#define BUNDLE_MAGIC "NUPPCORE"

enum { MAGIC_BYTES = 8 };

enum bundlefield {
  BUNDLE_VERSION, /* BUNDLE_FORMAT */
  BUNDLE_ARCHITECTURE, /* Host-specific instruction set and ABI. */
  BUNDLE_ENTRY, /* the entry's byte offset within code */
  BUNDLE_CODE_BYTES,
  BUNDLE_DATA_BYTES,
  BUNDLE_SCRATCH_BYTES,
  BUNDLE_OUTPUT_WORDS, /* how many words the entry answers */
  BUNDLE_RESERVED, /* zero */
  BUNDLE_FIELDS
};

enum {
  BUNDLE_FORMAT = 1,
  HEADER_BYTES = MAGIC_BYTES + BUNDLE_FIELDS * WORD_BYTES,
};

/* Each region is at most REGION bytes and all three together at most twice
 * that. Input and output are each at most MAX_WORDS words. */
static const uint64_t REGION = UINT64_C(1024) * 1024 * 1024;
static const uint64_t MAX_WORDS = UINT64_C(1024) * 1024;

/* The entry is called with a pointer to this packet and to the output words.
 * The generated entry loads these fields at fixed word offsets. */
enum packetfield {
  PACKET_VERSION, /* PACKET_FORMAT */
  PACKET_CODE,
  PACKET_CODE_BYTES,
  PACKET_DATA,
  PACKET_DATA_BYTES,
  PACKET_SCRATCH,
  PACKET_SCRATCH_BYTES,
  PACKET_IMPORTS,
  PACKET_IMPORT_COUNT,
  PACKET_INPUT,
  PACKET_INPUT_WORDS,
  PACKET_OUTPUT_WORDS,
  PACKET_FIELDS
};

enum { PACKET_FORMAT = 1 };

/* The packet's import table: the addresses of the C the Nupp code calls. The
 * I/O pool's six (reactor.h) come first, then the OS loader, then the
 * symbol table guestforeign.nupp fills as it resolves foreign symbols. */
enum import {
  IMPORT_IO_START,
  IMPORT_IO_SUBMIT,
  IMPORT_IO_TAKE,
  IMPORT_IO_FINISH,
  IMPORT_IO_CANCEL,
  IMPORT_IO_SETTLE,
  IMPORT_DLOPEN,
  IMPORT_DLSYM,
  IMPORT_DLCLOSE,
  IMPORT_SYMBOLS,
  IMPORT_COUNT
};

enum { SYMBOL_TABLE_WORDS = 1024 };

/* The entry's status when the guest has already reported, on standard
 * error, an error it did not catch (GUEST_ERROR_STATUS in context.nupp). */
enum { GUEST_ERROR_STATUS = 6 };

static uint64_t symboltable[SYMBOL_TABLE_WORDS];

/* The directory the bundle was loaded from. The Nupp loader finds it by name
 * through the import table and resolves artifact-relative paths against it. */
#ifdef _WIN32
__declspec(dllexport)
#endif
const char *nupp_core_artifact_directory;
static _Thread_local int retain_guest_backing;
static uint64_t processargumentcount;
static char **processarguments;

/** Returns a UTF-8 argument from the bridge's command line. */
#ifdef _WIN32
__declspec(dllexport)
#endif
const char *nupp_core_argument_at (uint64_t index) {
  return index < processargumentcount ? processarguments[index] : NULL;
}

void nupp_core_retain_guest_backing (void) {
  retain_guest_backing = 1;
}

#ifndef NUPP_CORE_NET
int64_t nuppnetcall (void *scope, uint64_t op, uint64_t key, void *bytes,
                     uint64_t size, uint64_t option) {
  (void)scope;
  (void)op;
  (void)key;
  (void)bytes;
  (void)size;
  (void)option;

  return -ENOSYS;
}

void nuppnetdetach (void *scope) {
  (void)scope;
}
#endif

#ifdef NUPP_CORE_HTTP
static _Thread_local void *http_scope;
static int curl_initialized;

_Static_assert((int)NUPP_UV_OWNER_ACTIVE == (int)NUPP_HTTP_ACTIVE &&
                   (int)NUPP_UV_OWNER_NATIVE_READY ==
                       (int)NUPP_HTTP_NATIVE_READY &&
                   (int)NUPP_UV_OWNER_MANAGED_READY ==
                       (int)NUPP_HTTP_MANAGED_READY,
               "HTTP owner flags must match the reactor");

int nupp_http_scope_attach (void *scope) {
  if (!scope) {
    return -EINVAL;
  }

  if (http_scope) {
    return http_scope == scope ? 0 : -EBUSY;
  }

  if (!curl_initialized) {
    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK) {
      return -EIO;
    }

    curl_initialized = 1;
  }

  int status = nupp_uv_set_owner_driver(nupp_http_owner_step,
                                        nupp_http_owner_ready, scope);

  if (!status) {
    http_scope = scope;
  }

  return status;
}

int nupp_http_scope_detach (void *scope) {
  if (!scope || scope != http_scope) {
    return 0;
  }

  nupp_curl_close_scope((uintptr_t)scope);
  int status = nupp_uv_set_owner_driver(NULL, NULL, NULL);

  if (!status) {
    http_scope = NULL;
  }

  return status;
}
#else
int nupp_http_scope_attach (void *scope) {
  (void)scope;

  return -ENOSYS;
}

int nupp_http_scope_detach (void *scope) {
  (void)scope;

  return 0;
}

/* shortcut: refuse IDNA until the Linux bridge links a converter. */
int32_t nupp_uri_idna_ascii (const char *domain, size_t count, char *out,
                             size_t room) {
  (void)domain;
  (void)count;
  (void)out;
  (void)room;

  return -2;
}
#endif

typedef uint64_t (*Entry)(const uint64_t *packet, uint64_t *output);

/* A bundle's header fields, once read and checked. */
struct bundle {
  uint64_t entry, codebytes, databytes, scratchbytes, outputwords;
};

/* Where a bundle's regions are mapped. scratch lies within scratchmap,
 * which under the guard is larger than the region the bundle declares. */
struct regions {
  unsigned char *code, *data, *scratchmap, *scratch;
  size_t scratchmapbytes;
};

static uint64_t loadle64 (const unsigned char *bytes) {
  uint64_t value = 0;

  for (unsigned i = 0; i < WORD_BYTES; ++i) {
    value |= (uint64_t)bytes[i] << (i * 8);
  }

  return value;
}

static void storele64 (unsigned char *bytes, uint64_t value) {
  for (unsigned i = 0; i < WORD_BYTES; ++i) {
    bytes[i] = (unsigned char)(value >> (i * 8));
  }
}

/* Where a header field lies within a bundle. */
static size_t headeroffset (enum bundlefield field) {
  return MAGIC_BYTES + (size_t)field * WORD_BYTES;
}

static int error (const char *message) {
  fprintf(stderr, "nupp-core: %s\n", message);

  return 1;
}

#ifndef _WIN32

/** The host page size, or zero when the platform cannot provide it. */
uint64_t nupp_core_page_size (void) {
  long size = sysconf(_SC_PAGESIZE);

  return size > 0 ? (uint64_t)size : 0;
}

/** Releases one exact page mapping, returning the host error code. */
uint64_t nupp_core_release_pages (void *region, size_t bytes) {
  return munmap(region, bytes) ? (uint64_t)errno : 0;
}
#endif

static void *mapregion (size_t bytes) {
  if (!bytes) {
    return NULL;
  }

#ifdef _WIN32

  return win64_map_pages(bytes);
#else
  void *region = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);

  return region == MAP_FAILED ? NULL : region;
#endif
}

#ifndef _WIN32

/** Maps zeroed pages through the host's anonymous mapping ABI. */
void *nupp_core_map_pages (size_t bytes) {
  return mapregion(bytes);
}
#endif

static void unmap_region (void *region, size_t bytes) {
#ifdef _WIN32
  (void)bytes;
  win64_release_pages(region);
#else
  nupp_core_release_pages(region, bytes);
#endif
}

static FILE *open_path (const char *path, const char *mode) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  FILE *file = wide ? _wfopen(wide, mode[0] == 'r' ? L"rb" : L"wb") : NULL;
  free(wide);

  return file;
#else

  return fopen(path, mode);
#endif
}

static int64_t file_size (FILE *file) {
#ifdef _WIN32
  struct _stat64 info;

  return _fstat64(_fileno(file), &info) ? -1 : info.st_size;
#else
  struct stat info;

  return fstat(fileno(file), &info) ? -1 : info.st_size;
#endif
}

/** Reads a file of whole words into a new array, which the caller frees. */
static int readwords (const char *path, uint64_t **words, size_t *count) {
  FILE *file = open_path(path, "rb");

  if (!file) {
    return error("input cannot be opened");
  }

  int64_t size = file_size(file);

  if (size < 0 || size % WORD_BYTES ||
      (uint64_t)size / WORD_BYTES > MAX_WORDS) {
    fclose(file);

    return error("input must contain bounded complete words");
  }

  size_t bytes = (size_t)size;
  unsigned char *raw = malloc(bytes ? bytes : 1);

  if (!raw) {
    fclose(file);

    return error("input allocation failed");
  }

  int complete = fread(raw, 1, bytes, file) == bytes && fgetc(file) == EOF &&
                 !ferror(file);
  fclose(file);

  if (!complete) {
    free(raw);

    return error("input changed while reading");
  }

  /* Decode in place: each word is read before it is overwritten. */
  *count = bytes / WORD_BYTES;
  *words = (uint64_t *)raw;

  for (size_t i = 0; i < *count; ++i) {
    (*words)[i] = loadle64(raw + i * WORD_BYTES);
  }

  return 0;
}

/** Reads and checks the header of an open bundle filebytes long, leaving the
 * file at the code region. */
static int readheader (FILE *file, int64_t filebytes, struct bundle *bundle) {
  unsigned char header[HEADER_BYTES];

  if (filebytes < HEADER_BYTES ||
      fread(header, 1, HEADER_BYTES, file) != HEADER_BYTES ||
      memcmp(header, BUNDLE_MAGIC, MAGIC_BYTES) != 0) {
    return error("invalid bundle header");
  }

  uint64_t fields[BUNDLE_FIELDS];

  for (unsigned field = 0; field < BUNDLE_FIELDS; ++field) {
    fields[field] = loadle64(header + headeroffset(field));
  }

  bundle->entry = fields[BUNDLE_ENTRY];
  bundle->codebytes = fields[BUNDLE_CODE_BYTES];
  bundle->databytes = fields[BUNDLE_DATA_BYTES];
  bundle->scratchbytes = fields[BUNDLE_SCRATCH_BYTES];
  bundle->outputwords = fields[BUNDLE_OUTPUT_WORDS];

  if (fields[BUNDLE_VERSION] != BUNDLE_FORMAT ||
      fields[BUNDLE_ARCHITECTURE] != HOST_ARCH || fields[BUNDLE_RESERVED]) {
    return error("unsupported bundle version, architecture or reserved field");
  }

  if (!bundle->codebytes || bundle->codebytes % INSTRUCTION_BYTES ||
      bundle->entry % INSTRUCTION_BYTES || bundle->entry >= bundle->codebytes) {
    return error("invalid code extent or entry alignment");
  }

  if (bundle->codebytes > REGION || bundle->databytes > REGION ||
      bundle->scratchbytes > REGION || bundle->outputwords > MAX_WORDS) {
    return error("bundle region exceeds transport limit");
  }

  /* Each region is bounded by now, so neither sum can overflow. */
  uint64_t mappedbytes =
      bundle->codebytes + bundle->databytes + bundle->scratchbytes;
  uint64_t storedbytes = HEADER_BYTES + bundle->codebytes + bundle->databytes;

  if (mappedbytes > REGION * 2 || storedbytes != (uint64_t)filebytes) {
    return error("bundle extent differs from file or exceeds total limit");
  }

  return 0;
}

static int pagesize (size_t *page) {
#ifdef _WIN32
  size_t size = win64_page_size();
#else
  size_t size = (size_t)nupp_core_page_size();
#endif

  if (!size || (size & (size - 1))) {
    return error("invalid host page size");
  }

  *page = size;

  return 0;
}

/** Makes loaded code executable, and so no longer writable. */
static int sealcode (unsigned char *code, size_t bytes) {
#ifdef _WIN32
  DWORD prior;

  if (!VirtualProtect(code, bytes, PAGE_EXECUTE_READ, &prior) ||
      !FlushInstructionCache(GetCurrentProcess(), code, bytes)) {
    return error("seal failed");
  }

#else

  if (mprotect(code, bytes, PROT_READ | PROT_EXEC)) {
    return error("seal failed");
  }

#ifdef __APPLE__
  sys_icache_invalidate(code, bytes);
#else
  __builtin___clear_cache((char *)code, (char *)code + bytes);
#endif
#endif

  return 0;
}

#ifdef NUPP_CORE_GUARD

/* The guard maps scratch with an inaccessible page on each side and fills it
 * above a high-water mark with CANARY, which must survive the entry, so an
 * entry that strays outside the scratch it declared fails. The mark comes
 * from CORE_TEST_HIGH_WATER and defaults to the whole region. */
enum { CANARY = 0xa5 };

/* tests/core/bridgeabi.S: calls the entry with every callee-saved
 * register set to a known value, and reports the entry's status and a mask
 * of the registers it failed to preserve. */
enum abireport { ABI_REPORT_STATUS, ABI_REPORT_CLOBBERED, ABI_REPORT_WORDS };

extern void nuppabiprobe (Entry entry, const uint64_t *packet, uint64_t *output,
                          uint64_t *report);

static int readhighwater (size_t scratchbytes, size_t *highwater) {
  *highwater = scratchbytes;
  const char *limit = getenv("CORE_TEST_HIGH_WATER");

  if (!limit) {
    return 0;
  }

  char *end;
  errno = 0;
  unsigned long long parsed = strtoull(limit, &end, 10);

  if (errno || !*limit || *end || parsed > scratchbytes) {
    return error("invalid scratch high-water");
  }

  *highwater = (size_t)parsed;

  return 0;
}

/* Scratch rounded up to whole pages, and a guard page on each side. */
static size_t scratchmapbytes (size_t scratchbytes, size_t page) {
  if (!scratchbytes) {
    return 0;
  }

  return ((scratchbytes + page - 1) & ~(page - 1)) + page * 2;
}

/* The scratch the entry may use: everything between the guard pages. */
static size_t usablebytes (size_t mapbytes, size_t page) {
  return mapbytes - page * 2;
}

/* Protects the guard pages, places the entry's scratch between them, and
 * plants the canary. */
static int fencescratch (struct regions *regions, size_t page,
                         size_t highwater) {
  size_t mapbytes = regions->scratchmapbytes;
  unsigned char *mapping = regions->scratchmap;

  if (!mapbytes) {
    return 0;
  }

  regions->scratch = mapping + page;

#ifdef _WIN32
  DWORD prior;

  if (!VirtualProtect(mapping, page, PAGE_NOACCESS, &prior) ||
      !VirtualProtect(mapping + mapbytes - page, page, PAGE_NOACCESS, &prior)) {
#else

  if (mprotect(mapping, page, PROT_NONE) ||
      mprotect(mapping + mapbytes - page, page, PROT_NONE)) {
#endif

    return error("test guard protection failed");
  }

  memset(regions->scratch + highwater, CANARY,
         usablebytes(mapbytes, page) - highwater);

  return 0;
}

static int scratchuntouched (const struct regions *regions, size_t page,
                             size_t highwater) {
  size_t mapbytes = regions->scratchmapbytes;

  if (!mapbytes) {
    return 0;
  }

  for (size_t i = highwater; i < usablebytes(mapbytes, page); ++i) {
    if (regions->scratch[i] != CANARY) {
      return error("scratch high-water canary changed");
    }
  }

  return 0;
}

static int callentry (Entry entry, const uint64_t *packet, uint64_t *output,
                      uint64_t *status) {
  uint64_t report[ABI_REPORT_WORDS] = {0, 0};
  nuppabiprobe(entry, packet, output, report);

  if (report[ABI_REPORT_CLOBBERED]) {
    return error("C ABI preservation failed");
  }

  *status = report[ABI_REPORT_STATUS];

  return 0;
}

#else

/* Without the guard, scratch is exactly the region the bundle declares. */
static int readhighwater (size_t scratchbytes, size_t *highwater) {
  *highwater = scratchbytes;

  return 0;
}

static size_t scratchmapbytes (size_t scratchbytes, size_t page) {
  (void)page;

  return scratchbytes;
}

static int fencescratch (struct regions *regions, size_t page,
                         size_t highwater) {
  (void)page;
  (void)highwater;
  regions->scratch = regions->scratchmap;

  return 0;
}

static int scratchuntouched (const struct regions *regions, size_t page,
                             size_t highwater) {
  (void)regions;
  (void)page;
  (void)highwater;

  return 0;
}

static int callentry (Entry entry, const uint64_t *packet, uint64_t *output,
                      uint64_t *status) {
  *status = entry(packet, output);

  return 0;
}

#endif

/** Reads the code and data regions, which must end the file. */
static int readregions (FILE *file, const struct bundle *bundle,
                        const struct regions *regions) {
  size_t codebytes = (size_t)bundle->codebytes;
  size_t databytes = (size_t)bundle->databytes;

  if (fread(regions->code, 1, codebytes, file) != codebytes ||
      (databytes && fread(regions->data, 1, databytes, file) != databytes) ||
      fgetc(file) != EOF || ferror(file)) {
    return error("bundle changed while reading");
  }

  return 0;
}

/** Builds the packet for a loaded bundle and calls its entry. */
static int enter (const struct bundle *bundle, const struct regions *regions,
                  const uint64_t *words, size_t count, uint64_t *output,
                  uint64_t *status) {
  uint64_t imports[IMPORT_COUNT] = {
      [IMPORT_IO_START] = (uintptr_t)nuppiostart,
      [IMPORT_IO_SUBMIT] = (uintptr_t)nuppiosubmit,
      [IMPORT_IO_TAKE] = (uintptr_t)nuppiotake,
      [IMPORT_IO_FINISH] = (uintptr_t)nuppiofinish,
      [IMPORT_IO_CANCEL] = (uintptr_t)nuppiocancel,
      [IMPORT_IO_SETTLE] = (uintptr_t)nuppiosettle,
#ifdef _WIN32
      [IMPORT_DLOPEN] = (uintptr_t)open_library,
      [IMPORT_DLSYM] = (uintptr_t)find_symbol,
      [IMPORT_DLCLOSE] = (uintptr_t)close_library,
#else
      [IMPORT_DLOPEN] = (uintptr_t)dlopen,
      [IMPORT_DLSYM] = (uintptr_t)dlsym,
      [IMPORT_DLCLOSE] = (uintptr_t)dlclose,
#endif
      [IMPORT_SYMBOLS] = (uintptr_t)symboltable,
  };
  uint64_t packet[PACKET_FIELDS] = {
      [PACKET_VERSION] = PACKET_FORMAT,
      [PACKET_CODE] = (uintptr_t)regions->code,
      [PACKET_CODE_BYTES] = bundle->codebytes,
      [PACKET_DATA] = (uintptr_t)regions->data,
      [PACKET_DATA_BYTES] = bundle->databytes,
      [PACKET_SCRATCH] = (uintptr_t)regions->scratch,
      [PACKET_SCRATCH_BYTES] = bundle->scratchbytes,
      [PACKET_IMPORTS] = (uintptr_t)imports,
      [PACKET_IMPORT_COUNT] = IMPORT_COUNT,
      [PACKET_INPUT] = (uintptr_t)words,
      [PACKET_INPUT_WORDS] = count,
      [PACKET_OUTPUT_WORDS] = bundle->outputwords,
  };
  Entry entry = (Entry)(regions->code + bundle->entry);

  return callentry(entry, packet, output, status);
}

/** Loads the bundle at path, enters it with the input words, and answers the
 * entry's status and output words, which the caller frees. */
static int execute (const char *path, const uint64_t *words, size_t count,
                    uint64_t **answer, size_t *length, uint64_t *status) {
  if (!HOST_SUPPORTED) {
    return error("standalone bridge requires ARM64 macOS/Linux or x64 Windows");
  }

  int result = 1;
  struct bundle bundle = {0};
  struct regions regions = {0};
  size_t page = 0, highwater = 0;
  uint64_t *output = NULL;

  FILE *file = open_path(path, "rb");

  if (!file) {
    return error("bundle cannot be opened");
  }

  int64_t size = file_size(file);

  if (size < 0) {
    error("invalid bundle header");
    goto out;
  }

  if (readheader(file, size, &bundle) || pagesize(&page) ||
      readhighwater((size_t)bundle.scratchbytes, &highwater)) {
    goto out;
  }

  regions.scratchmapbytes = scratchmapbytes((size_t)bundle.scratchbytes, page);
  regions.code = mapregion((size_t)bundle.codebytes);
  regions.data = mapregion((size_t)bundle.databytes);
  regions.scratchmap = mapregion(regions.scratchmapbytes);
  output = calloc(bundle.outputwords ? (size_t)bundle.outputwords : 1,
                  sizeof(uint64_t));

  if (!regions.code || (bundle.databytes && !regions.data) ||
      (regions.scratchmapbytes && !regions.scratchmap) || !output) {
    error("map failed");
    goto out;
  }

  if (readregions(file, &bundle, &regions) ||
      sealcode(regions.code, (size_t)bundle.codebytes) ||
      fencescratch(&regions, page, highwater) ||
      enter(&bundle, &regions, words, count, output, status) ||
      scratchuntouched(&regions, page, highwater)) {
    goto out;
  }

  *answer = output;
  *length = (size_t)bundle.outputwords;
  output = NULL;
  result = 0;
out:

  /* Native callbacks must finish before the executing artifact is unmapped. */
  if (nupp_uv_begin_shutdown()
#ifdef NUPP_CORE_HTTP
      || nupp_http_scope_detach(http_scope)
#endif
      || nupp_uv_shutdown()) {
    error("native completion drain failed");
    _exit(1); /* Retain the entry and callback backing until process exit. */
  }

#ifdef NUPP_CORE_HTTP

  if (curl_initialized) {
    curl_global_cleanup();
    curl_initialized = 0;
  }

#endif

  if (retain_guest_backing) {
    error("guest backing retained after cleanup refusal");
    _exit(1);
  }

  fclose(file);

  if (regions.code) {
    unmap_region(regions.code, (size_t)bundle.codebytes);
  }

  if (regions.data) {
    unmap_region(regions.data, (size_t)bundle.databytes);
  }

  if (regions.scratchmap) {
    unmap_region(regions.scratchmap, regions.scratchmapbytes);
  }

  free(output);

  return result;
}

/* Publishes the directory holding the bundle at path as
 * nupp_core_artifact_directory, answering it for the caller to free once the
 * entry has returned. */
static char *publishdirectory (const char *path) {
#ifdef _WIN32
  char *directory = canonical_path(path);
#else
  char *directory = realpath(path, NULL);
#endif

  if (!directory) {
    error("bundle cannot be resolved");

    return NULL;
  }

  char *slash = strrchr(directory, '/');

  if (!slash) {
    free(directory);
    error("bundle has no parent directory");

    return NULL;
  }

  /* Keep the slash at a filesystem root. */
  int root = slash == directory;

#ifdef _WIN32
  root = root || slash[-1] == ':';
#endif

  if (root) {
    slash[1] = 0;
  }
  else {
    *slash = 0;
  }

  nupp_core_artifact_directory = directory;

  return directory;
}

static int writewords (const char *path, const uint64_t *words, size_t count) {
  FILE *file = open_path(path, "wb");

  if (!file) {
    return error("output cannot be opened");
  }

  int result = 0;

  for (size_t i = 0; i < count; ++i) {
    unsigned char bytes[WORD_BYTES];
    storele64(bytes, words[i]);

    if (fwrite(bytes, 1, WORD_BYTES, file) != WORD_BYTES) {
      result = error("output cannot be written");
      break;
    }
  }

  if (fclose(file)) {
    result = error("output cannot be closed");
  }

  return result;
}

/* Any status but zero fails the run. A guest error has been reported
 * already; any other status is the entry refusing, and is reported here. */
static int checkstatus (uint64_t status) {
  if (!status) {
    return 0;
  }

  if (status != GUEST_ERROR_STATUS) {
    fprintf(stderr,
            "nupp-core: Nupp entry refused with transport status %llu\n",
            (unsigned long long)status);
  }

  return 1;
}

static int run (const char *bundle, const char *input, const char *output) {
  char *directory = publishdirectory(bundle);

  if (!directory) {
    return 1;
  }

  uint64_t *words = NULL, *answer = NULL, status = 0;
  size_t count = 0, length = 0;
  int result = readwords(input, &words, &count) ||
               execute(bundle, words, count, &answer, &length, &status) ||
               checkstatus(status) || writewords(output, answer, length);
  free(answer);
  free(words);
  free(directory);

  return result;
}

#ifdef _WIN32
int wmain (int argc, wchar_t **argv) {
  if (argc < 4) {
    return error("usage: nupp-core BUNDLE INPUT OUTPUT [ARGUMENT...]");
  }

  char **arguments = calloc((size_t)argc, sizeof(*arguments));

  if (!arguments) {
    return error("cannot allocate arguments");
  }

  int converted = 0;

  while (converted < argc) {
    arguments[converted] = utf8_path(argv[converted]);

    if (!arguments[converted]) {
      break;
    }

    ++converted;
  }

  processargumentcount = (uint64_t)converted;
  processarguments = arguments;
  int result = converted == argc ? run(arguments[1], arguments[2], arguments[3])
                                 : error("invalid argument");
  processargumentcount = 0;
  processarguments = NULL;

  for (int at = 0; at < converted; ++at) {
    free(arguments[at]);
  }

  free(arguments);

  return result;
}
#else
int main (int argc, char **argv) {
  if (argc < 4) {
    return error("usage: nupp-core BUNDLE INPUT OUTPUT [ARGUMENT...]");
  }

  processargumentcount = (uint64_t)argc;
  processarguments = argv;

  return run(argv[1], argv[2], argv[3]);
}
#endif
