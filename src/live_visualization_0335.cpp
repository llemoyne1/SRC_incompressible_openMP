#include "live_visualization_0335.h"

#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

namespace {

bool env_truthy_0335(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return false;
    const std::string s(v);
    return !(s == "0" || s == "false" || s == "FALSE" ||
             s == "off" || s == "OFF" || s == "no" || s == "NO");
}

} // namespace

#ifndef MPCD_ENABLE_LIVE_VIS

namespace mpcd {

struct LiveVisualization0335::Impl {
    bool requested = false;
};

LiveVisualization0335::LiveVisualization0335() : impl_(std::make_unique<Impl>()) {}
LiveVisualization0335::~LiveVisualization0335() = default;

void LiveVisualization0335::maybe_initialize(const SimulationParams&) {
    impl_->requested = env_truthy_0335("SRC_LIVE_VIS_ENABLE") ||
                       env_truthy_0335("MPCD_LIVE_VIS_ENABLE");
    if (impl_->requested) {
        std::cerr << "[livevis0335] requested but this binary was built without "
                  << "MPCD_ENABLE_LIVE_VIS=1; continuing without live visualization\n";
    }
}

bool LiveVisualization0335::enabled() const { return false; }

bool LiveVisualization0335::should_draw(std::uint64_t, std::uint64_t) const { return false; }

void LiveVisualization0335::update(const ParticleState&, const SimulationParams&, std::uint64_t, double) {}
void LiveVisualization0335::draw_rgba_frame(const SimulationParams&, std::uint64_t, double,
                                            const std::vector<unsigned char>&, int, int,
                                            const std::string&) {}

} // namespace mpcd

#else

#include "particle_state.h"
#include "src_mpcd_base.h"

#include <GLFW/glfw3.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <limits>
#include <sstream>
#include <vector>

namespace {

int env_int_0335(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try { return std::stoi(v); } catch (...) { return fallback; }
}

double env_double_0335(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try { return std::stod(v); } catch (...) { return fallback; }
}

std::string env_string_0335(const char* name, const std::string& fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return std::string(v);
}

unsigned char clamp_u8_0335(double x) {
    const int v = static_cast<int>(std::lround(std::clamp(x, 0.0, 255.0)));
    return static_cast<unsigned char>(v);
}

bool signed_field_0335(const std::string& field) {
    return field == "ux" || field == "uy" || field == "vx" || field == "vy" || field == "vorticity";
}

} // namespace

namespace mpcd {

struct LiveVisualization0335::Impl {
    bool enabled = false;
    bool glfwReady = false;
    GLFWwindow* window = nullptr;

    int nx = 300;
    int ny = 80;
    int every = 10;
    int smoothPasses = 0;
    int windowScale = 1;
    double alpha = 0.08;
    double clip = -1.0;
    double quantile = 0.995;
    double gain = 1.0;
    bool overlaySolid = true;
    std::string field = "ux";

    std::vector<double> sumUx;
    std::vector<double> sumUy;
    std::vector<double> sumMass;
    std::vector<double> scalar;
    std::vector<double> scalarTmp;
    std::vector<double> displayScalar;
    std::vector<unsigned char> rgba;

    void allocate() {
        const std::size_t n = static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny);
        sumUx.assign(n, 0.0);
        sumUy.assign(n, 0.0);
        sumMass.assign(n, 0.0);
        scalar.assign(n, 0.0);
        scalarTmp.assign(n, 0.0);
        displayScalar.assign(n, 0.0);
        rgba.assign(4u * n, 255u);
    }

    void disable(const std::string& reason) {
        if (enabled) {
            std::cerr << "[livevis0335] disabled: " << reason << '\n';
        }
        enabled = false;
    }
};

LiveVisualization0335::LiveVisualization0335() : impl_(std::make_unique<Impl>()) {}

LiveVisualization0335::~LiveVisualization0335() {
    if (impl_ && impl_->window != nullptr) {
        glfwDestroyWindow(impl_->window);
        impl_->window = nullptr;
    }
    if (impl_ && impl_->glfwReady) {
        glfwTerminate();
        impl_->glfwReady = false;
    }
}

