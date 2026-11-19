/**
 * @file
 * @brief Exercises callbacks, multidimensional arrays, and pointer
 * declarations.
 *
 * Test fixture for C interop: the declarators a rendering that reads only
 * simple ones would get wrong. A nested fixed array, a callback held in a
 * struct, an array parameter that is a pointer in disguise, and a function
 * that returns a pointer to an array. importctest and cheadertest import it,
 * and the VM's declaration registry replays it whole.
 */

#ifndef NUPP_COMPLETE_C_INTEROP_H
#define NUPP_COMPLETE_C_INTEROP_H

typedef void (*nupp_complete_callback)(int value);

typedef struct {
  float matrix[2][3];
  nupp_complete_callback callback;
} nupp_complete_context;

void nupp_complete_use_context (nupp_complete_context *context);
nupp_complete_callback nupp_complete_get_callback (void);
void nupp_complete_set_callbacks (nupp_complete_callback callbacks[4]);
int (*nupp_complete_get_row(void))[4];

#endif
