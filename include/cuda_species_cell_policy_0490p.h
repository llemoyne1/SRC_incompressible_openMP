#pragma once

namespace mpcd {

// 0490p: device-resident cell-policy view built from the authoritative 0490h
// species deposit.  No per-cell policy array is mirrored through the host in
// the strict resident path.
struct CudaSpeciesCellPolicyDeviceView0490p {
    int numCells = 0;
    const unsigned char* wetCell = nullptr;
    const unsigned char* poorCell = nullptr;
    const unsigned char* richCell = nullptr;
    const unsigned char* targetBandCell = nullptr;
};

} // namespace mpcd
