# Builds nupp_crc, the CRC adapter over ISA-L (crc.c), as a shared and a
# static library. scripts/c-libraries/isal.sh runs it with ISAL_SOURCE naming
# the pinned ISA-L checkout; the core binds the result through
# NUPP_CRC_LIBRARY.

cmake_minimum_required(VERSION 3.20)
project(nupp_crc C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(ISAL_BUILD_TESTS OFF)
set(ISAL_BUILD_PERF_TESTS OFF)

# Use the upstream CRC source lists, including its CPU dispatch and C fallback.
# No compression, RAID, crypto, or erasure-code implementation is compiled.
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64)$")
  set(CPU_X86_64 ON)

  if(WIN32)
    set(CMAKE_ASM_NASM_OBJECT_FORMAT win64)
  elseif(APPLE)
    set(CMAKE_ASM_NASM_OBJECT_FORMAT macho64)
    set(CMAKE_ASM_NASM_FLAGS "--prefix=_")
  else()
    set(CMAKE_ASM_NASM_OBJECT_FORMAT elf64)
    set(CMAKE_ASM_NASM_FLAGS "-D LINUX")
  endif()

  enable_language(ASM_NASM)
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(CPU_AARCH64 ON)
  enable_language(ASM)
else()
  set(CPU_UNDEFINED ON)
endif()

include("${ISAL_SOURCE}/cmake/crc.cmake")
list(TRANSFORM CRC_SOURCES PREPEND "${ISAL_SOURCE}/")

# One set of objects, linked into both libraries.
add_library(crc_objects OBJECT ${CRC_SOURCES} crc.c)
target_include_directories(
  crc_objects
  PRIVATE "${ISAL_SOURCE}/include" "${ISAL_SOURCE}" "${ISAL_SOURCE}/crc"
)

if(CPU_AARCH64)
  target_compile_definitions(crc_objects PRIVATE aarch64)
  target_compile_definitions(
    crc_objects
    PRIVATE $<$<COMPILE_LANGUAGE:ASM>:__ASSEMBLY__>
  )
endif()

add_library(nupp_crc SHARED $<TARGET_OBJECTS:crc_objects>)
add_library(nupp_crc_static STATIC $<TARGET_OBJECTS:crc_objects>)
set_target_properties(nupp_crc PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
set_target_properties(nupp_crc_static PROPERTIES OUTPUT_NAME nupp_crc_static)

install(
  TARGETS nupp_crc nupp_crc_static
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  RUNTIME DESTINATION bin
)
install(FILES nupp_crc.h DESTINATION include)
install(
  FILES "${ISAL_SOURCE}/include/crc.h" "${ISAL_SOURCE}/include/crc64.h"
  DESTINATION include/isa-l
)
