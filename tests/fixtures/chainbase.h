/**
 * @file
 * @brief Exercises dependency ordering across a chain of C typedefs.
 *
 * Test fixture for nupp import-c: a typedef chain whose alphabetical order is
 * the reverse of the order C can read it in. Sorting these to make the output
 * deterministic makes every one of them unparseable. The reserved names are
 * a system header's, on purpose.
 * NOLINTBEGIN(bugprone-reserved-identifier,cert-dcl37-c)
 */

typedef unsigned long long __zz_chain_base_t;
typedef __zz_chain_base_t __aa_chain_mid_t;
typedef __aa_chain_mid_t chain_size_t;
/* NOLINTEND(bugprone-reserved-identifier,cert-dcl37-c) */
