#include "runtime_summary.h"

#include <cmath>
#include <iomanip>
#include <limits>
#include <stdexcept>

namespace mpcd {

RuntimeSummary compute_runtime_summary(const ParticleState& state,
                                       const SimulationParams& params,
                                       int step,
                                       double wallTime,
                                       const std::vector<std::uint32_t>* cellCount,
                                       const BoundaryDiagnostics* boundary) {
    validate_particle_state(state, "compute_runtime_summary");
    RuntimeSummary s{};
    s.step = step;
    s.time = static_cast<double>(step) * params.dt;
    s.wallTime = wallTime;
    s.Np = state.Np;

    const std::size_t n = static_cast<std::size_t>(state.Np);
    double mass = 0.0;
    double px = 0.0;
    double py = 0.0;
    double kinetic = 0.0;

    #pragma omp parallel for reduction(+:mass,px,py,kinetic) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const double m = state.mass[i];
        mass += m;
        px += m * state.vx[i];
        py += m * state.vy[i];
        kinetic += 0.5 * m * (state.vx[i] * state.vx[i] + state.vy[i] * state.vy[i]);
    }

    s.totalMass = mass;
    s.Px = px;
    s.Py = py;
    if (mass > 0.0) {
        s.meanVx = px / mass;
        s.meanVy = py / mass;
    }
    if (n > 0u) {
        s.meanKinetic = kinetic / static_cast<double>(n);
    }

    double thermal = 0.0;
    #pragma omp parallel for reduction(+:thermal) if(n > 10000)
    for (std::int64_t ii = 0; ii < static_cast<std::int64_t>(n); ++ii) {
        const std::size_t i = static_cast<std::size_t>(ii);
        const double dvx = state.vx[i] - s.meanVx;
        const double dvy = state.vy[i] - s.meanVy;
        thermal += state.mass[i] * (dvx * dvx + dvy * dvy);
    }
    if (n > 0u) {
        s.kBTEstimate = thermal / (2.0 * static_cast<double>(n));
    }

    if (boundary != nullptr) {
        s.hitsLeft = boundary->hitsLeft;
        s.hitsRight = boundary->hitsRight;
        s.hitsBottom = boundary->hitsBottom;
        s.hitsTop = boundary->hitsTop;
    }

    if (cellCount != nullptr && !cellCount->empty()) {
        const auto& count = *cellCount;
        const std::size_t nc = count.size();
        double sum = 0.0;
        double sum2 = 0.0;
        std::uint32_t minN = std::numeric_limits<std::uint32_t>::max();
        std::uint32_t maxN = 0u;
        for (const std::uint32_t c : count) {
            const double d = static_cast<double>(c);
            sum += d;
            sum2 += d * d;
            if (c < minN) minN = c;
            if (c > maxN) maxN = c;
        }
        if (nc > 0u) {
            s.meanN = sum / static_cast<double>(nc);
            const double var = sum2 / static_cast<double>(nc) - s.meanN * s.meanN;
            s.stdN = std::sqrt(var > 0.0 ? var : 0.0);
            s.minN = minN;
            s.maxN = maxN;
        }
    } else {
        const double nc = static_cast<double>(params.Nx * params.Ny);
        s.meanN = nc > 0.0 ? static_cast<double>(n) / nc : 0.0;
        s.stdN = 0.0;
        s.minN = 0u;
        s.maxN = 0u;
    }

    return s;
}

RuntimeSummaryWriter::RuntimeSummaryWriter(const std::string& filepath) : out_(filepath) {
    if (!out_) {
        throw std::runtime_error("Cannot open runtime summary file for writing: " + filepath);
    }
    out_ << "step,time,wallTime,Np,totalMass,Px,Py,meanVx,meanVy,meanKinetic,kBTEstimate,meanN,stdN,minN,maxN,hitsLeft,hitsRight,hitsBottom,hitsTop\n";
}

void RuntimeSummaryWriter::append(const RuntimeSummary& s) {
    if (!out_) {
        throw std::runtime_error("Runtime summary file is not writable");
    }
    out_ << s.step << ','
         << std::setprecision(17) << s.time << ','
         << s.wallTime << ','
         << s.Np << ','
         << s.totalMass << ','
         << s.Px << ','
         << s.Py << ','
         << s.meanVx << ','
         << s.meanVy << ','
         << s.meanKinetic << ','
         << s.kBTEstimate << ','
         << s.meanN << ','
         << s.stdN << ','
         << s.minN << ','
         << s.maxN << ','
         << s.hitsLeft << ','
         << s.hitsRight << ','
         << s.hitsBottom << ','
         << s.hitsTop << '\n';
}

} // namespace mpcd
