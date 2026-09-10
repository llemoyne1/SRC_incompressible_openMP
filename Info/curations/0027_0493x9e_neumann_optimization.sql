-- V4.27: reintegrate the post-x14av multiphase Neumann lineage after its
-- autonomous implementation was cherry-picked into the canonical surf branch.
--
-- V4.25 was correct at the time it was written: V4.22/V4.23 were then scoped
-- only to SRC_GPU-SURF-x8q-ablation.  In V4.27 their source files are restored
-- unchanged and this curation continues the now-mainline lineage through x9e-fix3.
--
-- IMPORTANT: x9e already names the historical capillary static-drop diagnostic.
-- The base Neumann optimization is therefore canonically x9e-neumann.  The
-- explicitly attested fix labels are kept as x9e-fix1/fix2/fix2b/fix3, and the
-- builder suppresses generic "-fixN -> base" inference in OPEN_BOUNDARY_MULTIPHASE;
-- all causal relations below are explicit.
PRAGMA foreign_keys=ON;

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x9e-neumann','MILESTONE','x9e-neumann','curation:0027_0493x9e_neumann_optimization');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x9e-neumann','0493x9e-neumann','x9e-neumann','0493x9e-neumann',
  'post-x14av : optimisation Neumann multiphasique',
  'Pool résident de recyclage des slots supprimés',
  'Ajoute à x9d-fix1-neumann un pool résident [slots supprimés du pas | tail inactif compact] réutilisé pour les insertions Neumann/réservoir et un fast path de réparation du préfixe actif; la physique reste explicitement celle de x9c-outlet.',
  'PERF','OPEN_BOUNDARY_MULTIPHASE',
  'Optimisation de base intégrée à surf; physique x9c-outlet inchangée. La réparation de préfixe initiale est ensuite raffinée par x9e-fix2, x9e-fix2b puis x9e-fix3.',
  'A','2026-09-09',NULL,NULL,
  'Le runner unifié sélectionne x9c, x9d-fix1 ou x9e et prend x9e comme candidat optimisé par défaut. Le suffixe canonique -neumann évite toute collision avec le jalon capillaire historique x9e.',
  'Info/inputs/historical/README_x9e_neumann_recycle_opt_0493x9e.txt',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x9e-fix1','MILESTONE','x9e-fix1','curation:0027_0493x9e_neumann_optimization');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x9e-fix1','0493x9e-fix1','x9e-fix1','0493x9e-fix1',
  'post-x14av : optimisation Neumann multiphasique',
  'Correction de compilation du banner x9e-neumann',
  'Corrige uniquement un retour à la ligne source inséré dans le littéral C/C++ du banner runtime x9e-neumann, qui provoquait une erreur nvcc de quote non fermée.',
  'FIX','OPEN_BOUNDARY_MULTIPHASE',
  'Correctif de compilation historique; aucune loi physique ni logique de performance modifiée.',
  'A','2026-09-09',NULL,NULL,
  'Jalon volontairement conservé dans le lexique car le label 0493x9e-fix1 est explicitement attesté et peut apparaître dans l’historique; il ne représente aucune nouvelle physique.',
  'Info/inputs/historical/README_x9e_fix1_compile_quote_0493x9e_fix1.txt',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x9e-fix2','MILESTONE','x9e-fix2','curation:0027_0493x9e_neumann_optimization');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x9e-fix2','0493x9e-fix2','x9e-fix2','0493x9e-fix2',
  'post-x14av : optimisation Neumann multiphasique',
  'Fast path par invariant comptable de compacité',
  'Supprime du chemin normal x9e-neumann le scan O(Nactive) de role[] lorsque les comptages insertion/suppression prouvent un pas exactement équilibré; conserve un oracle full-prefix optionnel et le fallback exact 0315c.',
  'PERF','OPEN_BOUNDARY_MULTIPHASE',
  'Optimisation intermédiaire; l’hypothèse de pas équilibré s’avère trop restrictive pour le hard-reservoir réel et est remplacée par x9e-fix2b puis x9e-fix3.',
  'A','2026-09-09',NULL,NULL,
  'La physique, le pool [deleted|tail], les candidats, RNG et kernels d’insertion restent inchangés. L’optimisation ne s’applique que lorsque toutes les conditions comptables A-F du README sont satisfaites.',
  'Info/inputs/historical/README_x9e_fix2_accounting_invariant_0493x9e_fix2.txt',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x9e-fix2b','MILESTONE','x9e-fix2b','curation:0027_0493x9e_neumann_optimization');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x9e-fix2b','0493x9e-fix2b','x9e-fix2b','0493x9e-fix2b',
  'post-x14av : optimisation Neumann multiphasique',
  'Invariant ciblé sur la liste des slots supprimés',
  'Remplace le critère dense de x9e-fix2 par une vérification CUDA O(deletedCount) des seuls slots supprimés et réutilisés; le fast path exige encore expectedActive=oldActive et conserve l’oracle full-prefix optionnel ainsi que le fallback 0315c.',
  'FIX','OPEN_BOUNDARY_MULTIPHASE',
  'Correctif intermédiaire de x9e-fix2; le diagnostic de premier fallback montre qu’un pas hard-reservoir légitime peut avoir un bilan net négatif et motive x9e-fix3.',
  'A','2026-09-10',NULL,NULL,
  'Le package exact a été régénéré contre la vraie préimage x9e-fix2 après échec d’un diff fondé sur un contexte synthétique. Le diagnostic temporaire first-fallback est conservé comme provenance mais n’est pas un jalon autonome.',
  'Info/inputs/historical/README_x9e_fix2b_deleted_list_invariant_0493x9e_fix2b.txt',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x9e-fix3','MILESTONE','x9e-fix3','curation:0027_0493x9e_neumann_optimization');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x9e-fix3','0493x9e-fix3','x9e-fix3','0493x9e-fix3',
  'post-x14av : optimisation Neumann multiphasique',
  'Réparation ciblée exacte du préfixe actif',
  'Remplace la réparation globale 0315c du chemin normal par une réparation exacte bornée au support muté: trous dérivés de deletedIndices, donneurs bornés par le tail du pool, appariement lowest-hole/highest-donor compatible 0315c, vérification exacte du support et fallback 0315c sur tout cas atypique.',
  'PERF','OPEN_BOUNDARY_MULTIPHASE',
  'Chemin de production intégré à surf et qualifié au niveau implémentation/non-régression: algorithme pré-cleanup passé sur 3000 pas; cleanup final passé sur smoke surf 400x400 250/250 avec fast path ciblé actif et sans fallback observé. Physique x9c-outlet inchangée; aucune qualification universelle de toutes les sorties Neumann n’est revendiquée.',
  'A','2026-09-10',NULL,NULL,
  'Le cleanup production retire l’oracle full-prefix et la télémétrie chantier après validation, conserve les statuts exacts 8/9 sur support muté, le work-cap et le fallback compact_active_prefix_device_0315c. Le smoke final fourni donne t=1.587, kBT=4.082e-03, stdN=2.927, resM=0, q6F=1.16e-04, q6A=1.12e+01, wall=20.1 s à 250/250.',
  'Info/inputs/historical/README_x9e_fix3_cleanup_production_0493x9e_fix3.txt',NULL
);

