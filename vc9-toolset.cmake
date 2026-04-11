# vc9-toolset.cmake — CMake module for VC9 SP1 toolchain extraction
#
# Usage with FetchContent:
#
#   include(FetchContent)
#   FetchContent_Declare(vc9_toolset
#       GIT_REPOSITORY https://github.com/JohnsterID/vc9-toolset.git
#       GIT_TAG        main
#   )
#   FetchContent_MakeAvailable(vc9_toolset)
#   vc9_setup("${CMAKE_BINARY_DIR}/vc9sp1")
#
#   add_executable(myapp main.cpp ${VC9_RUNTIME_STUBS_SRC})
#   vc9_target_setup(myapp)          # ← sets includes, flags, libs in one call
#
# Or configure targets manually using the exported variables:
#
#   # Paths:  VC9_ROOT, VC9_INCLUDE_DIRS, VC9_LIB_DIRS, VC9_BIN_DIR,
#   #         WINSDK_INCLUDE_DIR, WINSDK_LIB_DIR
#   # Compat: VC9_COMPAT_HEADER      — pre-include for SAL/driver annotation stubs
#   #         VC9_RUNTIME_STUBS_SRC   — .cpp with link-time stubs (sized delete, etc.)
#   #         VC9_CLANG_COMPILE_FLAGS — ready-made flag list for add_compile_options()
#   #         VC9_CLANG_LINK_LIBS     — CRT + kernel32 link libs for the selected config
#
# Configuration (set BEFORE calling vc9_setup):
#
#   set(VC9_CRT "MD")   # /MD  — DLL runtime (default)
#   set(VC9_CRT "MDd")  # /MDd — DLL runtime, debug  (needs Optional: Debug CRT)
#   set(VC9_CRT "MT")   # /MT  — static runtime
#   set(VC9_CRT "MTd")  # /MTd — static runtime, debug (needs Optional: Debug CRT)
#
#   set(VC9_ARCH "x86")  # 32-bit (default)
#   set(VC9_ARCH "x64")  # 64-bit
#
# With Ninja cross-compilation (use the supplied toolchain files):
#
#   cmake -G Ninja -B build \
#     -DCMAKE_TOOLCHAIN_FILE=toolchain/vc9-cross-x86.cmake \
#     -DVC9_ROOT=/path/to/vc9sp1
#
# Or standalone (if repo is already cloned):
#
#   include(/path/to/vc9-toolset/vc9-toolset.cmake)
#   vc9_setup("${CMAKE_BINARY_DIR}/vc9sp1")

