#!/usr/bin/env python3
from pathlib import Path
import sys

PATH = Path('src/cuda_q6_resident_0400.cu')
FLAG = 'MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE'
MARKER = '0493x10u-oneforone'


def die(msg):
    raise SystemExit(f'[0493x10u-oneforone] ERROR: {msg}')


def replace_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        die(f'{label}: expected 1 exact match, found {n}')
    return text.replace(old, new, 1)


def find_function(text, name):
    pos = text.find(name)
    if pos < 0:
        die(f'function not found: {name}')
    p0 = text.rfind('(', 0, pos + len(name) + 1)
    if p0 < 0:
        p0 = text.find('(', pos + len(name))
    else:
        # rfind may catch a call in a preceding expression; require '(' after name.
        p0 = text.find('(', pos + len(name))
    if p0 < 0:
        die(f'parameter list not found: {name}')
    depth = 0
    p1 = None
    for i in range(p0, len(text)):
        c = text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                p1 = i
                break
    if p1 is None:
        die(f'parameter list unterminated: {name}')
    b0 = text.find('{', p1)
    if b0 < 0:
        die(f'body not found: {name}')
    depth = 0
    b1 = None
    i = b0
    in_str = False
    in_chr = False
    esc = False
    line_comment = False
    block_comment = False
    while i < len(text):
        c = text[i]
        n = text[i+1] if i + 1 < len(text) else ''
        if line_comment:
            if c == '\n': line_comment = False
        elif block_comment:
            if c == '*' and n == '/':
                block_comment = False; i += 1
        elif in_str:
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == '"': in_str = False
        elif in_chr:
            if esc: esc = False
            elif c == '\\': esc = True
            elif c == "'": in_chr = False
        else:
            if c == '/' and n == '/': line_comment = True; i += 1
            elif c == '/' and n == '*': block_comment = True; i += 1
            elif c == '"': in_str = True
            elif c == "'": in_chr = True
            elif c == '{': depth += 1
            elif c == '}':
                depth -= 1
                if depth == 0:
                    b1 = i
                    break
        i += 1
    if b1 is None:
        die(f'body unterminated: {name}')
    return p0, p1, b0, b1


def validate(text):
    checks = {
        'one-for-one flag present': FLAG in text,
        'CIC prerequisite retained': '0493x10cic requires positive phase-A reference cell mass' in text,
        'true Q2 prerequisite retained': 'q6_x10biq_collide_moving_patch(' in text,
        'Q2 overlap retained': 'q6_x10biq_closest_current_wall(' in text,
        'kernel mode parameter': text.count('int oneForOneRelocation0493x10u,') == 1,
        'host mode gate': 'const bool oneForOneRelocation0493x10u =' in text,
        'launch mode arg': 'oneForOneRelocation0493x10u ? 1 : 0,' in text,
        'velocity exact preservation': 'best.newVx = cvx;\n                best.newVy = cvy;' in text,
        'zero interface impulse': 'best.impulseWallX = 0.0;\n                best.impulseWallY = 0.0;' in text,
        'swept endpoint mirror': 'const double mirrorDistance0493x10u =\n                        2.0 * fmax(0.0, best.relnBefore) * postTime0493x10u;' in text,
        'overlap spatial mirror': '2.0 * fmax(0.0, best.penetration) + inwardBias0493x10u' in text,
        'legacy reflection helper retained': 'out->newVx = vx - 2.0 * reln * nxh;' in text,
        'mass never modified by patch': 'particles.mass[p] =' not in text[text.find('// 0493x10u-oneforone'):text.find('// 0493x10i: reduce existing')],
        'no new kernel': '__global__ void q6_x10u' not in text,
        'no new device buffer': 'DeviceBuffer0400<' + 'double> oneForOne' not in text,
    }
    bad = [k for k,v in checks.items() if not v]
    for k,v in checks.items():
        print(f'[0493x10u-oneforone] {"PASS" if v else "FAIL"} {k}')
    if bad:
        die('static validation failed: ' + ', '.join(bad))


