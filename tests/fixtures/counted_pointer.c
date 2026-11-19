#include <stddef.h>
#include <stdint.h>

static uint64_t counted_pointer_calls = 0;

void counted_pointer_reset(void) {
    counted_pointer_calls = 0;
}

uint64_t counted_pointer_call_count(void) {
    return counted_pointer_calls;
}

void counted_pointer_transform(
    int32_t *output,
    const int32_t *input,
    size_t count
) {
    counted_pointer_calls += 1;
    for (size_t i = 0; i < count; ++i) {
        output[i] = input[i] + 10;
    }
}

void counted_pointer_independent(
    int32_t *output,
    size_t output_count,
    const int32_t *input,
    size_t input_count
) {
    counted_pointer_calls += 1;
    if (output_count > 0) {
        output[0] = (int32_t)output_count;
    }
    if (output_count > 1) {
        output[1] = (int32_t)input_count;
    }
    if (output_count > 2 && input_count > 0) {
        output[2] = input[0];
    }
}
