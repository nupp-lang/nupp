/**
 * @file
 * @brief Checks libyaml's layouts against the binding serde.yaml declares.
 *
 * The libyaml layout probe. scripts/c-libraries/libyaml.sh builds it against
 * the exact header and library it has just built, and runs it before the
 * artifact is published; it prints one line of JSON.
 *
 * The core reads libyaml's structures through the overlays
 * nupp.runtime.core.yamlcodec declares rather than through this header: the
 * parser's and emitter's leading error fields, and an event's type, the
 * scalar member of its union, the collection-start member and its marks. This
 * file states those sizes and offsets once more in C, so a target or release
 * that lays them out differently fails to build instead of being misread.
 * main then parses a small document and emits one through a growable write
 * handler, the shape the core's bridge keeper has.
 */

#include <yaml.h>

#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The storage yamlcodec.nupp allocates for each structure. */
#define PARSER_BYTES 480
#define EMITTER_BYTES 432
#define EVENT_BYTES 104
#define MARK_BYTES 24

_Static_assert(sizeof(void *) == 8 && sizeof(size_t) == 8,
               "yamlcodec reads 64-bit pointers and sizes");
_Static_assert(sizeof(yaml_parser_t) == PARSER_BYTES, "yaml_parser_t drift");
_Static_assert(sizeof(yaml_emitter_t) == EMITTER_BYTES, "yaml_emitter_t drift");
_Static_assert(sizeof(yaml_event_t) == EVENT_BYTES, "yaml_event_t drift");
_Static_assert(sizeof(yaml_mark_t) == MARK_BYTES, "yaml_mark_t drift");
_Static_assert(offsetof(yaml_mark_t, index) == 0 &&
                   offsetof(yaml_mark_t, line) == 8 &&
                   offsetof(yaml_mark_t, column) == 16,
               "yaml_mark_t field drift");

/* The parser's error prefix (yamlcodec's ParserErrors). */
_Static_assert(offsetof(yaml_parser_t, error) == 0, "parser error drift");
_Static_assert(offsetof(yaml_parser_t, problem) == 8, "parser problem drift");
_Static_assert(offsetof(yaml_parser_t, problem_offset) == 16,
               "parser problem_offset drift");
_Static_assert(offsetof(yaml_parser_t, problem_value) == 24,
               "parser problem_value drift");
_Static_assert(offsetof(yaml_parser_t, problem_mark) == 32,
               "parser problem_mark drift");
_Static_assert(offsetof(yaml_parser_t, context) == 56, "parser context drift");
_Static_assert(offsetof(yaml_parser_t, context_mark) == 64,
               "parser context_mark drift");

/* The emitter's error prefix (EmitterErrors). */
_Static_assert(offsetof(yaml_emitter_t, error) == 0, "emitter error drift");
_Static_assert(offsetof(yaml_emitter_t, problem) == 8, "emitter problem drift");

/* An event (Event and CollectionEvent): its type, the union at 8 whose
 * scalar member is its widest, and the marks after it. */
_Static_assert(offsetof(yaml_event_t, type) == 0, "event type drift");
_Static_assert(sizeof(((yaml_event_t *)0)->data) == 48, "event data drift");
_Static_assert(offsetof(yaml_event_t, data.scalar.anchor) == 8 &&
                   offsetof(yaml_event_t, data.scalar.tag) == 16 &&
                   offsetof(yaml_event_t, data.scalar.value) == 24 &&
                   offsetof(yaml_event_t, data.scalar.length) == 32 &&
                   offsetof(yaml_event_t, data.scalar.plain_implicit) == 40 &&
                   offsetof(yaml_event_t, data.scalar.quoted_implicit) == 44 &&
                   offsetof(yaml_event_t, data.scalar.style) == 48,
               "scalar event drift");
_Static_assert(offsetof(yaml_event_t, data.sequence_start.anchor) == 8 &&
                   offsetof(yaml_event_t, data.sequence_start.tag) == 16 &&
                   offsetof(yaml_event_t, data.sequence_start.implicit) == 24 &&
                   offsetof(yaml_event_t, data.sequence_start.style) == 28,
               "sequence event drift");
