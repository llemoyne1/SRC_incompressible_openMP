#!/usr/bin/env bash
# Shared qualified free-surface profile for run_ok liquid demonstrations.
#
# Reference: tag surf-tension-qualified-x13h-20260831, commit 7655b81.
# Active chain when RUN_OK_LIQUID_SURFACE_ENABLE=1:
#   x10o + CIC + true-Q2 + x10p/x10q + x10u + x10v full-vector swap + x12a
# together with x9 surface tension in the Q6-g-f pressure boundary condition.
#
# This file is a shell function library.  Callers must already source
# scripts/src_mpcd_run_common_0434.sh.

run_ok_liquid_surface_enabled_0493x13zg() {
  suite_truthy_0434 "${RUN_OK_LIQUID_SURFACE_ENABLE:-1}"
}

run_ok_liquid_surface_defaults_0493x13zg() {
  local kbt=${1:?0493x13zg requires KBT}

  RUN_OK_LIQUID_SURFACE_ENABLE="${RUN_OK_LIQUID_SURFACE_ENABLE:-1}"
  RUN_OK_LIQUID_SURFACE_SIGMA="${RUN_OK_LIQUID_SURFACE_SIGMA:-9450.0}"
  RUN_OK_LIQUID_SURFACE_MIN_RADIUS_CELLS="${RUN_OK_LIQUID_SURFACE_MIN_RADIUS_CELLS:-4}"
  RUN_OK_LIQUID_SURFACE_KINETIC_REFLECTION_FRACTION="${RUN_OK_LIQUID_SURFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
  RUN_OK_LIQUID_SURFACE_EVAPORATION_TARGET_TYPE="${RUN_OK_LIQUID_SURFACE_EVAPORATION_TARGET_TYPE:--1}"
  # Wetting remains less mature than the bulk free-surface closure.  Keep it
  # disabled by default rather than silently imposing a 90-degree contact law.
  RUN_OK_LIQUID_SURFACE_CONTACT_ANGLE_DEG="${RUN_OK_LIQUID_SURFACE_CONTACT_ANGLE_DEG:--1}"
  RUN_OK_LIQUID_SURFACE_X10O_THERMAL_SIGMAS="${RUN_OK_LIQUID_SURFACE_X10O_THERMAL_SIGMAS:-3.0}"
  RUN_OK_LIQUID_SURFACE_X10O_THERMAL_MAX_CELLS="${RUN_OK_LIQUID_SURFACE_X10O_THERMAL_MAX_CELLS:-0.75}"
  RUN_OK_LIQUID_SURFACE_X12A_RADIUS_CELLS="${RUN_OK_LIQUID_SURFACE_X12A_RADIUS_CELLS:-25.298221281347036}"

  if run_ok_liquid_surface_enabled_0493x13zg; then
    # x12a acts through the every-step relative-cell thermostat.  These are
    # part of the qualified surface profile, not optional inherited shell state.
    THERMOSTAT_ENABLE=true
    THERMOSTAT_MODE=cell_relative_rescale
    THERMOSTAT_EVERY=1
    THERMOSTAT_TARGET_KBT="$kbt"

    # The qualified x13h surface chain was established without particle
    # resampling/refill/virial fallbacks.  Hard segmented inlet activation is
    # independent of these resampling mechanisms and remains available.
    SPECIES_RESAMPLING_ENABLE=false
    LIQUID_RESAMPLING_ENABLE=false
    GAS_RESAMPLING_ENABLE=false
    MASS_RECONDITION_ENABLE=0
    RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
    RESAMPLING_MASS_GUARD_ENABLE=false
    WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
    CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
    VIRIAL_DENSITY_KICK_ENABLE=false
  fi
}

run_ok_liquid_surface_require_mode_0493x13zg() {
  local mode=${1:?0493x13zg requires mode}
  if run_ok_liquid_surface_enabled_0493x13zg && [[ "$mode" != "src-q6-g-f" ]]; then
    echo "[0493x13zg-run-ok] ERROR complete-liquid surface profile requires mode=src-q6-g-f; got '$mode'" >&2
    echo "[0493x13zg-run-ok] set RUN_OK_LIQUID_SURFACE_ENABLE=0 to recover the historical non-capillary comparison paths" >&2
    return 2
  fi
}

