// dcp: GPU-side assertion failures stop the port with exit code 23.
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include "common/assert.h"
#include "common/logging/log.h"

#ifndef _WIN32
// The loader's log reader (runtime_log_posix.c) drains stderr through a pipe: flush it before _Exit, or the
// assertion message is lost. Weak, as tests link this library without the runtime.
extern "C" __attribute__((weak)) void runtime_log_flush(void);
#endif

void assert_fail_impl() {
    std::fflush(stdout);
    std::fputs("STOP: GPU library assertion failed (see GPU log above)\n", stderr);
#ifndef _WIN32
    if (runtime_log_flush) {
        runtime_log_flush();
    }
#endif
    std::_Exit(23);
}

[[noreturn]] void unreachable_impl() {
    assert_fail_impl();
    throw std::runtime_error("Unreachable code");
}

void assert_fail_debug_msg(const char* msg) {
    LOG_CRITICAL(Debug, "Assertion Failed!\n{}", msg);
    assert_fail_impl();
}
