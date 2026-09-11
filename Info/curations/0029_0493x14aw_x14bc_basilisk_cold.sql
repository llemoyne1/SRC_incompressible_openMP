-- V4.30: evidence-driven curation of the post-x14av Basilisk analogue work
-- performed on 2026-09-11: x14aw, x14ax, x14ay, x14az, x14ba, x14bc.
--
-- Important: labels x14bb/x14bb2 are NOT promoted. 0493x14bb2 was only a
-- campaign/run-root label used for the cold-liquid TG calibration.
-- Source-only documentary curation; generated products are rebuilt later.
PRAGMA foreign_keys=ON;

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x14aw','MILESTONE','x14aw','curation:0029_0493x14aw_x14bc_basilisk_cold');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x14aw','0493x14aw','x14aw','0493x14aw',
  'post-x14av : benchmark Basilisk et interface froide',
  'Analogue 2-D Basilisk atomisation ReL=500 / WeG=200',
  'Introduit un jet liquide rectiligne dans gaz stagnant, rhoL/rhoG=27.84, D/h=96, domaine 18D x 18D, avec la chaîne liquide/gaz x14 existante. Le premier point liquide retenu utilise gamma=8, alpha=90 deg, kBTL=0.03125 et nuL=0.0003303602194; l’entrée est d’abord stationnaire.',
  'BENCHMARK','LIQUID_GAS',
  'Benchmark exploratoire 2-D; géométrie et nombres sans revendication d’équivalence 3-D exacte avec Basilisk.',
  'A','2026-09-11',NULL,NULL,
  'Runner exact conservé dans l’archive historique V4.30. Le cas devient la base des diagnostics x14ax/x14ay/x14az et de la pulsation x14ba.',
  'Info/inputs/historical/README_0493X14AW_X14BC_BASILISK_COLD_20260911.md',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x14ax','MILESTONE','x14ax','curation:0029_0493x14aw_x14bc_basilisk_cold');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x14ax','0493x14ax','x14ax','0493x14ax',
  'post-x14av : benchmark Basilisk et interface froide',
  'Recorder alpha_x6c du champ liquide physique résident',
  'Expose phaseAlphaFiltered0493x6c au filtered recorder sous le nom alpha_x6c avec alias phase_alpha, phase_alpha_x6c et liquid_fraction_x6c, via remapping conservatif par aire vers la grille recorder sans téléchargement hôte du champ solveur complet.',
  'DIAGNOSTIC','LIQUID_GAS',
  'Diagnostic intégré et utilisé dans les campagnes d’interface; ne modifie pas la fermeture physique lorsque le champ n’est pas demandé.',
  'A','2026-09-11',NULL,NULL,
  'Aucun lissage recorder supplémentaire sur alpha_x6c; le root livevis_control.kv reste user-owned.',
  'Info/inputs/historical/README_0493X14AW_X14BC_BASILISK_COLD_20260911.md',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x14ay','MILESTONE','x14ay','curation:0029_0493x14aw_x14bc_basilisk_cold');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x14ay','0493x14ay','x14ay','0493x14ay',
  'post-x14av : benchmark Basilisk et interface froide',
  'Raffinement particulaire gamma 12/16 à similitude thermique',
  'Runner d’ablation qui augmente gamma en diminuant masse et kBT selon m->m/s et kBT->kBT/s afin de préserver gamma*m, gamma*kBT, kBT/m et lambda/h dans les grandes lignes.',
  'EXPERIMENT','LIQUID_GAS',
  'Smoke gamma=12 exploitable mais amélioration interfaciale jugée trop faible face au surcoût; gamma=12/16 non retenu pour le benchmark courant.',
  'A','2026-09-11',NULL,NULL,
  'Le runner reste une ablation documentée. La décision de campagne revient à gamma=8 et agit ensuite directement sur kBTL/mL.',
  'Info/inputs/historical/README_0493X14AW_X14BC_BASILISK_COLD_20260911.md',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x14az','MILESTONE','x14az','curation:0029_0493x14aw_x14bc_basilisk_cold');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x14az','0493x14az','x14az','0493x14az',
  'post-x14av : benchmark Basilisk et interface froide',
  'Affichage LiveVis direct de alpha_x6c',
  'Complète x14ax en rendant alpha_x6c et ses alias visualisables directement par le renderer LiveVis à partir du champ x6c résident; l’ancien champ alpha reste l’alpha Darcy.',
  'VISUALIZATION','LIQUID_GAS',
  'Diagnostic LiveVis opérationnel; smoothPasses neutralisé pour alpha_x6c afin de montrer le champ physique x6c sans lissage LiveVis additionnel.',
  'A','2026-09-11',NULL,NULL,
  'Le root livevis_control.kv n’est pas modifié par le patch.',
  'Info/inputs/historical/README_0493X14AW_X14BC_BASILISK_COLD_20260911.md',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x14ba','MILESTONE','x14ba','curation:0029_0493x14aw_x14bc_basilisk_cold');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x14ba','0493x14ba','x14ba','0493x14ba',
  'post-x14av : benchmark Basilisk et interface froide',
  'Oscillation globale sinusoïdale de vitesse d’entrée',
  'Ajoute un multiplicateur d’entrée Fosc=1+A sin(2*pi*(t+offset-start)/T+phase), combiné au ramp existant et propagé aux injections particulaires ainsi qu’aux flux Q6 host/CUDA pour conserver le verrouillage de phase.',
  'CODE','OPEN_BOUNDARY_MULTIPHASE',
  'Chemin désactivé strictement neutre; checker statique/maths PASS et chemin pulsé exercé ensuite par le smoke x14bc. Qualification longue du breakup non encore revendiquée.',
  'A','2026-09-11',NULL,NULL,
  'Six paramètres canoniques inletVelocityOscillation*; alias inletOscillation*. Amplitude bornée [0,1], période >0; timeOffset assure la continuité de phase au restart.',
  'Info/inputs/historical/README_0493X14AW_X14BC_BASILISK_COLD_20260911.md',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x14bc','MILESTONE','x14bc','curation:0029_0493x14aw_x14bc_basilisk_cold');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x14bc','0493x14bc','x14bc','0493x14bc',
  'post-x14av : benchmark Basilisk et interface froide',
  'Benchmark Basilisk froid pulsé ReL=500',
  'Runner final courant du benchmark ReL=500/WeG=200 à gamma=8 avec liquide froid calibré kBTL=0.0078125, nuL=0.0002122268985, gaz conservé kBTG=0.00575, nuG=0.0003536191886, pulse x14ba à +/-5% et St=5/3.',
  'RUNNER','LIQUID_GAS',
  'Calibration liquide TG128 8 graines PASS, CV=2.2%; smoke pulsé 300 pas PASS intégration/visualisation. Production longue 4758 pas planifiée, non encore qualifiée statistiquement.',
  'A','2026-09-11',NULL,NULL,
  'Valeurs dérivées: U≈0.282969198, sigma≈2.827354642, ReG≈300, nuG/nuL≈1.67, période≈0.79514≈125.2 pas. Coût long ~2 h: stratégie retenue d’un seed long de référence et analyse temporelle/phase-folded, pas ensemble multi-seed.',
  'Info/inputs/historical/README_0493X14AW_X14BC_BASILISK_COLD_20260911.md',NULL
);

