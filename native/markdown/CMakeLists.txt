# Builds nupp_markdown, the Markdown renderer over cmark-gfm (markdown.c) with
# its definition-list extension, as a shared and a static library.
# scripts/c-libraries/cmark.sh runs it with CMARK_SOURCE naming the pinned
# cmark-gfm checkout, which is compiled in statically.

cmake_minimum_required(VERSION 3.20)
project(nupp_markdown C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Upstream cmark-gfm, static and without its tests.
set(CMARK_TESTS OFF CACHE BOOL "" FORCE)
set(CMARK_SHARED OFF CACHE BOOL "" FORCE)
set(CMARK_STATIC ON CACHE BOOL "" FORCE)
add_subdirectory("${CMARK_SOURCE}" upstream)

if(NOT WIN32)
  find_package(Threads REQUIRED)
endif()

add_library(nupp_markdown SHARED markdown.c definitionlist.c)
target_compile_definitions(nupp_markdown PRIVATE NUPP_MD_EXPORTS)
add_library(nupp_markdown_static STATIC markdown.c definitionlist.c)
set_target_properties(
  nupp_markdown_static
  PROPERTIES OUTPUT_NAME nupp_markdown_static
)

foreach(target nupp_markdown nupp_markdown_static)
  target_compile_definitions(${target} PRIVATE CMARK_NO_SHORT_NAMES)
  target_include_directories(
    ${target}
    PRIVATE
      "${CMARK_SOURCE}/src"
      "${CMARK_SOURCE}/extensions"
      "${CMAKE_CURRENT_BINARY_DIR}/upstream/src"
      "${CMAKE_CURRENT_BINARY_DIR}/upstream/extensions"
  )
  target_link_libraries(
    ${target}
    PRIVATE libcmark-gfm-extensions_static libcmark-gfm_static
  )

  if(NOT WIN32)
    target_link_libraries(${target} PRIVATE Threads::Threads)
  endif()
endforeach()

set_target_properties(
  nupp_markdown
  PROPERTIES INSTALL_RPATH "$ORIGIN;@loader_path" C_VISIBILITY_PRESET hidden
)

install(
  TARGETS nupp_markdown nupp_markdown_static
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
)
install(FILES markdown.h definitionlist.h DESTINATION include/nupp)
