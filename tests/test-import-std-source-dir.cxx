import std;

int main()
{
    auto values = std::vector<int>{ 9, 7, 8, 6 };
    std::ranges::sort(values);

    if (values != std::vector<int>{ 6, 7, 8, 9 })
        return 1;

    return 0;
}