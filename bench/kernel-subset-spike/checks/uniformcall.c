/* A uniform helper call inside a lane body, compared between the two generated
 * bodies.
 *
 * The call happens once per group rather than once per lane, and its results
 * are broadcast where they meet vectors. What this checks is that hoisting it
 * out of the lanes did not change what any lane computed. See
 * `checks/mandelbrot.c` for why this is asked in C rather than through the Lua
 * harness.
 */
#include <stdio.h>
#include <string.h>

#include KERNEL_C

#define COUNT 4093

int main(void) {
    static KsVelocity velocities[COUNT];
    static KsPosition lanes[COUNT];
    static KsPosition scalar[COUNT];

    for (int index = 0; index < COUNT; index += 1) {
        velocities[index].vx = 0.5f - (float)(index % 31) / 30.0f;
        velocities[index].vy = 0.5f - (float)(index % 29) / 28.0f;
        lanes[index].x = scalar[index].x = 0.25f * (float)(index % 17);
        lanes[index].y = scalar[index].y = 0.25f * (float)(index % 19);
    }

    ks_advance(lanes, velocities, 1, COUNT, 0.03125, 0.125, COUNT);
    ks_advance_forced_scalar(scalar, velocities, 1, COUNT, 0.03125, 0.125, COUNT);

    for (int index = 0; index < COUNT; index += 1) {
        if (memcmp(&lanes[index], &scalar[index], sizeof lanes[index]) != 0) {
            printf("uniformcall: element %d differs: lanes %g/%g, scalar %g/%g\n",
                index, (double)lanes[index].x, (double)lanes[index].y,
                (double)scalar[index].x, (double)scalar[index].y);
            return 1;
        }
    }

    printf("uniformcall: %d elements agree between lane-parallel and scalar C\n", COUNT);
    return 0;
}
