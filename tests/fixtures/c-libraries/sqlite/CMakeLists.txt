# Builds sqlite-probe (probe.c) against the pinned nupp_sqlite prefix, to prove
# the library answers as its header and pin say and carries the options the
# core's provider requires. .github/scripts/test-c-libraries.sh configures it
# with NUPP_SQLITE.

cmake_minimum_required(VERSION 3.20)
project(nupp_sqlite_probe C)

set(CMAKE_C_STANDARD 11)

# A reused probe directory must resolve the current exact prefix again.
unset(SQLITE_INCLUDE CACHE)
unset(SQLITE_LIBRARY CACHE)

find_path(
  SQLITE_INCLUDE
  sqlite3.h
  PATHS "${NUPP_SQLITE}/include"
  NO_DEFAULT_PATH
  REQUIRED
)
find_library(
  SQLITE_LIBRARY
  NAMES nupp_sqlite
  PATHS "${NUPP_SQLITE}/lib" "${NUPP_SQLITE}/bin"
  NO_DEFAULT_PATH
  REQUIRED
)

add_executable(sqlite-probe probe.c)
target_include_directories(sqlite-probe PRIVATE "${SQLITE_INCLUDE}")
target_link_libraries(sqlite-probe PRIVATE "${SQLITE_LIBRARY}")

# Assertions are the probe, including in release builds.
if(MSVC)
  target_compile_options(sqlite-probe PRIVATE /UNDEBUG)
else()
  target_compile_options(sqlite-probe PRIVATE -UNDEBUG -Wall -Wextra -Werror)
endif()

set_property(TARGET sqlite-probe PROPERTY BUILD_RPATH "${NUPP_SQLITE}/lib")
