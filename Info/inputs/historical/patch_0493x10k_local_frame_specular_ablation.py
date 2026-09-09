#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.').resolve()
SRC = ROOT / 'src/cuda_q6_resident_0400.cu'
if not SRC.exists():
    raise SystemExit(f'[0493x10k-patch] missing {SRC}')

text = SRC.read_text()

if '0493x10j-simple-lab-specular-ablation' not in text:
    raise SystemExit('[0493x10k-patch] prerequisite not found: 0493x10j-simple-lab-specular-ablation')
if '0493x10k-local-frame-specular-ablation' in text:
    raise SystemExit('[0493x10k-patch] x10k already appears applied')


def replace_once(old: str, new: str, label: str):
    global text
    n = text.count(old)
    if n != 1:
        raise SystemExit(f'[0493x10k-patch] {label}: expected 1 anchor, found {n}')
    text = text.replace(old, new, 1)


def replace_span(start: str, end: str, new: str, label: str):
    global text
    i = text.find(start)
    if i < 0:
        raise SystemExit(f'[0493x10k-patch] {label}: start anchor not found')
    j = text.find(end, i)
    if j < 0:
        raise SystemExit(f'[0493x10k-patch] {label}: end anchor not found')
    text = text[:i] + new + text[j:]


# ---------------------------------------------------------------------------
# x10k audit: local-frame reflection preserves |v-u_b|, not |v| in the lab.
# The interface counter-impulse remains deliberately ignored in this ablation.
# ---------------------------------------------------------------------------
replace_once(
'''    double simpleSpecularPositionShiftAbsSum = 0.0;
};
''',
'''    double simpleSpecularPositionShiftAbsSum = 0.0;

    // 0493x10k local-liquid-frame specular ablation.
    unsigned long long localFrameSpecularReflections = 0ull;
    unsigned long long localFrameInteriorCollisions = 0ull;
    unsigned long long localFrameShellReflections = 0ull;
    unsigned long long localFrameRelativeStillOutward = 0ull;
    unsigned long long localFrameInteriorEndpointOuter = 0ull;
    unsigned long long localFrameShellEndpointOuter = 0ull;
    double localFrameRelativeSpeedSqAbsErrorSum = 0.0;
    double localFrameRelativeSpeedSqReferenceSum = 0.0;
    double localFrameLabSpeedSqChangeSum = 0.0;
    double localFrameLabSpeedSqAbsChangeSum = 0.0;
    double localFramePositionShiftAbsSum = 0.0;
};
''',
'audit x10k fields')

# Kernel receives both ablation modes. x10k takes precedence on the host.
replace_once(
'''    int mesoBlocksX,
    int simpleSpecularAblation,
    std::uint32_t phaseAType,
''',
'''    int mesoBlocksX,
    int simpleSpecularAblation,
    int localFrameSpecularAblation,
    std::uint32_t phaseAType,
''',
'apply kernel local-frame flag')

# Reconstruct common crossing/halo audit in either simple-ablation mode.
replace_once(
'''        if (simpleSpecularAblation && audit) {
''',
'''        if ((simpleSpecularAblation || localFrameSpecularAblation) && audit) {
''',
'common simple audit gate')

replace_once(
'''        const bool hardR1Reaction = reflectionFraction >= 1.0;
        const bool simpleSpecular = simpleSpecularAblation && hardR1Reaction;
        const bool donor = d.crossing && d.reflect;
''',
'''        const bool hardR1Reaction = reflectionFraction >= 1.0;
        const bool localFrameSpecular =
            localFrameSpecularAblation && hardR1Reaction;
        const bool simpleSpecular =
            (simpleSpecularAblation || localFrameSpecularAblation) &&
            hardR1Reaction;
        const bool donor = d.crossing && d.reflect;
''',
'local/simple mode bools')

