
#include "visualization.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <string>
#include <vector>

#ifdef ENABLE_VISUALIZATION
#include <GLFW/glfw3.h>
#endif

namespace mpcd {

namespace {

double clamp01(double x) {
    if (x < 0.0) return 0.0;
    if (x > 1.0) return 1.0;
    return x;
}

int cell_id(int ix, int iy, int Nx) {
    return ix + Nx * iy;
}

void scalar_color(double value, double vmin, double vmax, float& r, float& g, float& b) {
    const double den = std::max(vmax - vmin, 1e-30);
    const double s = clamp01((value - vmin) / den);

    r = static_cast<float>(s);
    g = static_cast<float>(0.15 + 0.70 * (1.0 - std::abs(2.0 * s - 1.0)));
    b = static_cast<float>(1.0 - s);
}

double particle_value(
    const State& state,
    int i,
    const std::string& mode
) {
    const double vx = state.v[2 * i];
    const double vy = state.v[2 * i + 1];

    if (mode == "Ux" || mode == "ux" || mode == "vx") return vx;
    if (mode == "Uy" || mode == "uy" || mode == "vy") return vy;

    return std::sqrt(vx * vx + vy * vy);
}

std::vector<double> build_field_values(
    const Params& p,
    const CellFields& f
) {
    const int Nx = p.Nx;
    const int Ny = p.Ny;
    const int Nc = Nx * Ny;

    std::vector<double> out(Nc, 0.0);

    if (p.visualField == "Ux" || p.visualField == "ux") {
        out = f.Ux;
    } else if (p.visualField == "Uy" || p.visualField == "uy") {
        out = f.Uy;
    }  else if (p.visualField == "N" || p.visualField == "n") {
    for (int c = 0; c < Nc; ++c) {
        out[c] = static_cast<double>(f.N[c]);
    }
    } else if (p.visualField == "rho") {
        out = f.rho;
    } else if (p.visualField == "P" || p.visualField == "p") {
        out = f.P;
    } else if (p.visualField == "vorticity" || p.visualField == "omega") {
        const double dx = p.Lx / static_cast<double>(std::max(1, Nx));
        const double dy = p.Ly / static_cast<double>(std::max(1, Ny));
        const bool perX = (p.boundary_left == "periodic" && p.boundary_right == "periodic");

        for (int iy = 0; iy < Ny; ++iy) {
            for (int ix = 0; ix < Nx; ++ix) {
                const int c = cell_id(ix, iy, Nx);

                int ixm = ix - 1;
                int ixp = ix + 1;
                double ddx = 2.0 * dx;

                if (ix == 0) {
                    if (perX) ixm = Nx - 1;
                    else { ixm = ix; ddx = dx; }
                }
                if (ix == Nx - 1) {
                    if (perX) ixp = 0;
                    else { ixp = ix; ddx = dx; }
                }

                int iym = iy - 1;
                int iyp = iy + 1;
                double ddy = 2.0 * dy;

                if (iy == 0) {
                    iym = iy;
                    ddy = dy;
                }
                if (iy == Ny - 1) {
                    iyp = iy;
                    ddy = dy;
                }

                const double dUy_dx =
                    (f.Uy[cell_id(ixp, iy, Nx)] - f.Uy[cell_id(ixm, iy, Nx)]) / ddx;

                const double dUx_dy =
                    (f.Ux[cell_id(ix, iyp, Nx)] - f.Ux[cell_id(ix, iym, Nx)]) / ddy;

                out[c] = dUy_dx - dUx_dy;
            }
        }
    } else {
        for (int c = 0; c < Nc; ++c) {
            const double ux = f.Ux[c];
            const double uy = f.Uy[c];
            out[c] = std::sqrt(ux * ux + uy * uy);
        }
    }

    return out;
}

void autoscale_range(const std::vector<double>& a, double& vmin, double& vmax) {
    vmin = std::numeric_limits<double>::infinity();
    vmax = -std::numeric_limits<double>::infinity();

    for (double x : a) {
        if (!std::isfinite(x)) continue;
        vmin = std::min(vmin, x);
        vmax = std::max(vmax, x);
    }

    if (!std::isfinite(vmin) || !std::isfinite(vmax) || vmax <= vmin) {
        vmin = 0.0;
        vmax = 1.0;
    }
}

double wrap_x(double x, double Lx) {
    if (Lx <= 0.0) return x;
    x = std::fmod(x, Lx);
    if (x < 0.0) x += Lx;
    return x;
}

} // namespace

bool Visualizer::init(const Params& params) {
    enabled_ = params.visualEnable;
    every_ = std::max(1, params.visualEvery);
    close_ = false;

#ifndef ENABLE_VISUALIZATION
    enabled_ = false;
    return true;
#else
    if (!enabled_) return true;

    if (!glfwInit()) {
        enabled_ = false;
        return false;
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 1);

    GLFWwindow* win = glfwCreateWindow(
        1100,
        850,
        "SRC/MPCD real-time view",
        nullptr,
        nullptr
    );

    if (!win) {
        glfwTerminate();
        enabled_ = false;
        return false;
    }

    window_ = static_cast<void*>(win);

    glfwMakeContextCurrent(win);
    glfwSwapInterval(0);

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_LIGHTING);
    glClearColor(0.02f, 0.02f, 0.025f, 1.0f);

