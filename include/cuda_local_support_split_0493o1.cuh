// 0493o1 target-driven effective-population split guard.
//
// This file is included inside the anonymous namespace of
// cuda_resampling_population_guard_0297.cu, after the legacy helpers.  It is
// deliberately not a separate translation unit: the implementation reuses the
// validated 0297 geometry/safety helpers and the resident particle views.

constexpr unsigned long long kSyntheticTokenMask0493o1 = 1ull << 63;
constexpr unsigned long long kSyntheticTokenIndexMask0493o1 = ~kSyntheticTokenMask0493o1;

struct LocalSupportSplitResult0493o1 {
    std::uint64_t poorNonEmptyPairs = 0u;
    std::uint64_t emptySpeciesPairs = 0u;
    std::uint64_t requestedSplits = 0u;
    std::uint64_t appliedSplits = 0u;
    std::uint64_t repairedToTarget = 0u;
    std::uint64_t incompleteRepairCells = 0u;
    std::uint64_t missingSplitsToTarget = 0u;
    std::uint64_t limitedByCellCap = 0u;
    std::uint64_t limitedByStepCap = 0u;
    std::uint64_t limitedByPool = 0u;
    std::uint64_t noCandidatePairs = 0u;
    std::uint64_t candidateCountMismatchPairs = 0u;
    std::uint64_t safetyLimitedPairs = 0u;
    std::uint64_t maxSplitsPerPair = 0u;
    double minNeffBefore = 0.0;
    double minNeffAfter = 0.0;
    bool noPoorEarlyExit0493o3 = false;
    double resetSeconds0493o3 = 0.0;
    double classifySeconds0493o3 = 0.0;
    double poorCountDownloadSeconds0493o3 = 0.0;
    double candidateBuildSeconds0493o3 = 0.0;
    double planSeconds0493o3 = 0.0;
    double applySeconds0493o3 = 0.0;
    double diagnosticsSeconds0493o3 = 0.0;
};

struct LocalSupportSplitDeviceView0493o1 {
    unsigned char* dPoor;
    unsigned char* dProcessed;
    unsigned char* dTargetReached;
    unsigned char* dCellCapLimited;
    unsigned char* dStepCapLimited;
    unsigned char* dPoolLimited;
    unsigned char* dSafetyLimited;
    double* dNeff;
    double* dDeficit;
    double* dS2After;
    unsigned int* dRequested;
    unsigned int* dGranted;
    unsigned int* dApplied;
    unsigned int* dSlotOffset;
    unsigned int* dPairOffset;
    unsigned int* dPairCursor;
    unsigned int* dCandidateCount;
    unsigned int* dParticleIndex;
    double* dCandidateMass;
    unsigned long long* dCandidateToken;
    unsigned long long* dPlanParentToken;
    unsigned long long* dStats;
    double* dMinima;
};

struct LocalSupportSplitBuffers0493o1 {
    unsigned char* dPoor = nullptr;
    unsigned char* dProcessed = nullptr;
    unsigned char* dTargetReached = nullptr;
    unsigned char* dCellCapLimited = nullptr;
    unsigned char* dStepCapLimited = nullptr;
    unsigned char* dPoolLimited = nullptr;
    unsigned char* dSafetyLimited = nullptr;
    double* dNeff = nullptr;
    double* dDeficit = nullptr;
    double* dS2After = nullptr;
    unsigned int* dRequested = nullptr;
    unsigned int* dGranted = nullptr;
    unsigned int* dApplied = nullptr;
    unsigned int* dSlotOffset = nullptr;
    unsigned int* dPairOffset = nullptr;
    unsigned int* dPairCursor = nullptr;
    unsigned int* dCandidateCount = nullptr;
    unsigned int* dParticleIndex = nullptr;
    double* dCandidateMass = nullptr;
    unsigned long long* dCandidateToken = nullptr;
    unsigned long long* dPlanParentToken = nullptr;
    unsigned long long* dStats = nullptr;
    double* dMinima = nullptr;
    cudaEvent_t timingEvents0493o3[11] = {};
    bool timingEventsReady0493o3 = false;
    int denseCapacity = 0;
    int maxSplitsCapacity = 0;
    int particleCapacity = 0;

    LocalSupportSplitBuffers0493o1() = default;
    LocalSupportSplitBuffers0493o1(const LocalSupportSplitBuffers0493o1&) = delete;
    LocalSupportSplitBuffers0493o1& operator=(const LocalSupportSplitBuffers0493o1&) = delete;
    LocalSupportSplitBuffers0493o1(LocalSupportSplitBuffers0493o1&&) = delete;
    LocalSupportSplitBuffers0493o1& operator=(LocalSupportSplitBuffers0493o1&&) = delete;
    ~LocalSupportSplitBuffers0493o1() { release(); }

    LocalSupportSplitDeviceView0493o1 device_view() const {
        return {
            dPoor, dProcessed, dTargetReached, dCellCapLimited,
            dStepCapLimited, dPoolLimited, dSafetyLimited,
            dNeff, dDeficit, dS2After,
            dRequested, dGranted, dApplied, dSlotOffset,
            dPairOffset, dPairCursor, dCandidateCount, dParticleIndex,
            dCandidateMass, dCandidateToken, dPlanParentToken,
            dStats, dMinima
        };
    }

    template <class T>
    static void free_ptr(T*& p) {
        if (p != nullptr) cudaFree(p);
        p = nullptr;
    }

    void ensure_timing_events_0493o3() {
        if (timingEventsReady0493o3) return;
        for (cudaEvent_t& event : timingEvents0493o3) {
            cuda_check_0297(cudaEventCreate(&event), "0493o3 create timing event");
        }
        timingEventsReady0493o3 = true;
    }

