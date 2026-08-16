/* The bitwise lane path, compared between the two generated bodies.
 *
 * Bit operations are where the two gangs differ most: a binary64 gang converts
 * out to a 32-bit vector and back, which is a real instruction sequence on one
 * architecture and a different one on another, and an arithmetic shift has to
 * reinterpret the operand as signed first. See `checks/mandelbrot.c` for why
 * this is asked in C rather than through the Lua harness.
 */
#include <stdio.h>
#include <string.h>

#include KERNEL_C

#define COUNT 4093

int main(void) {
    static KsMotion motions[COUNT];
    static KsTransform2D lanes[COUNT];
    static KsTransform2D scalar[COUNT];

    for (int index = 0; index < COUNT; index += 1) {
        motions[index].vx = 0.5f - (float)(index % 31) / 30.0f;
        motions[index].vy = 0.5f - (float)(index % 29) / 28.0f;
        motions[index].angularVelocity = 0.125f * (float)(index % 7);
        motions[index].drag = 0.0625f * (float)(index % 5);
        lanes[index].x = scalar[index].x = 0.25f * (float)(index % 17);
        lanes[index].y = scalar[index].y = 0.25f * (float)(index % 19);
        lanes[index].rotation = scalar[index].rotation = 0.5f * (float)(index % 13);
        lanes[index].layer = scalar[index].layer = index % 11;
        /* A spread of flag words, so the enabled mask selects some lanes of
         * every gang and not others -- which is the case the mask has to get
         * right and a uniform pattern would not exercise. */
        lanes[index].flags = scalar[index].flags = (uint32_t)index * 2654435761u;
    }

    ks_advance(lanes, motions, 1, COUNT, 0.03125f, 0x5Au, COUNT);
    ks_advance_forced_scalar(scalar, motions, 1, COUNT, 0.03125f, 0x5Au, COUNT);

    if (memcmp(lanes, scalar, sizeof lanes) != 0) {
        for (int index = 0; index < COUNT; index += 1) {
            if (memcmp(&lanes[index], &scalar[index], sizeof lanes[index]) != 0) {
                printf("tecsbits: element %d differs: lanes %g/%g/%d/%u, scalar %g/%g/%d/%u\n",
                    index, (double)lanes[index].x, (double)lanes[index].y,
                    lanes[index].layer, lanes[index].flags,
                    (double)scalar[index].x, (double)scalar[index].y,
                    scalar[index].layer, scalar[index].flags);
                return 1;
            }
        }
    }

    printf("tecsbits: %d elements agree between lane-parallel and scalar C\n", COUNT);
    return 0;
}
