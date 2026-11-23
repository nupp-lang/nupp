# Builds nupp_yaml, the pinned libyaml's own sources as one shared library
# with the same name on every target. scripts/c-libraries/libyaml.sh runs it
# with LIBYAML_SOURCE naming the verified release tree and LIBYAML_VERSION its
# pin; the core binds the result through NUPP_YAML_LIBRARY (serde.yaml).
#
# Upstream's CMake is not used: the release archive does not carry the
# config.h template it configures, its library is libyaml.dll under MinGW and
# yaml.dll under MSVC, and it adds tests and tools the artifact does not want.

cmake_minimum_required(VERSION 3.20)
project(nupp_yaml C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT LIBYAML_VERSION MATCHES "^([0-9]+)\\.([0-9]+)\\.([0-9]+)$")
  message(FATAL_ERROR "LIBYAML_VERSION must be MAJOR.MINOR.PATCH")
endif()

set(major "${CMAKE_MATCH_1}")
set(minor "${CMAKE_MATCH_2}")
set(patch "${CMAKE_MATCH_3}")

add_library(
  nupp_yaml
  SHARED
  "${LIBYAML_SOURCE}/src/api.c"
  "${LIBYAML_SOURCE}/src/dumper.c"
  "${LIBYAML_SOURCE}/src/emitter.c"
  "${LIBYAML_SOURCE}/src/loader.c"
  "${LIBYAML_SOURCE}/src/parser.c"
  "${LIBYAML_SOURCE}/src/reader.c"
  "${LIBYAML_SOURCE}/src/scanner.c"
  "${LIBYAML_SOURCE}/src/writer.c"
)

# What upstream's config.h would define, from the pin. YAML_DECLARE_EXPORT
# exports the API from the DLL; elsewhere every YAML_DECLARE is visible.
target_compile_definitions(
  nupp_yaml
  PRIVATE
    YAML_VERSION_MAJOR=${major}
    YAML_VERSION_MINOR=${minor}
    YAML_VERSION_PATCH=${patch}
    YAML_VERSION_STRING="${LIBYAML_VERSION}"
    YAML_DECLARE_EXPORT
)
target_include_directories(nupp_yaml PRIVATE "${LIBYAML_SOURCE}/include")

# One file name everywhere: nupp_yaml.dll, not MinGW's libnupp_yaml.dll.
if(WIN32)
  set_target_properties(nupp_yaml PROPERTIES PREFIX "" IMPORT_PREFIX "")
endif()

install(
  TARGETS nupp_yaml
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)
install(FILES "${LIBYAML_SOURCE}/include/yaml.h" DESTINATION include)
