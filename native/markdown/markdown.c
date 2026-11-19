/**
 * @file
 * @brief Renders Markdown through cmark-gfm with bounded resource use.
 *
 * The Markdown renderer behind markdown.h: the pinned upstream cmark-gfm, with
 * its tables and the colon definition lists of definitionlist.c, made to
 * write the HTML bytes of the renderer it replaced, whose frozen outputs are
 * in tests/fixtures/markdown. The core's Markdown provider and the checkout's
 * documentation host call it through FFI; docs/native-markdown.md describes
 * the dialect and the byte policy.
 *
 * Upstream is used unchanged. Around it this file adds three things:
 *
 * - A bounded allocation boundary for upstream C code which assumes
 *   allocation succeeds. Every allocation is charged to the document's budget
 *   and tracked, and a failure longjmps back to nuppmarkdownrender, which
 *   frees what was tracked. No longjmp crosses a guest frame or calls guest
 *   code.
 * - Compatibility rendering, which writes tables, links, images, code, text,
 *   block quotes and raw HTML the way the old renderer did.
 * - A byte transport for NUL and an initial BOM, which cmark consumes before
 *   any extension hook could see them (see transport).
 */

#include "markdown.h"
#include "definitionlist.h"

#include <cmark-gfm-core-extensions.h>
#include <houdini.h>
#include <node.h>
#include <render.h>

#include <setjmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* One lock around every call into cmark (see the comment on its use). */
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

/* The upstream commit and the definition-list hook ABI this library is built
 * from. Its callers compare it with the revision they were written for. */
#define REVISION "27d942c8b0a62d192f616e5bf3578f4b6a89e180/definition-list-1"

/* The largest input and budget nuppmarkdownrender accepts. */
#define MAX_INPUT_BYTES ((size_t)8 * 1024 * 1024)
#define MAX_BUDGET_BYTES ((size_t)256 * 1024 * 1024)

/* The UTF-8 byte order mark, which cmark skips at the start of its input. */
#define UTF8_BOM "\xef\xbb\xbf"
#define UTF8_BOM_BYTES 3

/* The token as upstream percent-encodes it in a link destination (see
 * transport): ESCAPED_ONE is RUN_BYTE and ESCAPED_MIDDLE the token's
 * middle, each escaped byte ESCAPE_BYTES long. */
#define ESCAPED_ONE "%01"
#define ESCAPED_MIDDLE "%02%20%02"
#define ESCAPE_BYTES 3
#define ESCAPED_MIDDLE_BYTES 9

/* How a link destination spells a transported NUL in HTML. */
#define ESCAPED_NUL "%00"

/* What nuppmarkdownrender answers. */
enum status {
  RENDERED = 0,

  /* The budget ran out, or an allocation failed. */
  NO_RESOURCES = -1,

  /* The input or the budget is larger than this library accepts. */
  TOO_LARGE = -2,

  /* No document, one already rendered, or a NULL input with a length. */
  MISUSE = -3,
};

/* How a source line ends, as a document's lineendings records it. */
enum lineending { LF = 0, CR = 1, CRLF = 2 };

/* The two bytes the transport's markers are made of (see transport). */
enum { RUN_BYTE = 1, MIDDLE_BYTE = 2 };

/* The flag findrawhtml sets on each input byte that raw HTML holds. */
enum { IN_RAW_HTML = 1 };

/* The header in front of each allocation. It links the allocation into its
 * document's list, so that a failure can free everything, and records its
 * size for resize. As a union it is padded to the strictest alignment, so
 * the bytes after it suit any type. */
typedef union allocation allocation;

union allocation {
  struct {
    allocation *prev, *next;
    size_t bytes;
  } h;

  long double alignment;
  void *pointeralign;
};

struct nuppmarkdown {

  /* Every live allocation, newest first. */
  allocation *allocations;

  /* Where a failure inside cmark returns to. */
  jmp_buf failure;

  /* The budget still unspent, and the byte length of text. */
  size_t remaining, size;

  /* The rendered HTML, which may hold NUL. */
  char *text;

  /* How each source line ends, indexed by line number from 1, and the
   * number of entries. */
  unsigned char *lineendings;
  size_t lines;

  /* Where the alt text of the image being rendered starts in the HTML. */
  bufsize_t altstart;

  /* The source's last line has no line break. */
  int unterminated;

  /* nuppmarkdownrender has been called. */
  int used;
};

/* cmark's registry and optional arena are process-global. Serialize only this
 * private copy of upstream cmark; no guest callback or scheduler runs here. */
static nuppmarkdown *active;

/* Abandons the render: returns to nuppmarkdownrender's setjmp. */
static void fail (void) {
  longjmp(active->failure, 1);
}

/* Charges work that allocates nothing, such as a literal search, to the
 * budget. */
static void charge (size_t bytes) {
  if (bytes > active->remaining) {
    fail();
  }

  active->remaining -= bytes;
}

