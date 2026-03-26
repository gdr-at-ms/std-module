import std;

int main()
{
    // Containers + ranges — exercises a wide swathe of the module surface.
    auto values = std::vector<int>{ 5, 3, 1, 4, 2 };
    std::ranges::sort(values);
    if (values != std::vector<int>{ 1, 2, 3, 4, 5 })
        return 1;

    // std::format — heavyweight template machinery; a good BMI stress test.
    auto message = std::format("Hello, {} module!", "std");
    if (message != "Hello, std module!")
        return 2;

    // std::println — C++23-specific; confirms standard version propagated.
    std::println("test-import-std: PASS");
    return 0;
}
