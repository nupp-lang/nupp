#ifndef NUPP_DEFINITION_LIST_H
#define NUPP_DEFINITION_LIST_H
#include <cmark-gfm.h>
#include <cmark-gfm-extension_api.h>
/* The caller retains the extension and allocator through AST destruction. */
cmark_syntax_extension *nupp_definition_list_new (cmark_mem *mem);
#endif
