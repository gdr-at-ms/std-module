import std;
import std.compat;

// Importing both modules in a single translation unit is valid per the
// standard, but has historically triggered duplicate-symbol or ODR
// issues in some implementations.  This test guards against regressions.

int main()
{
    // From std — containers and ranges.
    auto values = std::vector<double>{ 3.14, 2.72, 1.41 };
    std::ranges::sort(values);

    // From std.compat — global-namespace C I/O.
    printf("first: %.2f\n", values.front());

    // Mixed — C++ formatting + C output.
    auto message = std::format("sorted {} elements", values.size());
    puts(message.c_str());

    std::println("test-import-both: PASS");
    return 0;
}