    void release_timing_events_0493o3() {
        if (!timingEventsReady0493o3) return;
        for (cudaEvent_t& event : timingEvents0493o3) {
            if (event != nullptr) cudaEventDestroy(event);
            event = nullptr;
        }
        timingEventsReady0493o3 = false;
    }

    void release() {
        free_ptr(dPoor);
        free_ptr(dProcessed);
        free_ptr(dTargetReached);
        free_ptr(dCellCapLimited);
        free_ptr(dStepCapLimited);
        free_ptr(dPoolLimited);
        free_ptr(dSafetyLimited);
        free_ptr(dNeff);
        free_ptr(dDeficit);
        free_ptr(dS2After);
        free_ptr(dRequested);
        free_ptr(dGranted);
        free_ptr(dApplied);
        free_ptr(dSlotOffset);
        free_ptr(dPairOffset);
        free_ptr(dPairCursor);
        free_ptr(dCandidateCount);
        free_ptr(dParticleIndex);
        free_ptr(dCandidateMass);
        free_ptr(dCandidateToken);
        free_ptr(dPlanParentToken);
        free_ptr(dStats);
        free_ptr(dMinima);
        release_timing_events_0493o3();
        denseCapacity = 0;
        maxSplitsCapacity = 0;
        particleCapacity = 0;
    }

    void ensure(int denseSize, int maxSplits, int particleCount) {
        if (denseSize <= 0 || maxSplits <= 0 || particleCount < 0 ||
            maxSplits == std::numeric_limits<int>::max()) {
            throw std::runtime_error("0493o1 requires valid positive workspace dimensions");
        }
        if (denseSize <= denseCapacity && maxSplits <= maxSplitsCapacity &&
            particleCount <= particleCapacity &&
            dPoor && dProcessed && dTargetReached && dCellCapLimited &&
            dStepCapLimited && dPoolLimited && dSafetyLimited && dNeff &&
            dDeficit && dS2After && dRequested && dGranted && dApplied &&
            dSlotOffset && dPairOffset && dPairCursor && dCandidateCount &&
            (particleCount == 0 || dParticleIndex) && dCandidateMass &&
            dCandidateToken && dPlanParentToken && dStats && dMinima) {
            ensure_timing_events_0493o3();
            return;
        }
        release();
        const std::size_t dense = static_cast<std::size_t>(denseSize);
        const std::size_t candidateStride = static_cast<std::size_t>(maxSplits) + 1u;
        const std::size_t maxSize = std::numeric_limits<std::size_t>::max();
        if (dense > maxSize / candidateStride ||
            dense > maxSize / static_cast<std::size_t>(maxSplits)) {
            throw std::runtime_error("0493o1 workspace size overflow");
        }
        const std::size_t candidates = dense * candidateStride;
        const std::size_t plan = dense * static_cast<std::size_t>(maxSplits);
        cuda_check_0297(cudaMalloc(&dPoor, dense * sizeof(unsigned char)), "0493o1 malloc poor");
        cuda_check_0297(cudaMalloc(&dProcessed, dense * sizeof(unsigned char)), "0493o1 malloc processed");
        cuda_check_0297(cudaMalloc(&dTargetReached, dense * sizeof(unsigned char)), "0493o1 malloc target reached");
        cuda_check_0297(cudaMalloc(&dCellCapLimited, dense * sizeof(unsigned char)), "0493o1 malloc cell cap");
        cuda_check_0297(cudaMalloc(&dStepCapLimited, dense * sizeof(unsigned char)), "0493o1 malloc step cap");
        cuda_check_0297(cudaMalloc(&dPoolLimited, dense * sizeof(unsigned char)), "0493o1 malloc pool cap");
        cuda_check_0297(cudaMalloc(&dSafetyLimited, dense * sizeof(unsigned char)), "0493o1 malloc safety cap");
        cuda_check_0297(cudaMalloc(&dNeff, dense * sizeof(double)), "0493o1 malloc neff");
        cuda_check_0297(cudaMalloc(&dDeficit, dense * sizeof(double)), "0493o1 malloc deficit");
        cuda_check_0297(cudaMalloc(&dS2After, dense * sizeof(double)), "0493o1 malloc s2 after");
        cuda_check_0297(cudaMalloc(&dRequested, dense * sizeof(unsigned int)), "0493o1 malloc requested");
        cuda_check_0297(cudaMalloc(&dGranted, dense * sizeof(unsigned int)), "0493o1 malloc granted");
        cuda_check_0297(cudaMalloc(&dApplied, dense * sizeof(unsigned int)), "0493o1 malloc applied");
        cuda_check_0297(cudaMalloc(&dSlotOffset, dense * sizeof(unsigned int)), "0493o1 malloc slot offsets");
        cuda_check_0297(cudaMalloc(&dPairOffset, dense * sizeof(unsigned int)), "0493o1 malloc pair offsets");
        cuda_check_0297(cudaMalloc(&dPairCursor, dense * sizeof(unsigned int)), "0493o1 malloc pair cursors");
        cuda_check_0297(cudaMalloc(&dCandidateCount, dense * sizeof(unsigned int)), "0493o1 malloc candidate counts");
        if (particleCount > 0) {
            cuda_check_0297(cudaMalloc(&dParticleIndex,
                static_cast<std::size_t>(particleCount) * sizeof(unsigned int)),
                "0493o1 malloc compact particle indices");
        }
        cuda_check_0297(cudaMalloc(&dCandidateMass, candidates * sizeof(double)), "0493o1 malloc candidate masses");
        cuda_check_0297(cudaMalloc(&dCandidateToken, candidates * sizeof(unsigned long long)), "0493o1 malloc candidate tokens");
        cuda_check_0297(cudaMalloc(&dPlanParentToken, plan * sizeof(unsigned long long)), "0493o1 malloc plan tokens");
        cuda_check_0297(cudaMalloc(&dStats, 16u * sizeof(unsigned long long)), "0493o1 malloc stats");
        cuda_check_0297(cudaMalloc(&dMinima, 2u * sizeof(double)), "0493o1 malloc minima");
        ensure_timing_events_0493o3();
        denseCapacity = denseSize;
        maxSplitsCapacity = maxSplits;
        particleCapacity = particleCount;
    }
};

