#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(".").resolve()
SRC = ROOT / "src/cuda_q6_resident_0400.cu"
if not SRC.exists():
    raise SystemExit(f"[0493x10h-patch] missing {SRC}")

text = SRC.read_text()

if "0493x10g-hierarchical-global-reduction-performance-only" not in text:
    raise SystemExit("[0493x10h-patch] x10g prerequisite not found")
if "0493x10h-mobile-interface-relative-thermal-retention" in text:
    raise SystemExit("[0493x10h-patch] x10h already appears applied")

def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"[0493x10h-patch] {label}: expected 1 anchor, found {n}")
    text = text.replace(old, new, 1)

# PASS 2: all non-donors belong to the receiver pool, including shell-side
# particles. Only g=(v-u_b).n>0 donors are kinetic escape candidates.
replace_once(
'''        if (!d.crossing) {
            // x10b: r=1 means an impermeable kinetic interface.  A particle
            // already on the pointwise outer side but still connected to a
            // direct bulk bath is reserved for hard positional recovery in
            // pass 3 and must not contaminate the reaction receiver pool.
            const bool hardShellCapture = reflectionFraction >= 1.0 && d.shellRecoverable;
            if (!hardShellCapture) {
                atomic_add_double_0400(&recvM[c], m);
                atomic_add_double_0400(&recvPx[c], m * vx);
                atomic_add_double_0400(&recvPy[c], m * vy);
                // Hard r=1 x10f reuses recvK as donor-H scratch below.
                // The global exact energy root does not need receiver K.
                // Preserve the historical receiver thermal accumulator only
                // for r<1 evaporation semantics.
                if (reflectionFraction < 1.0)
                    atomic_add_double_0400(&recvK[c], 0.5 * m * (vx * vx + vy * vy));
            }
            continue;
        }
''',
'''        if (!d.crossing) {
            // 0493x10h mobile-interface semantics:
            //
            // A particle is a kinetic donor only when its velocity is outward
            // RELATIVE to its local liquid bath, g=(v-u_b).n > 0.  A particle
            // that is not such a donor belongs to the receiver population even
            // when its pointwise position is temporarily on the alpha<0.5 side.
            //
            // alpha=0.5 is a reconstructed mobile free surface, not a material
            // wall.  Non-donor particles must be free to advect the interface
            // into vacuum (jet growth, ligament extension, spreading, splash).
            // Only thermal relative escape is reflected.
            atomic_add_double_0400(&recvM[c], m);
            atomic_add_double_0400(&recvPx[c], m * vx);
            atomic_add_double_0400(&recvPy[c], m * vy);
            // Hard r=1 x10f/x10g reuses recvK as donor-H scratch below.
            // The global exact energy root does not need receiver K.
            // Preserve the historical receiver thermal accumulator only for
            // r<1 evaporation semantics.
            if (reflectionFraction < 1.0)
                atomic_add_double_0400(&recvK[c], 0.5 * m * (vx * vx + vy * vy));
            continue;
        }
''',
"pass2 mobile receiver pool")

replace_once(
'''        if (!(gn > 0.0) || !isfinite(gn)) {
            // Already outside but naturally moving back toward the bulk.  In
            // hard-retention r=1 mode, pass 3 may still repair its endpoint if
            // it would remain outside; no velocity reflection is requested.
            return d;
        }
''',
'''        if (!(gn > 0.0) || !isfinite(gn)) {
            // Already pointwise outside, but not escaping thermally relative
            // to the local bath. x10h requests neither velocity reflection nor
            // positional recovery: this particle belongs to the advected
            // mobile-interface population and enters the receiver pool.
            return d;
        }
''',
"shell non-donor semantics")

