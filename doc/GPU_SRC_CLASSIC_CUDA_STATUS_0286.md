# SRC classic CUDA status at milestone 0286

## Definition

In this branch, **SRC classic** means:

```text
advection / streaming + random grid shift + SRC collision/rotation + thermostat
```

The liquid closure is separate:

```text
Q6 + weighted resampling + virial/capacity response
```

## Validated CUDA families

| Family | Status | Main validator |
|---|---|---|
| Periodic SRC classic | validated | `run_cuda_classic_src_periodic_resident_0260.sh` |
| Wall-simple / Poiseuille | validated | `run_cuda_persistent_src_thermostat_wall_0276.sh` |
| Rectangle / step solid | validated | `run_cuda_persistent_src_thermostat_solid_0277.sh` |
| Piston / mobile wall legacy | validated | `run_cuda_persistent_src_thermostat_piston_0278.sh` |
| Inlet/outlet full-face | validated | `run_cuda_persistent_src_thermostat_io_fullface_0279b.sh` |
| Inlet/outlet segmented | validated | `run_cuda_persistent_src_thermostat_io_segmented_0280c.sh` |
| Periodic circular solid | validated | `run_cuda_persistent_src_thermostat_circle_0284.sh` |
| Circular solid + full-face IO | validated | `run_cuda_persistent_src_thermostat_circle_io_0285.sh` |
| Final consolidated check | wrapper | `run_cuda_src_classic_full_consolidated_0286.sh` |

## Resulting claim

The branch now contains a physically validated **SRC/MPCD classic full CUDA resident** path for periodic, wall, rectangle/step solid, circular solid, piston/mobile wall, full-face inlet/outlet and segmented inlet/outlet cases.

This statement does not claim that Q6, resampling or virial have been fully migrated to CUDA.

## Current limitations

- Q6 remains CPU/OpenMP.
- Resampling remains CPU/OpenMP or hybrid; several CUDA building blocks exist but the liquid closure is not yet full CUDA.
- Virial/capacity response remains separate and must not be bypassed by classic-only fused paths.
- The 0285 circular-solid inlet/outlet validation covers full-face IO; segmented IO with circular obstacle is a natural future extension if needed.
