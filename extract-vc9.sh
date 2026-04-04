#!/bin/bash
# extract-vc9.sh — Extract VC9 SP1 toolchain on any platform (Linux, macOS, WSL)
#
# No msiexec, no Mount-DiskImage, no admin rights needed.
# Uses 7z to extract ISOs/EXEs/CABs, and msiextract (msitools) for MSIs.
#
# Usage:
#   ./extract-vc9.sh [destination_dir]
#   ./extract-vc9.sh --include-mfc [destination_dir]
#
# Prerequisites:
#   7z          — p7zip-full (Debian/Ubuntu), 7-zip (Windows), p7zip (macOS)
#   msiextract  — msitools (Debian/Ubuntu), msitools (macOS Homebrew)
#   wget or curl
#
# What gets extracted (~343 MB):
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
# Source: Windows SDK 7.0 ISO (1.48 GB download).
# MSBuild v90 files are bundled in this repository (8 KB, from VS2010).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Configuration ---
# Windows SDK 7.0 contains VC9 SP1 (15.0.30729.1) + Windows SDK 7.0 headers/libs
# WARNING: archive.org/grmsdkx-en-dvd is SDK 7.1 (VC10) — do NOT use that.
SDK70_URL="https://web.archive.org/web/20161230154527/http://download.microsoft.com/download/2/E/9/2E911956-F90F-4BFB-8231-E292A7B6F287/GRMSDK_EN_DVD.iso"
SDK70_SIZE=1552508928
SDK70_NAME="GRMSDK_EN_DVD.iso"

# --- Parse arguments ---
INCLUDE_MFC=0
DEST=""
for arg in "$@"; do
    case "$arg" in
        --include-mfc) INCLUDE_MFC=1 ;;
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
    command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || die "wget or curl required"
}

filesize() {
    stat -L -c%s "$1" 2>/dev/null || stat -L -f%z "$1" 2>/dev/null
}

download_file() {
    local url="$1" dest="$2" expected_size="$3" name
    name=$(basename "$dest")

    # Check next to script first
    local local_file="$SCRIPT_DIR/$name"
    if [ -f "$local_file" ] && [ "$(filesize "$local_file")" = "$expected_size" ]; then
        echo "  Using local: $local_file"
        ln -sf "$local_file" "$dest" 2>/dev/null || cp "$local_file" "$dest"
        return 0
    fi

    # Check if already downloaded
    if [ -f "$dest" ] && [ "$(filesize "$dest")" = "$expected_size" ]; then
        echo "  Using cached: $dest"
        return 0
    fi

    echo "  Downloading: $name ($(( expected_size / 1048576 )) MB)"
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$dest" "$url" 2>&1 || wget -O "$dest" "$url"
    else
        curl -L --progress-bar -o "$dest" "$url"
    fi

    local size
    size=$(filesize "$dest")
    if [ "$size" != "$expected_size" ]; then
        die "Download size mismatch for $name: got $size, expected $expected_size"
    fi
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

ISO_PATH="$TEMP_DIR/$SDK70_NAME"
download_file "$SDK70_URL" "$ISO_PATH" "$SDK70_SIZE"

echo "  Extracting ISO..."
7z x "$ISO_PATH" -o"$TEMP_DIR/sdk7" -y > /dev/null || die "Failed to extract SDK ISO"
rm -f "$ISO_PATH"

echo "  Extracting vc_stdx86.msi (compiler + headers + libs)..."
msiextract "$TEMP_DIR/sdk7/Setup/vc_stdx86/vc_stdx86.msi" -C "$TEMP_DIR/vc9_raw" > /dev/null 2>&1 \
    || die "Failed to extract vc_stdx86.msi"

echo "  Extracting WinSDKBuild_x86.msi (Windows SDK headers + libs)..."
msiextract "$TEMP_DIR/sdk7/Setup/WinSDKBuild/WinSDKBuild_x86.msi" -C "$TEMP_DIR/winsdk_raw" > /dev/null 2>&1 \
    || die "Failed to extract WinSDKBuild_x86.msi"

# Free extracted ISO space
rm -rf "$TEMP_DIR/sdk7"

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
# Optional: MFC Feature Pack
# ============================================
if [ "$INCLUDE_MFC" -eq 1 ]; then
    echo ""
    echo "MFC Feature Pack extraction is not yet automated."
    echo "See: https://github.com/archaic-msvc/msvc900 (msvc900_sp1 branch)"
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
