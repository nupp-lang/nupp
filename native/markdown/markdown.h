/* The C interface of Nupp's Markdown renderer, a private build of the pinned
 * upstream cmark-gfm with tables and the colon definition lists of
 * definition-list.c. The documentation host and the core load it as the
 * library "nupp_markdown" (coremarkdown.nupp, markdownlibrary.nupp), and
 * docs/native-markdown.md describes the dialect and the byte policy.
 *
 * A document is used once: create it, render one input into it, read the
 * HTML back by size, and free it. */

#ifndef NUPP_MARKDOWN_H
#define NUPP_MARKDOWN_H

#include <stddef.h>

/* NUPP_MD_API marks the exported functions: dllexport while building the
 * Windows DLL (NUPP_MD_EXPORTS), nothing while consuming it, and default
 * visibility elsewhere, since the library builds with hidden visibility. */
#ifdef _WIN32

#ifdef NUPP_MD_EXPORTS
#define NUPP_MD_API __declspec(dllexport)
#else
#define NUPP_MD_API
#endif

#else

#define NUPP_MD_API __attribute__((visibility("default")))

#endif

typedef struct nupp_markdown nupp_markdown;

/* The upstream commit and definition-list ABI this library was built from,
 * which a caller compares with the one it was written against. */
NUPP_MD_API const char *nupp_markdown_revision (void);

/* A new, empty document, or NULL when out of memory. */
NUPP_MD_API nupp_markdown *nupp_markdown_new (void);

/* Input is explicit-length, already lossily decoded UTF-8; NUL is allowed.
 * Budget caps cumulative allocations, including parser, tree and HTML.
 * Zero means success; negative values mean resource/input/ownership failure.
 * No input pointer is retained. A document may be rendered only once. */
NUPP_MD_API int nupp_markdown_render (nupp_markdown *, const char *, size_t,
                                      size_t);

/* The rendered HTML, or NULL before a successful render. It may hold NUL
 * bytes, so read nupp_markdown_size bytes of it. */
NUPP_MD_API const char *nupp_markdown_text (const nupp_markdown *);

/* A bounded suffix, for C-string-only foreign callers preserving embedded NUL.
 * Copy each segment before freeing the document; size remains authoritative. */
NUPP_MD_API const char *nupp_markdown_text_at (const nupp_markdown *, size_t);

/* The byte length of the rendered HTML, or zero. */
NUPP_MD_API size_t nupp_markdown_size (const nupp_markdown *);

/* Frees the document and its HTML; NULL is allowed. */
NUPP_MD_API void nupp_markdown_free (nupp_markdown *);

#endif