# vc9_setup(<dest_dir>)
#
# Extracts VC9 SP1 toolchain to <dest_dir> (if not already extracted).
# Sets the following variables in the caller's scope:
#
#   VC9_ROOT               — root of the extracted toolchain
#   VC9_BIN_DIR            — VC compiler bin directory
#   VC9_INCLUDE_DIRS       — VC include + WinSDK include directories (list)
#   VC9_LIB_DIRS           — VC lib + WinSDK lib directories (list)
#   WINSDK_INCLUDE_DIR     — Windows SDK include directory
#   WINSDK_LIB_DIR         — Windows SDK lib directory
#
#   VC9_COMPAT_HEADER      — path to compat/vc9_compat.h   (compile-time stubs)
#   VC9_RUNTIME_STUBS_SRC  — path to compat/vc9_runtime_stubs.cpp (link-time stubs)
#   VC9_CLANG_COMPILE_FLAGS — list of flags for clang cross-compilation
#   VC9_CLANG_LINK_LIBS     — CRT + kernel32 link libs for the selected config
#   VC9_TARGET_TRIPLE       — clang target triple (i686- or x86_64-pc-windows-msvc)
#
function(vc9_setup DEST_DIR)
    set(_vc9_script_dir "${CMAKE_CURRENT_FUNCTION_LIST_DIR}")

    # Check if already extracted
    if(NOT EXISTS "${DEST_DIR}/VC/bin/cl.exe")
        message(STATUS "VC9 SP1: extracting to ${DEST_DIR} ...")
        find_program(_vc9_bash bash REQUIRED)
        execute_process(
            COMMAND "${_vc9_bash}" "${_vc9_script_dir}/extract-vc9.sh" "${DEST_DIR}"
            RESULT_VARIABLE _vc9_result
        )
        if(NOT _vc9_result EQUAL 0)
            message(FATAL_ERROR "VC9 SP1 extraction failed (exit code: ${_vc9_result})")
        endif()
    else()
        message(STATUS "VC9 SP1: using existing extraction at ${DEST_DIR}")
    endif()

    # Verify key files exist
    if(NOT EXISTS "${DEST_DIR}/VC/bin/cl.exe")
        message(FATAL_ERROR "VC9 SP1: cl.exe not found at ${DEST_DIR}/VC/bin/cl.exe")
    endif()

    # Architecture — auto-detect from toolchain or use VC9_ARCH (default x86)
    if(NOT DEFINED VC9_ARCH)
        if(CMAKE_C_COMPILER_TARGET MATCHES "x86_64|amd64")
            set(VC9_ARCH "x64")
        else()
            set(VC9_ARCH "x86")
        endif()
    endif()

    if(VC9_ARCH STREQUAL "x64")
        set(_vc9_target_triple "x86_64-pc-windows-msvc")
        set(_vc9_vc_lib_dir   "${DEST_DIR}/VC/lib/amd64")
        set(_vc9_sdk_lib_dir  "${DEST_DIR}/WinSDK/Lib/x64")
    elseif(VC9_ARCH STREQUAL "x86")
        set(_vc9_target_triple "i686-pc-windows-msvc")
        set(_vc9_vc_lib_dir   "${DEST_DIR}/VC/lib")
        set(_vc9_sdk_lib_dir  "${DEST_DIR}/WinSDK/Lib")
    else()
        message(FATAL_ERROR "VC9_ARCH must be x86 or x64 (got '${VC9_ARCH}')")
    endif()

    # Export path variables
    set(VC9_ROOT "${DEST_DIR}" PARENT_SCOPE)
    set(VC9_BIN_DIR "${DEST_DIR}/VC/bin" PARENT_SCOPE)
    set(VC9_INCLUDE_DIRS "${DEST_DIR}/VC/include;${DEST_DIR}/WinSDK/Include" PARENT_SCOPE)
    set(VC9_LIB_DIRS "${_vc9_vc_lib_dir};${_vc9_sdk_lib_dir}" PARENT_SCOPE)
    set(VC9_TARGET_TRIPLE "${_vc9_target_triple}" PARENT_SCOPE)
    set(WINSDK_INCLUDE_DIR "${DEST_DIR}/WinSDK/Include" PARENT_SCOPE)
    set(WINSDK_LIB_DIR "${_vc9_sdk_lib_dir}" PARENT_SCOPE)

    # Export compat file paths
    set(VC9_COMPAT_HEADER "${_vc9_script_dir}/compat/vc9_compat.h" PARENT_SCOPE)
    set(VC9_RUNTIME_STUBS_SRC "${_vc9_script_dir}/compat/vc9_runtime_stubs.cpp" PARENT_SCOPE)

    # CRT configuration — VC9_CRT selects /MD, /MDd, /MT, or /MTd
    if(NOT DEFINED VC9_CRT)
        set(VC9_CRT "MD")
    endif()
    set(_vc9_crt_defs "")
    set(_vc9_crt_libs "")
    if(VC9_CRT STREQUAL "MD")
        set(_vc9_crt_libs "msvcrt.lib" "msvcprt.lib")
    elseif(VC9_CRT STREQUAL "MDd")
        set(_vc9_crt_defs "-D_DEBUG")
        set(_vc9_crt_libs "msvcrtd.lib" "msvcprtd.lib")
    elseif(VC9_CRT STREQUAL "MT")
        set(_vc9_crt_defs "-DVC9_STATIC_CRT")
        set(_vc9_crt_libs "libcmt.lib" "libcpmt.lib")
    elseif(VC9_CRT STREQUAL "MTd")
        set(_vc9_crt_defs "-DVC9_STATIC_CRT" "-D_DEBUG")
        set(_vc9_crt_libs "libcmtd.lib" "libcpmtd.lib")
    else()
        message(FATAL_ERROR "VC9_CRT must be MD, MDd, MT, or MTd (got '${VC9_CRT}')")
    endif()

    # Export ready-made clang cross-compile flags.
    # Uses SHELL: prefix for multi-token flags (-include, -isystem) so that
    # add_compile_options() and target_compile_options() pass them correctly
    # to the compiler (CMake would otherwise deduplicate bare -isystem tokens).
    set(VC9_CLANG_COMPILE_FLAGS
        "--target=${_vc9_target_triple}"
        "-fms-compatibility"
        "-fms-extensions"
        "-fdelayed-template-parsing"
        "SHELL:-include ${_vc9_script_dir}/compat/vc9_compat.h"
        "-U_MSC_VER" "-D_MSC_VER=1500"
        ${_vc9_crt_defs}
        "SHELL:-isystem ${DEST_DIR}/VC/include"
        "SHELL:-isystem ${DEST_DIR}/WinSDK/Include"
        PARENT_SCOPE
    )

    # Export link libs for the selected CRT
    set(VC9_CLANG_LINK_LIBS ${_vc9_crt_libs} "kernel32.lib" PARENT_SCOPE)
