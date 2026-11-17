#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <nupp/markdown.h>
#ifdef _WIN32
#include <windows.h>
static DWORD WINAPI concurrent(LPVOID unused) {
#else
#include <pthread.h>
static void *concurrent(void *unused) {
#endif
    (void)unused;
    for (int i = 0; i < 16; i++) {
        nupp_markdown *doc = nupp_markdown_new();
        assert(doc && nupp_markdown_render(doc, "# Thread", 8, 65536) == 0);
        assert(!strcmp(nupp_markdown_text(doc), "<h1>Thread</h1>\n"));
        nupp_markdown_free(doc);
    }
    return 0;
}
int main(void) {
    assert(!strcmp(nupp_markdown_revision(), "27d942c8b0a62d192f616e5bf3578f4b6a89e180/definition-list-1"));
    for (size_t budget = 0; budget < 65536; budget = budget ? budget * 2 : 1) {
        nupp_markdown *doc = nupp_markdown_new();
        assert(doc);
        int status = nupp_markdown_render(doc, "Term\n: first\n\n    - child\n", 25, budget);
        if (status) { assert(status == -1); assert(!nupp_markdown_text(doc)); assert(!nupp_markdown_size(doc)); }
        else assert(nupp_markdown_text(doc));
        assert(nupp_markdown_render(doc, "x", 1, 65536) == -3);
        nupp_markdown_free(doc);
    }
    nupp_markdown *first = nupp_markdown_new(), *second = nupp_markdown_new();
    assert(first && second);
    assert(nupp_markdown_render(first, "a\0b", 3, 65536) == 0);
    assert(nupp_markdown_size(first) == 11);
    assert(!memcmp(nupp_markdown_text(first), "<p>a\0b</p>\n", 11));
    assert(!strcmp(nupp_markdown_text_at(first, 5), "b</p>\n"));
    assert(!nupp_markdown_text_at(first, 12));
    assert(nupp_markdown_render(second, "# Next", 6, 65536) == 0);
    nupp_markdown_free(second);
    assert(!memcmp(nupp_markdown_text(first), "<p>a\0b</p>\n", 11));
    nupp_markdown_free(first);
    first = nupp_markdown_new();
    assert(nupp_markdown_render(first, "x", 8388609, 65536) == -2);
    nupp_markdown_free(first);
    first = nupp_markdown_new();
    assert(nupp_markdown_render(first, NULL, 1, 65536) == -3);
    nupp_markdown_free(first);
    nupp_markdown_free(NULL);
#ifdef _WIN32
    HANDLE threads[2] = {CreateThread(NULL, 0, concurrent, NULL, 0, NULL), CreateThread(NULL, 0, concurrent, NULL, 0, NULL)};
    assert(threads[0] && threads[1]);
    assert(WaitForMultipleObjects(2, threads, TRUE, INFINITE) == WAIT_OBJECT_0);
    CloseHandle(threads[0]); CloseHandle(threads[1]);
#else
    pthread_t threads[2];
    assert(!pthread_create(&threads[0], NULL, concurrent, NULL));
    assert(!pthread_create(&threads[1], NULL, concurrent, NULL));
    assert(!pthread_join(threads[0], NULL) && !pthread_join(threads[1], NULL));
#endif
    puts("Markdown ownership/resource checks passed");
    return 0;
}
