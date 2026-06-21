# Chantier 0400 - Q6 CUDA resident

Date: 2026-06-20
Depot de travail: `/mnt/e/SRC_MPCD_DEV/SRC_GPU-Q6-CUDA`
Branche: `feature/cuda-resident-q6`
Base clonee: `SRC_GPU-RESAMP-cleanpush`, commit `d3dbadb`

## Objectif

Construire une variante CUDA residente de l etape Q6 qui s insere dans le pipeline SRC_GPU sans repasser par un `ParticleState` CPU entre collision SRC et les etapes aval. L objectif n est pas seulement d accelerer le solveur CG Q6: le backend CUDA existant couvre deja une partie de ce solveur. Le gain attendu vient surtout de la suppression de la frontiere CPU/GPU autour de Q6.

Reference numerique retenue: projection de type Chorin / MAC finite-volume sur champ de faces, avec resolution CG de l operateur elliptique `A = -div(alpha grad)`. Les choix doivent rester compatibles avec les principes classiques de projection incompressible de Chorin (1968), Harlow & Welch (1965), et l usage standard du gradient conjugue pour operateurs symetriques definis positifs sur le sous-espace jauge fixe.

## Etat actuel du code

### Chemin simulation

Dans `src/src_mpcd_base.cpp`, l etape Q6 est appelee apres la collision SRC:

```text
src_collision_step(...)
apply_q6_periodic_projection(state, params, grid, domain, time, workspace.q6)
```

La fonction `apply_q6_periodic_projection()` consomme un `ParticleState&` CPU. Quand `projectionEnable=true`, le code invalide ensuite l etat CUDA partage `0251`, ce qui confirme que Q6 est encore considere comme un mutateur CPU de vitesses.

### Adaptateur Q6 CPU

`src/q6_projection_adapter.cpp` effectue actuellement, sur CPU/OpenMP:

1. depot particules -> masses/moments/vitesses cellules;
2. construction du champ de faces `baseFlux`;
3. construction de `alpha`, masques solides et divergence cible;
4. appel au coeur elliptique `project_face_field()`;
5. mise a l echelle de la correction Q6;
6. diagnostics de divergence/leak solide;
7. conversion correction face -> correction cellule;
8. application de la correction aux vitesses particulaires, avec correction de quantite de mouvement globale.

### Backend CUDA existant

`src/cuda_q6_backend.cu` fournit deja un solveur CG CUDA pour un `EllipticOperatorPlan` construit cote CPU, avec kernels d application operateur, reductions et variantes device-scalar/batch. L integration `projectionBackend=cuda` est limitee dans `src/elliptic_projection.cpp` au cas:

- periodic x/y;
- pas de masque;
- toutes cellules actives;
- RHS et plan deja construits en memoire hote.

Cela accelere le CG mais ne rend pas Q6 resident: `rhs`, `phi`, `baseFlux`, diagnostics et correction particules traversent encore la frontiere hote/device.

### Ressources GPU reutilisables

`CudaCellWorkspace` contient deja `cellId`, `cellMass`, `cellPx`, `cellPy`, `cellUx`, `cellUy`. C est la bonne base pour Q6 resident. Il ne faut pas creer un deuxieme depot Q6 independant si le workspace de collision resident fournit deja ces grandeurs au bon instant physique.

## Risques numeriques et physiques

1. La projection Q6 agit sur les vitesses cellule et redistribue une correction aux particules par cellule. Modifier l ordre collision -> Q6 -> thermostat changerait la physique. Le chemin resident doit garder cet ordre.
2. Le solveur CG periodique a une jauge: moyenne RHS/phi. Les reductions GPU doivent reproduire une jauge stable et comparer avec tolerances realistes, pas bit a bit.
3. Les cas non periodiques, open boundaries, marches, cylindres et masques immerges ajoutent des coefficients `alpha`, profils de flux et faces fermees. Les inclure trop tot melangerait les erreurs de residentiel avec les erreurs de discretisation frontiere.
4. Les diagnostics actuels sont riches. Au debut il faut garder les diagnostics CPU optionnels ou telecharges ponctuellement sur pas de summary, mais jamais dans la boucle chaude par defaut.
5. La correction de quantite de mouvement globale apres application Q6 est une reduction particulaire: elle doit etre conservee, sinon les validations TG/Poiseuille peuvent passer en divergence mais deriver en impulsion.

