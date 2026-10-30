# macOS port (Intel)

**Status: playable, early.** On an Intel Mac the game installs from the launcher, boots, and plays its tutorial with
good graphics, sound and a PS5 controller, at about 30-40 FPS. It is not packaged yet, and longer play is largely
untested. Work is on branch `feature/macos-intel`.

The approach is the Linux port's ([LINUX.md](LINUX.md)): the same loader, runtime and video core, with
`#if defined(__APPLE__)` branches beside the existing `_WIN32` and Linux ones. Windows and Linux behaviour is
unchanged unless a section below says otherwise.

## Building and running

```bash
brew install llvm lld cmake ninja pkgconf sdl3 freetype libpng openssl@3 xxhash \
    vulkan-headers vulkan-loader glslang spirv-tools fmt boost zydis robin-map
# Not in Homebrew (both go in the git-ignored build/ folder):
#   build/macos-deps/include/vma/vk_mem_alloc.h   VMA v3.4.0 (SHA-256 in packaging/linux/ci-deps.sh)
#   build/macos-deps/lib/libMoltenVK.dylib         Khronos MoltenVK 1.4.2 or newer (or set DCP_MOLTENVK)
tools/build.sh                    # builds build/cmake/macos/bin/dragons_crown_pro
tools/build.sh --test             # also builds and runs the 17 focused test suites
build/cmake/macos/bin/dragons_crown_pro
```

The build copies MoltenVK and its ICD next to the executable, and the game points the Vulkan loader there itself: no
environment variables are needed. Install the game from the launcher's **Install game...** as on the other platforms.
`game/`, `user/` and `logs/` are created in the repository folder while running from the build tree.

## Where it stands

| Area | State |
| --- | --- |
| Build | done: Homebrew LLVM 23, x86_64, PIE |
| Focused tests | all 17 suites pass, `dcp-runtime-tests` included |
| Launcher | works: install from `.pkg`, settings, subtitle "MAC (INTEL) PORT" |
| Guest memory, threads, fibers | work (named Mach memory object, guest TCB in a pthread key) |
| Vulkan on MoltenVK 1.4.2 | works, with workarounds for missing robustness2 features, sparse buffers and a Metal compiler bug |
| Audio | works (Core Audio through SDL) |
| Input | works: keyboard, PS5 controller |
| Gameplay | tutorial played; leaving the tavern crashed once (thread cancel, fixed, awaiting a retest) |
| Frame rate | about 30-40 FPS where Windows gets 60; not profiled yet |
| Packaging | not started: runs from the build folder |
| Updater | **not adapted**: it offers the upstream release (Windows ZIP or AppImage); do not install updates from a Mac build |

### Open items

1. **Frame rate.** Profiled with `DCP_FRAME_STATS=1` over 108 windows of the first mission: median frame 33.3 ms
   (VSync holds frames that miss 16.7 ms to 30 FPS), mean 30 FPS, 5 windows at 50+. **GPU-bound**: in slow windows the
   render thread is idle 2% and blocked waiting on GPU ticks 58%; 0 write faults/s (the `mprotect` write tracking is
   not the cause); no shader compiles after start-up; 133-1442 draws per frame, median 434. The same GPU holds 60 on
   Windows (even on Intel UHD 730), so the cost is in the Metal path.
   Narrowed down since: the frame rate follows the draw count at about 70 us per draw (about 400 draws: 35 FPS, about
   650: 20 FPS); VSync off does not help, as the game paces its flips to its emulated 60 Hz (frames still snap to
   60/30/20/15). `MVK_CONFIG_PERFORMANCE_TRACKING=1` puts the time on the GPU: encoding a submission takes 3.7 ms on
   the CPU, executing one 43.9 ms on the GPU. Render passes are not the cause (8 per frame at 650 draws; counted in
   `Frame passes`). Leading suspect: rect and quad lists, the PS4's sprite primitives, are drawn through tessellation,
   which Metal does not have and MoltenVK emulates with a compute pass and an indirect draw per draw call. `Frame
   passes` now also counts rect/quad list draws per frame to confirm it.
2. **Thread cancel.** `scePthreadCancel` of a running thread stopped the game when leaving the tavern. A running thread
   now gets up to 2 s to finish ([runtime_thread.c](../src/runtime_thread.c)); if it is a long-running worker, real
   cancellation is needed.