def main():
    if not PATH.exists():
        die(f'run from repository root; missing {PATH}')
    text = PATH.read_text()

    # Idempotent on an already patched tree.
    if FLAG in text:
        print('[0493x10u-oneforone] already applied; validating current tree')
        validate(text)
        return

    # Exact current-state prerequisites: CIC + true Q2 + Q2 overlap consistency.
    required = [
        'MPCD_X10_KINETIC_INTERFACE_CIC',
        'q6_x10biq_collide_moving_patch(',
        'q6_x10biq_closest_current_wall(',
        '0493x10biq-overlap',
    ]
    missing = [x for x in required if x not in text]
    if missing:
        die('missing current CIC+Q2+overlap prerequisites: ' + ', '.join(missing))

    # ------------------------------------------------------------------
    # 1) Thread one enable bit through the existing x10n/x10o particle kernel.
    # ------------------------------------------------------------------
    p0, p1, b0, b1 = find_function(text, 'q6_x10n_apply_continuous_moving_interface')
    params = text[p0+1:p1]
    params = replace_once(
        params,
        '    double thermalThickness0493x10poly,\n'
        '    int quadraticInterface0493x10poly,\n'
        '    int microTraceStep0493x10diag,\n',
        '    double thermalThickness0493x10poly,\n'
        '    int quadraticInterface0493x10poly,\n'
        '    int oneForOneRelocation0493x10u,\n'
        '    int microTraceStep0493x10diag,\n',
        'kernel one-for-one parameter')
    text = text[:p0+1] + params + text[p1:]

    # ------------------------------------------------------------------
    # 2) Override ONLY the boundary action after the existing CIC+Q2 event
    #    selector has chosen a swept hit or initial overlap.
    #
    #    Swept hit: keep v and m exactly; mirror the would-be endpoint across
    #    the local moving tangent plane.  The needed final overshoot is
    #       d = ((v-u_wall).n) * (remaining - tau),
    #    so a -2 d n position correction gives the mirrored endpoint while
    #    leaving momentum and kinetic energy untouched.
    #
    #    Initial overlap: mirror the current penetration across the same Q2
    #    thermal wall, plus the pre-existing tiny inward numerical bias.
    # ------------------------------------------------------------------
    p0, p1, b0, b1 = find_function(text, 'q6_x10n_apply_continuous_moving_interface')
    body = text[b0+1:b1]
    anchor = '''            if (validHits > 1 && audit)
                atomicAdd(&audit->continuousWallMultipleCollisionCandidates, 1ull);

            if (microTraceStep0493x10diag >= 0) {
'''
    repl = '''            if (validHits > 1 && audit)
                atomicAdd(&audit->continuousWallMultipleCollisionCandidates, 1ull);

            // 0493x10u-oneforone: boundary SUPPORT correction only.
            // CIC+Q2 still decides whether/where the particle leaves the
            // liquid support, but the interface no longer acts as a material
            // wall.  Keep the exact same particle slot, mass and velocity.
            // Only its position is mirrored to the liquid side.
            if (oneForOneRelocation0493x10u) {
                best.newVx = cvx;
                best.newVy = cvy;
                best.impulseWallX = 0.0;
                best.impulseWallY = 0.0;
                best.overlapOutwardReflected = false;

                const double h0493x10u = fmin(dx, dy);
                if (best.initialOverlap) {
                    // Particle starts already outside the Q2 thermal wall.
                    // Mirror its measured normal penetration.  The tiny bias
                    // is numerical only and prevents an exactly-on-wall state.
                    const double inwardBias0493x10u =
                        4.0e-8 * fmax(1.0, h0493x10u);
                    const double mirrorDistance0493x10u =
                        2.0 * fmax(0.0, best.penetration) + inwardBias0493x10u;
                    best.positionCorrectionX =
                        -mirrorDistance0493x10u * best.nx;
                    best.positionCorrectionY =
                        -mirrorDistance0493x10u * best.ny;
                } else {
                    // Mirror the would-be end-of-step endpoint in the local
                    // moving interface frame.  Applying this shift at tau is
                    // algebraically equivalent to mirroring that endpoint;
                    // the unchanged velocity then streams for the remainder.
                    const double postTime0493x10u =
                        fmax(0.0, remaining - best.tau);
                    const double mirrorDistance0493x10u =
                        2.0 * fmax(0.0, best.relnBefore) * postTime0493x10u;
                    best.positionCorrectionX =
                        -mirrorDistance0493x10u * best.nx;
                    best.positionCorrectionY =
                        -mirrorDistance0493x10u * best.ny;
                }
            }

            if (microTraceStep0493x10diag >= 0) {
'''
    body = replace_once(body, anchor, repl, 'one-for-one boundary action')

    # Do not label one-for-one overlap relocation as an outward reflection.
    old = '''                            if (overlap.overlapOutwardReflected)
                                atomicAdd(
                                    &audit->x10pInitialOverlapOutwardReflected,
                                    1ull);
                            else
                                atomicAdd(
                                    &audit->x10pInitialOverlapInwardReleased,
                                    1ull);
'''
    new = '''                            if (!oneForOneRelocation0493x10u) {
                                if (overlap.overlapOutwardReflected)
                                    atomicAdd(
                                        &audit->x10pInitialOverlapOutwardReflected,
                                        1ull);
                                else
                                    atomicAdd(
                                        &audit->x10pInitialOverlapInwardReleased,
                                        1ull);
                            }
'''
    body = replace_once(body, old, new, 'initial-overlap legacy classification gate')

    # Existing specular-energy diagnostics should remain meaningful in legacy
    # mode but report exact zero velocity/energy change in one-for-one mode.
    old = '''                double beforeRelX = 0.0;
                double beforeRelY = 0.0;
                if (best.initialOverlap && !best.overlapOutwardReflected) {
                    beforeRelX = best.newVx - best.wallVx;
                    beforeRelY = best.newVy - best.wallVy;
                } else {
                    beforeRelX =
                        (best.newVx + 2.0 * best.relnBefore * best.nx) -
                        best.wallVx;
                    beforeRelY =
                        (best.newVy + 2.0 * best.relnBefore * best.ny) -
                        best.wallVy;
                }
'''
    new = '''                double beforeRelX = 0.0;
                double beforeRelY = 0.0;
                if (oneForOneRelocation0493x10u ||
                    (best.initialOverlap && !best.overlapOutwardReflected)) {
                    beforeRelX = best.newVx - best.wallVx;
                    beforeRelY = best.newVy - best.wallVy;
                } else {
                    beforeRelX =
                        (best.newVx + 2.0 * best.relnBefore * best.nx) -
                        best.wallVx;
                    beforeRelY =
                        (best.newVy + 2.0 * best.relnBefore * best.ny) -
                        best.wallVy;
                }
'''
    body = replace_once(body, old, new, 'relative-energy diagnostic semantics')

    old = '''                if (!(relAfter < 1.0e-12 * fmax(1.0, fabs(best.relnBefore))))
                    atomicAdd(&audit->continuousWallRelativeStillOutward, 1ull);
'''
    new = '''                if (!oneForOneRelocation0493x10u &&
                    !(relAfter < 1.0e-12 * fmax(1.0, fabs(best.relnBefore))))
                    atomicAdd(&audit->continuousWallRelativeStillOutward, 1ull);
'''
    body = replace_once(body, old, new, 'relative-still-outward diagnostic gate')

    # Add a compact invariant comment adjacent to the final particle update.
    old = '''        particles.x[p] = x0 + corrX;
        particles.y[p] = y0 + corrY;
        particles.vx[p] = cvx;
        particles.vy[p] = cvy;
'''
    new = '''        particles.x[p] = x0 + corrX;
        particles.y[p] = y0 + corrY;
        // 0493x10u-oneforone leaves particles.mass untouched.  In relocation
        // mode cvx/cvy are also exactly the incoming velocity, hence M, P and
        // particle kinetic energy are invariant under the support correction.
        particles.vx[p] = cvx;
        particles.vy[p] = cvy;
'''
    body = replace_once(body, old, new, 'final invariant comment')

    text = text[:b0+1] + body + text[b1:]

    # ------------------------------------------------------------------
    # 3) Host gate.  Default OFF; require the already-qualified CIC+Q2 path
    #    and x10p overlap resolution so every support correction uses the same
    #    geometry.  No new physics is active unless explicitly selected.
    # ------------------------------------------------------------------
    host_anchor = '''    static bool quadraticInterfaceReported0493x10poly = false;
    if (q6ThermalInterfaceWall0493x10o &&
        !quadraticInterfaceReported0493x10poly) {
'''
    if text.count(host_anchor) != 1:
        die(f'host one-for-one insertion anchor: expected 1, found {text.count(host_anchor)}')
    host_code = '''    const bool oneForOneRelocation0493x10u =
        quadraticInterface0493x10poly &&
        env_int_0400("MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE", 0) != 0;
    if (oneForOneRelocation0493x10u && !initialOverlapResolution0493x10p) {
        throw std::runtime_error(
            "0493x10u one-for-one relocation requires x10p initial-overlap resolution");
    }
    static bool oneForOneRelocationReported0493x10u = false;
    if (q6ThermalInterfaceWall0493x10o &&
        !oneForOneRelocationReported0493x10u) {
        std::cout << "[0493x10u-oneforone] enabled="
                  << (oneForOneRelocation0493x10u ? 1 : 0)
                  << " cic=" << (kineticInterfaceCIC0493x10cic ? 1 : 0)
                  << " biq=" << (quadraticInterface0493x10poly ? 1 : 0)
                  << " semantics=position-mirror-only;mass-velocity-unchanged"
                  << std::endl;
        oneForOneRelocationReported0493x10u = true;
    }

'''
    text = text.replace(host_anchor, host_code + host_anchor, 1)

    # ------------------------------------------------------------------
    # 4) Launch one scalar bit.  No buffer/pointer/kernel/pass is added.
    # ------------------------------------------------------------------
    launch_old = '''            thermalThickness0493x10o,
            quadraticInterface0493x10poly ? 1 : 0,
            (microReflectionTrace0493x10diag ? step : -1),
'''
    launch_new = '''            thermalThickness0493x10o,
            quadraticInterface0493x10poly ? 1 : 0,
            oneForOneRelocation0493x10u ? 1 : 0,
            (microReflectionTrace0493x10diag ? step : -1),
'''
    text = replace_once(text, launch_old, launch_new, 'kernel launch one-for-one arg')

    # Insert an architecture note before the kernel for reviewability.
    kernel_anchor = '__global__ void q6_x10n_apply_continuous_moving_interface(\n'
    note = '''// =============================================================================
// 0493x10u-oneforone — CONSERVATIVE ONE-PARTICLE SUPPORT RELOCATION
// =============================================================================
// Optional ablation replacing the x10o specular impulse by a spatial-only
// support correction.  CIC+true-Q2 crossing/overlap detection is unchanged.
// The same particle slot is retained with exactly the same mass and velocity;
// therefore the relocation contributes identically zero delta-M, delta-P and
// delta-K.  Only position changes.  Legacy reflection remains the default.
// No inactive-pool operation, merge, split, extra buffer, kernel or pass.
//
'''
    if text.count(kernel_anchor) != 1:
        die(f'kernel note anchor: expected 1, found {text.count(kernel_anchor)}')
    text = text.replace(kernel_anchor, note + kernel_anchor, 1)

    PATH.write_text(text)
    print(f'[0493x10u-oneforone] patched {PATH}')
    validate(text)
    print('[0493x10u-oneforone] default OFF')
    print('[0493x10u-oneforone] enable with:')
    print('  MPCD_X10_KINETIC_INTERFACE_CIC=1')
    print('  MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1')
    print('  MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1')
    print('[0493x10u-oneforone] semantics: same slot + same mass + same velocity; position mirror only')
    print('[0493x10u-oneforone] scope: x10o CIC+Q2 kinetic support only; Q6/resampling/surface tension untouched')


if __name__ == '__main__':
    main()