## Strategie proposee

### Phase 0 - Baseline et garde-fous

But: mesurer et verrouiller l existant dans le nouveau repo.

- Rejouer les validations historiques TG Q6 CPU vs `projectionBackend=cuda` avec les scripts 0188/0198 si l environnement CUDA le permet.
- Verifier que le binaire topo actuel compile avec `MPCD_ENABLE_CUDA_Q6`.
- Ajouter un script court dedie `run_q6_cuda_resident_baseline_0400.sh` qui ne modifie pas encore le code, mais sort les phases Q6, les transferts et les diagnostics.

Critere de sortie: baseline reproductible, avec `q6DivAfterProjectedFluxRms` comparable au CPU et timings transfer/CG identifies.

### Phase 1 - Q6 resident periodique minimal, sans masque

But: remplacer `apply_q6_periodic_projection()` par une variante CUDA pour le cas TG periodique complet.

Sous-ensemble volontaire:

- `projectionEnable=true`;
- `projectionBackend=cuda_resident` ou flag env explicite;
- periodic x/y;
- pas d immersed solid, pas d open boundary, pas de Q9/capacity complexe;
- `alpha=1`, divergence cible nulle ou constante compatible;
- cellules toutes actives.

Kernels necessaires:

1. `q6_resident_deposit_cell_velocity`: utilise `CudaParticleDeviceView` et `CudaCellWorkspaceDeviceView`; ecrit `cellId`, `cellMass`, `cellPx/Py`, `cellUx/Uy`.
2. `q6_resident_build_rhs_periodic`: construit `baseFlux` implicite depuis `cellUx/Uy`, calcule `div(baseFlux)`, soustrait la moyenne RHS.
3. `q6_resident_cg_periodic`: reutilise ou adapte le backend `cuda_q6_backend.cu` sans upload `rhs` ni download `phi`.
4. `q6_resident_apply_velocity_correction`: calcule `du = -grad(phi)`, l applique aux particules selon `cellId`, puis fait la correction de moment global par reduction GPU.
5. diagnostics minimaux device -> host seulement aux pas summary: iterations, residual, div before/after RMS, correction RMS, momentum residual.

Critere de sortie:

- TG periodic CPU Q6 vs Q6 resident: divergences et observables finales dans les tolerances des comparateurs existants.
- Pas de download actif entre collision et Q6 ni entre Q6 et thermostat si thermostat CUDA est actif.
- Etat 0251 marque frais apres Q6 resident, pas invalide.

### Phase 2 - Integration avec thermostat CUDA

But: fermer la sequence residente collision SRC -> Q6 -> thermostat pour TG.

- Brancher Q6 resident au point actuel de `src_mpcd_base.cpp`.
- Si Q6 resident est handled, ne pas appeler le Q6 CPU et ne pas invalider 0251.
- Laisser le thermostat CUDA consommer les vitesses corrigees device.
- Ne telecharger que pour summary/dump/livevis selon les mecanismes existants.

Critere de sortie: `ordered_full_cuda` devient effectivement resident, pas seulement compose de blocs CUDA separes avec transferts.

### Phase 3 - Generalisation elliptique GPU structuree

But: sortir du TG periodic sans casser la validation.

Ordre propose:

1. Poiseuille periodic-x / wall-y, sans open boundary: operateur a bords non periodiques mais sans masque.
2. Open boundaries uniformes: profils de flux aux faces, mais pas encore segments.
3. Immersed masks rectangulaires simples: `alpha` et cellules inactives.
4. Cylindre/VK: masques courbes, faces coupees et diagnostics de leak solide.

