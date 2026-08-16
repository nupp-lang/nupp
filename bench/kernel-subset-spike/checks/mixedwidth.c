/* Explicit binary32 rounded into binary64 lanes, compared between the two
 * generated bodies.
 *
 * This is the newest lowering and the one with the most target-specific shape:
 * every explicit binary32 operation becomes a wide operation and a conversion
 * out to a narrow vector and back. What that conversion pair lowers to differs
 * per architecture, and it is exactly where a lost rounding would hide. See
 * `checks/mandelbrot.c` for why this is asked in C.
 */
#include <stdio.h>
#include <string.h>

#include KERNEL_C

#define COUNT 4093
#define STEPS 64

int main(void) {
    static KsBody bodies[COUNT];
    static KsTrack lanes[COUNT];
    static KsTrack scalar[COUNT];

    for (int index = 0; index < COUNT; index += 1) {
        float radius = 0.05f + (float)(index % 97) * 0.031f;
        float angle = (float)index * 0.37f;
        bodies[index].x = radius * (1.0f - 2.0f * (float)(index % 3) / 2.0f);
        bodies[index].y = radius * (1.0f - 2.0f * (float)(index % 5) / 4.0f);
        bodies[index].vx = 0.01f * (float)(index % 7) - 0.03f;
        bodies[index].vy = 0.01f * (float)(index % 11) - 0.05f;
        (void)angle;
    }

    ks_integrate(lanes, bodies, 1, COUNT, STEPS, -0.0009765625f, 0.03125f, 0.25f, COUNT);
    ks_integrate_forced_scalar(scalar, bodies, 1, COUNT, STEPS, -0.0009765625f, 0.03125f, 0.25f, COUNT);

    for (int index = 0; index < COUNT; index += 1) {
        if (memcmp(&lanes[index], &scalar[index], sizeof lanes[index]) != 0) {
            printf("mixedwidth: element %d differs: lanes %g/%d, scalar %g/%d\n",
                index, (double)lanes[index].distance, lanes[index].steps,
                (double)scalar[index].distance, scalar[index].steps);
            return 1;
        }
    }

    printf("mixedwidth: %d elements agree between lane-parallel and scalar C\n", COUNT);
    return 0;
}