LocalSupportSplitBuffers0493o1 g_localSupportSplitBuffers0493o1;

enum LocalSupportTimingEvent0493o3 : int {
    ResetStart0493o3 = 0,
    ResetStop0493o3 = 1,
    ClassifyStop0493o3 = 2,
    CandidateStart0493o3 = 3,
    CandidateStop0493o3 = 4,
    PlanStart0493o3 = 5,
    PlanStop0493o3 = 6,
    ApplyStart0493o3 = 7,
    ApplyStop0493o3 = 8,
    DiagnosticsStart0493o3 = 9,
    DiagnosticsStop0493o3 = 10
};

void record_local_support_event_0493o3(int index) {
    cuda_check_0297(cudaEventRecord(
        g_localSupportSplitBuffers0493o1.timingEvents0493o3[index], 0),
        "0493o3 record timing event");
}

double elapsed_local_support_event_seconds_0493o3(int start, int stop) {
    float milliseconds = 0.0f;
    cuda_check_0297(cudaEventElapsedTime(
        &milliseconds,
        g_localSupportSplitBuffers0493o1.timingEvents0493o3[start],
        g_localSupportSplitBuffers0493o1.timingEvents0493o3[stop]),
        "0493o3 elapsed timing event");
    return 1.0e-3 * static_cast<double>(milliseconds);
}

__device__ bool candidate_precedes_0493o1(
    double ma, unsigned long long ta,
    double mb, unsigned long long tb) {
    return ma > mb || (ma == mb && ta < tb);
}

__device__ void insert_candidate_sorted_0493o1(
    double m,
    unsigned long long token,
    double* masses,
    unsigned long long* tokens,
    unsigned int& count,
    int capacity) {
    if (!(m > 0.0) || !isfinite(m) || capacity <= 0) return;
    unsigned int n = count;
    if (n > static_cast<unsigned int>(capacity)) n = static_cast<unsigned int>(capacity);
    unsigned int pos = 0u;
    while (pos < n && !candidate_precedes_0493o1(m, token, masses[pos], tokens[pos])) ++pos;
    if (pos >= static_cast<unsigned int>(capacity)) return;
    const unsigned int newCount = n < static_cast<unsigned int>(capacity) ? n + 1u : n;
    if (newCount > 0u) {
        for (unsigned int j = newCount - 1u; j > pos; --j) {
            masses[j] = masses[j - 1u];
            tokens[j] = tokens[j - 1u];
        }
    }
    masses[pos] = m;
    tokens[pos] = token;
    count = newCount;
}

__global__ void reset_local_support_detection_0493o3(
    int denseSize,
    LocalSupportSplitDeviceView0493o1 b) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k < denseSize) {
        b.dPoor[k] = 0u;
        b.dNeff[k] = 0.0;
        b.dDeficit[k] = 0.0;
        b.dS2After[k] = 0.0;
    }
    if (k == 0) {
        for (int j = 0; j < 16; ++j) b.dStats[j] = 0ull;
        b.dMinima[0] = 1.0e300;
        b.dMinima[1] = 1.0e300;
    }
}

__global__ void reset_local_support_plan_0493o3(
    int denseSize,
    int maxSplits,
    LocalSupportSplitDeviceView0493o1 b) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    if (k >= denseSize) return;
    b.dProcessed[k] = 0u;
    b.dTargetReached[k] = 0u;
    b.dCellCapLimited[k] = 0u;
    b.dStepCapLimited[k] = 0u;
    b.dPoolLimited[k] = 0u;
    b.dSafetyLimited[k] = 0u;
    b.dRequested[k] = 0u;
    b.dGranted[k] = 0u;
    b.dApplied[k] = 0u;
    b.dSlotOffset[k] = 0u;
    b.dPairOffset[k] = 0u;
    b.dPairCursor[k] = 0u;
    b.dCandidateCount[k] = 0u;
    const std::size_t pb = static_cast<std::size_t>(k) * static_cast<std::size_t>(maxSplits);
    for (int j = 0; j < maxSplits; ++j) {
        b.dPlanParentToken[pb + static_cast<std::size_t>(j)] = ~0ull;
    }
}

__global__ void classify_local_support_pairs_0493o1(
    CudaSpeciesCellDeviceView0490h species,
    const float* __restrict__ chiField,
    DevicePopulationGuardConfig0297 cfg,
    LocalSupportSplitDeviceView0493o1 b) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    const int denseSize = species.numCells * species.speciesCount;
    if (k >= denseSize) return;
    const int s = k / species.numCells;
    const int c = k - s * species.numCells;
    if (species.resamplingEnabled == nullptr || species.resamplingEnabled[s] == 0u) return;
    if (!cell_center_inside_active_domain_0297(c, cfg)) return;
    if (!chi_allows_resampling_0297(c, chiField, cfg)) return;
    const unsigned int n = species.count[k];
    if (n == 0u) {
        atomicAdd(&b.dStats[1], 1ull);
        return;
    }
    const double m = species.mass[k];
    const double s2 = species.massSquared[k];
    if (!(m > 0.0) || !(s2 > 0.0) || !isfinite(m) || !isfinite(s2)) return;
    const double neff = (m * m) / s2;
    if (!(neff > 0.0) || !isfinite(neff)) return;
    b.dNeff[k] = neff;
    b.dDeficit[k] = fmax(0.0, static_cast<double>(cfg.nTarget) - neff);
    b.dS2After[k] = s2;
    if (cfg.nMin > 0 && m * m < static_cast<double>(cfg.nMin) * s2) {
        b.dPoor[k] = 1u;
        atomic_min_double_positive_0307(&b.dMinima[0], neff);
        atomicAdd(&b.dStats[0], 1ull);
    }
}