3. **Host heap above 1 TiB.** Objects handed to the guest (TLS blocks, thread, mutex, semaphore, rwlock, event flag
   and fiber handles) still come from `malloc`, at `0x6000...` and `0x7f...` addresses that do not fit the guest's
   40-bit pointer fields. Nothing has failed from it yet; it is the most likely cause of a hard-to-explain crash. Fix:
   a `runtime_low_alloc` over `runtime_low_map` memory, plus a debug check on pointers returned to the guest.
4. **GPU workarounds to watch:** zeroed placeholders for null descriptors, no `coherent` buffers, `robustBufferAccess`
   1.0 instead of 2. Wrong pixels or flicker would point here.
5. **Dense arena memory.** Every touched 256 MiB arena page is allocated in full; VRAM use is not measured.
6. **Log noise.** MoltenVK warns "Metal does not support disabling primitive restart" on many draws; harmless.
7. **Packaging.** An `.app` with MoltenVK and the Homebrew dylibs inside, ad hoc signed; data in
   `~/Library/Application Support/DragonsCrownProPC`.
8. **Upstream.** The branch is based on v0.8.0; upstream has released v0.9.0.

## Target machine

| | |
| --- | --- |
| Model | Hackintosh reporting as iMac19,1, macOS 15.4 (24E248) |
| CPU | Intel Core i7-9700K: AVX2, LZCNT, BMI1/BMI2, MOVBE (nothing needs emulating, `isa_emulate.c` stays idle) |
| GPU | AMD Radeon RX 6600 XT, 8 GB, Metal 3, through MoltenVK |
| RAM | 32 GB |
| Display | the game window on the 60 Hz KG271U |
| Homebrew | Intel, under `/usr/local` (not `/opt/homebrew`) |

## Tools

Versions used: Homebrew LLVM and lld 23.1.4 (preferred over Apple clang 17: the same compiler family as the Windows and
Linux builds), CMake 4.4.4, Ninja 1.13.2, pkgconf 3.0.8, GNU bash 5.3 and coreutils 9.7 (the scripts need bash 4 and
`sha256sum`), SDL3 3.4.18, FreeType 2.14, libpng 1.6.59, OpenSSL 3.6.3 (keg-only; `tools/build.sh` adds its
`pkgconfig` folder), xxHash 0.8.3, Vulkan headers and loader 1.4.363, glslang 16.6.0, fmt 12.2.0 (Linux pins 9.1.0;
12 builds the video core), Boost 1.92 (headers only), Zydis 4.1.1, robin-map 1.4.1. `vulkan-tools` and
`vulkan-validationlayers` are useful for debugging and not needed to build.

