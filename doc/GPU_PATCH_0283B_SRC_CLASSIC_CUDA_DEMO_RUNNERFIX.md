# 0283b — SRC classic CUDA demo runner fix

This patch fixes the 0283 demonstration scripts.

## Root cause

The common SRC classic parameter block contained legacy keys that are not
accepted by the current `SRC_GPU` parameter parser:

```text
q9MassFluxProjectionEnable
virialDiagnosticsEnable
virialKickEnable
```

The executable therefore stopped immediately while parsing the first demo
configuration.  Because stderr was redirected to the `.time` file, the original
script only printed the generated initial-state path and the output directory,
then stopped without showing the actual parser error.

## Fix

The unsupported keys are removed.  The SRC classic / liquid-closure separation is
still explicit through accepted switches:

```text
projectionEnable = false
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
```

The runner now also checks that each demo produced:

```text
summary_runtime.csv
state_step_*.smpcd
```

and prints the stderr/time tail, stdout/log tail and parameter-file head on any
failure.

## Usage

```bash
bash scripts/run_demo_src_classic_cuda_all_0283.sh
```

For quick tests:

```bash
STEPS=300 DUMP_STATE_EVERY=100 SUMMARY_EVERY=100 \
  bash scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh
```
