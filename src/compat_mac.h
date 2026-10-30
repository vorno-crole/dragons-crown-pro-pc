/* macOS counterparts of the POSIX calls the runtime uses that Darwin's libc lacks. Included through
 * runtime.h after the C library headers, like compat_win.h, so they only stand in for calls in this
 * project's own sources. */
#ifndef DCP_COMPAT_MAC_H
#define DCP_COMPAT_MAC_H
#ifdef __APPLE__
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <time.h>

#ifndef TIMER_ABSTIME
#define TIMER_ABSTIME 1
#endif
/* No MAP_FIXED_NOREPLACE: without MAP_FIXED the address is a hint the kernel honours when the range is free,
 * and every caller checks that the mapping landed there. */
#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0
#endif
#ifndef CLOCK_REALTIME_COARSE
#define CLOCK_REALTIME_COARSE CLOCK_REALTIME
#endif

static inline int64_t compat_ns_until(clockid_t clock, const struct timespec *deadline) {
    struct timespec now;
    clock_gettime(clock, &now);
    return (int64_t)(deadline->tv_sec - now.tv_sec) * 1000000000 + (deadline->tv_nsec - now.tv_nsec);
}

/* Absolute deadlines are slept as relative ones, re-measured after each wake. */
static inline int clock_nanosleep(clockid_t clock, int flags, const struct timespec *request, struct timespec *remain) {
    if (!(flags & TIMER_ABSTIME)) return nanosleep(request, remain) ? errno : 0;
    for (int64_t left; (left = compat_ns_until(clock, request)) > 0;) {
        struct timespec step = {(time_t)(left / 1000000000), (long)(left % 1000000000)};
        if (nanosleep(&step, NULL) && errno != EINTR) return errno;
    }
    return 0;
}

/* No timed mutex or rwlock locks: try the lock until the CLOCK_REALTIME deadline, backing off from
 * 50 us to 1 ms between tries. Timed locks are rare in the game and almost never contended. */
#define COMPAT_TIMED_LOCK(try_lock, deadline)                                                    \
    do {                                                                                         \
        for (long backoff = 50000;; backoff = backoff < 1000000 ? backoff * 2 : 1000000) {     \
            int e_ = (try_lock);                                                                 \
            if (e_ != EBUSY) return e_;                                                          \
            int64_t left_ = compat_ns_until(CLOCK_REALTIME, (deadline));                         \
            if (left_ <= 0) return ETIMEDOUT;                                                    \
            struct timespec step_ = {0, left_ < backoff ? (long)left_ : backoff};                \
            nanosleep(&step_, NULL);                                                             \
        }                                                                                        \
    } while (0)
static inline int pthread_mutex_timedlock(pthread_mutex_t *mutex, const struct timespec *deadline) {
    COMPAT_TIMED_LOCK(pthread_mutex_trylock(mutex), deadline);
}
static inline int pthread_rwlock_timedrdlock(pthread_rwlock_t *lock, const struct timespec *deadline) {
    COMPAT_TIMED_LOCK(pthread_rwlock_tryrdlock(lock), deadline);
}
static inline int pthread_rwlock_timedwrlock(pthread_rwlock_t *lock, const struct timespec *deadline) {
    COMPAT_TIMED_LOCK(pthread_rwlock_trywrlock(lock), deadline);
}
#undef COMPAT_TIMED_LOCK
#endif
#endif
