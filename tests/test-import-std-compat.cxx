import std.compat;

// std.compat re-exports everything from std AND hoists C-library names
// into the global namespace.  Both aspects are verified.

int main()
{
    // Global-namespace C I/O — the defining feature of std.compat.
    char buf[64];
    snprintf(buf, sizeof(buf), "%d + %d = %d", 1, 2, 3);

    // C++ standard library (re-exported from std through std.compat).
    auto result = std::string(buf);
    if (result != "1 + 2 = 3")
        return 1;

    // Global-namespace C math.
    auto root = sqrt(144.0);
    if (root < 11.99 or root > 12.01)
        return 2;

    std::println("test-import-std-compat: PASS");
    return 0;
}
