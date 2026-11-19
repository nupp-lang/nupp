/* The entry of a program binary linked from libnupp_vm_program.a. A
 * program's object defines a nonempty table; without one the weak empty
 * definition links nothing and vector code is refused at startup. */

#include <stddef.h>
#include <stdint.h>

/* The length of the image hash the table carries. */
#define NUPP_AOT_HASH_BYTES 32

/* The linked table of compiled entries, as the runner reads it
 * (nupp_vm::compiled::LinkedTable): the ABI version, the hash of the image
 * the entries were compiled from, the entries, and the frame maps and
 * program counters that go with them. Every pointer is to storage emitted
 * into the executable, readable and unchanged for the life of the process. */
struct aottable {
  uint64_t abi;
  uint8_t hash[NUPP_AOT_HASH_BYTES];
  uint64_t count;
  const uint64_t *entries;
  uint64_t mapslen;
  const uint8_t *maps;
  uint64_t pcslen;
  const uint8_t *pcs;
};

/* The Rust side declares the same layout. These hold this side to it, so a
 * change to one that misses the other fails the build rather than the
 * program. */
_Static_assert(sizeof(struct aottable) == 88, "linked table size");
_Static_assert(_Alignof(struct aottable) == 8, "linked table alignment");
_Static_assert(offsetof(struct aottable, entries) == 48, "linked entry offset");
_Static_assert(offsetof(struct aottable, maps) == 64, "linked map offset");
_Static_assert(offsetof(struct aottable, pcs) == 80, "linked PC offset");

/* The table a binary with no compiled code links: all zero, so it holds no
 * entries. A program's object replaces it with a strong definition. Its
 * name is the one the VM's code emitter and the program linker look for. */
__attribute__((weak)) const struct aottable nupp_aot_table_v1 = {0};

/* The runner, from the Rust half of the archive, which names it. */
int nupp_vm_program_main (void);

int main (void) {
  return nupp_vm_program_main();
}
