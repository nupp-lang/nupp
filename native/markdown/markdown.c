/* Bounded allocation boundary for upstream C code which assumes allocation
 * succeeds. No longjmp crosses a guest frame or calls guest code. */
#include "markdown.h"
#include "definition-list.h"
#include <cmark-gfm-core-extensions.h>
#include <render.h>
#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
static SRWLOCK lock = SRWLOCK_INIT;
#define LOCK() AcquireSRWLockExclusive(&lock)
#define UNLOCK() ReleaseSRWLockExclusive(&lock)
#else
#include <pthread.h>
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
#define LOCK() pthread_mutex_lock(&lock)
#define UNLOCK() pthread_mutex_unlock(&lock)
#endif

typedef union allocation allocation;
union allocation {
    struct { allocation *prev, *next; size_t bytes; } h;
    long double alignment;
    void *pointer_alignment;
};
struct nupp_markdown {
    allocation *allocations;
    jmp_buf failure;
    size_t remaining, size;
    char *text;
    unsigned char *line_endings;
    size_t lines;
    int unterminated_line;
    int used;
};
/* cmark's registry and optional arena are process-global. Serialize only this
 * private copy of upstream cmark; no guest callback or scheduler runs here. */
static nupp_markdown *active;
static void *allocate(size_t count, size_t width) {
    if (width && count > SIZE_MAX / width) longjmp(active->failure, 1);
    size_t bytes = count * width;
    if (bytes > SIZE_MAX - sizeof(allocation) || bytes + sizeof(allocation) > active->remaining)
        longjmp(active->failure, 1);
    allocation *item = calloc(1, sizeof(allocation) + bytes);
    if (!item) longjmp(active->failure, 1);
    active->remaining -= sizeof(allocation) + bytes;
    item->h.bytes = bytes;
    item->h.next = active->allocations;
    if (item->h.next) item->h.next->h.prev = item;
    active->allocations = item;
    return item + 1;
}
static void release(void *ptr) {
    if (!ptr) return;
    allocation *item = (allocation *)ptr - 1;
    if (item->h.prev) item->h.prev->h.next = item->h.next;
    else active->allocations = item->h.next;
    if (item->h.next) item->h.next->h.prev = item->h.prev;
    free(item);
}
static void *resize(void *ptr, size_t bytes) {
    void *result = allocate(1, bytes);
    if (ptr) {
        size_t old = ((allocation *)ptr - 1)->h.bytes;
        memcpy(result, ptr, old < bytes ? old : bytes);
        release(ptr);
    }
    return result;
}
static cmark_mem memory = {allocate, resize, release};
static int contains(const char *haystack, size_t bytes, const char *needle, size_t length) {
    if (length > bytes) return 0;
    for (size_t at = 0; at <= bytes - length; at++)
        if (haystack[at] == needle[0] && !memcmp(haystack + at, needle, length)) return 1;
    return 0;
}
static cmark_node *tag(cmark_node_type type, const char *enter, const char *leave) {
    cmark_node *node = cmark_node_new_with_mem(type, &memory);
    cmark_node_set_on_enter(node, enter);
    cmark_node_set_on_exit(node, leave);
    return node;
}
/* Preserve the old table HTML bytes using public AST accessors. The upstream
 * table parser and inline renderer still own all Markdown interpretation. */
