#include "filtered_field_recorder_0432.h"

#include "live_visualization_0335.h"
#include "particle_state.h"
#include "simulation_params.h"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <unordered_set>
#include <vector>

namespace {

bool truthy_0432(const std::string& s0) {
    std::string s = s0;
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s == "1" || s == "true" || s == "yes" || s == "on" || s == "enable" || s == "enabled";
}

bool env_truthy_0432(const char* name) {
    const char* v = std::getenv(name);
    return v != nullptr && *v != '\0' && truthy_0432(v);
}

int env_int_0432(const char* name, int fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try { return std::stoi(v); } catch (...) { return fallback; }
}

double env_double_0432(const char* name, double fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    try { return std::stod(v); } catch (...) { return fallback; }
}

std::string env_string_0432(const char* name, const std::string& fallback) {
    const char* v = std::getenv(name);
    if (v == nullptr || *v == '\0') return fallback;
    return std::string(v);
}

std::string trim_0432(const std::string& input) {
    std::size_t begin = 0;
    while (begin < input.size() && std::isspace(static_cast<unsigned char>(input[begin]))) ++begin;
    std::size_t end = input.size();
    while (end > begin && std::isspace(static_cast<unsigned char>(input[end - 1]))) --end;
    return input.substr(begin, end - begin);
}

std::string lower_0432(std::string s) {
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

bool parse_int_0432(const std::string& text, int& value) {
    try {
        std::size_t consumed = 0;
        const int v = std::stoi(trim_0432(text), &consumed);
        if (consumed != trim_0432(text).size()) return false;
        value = v;
        return true;
    } catch (...) {
        return false;
    }
}

bool parse_double_0432(const std::string& text, double& value) {
    try {
        std::size_t consumed = 0;
        const double v = std::stod(trim_0432(text), &consumed);
        if (consumed != trim_0432(text).size()) return false;
        value = v;
        return true;
    } catch (...) {
        return false;
    }
}

std::vector<std::string> split_fields_0432(const std::string& text) {
    std::string s = text;
    for (char& c : s) {
        if (c == ',' || c == ';' || std::isspace(static_cast<unsigned char>(c))) c = ' ';
    }
    std::istringstream iss(s);
    std::vector<std::string> out;
    std::string item;
    while (iss >> item) out.push_back(item);
    return out;
}

std::string sanitize_name_0432(const std::string& input) {
    std::string out;
    out.reserve(input.size());
    for (char ch : input) {
        const unsigned char c = static_cast<unsigned char>(ch);
        if (std::isalnum(c) || ch == '_' || ch == '-' || ch == '.') out.push_back(ch);
        else out.push_back('_');
    }
    if (out.empty()) out = "record";
    return out;
}

std::string normalize_field_0432(const std::string& raw) {
    const std::string f = lower_0432(trim_0432(raw));
    if (f == "density" || f == "mass" || f == "rho") return "rho";
    if (f == "rho1" || f == "mass1" || f == "density1") return "rho1";
    if (f == "rho2" || f == "mass2" || f == "density2") return "rho2";
    if (f == "y1" || f == "fraction1" || f == "massfraction1") return "y1";
    if (f == "y2" || f == "fraction2" || f == "massfraction2") return "y2";
    if (f == "ux" || f == "vx") return "ux";
    if (f == "uy" || f == "vy") return "uy";
    if (f == "speed" || f == "normu" || f == "velocity") return "speed";
    if (f == "n" || f == "count" || f == "population" || f == "particle_count") return "n";
    if (f == "n1" || f == "count1" || f == "population1") return "n1";
    if (f == "n2" || f == "count2" || f == "population2") return "n2";
    if (f == "current") return "current";
    return f;
}

bool supported_field_0432(const std::string& f) {
    static const std::unordered_set<std::string> supported = {
        "rho", "rho1", "rho2", "y1", "y2", "ux", "uy", "speed", "n", "n1", "n2"
    };
    return supported.find(f) != supported.end();
}

std::string join_fields_0432(const std::vector<std::string>& fields) {
    std::ostringstream oss;
    for (std::size_t i = 0; i < fields.size(); ++i) {
        if (i) oss << ',';
        oss << fields[i];
    }
    return oss.str();
}

std::string step_string_0432(std::uint64_t step) {
    std::ostringstream oss;
    oss << std::setw(10) << std::setfill('0') << step;
    return oss.str();
}

void smooth_scalar_0432(std::vector<float>& field, int nx, int ny, int passes) {
    if (nx <= 0 || ny <= 0 || passes <= 0) return;
    const std::size_t n = static_cast<std::size_t>(nx) * static_cast<std::size_t>(ny);
    if (field.size() < n) return;
    std::vector<float> tmp(n, 0.0f);
    for (int pass = 0; pass < passes; ++pass) {
        tmp = field;
        for (int iy = 0; iy < ny; ++iy) {
            for (int ix = 0; ix < nx; ++ix) {
                double acc = 0.0;
                int cnt = 0;
                for (int dy = -1; dy <= 1; ++dy) {
                    const int yy = iy + dy;
                    if (yy < 0 || yy >= ny) continue;
                    for (int dx = -1; dx <= 1; ++dx) {
                        const int xx = ix + dx;
                        if (xx < 0 || xx >= nx) continue;
                        acc += tmp[static_cast<std::size_t>(yy) * static_cast<std::size_t>(nx) + static_cast<std::size_t>(xx)];
                        ++cnt;
                    }
                }
                field[static_cast<std::size_t>(iy) * static_cast<std::size_t>(nx) + static_cast<std::size_t>(ix)] =
                    cnt > 0 ? static_cast<float>(acc / static_cast<double>(cnt)) : 0.0f;
            }
        }
    }
}

} // namespace

namespace mpcd {

struct FilteredFieldRecorder0432::Impl {
    struct Control {
        bool recordEnable = false;
        std::string recordSession;
        std::string recordFieldsRaw = "current";
        int recordEvery = 25;
        std::string recordFormat = "f32";
        int liveGridNx = 300;
        int liveGridNy = 80;
        std::string field = "ux";
        std::string filterMode = "ema";
        double filterTau = 0.0;
        int filterSampleEvery = 1;
        int smoothPasses = 0;
    };

