/* A cmark-gfm block extension for definition lists, in the colon syntax of
 * commonmark-hs's definition_lists extension (and Pandoc's). A term is a
 * paragraph line of its own; each of its definitions starts with `:` and
 * the definition's content:
 *
 *   apple
 *   :   red fruit
 *
 *   orange
 *   :   orange fruit
 *   :   the color, too
 *
 * renders as
 *
 *   <dl>
 *   <dt>apple</dt>
 *   <dd>red fruit</dd>
 *   <dt>orange</dt>
 *   <dd>orange fruit</dd>
 *   <dd>the color, too</dd>
 *   </dl>
 *
 * Lines after the first continue the definition when indented to its content
 * column (the column after `:` and its spaces), or as lazy paragraph lines.
 * The list is tight, its definitions' paragraphs unwrapped, unless a blank
 * line separates a term from its definition or a definition's blocks from one
 * another; then every definition keeps its <p>. `~` is not a marker, since it
 * already means strikethrough. A paragraph that is only link reference
 * definitions is not a term.
 *
 * Only the block structure is decided here: the terms' inlines and the
 * definitions' blocks are parsed by upstream cmark as usual. The cases it is
 * held to are tests/fixtures/markdown/definition-lists.txt. */

#include "definitionlist.h"

#include <stdlib.h>
#include <string.h>

/* What a node this extension owns is: the list, one of its terms, or one of
 * its definitions. Zero is left unused, so a node's role is never zero. */
enum role { LIST = 1, TERM, DEFINITION };

/* The last argument of cmark_parser_advance_offset: whether its count is in
 * bytes or in columns, where a tab spans to the next tab stop. */
enum { BYTES = 0, COLUMNS = 1 };

/* As in a list item, more spaces than this after the marker start indented
 * code, so the definition's content begins one space after the marker. */
enum { CODE_INDENT = 4 };

/* The state the extension keeps on each node it owns, as cmark user data. */
typedef struct {
  enum role role;
  /* A definition's content column: a line indented this far continues it. */
  int padding;
  /* A blank line came between the definition and what came before it, or
   * between two of its blocks. */
  int loose;
  /* The number of the last blank line the definition held, or zero. */
  int blankline;
  /* The definition's first line was only its marker. */
  int startsblank;
} block;

static block *state (cmark_node *node) {
  return (block *)cmark_node_get_user_data(node);
}

static void freestate (cmark_mem *mem, void *value) {
  mem->free(value);
}

/* Claims node for the extension in the given role, with fresh state that the
 * node frees with itself. */
static void mark (cmark_syntax_extension *ext, cmark_node *node,
                  enum role role) {
  cmark_mem *mem = cmark_syntax_extension_get_private(ext);
  block *value = mem->calloc(1, sizeof(*value));
  value->role = role;
  cmark_node_set_user_data(node, value);
  cmark_node_set_user_data_free_func(node, freestate);
  cmark_node_set_syntax_extension(node, ext);
}

/* Whether node exists, belongs to the extension and plays the given role. */
static int is (cmark_syntax_extension *ext, cmark_node *node, enum role role) {
  return node && cmark_node_get_syntax_extension(node) == ext &&
         state(node)->role == role;
}

/* A term holds only inlines, as the paragraph it was; a list or definition
 * holds any block. */
static int cancontain (cmark_syntax_extension *ext, cmark_node *node,
                       cmark_node_type child) {
  return is(ext, node, TERM)
             ? (child & CMARK_NODE_TYPE_MASK) == CMARK_NODE_TYPE_INLINE
             : child != CMARK_NODE_DOCUMENT;
}

/* Only a term's text is parsed as inlines; a definition's is in its blocks. */
static int containsinlines (cmark_syntax_extension *ext, cmark_node *node) {
  return is(ext, node, TERM);
}

/* The last source line a block holds. A paragraph's recorded end line can lag
 * its content until it is finalized, so the content's lines count too. */
static int endline (cmark_node *node) {
  int end = cmark_node_get_start_line(node) - 1;
  const char *content = cmark_node_get_string_content(node);

  for (const char *p = content; *p; p++) {
    if (*p == '\n') {
      end++;
    }
  }

  return end > cmark_node_get_end_line(node) ? end
                                             : cmark_node_get_end_line(node);
}

/* Whether a paragraph holds a term, rather than only link reference
 * definitions. */
static int hasterm (cmark_syntax_extension *ext, cmark_node *term) {
  const char *text = cmark_node_get_string_content(term);

  if (*text != '[') {
    return 1;
  }

  /* Let upstream resolve leading link definitions; a definition alone is
   * not a term. The outer parser commits its own reference map on close. */
  cmark_mem *mem = cmark_syntax_extension_get_private(ext);
  cmark_parser *probe = cmark_parser_new_with_mem(CMARK_OPT_UNSAFE, mem);
  cmark_parser_feed(probe, text, strlen(text));
  cmark_node *root = cmark_parser_finish(probe);
  int found =
      cmark_node_get_type(cmark_node_last_child(root)) == CMARK_NODE_PARAGRAPH;
  cmark_node_free(root);
  cmark_parser_free(probe);

  return found;
}

