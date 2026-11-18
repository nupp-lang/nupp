#ifndef NUPP_CORE_TRANSPORT_H
#define NUPP_CORE_TRANSPORT_H
#include <stdint.h>
uint64_t nupp_io_start(uint64_t threads);
uint64_t nupp_io_submit(uint64_t kind, uint64_t word, uint64_t base,
                        uint64_t bytes);
uint64_t nupp_io_take(void);
uint64_t nupp_io_finish(uint64_t ticket, uint64_t out, uint64_t room);
uint64_t nupp_io_cancel(uint64_t ticket);
uint64_t nupp_io_settle(uint64_t ticket);
#endif