_Static_assert(offsetof(yaml_event_t, data.mapping_start.anchor) == 8 &&
                   offsetof(yaml_event_t, data.mapping_start.tag) == 16 &&
                   offsetof(yaml_event_t, data.mapping_start.implicit) == 24 &&
                   offsetof(yaml_event_t, data.mapping_start.style) == 28,
               "mapping event drift");
_Static_assert(offsetof(yaml_event_t, data.alias.anchor) == 8,
               "alias event drift");
_Static_assert(offsetof(yaml_event_t, start_mark) == 56 &&
                   offsetof(yaml_event_t, end_mark) == 80,
               "event mark drift");

/* The enumerators the binding names as constants. */
_Static_assert(YAML_NO_EVENT == 0 && YAML_STREAM_START_EVENT == 1 &&
                   YAML_STREAM_END_EVENT == 2 &&
                   YAML_DOCUMENT_START_EVENT == 3 &&
                   YAML_DOCUMENT_END_EVENT == 4 && YAML_ALIAS_EVENT == 5 &&
                   YAML_SCALAR_EVENT == 6 && YAML_SEQUENCE_START_EVENT == 7 &&
                   YAML_SEQUENCE_END_EVENT == 8 &&
                   YAML_MAPPING_START_EVENT == 9 &&
                   YAML_MAPPING_END_EVENT == 10,
               "event type drift");
_Static_assert(YAML_ANY_SCALAR_STYLE == 0 && YAML_PLAIN_SCALAR_STYLE == 1 &&
                   YAML_SINGLE_QUOTED_SCALAR_STYLE == 2 &&
                   YAML_DOUBLE_QUOTED_SCALAR_STYLE == 3 &&
                   YAML_LITERAL_SCALAR_STYLE == 4 &&
                   YAML_FOLDED_SCALAR_STYLE == 5,
               "scalar style drift");
_Static_assert(YAML_BLOCK_SEQUENCE_STYLE == 1 &&
                   YAML_FLOW_SEQUENCE_STYLE == 2 &&
                   YAML_BLOCK_MAPPING_STYLE == 1 &&
                   YAML_FLOW_MAPPING_STYLE == 2,
               "collection style drift");
_Static_assert(YAML_UTF8_ENCODING == 1 && YAML_NO_ERROR == 0,
               "encoding or error drift");

/* The version the binding refuses any other than. */
#define PINNED_MAJOR 0
#define PINNED_MINOR 2
#define PINNED_PATCH 6

/* The document main parses: a mapping holding a scalar and a sequence. */
static const char DOCUMENT[] = "name: probe\nlist: [1, two]\n";

/* The events it parses to, in order. */
static const yaml_event_type_t EXPECTED[] = {
    YAML_STREAM_START_EVENT,   YAML_DOCUMENT_START_EVENT,
    YAML_MAPPING_START_EVENT,  YAML_SCALAR_EVENT,
    YAML_SCALAR_EVENT,         YAML_SCALAR_EVENT,
    YAML_SEQUENCE_START_EVENT, YAML_SCALAR_EVENT,
    YAML_SCALAR_EVENT,         YAML_SEQUENCE_END_EVENT,
    YAML_MAPPING_END_EVENT,    YAML_DOCUMENT_END_EVENT,
    YAML_STREAM_END_EVENT,
};

#define EXPECTED_COUNT (sizeof(EXPECTED) / sizeof(EXPECTED[0]))

/* What main emits, and the text the emitter must write for it. */
static const char EMITTED[] = "key: value\n";

/* A growable buffer the emitter writes into. */
typedef struct {
  unsigned char *data;
  size_t used;
  size_t capacity;
} Sink;

