// SPDX-License-Identifier: GPL-2.0-or-later
// macOS: small POSIX helpers the renderer uses for diagnostics and thread identity, which
// glibc provides on Linux. Force-included into the GPU library on macOS only (CMakeLists.txt).
#pragma once
#ifdef __APPLE__
#include <pthread.h>
#ifdef __cplusplus
extern "C" {
#endif
// The low 32 bits of the system-wide thread id: what Linux's gettid() and Windows'
// GetCurrentThreadId() give the renderer (compared, logged, never passed to the kernel).
static inline int gettid(void) {
    unsigned long long id = 0;
    pthread_threadid_np(NULL, &id);
    return (int)id;
}
#ifdef __cplusplus
}
#endif
#endif
