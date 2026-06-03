# SRCMPCD_STATE_BIN_V1

Binary particle-state format for the new generic SRC/MPCD C++ core.

The file contains only the microscopic particle state. It intentionally does not
store simulation parameters such as domain size, grid, timestep, boundary
conditions, thermostat, projection, EOS, dump cadence, or diagnostics. Those
remain in `params.kv`.

## Header

All scalar values are little-endian. The format is fixed-size and written
field-by-field, not as a packed C/C++ struct.

| Field | Type | Value |
|---|---:|---|
| `magic` | `char[16]` | `SRCMPCD_STATE` followed by 3 zero bytes |
| `version` | `uint32` | `1` |
| `endian` | `uint32` | `0x01020304` |
| `dim` | `uint32` | `2` |
| `layout` | `uint32` | `1` = structure-of-arrays |
| `Np` | `uint64` | number of particles |
| `hasType` | `uint32` | `1` |
| `hasMass` | `uint32` | `1` |
| `realSize` | `uint32` | `8`, double precision |
| `typeSize` | `uint32` | `4`, uint32 particle type |
| `reserved` | `uint64[8]` | all zeros for version 1 |

Header size: 120 bytes.

## Payload

The payload is SoA:

```text
x[Np]       double
y[Np]       double
vx[Np]      double
vy[Np]      double
type[Np]    uint32
mass[Np]    double
```

Total file size in bytes:

```text
120 + Np * (5*8 + 4)
```

## MATLAB tools

- `write_smpcd_state.m`
- `read_smpcd_state.m`
- `generate_smpcd_state_uniform.m`
- `inspect_smpcd_state.m`

## C++ API

- `include/particle_state.h`
- `include/state_smpcd_io.h`
- `src/particle_state.cpp`
- `src/state_smpcd_io.cpp`
