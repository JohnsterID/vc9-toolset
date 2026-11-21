#!/bin/bash
# check-pe-imports.sh -- Check the DLL imports of a PE file built against VC9.
#
# Usage:
#   ./test/check-pe-imports.sh <file.exe|file.dll> [+DLL ...] [-DLL ...]
#
#   +DLL  the file must import DLL (e.g. +MSVCR90.dll)
#   -DLL  the file must not import DLL (e.g. -MSVCR90D.dll)
#
# Always fails on an import from a newer Visual C++ runtime (VCRUNTIME*,
# MSVCP1xx, MSVCR1xx, ucrtbase, api-ms-win-crt-*): a link that picked up a
# newer msvcrt.lib or libcmt.lib still succeeds, and the binary then needs a
# runtime the target machine may not have.
#
# Requires llvm-objdump (on PATH or in LLVM's default folder on Windows) or a
# binutils objdump that reads PE files.
#
# Exit code:
#   0  all checks passed
#   1  a check failed or the imports could not be read

die() { echo "FAIL: $*" >&2; exit 1; }

pe="${1:-}"
[ -n "$pe" ] || die "usage: $0 <file.exe|file.dll> [+DLL ...] [-DLL ...]"
[ -f "$pe" ] || die "$pe not found"
shift

# The last candidate is LLVM's default install folder in Git Bash on Windows
objdump_bin=""
for candidate in llvm-objdump objdump "/c/Program Files/LLVM/bin/llvm-objdump.exe"; do
    if command -v "$candidate" >/dev/null 2>&1; then
        objdump_bin="$candidate"
        break
    fi
done
[ -n "$objdump_bin" ] || die "neither llvm-objdump nor objdump found"

name=$(basename "$pe")
dump=$("$objdump_bin" -p "$pe") || die "$objdump_bin could not read $name"
imports=$(printf '%s\n' "$dump" | sed -n 's/^[[:space:]]*DLL Name:[[:space:]]*//p' | tr -d '\r')
# Every Win32 PE imports at least kernel32; no names means the dump format was not understood
[ -n "$imports" ] || die "no DLL imports found in $name ($objdump_bin output not understood)"

echo "$name imports:"
printf '%s\n' "$imports" | sed 's/^/  /'

fail=0
newer=$(printf '%s\n' "$imports" | grep -i -E '^(vcruntime[0-9]|msvcp1[0-9]|msvcr1[0-9]|ucrtbase|api-ms-win-crt-)' || true)
if [ -n "$newer" ]; then
    echo "FAIL: $name imports a newer Visual C++ runtime: $(printf '%s\n' "$newer" | tr '\n' ' ')"
    fail=1
fi

for want in "$@"; do
    dll="${want#[+-]}"
    if printf '%s\n' "$imports" | grep -qixF "$dll"; then
        found=1
    else
        found=0
    fi
    case "$want" in
        +*) if [ "$found" = 1 ]; then echo "OK: $name imports $dll"
            else echo "FAIL: $name does not import $dll"; fail=1; fi ;;
        -*) if [ "$found" = 0 ]; then echo "OK: $name does not import $dll"
            else echo "FAIL: $name imports $dll"; fail=1; fi ;;
        *)  die "bad argument '$want' (use +DLL or -DLL)" ;;
    esac
done

exit $fail
