/**
 * @file
 * @brief C interface to the simdjson benchmark control.
 */

#ifndef NUPP_SIMDJSON_CONTROL_H
#define NUPP_SIMDJSON_CONTROL_H

#include <stddef.h>

#if defined(_WIN32)
#define NUPP_SIMDJSON_EXPORT __declspec(dllexport)
#else
#define NUPP_SIMDJSON_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/** Parser state and padded input reused between benchmark iterations. */
typedef struct nuppSimdjsonParser nuppSimdjsonParser;

/** Creates parser state, or returns null on allocation failure. */
nuppSimdjsonParser *nuppSimdjsonNew(void);
/** Releases the parser and its padded input. */
void nuppSimdjsonFree(nuppSimdjsonParser *parser);
/**
 * @brief Copies input into a padded buffer for subsequent parsing runs.
 * @param[in,out] parser Parser receiving the input.
 * @param[in] source Nonnull input borrowed for this call.
 * @param[in] length Input size in bytes.
 * @retval 0 Input copied successfully.
 * @retval -1 Invalid argument or allocation failure.
 */
int nuppSimdjsonPrepare(
    nuppSimdjsonParser *parser,
    const char *source,
    size_t length
);
/** Indexes the prepared input. Returns zero on success or an error code. */
int nuppSimdjsonStage1(nuppSimdjsonParser *parser);
/** Parses the prepared input into a DOM. Returns zero on success or an error code. */
int nuppSimdjsonDom(nuppSimdjsonParser *parser);
/** Returns a borrowed description of a code from the benchmark control. */
const char *nuppSimdjsonError(int code);
/** Returns the simdjson version used to build the control. */
const char *nuppSimdjsonVersion(void);
/** Returns the active simdjson implementation name in shared storage. */
const char *nuppSimdjsonImplementation(void);
struct lua_State;

#ifdef __cplusplus
}
#endif

#endif
