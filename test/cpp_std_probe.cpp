/*
 * cpp_std_probe.cpp -- Determine the highest usable C++ standard with
 *                      the VC9 SP1 headers and clang cross-compiler.
 *
 * VC9 (MSVC 2008) shipped C++03 headers with TR1 extensions.  When
 * cross-compiling with clang, the LANGUAGE standard can be set much
 * higher (-std=c++11 through c++23), but the LIBRARY is still VC9's
 * C++03 STL.  This file probes both dimensions:
 *
 *   Section A: VC9 STL headers -- do they parse at the requested -std=?
 *   Section B: C++ language features -- does clang accept them?
 *   Section C: TR1 headers -- are the TR1 extensions available?
 *   Section D: Mixed -- modern language + VC9 STL types together.
 *
 * Compile with each standard to see what works:
 *   clang++ -std=c++03 ... -c cpp_std_probe.cpp
 *   clang++ -std=c++11 ... -c cpp_std_probe.cpp
 *   clang++ -std=c++14 ... -c cpp_std_probe.cpp
 *   clang++ -std=c++17 ... -c cpp_std_probe.cpp
 *
 * If compilation succeeds, everything guarded by that standard works.
 * The probe reports via static_assert messages and #pragma message.
 */

/* ================================================================== */
/* Section A: VC9 STL headers                                         */
/* ================================================================== */

#include <cstddef>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <cmath>

#include <string>
#include <vector>
#include <list>
#include <deque>
#include <map>
#include <set>
#include <algorithm>
#include <functional>
#include <iterator>
#include <utility>
#include <memory>
#include <numeric>
#include <limits>
#include <stdexcept>
#include <sstream>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <typeinfo>
#include <new>
#include <cassert>

/* ================================================================== */
/* Section B: C++ language features (clang-provided)                  */
/* ================================================================== */

/* -- C++11 language features ----------------------------------------*/
#if __cplusplus >= 201103L

namespace probe_cpp11 {

/* nullptr */
static void* null_probe = nullptr;

/* auto type deduction */
static auto int_probe = 42;

/* decltype */
static decltype(int_probe) decl_probe = 7;

/* static_assert */
static_assert(sizeof(int) >= 4, "int must be at least 4 bytes");

/* constexpr */
constexpr int ce_square(int x) { return x * x; }
static_assert(ce_square(5) == 25, "constexpr function");

/* rvalue references */
static int&& rval_ref_probe(int&& x) { return static_cast<int&&>(x); }

/* variadic templates */
template<typename... Args>
static int count_args(Args...) { return static_cast<int>(sizeof...(Args)); }

/* lambda */
static auto lambda_probe = [](int a, int b) { return a + b; };

/* scoped enum */
enum class Color : int { Red, Green, Blue };

/* trailing return type */
static auto trailing_probe(int a) -> int { return a * 2; }

/* alias template */
template<typename T>
using Vec = std::vector<T>;

/* range-based for requires iterable -- test in function body */
static int range_for_probe() {
    int arr[] = {1, 2, 3, 4, 5};
    int sum = 0;
    for (auto x : arr) sum += x;
    return sum;
}

/* initializer list (language-level, not std::initializer_list) */
static int init_list_probe() {
    int arr[] = {10, 20, 30};
    return arr[1];
}

/* noexcept */
static void noexcept_probe() noexcept {}

/* override / final */
struct Base { virtual int vfunc() { return 0; } virtual ~Base() {} };
struct Derived final : Base { int vfunc() override { return 1; } };

} /* namespace probe_cpp11 */

#pragma message("C++11 language features: PASS")

#endif /* C++11 */

/* -- C++14 language features ----------------------------------------*/
#if __cplusplus >= 201402L

namespace probe_cpp14 {

/* relaxed constexpr */
constexpr int ce_factorial(int n) {
    int result = 1;
    for (int i = 2; i <= n; ++i)
        result *= i;
    return result;
}
static_assert(ce_factorial(5) == 120, "relaxed constexpr");

/* variable templates */
template<typename T>
constexpr T pi = T(3.14159265358979323846L);

/* generic lambdas */
static auto generic_lambda = [](auto a, auto b) { return a + b; };

/* binary literals and digit separators */
constexpr int binary_probe = 0b1010'0011;
static_assert(binary_probe == 163, "binary literal + digit separator");

/* decltype(auto) */
static decltype(auto) decltype_auto_probe() { return 42; }

/* [[deprecated]] attribute */
[[deprecated("probe only")]]
static inline void deprecated_func() {}

} /* namespace probe_cpp14 */