# Replace only the x10j simple branch. Shared remaining-time collision geometry
# is retained; x10k changes only the reflection frame and the diagnostics.
start = '''            if (simpleSpecular) {
                // 0493x10j SIMPLE ABLATION:
'''
end = '''            } else {
                // x10d hard-r1 mode replaces fixed specular factor 2 by the
'''
new = r'''            if (simpleSpecular) {
                // 0493x10j/x10k SIMPLE ABLATIONS.
                // x10j: laboratory-frame specular reflection.
                // x10k: local-liquid-frame specular reflection
                //       v' = v - 2[(v-u_b).n] n.
                // Both deliberately ignore the interface counter-impulse and
                // bypass all B8/global receiver machinery.
                if (localFrameSpecular) {
                    const double relVxBefore = oldVx - ubx;
                    const double relVyBefore = oldVy - uby;
                    const double relSpeedSqBefore =
                        relVxBefore * relVxBefore + relVyBefore * relVyBefore;
                    const double labSpeedSqBefore =
                        oldVx * oldVx + oldVy * oldVy;

                    // gn was already evaluated from the same bath velocity and
                    // pointwise interface normal and is strictly > 0 here.
                    newVx = oldVx - 2.0 * gn * d.nx;
                    newVy = oldVy - 2.0 * gn * d.ny;

                    const double relVxAfter = newVx - ubx;
                    const double relVyAfter = newVy - uby;
                    const double relSpeedSqAfter =
                        relVxAfter * relVxAfter + relVyAfter * relVyAfter;
                    const double gnAfter =
                        relVxAfter * d.nx + relVyAfter * d.ny;
                    const double labSpeedSqAfter =
                        newVx * newVx + newVy * newVy;

                    if (audit) {
                        atomicAdd(&audit->localFrameSpecularReflections, 1ull);
                        const double tolGn =
                            1.0e-12 * fmax(1.0, fabs(gn));
                        if (!(gnAfter < tolGn) || !isfinite(gnAfter))
                            atomicAdd(
                                &audit->localFrameRelativeStillOutward, 1ull);
                        atomic_add_double_0400(
                            &audit->localFrameRelativeSpeedSqAbsErrorSum,
                            fabs(relSpeedSqAfter - relSpeedSqBefore));
                        atomic_add_double_0400(
                            &audit->localFrameRelativeSpeedSqReferenceSum,
                            fabs(relSpeedSqBefore));
                        const double labDelta =
                            labSpeedSqAfter - labSpeedSqBefore;
                        atomic_add_double_0400(
                            &audit->localFrameLabSpeedSqChangeSum, labDelta);
                        atomic_add_double_0400(
                            &audit->localFrameLabSpeedSqAbsChangeSum,
                            fabs(labDelta));
                    }
                } else {
                    // 0493x10j laboratory-frame control ablation:
                    //   v' = v - 2(v.n)n
                    const double vnLab = oldVx * d.nx + oldVy * d.ny;
                    const double speedSqBefore =
                        oldVx * oldVx + oldVy * oldVy;
                    newVx = oldVx - 2.0 * vnLab * d.nx;
                    newVy = oldVy - 2.0 * vnLab * d.ny;
                    const double speedSqAfter =
                        newVx * newVx + newVy * newVy;

                    if (audit) {
                        atomicAdd(&audit->simpleSpecularReflections, 1ull);
                        if (!(vnLab > 0.0) || !isfinite(vnLab))
                            atomicAdd(
                                &audit->simpleSpecularNonPositiveLabNormal,
                                1ull);
                        atomic_add_double_0400(
                            &audit->simpleSpecularSpeedSqAbsErrorSum,
                            fabs(speedSqAfter - speedSqBefore));
                        atomic_add_double_0400(
                            &audit->simpleSpecularSpeedSqReferenceSum,
                            fabs(speedSqBefore));
                    }
                }

                if (d.interiorCrossing) {
                    // Standard remaining-time collision kinematics.  There is
                    // deliberately NO alpha endpoint seal: an interface moving
                    // with the local liquid may legitimately leave the final
                    // particle position on the outer side of the old alpha=.5.
                    const double x0p = particles.x[i];
                    const double y0p = particles.y[i];
                    const double s = fmin(fmax(d.crossingFraction, 0.0), 1.0);
                    const double xInside = x0p + s * oldVx * dt;
                    const double yInside = y0p + s * oldVy * dt;
                    const double xTarget = xInside + (1.0 - s) * newVx * dt;
                    const double yTarget = yInside + (1.0 - s) * newVy * dt;
                    const double corrX = xTarget - newVx * dt - x0p;
                    const double corrY = yTarget - newVy * dt - y0p;
                    particles.x[i] = x0p + corrX;
                    particles.y[i] = y0p + corrY;

                    if (audit) {
                        double aFinal = 0.0;
                        const bool finalOuter =
                            !q6_x9t_sample_alpha(
                                alpha,
                                particles.x[i] + newVx * dt,
                                particles.y[i] + newVy * dt,
                                nx, ny, lx, ly,
                                periodicX, periodicY, &aFinal) ||
                            !(aFinal >= 0.5);
                        const double shiftAbs =
                            sqrt(corrX * corrX + corrY * corrY);
                        if (localFrameSpecular) {
                            atomicAdd(
                                &audit->localFrameInteriorCollisions, 1ull);
                            atomic_add_double_0400(
                                &audit->localFramePositionShiftAbsSum,
                                shiftAbs);
                            if (finalOuter)
                                atomicAdd(
                                    &audit->localFrameInteriorEndpointOuter,
                                    1ull);
                        } else {
                            atomicAdd(
                                &audit->simpleSpecularInteriorCollisions, 1ull);
                            atomic_add_double_0400(
                                &audit->simpleSpecularPositionShiftAbsSum,
                                shiftAbs);
                            if (finalOuter)
                                atomicAdd(
                                    &audit->simpleSpecularInteriorFinalOutside,
                                    1ull);
                        }
                    }
                } else if (d.shellGuard) {
                    // Shell donors get only the velocity reflection; there is
                    // no positional recovery in either simple ablation.
                    if (audit) {
                        double aFinal = 0.0;
                        const bool finalOuter =
                            !q6_x9t_sample_alpha(
                                alpha,
                                particles.x[i] + newVx * dt,
                                particles.y[i] + newVy * dt,
                                nx, ny, lx, ly,
                                periodicX, periodicY, &aFinal) ||
                            !(aFinal >= 0.5);
                        if (localFrameSpecular) {
                            atomicAdd(
                                &audit->localFrameShellReflections, 1ull);
                            if (finalOuter)
                                atomicAdd(
                                    &audit->localFrameShellEndpointOuter, 1ull);
                        } else {
                            atomicAdd(
                                &audit->simpleSpecularShellReflections, 1ull);
                            if (finalOuter)
                                atomicAdd(
                                    &audit->simpleSpecularShellFinalOutside,
                                    1ull);
                        }
                    }
                }
'''
replace_span(start, end, new, 'replace simple specular branch with local-frame option')

