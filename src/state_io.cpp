#include "state_io.h"

#include <fstream>
#include <stdexcept>

namespace mpcd {
namespace {

template <typename T>
std::vector<T> read_vector_bin(const std::string& filepath, std::size_t n_expected) {
    std::ifstream fin(filepath, std::ios::binary);
    if (!fin) {
        throw std::runtime_error("Cannot open binary file: " + filepath);
    }
    std::vector<T> out(n_expected);
    fin.read(reinterpret_cast<char*>(out.data()), static_cast<std::streamsize>(n_expected * sizeof(T)));
    if (!fin) {
        throw std::runtime_error("Cannot read expected payload from: " + filepath);
    }
    return out;
}

template <typename T>
void write_vector_bin(const std::string& filepath, const std::vector<T>& data) {
    std::ofstream fout(filepath, std::ios::binary);
    if (!fout) {
        throw std::runtime_error("Cannot open binary file for writing: " + filepath);
    }
    fout.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size() * sizeof(T)));
    if (!fout) {
        throw std::runtime_error("Cannot write payload to: " + filepath);
    }
}

} // namespace

State read_state(const std::string& x_path,
                 const std::string& v_path,
                 const std::string& type_path,
                 const std::string& r0_path,
                 bool has_type,
                 bool has_r0,
                 int n_expected) {
    State s;
    s.x = read_vector_bin<double>(x_path, static_cast<std::size_t>(2 * n_expected));
    s.v = read_vector_bin<double>(v_path, static_cast<std::size_t>(2 * n_expected));
    if (has_type) {
        s.type = read_vector_bin<std::uint8_t>(type_path, static_cast<std::size_t>(n_expected));
    }
    if (has_r0) {
        s.r0 = read_vector_bin<double>(r0_path, static_cast<std::size_t>(2 * n_expected));
    }
    return s;
}

void write_xy_interleaved(const std::string& filepath, const std::vector<double>& data, int n_expected) {
    if (data.size() != static_cast<std::size_t>(2 * n_expected)) {
        throw std::runtime_error("Interleaved XY buffer has unexpected size for write: " + filepath);
    }
    write_vector_bin<double>(filepath, data);
}

void write_u8(const std::string& filepath, const std::vector<std::uint8_t>& data, int n_expected) {
    if (data.size() != static_cast<std::size_t>(n_expected)) {
        throw std::runtime_error("u8 buffer has unexpected size for write: " + filepath);
    }
    write_vector_bin<std::uint8_t>(filepath, data);
}

} // namespace mpcd
