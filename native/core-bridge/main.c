/* The native core's startup transport. It reads a core bundle, maps the
 * bundle's code, data and scratch regions, and enters the Nupp code the
 * bundle carries. That code is Nupp; this file knows no value, frame, task,
 * collector, instruction or optimizer layout.
 *
 * scripts/core-bridge builds it as nupp-core. guard.c and
 * tests/core/bridge-contracts.c include it whole, with main renamed, so they
 * can reach its static functions; guard.c also defines NUPP_CORE_GUARD, which
 * fences scratch and checks that the entry preserves the C ABI. */
#define _DARWIN_C_SOURCE 1
#define _GNU_SOURCE 1
#include "transport.h"
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#endif

#define ARRAY_LENGTH(array) (sizeof(array) / sizeof(*(array)))

/* Every word the transport reads or writes is a little-endian uint64. */
enum { WORD_BYTES = 8 };

/* A bundle is BUNDLE_MAGIC, then BUNDLE_FIELDS header words, then the code
 * and data regions back to back. Scratch is not stored: it is mapped zeroed.
 * The guest and unit runners write this layout. */
#define BUNDLE_MAGIC "NUPPCORE"

enum { MAGIC_BYTES = 8 };

enum bundle_field {
  BUNDLE_VERSION,      /* BUNDLE_FORMAT */
  BUNDLE_ARCHITECTURE, /* BUNDLE_ARM64, the only one */
  BUNDLE_ENTRY,        /* the entry's byte offset within code */
  BUNDLE_CODE_BYTES,
  BUNDLE_DATA_BYTES,
  BUNDLE_SCRATCH_BYTES,
  BUNDLE_OUTPUT_WORDS, /* how many words the entry answers */
  BUNDLE_RESERVED,     /* zero */
  BUNDLE_FIELDS
};

enum {
  BUNDLE_FORMAT = 1,
  BUNDLE_ARM64 = 1,
  HEADER_BYTES = MAGIC_BYTES + BUNDLE_FIELDS * WORD_BYTES,
  INSTRUCTION_BYTES = 4,
};

/* Each region is at most REGION bytes and all three together at most twice
 * that. Input and output are each at most MAX_WORDS words. */
static const uint64_t REGION = UINT64_C(1024) * 1024 * 1024;
static const uint64_t MAX_WORDS = UINT64_C(1024) * 1024;

/* The entry is called with a pointer to this packet and to the output words.
 * The generated entry loads these fields at fixed word offsets. */