__global__ void compute_local_support_pair_offsets_0493o1(
    int denseSize,
    int particleCount,
    CudaSpeciesCellDeviceView0490h species,
    LocalSupportSplitDeviceView0493o1 b) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    unsigned long long total = 0ull;
    for (int k = 0; k < denseSize; ++k) {
        b.dPairOffset[k] = static_cast<unsigned int>(total);
        b.dPairCursor[k] = 0u;
        if (b.dPoor[k] == 0u) continue;
        total += static_cast<unsigned long long>(species.count[k]);
        if (total > static_cast<unsigned long long>(particleCount) || total > 0xffffffffull) {
            b.dSafetyLimited[k] = 1u;
            total = static_cast<unsigned long long>(particleCount);
            break;
        }
    }
}

__global__ void scatter_local_support_particle_indices_0493o1(
    int nParticles,
    const int* __restrict__ cellId,
    const unsigned int* __restrict__ type,
    const unsigned char* __restrict__ role,
    CudaSpeciesCellDeviceView0490h species,
    LocalSupportSplitDeviceView0493o1 b) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= nParticles) return;
    if (role[i] != static_cast<unsigned char>(kParticleRoleFluid)) return;
    const int c = cellId[i];
    if (c < 0 || c >= species.numCells) return;
    const int s = species_index_0490f(type[i], species.speciesTypes, species.speciesCount);
    if (s < 0 || species.resamplingEnabled[s] == 0u) return;
    const int k = s * species.numCells + c;
    if (b.dPoor[k] == 0u) return;
    const unsigned int local = atomicAdd(&b.dPairCursor[k], 1u);
    const unsigned int expected = species.count[k];
    if (local >= expected) {
        b.dSafetyLimited[k] = 1u;
        return;
    }
    b.dParticleIndex[static_cast<std::size_t>(b.dPairOffset[k]) + local] =
        static_cast<unsigned int>(i);
}

__global__ void select_local_support_candidates_0493o1(
    const double* __restrict__ mass,
    CudaSpeciesCellDeviceView0490h species,
    int candidateStride,
    LocalSupportSplitDeviceView0493o1 b) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    const int denseSize = species.numCells * species.speciesCount;
    if (k >= denseSize || b.dPoor[k] == 0u) return;
    const std::size_t cb = static_cast<std::size_t>(k) * static_cast<std::size_t>(candidateStride);
    for (int j = 0; j < candidateStride; ++j) {
        b.dCandidateMass[cb + static_cast<std::size_t>(j)] = 0.0;
        b.dCandidateToken[cb + static_cast<std::size_t>(j)] = ~0ull;
    }
    const unsigned int expected = species.count[k];
    const unsigned int actual = b.dPairCursor[k];
    if (actual != expected) {
        b.dSafetyLimited[k] = 1u;
        atomicAdd(&b.dStats[12], 1ull);
    }
    const unsigned int count = actual < expected ? actual : expected;
    unsigned int selected = 0u;
    const std::size_t offset = static_cast<std::size_t>(b.dPairOffset[k]);
    for (unsigned int j = 0u; j < count; ++j) {
        const unsigned int i = b.dParticleIndex[offset + j];
        const double mi = mass[i];
        if (!(mi > 0.0) || !isfinite(mi)) continue;
        insert_candidate_sorted_0493o1(
            mi, static_cast<unsigned long long>(i),
            b.dCandidateMass + cb, b.dCandidateToken + cb,
            selected, candidateStride);
    }
    b.dCandidateCount[k] = selected;
}