# ---------------------------------------------------------------------------
# Host orchestration. x10k takes precedence if both flags are accidentally set.
# Both simple modes skip classification/reaction/B8 and retain only total bath
# moments plus the apply pass.
# ---------------------------------------------------------------------------
replace_once(
'''    const bool simpleSpecularAblation =
        r >= 1.0 &&
        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;
''',
'''    const bool localFrameSpecularAblation =
        r >= 1.0 &&
        env_int_0400("MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION", 0) != 0;
    const bool simpleSpecularAblation =
        !localFrameSpecularAblation && r >= 1.0 &&
        env_int_0400("MPCD_X10J_SIMPLE_SPECULAR_ABLATION", 0) != 0;
    const bool anySimpleSpecularAblation =
        simpleSpecularAblation || localFrameSpecularAblation;
''',
'host x10k runtime flag')

replace_once(
'''    const int mesoReservoirs = simpleSpecularAblation
        ? 1 : mesoBlocksX * mesoBlocksY;
''',
'''    const int mesoReservoirs = anySimpleSpecularAblation
        ? 1 : mesoBlocksX * mesoBlocksY;
''',
'avoid meso allocation in x10k')

# There are exactly two host-side guards in x10j: classification and reaction.
count = text.count('    if (!simpleSpecularAblation) {\n')
if count != 2:
    raise SystemExit(
        f'[0493x10k-patch] expected 2 x10j host guards, found {count}')
