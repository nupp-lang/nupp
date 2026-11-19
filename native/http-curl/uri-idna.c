#include "uri-idna.h"

#include <string.h>

#ifdef _WIN32

#ifndef NUPP_WIN64_HTTP_SYSTEM_ICU
#error "Win64 URI mapping requires opt-in to the system ICU SDK"
#endif

#include <icu.h>

#else

#include <unicode/uidna.h>

#endif

int32_t nupp_uri_idna_ascii (const char *domain, size_t count, char *out,
                             size_t room) {
  if (!domain || !count || count > INT32_MAX || room > INT32_MAX ||
      (room && !out) || memchr(domain, 0, count)) {
    return -1;
  }

  UErrorCode status = U_ZERO_ERROR;
  UIDNA *idna = uidna_openUTS46(UIDNA_CHECK_BIDI | UIDNA_CHECK_CONTEXTJ |
                                    UIDNA_NONTRANSITIONAL_TO_ASCII,
                                &status);

  if (U_FAILURE(status)) {
    return -2;
  }

  UIDNAInfo info = UIDNA_INFO_INITIALIZER;
  int32_t size = uidna_nameToASCII_UTF8(idna, domain, (int32_t)count, out,
                                        (int32_t)room, &info, &status);
  uidna_close(idna);

  if (U_FAILURE(status) && status != U_BUFFER_OVERFLOW_ERROR) {
    return -2;
  }

  /* WHATWG turns off CheckHyphens and VerifyDnsLength. Retain all other
   * checks, including contextual joiners and invalid A-labels. */
  uint32_t ignored = UIDNA_ERROR_LEADING_HYPHEN | UIDNA_ERROR_TRAILING_HYPHEN |
                     UIDNA_ERROR_HYPHEN_3_4 | UIDNA_ERROR_EMPTY_LABEL |
                     UIDNA_ERROR_LABEL_TOO_LONG |
                     UIDNA_ERROR_DOMAIN_NAME_TOO_LONG;

  if (size <= 0 || (info.errors & ~ignored)) {
    return -1;
  }

  if ((size_t)size < room) {
    for (int32_t index = 0; index < size; index++) {
      unsigned char byte = (unsigned char)out[index];

      if (byte <= 32 || byte >= 127 || strchr("#%/:<>?@[\\]^|", byte)) {
        return -1;
      }
    }
  }

  return size;
}