__global__ void plan_local_support_splits_0493o1(
    CudaSpeciesCellDeviceView0490h species,
    DevicePopulationGuardConfig0297 cfg,
    int maxSplits,
    int candidateStride,
    LocalSupportSplitDeviceView0493o1 b) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    const int denseSize = species.numCells * species.speciesCount;
    if (k >= denseSize || b.dPoor[k] == 0u) return;
    unsigned int heapCount = b.dCandidateCount[k];
    if (heapCount == 0u) {
        atomicAdd(&b.dStats[10], 1ull);
        b.dSafetyLimited[k] = 1u;
        return;
    }
    if (heapCount > static_cast<unsigned int>(candidateStride)) {
        heapCount = static_cast<unsigned int>(candidateStride);
    }
    const double totalMass = species.mass[k];
    double s2 = species.massSquared[k];
    const double targetLeft = totalMass * totalMass;
    const double targetMultiplier = static_cast<double>(cfg.nTarget);
    const int c = k % species.numCells;
    const bool solidAdjacent = population_guard_solid_adjacent_0307(c, cfg);
    const std::size_t cb = static_cast<std::size_t>(k) * static_cast<std::size_t>(candidateStride);
    const std::size_t pb = static_cast<std::size_t>(k) * static_cast<std::size_t>(maxSplits);
    unsigned int splits = 0u;
    while (targetLeft < targetMultiplier * s2 && splits < static_cast<unsigned int>(maxSplits)) {
        const double md = b.dCandidateMass[cb];
        const unsigned long long parentToken = b.dCandidateToken[cb];
        if (!(md > 0.0) || !isfinite(md) || parentToken == ~0ull) {
            b.dSafetyLimited[k] = 1u;
            break;
        }
        if (cfg.splitSafety0307) {
            double donorMin = cfg.splitDonorMinMass0307;
            if (solidAdjacent && cfg.solidAdjacentSplitMode0307 == 2) {
                b.dSafetyLimited[k] = 1u;
                break;
            }
            if (solidAdjacent && cfg.solidAdjacentSplitMode0307 == 1) {
                donorMin = fmax(donorMin, cfg.solidAdjacentDonorMinMass0307);
            }
            if (donorMin > 0.0 && md < donorMin) {
                b.dSafetyLimited[k] = 1u;
                break;
            }
        }
        const double half = 0.5 * md;
        const double floorMass = fmax(
            cfg.minDonorMassAfterSplit,
            cfg.splitSafety0307 ? cfg.splitNewParticleMinMass0307 : 0.0);
        if (!(half > 0.0) || !isfinite(half) || half < floorMass) {
            b.dSafetyLimited[k] = 1u;
            break;
        }
        b.dPlanParentToken[pb + static_cast<std::size_t>(splits)] = parentToken;
        s2 -= 0.5 * md * md;
        b.dCandidateMass[cb] = half;
        unsigned int n = heapCount;
        // Restore ordering for the retained parent half.
        unsigned int pos = 0u;
        while (pos + 1u < n && candidate_precedes_0493o1(
                   b.dCandidateMass[cb + pos + 1u], b.dCandidateToken[cb + pos + 1u],
                   b.dCandidateMass[cb + pos], b.dCandidateToken[cb + pos])) {
            const double tm = b.dCandidateMass[cb + pos];
            const unsigned long long tt = b.dCandidateToken[cb + pos];
            b.dCandidateMass[cb + pos] = b.dCandidateMass[cb + pos + 1u];
            b.dCandidateToken[cb + pos] = b.dCandidateToken[cb + pos + 1u];
            b.dCandidateMass[cb + pos + 1u] = tm;
            b.dCandidateToken[cb + pos + 1u] = tt;
            ++pos;
        }
        const unsigned long long childToken =
            kSyntheticTokenMask0493o1 | static_cast<unsigned long long>(splits);
        insert_candidate_sorted_0493o1(
            half, childToken, b.dCandidateMass + cb, b.dCandidateToken + cb,
            n, candidateStride);
        heapCount = n;
        ++splits;
    }
    b.dRequested[k] = splits;
    b.dS2After[k] = s2;
    b.dTargetReached[k] = targetLeft >= targetMultiplier * s2 ? 1u : 0u;
    if (b.dTargetReached[k] == 0u && splits >= static_cast<unsigned int>(maxSplits)) {
        b.dCellCapLimited[k] = 1u;
    }
    if (b.dSafetyLimited[k] != 0u) atomicAdd(&b.dStats[11], 1ull);
}

__global__ void allocate_local_support_budget_0493o1(
    int denseSize,
    unsigned long long availableSlots,
    unsigned long long maxSplitsPerStep,
    LocalSupportSplitDeviceView0493o1 b) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;

    // Nominal path: one linear pass, no sort and no quadratic work.  The
    // priority rule is relevant only when the global step cap or inactive pool
    // cannot satisfy the complete plan.
    unsigned long long totalRequested = 0ull;
    for (int k = 0; k < denseSize; ++k) {
        totalRequested += static_cast<unsigned long long>(b.dRequested[k]);
    }
    const unsigned long long totalBudget =
        availableSlots < maxSplitsPerStep ? availableSlots : maxSplitsPerStep;
    if (totalRequested <= totalBudget) {
        unsigned long long used = 0ull;
        for (int k = 0; k < denseSize; ++k) {
            const unsigned int req = b.dRequested[k];
            if (req == 0u) continue;
            b.dProcessed[k] = 1u;
            b.dSlotOffset[k] = static_cast<unsigned int>(used);
            b.dGranted[k] = req;
            used += static_cast<unsigned long long>(req);
        }
        return;
    }

    // Contention path: deterministic severity ordering.  It is deliberately
    // serial because this branch denotes a pathological resource shortage and
    // must remain simple and reproducible; the normal path above is O(dense).
    unsigned long long used = 0ull;
    for (;;) {
        int best = -1;
        double bestNeff = 0.0;
        double bestDeficit = 0.0;
        for (int k = 0; k < denseSize; ++k) {
            if (b.dPoor[k] == 0u || b.dProcessed[k] != 0u || b.dRequested[k] == 0u) continue;
            const double neff = b.dNeff[k];
            const double deficit = b.dDeficit[k];
            if (best < 0 || neff < bestNeff ||
                (neff == bestNeff && (deficit > bestDeficit ||
                 (deficit == bestDeficit && k < best)))) {
                best = k;
                bestNeff = neff;
                bestDeficit = deficit;
            }
        }
        if (best < 0) break;
        b.dProcessed[best] = 1u;
        const unsigned long long req = static_cast<unsigned long long>(b.dRequested[best]);
        const unsigned long long stepRemaining =
            used < maxSplitsPerStep ? maxSplitsPerStep - used : 0ull;
        const unsigned long long poolRemaining =
            used < availableSlots ? availableSlots - used : 0ull;
        unsigned long long grant64 = req;
        if (grant64 > stepRemaining) grant64 = stepRemaining;
        if (grant64 > poolRemaining) grant64 = poolRemaining;
        b.dSlotOffset[best] = static_cast<unsigned int>(used);
        b.dGranted[best] = static_cast<unsigned int>(grant64);
        if (grant64 < req) {
            if (stepRemaining < req) b.dStepCapLimited[best] = 1u;
            if (poolRemaining < req) b.dPoolLimited[best] = 1u;
        }
        used += grant64;
    }
}
__device__ unsigned int resolve_parent_slot_0493o1(
    unsigned long long token,
    unsigned long long activeBase,
    unsigned int pairSlotOffset) {
    if ((token & kSyntheticTokenMask0493o1) == 0ull) {
        return static_cast<unsigned int>(token);
    }
    const unsigned long long childOrdinal = token & kSyntheticTokenIndexMask0493o1;
    return static_cast<unsigned int>(activeBase +
        static_cast<unsigned long long>(pairSlotOffset) + childOrdinal);
}

