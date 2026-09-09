-- V4.14: reconstruct x8a..x8j before the open-boundary semantic repair x8k.
-- Natural boundary:
--   x8a-x8c  momentum-loss diagnosis/localization
--   x8d-x8e  independent Q6-g-f / Darcy qualification and calibration
--   x8f-x8j  first open VK campaign, continuation, wake and literature analysis
-- x8k and the later x8m/x8n/x8q-x8t chain are deliberately deferred to V4.15.

-- ---------------------------------------------------------------------------
-- Missing canonical stages x8a..x8i.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from) VALUES
('milestone:0493x8a','MILESTONE','x8a','curation:0015_0493x8a_x8j_diagnostics_vk'),
('milestone:0493x8b','MILESTONE','x8b','curation:0015_0493x8a_x8j_diagnostics_vk'),
('milestone:0493x8c','MILESTONE','x8c','curation:0015_0493x8a_x8j_diagnostics_vk'),
('milestone:0493x8d','MILESTONE','x8d','curation:0015_0493x8a_x8j_diagnostics_vk'),
('milestone:0493x8e','MILESTONE','x8e','curation:0015_0493x8a_x8j_diagnostics_vk'),
('milestone:0493x8f','MILESTONE','x8f','curation:0015_0493x8a_x8j_diagnostics_vk'),
('milestone:0493x8g','MILESTONE','x8g','curation:0015_0493x8a_x8j_diagnostics_vk'),
('milestone:0493x8h','MILESTONE','x8h','curation:0015_0493x8a_x8j_diagnostics_vk'),
('milestone:0493x8i','MILESTONE','x8i','curation:0015_0493x8a_x8j_diagnostics_vk');

