#!/bin/bash
# extract-vc9.sh — Extract VC9 SP1 toolchain on any platform (Linux, macOS, WSL)
#
# No msiexec, no Mount-DiskImage, no admin rights needed.
# Uses 7z to extract ISOs/EXEs/CABs, and msiextract (msitools) for MSIs.
#
# Usage:
#   ./extract-vc9.sh [destination_dir]
#   ./extract-vc9.sh --include-debug-crt [destination_dir]
#   ./extract-vc9.sh --setup-dir=<dir> [destination_dir]   (use or fill a fetch-vc9.sh folder, e.g. a CI cache)
#
# Prerequisites:
#   7z          — p7zip-full (Debian/Ubuntu), 7-zip (Windows), p7zip (macOS)
#   msiextract  — msitools (Debian/Ubuntu), msitools (macOS Homebrew)
#   curl, sha256sum or shasum
#
# What gets extracted (~343 MB base):
#   VC/bin/           VC9 SP1 compiler (cl.exe 15.0.30729.1), linker, assembler
#   VC/bin/x86_amd64/ x64 cross-compiler
#   VC/include/       C++ STL, CRT, TR1, ATL headers
#   VC/lib/           x86 libs (msvcrt.lib, msvcprt.lib, etc.)
#   VC/lib/amd64/     x64 libs
#   WinSDK/Include/   Windows SDK 7.0 headers (windows.h, etc.)
#   WinSDK/Lib/       Windows SDK 7.0 x86 libs (kernel32.lib, user32.lib, etc.)
#   WinSDK/Lib/x64/   Windows SDK 7.0 x64 libs
#   MSBuild/v90/      MSBuild toolset files (.props/.targets)
#
# Optional (--include-debug-crt, ~23 MB from VS2008 SP1):
#   VC/lib/           debug CRT libs (msvcrtd.lib, libcmtd.lib, etc.)
#   VC/redist/Debug_NonRedist/x86/Microsoft.VC90.DebugCRT/
#                     msvcr90d.dll, msvcp90d.dll, msvcm90d.dll
#
# Sources:
#   Base: Windows SDK 7.0 ISO (1.48 GB download)
#   Add-ons: VS2008 SP1 ISO (832 MB download)
# MSBuild v90 files are bundled in this repository (8 KB, from VS2010).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Downloads (URLs, sizes, SHA-256) are in fetch-vc9.sh
SP1_MSP_NAME="VC90sp1-KB947888-x86-enu.msp"

# --- Parse arguments ---
INCLUDE_DEBUG_CRT=0
DEST=""
SETUP_DIR=""
for arg in "$@"; do
    case "$arg" in
        --include-debug-crt) INCLUDE_DEBUG_CRT=1 ;;
        --setup-dir=*) SETUP_DIR="${arg#--setup-dir=}" ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) DEST="$arg" ;;
    esac
done
if [ -z "$DEST" ]; then
    DEST="$SCRIPT_DIR/vc9sp1"
fi

# --- Helpers ---
die() { echo "ERROR: $*" >&2; exit 1; }

check_prereqs() {
    command -v 7z >/dev/null 2>&1 || die "7z not found. Install: apt install p7zip-full (Debian/Ubuntu), brew install 7-zip (macOS)"
    command -v msiextract >/dev/null 2>&1 || die "msiextract not found. Install: apt install msitools (Debian/Ubuntu), brew install msitools (macOS)"
    command -v curl >/dev/null 2>&1 || die "curl required"
}

# --- Main ---
check_prereqs

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "=== VC9 SP1 Extractor (cross-platform) ==="
echo "Destination: $DEST"
echo ""

# ============================================
# Step 1: VC9 SP1 compiler + Windows SDK 7.0
# ============================================
echo "[1/3] Extracting VC9 SP1 + Windows SDK 7.0..."

# Download, verify and keep only the setup folders (skipped for what SETUP_DIR already has)
[ -n "$SETUP_DIR" ] || SETUP_DIR="$TEMP_DIR/setup"
FETCH_ARGS=()
[ "$INCLUDE_DEBUG_CRT" -eq 1 ] && FETCH_ARGS+=(--include-debug-crt)
bash "$SCRIPT_DIR/fetch-vc9.sh" "${FETCH_ARGS[@]}" "$SETUP_DIR" || die "Failed to fetch the VC9 SP1 setup files"
SDK7_SETUP="$SETUP_DIR/sdk70/Setup"

echo "  Extracting vc_stdx86.msi (compiler + headers + libs)..."
msiextract "$SDK7_SETUP/vc_stdx86/vc_stdx86.msi" -C "$TEMP_DIR/vc9_raw" > /dev/null 2>&1 \
    || die "Failed to extract vc_stdx86.msi"

echo "  Extracting WinSDKBuild_x86.msi (Windows SDK headers + libs)..."
msiextract "$SDK7_SETUP/WinSDKBuild/WinSDKBuild_x86.msi" -C "$TEMP_DIR/winsdk_raw" > /dev/null 2>&1 \
    || die "Failed to extract WinSDKBuild_x86.msi"

