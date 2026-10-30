# macOS port (Intel)

**Status: phase 1 in progress.** `tools/build.sh` builds `build/cmake/macos/bin/dragons_crown_pro` on an Intel Mac and
the launcher starts (Metal renderer); the game has not been installed or booted yet. The memory, thread and fault code
compiles but has not run, and guest-visible heap objects still come from `malloc` (above 1 TiB). This page records what is known about running the port natively on an Intel
Mac, the tools the build needs, what has been checked on real hardware, and the order of work. Apple silicon is out
of scope for now: the game's own x86-64 code runs directly on the host CPU, so an Arm Mac would need Rosetta 2.
Upstream shadPS4 runs that way, so an Intel build may later work under Rosetta, but nothing here has been tried there.

The approach is the Linux port's ([LINUX.md](LINUX.md)): the same loader, runtime and video core, with `#if
defined(__APPLE__)` branches beside the existing `_WIN32` and Linux ones, and no refactors.

## Target machine

| | |
| --- | --- |
| Model | Hackintosh reporting as iMac19,1, macOS 15.4 (24E248) |
| CPU | Intel Core i7-9700K: AVX2, LZCNT, BMI1/BMI2, MOVBE (nothing needs emulating, `isa_emulate.c` stays idle) |
| GPU | AMD Radeon RX 6600 XT, 8 GB, Metal 3, through MoltenVK |
| RAM | 32 GB |
| Homebrew | Intel, under `/usr/local` (not `/opt/homebrew`) |

## Tools

### Already installed

| Tool | Version | Notes |
| --- | --- | --- |
| Homebrew LLVM (`clang`, `clang++`) and `lld` | 23.1.4 | `/usr/local/opt/llvm/bin`. Use it instead of Apple clang 17, as SpeedBreaker does: same compiler family as the Windows and Linux builds |
| Xcode | | the macOS SDK, `codesign`, Metal tools |
| CMake, Ninja, pkgconf | 4.4.4, 1.13.2, 3.0.8 | the project needs CMake 3.24 |
| git, GNU bash, coreutils | 2.56, 5.3, 9.7 | the build scripts use bash 4+ features and `sha256sum` |
| SDL3 | 3.4.18 | Linux pins 3.4.16 |
| FreeType, libpng, OpenSSL 3 (libcrypto), xxHash | 2.14, 1.6.59, 3.6.3, 0.8.3 | zlib comes from the macOS SDK |
| Vulkan headers and loader, glslang, SPIRV-Tools | 1.4.363, 16.6.0, 1.4.363 | |
| molten-vk (Homebrew) | 1.2.11 | **Too old**: advertises Vulkan 1.2, and the video core needs 1.3. See below |

### To install

```bash
brew install fmt boost zydis robin-map vulkan-tools vulkan-validationlayers
```

| Package | Why |
| --- | --- |
| `fmt` | video core logging. Homebrew has 12.x; Linux pins 9.1.0. If 12 breaks the shadPS4 code, build 9.1.0 into a private prefix as `packaging/linux/ci-deps.sh` does |
| `boost` | headers only (Linux pins 1.83; Homebrew's 1.92 should do) |
| `zydis` (pulls in `zycore-c`) | x86 decoder for the video core and guest patching |
| `robin-map` | `tsl-robin-map` CMake package |
| `vulkan-tools`, `vulkan-validationlayers` | `vulkaninfo` and validation while debugging; not needed to build |
| VMA `vk_mem_alloc.h` | not in Homebrew. Fetch the header at the Linux pin (`v3.4.0`, SHA-256 in `ci-deps.sh`) into `<prefix>/include/vma/` |

### MoltenVK 1.4.2

Use the Khronos MoltenVK 1.4.2 release (the macOS release archive from
https://github.com/KhronosGroup/MoltenVK/releases), not Homebrew's Intel bottle. The SpeedBreaker Intel port already
has a copy at `speedbreaker/tools/Cellar/molten-vk/1.4.2/lib/libMoltenVK.dylib` (universal, x86_64 + arm64).

The build should ship the dylib with its own `MoltenVK_icd.json` next to the game and point the Vulkan loader at it
(`VK_ICD_FILENAMES`, set by the game before `vkCreateInstance`), so a system MoltenVK never gets picked up.
SpeedBreaker's `runtime/CMakeLists.txt` does this with `-DSB_MOLTENVK=<libMoltenVK.dylib>`.

## What has been checked

A small Vulkan probe was run on the RX 6600 XT against both MoltenVK builds.

| | Homebrew 1.2.11 | Khronos 1.4.2 |
| --- | --- | --- |
| Instance at Vulkan 1.3 | fails (`VK_ERROR_INCOMPATIBLE_DRIVER`) | device reports **1.3.357** |
| Required: `VK_KHR_swapchain`, `VK_KHR_push_descriptor`, `VK_EXT_vertex_attribute_divisor`, `VK_EXT_robustness2` | | **all present** |
| `maxComputeWorkGroupCount[0]` | | 1,073,741,824: the detiler's dispatch of more than 65535 groups (LINUX.md) is fine here |
| `geometryShader` / `tessellationShader` | | 0 / 1 |
| Present (optional) | | `present_wait`, `external_memory_host`, `memory_budget`, `maintenance5`, `maintenance8`, `extended_dynamic_state3`, `depth_clip_control`, `shader_stencil_export`, `shader_atomic_float`, `fragment_shader_barycentric` |
| Missing (optional) | | `custom_border_color`, `depth_clip_enable`, `vertex_input_dynamic_state`, `primitive_topology_list_restart`, `provoking_vertex`, `image_2d_view_of_3d`, `image_view_min_lod`, `depth_range_unrestricted` |

No geometry shaders is not a blocker: rect and quad lists are drawn with tessellation control shaders
([vk_graphics_pipeline.cpp](../gpu/shadps4/video_core/renderer_vulkan/vk_graphics_pipeline.cpp), `RectListTCS`), and
real ES/GS draws are skipped with a warning ([vk_pipeline_cache.cpp](../gpu/shadps4/video_core/renderer_vulkan/vk_pipeline_cache.cpp)).
Whether Dragon's Crown Pro issues any GS draws is still to be seen in the log. The missing optional extensions may
show up as small visual differences: borders on samplers with custom colours, depth clipping, provoking vertex on
flat-shaded primitives.

## Learnings from SpeedBreaker

SpeedBreaker (`../speedbreaker`, commits `49d8017` and `a7edf3e` on `mac_intel`) is an Xbox 360 static recompilation
ported to this same machine. Its CPU side is unlike this port's: it runs translated C over a guest memory array, while
this loader runs the PS4's own code at its real addresses. Its GPU and platform lessons transfer:

- **Use MoltenVK 1.4.2.** With 1.2.x on the RX 6600 XT, `R8_UNORM` images sampled as zero (green movies) and buffers
  made from imported host memory were refused with `VK_ERROR_FEATURE_NOT_PRESENT`. 1.4.2 fixed both.
- **Keep a soft fallback for host memory import.** If a driver accepts a host pointer and then refuses the buffer, log
  it and use a copy instead of asserting.
- **Fault decoding on Intel macOS:** the faulting PC is `uc_mcontext->__ss.__rip`, and the write bit is
  `uc_mcontext->__es.__err & 2`. Without the error code every fault looks like a write.
- **Frame pacing:** keep the monitor at 60 Hz (the KG272U was found at 70-74 Hz), which matches the game's fixed 60 Hz
  logic. `VK_KHR_present_wait` is present on 1.4.2.
- **Guest memory sits in system RAM:** with no CPU-visible VRAM reported, the GPU reads it over PCIe. Measure before
  assuming 1440p and 4K are free.
- **Debugging:** `MVK_CONFIG_DEBUG=1` logs the generated MSL; `MTL_DEBUG_LAYER=1 MTL_DEBUG_LAYER_ERROR_MODE=nslog`
  turns on Metal API validation. Writing frames to files, then converting them with `sips -s format png`, checks
  rendering without watching the screen.

## What differs from Linux

Each row is a place where the Linux code uses something macOS does not have.

| Area | Linux today | macOS plan |
| --- | --- | --- |
| Build gate | [CMakeLists.txt](../CMakeLists.txt) stopped on anything but Windows or Linux x86_64 | done: macOS x86_64 allowed; `tools/build.sh` has a macOS branch (Homebrew LLVM, keg-only OpenSSL, VMA header in `build/macos-deps`). Run the launcher with `VK_ICD_FILENAMES` naming MoltenVK 1.4.2's ICD until it is bundled |
| Non-PIE build | `-fno-pie` / `-no-pie` keeps the brk heap below 1 TiB | not supported on modern macOS, and there is no brk heap to rely on anyway. Build PIE and fix the heap explicitly (next row) |
| Host heap the guest sees | `mallopt(M_ARENA_MAX,1)` and `M_MMAP_THRESHOLD` in [loader.c](../src/loader.c) keep `malloc` low | macOS `malloc` returns `0x6000...` and `0x7f...` addresses, which do not fit the guest's 40-bit fields. Add a `runtime_low_alloc` / `runtime_low_free` over `runtime_low_map` memory and use it for every object handed to the guest. Starting list: `runtime_thread.c` (TLS blocks, `GuestThread`, `ThreadAttr`), `runtime_mutex.c` (attrs, mutexes, conds), `runtime_sema.c`, `runtime_rwlock.c`, `runtime_eventflag.c`, `runtime_fiber.c`. A debug check that any pointer returned to the guest is below 1 TiB catches the ones missed |
| Guest TCB | `arch_prctl(ARCH_SET_GS)` per thread ([runtime_thread.c](../src/runtime_thread.c)) | GS belongs to the pthread TSD array and cannot be moved. Do what Windows does: create a `pthread_key_t` at startup and have [loader.c](../src/loader.c) `patch_tcb_loads` rewrite `mov rax, gs:[0]` to `gs:[8*key]` (the same 9-byte instruction, another displacement). `runtime_thread_tcb_offset()` returns `8*key`; each thread does `pthread_setspecific(key, tcb)` |
| Address reservation | `MAP_FIXED_NOREPLACE` for `[64 GiB, 1 TiB)` and `[32 GiB, 64 GiB)` ([runtime_memory.c](../src/runtime_memory.c)) | `mach_vm_allocate` / `mach_vm_map` with `VM_FLAGS_FIXED`, which fails when the range is taken, the same contract. The 4 GiB `__PAGEZERO` is below both ranges, so it can stay |
| Guest memory backing | one sparse `memfd_create` file, mapped twice for aliasing; `fallocate` punches holes so released pages read as zero | a Mach memory entry (`mach_make_memory_entry_64`) mapped with `mach_vm_map` into both views, as shadPS4's macOS address space does; or `shm_open` + `shm_unlink` + one `ftruncate`. Released pages must still read as zero: decide between remapping a fresh entry over the range and clearing it |
| GPU write tracking | `userfaultfd` write protection ([page_manager.cpp](../gpu/shadps4/video_core/page_manager.cpp)), `mprotect` fallback | `mprotect` + the fault handler only. Correct, slower; measure |
| Fault handler | `uc_mcontext.gregs[REG_RIP]` etc. ([loader.c](../src/loader.c)) | `uc_mcontext->__ss.__rip` and friends, write bit from `__es.__err`; expect both `SIGSEGV` and `SIGBUS`. [signal_context.cpp](../gpu/shadps4/common/signal_context.cpp) already has the Apple branch. Under LLDB: `process handle SIGSEGV SIGBUS -n false -p true -s false` |
| Thread list for crash dumps | `/proc/self/task` via `SYS_getdents64`, then `SYS_tgkill` | `task_threads()` and `pthread_kill` over the runtime's own thread registry |
| Thread ids, names | `gettid`, `pthread_setname_np(thread, name)` | `pthread_threadid_np`; `pthread_setname_np(name)` names only the calling thread. [thread.cpp](../gpu/shadps4/common/thread.cpp) has the Apple branch |
| Timed locks | `pthread_mutex_timedlock`, `pthread_rwlock_timedrdlock` / `timedwrlock` | not in macOS: emulate with a condition variable or a bounded `trylock` loop |
| Sleeps | `clock_nanosleep` ([runtime_audio.c](../src/runtime_audio.c)) | `nanosleep`, or `mach_wait_until` for absolute deadlines |
| Embedded data | `.incbin` in ELF `.section` syntax (fonts, overlay assets) | Mach-O section names (`__DATA,__const`) and leading-underscore symbols |
| Fibers | assembly context switch (System V) | the same System V code in Mach-O syntax |
| Executable path | `/proc/self/exe` ([paths.cpp](../launcher/paths.cpp), loader) | `_NSGetExecutablePath` |
| Data folders | next to the AppImage, `$XDG_DATA_HOME` fallback | next to the `.app` while developing; `~/Library/Application Support/DragonsCrownProPC` for a packaged app |
| Launcher | `zenity` / `kdialog` or the built-in chooser, `xdg-open`, X11 Shift check | SDL3's native file dialog or the built-in chooser, `open`, Shift from `CGEventSourceFlagsState` |
| Updater | downloads the Windows ZIP or the AppImage | off on macOS until there is a macOS release asset |
| Vulkan | loader finds the system driver | ship MoltenVK 1.4.2 and its ICD next to the game; enable `VK_KHR_portability_enumeration` ([vk_platform.cpp](../gpu/shadps4/video_core/renderer_vulkan/vk_platform.cpp) has the Apple surface code) |

The calling convention needs no work: PS4 code uses the System V x86-64 ABI, which is also macOS's, so the Windows
build's `sysv_abi` thunks have nothing to do here.

## Gameplan

Each phase ends with a check that can be run, so a failure shows up in the phase that caused it.

| Phase | Work | Done when | Estimate |
| --- | --- | --- | --- |
| 0. Tools | install the packages above; MoltenVK 1.4.2 with its ICD; the Vulkan probe | probe passes (done for the required features) | done, apart from the installs |
| 1. Build | CMake Apple branch, the macOS branch of `tools/build.sh`, compile and link fixes from the table: embedded data, paths, thread names, timed locks, sleeps | the launcher opens, installs a `.pkg`, and **the boot image is byte-identical** to the one the Windows and Linux builds make | 2-4 days |
| 2. Runtime | Mach address reservation, memory backing and aliasing, low heap allocator, fibers, fault handler | `dcp-runtime-tests` pass (reservation, mapping, protection, executable pages, aliasing, fibers across threads) | 1-1.5 weeks |
| 3. Boot | guest TCB through a pthread key, the below-1 TiB pointer audit, crash dumps, Vulkan device and swapchain on MoltenVK | the LINUX.md first-boot list: window, device, guest start-up, threads, audio, keyboard, logo, save-data dialog, title menu | 1-2 weeks |
| 4. Play | rendering fixes on MoltenVK; frame pacing with `present_wait`; GPU write tracking speed; controllers | a full stage at a steady 60 fps at 1080p, saves and the shader cache written, no validation errors new to macOS | 1-3 weeks |
| 5. Package | `.app` with MoltenVK, ICD and dylibs inside; ad hoc signing; launcher Mac paths | the app runs from Finder on a clean user account | about 1 week |

That is about 3-7 weeks of part-time work for a playable personal build. Most of the remaining risk is on the CPU side:
any host pointer above 1 TiB that reaches the guest corrupts state without failing straight away. The GPU side is
de-risked by the probe and by SpeedBreaker running on the same card.

## Rules

- `#if defined(__APPLE__)` branches next to the existing ones; Windows and Linux behaviour unchanged.
- No game files, keys or derived data in the repository (`game/`, `user/`, boot images).
- Record anything found on the way here: what was tried, what fixed it, what it ruled out.