INSERT OR REPLACE INTO milestones(object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row) VALUES
('milestone:0493x8a','0493x8a','x8a','0493x8a','x8a-x8j : diagnostic, qualification et premier VK ouvert','Diagnostic exact du moment Darcy','Instrumente de façon opt-in le kick Darcy déterministe afin de sommer exactement l''impulsion particulaire appliquée et de fermer le bilan DeltaP = I_body + I_Darcy + I_nonDarcyResidual sur les comparaisons SRC/Q6/Q6-g-f.','DIAGNOSTIC','Q6_GF','Diagnostic opt-in; OFF en production','A','2026-08-14','3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f',NULL,'Le gate runtime ne change aucun paramètre physique. Pour forcingMode=mean, DeltaP_cell=-M_cell*lambda*(u_cell-u_s), avec le lambda float réellement consommé par le kernel.','README_0493X8A_EXACT_DARCY_MOMENTUM.md',NULL),
('milestone:0493x8b','0493x8b','x8b','0493x8b','x8a-x8j : diagnostic, qualification et premier VK ouvert','Attribution temporelle Darcy / résidu non-Darcy','Analyse hors ligne les runs x8a à chaque intervalle commun et compare Q6-g-f moins Q6 puis Q6 moins SRC, en séparant excès de perte Darcy exacte et résidu non-Darcy sans attribuer prématurément ce dernier à un opérateur particulier.','ANALYZER','Q6_GF','Analyseur hors ligne; aucune modification du solveur','A','2026-08-14','3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f',NULL,'Les temps d''apparition sont définis par fractions du propre excès final avec persistance, pas par un seuil absolu arbitraire.','README_0493X8B_MOMENTUM_DIVERGENCE.md',NULL),
('milestone:0493x8c','0493x8c','x8c','0493x8c','x8a-x8j : diagnostic, qualification et premier VK ouvert','Localisation temporaire du moment par étapes','Installe temporairement un audit de moment aux huit étapes du pas afin de localiser le résidu x8b entre Q6, stream/parois, boundary, collision, thermostat et Darcy, tout en conservant x8a comme autorité du bilan cumulatif.','DIAGNOSTIC','Q6_GF','Instrumentation temporaire retirée après campagne; preuve historique conservée','A','2026-08-14','3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f',NULL,'Le README qualifie explicitement x8c de disposable; le commit 423b1c2dc4e0 atteste ensuite son retrait. La suppression du code de diagnostic ne supprime pas le jalon historique.','README_0493X8C_STAGE_MOMENTUM.md',NULL),
('milestone:0493x8d','0493x8d','x8d','0493x8d','x8a-x8j : diagnostic, qualification et premier VK ouvert','Qualification indépendante Q6-g-f par Poiseuille et Brinkman','Qualifie Q6-g-f sans prendre SRC/Q6 comme référence : canal à parois physiques contre Poiseuille analytique et canal périodique avec slab chi contre la solution de Brinkman résolue, avec viscosité, forme, slip et longueur de pénétration mesurés.','QUALIFICATION','Q6_GF','Qualification analytique du chemin Q6-g-f; aucun changement C++/CUDA','A','2026-08-15','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d',NULL,'Le cas chi choisit ell_B=4a afin de qualifier d''abord l''équation de Brinkman résolue avant le régime de pénalisation raide.','README_0493X8D_Q6GF_POISEUILLE_QUALIFICATION.md',NULL),
('milestone:0493x8e','0493x8e','x8e','0493x8e','x8a-x8j : diagnostic, qualification et premier VK ouvert','Recalibration viscosité Q6-g-f et raideur Darcy','Recalibre le microfluide Q6-g-f x8d par un ensemble Taylor-Green multi-seeds via le calibrateur x7n, puis utilise la viscosité fraîche pour balayer ell_B/a=4,2,1,0.5 et documenter séparément l''endpoint raide alpha=4000 sous-résolu.','CALIBRATOR','Q6_GF','Calibration Q6-g-f et carte de raideur Darcy; aucun changement du solveur','A','2026-08-15','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d',NULL,'alpha=4000 est un endpoint de mur pénalisé et ne doit pas être présenté comme une couche de pénétration Brinkman résolue.','README_0493X8E_Q6GF_DARCY_VISCOSITY.md',NULL),
('milestone:0493x8f','0493x8f','x8f','0493x8f','x8a-x8j : diagnostic, qualification et premier VK ouvert','Premier candidat von Karman Q6-g-f à inlet/outlet ouverts','Construit un premier benchmark cylindre confiné avec le microfluide x8e gelé, inlet gauche contrôlé, outlet Neumann passif, parois no-slip et cylindre Brinkman, sans force volumique ni keep-mean-flow, afin d''observer l''établissement d''un sillage antisymétrique.','BENCHMARK','OPEN_BOUNDARY','Premier candidat VK ouvert; runner-only, ensuite prolongé/raffiné','A','2026-08-15','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d',NULL,'Le README initial dimensionne Re≈65 sur H=5D, Lx=10D, cylindre à 3D; des éditions locales ont ensuite allongé le domaine. Le jalon reste le premier benchmark ouvert x8f, pas une nouvelle physique C++/CUDA.','README_0493X8F_Q6GF_VK_RE65.md',NULL),
('milestone:0493x8g','0493x8g','x8g','0493x8g','x8a-x8j : diagnostic, qualification et premier VK ouvert','Qualification full-face et bilan de masse du VK','Décline le benchmark x8f sur la vraie famille io_fullface avec inlet/outlet plein cadre et balanced_flux afin d''isoler la fermeture de masse du chemin ouvert Q6-g-f avant les corrections segmentées ultérieures.','QUALIFICATION','OPEN_BOUNDARY','Qualification full-face/mass-balance du candidat VK; runner-only','A','2026-08-15','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d',NULL,'Le runner annonce explicitement une qualification true-fullface mass-balance à U=0.18 et conserve le même microfluide, les parois physiques et le cylindre Brinkman.','run_0493x8g_q6gf_vk_fullface_mass_smoke.sh',NULL),
('milestone:0493x8h','0493x8h','x8h','0493x8h','x8a-x8j : diagnostic, qualification et premier VK ouvert','Restart hydrodynamique pour les longs runs VK','Génère un runner de continuation à partir du x8f courant, valide état/params/chi/grille/dt, conserve l''origine globale des pas et redémarre depuis un dump sans régénérer les particules.','INFRA','OPEN_BOUNDARY','Infrastructure de continuation hydrodynamique; RNG non bitwise continu','A','2026-08-15','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d',NULL,'Le compteur local et le RNG redémarrent : le README précise qu''il s''agit d''un restart hydrodynamique, pas d''une continuation bitwise de la trajectoire stochastique.','README_0493X8H_VK_RESTART.md',NULL),
('milestone:0493x8i','0493x8i','x8i','0493x8i','x8a-x8j : diagnostic, qualification et premier VK ouvert','Analyse du sillage VK établi par POD et sondes','Caractérise l''état établi issu des continuations x8h : stationnarité amont, amplitude de brisure de symétrie, paire POD, fréquence/Strouhal par rotation de phase, fit harmonique indépendant aux sondes, progression de phase et champs moyennés en phase.','ANALYZER','OPEN_BOUNDARY','Analyseur du sillage établi; aucune modification du solveur','A','2026-08-15','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d',NULL,'Cette fonction était attribuée à tort à x8j dans le référentiel initial. L''analyseur x8i est explicitement conçu pour les enregistrements de restart x8h.','analyze_vk_established_0493x8i.m',NULL);

