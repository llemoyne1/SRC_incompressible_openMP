# GPU patch 0318 — Wall-circle resident CUDA stream for VK profile bottleneck

## Motivation

The 0317d profile on the restored 0315m state showed that the SRC periodic
Von-Karman-like run is dominated by `src_collision` and `immersed_solid`, with
`immersed_solid` spending most of its time in host-to-device upload.

For `src_cuda_v2_0315m_periodic`, 10000 steps at 192x64, gamma=20 gave:

- total elapsed: 73.61 s;
- profiled total: 72.37 s;
- `src_collision`: 32.93 s;
- `immersed_solid`: 31.86 s;
- `immersed_solid` CUDA resident upload: 23.97 s over 10000 uploads.

The same circle handler in the inlet/outlet resident path did not suffer this
upload cost, which shows that the expensive part is not the circle reflection
kernel itself but the missing upstream GPU residency in the periodic-x/wall-y
fixed-circle case.

## Change

This patch introduces the guarded environment flag:

```bash
MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=1
```

When enabled, it allows the existing CUDA wall-simple streaming kernel 0246 to
run for the validated subset:

- `bcLeft=periodic`, `bcRight=periodic`;
- bottom/top wall modes handled by the 0246 wall-simple kernel;
- fixed circular immersed solid;
- Q6 disabled;
- resampling disabled;
- closed-capacity/virial disabled.

The generic VK demo runner enables the guarded path by default for its own
periodic-x/wall-y/circle case. Other cases remain behind their existing flags.

## Expected measurement target

The target is to remove the measured per-step upload before `immersed_solid`
for the 0317d periodic case and to keep the particle state resident across:

```text
CUDA wall-simple stream/boundary -> CUDA circle -> CUDA collision/thermostat
```

This is not a float/double optimization. The 0317d profile showed the CUDA
collision kernels themselves were not the dominant bottleneck.

## Suggested validation

Rebuild only after applying the archive, then rerun the same 0317d periodic/VKKH
profile or a reduced 1000-step smoke test.  The key counters to check are:

- `cuda_resident_phase_profile_0266.csv`, `immersed_circle_0284` uploadCalls
  should drop from 10000 to approximately 0 or 1 on the periodic case;
- `phase_profile_0163.csv`, `immersed_solid` should drop sharply;
- physical validation should remain PASS for the classic VK demo.
