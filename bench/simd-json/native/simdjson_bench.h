#ifndef NUPP_SIMDJSON_BENCH_H
#define NUPP_SIMDJSON_BENCH_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct nupp_simdjson_parser nupp_simdjson_parser;

nupp_simdjson_parser *nupp_simdjson_new(void);
void nupp_simdjson_free(nupp_simdjson_parser *parser);
int nupp_simdjson_prepare(
    nupp_simdjson_parser *parser,
    const char *source,
    size_t length
);
int nupp_simdjson_stage1(nupp_simdjson_parser *parser);
int nupp_simdjson_dom(nupp_simdjson_parser *parser);
const char *nupp_simdjson_error(int code);
const char *nupp_simdjson_version(void);
const char *nupp_simdjson_implementation(void);

#ifdef __cplusplus
}
#endif

#endif
