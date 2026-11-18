/* Test fixture for nupp import-c: a header that includes another file with
 * its own basename, from another directory. The import must keep only what
 * this file declares, not everything from a file named target.h. */

#include "same-name/target.h"

int requested_target (void);