    struct ConservedFields {
        std::vector<double> rho;
        std::vector<double> rho1;
        std::vector<double> rho2;
        std::vector<double> px;
        std::vector<double> py;
        std::vector<double> n;
        std::vector<double> n1;
        std::vector<double> n2;

        void resize(std::size_t ncell) {
            rho.assign(ncell, 0.0);
            rho1.assign(ncell, 0.0);
            rho2.assign(ncell, 0.0);
            px.assign(ncell, 0.0);
            py.assign(ncell, 0.0);
            n.assign(ncell, 0.0);
            n1.assign(ncell, 0.0);
            n2.assign(ncell, 0.0);
        }

        void zero() {
            std::fill(rho.begin(), rho.end(), 0.0);
            std::fill(rho1.begin(), rho1.end(), 0.0);
            std::fill(rho2.begin(), rho2.end(), 0.0);
            std::fill(px.begin(), px.end(), 0.0);
            std::fill(py.begin(), py.end(), 0.0);
            std::fill(n.begin(), n.end(), 0.0);
            std::fill(n1.begin(), n1.end(), 0.0);
            std::fill(n2.begin(), n2.end(), 0.0);
        }
    };

    bool enabled = false;
    bool active = false;
    bool initialized = false;
    bool warnedLockedChange = false;
    std::string controlFile;
    int controlReloadEvery = 1;
    std::string outputRoot;
    Control preview;
    Control locked;
    std::vector<std::string> lockedFields;
    std::filesystem::path sessionDir;
    std::uint64_t startStep = 0;
    std::uint64_t lastSampleStep = std::numeric_limits<std::uint64_t>::max();
    double lastSampleTime = 0.0;
    std::uint64_t frameCount = 0;
    ConservedFields instant;
    ConservedFields ema;
    bool emaInitialized = false;

