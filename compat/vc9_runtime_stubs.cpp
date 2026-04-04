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
   on its main thread.  For real multi-threaded use, replace with atomics. */
int _Init_thread_epoch = 0;
void _Init_thread_header(int* p) { if (p && *p == 0) *p = 1; }
void _Init_thread_footer(int* p) { if (p) *p = 2; }
void _Init_thread_abort(int* p)  { if (p) *p = 0; }

} /* extern "C" */

/* clang (MSVC mode) emits sized delete (C++14 P0722R3) even when targeting
   older standards.  VC9 libs only have the unsized overload.             */
void operator delete(void* p, unsigned int) noexcept {
    ::operator delete(p);
}