run_ok_liquid_surface_validate_interface_0493x13zg() {
  local mode=${1:?} phase_a=${2:?} phase_b=${3:?} liquid_mass=${4:?}
  run_ok_liquid_surface_require_mode_0493x13zg "$mode" || return $?
  if ! run_ok_liquid_surface_enabled_0493x13zg; then
    return 0
  fi

  python3 - \
    "$RUN_OK_LIQUID_SURFACE_SIGMA" \
    "$RUN_OK_LIQUID_SURFACE_MIN_RADIUS_CELLS" \
    "$RUN_OK_LIQUID_SURFACE_KINETIC_REFLECTION_FRACTION" \
    "$RUN_OK_LIQUID_SURFACE_X12A_RADIUS_CELLS" \
    "$liquid_mass" <<'PY'
import math, sys
sigma, rmin, refl, rc, mass = map(float, sys.argv[1:])
if not (math.isfinite(sigma) and sigma > 0.0):
    raise SystemExit('[0493x13zg-run-ok] surface sigma must be finite and >0')
if not (math.isfinite(rmin) and rmin >= 0.0):
    raise SystemExit('[0493x13zg-run-ok] surface min-radius cells must be finite and >=0')
if not (math.isfinite(refl) and abs(refl-1.0) <= 1e-12):
    raise SystemExit('[0493x13zg-run-ok] qualified x10u/x10v path requires hard reflection fraction=1')
if not (math.isfinite(rc) and rc > 0.0):
    raise SystemExit('[0493x13zg-run-ok] x12a radius must be finite and >0')
if not (math.isfinite(mass) and mass > 0.0):
    raise SystemExit('[0493x13zg-run-ok] phase-A liquid particle mass must be finite and >0')
PY

  [[ "$phase_a" == type:* ]] || {
    echo "[0493x13zg-run-ok] ERROR phase-A selector must be a concrete liquid type, got '$phase_a'" >&2
    return 2
  }
  case "$phase_b" in
    vacuum|type:*) ;;
    *) echo "[0493x13zg-run-ok] ERROR phase-B selector must be vacuum or type:<id>, got '$phase_b'" >&2; return 2 ;;
  esac
}

run_ok_liquid_surface_append_params_0493x13zg() {
  local params=${1:?} mode=${2:?} phase_a=${3:?} phase_b=${4:?}
  local sigma=0 rmin=0 reflection=0 contact=-1 evaporation=-1
  if run_ok_liquid_surface_enabled_0493x13zg; then
    sigma="$RUN_OK_LIQUID_SURFACE_SIGMA"
    rmin="$RUN_OK_LIQUID_SURFACE_MIN_RADIUS_CELLS"
    reflection="$RUN_OK_LIQUID_SURFACE_KINETIC_REFLECTION_FRACTION"
    contact="$RUN_OK_LIQUID_SURFACE_CONTACT_ANGLE_DEG"
    evaporation="$RUN_OK_LIQUID_SURFACE_EVAPORATION_TARGET_TYPE"
  fi
  cat >> "$params" <<PARAMS_0493X13ZG
surfaceTensionSigma = $sigma
surfaceTensionMinRadiusCells = $rmin
phaseInterfaceKineticReflectionFraction = $reflection
phaseInterfaceEvaporationTargetType = $evaporation
phaseInterfaceASelector = $phase_a
phaseInterfaceBSelector = $phase_b
phaseInterfaceContactAngleDegrees = $contact
PARAMS_0493X13ZG
}

