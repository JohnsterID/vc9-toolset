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
- [7-Zip](https://www.7-zip.org/) in PATH (required on headless/Server; desktop falls back to Mount-DiskImage)
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
| VC9 x86 compiler + tools | 15.0.30729.1 | SDK 7.0 | 25 MB |
| VC9 x64 cross-compiler | 15.0.30729.1 | SDK 7.0 | 7 MB |
| VC9 CRT/STL/TR1 headers | SP1 | SDK 7.0 | 5 MB |
| VC9 libs (x86 + x64) | SP1 | SDK 7.0 | 161 MB |
| Windows SDK 7.0 headers | 7.0 | SDK 7.0 | 91 MB |
| Windows SDK 7.0 libs (x86 + x64) | 7.0 | SDK 7.0 | 53 MB |
| CRT runtime DLLs (release) | 9.0.30729.1 | SDK 7.0 | 2 MB |
| MSBuild v90 toolset | 4.0 | bundled | 8 KB |
| **Total (base)** | | | **~343 MB** |
| Debug CRT libs + DLLs *(optional)* | SP1 | VS2008 SP1 | 23 MB |

## Installation Paths

```
C:\Program Files (x86)\Microsoft Visual Studio 9.0\
├── Common7\Tools\
│   └── vsvars32.bat         # Environment setup script
└── VC\
    ├── bin\cl.exe           # Compiler
    ├── include\             # Headers (with TR1)
    └── lib\                 # Libraries

C:\Program Files (x86)\Microsoft SDKs\Windows\v7.0\
├── Include\                 # Windows SDK headers (windows.h, etc.)
└── Lib\                     # Windows SDK libs (kernel32.lib, user32.lib, etc.)
```

MSBuild toolset files are installed to **both** legacy and modern paths:

```
# Legacy (VS2010-2015):
C:\Program Files (x86)\MSBuild\Microsoft.Cpp\v4.0\Platforms\Win32\PlatformToolsets\v90\
├── Microsoft.Cpp.Win32.v90.props
└── Microsoft.Cpp.Win32.v90.targets

# VS2017+ (per-install, found via vswhere):
<VS Install>\MSBuild\Microsoft\VC\v170\Platforms\Win32\PlatformToolsets\v90\
├── Toolset.props            # Generated with v170-specific properties
└── Toolset.targets          # Generated with CppCommon.targets import
```

## Environment Variables

The script sets:

| Variable | Value |
|----------|-------|
| `VS90COMNTOOLS` | `C:\Program Files (x86)\Microsoft Visual Studio 9.0\Common7\Tools\` |

Registry keys for MSBuild:
- `HKLM\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0\Setup\VC\ProductDir`
- `HKLM\SOFTWARE\Wow6432Node\Microsoft\VisualStudio\9.0\Setup\VS\ProductDir`

## Sources

| File | Size | Provides | Download |
|------|------|----------|----------|
| SDK 7.0 | 1.48 GB | VC9 SP1 compiler, CRT/STL, x64 cross-compiler, WinSDK | [Wayback Machine](https://web.archive.org/web/20161230154527/http://download.microsoft.com/download/2/E/9/2E911956-F90F-4BFB-8231-E292A7B6F287/GRMSDK_EN_DVD.iso) |
| VS2008 SP1 | 832 MB | Debug CRT (optional `--include-debug-crt`) | [microsoft.com](https://download.microsoft.com/download/a/3/7/a371b6d1-fc5e-44f7-914c-cb452b4043a9/VS2008SP1ENUX1512962.iso) |
| MSBuild v90 | 8 KB | `.props` + `.targets` for `PlatformToolset=v90` | bundled in `MSBuild/v90/` |

Microsoft's original SDK 7.0 download link is no longer available; the ISO is sourced
from the Wayback Machine.

### Why these ISOs?

**Windows SDK 7.0** bundles the VC9 SP1 compiler (cl.exe 15.0.30729.1) with the full
Windows SDK — headers, libs, x64 cross-compiler, PGO, and OpenMP — all in one
1.48 GB download.  The alternative (VS2008 Express SP1, 749 MB) uses the same x86
compiler binary but is missing x64/IA64 cross-compilers, PGO tools, OpenMP, and
ships fewer libs (23 vs 29 in `VC/lib`).  Express also lacks a Windows SDK —
you'd need a second download.

**VS2008 SP1 ISO** is only needed for debug CRT (`/MDd`, `/MTd`).  The base SDK
ships release CRT only.  The SP1 ISO contains a `.msp` patch with the debug libs
(`msvcrtd.lib`, `libcmtd.lib`, etc.) and debug runtime DLLs (`MSVCR90D.dll`).

**MSBuild v90 toolset files** are the stock `.props` and `.targets` from Visual
Studio 2010 (byte-identical to the originals in `vs_setup.cab`, dated 2009-11-11).
These enable MSBuild to locate the VC9 compiler via registry keys when a project
sets `<PlatformToolset>v90</PlatformToolset>`.

⚠️ **Warning**: The [archive.org GRMSDK**X** item](https://archive.org/download/grmsdkx-en-dvd/GRMSDK_EN_DVD.iso) is SDK **7.1** (VC**10**/cl 16.0, 568 MB) — do **not** use it. The correct SDK 7.0 ISO is 1.48 GB from the Wayback Machine URL above.

## Optional Add-ons (from VS2008 SP1)

The base install (Windows SDK 7.0) includes the compiler and release CRT libs.
The optional debug CRT comes from a single additional download — the **VS2008 SP1**
ISO (832 MB, see [Sources](#sources) for the URL).

### Debug CRT

```powershell
.\install-vc9.ps1 -IncludeDebugCRT
```

Adds debug CRT libs (`msvcrtd.lib`, `libcmtd.lib`, etc.) and debug runtime DLLs
(`MSVCR90D.dll`, `MSVCP90D.dll`).  Enables `/MDd` and `/MTd` configurations for
debug heap validation, CRT assertions, and iterator debugging (~23 MB installed).
See [CRT configuration](#crt-configuration).

## Troubleshooting

### "Platform Toolset v90 cannot be found"
Re-run `install-vc9.ps1` as Administrator.

### "Cannot open include file: 'array'"
VC9 not installed correctly. Check that `cl.exe` exists:
```cmd
dir "C:\Program Files (x86)\Microsoft Visual Studio 9.0\VC\bin\cl.exe"
```

### cl.exe crashes with STATUS_DLL_NOT_FOUND (0xC0000135)
`cl.exe` depends on `mspdb80.dll`, `mspdbcore.dll`, `msobj80.dll`, and `mspdbsrv.exe`, which the SDK MSI installs to `Common7\IDE` instead of `VC\bin`. The install script automatically copies these to `VC\bin` (Step 2). If you installed VC9 manually, copy them yourself:
```cmd
copy "%ProgramFiles(x86)%\Microsoft Visual Studio 9.0\Common7\IDE\mspdb80.dll" "%ProgramFiles(x86)%\Microsoft Visual Studio 9.0\VC\bin\"
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
    GIT_REPOSITORY https://github.com/JohnsterID/vc9-toolset.git
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
#   VC9_CLANG_LINK_LIBS     — CRT + kernel32 link libs for selected VC9_CRT
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
COMPAT=/path/to/vc9-toolset/compat

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

# Link (C++)
lld-link /OUT:myapp.exe /MACHINE:x86 /SUBSYSTEM:CONSOLE /ENTRY:mainCRTStartup \
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
| `vc9_compat.h` | Always (compile-time) | SAL annotation paths, `__drv_*` driver macros, CRT runtime macros (`_DLL`, `_MT`; see [CRT configuration](#crt-configuration)), `_CRT_SECURE_NO_WARNINGS` |
| `vc9_runtime_stubs.cpp` | C++ linking only | `__std_terminate`, sized `operator delete`, magic-static init (`_Init_thread_*`) |

Use `vc9_compat.h` via `-include compat/vc9_compat.h` (one flag) instead of 30+
individual `-D` flags on the command line.

#### CRT configuration

The compat header defaults to `/MD` (DLL runtime).  To select static CRT,
define `VC9_STATIC_CRT`:

| Config | Compile flags | Link libs | Runtime |
|--------|---------------|-----------|---------|
| `/MD` *(default)* | *(none — compat header sets `_DLL _MT`)* | `msvcrt.lib msvcprt.lib` | MSVCR90.dll, MSVCP90.dll |
| `/MT` | `-DVC9_STATIC_CRT` | `libcmt.lib libcpmt.lib` | *(static, no DLL)* |
| `/MDd` | `-D_DEBUG` | `msvcrtd.lib msvcprtd.lib` | MSVCR90D.dll, MSVCP90D.dll |
| `/MTd` | `-DVC9_STATIC_CRT -D_DEBUG` | `libcmtd.lib libcpmtd.lib` | *(static debug)* |

> **Note:** `/MDd` and `/MTd` require debug libs not included in Windows
> SDK 7.0.  See [Optional Add-ons](#optional-add-ons-from-vs2008-sp1) to
> install them from VS2008 SP1.

⚠️ **ABI constraint:** when building a DLL loaded by a host process, your
CRT configuration **must match** the host.  Mixing `/MD` and `/MT` across a
DLL boundary causes cross-heap crashes (memory allocated by one CRT freed by
another).  Standalone executables can use either configuration.

**CMake (clang cross-compile):** set `VC9_CRT` before calling `vc9_setup()`:

```cmake
set(VC9_CRT "MT")                           # /MT — static CRT
vc9_setup("${CMAKE_BINARY_DIR}/vc9sp1")

target_compile_options(mylib PRIVATE ${VC9_CLANG_COMPILE_FLAGS})
target_link_libraries(mylib PRIVATE ${VC9_CLANG_LINK_LIBS})
# VC9_CLANG_LINK_LIBS = libcmt.lib libcpmt.lib kernel32.lib (for MT)
```

Valid values: `MD` *(default)*, `MDd`, `MT`, `MTd`.  The module sets the correct
compile defines and exports matching link libs in `VC9_CLANG_LINK_LIBS`.

**MSBuild / vcxproj (native cl.exe):** set `<RuntimeLibrary>` in your project —
cl.exe handles `_DLL`/`_MT`/`_DEBUG` automatically:

| RuntimeLibrary | cl.exe switch |
|----------------|---------------|
| `MultiThreadedDLL` | `/MD` |
| `MultiThreadedDebugDLL` | `/MDd` |
| `MultiThreaded` | `/MT` |
| `MultiThreadedDebug` | `/MTd` |

Projects needing specific STL ABI settings (e.g. `_SECURE_SCL=0`,
`_HAS_ITERATOR_DEBUGGING=0`) should define those in their own headers —
they are project-specific, not toolchain-universal.

## See Also

- [Community-Patch-DLL](https://github.com/JohnsterID/Community-Patch-DLL) - Example project using v90
- [archaic-msvc/msvc900](https://github.com/archaic-msvc/msvc900) - Pre-extracted VC9 toolchain (RTM, not SP1)
