#include "dump_io.h"

#include <fstream>
#include <stdexcept>

namespace mpcd {
namespace {

template <typename T>
void write_vector(std::ofstream& fout, const std::vector<T>& v) {
    fout.write(reinterpret_cast<const char*>(v.data()), static_cast<std::streamsize>(v.size() * sizeof(T)));
    if (!fout) {
        throw std::runtime_error("Failed while writing cell field payload");
    }
}

} // namespace

void write_cell_fields_bin(const std::string& filepath, const CellFields& G) {
    std::ofstream fout(filepath, std::ios::binary);
    if (!fout) {
        throw std::runtime_error("Cannot open cell field file for writing: " + filepath);
    }
    const std::int32_t Nx = static_cast<std::int32_t>(G.Nx);
    const std::int32_t Ny = static_cast<std::int32_t>(G.Ny);
    fout.write(reinterpret_cast<const char*>(&Nx), sizeof(std::int32_t));
    fout.write(reinterpret_cast<const char*>(&Ny), sizeof(std::int32_t));
    write_vector(fout, G.N);
    write_vector(fout, G.Ux);
    write_vector(fout, G.Uy);
    write_vector(fout, G.Px);
    write_vector(fout, G.Py);
    write_vector(fout, G.T);
    write_vector(fout, G.rho);
    write_vector(fout, G.Pkin);
    write_vector(fout, G.Pvir);
    write_vector(fout, G.P);
    write_vector(fout, G.rhoTarget);
}

} // namespace mpcd
