-- V4.12: consolidate the post-x7e generalisation/qualification/performance/diagnostic
-- sequence x7f -> x7n.  Split the retrospective x7k/x7l aggregate, restore the
-- substantive x7m-fix1 pressure-domain correction and add the missing x7n
-- path-selectable diagnostic calibrator.
--
-- Scope intentionally stops before the repair sequence x7d-v2 -> x7q.  x7f-fix1
-- is preserved as historical runner plumbing but is not promoted to a canonical
-- milestone; x7n fix1..fix4c are tooling refinements inside x7n, not separate
-- physical milestones.

-- Replace the retrospective telemetry aggregate by the two actual stages.
DELETE FROM objects WHERE object_id='milestone:reference:x7k/x7l';

-- Consolidate existing canonical milestones x7f..x7j.
UPDATE milestones
SET group_name='x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
    name='Extension Q6-g-f aux familles statiques multi-BC',
    summary='Généralise le chemin free_surface_masked + prestream_single_fused du dam-break aux familles statiques déjà supportées par le backend résident (périodique, canal à parois, boîte fermée, IO plein et segmenté) et rend la projection pré-transport active même à force volumique nulle. Les équations x6f/x6g/x7d/B1 ne changent pas.',
    nature='CODE', domain='Q6_GF',
    status='Actif sur les familles statiques qualifiées; Darcy encore exclu à cette étape',
    confidence='A',
    notes='Le patch est une généralisation de chemin/frontières, pas un nouveau modèle de projection. Le resampling n''est pas élargi et les domaines mobiles/immersed-solid restent exclus.',
    source_file='README_0493X7F_Q6_G_F_MULTIBC.md', source_row=NULL
WHERE object_id='milestone:0493x7f';

UPDATE milestones
SET group_name='x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
    name='Correctif de garde wall-simple pour canal mixte',
    summary='Corrige la garde du chemin résident wall-simple afin qu''un canal périodique-x avec faces solides/specular en y soit accepté sans exiger artificiellement wallVP. La règle de collision/réflexion elle-même n''est pas modifiée.',
    nature='FIX', domain='Q6_GF', status='Correctif actif du périmètre x7f', confidence='A',
    notes='Le patch x7f-fix1 séparé ne corrige que l''initialisation LiveVis du runner sous set -u et reste volontairement non canonique. x7f-fix2 est au contraire une correction de garde du chemin de calcul résident.',
    source_file='README_0493X7F_Q6_G_F_MULTIBC.md', source_row=NULL
WHERE object_id='milestone:0493x7f-fix2';

UPDATE milestones
SET group_name='x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
    name='Darcy-Brinkman placé avant la projection Q6-g-f',
    summary='Étend x7f au domaine fictif Darcy/chi résident en appliquant la relaxation déterministe de vitesse avant le solve Q6-g-f pré-transport, puis en supprimant l''ancien replay post-collision pour ce chemin afin d''éviter double application et recréation de divergence après projection.',
    nature='CODE', domain='Q6_GF', status='Actif sur le sous-ensemble Darcy/chi qualifié', confidence='A',
    notes='Le kernel Darcy résident existant est réutilisé. Le premier périmètre qualifié impose un domaine fictif rempli, sans darcyInitialDeactivateBelowChi, afin que chi ne fabrique pas une fausse surface libre.',
    source_file='README_0493X7G_Q6_G_F_DARCY.md', source_row=NULL
WHERE object_id='milestone:0493x7g';

UPDATE milestones
SET group_name='x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
    name='Factorisation des comparaisons run_ok SRC / Q6 / Q6-g-f',
    summary='Introduit le chemin explicite src-q6-g-f dans les helpers/runners historiques et factorise le profil x4b+x6c+x6f+x6g si gaz+B1+x7d sans modifier les équations. Les démonstrations run_ok deviennent des comparateurs reproductibles entre SRC, Q6 historique et Q6-g-f.',
    nature='INFRA', domain='Q6_GF', status='Infrastructure de démonstration et régression', confidence='A',
    notes='Les run_ok restent les démonstrations historiques stabilisées. x7h ajoute le routage/comparaison et le dam-break run_ok; les campagnes nouvelles spécialisées restent des run_*.',
    source_file='README_0493X7H_RUN_OK_Q6_G_F_COMPARISON.md', source_row=NULL