    void parse_control_file(const LiveVisualization0335RuntimeControls& liveControls) {
        if (!liveControls.field.empty()) preview.field = liveControls.field;
        if (liveControls.nx > 0) preview.liveGridNx = liveControls.nx;
        if (liveControls.ny > 0) preview.liveGridNy = liveControls.ny;
        preview.smoothPasses = std::max(0, liveControls.smoothPasses);

        if (controlFile.empty()) return;
        std::ifstream in(controlFile);
        if (!in) return;
        std::string line;
        while (std::getline(in, line)) {
            const std::size_t comment = line.find('#');
            if (comment != std::string::npos) line = line.substr(0, comment);
            const std::size_t eq = line.find('=');
            if (eq == std::string::npos) continue;
            const std::string key = lower_0432(trim_0432(line.substr(0, eq)));
            const std::string value = trim_0432(line.substr(eq + 1));
            if (key.empty() || value.empty()) continue;
            if (key == "recordenable" || key == "record_enable" || key == "filteredrecordenable" || key == "filtered_record_enable") {
                preview.recordEnable = truthy_0432(value);
            } else if (key == "recordsession" || key == "record_session") {
                preview.recordSession = value;
            } else if (key == "recordfields" || key == "record_fields") {
                preview.recordFieldsRaw = value;
            } else if (key == "recordevery" || key == "record_every") {
                int parsed = preview.recordEvery;
                if (parse_int_0432(value, parsed)) preview.recordEvery = std::max(1, parsed);
            } else if (key == "recordformat" || key == "record_format") {
                preview.recordFormat = lower_0432(value);
            } else if (key == "livegridnx" || key == "live_grid_nx" || key == "live_vis_nx" || key == "src_live_vis_nx") {
                int parsed = preview.liveGridNx;
                if (parse_int_0432(value, parsed)) preview.liveGridNx = std::max(16, parsed);
            } else if (key == "livegridny" || key == "live_grid_ny" || key == "live_vis_ny" || key == "src_live_vis_ny") {
                int parsed = preview.liveGridNy;
                if (parse_int_0432(value, parsed)) preview.liveGridNy = std::max(16, parsed);
            } else if (key == "field" || key == "live_vis_field" || key == "src_live_vis_field") {
                preview.field = value;
            } else if (key == "filtermode" || key == "filter_mode") {
                preview.filterMode = lower_0432(value);
            } else if (key == "filtertau" || key == "filter_tau") {
                double parsed = preview.filterTau;
                if (parse_double_0432(value, parsed)) preview.filterTau = std::max(0.0, parsed);
            } else if (key == "filtersampleevery" || key == "filter_sample_every") {
                int parsed = preview.filterSampleEvery;
                if (parse_int_0432(value, parsed)) preview.filterSampleEvery = std::max(1, parsed);
            } else if (key == "smoothpasses" || key == "smooth_passes" || key == "smooth") {
                int parsed = preview.smoothPasses;
                if (parse_int_0432(value, parsed)) preview.smoothPasses = std::max(0, parsed);
            }
        }
    }

    std::vector<std::string> resolve_fields() const {
        std::vector<std::string> out;
        std::unordered_set<std::string> seen;
        for (const std::string& raw0 : split_fields_0432(locked.recordFieldsRaw)) {
            std::string raw = raw0;
            if (normalize_field_0432(raw) == "current") raw = locked.field;
            const std::string f = normalize_field_0432(raw);
            if (!supported_field_0432(f)) {
                throw std::runtime_error("filtered recorder 0432 unsupported record field: " + raw0);
            }
            if (seen.insert(f).second) out.push_back(f);
        }
        if (out.empty()) {
            const std::string f = normalize_field_0432(locked.field);
            if (!supported_field_0432(f)) {
                throw std::runtime_error("filtered recorder 0432 unsupported current field: " + locked.field);
            }
            out.push_back(f);
        }
        return out;
    }

