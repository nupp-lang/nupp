#ifndef NUPP_MARKDOWN_H
#define NUPP_MARKDOWN_H
#include <stddef.h>
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
NUPP_MD_API const char *nupp_markdown_revision(void);
NUPP_MD_API nupp_markdown *nupp_markdown_new(void);
/* Input is explicit-length, already lossily decoded UTF-8; NUL is allowed.
 * Budget caps cumulative allocations, including parser, tree and HTML.
 * Zero means success; negative values mean resource/input/ownership failure.
 * No input pointer is retained. A document may be rendered only once. */
NUPP_MD_API int nupp_markdown_render(nupp_markdown *, const char *, size_t, size_t);
NUPP_MD_API const char *nupp_markdown_text(const nupp_markdown *);
/* A bounded suffix, for C-string-only foreign callers preserving embedded NUL.
 * Copy each segment before freeing the document; size remains authoritative. */
NUPP_MD_API const char *nupp_markdown_text_at(const nupp_markdown *, size_t);
NUPP_MD_API size_t nupp_markdown_size(const nupp_markdown *);
NUPP_MD_API void nupp_markdown_free(nupp_markdown *);
#endif
