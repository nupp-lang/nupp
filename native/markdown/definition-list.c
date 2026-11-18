/* Colon definitions only. Block and inline parsing remain in upstream cmark. */
#include "definition-list.h"
#include <stdlib.h>
#include <string.h>

enum role { LIST = 1, TERM, DEFINITION };

typedef struct {
  enum role role;
  int padding;
  int loose;
  int blank_line;
  int starts_blank;
} block;

static block *data (cmark_node *node) {
  return (block *)cmark_node_get_user_data(node);
}

static void release (cmark_mem *mem, void *value) {
  mem->free(value);
}

static void mark (cmark_syntax_extension *ext, cmark_node *node,
                  enum role role) {
  cmark_mem *mem = cmark_syntax_extension_get_private(ext);
  block *value = mem->calloc(1, sizeof(*value));
  value->role = role;
  cmark_node_set_user_data(node, value);
  cmark_node_set_user_data_free_func(node, release);
  cmark_node_set_syntax_extension(node, ext);
}

static int is (cmark_syntax_extension *ext, cmark_node *node, enum role role) {
  return node && cmark_node_get_syntax_extension(node) == ext &&
         data(node)->role == role;
}

static int contain (cmark_syntax_extension *ext, cmark_node *node,
                    cmark_node_type child) {
  return is(ext, node, TERM)
             ? (child & CMARK_NODE_TYPE_MASK) == CMARK_NODE_TYPE_INLINE
             : child != CMARK_NODE_DOCUMENT;
}

static int inlines (cmark_syntax_extension *ext, cmark_node *node) {
  return is(ext, node, TERM);
}

static int end_line (cmark_node *node) {
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

static int has_term (cmark_syntax_extension *ext, cmark_node *term) {
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

static int match (cmark_syntax_extension *ext, cmark_parser *parser,
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

    if (!last && data(node)->starts_blank) {
      return 0;
    }

    if (last && data(node)->blank_line &&
        cmark_node_get_start_line(last) > data(node)->blank_line) {
      data(node)->loose = 1;
    }

    data(node)->blank_line = cmark_parser_get_line_number(parser);

    return 1;
  }

  if (cmark_parser_get_indent(parser) < data(node)->padding) {
    return 0;
  }

  cmark_parser_advance_offset(parser, (const char *)input, data(node)->padding,
                              1);

  return 1;
}

static cmark_node *open_block (cmark_syntax_extension *ext, int indented,
                               cmark_parser *parser, cmark_node *parent,
                               unsigned char *input, int len) {
  int start = cmark_parser_get_first_nonspace(parser);
  int indent = cmark_parser_get_indent(parser);

  if (indented || start >= len || input[start] != ':') {
    return NULL;
  }

  cmark_node *term = cmark_node_get_type(parent) == CMARK_NODE_PARAGRAPH
                         ? parent
                         : cmark_node_last_child(parent);
  cmark_node *list = NULL;
  int loose;

  if (is(ext, parent, LIST) && is(ext, term, DEFINITION)) {
    list = parent;
    cmark_node *last = term;

    while (cmark_node_last_child(last)) {
      last = cmark_node_last_child(last);
    }

    loose = cmark_parser_get_line_number(parser) > end_line(last) + 1;
  }
  else {
    if (!term || cmark_node_get_type(term) != CMARK_NODE_PARAGRAPH ||
        cmark_node_get_syntax_extension(term)) {
      return NULL;
    }

    if (!has_term(ext, term)) {
      return NULL;
    }

    cmark_node *owner = cmark_node_parent(term);
    loose = cmark_parser_get_line_number(parser) > end_line(term) + 1;

    if (is(ext, owner, LIST)) {
      list = owner;
      /* Finalize the open paragraph before reclassifying it. */
      cmark_node *next =
          cmark_parser_add_child(parser, parent == term ? term : list,
                                 CMARK_NODE_CUSTOM_BLOCK, start + 1);
      mark(ext, term, TERM);
      mark(ext, next, DEFINITION);
      list = next;
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

  data(definition)->loose = loose;
  int spaces = 0;

  while (start + 1 + spaces < len && input[start + 1 + spaces] == ' ') {
    spaces++;
  }

  int after = spaces > 4 ? 1 : spaces;
  data(definition)->padding = indent + 1 + after;
  int content = start + 1 + spaces;

  while (content < len && (input[content] == ' ' || input[content] == '\t')) {
    content++;
  }

  data(definition)->starts_blank =
      content == len || input[content] == '\n' || input[content] == '\r';
  cmark_parser_advance_offset(parser, (const char *)input,
                              start + 1 - cmark_parser_get_offset(parser), 0);
  cmark_parser_advance_offset(parser, (const char *)input, after, 1);

  return definition;
}

static void tags (cmark_node *node, const char *enter, const char *leave) {
  cmark_node_set_type(node, CMARK_NODE_CUSTOM_INLINE);
  cmark_node_set_on_enter(node, enter);
  cmark_node_set_on_exit(node, leave);
}

static void render_list (cmark_syntax_extension *ext, cmark_node *node) {
  int loose = 0;

  for (cmark_node *dd = cmark_node_first_child(node); dd;
       dd = cmark_node_next(dd)) {
    if (!is(ext, dd, DEFINITION)) {
      continue;
    }

    if (data(dd)->loose) {
      loose = 1;
    }

    cmark_node *last = cmark_node_last_child(dd);

    if (last && data(dd)->blank_line &&
        cmark_node_get_start_line(last) > data(dd)->blank_line) {
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

  cmark_node_set_on_enter(node, "<dl>\n");
  cmark_node_set_on_exit(node, "</dl>\n");

  for (cmark_node *child = cmark_node_first_child(node); child;
       child = cmark_node_next(child)) {
    if (is(ext, child, TERM)) {
      tags(child, "<dt>", "</dt>\n");
    }
    else {
      tags(child, "<dd>", "</dd>\n");

      if (!loose) {
        for (cmark_node *p = cmark_node_first_child(child); p;
             p = cmark_node_next(p)) {
          if (cmark_node_get_type(p) == CMARK_NODE_PARAGRAPH) {
            tags(p, "", "");
          }
        }
      }
    }
  }
}

static void process (cmark_syntax_extension *ext, cmark_node *node) {
  /* Split around ordinary blocks, preserving their original position. */
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
      render_list(ext, part);
    }

    if (part == tail) {
      break;
    }
  }

  render_list(ext, node);
}

static cmark_node *postprocess (cmark_syntax_extension *ext,
                                cmark_parser *parser, cmark_node *root) {
  (void)parser;
  cmark_iter *iter = cmark_iter_new(root);
  cmark_event_type event;

  while ((event = cmark_iter_next(iter)) != CMARK_EVENT_DONE) {
    cmark_node *node = cmark_iter_get_node(iter);

    if (event == CMARK_EVENT_EXIT && is(ext, node, LIST)) {
      process(ext, node);
    }
  }

  cmark_iter_free(iter);

  return root;
}

cmark_syntax_extension *nupp_definition_list_new (cmark_mem *mem) {
  cmark_syntax_extension *ext =
      cmark_syntax_extension_new("nupp_definition_list");
  cmark_syntax_extension_set_private(ext, mem, NULL);
  cmark_syntax_extension_set_can_contain_func(ext, contain);
  cmark_syntax_extension_set_contains_inlines_func(ext, inlines);
  cmark_syntax_extension_set_match_block_func(ext, match);
  cmark_syntax_extension_set_open_block_func(ext, open_block);
  cmark_syntax_extension_set_postprocess_func(ext, postprocess);

  return ext;
}