A chaque etape, la regle est: une geometrie ajoutee, une validation CPU-vs-GPU, pas d extension simultanee du residentiel et de la physique.

## Architecture cible

Fichiers probables a ajouter/modifier:

- `include/cuda_q6_resident_0400.h`
- `src/cuda_q6_resident_0400.cu`
- `include/q6_projection_adapter.h` pour declarer une tentative CUDA residente ou une structure diagnostics.
- `src/src_mpcd_base.cpp` pour choisir Q6 resident avant le fallback CPU.
- `scripts/build_src_mpcd_cuda_q6_resident_0400.sh` ou extension controlee du build topo.
- `scripts/run_cuda_q6_resident_tg_0400.sh` pour baseline et regression.

Interface suggeree:

```cpp
CudaQ6ResidentDiagnostics try_apply_cuda_q6_resident_0400(
    ParticleState& hostState,
    const SimulationParams& params,
    const CellGrid& grid,
    const FluidDomainBounds& domain,
    int step,
    double time);
```

La presence de `ParticleState&` dans l interface est acceptable au depart pour metadata/tailles et fallback, mais la fonction ne doit pas lire les tableaux hote dans le chemin handled. Elle doit consommer `cuda_shared_particle_state_0251().device_view()` et conserver 0251 frais apres mutation.

## Validation minimale avant code large

1. Unit smoke kernels: depot cellulaire GPU vs depot CPU sur petit TG.
2. RHS/divergence GPU vs CPU sur champ connu sinusoidal.
3. CG periodic GPU resident vs `cuda_q6_solve_cg_operator_plan()` existant.
4. Application correction particules: conservation masse, impulsion residuelle apres correction, pas de changement role/support.
5. Simulation TG courte CPU Q6 vs Q6 resident.
6. Simulation TG avec collision CUDA + Q6 resident + thermostat CUDA.

## Decision immediate proposee

Ne pas commencer par VK, step ou cylindre. Le premier code doit viser TG periodique, car c est le seul sous-ensemble deja valide par le backend CUDA Q6 historique et il isole la question residentielle. Les cas step/VK viendront apres que le chemin collision -> Q6 -> thermostat soit resident et compare.


## Implementation status 0400

Implemented first TG-only CUDA-resident elliptic Q6 path in this branch. The
runtime selector is deliberately two-stage: existing `projectionBackend=cuda`
selects the CUDA projection family, and `MPCD_CUDA_Q6_RESIDENT_0400=1` enables
the new resident prototype. Unsupported geometries fall back to the existing
Q6 path.

Current supported subset: fully periodic x/y, static full box, no immersed
solid mask, no open boundary, no closed-capacity coupling. The operator remains
the current finite-volume elliptic solve, implemented as a periodic
constant-alpha CG on device for TG. This is intentionally not an FFT rewrite,
because FFT would validate only the periodic unmasked special case and would
not prepare the boundary/mask structure needed for later solids and complex CL.

A temporary host synchronization is performed immediately after resident Q6,
because the current downstream thermostat/resampling/summary stages still read
the host `ParticleState`. Removing that sync is the next residency milestone,
not a physics change.

Validation run completed:

- `scripts/run_cuda_q6_resident_tg_0400.sh` default (`NX=64 NY=64 GAMMA=20 STEPS=100 RESAMPLING_ENABLE=false`) passed strict CPU-vs-resident comparison. Final resident Q6: applied=1, converged=1, iterations=141, `q6DivAfterProjectedFluxRms=4.938911e-11`.
- Same 64x64/100 with `RESAMPLING_ENABLE=true` gives good Q6 diagnostics but fails strict global comparison after 100 steps. This is treated as coupled discrete-resampling sensitivity, not as validation of the elliptic kernel itself.


## Update: downstream GPU consumption attempt

The immediate downstream thermostat can now consume the resident GPU particle
state after Q6 without downloading particle velocities. The first attempt reused
the physical Q6 cells and failed strict TG comparison, because the validated
thermostat uses the SRC collision cell assignment, including grid-shift effects.
The corrected implementation uploads only the collision `cellId` array, rebuilds
thermostat cell moments on GPU from resident velocities, applies the cell-relative
rescale on GPU, and downloads only compact thermostat diagnostics.