/* cmark's calloc: zeroed, tracked and charged with its header. */
static void *allocate (size_t count, size_t width) {
  if (width && count > SIZE_MAX / width) {
    fail();
  }

  size_t bytes = count * width;

  if (bytes > SIZE_MAX - sizeof(allocation) ||
      bytes + sizeof(allocation) > active->remaining) {
    fail();
  }

  allocation *item = calloc(1, sizeof(allocation) + bytes);

  if (!item) {
    fail();
  }

  active->remaining -= sizeof(allocation) + bytes;
  item->h.bytes = bytes;

  item->h.next = active->allocations;

  if (item->h.next) {

    /* The analyzer loses the header behind the pointer release is given.
     * NOLINTNEXTLINE(clang-analyzer-unix.Malloc) */
    item->h.next->h.prev = item;
  }

  active->allocations = item;

  return item + 1;
}

/* cmark's free. What it frees is not credited back, so the budget caps the
 * total allocated rather than the most held at once. */
static void release (void *ptr) {
  if (!ptr) {
    return;
  }

  allocation *item = (allocation *)ptr - 1;

  if (item->h.prev) {
    item->h.prev->h.next = item->h.next;
  }
  else {
    active->allocations = item->h.next;
  }

  if (item->h.next) {
    item->h.next->h.prev = item->h.prev;
  }

  free(item);
}

/* cmark's realloc, as a fresh allocation and a copy. */
static void *resize (void *ptr, size_t bytes) {
  void *result = allocate(1, bytes);

  if (ptr) {
    size_t old = ((allocation *)ptr - 1)->h.bytes;
    memcpy(result, ptr, old < bytes ? old : bytes);
    release(ptr);
  }

  return result;
}

static cmark_mem memory = {allocate, resize, release};

/* Whether needle occurs in haystack. Unlike strstr, either may hold NUL. */
static int contains (const char *haystack, size_t bytes, const char *needle,
                     size_t length) {
  if (length > bytes) {
    return 0;
  }

  for (size_t at = 0; at <= bytes - length; at++) {
    if (haystack[at] == needle[0] && !memcmp(haystack + at, needle, length)) {
      return 1;
    }
  }

  return 0;
}

/* A new custom node that renders as enter, its children, then leave. */
static cmark_node *tag (cmark_node_type type, const char *enter,
                        const char *leave) {
  cmark_node *node = cmark_node_new_with_mem(type, &memory);
  cmark_node_set_on_enter(node, enter);
  cmark_node_set_on_exit(node, leave);

  return node;
}

/* The tag that opens a table cell, with its column's alignment, which the
 * table extension records as 'l', 'r', 'c' or none. */
static const char *cellopen (int header, uint8_t alignment) {
  const char *open = header ? "<th>" : "<td>";

  if (alignment == 'l') {
    open = header ? "<th style=\"text-align: left\">"
                  : "<td style=\"text-align: left\">";
  }

  if (alignment == 'r') {
    open = header ? "<th style=\"text-align: right\">"
                  : "<td style=\"text-align: right\">";
  }

  if (alignment == 'c') {
    open = header ? "<th style=\"text-align: center\">"
                  : "<td style=\"text-align: center\">";
  }

  return open;
}

/* Preserve the old table HTML bytes using public AST accessors. The upstream
 * table parser and inline renderer still own all Markdown interpretation.
 * Each table is replaced by custom nodes that write its tags around the
 * cells' own inlines, so that
 *
 *   | a |
 *   |---|
 *   | 1 |
 *
 * renders as
 *
 *   <table><thead><tr><th>a</th></tr></thead><tbody>
 *   <tr><td>1</td></tr>
 *   </tbody></table>
 *
 * The replacement is a block, except in a tight list item, where it is a
 * paragraph, which the item writes without <p>, and in a custom inline, such
 * as a definition, where it is inline too. */