__global__ void apply_local_support_plan_0493o1(
    CudaSpeciesCellDeviceView0490h species,
    DevicePopulationGuardConfig0297 cfg,
    int maxSplits,
    double* __restrict__ x,
    double* __restrict__ y,
    double* __restrict__ vx,
    double* __restrict__ vy,
    double* __restrict__ mass,
    unsigned int* __restrict__ type,
    unsigned char* __restrict__ role,
    unsigned long long* __restrict__ legacyCounters,
    LocalSupportSplitDeviceView0493o1 b) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    const int denseSize = species.numCells * species.speciesCount;
    if (k >= denseSize || b.dPoor[k] == 0u) return;
    const unsigned int grant = b.dGranted[k];
    if (grant == 0u) return;
    const int s = k / species.numCells;
    const int c = k - s * species.numCells;
    const unsigned int expectedType = species.speciesTypes[s];
    const std::size_t pb = static_cast<std::size_t>(k) * static_cast<std::size_t>(maxSplits);
    const unsigned int pairOffset = b.dSlotOffset[k];
    double s2 = species.massSquared[k];
    unsigned int applied = 0u;
    for (unsigned int j = 0u; j < grant; ++j) {
        const unsigned long long token = b.dPlanParentToken[pb + static_cast<std::size_t>(j)];
        if (token == ~0ull) break;
        const unsigned int donor = resolve_parent_slot_0493o1(token, cfg.activeBase0315, pairOffset);
        const unsigned long long slot64 = cfg.activeBase0315 +
            static_cast<unsigned long long>(pairOffset) + static_cast<unsigned long long>(j);
        if (slot64 >= cfg.activeBase0315 + cfg.activeCapacity0315 ||
            slot64 > 0xffffffffull) break;
        const unsigned int slot = static_cast<unsigned int>(slot64);
        if (donor == slot || role[donor] != static_cast<unsigned char>(kParticleRoleFluid) ||
            role[slot] != static_cast<unsigned char>(kParticleRoleInactive) ||
            type[donor] != expectedType) break;
        const double md = mass[donor];
        const double half = 0.5 * md;
        if (!(md > 0.0) || !(half > 0.0) || !isfinite(md) || !isfinite(half)) break;
        if (cfg.splitSafety0307) {
            double donorMin = cfg.splitDonorMinMass0307;
            const bool solidAdjacent = population_guard_solid_adjacent_0307(c, cfg);
            if (solidAdjacent && cfg.solidAdjacentSplitMode0307 == 2) break;
            if (solidAdjacent && cfg.solidAdjacentSplitMode0307 == 1) {
                donorMin = fmax(donorMin, cfg.solidAdjacentDonorMinMass0307);
            }
            if ((donorMin > 0.0 && md < donorMin) ||
                (cfg.splitNewParticleMinMass0307 > 0.0 && half < cfg.splitNewParticleMinMass0307)) break;
        }
        if (half < cfg.minDonorMassAfterSplit) break;
        const int ix = c % cfg.nx;
        const int iy = c / cfg.nx;
        const double xmin = static_cast<double>(ix) * cfg.dx;
        const double xmax = xmin + cfg.dx;
        const double ymin = static_cast<double>(iy) * cfg.dy;
        const double ymax = ymin + cfg.dy;
        const unsigned int pattern = static_cast<unsigned int>(k) * 2654435761u + j;
        const double epsx = 0.0625 * cfg.dx;
        const double epsy = 0.0625 * cfg.dy;
        double xn = clamp_0297(
            x[donor] + ((pattern & 1u) ? epsx : -epsx),
            xmin + 1.0e-12 * cfg.dx, xmax - 1.0e-12 * cfg.dx);
        double yn = clamp_0297(
            y[donor] + ((pattern & 2u) ? epsy : -epsy),
            ymin + 1.0e-12 * cfg.dy, ymax - 1.0e-12 * cfg.dy);
        if (!point_inside_active_domain_0297(xn, yn, cfg)) {
            xn = x[donor];
            yn = y[donor];
        }
        // Equal masses and identical velocities conserve M, P and kinetic energy
        // exactly up to roundoff.  No cell-level thermal correction is needed.
        mass[donor] = half;
        x[slot] = xn;
        y[slot] = yn;
        vx[slot] = vx[donor];
        vy[slot] = vy[donor];
        mass[slot] = half;
        type[slot] = expectedType;
        role[slot] = static_cast<unsigned char>(kParticleRoleFluid);
        s2 -= 0.5 * md * md;
        ++applied;
        atomicAdd(&legacyCounters[1], 1ull);
    }
    b.dApplied[k] = applied;
    b.dS2After[k] = s2;
}

