#include "cuda_resampling_population_guard_0297.h"

#if defined(MPCD_ENABLE_CUDA_RESAMPLING) && \
    defined(MPCD_ENABLE_CUDA_PARTICLE_STATE) && \
    defined(MPCD_ENABLE_CUDA_CELL_WORKSPACE) && \
    defined(MPCD_ENABLE_CUDA_CELL_MOMENTS)

#include "cuda_cell_moments.h"
#include "cuda_cell_workspace.h"
#include "cuda_darcy_brinkman_0343.h"
#include "cuda_shared_particle_state_0251.h"
#include "cuda_species_cell_fields_0490h.h"
#include "immersed_solid.h"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace mpcd {
namespace {

using Clock = std::chrono::steady_clock;
constexpr unsigned int kInvalidParticle0297 = 0xffffffffu;

struct DevicePopulationGuardConfig0297 {
    int nx = 0;
    int ny = 0;
    int numCells = 0;
    double lx = 1.0;
    double ly = 1.0;
    double dx = 1.0;
    double dy = 1.0;

    double domainXMin = 0.0;
    double domainXMax = 1.0;
    double domainYMin = 0.0;
    double domainYMax = 1.0;

    int solidShape = 0; // 0 none, 1 circle, 2 rectangle.
    double circleCx = 0.0;
    double circleCy = 0.0;
    double circleR = 0.0;
    double rectXMin = 0.0;
    double rectXMax = 0.0;
    double rectYMin = 0.0;
    double rectYMax = 0.0;

    int nMin = 0;
    int nTarget = 0;
    int nMax = 0;
    double splitFraction = 0.5;
    double minDonorMassAfterSplit = 1.0e-12;

    int boundaryAware0299 = 0;
    int boundaryHaloCells0299 = 0;
    int openBoundaryHaloCells0299 = 0;
    int solidHaloCells0299 = 0;
    int faceOpenLeft0299 = 0;
    int faceOpenRight0299 = 0;
    int faceOpenBottom0299 = 0;
    int faceOpenTop0299 = 0;
    int faceWallLeft0299 = 0;
    int faceWallRight0299 = 0;
    int faceWallBottom0299 = 0;
    int faceWallTop0299 = 0;

    // 0307 split cascade diagnostics/prevention.
    int splitSafety0307 = 0;
    int preferMaxMassDonor0307 = 0;
    double splitDonorMinMass0307 = 0.0;
    double splitNewParticleMinMass0307 = 0.0;
    double solidAdjacentDonorMinMass0307 = 0.0;
    int solidAdjacentSplitMode0307 = 0; // 0 normal, 1 cautious, 2 off.
    int solidAdjacentHaloCells0307 = 1;
    double tinyMassThreshold0307 = 0.25;

    int activePrefixSafe0315 = 1;
    unsigned long long activeBase0315 = 0ull;
    unsigned long long activeCapacity0315 = 0ull;

    int emptyRefillEnable0319 = 0;
    int emptyRefillTarget0319 = 0;
    int emptyRefillMemoryMaxAge0319 = 0;
    int speciesCompositionEnable0490f = 0;
    int speciesCount0490f = 0;

    int speciesPopulationGuardEnable0490j = 0;
    int speciesCount0490j = 0;

    int chiFilterEnable = 0;
    double chiMin = 0.0;
};

struct DeviceBuffers0297 {
    unsigned int* dPoorCells = nullptr;
    unsigned int* dRichCells = nullptr;
    unsigned int* dPoorCount = nullptr;
    unsigned int* dRichCount = nullptr;
    unsigned int* dInactiveList = nullptr;
    unsigned int* dInactiveCount = nullptr;
    unsigned int* dInactiveCursor = nullptr;
    unsigned int* dPoorDonor = nullptr;
    unsigned long long* dPoorDonorMassBits0307 = nullptr;
    double* dMinima0307 = nullptr;
    unsigned int* dRichKeep = nullptr;
    unsigned int* dRichExtract = nullptr;
    double* dKrelBefore0298 = nullptr;
    double* dKrelAfter0298 = nullptr;
    double* dSpeciesKrelBefore0493g = nullptr; // species-major: s * numCells + c
    double* dSpeciesKrelAfter0493g = nullptr;  // species-major: s * numCells + c
    unsigned long long* dEnergyRestoreCounters0298 = nullptr; // 0 updated particles, 1 skipped particles
    unsigned int* dEmptyCells0319 = nullptr;
    unsigned int* dEmptyCount0319 = nullptr;
    double* dLastCellMass0319 = nullptr;
    double* dLastCellUx0319 = nullptr;
    double* dLastCellUy0319 = nullptr;
    unsigned int* dCurrentCellType0490c = nullptr;
    unsigned int* dCurrentCellMixed0490c = nullptr;
    unsigned int* dLastCellType0490c = nullptr;
    unsigned int* dLastCellMixed0490c = nullptr;
    unsigned long long* dLastCellStep0319 = nullptr;
    double* dEmptyAdded0319 = nullptr; // 0..2 added mass/px/py, 3..5 chi-allowed pre-refill mass/px/py
    unsigned int* dSpeciesTypes0490f = nullptr;
    unsigned char* dSpeciesResamplingEnabled0493b = nullptr;
    double* dCurrentCellSpeciesMass0490f = nullptr;
    double* dLastCellSpeciesMass0490f = nullptr;
    double* dSpeciesMomentsBefore0490f = nullptr; // ns x {m,px,py}
    double* dSpeciesMomentsAdded0490f = nullptr;  // ns x {m,px,py}
    double* dSpeciesScaleShift0490f = nullptr;    // ns x {scale,dvx,dvy}
    double* dSpeciesMomentsAfter0490f = nullptr;  // ns x {m,px,py}
    unsigned long long* dCounters = nullptr; // 0 merge, 1 split, 2 noInactive, 3 noDonor, 4 noPair, 5 boundary, 6 open, 7 solidHalo
    int cellCapacity = 0;
    int speciesCapacity0490f = 0;
    std::uint64_t particleCapacity = 0u;

    ~DeviceBuffers0297() { release(); }

    void release() {
        if (dPoorCells) cudaFree(dPoorCells);
        if (dRichCells) cudaFree(dRichCells);
        if (dPoorCount) cudaFree(dPoorCount);
        if (dRichCount) cudaFree(dRichCount);
        if (dInactiveList) cudaFree(dInactiveList);
        if (dInactiveCount) cudaFree(dInactiveCount);
        if (dInactiveCursor) cudaFree(dInactiveCursor);
        if (dPoorDonor) cudaFree(dPoorDonor);
        if (dPoorDonorMassBits0307) cudaFree(dPoorDonorMassBits0307);
        if (dMinima0307) cudaFree(dMinima0307);
        if (dRichKeep) cudaFree(dRichKeep);
        if (dRichExtract) cudaFree(dRichExtract);
        if (dKrelBefore0298) cudaFree(dKrelBefore0298);
        if (dKrelAfter0298) cudaFree(dKrelAfter0298);
        if (dSpeciesKrelBefore0493g) cudaFree(dSpeciesKrelBefore0493g);
        if (dSpeciesKrelAfter0493g) cudaFree(dSpeciesKrelAfter0493g);
        if (dEnergyRestoreCounters0298) cudaFree(dEnergyRestoreCounters0298);
        if (dEmptyCells0319) cudaFree(dEmptyCells0319);
        if (dEmptyCount0319) cudaFree(dEmptyCount0319);
        if (dLastCellMass0319) cudaFree(dLastCellMass0319);
        if (dLastCellUx0319) cudaFree(dLastCellUx0319);
        if (dLastCellUy0319) cudaFree(dLastCellUy0319);
        if (dCurrentCellType0490c) cudaFree(dCurrentCellType0490c);
        if (dCurrentCellMixed0490c) cudaFree(dCurrentCellMixed0490c);
        if (dLastCellType0490c) cudaFree(dLastCellType0490c);
        if (dLastCellMixed0490c) cudaFree(dLastCellMixed0490c);
        if (dLastCellStep0319) cudaFree(dLastCellStep0319);
        if (dEmptyAdded0319) cudaFree(dEmptyAdded0319);
        if (dSpeciesTypes0490f) cudaFree(dSpeciesTypes0490f);
        if (dSpeciesResamplingEnabled0493b) cudaFree(dSpeciesResamplingEnabled0493b);
        if (dCurrentCellSpeciesMass0490f) cudaFree(dCurrentCellSpeciesMass0490f);
        if (dLastCellSpeciesMass0490f) cudaFree(dLastCellSpeciesMass0490f);
        if (dSpeciesMomentsBefore0490f) cudaFree(dSpeciesMomentsBefore0490f);
        if (dSpeciesMomentsAdded0490f) cudaFree(dSpeciesMomentsAdded0490f);
        if (dSpeciesScaleShift0490f) cudaFree(dSpeciesScaleShift0490f);
        if (dSpeciesMomentsAfter0490f) cudaFree(dSpeciesMomentsAfter0490f);
        if (dCounters) cudaFree(dCounters);
        dPoorCells = nullptr;
        dRichCells = nullptr;
        dPoorCount = nullptr;
        dRichCount = nullptr;
        dInactiveList = nullptr;
        dInactiveCount = nullptr;
        dInactiveCursor = nullptr;
        dPoorDonor = nullptr;
        dPoorDonorMassBits0307 = nullptr;
        dMinima0307 = nullptr;
        dRichKeep = nullptr;
        dRichExtract = nullptr;
        dKrelBefore0298 = nullptr;
        dKrelAfter0298 = nullptr;
        dSpeciesKrelBefore0493g = nullptr;
        dSpeciesKrelAfter0493g = nullptr;
        dEnergyRestoreCounters0298 = nullptr;
        dEmptyCells0319 = nullptr;
        dEmptyCount0319 = nullptr;
        dLastCellMass0319 = nullptr;
        dLastCellUx0319 = nullptr;
        dLastCellUy0319 = nullptr;
        dCurrentCellType0490c = nullptr;
        dCurrentCellMixed0490c = nullptr;
        dLastCellType0490c = nullptr;
        dLastCellMixed0490c = nullptr;
        dLastCellStep0319 = nullptr;
        dEmptyAdded0319 = nullptr;
        dSpeciesTypes0490f = nullptr;
        dSpeciesResamplingEnabled0493b = nullptr;
        dCurrentCellSpeciesMass0490f = nullptr;
        dLastCellSpeciesMass0490f = nullptr;
        dSpeciesMomentsBefore0490f = nullptr;
        dSpeciesMomentsAdded0490f = nullptr;
        dSpeciesScaleShift0490f = nullptr;
        dSpeciesMomentsAfter0490f = nullptr;
        dCounters = nullptr;
        cellCapacity = 0;
        speciesCapacity0490f = 0;
        particleCapacity = 0u;
    }

    void ensure(int numCells, std::uint64_t nParticles, int speciesCount0490f) {
        const bool speciesBuffersReady0490f = speciesCount0490f <= 0 ||
            (speciesCount0490f <= speciesCapacity0490f && dSpeciesTypes0490f &&
             dSpeciesResamplingEnabled0493b && dCurrentCellSpeciesMass0490f && dLastCellSpeciesMass0490f &&
             dSpeciesMomentsBefore0490f && dSpeciesMomentsAdded0490f &&
             dSpeciesScaleShift0490f && dSpeciesMomentsAfter0490f &&
             dSpeciesKrelBefore0493g && dSpeciesKrelAfter0493g);
        if (numCells <= cellCapacity && nParticles <= particleCapacity && speciesBuffersReady0490f && dPoorCells && dRichCells &&
            dPoorCount && dRichCount && dInactiveList && dInactiveCount && dInactiveCursor && dPoorDonor &&
            dPoorDonorMassBits0307 && dMinima0307 &&
            dRichKeep && dRichExtract && dKrelBefore0298 && dKrelAfter0298 &&
            dEnergyRestoreCounters0298 && dEmptyCells0319 && dEmptyCount0319 &&
            dLastCellMass0319 && dLastCellUx0319 && dLastCellUy0319 &&
            dCurrentCellType0490c && dCurrentCellMixed0490c &&
            dLastCellType0490c && dLastCellMixed0490c &&
            dLastCellStep0319 && dEmptyAdded0319 && dCounters) {
            return;
        }
        release();
        if (numCells <= 0 || nParticles == 0u) return;
        cudaError_t err = cudaSuccess;
        err = cudaMalloc(reinterpret_cast<void**>(&dPoorCells), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc poor cells: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dRichCells), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc rich cells: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dPoorCount), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc poor count: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dRichCount), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc rich count: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dInactiveList), sizeof(unsigned int) * static_cast<std::size_t>(nParticles));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc inactive list: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dInactiveCount), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc inactive count: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dInactiveCursor), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc inactive cursor: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dPoorDonor), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc poor donor: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dPoorDonorMassBits0307), sizeof(unsigned long long) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0307 poor donor mass bits: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dMinima0307), sizeof(double) * 3u);
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0307 minima: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dRichKeep), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc rich keep: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dRichExtract), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc rich extract: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dKrelBefore0298), sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0298 krel before: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dKrelAfter0298), sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0298 krel after: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dEnergyRestoreCounters0298), sizeof(unsigned long long) * 2u);
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0298 energy counters: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dEmptyCells0319), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0319 empty cells: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dEmptyCount0319), sizeof(unsigned int));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0319 empty count: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dLastCellMass0319), sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0319 last cell mass: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dLastCellUx0319), sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0319 last cell ux: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dLastCellUy0319), sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0319 last cell uy: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dCurrentCellType0490c), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490c current cell type: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dCurrentCellMixed0490c), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490c current cell mixed flag: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dLastCellType0490c), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490c last cell type: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dLastCellMixed0490c), sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490c last cell mixed flag: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dLastCellStep0319), sizeof(unsigned long long) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0319 last cell step: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dEmptyAdded0319), sizeof(double) * 6u);
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0319 added moments: ") + cudaGetErrorString(err));
        if (speciesCount0490f > 0) {
            const std::size_t ns = static_cast<std::size_t>(speciesCount0490f);
            const std::size_t ncs = static_cast<std::size_t>(numCells) * ns;
            err = cudaMalloc(reinterpret_cast<void**>(&dSpeciesTypes0490f), sizeof(unsigned int) * ns);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490f species types: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dSpeciesResamplingEnabled0493b), sizeof(unsigned char) * ns);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0493b species resampling flags: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dCurrentCellSpeciesMass0490f), sizeof(double) * ncs);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490f current cell species mass: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dLastCellSpeciesMass0490f), sizeof(double) * ncs);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490f last cell species mass: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dSpeciesMomentsBefore0490f), sizeof(double) * 3u * ns);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490f before moments: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dSpeciesMomentsAdded0490f), sizeof(double) * 3u * ns);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490f added moments: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dSpeciesScaleShift0490f), sizeof(double) * 3u * ns);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490f scale/shift: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dSpeciesMomentsAfter0490f), sizeof(double) * 3u * ns);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0490f after moments: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dSpeciesKrelBefore0493g), sizeof(double) * ncs);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0493g species krel before: ") + cudaGetErrorString(err));
            err = cudaMalloc(reinterpret_cast<void**>(&dSpeciesKrelAfter0493g), sizeof(double) * ncs);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc 0493g species krel after: ") + cudaGetErrorString(err));
            err = cudaMemset(dLastCellSpeciesMass0490f, 0, sizeof(double) * ncs);
            if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: memset 0490f last cell species mass: ") + cudaGetErrorString(err));
        }
        err = cudaMemset(dLastCellMass0319, 0, sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: memset 0319 last cell mass: ") + cudaGetErrorString(err));
        err = cudaMemset(dLastCellUx0319, 0, sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: memset 0319 last cell ux: ") + cudaGetErrorString(err));
        err = cudaMemset(dLastCellUy0319, 0, sizeof(double) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: memset 0319 last cell uy: ") + cudaGetErrorString(err));
        err = cudaMemset(dLastCellType0490c, 0xff, sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: memset 0490c last cell type: ") + cudaGetErrorString(err));
        err = cudaMemset(dLastCellMixed0490c, 0, sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: memset 0490c last cell mixed flag: ") + cudaGetErrorString(err));
        err = cudaMemset(dLastCellStep0319, 0, sizeof(unsigned long long) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: memset 0319 last cell step: ") + cudaGetErrorString(err));
        err = cudaMalloc(reinterpret_cast<void**>(&dCounters), sizeof(unsigned long long) * 32u);
        if (err != cudaSuccess) throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: malloc counters: ") + cudaGetErrorString(err));
        cellCapacity = numCells;
        speciesCapacity0490f = speciesCount0490f;
        particleCapacity = nParticles;
    }
};

struct SpeciesPopulationSelectionBuffers0490j {
    unsigned int* dPoorType = nullptr;
    unsigned int* dRichType = nullptr;
    unsigned int* dPoorPending = nullptr;
    unsigned int* dRichPending = nullptr;
    int cellCapacity = 0;

    ~SpeciesPopulationSelectionBuffers0490j() { release(); }

    void release() {
        if (dPoorType) cudaFree(dPoorType);
        if (dRichType) cudaFree(dRichType);
        if (dPoorPending) cudaFree(dPoorPending);
        if (dRichPending) cudaFree(dRichPending);
        dPoorType = nullptr;
        dRichType = nullptr;
        dPoorPending = nullptr;
        dRichPending = nullptr;
        cellCapacity = 0;
    }

    void ensure(int numCells) {
        if (numCells <= cellCapacity && dPoorType && dRichType &&
            dPoorPending && dRichPending) return;
        release();
        if (numCells <= 0) return;
        cudaError_t err = cudaMalloc(reinterpret_cast<void**>(&dPoorType),
                                     sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("0490j malloc poor selected type: ") +
                                     cudaGetErrorString(err));
        }
        err = cudaMalloc(reinterpret_cast<void**>(&dRichType),
                         sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("0490j malloc rich selected type: ") +
                                     cudaGetErrorString(err));
        }
        err = cudaMalloc(reinterpret_cast<void**>(&dPoorPending),
                         sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("0490j malloc poor pending state: ") +
                                     cudaGetErrorString(err));
        }
        err = cudaMalloc(reinterpret_cast<void**>(&dRichPending),
                         sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("0490j malloc rich pending state: ") +
                                     cudaGetErrorString(err));
        }
        err = cudaMemset(dPoorPending, 0,
                         sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("0490j reset poor pending state: ") +
                                     cudaGetErrorString(err));
        }
        err = cudaMemset(dRichPending, 0,
                         sizeof(unsigned int) * static_cast<std::size_t>(numCells));
        if (err != cudaSuccess) {
            throw std::runtime_error(std::string("0490j reset rich pending state: ") +
                                     cudaGetErrorString(err));
        }
        cellCapacity = numCells;
    }
};

thread_local CudaCellWorkspace g_populationGuardWorkspace0297;
thread_local DeviceBuffers0297 g_populationGuardBuffers0297;
thread_local CudaSpeciesCellWorkspace0490h g_populationGuardSpeciesWorkspace0490j;
thread_local SpeciesPopulationSelectionBuffers0490j g_populationGuardSpeciesSelection0490j;

inline double seconds_between(const Clock::time_point a, const Clock::time_point b) {
    return std::chrono::duration<double>(b - a).count();
}

void cuda_check_0297(cudaError_t err, const char* context) {
    if (err != cudaSuccess) {
        throw std::runtime_error(std::string("cuda_resampling_population_guard_0297: ") +
                                 context + ": " + cudaGetErrorString(err));
    }
}

__device__ inline double atomic_add_double_compat_0297(double* address, double value) {
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 600)
    return atomicAdd(address, value);
