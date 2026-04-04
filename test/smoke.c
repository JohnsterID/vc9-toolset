/* Smoke test: CRT + Win32 API headers compile and link against VC9 toolchain. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

int main(void) {
    /* CRT */
    char buf[64];
    sprintf(buf, "cl %d", _MSC_VER);
    printf("Compiler: %s\n", buf);

    /* Win32 */
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h != INVALID_HANDLE_VALUE) {
        const char msg[] = "Win32 OK\n";
        DWORD written;
        WriteFile(h, msg, (DWORD)(sizeof(msg) - 1), &written, NULL);
    }

    /* Verify _MSC_VER is VC9-era (1500) when compiled with cl.exe,
       or whatever the cross-compiler reports. */
#ifdef _MSC_VER
    printf("_MSC_VER=%d\n", _MSC_VER);
#endif

    return 0;
}
