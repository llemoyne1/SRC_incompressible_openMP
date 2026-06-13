#pragma once

#include "cuda_particle_state.h"

namespace mpcd {

// 0251: single process-local CUDA particle state shared by the validated
// boundary-condition kernels and by the active CUDA cell-moments path.
//
// This is deliberately a narrow bridge: the CPU state remains authoritative,
// but when the last particle update was performed by a CUDA boundary kernel and
// no subsequent CPU boundary edited the particles, cell moments can consume this
// already-resident CudaParticleState instead of uploading x/y/vx/vy again.
#if defined(MPCD_ENABLE_CUDA_PARTICLE_STATE)
CudaParticleState& cuda_shared_particle_state_0251();
void cuda_shared_particle_state_0251_mark_fresh(const char* writer);
void cuda_shared_particle_state_0251_invalidate(const char* reason);
bool cuda_shared_particle_state_0251_is_fresh();
const char* cuda_shared_particle_state_0251_last_writer();
const char* cuda_shared_particle_state_0251_last_invalidator();
bool cuda_shared_particle_state_0251_download_if_fresh(ParticleState& state);
bool cuda_shared_particle_state_0251_download_role_filtered_if_fresh(ParticleState& state,
                                                                    std::uint8_t keepRole,
                                                                    ParticleRoleCounts* roleCounts = nullptr);
// 0336a: visualization/debug snapshot.  Unlike the normal consumer function,
// this deliberately ignores the freshness flag and downloads from the process-
// local shared CudaParticleState if it has allocated storage.  It is intended
// for live visualization after CUDA resampling edits invalidate the 0251 fresh
// marker but leave the resident device arrays authoritative.
bool cuda_shared_particle_state_0251_download_role_filtered_snapshot_0336(ParticleState& state,
                                                                         std::uint8_t keepRole,
                                                                         ParticleRoleCounts* roleCounts = nullptr);
#else
inline void cuda_shared_particle_state_0251_invalidate(const char*) {}
inline bool cuda_shared_particle_state_0251_is_fresh() { return false; }
inline const char* cuda_shared_particle_state_0251_last_writer() { return "disabled"; }
inline const char* cuda_shared_particle_state_0251_last_invalidator() { return "disabled"; }
inline bool cuda_shared_particle_state_0251_download_if_fresh(ParticleState&) { return false; }
inline bool cuda_shared_particle_state_0251_download_role_filtered_if_fresh(ParticleState&, std::uint8_t, ParticleRoleCounts* = nullptr) { return false; }
inline bool cuda_shared_particle_state_0251_download_role_filtered_snapshot_0336(ParticleState&, std::uint8_t, ParticleRoleCounts* = nullptr) { return false; }
#endif

} // namespace mpcd