#else
    auto* addressAsUll = reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed;
    do {
        assumed = old;
        old = atomicCAS(addressAsUll,
                        assumed,
                        __double_as_longlong(value + __longlong_as_double(assumed)));
    } while (assumed != old);
    return __longlong_as_double(old);
#endif
}

__device__ inline void atomic_min_double_positive_0307(double* address, double value) {
    if (!(value >= 0.0) || !isfinite(value)) return;
    auto* addressAsUll = reinterpret_cast<unsigned long long int*>(address);
    unsigned long long int old = *addressAsUll;
    unsigned long long int assumed;
    do {
        assumed = old;
        const double oldVal = __longlong_as_double(static_cast<long long>(assumed));
        if (oldVal <= value) return;
        old = atomicCAS(addressAsUll, assumed, static_cast<unsigned long long int>(__double_as_longlong(value)));
    } while (assumed != old);
}


bool env_truthy_0297(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    std::string s(v);
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return !(s == "0" || s == "false" || s == "off" || s == "no");
}

int env_int_0297(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stoi(v);
    } catch (...) {
        return fallback;
    }
}

double env_double_0297(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try {
        return std::stod(v);
    } catch (...) {
        return fallback;
    }
}

std::string lower_copy_0299(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return s;
}

bool mode_is_periodic_0299(const std::string& mode) {
    return lower_copy_0299(mode) == "periodic";
}

bool mode_is_open_0299(const std::string& mode) {
    const std::string m = lower_copy_0299(mode);
    return m == "inlet" || m == "outlet" || m.find("inlet") != std::string::npos ||
           m.find("outlet") != std::string::npos || m.find("open") != std::string::npos;
}

void mark_segment_face_open_0299(DevicePopulationGuardConfig0297& cfg, const std::string& face) {
    const std::string f = lower_copy_0299(face);
    if (f == "left") cfg.faceOpenLeft0299 = 1;
    else if (f == "right") cfg.faceOpenRight0299 = 1;
    else if (f == "bottom") cfg.faceOpenBottom0299 = 1;
    else if (f == "top") cfg.faceOpenTop0299 = 1;
}

std::string csv_escape_0297(const std::string& s) {
    if (s.find_first_of(",\"\n\r") == std::string::npos) return s;
    std::string out = "\"";
    for (const char ch : s) {
        if (ch == '"') out += "\"\"";
        else out += ch;
    }
    out += "\"";
    return out;
}

__device__ bool point_inside_active_domain_0297(double x, double y, DevicePopulationGuardConfig0297 cfg) {
    if (x < cfg.domainXMin || x > cfg.domainXMax || y < cfg.domainYMin || y > cfg.domainYMax) {
        return false;
    }
    if (cfg.solidShape == 1) {
        const double dx = x - cfg.circleCx;
        const double dy = y - cfg.circleCy;
        return dx * dx + dy * dy >= cfg.circleR * cfg.circleR;
    }
    if (cfg.solidShape == 2) {
        const bool insideRect = x >= cfg.rectXMin && x <= cfg.rectXMax &&
                                y >= cfg.rectYMin && y <= cfg.rectYMax;
        return !insideRect;
    }
    return true;
}

__device__ bool cell_center_inside_active_domain_0297(int c, DevicePopulationGuardConfig0297 cfg) {
    const int ix = c % cfg.nx;
    const int iy = c / cfg.nx;
    const double cx = (static_cast<double>(ix) + 0.5) * cfg.dx;
    const double cy = (static_cast<double>(iy) + 0.5) * cfg.dy;
    return point_inside_active_domain_0297(cx, cy, cfg);
}

__device__ int population_guard_exclusion_reason_0299(int c, DevicePopulationGuardConfig0297 cfg) {
    if (!cfg.boundaryAware0299) return 0;
    const int ix = c % cfg.nx;
    const int iy = c / cfg.nx;

    const int openHalo = cfg.openBoundaryHaloCells0299;
    if (openHalo > 0) {
        if (cfg.faceOpenLeft0299 && ix < openHalo) return 2;
        if (cfg.faceOpenRight0299 && ix >= cfg.nx - openHalo) return 2;
        if (cfg.faceOpenBottom0299 && iy < openHalo) return 2;
        if (cfg.faceOpenTop0299 && iy >= cfg.ny - openHalo) return 2;
    }

    const int wallHalo = cfg.boundaryHaloCells0299;
    if (wallHalo > 0) {
        if (cfg.faceWallLeft0299 && ix < wallHalo) return 1;
        if (cfg.faceWallRight0299 && ix >= cfg.nx - wallHalo) return 1;
        if (cfg.faceWallBottom0299 && iy < wallHalo) return 1;
        if (cfg.faceWallTop0299 && iy >= cfg.ny - wallHalo) return 1;
    }

    const int solidHalo = cfg.solidHaloCells0299;
    if (solidHalo > 0 && cfg.solidShape != 0) {
        const double cx = (static_cast<double>(ix) + 0.5) * cfg.dx;
        const double cy = (static_cast<double>(iy) + 0.5) * cfg.dy;
        const double halo = static_cast<double>(solidHalo) * fmax(cfg.dx, cfg.dy);
        if (cfg.solidShape == 1) {
            const double dx = cx - cfg.circleCx;
            const double dy = cy - cfg.circleCy;
            const double r = sqrt(dx * dx + dy * dy);
            if (r >= cfg.circleR && r <= cfg.circleR + halo) return 3;
        } else if (cfg.solidShape == 2) {
            const double qx = fmax(fmax(cfg.rectXMin - cx, 0.0), cx - cfg.rectXMax);
            const double qy = fmax(fmax(cfg.rectYMin - cy, 0.0), cy - cfg.rectYMax);
            const double dist = sqrt(qx * qx + qy * qy);
            const bool outsideRect = !(cx >= cfg.rectXMin && cx <= cfg.rectXMax &&
                                       cy >= cfg.rectYMin && cy <= cfg.rectYMax);
            if (outsideRect && dist <= halo) return 3;
        }
    }
    return 0;
}


__device__ bool population_guard_solid_adjacent_0307(int c, DevicePopulationGuardConfig0297 cfg) {
    if (cfg.solidShape == 0) return false;
    const int ix = c % cfg.nx;
    const int iy = c / cfg.nx;
    const double cx = (static_cast<double>(ix) + 0.5) * cfg.dx;
    const double cy = (static_cast<double>(iy) + 0.5) * cfg.dy;
    const int haloCells0307 = cfg.solidAdjacentHaloCells0307 > 1 ? cfg.solidAdjacentHaloCells0307 : 1;
    const double halo = static_cast<double>(haloCells0307) * fmax(cfg.dx, cfg.dy);
    if (cfg.solidShape == 1) {
        const double dx = cx - cfg.circleCx;
        const double dy = cy - cfg.circleCy;
        const double r = sqrt(dx * dx + dy * dy);
        return (r >= cfg.circleR && r <= cfg.circleR + halo);
    }
    if (cfg.solidShape == 2) {
        const bool insideRect = (cx >= cfg.rectXMin && cx <= cfg.rectXMax && cy >= cfg.rectYMin && cy <= cfg.rectYMax);
        if (insideRect) return false;
        const double qx = fmax(fmax(cfg.rectXMin - cx, 0.0), cx - cfg.rectXMax);
        const double qy = fmax(fmax(cfg.rectYMin - cy, 0.0), cy - cfg.rectYMax);
        const double dist = sqrt(qx * qx + qy * qy);
        return dist <= halo;
    }
    return false;
}

__device__ bool chi_allows_resampling_0297(int c, const float* __restrict__ chiField, DevicePopulationGuardConfig0297 cfg) {
    if (!cfg.chiFilterEnable || chiField == nullptr) return true;
    if (c < 0 || c >= cfg.numCells) return false;
    const double chi = static_cast<double>(chiField[c]);
    return isfinite(chi) && chi >= cfg.chiMin;
}

__global__ void reset_population_guard_buffers_kernel_0297(
    int numCells,
    unsigned int* __restrict__ poorCount,
    unsigned int* __restrict__ richCount,
    unsigned int* __restrict__ inactiveCount,
    unsigned int* __restrict__ poorDonor,
    unsigned long long* __restrict__ poorDonorMassBits0307,
    double* __restrict__ minima0307,
    unsigned int* __restrict__ richKeep,
    unsigned int* __restrict__ richExtract,
    unsigned int* __restrict__ emptyCount0319,
    double* __restrict__ emptyAdded0319,
    unsigned long long* __restrict__ counters) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c < numCells) {
        poorDonor[c] = kInvalidParticle0297;
        if (poorDonorMassBits0307) poorDonorMassBits0307[c] = 0ull;
        richKeep[c] = kInvalidParticle0297;
        richExtract[c] = kInvalidParticle0297;
    }
    if (c == 0) {
        *poorCount = 0u;
        *richCount = 0u;
        *inactiveCount = 0u;
        if (emptyCount0319) *emptyCount0319 = 0u;
        if (emptyAdded0319) {
            for (int i = 0; i < 6; ++i) emptyAdded0319[i] = 0.0;
        }
        for (int i = 0; i < 32; ++i) counters[i] = 0ull;
        if (minima0307) {
            minima0307[0] = 1.0e300;
            minima0307[1] = 1.0e300;
            minima0307[2] = 1.0e300;
        }
    }
}

__global__ void classify_population_guard_cells_kernel_0297(
    const unsigned int* __restrict__ cellCount,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    unsigned int* __restrict__ poorPending0490j,
    unsigned int* __restrict__ richPending0490j,
    unsigned int* __restrict__ poorCells,
    unsigned int* __restrict__ richCells,
    unsigned int* __restrict__ poorCount,
    unsigned int* __restrict__ richCount,
    unsigned long long* __restrict__ counters) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= cfg.numCells) return;
    if (!cell_center_inside_active_domain_0297(c, cfg)) return;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) {
        atomicAdd(&counters[22], 1ull);
        return;
    }
    const int n = static_cast<int>(cellCount[c]);
    bool poor = cfg.nMin > 0 && n > 0 && n < cfg.nMin;
    bool rich = cfg.nMax > 0 && n > cfg.nMax;
    if (cfg.speciesPopulationGuardEnable0490j && poorPending0490j && richPending0490j) {
        unsigned int poorPending = poorPending0490j[c];
        unsigned int richPending = richPending0490j[c];
        if (n <= 0) {
            poorPending = 0u;
            richPending = 0u;
        } else if (cfg.nMin > 0 && n < cfg.nMin) {
            poorPending = 1u;
            richPending = 0u;
        } else if (cfg.nMax > 0 && n > cfg.nMax) {
            poorPending = 0u;
            richPending = 1u;
        } else {
            if (poorPending && n >= cfg.nTarget) poorPending = 0u;
            if (richPending && n <= cfg.nTarget) richPending = 0u;
        }
        poorPending0490j[c] = poorPending;
        richPending0490j[c] = richPending;
        poor = poorPending && n > 0 && n < cfg.nTarget;
        rich = richPending && n > cfg.nTarget;
    }
    if (!poor && !rich) return;
    const int reason0299 = population_guard_exclusion_reason_0299(c, cfg);
    if (reason0299 == 1) {
        atomicAdd(&counters[5], 1ull);
        return;
    }
    if (reason0299 == 2) {
        atomicAdd(&counters[6], 1ull);
        return;
    }
    if (reason0299 == 3) {
        atomicAdd(&counters[7], 1ull);
        return;
    }
    if (poor) {
        const unsigned int k = atomicAdd(poorCount, 1u);
        poorCells[k] = static_cast<unsigned int>(c);
    } else if (rich) {
        const unsigned int k = atomicAdd(richCount, 1u);
        richCells[k] = static_cast<unsigned int>(c);
    }
}

__global__ void accumulate_current_cell_types_kernel_0490c(
    int nParticles,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ type,
    DevicePopulationGuardConfig0297 cfg,
    unsigned int* __restrict__ currentType,
    unsigned int* __restrict__ currentMixed) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    const unsigned int ti = type[i];
    const unsigned int old = atomicCAS(&currentType[c], kInvalidParticle0297, ti);
    if (old != kInvalidParticle0297 && old != ti) {
        atomicExch(&currentMixed[c], 1u);
    }
}


__device__ inline int species_index_0490f(
    unsigned int type,
    const unsigned int* __restrict__ speciesTypes,
    int speciesCount) {
    for (int s = 0; s < speciesCount; ++s) {
        if (speciesTypes[s] == type) return s;
    }
    return -1;
}

__device__ inline bool species_resampling_enabled_0493b(
    unsigned int type,
    const unsigned int* __restrict__ speciesTypes,
    const unsigned char* __restrict__ resamplingEnabled,
    int speciesCount) {
    if (speciesCount <= 0 || speciesTypes == nullptr || resamplingEnabled == nullptr) return true;
    const int si = species_index_0490f(type, speciesTypes, speciesCount);
    return si < 0 || resamplingEnabled[si] != 0u;
}

__global__ void accumulate_species_memory_and_moments_kernel_0490f(
    int nParticles,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ type,
    const double* __restrict__ mass,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    const unsigned int* __restrict__ speciesTypes,
    double* __restrict__ currentCellSpeciesMass,
    double* __restrict__ speciesMomentsBefore,
    unsigned long long* __restrict__ counters) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    const double m = mass[i];
    if (!(m > 0.0) || !isfinite(m)) return;
    const int si = species_index_0490f(type[i], speciesTypes, cfg.speciesCount0490f);
    if (si < 0) {
        atomicAdd(&counters[26], 1ull);
        return;
    }
    atomic_add_double_compat_0297(
        &currentCellSpeciesMass[static_cast<std::size_t>(c) * static_cast<std::size_t>(cfg.speciesCount0490f) + static_cast<std::size_t>(si)], m);
    atomic_add_double_compat_0297(&speciesMomentsBefore[3 * si + 0], m);
    atomic_add_double_compat_0297(&speciesMomentsBefore[3 * si + 1], m * vx[i]);
    atomic_add_double_compat_0297(&speciesMomentsBefore[3 * si + 2], m * vy[i]);
}

__device__ inline int cell_from_position_0490f(
    double x, double y, DevicePopulationGuardConfig0297 cfg) {
    int ix = static_cast<int>(floor(x / cfg.dx));
    int iy = static_cast<int>(floor(y / cfg.dy));
    if (ix < 0) ix = 0;
    if (ix >= cfg.nx) ix = cfg.nx - 1;
    if (iy < 0) iy = 0;
    if (iy >= cfg.ny) iy = cfg.ny - 1;
    return iy * cfg.nx + ix;
}

__global__ void accumulate_species_moments_after_kernel_0490f(
    int nParticles,
    const unsigned char* __restrict__ role,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const unsigned int* __restrict__ type,
    const double* __restrict__ mass,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    const unsigned int* __restrict__ speciesTypes,
    double* __restrict__ speciesMomentsAfter) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    if (cfg.chiFilterEnable) {
        // Newly refilled particles have not yet gone through a fresh cell-ID
        // deposit. Use their current position for the chi inclusion test rather
        // than trusting a potentially stale but numerically valid cellId slot.
        const int c = cell_from_position_0490f(x[i], y[i], cfg);
        if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    }
    const double m = mass[i];
    if (!(m > 0.0) || !isfinite(m)) return;
    const int si = species_index_0490f(type[i], speciesTypes, cfg.speciesCount0490f);
    if (si < 0) return;
    atomic_add_double_compat_0297(&speciesMomentsAfter[3 * si + 0], m);
    atomic_add_double_compat_0297(&speciesMomentsAfter[3 * si + 1], m * vx[i]);
    atomic_add_double_compat_0297(&speciesMomentsAfter[3 * si + 2], m * vy[i]);
}

__global__ void scale_and_shift_species_particles_kernel_0490f(
    int nParticles,
    const unsigned char* __restrict__ role,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const unsigned int* __restrict__ type,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    const unsigned int* __restrict__ speciesTypes,
    const unsigned char* __restrict__ resamplingEnabled,
    const double* __restrict__ scaleShift,
    double* __restrict__ mass,
    double* __restrict__ vx,
    double* __restrict__ vy) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    if (cfg.chiFilterEnable) {
        // Newly refilled particles have not yet gone through a fresh cell-ID
        // deposit. Use their current position for the chi inclusion test rather
        // than trusting a potentially stale but numerically valid cellId slot.
        const int c = cell_from_position_0490f(x[i], y[i], cfg);
        if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    }
    const int si = species_index_0490f(type[i], speciesTypes, cfg.speciesCount0490f);
    if (si < 0 || !resamplingEnabled || resamplingEnabled[si] == 0u) return;
    const double scale = scaleShift[3 * si + 0];
    if (mass[i] > 0.0 && isfinite(mass[i])) mass[i] *= scale;
    vx[i] += scaleShift[3 * si + 1];
    vy[i] += scaleShift[3 * si + 2];
}

__global__ void update_empty_refill_memory_kernel_0319(
    int numCells,
    const unsigned int* __restrict__ cellCount,
    const double* __restrict__ cellMass,
    const double* __restrict__ cellUx,
    const double* __restrict__ cellUy,
    const float* __restrict__ chiField,
    const unsigned int* __restrict__ currentType,
    const unsigned int* __restrict__ currentMixed,
    DevicePopulationGuardConfig0297 cfg,
    unsigned long long step,
    double* __restrict__ lastMass,
    double* __restrict__ lastUx,
    double* __restrict__ lastUy,
    unsigned int* __restrict__ lastType,
    unsigned int* __restrict__ lastMixed,
    const double* __restrict__ currentCellSpeciesMass,
    double* __restrict__ lastCellSpeciesMass,
    unsigned long long* __restrict__ lastStep,
    unsigned long long* __restrict__ counters) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    const double m = cellMass[c];
    if (cellCount[c] == 0u || !(m > 0.0) || !isfinite(m)) return;
    const unsigned int rememberedType = currentType[c];
    if (rememberedType == kInvalidParticle0297) return;
    lastMass[c] = m;
    lastUx[c] = cellUx[c];
    lastUy[c] = cellUy[c];
    lastType[c] = rememberedType;
    lastMixed[c] = currentMixed[c];
    if (cfg.speciesCompositionEnable0490f && cfg.speciesCount0490f > 0 &&
        currentCellSpeciesMass && lastCellSpeciesMass) {
        const std::size_t base = static_cast<std::size_t>(c) * static_cast<std::size_t>(cfg.speciesCount0490f);
        for (int si = 0; si < cfg.speciesCount0490f; ++si) {
            lastCellSpeciesMass[base + static_cast<std::size_t>(si)] =
                currentCellSpeciesMass[base + static_cast<std::size_t>(si)];
        }
    }
    lastStep[c] = step;
    atomicAdd(&counters[21], 1ull);
}

