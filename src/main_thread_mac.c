/* macOS main-thread jobs (main_thread_mac.h). One job at a time: the launcher, then the game window, whose
 * event loop never returns. */
#include "main_thread_mac.h"
#include <pthread.h>
#include <stddef.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static void (*job)(void *);
static void *job_arg;
static unsigned long finished; /* jobs completed, so a waiter knows its own has run */

void dcp_main_thread_run(void (*fn)(void *), void *arg, int wait) {
    if (pthread_main_np()) {
        fn(arg);
        return;
    }
    pthread_mutex_lock(&lock);
    while (job) pthread_cond_wait(&changed, &lock);
    job = fn;
    job_arg = arg;
    const unsigned long mine = finished + 1;
    pthread_cond_broadcast(&changed);
    if (wait)
        while (finished < mine) pthread_cond_wait(&changed, &lock);
    pthread_mutex_unlock(&lock);
}

void dcp_main_thread_serve(void) {
    for (;;) {
        pthread_mutex_lock(&lock);
        while (!job) pthread_cond_wait(&changed, &lock);
        void (*fn)(void *) = job;
        void *arg = job_arg;
        pthread_mutex_unlock(&lock);
        fn(arg);
        pthread_mutex_lock(&lock);
        job = NULL;
        ++finished;
        pthread_cond_broadcast(&changed);
        pthread_mutex_unlock(&lock);
    }
}