# ============================================
# Reorganize into clean layout
# ============================================
echo "  Organizing file layout..."
mkdir -p "$DEST"

# VC compiler, headers, libs
# msiextract creates: "Program Files/Microsoft Visual Studio 9.0/VC:Vc7/{bin,include,lib,...}"
# The ":Vc7" suffix is an MSI component artifact — rename to just "VC"
VC_RAW="$TEMP_DIR/vc9_raw/Program Files/Microsoft Visual Studio 9.0/VC:Vc7"
if [ ! -d "$VC_RAW" ]; then
    die "Expected VC9 directory not found after extraction. Check msiextract output."
fi

mkdir -p "$DEST/VC"
cp -a "$VC_RAW/bin" "$DEST/VC/bin"
cp -a "$VC_RAW/include" "$DEST/VC/include"
mkdir -p "$DEST/VC/lib"
find "$VC_RAW/lib" -maxdepth 1 -type f -exec cp {} "$DEST/VC/lib/" \;
if [ -d "$VC_RAW/lib/amd64" ]; then
    cp -a "$VC_RAW/lib/amd64" "$DEST/VC/lib/amd64"
fi
if [ -d "$VC_RAW/redist" ]; then
    cp -a "$VC_RAW/redist" "$DEST/VC/redist"
fi
rm -rf "$TEMP_DIR/vc9_raw"

# Windows SDK headers and libs
SDK_RAW="$TEMP_DIR/winsdk_raw/Program Files/Microsoft SDKs/Windows/v7.0"
if [ -d "$SDK_RAW" ]; then
    mkdir -p "$DEST/WinSDK"
    cp -a "$SDK_RAW/Include" "$DEST/WinSDK/Include"
    mkdir -p "$DEST/WinSDK/Lib"
    find "$SDK_RAW/Lib" -maxdepth 1 -type f -exec cp {} "$DEST/WinSDK/Lib/" \;
    if [ -d "$SDK_RAW/Lib/x64" ]; then
        cp -a "$SDK_RAW/Lib/x64" "$DEST/WinSDK/Lib/x64"
    fi
fi
rm -rf "$TEMP_DIR/winsdk_raw"

# ============================================
# Step 2: MSBuild v90 toolset (from repo)
# ============================================
echo ""
echo "[2/3] Installing MSBuild v90 toolset files..."

MSBUILD_SRC="$SCRIPT_DIR/MSBuild/v90"
if [ -d "$MSBUILD_SRC" ]; then
    mkdir -p "$DEST/MSBuild/v90"
    cp "$MSBUILD_SRC/Microsoft.Cpp.Win32.v90.props" "$DEST/MSBuild/v90/"
    cp "$MSBUILD_SRC/Microsoft.Cpp.Win32.v90.targets" "$DEST/MSBuild/v90/"
    echo "  Copied from repo: MSBuild/v90/"
else
    echo "  WARNING: MSBuild/v90/ not found in repo at $MSBUILD_SRC"
    echo "  The extracted toolchain will work for command-line builds but not MSBuild."
fi

# ============================================
# Step 3: Case-insensitive symlinks (Linux)
# ============================================
echo ""
echo "[3/3] Creating case-insensitive symlinks for Linux..."

_symcount=0

# Phase 1: Lowercase symlinks for all header/lib files and subdirectories
for _dir in "$DEST/VC/include" "$DEST/WinSDK/Include"; do
    [ -d "$_dir" ] || continue
    for _f in "$_dir"/*; do
        [ -f "$_f" ] || [ -L "$_f" ] || continue
        _base=$(basename "$_f")
        _lower=$(echo "$_base" | tr '[:upper:]' '[:lower:]')
        if [ "$_base" != "$_lower" ] && [ ! -e "$_dir/$_lower" ]; then
            ln -s "$_base" "$_dir/$_lower"
            _symcount=$((_symcount + 1))
        fi
    done
    # Subdirectories (e.g. CodeAnalysis → codeanalysis)
    for _d in "$_dir"/*/; do
        [ -d "$_d" ] || continue
        _base=$(basename "$_d")
        _lower=$(echo "$_base" | tr '[:upper:]' '[:lower:]')
        if [ "$_base" != "$_lower" ] && [ ! -e "$_dir/$_lower" ]; then
            ln -s "$_base" "$_dir/$_lower"
            _symcount=$((_symcount + 1))
        fi
    done
done

# Phase 2: Scan headers for #include references with different case
# (e.g. kernelspecs.h includes "DriverSpecs.h" but file is driverspecs.h)
for _dir in "$DEST/VC/include" "$DEST/WinSDK/Include"; do
    [ -d "$_dir" ] || continue
    grep -rh '#include' "$_dir" 2>/dev/null \
        | sed -n 's/.*#include[[:space:]]*[<"]\([^>"]*\)[>"].*/\1/p' \
        | sed 's|.*[/\\]||' \
        | sort -u \
        | while read -r _ref; do
            [ -z "$_ref" ] && continue
            [ -e "$_dir/$_ref" ] && continue
            _match=$(find "$_dir" -maxdepth 1 -iname "$_ref" -print -quit 2>/dev/null)
            if [ -n "$_match" ]; then
                ln -s "$(basename "$_match")" "$_dir/$_ref" 2>/dev/null
            fi
        done