# PASS 3 dispatch: keep x10g global reaction, remove universal containment.
replace_once(
'''        const bool hardR1Containment = reflectionFraction >= 1.0;
        const bool hardShellCapture = hardR1Containment && d.shellRecoverable;
        const bool donor = d.crossing && d.reflect;
        const bool globalReactionActive =
            hardR1Containment && globalReaction && globalReaction->active != 0;
        const bool receiver =
            !d.crossing && !hardShellCapture &&
            (hardR1Containment ? globalReactionActive
                               : (reactionActive[c] > 0.5));
        // x10c: in r=1 mode every phase-A particle reaches the final endpoint
        // barrier below, even if it was not a donor/receiver/shell candidate.
        // This closes two residual escape paths:
        //   (1) an endpoint-outside trajectory rejected by the old gn>0 gate;
        //   (2) a receiver whose velocity becomes outward only after the x9z
        //       affine reaction has been applied in this same pass.
        if (!donor && !receiver && !hardShellCapture && !hardR1Containment) continue;
''',
'''        const bool hardR1Reaction = reflectionFraction >= 1.0;
        const bool donor = d.crossing && d.reflect;
        // x10h positional recovery is SELECTIVE: an already-outer shell
        // particle is sealed only when it is itself a reflected thermal donor.
        // Non-donor shell particles remain mobile and are ordinary receivers.
        const bool selectiveShellDonorSeal = hardR1Reaction && donor && d.shellRecoverable;
        const bool globalReactionActive =
            hardR1Reaction && globalReaction && globalReaction->active != 0;
        const bool receiver =
            !d.crossing &&
            (hardR1Reaction ? globalReactionActive
                            : (reactionActive[c] > 0.5));

        // No x10c/x10e universal endpoint barrier in x10h.
        if (!donor && !receiver) continue;
''',
"pass3 mobile-interface dispatch")

# The first two hard-r1 branches are the donor scale and receiver global du.
text = text.replace("if (hardR1Containment) {", "if (hardR1Reaction) {", 2)
if text.count("hardR1Containment") != 1:
    raise SystemExit(
        f"[0493x10h-patch] unexpected hardR1Containment count before "
        f"barrier removal: {text.count('hardR1Containment')}")

# x10b geometry becomes donor-only.
replace_once(
'''        // 0493x10b hard bulk retention for r=1 only.
        //
        // A shell particle is pointwise alpha(x0)<0.5 but has a direct bulk
        // bath.  After any donor velocity reflection above, first let it return
        // naturally if its ordinary streamed endpoint is already inside.  If
        // not, bracket alpha=0.5 on the short segment from that endpoint to the
        // direct bulk-cell centre, then mirror the endpoint to the interior
        // side.  This changes position only and intentionally leaves the x9z
        // impulse/energy reaction untouched for later work.
        if (hardShellCapture) {
''',
'''        // 0493x10h selective shell DONOR seal.
        //
        // This is no longer a general hard-retention mechanism. It runs only
        // for an already-outer shell particle that has independently satisfied
        // the relative thermal donor gate and has been selected for reflection.
        // Non-donor shell particles are never position-corrected here.
        if (selectiveShellDonorSeal) {
''',
"shell donor-only seal")

# Remove x10c/x10e universal endpoint barrier from the hot path.
start_marker = '''        // -----------------------------------------------------------------
        // 0493x10c — final r=1 endpoint barrier.
'''
end_marker = '''        particles.vx[i] = newVx;
        particles.vy[i] = newVy;
'''
s = text.find(start_marker)
e = text.find(end_marker, s)
if s < 0 or e < 0:
    raise SystemExit("[0493x10h-patch] universal endpoint barrier range not found")

text = (
    text[:s]
    + '''        // 0493x10h: no universal alpha(x_final)>=0.5 barrier.
        //
        // The current alpha=0.5 is allowed to move with the liquid. Only
        // actual relative-outward reflected donors receive positional sealing
        // (x10a interior donor seal or the selective shell donor seal above).
        // x10g exact global P/E reaction remains unchanged.

'''
    + text[e:]
)

if "hardR1Containment" in text:
    raise SystemExit("[0493x10h-patch] stale hardR1Containment remains")

replace_once(
'''           "interior-reflected-endpoint-alpha-ge-half-seal;"
           "r1-shell-hard-retention-direct-bulk-mirror;"
           "r1-final-post-velocity-endpoint-barrier-radius2-local-anchor;"
           "r1-final-endpoint-tangent-mirror-no-interface-clamp;"
           "r1-global-single-component-reservoir-ablation;"
           "0493x10g-hierarchical-global-reduction-performance-only;"
''',
'''           "interior-reflected-endpoint-alpha-ge-half-seal;"
           "r1-shell-position-seal-reflected-donors-only;"
           "r1-no-universal-alpha-endpoint-barrier;"
           "r1-mobile-interface-relative-thermal-donor-only-retention;"
           "r1-global-single-component-reservoir-ablation;"
           "0493x10g-hierarchical-global-reduction-performance-only;"
           "0493x10h-mobile-interface-relative-thermal-retention;"
''',
"contract tag")

SRC.write_text(text)