    bool locked_params_changed() const {
        return preview.liveGridNx != locked.liveGridNx ||
               preview.liveGridNy != locked.liveGridNy ||
               normalize_field_0432(preview.field) != normalize_field_0432(locked.field) ||
               preview.recordFieldsRaw != locked.recordFieldsRaw ||
               preview.recordEvery != locked.recordEvery ||
               lower_0432(preview.recordFormat) != lower_0432(locked.recordFormat) ||
               lower_0432(preview.filterMode) != lower_0432(locked.filterMode) ||
               std::abs(preview.filterTau - locked.filterTau) > 0.0 ||
               preview.filterSampleEvery != locked.filterSampleEvery ||
               preview.smoothPasses != locked.smoothPasses;
    }

    void start_session(std::uint64_t step, double time, const SimulationParams& params) {
        locked = preview;
        locked.liveGridNx = std::max(16, locked.liveGridNx);
        locked.liveGridNy = std::max(16, locked.liveGridNy);
        locked.recordEvery = std::max(1, locked.recordEvery);
        locked.filterSampleEvery = std::max(1, locked.filterSampleEvery);
        locked.smoothPasses = std::max(0, locked.smoothPasses);
        locked.filterMode = lower_0432(locked.filterMode);
        locked.recordFormat = lower_0432(locked.recordFormat);
        if (locked.recordFormat != "f32" && locked.recordFormat != "float32") {
            throw std::runtime_error("filtered recorder 0432 supports recordFormat=f32 only in 0432a");
        }
        lockedFields = resolve_fields();
        const std::size_t ncell = static_cast<std::size_t>(locked.liveGridNx) * static_cast<std::size_t>(locked.liveGridNy);
        instant.resize(ncell);
        ema.resize(ncell);
        emaInitialized = false;
        lastSampleStep = std::numeric_limits<std::uint64_t>::max();
        frameCount = 0;
        startStep = step;
        warnedLockedChange = false;
        std::string session = sanitize_name_0432(locked.recordSession);
        if (session == "record" || session.empty()) {
            session = "record_step_" + step_string_0432(step);
        }
        sessionDir = std::filesystem::path(outputRoot) / "recordings" / session;
        if (std::filesystem::exists(sessionDir)) {
            sessionDir = std::filesystem::path(outputRoot) / "recordings" / (session + "_step_" + step_string_0432(step));
        }
        std::filesystem::create_directories(sessionDir);
        write_manifest_start(step, time, params);
        write_timeline_header();
        active = true;
        std::cerr << "\n[filtered-record0432] start session=" << sessionDir.string()
                  << " fields=" << join_fields_0432(lockedFields)
                  << " grid=" << locked.liveGridNx << "x" << locked.liveGridNy
                  << " every=" << locked.recordEvery
                  << " filter=" << locked.filterMode << " tau=" << locked.filterTau
                  << " sampleEvery=" << locked.filterSampleEvery << '\n';
    }

    void stop_session(std::uint64_t step, double time) {
        if (!active) return;
        std::ofstream out(sessionDir / "session_end.kv");
        out << "endStep = " << step << "\n";
        out << "endTime = " << std::setprecision(17) << time << "\n";
        out << "frames = " << frameCount << "\n";
        active = false;
        std::cerr << "\n[filtered-record0432] stop session=" << sessionDir.string()
                  << " step=" << step << " frames=" << frameCount << '\n';
    }

    void write_manifest_start(std::uint64_t step, double time, const SimulationParams& params) const {
        std::ofstream out(sessionDir / "manifest.kv");
        out << "version = 0432a\n";
        out << "startStep = " << step << "\n";
        out << "startTime = " << std::setprecision(17) << time << "\n";
        out << "solverNx = " << params.Nx << "\n";
        out << "solverNy = " << params.Ny << "\n";
        out << "Lx = " << std::setprecision(17) << params.Lx << "\n";
        out << "Ly = " << std::setprecision(17) << params.Ly << "\n";
        out << "liveGridNx = " << locked.liveGridNx << "\n";
        out << "liveGridNy = " << locked.liveGridNy << "\n";
        out << "recordFieldCount = " << lockedFields.size() << "\n";
        out << "recordFields = " << join_fields_0432(lockedFields) << "\n";
        out << "currentFieldAtStart = " << normalize_field_0432(locked.field) << "\n";
        out << "recordEvery = " << locked.recordEvery << "\n";
        out << "recordFormat = f32\n";
        out << "filterMode = " << locked.filterMode << "\n";
        out << "filterTau = " << std::setprecision(17) << locked.filterTau << "\n";
        out << "filterSampleEvery = " << locked.filterSampleEvery << "\n";
        out << "smoothPasses = " << locked.smoothPasses << "\n";
        out << "layout = row_major\n";
        out << "filePattern = step_<step>_field_<field>.f32\n";
        out << "observationOnly = true\n";
    }