__global__ void classify_empty_refill_cells_kernel_0319(
    const unsigned int* __restrict__ cellCount,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    unsigned long long step,
    const unsigned int* __restrict__ lastType,
    const unsigned int* __restrict__ lastMixed,
    const unsigned int* __restrict__ speciesTypes,
    const unsigned char* __restrict__ resamplingEnabled,
    const double* __restrict__ lastCellSpeciesMass,
    const unsigned long long* __restrict__ lastStep,
    unsigned int* __restrict__ emptyCells,
    unsigned int* __restrict__ emptyCount,
    unsigned long long* __restrict__ counters) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= cfg.numCells || !cfg.emptyRefillEnable0319 || cfg.emptyRefillTarget0319 <= 0) return;
    if (cellCount[c] != 0u) return;
    if (!cell_center_inside_active_domain_0297(c, cfg)) return;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) {
        atomicAdd(&counters[22], 1ull);
        return;
    }
    const int reason0299 = population_guard_exclusion_reason_0299(c, cfg);
    if (reason0299 == 1) { atomicAdd(&counters[5], 1ull); return; }
    if (reason0299 == 2) { atomicAdd(&counters[6], 1ull); return; }
    if (reason0299 == 3) { atomicAdd(&counters[7], 1ull); return; }
    atomicAdd(&counters[16], 1ull);
    const unsigned long long last = lastStep[c];
    const bool validAge = last > 0ull && step >= last &&
        (cfg.emptyRefillMemoryMaxAge0319 == 0 ||
         (step - last) <= static_cast<unsigned long long>(cfg.emptyRefillMemoryMaxAge0319));
    if (!validAge || lastType[c] == kInvalidParticle0297) {
        atomicAdd(&counters[19], 1ull);
        return;
    }
    if (lastMixed[c] == 0u &&
        !species_resampling_enabled_0493b(
            lastType[c], speciesTypes, resamplingEnabled, cfg.speciesCount0490f)) {
        return;
    }
    if (lastMixed[c] != 0u) {
        if (!cfg.speciesCompositionEnable0490f || cfg.speciesCount0490f <= 0 || !lastCellSpeciesMass) {
            atomicAdd(&counters[23], 1ull);
            return;
        }
        const std::size_t base = static_cast<std::size_t>(c) * static_cast<std::size_t>(cfg.speciesCount0490f);
        int present = 0;
        for (int si = 0; si < cfg.speciesCount0490f; ++si) {
            if (!resamplingEnabled || resamplingEnabled[si] == 0u) continue;
            const double ms = lastCellSpeciesMass[base + static_cast<std::size_t>(si)];
            if (ms > 0.0 && isfinite(ms)) ++present;
        }
        if (present <= 0 || present > cfg.emptyRefillTarget0319) {
            atomicAdd(&counters[24], 1ull);
            return;
        }
    }
    const unsigned int k = atomicAdd(emptyCount, 1u);
    emptyCells[k] = static_cast<unsigned int>(c);
}

__device__ inline int refill_species_target_count_0490f(
    int si,
    int target,
    int present,
    double totalMass,
    const double* __restrict__ speciesMass,
    const unsigned int* __restrict__ speciesTypes,
    const unsigned char* __restrict__ resamplingEnabled,
    int speciesCount) {
    if (!resamplingEnabled || resamplingEnabled[si] == 0u) return 0;
    const double ms = speciesMass[si];
    if (!(ms > 0.0) || !isfinite(ms)) return 0;
    const int remaining = target - present;
    if (remaining <= 0) return 1;
    const double exact = static_cast<double>(remaining) * ms / totalMass;
    const int floorPart = static_cast<int>(floor(exact));
    int floorSum = 0;
    for (int sj = 0; sj < speciesCount; ++sj) {
        if (resamplingEnabled[sj] == 0u) continue;
        const double mj = speciesMass[sj];
        if (!(mj > 0.0) || !isfinite(mj)) continue;
        floorSum += static_cast<int>(floor(static_cast<double>(remaining) * mj / totalMass));
    }
    const int leftovers = remaining - floorSum;
    const double remainder = exact - floor(exact);
    int rank = 0;
    for (int sj = 0; sj < speciesCount; ++sj) {
        if (sj == si || resamplingEnabled[sj] == 0u) continue;
        const double mj = speciesMass[sj];
        if (!(mj > 0.0) || !isfinite(mj)) continue;
        const double exactJ = static_cast<double>(remaining) * mj / totalMass;
        const double remainderJ = exactJ - floor(exactJ);
        if (remainderJ > remainder ||
            (remainderJ == remainder && speciesTypes[sj] < speciesTypes[si])) {
            ++rank;
        }
    }
    return 1 + floorPart + (rank < leftovers ? 1 : 0);
}

__global__ void empty_refill_cells_kernel_0319(
    unsigned int emptyCount,
    const unsigned int* __restrict__ emptyCells,
    unsigned int* __restrict__ inactiveCursor,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    unsigned int* __restrict__ type,
    unsigned char* __restrict__ role,
    DevicePopulationGuardConfig0297 cfg,
    const double* __restrict__ lastMass,
    const double* __restrict__ lastUx,
    const double* __restrict__ lastUy,
    const unsigned int* __restrict__ lastType,
    const unsigned int* __restrict__ lastMixed,
    const unsigned int* __restrict__ speciesTypes,
    const unsigned char* __restrict__ resamplingEnabled,
    const double* __restrict__ lastCellSpeciesMass,
    double* __restrict__ speciesMomentsAdded,
    double* __restrict__ emptyAdded,
    unsigned long long* __restrict__ counters) {
    const unsigned int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k >= emptyCount) return;
    const unsigned int c = emptyCells[k];
    const int target = cfg.emptyRefillTarget0319;
    const double cellMass = lastMass[c];
    if (target <= 0 || !(cellMass > 0.0) || !isfinite(cellMass)) {
        atomicAdd(&counters[19], 1ull);
        return;
    }

    const bool composition = cfg.speciesCompositionEnable0490f &&
        cfg.speciesCount0490f > 0 && speciesTypes && lastCellSpeciesMass && speciesMomentsAdded;
    int present = 0;
    double rememberedSpeciesMass = 0.0;
    const std::size_t base = static_cast<std::size_t>(c) * static_cast<std::size_t>(cfg.speciesCount0490f);
    if (composition) {
        for (int si = 0; si < cfg.speciesCount0490f; ++si) {
            if (!resamplingEnabled || resamplingEnabled[si] == 0u) continue;
            const double ms = lastCellSpeciesMass[base + static_cast<std::size_t>(si)];
            if (ms > 0.0 && isfinite(ms)) {
                ++present;
                rememberedSpeciesMass += ms;
            }
        }
        if (present <= 0 || target < present || !(rememberedSpeciesMass > 0.0)) {
            atomicAdd(&counters[24], 1ull);
            return;
        }
    }

    const unsigned int first = atomicAdd(inactiveCursor, static_cast<unsigned int>(target));
    if (static_cast<unsigned long long>(first) + static_cast<unsigned long long>(target) > cfg.activeCapacity0315) {
        atomicAdd(&counters[20], 1ull);
        return;
    }
    const int ix = static_cast<int>(c % static_cast<unsigned int>(cfg.nx));
    const int iy = static_cast<int>(c / static_cast<unsigned int>(cfg.nx));
    const double xmin = static_cast<double>(ix) * cfg.dx;
    const double ymin = static_cast<double>(iy) * cfg.dy;
    const double ux = lastUx[c];
    const double uy = lastUy[c];

    int jGlobal = 0;
    if (composition) {
        const double* cellSpeciesMass = lastCellSpeciesMass + base;
        for (int si = 0; si < cfg.speciesCount0490f; ++si) {
            if (!resamplingEnabled || resamplingEnabled[si] == 0u) continue;
            const double ms = cellSpeciesMass[si];
            if (!(ms > 0.0) || !isfinite(ms)) continue;
            const int countSi = refill_species_target_count_0490f(
                si, target, present, rememberedSpeciesMass,
                cellSpeciesMass, speciesTypes, resamplingEnabled, cfg.speciesCount0490f);
            if (countSi <= 0) continue;
            const double mp = ms / static_cast<double>(countSi);
            for (int q = 0; q < countSi; ++q, ++jGlobal) {
                const unsigned long long slot64 = cfg.activeBase0315 +
                    static_cast<unsigned long long>(first + static_cast<unsigned int>(jGlobal));
                if (slot64 >= cfg.activeBase0315 + cfg.activeCapacity0315) {
                    atomicAdd(&counters[20], 1ull);
                    return;
                }
                const unsigned int slot = static_cast<unsigned int>(slot64);
                if (role[slot] != static_cast<unsigned char>(kParticleRoleInactive)) {
                    atomicAdd(&counters[20], 1ull);
                    return;
                }
                const double fx = (static_cast<double>((jGlobal * 37 + static_cast<int>(k) * 11) % 997) + 0.5) / 997.0;
                const double fy = (static_cast<double>((jGlobal * 53 + static_cast<int>(k) * 17) % 991) + 0.5) / 991.0;
                const double xlo = xmin + 1.0e-12 * cfg.dx;
                const double xhi = xmin + cfg.dx - 1.0e-12 * cfg.dx;
                const double ylo = ymin + 1.0e-12 * cfg.dy;
                const double yhi = ymin + cfg.dy - 1.0e-12 * cfg.dy;
                x[slot] = fmin(fmax(xmin + fx * cfg.dx, xlo), xhi);
                y[slot] = fmin(fmax(ymin + fy * cfg.dy, ylo), yhi);
                vx[slot] = ux;
                vy[slot] = uy;
                mass[slot] = mp;
                type[slot] = speciesTypes[si];
                role[slot] = static_cast<unsigned char>(kParticleRoleFluid);
            }
            atomic_add_double_compat_0297(&speciesMomentsAdded[3 * si + 0], ms);
            atomic_add_double_compat_0297(&speciesMomentsAdded[3 * si + 1], ms * ux);
            atomic_add_double_compat_0297(&speciesMomentsAdded[3 * si + 2], ms * uy);
        }
        if (jGlobal != target) {
            atomicAdd(&counters[24], 1ull);
            return;
        }
        if (lastMixed && lastMixed[c] != 0u) atomicAdd(&counters[25], 1ull);
        atomic_add_double_compat_0297(&emptyAdded[0], rememberedSpeciesMass);
        atomic_add_double_compat_0297(&emptyAdded[1], rememberedSpeciesMass * ux);
        atomic_add_double_compat_0297(&emptyAdded[2], rememberedSpeciesMass * uy);
    } else {
        if (!species_resampling_enabled_0493b(
                lastType[c], speciesTypes, resamplingEnabled, cfg.speciesCount0490f)) {
            atomicAdd(&counters[30], 1ull);
            return;
        }
        const double mp = cellMass / static_cast<double>(target);
        for (int j = 0; j < target; ++j) {
            const unsigned long long slot64 = cfg.activeBase0315 +
                static_cast<unsigned long long>(first + static_cast<unsigned int>(j));
            if (slot64 >= cfg.activeBase0315 + cfg.activeCapacity0315) {
                atomicAdd(&counters[20], 1ull);
                return;
            }
            const unsigned int slot = static_cast<unsigned int>(slot64);
            if (role[slot] != static_cast<unsigned char>(kParticleRoleInactive)) {
                atomicAdd(&counters[20], 1ull);
                return;
            }
            const double fx = (static_cast<double>((j * 37 + static_cast<int>(k) * 11) % 997) + 0.5) / 997.0;
            const double fy = (static_cast<double>((j * 53 + static_cast<int>(k) * 17) % 991) + 0.5) / 991.0;
            const double xlo = xmin + 1.0e-12 * cfg.dx;
            const double xhi = xmin + cfg.dx - 1.0e-12 * cfg.dx;
            const double ylo = ymin + 1.0e-12 * cfg.dy;
            const double yhi = ymin + cfg.dy - 1.0e-12 * cfg.dy;
            x[slot] = fmin(fmax(xmin + fx * cfg.dx, xlo), xhi);
            y[slot] = fmin(fmax(ymin + fy * cfg.dy, ylo), yhi);
            vx[slot] = ux;
            vy[slot] = uy;
            mass[slot] = mp;
            type[slot] = lastType[c];
            role[slot] = static_cast<unsigned char>(kParticleRoleFluid);
        }
        atomic_add_double_compat_0297(&emptyAdded[0], cellMass);
        atomic_add_double_compat_0297(&emptyAdded[1], cellMass * ux);
        atomic_add_double_compat_0297(&emptyAdded[2], cellMass * uy);
    }
    atomicAdd(&counters[17], 1ull);
    atomicAdd(&counters[18], static_cast<unsigned long long>(target));
}

__global__ void accumulate_chi_allowed_moments_kernel_0319(
    int numCells,
    const unsigned int* __restrict__ cellCount,
    const double* __restrict__ cellMass,
    const double* __restrict__ cellUx,
    const double* __restrict__ cellUy,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    double* __restrict__ emptyAdded) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= numCells) return;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    const double m = cellMass[c];
    if (!(m > 0.0) || !isfinite(m) || cellCount[c] == 0u) return;
    atomic_add_double_compat_0297(&emptyAdded[3], m);
    atomic_add_double_compat_0297(&emptyAdded[4], m * cellUx[c]);
    atomic_add_double_compat_0297(&emptyAdded[5], m * cellUy[c]);
}

__global__ void scale_and_shift_active_particles_kernel_0319(
    int nParticles,
    double massScale,
    double dvx,
    double dvy,
    unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    double* __restrict__ mass,
    double* __restrict__ vx,
    double* __restrict__ vy) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId ? cellId[i] : -1;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    if (mass[i] > 0.0 && isfinite(mass[i])) mass[i] *= massScale;
    vx[i] += dvx;
    vy[i] += dvy;
}

__global__ void select_species_population_policy_kernel_0490j(
    const unsigned int* __restrict__ totalCellCount,
    CudaSpeciesCellDeviceView0490h species,
    DevicePopulationGuardConfig0297 cfg,
    const unsigned int* __restrict__ poorPending0490j,
    const unsigned int* __restrict__ richPending0490j,
    unsigned int* __restrict__ poorSelectedType,
    unsigned int* __restrict__ richSelectedType,
    unsigned long long* __restrict__ counters) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c >= cfg.numCells) return;
    poorSelectedType[c] = kInvalidParticle0297;
    richSelectedType[c] = kInvalidParticle0297;
    if (!cfg.speciesPopulationGuardEnable0490j || cfg.speciesCount0490j <= 0 ||
        species.speciesCount != cfg.speciesCount0490j || species.numCells != cfg.numCells) return;

    const int total = static_cast<int>(totalCellCount[c]);
    const bool poor = poorPending0490j && poorPending0490j[c] &&
        total > 0 && total < cfg.nTarget;
    const bool rich = richPending0490j && richPending0490j[c] &&
        total > cfg.nTarget;
    if (!poor && !rich) return;

    int present = 0;
    int fixedCount = 0;
    double weightSum = 0.0;
    for (int s = 0; s < cfg.speciesCount0490j; ++s) {
        const int k = s * cfg.numCells + c;
        if (!species.resamplingEnabled || species.resamplingEnabled[s] == 0u) {
            fixedCount += static_cast<int>(species.count[k]);
            continue;
        }
        const unsigned int count = species.count[k];
        const double ref = species.referenceCellMass[s];
        const double mass = species.mass[k];
        if (count == 0u || !(ref > 0.0) || !isfinite(ref) || !(mass > 0.0) || !isfinite(mass)) continue;
        present += 1;
        weightSum += mass / ref;
    }
    const int mutableTarget = cfg.nTarget > fixedCount ? cfg.nTarget - fixedCount : 0;
    if (present == 0 || !(weightSum > 0.0) || mutableTarget <= 0) return;
    if (present > mutableTarget) atomicAdd(&counters[29], 1ull);

    const int guaranteed = present < mutableTarget ? present : mutableTarget;
    const int remaining = mutableTarget > guaranteed ? mutableTarget - guaranteed : 0;
    int baseAssigned = 0;
    for (int s = 0; s < cfg.speciesCount0490j; ++s) {
        const int k = s * cfg.numCells + c;
        if (!species.resamplingEnabled || species.resamplingEnabled[s] == 0u) continue;
        const unsigned int count = species.count[k];
        const double ref = species.referenceCellMass[s];
        const double mass = species.mass[k];
        if (count == 0u || !(ref > 0.0) || !isfinite(ref) || !(mass > 0.0) || !isfinite(mass)) continue;
        const double weight = mass / ref;
        const double ideal = remaining > 0 ? static_cast<double>(remaining) * weight / weightSum : 0.0;
        baseAssigned += static_cast<int>(floor(ideal));
    }
    const int leftover = remaining > baseAssigned ? remaining - baseAssigned : 0;

    int bestDeficit = 0;
    int bestExcess = 0;
    unsigned int bestPoorType = kInvalidParticle0297;
    unsigned int bestRichType = kInvalidParticle0297;
    for (int s = 0; s < cfg.speciesCount0490j; ++s) {
        const int k = s * cfg.numCells + c;
        if (!species.resamplingEnabled || species.resamplingEnabled[s] == 0u) continue;
        const unsigned int count = species.count[k];
        const double ref = species.referenceCellMass[s];
        const double mass = species.mass[k];
        if (count == 0u || !(ref > 0.0) || !isfinite(ref) || !(mass > 0.0) || !isfinite(mass)) continue;
        const unsigned int type = species.speciesTypes[s];
        const double weight = mass / ref;

        int target = 0;
        if (present <= mutableTarget) {
            target = 1;
        } else {
            int weightRank = 0;
            for (int t = 0; t < cfg.speciesCount0490j; ++t) {
                const int kt = t * cfg.numCells + c;
                if (!species.resamplingEnabled || species.resamplingEnabled[t] == 0u) continue;
                const unsigned int ct = species.count[kt];
                const double rt = species.referenceCellMass[t];
                const double mt = species.mass[kt];
                if (ct == 0u || !(rt > 0.0) || !isfinite(rt) || !(mt > 0.0) || !isfinite(mt)) continue;
                const double wt = mt / rt;
                const unsigned int tt = species.speciesTypes[t];
                if (wt > weight || (wt == weight && tt < type)) weightRank += 1;
            }
            target = weightRank < mutableTarget ? 1 : 0;
        }

        if (remaining > 0) {
            const double ideal = static_cast<double>(remaining) * weight / weightSum;
            const int base = static_cast<int>(floor(ideal));
            target += base;
            const double remainder = ideal - static_cast<double>(base);
            int remainderRank = 0;
            for (int t = 0; t < cfg.speciesCount0490j; ++t) {
                const int kt = t * cfg.numCells + c;
                if (!species.resamplingEnabled || species.resamplingEnabled[t] == 0u) continue;
                const unsigned int ct = species.count[kt];
                const double rt = species.referenceCellMass[t];
                const double mt = species.mass[kt];
                if (ct == 0u || !(rt > 0.0) || !isfinite(rt) || !(mt > 0.0) || !isfinite(mt)) continue;
                const double wt = mt / rt;
                const double it = static_cast<double>(remaining) * wt / weightSum;
                const double remt = it - floor(it);
                const unsigned int tt = species.speciesTypes[t];
                if (remt > remainder || (remt == remainder && tt < type)) remainderRank += 1;
            }
            if (remainderRank < leftover) target += 1;
        }

        const int deficit = target - static_cast<int>(count);
        const int excess = static_cast<int>(count) - target;
        if (poor && deficit > 0 &&
            (deficit > bestDeficit || (deficit == bestDeficit && type < bestPoorType))) {
            bestDeficit = deficit;
            bestPoorType = type;
        }
        if (rich && count >= 2u && excess > 0 &&
            (excess > bestExcess || (excess == bestExcess && type < bestRichType))) {
            bestExcess = excess;
            bestRichType = type;
        }
    }

    if (poor && bestPoorType != kInvalidParticle0297) {
        poorSelectedType[c] = bestPoorType;
        atomicAdd(&counters[27], 1ull);
    }
    if (rich && bestRichType != kInvalidParticle0297) {
        richSelectedType[c] = bestRichType;
        atomicAdd(&counters[28], 1ull);
    }
}