Validation: `NX=64 NY=64 GAMMA=20 STEPS=100 RESAMPLING_ENABLE=false` with
`MPCD_CUDA_Q6_RESIDENT_0400=1` and
`MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1` passed strict CPU-vs-resident
comparison.

A step-boundary host synchronization is still required before the next step
because the next `ForceStream` stage is currently CPU-host based. It is now
located after the downstream GPU consumers, not immediately after Q6. The
experimental override `MPCD_CUDA_Q6_RESIDENT_SKIP_STEP_BOUNDARY_SYNC_0400=1`
removes it, but TG validation diverges because the next CPU step reads stale
host velocities. Therefore, complete removal of the sync requires migrating the
next-step Force/Stream/Collision entry path to consume the same shared GPU state.


## Update 0401: resident SRC -> Q6 step

A guarded TG-only mode `MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1` now keeps the
main step resident across periodic force/stream, SRC collision, Q6, and the
immediate thermostat. It does not use `srcClassicCudaModeEnable`, because that
parameter intentionally short-circuits Q6. Instead, it requires:

- `projectionEnable=true`, `projectionBackend=cuda`;
- `MPCD_CUDA_Q6_RESIDENT_0400=1`;
- periodic x/y, no immersed solid, no open boundary, no capacity response;
- `MPCD_CUDA_STREAMING_PERIODIC_0245=1`;
- `MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1`;
- `MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1`;
- `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1`.

Validation: `scripts/run_cuda_q6_resident_src_step_tg_0401.sh` with
`NX=64 NY=64 GAMMA=20 STEPS=100 RESAMPLING_ENABLE=false` passed strict
CPU-vs-CUDA comparison. This lifts the previous step-boundary synchronization
for the TG SRC->Q6 path.

Resampling remains deliberately outside 0401. A short resampling-on experiment
ran successfully but failed strict comparison because discrete extraction/
insertion counts changed after small SRC/Q6 trajectory differences. To avoid
contaminating the validated resampling path, 0401 now requires
`resamplingEnable=false`; use `scripts/run_cuda_q6_resident_tg_0400.sh` for the
current mixed `SRC -> Q6 -> resampling` validation path, which synchronizes
before CPU resampling.

## Update 0404: full-face inlet/outlet box, no mask

The first box-family inlet/outlet step is implemented as a deliberately narrow
full-face case, not as the full `open_rect_obstacle_full` validation. The
supported geometry is left/right inlet/outlet with solid top/bottom walls,
uniform inlet profile, balanced-flux outlet, no immersed obstacle, no Q6 mask,
no resampling, and no capacity response. This isolates the open-boundary
elliptic operator from the still-open masked-solid problem.

Runtime gates:

- `MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=1` enables the resident SRC/Q6
  full-face inlet/outlet path.
- `MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1` keeps the streaming and
  inlet/outlet SRC step resident while allowing `projectionEnable=true` for this
  guarded 0404 path.
- The path rejects segmented boundaries, immersed solids, non-uniform inlet
  profiles, non-balanced outlet modes, resampling and capacity coupling.

Implementation notes:

- Q6 resident now supports non-periodic x boundaries by prescribing the x-low
  and x-high face fluxes in RHS construction and projected-divergence
  diagnostics. For balanced full-face inlet/outlet, the outlet flux is matched
  to the inlet flux.
- The CUDA diagnostics now match the CPU Q6 definitions for
  `q6DivBeforeMaxAbs`, vector-norm `q6CorrectionVelocityMaxAbs`, and absolute
  `q6MomentumResidualBeforeCorrection`. The earlier smoke failure was therefore
  diagnostic-definition mismatch, not a physical operator mismatch.
- `scripts/run_cuda_q6_resident_box_io_fullface_0404.sh` runs three autonomous
  cases from the same generated state: `SRC`, `CPU-Q6`, and `CUDA-Q6`, with
  dumps and optional live visualization.