enum packet_field {
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
 * I/O pool's six (transport.h) come first, then the OS loader, then the
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

static uint64_t symbol_table[SYMBOL_TABLE_WORDS];

/* The directory the bundle was loaded from. The Nupp loader finds it by name
 * with dlsym and resolves artifact-relative library paths against it. */
const char *nupp_core_artifact_directory;

typedef uint64_t (*Entry)(const uint64_t *packet, uint64_t *output);

/* A bundle's header fields, once read and checked. */
struct bundle {
  uint64_t entry, code_bytes, data_bytes, scratch_bytes, output_words;
};

/* Where a bundle's regions are mapped. scratch lies within scratch_mapping,
 * which under the guard is larger than the region the bundle declares. */
struct regions {
  unsigned char *code, *data, *scratch_mapping, *scratch;
  size_t scratch_mapping_bytes;
};

static uint64_t load_le64(const unsigned char *bytes)
{
  uint64_t value = 0;
  for (unsigned i = 0; i < WORD_BYTES; ++i)
    value |= (uint64_t)bytes[i] << (i * 8);
  return value;
}

static void store_le64(unsigned char *bytes, uint64_t value)
{
  for (unsigned i = 0; i < WORD_BYTES; ++i)
    bytes[i] = (unsigned char)(value >> (i * 8));
}

/* Where a header field lies within a bundle. */
static size_t header_offset(enum bundle_field field)
{
  return MAGIC_BYTES + (size_t)field * WORD_BYTES;
}

static int error(const char *message)
{
  fprintf(stderr, "nupp-core: %s\n", message);
  return 1;
}

static void *map_region(size_t bytes)
{
  if (!bytes)
    return NULL;
  void *region = mmap(NULL, bytes, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  return region == MAP_FAILED ? NULL : region;
}

/* Reads a file of whole words into a new array, which the caller frees. */
static int read_words(const char *path, uint64_t **words, size_t *count)
{
  FILE *file = fopen(path, "rb");
  if (!file)
    return error("input cannot be opened");
  struct stat info;
  if (fstat(fileno(file), &info) || info.st_size < 0 ||
      info.st_size % WORD_BYTES ||
      (uint64_t)info.st_size / WORD_BYTES > MAX_WORDS) {
    fclose(file);
    return error("input must contain bounded complete words");
  }
  size_t bytes = (size_t)info.st_size;
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
  for (size_t i = 0; i < *count; ++i)
    (*words)[i] = load_le64(raw + i * WORD_BYTES);
  return 0;
}

/* Reads and checks the header of an open bundle file_bytes long, leaving the
 * file at the code region. */
static int read_header(FILE *file, off_t file_bytes, struct bundle *bundle)
{
  unsigned char header[HEADER_BYTES];
  if (file_bytes < HEADER_BYTES ||
      fread(header, 1, HEADER_BYTES, file) != HEADER_BYTES ||
      memcmp(header, BUNDLE_MAGIC, MAGIC_BYTES))
    return error("invalid bundle header");
  uint64_t fields[BUNDLE_FIELDS];
  for (unsigned field = 0; field < BUNDLE_FIELDS; ++field)
    fields[field] = load_le64(header + header_offset(field));
  bundle->entry = fields[BUNDLE_ENTRY];
  bundle->code_bytes = fields[BUNDLE_CODE_BYTES];
  bundle->data_bytes = fields[BUNDLE_DATA_BYTES];
  bundle->scratch_bytes = fields[BUNDLE_SCRATCH_BYTES];
  bundle->output_words = fields[BUNDLE_OUTPUT_WORDS];

  if (fields[BUNDLE_VERSION] != BUNDLE_FORMAT ||
      fields[BUNDLE_ARCHITECTURE] != BUNDLE_ARM64 || fields[BUNDLE_RESERVED])
    return error("unsupported bundle version, architecture or reserved field");
  if (!bundle->code_bytes || bundle->code_bytes % INSTRUCTION_BYTES ||
      bundle->entry % INSTRUCTION_BYTES || bundle->entry >= bundle->code_bytes)
    return error("invalid code extent or entry alignment");
  if (bundle->code_bytes > REGION || bundle->data_bytes > REGION ||
      bundle->scratch_bytes > REGION || bundle->output_words > MAX_WORDS)
    return error("bundle region exceeds transport limit");
  /* Each region is bounded by now, so neither sum can overflow. */
  uint64_t mapped_bytes =
      bundle->code_bytes + bundle->data_bytes + bundle->scratch_bytes;
  uint64_t stored_bytes =
      HEADER_BYTES + bundle->code_bytes + bundle->data_bytes;
  if (mapped_bytes > REGION * 2 || stored_bytes != (uint64_t)file_bytes)
    return error("bundle extent differs from file or exceeds total limit");
  return 0;
}

static int page_size(size_t *page)
{
  long size = sysconf(_SC_PAGESIZE);
  if (size <= 0 || (size & (size - 1)))
    return error("invalid host page size");
  *page = (size_t)size;
  return 0;
}

/* Makes loaded code executable, and so no longer writable. */
static int seal_code(unsigned char *code, size_t bytes)
{
  if (mprotect(code, bytes, PROT_READ | PROT_EXEC))
    return error("seal failed");
#ifdef __APPLE__
  sys_icache_invalidate(code, bytes);
#else
  __builtin___clear_cache((char *)code, (char *)code + bytes);
#endif
  return 0;
}

#ifdef NUPP_CORE_GUARD
/* The guard maps scratch with an inaccessible page on each side and fills it
 * above a high-water mark with CANARY, which must survive the entry, so an
 * entry that strays outside the scratch it declared fails. The mark comes
 * from CORE_TEST_HIGH_WATER and defaults to the whole region. */
enum { CANARY = 0xa5 };

/* tests/core/bridge-abi-aarch64.S: calls the entry with every callee-saved
 * register set to a known value, and reports the entry's status and a mask
 * of the registers it failed to preserve. */
enum abi_report { ABI_REPORT_STATUS, ABI_REPORT_CLOBBERED, ABI_REPORT_WORDS };

extern void nupp_core_test_abi(Entry entry, const uint64_t *packet,
                               uint64_t *output, uint64_t *report);

static int scratch_high_water(size_t scratch_bytes, size_t *high_water)
{
  *high_water = scratch_bytes;
  const char *limit = getenv("CORE_TEST_HIGH_WATER");
  if (!limit)
    return 0;
  char *end;
  errno = 0;
  unsigned long long parsed = strtoull(limit, &end, 10);
  if (errno || !*limit || *end || parsed > scratch_bytes)
    return error("invalid scratch high-water");
  *high_water = (size_t)parsed;
  return 0;
}

/* Scratch rounded up to whole pages, and a guard page on each side. */
static size_t scratch_mapping_bytes(size_t scratch_bytes, size_t page)
{
  if (!scratch_bytes)
    return 0;
  return ((scratch_bytes + page - 1) & ~(page - 1)) + page * 2;
}

/* The scratch the entry may use: everything between the guard pages. */
static size_t usable_bytes(size_t mapping_bytes, size_t page)
{
  return mapping_bytes - page * 2;
}

/* Protects the guard pages, places the entry's scratch between them, and
 * plants the canary. */
static int fence_scratch(struct regions *regions, size_t page,
                         size_t high_water)
{
  size_t mapping_bytes = regions->scratch_mapping_bytes;
  unsigned char *mapping = regions->scratch_mapping;
  if (!mapping_bytes)
    return 0;
  regions->scratch = mapping + page;
  if (mprotect(mapping, page, PROT_NONE) ||
      mprotect(mapping + mapping_bytes - page, page, PROT_NONE))
    return error("test guard protection failed");
  memset(regions->scratch + high_water, CANARY,
         usable_bytes(mapping_bytes, page) - high_water);
  return 0;
}

static int scratch_untouched(const struct regions *regions, size_t page,
                             size_t high_water)
{
  size_t mapping_bytes = regions->scratch_mapping_bytes;
  if (!mapping_bytes)
    return 0;
  for (size_t i = high_water; i < usable_bytes(mapping_bytes, page); ++i)
    if (regions->scratch[i] != CANARY)
      return error("scratch high-water canary changed");
  return 0;
}

static int call_entry(Entry entry, const uint64_t *packet, uint64_t *output,
                      uint64_t *status)
{
  uint64_t report[ABI_REPORT_WORDS] = {0, 0};
  nupp_core_test_abi(entry, packet, output, report);
  if (report[ABI_REPORT_CLOBBERED])
    return error("C ABI preservation failed");
  *status = report[ABI_REPORT_STATUS];
  return 0;
}
#else
/* Without the guard, scratch is exactly the region the bundle declares. */
static int scratch_high_water(size_t scratch_bytes, size_t *high_water)
{
  *high_water = scratch_bytes;
  return 0;
}

static size_t scratch_mapping_bytes(size_t scratch_bytes, size_t page)
{
  (void)page;
  return scratch_bytes;
}

static int fence_scratch(struct regions *regions, size_t page,
                         size_t high_water)
{
  (void)page;
  (void)high_water;
  regions->scratch = regions->scratch_mapping;
  return 0;
}

static int scratch_untouched(const struct regions *regions, size_t page,
                             size_t high_water)
{
  (void)regions;
  (void)page;
  (void)high_water;
  return 0;
}

static int call_entry(Entry entry, const uint64_t *packet, uint64_t *output,
                      uint64_t *status)
{
  *status = entry(packet, output);
  return 0;
}
#endif

/* Reads the code and data regions, which must end the file. */
static int read_regions(FILE *file, const struct bundle *bundle,
                        const struct regions *regions)
{
  size_t code_bytes = (size_t)bundle->code_bytes;
  size_t data_bytes = (size_t)bundle->data_bytes;
  if (fread(regions->code, 1, code_bytes, file) != code_bytes ||
      (data_bytes && fread(regions->data, 1, data_bytes, file) != data_bytes) ||
      fgetc(file) != EOF || ferror(file))
    return error("bundle changed while reading");
  return 0;
}

/* Builds the packet for a loaded bundle and calls its entry. */
static int enter(const struct bundle *bundle, const struct regions *regions,
                 const uint64_t *words, size_t count, uint64_t *output,
                 uint64_t *status)
{
  uint64_t imports[IMPORT_COUNT] = {
      [IMPORT_IO_START] = (uintptr_t)nupp_io_start,
      [IMPORT_IO_SUBMIT] = (uintptr_t)nupp_io_submit,
      [IMPORT_IO_TAKE] = (uintptr_t)nupp_io_take,
      [IMPORT_IO_FINISH] = (uintptr_t)nupp_io_finish,
      [IMPORT_IO_CANCEL] = (uintptr_t)nupp_io_cancel,
      [IMPORT_IO_SETTLE] = (uintptr_t)nupp_io_settle,
      [IMPORT_DLOPEN] = (uintptr_t)dlopen,
      [IMPORT_DLSYM] = (uintptr_t)dlsym,
      [IMPORT_DLCLOSE] = (uintptr_t)dlclose,
      [IMPORT_SYMBOLS] = (uintptr_t)symbol_table,
  };
  uint64_t packet[PACKET_FIELDS] = {
      [PACKET_VERSION] = PACKET_FORMAT,
      [PACKET_CODE] = (uintptr_t)regions->code,
      [PACKET_CODE_BYTES] = bundle->code_bytes,
      [PACKET_DATA] = (uintptr_t)regions->data,
      [PACKET_DATA_BYTES] = bundle->data_bytes,
      [PACKET_SCRATCH] = (uintptr_t)regions->scratch,
      [PACKET_SCRATCH_BYTES] = bundle->scratch_bytes,
      [PACKET_IMPORTS] = (uintptr_t)imports,
      [PACKET_IMPORT_COUNT] = IMPORT_COUNT,
      [PACKET_INPUT] = (uintptr_t)words,
      [PACKET_INPUT_WORDS] = count,
      [PACKET_OUTPUT_WORDS] = bundle->output_words,
  };
  Entry entry = (Entry)(regions->code + bundle->entry);
  return call_entry(entry, packet, output, status);
}

/* Loads the bundle at path, enters it with the input words, and answers the
 * entry's status and output words, which the caller frees. */
static int execute(const char *path, const uint64_t *words, size_t count,
                   uint64_t **answer, size_t *length, uint64_t *status)
{
#if !defined(__aarch64__) && !defined(__arm64__)
  return error("standalone bridge requires little-endian ARM64 macOS or Linux");
#endif
  int result = 1;
  struct bundle bundle = {0};
  struct regions regions = {0};
  size_t page = 0, high_water = 0;
  uint64_t *output = NULL;
  struct stat info;

  FILE *file = fopen(path, "rb");
  if (!file)
    return error("bundle cannot be opened");
  if (fstat(fileno(file), &info)) {
    error("invalid bundle header");
    goto out;
  }
  if (read_header(file, info.st_size, &bundle) || page_size(&page) ||
      scratch_high_water((size_t)bundle.scratch_bytes, &high_water))
    goto out;

  regions.scratch_mapping_bytes =
      scratch_mapping_bytes((size_t)bundle.scratch_bytes, page);
  regions.code = map_region((size_t)bundle.code_bytes);
  regions.data = map_region((size_t)bundle.data_bytes);
  regions.scratch_mapping = map_region(regions.scratch_mapping_bytes);
  output = calloc(bundle.output_words ? (size_t)bundle.output_words : 1,
                  sizeof(uint64_t));
  if (!regions.code || (bundle.data_bytes && !regions.data) ||
      (regions.scratch_mapping_bytes && !regions.scratch_mapping) || !output) {
    error("map failed");
    goto out;
  }

  if (read_regions(file, &bundle, &regions) ||
      seal_code(regions.code, (size_t)bundle.code_bytes) ||
      fence_scratch(&regions, page, high_water) ||
      enter(&bundle, &regions, words, count, output, status) ||
      scratch_untouched(&regions, page, high_water))
    goto out;

  *answer = output;
  *length = (size_t)bundle.output_words;
  output = NULL;
  result = 0;
out:
  fclose(file);
  if (regions.code)
    munmap(regions.code, (size_t)bundle.code_bytes);
  if (regions.data)
    munmap(regions.data, (size_t)bundle.data_bytes);
  if (regions.scratch_mapping)
    munmap(regions.scratch_mapping, regions.scratch_mapping_bytes);
  free(output);
  return result;
}

/* Publishes the directory holding the bundle at path as
 * nupp_core_artifact_directory, answering it for the caller to free once the
 * entry has returned. */
static char *publish_artifact_directory(const char *path)
{
  char *directory = realpath(path, NULL);
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
  /* A bundle at the root keeps the slash: its directory is "/". */
  if (slash == directory)
    slash[1] = 0;
  else
    *slash = 0;
  nupp_core_artifact_directory = directory;
  return directory;
}

static int write_words(const char *path, const uint64_t *words, size_t count)
{
  FILE *file = fopen(path, "wb");
  if (!file)
    return error("output cannot be opened");
  int result = 0;
  for (size_t i = 0; i < count; ++i) {
    unsigned char bytes[WORD_BYTES];
    store_le64(bytes, words[i]);
    if (fwrite(bytes, 1, WORD_BYTES, file) != WORD_BYTES) {
      result = error("output cannot be written");
      break;
    }
  }
  if (fclose(file))
    result = error("output cannot be closed");
  return result;
}

/* Any status but zero fails the run. A guest error has been reported
 * already; any other status is the entry refusing, and is reported here. */
static int check_status(uint64_t status)
{
  if (!status)
    return 0;
  if (status != GUEST_ERROR_STATUS)
    fprintf(stderr,
            "nupp-core: Nupp entry refused with transport status %llu\n",
            (unsigned long long)status);
  return 1;
}

int main(int argc, char **argv)
{
  if (argc < 4)
    return error("usage: nupp-core BUNDLE INPUT OUTPUT [ARGUMENT...]");
  const char *bundle = argv[1], *input = argv[2], *output = argv[3];
  char *directory = publish_artifact_directory(bundle);
  if (!directory)
    return 1;
  uint64_t *words = NULL, *answer = NULL, status = 0;
  size_t count = 0, length = 0;
  int result = read_words(input, &words, &count) ||
               execute(bundle, words, count, &answer, &length, &status) ||
               check_status(status) || write_words(output, answer, length);
  free(answer);
  free(words);
  free(directory);
  return result;
}