text = text.replace(
    '    if (!simpleSpecularAblation) {\n',
    '    if (!anySimpleSpecularAblation) {\n',
    2)

replace_once(
'''        mesoBlocksX,
        simpleSpecularAblation ? 1 : 0,
        phaseAType,
''',
'''        mesoBlocksX,
        simpleSpecularAblation ? 1 : 0,
        localFrameSpecularAblation ? 1 : 0,
        phaseAType,
''',
'pass x10k flag to apply kernel')

# ---------------------------------------------------------------------------
# CSV diagnostics and contract tag.
# ---------------------------------------------------------------------------
replace_once(
'''               "simpleSpecularSpeedSqAbsErrorSum,simpleSpecularSpeedSqReferenceSum,"
               "simpleSpecularPositionShiftAbsSum,"
               "contract\\n";
''',
'''               "simpleSpecularSpeedSqAbsErrorSum,simpleSpecularSpeedSqReferenceSum,"
               "simpleSpecularPositionShiftAbsSum,"
               "localFrameSpecularReflections,localFrameInteriorCollisions,"
               "localFrameShellReflections,localFrameRelativeStillOutward,"
               "localFrameInteriorEndpointOuter,localFrameShellEndpointOuter,"
               "localFrameRelativeSpeedSqAbsErrorSum,"
               "localFrameRelativeSpeedSqReferenceSum,"
               "localFrameLabSpeedSqChangeSum,localFrameLabSpeedSqAbsChangeSum,"
               "localFramePositionShiftAbsSum,"
               "contract\\n";
''',
'CSV x10k header')

replace_once(
'''        << a.simpleSpecularSpeedSqAbsErrorSum << ','
        << a.simpleSpecularSpeedSqReferenceSum << ','
        << a.simpleSpecularPositionShiftAbsSum << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'''        << a.simpleSpecularSpeedSqAbsErrorSum << ','
        << a.simpleSpecularSpeedSqReferenceSum << ','
        << a.simpleSpecularPositionShiftAbsSum << ','
        << a.localFrameSpecularReflections << ','
        << a.localFrameInteriorCollisions << ','
        << a.localFrameShellReflections << ','
        << a.localFrameRelativeStillOutward << ','
        << a.localFrameInteriorEndpointOuter << ','
        << a.localFrameShellEndpointOuter << ','
        << a.localFrameRelativeSpeedSqAbsErrorSum << ','
        << a.localFrameRelativeSpeedSqReferenceSum << ','
        << a.localFrameLabSpeedSqChangeSum << ','
        << a.localFrameLabSpeedSqAbsChangeSum << ','
        << a.localFramePositionShiftAbsSum << ','
        << "actual-endpoint-first;pointwise-alpha-start-side;relative-outward-gate;"
''',
'CSV x10k row')

replace_once(
'''           "0493x10j-simple-lab-specular-ablation;"
           "x10j-runtime-overrides-r1-mesoscopic-reaction-when-enabled;"
''',
'''           "0493x10j-simple-lab-specular-ablation;"
           "0493x10k-local-frame-specular-ablation;"
           "x10k-v-minus-2-vminusub-dot-n-n;"
           "x10k-relative-speed-norm-conserving-no-interface-counterreaction;"
           "x10k-runtime-overrides-x10j-and-r1-mesoscopic-reaction-when-enabled;"
           "x10j-runtime-overrides-r1-mesoscopic-reaction-when-enabled;"
''',
'CSV x10k contract tag')

SRC.write_text(text)

# ---------------------------------------------------------------------------
# Dedicated analyzer.  In x10k the strict invariant is local thermal energy:
# |v-u_b| is conserved and the post-collision relative normal speed is inward.
# Lab-frame kinetic energy and momentum are intentionally NOT enforced.
# ---------------------------------------------------------------------------
an = ROOT / 'scripts/analyze_0493x10k_local_frame_specular.py'
an.write_text(r'''#!/usr/bin/env python3
import csv
import math
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        "usage: analyze_0493x10k_local_frame_specular.py "
        "<cuda_phase_kinetic_crossing_0493x9z.csv>")

