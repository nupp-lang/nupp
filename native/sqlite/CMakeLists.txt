# Builds nupp_sqlite, the pinned SQLite amalgamation (sqlite3.c), as a shared
# library under a name no system libsqlite3 shares, so a program opening it by
# path can never be handed another SQLite. scripts/c-libraries/sqlite.sh runs
# it with SQLITE_SOURCE naming the pinned sqlite-autoconf tree; the core binds
# the result through NUPP_SQLITE_LIBRARY (nupp.runtime.core.sqlitecodec).

cmake_minimum_required(VERSION 3.20)
project(nupp_sqlite C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(nupp_sqlite SHARED "${SQLITE_SOURCE}/sqlite3.c")

# The options the provider checks at first open: double-quoted strings are
# identifiers only, SQL cannot load native code, no deprecated interface or
# shared-cache mode is compiled, allocations are not counted globally, WAL
# defaults to synchronous=NORMAL, and full-text search and the math functions
# are built in. Serialized mode lets several threads each own a connection.
target_compile_definitions(
  nupp_sqlite
  PRIVATE
    SQLITE_DQS=0
    SQLITE_OMIT_LOAD_EXTENSION
    SQLITE_OMIT_DEPRECATED
    SQLITE_OMIT_SHARED_CACHE
    SQLITE_DEFAULT_MEMSTATUS=0
    SQLITE_DEFAULT_WAL_SYNCHRONOUS=1
    SQLITE_LIKE_DOESNT_MATCH_BLOBS
    SQLITE_ENABLE_FTS5
    SQLITE_ENABLE_MATH_FUNCTIONS
    SQLITE_THREADSAFE=1
)

# A DLL exports only what is marked, and is named as the binding names it
# (nupp_sqlite.dll), without the lib prefix MinGW would give it.
if(WIN32)
  target_compile_definitions(
    nupp_sqlite
    PRIVATE "SQLITE_API=__declspec(dllexport)"
  )
  set_target_properties(nupp_sqlite PROPERTIES PREFIX "")
endif()

if(NOT WIN32)
  find_package(Threads REQUIRED)
  target_link_libraries(nupp_sqlite PRIVATE Threads::Threads)
endif()

# The math functions call libm, which is part of the C library on Apple and
# Windows targets.
if(UNIX AND NOT APPLE)
  target_link_libraries(nupp_sqlite PRIVATE m)
endif()

install(
  TARGETS nupp_sqlite
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  RUNTIME DESTINATION bin
)
install(FILES "${SQLITE_SOURCE}/sqlite3.h" DESTINATION include)