    void write_timeline_header() const {
        std::ofstream out(sessionDir / "timeline.csv");
        out << "frame,step,time,field,nx,ny,file\n";
    }

    void append_timeline(std::uint64_t step, double time, const std::string& field, const std::string& file) const {
        std::ofstream out(sessionDir / "timeline.csv", std::ios::app);
        out << frameCount << ',' << step << ',' << std::setprecision(17) << time << ','
            << field << ',' << locked.liveGridNx << ',' << locked.liveGridNy << ',' << file << '\n';
    }

    void deposit(const ParticleState& state, const SimulationParams& params) {
        instant.zero();
        const std::size_t n = static_cast<std::size_t>(state.Np);
        const double invLx = params.Lx > 0.0 ? 1.0 / params.Lx : 1.0;
        const double invLy = params.Ly > 0.0 ? 1.0 / params.Ly : 1.0;
        for (std::size_t i = 0; i < n; ++i) {
            if (!state.role.empty() && state.role[i] != kParticleRoleFluid) continue;
            double x = state.x[i];
            double y = state.y[i];
            if (params.Lx > 0.0) x -= std::floor(x * invLx) * params.Lx;
            if (params.Ly > 0.0) y -= std::floor(y * invLy) * params.Ly;
            const int ix = std::clamp(static_cast<int>(std::floor(x * invLx * locked.liveGridNx)), 0, locked.liveGridNx - 1);
            const int iy = std::clamp(static_cast<int>(std::floor(y * invLy * locked.liveGridNy)), 0, locked.liveGridNy - 1);
            const std::size_t c = static_cast<std::size_t>(iy) * static_cast<std::size_t>(locked.liveGridNx) + static_cast<std::size_t>(ix);
            const double m = state.mass.empty() ? 1.0 : state.mass[i];
            const std::uint32_t typ = state.type.empty() ? 0u : state.type[i];
            instant.rho[c] += m;
            instant.px[c] += m * state.vx[i];
            instant.py[c] += m * state.vy[i];
            instant.n[c] += 1.0;
            if (typ == 1u) {
                instant.rho1[c] += m;
                instant.n1[c] += 1.0;
            } else if (typ == 2u) {
                instant.rho2[c] += m;
                instant.n2[c] += 1.0;
            }
        }
    }

    static void ema_update_array(std::vector<double>& dst, const std::vector<double>& src, double alpha) {
        if (dst.size() != src.size()) dst = src;
        for (std::size_t i = 0; i < dst.size(); ++i) dst[i] = (1.0 - alpha) * dst[i] + alpha * src[i];
    }

    void update_filter(std::uint64_t step, double time) {
        double alpha = 1.0;
        if (locked.filterMode == "ema" && locked.filterTau > 0.0 && emaInitialized) {
            const double dt = std::max(0.0, time - lastSampleTime);
            alpha = 1.0 - std::exp(-dt / std::max(locked.filterTau, 1.0e-300));
            alpha = std::clamp(alpha, 0.0, 1.0);
        }
        if (!emaInitialized || locked.filterMode == "instant" || locked.filterMode == "none") {
            ema = instant;
            emaInitialized = true;
        } else {
            ema_update_array(ema.rho, instant.rho, alpha);
            ema_update_array(ema.rho1, instant.rho1, alpha);
            ema_update_array(ema.rho2, instant.rho2, alpha);
            ema_update_array(ema.px, instant.px, alpha);
            ema_update_array(ema.py, instant.py, alpha);
            ema_update_array(ema.n, instant.n, alpha);
            ema_update_array(ema.n1, instant.n1, alpha);
            ema_update_array(ema.n2, instant.n2, alpha);
        }
        lastSampleStep = step;
        lastSampleTime = time;
    }