static void tablehtml (cmark_node *root) {
  cmark_iter *iter = cmark_iter_new(root);
  cmark_event_type event;

  while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    cmark_node *table = cmark_iter_get_node(iter);

    if (event != CMARK_EVENT_EXIT ||
        strcmp(cmark_node_get_type_string(table), "table") != 0) {
      continue;
    }

    cmark_node *parent = cmark_node_parent(table);
    cmark_node_type type = CMARK_NODE_CUSTOM_BLOCK;

    if (cmark_node_get_type(parent) == CMARK_NODE_CUSTOM_INLINE) {
      type = CMARK_NODE_CUSTOM_INLINE;
    }

    if (cmark_node_get_type(parent) == CMARK_NODE_ITEM &&
        cmark_node_get_list_tight(cmark_node_parent(parent))) {
      type = CMARK_NODE_PARAGRAPH;
    }

    cmark_node *block = cmark_node_new_with_mem(type, &memory);
    cmark_node *html =
        tag(CMARK_NODE_CUSTOM_INLINE, "<table><thead>", "</table>\n");
    cmark_node_append_child(block, html);
    uint8_t *alignment = cmark_gfm_extensions_get_table_alignments(table);

    for (cmark_node *row = cmark_node_first_child(table); row;
         row = cmark_node_next(row)) {
      int header = cmark_gfm_extensions_get_table_row_is_header(row);

      /* The first row after the header opens the body. */
      int body = !header && cmark_gfm_extensions_get_table_row_is_header(
                                cmark_node_previous(row));
      cmark_node *tr =
          tag(CMARK_NODE_CUSTOM_INLINE, body ? "<tbody>\n<tr>" : "<tr>",
              header ? (cmark_node_next(row) ? "</tr></thead>"
                                             : "</tr></thead><tbody>\n</tbody>")
              : cmark_node_next(row) ? "</tr>\n"
                                     : "</tr>\n</tbody>");
      cmark_node_append_child(html, tr);
      size_t column = 0;

      for (cmark_node *cell = cmark_node_first_child(row); cell;
           cell = cmark_node_next(cell), column++) {
        cmark_node *td =
            tag(CMARK_NODE_CUSTOM_INLINE, cellopen(header, alignment[column]),
                header ? "</th>" : "</td>");
        cmark_node_append_child(tr, td);

        while (cmark_node_first_child(cell)) {
          cmark_node_append_child(td, cmark_node_first_child(cell));
        }
      }
    }

    if (!cmark_node_insert_before(table, block)) {
      fail();
    }

    cmark_node_free(table);
    cmark_iter_reset(iter, block, CMARK_EVENT_EXIT);
  }

  cmark_iter_free(iter);
}

/* Writes text as the old renderer escaped it. Upstream's escaping escapes
 * double quotes and leaves single quotes alone. The old renderer wrote
 * double quotes bare in text, and in an attribute, where upstream escapes
 * them, also escaped single quotes as &#39;. */
static void escapetext (cmark_strbuf *html, const char *text, size_t size,
                        int attribute) {
  char byte = attribute ? '\'' : '"';

  while (size) {
    const char *next = memchr(text, byte, size);
    size_t span = next ? (size_t)(next - text) : size;
    houdini_escape_html0(html, (const unsigned char *)text, (bufsize_t)span, 0);

    if (!next) {
      break;
    }

    cmark_strbuf_puts(html, attribute ? "&#39;" : "\"");
    text = next + 1;
    size -= span + 1;
  }
}

/* Writes a link destination as upstream does, except that `^` stays bare,
 * as the old renderer left it. */
static void escapeurl (cmark_strbuf *html, const char *text) {
  for (const char *caret; (caret = strchr(text, '^')); text = caret + 1) {
    houdini_escape_href(html, (const unsigned char *)text,
                        (bufsize_t)(caret - text));
    cmark_strbuf_putc(html, '^');
  }

  houdini_escape_href(html, (const unsigned char *)text,
                      (bufsize_t)strlen(text));
}

/* Escapes the single quotes in the image alt text upstream has just written,
 * from active->altstart on, as &#39;. */
static void altquotes (cmark_strbuf *html) {
  bufsize_t start = active->altstart, size = html->size - start;

  if (!memchr(html->ptr + start, '\'', (size_t)size)) {
    return;
  }

  char *alt = allocate(1, (size_t)size + 1);
  memcpy(alt, html->ptr + start, (size_t)size);
  cmark_strbuf_truncate(html, start);

  for (const char *part = alt, *quote;; part = quote + 1) {
    quote = strchr(part, '\'');

    if (!quote) {
      cmark_strbuf_puts(html, part);
      break;
    }

    cmark_strbuf_put(html, (const unsigned char *)part,
                     (bufsize_t)(quote - part));
    cmark_strbuf_puts(html, "&#39;");
  }

  release(alt);
}

/* Writes a link as <a href="..." title="...">...</a>, or an image as
 * <img src="..." alt="..." title="..." />, with a title only when there is
 * one. An image's alt text is its content, which upstream writes as plain
 * text between the two events. */
static void linkhtml (cmark_html_renderer *renderer, cmark_node *node,
                      cmark_event_type event) {
  cmark_strbuf *html = renderer->html;
  int image = cmark_node_get_type(node) == CMARK_NODE_IMAGE;

  if (event == CMARK_EVENT_ENTER) {
    cmark_strbuf_puts(html, image ? "<img src=\"" : "<a href=\"");
    escapeurl(html, cmark_node_get_url(node));

    if (image) {
      cmark_strbuf_puts(html, "\" alt=\"");
      active->altstart = html->size;
      renderer->plain = node;

      return;
    }
  }
  else if (image) {
    altquotes(html);
  }
  else {
    cmark_strbuf_puts(html, "</a>");

    return;
  }

  const char *title = cmark_node_get_title(node);

  if (*title) {
    cmark_strbuf_puts(html, "\" title=\"");
    escapetext(html, title, strlen(title), 1);
  }

  cmark_strbuf_puts(html, image ? "\" />" : "\">");
}