-- x8j existed retrospectively but its semantics mixed x8i POD/probes with the
-- subsequent nondimensional literature comparison. Correct that split.
UPDATE milestones
SET group_name='x8a-x8j : diagnostic, qualification et premier VK ouvert',
    name='Nondimensionnalisation VK et comparaison bibliographique',
    summary='Convertit les mesures du sillage établi x8i dans les conventions propres à Zovatto-Pedrizzetti et Sahin-Owens, compare période/Strouhal et nombres de Reynolds sans mélanger leurs échelles de référence, et documente le conditionnement amont du cas.',
    nature='ANALYZER', domain='OPEN_BOUNDARY', status='Analyse bibliographique/nondimensionnelle; enrichie plus tard par les diagnostics de flux x8n', confidence='A',
    introduced_date='2026-08-15', introduced_commit='d0f4856e03d82098d5a5a1cedcdd4f89957fa98d',
    notes='Le premier rôle de x8j est la comparaison nondimensionnelle issue de x8i. Le support ultérieur des fichiers x8n apparaît dans des révisions postérieures et ne doit pas être pris pour une dépendance d''introduction.',
    source_file='analyze_vk_nondim_0493x8j.m', source_row=NULL
WHERE object_id='milestone:0493x8j';

-- ---------------------------------------------------------------------------
-- Primary evidence archives.
-- ---------------------------------------------------------------------------
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8a','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X8A_EXACT_DARCY_MOMENTUM.md','3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f','A','Primary x8a exact Darcy momentum diagnostic README'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8a' AND path='Info/inputs/historical/README_0493X8A_EXACT_DARCY_MOMENTUM.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8b','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X8B_MOMENTUM_DIVERGENCE.md','3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f','A','Primary x8b offline momentum-divergence analysis README'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8b' AND path='Info/inputs/historical/README_0493X8B_MOMENTUM_DIVERGENCE.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8c','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X8C_STAGE_MOMENTUM.md','3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f','A','Primary disposable x8c stage-momentum diagnostic README'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8c' AND path='Info/inputs/historical/README_0493X8C_STAGE_MOMENTUM.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8d','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X8D_Q6GF_POISEUILLE_QUALIFICATION.md','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d','A','Primary x8d independent Q6-g-f qualification README'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8d' AND path='Info/inputs/historical/README_0493X8D_Q6GF_POISEUILLE_QUALIFICATION.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8e','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X8E_Q6GF_DARCY_VISCOSITY.md','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d','A','Primary x8e viscosity/Darcy calibration README'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8e' AND path='Info/inputs/historical/README_0493X8E_Q6GF_DARCY_VISCOSITY.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8f','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X8F_Q6GF_VK_RE65.md','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d','A','Primary x8f open VK design README'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8f' AND path='Info/inputs/historical/README_0493X8F_Q6GF_VK_RE65.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8g','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x8g_q6gf_vk_fullface_mass_smoke.sh','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d','A','Primary x8g full-face mass-balance qualification runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8g' AND path='Info/inputs/historical/run_0493x8g_q6gf_vk_fullface_mass_smoke.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8h','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X8H_VK_RESTART.md','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d','A','Primary x8h hydrodynamic restart contract'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8h' AND path='Info/inputs/historical/README_0493X8H_VK_RESTART.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8i','HISTORICAL_SOURCE','Info/inputs/historical/analyze_vk_established_0493x8i.m','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d','A','x8i established-wake analyzer; archived consolidated copy'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8i' AND path='Info/inputs/historical/analyze_vk_established_0493x8i.m');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8j','HISTORICAL_SOURCE','Info/inputs/historical/analyze_vk_nondim_0493x8j.m','d0f4856e03d82098d5a5a1cedcdd4f89957fa98d','A','x8j nondimensional literature analyzer; archived consolidated copy'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8j' AND path='Info/inputs/historical/analyze_vk_nondim_0493x8j.m');