    std::vector<float> build_field(const std::string& field) const {
        const std::size_t ncell = ema.rho.size();
        std::vector<float> out(ncell, 0.0f);
        for (std::size_t c = 0; c < ncell; ++c) {
            const double rho = ema.rho[c];
            double value = 0.0;
            if (field == "rho") value = rho;
            else if (field == "rho1") value = ema.rho1[c];
            else if (field == "rho2") value = ema.rho2[c];
            else if (field == "y1") value = rho > 0.0 ? ema.rho1[c] / rho : 0.0;
            else if (field == "y2") value = rho > 0.0 ? ema.rho2[c] / rho : 0.0;
            else if (field == "ux") value = rho > 0.0 ? ema.px[c] / rho : 0.0;
            else if (field == "uy") value = rho > 0.0 ? ema.py[c] / rho : 0.0;
            else if (field == "speed") {
                const double ux = rho > 0.0 ? ema.px[c] / rho : 0.0;
                const double uy = rho > 0.0 ? ema.py[c] / rho : 0.0;
                value = std::sqrt(ux * ux + uy * uy);
            } else if (field == "n") value = ema.n[c];
            else if (field == "n1") value = ema.n1[c];
            else if (field == "n2") value = ema.n2[c];
            if (!std::isfinite(value)) value = 0.0;
            out[c] = static_cast<float>(value);
        }
        smooth_scalar_0432(out, locked.liveGridNx, locked.liveGridNy, locked.smoothPasses);
        return out;
    }

    void write_frame(std::uint64_t step, double time) {
        for (const std::string& field : lockedFields) {
            std::vector<float> data = build_field(field);
            const std::string filename = "step_" + step_string_0432(step) + "_field_" + field + ".f32";
            const std::filesystem::path path = sessionDir / filename;
            std::ofstream out(path, std::ios::binary);
            out.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size() * sizeof(float)));
            if (!out) throw std::runtime_error("filtered recorder 0432 failed writing " + path.string());
            append_timeline(step, time, field, filename);
        }
        ++frameCount;
    }
};

FilteredFieldRecorder0432::FilteredFieldRecorder0432() : impl_(std::make_unique<Impl>()) {}
FilteredFieldRecorder0432::~FilteredFieldRecorder0432() = default;

void FilteredFieldRecorder0432::maybe_initialize(const SimulationParams& params) {
    auto& r = *impl_;
    r.enabled = env_truthy_0432("MPCD_FILTERED_FIELD_RECORDING_0432") ||
                env_truthy_0432("SRC_FILTERED_FIELD_RECORDING_0432");
    if (!r.enabled) return;
    r.controlFile = env_string_0432("SRC_LIVE_VIS_CONTROL_FILE", env_string_0432("MPCD_LIVE_VIS_CONTROL_FILE", ""));
    r.controlReloadEvery = std::max(1, env_int_0432("SRC_LIVE_VIS_CONTROL_EVERY", env_int_0432("MPCD_LIVE_VIS_CONTROL_EVERY", 1)));
    r.outputRoot = params.outputDir;
    r.preview.liveGridNx = std::max(16, env_int_0432("SRC_LIVE_VIS_NX", env_int_0432("MPCD_LIVE_VIS_NX", 300)));
    r.preview.liveGridNy = std::max(16, env_int_0432("SRC_LIVE_VIS_NY", env_int_0432("MPCD_LIVE_VIS_NY", 80)));
    r.preview.field = env_string_0432("SRC_LIVE_VIS_FIELD", env_string_0432("MPCD_LIVE_VIS_FIELD", "ux"));
    r.preview.smoothPasses = std::max(0, env_int_0432("SRC_LIVE_VIS_SMOOTH_PASSES", env_int_0432("MPCD_LIVE_VIS_SMOOTH_PASSES", 0)));
    r.preview.filterTau = std::max(0.0, env_double_0432("SRC_FILTERED_FIELD_TAU", env_double_0432("MPCD_FILTERED_FIELD_TAU", 0.0)));
    r.preview.filterSampleEvery = std::max(1, env_int_0432("SRC_FILTERED_FIELD_SAMPLE_EVERY", env_int_0432("MPCD_FILTERED_FIELD_SAMPLE_EVERY", 1)));
    r.preview.recordEvery = std::max(1, env_int_0432("SRC_FILTERED_FIELD_RECORD_EVERY", env_int_0432("MPCD_FILTERED_FIELD_RECORD_EVERY", 25)));
    r.preview.recordFieldsRaw = env_string_0432("SRC_FILTERED_FIELD_RECORD_FIELDS", env_string_0432("MPCD_FILTERED_FIELD_RECORD_FIELDS", "current"));
    r.initialized = true;
    std::cerr << "[filtered-record0432] enabled controlFile=" << (r.controlFile.empty() ? "none" : r.controlFile)
              << " outputRoot=" << r.outputRoot << '\n';
}