/* The write handler: appends, doubling the buffer as needed. */
static int append (void *data, unsigned char *bytes, size_t size) {
  Sink *sink = data;

  if (size > sink->capacity - sink->used) {
    size_t capacity = sink->capacity ? sink->capacity : 64;

    while (capacity - sink->used < size) {
      capacity *= 2;
    }

    unsigned char *grown = realloc(sink->data, capacity);

    if (!grown) {
      return 0;
    }

    sink->data = grown;
    sink->capacity = capacity;
  }

  memcpy(sink->data + sink->used, bytes, size);
  sink->used += size;

  return 1;
}

/* Parses DOCUMENT and checks each event's type and the first scalar. */
static void parse (void) {
  yaml_parser_t parser;
  assert(yaml_parser_initialize(&parser));
  yaml_parser_set_input_string(&parser, (const unsigned char *)DOCUMENT,
                               sizeof(DOCUMENT) - 1);

  for (size_t i = 0; i < EXPECTED_COUNT; ++i) {
    yaml_event_t event;
    assert(yaml_parser_parse(&parser, &event));
    assert(event.type == EXPECTED[i]);

    if (i == 3) {
      assert(event.data.scalar.length == 4);
      assert(memcmp(event.data.scalar.value, "name", 4) == 0);
      assert(event.start_mark.line == 0 && event.start_mark.column == 0);
    }

    yaml_event_delete(&event);
  }

  yaml_parser_delete(&parser);
}

/* Emits one mapping through the write handler and checks the text. */
static void emit (void) {
  yaml_emitter_t emitter;
  Sink sink = {NULL, 0, 0};
  yaml_event_t event;
  assert(yaml_emitter_initialize(&emitter));
  yaml_emitter_set_output(&emitter, append, &sink);
  yaml_emitter_set_unicode(&emitter, 1);
  assert(yaml_stream_start_event_initialize(&event, YAML_UTF8_ENCODING));
  assert(yaml_emitter_emit(&emitter, &event));
  assert(yaml_document_start_event_initialize(&event, NULL, NULL, NULL, 1));
  assert(yaml_emitter_emit(&emitter, &event));
  assert(yaml_mapping_start_event_initialize(&event, NULL, NULL, 1,
                                             YAML_BLOCK_MAPPING_STYLE));
  assert(yaml_emitter_emit(&emitter, &event));
  assert(yaml_scalar_event_initialize(&event, NULL, NULL,
                                      (const yaml_char_t *)"key", 3, 1, 1,
                                      YAML_PLAIN_SCALAR_STYLE));
  assert(yaml_emitter_emit(&emitter, &event));
  assert(yaml_scalar_event_initialize(&event, NULL, NULL,
                                      (const yaml_char_t *)"value", 5, 1, 1,
                                      YAML_PLAIN_SCALAR_STYLE));
  assert(yaml_emitter_emit(&emitter, &event));
  assert(yaml_mapping_end_event_initialize(&event));
  assert(yaml_emitter_emit(&emitter, &event));
  assert(yaml_document_end_event_initialize(&event, 1));
  assert(yaml_emitter_emit(&emitter, &event));
  assert(yaml_stream_end_event_initialize(&event));
  assert(yaml_emitter_emit(&emitter, &event));
  assert(yaml_emitter_flush(&emitter));
  yaml_emitter_delete(&emitter);
  assert(sink.used == sizeof(EMITTED) - 1);
  assert(memcmp(sink.data, EMITTED, sink.used) == 0);
  free(sink.data);
}

int main (void) {
  int major = -1, minor = -1, patch = -1;
  yaml_get_version(&major, &minor, &patch);
  assert(major == PINNED_MAJOR && minor == PINNED_MINOR &&
         patch == PINNED_PATCH);
  parse();
  emit();
  printf("{\"libyaml\":\"%s\",\"parserBytes\":%zu,\"emitterBytes\":%zu,"
         "\"eventBytes\":%zu}\n",
         yaml_get_version_string(), sizeof(yaml_parser_t),
         sizeof(yaml_emitter_t), sizeof(yaml_event_t));

  return 0;
}