/* Starts a new line unless the HTML is empty or already at one. */
static void newline (cmark_strbuf *html) {
  if (html->size && html->ptr[html->size - 1] != '\n') {
    cmark_strbuf_putc(html, '\n');
  }
}

/* Writes inline code as <code>...</code>, or a code block as
 * <pre><code class="language-...">...</code></pre> on a line of its own, the
 * class naming the first word of its fence info when there is one. */
static void codehtml (cmark_strbuf *html, cmark_node *node, int block) {
  if (block) {
    newline(html);
    cmark_strbuf_puts(html, "<pre><code");
    const char *info = cmark_node_get_fence_info(node);
    size_t lang = info ? strcspn(info, " ") : 0;

    if (lang) {
      cmark_strbuf_puts(html, " class=\"language-");
      escapetext(html, info, lang, 1);
      cmark_strbuf_putc(html, '"');
    }

    cmark_strbuf_putc(html, '>');
  }
  else {
    cmark_strbuf_puts(html, "<code>");
  }

  const char *code = cmark_node_get_literal(node);
  escapetext(html, code, strlen(code), 0);
  cmark_strbuf_puts(html, block ? "</code></pre>\n" : "</code>");
}

/* The HTML renderer of the compatibility extension, which preparetree gives
 * every node the old renderer wrote differently. Upstream adds line breaks
 * around raw HTML blocks. The prior renderer emits only the block's source
 * line breaks, including inside containers. */
static void compatiblehtml (cmark_syntax_extension *ext,
                            cmark_html_renderer *renderer, cmark_node *node,
                            cmark_event_type event, int options) {
  (void)ext;
  cmark_strbuf *html = renderer->html;
  cmark_node_type type = cmark_node_get_type(node);

  if (type == CMARK_NODE_LINK || type == CMARK_NODE_IMAGE) {
    linkhtml(renderer, node, event);

    return;
  }

  if (type == CMARK_NODE_CODE || type == CMARK_NODE_CODE_BLOCK) {
    codehtml(html, node, type == CMARK_NODE_CODE_BLOCK);

    return;
  }

  if (type == CMARK_NODE_TEXT) {
    const char *literal = cmark_node_get_literal(node);
    escapetext(html, literal, strlen(literal), 0);

    return;
  }

  if (type == CMARK_NODE_BLOCK_QUOTE) {
    if (event == CMARK_EVENT_ENTER) {
      newline(html);
      cmark_strbuf_puts(html, "<blockquote>\n");
    }
    else {
      cmark_strbuf_puts(html, "</blockquote>\n");
    }

    return;
  }

  /* What is left is a raw HTML block. */
  if (event != CMARK_EVENT_ENTER) {
    return;
  }

  if (!(options & CMARK_OPT_UNSAFE)) {
    cmark_strbuf_puts(html, "<!-- raw HTML omitted -->\n");

    return;
  }

  const char *literal = cmark_node_get_literal(node);
  size_t size = strlen(literal);

  /* Upstream ends the block with a line break even where it ends the source
   * on a line without one; the old renderer did not add it. */
  if (active->unterminated && size && literal[size - 1] == '\n') {
    size_t line = (size_t)cmark_node_get_start_line(node);

    for (size_t at = 0; at + 1 < size; at++) {
      if (literal[at] == '\n') {
        line++;
      }
    }

    if (line == active->lines - 1) {
      size--;
    }
  }

  cmark_strbuf_put(html, (const unsigned char *)literal, (bufsize_t)size);
}

/* The source line an inline HTML literal starts on. Pinned cmark stores each
 * inline HTML literal as a view of the block's normalized text. Cmark's
 * source line can omit newlines in link destinations. Use the view's exact
 * byte position before get_literal converts it to a string. */
static size_t htmlline (cmark_node *node) {
  const cmark_chunk *literal = &node->as.literal;
  uintptr_t address = (uintptr_t)literal->data;

  for (const cmark_node *owner = node->parent; owner; owner = owner->parent) {
    const unsigned char *text = owner->content.ptr;
    uintptr_t base = (uintptr_t)text;
    size_t size = (size_t)owner->content.size;

    if (address < base || address - base >= size) {
      continue;
    }

    size_t offset = (size_t)(address - base);
    size_t line = (size_t)owner->start_line;
    size_t scan = owner->type == CMARK_NODE_PARAGRAPH ? size : offset;
    charge(scan);
    size_t before = 0, after = 0;

    for (size_t at = 0; at < scan; at++) {
      if (text[at] != '\n') {
        continue;
      }

      if (at < offset) {
        before++;
      }
      else {
        after++;
      }
    }

    /* Paragraph finalization can remove leading reference definitions
     * without moving the node's recorded first line. */
    if (owner->type == CMARK_NODE_PARAGRAPH &&
        (size_t)owner->end_line + 1 > line + before + after) {
      line = (size_t)owner->end_line + 1 - before - after;
    }

    return line + before;
  }

  return (size_t)cmark_node_get_start_line(node);
}

