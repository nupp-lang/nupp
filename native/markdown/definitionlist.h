/**
 * @file
 * @brief Constructs the cmark-gfm extension for colon definition lists.
 *
 * Colon definition lists for cmark-gfm; the syntax is described in
 * definitionlist.c.
 */

#ifndef NUPP_DEFINITIONLIST_H
#define NUPP_DEFINITIONLIST_H

#include <cmark-gfm.h>
#include <cmark-gfm-extension_api.h>

/** The caller retains the extension and allocator through AST destruction. */
cmark_syntax_extension *nuppdefinitionlistnew (cmark_mem *mem);

#endif