__global__ void select_population_guard_primary_particles_kernel_0297(
    int nParticles,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ cellCount,
    const double* __restrict__ mass,
    const unsigned int* __restrict__ type,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    const unsigned int* __restrict__ poorSelectedType0490j,
    const unsigned int* __restrict__ richSelectedType0490j,
    unsigned int* __restrict__ poorDonor,
    unsigned long long* __restrict__ poorDonorMassBits0307,
    unsigned int* __restrict__ richKeep) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    if (!point_inside_active_domain_0297(x[i], y[i], cfg)) return;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    const int n = static_cast<int>(cellCount[c]);
    const bool poor0490j = cfg.speciesPopulationGuardEnable0490j &&
        poorSelectedType0490j != nullptr &&
        poorSelectedType0490j[c] != kInvalidParticle0297;
    const bool rich0490j = cfg.speciesPopulationGuardEnable0490j &&
        richSelectedType0490j != nullptr &&
        richSelectedType0490j[c] != kInvalidParticle0297;
    if (poor0490j || (!cfg.speciesPopulationGuardEnable0490j &&
                      n > 0 && cfg.nMin > 0 && n < cfg.nMin)) {
        if (cfg.speciesPopulationGuardEnable0490j &&
            type[i] != poorSelectedType0490j[c]) return;
        if (cfg.preferMaxMassDonor0307 && mass != nullptr && poorDonorMassBits0307 != nullptr) {
            const double mi = mass[i];
            if (mi > 0.0 && isfinite(mi)) {
                const unsigned long long bits = static_cast<unsigned long long>(__double_as_longlong(mi));
                const unsigned long long old = atomicMax(&poorDonorMassBits0307[c], bits);
                if (bits >= old) poorDonor[c] = static_cast<unsigned int>(i);
            }
        } else {
            atomicMin(&poorDonor[c], static_cast<unsigned int>(i));
        }
    } else if (rich0490j || (!cfg.speciesPopulationGuardEnable0490j &&
                             cfg.nMax > 0 && n > cfg.nMax)) {
        if (cfg.speciesPopulationGuardEnable0490j &&
            type[i] != richSelectedType0490j[c]) return;
        atomicMin(&richKeep[c], static_cast<unsigned int>(i));
    }
}

__global__ void select_population_guard_rich_extract_kernel_0297(
    int nParticles,
    const double* __restrict__ x,
    const double* __restrict__ y,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ cellCount,
    const unsigned int* __restrict__ type,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    const unsigned int* __restrict__ richKeep,
    unsigned int* __restrict__ richExtract) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= cfg.numCells) return;
    if (!point_inside_active_domain_0297(x[i], y[i], cfg)) return;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    const int n = static_cast<int>(cellCount[c]);
    if (cfg.speciesPopulationGuardEnable0490j) {
        if (!(n > cfg.nTarget)) return;
    } else if (!(cfg.nMax > 0 && n > cfg.nMax)) {
        return;
    }
    const unsigned int keep = richKeep[c];
    const unsigned int ui = static_cast<unsigned int>(i);
    if (keep == kInvalidParticle0297 || ui == keep) return;
    if (type[ui] != type[keep]) return;
    atomicMin(&richExtract[c], ui);
}

__global__ void merge_rich_cells_kernel_0297(
    unsigned int richCount,
    const unsigned int* __restrict__ richCells,
    unsigned int* __restrict__ richKeep,
    unsigned int* __restrict__ richExtract,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    const unsigned int* __restrict__ type,
    unsigned char* __restrict__ role,
    const unsigned int* __restrict__ speciesTypes,
    const unsigned char* __restrict__ resamplingEnabled,
    int speciesCount,
    unsigned long long* __restrict__ counters) {
    const unsigned int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k >= richCount) return;
    const unsigned int c = richCells[k];
    const unsigned int keep = richKeep[c];
    const unsigned int drop = richExtract[c];
    if (keep == kInvalidParticle0297 || drop == kInvalidParticle0297 || keep == drop) {
        atomicAdd(&counters[4], 1ull);
        return;
    }
    if (role[keep] != static_cast<unsigned char>(kParticleRoleFluid) ||
        role[drop] != static_cast<unsigned char>(kParticleRoleFluid) ||
        type[keep] != type[drop]) {
        atomicAdd(&counters[4], 1ull);
        return;
    }
    if (!species_resampling_enabled_0493b(
            type[keep], speciesTypes, resamplingEnabled, speciesCount)) {
        atomicAdd(&counters[30], 1ull);
        return;
    }
    const double mk = mass[keep];
    const double md = mass[drop];
    if (!(mk > 0.0) || !(md > 0.0)) {
        atomicAdd(&counters[4], 1ull);
        return;
    }
    const double M = mk + md;
    const double px = mk * vx[keep] + md * vx[drop];
    const double py = mk * vy[keep] + md * vy[drop];
    mass[keep] = M;
    vx[keep] = px / M;
    vy[keep] = py / M;
    mass[drop] = 0.0;
    vx[drop] = 0.0;
    vy[drop] = 0.0;
    role[drop] = static_cast<unsigned char>(kParticleRoleInactive);
    atomicAdd(&counters[0], 1ull);
}

__device__ void copy_particle_slot_0315(unsigned long long dst,
                                        unsigned long long src,
                                        double* __restrict__ x,
                                        double* __restrict__ y,
                                        double* __restrict__ vx,
                                        double* __restrict__ vy,
                                        double* __restrict__ mass,
                                        unsigned int* __restrict__ type,
                                        unsigned char* __restrict__ role) {
    x[dst] = x[src];
    y[dst] = y[src];
    vx[dst] = vx[src];
    vy[dst] = vy[src];
    mass[dst] = mass[src];
    type[dst] = type[src];
    role[dst] = role[src];
}

__global__ void merge_rich_cells_prefix_safe_kernel_0315(
    unsigned int richCount,
    const unsigned int* __restrict__ richCells,
    unsigned int* __restrict__ richKeep,
    unsigned int* __restrict__ richExtract,
    unsigned long long activeBase,
    unsigned long long capacity,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    unsigned int* __restrict__ type,
    unsigned char* __restrict__ role,
    const unsigned int* __restrict__ speciesTypes,
    const unsigned char* __restrict__ resamplingEnabled,
    int speciesCount,
    unsigned long long* __restrict__ counters) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    unsigned long long active = activeBase + counters[1];
    if (active > capacity) active = capacity;

    for (unsigned int k = 0; k < richCount; ++k) {
        const unsigned int c = richCells[k];
        const unsigned int keep = richKeep[c];
        const unsigned int drop = richExtract[c];
        if (keep == kInvalidParticle0297 || drop == kInvalidParticle0297 || keep == drop ||
            static_cast<unsigned long long>(keep) >= active ||
            static_cast<unsigned long long>(drop) >= active) {
            counters[4] += 1ull;
            continue;
        }
        if (role[keep] != static_cast<unsigned char>(kParticleRoleFluid) ||
            role[drop] != static_cast<unsigned char>(kParticleRoleFluid) ||
            type[keep] != type[drop]) {
            counters[4] += 1ull;
            continue;
        }
        if (!species_resampling_enabled_0493b(
                type[keep], speciesTypes, resamplingEnabled, speciesCount)) {
            counters[30] += 1ull;
            continue;
        }
        const double mk = mass[keep];
        const double md = mass[drop];
        if (!(mk > 0.0) || !(md > 0.0) || !isfinite(mk) || !isfinite(md)) {
            counters[4] += 1ull;
            continue;
        }
        const double M = mk + md;
        const double px = mk * vx[keep] + md * vx[drop];
        const double py = mk * vy[keep] + md * vy[drop];
        mass[keep] = M;
        vx[keep] = px / M;
        vy[keep] = py / M;
        mass[drop] = 0.0;
        vx[drop] = 0.0;
        vy[drop] = 0.0;
        role[drop] = static_cast<unsigned char>(kParticleRoleInactive);
        counters[0] += 1ull;
    }

    unsigned long long left = 0ull;
    unsigned long long right = active;
    while (left < right) {
        if (role[left] == static_cast<unsigned char>(kParticleRoleFluid)) {
            ++left;
            continue;
        }
        do {
            if (right == 0ull) break;
            --right;
        } while (right > left && role[right] != static_cast<unsigned char>(kParticleRoleFluid));
        if (left >= right) break;
        copy_particle_slot_0315(left, right, x, y, vx, vy, mass, type, role);
        mass[right] = 0.0;
        vx[right] = 0.0;
        vy[right] = 0.0;
        role[right] = static_cast<unsigned char>(kParticleRoleInactive);
        ++left;
    }
}

__global__ void build_inactive_list_kernel_0297(
    int nParticles,
    const unsigned char* __restrict__ role,
    unsigned int* __restrict__ inactiveList,
    unsigned int* __restrict__ inactiveCount) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] == static_cast<unsigned char>(kParticleRoleInactive)) {
        const unsigned int k = atomicAdd(inactiveCount, 1u);
        inactiveList[k] = static_cast<unsigned int>(i);
    }
}

// 0313: bounded inactive-tail collector for the population guard.  The old
// build_inactive_list_kernel_0297 scans all particle slots.  With a large
// appended inactive reservoir that makes guard cost scale with capacity rather
// than with active support.  This fast path scans only a bounded tail window and
// falls back to the exact full scan when not enough inactive slots are found.
__global__ void build_inactive_tail_list_kernel_0313(
    int nParticles,
    int tailScan,
    const unsigned char* __restrict__ role,
    unsigned int* __restrict__ inactiveList,
    unsigned int* __restrict__ inactiveCount) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k >= tailScan || k >= nParticles) return;
    const int i = nParticles - 1 - k;
    if (role && role[i] == static_cast<unsigned char>(kParticleRoleInactive)) {
        const unsigned int pos = atomicAdd(inactiveCount, 1u);
        if (pos < static_cast<unsigned int>(tailScan)) inactiveList[pos] = static_cast<unsigned int>(i);
    }
}

int inactive_tail_scan_count_0313(int nParticles, unsigned int need) {
    if (nParticles <= 0 || need == 0u) return 0;
    const int minScan = std::max(1, env_int_0297("MPCD_CUDA_INACTIVE_TAIL_POOL_MIN_SCAN_0313", 8192));
    const int maxScan = std::max(1, env_int_0297("MPCD_CUDA_INACTIVE_TAIL_POOL_MAX_SCAN_0313", 262144));
    const int mult = std::max(1, env_int_0297("MPCD_CUDA_INACTIVE_TAIL_POOL_SCAN_MULT_0313", 4));
    long long scan = std::max<long long>(minScan, static_cast<long long>(need) * mult + 1024ll);
    scan = std::min<long long>(scan, maxScan);
    scan = std::min<long long>(scan, nParticles);
    return static_cast<int>(scan);
}

bool build_inactive_tail_list_0313(int nParticles,
                                   unsigned int need,
                                   const unsigned char* role,
                                   int block,
                                   unsigned int* inactiveList,
                                   unsigned int* inactiveCount) {
    const char* enableEnv0313 = std::getenv("MPCD_CUDA_INACTIVE_TAIL_POOL_0313");
    if (enableEnv0313 != nullptr && !env_truthy_0297("MPCD_CUDA_INACTIVE_TAIL_POOL_0313")) return false;
    if (nParticles <= 0 || need == 0u || role == nullptr || inactiveList == nullptr || inactiveCount == nullptr) return false;
    const int tailScan = inactive_tail_scan_count_0313(nParticles, need);
    if (tailScan <= 0) return false;
    cuda_check_0297(cudaMemset(inactiveCount, 0, sizeof(unsigned int)), "reset 0313 inactive tail count");
    const int grid = std::max(1, (tailScan + block - 1) / block);
    build_inactive_tail_list_kernel_0313<<<grid, block>>>(nParticles, tailScan, role, inactiveList, inactiveCount);
    cuda_check_0297(cudaGetLastError(), "launch build_inactive_tail_list_kernel_0313");
    unsigned int hCount = 0u;
    cuda_check_0297(cudaMemcpy(&hCount, inactiveCount, sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    "copy 0313 inactive tail count");
    if (hCount < need && !env_truthy_0297("MPCD_CUDA_INACTIVE_TAIL_POOL_NO_FALLBACK_0313")) {
        return false;
    }
    return true;
}

__device__ double clamp_0297(double v, double lo, double hi) {
    return fmin(fmax(v, lo), hi);
}

__global__ void split_poor_cells_kernel_0297(
    unsigned int poorCount,
    const unsigned int* __restrict__ poorCells,
    const unsigned int* __restrict__ inactiveList,
    const unsigned int* __restrict__ inactiveCount,
    unsigned int* __restrict__ inactiveCursor,
    const unsigned int* __restrict__ poorDonor,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    unsigned int* __restrict__ type,
    unsigned char* __restrict__ role,
    const unsigned int* __restrict__ speciesTypes,
    const unsigned char* __restrict__ resamplingEnabled,
    int speciesCount,
    DevicePopulationGuardConfig0297 cfg,
    unsigned long long* __restrict__ counters,
    double* __restrict__ minima0307) {
    const unsigned int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k >= poorCount) return;
    const unsigned int c = poorCells[k];
    const unsigned int donor = poorDonor[c];
    if (donor == kInvalidParticle0297 || role[donor] != static_cast<unsigned char>(kParticleRoleFluid)) {
        atomicAdd(&counters[3], 1ull);
        return;
    }
    if (!species_resampling_enabled_0493b(
            type[donor], speciesTypes, resamplingEnabled, speciesCount)) {
        atomicAdd(&counters[30], 1ull);
        return;
    }
    unsigned int slot = 0u;
    if (!cfg.activePrefixSafe0315) {
        const unsigned int slotOrdinal = atomicAdd(inactiveCursor, 1u);
        if (slotOrdinal >= *inactiveCount) {
            atomicAdd(&counters[2], 1ull);
            return;
        }
        slot = inactiveList[slotOrdinal];
        if (slot == donor || role[slot] != static_cast<unsigned char>(kParticleRoleInactive)) {
            atomicAdd(&counters[2], 1ull);
            return;
        }
    }
    const double md = mass[donor];
    if (!(md > 0.0) || !isfinite(md)) {
        atomicAdd(&counters[3], 1ull);
        return;
    }
    const bool solidAdjacent0307 = population_guard_solid_adjacent_0307(static_cast<int>(c), cfg);
    if (solidAdjacent0307) atomicAdd(&counters[10], 1ull);
    if (minima0307) atomic_min_double_positive_0307(&minima0307[0], md);

    if (cfg.splitSafety0307) {
        double donorMin = cfg.splitDonorMinMass0307;
        if (solidAdjacent0307 && cfg.solidAdjacentSplitMode0307 == 2) {
            atomicAdd(&counters[11], 1ull);
            return;
        }
        if (solidAdjacent0307 && cfg.solidAdjacentSplitMode0307 == 1) {
            donorMin = fmax(donorMin, cfg.solidAdjacentDonorMinMass0307);
        }
        if (donorMin > 0.0 && md < donorMin) {
            atomicAdd(&counters[8], 1ull);
            return;
        }
    }

    const double postFloor = fmax(cfg.minDonorMassAfterSplit, cfg.splitSafety0307 ? cfg.splitNewParticleMinMass0307 : 0.0);
    const double dm = fmin(md * cfg.splitFraction, fmax(0.0, md - postFloor));
    if (!(dm > 0.0) || !isfinite(dm)) {
        atomicAdd(&counters[3], 1ull);
        return;
    }
    if (cfg.splitSafety0307 && cfg.splitNewParticleMinMass0307 > 0.0 && dm < cfg.splitNewParticleMinMass0307) {
        atomicAdd(&counters[9], 1ull);
        return;
    }
    if (md < 0.5) atomicAdd(&counters[13], 1ull);
    if (md < 0.25) atomicAdd(&counters[14], 1ull);
    if (md < 0.1) atomicAdd(&counters[15], 1ull);
    if (minima0307) {
        atomic_min_double_positive_0307(&minima0307[1], dm);
        atomic_min_double_positive_0307(&minima0307[2], md - dm);
    }
    if (cfg.activePrefixSafe0315) {
        const unsigned int slotOrdinal = atomicAdd(inactiveCursor, 1u);
        if (slotOrdinal >= cfg.activeCapacity0315) {
            atomicAdd(&counters[2], 1ull);
            return;
        }
        slot = static_cast<unsigned int>(cfg.activeBase0315 + static_cast<unsigned long long>(slotOrdinal));
        if (slot == donor || role[slot] != static_cast<unsigned char>(kParticleRoleInactive)) {
            atomicAdd(&counters[2], 1ull);
            return;
        }
    }

    const int ix = static_cast<int>(c % static_cast<unsigned int>(cfg.nx));
    const int iy = static_cast<int>(c / static_cast<unsigned int>(cfg.nx));
    const double xmin = static_cast<double>(ix) * cfg.dx;
    const double xmax = xmin + cfg.dx;
    const double ymin = static_cast<double>(iy) * cfg.dy;
    const double ymax = ymin + cfg.dy;
    const double epsx = 0.0625 * cfg.dx;
    const double epsy = 0.0625 * cfg.dy;
    double xn = clamp_0297(x[donor] + ((k & 1u) ? epsx : -epsx), xmin + 1.0e-12 * cfg.dx, xmax - 1.0e-12 * cfg.dx);
    double yn = clamp_0297(y[donor] + ((k & 2u) ? epsy : -epsy), ymin + 1.0e-12 * cfg.dy, ymax - 1.0e-12 * cfg.dy);
    if (!point_inside_active_domain_0297(xn, yn, cfg)) {
        xn = x[donor];
        yn = y[donor];
    }

    mass[donor] = md - dm;
    x[slot] = xn;
    y[slot] = yn;
    vx[slot] = vx[donor];
    vy[slot] = vy[donor];
    mass[slot] = dm;
    type[slot] = type[donor];
    role[slot] = static_cast<unsigned char>(kParticleRoleFluid);
    atomicAdd(&counters[1], 1ull);
    if (solidAdjacent0307) atomicAdd(&counters[12], 1ull);
}

__global__ void reset_krel_buffer_kernel_0298(int numCells,
                                                double* __restrict__ krel,
                                                unsigned long long* __restrict__ counters) {
    const int c = blockIdx.x * blockDim.x + threadIdx.x;
    if (c < numCells) {
        krel[c] = 0.0;
    }
    if (c == 0 && counters != nullptr) {
        counters[0] = 0ull;
        counters[1] = 0ull;
    }
}

__global__ void accumulate_cell_relative_energy_kernel_0298(
    int nParticles,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const double* __restrict__ mass,
    const unsigned int* __restrict__ type,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    const double* __restrict__ cellUx,
    const double* __restrict__ cellUy,
    CudaSpeciesCellDeviceView0490h species,
    double* __restrict__ krel) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0) return;
    double ux = cellUx[c];
    double uy = cellUy[c];
    if (species.speciesCount > 0 && species.speciesTypes != nullptr &&
        species.resamplingEnabled != nullptr && species.mass != nullptr &&
        species.px != nullptr && species.py != nullptr) {
        if (!species_resampling_enabled_0493b(
                type[i], species.speciesTypes, species.resamplingEnabled,
                species.speciesCount)) return;
        double mutableMass = 0.0;
        double mutablePx = 0.0;
        double mutablePy = 0.0;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.resamplingEnabled[s] == 0u) continue;
            const int k = s * species.numCells + c;
            mutableMass += species.mass[k];
            mutablePx += species.px[k];
            mutablePy += species.py[k];
        }
        if (!(mutableMass > 0.0)) return;
        ux = mutablePx / mutableMass;
        uy = mutablePy / mutableMass;
    }
    const double m = mass[i];
    if (!(m > 0.0)) return;
    const double dvx = vx[i] - ux;
    const double dvy = vy[i] - uy;
    const double e = 0.5 * m * (dvx * dvx + dvy * dvy);
    if (isfinite(e)) atomic_add_double_compat_0297(&krel[c], e);
}