static void table_html(cmark_node *root) {
    cmark_iter *iter = cmark_iter_new(root);
    cmark_event_type event;
    while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
        cmark_node *table = cmark_iter_get_node(iter);
        if (event != CMARK_EVENT_EXIT || strcmp(cmark_node_get_type_string(table), "table")) continue;
        cmark_node *parent = cmark_node_parent(table);
        cmark_node_type type = CMARK_NODE_CUSTOM_BLOCK;
        if (cmark_node_get_type(parent) == CMARK_NODE_CUSTOM_INLINE) type = CMARK_NODE_CUSTOM_INLINE;
        if (cmark_node_get_type(parent) == CMARK_NODE_ITEM && cmark_node_get_list_tight(cmark_node_parent(parent)))
            type = CMARK_NODE_PARAGRAPH;
        cmark_node *block = cmark_node_new_with_mem(type, &memory);
        cmark_node *html = tag(CMARK_NODE_CUSTOM_INLINE, "<table><thead>", "</table>\n");
        cmark_node_append_child(block, html);
        uint8_t *alignment = cmark_gfm_extensions_get_table_alignments(table);
        for (cmark_node *row = cmark_node_first_child(table); row; row = cmark_node_next(row)) {
            int header = cmark_gfm_extensions_get_table_row_is_header(row);
            int body = !header && cmark_gfm_extensions_get_table_row_is_header(cmark_node_previous(row));
            cmark_node *tr = tag(CMARK_NODE_CUSTOM_INLINE, body ? "<tbody>\n<tr>" : "<tr>",
                header ? (cmark_node_next(row) ? "</tr></thead>" : "</tr></thead><tbody>\n</tbody>") :
                cmark_node_next(row) ? "</tr>\n" : "</tr>\n</tbody>");
            cmark_node_append_child(html, tr);
            size_t column = 0;
            for (cmark_node *cell = cmark_node_first_child(row); cell; cell = cmark_node_next(cell), column++) {
                const char *open = header ? "<th>" : "<td>";
                if (alignment[column] == 'l') open = header ? "<th style=\"text-align: left\">" : "<td style=\"text-align: left\">";
                if (alignment[column] == 'r') open = header ? "<th style=\"text-align: right\">" : "<td style=\"text-align: right\">";
                if (alignment[column] == 'c') open = header ? "<th style=\"text-align: center\">" : "<td style=\"text-align: center\">";
                cmark_node *td = tag(CMARK_NODE_CUSTOM_INLINE, open, header ? "</th>" : "</td>");
                cmark_node_append_child(tr, td);
                while (cmark_node_first_child(cell)) cmark_node_append_child(td, cmark_node_first_child(cell));
            }
        }
        if (!cmark_node_insert_before(table, block)) longjmp(active->failure, 1);
        cmark_node_free(table);
        cmark_iter_reset(iter, block, CMARK_EVENT_EXIT);
    }
    cmark_iter_free(iter);
}
/* Upstream adds line breaks around raw HTML blocks. The prior renderer
 * emits only the block's source line breaks, including inside containers. */
