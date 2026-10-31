# macOS port TODO

The single list of work left on the macOS port. [MACOS.md](MACOS.md) is the record of what was found; this is what
remains. Tick items off and move them to [Done](#done) with the date, and add new ones here, in the same change as the
work. Windows and Linux work belongs to [upstream](https://github.com/saulob/dragons-crown-pro-pc).

## Now

- [ ] **Play a session on v0.9.0.** The rebased build has only had a 45 s unattended boot. Check a cutscene ending, the
  launcher with no update banner, sprites, backgrounds and the UI for anything missing or spiky, and a good stretch of
  play.
- [ ] **Retest leaving the tavern.** It crashed once on thread cancel, and the fix has not been exercised since. Watch
  the log for `scePthreadCancel ... waited` and `STOP: scePthreadCancel`.
- [ ] **Measure VRAM use.** Every touched 256 MiB arena page is allocated in full (`DENSE_ARENAS`); the use has never
  been measured. Do it during the session above.

## Next

- [ ] **Host heap above 1 TiB.** Objects handed to the guest (TLS blocks, thread, mutex, semaphore, rwlock, event flag
  and fiber handles) still come from `malloc`, at `0x6000...` and `0x7f...` addresses that do not fit the guest's 40-bit
  pointer fields. Nothing has failed from it yet, but it is the likeliest cause of a hard-to-explain crash. Fix: a
  `runtime_low_alloc` over `runtime_low_map` memory, plus a debug check on pointers returned to the guest.
- [ ] **Thread cancel.** A running thread gets up to 2 s to finish ([runtime_thread.c](../src/runtime_thread.c)). If the
  log shows one is a long-running worker, real cancellation is needed.
- [ ] **A full stage and a full playthrough.** Gameplan phase 4: steady 60 FPS, with saves and the shader cache written.
- [ ] **Package an `.app`.** MoltenVK and the Homebrew dylibs inside, ad hoc signed, data in
  `~/Library/Application Support/DragonsCrownProPC`, and a CA file for `wss://`: `system_ca_bundle` knows only Linux
  paths, so online currently relies on Homebrew OpenSSL's own. Must run from Finder on a clean account.

## Later

- [ ] **Online play on a Mac.** It builds and its loopback tests pass, but it has never been run on a Mac, or against a
  lobby in `dcp-online-hle-tests` and the cross-build rooms. The lobby is upstream's production service, so first ask
  the upstream maintainer whether Mac clients are welcome there.
- [ ] **A macOS platform name.** `net::platform_name` has no macOS case, so a Mac shows other players `Linux`. Check that
  the lobby accepts a new value before changing it.
- [ ] **Hold Shift for the launcher.** `ShiftHeldAtStart` handles Windows and X11 only, so on macOS `--launcher` is the
  only way back. The launcher's text and the docs for the other platforms still mention Shift.
- [ ] **The updater.** The launcher skips its update check on macOS. If the fork publishes Mac builds, point it at them
  (`launcher/update_config.cpp`) and teach it the `.app` layout.
- [ ] **Apple silicon under Rosetta 2.** Untested, and needs an Arm Mac; see [Apple silicon](MACOS.md#apple-silicon).

## Fork

- [ ] **Decide what visitors see.** The fork's default branch is `main`, which matches upstream, so the macOS README is
  only visible on `feature/macos-intel`. Either make that the default branch or merge it into the fork's `main`.
- [ ] **Turn on Issues on the fork**, then link them from the README's "Reporting problems".
- [ ] **Launcher links.** `launcher/game_profile.h` still names the upstream repository on the About page, so Mac users
  are sent to the wrong place to report problems. The sponsor link should stay upstream's.
- [ ] **Offer the work upstream?** The branch keeps Windows and Linux behaviour unchanged, so it could become a PR.
- [ ] **Delete `backup/macos-intel-pre-v0.9.0`** (local only) and `HANDOVER-macos.md` when they are no longer needed.

## Watch

Nothing to do unless these show up.

- **Rect lists drawn indirectly.** Only `DrawRecord` trims partial patches, not `DrawIndirectRecord`; an indirect rect
  list with a spare vertex would bring the cutscene smear back. None has been seen.
- **The MoltenVK rect cause.** Patch rounding is the likely mechanism behind the smear, but it was never confirmed in
  MoltenVK's source, and it does not explain the smear's 45° edge.
- **A 1 s stall at native 1080p.** Seen once in about 45 s, with no shader compile behind it.
- **`Present: Skipping frame!`** A few times per run (swapchain acquire failed twice). It repeats a frame.
- **GPU workarounds.** Zeroed placeholders for null descriptors, no `coherent` buffers, `robustBufferAccess` 1.0 instead
  of 2. Wrong pixels or flicker would point here.
- **Unsupported formats.** `R5G6B5`, `B4G4R4A4`, `A1R5G5B5` and `D16S8` are unsupported on AMD under Metal, per the
  start-up warnings.
- **Log noise.** MoltenVK warns "Metal does not support disabling primitive restart" on many draws; harmless.

## Done

- 2026-10-31: forked to `vorno-crole/dragons-crown-pro-pc`; README, this list and the upstream sync steps added.
- 2026-10-31: launcher update check off on macOS.
- 2026-10-31: rebased on v0.9.0; online code and LZCNT tests build on macOS.
- 2026-10-31: the smear at the end of cutscenes fixed (rect list patches).
- 2026-10-31: 60 FPS confirmed at native 1080p.
- 2026-10-30: triangle fans drawn as lists, 20 to 60 FPS.