/* Whether the old renderer wrote node differently from upstream, so that the
 * compatibility extension should render it: links, images, code, raw HTML
 * blocks, text holding a double quote, and block quotes that end in raw
 * HTML. */
static int iscompatible (cmark_node *node, cmark_node_type type) {
  return type == CMARK_NODE_HTML_BLOCK || type == CMARK_NODE_LINK ||
         type == CMARK_NODE_IMAGE || type == CMARK_NODE_CODE ||
         type == CMARK_NODE_CODE_BLOCK ||
         (type == CMARK_NODE_TEXT &&
          strchr(cmark_node_get_literal(node), '"')) ||
         (type == CMARK_NODE_BLOCK_QUOTE &&
          cmark_node_get_type(cmark_node_last_child(node)) ==
              CMARK_NODE_HTML_BLOCK);
}

/* Gives a multi-line inline HTML literal back the line endings its source
 * lines had, which cmark normalized to LF. */
static void restoreendings (cmark_node *node) {
  size_t line = htmlline(node);
  const char *literal = cmark_node_get_literal(node);
  size_t size = strlen(literal), to = 0;

  /* Room for every byte to become two, as LF becomes CRLF. */
  char *copy = allocate(size + 1, 2);

  for (size_t at = 0; at < size; at++) {
    if (literal[at] == '\n') {
      unsigned char ending =
          line < active->lines ? active->lineendings[line] : LF;

      if (ending != LF) {
        copy[to++] = '\r';
      }

      if (ending != CR) {
        copy[to++] = '\n';
      }

      line++;
    }
    else {
      copy[to++] = literal[at];
    }
  }

  copy[to] = 0;
  cmark_node_set_literal(node, copy);
  release(copy);
}

/* Replaces each transport token in a code block's fence info with the plain
 * marker. The token holds a space, which would end the info's first word,
 * the language codehtml writes. */
static void restorefence (cmark_node *node, const char *token, size_t marker,
                          const char *plain, size_t base) {
  const char *info = cmark_node_get_fence_info(node);

  if (!info || !contains(info, strlen(info), token, marker)) {
    return;
  }

  size_t size = strlen(info), from = 0, to = 0;
  char *copy = allocate(1, size + 1);

  while (from < size) {
    if (marker <= size - from && !memcmp(info + from, token, marker)) {
      memcpy(copy + to, plain, base);
      to += base;
      from += marker;
    }
    else {
      copy[to++] = info[from++];
    }
  }

  copy[to] = 0;
  cmark_node_set_fence_info(node, copy);
  release(copy);
}

/* Readies a parsed tree for rendering: gives the nodes the old renderer
 * wrote differently to the compatibility extension, restores inline HTML's
 * line endings and, while transporting bytes, fence info holding a token. */
static void preparetree (cmark_node *root, cmark_syntax_extension *compatible,
                         const char *token, size_t marker, const char *plain,
                         size_t base) {
  cmark_iter *iter = cmark_iter_new(root);
  cmark_event_type event;

  while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    cmark_node *node = cmark_iter_get_node(iter);
    cmark_node_type type = cmark_node_get_type(node);

    if (event != CMARK_EVENT_ENTER) {
      continue;
    }

    if (iscompatible(node, type)) {
      cmark_node_set_syntax_extension(node, compatible);
    }

    if (type == CMARK_NODE_HTML_INLINE &&
        memchr(node->as.literal.data, '\n', (size_t)node->as.literal.len)) {
      restoreendings(node);
    }

    if (token && type == CMARK_NODE_CODE_BLOCK) {
      restorefence(node, token, marker, plain, base);
    }
  }

  cmark_iter_free(iter);
}

/* Flags the bytes of a multi-line raw HTML literal that input does not hold
 * whole. Container prefixes were removed by upstream. Match each literal
 * fragment only on its upstream source line. */
static void findhtmllines (const char *input, size_t bytes, cmark_node *node,
                           const char *literal, unsigned char *html) {
  const char *row = input;

  for (int line = 1; line < cmark_node_get_start_line(node) && *row; line++) {
    const char *end = strchr(row, '\n');
    row = end ? end + 1 : input + bytes;
  }

  for (const char *part = literal; *part && *row;) {
    const char *next = strchr(part, '\n'), *end = strchr(row, '\n');
    size_t count = next ? (size_t)(next - part) : strlen(part);

    if (!end) {
      end = input + bytes;
    }

    for (const char *at = row; count && count <= (size_t)(end - at); at++) {
      if (!memcmp(at, part, count)) {
        memset(html + (at - input), IN_RAW_HTML, count);
      }
    }

    if (!next || end == input + bytes) {
      break;
    }

    part = next + 1;
    row = end + 1;
  }
}