-- Primary documentary evidence. The combined archive contains original nested
-- packages byte-for-byte with its own SHA-256 manifest.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes) VALUES
('milestone:0493x9e-neumann','HISTORICAL_SOURCE','Info/inputs/historical/README_x9e_neumann_recycle_opt_0493x9e.txt','A','Original x9e recycle-pool README extracted byte-for-byte from the preserved package.'),
('milestone:0493x9e-neumann','RUNNER_CONTRACT','Info/inputs/historical/README_x9e_neumann_unified_runner_0493x9e.txt','A','Unified runner defines x9c/x9d-fix1/x9e profiles and x9e as the optimized default candidate.'),
('milestone:0493x9e-fix1','HISTORICAL_SOURCE','Info/inputs/historical/README_x9e_fix1_compile_quote_0493x9e_fix1.txt','A','Compile-only quote fix; no physics/performance logic change.'),
('milestone:0493x9e-fix2','HISTORICAL_SOURCE','Info/inputs/historical/README_x9e_fix2_accounting_invariant_0493x9e_fix2.txt','A','Original accounting-invariant optimization specification.'),
('milestone:0493x9e-fix2b','HISTORICAL_SOURCE','Info/inputs/historical/README_x9e_fix2b_deleted_list_invariant_0493x9e_fix2b.txt','A','Exact fix2b specification generated against the real x9e-fix2 preimage.'),
('milestone:0493x9e-fix3','DIAGNOSTIC_SOURCE','Info/inputs/historical/README_x9e_fix2b_first_fallback_diag_0493x9e.txt','A','Diagnostic instrumentation that identified legitimate net-negative hard-reservoir steps and motivated targeted repair.'),
('milestone:0493x9e-fix3','HISTORICAL_SOURCE','Info/inputs/historical/README_x9e_fix3_targeted_prefix_repair_0493x9e_fix3.txt','A','Original targeted exact prefix-repair specification and diagnostic basis.'),
('milestone:0493x9e-fix3','PRODUCTION_CLEANUP','Info/inputs/historical/README_x9e_fix3_cleanup_production_0493x9e_fix3.txt','A','Cleanup after long validation; qualification-only full-prefix oracle removed while exact targeted checks/fallback remain.'),
('milestone:0493x9e-fix3','RUNTIME_SUMMARY','Info/inputs/historical/0493x9e_fix3_surf_cleanup_smoke_20260910.txt','B','Curated transcription of user-supplied final surf smoke: 250/250, wall=20.1s, targeted fast path selected, no fallback marker observed.'),
('milestone:0493x9e-fix3','PROVENANCE_ARCHIVE','Info/inputs/historical/0493x9e_neumann_optimization_original_sources.zip','A','Original x9e/fix1/unified-runner/fix2/fix2b/diagnostic/fix3/cleanup packages preserved byte-for-byte inside one manifest archive.');

