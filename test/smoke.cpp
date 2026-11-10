// Smoke test: C++ STL + CRT + Win32 API headers compile and link.
#include <iostream>
#include <stdarg.h>
#include <string>
#include <vector>
#include <windows.h>

#if defined(__clang__)
// VC9's va_start takes the address of the last named parameter, which breaks
// once clang inlines the variadic function. Clang's own stdarg.h/vadefs.h
// replace it with __builtin_va_start, but only when clang's builtin headers
// are searched before the VC9 include directories (-idirafter, or -imsvc for
// clang-cl; -isystem and -I put VC9 first). The builtin is a void expression,
// VC9's macro is an assignment that yields a va_list.
template <class T> struct vc9_is_void { enum { value = 0 }; };
template <> struct vc9_is_void<void> { enum { value = 1 }; };

static int first_vararg(int last, ...) {
    va_list ap;
    typedef char va_start_is_not_clang_builtin_check_include_order
        [vc9_is_void<__decltype(va_start(ap, last))>::value ? 1 : -1];
    int first;
    (void)sizeof(va_start_is_not_clang_builtin_check_include_order);
    va_start(ap, last);
    first = va_arg(ap, int);
    va_end(ap);
    return first;
}
#endif

int main() {
    // C++ STL
    std::vector<std::string> items;
    items.push_back("VC9");
    items.push_back("SP1");
    items.push_back("15.0.30729.1");

    for (size_t i = 0; i < items.size(); ++i)
        std::cout << items[i] << " ";
    std::cout << std::endl;

    // Win32
    DWORD ver = GetVersion();
    std::cout << "Windows " << (int)LOBYTE(LOWORD(ver)) << "."
              << (int)HIBYTE(LOWORD(ver)) << std::endl;

#ifdef _MSC_VER
    std::cout << "_MSC_VER=" << _MSC_VER << std::endl;
#endif

#if defined(__clang__)
    std::cout << "va_arg " << first_vararg(0, 42) << std::endl;
#endif

    return 0;
}
