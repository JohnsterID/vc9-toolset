/*
 * vc9_runtime_stubs.cpp — Link-time stubs for symbols that modern clang
 *                          emits but the VC9 CRT/C++ runtime lacks.
 *
 * Compile:
 *   clang++ --target=i686-pc-windows-msvc -c vc9_runtime_stubs.cpp
 *
 * Link the resulting .obj alongside your other objects.
 *
 * When to use:
 *   - C programs that only use CRT + Win32 typically don't need this.
 *   - C++ programs (iostream, string, vector, exceptions) almost always do.
 */

extern "C" {

void exit(int status);

/* clang's C++ EH personality references __std_terminate (VC14+ CRT).
   VC9 only ships _terminate / terminate().  Provide a minimal stub. */
void __std_terminate() { exit(1); }

/* Thread-safe static-local initialization (VC14+ CRT, aka "magic statics").
   clang emits calls to these even when targeting _MSC_VER=1500.
   Stubs here are single-threaded; safe for DLLs loaded by the game engine
   on its main thread.  For real multi-threaded use, replace with atomics.

   Protocol (MSVC ABI):
     guard starts at 0 (BSS).  Compiler emits:
       if (guard > _Init_thread_epoch) goto done;   // fast path
       _Init_thread_header(&guard);
       if (guard == -1) { <init>; _Init_thread_footer(&guard); }
     header: set guard = -1 ("this thread initialises")
     footer: set guard > epoch  ("done, skip next time")
     abort:  reset guard = 0    ("retry on next call")

   _Init_thread_epoch MUST be __declspec(thread) because the compiler
   accesses it via TLS (fs:__tls_array + __tls_index + @SECREL32).
   A plain int in .bss would cause the @SECREL32 relocation to read
   from the wrong offset inside the TLS block at runtime.             */
__declspec(thread) int _Init_thread_epoch = 0;
void _Init_thread_header(int* p) { if (p) *p = -1; }
void _Init_thread_footer(int* p) { if (p) *p = 1; }
void _Init_thread_abort(int* p)  { if (p) *p = 0; }

} /* extern "C" */

/* clang (MSVC mode) emits sized delete (C++14 P0722R3) even when targeting
   older standards.  VC9 libs only have the unsized overload.
   decltype(sizeof(0)) gives unsigned int on x86, unsigned __int64 on x64. */
void operator delete(void* p, decltype(sizeof(0))) noexcept {
    ::operator delete(p);
}
