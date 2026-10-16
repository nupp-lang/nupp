/* The entry of a program binary linked from libnupp_vm_program.a. A
 * program's object defines a nonempty table; without one the weak empty
 * definition links nothing and vector code is refused at startup. */
#include <stdint.h>
#include <stddef.h>

struct nupp_aot_table {
    uint64_t abi;
    uint8_t hash[32];
    uint64_t count;
    const uint64_t *entries;
    uint64_t maps_len;
    const uint8_t *maps;
    uint64_t pcs_len;
    const uint8_t *pcs;
};

_Static_assert(sizeof(struct nupp_aot_table) == 88, "linked table size");
_Static_assert(_Alignof(struct nupp_aot_table) == 8, "linked table alignment");
_Static_assert(offsetof(struct nupp_aot_table, entries) == 48, "linked entry offset");
_Static_assert(offsetof(struct nupp_aot_table, maps) == 64, "linked map offset");

_Static_assert(offsetof(struct nupp_aot_table, pcs) == 80, "linked PC offset");

__attribute__((weak)) const struct nupp_aot_table nupp_aot_table_v1 = {0};

int nupp_vm_program_main(void);

int main(void) {
    return nupp_vm_program_main();
}
