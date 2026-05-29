#include "state_smpcd_io.h"

#include <array>
#include <cstring>
#include <fstream>
#include <stdexcept>

namespace mpcd {
namespace {

constexpr std::array<char, 16> kMagic{{'S','R','C','M','P','C','D','_','S','T','A','T','E','\0','\0','\0'}};
constexpr std::uint32_t kVersionV1 = 1u;
constexpr std::uint32_t kVersionV2 = 2u;
constexpr std::uint32_t kEndianMarker = 0x01020304u;
constexpr std::uint32_t kDim2 = 2u;
constexpr std::uint32_t kLayoutSoA = 1u;
constexpr std::uint32_t kHasType = 1u;
constexpr std::uint32_t kHasMass = 1u;
constexpr std::uint32_t kRealSize = 8u;
constexpr std::uint32_t kTypeSize = 4u;
constexpr std::uint32_t kRoleSize = 1u;
constexpr std::uint64_t kHasRoleReservedFlag = 1u;
constexpr std::size_t kReservedCount = 8u;

// Header layout, written field-by-field to avoid compiler padding ambiguity:
// magic[16] char
// version uint32
// endian uint32
// dim uint32
// layout uint32
// Np uint64
// hasType uint32
// hasMass uint32
// realSize uint32
// typeSize uint32
// reserved[8] uint64
//
// V1 payload: x, y, vx, vy, type, mass.
// V2 payload: x, y, vx, vy, type, mass, role.  reserved[0]=1 flags that
// the role array is present while preserving the compact V1 header shape.

template <typename T>
void read_exact(std::ifstream& fin, T& value, const std::string& label) {
    fin.read(reinterpret_cast<char*>(&value), static_cast<std::streamsize>(sizeof(T)));
    if (!fin) {
        throw std::runtime_error("Cannot read " + label + " from .smpcd file");
    }
}

void read_bytes(std::ifstream& fin, char* data, std::size_t n, const std::string& label) {
    fin.read(data, static_cast<std::streamsize>(n));
    if (!fin) {
        throw std::runtime_error("Cannot read " + label + " from .smpcd file");
    }
}

template <typename T>
void write_exact(std::ofstream& fout, const T& value, const std::string& label) {
    fout.write(reinterpret_cast<const char*>(&value), static_cast<std::streamsize>(sizeof(T)));
    if (!fout) {
        throw std::runtime_error("Cannot write " + label + " to .smpcd file");
    }
}

void write_bytes(std::ofstream& fout, const char* data, std::size_t n, const std::string& label) {
    fout.write(data, static_cast<std::streamsize>(n));
    if (!fout) {
        throw std::runtime_error("Cannot write " + label + " to .smpcd file");
    }
}

template <typename T>
void read_vector(std::ifstream& fin, std::vector<T>& data, std::size_t n, const std::string& label) {
    data.resize(n);
    if (n == 0u) {
        return;
    }
    fin.read(reinterpret_cast<char*>(data.data()), static_cast<std::streamsize>(n * sizeof(T)));
    if (!fin) {
        throw std::runtime_error("Cannot read array " + label + " from .smpcd file");
    }
}

template <typename T>
void write_vector(std::ofstream& fout, const std::vector<T>& data, const std::string& label) {
    if (data.empty()) {
        return;
    }
    fout.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size() * sizeof(T)));
    if (!fout) {
        throw std::runtime_error("Cannot write array " + label + " to .smpcd file");
    }
}

void require_equal(std::uint32_t got, std::uint32_t expected, const std::string& label) {
    if (got != expected) {
        throw std::runtime_error("Unsupported .smpcd " + label);
    }
}

void require_supported_version(std::uint32_t version) {
    if (version != kVersionV1 && version != kVersionV2) {
        throw std::runtime_error("Unsupported .smpcd version");
    }
}

} // namespace