#pragma message("C++14 language features: PASS")

#endif /* C++14 */

/* -- C++17 language features ----------------------------------------*/
#if __cplusplus >= 201703L

namespace probe_cpp17 {

/* if constexpr */
template<typename T>
static int if_constexpr_probe(T val) {
    if constexpr (sizeof(T) > 4)
        return 8;
    else
        return 4;
}

/* fold expressions */
template<typename... Args>
static auto fold_sum(Args... args) { return (args + ...); }

/* inline variables */
inline constexpr int inline_var = 99;

/* nested namespaces */
} /* close probe_cpp17 */
namespace probe_cpp17::nested { static const int n = 1; }
namespace probe_cpp17 {

/* structured bindings -- requires real std::pair from VC9 headers */
static int structured_binding_probe() {
    std::pair<int, double> p(10, 3.14);
    auto [a, b] = p;
    return a + static_cast<int>(b);
}

/* [[maybe_unused]], [[nodiscard]] */
[[nodiscard]] static int nodiscard_probe() { return 42; }
static void maybe_unused_probe([[maybe_unused]] int x) {}

/* constexpr if with type traits -- use manual trait, VC9 has no <type_traits> */
template<typename T>
constexpr bool is_pointer_v = false;
template<typename T>
constexpr bool is_pointer_v<T*> = true;

template<typename T>
static int ptr_dispatch(T val) {
    if constexpr (is_pointer_v<T>)
        return *val;
    else
        return val;
}

} /* namespace probe_cpp17 */

#pragma message("C++17 language features: PASS")

#endif /* C++17 */

/* -- C++20 language features ----------------------------------------*/
#if __cplusplus >= 202002L

namespace probe_cpp20 {

/* designated initializers */
struct Point { int x; int y; };
static Point designated_init_probe() {
    Point p = { .x = 10, .y = 20 };
    return p;
}

/* char8_t is a distinct type in C++20 */
static_assert(!__is_same(char8_t, unsigned char) || sizeof(char8_t) == 1,
              "char8_t exists");

/* three-way comparison (spaceship) -- language level, no <compare> */
static int spaceship_probe(int a, int b) {
    /* manual signum -- VC9 lacks <compare> / std::strong_ordering */
    return (a > b) - (a < b);
}

/* consteval (immediate function) */
consteval int ce_immediate(int x) { return x * x; }
static_assert(ce_immediate(6) == 36, "consteval");

/* constinit (namespace-scope) */
constinit static int ci_var = 42;

/* [[likely]] / [[unlikely]] */
static int likely_probe(int x) {
    if (x > 0) [[likely]]
        return 1;
    else [[unlikely]]
        return -1;
}

/* Abbreviated function template (auto params) */
static auto abbrev_template_probe(auto a, auto b) { return a + b; }

/* Lambda with template parameter list */
static auto template_lambda = []<typename T>(T a, T b) { return a + b; };

/* Aggregate with parenthesized init */
static Point paren_agg_probe() {
    Point p(3, 4);
    return p;
}

/* requires-expression (concept-lite, no stdlib concepts) */
template<typename T>
concept Addable = requires(T a, T b) { a + b; };

template<Addable T>
static T concept_add(T a, T b) { return a + b; }

/* using enum */
enum class Dir { Up, Down, Left, Right };
static int using_enum_probe() {
    using enum Dir;
    return static_cast<int>(Up);
}

} /* namespace probe_cpp20 */

#pragma message("C++20 language features: PASS")

#endif /* C++20 */

/* -- C++23 language features ----------------------------------------*/
#if __cplusplus >= 202302L