**MoltenVK:** use the Khronos 1.4.2 release (https://github.com/KhronosGroup/MoltenVK/releases), not Homebrew's
Intel bottle (1.2.11), which reports Vulkan 1.2 where the video core needs 1.3. 1.2.x also sampled `R8_UNORM` images as
zero and refused imported host memory on this card (found by SpeedBreaker).

Homebrew's Zydis package links `Zycore` by name without a path; [gpu/CMakeLists.txt](../gpu/CMakeLists.txt) points
it at the `Zycore::Zycore` target.

## What differs from Linux

| Area | Linux | macOS |
| --- | --- | --- |
| Build | non-PIE so the brk heap stays below 1 TiB | PIE (macOS has neither non-PIE executables nor a brk heap); see open item 3 |
| Main thread | the loader runs the game; the game window has a thread of its own | AppKit only works on the main thread: `main` starts the loader on a 16 MiB thread, and the main thread runs the launcher and the game window's event loop ([main_thread_mac.c](../src/main_thread_mac.c)) |
| Guest TCB | `arch_prctl(ARCH_SET_GS)` per thread | GS is the pthread TSD array: the TCB is a pthread key's value, and the loader patches `mov rax, gs:[0]` to `gs:[8*key]`, as Windows does with a TEB TLS slot |
| Address reservation | `MAP_FIXED_NOREPLACE` | the address as a hint (`MAP_FIXED_NOREPLACE` is defined as 0 in [compat_mac.h](../src/compat_mac.h)); every caller checks where the mapping landed |
| Guest memory backing | one sparse `memfd`, `fallocate` hole punching | one named Mach memory object (`mach_make_memory_entry_64`, `MAP_MEM_NAMED_CREATE`); every view, host and guest, is a `mach_vm_map` of it; released pages are cleared with `memset` |
| GPU write tracking | `userfaultfd`, `mprotect` fallback | `mprotect` and the fault handler only; protection faults arrive as `SIGBUS` |
| Fault handler | `uc_mcontext.gregs[REG_RIP]` | `uc_mcontext->__ss.__rip` and friends; write bit from `__es.__err & 2` |
| Watchdog thread dump | `/proc/self/task`, `tgkill`, `process_vm_readv` | `task_threads`, `pthread_kill`, `mach_vm_read_overwrite` |
| libc gaps | | [compat_mac.h](../src/compat_mac.h): timed mutex and rwlock locks (bounded `trylock` loop), absolute `clock_nanosleep`, `CLOCK_REALTIME_COARSE`; local branches for `st_mtimespec`, `pipe2`, `getrandom` (`arc4random_buf`), `RUSAGE_THREAD`, `pthread_condattr_setclock`, `gettid` ([dcp_mac_compat.h](../gpu/shim/dcp_mac_compat.h)) |
| Embedded data, fibers | ELF `.incbin` sections, ELF assembly | `__TEXT,__const`, leading-underscore symbols |
| Executable path | `/proc/self/exe` | `_NSGetExecutablePath` |
| JSON numbers (updater) | `std::from_chars` for doubles | `strtod_l` in the C locale (libc++ has it only from macOS 26) |
| Vulkan driver | the system's | MoltenVK and its ICD next to the game (`DCP_MOLTENVK`); `VK_DRIVER_FILES` points the loader there. Both instances (the game's and the launcher's probe) ask for `VK_KHR_portability_enumeration`, and the device enables `VK_KHR_portability_subset` |
| Game window | X11 or Wayland surface | a Metal view: `SDL_Metal_GetLayer(SDL_Metal_CreateView(window))` |

## What was found on the way

**Guest memory.** Two designs failed before the named Mach memory object. POSIX shared memory (`shm_open`) can never be
executable on macOS: its maximum protection is read/write, and an RWX `mmap` silently comes back RW. A Mach memory
entry made from an existing allocation aliases whole views, but not views at an offset into it. Both were caught by
`dcp-runtime-tests`, whose `/proc/self/maps` reader now has a `mach_vm_region` counterpart.

**Robustness2.** MoltenVK 1.4.2 lists `VK_EXT_robustness2` on this card but reports none of its features
(`robustBufferAccess2`, `robustImageAccess2`, `nullDescriptor`). On macOS they are optional: null buffers (storage,
uniform, vertex) bind a zeroed 256-byte stream buffer range, null images a cleared 1x1 placeholder of the binding's view
type (`Rasterizer::NullBuffer`, `NullImageView`), and out-of-bounds accesses follow `robustBufferAccess` 1.0. An early
extension probe had checked extensions, not features, and missed this.

**Sparse buffers.** The buffer cache kept guest GPU memory in sparse arenas of up to 4 GiB, with memory bound where the
game uses it. Metal has no sparse buffers. On macOS the arenas are ordinary device-local buffers of 256 MiB pages
(`DENSE_ARENAS` in [buffer_cache.h](../gpu/shadps4/video_core/buffer_cache/buffer_cache.h)), allocated in full when first
used. `EnsureResident` only records residency and writes the BDA page table (`WritePageTable`); a migrating arena copies
the resident ranges from the arenas it replaces and points the page table at the copy. Importing guest memory directly
(`VK_EXT_external_memory_host`) would avoid the copies but changes how the cache keeps GPU and CPU copies apart.

**Metal compiler.** Apple's compiler for AMD GPUs fails on MSL `coherent device` ("Compiler encountered an internal
error"). The game's compute shader `cs_0x000000008d304694` decorates a written buffer `Coherent`, which MoltenVK
turns into `coherent`. Reproduced outside the game with `newComputePipelineStateWithFunction` on the RX 6600 XT; the same
MSL without `coherent` builds in safe and fast math. The recompiler leaves the decoration out on macOS
([spirv_emit_context.cpp](../gpu/shadps4/shader_recompiler/backend/spirv/spirv_emit_context.cpp)).

**Thread cancel.** The game cancels short-lived worker threads. On Windows they have finished by then and the cancel
returns ESRCH; on the slower Mac one was still running and the runtime stopped the game. This applies to every
platform: a running thread now gets up to 2 s to finish.

**Smaller ones.** GPU assertion messages were lost because `assert_fail_impl` called `_Exit` before the log reader
drained the stderr pipe (Linux too; it flushes now). `<mach/mach.h>` defines `round_page`, which collided with the
loader's own. The launcher tests read `loader.c`'s call order as text, so the macOS launcher wrapper sits after `main`.
ld64 only leaves a weak symbol undefined when told to (`-Wl,-U`).

## Debugging

| Tool | Use |
| --- | --- |
| `--dcp-skip-launcher` | start the game directly |
| `--timeout N` | watchdog: after N seconds, dump every thread's stack and stop (exit 142); not a crash |
| `--check-imports` | create the window and Vulkan device, load the image, resolve imports, run no game code |
| `DCP_FRAME_STATS=1` | FPS and pacing, and a breakdown of every frame over 40 ms |
| `DCP_GPU_LOG=info` | more of the video core's log (default: warnings) |
| `MVK_CONFIG_DEBUG=1` | MoltenVK prints the MSL of every shader it converts |
| `MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=nslog` | Metal API validation |

Logs are in `logs/` next to the game (`build/logs/` from the build tree). A Metal compiler failure can be reproduced
outside the game: save the MSL from `MVK_CONFIG_DEBUG=1` and build it with a few lines of Objective-C
(`newLibraryWithSource`, then `newComputePipelineStateWithFunction`, `MTLLanguageVersion3_2`). `xcrun metal` only runs the
front end, which does not reach the GPU-specific failures.

## Apple silicon

**Not natively.** The port's core runs the PS4's own x86-64 machine code directly on the CPU; an arm64 build would need
a translator for the game's code, an emulator-sized project.

**Possibly under Rosetta 2, untested.** This x86_64 build could run on an Arm Mac as it is, with Rosetta translating
both the port and the game's code:

- For: upstream shadPS4's macOS builds run this way. The guest TCB trick (`gs:[8*key]`) is the same mechanism every
  Intel Mac program uses for its thread storage, which Rosetta must support. Rosetta translates AVX and AVX2 since
  macOS 15. Guest pages are already 16 KiB, the Arm host's page size. MoltenVK ships a universal binary, and Apple GPUs
  have unified memory (no PCIe copies) and better robustness support than AMD under Metal.
- Against: the game's code is loaded and patched at run time, which Rosetta translates on its slower JIT path; the
  fault handler rewrites x86 register state under translation (GPU write tracking depends on it); Rosetta's
  instruction coverage for LZCNT and MOVBE is unverified, though the SIGILL emulation covers MOVBE and BMI1 if signals
  work; Apple GPUs have their own MoltenVK limits.

It needs an Apple silicon Mac to try; nothing here has been run there.

## Gameplan

| Phase | Done when | State |
| --- | --- | --- |
| 0. Tools | Homebrew packages, MoltenVK 1.4.2, Vulkan probe | done |
| 1. Build | launcher opens and installs a `.pkg` | done (the boot image byte comparison against Windows/Linux was skipped: no reference build) |
| 2. Runtime | `dcp-runtime-tests` pass | done |
| 3. Boot | window, device, guest start-up, threads, audio, input, title menu | done |
| 4. Play | a full stage at a steady 60 FPS, saves and shader cache written | in progress: tutorial played at 30-40 FPS; open items 1-5 |
| 5. Package | an `.app` that runs from Finder on a clean account | not started |

Phases 0-3 and the start of 4 took about two days. The estimate for the rest: about 1-3 weeks part-time for 60 FPS and
a stable full playthrough (most of it depends on what profiling shows), and about a week for packaging.

## Learnings from SpeedBreaker

SpeedBreaker (`../speedbreaker`, branch `mac_intel`) is an Xbox 360 static recompilation ported to this same machine.
Its CPU side is unlike this port's (translated C over a guest memory array), but its GPU lessons transferred: use
MoltenVK 1.4.2; keep a soft fallback for host memory import; decode Intel Mac faults from `__ss.__rip` and
`__es.__err & 2`; keep the display at 60 Hz for the game's fixed 60 Hz logic; and guest memory in system RAM is read
by a discrete GPU over PCIe, so measure before assuming high resolutions are free.

## Rules

- `#if defined(__APPLE__)` branches next to the existing ones; Windows and Linux behaviour unchanged unless a change
  fixes a shared bug (the log flush, thread cancel), and then the commit says so.
- No game files, keys or derived data in the repository (`game/`, `user/`, boot images, `rars/`).
- Record what was found here: what was tried, what fixed it, what it ruled out.
