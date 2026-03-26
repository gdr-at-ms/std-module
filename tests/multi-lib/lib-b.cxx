export module lib_b;

import std;

export namespace lib_b {
    std::string greet()
    {
        return std::format("hello from lib_b ({})", 2);
    }
}
