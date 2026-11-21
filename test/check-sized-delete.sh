#!/bin/bash
# check-sized-delete.sh -- Check whether an object built from test/smoke.cpp
#                          calls the sized operator delete and delete[].
#
# Usage:
#   ./test/check-sized-delete.sh <file.obj> yes|no
#
#   yes  both operator delete(void*, size_t) and operator delete[](void*,
#        size_t) are referenced (clang 19 and later, C++14 and later): the
#        link needs compat/vc9_runtime_stubs.cpp
#   no   neither is referenced (C++11, clang 18, -fno-sized-deallocation or
#        /Zc:sizedDealloc-)
#
# Requires llvm-nm (on PATH or in LLVM's default folder on Windows).
#
# Exit code:
#   0  as expected
#   1  not as expected, or the symbols could not be read

die() { echo "FAIL: $*" >&2; exit 1; }

obj="${1:-}"
expect="${2:-}"
[ -f "$obj" ] || die "usage: $0 <file.obj> yes|no"
case "$expect" in yes|no) ;; *) die "usage: $0 <file.obj> yes|no" ;; esac

# The last candidate is LLVM's default install folder in Git Bash on Windows
nm_bin=""
for candidate in llvm-nm "/c/Program Files/LLVM/bin/llvm-nm.exe"; do
    if command -v "$candidate" >/dev/null 2>&1; then
        nm_bin="$candidate"
        break
    fi
done
[ -n "$nm_bin" ] || die "llvm-nm not found"

name=$(basename "$obj")
undefined=$("$nm_bin" -u "$obj") || die "$nm_bin could not read $name"
[ -n "$undefined" ] || die "no undefined symbols in $name"

# MSVC mangling, x86 (unsigned int) and x64 (unsigned __int64)
scalar=$(printf '%s\n' "$undefined" | grep -c -E '\?\?3@YAXPE?AX(I|_K)@Z' || true)
array=$(printf '%s\n' "$undefined" | grep -c -E '\?\?_V@YAXPE?AX(I|_K)@Z' || true)
echo "$name: sized operator delete referenced: $scalar, sized operator delete[]: $array"

if [ "$expect" = yes ]; then
    if [ "$scalar" -eq 0 ] || [ "$array" -eq 0 ]; then die "$name: expected both sized deletes"; fi
else
    if [ "$scalar" -ne 0 ] || [ "$array" -ne 0 ]; then die "$name: expected no sized delete"; fi
fi
echo "OK: $name sized delete = $expect"
