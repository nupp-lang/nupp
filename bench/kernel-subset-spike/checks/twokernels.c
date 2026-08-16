/* Two functions from one file, each compared against its own scalar body.
 *
 * They chose different gangs, so this file carries both preludes: the mask
 * helpers are named for their mask and the scalar helpers appear once. What
 * this checks is that neither definition displaced the other, and that each
 * function still answers what its own scalar body does. See
 * `checks/mandelbrot.c` for why this is asked in C.
 */
#include <stdio.h>
#include <string.h>

#include KERNEL_C

#define COUNT 4093

static KsSample source[COUNT];
static KsSample lanes[COUNT];
static KsSample scalar[COUNT];

static int compare(const char *name) {
    for (int index = 0; index < COUNT; index += 1) {
        if (memcmp(&lanes[index], &scalar[index], sizeof lanes[index]) != 0) {
            printf("twokernels/%s: element %d differs: lanes %g/%g, scalar %g/%g\n",
                name, index, (double)lanes[index].value, (double)lanes[index].weight,
                (double)scalar[index].value, (double)scalar[index].weight);
            return 1;
        }
    }
    return 0;
}

int main(void) {
    for (int index = 0; index < COUNT; index += 1) {
        source[index].value = 0.5f - (float)(index % 31) / 30.0f;
        source[index].weight = 0.25f + (float)(index % 17) / 16.0f;
    }

    ks_scale(lanes, source, 1, COUNT, 1.5, COUNT);
    ks_scale_forced_scalar(scalar, source, 1, COUNT, 1.5, COUNT);
    if (compare("scale") != 0) {
        return 1;
    }

    ks_brighten(lanes, source, 1, COUNT, 0.125f, COUNT);
    ks_brighten_forced_scalar(scalar, source, 1, COUNT, 0.125f, COUNT);
    if (compare("brighten") != 0) {
        return 1;
    }

    printf("twokernels: %d elements agree for both functions, across two gangs in one file\n", COUNT);
    return 0;
}
