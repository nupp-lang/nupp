/* The entry of a program binary linked from libnupp_vm_program.a. A
 * program's object defines a nonempty table; without one the weak empty
 * definition links nothing and vector code is refused at startup. */
#include <stdint.h>

struct nupp_aot_table {
    uint64_t abi;
    uint8_t hash[32];
    uint64_t count;
    const uint64_t *entries;
    uint64_t maps_len;
    const uint8_t *maps;
};

__attribute__((weak)) const struct nupp_aot_table nupp_aot_table = {0};

int nupp_vm_program_main(void);

int main(void) {
    return nupp_vm_program_main();
}