void LiveVisualization0335::maybe_initialize(const SimulationParams& params) {
    auto& v = *impl_;
    v.enabled = env_truthy_0335("SRC_LIVE_VIS_ENABLE") || env_truthy_0335("MPCD_LIVE_VIS_ENABLE");
    if (!v.enabled) return;

    v.every = std::max(1, env_int_0335("SRC_LIVE_VIS_EVERY", env_int_0335("MPCD_LIVE_VIS_EVERY", 10)));
    // 0335c: default to a coarse rendering grid.  A 600x160 grid is too sparse
    // for gamma~20 VK runs and displays thermal shot noise rather than a mean field.
    v.nx = std::max(16, env_int_0335("SRC_LIVE_VIS_NX", env_int_0335("MPCD_LIVE_VIS_NX", 300)));
    v.ny = std::max(16, env_int_0335("SRC_LIVE_VIS_NY", env_int_0335("MPCD_LIVE_VIS_NY", 80)));
    v.field = env_string_0335("SRC_LIVE_VIS_FIELD", env_string_0335("MPCD_LIVE_VIS_FIELD", "ux"));
    v.alpha = std::clamp(env_double_0335("SRC_LIVE_VIS_ALPHA", env_double_0335("MPCD_LIVE_VIS_ALPHA", 0.08)), 0.0, 1.0);
    v.clip = env_double_0335("SRC_LIVE_VIS_CLIP", env_double_0335("MPCD_LIVE_VIS_CLIP", -1.0));
    v.quantile = std::clamp(env_double_0335("SRC_LIVE_VIS_QUANTILE", env_double_0335("MPCD_LIVE_VIS_QUANTILE", 0.995)), 0.50, 1.0);
    v.gain = std::max(1.0e-12, env_double_0335("SRC_LIVE_VIS_GAIN", env_double_0335("MPCD_LIVE_VIS_GAIN", 1.0)));
    v.smoothPasses = std::max(0, env_int_0335("SRC_LIVE_VIS_SMOOTH_PASSES", env_int_0335("MPCD_LIVE_VIS_SMOOTH_PASSES", 1)));
    v.windowScale = std::max(1, env_int_0335("SRC_LIVE_VIS_WINDOW_SCALE", env_int_0335("MPCD_LIVE_VIS_WINDOW_SCALE", 1)));
    v.overlaySolid = !env_truthy_0335("SRC_LIVE_VIS_NO_SOLID_OVERLAY") &&
                     !env_truthy_0335("MPCD_LIVE_VIS_NO_SOLID_OVERLAY");

    if (!glfwInit()) {
        v.disable("glfwInit() failed; check WSLg/OpenGL or build without live visualization");
        return;
    }
    v.glfwReady = true;

    const int width = v.nx * v.windowScale;
    const int height = v.ny * v.windowScale;
    std::ostringstream title;
    title << "SRC/MPCD live 0335a - " << v.field
          << "  " << params.Lx << " x " << params.Ly;
    v.window = glfwCreateWindow(width, height, title.str().c_str(), nullptr, nullptr);
    if (v.window == nullptr) {
        v.disable("glfwCreateWindow() failed");
        return;
    }
    glfwMakeContextCurrent(v.window);
    glfwSwapInterval(env_int_0335("SRC_LIVE_VIS_VSYNC", env_int_0335("MPCD_LIVE_VIS_VSYNC", 0)));
    v.allocate();
    std::cerr << "[livevis0335] enabled field=" << v.field
              << " grid=" << v.nx << "x" << v.ny
              << " every=" << v.every
              << " alpha=" << v.alpha
              << " clip=" << v.clip
              << " quantile=" << v.quantile
              << " gain=" << v.gain << '\n';
}

bool LiveVisualization0335::enabled() const { return impl_ && impl_->enabled; }

bool LiveVisualization0335::should_draw(std::uint64_t step, std::uint64_t finalStep) const {
    if (!enabled()) return false;
    return (step % static_cast<std::uint64_t>(impl_->every) == 0u) || step == finalStep;
}