run_ok_liquid_surface_export_flags_0493x13zg() {
  local mode=${1:?} liquid_mass=${2:?}
  run_ok_liquid_surface_require_mode_0493x13zg "$mode" || return $?

  if run_ok_liquid_surface_enabled_0493x13zg; then
    export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
    export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
    export MPCD_X10M_MOVING_INTERFACE_WALL=0
    export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
    export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
    export MPCD_X10O_THERMAL_PARTICLE_MASS="$liquid_mass"
    export MPCD_X10O_THERMAL_SIGMAS="$RUN_OK_LIQUID_SURFACE_X10O_THERMAL_SIGMAS"
    export MPCD_X10O_THERMAL_MAX_CELLS="$RUN_OK_LIQUID_SURFACE_X10O_THERMAL_MAX_CELLS"
    export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=0
    export MPCD_X10_KINETIC_INTERFACE_CIC=1
    export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
    export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
    export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
    export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
    export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
    export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
    export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
    export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
    export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
    export MPCD_X12A_LOCAL_THERMAL_COOLING=1
    export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$RUN_OK_LIQUID_SURFACE_X12A_RADIUS_CELLS"
  else
    # Exact no-op fallback for the older comparison runners.  Clear every gate
    # owned by this helper so an inherited shell experiment cannot leak in.
    export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
    export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
    export MPCD_X10M_MOVING_INTERFACE_WALL=0
    export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
    export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=0
    export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=0
    export MPCD_X10_KINETIC_INTERFACE_CIC=0
    export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=0
    export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=0
    export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=0
    export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=0
    export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
    export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
    export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
    export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
    export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
    export MPCD_X12A_LOCAL_THERMAL_COOLING=0
  fi
}

run_ok_liquid_surface_append_env_0493x13zg() {
  local file=${1:?} mode=${2:?} phase_a=${3:?} phase_b=${4:?}
  [[ -f "$file" ]] || return 0
  cat >> "$file" <<META_0493X13ZG
RUN_OK_LIQUID_SURFACE_PROFILE=0493x13zg_7655b81
RUN_OK_LIQUID_SURFACE_ENABLE=${RUN_OK_LIQUID_SURFACE_ENABLE}
RUN_OK_LIQUID_SURFACE_REFERENCE_TAG=surf-tension-qualified-x13h-20260831
RUN_OK_LIQUID_SURFACE_MODE=${mode}
RUN_OK_LIQUID_SURFACE_SIGMA=${RUN_OK_LIQUID_SURFACE_SIGMA}
RUN_OK_LIQUID_SURFACE_MIN_RADIUS_CELLS=${RUN_OK_LIQUID_SURFACE_MIN_RADIUS_CELLS}
RUN_OK_LIQUID_SURFACE_PHASE_A=${phase_a}
RUN_OK_LIQUID_SURFACE_PHASE_B=${phase_b}
RUN_OK_LIQUID_SURFACE_REFLECTION=${RUN_OK_LIQUID_SURFACE_KINETIC_REFLECTION_FRACTION}
RUN_OK_LIQUID_SURFACE_CONTACT_ANGLE_DEG=${RUN_OK_LIQUID_SURFACE_CONTACT_ANGLE_DEG}
RUN_OK_LIQUID_SURFACE_X12A_RADIUS_CELLS=${RUN_OK_LIQUID_SURFACE_X12A_RADIUS_CELLS}
RUN_OK_LIQUID_SURFACE_CHAIN=x9-sigma-kappa+x10o+CIC+Q2+x10p/q+x10u+x10v-full-vector+x12a
META_0493X13ZG
}

run_ok_liquid_surface_print_0493x13zg() {
  local mode=${1:?} phase_a=${2:?} phase_b=${3:?}
  if run_ok_liquid_surface_enabled_0493x13zg; then
    printf '%s\n' \
      "[0493x13zg-run-ok] complete-liquid surface profile=ON mode=$mode" \
      "[0493x13zg-run-ok] reference=surf-tension-qualified-x13h-20260831" \
      "[0493x13zg-run-ok] interface A=$phase_a B=$phase_b sigma=$RUN_OK_LIQUID_SURFACE_SIGMA rmin/h=$RUN_OK_LIQUID_SURFACE_MIN_RADIUS_CELLS contact=$RUN_OK_LIQUID_SURFACE_CONTACT_ANGLE_DEG" \
      "[0493x13zg-run-ok] chain=x9 sigma*kappa + x10o+CIC+Q2+x10p/q+x10u+x10v-full-vector+x12a Rc/h=$RUN_OK_LIQUID_SURFACE_X12A_RADIUS_CELLS"
  else
    echo "[0493x13zg-run-ok] complete-liquid surface profile=OFF (historical hydrodynamic comparison path)"
  fi
}
