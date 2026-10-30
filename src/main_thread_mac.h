/* macOS: AppKit, and so SDL video, only works on the process's main thread. The loader runs on a thread of
 * its own and hands the launcher and the game window to the main thread through these calls. */
#ifndef DCP_MAIN_THREAD_MAC_H
#define DCP_MAIN_THREAD_MAC_H
#ifdef __APPLE__
#ifdef __cplusplus
extern "C" {
#endif
/* Runs fn(arg) on the main thread; with wait, returns once it has finished. On the main thread it just calls fn. */
void dcp_main_thread_run(void (*fn)(void *), void *arg, int wait);
/* The main thread's loop: runs what dcp_main_thread_run hands it, one job at a time. Never returns. */
void dcp_main_thread_serve(void);
#ifdef __cplusplus
}
#endif
#endif
#endif