void LiveVisualization0335::update(const ParticleState& state, const SimulationParams& params,
                                   std::uint64_t step, double time) {
    auto& v = *impl_;
    if (!v.enabled) return;
    if (v.window == nullptr || glfwWindowShouldClose(v.window)) {
        v.disable("window closed");
        return;
    }

    std::fill(v.sumUx.begin(), v.sumUx.end(), 0.0);
    std::fill(v.sumUy.begin(), v.sumUy.end(), 0.0);
    std::fill(v.sumMass.begin(), v.sumMass.end(), 0.0);
    std::fill(v.scalar.begin(), v.scalar.end(), 0.0);

    const std::size_t n = static_cast<std::size_t>(state.Np);
    const double invLx = params.Lx > 0.0 ? 1.0 / params.Lx : 1.0;
    const double invLy = params.Ly > 0.0 ? 1.0 / params.Ly : 1.0;
    for (std::size_t i = 0; i < n; ++i) {
        if (!state.role.empty() && state.role[i] != kParticleRoleFluid) continue;
        double x = state.x[i];
        double y = state.y[i];
        if (params.Lx > 0.0) {
            x -= std::floor(x * invLx) * params.Lx;
        }
        if (params.Ly > 0.0) {
            y -= std::floor(y * invLy) * params.Ly;
        }
        const int ix = std::clamp(static_cast<int>(std::floor(x * invLx * v.nx)), 0, v.nx - 1);
        const int iy = std::clamp(static_cast<int>(std::floor(y * invLy * v.ny)), 0, v.ny - 1);
        const std::size_t c = static_cast<std::size_t>(iy) * static_cast<std::size_t>(v.nx) + static_cast<std::size_t>(ix);
        const double m = state.mass.empty() ? 1.0 : state.mass[i];
        v.sumMass[c] += m;
        v.sumUx[c] += m * state.vx[i];
        v.sumUy[c] += m * state.vy[i];
    }

    for (std::size_t c = 0; c < v.scalar.size(); ++c) {
        const double m = v.sumMass[c];
        const double ux = m > 0.0 ? v.sumUx[c] / m : 0.0;
        const double uy = m > 0.0 ? v.sumUy[c] / m : 0.0;
        if (v.field == "ux" || v.field == "vx") v.scalar[c] = ux;
        else if (v.field == "uy" || v.field == "vy") v.scalar[c] = uy;
        else if (v.field == "speed") v.scalar[c] = std::sqrt(ux * ux + uy * uy);
        else if (v.field == "mass" || v.field == "density") v.scalar[c] = m;
        else v.scalar[c] = m;
    }

    if (v.field == "vorticity") {
        const double dx = params.Lx / static_cast<double>(std::max(1, v.nx));
        const double dy = params.Ly / static_cast<double>(std::max(1, v.ny));
        for (int iy = 0; iy < v.ny; ++iy) {
            const int ym = std::max(0, iy - 1);
            const int yp = std::min(v.ny - 1, iy + 1);
            for (int ix = 0; ix < v.nx; ++ix) {
                const int xm = std::max(0, ix - 1);
                const int xp = std::min(v.nx - 1, ix + 1);
                const std::size_t c = static_cast<std::size_t>(iy) * v.nx + ix;
                const std::size_t cxm = static_cast<std::size_t>(iy) * v.nx + xm;
                const std::size_t cxp = static_cast<std::size_t>(iy) * v.nx + xp;
                const std::size_t cym = static_cast<std::size_t>(ym) * v.nx + ix;
                const std::size_t cyp = static_cast<std::size_t>(yp) * v.nx + ix;
                const double m_xm = v.sumMass[cxm], m_xp = v.sumMass[cxp];
                const double m_ym = v.sumMass[cym], m_yp = v.sumMass[cyp];
                const double uy_xm = m_xm > 0.0 ? v.sumUy[cxm] / m_xm : 0.0;
                const double uy_xp = m_xp > 0.0 ? v.sumUy[cxp] / m_xp : 0.0;
                const double ux_ym = m_ym > 0.0 ? v.sumUx[cym] / m_ym : 0.0;
                const double ux_yp = m_yp > 0.0 ? v.sumUx[cyp] / m_yp : 0.0;
                v.scalar[c] = (uy_xp - uy_xm) / (static_cast<double>(xp - xm) * dx + 1e-300)
                            - (ux_yp - ux_ym) / (static_cast<double>(yp - ym) * dy + 1e-300);
            }
        }
    }

    for (int pass = 0; pass < v.smoothPasses; ++pass) {
        v.scalarTmp = v.scalar;
        for (int iy = 0; iy < v.ny; ++iy) {
            for (int ix = 0; ix < v.nx; ++ix) {
                double acc = 0.0;
                int cnt = 0;
                for (int dy = -1; dy <= 1; ++dy) {
                    const int yy = iy + dy;
                    if (yy < 0 || yy >= v.ny) continue;
                    for (int dx = -1; dx <= 1; ++dx) {
                        const int xx = ix + dx;
                        if (xx < 0 || xx >= v.nx) continue;
                        acc += v.scalarTmp[static_cast<std::size_t>(yy) * v.nx + xx];
                        ++cnt;
                    }
                }
                v.scalar[static_cast<std::size_t>(iy) * v.nx + ix] = cnt > 0 ? acc / cnt : 0.0;
            }
        }
    }

    for (std::size_t c = 0; c < v.scalar.size(); ++c) {
        v.displayScalar[c] = (v.alpha >= 1.0) ? v.scalar[c]
                           : (v.alpha * v.scalar[c] + (1.0 - v.alpha) * v.displayScalar[c]);
    }

    const bool signedField = signed_field_0335(v.field);
    std::vector<double> scaleSamples;
    scaleSamples.reserve(v.displayScalar.size());
    for (double x : v.displayScalar) {
        const double sample = signedField ? std::abs(x) : std::max(0.0, x);
        if (sample > 0.0 && std::isfinite(sample)) scaleSamples.push_back(sample);
    }
    double autoScale = 1.0;
    if (!scaleSamples.empty()) {
        const std::size_t k = std::min<std::size_t>(scaleSamples.size() - 1u,
            static_cast<std::size_t>(std::floor(v.quantile * static_cast<double>(scaleSamples.size() - 1u))));
        std::nth_element(scaleSamples.begin(), scaleSamples.begin() + static_cast<std::ptrdiff_t>(k), scaleSamples.end());
        autoScale = scaleSamples[k];
    }
    const double scale = v.clip > 0.0 ? v.clip : autoScale;
    const double denom = scale > std::numeric_limits<double>::min() ? scale : 1.0;

    for (int iy = 0; iy < v.ny; ++iy) {
        for (int ix = 0; ix < v.nx; ++ix) {
            const std::size_t c = static_cast<std::size_t>(iy) * v.nx + ix;
            unsigned char r=0, g=0, b=0;
            if (signedField) {
                const double q = std::clamp(0.5 + 0.5 * v.gain * v.displayScalar[c] / denom, 0.0, 1.0);
                r = clamp_u8_0335(255.0 * std::max(0.0, 2.0 * q - 1.0));
                b = clamp_u8_0335(255.0 * std::max(0.0, 1.0 - 2.0 * q));
                g = clamp_u8_0335(255.0 * (1.0 - std::abs(2.0 * q - 1.0)));
                r = static_cast<unsigned char>(std::max<int>(r, g));
                b = static_cast<unsigned char>(std::max<int>(b, g));
            } else {
                const double q = std::clamp(v.gain * v.displayScalar[c] / denom, 0.0, 1.0);
                r = clamp_u8_0335(255.0 * std::max(0.0, 2.0 * q - 1.0));
                g = clamp_u8_0335(255.0 * (1.0 - std::abs(2.0 * q - 1.0)));
                b = clamp_u8_0335(255.0 * std::max(0.0, 1.0 - 2.0 * q));
            }
            const std::size_t o = 4u * c;
            v.rgba[o+0] = r; v.rgba[o+1] = g; v.rgba[o+2] = b; v.rgba[o+3] = 255u;
        }
    }

    if (v.overlaySolid && params.immersedSolidEnable) {
        const double px = params.Lx / static_cast<double>(v.nx);
        const double py = params.Ly / static_cast<double>(v.ny);
        const double thickness = 1.75 * std::max(px, py);
        for (int iy = 0; iy < v.ny; ++iy) {
            const double y = (static_cast<double>(iy) + 0.5) * py;
            for (int ix = 0; ix < v.nx; ++ix) {
                const double x = (static_cast<double>(ix) + 0.5) * px;
                const double dx = x - params.immersedSolidCx;
                const double dy = y - params.immersedSolidCy;
                const double d = std::sqrt(dx*dx + dy*dy);
                if (std::abs(d - params.immersedSolidR) <= thickness) {
                    const std::size_t o = 4u * (static_cast<std::size_t>(iy) * v.nx + ix);
                    v.rgba[o+0] = 0u; v.rgba[o+1] = 0u; v.rgba[o+2] = 0u; v.rgba[o+3] = 255u;
                }
            }
        }
    }

    std::ostringstream title;
    title << "SRC/MPCD live 0335a | " << v.field
          << " | step " << step << " | scale=" << std::setprecision(3) << denom << " | t=" << std::fixed << std::setprecision(3) << time;
    glfwSetWindowTitle(v.window, title.str().c_str());

    glfwMakeContextCurrent(v.window);
    int fbw = 0, fbh = 0;
    glfwGetFramebufferSize(v.window, &fbw, &fbh);
    glViewport(0, 0, fbw, fbh);
    glClear(GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0.0, static_cast<double>(fbw), 0.0, static_cast<double>(fbh), -1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glRasterPos2i(0, 0);
    glPixelZoom(static_cast<float>(fbw) / static_cast<float>(v.nx),
                static_cast<float>(fbh) / static_cast<float>(v.ny));
    glDrawPixels(v.nx, v.ny, GL_RGBA, GL_UNSIGNED_BYTE, v.rgba.data());
    glPixelZoom(1.0f, 1.0f);

    glfwSwapBuffers(v.window);
    glfwPollEvents();
}

void LiveVisualization0335::draw_rgba_frame(const SimulationParams&, std::uint64_t step, double time,
                                            const std::vector<unsigned char>& frame,
                                            int frameNx,
                                            int frameNy,
                                            const std::string& sourceLabel) {
    auto& v = *impl_;
    if (!v.enabled) return;
    if (v.window == nullptr || glfwWindowShouldClose(v.window)) {
        v.disable("window closed");
        return;
    }
    if (frameNx <= 0 || frameNy <= 0 || frame.size() < 4u * static_cast<std::size_t>(frameNx) * static_cast<std::size_t>(frameNy)) return;
    std::ostringstream title;
    title << "SRC/MPCD live 0335a | " << v.field << " | " << sourceLabel
          << " | step " << step << " | t=" << time;
    glfwSetWindowTitle(v.window, title.str().c_str());
    glfwMakeContextCurrent(v.window);
    int fbw = 0, fbh = 0;
    glfwGetFramebufferSize(v.window, &fbw, &fbh);
    glViewport(0, 0, fbw, fbh);
    glClear(GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0.0, static_cast<double>(fbw), 0.0, static_cast<double>(fbh), -1.0, 1.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glRasterPos2i(0, 0);
    glPixelZoom(static_cast<float>(fbw) / static_cast<float>(frameNx), static_cast<float>(fbh) / static_cast<float>(frameNy));
    glDrawPixels(frameNx, frameNy, GL_RGBA, GL_UNSIGNED_BYTE, frame.data());
    glPixelZoom(1.0f, 1.0f);
    glfwSwapBuffers(v.window);
    glfwPollEvents();
}

} // namespace mpcd

#endif // MPCD_ENABLE_LIVE_VIS