__global__ void finalize_local_support_diagnostics_0493o1(
    CudaSpeciesCellDeviceView0490h species,
    DevicePopulationGuardConfig0297 cfg,
    LocalSupportSplitDeviceView0493o1 b) {
    const int k = blockIdx.x * blockDim.x + threadIdx.x;
    const int denseSize = species.numCells * species.speciesCount;
    if (k >= denseSize || b.dPoor[k] == 0u) return;
    const unsigned int req = b.dRequested[k];
    const unsigned int grant = b.dGranted[k];
    const unsigned int applied = b.dApplied[k];
    atomicAdd(&b.dStats[2], static_cast<unsigned long long>(req));
    atomicAdd(&b.dStats[3], static_cast<unsigned long long>(applied));
    atomicMax(&b.dStats[13], static_cast<unsigned long long>(applied));
    const double m = species.mass[k];
    const double s2 = b.dS2After[k];
    double neffAfter = 0.0;
    if (m > 0.0 && s2 > 0.0 && isfinite(m) && isfinite(s2)) {
        neffAfter = (m * m) / s2;
        if (neffAfter > 0.0 && isfinite(neffAfter)) {
            atomic_min_double_positive_0307(&b.dMinima[1], neffAfter);
        }
    }
    const bool reached = neffAfter >= static_cast<double>(cfg.nTarget);
    if (reached && applied == grant && grant == req) {
        atomicAdd(&b.dStats[4], 1ull);
    } else {
        atomicAdd(&b.dStats[5], 1ull);
        unsigned long long missing = 0ull;
        if (req > applied) missing += static_cast<unsigned long long>(req - applied);
        if (!reached && missing == 0ull) missing = 1ull; // lower bound when the cell cap stopped planning.
        atomicAdd(&b.dStats[6], missing);
    }
    if (b.dCellCapLimited[k] != 0u) atomicAdd(&b.dStats[7], 1ull);
    if (b.dStepCapLimited[k] != 0u) atomicAdd(&b.dStats[8], 1ull);
    if (b.dPoolLimited[k] != 0u) atomicAdd(&b.dStats[9], 1ull);
}

LocalSupportSplitResult0493o1 detect_local_support_pairs_0493o3(
    int particleCount,
    int block,
    CudaSpeciesCellDeviceView0490h species,
    const float* dChi,
    DevicePopulationGuardConfig0297 cfg) {
    if (!cfg.localSupportSplitOnly0493o1) return {};
    if (!cfg.activePrefixSafe0315) {
        throw std::runtime_error("0493o1 currently requires the active-prefix-safe CUDA carrier");
    }
    if (species.numCells != cfg.numCells || species.speciesCount <= 0 ||
        species.speciesTypes == nullptr || species.resamplingEnabled == nullptr ||
        species.count == nullptr || species.mass == nullptr || species.massSquared == nullptr) {
        throw std::runtime_error("0493o1 requires a complete resident species-cell deposit including massSquared");
    }
    if (cfg.nMin <= 0 || cfg.nTarget <= cfg.nMin || cfg.maxSplitsPerCell0493o1 <= 0 ||
        cfg.maxSplitsPerStep0493o1 <= 0) {
        throw std::runtime_error("0493o1 requires NMin>0, NTarget>NMin and positive split caps");
    }
    const int denseSize = species.numCells * species.speciesCount;
    const int maxSplits = cfg.maxSplitsPerCell0493o1;
    g_localSupportSplitBuffers0493o1.ensure(denseSize, maxSplits, particleCount);
    const LocalSupportSplitDeviceView0493o1 b = g_localSupportSplitBuffers0493o1.device_view();
    const int denseGrid = std::max(1, (denseSize + block - 1) / block);

    record_local_support_event_0493o3(ResetStart0493o3);
    reset_local_support_detection_0493o3<<<denseGrid, block>>>(denseSize, b);
    cuda_check_0297(cudaGetLastError(), "launch reset_local_support_detection_0493o3");
    record_local_support_event_0493o3(ResetStop0493o3);
    classify_local_support_pairs_0493o1<<<denseGrid, block>>>(species, dChi, cfg, b);
    cuda_check_0297(cudaGetLastError(), "launch classify_local_support_pairs_0493o1");
    record_local_support_event_0493o3(ClassifyStop0493o3);

    unsigned long long detectionStats[2] = {0ull, 0ull};
    double minNeffBefore = 1.0e300;
    const Clock::time_point td0 = Clock::now();
    cuda_check_0297(cudaMemcpy(
        detectionStats, b.dStats, sizeof(detectionStats), cudaMemcpyDeviceToHost),
        "copy 0493o3 poor/empty counters D2H");
    cuda_check_0297(cudaMemcpy(
        &minNeffBefore, b.dMinima, sizeof(double), cudaMemcpyDeviceToHost),
        "copy 0493o3 minimum Neff D2H");
    const Clock::time_point td1 = Clock::now();

    LocalSupportSplitResult0493o1 out{};
    out.poorNonEmptyPairs = detectionStats[0];
    out.emptySpeciesPairs = detectionStats[1];
    out.minNeffBefore = minNeffBefore < 1.0e299 ? minNeffBefore : 0.0;
    out.noPoorEarlyExit0493o3 = out.poorNonEmptyPairs == 0u;
    out.resetSeconds0493o3 = elapsed_local_support_event_seconds_0493o3(
        ResetStart0493o3, ResetStop0493o3);
    out.classifySeconds0493o3 = elapsed_local_support_event_seconds_0493o3(
        ResetStop0493o3, ClassifyStop0493o3);
    out.poorCountDownloadSeconds0493o3 = seconds_between(td0, td1);
    return out;
}