static void raw_html(cmark_syntax_extension *ext, cmark_html_renderer *renderer,
                     cmark_node *node, cmark_event_type event, int options) {
    (void)ext;
    cmark_strbuf *html = renderer->html;
    if (cmark_node_get_type(node) == CMARK_NODE_BLOCK_QUOTE) {
        if (event == CMARK_EVENT_ENTER) {
            if (html->size && html->ptr[html->size - 1] != '\n') cmark_strbuf_putc(html, '\n');
            cmark_strbuf_puts(html, "<blockquote>\n");
        } else cmark_strbuf_puts(html, "</blockquote>\n");
        return;
    }
    if (event != CMARK_EVENT_ENTER) return;
    if (!(options & CMARK_OPT_UNSAFE)) {
        cmark_strbuf_puts(html, "<!-- raw HTML omitted -->\n");
        return;
    }
    const char *literal = cmark_node_get_literal(node);
    size_t size = strlen(literal);
    if (active->unterminated_line && size && literal[size - 1] == '\n') {
        size_t line = (size_t)cmark_node_get_start_line(node);
        for (size_t at = 0; at + 1 < size; at++)
            if (literal[at] == '\n') line++;
        if (line == active->lines - 1) size--;
    }
    cmark_strbuf_put(html, (const unsigned char *)literal, (bufsize_t)size);
}
static void compatible_text(cmark_node *root, cmark_syntax_extension *raw,
                            const char *token, size_t marker, const char *plain, size_t base) {
    cmark_iter *iter = cmark_iter_new(root);
    cmark_event_type event;
    int image = 0;
    while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
        cmark_node *node = cmark_iter_get_node(iter);
        cmark_node_type type = cmark_node_get_type(node);
        if (event == CMARK_EVENT_ENTER && (type == CMARK_NODE_HTML_BLOCK ||
            (type == CMARK_NODE_BLOCK_QUOTE && cmark_node_get_type(cmark_node_last_child(node)) == CMARK_NODE_HTML_BLOCK)))
            cmark_node_set_syntax_extension(node, raw);
        if (type == CMARK_NODE_IMAGE) image += event == CMARK_EVENT_ENTER ? 1 : -1;
        if (event == CMARK_EVENT_ENTER && type == CMARK_NODE_HTML_INLINE) {
            const char *literal = cmark_node_get_literal(node);
            size_t size = strlen(literal), to = 0;
            char *copy = allocate(size + 1, 2);
            size_t line = (size_t)cmark_node_get_start_line(node);
            for (size_t at = 0; at < size; at++) {
                if (literal[at] == '\n') {
                    unsigned char ending = line < active->lines ? active->line_endings[line] : 0;
                    if (ending) copy[to++] = '\r';
                    if (ending != 1) copy[to++] = '\n';
                    line++;
                } else copy[to++] = literal[at];
            }
            copy[to] = 0;
            cmark_node_set_literal(node, copy);
            release(copy);
        }
        if (event == CMARK_EVENT_ENTER && token && cmark_node_get_type(node) == CMARK_NODE_CODE_BLOCK) {
            const char *info = cmark_node_get_fence_info(node);
            if (info && contains(info, strlen(info), token, marker)) {
                size_t size = strlen(info), from = 0, to = 0;
                char *copy = allocate(1, size + 1);
                while (from < size) {
                    if (marker <= size - from && !memcmp(info + from, token, marker)) {
                        memcpy(copy + to, plain, base); to += base; from += marker;
                    } else copy[to++] = info[from++];
                }
                copy[to] = 0;
                cmark_node_set_fence_info(node, copy);
                release(copy);
            }
        }
        if (image || event != CMARK_EVENT_ENTER || cmark_node_get_type(node) != CMARK_NODE_TEXT ||
            !strchr(cmark_node_get_literal(node), '"')) continue;
        /* Keep pulldown's text spelling, while upstream still escapes markup
         * and quotes in attributes. Never unescape the rendered document. */
        char *escaped = cmark_render_html_with_mem(node, CMARK_OPT_UNSAFE, NULL, &memory);
        size_t from = 0, to = 0;
        while (escaped[from]) {
            if (!strncmp(escaped + from, "&quot;", 6)) { escaped[to++] = '"'; from += 6; }
            else escaped[to++] = escaped[from++];
        }
        escaped[to] = 0;
        /* Table cells permit HTML_INLINE, but not CUSTOM_INLINE. The value
         * was escaped by upstream above; this cannot introduce HTML syntax. */
        if (!cmark_node_set_type(node, CMARK_NODE_HTML_INLINE) || !cmark_node_set_literal(node, escaped))
            longjmp(active->failure, 1);
        release(escaped);
    }
    cmark_iter_free(iter);
}
static char *render(const char *input, size_t bytes, cmark_syntax_extension *definition,
                    cmark_syntax_extension *raw,
                    const char *token, size_t marker, const char *plain, size_t base, unsigned char *html) {
    cmark_parser *parser = cmark_parser_new_with_mem(CMARK_OPT_UNSAFE | CMARK_OPT_TABLE_PREFER_STYLE_ATTRIBUTES, &memory);
    cmark_parser_attach_syntax_extension(parser, definition);
    cmark_parser_attach_syntax_extension(parser, cmark_find_syntax_extension("table"));
    cmark_parser_feed(parser, input, bytes);
    cmark_node *root = cmark_parser_finish(parser);
    if (html) {
        cmark_iter *iter = cmark_iter_new(root);
        cmark_event_type event;
        while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
            cmark_node *node = cmark_iter_get_node(iter);
            cmark_node_type type = cmark_node_get_type(node);
            if (event != CMARK_EVENT_ENTER || (type != CMARK_NODE_HTML_INLINE && type != CMARK_NODE_HTML_BLOCK)) continue;
            const char *literal = cmark_node_get_literal(node);
            if (!strstr(literal, plain)) continue;
            /* The upstream AST, not a tag scanner, identifies raw HTML. Charge
             * literal searches to the same finite native resource budget. */
            if (bytes > active->remaining) longjmp(active->failure, 1);
            active->remaining -= bytes;
            size_t length = strlen(literal);
            const char *found = strstr(input, literal);
            for (const char *at = found; at; at = strstr(at + length, literal))
                memset(html + (at - input), 1, length);
            if (!found && strchr(literal, '\n')) {
                /* Container prefixes were removed by upstream. Match each
                 * literal fragment only on its upstream source line. */
                const char *row = input;
                for (int line = 1; line < cmark_node_get_start_line(node) && *row; line++) {
                    const char *end = strchr(row, '\n');
                    row = end ? end + 1 : input + bytes;
                }
                for (const char *part = literal; *part && *row;) {
                    const char *next = strchr(part, '\n'), *end = strchr(row, '\n');
                    size_t count = next ? (size_t)(next - part) : strlen(part);
                    if (!end) end = input + bytes;
                    for (const char *at = row; count && count <= (size_t)(end - at); at++)
                        if (!memcmp(at, part, count)) memset(html + (at - input), 1, count);
                    if (!next || !*end) break;
                    part = next + 1; row = end + 1;
                }
            }
        }
        cmark_iter_free(iter);
    }
    compatible_text(root, raw, token, marker, plain, base);
    table_html(root);
    char *result = cmark_render_html(root, CMARK_OPT_UNSAFE | CMARK_OPT_TABLE_PREFER_STYLE_ATTRIBUTES,
                                    cmark_parser_get_syntax_extensions(parser));
    cmark_node_free(root);
    cmark_parser_free(parser);
    return result;
}
static void clear(nupp_markdown *doc) {
    while (doc->allocations) {
        allocation *next = doc->allocations->h.next;
        free(doc->allocations);
        doc->allocations = next;
    }
    doc->text = NULL;
    doc->size = 0;
}
const char *nupp_markdown_revision(void) {
    return "27d942c8b0a62d192f616e5bf3578f4b6a89e180/definition-list-1";
}
nupp_markdown *nupp_markdown_new(void) { return calloc(1, sizeof(nupp_markdown)); }
int nupp_markdown_render(nupp_markdown *doc, const char *input, size_t bytes, size_t budget) {
    if (!doc || doc->used || (!input && bytes)) return -3;
    doc->used = 1;
    if (bytes > 8 * 1024 * 1024 || budget > 256 * 1024 * 1024) return -2;
    LOCK();
    active = doc;
    doc->remaining = budget;
    cmark_gfm_core_extensions_ensure_registered();
    cmark_syntax_extension *definition = nupp_definition_list_new(&memory);
    cmark_syntax_extension *raw = cmark_syntax_extension_new("nupp_raw_html");
    cmark_syntax_extension_set_html_render_func(raw, raw_html);
    int status = -1;
    if (!setjmp(doc->failure)) {
        const char *source = input ? input : "";
        doc->unterminated_line = bytes && source[bytes - 1] != '\n' && source[bytes - 1] != '\r';
        doc->lines = 2;
        for (size_t at = 0; at < bytes; at++) {
            if (source[at] == '\n' || source[at] == '\r') {
                doc->lines++;
                if (source[at] == '\r' && at + 1 < bytes && source[at + 1] == '\n') at++;
            }
        }
        doc->line_endings = allocate(doc->lines, 1);
        size_t line = 1;
        for (size_t at = 0; at < bytes; at++) {
            if (source[at] == '\r') {
                doc->line_endings[line] = 1;
                if (at + 1 < bytes && source[at + 1] == '\n') { doc->line_endings[line] = 2; at++; }
                line++;
            } else if (source[at] == '\n') line++;
        }
        doc->text = render(source, bytes, definition, raw, NULL, 0, NULL, 0, NULL);
        int bom = bytes >= 3 && !memcmp(source, "\xef\xbb\xbf", 3);
        if (memchr(source, 0, bytes) || bom) {
            /* Lossless byte transport, not Markdown preprocessing. cmark
             * consumes NUL and an initial BOM before public hooks run. Pick
             * a control sequence absent in source AND ordinary rendered HTML
             * (including entity-decoded text), then restore by explicit size. */
            size_t ones = 1, run = 0;
            for (size_t i = 0; i < bytes; i++) {
                run = source[i] == 1 ? run + 1 : 0;
                if (run >= ones) ones = run + 1;
            }
            run = 0;
            for (const char *p = doc->text; *p; p++) {
                run = *p == 1 ? run + 1 : 0;
                if (run >= ones) ones = run + 1;
            }
            char *url;
            size_t url_size;
            for (;;) {
                url_size = ones * 6 + 9;
                url = allocate(1, url_size + 1);
                for (size_t i = 0; i < ones; i++) memcpy(url + i * 3, "%01", 3);
                memcpy(url + ones * 3, "%02%20%02", 9);
                for (size_t i = 0; i < ones; i++) memcpy(url + ones * 3 + 9 + i * 3, "%01", 3);
                if (!contains(source, bytes, url, url_size) && !strstr(doc->text, url)) break;
                release(url);
                ones *= 2;
            }
            size_t base = ones * 2 + 2, marker = base + 1;
            char *plain = allocate(1, base + 1), *token = allocate(1, marker + 1);
            memset(plain, 1, base); plain[ones] = plain[ones + 1] = 2;
            memset(token, 1, marker); token[ones] = token[ones + 2] = 2; token[ones + 1] = ' ';
            size_t zeros = 0;
            for (size_t at = 0; at < bytes; at++) if (source[at] == 0) zeros++;
            char *candidate = allocate(1, bytes + zeros * (base - 1) + (bom ? base : 0) + 1);
            size_t size = 0;
            if (bom) { memcpy(candidate, plain, base); size += base; }
            for (size_t at = 0; at < bytes; at++) {
                if (source[at] == 0) { memcpy(candidate + size, plain, base); size += base; }
                else if (source[at] == '\r') {
                    candidate[size++] = '\n';
                    if (at + 1 < bytes && source[at + 1] == '\n') at++;
                } else candidate[size++] = source[at];
            }
            unsigned char *html = allocate(size + 1, 1);
            char *probe = render(candidate, size, definition, raw, NULL, 0, plain, base, html);
            release(probe);
            char *encoded = allocate(1, bytes + zeros * (marker - 1) + (bom ? base : 0) + 1);
            size_t encoded_size = 0;
            for (size_t at = 0; at < size;) {
                if (base <= size - at && !memcmp(candidate + at, plain, base)) {
                    int raw = html[at] || (bom && at == 0);
                    size_t width = raw ? base : marker;
                    memcpy(encoded + encoded_size, raw ? plain : token, width);
                    encoded_size += width; at += base;
                } else encoded[encoded_size++] = candidate[at++];
            }
            release(candidate);
            release(html);
            release(doc->text);
            doc->text = render(encoded, encoded_size, definition, raw, token, marker, plain, base, NULL);
            release(encoded);
            size_t from = 0, to = 0, length = strlen(doc->text);
            while (from < length) {
                if (marker <= length - from && !memcmp(doc->text + from, token, marker)) {
                    doc->text[to++] = 0;
                    from += marker;
                } else if (base <= length - from && !memcmp(doc->text + from, plain, base)) {
                    if (bom) bom = 0;
                    else doc->text[to++] = 0;
                    from += base;
                } else if (url_size <= length - from && !memcmp(doc->text + from, url, url_size)) {
                    memcpy(doc->text + to, "%00", 3); to += 3; from += url_size;
                } else doc->text[to++] = doc->text[from++];
            }
            doc->text[to] = 0;
            doc->size = to;
            release(token);
            release(plain);
            release(url);
        } else doc->size = strlen(doc->text);
        status = 0;
    } else clear(doc);
    cmark_syntax_extension_free(cmark_get_default_mem_allocator(), raw);
    cmark_syntax_extension_free(cmark_get_default_mem_allocator(), definition);
    active = NULL;
    UNLOCK();
    return status;
}
const char *nupp_markdown_text(const nupp_markdown *doc) { return doc ? doc->text : NULL; }
const char *nupp_markdown_text_at(const nupp_markdown *doc, size_t at) {
    return doc && at <= doc->size && doc->text ? doc->text + at : NULL;
}
size_t nupp_markdown_size(const nupp_markdown *doc) { return doc ? doc->size : 0; }
void nupp_markdown_free(nupp_markdown *doc) { if (doc) { clear(doc); free(doc); } }
