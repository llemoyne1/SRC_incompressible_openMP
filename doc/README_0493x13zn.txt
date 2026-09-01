0493x13zn — injection runner cleanup

Scope:
  scripts/run_ok_injection_type1_into_type2.sh
  scripts/src_mpcd_run_ok_common.sh

livevis_control.kv is explicitly outside the patch scope and is never read or written.

Changes:
1. Remove the duplicate runner-side:
     speciesQ6Mode = ${SPECIES_Q6_MODE}
   For src-q6-g-f, the common writer remains authoritative and writes
   free_surface_masked.

2. In suite_run_binary_0434(), rename the local argument holder
   params -> params_file to avoid Bash dynamic-scope clobbering.

Apply from repo root:
  unzip -o 0493x13zn_injection_runner_cleanup.zip
  python3 tools/apply_0493x13zn_injection_runner_cleanup.py

Validate:
  PREFLIGHT_ONLY=1 bash scripts/run_ok_injection_type1_into_type2.sh

The [0434-suite] params= path should contain:
  .../src-q6-g-f/params/injection_type1_into_type2.kv

Then:
  PARAMS='runs/0493w4_injection_type1_into_type2_liquid_type1_into_full_gas_type2_mr10._768x256_g8/src-q6-g-f/params/injection_type1_into_type2.kv'
  grep -n '^speciesQ6Mode' "$PARAMS"

Expected: one line only, free_surface_masked.
