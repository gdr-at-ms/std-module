import lib_a;
import lib_b;
import lib_c;
import std;

int main()
{
    std::println("{}", lib_a::greet());
    std::println("{}", lib_b::greet());

    auto data = lib_c::make_data();
    std::println("lib_c data: [{}, {}, {}]", data[0], data[1], data[2]);

    return 0;
}