/* Flags in html each byte of input that raw HTML holding the plain marker
 * covers, so that transport keeps the plain marker there. */
static void findrawhtml (cmark_node *root, const char *input, size_t bytes,
                         const char *plain, unsigned char *html) {
  cmark_iter *iter = cmark_iter_new(root);
  cmark_event_type event;

  while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    cmark_node *node = cmark_iter_get_node(iter);
    cmark_node_type type = cmark_node_get_type(node);

    if (event != CMARK_EVENT_ENTER ||
        (type != CMARK_NODE_HTML_INLINE && type != CMARK_NODE_HTML_BLOCK)) {
      continue;
    }

    const char *literal = cmark_node_get_literal(node);

    if (!strstr(literal, plain)) {
      continue;
    }

    /* The upstream AST, not a tag scanner, identifies raw HTML. Charge
     * literal searches to the same finite native resource budget. */
    charge(bytes);
    size_t length = strlen(literal);
    const char *found = strstr(input, literal);

    for (const char *at = found; at; at = strstr(at + length, literal)) {
      memset(html + (at - input), IN_RAW_HTML, length);
    }

    if (!found && strchr(literal, '\n')) {
      findhtmllines(input, bytes, node, literal, html);
    }
  }

  cmark_iter_free(iter);
}

/* Parses input and renders it as HTML. While transporting bytes, plain and
 * token are its markers (see transport), and a non-NULL html asks for
 * the bytes raw HTML holds to be flagged in it. */
static char *render (const char *input, size_t bytes,
                     cmark_syntax_extension *definition,
                     cmark_syntax_extension *compatible, const char *token,
                     size_t marker, const char *plain, size_t base,
                     unsigned char *html) {
  cmark_parser *parser = cmark_parser_new_with_mem(
      CMARK_OPT_UNSAFE | CMARK_OPT_SOURCEPOS, &memory);
  cmark_parser_attach_syntax_extension(parser, definition);
  cmark_parser_attach_syntax_extension(parser,
                                       cmark_find_syntax_extension("table"));
  cmark_parser_feed(parser, input, bytes);
  cmark_node *root = cmark_parser_finish(parser);

  if (html) {
    findrawhtml(root, input, bytes, plain, html);
  }

  preparetree(root, compatible, token, marker, plain, base);
  tablehtml(root);
  char *result = cmark_render_html(
      root, CMARK_OPT_UNSAFE | CMARK_OPT_TABLE_PREFER_STYLE_ATTRIBUTES,
      cmark_parser_get_syntax_extensions(parser));
  cmark_node_free(root);
  cmark_parser_free(parser);

  return result;
}

/* Records how each source line ends, for restoreendings, and whether
 * the last one ends at all, for compatiblehtml. */
static void scanlines (nuppmarkdown *doc, const char *source, size_t bytes) {
  doc->unterminated =
      bytes && source[bytes - 1] != '\n' && source[bytes - 1] != '\r';

  /* Line numbers start at 1 and the last line follows the last break, so
   * the table has two entries more than the source has breaks. */
  doc->lines = 2;

  for (size_t at = 0; at < bytes; at++) {
    if (source[at] == '\n' || source[at] == '\r') {
      doc->lines++;

      if (source[at] == '\r' && at + 1 < bytes && source[at + 1] == '\n') {
        at++;
      }
    }
  }

  doc->lineendings = allocate(doc->lines, 1);
  size_t line = 1;

  for (size_t at = 0; at < bytes; at++) {
    if (source[at] == '\r') {
      doc->lineendings[line] = CR;

      if (at + 1 < bytes && source[at + 1] == '\n') {
        doc->lineendings[line] = CRLF;
        at++;
      }

      line++;
    }
    else if (source[at] == '\n') {
      line++;
    }
  }
}

/* Lossless byte transport, not Markdown preprocessing. cmark consumes NUL and
 * an initial BOM before public hooks run, so they travel through it as
 * markers made of RUN_BYTE and MIDDLE_BYTE, n being longer than any run of
 * RUN_BYTE in the source or in its first rendering:
 *
 *   plain  n RUN_BYTE, MIDDLE_BYTE, MIDDLE_BYTE, n RUN_BYTE
 *   token  n RUN_BYTE, MIDDLE_BYTE, ' ', MIDDLE_BYTE, n RUN_BYTE
 *
 * A NUL becomes the token, whose space keeps it from becoming a bare link
 * destination, except in raw HTML, which keeps the plain marker; a rendering
 * with every NUL as plain finds where raw HTML is. A BOM stays as text behind
 * a plain marker, which shields it from cmark and is then dropped. In a link
 * destination upstream percent-encodes the token as its url, n ESCAPED_ONE,
 * ESCAPED_MIDDLE, n ESCAPED_ONE, which becomes ESCAPED_NUL, and n doubles
 * until that url is absent from the source and the first rendering too. The
 * markers are restored by explicit size, since the HTML then holds NUL. */