// 0493g: preserve the thermodynamic moments of each mutable species
// independently.  Split/merge operations are already type-preserving and
// conserve mass and momentum for the selected type.  The former 0298 path
// accumulated all enabled species around one mixture barycentre, then scaled
// every enabled particle around that common velocity.  That conserved mixture
// momentum/energy but exchanged both between species.  These kernels retain a
// species-major cell energy budget and restore each type around its own
// pre-mutation barycentre.
__global__ void accumulate_species_cell_relative_energy_kernel_0493g(
    int nParticles,
    const double* __restrict__ vx,
    const double* __restrict__ vy,
    const double* __restrict__ mass,
    const unsigned int* __restrict__ type,
    const unsigned char* __restrict__ role,
    const int* __restrict__ cellId,
    CudaSpeciesCellDeviceView0490h species,
    double* __restrict__ speciesKrel) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= species.numCells) return;
    if (species.speciesCount <= 0 || species.speciesTypes == nullptr ||
        species.resamplingEnabled == nullptr || species.mass == nullptr ||
        species.px == nullptr || species.py == nullptr || speciesKrel == nullptr) return;

    const int si = species_index_0490f(type[i], species.speciesTypes, species.speciesCount);
    if (si < 0 || species.resamplingEnabled[si] == 0u) return;
    const int k = si * species.numCells + c;
    const double ms = species.mass[k];
    const double m = mass[i];
    if (!(ms > 0.0) || !(m > 0.0) || !isfinite(ms) || !isfinite(m)) return;
    const double ux = species.px[k] / ms;
    const double uy = species.py[k] / ms;
    const double dvx = vx[i] - ux;
    const double dvy = vy[i] - uy;
    const double e = 0.5 * m * (dvx * dvx + dvy * dvy);
    if (isfinite(e)) atomic_add_double_compat_0297(&speciesKrel[k], e);
}

__global__ void restore_species_cell_relative_energy_kernel_0493g(
    int nParticles,
    const double* __restrict__ targetSpeciesKrel,
    const double* __restrict__ currentSpeciesKrel,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ type,
    const unsigned char* __restrict__ role,
    CudaSpeciesCellDeviceView0490h species,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double minCurrentKrel,
    double maxScale,
    double absTol,
    double relTol,
    unsigned long long* __restrict__ counters) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= species.numCells) return;
    if (species.speciesCount <= 0 || species.speciesTypes == nullptr ||
        species.resamplingEnabled == nullptr || species.mass == nullptr ||
        species.px == nullptr || species.py == nullptr ||
        targetSpeciesKrel == nullptr || currentSpeciesKrel == nullptr) return;

    const int si = species_index_0490f(type[i], species.speciesTypes, species.speciesCount);
    if (si < 0 || species.resamplingEnabled[si] == 0u) return;
    const int k = si * species.numCells + c;
    const double ms = species.mass[k];
    if (!(ms > 0.0) || !isfinite(ms)) return;

    const double target = targetSpeciesKrel[k];
    const double current = currentSpeciesKrel[k];
    if (!(target >= 0.0) || !(current > minCurrentKrel) ||
        !isfinite(target) || !isfinite(current)) {
        if (counters != nullptr) atomicAdd(&counters[1], 1ull);
        return;
    }
    const double diff = fabs(current - target);
    const double den = fmax(1.0, fabs(target));
    if (diff <= absTol + relTol * den) return;

    double scale = sqrt(target / current);
    if (!isfinite(scale)) {
        if (counters != nullptr) atomicAdd(&counters[1], 1ull);
        return;
    }
    if (scale > maxScale) scale = maxScale;
    if (scale < 0.0) scale = 0.0;

    const double ux = species.px[k] / ms;
    const double uy = species.py[k] / ms;
    vx[i] = ux + scale * (vx[i] - ux);
    vy[i] = uy + scale * (vy[i] - uy);
    if (counters != nullptr) atomicAdd(&counters[0], 1ull);
}

__global__ void restore_cell_relative_energy_kernel_0298(
    int nParticles,
    const double* __restrict__ targetKrel,
    const double* __restrict__ currentKrel,
    const unsigned int* __restrict__ cellCount,
    const double* __restrict__ cellMass,
    const double* __restrict__ cellUx,
    const double* __restrict__ cellUy,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ type,
    const unsigned char* __restrict__ role,
    CudaSpeciesCellDeviceView0490h species,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double minCurrentKrel,
    double maxScale,
    double absTol,
    double relTol,
    unsigned long long* __restrict__ counters) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role && role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0) return;
    double ux = cellUx[c];
    double uy = cellUy[c];
    unsigned int mutableCount = cellCount[c];
    double mutableMass = cellMass[c];
    if (species.speciesCount > 0 && species.speciesTypes != nullptr &&
        species.resamplingEnabled != nullptr && species.count != nullptr &&
        species.mass != nullptr && species.px != nullptr && species.py != nullptr) {
        if (!species_resampling_enabled_0493b(
                type[i], species.speciesTypes, species.resamplingEnabled,
                species.speciesCount)) return;
        mutableCount = 0u;
        mutableMass = 0.0;
        double mutablePx = 0.0;
        double mutablePy = 0.0;
        for (int s = 0; s < species.speciesCount; ++s) {
            if (species.resamplingEnabled[s] == 0u) continue;
            const int k = s * species.numCells + c;
            mutableCount += species.count[k];
            mutableMass += species.mass[k];
            mutablePx += species.px[k];
            mutablePy += species.py[k];
        }
        if (mutableMass > 0.0) {
            ux = mutablePx / mutableMass;
            uy = mutablePy / mutableMass;
        }
    }
    if (mutableCount < 2u || !(mutableMass > 0.0)) return;
    const double target = targetKrel[c];
    const double current = currentKrel[c];
    if (!(target >= 0.0) || !(current > minCurrentKrel) || !isfinite(target) || !isfinite(current)) {
        return;
    }
    const double diff = fabs(current - target);
    const double den = fmax(1.0, fabs(target));
    if (diff <= absTol + relTol * den) {
        return;
    }
    double scale = sqrt(target / current);
    if (!isfinite(scale)) return;
    if (scale > maxScale) scale = maxScale;
    if (scale < 0.0) scale = 0.0;
    vx[i] = ux + scale * (vx[i] - ux);
    vy[i] = uy + scale * (vy[i] - uy);
    // The per-particle counter over-counts active cells, but it is useful as an
    // inexpensive indication that the restoration kernel was actually applied.
    atomicAdd(&counters[0], 1ull);
}

