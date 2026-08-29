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

typedef struct nuppSimdjsonParser nuppSimdjsonParser;

nuppSimdjsonParser *nuppSimdjsonNew(void);
void nuppSimdjsonFree(nuppSimdjsonParser *parser);
int nuppSimdjsonPrepare(
    nuppSimdjsonParser *parser,
    const char *source,
    size_t length
);
int nuppSimdjsonStage1(nuppSimdjsonParser *parser);
int nuppSimdjsonDom(nuppSimdjsonParser *parser);
const char *nuppSimdjsonError(int code);
const char *nuppSimdjsonVersion(void);
const char *nuppSimdjsonImplementation(void);
struct lua_State;

#ifdef __cplusplus
}
#endif

#endif