done

# Phase 3: Lowercase symlinks for lib files
for _dir in "$DEST/VC/lib" "$DEST/VC/lib/amd64" "$DEST/WinSDK/Lib" "$DEST/WinSDK/Lib/x64"; do
    [ -d "$_dir" ] || continue
    for _f in "$_dir"/*; do
        [ -f "$_f" ] || [ -L "$_f" ] || continue
        _base=$(basename "$_f")
        _lower=$(echo "$_base" | tr '[:upper:]' '[:lower:]')
        if [ "$_base" != "$_lower" ] && [ ! -e "$_dir/$_lower" ]; then
            ln -s "$_base" "$_dir/$_lower"
            _symcount=$((_symcount + 1))
        fi
    done
done

echo "  Created $_symcount+ case-insensitive symlinks"

# ============================================
# Optional: Debug CRT from VS2008 SP1
# ============================================
if [ "$INCLUDE_DEBUG_CRT" -eq 1 ]; then
    echo ""
    echo "[SP1] Extracting Debug CRT from VS2008 SP1..."

    echo "  Extracting VC90 SP1 MSP (this may take a moment)..."
    7z x "$SETUP_DIR/sp1/$SP1_MSP_NAME" -o"$TEMP_DIR/sp1msp" -y > /dev/null \
        || die "Failed to extract VC90 SP1 MSP"

    MSP="$TEMP_DIR/sp1msp"

    echo "  Installing debug CRT libs..."
    mkdir -p "$DEST/VC/lib"

    # Debug CRT libs → VC/lib/
    _dbg_count=0
    for _map in \
        "FL_msvcrtd_lib_:msvcrtd.lib" \
        "FL_msvcprtd_lib_:msvcprtd.lib" \
        "FL_libcmtd_lib_:libcmtd.lib" \
        "FL_libcpmtd_lib_:libcpmtd.lib" \
        "FL_libcmtd_pdb_:libcmtd.pdb" \
        "FL_libcpmtd_pdb_:libcpmtd.pdb"; do
        _pattern="${_map%%:*}"
        _target="${_map##*:}"
        _src=$(find "$MSP" -maxdepth 1 -name "${_pattern}*" -print -quit)
        if [ -n "$_src" ]; then
            cp "$_src" "$DEST/VC/lib/$_target"
            _dbg_count=$((_dbg_count + 1))
        else
            echo "  WARNING: ${_target} not found in SP1 MSP"
        fi
    done

    # Debug CRT DLLs → VC/redist/Debug_NonRedist/x86/Microsoft.VC90.DebugCRT/
    _dbg_dll_dir="$DEST/VC/redist/Debug_NonRedist/x86/Microsoft.VC90.DebugCRT"
    mkdir -p "$_dbg_dll_dir"
    for _map in \
        "FL_msvcr90_d_dll_:msvcr90d.dll" \
        "FL_msvcp90_d_dll_:msvcp90d.dll" \
        "FL_msvcm90_d_dll_:msvcm90d.dll" \
        "FL_Microsoft_VC90_DebugCRT_manifest_:Microsoft.VC90.DebugCRT.manifest"; do
        _pattern="${_map%%:*}"
        _target="${_map##*:}"
        _src=$(find "$MSP" -maxdepth 1 -name "${_pattern}*" -print -quit)
        if [ -n "$_src" ]; then
            cp "$_src" "$_dbg_dll_dir/$_target"
            _dbg_count=$((_dbg_count + 1))
        fi
    done
    echo "  Installed $_dbg_count debug CRT files"

    rm -rf "$TEMP_DIR/sp1msp"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "=== Extraction Complete ==="
echo ""
echo "Layout:"
echo "  $DEST/"
echo "  ├── VC/bin/           cl.exe (15.0.30729.1), link.exe, ml.exe, ..."
echo "  │   └── x86_amd64/   x64 cross-compiler"
echo "  ├── VC/include/       C++ STL, CRT, TR1 headers"
echo "  ├── VC/lib/           x86 libs (msvcrt.lib, ...)"
echo "  │   └── amd64/        x64 libs"
echo "  ├── WinSDK/Include/   windows.h, winnt.h, ..."
echo "  ├── WinSDK/Lib/       kernel32.lib, user32.lib, ... (x86)"
echo "  │   └── x64/          x64 SDK libs"
echo "  └── MSBuild/v90/      .props + .targets for MSBuild"
echo ""

TOTAL=$(find "$DEST" -type f | wc -l)
SIZE=$(du -sh "$DEST" | cut -f1)
echo "Total: $TOTAL files, $SIZE"