-- Primary evidence preserved byte-for-byte in one archive with an internal
-- SHA-256 manifest.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes) VALUES
('milestone:0493x14aw','HISTORICAL_SOURCE','Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip','A','Archive contains the exact x14aw runner used as the first Basilisk 2-D Re500 benchmark source.'),
('milestone:0493x14ax','HISTORICAL_SOURCE','Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip','A','Archive contains exact 0493x14ax_livevis_alpha_x6c.zip package.'),
('milestone:0493x14ay','HISTORICAL_SOURCE','Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip','A','Archive contains exact gamma-refinement runner package and gamma12 interface captures.'),
('milestone:0493x14az','HISTORICAL_SOURCE','Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip','A','Archive contains exact 0493x14az LiveVis alpha_x6c display package.'),
('milestone:0493x14ba','HISTORICAL_SOURCE','Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip','A','Archive contains exact global-inlet-oscillation patch package.'),
('milestone:0493x14bc','HISTORICAL_SOURCE','Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip','A','Archive contains exact x14bc runner bundle, cold-liquid TG log and selected visual evidence.'),
('milestone:0493x14bc','CALIBRATION_LOG','Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip','A','Exact TG128 8-seed log: src-q6-g-f PASS, nu=0.0002122268985, std=4.705e-06, CV=0.022.'),
('milestone:0493x14bc','RUNTIME_SMOKE','Info/inputs/historical/0493x14aw_x14bc_20260911_original_sources.zip','B','User-supplied x14bc pulsed smoke screen capture at step 276 confirms alpha_x6c LiveVis path during a successful 300-step integration smoke; no quantitative breakup claim.');

