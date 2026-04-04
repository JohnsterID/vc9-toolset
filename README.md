# VC9 SP1 Installer

Installs Visual C++ 2008 SP1 (`PlatformToolset=v90`) for use with Visual Studio 2010-2022.

## Quick Start

```powershell
# Run as Administrator
.\install-vc9.ps1
```

## What It Does

1. Downloads **Windows SDK 7.0** and installs VC9 SP1 compiler (15.0.30729.1)
2. Installs MSBuild v90 toolset files (bundled in this repository)
3. Sets up registry keys and environment for MSBuild (works with all VS versions)

## Requirements

- Windows 10/11
- Visual Studio 2010 or later (any edition)
- PowerShell 5.1+
- [7-Zip](https://www.7-zip.org/) in PATH
- ~1.5 GB free disk space for download (can be cleaned up after)

## Pre-downloaded ISO

If you already have the ISO, place it next to the script to skip downloading:

```
install-vc9.ps1
GRMSDK_EN_DVD.iso      (1.48 GB - SDK 7.0)
```

The script checks for local files first, then cached downloads, then downloads fresh.

## What Gets Installed

| Component | Version | Source | Installed Size |
|-----------|---------|--------|----------------|
| VC9 x86 compiler | 15.0.30729.1 | SDK 7.0 | ~50 MB |
| VC9 x64 cross-compiler | 15.0.30729.1 | SDK 7.0 | ~50 MB |
| MSBuild v90 toolset | - | bundled | 8 KB |

## Installation Paths

```
C:\Program Files (x86)\Microsoft Visual Studio 9.0\
├── Common7\Tools\
│   └── vsvars32.bat         # Environment setup script
└── VC\
    ├── bin\cl.exe           # Compiler
    ├── include\             # Headers (with TR1)
    └── lib\                 # Libraries

C:\Program Files (x86)\MSBuild\Microsoft.Cpp\v4.0\Platforms\Win32\PlatformToolsets\v90\
├── Microsoft.Cpp.Win32.v90.props
└── Microsoft.Cpp.Win32.v90.targets
```

The legacy MSBuild path (`v4.0\Platforms`) is checked by all Visual Studio versions (2010-2022).

## Environment Variables

The script sets:

| Variable | Value |
|----------|-------|
| `VS90COMNTOOLS` | `C:\Program Files (x86)\Microsoft Visual Studio 9.0\Common7\Tools\` |

Registry keys for MSBuild:
- `HKLM\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0\Setup\VC\ProductDir`
- `HKLM\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0\Setup\VS\ProductDir`

## Sources

Microsoft's original SDK 7.0 download link is no longer available. The ISO is downloaded from the Wayback Machine:

| File | Size | Source |
|------|------|--------|
| SDK 7.0 | 1.48 GB | [web.archive.org](https://web.archive.org/web/20161230154527/http://download.microsoft.com/download/2/E/9/2E911956-F90F-4BFB-8231-E292A7B6F287/GRMSDK_EN_DVD.iso) |
| MSBuild v90 | 8 KB | bundled in `MSBuild/v90/` (originally from VS2010) |

⚠️ **Warning**: The [archive.org GRMSDK**X** item](https://archive.org/download/grmsdkx-en-dvd/GRMSDK_EN_DVD.iso) is SDK **7.1** (VC10/cl 16.0) — do **not** use that. The correct SDK 7.0 ISO is 1.48 GB from the Wayback Machine URL above.

## Optional: MFC Feature Pack

```powershell
.\install-vc9.ps1 -IncludeMFC
```

Adds MFC Feature Pack (Office 2007-style ribbon UI, docking panes, visual managers).  
Source: VS2008 SP1 (~900 MB download, ~100 MB installed)

## Troubleshooting

### "Platform Toolset v90 cannot be found"
Re-run `install-vc9.ps1` as Administrator.

### "Cannot open include file: 'array'"
VC9 not installed correctly. Check that `cl.exe` exists:
```cmd
dir "C:\Program Files (x86)\Microsoft Visual Studio 9.0\VC\bin\cl.exe"
```

### 7-Zip not found
Install 7-Zip and ensure it's in your PATH:
```powershell
winget install 7zip.7zip
```

## Linux / Cross-Platform Extraction

For Linux, macOS, or WSL (no admin rights, no Windows required):

```bash
# Prerequisites
sudo apt install p7zip-full msitools   # Debian/Ubuntu
# brew install 7-zip msitools           # macOS

./extract-vc9.sh ~/vc9sp1
```

This extracts the full toolchain to a portable directory (~343 MB, ~2950 files) and
automatically creates case-insensitive symlinks so headers resolve correctly on Linux:

```
vc9sp1/
├── VC/bin/           cl.exe (15.0.30729.1), link.exe, ml.exe
│   └── x86_amd64/   x64 cross-compiler
├── VC/include/       C++ STL, CRT, TR1 headers
├── VC/lib/           x86 libs (msvcrt.lib, msvcprt.lib, ...)
│   └── amd64/        x64 libs
├── WinSDK/Include/   windows.h, winnt.h, etc.
├── WinSDK/Lib/       kernel32.lib, user32.lib, etc. (x86)
│   └── x64/          x64 SDK libs
└── MSBuild/v90/      .props + .targets for MSBuild
```

### CMake FetchContent

Use with CMake to download and extract at configure time (requires CMake 3.19+):

```cmake
include(FetchContent)
FetchContent_Declare(vc9_toolset
    GIT_REPOSITORY https://github.com/JohnsterID/vc9-msbuild-toolset.git
    GIT_TAG        main
)
FetchContent_MakeAvailable(vc9_toolset)

vc9_setup("${CMAKE_BINARY_DIR}/vc9sp1")

# Path variables:
#   VC9_ROOT, VC9_BIN_DIR, VC9_INCLUDE_DIRS, VC9_LIB_DIRS,
#   WINSDK_INCLUDE_DIR, WINSDK_LIB_DIR
#
# Cross-compilation helpers:
#   VC9_COMPAT_HEADER       — compat/vc9_compat.h  (SAL/driver annotation stubs)
#   VC9_RUNTIME_STUBS_SRC   — compat/vc9_runtime_stubs.cpp (link-time stubs)
#   VC9_CLANG_COMPILE_FLAGS — ready-made flag list for clang cross-compilation
```

The `vc9_setup()` function (from `vc9-toolset.cmake`) runs `extract-vc9.sh` on first
configure, then caches the result. Subsequent configures skip extraction.

### Clang Cross-Compilation from Linux

Cross-compile Windows PE32 binaries from Linux using `clang` + `lld-link` with the
extracted VC9 headers and libs.

**Prerequisites:** `clang`, `lld` (e.g. `apt install clang-19 lld-19`)

#### Quick start (command line)

```bash
VC9=~/vc9sp1
COMPAT=/path/to/vc9-msbuild-toolset/compat

# Compile C
clang --target=i686-pc-windows-msvc \
  -fms-compatibility -fms-extensions \
  -include "$COMPAT/vc9_compat.h" \
  -U_MSC_VER -D_MSC_VER=1500 \
  -isystem "$VC9/VC/include" -isystem "$VC9/WinSDK/Include" \
  -c myfile.c -o myfile.obj

# Compile C++
clang++ --target=i686-pc-windows-msvc \
  -fms-compatibility -fms-extensions -fdelayed-template-parsing \
  -include "$COMPAT/vc9_compat.h" \
  -U_MSC_VER -D_MSC_VER=1500 \
  -isystem "$VC9/VC/include" -isystem "$VC9/WinSDK/Include" \
  -c myfile.cpp -o myfile.obj

# Compile runtime stubs (needed for C++ linking)
clang++ --target=i686-pc-windows-msvc \
  -fms-compatibility -fms-extensions \
  -isystem "$VC9/VC/include" \
  -c "$COMPAT/vc9_runtime_stubs.cpp" -o vc9_stubs.obj

# Link (C)
lld-link /OUT:myapp.exe /MACHINE:x86 /SUBSYSTEM:CONSOLE /ENTRY:mainCRTStartup \
  /LIBPATH:"$VC9/VC/lib" /LIBPATH:"$VC9/WinSDK/Lib" \
  myfile.obj msvcrt.lib kernel32.lib

# Link (C++ — add vc9_stubs.obj and C++ runtime libs)
lld-link /OUT:myapp.exe /MACHINE:x86 /SUBSYSTEM:CONSOLE /ENTRY:mainCRTStartup \
  /FORCE:MULTIPLE \
  /LIBPATH:"$VC9/VC/lib" /LIBPATH:"$VC9/WinSDK/Lib" \
  myfile.obj vc9_stubs.obj msvcrt.lib msvcprt.lib kernel32.lib
```

#### CMake toolchain file

```cmake
# toolchain-clang-vc9.cmake
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_C_COMPILER_TARGET i686-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET i686-pc-windows-msvc)
set(CMAKE_LINKER lld-link)

# cmake -DCMAKE_TOOLCHAIN_FILE=toolchain-clang-vc9.cmake \
#        -DVC9_ROOT=/path/to/vc9sp1 ..
```

### Compat layer explained

The `compat/` directory handles two categories of issues when using VC9/SDK 7.0
headers with clang on Linux:

| File | When needed | What it fixes |
|------|-------------|---------------|
| `vc9_compat.h` | Always (compile-time) | SAL annotation paths, `__drv_*` driver macros, `_CRT_SECURE_NO_WARNINGS` |
| `vc9_runtime_stubs.cpp` | C++ linking only | `__std_terminate`, sized `operator delete`, magic-static init (`_Init_thread_*`) |

Use `vc9_compat.h` via `-include compat/vc9_compat.h` (one flag) instead of 30+
individual `-D` flags on the command line.

## See Also

- [Community-Patch-DLL](https://github.com/JohnsterID/Community-Patch-DLL) - Example project using v90
- [archaic-msvc/msvc900](https://github.com/archaic-msvc/msvc900) - Pre-extracted VC9 toolchain (RTM, not SP1)
