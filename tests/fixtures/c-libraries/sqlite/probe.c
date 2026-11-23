/**
 * @file
 * @brief Checks that the pinned SQLite library matches its header and pin.
 *
 * The SQLite probe: a test-only program that checks the nupp_sqlite library
 * the C-library lane builds. The library must report the version and source
 * id of the header installed beside it and of scripts/toolchain.pins, carry
 * the compile options the core's provider refuses a library without
 * (nupp.runtime.core.sqlitecodec), and do real work on an in-memory
 * database: a statement over a tail, every storage class read back exactly,
 * and a syntax error reported at its byte offset.
 *
 * .github/scripts/test-c-libraries.sh builds it with CMakeLists.txt beside
 * it and reads the one line of JSON it prints. Every check is an assert, so
 * the build keeps assertions on in release builds too.
 */

#include <sqlite3.h>

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* The version scripts/toolchain.pins pins; a pin bump changes these too. */
#define EXPECTED_VERSION "3.54.1"
#define EXPECTED_VERSION_NUMBER 3054001

/* The SQL the probe runs: two statements in one text, so the second is
 * reached through the first one's tail. */
#define STATEMENTS                                                             \
  "create table t (i integer, r real, s text, b blob);"                        \
  "insert into t values (?, ?, ?, ?)"

/* A syntax error, and the byte offset SQLite reports for it: the start of
 * the token it could not parse. `frm` reads as the column's alias, so that
 * token is `t`. */
#define BROKEN "select 1 frm t"
#define BROKEN_OFFSET 13

/* The TEXT and BLOB values the probe binds, each with an embedded NUL. */
static const char text[] = "a\0b";
static const unsigned char blob[] = {0, 1, 0xff, 0};

/* A blob's length when bound and read back. */
#define TEXT_BYTES 3
#define BLOB_BYTES 4

/* The options the provider requires, and the ones it refuses. */
static const char *const required[] = {"OMIT_LOAD_EXTENSION", "ENABLE_FTS5",
                                       "THREADSAFE=1", "DQS=0"};
#define REQUIRED_COUNT (sizeof(required) / sizeof(required[0]))

/* Prepares the first statement of sql, which is length bytes, and answers
 * how many bytes it consumed. */
static int prepare (sqlite3 *db, const char *sql, int length,
                    sqlite3_stmt **statement) {
  const char *tail = NULL;
  assert(sqlite3_prepare_v3(db, sql, length, 0, statement, &tail) == SQLITE_OK);

  return (int)(tail - sql);
}

/* Binds and reads back every storage class, through a second statement
 * reached by the first one's tail. */
static void values (sqlite3 *db) {
  const char *sql = STATEMENTS;
  int length = (int)strlen(sql);
  sqlite3_stmt *statement = NULL;
  int consumed = prepare(db, sql, length, &statement);
  assert(sqlite3_step(statement) == SQLITE_DONE);
  assert(sqlite3_finalize(statement) == SQLITE_OK);
  int second = prepare(db, sql + consumed, length - consumed, &statement);
  assert(consumed + second == length);
  assert(sqlite3_bind_int64(statement, 1, INT64_MIN) == SQLITE_OK);
  assert(sqlite3_bind_double(statement, 2, 2.0) == SQLITE_OK);
  assert(sqlite3_bind_text64(statement, 3, text, TEXT_BYTES, SQLITE_TRANSIENT,
                             SQLITE_UTF8) == SQLITE_OK);
  assert(sqlite3_bind_blob64(statement, 4, blob, BLOB_BYTES,
                             SQLITE_TRANSIENT) == SQLITE_OK);
  assert(sqlite3_step(statement) == SQLITE_DONE);
  assert(sqlite3_finalize(statement) == SQLITE_OK);
  assert(sqlite3_changes64(db) == 1);
  prepare(db, "select i, r, s, b from t", -1, &statement);
  assert(sqlite3_step(statement) == SQLITE_ROW);
  assert(sqlite3_column_type(statement, 0) == SQLITE_INTEGER);
  assert(sqlite3_column_int64(statement, 0) == INT64_MIN);
  assert(sqlite3_column_type(statement, 1) == SQLITE_FLOAT);
  assert(sqlite3_column_double(statement, 1) == 2.0);
  assert(sqlite3_column_type(statement, 2) == SQLITE_TEXT);
  assert(sqlite3_column_bytes(statement, 2) == TEXT_BYTES);
  assert(!memcmp(sqlite3_column_text(statement, 2), text, TEXT_BYTES));
  assert(sqlite3_column_type(statement, 3) == SQLITE_BLOB);
  assert(sqlite3_column_bytes(statement, 3) == BLOB_BYTES);
  assert(!memcmp(sqlite3_column_blob(statement, 3), blob, BLOB_BYTES));
  assert(sqlite3_step(statement) == SQLITE_DONE);
  assert(sqlite3_finalize(statement) == SQLITE_OK);
}

/* A syntax error names its offset, and the statement is not made. */
static void syntaxerror (sqlite3 *db) {
  sqlite3_stmt *statement = NULL;
  int status = sqlite3_prepare_v3(db, BROKEN, -1, 0, &statement, NULL);
  assert(status == SQLITE_ERROR && statement == NULL);
  assert(sqlite3_error_offset(db) == BROKEN_OFFSET);
}

/* Checks the library against its header and pin, then has it do its work,
 * and reports. */
int main (void) {
  assert(sqlite3_libversion_number() == SQLITE_VERSION_NUMBER);
  static_assert(SQLITE_VERSION_NUMBER == EXPECTED_VERSION_NUMBER,
                "the header is the pinned SQLite's");
  assert(!strcmp(sqlite3_libversion(), EXPECTED_VERSION));
  assert(!strcmp(sqlite3_sourceid(), SQLITE_SOURCE_ID));

  for (size_t i = 0; i < REQUIRED_COUNT; ++i) {
    assert(sqlite3_compileoption_used(required[i]));
  }

  assert(!sqlite3_compileoption_used("ENABLE_LOAD_EXTENSION"));
  sqlite3 *db = NULL;
  int flags =
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXRESCODE;
  assert(sqlite3_open_v2(":memory:", &db, flags, NULL) == SQLITE_OK);
  values(db);
  syntaxerror(db);
  assert(sqlite3_close_v2(db) == SQLITE_OK);
  printf("{\"schemaVersion\":1,\"sqlite\":\"%s\",\"sourceId\":\"%s\","
         "\"passed\":true}\n",
         sqlite3_libversion(), sqlite3_sourceid());

  return 0;
}
