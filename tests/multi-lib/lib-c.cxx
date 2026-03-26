export module lib_c;

import std;

export namespace lib_c {
    std::vector<int> make_data()
    {
        auto v = std::vector<int>{ 10, 20, 30 };
        std::ranges::sort(v);
        return v;
    }
}
