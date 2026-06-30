#include "live_visualization_0335.h"

#include <cstdlib>
#include <cctype>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <chrono>
#include <thread>

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

void LiveVisualization0335::maybe_reload_controls(std::uint64_t) {}

LiveVisualization0335RuntimeControls LiveVisualization0335::current_controls() const { return LiveVisualization0335RuntimeControls{}; }

void LiveVisualization0335::update(const ParticleState&, const SimulationParams&, std::uint64_t, double) {}
void LiveVisualization0335::draw_rgba_frame(const SimulationParams&, std::uint64_t, double,
                                            const std::vector<unsigned char>&, int, int,
                                            const std::string&,
                                            const LiveVisualization0335QuiverFrame*) {}

void LiveVisualization0335::hold_until_closed_on_exit() {}


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

std::string trim_0335(const std::string& input) {
    std::size_t begin = 0;
    while (begin < input.size() && std::isspace(static_cast<unsigned char>(input[begin]))) ++begin;
    std::size_t end = input.size();
    while (end > begin && std::isspace(static_cast<unsigned char>(input[end - 1]))) --end;
    return input.substr(begin, end - begin);
}

std::string lower_0335(std::string s) {
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

bool truthy_value_0335(const std::string& raw) {
    const std::string s = lower_0335(trim_0335(raw));
    return s == "1" || s == "true" || s == "yes" || s == "on" ||
           s == "enable" || s == "enabled";
}

bool parse_double_0335(const std::string& text, double& value) {
    try {
        std::size_t consumed = 0;
        const double v = std::stod(text, &consumed);
        if (consumed != trim_0335(text).size()) return false;
        value = v;
        return true;
    } catch (...) {
        return false;
    }
}

bool parse_int_0335(const std::string& text, int& value) {
    try {
        std::size_t consumed = 0;
        const int v = std::stoi(text, &consumed);
        if (consumed != trim_0335(text).size()) return false;
        value = v;
        return true;
    } catch (...) {
        return false;
    }
}

unsigned char clamp_u8_0335(double x) {
    const int v = static_cast<int>(std::lround(std::clamp(x, 0.0, 255.0)));
    return static_cast<unsigned char>(v);
}

bool signed_field_0335(const std::string& rawField) {
    const std::string field = lower_0335(trim_0335(rawField));
    return field == "ux" || field == "uy" || field == "vx" || field == "vy" ||
           field == "vorticity" || field == "omega" || field == "curl";
}

std::string normalize_colormap_0342(const std::string& input) {
    const std::string cm = lower_0335(trim_0335(input));
    if (cm == "gray" || cm == "grey" || cm == "grayscale" || cm == "greyscale") return "gray";
    if (cm == "thermal" || cm == "heat" || cm == "hot") return "thermal";
    return "blue_red";
}

void export_colormap_env_0342(const std::string& colormap) {
#if !defined(_WIN32)
    setenv("SRC_LIVE_VIS_COLORMAP", colormap.c_str(), 1);
#else
    (void)colormap;
#endif
}

void map_color_0342(double q, bool signedField, const std::string& colormap,
                    unsigned char& r, unsigned char& g, unsigned char& b) {
    q = std::clamp(q, 0.0, 1.0);
    const std::string cm = normalize_colormap_0342(colormap);
    if (cm == "gray") {
        const unsigned char v = clamp_u8_0335(255.0 * q);
        r = v; g = v; b = v;
        return;
    }
    if (cm == "thermal") {
        r = clamp_u8_0335(255.0 * std::clamp(3.0 * q - 1.0, 0.0, 1.0));
        g = clamp_u8_0335(255.0 * std::clamp(3.0 * q - 2.0, 0.0, 1.0));
        b = clamp_u8_0335(255.0 * std::clamp(1.5 - 3.0 * q, 0.0, 1.0));
        return;
    }
    if (signedField) {
        r = clamp_u8_0335(255.0 * std::max(0.0, 2.0 * q - 1.0));
        b = clamp_u8_0335(255.0 * std::max(0.0, 1.0 - 2.0 * q));
        g = clamp_u8_0335(255.0 * (1.0 - std::abs(2.0 * q - 1.0)));
        r = static_cast<unsigned char>(std::max<int>(r, g));
        b = static_cast<unsigned char>(std::max<int>(b, g));
    } else {
        r = clamp_u8_0335(255.0 * std::max(0.0, 2.0 * q - 1.0));
        g = clamp_u8_0335(255.0 * (1.0 - std::abs(2.0 * q - 1.0)));
        b = clamp_u8_0335(255.0 * std::max(0.0, 1.0 - 2.0 * q));
    }
}

void smooth_quiver_vectors_0365(std::vector<float>& qUx, std::vector<float>& qUy,
                                int qNx, int qNy, int passes) {
    if (qNx <= 0 || qNy <= 0 || passes <= 0) return;
    const std::size_t n = static_cast<std::size_t>(qNx) * static_cast<std::size_t>(qNy);
    if (qUx.size() < n || qUy.size() < n) return;
    std::vector<float> tmpUx(n, 0.0f);
    std::vector<float> tmpUy(n, 0.0f);
    for (int pass = 0; pass < passes; ++pass) {
        for (int iy = 0; iy < qNy; ++iy) {
            for (int ix = 0; ix < qNx; ++ix) {
                double sx = 0.0;
                double sy = 0.0;
                int cnt = 0;
                for (int dy = -1; dy <= 1; ++dy) {
                    const int yy = iy + dy;
                    if (yy < 0 || yy >= qNy) continue;
                    for (int dx = -1; dx <= 1; ++dx) {
                        const int xx = ix + dx;
                        if (xx < 0 || xx >= qNx) continue;
                        const std::size_t kk = static_cast<std::size_t>(yy) * static_cast<std::size_t>(qNx) + static_cast<std::size_t>(xx);
                        const double ux = static_cast<double>(qUx[kk]);
                        const double uy = static_cast<double>(qUy[kk]);
                        if (!std::isfinite(ux) || !std::isfinite(uy)) continue;
                        sx += ux;
                        sy += uy;
                        ++cnt;
                    }
                }
                const std::size_t k = static_cast<std::size_t>(iy) * static_cast<std::size_t>(qNx) + static_cast<std::size_t>(ix);
                if (cnt > 0) {
                    tmpUx[k] = static_cast<float>(sx / static_cast<double>(cnt));
                    tmpUy[k] = static_cast<float>(sy / static_cast<double>(cnt));
                } else {
                    tmpUx[k] = 0.0f;
                    tmpUy[k] = 0.0f;
                }
            }
        }
        qUx.swap(tmpUx);
        qUy.swap(tmpUy);
    }
}

void draw_quiver_lines_0364(int fbw, int fbh,
                            int qNx, int qNy,
                            const float* qUx, const float* qUy,
                            double quiverScale,
                            double quiverMinSpeed) {
    if (fbw <= 0 || fbh <= 0 || qNx <= 0 || qNy <= 0 || qUx == nullptr || qUy == nullptr) return;
    if (!(quiverScale >= 0.0) || !std::isfinite(quiverScale)) return;
    const double minSpeed2 = std::max(0.0, quiverMinSpeed) * std::max(0.0, quiverMinSpeed);
    glLineWidth(1.0f);
    glColor3f(0.0f, 0.0f, 0.0f);
    glBegin(GL_LINES);
    for (int iy = 0; iy < qNy; ++iy) {
        const double y = (static_cast<double>(iy) + 0.5) * static_cast<double>(fbh) / static_cast<double>(qNy);
        for (int ix = 0; ix < qNx; ++ix) {
            const int k = iy * qNx + ix;
            const double ux = static_cast<double>(qUx[k]);
            const double uy = static_cast<double>(qUy[k]);
            if (!std::isfinite(ux) || !std::isfinite(uy)) continue;
            const double speed2 = ux * ux + uy * uy;
            if (speed2 <= minSpeed2) continue;
            const double x = (static_cast<double>(ix) + 0.5) * static_cast<double>(fbw) / static_cast<double>(qNx);
            const double dx = quiverScale * ux;
            const double dy = quiverScale * uy;
            glVertex2d(x - 0.5 * dx, y - 0.5 * dy);
            glVertex2d(x + 0.5 * dx, y + 0.5 * dy);
        }
    }
    glEnd();
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
    int quiverNx = 60;
    int quiverNy = 32;
    double quiverScale = -1.0;
    double quiverMinSpeed = 0.0;
    int quiverSmoothPasses = -1;
    double alpha = 0.08;
    double clip = -1.0;
    double quantile = 0.995;
    double gain = 1.0;
    bool overlaySolid = true;
    std::string field = "ux";
    std::string colormap = "blue_red";
    std::string controlFile;
    int controlReloadEvery = 1;
    bool controlLog = false;
    bool lastRecordEnableInControl0432 = false;

    std::vector<double> sumUx;
    std::vector<double> sumUy;
    std::vector<double> sumMass;
    std::vector<double> sumCount;
    std::vector<double> scalar;
    std::vector<double> scalarTmp;
    std::vector<double> displayScalar;
    std::vector<unsigned char> rgba;

    void allocate() {
        const std::size_t n = static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny);
        sumUx.assign(n, 0.0);
        sumUy.assign(n, 0.0);
        sumMass.assign(n, 0.0);
        sumCount.assign(n, 0.0);
        scalar.assign(n, 0.0);
        scalarTmp.assign(n, 0.0);
        displayScalar.assign(n, 0.0);
        rgba.assign(4u * n, 255u);
    }

    void resize_grid(int newNx, int newNy) {
        newNx = std::max(16, newNx);
        newNy = std::max(16, newNy);
        if (newNx == nx && newNy == ny) return;
        nx = newNx;
        ny = newNy;
        allocate();
        if (window != nullptr) {
            glfwSetWindowSize(window, nx * windowScale, ny * windowScale);
        }
        std::cerr << "\n[livevis0335] resized live grid=" << nx << "x" << ny << " (filter reset)\n";
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

void LiveVisualization0335::hold_until_closed_on_exit() {
    if (!impl_ || !impl_->enabled || impl_->window == nullptr) return;
    const bool hold = env_truthy_0335("SRC_LIVE_VIS_HOLD_ON_EXIT") ||
                      env_truthy_0335("MPCD_LIVE_VIS_HOLD_ON_EXIT");
    if (!hold) return;
    std::cerr << "[livevis0335] hold-on-exit enabled; close the livevis window to exit\n";
    while (impl_->window != nullptr && !glfwWindowShouldClose(impl_->window)) {
        glfwPollEvents();
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
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
    v.colormap = normalize_colormap_0342(env_string_0335("SRC_LIVE_VIS_COLORMAP", env_string_0335("MPCD_LIVE_VIS_COLORMAP", "blue_red")));
    export_colormap_env_0342(v.colormap);
    v.alpha = std::clamp(env_double_0335("SRC_LIVE_VIS_ALPHA", env_double_0335("MPCD_LIVE_VIS_ALPHA", 0.08)), 0.0, 1.0);
    v.clip = env_double_0335("SRC_LIVE_VIS_CLIP", env_double_0335("MPCD_LIVE_VIS_CLIP", -1.0));
    v.quantile = std::clamp(env_double_0335("SRC_LIVE_VIS_QUANTILE", env_double_0335("MPCD_LIVE_VIS_QUANTILE", 0.995)), 0.50, 1.0);
    v.gain = std::max(1.0e-12, env_double_0335("SRC_LIVE_VIS_GAIN", env_double_0335("MPCD_LIVE_VIS_GAIN", 1.0)));
    v.smoothPasses = std::max(0, env_int_0335("SRC_LIVE_VIS_SMOOTH_PASSES", env_int_0335("MPCD_LIVE_VIS_SMOOTH_PASSES", 1)));
    v.quiverNx = std::max(1, env_int_0335("SRC_LIVE_VIS_QUIVER_NX", env_int_0335("MPCD_LIVE_VIS_QUIVER_NX", 60)));
    v.quiverNy = std::max(1, env_int_0335("SRC_LIVE_VIS_QUIVER_NY", env_int_0335("MPCD_LIVE_VIS_QUIVER_NY", 32)));
    v.quiverScale = env_double_0335("SRC_LIVE_VIS_QUIVER_SCALE", env_double_0335("MPCD_LIVE_VIS_QUIVER_SCALE", -1.0));
    v.quiverMinSpeed = std::max(0.0, env_double_0335("SRC_LIVE_VIS_QUIVER_MIN_SPEED", env_double_0335("MPCD_LIVE_VIS_QUIVER_MIN_SPEED", 0.0)));
    v.quiverSmoothPasses = env_int_0335("SRC_LIVE_VIS_QUIVER_SMOOTH_PASSES", env_int_0335("MPCD_LIVE_VIS_QUIVER_SMOOTH_PASSES", -1));
    v.controlFile = env_string_0335("SRC_LIVE_VIS_CONTROL_FILE", env_string_0335("MPCD_LIVE_VIS_CONTROL_FILE", ""));
    v.controlReloadEvery = std::max(1, env_int_0335("SRC_LIVE_VIS_CONTROL_EVERY", env_int_0335("MPCD_LIVE_VIS_CONTROL_EVERY", 1)));
    v.controlLog = env_truthy_0335("SRC_LIVE_VIS_CONTROL_LOG") || env_truthy_0335("MPCD_LIVE_VIS_CONTROL_LOG");
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
              << " colormap=" << v.colormap
              << " alpha=" << v.alpha
              << " clip=" << v.clip
              << " quantile=" << v.quantile
              << " gain=" << v.gain
              << " quiver=" << ((v.quiverScale >= 0.0) ? 1 : 0)
              << " quiverGrid=" << v.quiverNx << "x" << v.quiverNy
              << " quiverScale=" << v.quiverScale
              << " quiverMinSpeed=" << v.quiverMinSpeed
              << " quiverSmoothPasses=" << ((v.quiverSmoothPasses >= 0) ? v.quiverSmoothPasses : v.smoothPasses)
              << " controlFile=" << (v.controlFile.empty() ? "none" : v.controlFile) << '\n';
}

bool LiveVisualization0335::enabled() const { return impl_ && impl_->enabled; }

bool LiveVisualization0335::should_draw(std::uint64_t step, std::uint64_t finalStep) const {
    if (!enabled()) return false;
    return (step % static_cast<std::uint64_t>(impl_->every) == 0u) || step == finalStep;
}

void LiveVisualization0335::maybe_reload_controls(std::uint64_t step) {
    auto& v = *impl_;
    if (!v.enabled || v.controlFile.empty()) return;
    if (v.controlReloadEvery > 1 && (step % static_cast<std::uint64_t>(v.controlReloadEvery)) != 0u) return;

    std::ifstream in(v.controlFile);
    if (!in) return;

    const std::string oldField = v.field;
    const int oldNx = v.nx;
    const int oldNy = v.ny;
    const bool wasRecordEnableInControl0432 = v.lastRecordEnableInControl0432;
    bool recordEnableInControl0432 = false;
    bool recordEnableKeySeen0432 = false;
    const std::string oldColormap = v.colormap;
    const double oldClip = v.clip;
    const double oldGain = v.gain;
    const int oldEvery = v.every;
    const int oldSmooth = v.smoothPasses;
    const int oldQuiverNx = v.quiverNx;
    const int oldQuiverNy = v.quiverNy;
    const double oldQuiverScale = v.quiverScale;
    const double oldQuiverMinSpeed = v.quiverMinSpeed;
    const int oldQuiverSmoothPasses = v.quiverSmoothPasses;

    std::string line;
    while (std::getline(in, line)) {
        const std::size_t comment = line.find('#');
        if (comment != std::string::npos) line = line.substr(0, comment);
        const std::size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        const std::string key = lower_0335(trim_0335(line.substr(0, eq)));
        const std::string value = trim_0335(line.substr(eq + 1));
        if (key.empty() || value.empty()) continue;

        if (key == "field" || key == "live_vis_field" || key == "src_live_vis_field") {
            v.field = value;
        } else if (key == "livegridnx" || key == "live_grid_nx" || key == "live_vis_nx" || key == "src_live_vis_nx") {
            int parsed = v.nx;
            if (parse_int_0335(value, parsed)) v.nx = std::max(16, parsed);
        } else if (key == "livegridny" || key == "live_grid_ny" || key == "live_vis_ny" || key == "src_live_vis_ny") {
            int parsed = v.ny;
            if (parse_int_0335(value, parsed)) v.ny = std::max(16, parsed);
        } else if (key == "recordenable" || key == "record_enable" || key == "filteredrecordenable" || key == "filtered_record_enable") {
            recordEnableKeySeen0432 = true;
            recordEnableInControl0432 = truthy_value_0335(value);
        } else if (key == "colormap" || key == "cmap" || key == "live_vis_colormap" || key == "src_live_vis_colormap") {
            v.colormap = normalize_colormap_0342(value);
            export_colormap_env_0342(v.colormap);
        } else if (key == "clip" || key == "live_vis_clip" || key == "src_live_vis_clip") {
            double parsed = v.clip;
            if (parse_double_0335(value, parsed)) v.clip = parsed;
        } else if (key == "gain" || key == "live_vis_gain" || key == "src_live_vis_gain") {
            double parsed = v.gain;
            if (parse_double_0335(value, parsed)) v.gain = std::max(1.0e-12, parsed);
        } else if (key == "liveevery" || key == "every" || key == "visualevery" ||
                   key == "live_vis_every" || key == "src_live_vis_every" || key == "mpcd_live_vis_every") {
            int parsed = v.every;
            if (parse_int_0335(value, parsed)) v.every = std::max(1, parsed);
        } else if (key == "smoothpasses" || key == "smooth_passes" || key == "smooth" ||
                   key == "live_vis_smooth_passes" || key == "src_live_vis_smooth_passes") {
            int parsed = v.smoothPasses;
            if (parse_int_0335(value, parsed)) v.smoothPasses = std::max(0, parsed);
        } else if (key == "quivernx" || key == "quiver_nx" || key == "live_vis_quiver_nx" || key == "src_live_vis_quiver_nx") {
            int parsed = v.quiverNx;
            if (parse_int_0335(value, parsed)) v.quiverNx = std::max(1, parsed);
        } else if (key == "quiverny" || key == "quiver_ny" || key == "live_vis_quiver_ny" || key == "src_live_vis_quiver_ny") {
            int parsed = v.quiverNy;
            if (parse_int_0335(value, parsed)) v.quiverNy = std::max(1, parsed);
        } else if (key == "quiverscale" || key == "quiver_scale" || key == "quivergain" || key == "quiver_gain" ||
                   key == "live_vis_quiver_scale" || key == "src_live_vis_quiver_scale") {
            double parsed = v.quiverScale;
            if (parse_double_0335(value, parsed)) v.quiverScale = parsed;
        } else if (key == "quiverminspeed" || key == "quiver_min_speed" ||
                   key == "live_vis_quiver_min_speed" || key == "src_live_vis_quiver_min_speed") {
            double parsed = v.quiverMinSpeed;
            if (parse_double_0335(value, parsed)) v.quiverMinSpeed = std::max(0.0, parsed);
        } else if (key == "quiversmoothpasses" || key == "quiver_smooth_passes" ||
                   key == "live_vis_quiver_smooth_passes" || key == "src_live_vis_quiver_smooth_passes") {
            int parsed = v.quiverSmoothPasses;
            if (parse_int_0335(value, parsed)) v.quiverSmoothPasses = parsed;
        }
    }

    const bool gridChanged0432 = (v.nx != oldNx || v.ny != oldNy);
    if (gridChanged0432) {
        const int requestedNx0432 = v.nx;
        const int requestedNy0432 = v.ny;
        v.nx = oldNx;
        v.ny = oldNy;
        if (wasRecordEnableInControl0432 && recordEnableInControl0432) {
            if (v.controlLog) {
                std::cerr << "\n[livevis0335] liveGrid change ignored while recordEnable=true; stop recording first"
                          << " requested=" << requestedNx0432 << "x" << requestedNy0432
                          << " current=" << oldNx << "x" << oldNy << '\n';
            }
        } else {
            v.resize_grid(requestedNx0432, requestedNy0432);
        }
    }

    v.lastRecordEnableInControl0432 = recordEnableKeySeen0432 ? recordEnableInControl0432 : false;

    if (v.controlLog && (v.field != oldField || v.nx != oldNx || v.ny != oldNy || v.colormap != oldColormap || v.clip != oldClip || v.gain != oldGain ||
                         v.every != oldEvery || v.smoothPasses != oldSmooth || v.quiverNx != oldQuiverNx || v.quiverNy != oldQuiverNy ||
                         v.quiverScale != oldQuiverScale || v.quiverMinSpeed != oldQuiverMinSpeed ||
                         v.quiverSmoothPasses != oldQuiverSmoothPasses)) {
        std::cerr << "\n[livevis0335] control reload step=" << step
                  << " field=" << v.field
                  << " grid=" << v.nx << "x" << v.ny
                  << " colormap=" << v.colormap
                  << " clip=" << v.clip
                  << " gain=" << v.gain
                  << " smoothPasses=" << v.smoothPasses
                  << " quiver=" << ((v.quiverScale >= 0.0) ? 1 : 0)
                  << " quiverGrid=" << v.quiverNx << "x" << v.quiverNy
                  << " quiverScale=" << v.quiverScale
                  << " quiverMinSpeed=" << v.quiverMinSpeed
                  << " quiverSmoothPasses=" << ((v.quiverSmoothPasses >= 0) ? v.quiverSmoothPasses : v.smoothPasses)
                  << " file=" << v.controlFile << '\n';
    }
}

LiveVisualization0335RuntimeControls LiveVisualization0335::current_controls() const {
    LiveVisualization0335RuntimeControls c{};
    if (impl_) {
        c.field = impl_->field;
        c.nx = impl_->nx;
        c.ny = impl_->ny;
        c.colormap = impl_->colormap;
        c.clip = impl_->clip;
        c.gain = impl_->gain;
        c.every = impl_->every;
        c.smoothPasses = impl_->smoothPasses;
        c.quiverNx = impl_->quiverNx;
        c.quiverNy = impl_->quiverNy;
        c.quiverScale = impl_->quiverScale;
        c.quiverMinSpeed = impl_->quiverMinSpeed;
        c.quiverSmoothPasses = impl_->quiverSmoothPasses;
    }
    return c;
}

void LiveVisualization0335::update(const ParticleState& state, const SimulationParams& params,
                                   std::uint64_t step, double time) {
    maybe_reload_controls(step);
    auto& v = *impl_;
    if (!v.enabled) return;
    if (v.window == nullptr || glfwWindowShouldClose(v.window)) {
        v.disable("window closed");
        return;
    }

    std::fill(v.sumUx.begin(), v.sumUx.end(), 0.0);
    std::fill(v.sumUy.begin(), v.sumUy.end(), 0.0);
    std::fill(v.sumMass.begin(), v.sumMass.end(), 0.0);
    std::fill(v.sumCount.begin(), v.sumCount.end(), 0.0);
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
        v.sumCount[c] += 1.0;
        v.sumUx[c] += m * state.vx[i];
        v.sumUy[c] += m * state.vy[i];
    }

    const std::string field = lower_0335(trim_0335(v.field));
    for (std::size_t c = 0; c < v.scalar.size(); ++c) {
        const double m = v.sumMass[c];
        const double ux = m > 0.0 ? v.sumUx[c] / m : 0.0;
        const double uy = m > 0.0 ? v.sumUy[c] / m : 0.0;
        if (field == "ux" || field == "vx") v.scalar[c] = ux;
        else if (field == "uy" || field == "vy") v.scalar[c] = uy;
        else if (field == "speed") v.scalar[c] = std::sqrt(ux * ux + uy * uy);
        else if (field == "n" || field == "count" || field == "population" ||
                 field == "particle_count" || field == "cell_count") v.scalar[c] = v.sumCount[c];
        else if (field == "mass" || field == "density") v.scalar[c] = m;
        else v.scalar[c] = m;
    }

    if (field == "vorticity" || field == "omega" || field == "curl") {
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

    double fieldMin0363 = std::numeric_limits<double>::infinity();
    double fieldMax0363 = -std::numeric_limits<double>::infinity();
    bool haveMinMax0363 = false;
    for (double x : v.displayScalar) {
        if (std::isfinite(x)) {
            fieldMin0363 = std::min(fieldMin0363, x);
            fieldMax0363 = std::max(fieldMax0363, x);
            haveMinMax0363 = true;
        }
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
            const double q = signedField
                ? (0.5 + 0.5 * v.gain * v.displayScalar[c] / denom)
                : (v.gain * v.displayScalar[c] / denom);
            map_color_0342(q, signedField, v.colormap, r, g, b);
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
    title << "SRC/MPCD live 0335a | " << v.field << " | cmap=" << v.colormap;
    if (haveMinMax0363) {
        title << " | min=" << std::setprecision(3) << fieldMin0363
              << " max=" << std::setprecision(3) << fieldMax0363;
    }
    title << " | step " << step << " | scale=" << std::setprecision(3) << denom
          << " | t=" << std::fixed << std::setprecision(3) << time;
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
    if (v.quiverScale >= 0.0 && v.quiverNx > 0 && v.quiverNy > 0) {
        const int qCount = v.quiverNx * v.quiverNy;
        std::vector<float> qUx(static_cast<std::size_t>(qCount), 0.0f);
        std::vector<float> qUy(static_cast<std::size_t>(qCount), 0.0f);
        for (int qy = 0; qy < v.quiverNy; ++qy) {
            int iy = static_cast<int>(std::floor((static_cast<double>(qy) + 0.5) * static_cast<double>(v.ny) / static_cast<double>(v.quiverNy)));
            iy = std::clamp(iy, 0, v.ny - 1);
            for (int qx = 0; qx < v.quiverNx; ++qx) {
                int ix = static_cast<int>(std::floor((static_cast<double>(qx) + 0.5) * static_cast<double>(v.nx) / static_cast<double>(v.quiverNx)));
                ix = std::clamp(ix, 0, v.nx - 1);
                const std::size_t c = static_cast<std::size_t>(iy) * static_cast<std::size_t>(v.nx) + static_cast<std::size_t>(ix);
                const std::size_t k = static_cast<std::size_t>(qy) * static_cast<std::size_t>(v.quiverNx) + static_cast<std::size_t>(qx);
                const double m = v.sumMass[c];
                if (m > 0.0) {
                    qUx[k] = static_cast<float>(v.sumUx[c] / m);
                    qUy[k] = static_cast<float>(v.sumUy[c] / m);
                }
            }
        }
        const int qSmooth = (v.quiverSmoothPasses >= 0) ? v.quiverSmoothPasses : v.smoothPasses;
        smooth_quiver_vectors_0365(qUx, qUy, v.quiverNx, v.quiverNy, qSmooth);
        draw_quiver_lines_0364(fbw, fbh, v.quiverNx, v.quiverNy, qUx.data(), qUy.data(), v.quiverScale, v.quiverMinSpeed);
    }

    glfwSwapBuffers(v.window);
    glfwPollEvents();
}

void LiveVisualization0335::draw_rgba_frame(const SimulationParams&, std::uint64_t step, double time,
                                            const std::vector<unsigned char>& frame,
                                            int frameNx,
                                            int frameNy,
                                            const std::string& sourceLabel,
                                            const LiveVisualization0335QuiverFrame* quiver) {
    maybe_reload_controls(step);
    auto& v = *impl_;
    if (!v.enabled) return;
    if (v.window == nullptr || glfwWindowShouldClose(v.window)) {
        v.disable("window closed");
        return;
    }
    if (frameNx <= 0 || frameNy <= 0 || frame.size() < 4u * static_cast<std::size_t>(frameNx) * static_cast<std::size_t>(frameNy)) return;
    std::ostringstream title;
    title << "SRC/MPCD live 0335a | " << v.field << " | cmap=" << v.colormap << " | " << sourceLabel
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
    if (quiver != nullptr && quiver->scale >= 0.0 && quiver->nx > 0 && quiver->ny > 0 &&
        quiver->ux.size() >= static_cast<std::size_t>(quiver->nx * quiver->ny) &&
        quiver->uy.size() >= static_cast<std::size_t>(quiver->nx * quiver->ny)) {
        const int qSmooth = (v.quiverSmoothPasses >= 0) ? v.quiverSmoothPasses : v.smoothPasses;
        if (qSmooth > 0) {
            std::vector<float> qUx = quiver->ux;
            std::vector<float> qUy = quiver->uy;
            smooth_quiver_vectors_0365(qUx, qUy, quiver->nx, quiver->ny, qSmooth);
            draw_quiver_lines_0364(fbw, fbh, quiver->nx, quiver->ny, qUx.data(), qUy.data(), quiver->scale, quiver->minSpeed);
        } else {
            draw_quiver_lines_0364(fbw, fbh, quiver->nx, quiver->ny, quiver->ux.data(), quiver->uy.data(), quiver->scale, quiver->minSpeed);
        }
    }
    glfwSwapBuffers(v.window);
    glfwPollEvents();
}

} // namespace mpcd

#endif // MPCD_ENABLE_LIVE_VIS