namespace probe_cpp23 {

/* if consteval */
static int if_consteval_probe() {
    if consteval {
        return 1;
    } else {
        return 0;
    }
}

/* static operator() */
struct StaticCall {
    static int operator()(int a, int b) { return a + b; }
};

/* size_t literal suffix (__cpp_size_t_suffix may not be set yet on all
   compilers, guard conservatively) */
#if defined(__cpp_size_t_suffix) || defined(__clang__)
static auto size_literal_probe() {
    auto s = 42uz;
    return s;
}
#endif

/* auto(x) -- decay-copy */
static int decay_copy_probe() {
    int arr[] = {1, 2, 3};
    auto p = auto(arr);
    (void)p;
    return 0;
}

/* [[assume(expr)]] -- compiler hint, no runtime effect */
static int assume_probe(int x) {
    [[assume(x > 0)]];
    return x;
}

/* Deducing this (explicit object parameter) */
struct SelfDeducer {
    int value;
    int get(this const SelfDeducer& self) { return self.value; }
};

/* Multidimensional subscript operator */
struct Matrix {
    int data[4];
    int& operator[](int r, int c) { return data[r * 2 + c]; }
};

} /* namespace probe_cpp23 */

#pragma message("C++23 language features: PASS")

#endif /* C++23 */

/* ================================================================== */
/* Section C: TR1 headers                                             */
/* ================================================================== */

/*
 * VC9 ships TR1 under <type_traits>, <unordered_map>, <unordered_set>,
 * <array>, <tuple>, <functional> (with std::tr1:: namespace), and
 * <memory> (std::tr1::shared_ptr).  The headers may be directly in
 * VC/include/ or under VC/include/. Some are in std::tr1::, some
 * were promoted to std:: in later MSVC versions.
 *
 * We test with _HAS_TR1 guards since VC9's yvals.h controls this.
 */

#ifdef _HAS_TR1
#if _HAS_TR1

namespace probe_tr1 {

/* std::tr1::shared_ptr -- in <memory> on VC9 */
static void shared_ptr_probe() {
    std::tr1::shared_ptr<int> sp(new int(42));
    (void)sp;
}

} /* namespace probe_tr1 */

#pragma message("TR1 (via _HAS_TR1): PASS")

#endif /* _HAS_TR1 == 1 */
#endif /* defined _HAS_TR1 */

/* ================================================================== */
/* Section D: Modern language + VC9 STL types                         */
/* ================================================================== */

#if __cplusplus >= 201103L

namespace probe_mixed {

/* auto + VC9 vector */
static int auto_vector_probe() {
    std::vector<int> v;
    v.push_back(1);
    v.push_back(2);
    v.push_back(3);
    auto sz = v.size();
    return static_cast<int>(sz);
}

/* range-for over VC9 vector (requires begin/end ADL or member) */
static int range_for_vector() {
    std::vector<int> v;
    v.push_back(10);
    v.push_back(20);
    int sum = 0;
    for (auto x : v) sum += x;
    return sum;
}

/* lambda + VC9 std::string */
static std::string lambda_string_probe() {
    auto make_greeting = [](const std::string& name) -> std::string {
        return "Hello, " + name;
    };
    return make_greeting("VC9");
}

/* decltype with VC9 map */
static int decltype_map_probe() {
    std::map<std::string, int> m;
    m["a"] = 1;
    decltype(m)::iterator it = m.begin();
    return it->second;
}

/* nullptr with VC9 pointers */
static int nullptr_probe() {
    std::vector<int>* vp = nullptr;
    (void)vp;
    return 0;
}

/* scoped enum with VC9 map */
enum class Fruit : int { Apple, Banana, Cherry };
static int enum_class_map_probe() {
    std::map<int, std::string> m;
    m[static_cast<int>(Fruit::Apple)] = "apple";
    return static_cast<int>(m.size());
}

} /* namespace probe_mixed */

#pragma message("C++11 language + VC9 STL: PASS")

#endif /* C++11 mixed */

#if __cplusplus >= 201402L

namespace probe_mixed14 {

/* generic lambda + VC9 vector */
static int generic_lambda_vector() {
    std::vector<int> v;
    v.push_back(5);
    v.push_back(10);
    auto sum_elements = [](const auto& container) {
        int total = 0;
        for (auto it = container.begin(); it != container.end(); ++it)
            total += *it;
        return total;
    };
    return sum_elements(v);
}

} /* namespace probe_mixed14 */

