#!/usr/bin/env bash
# Builds dragons_crown_pro on Linux x86_64 or (in progress) macOS x86_64 incrementally (Clang, CMake + Ninja): the
# Linux and macOS counterpart of tools/build.ps1. The one build configuration, RelWithDebInfo, is what is tested and
# what an AppImage contains.
#
#   tools/build.sh            build build/cmake/<linux|macos>/bin/dragons_crown_pro
#   tools/build.sh --clean    delete build/cmake/<linux|macos> first
#   tools/build.sh --test     also build and run the focused tests
#   tools/build.sh --run [args...]   start the loader that was just built (arguments after --run go to it)
#
# Missing tools or libraries are listed; packaging/linux/ci-deps.sh installs them on Ubuntu 20.04 (the release baseline),
# docs/MACOS.md lists the Homebrew packages for macOS.
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
platform=linux
[[ $(uname -s) == Darwin ]] && platform=macos
build_dir=$root/build/cmake/$platform
config=RelWithDebInfo
clean=0 test=0 run=0
loader_args=()
while (($#)); do
    case $1 in
        --clean) clean=1 ;;
        --test) test=1 ;;
        --run) run=1; shift; loader_args=("$@"); break ;;
        -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

step() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $(uname -s) =~ ^(Linux|Darwin)$ && $(uname -m) == x86_64 ]] ||
    die 'This script builds for Linux x86_64 and macOS x86_64 only (Windows: tools\build.ps1).'

cmake_platform_args=()
if [[ $platform == macos ]]; then
    # Homebrew's LLVM (Intel Homebrew lives in /usr/local), keg-only OpenSSL, and the VMA header that Homebrew lacks.
    brew_prefix=$(brew --prefix 2>/dev/null || echo /usr/local)
    cc=${CC:-$brew_prefix/opt/llvm/bin/clang} cxx=${CXX:-$brew_prefix/opt/llvm/bin/clang++}
    export PKG_CONFIG_PATH=$brew_prefix/opt/openssl@3/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
    vma_header=$root/build/macos-deps/include/vma/vk_mem_alloc.h
    [[ -f $vma_header ]] || die "Missing $vma_header (docs/MACOS.md: VMA v3.4.0)"
    moltenvk=${DCP_MOLTENVK:-$root/build/macos-deps/lib/libMoltenVK.dylib}
    [[ -f $moltenvk ]] || die "Missing $moltenvk (docs/MACOS.md: MoltenVK 1.4.2; or set DCP_MOLTENVK)"
    cmake_platform_args+=("-DCMAKE_PREFIX_PATH=$brew_prefix;$brew_prefix/opt/openssl@3;$root/build/macos-deps"
                          "-DDCP_MOLTENVK=$moltenvk")
else
    cc=${CC:-clang} cxx=${CXX:-clang++}
fi
missing=()
for tool in "$cc" "$cxx" cmake ninja pkg-config git; do
    command -v "$tool" >/dev/null || missing+=("$tool")
done
command -v glslang >/dev/null || command -v glslangValidator >/dev/null || missing+=(glslang)
if command -v pkg-config >/dev/null; then
    for module in sdl3 freetype2 libpng zlib openssl libxxhash vulkan; do
        pkg-config --exists "$module" || missing+=("pkg-config:$module")
    done