# Static-drop qualification runner.
run = ROOT / "scripts/run_0493x10h_mobile_interface_drop.sh"
run.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export TARGET=wall
export RUN_ROOT="${RUN_ROOT:-runs/0493x10h_mobile_interface_drop}"
export GAMMA="${GAMMA:-20}"
export DT="${DT:-0.002}"
export KBT="${KBT:-0.125}"
export LIQUID_MASS="${LIQUID_MASS:-1.0}"
export ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
export RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
export GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
export THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
export THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
export THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
export THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
export THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
export SIGMA_ACTIVE="${SIGMA_ACTIVE:-9450.0}"
export SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"
export KINETIC_REFLECTION_FRACTION="${KINETIC_REFLECTION_FRACTION:-1.0}"
export EVAPORATION_TARGET_TYPE="${EVAPORATION_TARGET_TYPE:--1}"
export DROP_RADIUS_CELLS="${DROP_RADIUS_CELLS:-40}"
export DROP_CENTER_X="${DROP_CENTER_X:-1.5625}"
export DROP_CENTER_Y="${DROP_CENTER_Y:-0.78125}"
export DROP_VX="${DROP_VX:-0.0}"
export DROP_VY="${DROP_VY:-0.0}"
export GRAVITY_Y="${GRAVITY_Y:-0.0}"
export STEPS="${STEPS:-800}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-25}"
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

if [[ "$KINETIC_REFLECTION_FRACTION" != "1" && "$KINETIC_REFLECTION_FRACTION" != "1.0" ]]; then
  echo "[0493x10h-suite] ERROR qualification intentionally restricted to r=1" >&2
  exit 2
fi

printf '%s\n' \
  "[0493x10h-suite] MOBILE FREE SURFACE: reflect relative thermal donors, not interface advection" \
  "[0493x10h-suite] x10g exact global P/E reaction + hierarchical reduction retained" \
  "[0493x10h-suite] x10a interior donor seal retained; shell position seal now donor-only" \
  "[0493x10h-suite] x10b general shell recovery DISABLED; x10c/x10e universal endpoint barrier DISABLED" \
  "[0493x10h-suite] no new particle pass; no merge/resampling" \
  "[0493x10h-suite] kBT=$KBT r=$KINETIC_REFLECTION_FRACTION LiveVis=$LIVE_VIS_ENABLE filteredRecording=$FILTERED_RECORDING_ENABLE"

bash scripts/run_0493x9s_splash.sh

CSV="$RUN_ROOT/output/cuda_phase_kinetic_crossing_0493x9z.csv"
[[ -f "$CSV" ]] || { echo "[0493x10h-suite] ERROR missing $CSV" >&2; exit 2; }

python3 scripts/analyze_0493x10h_mobile_interface.py "$CSV"
''')
run.chmod(0o755)

an = ROOT / "scripts/analyze_0493x10h_mobile_interface.py"
an.write_text(r'''#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        "usage: analyze_0493x10h_mobile_interface.py "
        "<cuda_phase_kinetic_crossing_0493x9z.csv>")

p = Path(sys.argv[1])
with p.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("[0493x10h-check] ERROR empty CSV")

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def S(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)

hard_checks = S("hardFinalEndpointChecks")
hard_corr = S("hardFinalEndpointCorrections")
hard_miss = S("hardFinalLocalAnchorMisses")

interior = S("interiorCrossings")
shell_cross = S("shellGuardCrossings")
shell_recoverable = S("shellRecoverableParticles")
shell_seal_candidates = S("shellHardRetentionCandidates")
interior_final_out = S("appliedInteriorFinalOutside")
shell_final_out = S("shellHardRetentionFinalOutside")

deep = [I(r,"deepOuterParticles") for r in rows]
outer = [I(r,"phaseAOuterCellParticles") for r in rows]
shell = [I(r,"shellParticles") for r in rows]

active = S("globalReactionActive")
trivial = S("globalReactionTrivial")
invalid = S("globalReactionInvalid")
scales = [F(r,"globalReactionScale") for r in rows if I(r,"globalReactionActive")]

dp = max(maxabs("deltaPx"), maxabs("deltaPy"))
de = maxabs("deltaKineticEnergy")
formula = maxabs("globalReactionFormulaResidual")

print("===== 0493x10h MOBILE INTERFACE / RELATIVE THERMAL RETENTION =====")
print(f"file={p} rows={len(rows)} lastStep={rows[-1].get('step','?')}")
print("--- interface mobility contract ---")
print(f"universalHardBarrier checks={hard_checks} corrections={hard_corr} anchorMisses={hard_miss}")
print(f"interiorDonorCrossings={interior} interiorDonorFinalOutside={interior_final_out}")
print(f"shellDonorCrossings={shell_cross} selectiveShellSealCandidates={shell_seal_candidates} "
      f"shellDonorFinalOutside={shell_final_out}")