-- Dedicated evidence of x8c removal: this proves temporary diagnostic status,
-- not a separate canonical milestone or an introduction commit.
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8c','GIT_COMMIT',NULL,'423b1c2dc4e0','A','0493x8c stage_momentum removed — confirms deliberate removal after measurement'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8c' AND commit_hash LIKE '423b1c2dc4e0%');

-- ---------------------------------------------------------------------------
-- Canonical causal chain. x8h derives from x8f directly; x8g is a parallel
-- mass-balance qualification branch, not a prerequisite of restart mechanics.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:0493x8a','BUILDS_ON','milestone:0493x7q','A','momentum diagnosis begins from the qualified x7q Q6-g-f chain'),
('milestone:0493x8b','BUILDS_ON','milestone:0493x8a','A','offline temporal attribution consumes completed x8a budgets'),
('milestone:0493x8c','BUILDS_ON','milestone:0493x8b','A','stage-resolved sampling localizes the non-Darcy residual isolated by x8b'),
('milestone:0493x8c','REFERENCES','milestone:0493x8a','A','x8c reuses x8a exact Darcy authority rather than reimplementing it'),
('milestone:0493x8d','BUILDS_ON','milestone:0493x8c','A','after causal localization the campaign pivots to independent analytical Q6-g-f qualification'),
('milestone:0493x8e','BUILDS_ON','milestone:0493x8d','A','fresh TG viscosity and Darcy stiffness map use the x8d microscopic state'),
('milestone:0493x8f','BUILDS_ON','milestone:0493x8e','A','first open VK freezes the freshly calibrated Q6-g-f transport signature'),
('milestone:0493x8f','REFERENCES','milestone:0493x8d','A','physical no-slip walls and Brinkman behaviour were qualified in x8d'),
('milestone:0493x8g','BUILDS_ON','milestone:0493x8f','A','true-fullface mass-balance qualification is a controlled variant of x8f'),
('milestone:0493x8h','BUILDS_ON','milestone:0493x8f','A','restart runner is generated from the exact current x8f runner'),
('milestone:0493x8i','BUILDS_ON','milestone:0493x8h','A','established-wake analyzer is designed for x8h restart recordings'),
('milestone:0493x8j','BUILDS_ON','milestone:0493x8i','A','literature nondimensionalization consumes established-wake measurements from x8i');

-- Candidate reconciliation: explicit X labels become linked when present in
-- the imported Git audit. This does not affect the numeric reconciliation count.
UPDATE git_milestone_candidates
SET status='LINKED', linked_milestone_object_id='milestone:0493' || label
WHERE label IN ('x8a','x8b','x8c','x8d','x8e','x8f','x8g','x8h','x8i','x8j')
  AND EXISTS (SELECT 1 FROM milestones m WHERE m.object_id='milestone:0493' || git_milestone_candidates.label);

