#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

# Runs a selected 0140 revalidation subset. Initial .smpcd files must already exist in init/**.
# Select tests with VALIDATION_TESTS, space-separated:
#   tg_void tg_random tg_forced poiseuille periodic_cylinder channel_cylinder bstep rect_obstacle fill
# Default keeps runtime moderate and targets the 0140 population-support guard.
VALIDATION_TESTS=${VALIDATION_TESTS:-"tg_random poiseuille rect_obstacle fill"}

run_test() {
    local name=$1
    shift
    echo
    echo "[0141 suite] Running $name"
    "$@"
}

if [[ ! -x build/src_mpcd_base ]]; then
    ./scripts/build_src_mpcd_base.sh
fi

for test_name in $VALIDATION_TESTS; do
    case "$test_name" in
        tg_void)
            run_test tg_void ./scripts/run_taylor_green_void_rich_resampling_validation_0127.sh
            ;;
        tg_random)
            run_test tg_random ./scripts/run_taylor_green_random_population_resampling_validation_0128.sh
            ;;
        tg_forced)
            run_test tg_forced ./scripts/run_taylor_green_forced_random_population_resampling_validation_0130.sh
            ;;
        poiseuille)
            run_test poiseuille ./scripts/run_poiseuille_wallvp_resampling_validation_0131.sh
            ;;
        periodic_cylinder)
            run_test periodic_cylinder ./scripts/run_periodic_cylinder_resampling_validation_0134.sh
            ;;
        channel_cylinder)
            run_test channel_cylinder ./scripts/run_channel_cylinder_resampling_validation_0135.sh
            ;;
        bstep)
            run_test bstep ./scripts/run_backward_step_resampling_validation_0136.sh
            ;;
        rect_obstacle)
            run_test rect_obstacle ./scripts/run_open_channel_rect_obstacle_resampling_validation_0138b.sh
            ;;
        fill)
            run_test fill ./scripts/run_injection_fill_resampling_validation_0139.sh
            ;;
        *)
            echo "Unknown validation test '$test_name'" >&2
            exit 2
            ;;
    esac
done

echo
cat <<MSG
[0141 suite] Completed selected 0140 validation tests:
  $VALIDATION_TESTS

Each script writes to runs/*_0140 by default. Run the corresponding MATLAB analyzers manually, for example:
  cd matlab
  analyze_taylor_green_random_population_resampling_0128('../runs/taylor_green_random_population_resampling_0128_0140');
  analyze_poiseuille_wallvp_resampling_0131('../runs/poiseuille_wallvp_resampling_0131_0140');
  analyze_open_channel_rect_obstacle_resampling_0138b('../runs/open_channel_rect_obstacle_resampling_0138b_0140');
  analyze_injection_fill_resampling_0139('../runs/injection_fill_resampling_0139_0140');
MSG
