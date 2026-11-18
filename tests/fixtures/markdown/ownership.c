/* The Markdown renderer's ownership and resource checks, only in tests.
 * .github/scripts/test-markdown.sh runs it against the relocated library:
 * the revision, a budget failure at every size releasing what it held, a
 * document refusing a second render, NUL surviving in the HTML and its
 * suffixes, the size limit, a NULL input, and two threads rendering at once
 * under the library's lock. */

#include <assert.h>
#include <stdio.h>
#include <string.h>

#include <nupp/markdown.h>

#ifdef _WIN32

#include <windows.h>

#else

#include <pthread.h>

#endif

/* What nupp_markdown_render answers for a failure (markdown.c). */
enum { NO_RESOURCES = -1, TOO_LARGE = -2, MISUSE = -3 };

/* A budget every document here fits in. */
enum { BUDGET = 65536 };

/* One more byte than the renderer accepts. */
enum { OVERSIZED = 8388609 };

/* How many documents each thread renders. */
enum { RENDERS = 16 };

/* A thread's body: renders a heading RENDERS times, while the other thread
 * does the same. */
#ifdef _WIN32
static DWORD WINAPI concurrent (LPVOID unused)
#else
static void *concurrent (void *unused)
#endif
{
  (void)unused;

  for (int i = 0; i < RENDERS; i++) {
    nupp_markdown *doc = nupp_markdown_new();
    assert(doc && nupp_markdown_render(doc, "# Thread", 8, BUDGET) == 0);
    assert(!strcmp(nupp_markdown_text(doc), "<h1>Thread</h1>\n"));
    nupp_markdown_free(doc);
  }

  return 0;
}

int main (void) {
  assert(!strcmp(nupp_markdown_revision(),
                 "27d942c8b0a62d192f616e5bf3578f4b6a89e180/definition-list-1"));

  for (size_t budget = 0; budget < BUDGET; budget = budget ? budget * 2 : 1) {
    nupp_markdown *doc = nupp_markdown_new();
    assert(doc);
    int status =
        nupp_markdown_render(doc, "Term\n: first\n\n    - child\n", 25, budget);

    if (status) {
      assert(status == NO_RESOURCES);
      assert(!nupp_markdown_text(doc));
      assert(!nupp_markdown_size(doc));
    }
    else {
      assert(nupp_markdown_text(doc));
    }

    assert(nupp_markdown_render(doc, "x", 1, BUDGET) == MISUSE);
    nupp_markdown_free(doc);
  }

  nupp_markdown *first = nupp_markdown_new(), *second = nupp_markdown_new();
  assert(first && second);
  assert(nupp_markdown_render(first, "a\0b", 3, BUDGET) == 0);
  assert(nupp_markdown_size(first) == 11);
  assert(!memcmp(nupp_markdown_text(first), "<p>a\0b</p>\n", 11));
  assert(!strcmp(nupp_markdown_text_at(first, 5), "b</p>\n"));
  assert(!nupp_markdown_text_at(first, 12));

  assert(nupp_markdown_render(second, "# Next", 6, BUDGET) == 0);
  nupp_markdown_free(second);
  assert(!memcmp(nupp_markdown_text(first), "<p>a\0b</p>\n", 11));
  nupp_markdown_free(first);

  first = nupp_markdown_new();
  assert(nupp_markdown_render(first, "x", OVERSIZED, BUDGET) == TOO_LARGE);
  nupp_markdown_free(first);

  first = nupp_markdown_new();
  assert(nupp_markdown_render(first, NULL, 1, BUDGET) == MISUSE);
  nupp_markdown_free(first);
  nupp_markdown_free(NULL);

#ifdef _WIN32
  HANDLE threads[2] = {CreateThread(NULL, 0, concurrent, NULL, 0, NULL),
                       CreateThread(NULL, 0, concurrent, NULL, 0, NULL)};
  assert(threads[0] && threads[1]);
  assert(WaitForMultipleObjects(2, threads, TRUE, INFINITE) == WAIT_OBJECT_0);
  CloseHandle(threads[0]);
  CloseHandle(threads[1]);
#else
  pthread_t threads[2];
  assert(!pthread_create(&threads[0], NULL, concurrent, NULL));
  assert(!pthread_create(&threads[1], NULL, concurrent, NULL));
  assert(!pthread_join(threads[0], NULL) && !pthread_join(threads[1], NULL));
#endif

  puts("Markdown ownership/resource checks passed");

  return 0;
}