/* cmark's question for each open block on each new line: does the line
 * continue it? A list always does, leaving the answer to its children, and a
 * term, one line long, never does. A definition takes blank lines, unless it is
 * still empty and opened with nothing after its marker, and lines indented to
 * its content column, which it consumes. Lazy continuation lines are
 * upstream's. */
static int matchblock (cmark_syntax_extension *ext, cmark_parser *parser,
                       unsigned char *input, int len, cmark_node *node) {
  (void)len;

  if (is(ext, node, LIST)) {
    return 1;
  }

  if (is(ext, node, TERM)) {
    return 0;
  }

  if (cmark_parser_is_blank(parser)) {
    cmark_node *last = cmark_node_last_child(node);

    if (!last && state(node)->startsblank) {
      return 0;
    }

    /* A blank line between two of the definition's blocks loosens it. */
    if (last && state(node)->blankline &&
        cmark_node_get_start_line(last) > state(node)->blankline) {
      state(node)->loose = 1;
    }

    state(node)->blankline = cmark_parser_get_line_number(parser);

    return 1;
  }

  if (cmark_parser_get_indent(parser) < state(node)->padding) {
    return 0;
  }

  cmark_parser_advance_offset(parser, (const char *)input, state(node)->padding,
                              COLUMNS);

  return 1;
}

/* Records where the definition's content starts, and moves the parser past
 * its marker and the spaces before that content. start is the marker's
 * byte offset in input and indent its column. */
static void begincontent (cmark_parser *parser, cmark_node *definition,
                          unsigned char *input, int len, int start,
                          int indent) {
  int spaces = 0;

  while (start + 1 + spaces < len && input[start + 1 + spaces] == ' ') {
    spaces++;
  }

  int after = spaces > CODE_INDENT ? 1 : spaces;
  state(definition)->padding = indent + 1 + after;
  int content = start + 1 + spaces;

  while (content < len && (input[content] == ' ' || input[content] == '\t')) {
    content++;
  }

  state(definition)->startsblank =
      content == len || input[content] == '\n' || input[content] == '\r';
  cmark_parser_advance_offset(parser, (const char *)input,
                              start + 1 - cmark_parser_get_offset(parser),
                              BYTES);
  cmark_parser_advance_offset(parser, (const char *)input, after, COLUMNS);
}

/* cmark's question for a line no open block took: does it open one here? A
 * line whose first non-space is `:` opens a definition when it follows a
 * term's paragraph or another definition of the same list. */
static cmark_node *openblock (cmark_syntax_extension *ext, int indented,
                              cmark_parser *parser, cmark_node *parent,
                              unsigned char *input, int len) {
  int start = cmark_parser_get_first_nonspace(parser);
  int indent = cmark_parser_get_indent(parser);

  if (indented || start >= len || input[start] != ':') {
    return NULL;
  }

  /* The paragraph before the marker, or the definition before it when the
   * line continues a list. */
  cmark_node *term = cmark_node_get_type(parent) == CMARK_NODE_PARAGRAPH
                         ? parent
                         : cmark_node_last_child(parent);
  /* The list the new definition joins, or, when its term joins a list
   * already open, the definition itself. */
  cmark_node *list;
  /* A blank line separates the definition from what came before it. */
  int loose;

  if (is(ext, parent, LIST) && is(ext, term, DEFINITION)) {
    list = parent;
    cmark_node *last = term;

    while (cmark_node_last_child(last)) {
      last = cmark_node_last_child(last);
    }

    loose = cmark_parser_get_line_number(parser) > endline(last) + 1;
  }
  else {
    if (!term || cmark_node_get_type(term) != CMARK_NODE_PARAGRAPH ||
        cmark_node_get_syntax_extension(term)) {
      return NULL;
    }

    if (!hasterm(ext, term)) {
      return NULL;
    }

    cmark_node *owner = cmark_node_parent(term);
    loose = cmark_parser_get_line_number(parser) > endline(term) + 1;

    /* Adding a child to the term while it is the open paragraph finalizes
     * it, which must come before it is claimed as a term. */
    if (is(ext, owner, LIST)) {
      list = cmark_parser_add_child(parser, parent == term ? term : owner,
                                    CMARK_NODE_CUSTOM_BLOCK, start + 1);
      mark(ext, term, TERM);
      mark(ext, list, DEFINITION);
    }
    else {
      list = cmark_parser_add_child(parser, parent == term ? term : owner,
                                    CMARK_NODE_CUSTOM_BLOCK, start + 1);
      mark(ext, list, LIST);
      mark(ext, term, TERM);
      cmark_node_append_child(list, term);
    }
  }

  cmark_node *definition;

  if (is(ext, list, DEFINITION)) {
    definition = list;
  }
  else {
    definition = cmark_parser_add_child(parser, list, CMARK_NODE_CUSTOM_BLOCK,
                                        start + 1);
    mark(ext, definition, DEFINITION);
  }

  state(definition)->loose = loose;
  begincontent(parser, definition, input, len, start, indent);

  return definition;
}