Validation smoke: `NX=32 NY=16 GAMMA=10 STEPS=20 INLET_UX=0.04 INITIAL_UX=0.01`
passes strict `CPU-Q6` versus `CUDA-Q6` comparison: 490 metrics compared, 0
failures. Final CUDA-Q6 diagnostics: `q6Iterations=116`,
`q6DivBeforeRms=0.24442155308965`,
`q6DivAfterProjectedFluxRms=2.1581774999409511e-11`,
`q6OpenBoundaryEnabled=1`, `q6OpenBoundaryFluxBalance=0`. The `SRC` versus
`CUDA-Q6` comparison is expected to differ because Q6 changes the projected
velocity field.

Default run: `NX=64 NY=32 GAMMA=20 STEPS=100` also passes strict `CPU-Q6`
versus `CUDA-Q6` comparison: 490 metrics compared, 0 failures. Final CUDA-Q6
diagnostics: `q6Iterations=231`, `q6DivBeforeRms=0.37259930046569706`,
`q6DivAfterProjectedFluxRms=3.3090879357721942e-11`,
`q6OpenBoundaryEnabled=1`, `q6OpenBoundaryFluxBalance=0`.

Next box step: introduce the obstacle/mask part of `open_rect_obstacle_full`
without changing the already validated full-face inlet/outlet flux treatment.

## Update 0407: small-grid single-block CUDA CG

Profiling confirmed that the resident CUDA Q6 slowdown on TG/Poiseuille-size
grids was not a numerical convergence issue. CPU-Q6 and CUDA-Q6 used the same
iteration count and produced matching residuals, but the CUDA CG loop was
host-driven: every iteration copied scalar reductions such as `pAp` and `rrNew`
from device to host. For a `128x64` grid, the useful work per kernel is too
small to amortize hundreds of kernel launches and device-host synchronizations
per Q6 step.

A guarded small-grid path now keeps the CG iteration loop inside one CUDA block:
`q6_cg_single_block_0407`. It performs the operator application, dot products,
residual update, beta update, and the existing 25-iteration mean recentering in
one resident kernel using shared-memory reductions. The CPU receives only the
final iteration count, residual and status after the solve. This preserves the
current finite-volume elliptic logic; it is not an FFT rewrite and does not alter
the boundary-condition structure.

Activation:

- automatic for `grid.numCells <= 65536`;
- override threshold with `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_MAX_CELLS_0407`;
- force on/off with `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=1` or `0`.

The old host-driven CG remains available above the threshold or when forced off,
because a single block is not the right execution model for very large grids.

Validation/performance smoke on Poiseuille `128x64`, `GAMMA=20`, `STEPS=100`:

- CPU-Q6 vs CUDA-Q6 with single-block CG: strict comparison PASS, 490 metrics,
  0 failures; `q6Iterations=268`, `q6DivAfterProjectedFluxRms=5.9270266508e-11`.
- CUDA-Q6 host-driven forced off/on comparison: CUDA-Q6 wall time decreased from
  `5.756216527 s` to `2.446397867 s` for the 100-step run.
- CPU-Q6 wall time for the same run was `1.253638774 s`; the CUDA path is still
  slower than CPU on this grid, but the main host-synchronization bottleneck is
  reduced by about `2.35x`.

Regression smoke: TG `16x16/3` and box full-face inlet/outlet `32x16/20` both
pass strict CPU-Q6 versus CUDA-Q6 comparison after this change.
## Update 0408: Q6 warm-start test

A guarded warm-start experiment was added for the small-grid single-block CUDA
CG path. With `MPCD_CUDA_Q6_RESIDENT_WARM_START_0408=1`, the resident workspace
keeps the previous Q6 potential `phi` and uses it as the initial CG guess on the
next projection, provided the grid size and periodicity flags are unchanged. The
first projection remains a zero-start solve, and the warm state is retained only
after a converged single-block CUDA solve. The thermostat cell-moment pass no
longer clears `phi`, because it does not use that array and doing so made the
warm-start flag ineffective.