-- Commit objects are optional in archive-only rebuilds but available in the
-- real 49-ref Git audit.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'EVIDENCED_BY_COMMIT','git:3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f','B','14-August bundled diagnostic sources commit'
FROM milestones m
WHERE m.object_id IN ('milestone:0493x8a','milestone:0493x8b','milestone:0493x8c')
  AND EXISTS (SELECT 1 FROM objects WHERE object_id='git:3bd07c80352ef36cb5be2658b4f02e3ebcb09a8f');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'EVIDENCED_BY_COMMIT','git:d0f4856e03d82098d5a5a1cedcdd4f89957fa98d','B','15-August bundled Q6-g-f qualification/VK analysis sources commit'
FROM milestones m
WHERE m.object_id IN ('milestone:0493x8d','milestone:0493x8e','milestone:0493x8f','milestone:0493x8g','milestone:0493x8h','milestone:0493x8i','milestone:0493x8j')
  AND EXISTS (SELECT 1 FROM objects WHERE object_id='git:d0f4856e03d82098d5a5a1cedcdd4f89957fa98d');

-- ---------------------------------------------------------------------------
-- Current-tree artifacts, when present on the audited ref. Historical-branch
-- files absent from surf remain grounded by the Info evidence archive above.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8a','ANALYZED_BY',object_id,'A','exact Darcy momentum analyzer' FROM artifacts WHERE path='scripts/analyze_0493x8a_vk_momentum.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8b','ANALYZED_BY',object_id,'A','time-resolved momentum-divergence analyzer' FROM artifacts WHERE path='scripts/analyze_0493x8b_momentum_divergence.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8c','ANALYZED_BY',object_id,'A','stage-bucket analyzer' FROM artifacts WHERE path='scripts/analyze_0493x8c_stage_momentum.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8c','QUALIFIED_BY',object_id,'A','temporary stage-momentum campaign runner' FROM artifacts WHERE path='scripts/run_0493x8c_stage_momentum.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8d','ANALYZED_BY',object_id,'A','analytical Poiseuille/Brinkman qualification analyzer' FROM artifacts WHERE path='matlab/analyze_0493x8d_q6gf_poiseuille_qualification.m';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8d','QUALIFIED_BY',object_id,'A','Q6-g-f physical-wall/chi qualification runner' FROM artifacts WHERE path='scripts/run_0493x8d_q6gf_poiseuille_qualification.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8e','QUALIFIED_BY',object_id,'A','fresh Q6-g-f TG viscosity ensemble' FROM artifacts WHERE path='scripts/run_0493x8e_q6gf_tg_viscosity_ensemble.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8e','QUALIFIED_BY',object_id,'A','Darcy stiffness sweep based on fresh viscosity' FROM artifacts WHERE path='scripts/run_0493x8e_q6gf_darcy_alpha_sweep.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8f','QUALIFIED_BY',object_id,'A','first open Q6-g-f VK runner' FROM artifacts WHERE path='scripts/run_0493x8f_q6gf_vk_re65.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8g','QUALIFIED_BY',object_id,'A','true-fullface mass-balance VK runner' FROM artifacts WHERE path='scripts/run_0493x8g_q6gf_vk_fullface_mass_smoke.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8h','IMPLEMENTED_IN',object_id,'A','hydrodynamic restart runner' FROM artifacts WHERE path='scripts/run_0493x8h_q6gf_vk_restart.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8i','ANALYZED_BY',object_id,'A','established-wake POD/probe analyzer' FROM artifacts WHERE path='matlab/analyze_vk_established_0493x8i.m';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8j','ANALYZED_BY',object_id,'A','nondimensional literature-comparison analyzer' FROM artifacts WHERE path='matlab/analyze_vk_nondim_0493x8j.m';
