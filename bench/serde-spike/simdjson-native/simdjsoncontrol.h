/**
 * @file
 * @brief C interface to the simdjson benchmark control.
 *
 * The serialization benchmark's native control: simdjson behind a small C
 * interface, built by bench/serde-spike/nupp.lua from simdjsoncontrol.cpp,
 * so that bench/serde-spike can time the serde.json variants beside a
 * native parser reading the same documents.
 *
 * The int-returning calls answer 0 for success, -1 for a bad argument or an
 * allocation failure in this bridge, and otherwise simdjson's error code;
 * nuppsimdjsonerror names any of them.
 */

#ifndef NUPP_SIMDJSON_CONTROL_H
#define NUPP_SIMDJSON_CONTROL_H

#include <stddef.h>

/** Marks the Lua module opener simdjsoncontrol.cpp exports. */
#if defined(_WIN32)

#define NUPP_SIMDJSON_EXPORT __declspec(dllexport)

#else

#define NUPP_SIMDJSON_EXPORT __attribute__((visibility("default")))

#endif

#ifdef __cplusplus
extern "C" {
#endif

/** A parser and the padded copy of the document it last prepared. */
typedef struct nuppsimdjsonparser nuppsimdjsonparser;

/** A new parser, or NULL when it cannot be allocated. */
nuppsimdjsonparser *nuppsimdjsonnew (void);

/** Releases the parser and its padded input. */
void nuppsimdjsonfree (nuppsimdjsonparser *parser);

/** Copies `length` bytes of `source` into the parser's buffer with the
 * padding simdjson reads past the end, so the timed calls below parse
 * without copying. */
int nuppsimdjsonprepare (nuppsimdjsonparser *parser, const char *source,
                         size_t length);

/** Starts an On-Demand iteration over the prepared document, which runs
 * simdjson's structural indexing alone. */
int nuppsimdjsonstage1 (nuppsimdjsonparser *parser);

/** Parses the prepared document into a DOM. */
int nuppsimdjsondom (nuppsimdjsonparser *parser);

/** Returns a borrowed description of a control error code. */
const char *nuppsimdjsonerror (int code);

/** Returns the upstream simdjson version of the control. */
const char *nuppsimdjsonversion (void);

/** The name of the simdjson kernel chosen for this CPU. The string stays
 * valid until the next call. */
const char *nuppsimdjsonimplementation (void);

/* For the opener's signature, without making this header include lua.h. */
struct lua_State;

#ifdef __cplusplus
}
#endif

#endif
