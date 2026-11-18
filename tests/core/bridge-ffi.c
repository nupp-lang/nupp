/* Test fixture, not a provider wrapper. */
#include <stdint.h>

uint64_t nuppBridgeFixture (uint64_t left, uint64_t right) {
  return left ^ right;
}

uint64_t nuppBridgeSlash (uint64_t left, uint64_t right) {
  return left ^ right;
}
