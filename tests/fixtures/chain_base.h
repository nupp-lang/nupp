/**
 * @file
 * @brief Exercises dependency ordering across a chain of C typedefs.
 *
 * Alphabetical order reverses the dependency order. The importer must emit
 * each underlying typedef before the name that uses it.
 */

typedef unsigned long long __zz_chain_base_t;
typedef __zz_chain_base_t __aa_chain_mid_t;
typedef __aa_chain_mid_t chain_size_t;
