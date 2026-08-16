/* A uniform inner loop over lane-parallel statements, compared between the two
 * generated bodies.
 *
 * No masks are involved, which is the point: the loop is ordinary control flow
 * and only the values in it are vectors. What that costs is a gather at the top
 * and a scatter at the bottom, and this checks the answers survive both on
 * whatever target compiled them. See `checks/mandelbrot.c` for why this is asked
 * in C rather than through the Lua harness.
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

    ks_integrate(lanes, bodies, 1, COUNT, STEPS, 0.03125f, COUNT);
    ks_integrate_forced_scalar(scalar, bodies, 1, COUNT, STEPS, 0.03125f, COUNT);

    for (int index = 0; index < COUNT; index += 1) {
        if (memcmp(&lanes[index], &scalar[index], sizeof lanes[index]) != 0) {
            printf("uniform: element %d differs: lanes %g/%d, scalar %g/%d\n",
                index, (double)lanes[index].distance, lanes[index].steps,
                (double)scalar[index].distance, scalar[index].steps);
            return 1;
        }
    }

    printf("uniform: %d elements agree between lane-parallel and scalar C\n", COUNT);
    return 0;
}
