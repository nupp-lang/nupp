/* The ABI and scratch guard: a test-only build of the startup transport that
 * checks a generated entry rather than only running it. It replaced a Rust
 * test, and the core guest and unit runners still run it the way they ran
 * that test,
 *
 *   nupp-core-guard --ignored --exact TEST --test-threads=1
 *
 * looking for the summary line it prints when TEST passes. The environment
 * names the rest: CORE_TEST_BUNDLE and CORE_TEST_INPUT always,
 * CORE_TEST_EXPECTED or CORE_TEST_STATUS for what the entry must answer,
 * CORE_TEST_ARGUMENTS for the guest's command-line arguments, and
 * CORE_TEST_HIGH_WATER for its scratch canary (main.c). */

/* The transport itself, with its main renamed so this file can have one. */
#define NUPP_CORE_GUARD 1
#define main bootstrap_main
#include "main.c"
#undef main

#ifdef __APPLE__
#include <crt_externs.h>
#endif

/* The arguments the guest sees ahead of CORE_TEST_ARGUMENTS's, as nupp-core
 * gives them: the program, the bundle, the input and an empty output. */
enum { GUEST_LEADING_ARGUMENTS = 4 };

/* One way to shorten a bundle: a header field and the value it gets. Each
 * leaves a region shorter than any generated entry needs. */
struct shortening {
  enum bundle_field field;
  uint64_t value;
};

static const struct shortening shortenings[] = {
    {BUNDLE_DATA_BYTES, 0},
    {BUNDLE_DATA_BYTES, 31},
    {BUNDLE_SCRATCH_BYTES, 0},
    /* A byte less than the least scratch a guest program declares. */
    {BUNDLE_SCRATCH_BYTES, 65535},
    {BUNDLE_OUTPUT_WORDS, 0},
};

static const char *required (const char *name) {
  const char *value = getenv(name);

  if (!value || !*value) {
    error(name);
    exit(1);
  }

  return value;
}

/* Makes the process's arguments the ones nupp-core would give the guest,
 * followed by CORE_TEST_ARGUMENTS split at spaces. Only macOS offers a way
 * to replace them; elsewhere they are left alone. The storage stays live
 * until exit, since the guest can read its arguments at any point. */
static int present_guest_arguments (const char *bundle, const char *input) {
#ifdef __APPLE__
  const char *words = getenv("CORE_TEST_ARGUMENTS");
  char *extra = strdup(words ? words : "");

  if (!extra)
    return 1;

  /* A string of n bytes holds at most n / 2 + 1 words; leave room for those,
   * the leading arguments and the terminating NULL. */
  size_t capacity = strlen(extra) / 2 + 1 + GUEST_LEADING_ARGUMENTS + 1;
  char **arguments = calloc(capacity, sizeof(char *));

  if (!arguments) {
    free(extra);

    return 1;
  }

  int count = 0;
  arguments[count++] = "nupp-core-guard";
  arguments[count++] = (char *)bundle;
  arguments[count++] = (char *)input;
  arguments[count++] = "";
  char *save = NULL;

  for (char *word = strtok_r(extra, " ", &save); word;
       word = strtok_r(NULL, " ", &save))
    arguments[count++] = word;

  *_NSGetArgc() = count;
  *_NSGetArgv() = arguments;
#else
  (void)bundle;
  (void)input;
#endif

  return 0;
}

/* Runs the bundle at path as nupp-core would, from its own directory. */
static int invoke (const char *path, const uint64_t *words, size_t count,
                   uint64_t **answer, size_t *length, uint64_t *status) {
  char *directory = publish_artifact_directory(path);

  if (!directory)
    return 1;

  int result = execute(path, words, count, answer, length, status);
  nupp_core_artifact_directory = NULL;
  free(directory);

  return result;
}

static int check_output (const char *bundle, const uint64_t *words,
                         size_t count) {
  uint64_t *answer = NULL, *expected = NULL, status = 0;
  size_t length = 0, expected_count = 0;
  int result =
      invoke(bundle, words, count, &answer, &length, &status) ||
      read_words(required("CORE_TEST_EXPECTED"), &expected, &expected_count) ||
      status || expected_count != length ||
      memcmp(expected, answer, length * sizeof(uint64_t));
  free(expected);
  free(answer);

  return result;
}

static int check_requested_status (const char *bundle, const uint64_t *words,
                                   size_t count) {
  const char *requested = getenv("CORE_TEST_STATUS");
  uint64_t *answer = NULL, status = 0;
  size_t length = 0;
  int result = invoke(bundle, words, count, &answer, &length, &status);
  free(answer);

  if (result || !requested || !*requested)
    return 1;

  char *end;
  unsigned long long wanted = strtoull(requested, &end, 10);

  return *end || !wanted || status != wanted;
}

