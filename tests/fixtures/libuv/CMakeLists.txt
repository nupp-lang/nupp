cmake_minimum_required(VERSION 3.20)
project(nupp_libuv_probe C)
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
# Use upstream's relocatable config, matched headers and shared import target.
find_package(libuv ${NUPP_LIBUV_VERSION} EXACT CONFIG REQUIRED
  PATHS "${NUPP_LIBUV}/lib/cmake/libuv" NO_DEFAULT_PATH)
add_executable(libuv-probe probe.c)
# Put the pinned headers before any host libuv headers on the include path.
set_property(TARGET libuv-probe PROPERTY NO_SYSTEM_FROM_IMPORTED ON)
target_link_libraries(libuv-probe PRIVATE libuv::uv)
target_compile_definitions(libuv-probe PRIVATE
  NUPP_EXPECT_TARGET="${NUPP_TARGET}" NUPP_EXPECT_VERSION="${NUPP_LIBUV_VERSION}")
if(MSVC)
  target_compile_options(libuv-probe PRIVATE /UNDEBUG)
else()
  target_compile_options(libuv-probe PRIVATE -UNDEBUG -Wall -Wextra -Werror)
endif()
if(APPLE)
  set_property(TARGET libuv-probe PROPERTY INSTALL_RPATH "@loader_path/../lib")
elseif(UNIX)
  set_property(TARGET libuv-probe PROPERTY INSTALL_RPATH "$ORIGIN/../lib")
endif()
install(TARGETS libuv-probe RUNTIME DESTINATION bin)