WHERE object_id='milestone:0493x7h';

UPDATE milestones
SET group_name='x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
    name='Benchmark physique multi-cas SRC / Q6 / Q6-g-f',
    summary='Compare les trois chemins sur Taylor-Green forcé, Poiseuille, bend-pipe Darcy et same-face IO à partir de dumps particulaires et d''analyses hors ligne. La campagne mesure compressibilité structurée, profil/transport effectif et propagation de démarrage sans changer le solveur.',
    nature='BENCHMARK', domain='Q6_GF', status='Benchmark diagnostique de référence; sans seuil PASS/FAIL arbitraire', confidence='A',
    notes='Le README qualifie explicitement la campagne de physique mais précise qu''elle est diagnostic-driven et non threshold-driven. BENCHMARK est donc conservé plutôt que QUALIFICATION binaire.',
    source_file='README_0493X7I_Q6_G_F_PHYSICAL_QUALIFICATION.md', source_row=NULL
WHERE object_id='milestone:0493x7i';

UPDATE milestones
SET group_name='x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
    name='CG Q6-g-f entièrement CUDA résident',
    summary='Supprime les réductions et synchronisations GPU-vers-host à chaque itération du CG masqué x6f en remplaçant la boucle hôte par un noyau coopératif résident couvrant la récurrence de Krylov complète; la physique, le RHS, le stencil et B1 restent inchangés.',
    nature='PERF', domain='Q6_GF', status='Optimisation majeure du solve Q6-g-f; fallback hôte conservé', confidence='A',
    introduced_date='2026-08-10', introduced_commit='8e11eefc50a7b16ff67aa57d5149f5e6ae7dae0f',
    notes='Le sujet Git 0493x7j constitue une preuve explicite d''introduction distincte des commits ultérieurs de documentation. Le cas TG x7i avait isolé ~164 itérations comparables mais un coût de solve dominant dû aux synchronisations hôte.',
    source_file='README_0493X7J_Q6_G_F_RESIDENT_CG.md', source_row=NULL
WHERE object_id='milestone:0493x7j';

-- x7k and x7l are separate performance stages introduced together in one commit.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7k','MILESTONE','x7k','curation:0013_0493x7f_x7n_postqualification');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7k','0493x7k','x7k','0493x7k',
  'x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
  'Stripping des diagnostics Q6-g-f en production',
  'Conserve tous les diagnostics d''échec mais ne calcule les audits/réductions coûteux du chemin Q6-g-f qu''au premier pas et à la cadence summaryEvery. Aucun paramètre physique ni opérateur n''est modifié.',
  'PERF','Q6_GF','Optimisation de télémétrie active en production','A',
  '2026-08-10','f12cfe7c65e4acffdfb4a7040dc291dfd3f1e908',NULL,
  'x7k et x7l sont introduits ensemble par le commit explicitement nommé 0493x7k-x7l mais possèdent chacun un README et un patch propres. Le candidat composite Git reste une provenance de commit, pas un jalon canonique composite.',
  'README_0493X7K_Q6_G_F_PRODUCTION_DIAGNOSTICS_STRIP.md',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7l','MILESTONE','x7l','curation:0013_0493x7f_x7n_postqualification');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7l','0493x7l','x7l','0493x7l',
  'x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
  'Stripping de la télémétrie thermostat/espèces',
  'Supprime des pas de production Q6-g-f les téléchargements et réductions de télémétrie thermostat/espèces, tout en conservant la séquence physique deposit/kinetic/scale/apply et les diagnostics à la cadence x7k.',
  'PERF','Q6_GF','Optimisation de télémétrie active; thermostat physique inchangé','A',
  '2026-08-10','f12cfe7c65e4acffdfb4a7040dc291dfd3f1e908',NULL,
  'Le suffixe fix1 du nom de patch archivé correspond à une correction de la réalisation du stripping x7l; le jalon historique identifié par README/commit reste x7l.',
  'README_0493X7L_Q6_G_F_PRODUCTION_THERMOSTAT_TELEMETRY_STRIP.md',NULL
);

