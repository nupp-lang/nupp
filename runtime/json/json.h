#ifndef NUPP_JSON_H
#define NUPP_JSON_H

#include <stddef.h>

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
int luaopen_jsonNative(struct lua_State *state);

#ifdef __cplusplus
}
#endif

#endif
