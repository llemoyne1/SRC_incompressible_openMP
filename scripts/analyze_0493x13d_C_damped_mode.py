#!/usr/bin/env python3
"""Fast direct damped-mode estimator for x13c longitudinal data (x13d-C fix1).

Physics/estimator is unchanged:
    rho_k(t) = C + exp(-beta*t) [A cos(omega*t) + B sin(omega*t)]
    nu_L = 2 beta / k^2
    c_s  = sqrt(omega^2 + beta^2) / k

Acceleration strategy:
  * one legacy/global coarse-to-fine search per physical group;
  * individual-replicate and bootstrap fits use a compact local search around
    the pooled optimum;
  * any local fit that lands on its local search boundary falls back to the
    full legacy/global search, so the fast path does not silently clip a fit.

No scipy and no pandas.  Requires numpy, as did the original x13d analyzer.
"""
from __future__ import annotations
import argparse, csv, importlib.util, math, time
from pathlib import Path
import numpy as np

FIX_TAG = "0493x13d-C-fastfit-fix1"


def load_w1(root):
    path = root / 'scripts' / 'analyze_0493w1_src_fluid_calibrator.py'
    spec = importlib.util.spec_from_file_location('w1damp', path)
    if not spec or not spec.loader:
        raise RuntimeError(f'cannot import {path}')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_csv(path):
    if not Path(path).exists():
        return []
    with Path(path).open(newline='') as f:
        return list(csv.DictReader(f))


def write_csv(path, rows):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text('')
        return
    fields = []
    for r in rows:
        for k in r:
            if k not in fields:
                fields.append(k)
    with path.open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, lineterminator='\n')
        w.writeheader()
        w.writerows(rows)


def ff(r, k, d=math.nan):
    try:
        return float(r[k])
    except Exception:
        return d


def qstats(vals):
    a = np.asarray([x for x in vals if math.isfinite(x)], float)
    if len(a) == 0:
        return dict(n=0, mean=math.nan, std=math.nan, cv=math.nan,
                    p025=math.nan, p50=math.nan, p975=math.nan)
    mean = float(np.mean(a))
    std = float(np.std(a, ddof=1)) if len(a) > 1 else 0.0
    q = np.quantile(a, [.025, .5, .975])
    return dict(n=len(a), mean=mean, std=std,
                cv=std / abs(mean) if mean else math.nan,
                p025=float(q[0]), p50=float(q[1]), p975=float(q[2]))


def load_group(w1, row, run_root):
    group = run_root / row['runDir']
    reps = sorted(p for p in group.glob('rep*')
                  if p.is_dir() and (p / 'RUN_COMPLETE_0493x13c_Cstat').exists())
    if not reps:
        raise ValueError(f'no completed Cstat reps in {group}')
    k = 2 * math.pi * int(row['modeX']) / ff(row, 'Lx')
    t_ref = None
    rho = []
    for rep in reps:
        q = w1._sound_series_from_case(rep, ff(row, 'dt'), k)
        t = np.asarray([x[1] for x in q], float)
        rr = np.asarray([x[2] for x in q], complex)
        if t_ref is None:
            t_ref = t
        elif len(t) != len(t_ref) or np.max(np.abs(t - t_ref)) > 1e-12:
            raise ValueError('replicate time mismatch')
        rho.append(rr)
    return reps, t_ref, np.asarray(rho), k


def _prepare_series(t, y, omega_min, omega_max):
    t = np.asarray(t, float)
    y = np.asarray(y, float)
    mask = np.isfinite(t) & np.isfinite(y)
    t = t[mask]
    y = y[mask]
    if len(t) < 12:
        raise ValueError('not enough points for damped-cosine sound fit')
    order = np.argsort(t)
    t = t[order]
    y = y[order]
    t = t - t[0]
    span = float(t[-1])
    if span <= 0:
        raise ValueError('zero sound fit time span')
    dt_sample = float(np.median(np.diff(t)))
    nyquist = math.pi / dt_sample
    omega_min = max(float(omega_min), 0.35 * 2 * math.pi / span)
    omega_max = min(float(omega_max), 0.92 * nyquist)
    if not (0 < omega_min < omega_max):
        raise ValueError(f'invalid sound frequency search window [{omega_min},{omega_max}]')
    total_variance = float(np.sum((y - np.mean(y)) ** 2))
    if total_variance <= 0:
        raise ValueError('zero sound-mode variance')
    return t, y, span, omega_min, omega_max, total_variance


