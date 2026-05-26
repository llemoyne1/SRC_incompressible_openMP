# 0068d fix Q9 low-mass parser and long-run script

This package contains no `.patch` file.

Run from the repository root:

```bash
python3 /path/to/apply_0068d_fix_q9_low_mass_parser.py
./scripts/build_src_mpcd_base.sh
```

It ensures that the executable accepts these `.kv` keys:

```kv
q9LowMassTreatment = ramp_floor
q9MassFloorForCorrection = 8.0
q9LowMassRampStart = 1.0
q9LowMassRampEnd = 8.0
```

It also ensures that `scripts/run_backward_step_hard_inlet_long_0067e.sh` emits the full Q9 safety + ramp-floor block.
