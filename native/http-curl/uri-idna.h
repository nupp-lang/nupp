#ifndef NUPP_URI_IDNA_H
#define NUPP_URI_IDNA_H

#include <stddef.h>
#include <stdint.h>

/* The URL parser passes the percent-decoded domain. The return value is its
 * ASCII size excluding the NUL, even when room is insufficient; -1 means
 * invalid input and -2 means the conversion service failed. */
int32_t nupp_uri_idna_ascii (const char *domain, size_t count, char *out,
                             size_t room);

#endif
