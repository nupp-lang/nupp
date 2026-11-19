/**
 * @file
 * @brief Symbolic inputs and assertions shared by the CBMC harnesses.
 */

#ifndef NUPP_PROOF_INTRINSICS_H
#define NUPP_PROOF_INTRINSICS_H

#include <stddef.h>
#include <stdint.h>

/* CBMC models each call as an independent arbitrary value. */
extern unsigned char nondet_byte (void);
extern size_t nondet_size (void);
extern int64_t nondet_filesize (void);

/* Declare CBMC's reserved intrinsics for ordinary C linting. */
/* NOLINTNEXTLINE(bugprone-reserved-identifier,cert-dcl37-c) */
extern void __CPROVER_assume (_Bool condition);

/* NOLINTNEXTLINE(bugprone-reserved-identifier,cert-dcl37-c) */
extern void __CPROVER_assert (_Bool condition, const char *description);

#endif
