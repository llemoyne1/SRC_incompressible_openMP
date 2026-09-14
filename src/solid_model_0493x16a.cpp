#include "solid_model_0493x16a.h"
#include "solid_model_rigid_slab_0493x16a.h"
#include "simulation_params.h"

#include <stdexcept>

namespace mpcd {

SolidModelBundle0493x16a make_solid_model_0493x16a(const SimulationParams& params) {
    if (params.chiSolidModel == "rigid_slab_1d") {
        return make_rigid_slab_1d_0493x16a(params);
    }
    throw std::runtime_error("0493x16a unknown chiSolidModel=" + params.chiSolidModel);
}

} // namespace mpcd
