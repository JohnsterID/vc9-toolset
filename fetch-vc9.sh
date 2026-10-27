#!/bin/bash
# fetch-vc9.sh — Download and verify the VC9 SP1 sources, keeping only the files the installers use
#
# Usage:
#   ./fetch-vc9.sh [--include-debug-crt] <setup_dir>
#
# Creates (skipping what is already there and complete):
#   <setup_dir>/sdk70/Setup/vc_stdx86/      VC9 SP1 x86 compiler, CRT, headers, libs (MSI + cabs)
#   <setup_dir>/sdk70/Setup/vc_stdamd64/    VC9 SP1 x64 cross-compiler
#   <setup_dir>/sdk70/Setup/WinSDKBuild/    Windows SDK 7.0 headers + libs
#   <setup_dir>/sp1/VC90sp1-KB947888-x86-enu.msp   (--include-debug-crt) debug CRT patch from VS2008 SP1
#
# install-vc9.ps1 -SetupDir and extract-vc9.sh --setup-dir install or extract from this folder, so it can be
# cached (the GitHub Action caches it) instead of the 1.48 GB and 832 MB ISOs.
#
# Every ISO is checked by size and SHA-256 before use: a mirror that answers 200 with an HTML page fails
# the check, and the next URL is tried. An ISO placed next to this script or in $VC9_ISO_DIR is used
# instead of downloading when it passes the same check.
#
# Prerequisites: curl, 7z, sha256sum or shasum (Linux, macOS, Git Bash on Windows)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SDK70_NAME="GRMSDK_EN_DVD.iso"
SDK70_SIZE=1552508928
SDK70_SHA256="65739fb0874cc17ea6962d8ce7915364c7161fa106ed1bf1c917924c18ac63ca"
# Microsoft no longer hosts it; two Wayback Machine captures of the same file.
# WARNING: archive.org/grmsdkx-en-dvd is SDK 7.1 (VC10) — do NOT use that.
SDK70_URLS=(
    "https://web.archive.org/web/20161230154527/http://download.microsoft.com/download/2/E/9/2E911956-F90F-4BFB-8231-E292A7B6F287/GRMSDK_EN_DVD.iso"
    "https://web.archive.org/web/20130601064541/http://download.microsoft.com/download/2/E/9/2E911956-F90F-4BFB-8231-E292A7B6F287/GRMSDK_EN_DVD.iso"
)
SDK70_FOLDERS=(vc_stdx86 vc_stdamd64 WinSDKBuild)

SP1_NAME="VS2008SP1ENUX1512962.iso"
SP1_SIZE=871700480
SP1_SHA256="580f717269faa10cf668140ef0a1a264cec194e20a0083cb0d0004a897cc675e"
SP1_URLS=(
    "https://download.microsoft.com/download/a/3/7/a371b6d1-fc5e-44f7-914c-cb452b4043a9/VS2008SP1ENUX1512962.iso"
)
SP1_MSP="vs90sp1/VC90sp1-KB947888-x86-enu.msp"

INCLUDE_DEBUG_CRT=0
DEST=""
for arg in "$@"; do
    case "$arg" in
        --include-debug-crt) INCLUDE_DEBUG_CRT=1 ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *) DEST="$arg" ;;
    esac
done
[ -n "$DEST" ] || { echo "Usage: $0 [--include-debug-crt] <setup_dir>" >&2; exit 1; }

die() { echo "ERROR: $*" >&2; exit 1; }
filesize() { stat -L -c%s "$1" 2>/dev/null || stat -L -f%z "$1"; }
sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

command -v curl >/dev/null 2>&1 || die "curl not found"
command -v 7z >/dev/null 2>&1 || die "7z not found. Install: apt install p7zip-full (Debian/Ubuntu), brew install 7-zip (macOS)"