#pragma message("C++14 language + VC9 STL: PASS")

#endif /* C++14 mixed */

#if __cplusplus >= 201703L

namespace probe_mixed17 {

/* structured bindings + VC9 pair/map */
static int structured_binding_map() {
    std::map<std::string, int> m;
    m["x"] = 42;
    auto it = m.begin();
    auto& [key, val] = *it;
    return val;
}

/* if constexpr + VC9 types */
template<typename T>
static std::string type_name_probe(T val) {
    if constexpr (sizeof(T) == sizeof(int))
        return "int-sized";
    else
        return "other";
}

/* fold expression building a VC9 string */
template<typename... Args>
static std::string concat_all(Args... args) {
    std::string result;
    ((result += args), ...);
    return result;
}

static std::string fold_string_probe() {
    return concat_all(std::string("A"), std::string("B"), std::string("C"));
}

} /* namespace probe_mixed17 */

#pragma message("C++17 language + VC9 STL: PASS")

#endif /* C++17 mixed */

#if __cplusplus >= 202002L

namespace probe_mixed20 {

/* concepts constraining VC9 STL usage */
template<typename T>
concept HasPushBack = requires(T t, typename T::value_type v) {
    t.push_back(v);
};

template<HasPushBack Container>
static int concept_container_probe(Container& c) {
    return static_cast<int>(c.size());
}

static int concept_vector_probe() {
    std::vector<int> v;
    v.push_back(1);
    return concept_container_probe(v);
}

/* designated init + VC9 map */
struct Config { int width; int height; };
static int designated_init_stl_probe() {
    Config cfg = { .width = 800, .height = 600 };
    std::map<std::string, int> m;
    m["w"] = cfg.width;
    m["h"] = cfg.height;
    return static_cast<int>(m.size());
}

/* abbreviated template + VC9 string */
static auto concat_anything(const auto& a, const auto& b) {
    std::string result;
    std::ostringstream oss;
    oss << a << b;
    return oss.str();
}

} /* namespace probe_mixed20 */

#pragma message("C++20 language + VC9 STL: PASS")

#endif /* C++20 mixed */

#if __cplusplus >= 202302L

namespace probe_mixed23 {

/* deducing this on a wrapper around VC9 vector */
struct IntVec {
    std::vector<int> data;
    int size(this const IntVec& self) {
        return static_cast<int>(self.data.size());
    }
};

/* static operator() with VC9 string */
struct Greeter {
    static std::string operator()(const std::string& name) {
        return "Hello, " + name;
    }
};

} /* namespace probe_mixed23 */

#pragma message("C++23 language + VC9 STL: PASS")

#endif /* C++23 mixed */

/* ================================================================== */
/* Report                                                             */
/* ================================================================== */

#pragma message("__cplusplus = " _CRT_STRINGIZE(__cplusplus))

#ifdef _MSC_VER
#pragma message("_MSC_VER = " _CRT_STRINGIZE(_MSC_VER))
#endif

/* Minimal main -- proves the object file is well-formed */
int main() {
    std::printf("cpp_std_probe: __cplusplus=%ld\n",
                static_cast<long>(__cplusplus));

#if __cplusplus >= 201103L
    std::printf("  C++11 language: OK\n");
    std::printf("  C++11 + VC9 STL: OK\n");
#endif
#if __cplusplus >= 201402L
    std::printf("  C++14 language: OK\n");
    std::printf("  C++14 + VC9 STL: OK\n");
#endif
#if __cplusplus >= 201703L
    std::printf("  C++17 language: OK\n");
    std::printf("  C++17 + VC9 STL: OK\n");
#endif
#if __cplusplus >= 202002L
    std::printf("  C++20 language: OK\n");
    std::printf("  C++20 + VC9 STL: OK\n");
#endif
#if __cplusplus >= 202302L
    std::printf("  C++23 language: OK\n");
    std::printf("  C++23 + VC9 STL: OK\n");
#endif

#ifdef _HAS_TR1
#if _HAS_TR1
    std::printf("  TR1: OK\n");
#endif
#endif

    return 0;
}