-- x7m initial monophase guard.
UPDATE milestones
SET group_name='x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
    name='Garde topologique monophase par registre de phases',
    summary='Évite qu''une fluctuation alpha<0.5 soit interprétée comme interface physique dans un cas explicitement monophase : la présence d''une phase gaz enregistrée devient l''autorité qui active le stencil d''interface x6f. La première version conserve toutefois pressureMask=carrierMask en monophase.',
    nature='CODE', domain='Q6_GF', status='Étape initiale; complétée par x7m-fix1', confidence='A',
    notes='Le same-face IO 300x300 avait créé une fausse interface avec carrier complet mais un pressureMask amputé. x7m sépare d''abord la notion de phase enregistrée de la fluctuation alpha; le problème des cellules temporairement vides subsiste jusqu''à fix1.',
    source_file='README_0493X7M_Q6_G_F_MONOPHASE_INTERFACE_GUARD.md', source_row=NULL
WHERE object_id='milestone:0493x7m';

-- x7m-fix1: substantive pressure-domain correction, explicitly preserved although no Git candidate exists.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7m-fix1','MILESTONE','x7m-fix1','curation:0013_0493x7f_x7n_postqualification');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7m-fix1','0493x7m-fix1','x7m-fix1','0493x7m-fix1',
  'x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
  'Domaine de pression monophase persistant',
  'Corrige x7m en rendant le pressureMask monophase égal au domaine de calcul complet, indépendamment de l''occupation particulaire instantanée. Une cellule MPCD temporairement vide reste un inconnu de pression mais pas un support de vitesse inventé.',
  'FIX','Q6_GF','Correctif structurel actif du chemin monophase','A',
  NULL,NULL,NULL,
  'Le bend-pipe avait perdu deux cellules carrier après 613 pas, créant cinq faces tronquées et une composante pure Neumann incompatible. Le patch historique x7m-fix1 est une preuve primaire même sans candidat Git autonome; les cas deux-phases restent inchangés.',
  'README_0493X7M_Q6_G_F_MONOPHASE_INTERFACE_GUARD.md',NULL
);

-- x7n: missing canonical diagnostic/calibration milestone.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7n','MILESTONE','x7n','curation:0013_0493x7f_x7n_postqualification');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7n','0493x7n','x7n','0493x7n',
  'x7f-x7n : généralisation, qualification, performance et diagnostic Q6-g-f',
  'Calibrateur de fluide sélectionnable par chemin et diagnostic compression/bruit',
  'Étend le calibrateur 0493w1 sans modifier celui-ci afin de caractériser explicitement src, src-q6 et src-q6-g-f, et ajoute les analyses hors ligne utilisées pour distinguer transport intrinsèque, fluctuations d''occupation et compression cohérente. Cette étape fournit le diagnostic qui motive la réparation ultérieure x7d-v2.',
  'DIAGNOSTIC','Q6_GF','Diagnostic/calibrateur de chemin; précède les corrections x7d-v2 et la qualification x7q','A',
  NULL,NULL,NULL,
  'Le commit qui introduit README/runner/analyseurs x7n porte le sujet "defaut x7d compression/bruit identifié via Poiseuille+TG, Dambreak confirmé ok" : il atteste le diagnostic mais ne nomme pas x7n dans le sujet, donc il n''est pas forcé ici comme introduced_commit. Les fix1..fix4c de l''outillage x7n restent des sous-révisions du calibrateur, non des jalons physiques autonomes.',
  'README_0493X7N_PATH_SELECTABLE_FLUID_CALIBRATOR.md',NULL
);