p = Path(sys.argv[1])
with p.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("[0493x10k-check] ERROR empty CSV")

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def isum(k): return sum(I(r,k) for r in rows)
def fsum(k): return sum(F(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)

refl = isum("localFrameSpecularReflections")
interior = isum("localFrameInteriorCollisions")
shell = isum("localFrameShellReflections")
still = isum("localFrameRelativeStillOutward")
int_outer = isum("localFrameInteriorEndpointOuter")
shell_outer = isum("localFrameShellEndpointOuter")
rel_err = fsum("localFrameRelativeSpeedSqAbsErrorSum")
rel_ref = fsum("localFrameRelativeSpeedSqReferenceSum")
rel_err_ratio = rel_err / max(rel_ref, 1.0e-300)
lab_delta = fsum("localFrameLabSpeedSqChangeSum")
lab_abs_delta = fsum("localFrameLabSpeedSqAbsChangeSum")
pos_shift = fsum("localFramePositionShiftAbsSum")
x10j_refl = isum("simpleSpecularReflections")
receiver = isum("receiverCorrectedParticles")
reaction = isum("reactionActiveCells")
meso = isum("mesoReactionActiveReservoirs")
dp = max(math.hypot(F(r,"deltaPx"), F(r,"deltaPy")) for r in rows)
de = maxabs("deltaKineticEnergy")
deep = [I(r,"deepOuterParticles") for r in rows]
shell_pop = [I(r,"shellParticles") for r in rows]
outer = [I(r,"phaseAOuterCellParticles") for r in rows]

print("===== 0493x10k LOCAL-LIQUID-FRAME SPECULAR ABLATION =====")
print(f"file={p} rows={len(rows)} lastStep={I(rows[-1],'step')}")
print("--- local-frame reflection path ---")
print(f"reflections={refl} interior={interior} shell={shell} "
      f"relativeStillOutward={still}")
print(f"interiorEndpointOuter={int_outer} shellEndpointOuter={shell_outer}")
print(f"relativeSpeedSqAbsErrorSum={rel_err:.12e}")
print(f"relativeSpeedSqRelativeError={rel_err_ratio:.12e}")
print(f"labSpeedSqChangeSum={lab_delta:.12e} "
      f"labSpeedSqAbsChangeSum={lab_abs_delta:.12e}")
print(f"max|deltaKE(row)|={de:.12e}")
print(f"interfaceImpulseIgnored max|deltaP(row)|={dp:.12e}")
print(f"collisionPositionShiftAbsSum={pos_shift:.12e}")
print("--- disabled collective machinery ---")
print(f"x10jLabReflections={x10j_refl} receiverCorrectedParticles={receiver} "
      f"reactionActiveCells={reaction} mesoReactionActiveReservoirs={meso}")
print("--- halo context ---")
print(f"outer first/max/last={outer[0]}/{max(outer)}/{outer[-1]}")
print(f"shell first/max/last={shell_pop[0]}/{max(shell_pop)}/{shell_pop[-1]}")
print(f"deepOuter first/max/last={deep[0]}/{max(deep)}/{deep[-1]}")

path_ok = (
    refl > 0 and x10j_refl == 0 and receiver == 0 and reaction == 0 and meso == 0)
relative_ok = rel_err_ratio < 1.0e-12 and still == 0
print("localFramePathContract=" + ("PASS" if path_ok else "FAIL"))
print("relativeSpeedNormContract=" + ("PASS" if relative_ok else "FAIL"))
print("labEnergyContract=NOT_ENFORCED_MOVING_LOCAL_FRAME")
print("momentumContract=INTENTIONALLY_NOT_ENFORCED_INTERFACE_IMPULSE_IGNORED")
print("endpointOuter=CONTEXT_NOT_FAILURE_INTERFACE_MAY_ADVECT")
print("retentionOutcome=VISUAL_PLUS_HALO_REVIEW")
print("shapeContract=VISUAL_PENDING")
''')
an.chmod(0o755)

# Pure local-frame reflection math test.
chk = ROOT / 'scripts/check_0493x10k_local_frame_specular_math.py'
chk.write_text(r'''#!/usr/bin/env python3
import math
import random
rng = random.Random(4931012)
max_rel_e = 0.0
max_g_res = 0.0
nonzero_lab_work = 0
for _ in range(200000):
    a = rng.uniform(-math.pi, math.pi)
    nx, ny = math.cos(a), math.sin(a)
    ubx, uby = rng.uniform(-1,1), rng.uniform(-1,1)
    # Build an outward relative velocity so the donor gate is satisfied.
    tx, ty = -ny, nx
    gn = rng.uniform(1.0e-6, 2.0)
    gt = rng.uniform(-2.0, 2.0)
    vx = ubx + gn*nx + gt*tx
    vy = uby + gn*ny + gt*ty
    wx = vx - 2.0*gn*nx
    wy = vy - 2.0*gn*ny
    rb = (vx-ubx)**2 + (vy-uby)**2
    ra = (wx-ubx)**2 + (wy-uby)**2
    ga = (wx-ubx)*nx + (wy-uby)*ny
    max_rel_e = max(max_rel_e, abs(ra-rb))
    max_g_res = max(max_g_res, abs(ga + gn))
    lab_before = vx*vx + vy*vy
    lab_after = wx*wx + wy*wy
    if abs(lab_after-lab_before) > 1.0e-12:
        nonzero_lab_work += 1
print(f"maxRelativeSpeedSqError={max_rel_e:.12e}")
print(f"maxRelativeNormalReflectionResidual={max_g_res:.12e}")
print(f"casesWithNonzeroLabSpeedSqChange={nonzero_lab_work}")
ok = max_rel_e < 1.0e-12 and max_g_res < 1.0e-12 and nonzero_lab_work > 0
print("status=" + ("PASS" if ok else "FAIL"))
if not ok:
    raise SystemExit(2)
''')
chk.chmod(0o755)

# ---------------------------------------------------------------------------
# Qualification runners.  Keep the user's requested recording defaults and
# test static + dripping in the same sequential campaign.
# ---------------------------------------------------------------------------
base_static = ROOT / 'scripts/run_0493x10j_simple_specular_static_drop.sh'
if not base_static.exists():
    raise SystemExit('[0493x10k-patch] missing x10j static runner prerequisite')
static_text = base_static.read_text()
static_text = static_text.replace(
    'export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=1',
    'export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0\nexport MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=1')
static_text = static_text.replace(
    'runs/0493x10j_simple_specular_static_s4500',
    'runs/0493x10k_local_frame_specular_static_s4500')
static_text = static_text.replace(
    '0493x10j STATIC DROP / SIMPLE LAB SPECULAR',
    '0493x10k STATIC DROP / LOCAL-FRAME SPECULAR')
static_text = static_text.replace(
    '[0493x10j] sigma=$SIGMA_ACTIVE kBT=$KBT; no B8/global receiver reaction',
    '[0493x10k] sigma=$SIGMA_ACTIVE kBT=$KBT; no B8/global receiver reaction')
static_text = static_text.replace(
    '[0493x10j] v\' = v - 2(v.n)n; interface counter-impulse intentionally ignored',
    '[0493x10k] v\' = v - 2[(v-u_b).n]n; interface counter-impulse intentionally ignored')
static_text = static_text.replace(
    '[0493x10j] liveEvery=',
    '[0493x10k] liveEvery=')
static_text = static_text.replace(
    'scripts/analyze_0493x10j_simple_specular.py',
    'scripts/analyze_0493x10k_local_frame_specular.py')
static = ROOT / 'scripts/run_0493x10k_local_frame_specular_static_drop.sh'
static.write_text(static_text)
static.chmod(0o755)

base_drip = ROOT / 'scripts/run_0493x10j_simple_specular_dripping.sh'
if not base_drip.exists():
    raise SystemExit('[0493x10k-patch] missing x10j dripping runner prerequisite')
drip_text = base_drip.read_text()
drip_text = drip_text.replace(
    'dripping_vk_0493x10j_simple_specular',
    'dripping_vk_0493x10k_local_frame_specular')
drip_text = drip_text.replace(
    'runs/0493x10j_simple_specular_dripping_s4500_g01',
    'runs/0493x10k_local_frame_specular_dripping_s4500_g01')
drip_text = drip_text.replace(
    'MPCD_X10J_SIMPLE_SPECULAR_ABLATION=1\nexport MPCD_X10J_SIMPLE_SPECULAR_ABLATION',
    'MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0\nMPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=1\nexport MPCD_X10J_SIMPLE_SPECULAR_ABLATION MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION')
drip_text = drip_text.replace(
    '[0493x10j-drip] objective=simple lab-frame specular interface ablation; no collective receiver reaction; retain jet/neck/pinch-off/drop/impact',
    '[0493x10k-drip] objective=local-liquid-frame specular interface ablation; no collective receiver reaction; retain jet/neck/pinch-off/drop/impact')
drip_text = drip_text.replace(
    'scripts/analyze_0493x10j_simple_specular.py',
    'scripts/analyze_0493x10k_local_frame_specular.py')
drip = ROOT / 'scripts/run_0493x10k_local_frame_specular_dripping.sh'
drip.write_text(drip_text)
drip.chmod(0o755)

dual = ROOT / 'scripts/run_0493x10k_local_frame_specular_dual_qualification.sh'
dual.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
mkdir -p logs

echo "===== 0493x10k DUAL QUALIFICATION: STATIC THEN DRIPPING ====="
echo "[0493x10k] local-liquid-frame reflection; no B8/global receiver reaction"
echo "[0493x10k] sequential on one GPU; close LiveVis after static to continue"

echo
echo "===== STATIC DROP ====="
RUN_ROOT="${STATIC_RUN_ROOT:-runs/0493x10k_local_frame_specular_static_s4500}" \
SIGMA_ACTIVE="${STATIC_SIGMA_ACTIVE:-4500}" \
STEPS="${STATIC_STEPS:-800}" \
SUMMARY_EVERY="${STATIC_SUMMARY_EVERY:-25}" \
LIVE_PROGRESS=1 LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}" \
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}" \
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}" \
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}" \
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}" \
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}" \
bash scripts/run_0493x10k_local_frame_specular_static_drop.sh \
2>&1 | tee logs/0493x10k_local_frame_specular_static.log

echo
echo "===== DRIPPING ====="
RUN_ROOT="${DRIP_RUN_ROOT:-runs/0493x10k_local_frame_specular_dripping_s4500_g01}" \
SIGMA_ACTIVE="${DRIP_SIGMA_ACTIVE:-4500}" \
GRAVITY_Y="${DRIP_GRAVITY_Y:--0.1}" \
STEPS="${DRIP_STEPS:-8000}" \
SUMMARY_EVERY="${DRIP_SUMMARY_EVERY:-25}" \
LIVE_PROGRESS=1 LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-100}" \
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}" \
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}" \
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}" \
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}" \
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}" \
bash scripts/run_0493x10k_local_frame_specular_dripping.sh \
2>&1 | tee logs/0493x10k_local_frame_specular_dripping.log
''')
dual.chmod(0o755)

print('[0493x10k-patch] patched src/cuda_q6_resident_0400.cu')
print('[0493x10k-patch] runtime flag: MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=1')
print('[0493x10k-patch] x10k takes precedence over x10j when both are set')
print('[0493x10k-patch] reflection: v <- v - 2[(v-u_b).n]n')
print('[0493x10k-patch] invariant: |v-u_b| preserved; lab |v| intentionally not constrained')
print('[0493x10k-patch] no receiver counter-impulse, no B8/global reaction, no endpoint seal')
print('[0493x10k-patch] wrote analyzer/math check/static+dripping+dual runners')