LocalSupportSplitResult0493o1 apply_local_support_split_only_0493o1(
    int particleCount,
    int particleGrid,
    int block,
    const CudaParticleDeviceView& pv,
    const CudaCellWorkspaceDeviceView& cv,
    CudaSpeciesCellDeviceView0490h species,
    const float* dChi,
    DevicePopulationGuardConfig0297 cfg,
    unsigned long long* legacyCounters,
    const LocalSupportSplitResult0493o1& detected0493o3) {
    if (!cfg.localSupportSplitOnly0493o1) return {};
    LocalSupportSplitResult0493o1 out = detected0493o3;
    if (out.poorNonEmptyPairs == 0u) {
        out.noPoorEarlyExit0493o3 = true;
        return out;
    }

    const int denseSize = species.numCells * species.speciesCount;
    const int maxSplits = cfg.maxSplitsPerCell0493o1;
    const int candidateStride = maxSplits + 1;
    const LocalSupportSplitDeviceView0493o1 b = g_localSupportSplitBuffers0493o1.device_view();
    const int denseGrid = std::max(1, (denseSize + block - 1) / block);

    record_local_support_event_0493o3(CandidateStart0493o3);
    reset_local_support_plan_0493o3<<<denseGrid, block>>>(denseSize, maxSplits, b);
    cuda_check_0297(cudaGetLastError(), "launch reset_local_support_plan_0493o3");
    compute_local_support_pair_offsets_0493o1<<<1, 1>>>(
        denseSize, particleCount, species, b);
    cuda_check_0297(cudaGetLastError(), "launch compute_local_support_pair_offsets_0493o1");
    if (particleCount > 0) {
        scatter_local_support_particle_indices_0493o1<<<particleGrid, block>>>(
            particleCount, cv.cellId, pv.type, pv.role, species, b);
        cuda_check_0297(cudaGetLastError(), "launch scatter_local_support_particle_indices_0493o1");
    }
    select_local_support_candidates_0493o1<<<denseGrid, block>>>(
        pv.mass, species, candidateStride, b);
    cuda_check_0297(cudaGetLastError(), "launch select_local_support_candidates_0493o1");
    record_local_support_event_0493o3(CandidateStop0493o3);

    record_local_support_event_0493o3(PlanStart0493o3);
    plan_local_support_splits_0493o1<<<denseGrid, block>>>(
        species, cfg, maxSplits, candidateStride, b);
    cuda_check_0297(cudaGetLastError(), "launch plan_local_support_splits_0493o1");
    allocate_local_support_budget_0493o1<<<1, 1>>>(
        denseSize, cfg.activeCapacity0315,
        static_cast<unsigned long long>(cfg.maxSplitsPerStep0493o1), b);
    cuda_check_0297(cudaGetLastError(), "launch allocate_local_support_budget_0493o1");
    record_local_support_event_0493o3(PlanStop0493o3);

    record_local_support_event_0493o3(ApplyStart0493o3);
    apply_local_support_plan_0493o1<<<denseGrid, block>>>(
        species, cfg, maxSplits,
        pv.x, pv.y, pv.vx, pv.vy, pv.mass, pv.type, pv.role,
        legacyCounters, b);
    cuda_check_0297(cudaGetLastError(), "launch apply_local_support_plan_0493o1");
    record_local_support_event_0493o3(ApplyStop0493o3);

    record_local_support_event_0493o3(DiagnosticsStart0493o3);
    finalize_local_support_diagnostics_0493o1<<<denseGrid, block>>>(species, cfg, b);
    cuda_check_0297(cudaGetLastError(), "launch finalize_local_support_diagnostics_0493o1");
    record_local_support_event_0493o3(DiagnosticsStop0493o3);

    unsigned long long stats[16] = {};
    double minima[2] = {1.0e300, 1.0e300};
    const Clock::time_point td0 = Clock::now();
    cuda_check_0297(cudaMemcpy(stats, b.dStats, sizeof(stats), cudaMemcpyDeviceToHost),
                    "copy 0493o1 stats D2H");
    cuda_check_0297(cudaMemcpy(minima, b.dMinima, sizeof(minima), cudaMemcpyDeviceToHost),
                    "copy 0493o1 minima D2H");
    const Clock::time_point td1 = Clock::now();

    out.poorNonEmptyPairs = stats[0];
    out.emptySpeciesPairs = stats[1];
    out.requestedSplits = stats[2];
    out.appliedSplits = stats[3];
    out.repairedToTarget = stats[4];
    out.incompleteRepairCells = stats[5];
    out.missingSplitsToTarget = stats[6];
    out.limitedByCellCap = stats[7];
    out.limitedByStepCap = stats[8];
    out.limitedByPool = stats[9];
    out.noCandidatePairs = stats[10];
    out.safetyLimitedPairs = stats[11];
    out.candidateCountMismatchPairs = stats[12];
    out.maxSplitsPerPair = stats[13];
    out.minNeffBefore = minima[0] < 1.0e299 ? minima[0] : 0.0;
    out.minNeffAfter = minima[1] < 1.0e299 ? minima[1] : 0.0;
    out.noPoorEarlyExit0493o3 = false;
    out.candidateBuildSeconds0493o3 = elapsed_local_support_event_seconds_0493o3(
        CandidateStart0493o3, CandidateStop0493o3);
    out.planSeconds0493o3 = elapsed_local_support_event_seconds_0493o3(
        PlanStart0493o3, PlanStop0493o3);
    out.applySeconds0493o3 = elapsed_local_support_event_seconds_0493o3(
        ApplyStart0493o3, ApplyStop0493o3);
    out.diagnosticsSeconds0493o3 = elapsed_local_support_event_seconds_0493o3(
        DiagnosticsStart0493o3, DiagnosticsStop0493o3) + seconds_between(td0, td1);
    return out;
}