def _solve_one(t, y, omega, beta):
    decay = np.exp(-beta * t)
    matrix = np.column_stack((np.ones_like(t),
                              decay * np.cos(omega * t),
                              decay * np.sin(omega * t)))
    # 3-column least squares; same linear model as 0493w1.
    coeff, _, _, _ = np.linalg.lstsq(matrix, y, rcond=None)
    model = matrix @ coeff
    sse = float(np.sum((y - model) ** 2))
    return sse, coeff, model


def fit_damped_cosine_local(t, y, omega_min, omega_max, center,
                            omega_window_fraction=0.08,
                            beta_window_fraction=0.20,
                            schedule=((21, 17), (17, 13), (13, 11))):
    """Coarse-to-fine local fit around a pooled/global optimum.

    Typical cost is 21*17 + 17*13 + 13*11 = 721 linear solves rather than 18,160.
    """
    t, y, span, omega_min, omega_max, total_variance = _prepare_series(
        t, y, omega_min, omega_max)
    beta_global_max = 12.0 / span
    omega_full_span = omega_max - omega_min

    omega_c = float(center['omega'])
    beta_c = float(center['beta'])
    omega_half = max(4e-4, omega_window_fraction * omega_full_span)
    beta_half = max(4e-4, beta_window_fraction * beta_global_max)
    omega_lo = max(omega_min, omega_c - omega_half)
    omega_hi = min(omega_max, omega_c + omega_half)
    beta_lo = max(0.0, beta_c - beta_half)
    beta_hi = min(beta_global_max, beta_c + beta_half)
    initial_bounds = (omega_lo, omega_hi, beta_lo, beta_hi)

    best = None
    for level, (n_omega, n_beta) in enumerate(schedule):
        omegas = np.linspace(omega_lo, omega_hi, n_omega)
        betas = np.linspace(beta_lo, beta_hi, n_beta)
        local_best = None
        for omega in omegas:
            for beta in betas:
                sse, coeff, model = _solve_one(t, y, float(omega), float(beta))
                item = (sse, float(omega), float(beta), coeff, model)
                if local_best is None or item[0] < local_best[0]:
                    local_best = item
        best = local_best
        if level + 1 < len(schedule):
            _, omega_c, beta_c, _, _ = best
            omega_step = (omega_hi - omega_lo) / max(1, n_omega - 1)
            beta_step = (beta_hi - beta_lo) / max(1, n_beta - 1)
            omega_lo = max(initial_bounds[0], omega_c - 2.5 * omega_step)
            omega_hi = min(initial_bounds[1], omega_c + 2.5 * omega_step)
            beta_lo = max(initial_bounds[2], beta_c - 2.5 * beta_step)
            beta_hi = min(initial_bounds[3], beta_c + 2.5 * beta_step)

    sse, omega, beta, coeff, model = best
    offset, cosine_coeff, sine_coeff = map(float, coeff)
    amplitude = math.hypot(cosine_coeff, sine_coeff)
    phase = math.atan2(-sine_coeff, cosine_coeff)
    r2 = 1.0 - sse / total_variance

    # Detect clipping against the *initial local* window.  If this is true,
    # caller should fall back to the legacy global search.
    oi0, oi1, bi0, bi1 = initial_bounds
    omega_tol_local = max(1e-12, 0.04 * max(1e-12, oi1 - oi0))
    beta_tol_local = max(1e-12, 0.04 * max(1e-12, bi1 - bi0))
    local_boundary = (
        abs(omega - oi0) <= omega_tol_local or
        abs(omega - oi1) <= omega_tol_local or
        abs(beta - bi0) <= beta_tol_local or
        abs(beta - bi1) <= beta_tol_local
    )
    omega_tolerance = max(1e-12, 0.015 * (omega_max - omega_min))
    beta_tolerance = max(1e-12, 0.02 * beta_global_max)
    return {
        'omega': omega, 'beta': beta, 'offset': offset,
        'cosineCoeff': cosine_coeff, 'sineCoeff': sine_coeff,
        'amplitude': amplitude, 'phase': phase, 'r2': r2,
        'points': len(t), 'cycles': omega * span / (2 * math.pi),
        'timeSpan': span, 'omegaSearchMin': omega_min,
        'omegaSearchMax': omega_max, 'betaSearchMax': beta_global_max,
        'omegaAtBoundary': (
            abs(omega - omega_min) <= omega_tolerance or
            abs(omega - omega_max) <= omega_tolerance),
        'betaAtBoundary': beta >= beta_global_max - beta_tolerance,
        'localWindowBoundary': bool(local_boundary),
        'model': model,
    }