    return true;
#endif
}

bool Visualizer::enabled() const {
    return enabled_;
}

bool Visualizer::should_draw(int step) const {
    return enabled_ && step >= 0 && (step % every_ == 0);
}

bool Visualizer::should_close() const {
    return close_;
}

void Visualizer::update(
    int,
    double,
    const Params& p,
    const State& state,
    const CellFields& fields
) {
#ifndef ENABLE_VISUALIZATION
    (void)p;
    (void)state;
    (void)fields;
#else
    if (!enabled_ || !window_) return;

    GLFWwindow* win = static_cast<GLFWwindow*>(window_);

    if (glfwWindowShouldClose(win) || glfwGetKey(win, GLFW_KEY_ESCAPE) == GLFW_PRESS) {
        close_ = true;
        return;
    }

    glfwMakeContextCurrent(win);

    int w = 1;
    int h = 1;
    glfwGetFramebufferSize(win, &w, &h);
    glViewport(0, 0, w, h);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0.0, p.Lx, 0.0, p.Ly, -1.0, 1.0);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glClear(GL_COLOR_BUFFER_BIT);

    const bool showField =
        (p.visualMode == "field" || p.visualMode == "field_particles");

    const bool showParticles =
        p.visualShowParticles &&
        (p.visualMode == "particles" || p.visualMode == "field_particles");

    if (showField) {
        std::vector<double> values = build_field_values(p, fields);

        double vmin = p.visualFieldMin;
        double vmax = p.visualFieldMax;

        if (p.visualFieldAutoScale) {
            autoscale_range(values, vmin, vmax);
        }

        const double dx = p.Lx / static_cast<double>(std::max(1, p.Nx));
        const double dy = p.Ly / static_cast<double>(std::max(1, p.Ny));

        glBegin(GL_QUADS);
        for (int iy = 0; iy < p.Ny; ++iy) {
            for (int ix = 0; ix < p.Nx; ++ix) {
                const int c = cell_id(ix, iy, p.Nx);

                float r, g, b;
                scalar_color(values[c], vmin, vmax, r, g, b);
                glColor3f(r, g, b);

                const double x0 = ix * dx;
                const double x1 = x0 + dx;
                const double y0 = iy * dy;
                const double y1 = y0 + dy;

                glVertex2d(x0, y0);
                glVertex2d(x1, y0);
                glVertex2d(x1, y1);
                glVertex2d(x0, y1);
            }
        }
        glEnd();
    }

    if (showParticles) {
        const int n = std::max(0, p.n);
        const int maxP = std::max(1, p.visualMaxParticles);
        const int stride = std::max(1, n / maxP);

        double vmin = 0.0;
        double vmax = 1.0;

        if (p.visualParticleColorMode != "type") {
            std::vector<double> pv;
            pv.reserve(static_cast<std::size_t>(std::min(n, maxP + 1)));

            for (int i = 0; i < n; i += stride) {
                pv.push_back(particle_value(state, i, p.visualParticleColorMode));
            }

            autoscale_range(pv, vmin, vmax);
        }

        glPointSize(static_cast<float>(std::max(1.0, p.visualPointSize)));
        glBegin(GL_POINTS);

        for (int i = 0; i < n; i += stride) {
            const double x = wrap_x(state.x[2 * i], p.Lx);
            const double y = state.x[2 * i + 1];

            float r, g, b;

            if (p.visualParticleColorMode == "type" && !state.type.empty()) {
                const int t = static_cast<int>(state.type[i]) % 6;
                const float colors[6][3] = {
                    {1.0f, 1.0f, 1.0f},
                    {1.0f, 0.2f, 0.2f},
                    {0.2f, 1.0f, 0.2f},
                    {0.2f, 0.5f, 1.0f},
                    {1.0f, 1.0f, 0.2f},
                    {1.0f, 0.2f, 1.0f}
                };
                r = colors[t][0];
                g = colors[t][1];
                b = colors[t][2];
            } else {
                const double val = particle_value(state, i, p.visualParticleColorMode);
                scalar_color(val, vmin, vmax, r, g, b);
            }

            glColor3f(r, g, b);
            glVertex2d(x, y);
        }

        glEnd();
    }

    glColor3f(1.0f, 1.0f, 1.0f);
    glBegin(GL_LINE_LOOP);
    glVertex2d(0.0, 0.0);
    glVertex2d(p.Lx, 0.0);
    glVertex2d(p.Lx, p.Ly);
    glVertex2d(0.0, p.Ly);
    glEnd();

    glfwSwapBuffers(win);
    glfwPollEvents();

    if (glfwWindowShouldClose(win)) {
        close_ = true;
    }
#endif
}

void Visualizer::shutdown() {
#ifdef ENABLE_VISUALIZATION
    if (window_) {
        GLFWwindow* win = static_cast<GLFWwindow*>(window_);
        glfwDestroyWindow(win);
        window_ = nullptr;
        glfwTerminate();
    }
#endif
    enabled_ = false;
    close_ = false;
}

} // namespace mpcd