typedef struct {

  /* n, the length of each run of RUN_BYTE. */
  size_t ones;

  /* The plain marker, the token and the token's url. */
  char *plain, *token, *url;

  /* Their lengths. */
  size_t base, marker, urlsize;
} markers;

/* The least n longer than every run of RUN_BYTE in the source and in the
 * NUL-terminated first rendering. */
static size_t runlength (const char *source, size_t bytes, const char *html) {
  size_t ones = 1, run = 0;

  for (size_t i = 0; i < bytes; i++) {
    run = source[i] == RUN_BYTE ? run + 1 : 0;

    if (run >= ones) {
      ones = run + 1;
    }
  }

  run = 0;

  for (const char *p = html; *p; p++) {
    run = *p == RUN_BYTE ? run + 1 : 0;

    if (run >= ones) {
      ones = run + 1;
    }
  }

  return ones;
}

/* Spells the token's url for m->ones, doubling it until the url occurs in
 * neither the source nor the first rendering. */
static void chooseurl (markers *m, const char *source, size_t bytes,
                       const char *html) {
  for (;;) {
    size_t ones = m->ones;
    m->urlsize = ones * 2 * ESCAPE_BYTES + ESCAPED_MIDDLE_BYTES;
    m->url = allocate(1, m->urlsize + 1);

    for (size_t i = 0; i < ones; i++) {
      memcpy(m->url + i * ESCAPE_BYTES, ESCAPED_ONE, ESCAPE_BYTES);
    }

    memcpy(m->url + ones * ESCAPE_BYTES, ESCAPED_MIDDLE, ESCAPED_MIDDLE_BYTES);

    for (size_t i = 0; i < ones; i++) {
      memcpy(m->url + ones * ESCAPE_BYTES + ESCAPED_MIDDLE_BYTES +
                 i * ESCAPE_BYTES,
             ESCAPED_ONE, ESCAPE_BYTES);
    }

    if (!contains(source, bytes, m->url, m->urlsize) && !strstr(html, m->url)) {
      return;
    }

    release(m->url);
    m->ones *= 2;
  }
}

/* Builds the plain marker and the token for m->ones. */
static void makemarkers (markers *m) {
  size_t ones = m->ones;
  m->base = ones * 2 + 2;
  m->marker = m->base + 1;
  m->plain = allocate(1, m->base + 1);
  m->token = allocate(1, m->marker + 1);
  memset(m->plain, RUN_BYTE, m->base);
  m->plain[ones] = m->plain[ones + 1] = MIDDLE_BYTE;
  memset(m->token, RUN_BYTE, m->marker);
  m->token[ones] = m->token[ones + 2] = MIDDLE_BYTE;
  m->token[ones + 1] = ' ';
}

/* The source with every NUL as the plain marker, its line breaks as LF, and
 * a plain marker in front of a BOM. Its length is left in size. */
static char *substitute (const markers *m, const char *source, size_t bytes,
                         size_t zeros, int bom, size_t *size) {
  char *candidate =
      allocate(1, bytes + zeros * (m->base - 1) + (bom ? m->base : 0) + 1);
  size_t length = 0;

  if (bom) {
    memcpy(candidate, m->plain, m->base);
    length += m->base;
  }

  for (size_t at = 0; at < bytes; at++) {
    if (source[at] == 0) {
      memcpy(candidate + length, m->plain, m->base);
      length += m->base;
    }
    else if (source[at] == '\r') {
      candidate[length++] = '\n';

      if (at + 1 < bytes && source[at + 1] == '\n') {
        at++;
      }
    }
    else {
      candidate[length++] = source[at];
    }
  }

  *size = length;

  return candidate;
}

/* The candidate again, with the token in place of each plain marker outside
 * the raw HTML that html flags, the BOM's shield aside. Its length is left in
 * encodedsize. */
static char *encode (const markers *m, const char *candidate, size_t size,
                     const unsigned char *html, size_t bytes, size_t zeros,
                     int bom, size_t *encodedsize) {
  char *encoded =
      allocate(1, bytes + zeros * (m->marker - 1) + (bom ? m->base : 0) + 1);
  size_t length = 0;

  for (size_t at = 0; at < size;) {
    if (m->base <= size - at && !memcmp(candidate + at, m->plain, m->base)) {
      int keepplain = html[at] || (bom && at == 0);
      size_t width = keepplain ? m->base : m->marker;
      memcpy(encoded + length, keepplain ? m->plain : m->token, width);
      length += width;
      at += m->base;
    }
    else {
      encoded[length++] = candidate[at++];
    }
  }

  *encodedsize = length;

  return encoded;
}

/* Turns the markers in the rendered HTML back into the bytes they carried,
 * in place, and records its length. */