-- Preserve the retrospective reference row as provenance for each split telemetry stage.
INSERT INTO evidence(object_id,evidence_type,path,line_hint,confidence,notes)
SELECT 'milestone:0493x7k','REFERENCE_TEX','Info/inputs/snapshots/referentiel_jalons_SRC_GPU_SURF_20260905.tex','75','B','Original retrospective x7k/x7l aggregate row, split by V4.12'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7k' AND evidence_type='REFERENCE_TEX' AND line_hint='75');
INSERT INTO evidence(object_id,evidence_type,path,line_hint,confidence,notes)
SELECT 'milestone:0493x7l','REFERENCE_TEX','Info/inputs/snapshots/referentiel_jalons_SRC_GPU_SURF_20260905.tex','75','B','Original retrospective x7k/x7l aggregate row, split by V4.12'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7l' AND evidence_type='REFERENCE_TEX' AND line_hint='75');

-- Primary historical source evidence.  x7f-fix1 is deliberately attached to x7f
-- as a non-canonical runner repair, while x7f-fix2 and x7m-fix1 are canonical FIXes.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7f','HISTORICAL_PATCH','Info/inputs/historical/0493x7f_q6_g_f_multibc.patch','A','Original x7f multi-BC patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7f' AND path='Info/inputs/historical/0493x7f_q6_g_f_multibc.patch');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7f','HISTORICAL_PATCH','Info/inputs/historical/0493x7f_fix1_livevis_env_init.patch','A','Preserved non-canonical runner-only x7f-fix1: LiveVis environment initialization under set -u'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7f' AND path='Info/inputs/historical/0493x7f_fix1_livevis_env_init.patch');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7f-fix2','HISTORICAL_PATCH','Info/inputs/historical/0493x7f_fix2_mixed_wall_channel_guard.patch','A','Primary x7f-fix2 mixed wall/simple channel guard patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7f-fix2' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7g','HISTORICAL_PATCH','Info/inputs/historical/0493x7g_q6_g_f_darcy_resident.patch','A','Original x7g Darcy-before-Q6-g-f patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7g' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7h','HISTORICAL_PATCH','Info/inputs/historical/0493x7h_run_ok_q6_g_f_comparison.patch','A','Rebased historical x7h run_ok comparison patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7h' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7i','HISTORICAL_PATCH','Info/inputs/historical/0493x7i_q6_g_f_physical_qualification.patch','A','Original x7i physical comparison/analysis patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7i' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7j','HISTORICAL_PATCH','Info/inputs/historical/0493x7j_q6_g_f_fully_resident_cooperative_cg.patch','A','Original x7j fully resident cooperative-CG patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7j' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7k','HISTORICAL_PATCH','Info/inputs/historical/0493x7k_q6_g_f_production_diagnostics_strip.patch','A','Original x7k production diagnostics strip patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7k' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7l','HISTORICAL_PATCH','Info/inputs/historical/0493x7l_q6_g_f_production_thermostat_telemetry_strip.patch','A','Historical x7l production thermostat/species telemetry strip patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7l' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7m','HISTORICAL_PATCH','Info/inputs/historical/0493x7m_q6_g_f_monophase_interface_guard.py','A','Original x7m monophase phase-registry guard patcher'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7m' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7m-fix1','HISTORICAL_PATCH','Info/inputs/historical/0493x7m_fix1_monophase_full_pressure_domain.py','A','Primary x7m-fix1 full pressure-domain patcher'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7m-fix1' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7n','HISTORICAL_PATCH','Info/inputs/historical/0493x7n_path_selectable_fluid_calibrator.py','A','Original x7n path-selectable calibrator patcher'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7n' AND evidence_type='HISTORICAL_PATCH');

