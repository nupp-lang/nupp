/* Test fixture for nupp import-c: a typedef chain whose alphabetical order is
   the reverse of the order C can read it in. Sorting these to make the output
   deterministic makes every one of them unparseable. */

typedef unsigned long long __zz_chain_base_t;
typedef __zz_chain_base_t __aa_chain_mid_t;
typedef __aa_chain_mid_t chain_size_t;
