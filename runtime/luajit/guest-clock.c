/* A C call prevents LuaJIT from hoisting a host-updated mailbox clock load. */
double nupp_browser_clock(const void *address) {
    return *(const volatile double *)address;
}
