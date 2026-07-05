# 0483 — validation du gain remap-fusion CUDA résident

## État de référence

État validé repris du chantier 0446--0476 :

- 0446 : nonzero-plan smoke, `src-resampling` et `src-q6-resampling`, 64x64, `steps=5`, PASS-like 10/10.
- 0456 : device-carrier stress, périodique nonzero-plan, seeds `1628638 1628639 1628640`, modes `src-resampling` et `src-q6-resampling`, PASS-like 12/12.
- 0462 : sparse-gate stress sur 0461, seeds `1628638 1628639 1628640`, `steps=200`, `DEVICE_GATE_EVERY=50`, PASS-like 6/6, deltas résumé de l'ordre de `1e-13` à `1e-12`.
- 0464 : scaling CPU/CUDA, base multi-tailles, appuyé sur `run_0464_scaling_cuda_vs_cpu.sh`.
- 0475b : 128x128, `src-resampling` et `src-q6-resampling`, materializer shared-state/cell-list, PASS.
- 0476 : 0475b authoritative via bridge compact 0458, avec attribution des phases. Ce point est la base conceptuelle pour mesurer ce que 0483 améliore.

Les quatre gains déjà committés après 0477 sont pris comme acquis :

- `474307e` — 0479 : dépôt post-remap sans recalcul CPU des `cellId`.
- `3858eb2` — 0480 : carrier dimensionné sur les opérations compactes.
- `87948c7` — 0481 : synchronisations guards/refill redondantes supprimées.
- `b4d0a77` — 0482 : synchronisations Q6 redondantes supprimées.

## Objet 0483

Le changement 0483 fusionne les deux kernels :

- `accumulate_remap_target_energy_kernel_0445`
- `apply_remap_mass_kernel_0445`

en un kernel unique :

- `accumulate_target_and_apply_remap_mass_kernel_0483`

L'ordre physique attendu reste :

1. lire `massBefore`,
2. accumuler l'énergie thermique cible avec `massBefore`,
3. appliquer `mass = massBefore * scale[c]`,
4. laisser le kernel thermique suivant renormaliser à partir de l'énergie courante post-remap.

## Matrice de validation proposée

La validation minimale à committer doit couvrir :

- modes : `src-resampling`, `src-q6-resampling` ;
- grilles : `64x64x40`, `96x96x40`, `128x128x40` ;
- seed smoke : `1628638` ;
- seed stress recommandé : `1628638 1628639 1628640` ;
- `STEPS=200`, `SUMMARY_EVERY=50`, `DEVICE_GATE_EVERY=50` ;
- tolérance : `MAX_SUMMARY_DELTA_TOL=1e-9`.

Critères PASS :

- `pass=1` pour toutes les lignes `case × mode × seed` ;
- `max_summary_delta <= 1e-9` ;
- `invalid_materialize_ops=0`, `invalid_apply_ops=0` ;
- `op_mismatch=0`, `duplicate_particle_mismatch=0` ;
- présence de lignes remap résidentes : `remap_rows > 0`, `remap_shared_rows > 0`, `remap_upload_skipped_rows > 0` ;
- carrier compact 0458 actif : `carrier_cpuop_rows > 0`.

## Commandes principales

Build candidat 0483 :

```bash
OUT=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0483 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

Smoke multi-grille, un seed :

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0483 \
BASE_0483_ROOT=runs/0483_remap_fusion_cpu_cuda_matrix_smoke \
SCALE_CASES='64x64x40 96x96x40 128x128x40' \
SEEDS='1628638' \
STEPS=200 SUMMARY_EVERY=50 DEVICE_GATE_EVERY=50 \
LIVE_PROGRESS=1 \
bash scripts/run_0483_remap_fusion_cpu_cuda_matrix.sh
```

Stress multi-grille, trois seeds :

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0483 \
BASE_0483_ROOT=runs/0483_remap_fusion_cpu_cuda_matrix_stress \
SCALE_CASES='64x64x40 96x96x40 128x128x40' \
SEEDS='1628638 1628639 1628640' \
STEPS=200 SUMMARY_EVERY=50 DEVICE_GATE_EVERY=50 \
LIVE_PROGRESS=1 \
bash scripts/run_0483_remap_fusion_cpu_cuda_matrix.sh
```

Sorties attendues :

- `runs/.../remap_fusion_cpu_cuda_summary_0483.csv`
- `runs/.../remap_fusion_cpu_cuda_report_0483.md`
- `runs/.../scaling_cuda_vs_cpu_summary_0463.csv`
- sous-répertoires par taille contenant les sorties CPU/CUDA héritées du runner 0464.

## Comparaison de gain 0482/0483

Pour mesurer le gain, conserver un binaire baseline avant application du diff 0483, puis construire le candidat :

```bash
OUT=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0482_baseline \
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh

# appliquer ensuite le diff 0483, puis :
OUT=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0483 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

Puis :

```bash
BASELINE_BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0482_baseline \
CANDIDATE_BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0483 \
GAIN_ROOT=runs/0483_remap_fusion_gain_ab \
SCALE_CASES='64x64x40 96x96x40 128x128x40' \
SEEDS='1628638' \
STEPS=200 SUMMARY_EVERY=50 DEVICE_GATE_EVERY=50 \
LIVE_PROGRESS=1 \
bash scripts/run_0483_vs_baseline_remap_gain.sh
```

Sorties attendues :

- `runs/0483_remap_fusion_gain_ab/remap_fusion_gain_compare_0483.csv`
- `runs/0483_remap_fusion_gain_ab/remap_fusion_gain_compare_0483.md`

## Commit conseillé après validation

Commit code seul si le smoke est PASS :

```bash
git add src/cuda_resampling_pipeline_shadow_0445.cu
git commit -m "0483: fuse resident remap target and mass kernels"
```

Commit validation/documentation ensuite :

```bash
git add scripts/run_0483_remap_fusion_cpu_cuda_matrix.sh \
        scripts/run_0483_vs_baseline_remap_gain.sh \
        scripts/compare_0483_remap_fusion_roots.py \
        doc/RESAMPLING_CUDA_REMAP_FUSION_VALIDATION_0483.md
git commit -m "0483: add resident remap fusion validation matrix"
```