bool FilteredFieldRecorder0432::enabled() const { return impl_ && impl_->enabled; }

void FilteredFieldRecorder0432::poll_controls(std::uint64_t step,
                                               double time,
                                               const LiveVisualization0335RuntimeControls& liveControls) {
    auto& r = *impl_;
    if (!r.enabled) return;
    if (!r.initialized) return;
    if (r.controlReloadEvery > 1 && (step % static_cast<std::uint64_t>(r.controlReloadEvery)) != 0u) return;
    r.parse_control_file(liveControls);
    if (r.active) {
        if (!r.preview.recordEnable) {
            r.stop_session(step, time);
            return;
        }
        if (r.locked_params_changed() && !r.warnedLockedChange) {
            r.warnedLockedChange = true;
            std::cerr << "\n[filtered-record0432] recording locked; grid/fields/filter/cadence changes ignored until recordEnable=false\n";
        }
        return;
    }
    if (r.preview.recordEnable) {
        // The physical time is supplied at the first sample; use step*dt there.
        // A zero time in the initial manifest is corrected by sample_and_maybe_write.
        // The manifest start time is informational only in 0432a.
        // session actually starts below with the correct time if sample is called.
    }
}

bool FilteredFieldRecorder0432::needs_host_state(std::uint64_t step) const {
    const auto& r = *impl_;
    if (!r.enabled) return false;
    if (!r.active && r.preview.recordEnable) return true;
    if (!r.active) return false;
    if (r.lastSampleStep == std::numeric_limits<std::uint64_t>::max()) return true;
    return (step - r.lastSampleStep) >= static_cast<std::uint64_t>(std::max(1, r.locked.filterSampleEvery));
}

void FilteredFieldRecorder0432::sample_and_maybe_write(const ParticleState& state,
                                                        const SimulationParams& params,
                                                        std::uint64_t step,
                                                        double time) {
    auto& r = *impl_;
    if (!r.enabled) return;
    if (!r.active && r.preview.recordEnable) {
        r.start_session(step, time, params);
    }
    if (!r.active) return;
    const bool shouldSample = r.lastSampleStep == std::numeric_limits<std::uint64_t>::max() ||
        (step - r.lastSampleStep) >= static_cast<std::uint64_t>(std::max(1, r.locked.filterSampleEvery));
    if (shouldSample) {
        r.deposit(state, params);
        r.update_filter(step, time);
    }
    const bool shouldWrite = r.emaInitialized && ((step - r.startStep) % static_cast<std::uint64_t>(r.locked.recordEvery) == 0u);
    if (shouldWrite) {
        r.write_frame(step, time);
    }
}

void FilteredFieldRecorder0432::finalize(std::uint64_t step, double time) {
    auto& r = *impl_;
    if (!r.enabled || !r.active) return;
    r.stop_session(step, time);
}

} // namespace mpcd
