/* Smoke test: CRT + Win32 API headers compile and link against VC9 toolchain. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#if defined(__clang__)
/* See smoke.cpp: va_start must be clang's builtin (a void expression), not
   VC9's macro, so the VC9 include directories must come after clang's
   builtin headers (-idirafter, or -imsvc for clang-cl). */
static int first_vararg(int last, ...) {
    va_list ap;
    typedef char va_start_is_not_clang_builtin_check_include_order
        [__builtin_types_compatible_p(__typeof__(va_start(ap, last)), void) ? 1 : -1];
    int first;
    (void)sizeof(va_start_is_not_clang_builtin_check_include_order);
    va_start(ap, last);
    first = va_arg(ap, int);
    va_end(ap);
    return first;
}
#endif

int main(void) {
    /* C89: all declarations before statements */
    char buf[64];
    HANDLE h;
    const char msg[] = "Win32 OK\n";
    DWORD written;

    /* CRT */
    sprintf(buf, "cl %d", _MSC_VER);
    printf("Compiler: %s\n", buf);

    /* Win32 */
    h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h != INVALID_HANDLE_VALUE) {
        WriteFile(h, msg, (DWORD)(sizeof(msg) - 1), &written, NULL);
    }

    /* Verify _MSC_VER is VC9-era (1500) when compiled with cl.exe,
       or whatever the cross-compiler reports. */
#ifdef _MSC_VER
    printf("_MSC_VER=%d\n", _MSC_VER);
#endif

#if defined(__clang__)
    printf("va_arg %d\n", first_vararg(0, 42));
#endif

    return 0;
}
