#include <stddef.h>
#include <stdint.h>
#include <time.h>

double spike_sum(const double *values, size_t count) {
    double total = 0;
    for (size_t i = 0; i < count; ++i) total += values[i];
    return total;
}
int spike_callback(int (*callback)(int), int value) {
    return callback(value) + 1;
}
/* The worker copies the parent's atomic clock between emulation slices.
 * A single x86 double load cannot straddle two JavaScript clock updates. */
double spike_clock(const void *mailbox) {
    return *(const volatile double *)mailbox;
}
/* Let the guest C ABI handle musl's 64-bit time_t on i386. */
double spike_monotonic(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value)) return -1;
    return (double)value.tv_sec + (double)value.tv_nsec / 1e9;
}