# fetch_iso <dest> <size> <sha256> <url>...
fetch_iso() {
    local dest="$1" size="$2" hash="$3"
    shift 3
    local url got start candidate
    # An ISO already next to this script or in $VC9_ISO_DIR, if it is the right file
    for candidate in "${VC9_ISO_DIR:+$VC9_ISO_DIR/$(basename "$dest")}" "$SCRIPT_DIR/$(basename "$dest")"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ] && [ "$(filesize "$candidate")" = "$size" ] \
                && [ "$(sha256 "$candidate")" = "$hash" ]; then
            echo "  Using local: $candidate"
            ln -sf "$candidate" "$dest" 2>/dev/null || cp "$candidate" "$dest"
            return 0
        fi
    done
    for url in "$@"; do
        echo "  Downloading $(basename "$dest") ($(( size / 1048576 )) MB): $url"
        start=$SECONDS
        # curl has no read timeout: --speed-limit/--speed-time abort a stalled transfer, --retry retries it
        if ! curl -L --fail --retry 2 --retry-all-errors --connect-timeout 60 --speed-limit 1024 --speed-time 120 \
                --no-progress-meter -o "$dest" "$url"; then
            echo "  WARNING: download failed: $url" >&2
            continue
        fi
        got=$(filesize "$dest")
        if [ "$got" != "$size" ]; then
            echo "  WARNING: $got bytes, expected $size: $url" >&2
            continue
        fi
        got=$(sha256 "$dest")
        if [ "$got" != "$hash" ]; then
            echo "  WARNING: SHA-256 $got, expected $hash: $url" >&2
            continue
        fi
        echo "  OK: size and SHA-256 match ($(( SECONDS - start )) s)"
        return 0
    done
    die "no URL gave the expected $(basename "$dest")"
}

mkdir -p "$DEST"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# A folder counts as complete only after its marker is written, so an interrupted run is redone
SDK70_DIR="$DEST/sdk70"
if [ -f "$SDK70_DIR/.complete" ]; then
    echo "SDK 7.0 setup files: already in $SDK70_DIR"
else
    echo "SDK 7.0 setup files -> $SDK70_DIR"
    rm -rf "$SDK70_DIR"
    fetch_iso "$TEMP_DIR/$SDK70_NAME" "$SDK70_SIZE" "$SDK70_SHA256" "${SDK70_URLS[@]}"
    paths=()
    for f in "${SDK70_FOLDERS[@]}"; do paths+=("Setup/$f"); done
    7z x "$TEMP_DIR/$SDK70_NAME" -o"$SDK70_DIR" -y "${paths[@]}" > /dev/null || die "failed to extract the SDK 7.0 ISO"
    rm -f "$TEMP_DIR/$SDK70_NAME"
    for f in "${SDK70_FOLDERS[@]}"; do
        ls "$SDK70_DIR/Setup/$f/"*.msi > /dev/null 2>&1 || die "Setup/$f has no MSI after extraction"
    done
    echo "$SDK70_SHA256" > "$SDK70_DIR/.complete"
    echo "  $(du -sm "$SDK70_DIR" | cut -f1) MB"
fi

if [ "$INCLUDE_DEBUG_CRT" = 1 ]; then
    SP1_DIR="$DEST/sp1"
    if [ -f "$SP1_DIR/.complete" ]; then
        echo "VS2008 SP1 debug CRT patch: already in $SP1_DIR"
    else
        echo "VS2008 SP1 debug CRT patch -> $SP1_DIR"
        rm -rf "$SP1_DIR"
        fetch_iso "$TEMP_DIR/$SP1_NAME" "$SP1_SIZE" "$SP1_SHA256" "${SP1_URLS[@]}"
        7z x "$TEMP_DIR/$SP1_NAME" -o"$TEMP_DIR/sp1iso" -y "$SP1_MSP" > /dev/null || die "failed to extract the SP1 ISO"
        mkdir -p "$SP1_DIR"
        mv "$TEMP_DIR/sp1iso/$SP1_MSP" "$SP1_DIR/"
        echo "$SP1_SHA256" > "$SP1_DIR/.complete"
        echo "  $(du -sm "$SP1_DIR" | cut -f1) MB"
    fi
fi
