// Smoke test: C++ STL + CRT + Win32 API headers compile and link.
#include <iostream>
#include <string>
#include <vector>
#include <windows.h>

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

    return 0;
}