-- Explicit causal chain. Do not rely on generic fix suffix inference because
-- the bare historical x9e identifier belongs to the capillary cycle.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:0493x9e-neumann','BUILDS_ON','milestone:0493x9d-fix1-neumann','A','x9e preserves x9d-fix1 exact host counts/workspace and adds deleted-slot recycling.'),
('milestone:0493x9e-neumann','OPTIMIZES','milestone:0493x9d-fix1-neumann','A','performance-only recycle/prefix optimization; runtime marker states physics=x9c_unchanged.'),
('milestone:0493x9e-neumann','REFERENCES','milestone:0493x9c-outlet','A','x9e retains the x9c-outlet physical continuation unchanged.'),
('milestone:0493x9e-neumann','REFERENCES','milestone:0493x14av','A','developed and exercised with the x14av air-assisted atomizer runner.'),
('milestone:0493x9e-fix1','FIXES','milestone:0493x9e-neumann','A','compile-only correction of the x9e runtime banner string literal.'),
('milestone:0493x9e-fix2','BUILDS_ON','milestone:0493x9e-fix1','A','accounting-invariant fast path follows the corrected compiled x9e source.'),
('milestone:0493x9e-fix2','OPTIMIZES','milestone:0493x9e-neumann','A','removes the normal O(Nactive) prefix scan under a conservative accounting proof.'),
('milestone:0493x9e-fix2b','BUILDS_ON','milestone:0493x9e-fix2','A','replaces the overly strict dense accounting condition with a deleted-list invariant.'),
('milestone:0493x9e-fix2b','FIXES','milestone:0493x9e-fix2','A','corrects the fast-path proof to inspect only slots actually deleted/recycled.'),
('milestone:0493x9e-fix3','BUILDS_ON','milestone:0493x9e-fix2b','A','targeted exact repair follows the fix2b/first-fallback diagnosis.'),
('milestone:0493x9e-fix3','FIXES','milestone:0493x9e-fix2b','A','handles legitimate net-negative hard-reservoir steps where expectedActive differs from oldActive.'),
('milestone:0493x9e-fix3','OPTIMIZES','milestone:0493x9e-neumann','A','final production implementation retains the x9e recycle pool and replaces global prefix repair by exact targeted repair.'),
('milestone:0493x9e-fix3','REFERENCES','milestone:0493x9c-outlet','A','final path explicitly preserves x9c outlet physics.'),
('milestone:0493x9e-fix3','REFERENCES','milestone:0493x14av','A','final long/smoke qualification uses the x14av atomizer configuration.');