fi
if ((${#missing[@]})); then
    echo "Missing: ${missing[*]}" >&2
    echo 'packaging/linux/ci-deps.sh prepares the Ubuntu 20.04 release build environment (docs/LINUX.md);' >&2
    echo 'on macOS, docs/MACOS.md lists the Homebrew packages.' >&2
    exit 1
fi

step "Toolchain $($cc --version | head -1), $config"

step 'Video core dependencies (gpu/deps.txt)'
patches_of() {
    local LC_ALL=C dir=$1 file
    PATCHES=()
    for file in "$dir"/*.patch; do
        [[ -f $file ]] || continue
        PATCHES+=("$file")
    done
}
patches_fingerprint() {
    local file hash
    (($#)) || return 0
    for file in "$@"; do
        hash=$(sha256sum < "$file" | cut -d' ' -f1)
        printf '%s:%s\n' "$(basename "$file")" "${hash^^}"
    done | sha256sum | cut -d' ' -f1 | tr 'a-f' 'A-F'
}
while read -r path url commit; do
    [[ -z ${path:-} || $path == \#* ]] && continue
    dir=$root/gpu/$path
    patches_of "$root/gpu/patches/$(basename "$path")"
    fingerprint=$(patches_fingerprint "${PATCHES[@]}")
    expected=$commit
    [[ -n $fingerprint ]] && expected=$commit$'\n'$fingerprint
    [[ -f $dir/.dcp_commit && $(<"$dir/.dcp_commit") == "$expected" ]] && continue
    echo "Fetching $path (${commit:0:7})"
    rm -rf "$dir"
    mkdir -p "$dir"
    git -C "$dir" init --quiet
    git -C "$dir" fetch --quiet --depth 1 "$url" "$commit"
    git -C "$dir" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
    [[ -f $dir/.gitmodules ]] && git -C "$dir" submodule update --quiet --init --recursive --depth 1
    for patch in "${PATCHES[@]}"; do
        git -C "$dir" apply "$patch"
    done
    printf '%s' "$expected" > "$dir/.dcp_commit"
done < "$root/gpu/deps.txt"

((clean)) && { step "Cleaning build/cmake/$platform"; rm -rf "$build_dir"; }
if ! grep -qs "CMAKE_BUILD_TYPE:STRING=$config" "$build_dir/CMakeCache.txt" || [[ ! -f $build_dir/build.ninja ]]; then
    step 'Configuring'
    cmake -S "$root" -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE=$config \
        -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" "${cmake_platform_args[@]}"
fi
step 'Building'
targets=(dragons_crown_pro)
((test)) && targets+=(dcp-launcher-tests dcp-trophy-tests dcp-cheats-tests dcp-voice-tests dcp-system-type-tests dcp-runtime-tests dcp-text-tests dcp-savedata-tests dcp-tiling-tests dcp-cursor-tests dcp-window-tests dcp-present-tests dcp-frame-pacing-tests dcp-amd-water-tests dcp-water-diag-tests dcp-ultrawide-tests dcp-ultrawide-sides-tests dcp-isa-tests dcp-update-tests dcp-net-tests dcp-online-hle-tests dcp-online-builds-tests dcp-skip-offers-tests dcp-rtc-tests)
ninja -C "$build_dir" "${targets[@]}"
loader=$build_dir/bin/dragons_crown_pro
[[ -x $loader ]] || die "Missing $loader"

if ((test)); then
    step 'Running the launcher tests'
    "$build_dir/bin/dcp-launcher-tests"
    step 'Running the trophy tests'
    "$build_dir/bin/dcp-trophy-tests"
    step 'Running the cheat tests'
    "$build_dir/bin/dcp-cheats-tests"
    step 'Running the Japanese NPC voice tests'
    "$build_dir/bin/dcp-voice-tests"
    step 'Running the online System type hook tests'
    "$build_dir/bin/dcp-system-type-tests"
    step 'Running the runtime tests (memory, fibers)'
    "$build_dir/bin/dcp-runtime-tests"
    step 'Running the text tests (text dialog, system font set)'
    "$build_dir/bin/dcp-text-tests"
    step 'Running the save-data tests (mounts, Japanese startup save hook)'
    "$build_dir/bin/dcp-savedata-tests"
    step 'Running the cursor visibility tests'
    "$build_dir/bin/dcp-cursor-tests"
    step 'Running the window fit tests'
    "$build_dir/bin/dcp-window-tests"
    step 'Running the present tests (swapchain images, present mode, flip pacing)'
    "$build_dir/bin/dcp-present-tests"
    step 'Running the frame pacing tests (Frame rate setting, repeat cadence, limiter)'
    "$build_dir/bin/dcp-frame-pacing-tests"
    step 'Running the AMD water workaround tests (vendor defaults, no hotkey)'
    "$build_dir/bin/dcp-amd-water-tests"
    step 'Running the water diagnostics tests (AMD only, deduplication, cap)'
    "$build_dir/bin/dcp-water-diag-tests"
    step 'Running the True Ultrawide hook tests'
    "$build_dir/bin/dcp-ultrawide-tests"
    step 'Running the True Ultrawide side area tests'
    "$build_dir/bin/dcp-ultrawide-sides-tests"
    step 'Running the MOVBE, BMI1 and LZCNT tests'
    "$build_dir/bin/dcp-isa-tests"
    step 'Running the tiling tests (GPU tile layouts and addresses)'
    "$build_dir/bin/dcp-tiling-tests"
    step 'Running the updater tests (versions, release JSON, SHA-256, ZIP safety, staging and rollback)'
    "$build_dir/bin/dcp-update-tests"
    step 'Running the RTC tests (Win32 file time)'
    "$build_dir/bin/dcp-rtc-tests"
    step 'Running the Skip Offer tests (synthetic and local boot images)'
    "$build_dir/bin/dcp-skip-offers-tests"
    step 'Running the online tests (JSON, identity, STUN, peer transport over loopback)'
    "$build_dir/bin/dcp-net-tests"
    step "Running the online build tests (every supported build's online imports, one lobby game, cheat lock)"
    "$build_dir/bin/dcp-online-builds-tests"
    step 'Running the online HLE tests (needs DCP_TEST_LOBBY; skipped without it)'
    "$build_dir/bin/dcp-online-hle-tests"
fi

view=$root/game/prepared/v1.03 image=$root/build/image/v1.03
if [[ -f $view/.dcp_view.json ]]; then
    if [[ ! -f $image/boot.bin || $view/.dcp_view.json -nt $image/boot.bin ||
          $root/launcher/boot_image.cpp -nt $image/boot.bin || $root/launcher/game_profile.h -nt $image/boot.bin ]]; then
        step 'Updating the boot image'
        "$loader" --prepare-image "$view" "$image"
    fi
else
    echo 'The game is not installed yet: start the loader and use Install game... on the launcher'\''s Play page.'
fi
printf '\nBuilt %s\n' "$loader"
((run)) || exit 0
cd -- "$(dirname -- "$loader")"
exec "$loader" "${loader_args[@]}"
