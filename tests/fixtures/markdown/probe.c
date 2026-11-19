/**
 * @file
 * @brief Renders standard input with the installed Markdown library.
 *
 * The Markdown renderer's probe, only in tests. It renders standard input
 * with the installed library and writes the HTML, byte for byte, to standard
 * output. .github/scripts/test-markdown.sh builds it against the relocated
 * library, and check.mjs runs it on every fixture in this directory.
 */

#include <stdio.h>
#include <stdlib.h>

#include <nupp/markdown.h>

#ifdef _WIN32

#include <fcntl.h>
#include <io.h>

#endif

/* How the probe exits. */
enum {
  RENDERED = 0,
  /* Reading standard input failed, or it held more than INPUT_BYTES. */
  BAD_INPUT = 2,
  NO_DOCUMENT = 3,
  RENDER_FAILED = 4,
};

/* The largest input the probe reads, which is all any fixture needs. */
enum { INPUT_BYTES = 1048576 };

/* The renderer's budget, the one the core gives it. */
enum { BUDGET = 128 * 1024 * 1024 };

int main (void) {
  static char input[INPUT_BYTES];
#ifdef _WIN32

  /* Pass CR and NUL through untranslated. */
  if (_setmode(_fileno(stdin), _O_BINARY) == -1 ||
      _setmode(_fileno(stdout), _O_BINARY) == -1) {
    return BAD_INPUT;
  }

#endif

  size_t size = fread(input, 1, sizeof(input), stdin);

  if (ferror(stdin) || !feof(stdin)) {
    return BAD_INPUT;
  }

  nuppmarkdown *doc = nuppmarkdownnew();

  if (!doc) {
    return NO_DOCUMENT;
  }

  int status = nuppmarkdownrender(doc, input, size, BUDGET);

  if (!status) {
    fwrite(nuppmarkdowntext(doc), 1, nuppmarkdownsize(doc), stdout);
  }

  nuppmarkdownfree(doc);

  if (status) {
    return RENDER_FAILED;
  }

  return RENDERED;
}
