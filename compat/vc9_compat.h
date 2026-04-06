/*
 * vc9_compat.h — Pre-include header for cross-compiling VC9/SDK 7.0 code
 *                with clang (or clang-cl) on Linux.
 *
 * Usage:  clang --target=i686-pc-windows-msvc -include vc9_compat.h ...
 *
 * Handles four classes of problems:
 *   1. SAL annotations  — VC9 sal.h pulls in CodeAnalysis headers via
 *      backslash paths that don't resolve on Linux.  Disabling the
 *      attribute-based SAL codepath avoids this entirely.
 *   2. Driver annotations — kernelspecs.h (included unconditionally by
 *      SDK 7.0 winnt.h) defines __drv_* macros only when DriverSpecs.h
 *      content is active.  We stub them all to empty.
 *   3. CRT runtime macros — _DLL and _MT (= cl.exe /MD) are set by
 *      default so VC9 headers use __declspec(dllimport) on CRT/STL
 *      symbols.  Define VC9_STATIC_CRT for /MT (static CRT) instead.
 *   4. Type / intrinsic gaps — a handful of typedefs that clang's MSVC
 *      mode doesn't provide in the global namespace.
 */
#ifndef VC9_COMPAT_H
#define VC9_COMPAT_H

/* ── 1. SAL ─────────────────────────────────────────────────────────── */
/* Prevent the attribute-based SAL path (which #includes the backslash-
   pathed codeanalysis\sourceannotations.h) from activating.            */
#undef  _USE_ATTRIBUTES_FOR_SAL
#define _USE_ATTRIBUTES_FOR_SAL  0
#undef  _USE_DECLSPECS_FOR_SAL
#define _USE_DECLSPECS_FOR_SAL   0
#undef  __SAL_H_VERSION
#define __SAL_H_VERSION          0

/* ── 2. Driver / kernel annotations ─────────────────────────────────── */
/* DriverSpecs.h defines these when _PREFAST_ is set; kernelspecs.h uses
   them unconditionally.  Stub every macro to empty so winnt.h parses.  */
#define __pre
#define __post
#define __deref

/* Macros with arguments — must accept the right arity. */
#define __drv_functionClass(x)
#define __drv_when(cond, annotes)
#define __drv_in(annotes)
#define __drv_out(annotes)
#define __drv_inout(annotes)
#define __drv_declspec(x)
#define __drv_nop(x) x
#define __drv_at(expr, annotes)
#define __drv_group(x)
/* __$drv_group is an internal helper used by some SDK headers */
#define __$drv_group(x)

/* No-argument annotation macros */
#define __drv_interlocked
#define __drv_aliasesMem
#define __drv_inTry
#define __drv_sameIRQL
#define __drv_restoresIRQL
#define __drv_useCancelIRQL

/* Single-argument annotation macros */
#define __drv_freesMem(kind)
#define __drv_preferredFunction(func, why)
#define __drv_allocatesMem(kind)
#define __drv_maxIRQL(x)
#define __drv_minIRQL(x)
#define __drv_setsIRQL(x)
#define __drv_raisesIRQL(x)
#define __drv_requiresIRQL(x)
#define __drv_savesIRQL(x)
#define __drv_isCancelIRQL(x)
#define __drv_maxFunctionIRQL(x)
#define __drv_minFunctionIRQL(x)

/* Two-argument annotation macros */
#define __drv_savesIRQLGlobal(x, y)
#define __drv_restoresIRQLGlobal(x, y)
#define __drv_innerMustHoldGlobal(x, y)
#define __drv_innerReleasesGlobal(x, y)

/* ── 3. CRT runtime macros ─────────────────────────────────────────── */
/* _DLL and _MT control __declspec(dllimport) on CRT/STL symbols
   (via _CRTIMP, _CRTIMP2, _CRTIMP2_PURE in crtdefs.h / yvals.h).

   Default: _DLL + _MT (= cl.exe /MD) → link against msvcrt.lib +
   msvcprt.lib (MSVCR90.dll / MSVCP90.dll).  This is the standard
   configuration for DLLs and most executables.

   To select static CRT (/MT): define VC9_STATIC_CRT before including
   this header (e.g. -DVC9_STATIC_CRT), then link against libcmt.lib +
   libcpmt.lib instead.  _DLL is NOT set in that case so the headers
   pull in static CRT objects rather than DLL imports.

   Without _DLL the headers expand _CRTIMP2_PURE to nothing and clang
   inlines STL functions (e.g. locale::facet::_Decref) that also exist
   as DLL exports in MSVCP90.dll, causing duplicate-symbol link errors
   when linking against msvcprt.lib.  Defining _DLL makes the headers
   emit proper dllimport decorations, eliminating the conflict.         */
#ifndef _MT
#define _MT
#endif
#ifndef VC9_STATIC_CRT
  #ifndef _DLL
  #define _DLL
  #endif
#endif

/* ── 4. Type / misc gaps ────────────────────────────────────────────── */
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif

#endif /* VC9_COMPAT_H */