print(f"shellRecoverable(all)={shell_recoverable} "
      f"nonDonorShellFreeApprox={max(0, shell_recoverable-shell_seal_candidates)}")
print("--- halo / reconstructed-alpha context ---")
print(f"outer first={outer[0]} max={max(outer)} last={outer[-1]}")
print(f"shell first={shell[0]} max={max(shell)} last={shell[-1]}")
print(f"deepOuter first={deep[0]} max={max(deep)} last={deep[-1]}")
print("--- x10g global exact reaction retained ---")
print(f"active={active} trivial={trivial} invalid={invalid}")
if scales:
    print(f"scale a last={scales[-1]:.9g} min={min(scales):.9g} "
          f"max={max(scales):.9g} mean={sum(scales)/len(scales):.9g}")
print(f"max|deltaP|={dp:.12e}")
print(f"max|deltaKE|={de:.12e}")
print(f"max|analyticResidual|={formula:.12e}")

mobile = (
    hard_checks == 0 and hard_corr == 0 and hard_miss == 0 and
    shell_seal_candidates == shell_cross
)
donor_seal = (interior_final_out == 0 and shell_final_out == 0)
cons = (dp < 1e-9 and de < 1e-9 and formula < 1e-9)
glob = (active > 0 and invalid == 0)

print("mobileInterfaceContract=" + ("PASS" if mobile else "FAIL"))
print("thermalDonorSealContract=" + ("PASS" if donor_seal else "FAIL"))
print("conservationContract=" + ("PASS" if cons else "FAIL"))
print("globalReservoirContract=" + ("PASS" if glob else "FAIL"))
print("antiEvaporationOutcome=VISUAL_AND_HALO_REVIEW")
print("shapeContract=VISUAL_PENDING")
print("multiComponentContract=NOT_APPLICABLE_ABLATION_ONLY")
''')
an.chmod(0o755)

chk = ROOT / "scripts/check_0493x10h_mobile_interface_math.py"
chk.write_text(r'''#!/usr/bin/env python3
# 1D normal sanity check. n points from liquid to vacuum.
# v = U + c. The donor gate uses g=c, not absolute v.
U = 0.04
thermal = [-0.03, -0.01, 0.01, 0.03]

free_absolute_outward = 0
reflected_donors = 0
for c in thermal:
    v = U + c
    g = c
    if g > 0:
        v2 = v - 2.0*g
        assert abs(v2 - (U-c)) < 1e-15
        reflected_donors += 1
    else:
        if v > 0:
            free_absolute_outward += 1

if free_absolute_outward == 0:
    raise SystemExit("FAIL: relative gate still pins translating interface")
if reflected_donors == 0:
    raise SystemExit("FAIL: no thermal donors reflected")

print(f"bulkNormalVelocity={U}")
print(f"freeAbsoluteOutwardNonDonors={free_absolute_outward}")
print(f"reflectedRelativeThermalDonors={reflected_donors}")
print("status=PASS")
''')
chk.chmod(0o755)

base_drip = ROOT / "scripts/run_0493x10g_dripping_vk_validation.sh"
if base_drip.exists():
    drip = ROOT / "scripts/run_0493x10h_dripping_vk_validation.sh"
    drip.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

export RUN_ROOT="${RUN_ROOT:-runs/0493x10h_dripping_vk_validation}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"

printf '%s\n' \
  "[0493x10h-drip] VK dripping capability with MOBILE interface semantics" \
  "[0493x10h-drip] non-donor liquid may advance alpha into vacuum; relative thermal donors are reflected" \
  "[0493x10h-drip] x10g global single-component reservoir still limits interpretation after pinch-off"

bash scripts/run_0493x10g_dripping_vk_validation.sh
''')
    drip.chmod(0o755)
    print("[0493x10h-patch] wrote scripts/run_0493x10h_dripping_vk_validation.sh")
else:
    print("[0493x10h-patch] note: x10g dripping VK runner not present; no wrapper written")

print("[0493x10h-patch] patched src/cuda_q6_resident_0400.cu")
print("[0493x10h-patch] wrote scripts/run_0493x10h_mobile_interface_drop.sh")
print("[0493x10h-patch] wrote scripts/analyze_0493x10h_mobile_interface.py")
print("[0493x10h-patch] wrote scripts/check_0493x10h_mobile_interface_math.py")
print("[0493x10h-patch] x10g global P/E reaction and hierarchical reduction unchanged")