endfunction()

# vc9_target_setup(<target>)
#
# Convenience function: configures a CMake target for VC9 cross-compilation
# using native CMake commands.  Call vc9_setup() first, then:
#
#   add_executable(myapp main.cpp ${VC9_RUNTIME_STUBS_SRC})
#   vc9_target_setup(myapp)
#
# Sets system include directories, compile flags, link directories, and link
# libraries on the target.  Requires vc9_setup() to have been called first.
#
function(vc9_target_setup target)
    if(NOT VC9_ROOT)
        message(FATAL_ERROR "vc9_target_setup: call vc9_setup() first")
    endif()

    # VC9 headers/libs target Windows.  Without a cross-compilation toolchain
    # file, GCC rejects --target= and -fms-compatibility, while native clang
    # compiles objects but the Linux linker can't consume .lib files.  Catch
    # both cases early with an actionable message.
    if(NOT CMAKE_CROSSCOMPILING AND NOT CMAKE_SYSTEM_NAME STREQUAL "Windows")
        message(FATAL_ERROR
            "vc9_target_setup: VC9 headers require cross-compilation to Windows.\n"
            "Use a toolchain file, e.g.:\n"
            "  cmake -G Ninja -B build \\\n"
            "    -DCMAKE_TOOLCHAIN_FILE=toolchain/vc9-cross-x86.cmake \\\n"
            "    -DVC9_ROOT=/path/to/vc9sp1\n"
            "See README.md § 'Clang Cross-Compilation from Linux'.")
    endif()

    target_include_directories(${target} SYSTEM PRIVATE ${VC9_INCLUDE_DIRS})

    target_compile_options(${target} PRIVATE
        "--target=${VC9_TARGET_TRIPLE}"
        "-fms-compatibility"
        "-fms-extensions"
        "-fdelayed-template-parsing"
        "SHELL:-include ${VC9_COMPAT_HEADER}"
        "-U_MSC_VER" "-D_MSC_VER=1500"
    )

    target_link_directories(${target} PRIVATE ${VC9_LIB_DIRS})
    target_link_libraries(${target} PRIVATE ${VC9_CLANG_LINK_LIBS})
endfunction()