ParticleState read_smpcd_state(const std::string& filepath) {
    std::ifstream fin(filepath, std::ios::binary);
    if (!fin) {
        throw std::runtime_error("Cannot open .smpcd file for reading: " + filepath);
    }

    std::array<char, 16> magic{};
    read_bytes(fin, magic.data(), magic.size(), "magic");
    if (magic != kMagic) {
        throw std::runtime_error("Invalid .smpcd magic in: " + filepath);
    }

    std::uint32_t version = 0u;
    std::uint32_t endian = 0u;
    std::uint32_t dim = 0u;
    std::uint32_t layout = 0u;
    std::uint64_t Np = 0u;
    std::uint32_t hasType = 0u;
    std::uint32_t hasMass = 0u;
    std::uint32_t realSize = 0u;
    std::uint32_t typeSize = 0u;

    read_exact(fin, version, "version");
    read_exact(fin, endian, "endian marker");
    read_exact(fin, dim, "dimension");
    read_exact(fin, layout, "layout");
    read_exact(fin, Np, "Np");
    read_exact(fin, hasType, "hasType");
    read_exact(fin, hasMass, "hasMass");
    read_exact(fin, realSize, "realSize");
    read_exact(fin, typeSize, "typeSize");

    std::array<std::uint64_t, kReservedCount> reserved{};
    for (std::size_t i = 0; i < kReservedCount; ++i) {
        read_exact(fin, reserved[i], "reserved");
    }

    require_supported_version(version);
    require_equal(endian, kEndianMarker, "endianness or byte order");
    require_equal(dim, kDim2, "dimension");
    require_equal(layout, kLayoutSoA, "layout");
    require_equal(hasType, kHasType, "type flag");
    require_equal(hasMass, kHasMass, "mass flag");
    require_equal(realSize, kRealSize, "floating-point precision");
    require_equal(typeSize, kTypeSize, "type integer size");

    ParticleState state{};
    state.Np = Np;
    state.dim = dim;
    const std::size_t n = static_cast<std::size_t>(Np);

    if (static_cast<std::uint64_t>(n) != Np) {
        throw std::runtime_error(".smpcd particle count does not fit in std::size_t on this platform");
    }

    read_vector(fin, state.x, n, "x");
    read_vector(fin, state.y, n, "y");
    read_vector(fin, state.vx, n, "vx");
    read_vector(fin, state.vy, n, "vy");
    read_vector(fin, state.type, n, "type");
    read_vector(fin, state.mass, n, "mass");
    if (version == kVersionV2) {
        if (reserved[0] != kHasRoleReservedFlag) {
            throw std::runtime_error("Unsupported .smpcd V2 role flag");
        }
        read_vector(fin, state.role, n, "role");
    } else {
        state.role.assign(n, kParticleRoleFluid);
    }

    validate_particle_state(state, "read_smpcd_state");
    return state;
}

void write_smpcd_state(const std::string& filepath, const ParticleState& state) {
    ParticleState normalized = state;
    ensure_particle_roles(normalized, ParticleRole::Fluid);
    validate_particle_state(normalized, "write_smpcd_state");

    std::ofstream fout(filepath, std::ios::binary);
    if (!fout) {
        throw std::runtime_error("Cannot open .smpcd file for writing: " + filepath);
    }

    write_bytes(fout, kMagic.data(), kMagic.size(), "magic");

    const std::uint32_t version = kVersionV2;
    const std::uint32_t endian = kEndianMarker;
    const std::uint32_t dim = kDim2;
    const std::uint32_t layout = kLayoutSoA;
    const std::uint64_t Np = normalized.Np;
    const std::uint32_t hasType = kHasType;
    const std::uint32_t hasMass = kHasMass;
    const std::uint32_t realSize = kRealSize;
    const std::uint32_t typeSize = kTypeSize;

    write_exact(fout, version, "version");
    write_exact(fout, endian, "endian marker");
    write_exact(fout, dim, "dimension");
    write_exact(fout, layout, "layout");
    write_exact(fout, Np, "Np");
    write_exact(fout, hasType, "hasType");
    write_exact(fout, hasMass, "hasMass");
    write_exact(fout, realSize, "realSize");
    write_exact(fout, typeSize, "typeSize");

    std::array<std::uint64_t, kReservedCount> reserved{};
    reserved[0] = kHasRoleReservedFlag;
    reserved[1] = kRoleSize;
    for (std::size_t i = 0; i < kReservedCount; ++i) {
        write_exact(fout, reserved[i], "reserved");
    }

    write_vector(fout, normalized.x, "x");
    write_vector(fout, normalized.y, "y");
    write_vector(fout, normalized.vx, "vx");
    write_vector(fout, normalized.vy, "vy");
    write_vector(fout, normalized.type, "type");
    write_vector(fout, normalized.mass, "mass");
    write_vector(fout, normalized.role, "role");
}

} // namespace mpcd