def _fit_to_result(fit, k, fit_path):
    beta = float(fit['beta'])
    omega = float(fit['omega'])
    nu = 2 * beta / (k * k)
    cs = math.sqrt(omega * omega + beta * beta) / k
    beta_zero = beta <= max(1e-12, 0.02 * float(fit['betaSearchMax']))
    status = ('PASS' if fit['r2'] >= .98 and fit['cycles'] >= 2.0
              and not fit['omegaAtBoundary'] and not fit['betaAtBoundary']
              else ('REVIEW' if fit['r2'] >= .94 and fit['cycles'] >= 1.5
                    and not fit['omegaAtBoundary'] else 'INVALID'))
    return {
        'status': status, 'cs': cs, 'nuL': nu, 'beta': beta,
        'omegaDamped': omega, 'r2': fit['r2'], 'cycles': fit['cycles'],
        'points': fit['points'], 'timeSpan': fit['timeSpan'],
        'omegaAtBoundary': int(bool(fit['omegaAtBoundary'])),
        'betaAtBoundary': int(bool(fit['betaAtBoundary'])),
        'betaNearZero': int(beta_zero), 'fitAmplitude': fit['amplitude'],
        'fitOffset': fit['offset'], 'fitPath': fit_path,
    }


def project_mode(rho):
    rho = np.asarray(rho, complex)
    ref = rho[0]
    unit = np.conj(ref) / abs(ref) if abs(ref) > 0 else 1.0
    return np.real(rho * unit)


def direct_fit_global(w1, t, rho, k, cs_min, cs_max):
    projected = project_mode(rho)
    fit = w1.fit_damped_cosine(t, projected,
                               max(1e-10, cs_min * k), cs_max * k)
    return _fit_to_result(fit, k, 'GLOBAL'), fit


def direct_fit_local(w1, t, rho, k, cs_min, cs_max, center_fit,
                     allow_fallback=True):
    projected = project_mode(rho)
    fit = fit_damped_cosine_local(
        t, projected, max(1e-10, cs_min * k), cs_max * k, center_fit)
    if allow_fallback and fit.get('localWindowBoundary', False):
        fit = w1.fit_damped_cosine(t, projected,
                                   max(1e-10, cs_min * k), cs_max * k)
        return _fit_to_result(fit, k, 'GLOBAL_FALLBACK'), fit
    return _fit_to_result(fit, k, 'LOCAL'), fit


def compare_fits(a, b):
    cs_rel = abs(a['cs'] - b['cs']) / max(1e-30, abs(a['cs']))
    if a['nuL'] > 1e-12:
        nu_rel = abs(a['nuL'] - b['nuL']) / abs(a['nuL'])
    else:
        nu_rel = abs(a['nuL'] - b['nuL'])
    return cs_rel, nu_rel


