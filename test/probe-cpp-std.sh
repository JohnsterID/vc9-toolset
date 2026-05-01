#!/bin/bash
# probe-cpp-std.sh -- Probe which C++ standard levels work with the
#                      VC9 SP1 headers under clang cross-compilation.
#
# Usage:
#   ./test/probe-cpp-std.sh <vc9_root>
#   ./test/probe-cpp-std.sh /path/to/vc9sp1
#
# Requires: clang++, lld-link (e.g. apt install clang lld)
#
# Tested features per standard:
#   C++03  VC9 STL headers + TR1
#   C++11  auto, lambda, nullptr, constexpr, range-for, rvalue refs, ...
#   C++14  generic lambdas, relaxed constexpr, variable templates, ...
#   C++17  structured bindings, if constexpr, fold expressions, ...
#   C++20  concepts, consteval, constinit, designated initializers, ...
#   C++23  deducing this, static operator(), if consteval, ...
#
# Exit code:
#   0  all tested standards passed (compile + link)
#   1  one or more standards failed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPAT="$REPO_DIR/compat"
PROBE_SRC="$SCRIPT_DIR/cpp_std_probe.cpp"

die() { echo "ERROR: $*" >&2; exit 1; }

VC9="${1:-}"
if [ -z "$VC9" ]; then
    die "Usage: $0 <vc9_root>"
fi
[ -d "$VC9/VC/include" ] || die "VC9 headers not found at $VC9/VC/include"
[ -f "$COMPAT/vc9_compat.h" ] || die "compat header not found at $COMPAT/vc9_compat.h"
[ -f "$PROBE_SRC" ] || die "probe source not found at $PROBE_SRC"

command -v clang++ >/dev/null 2>&1 || die "clang++ not found"
command -v lld-link >/dev/null 2>&1 || die "lld-link not found"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

ARCHS="x86 x64"
STANDARDS="c++03 c++11 c++14 c++17 c++20 c++23"

_pass=0
_fail=0
_total=0

echo "=================================================================="
echo "  VC9 C++ Standard Probe"
echo "  VC9_ROOT: $VC9"
echo "  Clang:    $(clang++ --version 2>&1 | head -1)"
echo "=================================================================="
echo ""

for arch in $ARCHS; do
    if [ "$arch" = "x86" ]; then
        triple="i686-pc-windows-msvc"
        vc_lib="$VC9/VC/lib"
        sdk_lib="$VC9/WinSDK/Lib"
        machine="x86"
    else
        triple="x86_64-pc-windows-msvc"
        vc_lib="$VC9/VC/lib/amd64"
        sdk_lib="$VC9/WinSDK/Lib/x64"
        machine="x64"
    fi

    [ -d "$vc_lib" ] || { echo "  SKIP $arch (libs not found at $vc_lib)"; continue; }

    echo "--- $arch ($triple) ---"

    # Compile runtime stubs once per arch
    stubs_obj="$TMPDIR/vc9_stubs_${arch}.obj"
    clang++ --target="$triple" \
        -fms-compatibility -fms-extensions \
        -isystem "$VC9/VC/include" \
        -c "$COMPAT/vc9_runtime_stubs.cpp" -o "$stubs_obj" 2>/dev/null \
        || die "Failed to compile runtime stubs for $arch"

    for std in $STANDARDS; do
        _total=$((_total + 1))
        label="$arch $std"
        obj="$TMPDIR/probe_${arch}_${std}.obj"
        exe="$TMPDIR/probe_${arch}_${std}.exe"

        # Compile
        compile_out=$(clang++ --target="$triple" -std="$std" \
            -fms-compatibility -fms-extensions \
            -fdelayed-template-parsing \
            -Wno-delayed-template-parsing-in-cxx20 \
            -include "$COMPAT/vc9_compat.h" \
            -U_MSC_VER -D_MSC_VER=1500 \
            -isystem "$VC9/VC/include" -isystem "$VC9/WinSDK/Include" \
            -c "$PROBE_SRC" -o "$obj" 2>&1)
        if [ $? -ne 0 ]; then
            echo "  FAIL  $label  (compile)"
            echo "$compile_out" | head -5 | sed 's/^/        /'
            _fail=$((_fail + 1))
            continue
        fi

        # Count which sections passed from #pragma message output
        nsections=$(echo "$compile_out" \
            | grep -c 'PASS \[-W#pragma-messages\]' || true)

        # Link
        link_out=$(lld-link /OUT:"$exe" /MACHINE:"$machine" \
            /SUBSYSTEM:CONSOLE /ENTRY:mainCRTStartup \
            /LIBPATH:"$vc_lib" /LIBPATH:"$sdk_lib" \
            "$obj" "$stubs_obj" \
            msvcrt.lib msvcprt.lib kernel32.lib 2>&1)
        if [ $? -ne 0 ]; then
            echo "  FAIL  $label  (link)"
            echo "$link_out" | head -5 | sed 's/^/        /'
            _fail=$((_fail + 1))
            continue
        fi

        _pass=$((_pass + 1))
        echo "  PASS  $label  ($nsections sections)"
    done
    echo ""
done

echo "=================================================================="
echo "  Results: $_pass/$_total passed, $_fail failed"
echo "=================================================================="

if [ "$_fail" -gt 0 ]; then
    exit 1
fi
exit 0