-- Causal/semantic chain.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7f','BUILDS_ON','milestone:0493x7e','A','x7f generalises the x7e-qualified Q6-g-f composition to static resident BC families');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7f-fix2','FIXES','milestone:0493x7f','A','wall-simple topology guard correction within x7f multi-BC support');
UPDATE relations
SET confidence='A',
    evidence_text='wall-simple topology guard correction within x7f multi-BC support; primary x7f-fix2 historical patch'
WHERE source_object_id='milestone:0493x7f-fix2'
  AND relation_type='FIXES'
  AND target_object_id='milestone:0493x7f';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7g','BUILDS_ON','milestone:0493x7f-fix2','A','x7g adds Darcy/chi ordering after the corrected static-BC path');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7h','BUILDS_ON','milestone:0493x7g','A','x7h exposes the current Q6-g-f stack, including Darcy-capable cases, through common run_ok routing');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7i','BUILDS_ON','milestone:0493x7h','A','x7i turns the x7h comparison entrypoints into a controlled physical benchmark');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7j','BUILDS_ON','milestone:0493x7i','A','the x7i TG performance audit motivates the fully resident CG optimization');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7k','BUILDS_ON','milestone:0493x7j','A','after resident CG, x7k removes remaining every-step Q6-g-f diagnostic overhead');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7l','BUILDS_ON','milestone:0493x7k','A','x7l extends the production telemetry strip to thermostat/species diagnostics');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7m','BUILDS_ON','milestone:0493x7l','A','x7m addresses the monophase topology defect exposed during multi-case qualification');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7m-fix1','FIXES','milestone:0493x7m','A','persistent full pressure domain repairs transient carrier holes left by initial x7m');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7n','BUILDS_ON','milestone:0493x7m-fix1','A','x7n characterises the corrected path and isolates the remaining density-compression/noise issue');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7n','REFERENCES','milestone:0493x7d','B','x7n diagnostics explicitly target the density-relaxation behaviour inherited from x7d');

-- Explicit implementation/qualification artifacts when present in the scanned repository.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7f','QUALIFIED_BY',object_id,'A','x7f static multi-BC runner/checker'
FROM artifacts WHERE path IN ('scripts/run_0493x7f_q6_g_f_multibc_validation.sh','scripts/check_0493x7f_q6_g_f_multibc.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7g','QUALIFIED_BY',object_id,'A','x7g Darcy qualification runner/checker'
FROM artifacts WHERE path IN ('scripts/run_0493x7g_q6_g_f_darcy_validation.sh','scripts/check_0493x7g_q6_g_f_darcy.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7i','QUALIFIED_BY',object_id,'A','x7i physical comparison runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x7i_q6_g_f_physical_qualification.sh','matlab/analyze_0493x7i_q6_g_f_qualification.m');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7j','IMPLEMENTED_IN',object_id,'A','fully resident cooperative CG implementation'
FROM artifacts WHERE path='src/cuda_q6_resident_0400.cu';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','x7k/x7l production telemetry routing in resident CUDA path'
FROM milestones m JOIN artifacts a ON a.path='src/cuda_q6_resident_0400.cu'
WHERE m.object_id IN ('milestone:0493x7k','milestone:0493x7l');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','monophase pressure/interface guard in resident CUDA path'
FROM milestones m JOIN artifacts a ON a.path='src/cuda_q6_resident_0400.cu'
WHERE m.object_id IN ('milestone:0493x7m','milestone:0493x7m-fix1');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7n','ANALYZED_BY',object_id,'A','x7n path calibrator / density diagnostics'
FROM artifacts WHERE path IN (
 'scripts/run_0493x7n_path_fluid_calibrator.sh',
 'scripts/analyze_0493x7n_tg_only.py',
 'scripts/analyze_0493x7n_density_noise_gate_offline.py',
 'scripts/analyze_0493x7n_compression_noise_gate_long.py',
 'scripts/analyze_0493x7n_density_filters_offline.py',
 'scripts/analyze_0493x7n_density_spectrum.py',
 'scripts/analyze_0493x7n_compression_estimator_offline.py'
);
