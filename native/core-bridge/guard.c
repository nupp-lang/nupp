/* Test-only ABI preservation and opaque scratch guard. */
#define NUPP_CORE_GUARD 1
#define main bootstrap_main
#include "main.c"
#undef main
#ifdef __APPLE__
#include <crt_externs.h>
#endif
static const char *required(const char *name)
{
  const char *value = getenv(name);
  if (!value || !*value) {
    error(name);
    exit(1);
  }
  return value;
}

static int invoke(const char *bundle, const uint64_t *words, size_t count,
                  uint64_t **answer, size_t *length, uint64_t *status)
{
  char *canonical = realpath(bundle, NULL);
  if (!canonical)
    return error("guard bundle cannot be resolved");
  char *slash = strrchr(canonical, '/');
  if (!slash) {
    free(canonical);
    return 1;
  }
  if (slash == canonical)
    slash[1] = 0;
  else
    *slash = 0;
  nupp_core_artifact_directory = canonical;
  int result = execute(bundle, words, count, answer, length, status);
  nupp_core_artifact_directory = NULL;
  free(canonical);
  return result;
}

static int short_regions(const char *bundle, const uint64_t *words,
                         size_t count)
{
  FILE *file = fopen(bundle, "rb");
  if (!file)
    return 1;
  struct stat info;
  if (fstat(fileno(file), &info) || info.st_size < HEADER ||
      (uint64_t)info.st_size > REGION * 2 + HEADER) {
    fclose(file);
    return 1;
  }
  size_t size = (size_t)info.st_size;
  unsigned char *original = malloc(size), *modified = malloc(size);
  if (!original || !modified) {
    free(original);
    free(modified);
    fclose(file);
    return 1;
  }
  int result = fread(original, 1, size, file) != size;
  fclose(file);
  const unsigned fields[] = {4, 4, 5, 5, 6};
  const uint64_t values[] = {0, 31, 0, 65535, 0};
  for (unsigned i = 0; !result && i < 5; ++i) {
    memcpy(modified, original, size);
    for (unsigned byte = 0; byte < 8; ++byte)
      modified[8 + fields[i] * 8 + byte] =
          (unsigned char)(values[i] >> (byte * 8));
    size_t modified_size =
        fields[i] == 4
            ? HEADER + (size_t)little(original + 32) + (size_t)values[i]
            : size;
    if (modified_size > size) {
      result = 1;
      break;
    }
    const char *temporary = getenv("TMPDIR");
    if (!temporary)
      temporary = "/tmp";
    char *path = NULL;
    if (asprintf(&path, "%s/nupp-core-guard-XXXXXX", temporary) < 0) {
      result = 1;
      break;
    }
    int fd = mkstemp(path);
    file = fd < 0 ? NULL : fdopen(fd, "wb");
    if (!file) {
      if (fd >= 0)
	close(fd);
      free(path);
      result = 1;
      break;
    }
    if (fwrite(modified, 1, modified_size, file) != modified_size)
      result = 1;
    if (fclose(file))
      result = 1;
    uint64_t *answer = NULL, status = 0;
    size_t length = 0;
    if (!result &&
        (invoke(path, words, count, &answer, &length, &status) || status == 0))
      result = 1;
    free(answer);
    unlink(path);
    free(path);
  }
  free(original);
  free(modified);
  return result;
}

int main(int argc, char **argv)
{
  const char *bundle = required("CORE_TEST_BUNDLE"),
             *input_path = required("CORE_TEST_INPUT");
  int short_test = 0;
  const char *selection = NULL;
  for (int i = 1; i + 1 < argc; ++i)
    if (!strcmp(argv[i], "--exact"))
      selection = argv[i + 1];
  if (!selection ||
      (strcmp(selection, "abi::generated_entry_preserves_c_abi_and_output") &&
       strcmp(selection, "abi::generated_entry_returns_requested_status") &&
       strcmp(selection, "abi::generated_entry_refuses_short_regions")))
    return error("unknown C guard selection");
  short_test = !strcmp(selection, "abi::generated_entry_refuses_short_regions");
  char *extra = strdup(
      getenv("CORE_TEST_ARGUMENTS") ? getenv("CORE_TEST_ARGUMENTS") : "");
  if (!extra)
    return 1;
  size_t capacity = strlen(extra) / 2 + 8;
  char **arguments = calloc(capacity, sizeof(char *));
  if (!arguments) {
    free(extra);
    return 1;
  }
  arguments[0] = "nupp-core-guard";
  arguments[1] = (char *)bundle;
  arguments[2] = (char *)input_path;
  arguments[3] = "";
  int count_arguments = 4;
  char *save = NULL;
  for (char *word = strtok_r(extra, " ", &save); word;
       word = strtok_r(NULL, " ", &save))
    arguments[count_arguments++] = word;
#ifdef __APPLE__
  *_NSGetArgc() = count_arguments;
  *_NSGetArgv() = arguments;
#endif
  uint64_t *words = NULL, *answer = NULL, status = 0;
  size_t count = 0, length = 0;
  int result = input(input_path, &words, &count);
  if (!result && short_test)
    result = short_regions(bundle, words, count);
  else if (!result) {
    result = invoke(bundle, words, count, &answer, &length, &status);
    const char *wanted_status = getenv("CORE_TEST_STATUS");
    if (!result && wanted_status) {
      char *end;
      unsigned long long wanted = strtoull(wanted_status, &end, 10);
      if (!*wanted_status || *end || !wanted || status != wanted)
	result = 1;
    } else if (!result) {
      uint64_t *expected = NULL;
      size_t expected_count = 0;
      result =
          input(required("CORE_TEST_EXPECTED"), &expected, &expected_count);
      if (!result && (status || expected_count != length ||
                      memcmp(expected, answer, length * sizeof(uint64_t))))
	result = 1;
      free(expected);
    }
  }
  free(words);
  free(answer);
  /* argv storage stays live until exit: the guest can inspect its arguments. */
  if (result)
    return error("guard failed");
  puts("1 passed; 0 failed; 0 ignored;");
  return 0;
}
