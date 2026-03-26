export module lib_a;

import std;

export namespace lib_a {
    std::string greet()
    {
        return std::format("hello from lib_a ({})", 1);
    }
}