static void restore (nuppmarkdown *doc, const markers *m, int bom) {
  size_t from = 0, to = 0, length = strlen(doc->text);

  while (from < length) {
    if (m->marker <= length - from &&
        !memcmp(doc->text + from, m->token, m->marker)) {
      doc->text[to++] = 0;
      from += m->marker;
    }
    else if (m->base <= length - from &&
             !memcmp(doc->text + from, m->plain, m->base)) {

      /* The first plain marker is the BOM's shield. */
      if (bom) {
        bom = 0;
      }
      else {
        doc->text[to++] = 0;
      }

      from += m->base;
    }
    else if (m->urlsize <= length - from &&
             !memcmp(doc->text + from, m->url, m->urlsize)) {
      memcpy(doc->text + to, ESCAPED_NUL, ESCAPE_BYTES);
      to += ESCAPE_BYTES;
      from += m->urlsize;
    }
    else {
      doc->text[to++] = doc->text[from++];
    }
  }

  doc->text[to] = 0;
  doc->size = to;
}

/* Renders the source again with its NUL bytes and BOM transported, replacing
 * the first rendering, doc->text. */
static void transport (nuppmarkdown *doc, const char *source, size_t bytes,
                       int bom, cmark_syntax_extension *definition,
                       cmark_syntax_extension *compatible) {
  markers m;
  m.ones = runlength(source, bytes, doc->text);
  chooseurl(&m, source, bytes, doc->text);
  makemarkers(&m);
  size_t zeros = 0;

  for (size_t at = 0; at < bytes; at++) {
    if (source[at] == 0) {
      zeros++;
    }
  }

  size_t size, encodedsize;
  char *candidate = substitute(&m, source, bytes, zeros, bom, &size);
  unsigned char *html = allocate(size + 1, 1);
  char *probe = render(candidate, size, definition, compatible, NULL, 0,
                       m.plain, m.base, html);
  release(probe);
  char *encoded =
      encode(&m, candidate, size, html, bytes, zeros, bom, &encodedsize);
  release(candidate);
  release(html);
  release(doc->text);
  doc->text = render(encoded, encodedsize, definition, compatible, m.token,
                     m.marker, m.plain, m.base, NULL);
  release(encoded);
  restore(doc, &m, bom);
  release(m.token);
  release(m.plain);
  release(m.url);
}

/* Frees every allocation the document holds, its HTML among them. */
static void clear (nuppmarkdown *doc) {
  while (doc->allocations) {
    allocation *next = doc->allocations->h.next;
    free(doc->allocations);
    doc->allocations = next;
  }

  doc->text = NULL;
  doc->size = 0;
}

const char *nuppmarkdownrevision (void) {
  return REVISION;
}

nuppmarkdown *nuppmarkdownnew (void) {
  return calloc(1, sizeof(nuppmarkdown));
}

int nuppmarkdownrender (nuppmarkdown *doc, const char *input, size_t bytes,
                        size_t budget) {
  if (!doc || doc->used || (!input && bytes)) {
    return MISUSE;
  }

  doc->used = 1;

  if (bytes > MAX_INPUT_BYTES || budget > MAX_BUDGET_BYTES) {
    return TOO_LARGE;
  }

  LOCK();
  active = doc;
  doc->remaining = budget;
  cmark_gfm_core_extensions_ensure_registered();
  cmark_syntax_extension *definition = nuppdefinitionlistnew(&memory);
  cmark_syntax_extension *compatible =
      cmark_syntax_extension_new("nupp_compatible_html");
  cmark_syntax_extension_set_html_render_func(compatible, compatiblehtml);
  int status = NO_RESOURCES;

  if (!setjmp(doc->failure)) {
    const char *source = input ? input : "";
    scanlines(doc, source, bytes);
    doc->text =
        render(source, bytes, definition, compatible, NULL, 0, NULL, 0, NULL);
    int bom =
        bytes >= UTF8_BOM_BYTES && !memcmp(source, UTF8_BOM, UTF8_BOM_BYTES);

    if (memchr(source, 0, bytes) || bom) {
      transport(doc, source, bytes, bom, definition, compatible);
    }
    else {
      doc->size = strlen(doc->text);
    }

    status = RENDERED;
  }
  else {
    clear(doc);
  }

  cmark_syntax_extension_free(cmark_get_default_mem_allocator(), compatible);
  cmark_syntax_extension_free(cmark_get_default_mem_allocator(), definition);
  active = NULL;
  UNLOCK();

  return status;
}

const char *nuppmarkdowntext (const nuppmarkdown *doc) {
  return doc ? doc->text : NULL;
}

const char *nuppmarkdowntextat (const nuppmarkdown *doc, size_t at) {
  return doc && at <= doc->size && doc->text ? doc->text + at : NULL;
}

size_t nuppmarkdownsize (const nuppmarkdown *doc) {
  return doc ? doc->size : 0;
}

void nuppmarkdownfree (nuppmarkdown *doc) {
  if (doc) {
    clear(doc);
    free(doc);
  }
}
