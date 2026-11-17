#include <stdio.h>
#include <stdlib.h>
#include <nupp/markdown.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
int main(void) {
    static char input[1048576];
#ifdef _WIN32
    if (_setmode(_fileno(stdin), _O_BINARY) == -1 || _setmode(_fileno(stdout), _O_BINARY) == -1) return 2;
#endif
    size_t size = fread(input, 1, sizeof(input), stdin);
    if (ferror(stdin) || !feof(stdin)) return 2;
    nupp_markdown *doc = nupp_markdown_new();
    if (!doc) return 3;
    int status = nupp_markdown_render(doc, input, size, 128 * 1024 * 1024);
    if (!status) fwrite(nupp_markdown_text(doc), 1, nupp_markdown_size(doc), stdout);
    nupp_markdown_free(doc);
    if (status) return 4;
    return 0;
}
