#ifndef NUPP_COMPLETE_C_INTEROP_H
#define NUPP_COMPLETE_C_INTEROP_H

typedef void (*nupp_complete_callback)(int value);

typedef struct {
    float matrix[2][3];
    nupp_complete_callback callback;
} nupp_complete_context;

void nupp_complete_use_context(nupp_complete_context *context);
nupp_complete_callback nupp_complete_get_callback(void);
void nupp_complete_set_callbacks(nupp_complete_callback callbacks[4]);
int (*nupp_complete_get_row(void))[4];

#endif