/* Has node render as the given HTML around its children. */
static void renderas (cmark_node *node, const char *enter, const char *leave) {
  cmark_node_set_type(node, CMARK_NODE_CUSTOM_INLINE);
  cmark_node_set_on_enter(node, enter);
  cmark_node_set_on_exit(node, leave);
}

/* Whether any of the list's definitions is loose: separated by a blank line
 * from what came before it, or holding blocks a blank line apart. */
static int isloose (cmark_syntax_extension *ext, cmark_node *list) {
  int loose = 0;

  for (cmark_node *dd = cmark_node_first_child(list); dd;
       dd = cmark_node_next(dd)) {
    if (!is(ext, dd, DEFINITION)) {
      continue;
    }

    if (state(dd)->loose) {
      loose = 1;
    }

    cmark_node *last = cmark_node_last_child(dd);

    if (last && state(dd)->blankline &&
        cmark_node_get_start_line(last) > state(dd)->blankline) {
      loose = 1;
    }

    for (cmark_node *p = cmark_node_first_child(dd); p;
         p = cmark_node_next(p)) {
      cmark_node *next = cmark_node_next(p);

      if (next &&
          cmark_node_get_start_line(next) > cmark_node_get_end_line(p) + 1) {
        loose = 1;
      }
    }
  }

  return loose;
}

/* Gives a finished list its HTML: <dl> around it, <dt> and <dd> around its
 * terms and definitions, and, in a tight list, definitions' paragraphs
 * without their <p>. */
static void renderlist (cmark_syntax_extension *ext, cmark_node *node) {
  int loose = isloose(ext, node);
  cmark_node_set_on_enter(node, "<dl>\n");
  cmark_node_set_on_exit(node, "</dl>\n");

  for (cmark_node *child = cmark_node_first_child(node); child;
       child = cmark_node_next(child)) {
    if (is(ext, child, TERM)) {
      renderas(child, "<dt>", "</dt>\n");
    }
    else {
      renderas(child, "<dd>", "</dd>\n");

      if (!loose) {
        for (cmark_node *p = cmark_node_first_child(child); p;
             p = cmark_node_next(p)) {
          if (cmark_node_get_type(p) == CMARK_NODE_PARAGRAPH) {
            renderas(p, "", "");
          }
        }
      }
    }
  }
}

/* A list stays open past every line, so it also collects the ordinary blocks
 * that follow it. Moves each of those out to stand after the list, in order,
 * gathers the terms and definitions after one into a new list, and renders
 * every list. */
static void splitlist (cmark_syntax_extension *ext, cmark_node *node) {
  cmark_node *tail = node;
  cmark_node *segment = node;

  for (cmark_node *child = cmark_node_first_child(node), *next; child;
       child = next) {
    next = cmark_node_next(child);

    if (!is(ext, child, TERM) && !is(ext, child, DEFINITION)) {
      cmark_node_insert_after(tail, child);
      tail = child;
      segment = NULL;
    }
    else if (segment != node) {
      if (!segment) {
        cmark_mem *mem = cmark_syntax_extension_get_private(ext);
        segment = cmark_node_new_with_mem(CMARK_NODE_CUSTOM_BLOCK, mem);
        mark(ext, segment, LIST);
        cmark_node_insert_after(tail, segment);
        tail = segment;
      }

      cmark_node_append_child(segment, child);
    }
  }

  for (cmark_node *part = tail == node ? NULL : cmark_node_next(node); part;
       part = cmark_node_next(part)) {
    if (is(ext, part, LIST)) {
      renderlist(ext, part);
    }

    if (part == tail) {
      break;
    }
  }

  renderlist(ext, node);
}

/* Runs once the document is parsed: splits and renders every list, each
 * after its contents, so a list nested in a definition is done first. */
static cmark_node *postprocess (cmark_syntax_extension *ext,
                                cmark_parser *parser, cmark_node *root) {
  (void)parser;
  cmark_iter *iter = cmark_iter_new(root);
  cmark_event_type event;

  while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    cmark_node *node = cmark_iter_get_node(iter);

    if (event == CMARK_EVENT_EXIT && is(ext, node, LIST)) {
      splitlist(ext, node);
    }
  }

  cmark_iter_free(iter);

  return root;
}

cmark_syntax_extension *nuppdefinitionlistnew (cmark_mem *mem) {
  cmark_syntax_extension *ext =
      cmark_syntax_extension_new("nupp_definition_list");
  cmark_syntax_extension_set_private(ext, mem, NULL);
  cmark_syntax_extension_set_can_contain_func(ext, cancontain);
  cmark_syntax_extension_set_contains_inlines_func(ext, containsinlines);
  cmark_syntax_extension_set_match_block_func(ext, matchblock);
  cmark_syntax_extension_set_open_block_func(ext, openblock);
  cmark_syntax_extension_set_postprocess_func(ext, postprocess);

  return ext;
}