def self_test(w1, benchmark=False):
    t = np.linspace(0, 2.4, 121)
    k = 2 * math.pi / 0.25
    cs0 = .353
    nu0 = .0008
    beta = .5 * nu0 * k * k
    wd = math.sqrt((cs0 * k) ** 2 - beta ** 2)
    y = .04 * np.exp(-beta * t) * (np.cos(wd * t) + .08 * np.sin(wd * t))
    rho = y.astype(complex)

    t0 = time.perf_counter()
    fg, center = direct_fit_global(w1, t, rho, k, .20, .50)
    tg = time.perf_counter() - t0
    t0 = time.perf_counter()
    fl, _ = direct_fit_local(w1, t, rho, k, .20, .50, center,
                             allow_fallback=False)
    tl = time.perf_counter() - t0
    ercs = abs(fg['cs'] - cs0) / cs0
    ernu = abs(fg['nuL'] - nu0) / nu0
    crcs, crnu = compare_fits(fg, fl)
    print(f'[{FIX_TAG}-selftest] global cs={fg["cs"]:.9g} target={cs0} '
          f'relErr={ercs:.3e} nuL={fg["nuL"]:.9g} target={nu0} '
          f'relErr={ernu:.3e} R2={fg["r2"]:.9g}')
    print(f'[{FIX_TAG}-selftest] local-vs-global csRel={crcs:.3e} '
          f'nuLRel={crnu:.3e} globalSec={tg:.3f} localSec={tl:.4f} '
          f'speedup={tg/max(tl,1e-12):.1f}x')
    if ercs > .01 or ernu > .05 or fg['r2'] < .999:
        raise SystemExit('global Cdamp self-test failed')
    if crcs > .005 or crnu > .05:
        raise SystemExit('local/global Cdamp agreement self-test failed')

    if benchmark:
        rng = np.random.default_rng(4931691)
        reps = []
        for _ in range(24):
            noise = rng.normal(0.0, .0025, size=len(t))
            reps.append((y + noise).astype(complex))
        stack = np.asarray(reps)
        nboot = 100
        t0 = time.perf_counter()
        fallback = 0
        for _ in range(nboot):
            idx = rng.integers(0, len(stack), size=len(stack))
            f, _ = direct_fit_local(w1, t, np.mean(stack[idx], axis=0), k,
                                    .20, .50, center, allow_fallback=True)
            fallback += (f['fitPath'] == 'GLOBAL_FALLBACK')
        elapsed = time.perf_counter() - t0
        print(f'[{FIX_TAG}-benchmark] bootstraps={nboot} elapsedSec={elapsed:.3f} '
              f'perBootstrapMs={1000*elapsed/nboot:.3f} fallback={fallback}')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--x13c-root', type=Path,
                   default=Path('runs/0493x13c_transport_qualification'))
    p.add_argument('--output-root', type=Path,
                   default=Path('runs/0493x13d_transport_followup/analysis'))
    p.add_argument('--repo-root', type=Path, default=Path('.'))
    p.add_argument('--bootstrap', type=int, default=500)
    p.add_argument('--bootstrap-seed', type=int, default=4931691)
    p.add_argument('--cs-min', type=float, default=.20)
    p.add_argument('--cs-max', type=float, default=.50)
    p.add_argument('--self-test', action='store_true')
    p.add_argument('--benchmark-self-test', action='store_true')
    p.add_argument('--validate-local', action='store_true', default=False,
                   help='print pooled global-vs-local agreement per group')
    a = p.parse_args()

    root = a.repo_root.resolve()
    w1 = load_w1(root)
    if a.self_test or a.benchmark_self_test:
        self_test(w1, benchmark=a.benchmark_self_test)
        return

    run_root = a.x13c_root / 'C_statistics'
    manifest = run_root / 'manifest_0493x13c_Cstat.csv'
    if not manifest.exists():
        raise SystemExit(f'missing x13c Cstat manifest: {manifest}')
    a.output_root.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(a.bootstrap_seed)
    groups = []
    individual = []
    analysis_t0 = time.perf_counter()

    manifest_rows = read_csv(manifest)
    print(f'[{FIX_TAG}] groups={len(manifest_rows)} bootstrap={a.bootstrap}')

    for gi, row in enumerate(manifest_rows, 1):
        group_t0 = time.perf_counter()
        try:
            reps, t, rho_stack, k = load_group(w1, row, run_root)
            n = len(reps)

            # One full/global search for this physical group.
            pooled, center_fit = direct_fit_global(
                w1, t, np.mean(rho_stack, axis=0), k, a.cs_min, a.cs_max)

            # Cheap consistency test: the local search must reproduce the
            # pooled global optimum before we trust it for bootstrap use.
            pooled_local, _ = direct_fit_local(
                w1, t, np.mean(rho_stack, axis=0), k, a.cs_min, a.cs_max,
                center_fit, allow_fallback=False)
            cs_agree, nu_agree = compare_fits(pooled, pooled_local)
            local_validation = 'PASS' if cs_agree <= .005 and nu_agree <= .05 else 'REVIEW'
            if a.validate_local or local_validation != 'PASS':
                print(f'[{FIX_TAG}] validate {row["fluid"]} eps={row["amplitude"]} '
                      f'csRel={cs_agree:.3e} nuLRel={nu_agree:.3e} {local_validation}')
            if local_validation != 'PASS':
                raise RuntimeError(
                    f'fast local fit failed pooled legacy agreement: '
                    f'csRel={cs_agree:.3e} nuLRel={nu_agree:.3e}')

            # Individual fits are diagnostic only; use fast local search with
            # fallback so they do not dominate wall time.
            for i, rep in enumerate(reps):
                try:
                    fi, _ = direct_fit_local(
                        w1, t, rho_stack[i], k, a.cs_min, a.cs_max,
                        center_fit, allow_fallback=True)
                    individual.append({**row, 'replicate': rep.name, **fi})
                except Exception as e:
                    individual.append({**row, 'replicate': rep.name,
                                       'status': 'ERROR', 'error': str(e)})

            csb, nub, r2b, statuses = [], [], [], []
            bzero = bbound = obound = fallback_count = 0
            for _ in range(a.bootstrap):
                idx = rng.integers(0, n, size=n)
                try:
                    f, _ = direct_fit_local(
                        w1, t, np.mean(rho_stack[idx], axis=0), k,
                        a.cs_min, a.cs_max, center_fit, allow_fallback=True)
                    csb.append(f['cs'])
                    nub.append(f['nuL'])
                    r2b.append(f['r2'])
                    statuses.append(f['status'])
                    bzero += f['betaNearZero']
                    bbound += f['betaAtBoundary']
                    obound += f['omegaAtBoundary']
                    fallback_count += (f['fitPath'] == 'GLOBAL_FALLBACK')
                except Exception:
                    pass

            cs = qstats(csb)
            nu = qstats(nub)
            nb = len(csb)
            group_elapsed = time.perf_counter() - group_t0
            groups.append({
                **row, 'replicatesCompleted': n,
                'dampStatus': pooled['status'],
                'csDampedPooled': pooled['cs'], 'nuLDampedPooled': pooled['nuL'],
                'betaPooled': pooled['beta'], 'omegaDampedPooled': pooled['omegaDamped'],
                'fitR2Pooled': pooled['r2'], 'fitCyclesPooled': pooled['cycles'],
                'fitPointsPooled': pooled['points'],
                'fitBetaNearZeroPooled': pooled['betaNearZero'],
                'localValidation': local_validation,
                'localVsGlobalCsRelative': cs_agree,
                'localVsGlobalNuLRelative': nu_agree,
                'bootstrapRequested': a.bootstrap, 'bootstrapCompleted': nb,
                'bootstrapPassFraction': sum(s == 'PASS' for s in statuses) / nb if nb else math.nan,
                'bootstrapUsableFraction': sum(s in ('PASS', 'REVIEW') for s in statuses) / nb if nb else math.nan,
                'bootstrapGlobalFallbackFraction': fallback_count / nb if nb else math.nan,
                'csBootstrapMean': cs['mean'], 'csBootstrapStd': cs['std'],
                'csBootstrapCV': cs['cv'], 'csBootstrapP025': cs['p025'],
                'csBootstrapMedian': cs['p50'], 'csBootstrapP975': cs['p975'],
                'nuLBootstrapMean': nu['mean'], 'nuLBootstrapStd': nu['std'],
                'nuLBootstrapCV': nu['cv'], 'nuLBootstrapP025': nu['p025'],
                'nuLBootstrapMedian': nu['p50'], 'nuLBootstrapP975': nu['p975'],
                'betaNearZeroFraction': bzero / nb if nb else math.nan,
                'betaUpperBoundaryFraction': bbound / nb if nb else math.nan,
                'omegaBoundaryFraction': obound / nb if nb else math.nan,
                'analysisElapsedSeconds': group_elapsed,
                'analysisMsPerBootstrap': 1000 * group_elapsed / max(1, nb),
                'k': k, 'analysisFix': FIX_TAG,
            })
            print(f'[{FIX_TAG}] {gi}/{len(manifest_rows)} {row["fluid"]} '
                  f'eps={row["amplitude"]} reps={n} boot={nb} '
                  f'fallback={fallback_count}/{nb} elapsed={group_elapsed:.2f}s')
        except Exception as e:
            groups.append({**row, 'dampStatus': 'ERROR', 'error': str(e),
                           'analysisFix': FIX_TAG})
            print(f'[{FIX_TAG}] ERROR {row.get("fluid", "?")} '
                  f'eps={row.get("amplitude", "?")}: {e}')

    write_csv(a.output_root / 'Cdamp_individual_replicates_0493x13d.csv', individual)
    write_csv(a.output_root / 'Cdamp_group_statistics_0493x13d.csv', groups)

    by = {}
    for r in groups:
        if r.get('dampStatus') != 'ERROR':
            by.setdefault(r['fluid'], []).append(r)
    qual = []
    for fluid, grp in sorted(by.items()):
        g = sorted(grp, key=lambda r: ff(r, 'amplitude'))
        if len(g) < 2:
            continue
        lo, hi = g[0], g[-1]
        cslo, cshi = ff(lo, 'csDampedPooled'), ff(hi, 'csDampedPooled')
        nulo, nuhi = ff(lo, 'nuLDampedPooled'), ff(hi, 'nuLDampedPooled')
        csrel = abs(cshi - cslo) / (0.5 * (cshi + cslo)) if cslo > 0 and cshi > 0 else math.nan
        nurel = abs(nuhi - nulo) / (0.5 * (nuhi + nulo)) if nulo > 0 and nuhi > 0 else math.inf
        cscv = max(ff(lo, 'csBootstrapCV'), ff(hi, 'csBootstrapCV'))
        nucv = max(ff(lo, 'nuLBootstrapCV'), ff(hi, 'nuLBootstrapCV'))
        bfrac = max(ff(lo, 'betaNearZeroFraction'), ff(hi, 'betaNearZeroFraction'))
        uf = min(ff(lo, 'bootstrapUsableFraction'), ff(hi, 'bootstrapUsableFraction'))
        fb = max(ff(lo, 'bootstrapGlobalFallbackFraction'), ff(hi, 'bootstrapGlobalFallbackFraction'))
        csgrade = ('PASS' if csrel <= .03 and cscv <= .03 and uf >= .9
                   else ('REVIEW' if csrel <= .06 and cscv <= .06 and uf >= .75
                         else 'UNRESOLVED'))
        nugrade = ('PASS' if nurel <= .25 and nucv <= .25 and bfrac <= .05 and uf >= .9
                   else ('REVIEW' if nurel <= .50 and nucv <= .40 and bfrac <= .15 and uf >= .75
                         else 'UNRESOLVED'))
        qual.append({
            'fluid': fluid, 'gamma': lo.get('gamma', ''),
            'amplitudeLow': lo.get('amplitude', ''),
            'amplitudeHigh': hi.get('amplitude', ''),
            'csLow': cslo, 'csHigh': cshi,
            'csRelativeDifference': csrel, 'csMaxBootstrapCV': cscv,
            'csQualification': csgrade,
            'csEstimate': 0.5 * (cslo + cshi) if csgrade != 'UNRESOLVED' else math.nan,
            'nuLLow': nulo, 'nuLHigh': nuhi,
            'nuLRelativeDifference': nurel, 'nuLMaxBootstrapCV': nucv,
            'betaNearZeroFractionMax': bfrac,
            'bootstrapGlobalFallbackFractionMax': fb,
            'nuLQualification': nugrade,
            'nuLEstimate': 0.5 * (nulo + nuhi) if nugrade != 'UNRESOLVED' else math.nan,
            'bootstrapUsableFractionMin': uf,
            'analysisFix': FIX_TAG,
        })
    write_csv(a.output_root / 'Cdamp_fluid_qualification_0493x13d.csv', qual)

    print(f'[{FIX_TAG}] fluid cs(.04/.08) csGrade nuL(.04/.08) nuLGrade')
    for r in qual:
        print(f"  {r['fluid']:<4s} {ff(r,'csLow'):.6g}/{ff(r,'csHigh'):.6g} "
              f"{r['csQualification']:<10s} {ff(r,'nuLLow'):.6g}/{ff(r,'nuLHigh'):.6g} "
              f"{r['nuLQualification']}")
    total_elapsed = time.perf_counter() - analysis_t0
    print(f'[{FIX_TAG}] ANALYSIS COMPLETE elapsed={total_elapsed:.2f}s output={a.output_root}')


if __name__ == '__main__':
    main()