The initialization computes the residual as `rhs - A phi_previous`, recenters
`phi` after this residual construction to avoid an intra-block race, and uses
`||rhs||` rather than `||r0||` as the relative-residual denominator. This keeps
the convergence criterion comparable with the zero-start path.

Validation result on Poiseuille `128x64`, `GAMMA=20`, `STEPS=100`, current script
body force `(0.1,0.0)`:

- zero-start single-block CUDA-Q6 remains the accepted reference: strict CPU-Q6
  versus CUDA-Q6 comparison PASS, `q6Iterations=268`,
  `q6DivAfterProjectedFluxRms≈5.927e-11`, CUDA-Q6 wall time about `2.4 s`;
- warm-start CUDA-Q6 is not beneficial on this stochastic MPCD case: strict
  CPU-Q6 versus CUDA-Q6 comparison FAIL on 4 Q6 diagnostics, `q6Iterations=271`,
  `q6DivAfterProjectedFluxRms≈6.741e-11`, CUDA-Q6 wall time about `2.5 s`;
- bulk physical metrics remain essentially unchanged (`meanVx` delta versus
  CPU-Q6 about `2.6e-15`, `q6CorrectionVelocityRms` delta about `1.5e-14`), so
  the issue is not a macroscopic field drift but an ineffective initial guess for
  the elliptic solve.

Conclusion: keep `MPCD_CUDA_Q6_RESIDENT_WARM_START_0408` disabled by default. On
this validation case, the previous-step potential is not a useful CG initial
guess, likely because the stochastic collision/thermostat step changes the RHS
enough between projections that the warm residual does not move closer to the
solution in the CG sense.
## Update 0409: first segmented inlet/outlet path for resident SRC/Q6

A first guarded segmented inlet/outlet continuation was added for the resident
CUDA SRC/Q6 path. It is enabled explicitly with
`MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1` together with the existing
resident Q6 and segmented resident SRC flags. The implementation deliberately
keeps the same conservative topology as the existing classic segmented CUDA
path: wall-like box boundaries, open segments only on the left face, at least one
inlet and one outlet segment, uniform segment velocities, no immersed solid, no
resampling and no capacity coupling.

The SRC side now allows the segmented resident stream/boundary path to remain
active when this Q6 continuation is explicitly requested. The Q6 side no longer
rejects this supported segmented subset. It builds a small host-side segment
configuration and passes it by value to the CUDA RHS and projected-divergence
diagnostic kernels. The elliptic operator itself is unchanged; only the imposed
Neumann flux on the x-low boundary is made piecewise in the segment coordinate.
This preserves the current finite-volume CG logic and avoids changing the
already validated full-face path.

Smoke validation: left-face box segmented case, `32x32`, `GAMMA=10`, `STEPS=20`,
segments `left inlet 0.10..0.35 ux=0.08` and
`left outlet 0.65..0.90 ux=-0.08`, resident SRC segmented + resident CUDA Q6:

- run completes with `q6Applied=1`, `q6Converged=1`;
- `q6Iterations=140`, `q6ResidualRel≈6.998e-11`;
- `q6DivBeforeRms≈4.940e-1`, `q6DivAfterProjectedFluxRms≈3.466e-11`;
- `q6OpenBoundaryEnabled=1`, integrated x-low flux balance is zero to roundoff
  (`≈3.47e-18`) for the symmetric inlet/outlet segments;
- internal profile on this smoke gives `q6_projection≈2.78 ms/step`.

The CPU-Q6 path is not a useful reference for this segmented case yet: with the
same physical setup it leaves a projected divergence around `1.6e-2`, indicating
that the CPU projection does not currently impose the compact open segments in
the same way. The current 0409 status is therefore an implementation smoke, not
a full CPU/CUDA parity validation. Next validation should compare against a
longer physical segmented-box run and then extend the segment flux treatment to
right/bottom/top faces if that topology is needed.