/* Reads a whole bundle no larger than the transport accepts. */
static int read_bundle (const char *path, unsigned char **bytes, size_t *size) {
  FILE *file = fopen(path, "rb");

  if (!file)
    return 1;

  struct stat info;
  int result = 1;

  if (fstat(fileno(file), &info) || info.st_size < HEADER_BYTES ||
      (uint64_t)info.st_size > REGION * 2 + HEADER_BYTES)
    goto out;

  *size = (size_t)info.st_size;
  *bytes = malloc(*size);

  if (*bytes && fread(*bytes, 1, *size, file) == *size)
    result = 0;

out:
  fclose(file);

  return result;
}

/* Applies a shortening to a copy of the bundle. A shorter data region
 * shortens the file to match, so the bundle is still well formed. */
static int shorten (const unsigned char *original, size_t size,
                    const struct shortening *shortening,
                    unsigned char *modified, size_t *modified_size) {
  memcpy(modified, original, size);
  store_le64(modified + header_offset(shortening->field), shortening->value);
  *modified_size = size;

  if (shortening->field == BUNDLE_DATA_BYTES) {
    uint64_t code_bytes =
        load_le64(original + header_offset(BUNDLE_CODE_BYTES));
    *modified_size =
        HEADER_BYTES + (size_t)code_bytes + (size_t)shortening->value;
  }

  return *modified_size > size;
}

/* Writes bytes to a new temporary file, answering its path. */
static int write_temporary (const unsigned char *bytes, size_t size,
                            char **path) {
  const char *directory = getenv("TMPDIR");

  if (!directory)
    directory = "/tmp";

  if (asprintf(path, "%s/nupp-core-guard-XXXXXX", directory) < 0) {
    *path = NULL;

    return 1;
  }

  int descriptor = mkstemp(*path);
  FILE *file = descriptor < 0 ? NULL : fdopen(descriptor, "wb");

  if (!file) {
    if (descriptor >= 0)
      close(descriptor);

    free(*path);
    *path = NULL;

    return 1;
  }

  int result = fwrite(bytes, 1, size, file) != size;

  if (fclose(file))
    result = 1;

  return result;
}

/* The bundle at path must load, and its entry must answer a nonzero status. */
static int refused (const char *path, const uint64_t *words, size_t count) {
  uint64_t *answer = NULL, status = 0;
  size_t length = 0;
  int result = invoke(path, words, count, &answer, &length, &status);
  free(answer);

  return !result && status != 0;
}

static int check_short_regions (const char *bundle, const uint64_t *words,
                                size_t count) {
  unsigned char *original = NULL, *modified = NULL;
  size_t size = 0;
  int result = 1;

  if (read_bundle(bundle, &original, &size))
    goto out;

  modified = malloc(size);

  if (!modified)
    goto out;

  for (size_t i = 0; i < ARRAY_LENGTH(shortenings); ++i) {
    size_t modified_size;
    char *path = NULL;

    if (shorten(original, size, &shortenings[i], modified, &modified_size))
      goto out;

    int written = !write_temporary(modified, modified_size, &path);
    int passed = written && refused(path, words, count);

    if (path)
      unlink(path);

    free(path);

    if (!passed)
      goto out;
  }

  result = 0;
out:
  free(original);
  free(modified);

  return result;
}

/* The checks the guard can run, by the name the runners select them with. */
struct guard_test {
  const char *name;
  int (*check)(const char *bundle, const uint64_t *words, size_t count);
};

static const struct guard_test tests[] = {
    /* The entry preserves the C ABI and answers CORE_TEST_EXPECTED's words. */
    {"abi::generated_entry_preserves_c_abi_and_output", check_output},
    /* The entry answers CORE_TEST_STATUS, which is not zero. */
    {"abi::generated_entry_returns_requested_status", check_requested_status},
    /* The entry refuses the bundle when any region is too short for it. */
    {"abi::generated_entry_refuses_short_regions", check_short_regions},
};

/* Finds the test --exact names; the last one wins. */
static const struct guard_test *select_test (int argc, char **argv) {
  const char *selection = NULL;

  for (int i = 1; i + 1 < argc; ++i)
    if (!strcmp(argv[i], "--exact"))
      selection = argv[i + 1];

  for (size_t i = 0; selection && i < ARRAY_LENGTH(tests); ++i)
    if (!strcmp(selection, tests[i].name))
      return &tests[i];

  error("unknown C guard selection");

  return NULL;
}

int main (int argc, char **argv) {
  const char *bundle = required("CORE_TEST_BUNDLE");
  const char *input = required("CORE_TEST_INPUT");
  const struct guard_test *test = select_test(argc, argv);

  if (!test || present_guest_arguments(bundle, input))
    return 1;

  uint64_t *words = NULL;
  size_t count = 0;
  int result =
      read_words(input, &words, &count) || test->check(bundle, words, count);
  free(words);

  if (result)
    return error("guard failed");

  puts("1 passed; 0 failed; 0 ignored;");

  return 0;
}
