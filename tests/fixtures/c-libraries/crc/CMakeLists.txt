# Builds the CRC adapter's probes against the pinned ISA-L prefix: crc-probe
# (probe.c) checks every algorithm through each forced code path, and
# crc-shared-probe (shared.c) checks the shared library.
# .github/scripts/test-crc-isal.sh configures it with NUPP_ISAL.

cmake_minimum_required(VERSION 3.20)
project(nupp_crc_probe C)

set(CMAKE_C_STANDARD 11)
set(adapter "${CMAKE_CURRENT_SOURCE_DIR}/../../../../native/crc")

unset(CRC_LIBRARY CACHE)
find_library(
  CRC_LIBRARY
  NAMES nupp_crc_static
  PATHS "${NUPP_ISAL}/lib"
  NO_DEFAULT_PATH
  REQUIRED
)

# The adapter compiled again (force.c) with one code path forced, under its
# own symbol names so several paths link into one probe.
function(forced name)
  add_library(${name} OBJECT force.c)
  target_include_directories(
    ${name}
    PRIVATE "${NUPP_ISAL}/include/isa-l" "${adapter}"
  )
  target_compile_definitions(
    ${name}
    PRIVATE nuppCrcUpdate=${name} nuppCrcLastError=${name}error ${ARGN}
  )
endfunction()

forced(crcbase NUPP_FORCE_BASE)
forced(crcsmall NUPP_FORCE_BASE NUPP_FORCE_SMALL_CHUNKS)

add_executable(
  crc-probe
  probe.c
  $<TARGET_OBJECTS:crcbase>
  $<TARGET_OBJECTS:crcsmall>
)
target_include_directories(crc-probe PRIVATE "${NUPP_ISAL}/include")
target_link_libraries(crc-probe PRIVATE "${CRC_LIBRARY}")

unset(CRC_SHARED_LIBRARY CACHE)
find_library(
  CRC_SHARED_LIBRARY
  NAMES nupp_crc
  PATHS "${NUPP_ISAL}/lib"
  NO_DEFAULT_PATH
  REQUIRED
)

add_executable(crc-shared-probe shared.c)
target_include_directories(crc-shared-probe PRIVATE "${NUPP_ISAL}/include")
target_link_libraries(crc-shared-probe PRIVATE "${CRC_SHARED_LIBRARY}")

# The host's SIMD path, where it has one.
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64)$")
  forced(crcsimd NUPP_FORCE_X86)
  target_compile_definitions(crc-probe PRIVATE NUPP_TEST_X86)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  forced(crcsimd NUPP_FORCE_ARM)
  target_compile_definitions(crc-probe PRIVATE NUPP_TEST_ARM)
endif()

if(TARGET crcsimd)
  target_sources(crc-probe PRIVATE $<TARGET_OBJECTS:crcsimd>)
endif()

# Assertions are the probe, including in release builds.
if(MSVC)
  target_compile_options(crc-probe PRIVATE /UNDEBUG)
  target_compile_options(crc-shared-probe PRIVATE /UNDEBUG)
else()
  target_compile_options(crc-probe PRIVATE -UNDEBUG -Wall -Wextra -Werror)
  target_compile_options(
    crc-shared-probe
    PRIVATE -UNDEBUG -Wall -Wextra -Werror
  )
endif()
