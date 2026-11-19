/* The serialization benchmark's native control: simdjson behind a small C
 * interface, built by bench/serde-spike/nupp.lua from simdjson_control.cpp,
 * so that bench/serde-spike can time the serde.json variants beside a
 * native parser reading the same documents.
 *
 * The int-returning calls answer 0 for success, -1 for a bad argument or an
 * allocation failure in this bridge, and otherwise simdjson's error code;
 * nuppSimdjsonError names any of them. */

#ifndef NUPP_SIMDJSON_CONTROL_H
#define NUPP_SIMDJSON_CONTROL_H

#include <stddef.h>

/* Marks the Lua module opener simdjson_control.cpp exports. */
#if defined(_WIN32)

#define NUPP_SIMDJSON_EXPORT __declspec(dllexport)

#else

#define NUPP_SIMDJSON_EXPORT __attribute__((visibility("default")))

#endif

#ifdef __cplusplus
extern "C" {
#endif

/* A parser and the padded copy of the document it last prepared. */
typedef struct nuppSimdjsonParser nuppSimdjsonParser;

/* A new parser, or NULL when it cannot be allocated. */
nuppSimdjsonParser *nuppSimdjsonNew (void);
void nuppSimdjsonFree (nuppSimdjsonParser *parser);

/* Copies `length` bytes of `source` into the parser's buffer with the
 * padding simdjson reads past the end, so the timed calls below parse
 * without copying. */
int nuppSimdjsonPrepare (nuppSimdjsonParser *parser, const char *source,
                         size_t length);

/* Starts an On-Demand iteration over the prepared document, which runs
 * simdjson's structural indexing alone. */
int nuppSimdjsonStage1 (nuppSimdjsonParser *parser);

/* Parses the prepared document into a DOM. */
int nuppSimdjsonDom (nuppSimdjsonParser *parser);

const char *nuppSimdjsonError (int code);
const char *nuppSimdjsonVersion (void);

/* The name of the simdjson kernel chosen for this CPU. The string stays
 * valid until the next call. */
const char *nuppSimdjsonImplementation (void);

/* For the opener's signature, without making this header include lua.h. */
struct lua_State;

#ifdef __cplusplus
}
#endif

#endif