DevicePopulationGuardConfig0297 make_config_0297(const SimulationParams& params,
                                                 const CellGrid& grid,
                                                 const FluidDomainBounds& domain,
                                                 double time) {
    DevicePopulationGuardConfig0297 cfg{};
    cfg.nx = grid.Nx;
    cfg.ny = grid.Ny;
    cfg.numCells = grid.numCells;
    cfg.lx = grid.Lx;
    cfg.ly = grid.Ly;
    cfg.dx = grid.dx;
    cfg.dy = grid.dy;
    cfg.domainXMin = domain.xMin;
    cfg.domainXMax = domain.xMax;
    cfg.domainYMin = domain.yMin;
    cfg.domainYMax = domain.yMax;
    cfg.nMin = std::max(0, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN", 0));
    cfg.nTarget = std::max(cfg.nMin, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET", 20));
    cfg.nMax = std::max(0, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX", 0));
    cfg.splitFraction = std::clamp(env_double_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION", 0.5), 1.0e-6, 0.5);
    cfg.minDonorMassAfterSplit = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_MIN_DONOR_MASS_AFTER_SPLIT", 1.0e-12));
    cfg.splitSafety0307 = env_truthy_0297("MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307") ? 1 : 0;
    cfg.preferMaxMassDonor0307 = env_truthy_0297("MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307") ? 1 : 0;
    if (cfg.splitSafety0307 && !std::getenv("MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307")) {
        cfg.preferMaxMassDonor0307 = 1;
    }
    cfg.splitDonorMinMass0307 = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307", 0.0));
    cfg.splitNewParticleMinMass0307 = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307", 0.0));
    cfg.solidAdjacentDonorMinMass0307 = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_DONOR_MIN_MASS_0307", cfg.splitDonorMinMass0307));
    cfg.solidAdjacentSplitMode0307 = std::clamp(env_int_0297("MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307", 0), 0, 2);
    cfg.solidAdjacentHaloCells0307 = std::max(1, env_int_0297("MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_HALO_CELLS_0307", 1));
    cfg.tinyMassThreshold0307 = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_TINY_MASS_THRESHOLD_0307", 0.25));
    cfg.activePrefixSafe0315 = env_truthy_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_LEGACY_TAIL_SPLIT")
        ? 0 : 1;
    const std::string emptyRef = lower_copy_0299(params.cudaResamplingEmptyRefillReference);
    int emptyReference = cfg.nTarget > 0 ? cfg.nTarget : 1;
    if (emptyRef == "gamma") {
        emptyReference = params.cudaResamplingEmptyRefillGamma > 0
            ? params.cudaResamplingEmptyRefillGamma
            : static_cast<int>(std::llround(params.resamplingTargetCellMass));
        if (emptyReference <= 0) emptyReference = cfg.nTarget > 0 ? cfg.nTarget : 1;
    }
    cfg.emptyRefillEnable0319 = (params.cudaResamplingEmptyRefillEnable ||
                                 env_truthy_0297("MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319")) ? 1 : 0;
    cfg.emptyRefillTarget0319 = std::max(1, static_cast<int>(std::llround(
        params.cudaResamplingEmptyRefillTargetFraction * static_cast<double>(std::max(1, emptyReference)))));
    cfg.emptyRefillMemoryMaxAge0319 = std::max(0, params.cudaResamplingEmptyRefillMemoryMaxAge);
    cfg.speciesCompositionEnable0490f = params.cudaResamplingEmptyRefillSpeciesCompositionEnable ? 1 : 0;
    cfg.speciesCount0490f = cfg.speciesCompositionEnable0490f
        ? static_cast<int>(params.speciesDefinitions.size()) : 0;
    cfg.speciesPopulationGuardEnable0490j =
        params.speciesResamplingPopulationGuardCudaEnable ? 1 : 0;
    cfg.speciesCount0490j = cfg.speciesPopulationGuardEnable0490j
        ? static_cast<int>(params.speciesDefinitions.size()) : 0;
    if (cfg.speciesPopulationGuardEnable0490j) {
        cfg.nMin = params.resamplingPopulationNMin;
        cfg.nTarget = params.resamplingPopulationNTarget;
        cfg.nMax = params.resamplingPopulationNMax;
    }
    cfg.chiFilterEnable = (params.darcyBrinkmanEnable && params.cudaResamplingChiFilterEnable) ? 1 : 0;
    cfg.chiMin = std::clamp(params.cudaResamplingChiMin, 0.0, 1.0);
    cfg.boundaryAware0299 = env_truthy_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE") ? 1 : 0;
    if (const char* v = std::getenv("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE")) {
        (void)v;
    } else {
        // Boundary-aware filtering is enabled by default for 0299, but the
        // default halo widths below are deliberately conservative and only the
        // open-boundary reservoir layer is excluded by default.
        cfg.boundaryAware0299 = 1;
    }
    cfg.boundaryHaloCells0299 = std::max(0, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS", 0));
    cfg.openBoundaryHaloCells0299 = std::max(0, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS", 1));
    cfg.solidHaloCells0299 = std::max(0, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS", 0));

    cfg.faceOpenLeft0299 = mode_is_open_0299(params.bcLeft) ? 1 : 0;
    cfg.faceOpenRight0299 = mode_is_open_0299(params.bcRight) ? 1 : 0;
    cfg.faceOpenBottom0299 = mode_is_open_0299(params.bcBottom) ? 1 : 0;
    cfg.faceOpenTop0299 = mode_is_open_0299(params.bcTop) ? 1 : 0;
    cfg.faceWallLeft0299 = (!mode_is_periodic_0299(params.bcLeft) && !cfg.faceOpenLeft0299) ? 1 : 0;
    cfg.faceWallRight0299 = (!mode_is_periodic_0299(params.bcRight) && !cfg.faceOpenRight0299) ? 1 : 0;
    cfg.faceWallBottom0299 = (!mode_is_periodic_0299(params.bcBottom) && !cfg.faceOpenBottom0299) ? 1 : 0;
    cfg.faceWallTop0299 = (!mode_is_periodic_0299(params.bcTop) && !cfg.faceOpenTop0299) ? 1 : 0;
    if (params.openBoundarySegmentsEnable) {
        for (const auto& seg : params.openBoundarySegments) {
            if (mode_is_open_0299(seg.mode)) mark_segment_face_open_0299(cfg, seg.face);
        }
    }

    if (immersed_solid_enabled(params)) {
        const ImmersedSolidShape shape = immersed_solid_shape(params);
        if (shape == ImmersedSolidShape::Circle) {
            cfg.solidShape = 1;
            immersed_solid_circle_center(params, time, cfg.circleCx, cfg.circleCy);
            cfg.circleR = params.immersedSolidR;
        } else if (shape == ImmersedSolidShape::Rectangle) {
            cfg.solidShape = 2;
            immersed_solid_rectangle_bounds(params, time,
                                            cfg.rectXMin, cfg.rectXMax,
                                            cfg.rectYMin, cfg.rectYMax);
        }
    }
    return cfg;
}

void write_csv_row_0297(const SimulationParams& params,
                        CudaResamplingPopulationGuard0297Diagnostics& d) {
    std::filesystem::create_directories(params.outputDir);
    const std::filesystem::path path = std::filesystem::path(params.outputDir) /
        "cuda_resampling_population_guard_0297.csv";
    const bool needHeader = !std::filesystem::exists(path) || std::filesystem::file_size(path) == 0u;
    std::ofstream out(path, std::ios::app);
    if (!out) return;
    d.outputCsv = path.string();
    if (needHeader) {
        out << "step,stage,handled,cudaAvailable,sharedStateFreshBefore,skippedBecauseStateNotFresh,"
               "particles,cells,fluidParticlesBefore,fluidParticlesAfter,inactiveParticlesBefore,inactiveParticlesAfter,"
               "wetCellsBefore,wetCellsAfter,poorCells,richCells,mergeApplied,splitApplied,splitSkippedNoInactive,"
               "splitSkippedNoDonor,mergeSkippedNoPair,"
               "speciesPopulationGuardCuda0490j,speciesCount0490j,speciesPoorSelections0490j,"
               "speciesRichSelections0490j,speciesDirectedSplits0490j,speciesDirectedMerges0490j,"
               "speciesTargetInfeasibleCells0490j,speciesInvalidTypeCount0490j,speciesWorkspaceReused0490j,"
               "nMin,nTarget,nMax,splitFraction,minDonorMassAfterSplit,"
               "splitSafety0307,preferMaxMassDonor0307,splitDonorMinMass0307,splitNewParticleMinMass0307,"
               "solidAdjacentDonorMinMass0307,solidAdjacentSplitMode0307,solidAdjacentHaloCells0307,tinyMassThreshold0307,"
               "chiFilterEnable,chiMin,excludedChiCells,"
               "splitCandidatesSolidAdjacent0307,splitAppliedSolidAdjacent0307,splitSkippedDonorMass0307,"
               "splitSkippedNewMass0307,splitSkippedSolidAdjacent0307,splitFromMassBelow0p5_0307,"
               "splitFromMassBelow0p25_0307,splitFromMassBelow0p1_0307,minSplitDonorMass0307,"
               "minSplitNewParticleMass0307,minPostSplitDonorMass0307,"
               "emptyRefillEnable0319,emptyRefillTarget0319,emptyRefillTargetFraction0319,emptyRefillReference0319,"
               "emptyRefillMemoryMaxAge0319,emptyRefillMemoryUpdates0319,emptyRefillCandidates0319,"
               "emptyRefillCells0319,emptyRefillParticles0319,emptyRefillSkippedNoMemory0319,"
               "emptyRefillSkippedNoCapacity0319,emptyRefillSkippedMixedSpecies0490c,"
               "emptyRefillSpeciesCompositionEnable0490f,emptyRefillSpeciesCount0490f,"
               "emptyRefillMixedCells0490f,emptyRefillSkippedTargetTooSmall0490f,"
               "emptyRefillMaxAbsSpeciesMassError0490f,emptyRefillMaxAbsSpeciesMomentumError0490f,"
               "emptyRefillAddedMass0319,emptyRefillAddedPx0319,"
               "emptyRefillAddedPy0319,emptyRefillMassScale0319,emptyRefillVelocityShiftX0319,emptyRefillVelocityShiftY0319,"
               "totalMassBefore,totalMassAfter,totalPxBefore,totalPxAfter,totalPyBefore,totalPyAfter,"
               "momentRestoreRequested0298,energyRestoreApplied0298,energyRestoreParticleUpdates0298,energyRestoreSkippedParticles0298,"
               "energyRestoreMaxScale0298,totalKrelBefore0298,totalKrelAfterPreRestore0298,totalKrelAfter0298,"
               "maxAbsCellKrelErrorPreRestore0298,maxRelCellKrelErrorPreRestore0298,"
               "maxAbsCellKrelError0298,maxRelCellKrelError0298,"
               "maxAbsCellMassError,maxRelCellMassError,maxAbsCellMomentumError,maxRelCellMomentumError,"
               "boundaryAware0299,boundaryHaloCells0299,openBoundaryHaloCells0299,solidHaloCells0299,"
               "excludedBoundaryCells0299,excludedOpenBoundaryCells0299,excludedSolidHaloCells0299,"
               "depositBeforeSeconds,kernelSeconds,depositAfterSeconds,downloadSeconds,totalSeconds\n";
    }
    out << std::setprecision(17)
        << d.step << ','
        << csv_escape_0297(d.stage) << ','
        << (d.handled ? 1 : 0) << ','
        << (d.cudaAvailable ? 1 : 0) << ','
        << (d.sharedStateFreshBefore ? 1 : 0) << ','
        << (d.skippedBecauseStateNotFresh ? 1 : 0) << ','
        << d.particles << ',' << d.cells << ','
        << d.fluidParticlesBefore << ',' << d.fluidParticlesAfter << ','
        << d.inactiveParticlesBefore << ',' << d.inactiveParticlesAfter << ','
        << d.wetCellsBefore << ',' << d.wetCellsAfter << ','
        << d.poorCells << ',' << d.richCells << ','
        << d.mergeApplied << ',' << d.splitApplied << ','
        << d.splitSkippedNoInactive << ',' << d.splitSkippedNoDonor << ',' << d.mergeSkippedNoPair << ','
        << (d.speciesPopulationGuardCuda0490j ? 1 : 0) << ','
        << d.speciesCount0490j << ',' << d.speciesPoorSelections0490j << ','
        << d.speciesRichSelections0490j << ',' << d.speciesDirectedSplits0490j << ','
        << d.speciesDirectedMerges0490j << ',' << d.speciesTargetInfeasibleCells0490j << ','
        << d.speciesInvalidTypeCount0490j << ',' << d.speciesWorkspaceReused0490j << ','
        << d.nMin << ',' << d.nTarget << ',' << d.nMax << ','
        << d.splitFraction << ',' << d.minDonorMassAfterSplit << ','
        << (d.splitSafety0307 ? 1 : 0) << ','
        << (d.preferMaxMassDonor0307 ? 1 : 0) << ','
        << d.splitDonorMinMass0307 << ',' << d.splitNewParticleMinMass0307 << ','
        << d.solidAdjacentDonorMinMass0307 << ',' << d.solidAdjacentSplitMode0307 << ','
        << d.solidAdjacentHaloCells0307 << ',' << d.tinyMassThreshold0307 << ','
        << (d.chiFilterEnable ? 1 : 0) << ',' << d.chiMin << ',' << d.excludedChiCells << ','
        << d.splitCandidatesSolidAdjacent0307 << ',' << d.splitAppliedSolidAdjacent0307 << ','
        << d.splitSkippedDonorMass0307 << ',' << d.splitSkippedNewMass0307 << ','
        << d.splitSkippedSolidAdjacent0307 << ',' << d.splitFromMassBelow0p5_0307 << ','
        << d.splitFromMassBelow0p25_0307 << ',' << d.splitFromMassBelow0p1_0307 << ','
        << d.minSplitDonorMass0307 << ',' << d.minSplitNewParticleMass0307 << ','
        << d.minPostSplitDonorMass0307 << ','
        << (d.emptyRefillEnable0319 ? 1 : 0) << ',' << d.emptyRefillTarget0319 << ','
        << d.emptyRefillTargetFraction0319 << ',' << csv_escape_0297(d.emptyRefillReference0319) << ','
        << d.emptyRefillMemoryMaxAge0319 << ',' << d.emptyRefillMemoryUpdates0319 << ','
        << d.emptyRefillCandidates0319 << ',' << d.emptyRefillCells0319 << ','
        << d.emptyRefillParticles0319 << ',' << d.emptyRefillSkippedNoMemory0319 << ','
        << d.emptyRefillSkippedNoCapacity0319 << ',' << d.emptyRefillSkippedMixedSpecies0490c << ','
        << (d.emptyRefillSpeciesCompositionEnable0490f ? 1 : 0) << ','
        << d.emptyRefillSpeciesCount0490f << ','
        << d.emptyRefillMixedCells0490f << ','
        << d.emptyRefillSkippedTargetTooSmall0490f << ','
        << d.emptyRefillMaxAbsSpeciesMassError0490f << ','
        << d.emptyRefillMaxAbsSpeciesMomentumError0490f << ','
        << d.emptyRefillAddedMass0319 << ','
        << d.emptyRefillAddedPx0319 << ',' << d.emptyRefillAddedPy0319 << ','
        << d.emptyRefillMassScale0319 << ',' << d.emptyRefillVelocityShiftX0319 << ','
        << d.emptyRefillVelocityShiftY0319 << ','
        << d.totalMassBefore << ',' << d.totalMassAfter << ','
        << d.totalPxBefore << ',' << d.totalPxAfter << ','
        << d.totalPyBefore << ',' << d.totalPyAfter << ','
        << (d.momentRestoreRequested0298 ? 1 : 0) << ','
        << (d.energyRestoreApplied0298 ? 1 : 0) << ','
        << d.energyRestoreParticleUpdates0298 << ',' << d.energyRestoreSkippedParticles0298 << ','
        << d.energyRestoreMaxScale0298 << ','
        << d.totalKrelBefore0298 << ',' << d.totalKrelAfterPreRestore0298 << ',' << d.totalKrelAfter0298 << ','
        << d.maxAbsCellKrelErrorPreRestore0298 << ',' << d.maxRelCellKrelErrorPreRestore0298 << ','
        << d.maxAbsCellKrelError0298 << ',' << d.maxRelCellKrelError0298 << ','
        << d.maxAbsCellMassError << ',' << d.maxRelCellMassError << ','
        << d.maxAbsCellMomentumError << ',' << d.maxRelCellMomentumError << ','
        << (d.boundaryAware0299 ? 1 : 0) << ','
        << d.boundaryHaloCells0299 << ',' << d.openBoundaryHaloCells0299 << ',' << d.solidHaloCells0299 << ','
        << d.excludedBoundaryCells0299 << ',' << d.excludedOpenBoundaryCells0299 << ',' << d.excludedSolidHaloCells0299 << ','
        << d.depositBeforeSeconds << ',' << d.kernelSeconds << ','
        << d.depositAfterSeconds << ',' << d.downloadSeconds << ',' << d.totalSeconds << '\n';
}

void accumulate_global_diagnostics_0297(const CudaCellMoments& m,
                                        std::uint64_t& fluid,
                                        std::uint64_t& wet,
                                        double& mass,
                                        double& px,
                                        double& py) {
    fluid = 0u;
    wet = 0u;
    mass = 0.0;
    px = 0.0;
    py = 0.0;
    const std::size_t n = m.cellCount.size();
    for (std::size_t c = 0; c < n; ++c) {
        const std::uint32_t cnt = m.cellCount[c];
        fluid += static_cast<std::uint64_t>(cnt);
        if (cnt > 0u) ++wet;
        mass += m.cellMass[c];
        px += m.cellPx[c];
        py += m.cellPy[c];
    }
}

void compare_before_after_0297(const CudaCellMoments& before,
                               const CudaCellMoments& after,
                               CudaResamplingPopulationGuard0297Diagnostics& d) {
    const std::size_t n = std::min(before.cellCount.size(), after.cellCount.size());
    for (std::size_t c = 0; c < n; ++c) {
        if (before.cellCount[c] == 0u && after.cellCount[c] == 0u) continue;
        const double dm = after.cellMass[c] - before.cellMass[c];
        const double dpx = after.cellPx[c] - before.cellPx[c];
        const double dpy = after.cellPy[c] - before.cellPy[c];
        const double massDen = std::max(1.0, std::abs(before.cellMass[c]));
        const double momDen = std::max(1.0, std::hypot(before.cellPx[c], before.cellPy[c]));
        d.maxAbsCellMassError = std::max(d.maxAbsCellMassError, std::abs(dm));
        d.maxRelCellMassError = std::max(d.maxRelCellMassError, std::abs(dm) / massDen);
        d.maxAbsCellMomentumError = std::max(d.maxAbsCellMomentumError, std::hypot(dpx, dpy));
        d.maxRelCellMomentumError = std::max(d.maxRelCellMomentumError, std::hypot(dpx, dpy) / momDen);
    }
}

std::vector<double> compute_cell_krel_0298(int nParticles,
                                           int numCells,
                                           int particleGrid,
                                           int cellGrid,
                                           int block,
                                           const CudaParticleDeviceView& pv,
                                           const CudaCellWorkspaceDeviceView& cv,
                                           CudaSpeciesCellDeviceView0490h species,
                                           double* dKrel,
                                           unsigned long long* countersOrNull,
                                           const char* label,
                                           bool downloadHost) {
    reset_krel_buffer_kernel_0298<<<cellGrid, block>>>(numCells, dKrel, countersOrNull);
    cuda_check_0297(cudaGetLastError(), label);
    accumulate_cell_relative_energy_kernel_0298<<<particleGrid, block>>>(
        nParticles, pv.vx, pv.vy, pv.mass, pv.type, pv.role,
        cv.cellId, cv.cellUx, cv.cellUy, species, dKrel);
    cuda_check_0297(cudaGetLastError(), "launch accumulate_cell_relative_energy_kernel_0298");
    if (!downloadHost) return {};
    std::vector<double> out(static_cast<std::size_t>(numCells), 0.0);
    cuda_check_0297(cudaMemcpy(out.data(), dKrel, sizeof(double) * static_cast<std::size_t>(numCells),
                               cudaMemcpyDeviceToHost),
                    "copy 0298 krel D2H");
    return out;
}


std::vector<double> compute_species_cell_krel_0493g(
    int nParticles,
    int particleGrid,
    int block,
    const CudaParticleDeviceView& pv,
    const CudaCellWorkspaceDeviceView& cv,
    CudaSpeciesCellDeviceView0490h species,
    double* dSpeciesKrel,
    const char* resetLabel,
    bool downloadHost) {
    if (species.speciesCount <= 0 || species.numCells <= 0 ||
        species.speciesTypes == nullptr || species.resamplingEnabled == nullptr ||
        species.mass == nullptr || species.px == nullptr || species.py == nullptr ||
        dSpeciesKrel == nullptr) {
        return {};
    }
    const std::size_t ncs =
        static_cast<std::size_t>(species.speciesCount) *
        static_cast<std::size_t>(species.numCells);
    cuda_check_0297(cudaMemset(dSpeciesKrel, 0, sizeof(double) * ncs), resetLabel);
    accumulate_species_cell_relative_energy_kernel_0493g<<<particleGrid, block>>>(
        nParticles, pv.vx, pv.vy, pv.mass, pv.type, pv.role,
        cv.cellId, species, dSpeciesKrel);
    cuda_check_0297(
        cudaGetLastError(),
        "launch accumulate_species_cell_relative_energy_kernel_0493g");
    if (!downloadHost) return {};
    std::vector<double> out(ncs, 0.0);
    cuda_check_0297(
        cudaMemcpy(out.data(), dSpeciesKrel, sizeof(double) * ncs,
                   cudaMemcpyDeviceToHost),
        "copy 0493g species krel D2H");
    return out;
}

double sum_vector_0298(const std::vector<double>& v) {
    double s = 0.0;
    for (const double x : v) s += x;
    return s;
}

void compare_krel_vectors_0298(const std::vector<double>& target,
                               const std::vector<double>& observed,
                               double& maxAbs,
                               double& maxRel) {
    const std::size_t n = std::min(target.size(), observed.size());
    maxAbs = 0.0;
    maxRel = 0.0;
    for (std::size_t c = 0; c < n; ++c) {
        const double diff = observed[c] - target[c];
        const double den = std::max(1.0, std::abs(target[c]));
        maxAbs = std::max(maxAbs, std::abs(diff));
        maxRel = std::max(maxRel, std::abs(diff) / den);
    }
}

} // namespace

bool cuda_resampling_population_guard_0297_requested(const SimulationParams& params, std::uint64_t step) {
    const bool requestedByEnv = env_truthy_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297");
    const bool requestedByEmptyRefill = params.resamplingEnable && params.cudaResamplingEmptyRefillEnable;
    const bool requestedBySpecies0490j =
        params.resamplingEnable && params.speciesResamplingPopulationGuardCudaEnable;
    if (!requestedByEnv && !requestedByEmptyRefill && !requestedBySpecies0490j) return false;
    const int every = std::max(1, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY", 1));
    return (step % static_cast<std::uint64_t>(every)) == 0u;
}

CudaResamplingPopulationGuard0297Diagnostics try_apply_cuda_resampling_population_guard_0297(
    ParticleState& hostMirror,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    std::uint64_t step,
    double time,
    const char* stage) {
    CudaResamplingPopulationGuard0297Diagnostics d{};
    d.attempted = true;
    d.step = step;
    d.stage = stage != nullptr ? stage : "post_src_population_guard";
    d.particles = hostMirror.Np;
    d.cells = static_cast<std::uint64_t>(std::max(0, grid.numCells));
    DevicePopulationGuardConfig0297 cfg = make_config_0297(params, grid, domain, time);
    d.nMin = cfg.nMin;
    d.nTarget = cfg.nTarget;
    d.nMax = cfg.nMax;
    d.splitFraction = cfg.splitFraction;
    d.minDonorMassAfterSplit = cfg.minDonorMassAfterSplit;
    d.splitSafety0307 = cfg.splitSafety0307 != 0;
    d.preferMaxMassDonor0307 = cfg.preferMaxMassDonor0307 != 0;
    d.splitDonorMinMass0307 = cfg.splitDonorMinMass0307;
    d.splitNewParticleMinMass0307 = cfg.splitNewParticleMinMass0307;
    d.solidAdjacentDonorMinMass0307 = cfg.solidAdjacentDonorMinMass0307;
    d.solidAdjacentSplitMode0307 = cfg.solidAdjacentSplitMode0307;
    d.solidAdjacentHaloCells0307 = cfg.solidAdjacentHaloCells0307;
    d.tinyMassThreshold0307 = cfg.tinyMassThreshold0307;
    d.chiFilterEnable = cfg.chiFilterEnable != 0;
    d.chiMin = cfg.chiMin;
    d.emptyRefillEnable0319 = cfg.emptyRefillEnable0319 != 0;
    d.emptyRefillTarget0319 = cfg.emptyRefillTarget0319;
    d.emptyRefillTargetFraction0319 = params.cudaResamplingEmptyRefillTargetFraction;
    d.emptyRefillReference0319 = params.cudaResamplingEmptyRefillReference;
    d.emptyRefillMemoryMaxAge0319 = cfg.emptyRefillMemoryMaxAge0319;
    d.emptyRefillSpeciesCompositionEnable0490f = cfg.speciesCompositionEnable0490f != 0;
    d.emptyRefillSpeciesCount0490f = static_cast<std::uint64_t>(std::max(0, cfg.speciesCount0490f));
    d.speciesPopulationGuardCuda0490j = cfg.speciesPopulationGuardEnable0490j != 0;
    d.speciesCount0490j = static_cast<std::uint64_t>(std::max(0, cfg.speciesCount0490j));
    d.boundaryAware0299 = cfg.boundaryAware0299 != 0;
    d.boundaryHaloCells0299 = cfg.boundaryHaloCells0299;
    d.openBoundaryHaloCells0299 = cfg.openBoundaryHaloCells0299;
    d.solidHaloCells0299 = cfg.solidHaloCells0299;
    d.momentRestoreRequested0298 = env_truthy_0297("MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298");
    d.energyRestoreMaxScale0298 = std::max(1.0, env_double_0297("MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE", 4.0));
    const double minCurrentKrel0298 = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MIN_CURRENT_KREL", 1.0e-30));
    const double restoreAbsTol0298 = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL", 1.0e-14));
    const double restoreRelTol0298 = std::max(0.0, env_double_0297("MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL", 1.0e-12));
    const Clock::time_point t0 = Clock::now();

    d.cudaAvailable = cuda_cell_moments_available();
    if (!d.cudaAvailable) {
        d.totalSeconds = seconds_between(t0, Clock::now());
        write_csv_row_0297(params, d);
        return d;
    }
    if (grid.Nx <= 0 || grid.Ny <= 0 || grid.numCells != grid.Nx * grid.Ny) {
        throw std::runtime_error("cuda_resampling_population_guard_0297: invalid grid");
    }

    d.sharedStateFreshBefore = cuda_shared_particle_state_0251_is_fresh();
    if (!d.sharedStateFreshBefore) {
        // 0297 mutates roles/masses/positions.  It is only allowed when the
        // resident CUDA state is authoritative.  A later CPU/Q6 handoff can add
        // an explicit upload/download contract; this minimal patch must not
        // infer authority from a stale host mirror.
        d.skippedBecauseStateNotFresh = true;
        d.totalSeconds = seconds_between(t0, Clock::now());
        write_csv_row_0297(params, d);
        return d;
    }

    CudaParticleState& gpuState = cuda_shared_particle_state_0251();
    ParticleState guardMirror = hostMirror;
    if (cfg.activePrefixSafe0315) {
        guardMirror.NactiveFluid = gpuState.active_fluid_size();
    }
    CudaCellWorkspaceDiagnostics workspaceDiag{};
    g_populationGuardWorkspace0297.ensure_capacity(hostMirror.Np, grid.numCells, &workspaceDiag);

    const bool residentZeroHostMirrors0493b =
        params.speciesResamplingCudaResidentFastPathEnable &&
        params.speciesRegistryEnable && !params.speciesDefinitions.empty();
    CudaCellMomentsOptions options{};
    options.threadsPerBlock = std::max(32, env_int_0297("MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_THREADS", 256));
    options.reuseDeviceBuffers = true;
    options.computeCellVelocities = true;
    options.downloadCellVelocities = !residentZeroHostMirrors0493b;
    options.downloadHostArrays = !residentZeroHostMirrors0493b;
    options.enableAllFluidFastPath = false;
    options.enableUniformMassFastPath = false;

    CudaCellMoments before{};
    CudaCellMomentsDiagnostics beforeDiag{};
    cuda_deposit_cell_moments_atomic_from_persistent_state(
        guardMirror, gpuState, g_populationGuardWorkspace0297, grid, GridShift{}, params,
        before, &beforeDiag, options);
    d.depositBeforeSeconds = beforeDiag.totalSeconds + workspaceDiag.totalSeconds;
    if (!residentZeroHostMirrors0493b) {
        accumulate_global_diagnostics_0297(before,
                                           d.fluidParticlesBefore,
                                           d.wetCellsBefore,
                                           d.totalMassBefore,
                                           d.totalPxBefore,
                                           d.totalPyBefore);
    } else {
        d.fluidParticlesBefore = gpuState.active_fluid_size();
    }

    CudaCellWorkspaceDeviceView cv = g_populationGuardWorkspace0297.device_view();
    CudaParticleDeviceView pv = gpuState.device_view();
    if (cv.cellId == nullptr || cv.count == nullptr || cv.cellMass == nullptr ||
        pv.x == nullptr || pv.y == nullptr || pv.vx == nullptr || pv.vy == nullptr ||
        pv.mass == nullptr || pv.type == nullptr || pv.role == nullptr) {
        throw std::runtime_error("cuda_resampling_population_guard_0297: incomplete device views");
    }

    const int speciesBufferCount0493g =
        params.speciesRegistryEnable
            ? static_cast<int>(params.speciesDefinitions.size())
            : cfg.speciesCount0490f;
    g_populationGuardBuffers0297.ensure(
        grid.numCells, hostMirror.Np,
        std::max(cfg.speciesCount0490f, speciesBufferCount0493g));
    if (cfg.speciesPopulationGuardEnable0490j) {
        g_populationGuardSpeciesSelection0490j.ensure(grid.numCells);
    }
    CudaSpeciesCellDeviceView0490h mutationSpeciesView0493b{};
    const std::uint64_t activeBase0315 = gpuState.active_fluid_size();
    if (cfg.activePrefixSafe0315) {
        cfg.activeBase0315 = activeBase0315;
        cfg.activeCapacity0315 = hostMirror.Np >= activeBase0315 ? hostMirror.Np - activeBase0315 : 0u;
    }
    const float* dChi0297 = nullptr;
    int chiNx0297 = 0;
    int chiNy0297 = 0;
    if (d.chiFilterEnable) {
        if (!cuda_darcy_brinkman_0343_device_chi_field(params, &dChi0297, &chiNx0297, &chiNy0297) ||
            chiNx0297 != grid.Nx || chiNy0297 != grid.Ny) {
            throw std::runtime_error("cuda_resampling_population_guard_0297: requested chi filter but Darcy chi field is unavailable");
        }
    }
    const int block = options.threadsPerBlock;
    const int cellGrid = std::max(1, (grid.numCells + block - 1) / block);
    if (cfg.speciesCompositionEnable0490f) {
        validate_species_definitions(
            params.speciesDefinitions,
            "cuda_resampling_population_guard_0297 0490f species registry");
        std::vector<unsigned int> speciesTypes0490f;
        std::vector<unsigned char> speciesResamplingEnabled0493b;
        speciesTypes0490f.reserve(params.speciesDefinitions.size());
        speciesResamplingEnabled0493b.reserve(params.speciesDefinitions.size());
        for (const auto& def : params.speciesDefinitions) {
            speciesTypes0490f.push_back(def.type);
            speciesResamplingEnabled0493b.push_back(def.resamplingEnable ? 1u : 0u);
        }
        cuda_check_0297(cudaMemcpy(
            g_populationGuardBuffers0297.dSpeciesTypes0490f, speciesTypes0490f.data(),
            sizeof(unsigned int) * speciesTypes0490f.size(), cudaMemcpyHostToDevice),
            "copy 0490f species types H2D");
        cuda_check_0297(cudaMemcpy(
            g_populationGuardBuffers0297.dSpeciesResamplingEnabled0493b,
            speciesResamplingEnabled0493b.data(),
            sizeof(unsigned char) * speciesResamplingEnabled0493b.size(), cudaMemcpyHostToDevice),
            "copy 0493b species resampling flags H2D");
    }

    const std::uint64_t particleCountBefore64 = cfg.activePrefixSafe0315 ? activeBase0315 : hostMirror.Np;
    const int particleCountBefore = static_cast<int>(particleCountBefore64);
    if (static_cast<std::uint64_t>(particleCountBefore) != particleCountBefore64) {
        throw std::runtime_error("cuda_resampling_population_guard_0297: active particle count exceeds int range");
    }
    const int particleGrid = std::max(1, (particleCountBefore + block - 1) / block);

    const Clock::time_point tk0 = Clock::now();
    reset_population_guard_buffers_kernel_0297<<<cellGrid, block>>>(
        grid.numCells,
        g_populationGuardBuffers0297.dPoorCount,
        g_populationGuardBuffers0297.dRichCount,
        g_populationGuardBuffers0297.dInactiveCount,
        g_populationGuardBuffers0297.dPoorDonor,
        g_populationGuardBuffers0297.dPoorDonorMassBits0307,
        g_populationGuardBuffers0297.dMinima0307,
        g_populationGuardBuffers0297.dRichKeep,
        g_populationGuardBuffers0297.dRichExtract,
        g_populationGuardBuffers0297.dEmptyCount0319,
        g_populationGuardBuffers0297.dEmptyAdded0319,
        g_populationGuardBuffers0297.dCounters);
    cuda_check_0297(cudaGetLastError(), "launch reset_population_guard_buffers_kernel_0297");

    const bool speciesMutationPolicy0493b =
        params.speciesRegistryEnable && !params.speciesDefinitions.empty();
    if (cfg.speciesPopulationGuardEnable0490j || speciesMutationPolicy0493b) {
        validate_species_definitions(
            params.speciesDefinitions,
            "cuda_resampling_population_guard_0297 species mutation registry");
        if (cfg.speciesPopulationGuardEnable0490j) {
            cuda_check_0297(cudaMemset(
                g_populationGuardSpeciesSelection0490j.dPoorType, 0xff,
                sizeof(unsigned int) * static_cast<std::size_t>(grid.numCells)),
                "reset 0490j poor selected type");
            cuda_check_0297(cudaMemset(
                g_populationGuardSpeciesSelection0490j.dRichType, 0xff,
                sizeof(unsigned int) * static_cast<std::size_t>(grid.numCells)),
                "reset 0490j rich selected type");
        }
        CudaSpeciesCellDepositDiagnostics0490h speciesDeposit0490j{};
        cuda_deposit_species_cell_fields_resident_0490h(
            pv, grid, params, params.speciesDefinitions,
            g_populationGuardSpeciesWorkspace0490j, &speciesDeposit0490j, block);
        mutationSpeciesView0493b =
            g_populationGuardSpeciesWorkspace0490j.device_view();
        d.speciesWorkspaceReused0490j = speciesDeposit0490j.reusedAllocation;
        d.speciesInvalidTypeCount0490j = speciesDeposit0490j.invalidTypeCount;
        if (speciesDeposit0490j.invalidTypeCount != 0u &&
            params.speciesRequireRegisteredTypes) {
            throw std::runtime_error(
                "0490j resident species population deposit encountered an unregistered type");
        }
    }

    std::vector<double> krelBefore0298 = compute_cell_krel_0298(
        particleCountBefore, grid.numCells, particleGrid, cellGrid, block,
        pv, cv, mutationSpeciesView0493b,
        g_populationGuardBuffers0297.dKrelBefore0298, nullptr,
        "reset 0298 krel before", !residentZeroHostMirrors0493b);
    d.totalKrelBefore0298 = sum_vector_0298(krelBefore0298);

    const bool speciesLocalMomentRestore0493g =
        mutationSpeciesView0493b.speciesCount > 0 &&
        mutationSpeciesView0493b.numCells == grid.numCells &&
        mutationSpeciesView0493b.speciesTypes != nullptr &&
        mutationSpeciesView0493b.resamplingEnabled != nullptr &&
        mutationSpeciesView0493b.mass != nullptr &&
        mutationSpeciesView0493b.px != nullptr &&
        mutationSpeciesView0493b.py != nullptr &&
        g_populationGuardBuffers0297.dSpeciesKrelBefore0493g != nullptr &&
        g_populationGuardBuffers0297.dSpeciesKrelAfter0493g != nullptr;
    if (speciesLocalMomentRestore0493g) {
        (void)compute_species_cell_krel_0493g(
            particleCountBefore, particleGrid, block, pv, cv,
            mutationSpeciesView0493b,
            g_populationGuardBuffers0297.dSpeciesKrelBefore0493g,
            "reset 0493g species krel before", false);
    }

    if (cfg.speciesCompositionEnable0490f) {
        const std::size_t ns0490f = static_cast<std::size_t>(cfg.speciesCount0490f);
        cuda_check_0297(cudaMemset(
            g_populationGuardBuffers0297.dCurrentCellSpeciesMass0490f, 0,
            sizeof(double) * static_cast<std::size_t>(grid.numCells) * ns0490f),
            "reset 0490f current cell species mass");
        cuda_check_0297(cudaMemset(
            g_populationGuardBuffers0297.dSpeciesMomentsBefore0490f, 0,
            sizeof(double) * 3u * ns0490f), "reset 0490f before moments");
        cuda_check_0297(cudaMemset(
            g_populationGuardBuffers0297.dSpeciesMomentsAdded0490f, 0,
            sizeof(double) * 3u * ns0490f), "reset 0490f added moments");
        cuda_check_0297(cudaMemset(
            g_populationGuardBuffers0297.dSpeciesMomentsAfter0490f, 0,
            sizeof(double) * 3u * ns0490f), "reset 0490f after moments");
        accumulate_species_memory_and_moments_kernel_0490f<<<particleGrid, block>>>(
            particleCountBefore, pv.role, cv.cellId, pv.type, pv.mass, pv.vx, pv.vy,
            dChi0297, cfg, g_populationGuardBuffers0297.dSpeciesTypes0490f,
            g_populationGuardBuffers0297.dCurrentCellSpeciesMass0490f,
            g_populationGuardBuffers0297.dSpeciesMomentsBefore0490f,
            g_populationGuardBuffers0297.dCounters);
        cuda_check_0297(cudaGetLastError(), "launch accumulate_species_memory_and_moments_kernel_0490f");
    }

    if (cfg.emptyRefillEnable0319 && cfg.activePrefixSafe0315) {
        cuda_check_0297(cudaMemset(g_populationGuardBuffers0297.dCurrentCellType0490c, 0xff,
                                   sizeof(unsigned int) * static_cast<std::size_t>(grid.numCells)),
                        "reset 0490c current cell type");
        cuda_check_0297(cudaMemset(g_populationGuardBuffers0297.dCurrentCellMixed0490c, 0,
                                   sizeof(unsigned int) * static_cast<std::size_t>(grid.numCells)),
                        "reset 0490c current cell mixed flag");
        accumulate_current_cell_types_kernel_0490c<<<particleGrid, block>>>(
            particleCountBefore, pv.role, cv.cellId, pv.type, cfg,
            g_populationGuardBuffers0297.dCurrentCellType0490c,
            g_populationGuardBuffers0297.dCurrentCellMixed0490c);
        cuda_check_0297(cudaGetLastError(), "launch accumulate_current_cell_types_kernel_0490c");
        update_empty_refill_memory_kernel_0319<<<cellGrid, block>>>(
            grid.numCells, cv.count, cv.cellMass, cv.cellUx, cv.cellUy,
            dChi0297,
            g_populationGuardBuffers0297.dCurrentCellType0490c,
            g_populationGuardBuffers0297.dCurrentCellMixed0490c,
            cfg, static_cast<unsigned long long>(step),
            g_populationGuardBuffers0297.dLastCellMass0319,
            g_populationGuardBuffers0297.dLastCellUx0319,
            g_populationGuardBuffers0297.dLastCellUy0319,
            g_populationGuardBuffers0297.dLastCellType0490c,
            g_populationGuardBuffers0297.dLastCellMixed0490c,
            g_populationGuardBuffers0297.dCurrentCellSpeciesMass0490f,
            g_populationGuardBuffers0297.dLastCellSpeciesMass0490f,
            g_populationGuardBuffers0297.dLastCellStep0319,
            g_populationGuardBuffers0297.dCounters);
        cuda_check_0297(cudaGetLastError(), "launch update_empty_refill_memory_kernel_0319");
        classify_empty_refill_cells_kernel_0319<<<cellGrid, block>>>(
            cv.count, dChi0297, cfg, static_cast<unsigned long long>(step),
            g_populationGuardBuffers0297.dLastCellType0490c,
            g_populationGuardBuffers0297.dLastCellMixed0490c,
            g_populationGuardBuffers0297.dSpeciesTypes0490f,
            g_populationGuardBuffers0297.dSpeciesResamplingEnabled0493b,
            g_populationGuardBuffers0297.dLastCellSpeciesMass0490f,
            g_populationGuardBuffers0297.dLastCellStep0319,
            g_populationGuardBuffers0297.dEmptyCells0319,
            g_populationGuardBuffers0297.dEmptyCount0319,
            g_populationGuardBuffers0297.dCounters);
        cuda_check_0297(cudaGetLastError(), "launch classify_empty_refill_cells_kernel_0319");
    }

    classify_population_guard_cells_kernel_0297<<<cellGrid, block>>>(
        cv.count,
        dChi0297,
        cfg,
        cfg.speciesPopulationGuardEnable0490j
            ? g_populationGuardSpeciesSelection0490j.dPoorPending : nullptr,
        cfg.speciesPopulationGuardEnable0490j
            ? g_populationGuardSpeciesSelection0490j.dRichPending : nullptr,
        g_populationGuardBuffers0297.dPoorCells,
        g_populationGuardBuffers0297.dRichCells,
        g_populationGuardBuffers0297.dPoorCount,
        g_populationGuardBuffers0297.dRichCount,
        g_populationGuardBuffers0297.dCounters);
    cuda_check_0297(cudaGetLastError(), "launch classify_population_guard_cells_kernel_0297");

    if (cfg.speciesPopulationGuardEnable0490j) {
        select_species_population_policy_kernel_0490j<<<cellGrid, block>>>(
            cv.count, g_populationGuardSpeciesWorkspace0490j.device_view(), cfg,
            g_populationGuardSpeciesSelection0490j.dPoorPending,
            g_populationGuardSpeciesSelection0490j.dRichPending,
            g_populationGuardSpeciesSelection0490j.dPoorType,
            g_populationGuardSpeciesSelection0490j.dRichType,
            g_populationGuardBuffers0297.dCounters);
        cuda_check_0297(cudaGetLastError(),
                        "launch select_species_population_policy_kernel_0490j");
    }

    select_population_guard_primary_particles_kernel_0297<<<particleGrid, block>>>(
        particleCountBefore,
        pv.x, pv.y, pv.role, cv.cellId, cv.count, pv.mass, pv.type, dChi0297, cfg,
        cfg.speciesPopulationGuardEnable0490j
            ? g_populationGuardSpeciesSelection0490j.dPoorType : nullptr,
        cfg.speciesPopulationGuardEnable0490j
            ? g_populationGuardSpeciesSelection0490j.dRichType : nullptr,
        g_populationGuardBuffers0297.dPoorDonor,
        g_populationGuardBuffers0297.dPoorDonorMassBits0307,
        g_populationGuardBuffers0297.dRichKeep);
    cuda_check_0297(cudaGetLastError(), "launch select_population_guard_primary_particles_kernel_0297");
    select_population_guard_rich_extract_kernel_0297<<<particleGrid, block>>>(
        particleCountBefore,
        pv.x, pv.y, pv.role, cv.cellId, cv.count, pv.type, dChi0297, cfg,
        g_populationGuardBuffers0297.dRichKeep,
        g_populationGuardBuffers0297.dRichExtract);
    cuda_check_0297(cudaGetLastError(), "launch select_population_guard_rich_extract_kernel_0297");

    unsigned int hPoorCount = 0u;
    unsigned int hRichCount = 0u;
    cuda_check_0297(cudaMemcpy(&hPoorCount, g_populationGuardBuffers0297.dPoorCount,
                               sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    "copy poor count D2H");
    cuda_check_0297(cudaMemcpy(&hRichCount, g_populationGuardBuffers0297.dRichCount,
                               sizeof(unsigned int), cudaMemcpyDeviceToHost),
                    "copy rich count D2H");
    d.poorCells = hPoorCount;
    d.richCells = hRichCount;

    std::uint64_t activeBaseAfterRefill0319 = activeBase0315;
    if (cfg.emptyRefillEnable0319 && cfg.activePrefixSafe0315 && cfg.emptyRefillTarget0319 > 0) {
        unsigned int hEmptyCount0319 = 0u;
        cuda_check_0297(cudaMemcpy(&hEmptyCount0319, g_populationGuardBuffers0297.dEmptyCount0319,
                                   sizeof(unsigned int), cudaMemcpyDeviceToHost),
                        "copy 0319 empty count D2H");
        if (hEmptyCount0319 > 0u && cfg.activeCapacity0315 > 0ull) {
            cuda_check_0297(cudaMemset(g_populationGuardBuffers0297.dInactiveCursor, 0, sizeof(unsigned int)),
                            "reset 0319 refill cursor");
            const int emptyGrid0319 = std::max(1, (static_cast<int>(hEmptyCount0319) + block - 1) / block);
            if (d.chiFilterEnable) {
                accumulate_chi_allowed_moments_kernel_0319<<<cellGrid, block>>>(
                    grid.numCells, cv.count, cv.cellMass, cv.cellUx, cv.cellUy, dChi0297, cfg,
                    g_populationGuardBuffers0297.dEmptyAdded0319);
                cuda_check_0297(cudaGetLastError(), "launch accumulate_chi_allowed_moments_kernel_0319");
            }
            empty_refill_cells_kernel_0319<<<emptyGrid0319, block>>>(
                hEmptyCount0319,
                g_populationGuardBuffers0297.dEmptyCells0319,
                g_populationGuardBuffers0297.dInactiveCursor,
                pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.type, pv.role,
                cfg,
                g_populationGuardBuffers0297.dLastCellMass0319,
                g_populationGuardBuffers0297.dLastCellUx0319,
                g_populationGuardBuffers0297.dLastCellUy0319,
                g_populationGuardBuffers0297.dLastCellType0490c,
                g_populationGuardBuffers0297.dLastCellMixed0490c,
                g_populationGuardBuffers0297.dSpeciesTypes0490f,
                g_populationGuardBuffers0297.dSpeciesResamplingEnabled0493b,
                g_populationGuardBuffers0297.dLastCellSpeciesMass0490f,
                g_populationGuardBuffers0297.dSpeciesMomentsAdded0490f,
                g_populationGuardBuffers0297.dEmptyAdded0319,
                g_populationGuardBuffers0297.dCounters);
            cuda_check_0297(cudaGetLastError(), "launch empty_refill_cells_kernel_0319");
            unsigned long long hRefillCounters0319[32] = {};
            double hEmptyAdded0319[6] = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
            cuda_check_0297(cudaMemcpy(hRefillCounters0319, g_populationGuardBuffers0297.dCounters,
                                       sizeof(hRefillCounters0319), cudaMemcpyDeviceToHost),
                            "copy 0319 refill counters D2H");
            cuda_check_0297(cudaMemcpy(hEmptyAdded0319, g_populationGuardBuffers0297.dEmptyAdded0319,
                                       sizeof(hEmptyAdded0319), cudaMemcpyDeviceToHost),
                            "copy 0319 added moments D2H");
            const std::uint64_t refillParticles0319 = static_cast<std::uint64_t>(hRefillCounters0319[18]);
            if (refillParticles0319 > 0u) {
                activeBaseAfterRefill0319 = activeBase0315 + refillParticles0319;
                d.emptyRefillAddedMass0319 = hEmptyAdded0319[0];
                d.emptyRefillAddedPx0319 = hEmptyAdded0319[1];
                d.emptyRefillAddedPy0319 = hEmptyAdded0319[2];
                const int activeAfterRefillInt0319 = static_cast<int>(activeBaseAfterRefill0319);
                if (static_cast<std::uint64_t>(activeAfterRefillInt0319) != activeBaseAfterRefill0319) {
                    throw std::runtime_error("cuda_resampling_population_guard_0297: 0319 active count exceeds int range");
                }
                const int particleGridRefill0319 = std::max(1, (activeAfterRefillInt0319 + block - 1) / block);
                if (cfg.speciesCompositionEnable0490f) {
                    const std::size_t ns0490f = static_cast<std::size_t>(cfg.speciesCount0490f);
                    std::vector<double> before0490f(3u * ns0490f, 0.0);
                    std::vector<double> added0490f(3u * ns0490f, 0.0);
                    std::vector<double> scaleShift0490f(3u * ns0490f, 0.0);
                    cuda_check_0297(cudaMemcpy(
                        before0490f.data(), g_populationGuardBuffers0297.dSpeciesMomentsBefore0490f,
                        sizeof(double) * before0490f.size(), cudaMemcpyDeviceToHost),
                        "copy 0490f before moments D2H");
                    cuda_check_0297(cudaMemcpy(
                        added0490f.data(), g_populationGuardBuffers0297.dSpeciesMomentsAdded0490f,
                        sizeof(double) * added0490f.size(), cudaMemcpyDeviceToHost),
                        "copy 0490f added moments D2H");
                    for (std::size_t si = 0; si < ns0490f; ++si) {
                        if (!params.speciesDefinitions[si].resamplingEnable) {
                            scaleShift0490f[3u * si + 0u] = 1.0;
                            continue;
                        }
                        const double m0 = before0490f[3u * si + 0u];
                        const double ma = added0490f[3u * si + 0u];
                        if (ma > 0.0 && !(m0 > 0.0)) {
                            throw std::runtime_error(
                                "0490f mixed refill cannot conserve a species absent from the current active population");
                        }
                        const double scale = (m0 > 0.0 && ma > 0.0) ? m0 / (m0 + ma) : 1.0;
                        const double pxScaled = scale * (before0490f[3u * si + 1u] + added0490f[3u * si + 1u]);
                        const double pyScaled = scale * (before0490f[3u * si + 2u] + added0490f[3u * si + 2u]);
                        scaleShift0490f[3u * si + 0u] = scale;
                        scaleShift0490f[3u * si + 1u] = m0 > 0.0
                            ? (before0490f[3u * si + 1u] - pxScaled) / m0 : 0.0;
                        scaleShift0490f[3u * si + 2u] = m0 > 0.0
                            ? (before0490f[3u * si + 2u] - pyScaled) / m0 : 0.0;
                    }
                    cuda_check_0297(cudaMemcpy(
                        g_populationGuardBuffers0297.dSpeciesScaleShift0490f, scaleShift0490f.data(),
                        sizeof(double) * scaleShift0490f.size(), cudaMemcpyHostToDevice),
                        "copy 0490f species scale/shift H2D");
                    scale_and_shift_species_particles_kernel_0490f<<<particleGridRefill0319, block>>>(
                        activeAfterRefillInt0319, pv.role, pv.x, pv.y, pv.type, dChi0297, cfg,
                        g_populationGuardBuffers0297.dSpeciesTypes0490f,
                        g_populationGuardBuffers0297.dSpeciesResamplingEnabled0493b,
                        g_populationGuardBuffers0297.dSpeciesScaleShift0490f,
                        pv.mass, pv.vx, pv.vy);
                    cuda_check_0297(cudaGetLastError(), "launch scale_and_shift_species_particles_kernel_0490f");
                    cuda_check_0297(cudaMemset(
                        g_populationGuardBuffers0297.dSpeciesMomentsAfter0490f, 0,
                        sizeof(double) * 3u * ns0490f), "reset 0490f after moments post-correction");
                    accumulate_species_moments_after_kernel_0490f<<<particleGridRefill0319, block>>>(
                        activeAfterRefillInt0319, pv.role, pv.x, pv.y, pv.type, pv.mass, pv.vx, pv.vy,
                        dChi0297, cfg, g_populationGuardBuffers0297.dSpeciesTypes0490f,
                        g_populationGuardBuffers0297.dSpeciesMomentsAfter0490f);
                    cuda_check_0297(cudaGetLastError(), "launch accumulate_species_moments_after_kernel_0490f");
                    std::vector<double> after0490f(3u * ns0490f, 0.0);
                    cuda_check_0297(cudaMemcpy(
                        after0490f.data(), g_populationGuardBuffers0297.dSpeciesMomentsAfter0490f,
                        sizeof(double) * after0490f.size(), cudaMemcpyDeviceToHost),
                        "copy 0490f after moments D2H");
                    for (std::size_t si = 0; si < ns0490f; ++si) {
                        d.emptyRefillMaxAbsSpeciesMassError0490f = std::max(
                            d.emptyRefillMaxAbsSpeciesMassError0490f,
                            std::abs(after0490f[3u * si + 0u] - before0490f[3u * si + 0u]));
                        const double dpx = after0490f[3u * si + 1u] - before0490f[3u * si + 1u];
                        const double dpy = after0490f[3u * si + 2u] - before0490f[3u * si + 2u];
                        d.emptyRefillMaxAbsSpeciesMomentumError0490f = std::max(
                            d.emptyRefillMaxAbsSpeciesMomentumError0490f, std::hypot(dpx, dpy));
                    }
                } else {
                    const double scaleMassBase0319 = d.chiFilterEnable ? hEmptyAdded0319[3] : d.totalMassBefore;
                    const double scalePxBase0319 = d.chiFilterEnable ? hEmptyAdded0319[4] : d.totalPxBefore;
                    const double scalePyBase0319 = d.chiFilterEnable ? hEmptyAdded0319[5] : d.totalPyBefore;
                    if (scaleMassBase0319 > 0.0 && hEmptyAdded0319[0] > 0.0) {
                        d.emptyRefillMassScale0319 = scaleMassBase0319 / (scaleMassBase0319 + hEmptyAdded0319[0]);
                        const double pxAfterScale = d.emptyRefillMassScale0319 * (scalePxBase0319 + hEmptyAdded0319[1]);
                        const double pyAfterScale = d.emptyRefillMassScale0319 * (scalePyBase0319 + hEmptyAdded0319[2]);
                        d.emptyRefillVelocityShiftX0319 = (scalePxBase0319 - pxAfterScale) / scaleMassBase0319;
                        d.emptyRefillVelocityShiftY0319 = (scalePyBase0319 - pyAfterScale) / scaleMassBase0319;
                        scale_and_shift_active_particles_kernel_0319<<<particleGridRefill0319, block>>>(
                            activeAfterRefillInt0319,
                            d.emptyRefillMassScale0319,
                            d.emptyRefillVelocityShiftX0319,
                            d.emptyRefillVelocityShiftY0319,
                            pv.role, cv.cellId, dChi0297, cfg, pv.mass, pv.vx, pv.vy);
                        cuda_check_0297(cudaGetLastError(), "launch scale_and_shift_active_particles_kernel_0319");
                    }
                }
            }
        }
    }

    DevicePopulationGuardConfig0297 splitCfg0319 = cfg;
    if (splitCfg0319.activePrefixSafe0315) {
        splitCfg0319.activeBase0315 = activeBaseAfterRefill0319;
        splitCfg0319.activeCapacity0315 = hostMirror.Np >= activeBaseAfterRefill0319
            ? hostMirror.Np - activeBaseAfterRefill0319 : 0u;
    }

    const int richGrid = std::max(1, (static_cast<int>(hRichCount) + block - 1) / block);
    if (hRichCount > 0u && !cfg.activePrefixSafe0315) {
        merge_rich_cells_kernel_0297<<<richGrid, block>>>(
            hRichCount,
            g_populationGuardBuffers0297.dRichCells,
            g_populationGuardBuffers0297.dRichKeep,
            g_populationGuardBuffers0297.dRichExtract,
            pv.vx, pv.vy, pv.mass, pv.type, pv.role,
            mutationSpeciesView0493b.speciesTypes,
            mutationSpeciesView0493b.resamplingEnabled,
            mutationSpeciesView0493b.speciesCount,
            g_populationGuardBuffers0297.dCounters);
        cuda_check_0297(cudaGetLastError(), "launch merge_rich_cells_kernel_0297");
    }
    const bool usedTailInactivePool0313 = !cfg.activePrefixSafe0315 && build_inactive_tail_list_0313(
        static_cast<int>(hostMirror.Np), hPoorCount, pv.role, block,
        g_populationGuardBuffers0297.dInactiveList,
        g_populationGuardBuffers0297.dInactiveCount);
    if (!cfg.activePrefixSafe0315 && !usedTailInactivePool0313) {
        cuda_check_0297(cudaMemset(g_populationGuardBuffers0297.dInactiveCount, 0, sizeof(unsigned int)),
                        "reset inactive count");
        build_inactive_list_kernel_0297<<<particleGrid, block>>>(
            static_cast<int>(hostMirror.Np), pv.role,
            g_populationGuardBuffers0297.dInactiveList,
            g_populationGuardBuffers0297.dInactiveCount);
        cuda_check_0297(cudaGetLastError(), "launch build_inactive_list_kernel_0297");
    }
    cuda_check_0297(cudaMemset(g_populationGuardBuffers0297.dInactiveCursor, 0, sizeof(unsigned int)),
                    "reset inactive cursor");

    const int poorGrid = std::max(1, (static_cast<int>(hPoorCount) + block - 1) / block);
    if (hPoorCount > 0u) {
        split_poor_cells_kernel_0297<<<poorGrid, block>>>(
            hPoorCount,
            g_populationGuardBuffers0297.dPoorCells,
            g_populationGuardBuffers0297.dInactiveList,
            g_populationGuardBuffers0297.dInactiveCount,
            g_populationGuardBuffers0297.dInactiveCursor,
            g_populationGuardBuffers0297.dPoorDonor,
            pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.type, pv.role,
            mutationSpeciesView0493b.speciesTypes,
            mutationSpeciesView0493b.resamplingEnabled,
            mutationSpeciesView0493b.speciesCount,
            splitCfg0319,
            g_populationGuardBuffers0297.dCounters,
            g_populationGuardBuffers0297.dMinima0307);
        cuda_check_0297(cudaGetLastError(), "launch split_poor_cells_kernel_0297");
    }
    if (hRichCount > 0u && cfg.activePrefixSafe0315) {
        merge_rich_cells_prefix_safe_kernel_0315<<<1, 1>>>(
            hRichCount,
            g_populationGuardBuffers0297.dRichCells,
            g_populationGuardBuffers0297.dRichKeep,
            g_populationGuardBuffers0297.dRichExtract,
            activeBaseAfterRefill0319,
            static_cast<unsigned long long>(hostMirror.Np),
            pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.type, pv.role,
            mutationSpeciesView0493b.speciesTypes,
            mutationSpeciesView0493b.resamplingEnabled,
            mutationSpeciesView0493b.speciesCount,
            g_populationGuardBuffers0297.dCounters);
        cuda_check_0297(cudaGetLastError(), "launch merge_rich_cells_prefix_safe_kernel_0315");
    }
    const Clock::time_point tk1 = Clock::now();
    d.kernelSeconds = seconds_between(tk0, tk1);

    unsigned long long hCounters[32] = {};
    double hMinima0307[3] = {1.0e300, 1.0e300, 1.0e300};
    const Clock::time_point td0 = Clock::now();
    cuda_check_0297(cudaMemcpy(hCounters, g_populationGuardBuffers0297.dCounters,
                               sizeof(hCounters), cudaMemcpyDeviceToHost),
                    "copy counters D2H");
    cuda_check_0297(cudaMemcpy(hMinima0307, g_populationGuardBuffers0297.dMinima0307,
                               sizeof(hMinima0307), cudaMemcpyDeviceToHost),
                    "copy 0307 minima D2H");
    const Clock::time_point td1 = Clock::now();
    d.downloadSeconds = seconds_between(td0, td1);
    d.mergeApplied = static_cast<std::uint64_t>(hCounters[0]);
    d.splitApplied = static_cast<std::uint64_t>(hCounters[1]);
    d.splitSkippedNoInactive = static_cast<std::uint64_t>(hCounters[2]);
    d.splitSkippedNoDonor = static_cast<std::uint64_t>(hCounters[3]);
    d.mergeSkippedNoPair = static_cast<std::uint64_t>(hCounters[4]);
    d.excludedBoundaryCells0299 = static_cast<std::uint64_t>(hCounters[5]);
    d.excludedOpenBoundaryCells0299 = static_cast<std::uint64_t>(hCounters[6]);
    d.excludedSolidHaloCells0299 = static_cast<std::uint64_t>(hCounters[7]);
    d.splitSkippedDonorMass0307 = static_cast<std::uint64_t>(hCounters[8]);
    d.splitSkippedNewMass0307 = static_cast<std::uint64_t>(hCounters[9]);
    d.splitCandidatesSolidAdjacent0307 = static_cast<std::uint64_t>(hCounters[10]);
    d.splitSkippedSolidAdjacent0307 = static_cast<std::uint64_t>(hCounters[11]);
    d.splitAppliedSolidAdjacent0307 = static_cast<std::uint64_t>(hCounters[12]);
    d.splitFromMassBelow0p5_0307 = static_cast<std::uint64_t>(hCounters[13]);
    d.splitFromMassBelow0p25_0307 = static_cast<std::uint64_t>(hCounters[14]);
    d.splitFromMassBelow0p1_0307 = static_cast<std::uint64_t>(hCounters[15]);
    d.emptyRefillCandidates0319 = static_cast<std::uint64_t>(hCounters[16]);
    d.emptyRefillCells0319 = static_cast<std::uint64_t>(hCounters[17]);
    d.emptyRefillParticles0319 = static_cast<std::uint64_t>(hCounters[18]);
    d.emptyRefillSkippedNoMemory0319 = static_cast<std::uint64_t>(hCounters[19]);
    d.emptyRefillSkippedNoCapacity0319 = static_cast<std::uint64_t>(hCounters[20]);
    d.emptyRefillMemoryUpdates0319 = static_cast<std::uint64_t>(hCounters[21]);
    d.emptyRefillSkippedMixedSpecies0490c = static_cast<std::uint64_t>(hCounters[23]);
    d.emptyRefillSkippedTargetTooSmall0490f = static_cast<std::uint64_t>(hCounters[24]);
    d.emptyRefillMixedCells0490f = static_cast<std::uint64_t>(hCounters[25]);
    d.speciesPoorSelections0490j = static_cast<std::uint64_t>(hCounters[27]);
    d.speciesRichSelections0490j = static_cast<std::uint64_t>(hCounters[28]);
    d.speciesTargetInfeasibleCells0490j = static_cast<std::uint64_t>(hCounters[29]);
    d.disabledSpeciesMutationCount0493b = static_cast<std::uint64_t>(hCounters[30]);
    if (d.speciesPopulationGuardCuda0490j) {
        d.speciesDirectedSplits0490j = d.splitApplied;
        d.speciesDirectedMerges0490j = d.mergeApplied;
    }
    if (hCounters[26] != 0ull) {
        throw std::runtime_error(
            "0490f CUDA species composition deposit encountered an unregistered fluid type");
    }
    if (hCounters[30] != 0ull) {
        throw std::runtime_error(
            "0493b population guard attempted to mutate a resampling-disabled species");
    }
    d.excludedChiCells = static_cast<std::uint64_t>(hCounters[22]);
    d.minSplitDonorMass0307 = hMinima0307[0] < 1.0e299 ? hMinima0307[0] : 0.0;
    d.minSplitNewParticleMass0307 = hMinima0307[1] < 1.0e299 ? hMinima0307[1] : 0.0;
    d.minPostSplitDonorMass0307 = hMinima0307[2] < 1.0e299 ? hMinima0307[2] : 0.0;

    if (d.mergeApplied > 0u || d.splitApplied > 0u || d.emptyRefillParticles0319 > 0u) {
        if (cfg.activePrefixSafe0315) {
            gpuState.set_active_fluid_size(activeBaseAfterRefill0319 + d.splitApplied - d.mergeApplied);
        }
        cuda_shared_particle_state_0251_mark_fresh("cuda_resampling_population_guard_0297");
    }

    ParticleState afterMirror = guardMirror;
    if (cfg.activePrefixSafe0315) {
        afterMirror.NactiveFluid = gpuState.active_fluid_size();
        g_populationGuardWorkspace0297.ensure_capacity(afterMirror.NactiveFluid, grid.numCells, &workspaceDiag);
    }
    CudaCellMoments after{};
    CudaCellMomentsDiagnostics afterDiag{};
    cuda_deposit_cell_moments_atomic_from_persistent_state(
        afterMirror, gpuState, g_populationGuardWorkspace0297, grid, GridShift{}, params,
        after, &afterDiag, options);
    d.depositAfterSeconds = afterDiag.totalSeconds;

    // 0298: after the support mutation, measure the cell-relative kinetic
    // energy loss/gain against the pre-mutation target.  This is the missing
    // budget for merge operations: mass and momentum are conserved by 0297,
    // while relative kinetic energy generally is not unless we rescale the
    // post-mutation relative velocities inside each affected cell.
    const std::uint64_t particleCountAfter64 = cfg.activePrefixSafe0315 ? afterMirror.NactiveFluid : hostMirror.Np;
    const int particleCountAfter = static_cast<int>(particleCountAfter64);
    if (static_cast<std::uint64_t>(particleCountAfter) != particleCountAfter64) {
        throw std::runtime_error("cuda_resampling_population_guard_0297: post-split particle count exceeds int range");
    }
    const int particleGridAfter = std::max(1, (particleCountAfter + block - 1) / block);
    std::vector<double> krelAfterPreRestore0298 = compute_cell_krel_0298(
        particleCountAfter, grid.numCells, particleGridAfter, cellGrid, block,
        pv, g_populationGuardWorkspace0297.device_view(), mutationSpeciesView0493b,
        g_populationGuardBuffers0297.dKrelAfter0298,
        g_populationGuardBuffers0297.dEnergyRestoreCounters0298,
        "reset 0298 krel after pre-restore", !residentZeroHostMirrors0493b);
    if (!residentZeroHostMirrors0493b) {
        d.totalKrelAfterPreRestore0298 = sum_vector_0298(krelAfterPreRestore0298);
        compare_krel_vectors_0298(krelBefore0298,
                                  krelAfterPreRestore0298,
                                  d.maxAbsCellKrelErrorPreRestore0298,
                                  d.maxRelCellKrelErrorPreRestore0298);
    }

    if (speciesLocalMomentRestore0493g) {
        (void)compute_species_cell_krel_0493g(
            particleCountAfter, particleGridAfter, block, pv,
            g_populationGuardWorkspace0297.device_view(),
            mutationSpeciesView0493b,
            g_populationGuardBuffers0297.dSpeciesKrelAfter0493g,
            "reset 0493g species krel after pre-restore", false);
    }

    if (d.momentRestoreRequested0298 && (d.mergeApplied > 0u || d.splitApplied > 0u)) {
        if (speciesLocalMomentRestore0493g) {
            restore_species_cell_relative_energy_kernel_0493g<<<particleGridAfter, block>>>(
                particleCountAfter,
                g_populationGuardBuffers0297.dSpeciesKrelBefore0493g,
                g_populationGuardBuffers0297.dSpeciesKrelAfter0493g,
                g_populationGuardWorkspace0297.device_view().cellId,
                pv.type, pv.role, mutationSpeciesView0493b, pv.vx, pv.vy,
                minCurrentKrel0298, d.energyRestoreMaxScale0298,
                restoreAbsTol0298, restoreRelTol0298,
                g_populationGuardBuffers0297.dEnergyRestoreCounters0298);
            cuda_check_0297(
                cudaGetLastError(),
                "launch restore_species_cell_relative_energy_kernel_0493g");
        } else {
            restore_cell_relative_energy_kernel_0298<<<particleGridAfter, block>>>(
                particleCountAfter,
                g_populationGuardBuffers0297.dKrelBefore0298,
                g_populationGuardBuffers0297.dKrelAfter0298,
                g_populationGuardWorkspace0297.device_view().count,
                g_populationGuardWorkspace0297.device_view().cellMass,
                g_populationGuardWorkspace0297.device_view().cellUx,
                g_populationGuardWorkspace0297.device_view().cellUy,
                g_populationGuardWorkspace0297.device_view().cellId,
                pv.type, pv.role, mutationSpeciesView0493b, pv.vx, pv.vy,
                minCurrentKrel0298, d.energyRestoreMaxScale0298,
                restoreAbsTol0298, restoreRelTol0298,
                g_populationGuardBuffers0297.dEnergyRestoreCounters0298);
            cuda_check_0297(
                cudaGetLastError(),
                "launch restore_cell_relative_energy_kernel_0298");
        }
        unsigned long long hEnergyCounters0298[2] = {0ull, 0ull};
        cuda_check_0297(cudaMemcpy(hEnergyCounters0298,
                                   g_populationGuardBuffers0297.dEnergyRestoreCounters0298,
                                   sizeof(hEnergyCounters0298), cudaMemcpyDeviceToHost),
                        "copy 0298 energy counters D2H");
        d.energyRestoreParticleUpdates0298 = static_cast<std::uint64_t>(hEnergyCounters0298[0]);
        d.energyRestoreSkippedParticles0298 = static_cast<std::uint64_t>(hEnergyCounters0298[1]);
        d.energyRestoreApplied0298 = d.energyRestoreParticleUpdates0298 > 0u;
        if (d.energyRestoreApplied0298) {
            cuda_shared_particle_state_0251_mark_fresh("cuda_resampling_moment_restore_0298");
        }

        CudaCellMomentsDiagnostics restoredDiag{};
        cuda_deposit_cell_moments_atomic_from_persistent_state(
            afterMirror, gpuState, g_populationGuardWorkspace0297, grid, GridShift{}, params,
            after, &restoredDiag, options);
        d.depositAfterSeconds += restoredDiag.totalSeconds;
    }

    std::vector<double> krelAfter0298 = compute_cell_krel_0298(
        particleCountAfter, grid.numCells, particleGridAfter, cellGrid, block,
        pv, g_populationGuardWorkspace0297.device_view(), mutationSpeciesView0493b,
        g_populationGuardBuffers0297.dKrelAfter0298, nullptr,
        "reset 0298 krel final", !residentZeroHostMirrors0493b);
    if (!residentZeroHostMirrors0493b) {
        d.totalKrelAfter0298 = sum_vector_0298(krelAfter0298);
        compare_krel_vectors_0298(krelBefore0298,
                                  krelAfter0298,
                                  d.maxAbsCellKrelError0298,
                                  d.maxRelCellKrelError0298);
        accumulate_global_diagnostics_0297(after,
                                           d.fluidParticlesAfter,
                                           d.wetCellsAfter,
                                           d.totalMassAfter,
                                           d.totalPxAfter,
                                           d.totalPyAfter);
        compare_before_after_0297(before, after, d);
    } else {
        d.fluidParticlesAfter = gpuState.active_fluid_size();
    }

    // Do not download the resident particle state just for 0297 diagnostics.
    // These counts are non-fluid storage slots (inactive plus any latent slots)
    // inferred from the deposited fluid count; downstream CPU diagnostics still
    // perform their usual explicit download on summary/final steps.
    d.inactiveParticlesBefore = hostMirror.Np >= d.fluidParticlesBefore ? hostMirror.Np - d.fluidParticlesBefore : 0u;
    d.inactiveParticlesAfter = hostMirror.Np >= d.fluidParticlesAfter ? hostMirror.Np - d.fluidParticlesAfter : 0u;

    d.handled = true;
    d.totalSeconds = seconds_between(t0, Clock::now());
    write_csv_row_0297(params, d);
    return d;
}

} // namespace mpcd

#endif