-- Explicit causal/documentary chain. Missing x14bb is intentional.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:0493x14aw','BUILDS_ON','milestone:0493x14av','B','Straight-jet benchmark reuses the existing x14 liquid/gas chain while changing the benchmark geometry and similarity target.'),
('milestone:0493x14ax','BUILDS_ON','milestone:0493x6c','A','Recorder exports the resident x6c phaseAlphaFiltered field used by the interface chain.'),
('milestone:0493x14ax','DIAGNOSES','milestone:0493x14aw','A','alpha_x6c recorder was added to inspect the rough interface observed in the Basilisk analogue.'),
('milestone:0493x14az','BUILDS_ON','milestone:0493x14ax','A','LiveVis display reuses the recorder-side alpha_x6c resident/remap plumbing.'),
('milestone:0493x14ay','BUILDS_ON','milestone:0493x14aw','A','gamma refinement is an ablation of the same Re500 benchmark geometry.'),
('milestone:0493x14ay','DIAGNOSES','milestone:0493x14aw','A','tests whether occupancy noise rather than thermal displacement dominates interface roughness.'),
('milestone:0493x14ba','BUILDS_ON','milestone:0493x14aw','A','adds the exact missing Basilisk-style global inlet modulation to the benchmark path.'),
('milestone:0493x14bc','SUPERSEDES','milestone:0493x14aw','A','current Re500 runner replaces the earlier liquid reference and enables the validated pulse mechanism.'),
('milestone:0493x14bc','BUILDS_ON','milestone:0493x14ba','A','x14bc enables x14ba global inlet oscillation by default with A/U=0.05 and St=5/3.'),
('milestone:0493x14bc','BUILDS_ON','milestone:0493x14az','A','x14bc uses alpha_x6c as the default LiveVis field and recorder diagnostic.'),
('milestone:0493x14bc','REFERENCES','milestone:0493x14ay','B','gamma-refinement result motivates return to gamma=8 before the cold-kBT sweep.');

-- Conditional current-tree links. They resolve automatically once the corresponding
-- runner/patch implementation files are present in the checkout being rebuilt.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x14aw','RUN_BY',object_id,'A','V4.30 current-tree runner' FROM artifacts
WHERE path='scripts/run_0493x14aw_basilisk_atomisation_re500.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x14ay','RUN_BY',object_id,'A','V4.30 current-tree runner' FROM artifacts
WHERE path='scripts/run_0493x14ay_basilisk_atomisation_gamma_refinement.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x14bc','RUN_BY',object_id,'A','V4.30 current-tree runner' FROM artifacts
WHERE path='scripts/run_0493x14bc_basilisk_atomisation_cold_re500.sh';
