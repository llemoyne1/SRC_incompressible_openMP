-- 0493o -> 0493w historical transition:
-- local support repair, constitutive SRC calibration, calibrated segmented/Darcy
-- reference, generic multi-species injection runners, and independent_masked Q6.
--
-- Admission policy:
--   * preserve labels explicitly attested by Git, code, runners/checkers, or README;
--   * do not manufacture missing bases (notably no autonomous 0493O2 is created: the
--     surviving explicit label is 0493O2-fix1);
--   * a grouped Git checkpoint may contain several independently attested sub-jalons.

CREATE TEMP TABLE _cur_0493ow(
  milestone_id TEXT PRIMARY KEY,
  milestone_key TEXT NOT NULL,
  group_name TEXT NOT NULL,
  name TEXT NOT NULL,
  summary TEXT NOT NULL,
  nature TEXT NOT NULL,
  domain TEXT NOT NULL,
  status TEXT NOT NULL,
  source_file TEXT NOT NULL,
  evidence_type TEXT NOT NULL,
  evidence_confidence TEXT NOT NULL,
  milestone_confidence TEXT NOT NULL
);

INSERT INTO _cur_0493ow VALUES
('0493O0','history:0493o0','0493o : références SRC et réparation locale du support',
 'Références SRC seules avant réparation locale du support',
 'Établit deux références SRC-only sans Q6 ni resampling mutant : Taylor--Green périodique et cas segmented inlet/outlet avec obstacle Darcy/chi. Les diagnostics de support restent passifs afin de mesurer le problème avant toute réparation.',
 'BENCHMARK','MULTISPECIES_RESAMPLING','Référence historique pré-réparation',
 'scripts/check_0493o0_src_baseline_runners.sh','QUALIFICATION_CHECKER','A','A'),
('0493O1','history:0493o1','0493o : références SRC et réparation locale du support',
 'Population effective cible : split local piloté par Neff',
 'Introduit le mode résident split-only piloté par Neff=(sum m)^2/sum(m^2) pour chaque paire cellule/espèce active. Une paire pauvre est réparée vers NTarget par scission déterministe des fragments les plus lourds, avec conservation locale masse, impulsion et énergie cinétique.',
 'CODE','MULTISPECIES_RESAMPLING','Jalon historique documenté',
 'README_0493O1_TARGET_DRIVEN_NEFF_SPLIT_GUARD.md','MILESTONE_README','A','A'),
('0493O1-fix2','history:0493o1-fix2','0493o : références SRC et réparation locale du support',
 'Autorité CUDA du split-only local',
 'Rend le guard CUDA split-only autoritaire et interdit le repli vers l''ancien population guard CPU. Ce repli pouvait appliquer des merges malgré extraction=false et créer des trous dans l''active prefix avant resynchronisation.',
 'FIX','MULTISPECIES_RESAMPLING','Correctif de sûreté résident attesté par le code',
 'scripts/check_0493o1_fix2_cuda_authority.sh','QUALIFICATION_CHECKER','A','A'),
('0493O2-fix1','history:0493o2-fix1','0493o : références SRC et réparation locale du support',
 'Runner TG mono/dual-espèces pour la réparation de support',
 'Étend le runner TG de O1 à un mode dual-espèces contrôlé : seul le tableau des types est réécrit en répartition locale équilibrée, tandis que positions, vitesses, masses et rôles restent identiques à l''état TG de référence. Aucun jalon O2 de base n''est reconstruit.',
 'FIX','MULTISPECIES_RESAMPLING','Sous-jalon historique explicitement attesté',
 'scripts/check_0493o2_fix1_tg_multispecies_runner.sh','QUALIFICATION_CHECKER','A','A'),
('0493O3','history:0493o3','0493o : références SRC et réparation locale du support',
 'Early-exit résident lorsqu''aucune paire cellule/espèce n''est pauvre',
 'Ajoute une détection anticipée des paires pauvres. Si aucune réparation n''est requise, le chemin évite préparation cinétique, collecte de candidats, planification, mutation et contrôles post-mutation, tout en exposant des chronométrages dédiés.',
 'PERF','MULTISPECIES_RESAMPLING','Optimisation résidente historique',
 'scripts/check_0493o3_no_poor_early_exit.sh','QUALIFICATION_CHECKER','A','A'),
('0493O4','history:0493o4','0493o : références SRC et réparation locale du support',
 'Qualification de la réparation de support en segmented-Darcy',
 'Restaure une comparaison appariée baseline/réparation sur le cas segmented inlet/outlet + Darcy/chi, avec registre d''espèces strict, split-only activable, empty-refill/mass-guard/thermal-renormalization désactivés et paramètres identiques hors réparation.',
 'QUALIFICATION','MULTISPECIES_RESAMPLING','Qualification historique',
 'scripts/check_0493o4_segmented_darcy_support_repair_runner.sh','QUALIFICATION_CHECKER','A','A'),

('0493W0','history:0493w0','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Audit du régime cinétique du cas segmented-Darcy',
 'Balaye le régime SRC-only du cas cylindre/Darcy pour déterminer si lip d''entrée et wake appauvri proviennent d''un régime mésoscopique extrême avant d''attribuer ces effets à un défaut de support. Q6 et réparations mutantes restent désactivés.',
 'BENCHMARK','SRC_CALIBRATION','Diagnostic historique du régime cinétique',
 'scripts/run_0493w0_darcy_kinetic_regime_sweep.sh','QUALIFICATION_RUNNER','A','A'),
('0493W1','history:0493w1','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Calibrateur constitutif du fluide SRC',
 'Caractérise le fluide SRC homogène par Taylor--Green pour la viscosité, réponse longitudinale pour la célérité acoustique et MSD pour l''autodiffusion; en déduit notamment Sc et, lorsque les échelles sont fournies, Re/Ma/Pe.',
 'CALIBRATOR','SRC_CALIBRATION','Calibrateur historique',
 'scripts/run_0493w1_src_fluid_calibrator.sh','CALIBRATION_RUNNER','A','A'),
('0493W2','history:0493w2','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Référence segmented-Darcy sur fluide SRC calibré',
 'Rejoue le cylindre avec entrée/sortie segmentées et Darcy/chi en conservant la taille de cellule et les propriétés mesurées en W1. Le cas devient une référence physique dimensionnée, avec support repair, resampling, refill et reconditionnement désactivés.',
 'BENCHMARK','SRC_CALIBRATION','Référence physique calibrée',
 'scripts/run_0493w2_src_calibrated_segmented_darcy_reference.sh','QUALIFICATION_RUNNER','A','A'),
('0493W3','history:0493w3','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Correction de l''injection sur cellule partielle d''une entrée segmentée',
 'Corrige le traitement des cellules partielles au bord d''une aperture d''entrée segmentée afin que l''injection prescrite reste cohérente avec la fraction effectivement ouverte. Le jalon est conservé par son commit Git explicite.',
 'FIX','BOUNDARY','Correctif historique attesté par Git',
 'git:9355b6b','GIT_COMMIT','A','A'),
('0493W4','history:0493w4','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Runner d''injection multi-espèces normalisé par famille de phase',
 'Normalise les runners d''injection autour des familles liquid/gas plutôt que des seuls identifiants de type : forces Q6 et fermeture de masse déclarées, rapport de masses, domaine empty/full, diagnostics species et contrat de post-check deviennent explicites et indépendants du numéro de type.',
 'RUNNER','MULTISPECIES_RUNNER','Jalon de runner attesté par le code et les inventaires',
 'scripts/run_ok_injection_type1_into_type2_empty.sh','IMPLEMENTATION_SOURCE','A','B'),
('0493W5','history:0493w5','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Q6 multi-espèces independent_masked — étape périodique',
 'Introduit speciesQ6Mode=independent_masked : chaque espèce de force Q6 positive construit son propre support à partir de l''occupation mass/referenceCellMass et reçoit son propre solveur masqué; une espèce de force nulle ne reçoit structurellement aucune correction Q6 directe. L''étape initiale est périodique.',
 'CODE','SPECIES_Q6','Jalon historique documenté',
 'README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md','MILESTONE_README','A','A'),
('0493W6','history:0493w6','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Diagnostic de divergence après application du Q6 masqué',
 'Distingue la divergence du flux de face auxiliaire projeté de celle du champ cellulaire redéposé après correction particulaire. Ce diagnostic révèle notamment le mismatch face-vers-cellule aux bords internes d''un support partiellement masqué sans modifier l''opérateur.',
 'DIAGNOSTIC','SPECIES_Q6','Diagnostic historique documenté',
 'README_0493W6_INDEPENDENT_MASKED_POSTAPPLY_DIAGNOSTIC.md','MILESTONE_README','A','A'),
('0493W7','history:0493w7','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Q6 independent_masked sur toutes les familles de frontières résidentes',
 'Étend le solveur Q6 indépendant par espèce aux topologies déjà acceptées par le backend résident : périodique, canal à parois, entrée/sortie pleine face, apertures segmentées et Darcy-Brinkman, sans réintroduire correction barycentrique ni fallback common.',
 'CODE','SPECIES_Q6','Jalon historique documenté et qualifié',
 'README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md','MILESTONE_README','A','A'),
('0493W8','history:0493w8','0493w : régime SRC calibré, runners multi-espèces et Q6 independent_masked',
 'Équivalence Taylor--Green mono / dual-identique du Q6 independent_masked',
 'Qualifie la neutralité du registre et du découpage en types, la non-régression du solveur independent_masked en support plein face au Q6 mono historique, et le transport TG de deux labels indépendamment projetés représentant le même fluide.',
 'QUALIFICATION','SPECIES_Q6','Qualification historique consolidée',
 'README_0493W8_TG_MONO_DUAL_IDENTICAL_EQUIVALENCE.md','MILESTONE_README','A','A');

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
SELECT 'milestone:'||milestone_key,'MILESTONE',milestone_id,'curation:0006_0493ow' FROM _cur_0493ow;

INSERT OR REPLACE INTO milestones(
 object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
 confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
SELECT 'milestone:'||milestone_key,milestone_key,milestone_id,milestone_key,
 group_name,name,summary,nature,domain,status,milestone_confidence,NULL,NULL,NULL,
 CASE
   WHEN milestone_id='0493O2-fix1' THEN 'Le label survivant est explicitement 0493O2-fix1; aucun 0493O2 autonome n''est créé sans preuve.'
   WHEN evidence_type='GIT_COMMIT' THEN 'Jalon conservé par un commit Git explicitement nommé; aucun artefact numéroté survivant n''est requis.'
   WHEN evidence_type='IMPLEMENTATION_SOURCE' THEN 'Jalon conservé par sémantique numérotée dans le runner/code et inventaires; confiance canonique B en l''absence de commit/README dédié.'
   ELSE 'Curation historique 0493o/w fondée sur runner, checker, README et graphe Git.' END,
 source_file,NULL
FROM _cur_0493ow;

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:'||milestone_key,evidence_type,source_file,evidence_confidence,
 CASE evidence_type
   WHEN 'MILESTONE_README' THEN 'README dédié au jalon.'
   WHEN 'GIT_COMMIT' THEN 'Commit Git explicitement nommé pour ce jalon.'
   WHEN 'QUALIFICATION_CHECKER' THEN 'Checker numéroté qui atteste directement le contrat du jalon.'
   WHEN 'QUALIFICATION_RUNNER' THEN 'Runner numéroté qui matérialise le cas de référence/qualification.'
   WHEN 'CALIBRATION_RUNNER' THEN 'Runner de calibration constitutive numéroté.'
   WHEN 'IMPLEMENTATION_SOURCE' THEN 'Runner/code conservant explicitement la sémantique numérotée.'
   ELSE 'Preuve primaire du cycle 0493o/w.' END
FROM _cur_0493ow;

-- Primary repository artifacts when they survive in the current tree.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:'||c.milestone_key,
 CASE c.evidence_type
   WHEN 'MILESTONE_README' THEN 'DOCUMENTED_BY'
   WHEN 'IMPLEMENTATION_SOURCE' THEN 'IMPLEMENTED_IN'
   WHEN 'QUALIFICATION_CHECKER' THEN 'QUALIFIED_BY'
   WHEN 'QUALIFICATION_RUNNER' THEN 'QUALIFIED_BY'
   WHEN 'CALIBRATION_RUNNER' THEN 'CALIBRATED_BY'
   ELSE 'EVIDENCED_BY' END,
 a.object_id,c.evidence_confidence,'0493o/w curated primary artifact'
FROM _cur_0493ow c JOIN artifacts a
 ON lower(a.path)=lower(c.source_file) OR lower(a.basename)=lower(c.source_file);

-- Additional inspectable artifacts for the O-series.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493o0','QUALIFIED_BY',object_id,'A','paired SRC-only O0 baselines/checker'
FROM artifacts WHERE path IN (
 'scripts/run_0493o0_src_baseline_tg.sh',
 'scripts/run_0493o0_src_baseline_segmented_darcy.sh',
 'scripts/check_0493o0_src_baseline_runners.sh');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493o1','IMPLEMENTED_IN',object_id,'A','target-driven Neff split implementation'
FROM artifacts WHERE path='include/cuda_local_support_split_0493o1.cuh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493o1','QUALIFIED_BY',object_id,'A','O1 TG split-guard validation'
FROM artifacts WHERE path IN ('scripts/run_0493o1_tg_split_guard.sh','scripts/check_0493o1_target_driven_neff_split_guard.sh','scripts/test_0493o1_reference_planner.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493o3','ANALYZED_BY',object_id,'A','O3 no-poor early-exit timing/integrity analyzer'
FROM artifacts WHERE path='scripts/analyze_0493o3_no_poor_early_exit.py';

-- Calibration/reference and independent-Q6 artifacts.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493w0','ANALYZED_BY',object_id,'A','W0 kinetic-regime sweep analyzer/checker'
FROM artifacts WHERE path IN ('scripts/analyze_0493w0_darcy_kinetic_regime_sweep.py','scripts/check_0493w0_darcy_kinetic_regime_sweep.sh');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493w1','CALIBRATED_BY',object_id,'A','W1 SRC fluid presweep/calibrator suite'
FROM artifacts WHERE path IN (
 'scripts/run_0493w1_src_fluid_presweep.sh','scripts/run_0493w1_src_fluid_calibrator.sh',
 'scripts/analyze_0493w1_src_fluid_calibrator.py','scripts/check_0493w1_src_fluid_calibrator.sh',
 'scripts/calibrate_src_tg_0493w1_standalone.sh','scripts/calibrate_src_fluid_0493w1_standalone.sh',
 'scripts/calibrate_fluid_0493w1_standalone.sh');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493w5','QUALIFIED_BY',object_id,'A','W5 independent-masked periodic smoke'
FROM artifacts WHERE path IN ('scripts/run_0493w5_independent_masked_periodic_smoke.sh','scripts/generate_0493w5_independent_masked_state.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493w6','QUALIFIED_BY',object_id,'A','W6 post-application diagnostic runner/checker'
FROM artifacts WHERE path IN ('scripts/run_0493w6_independent_masked_postapply_diagnostic.sh','scripts/check_0493w6_independent_masked_postapply.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493w7','QUALIFIED_BY',object_id,'A','W7 multi-boundary-condition resident qualification'
FROM artifacts WHERE path IN ('scripts/run_0493w7_independent_masked_multibc_smoke.sh','scripts/check_0493w7_independent_masked_multibc.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493w8','QUALIFIED_BY',object_id,'A','W8 TG mono/dual-identical equivalence campaign'
FROM artifacts WHERE path IN ('scripts/run_0493w8_tg_mono_dual_equivalence.sh','scripts/analyze_0493w8_tg_mono_dual_equivalence.py','scripts/generate_0493w8_tg_identical_states.py');

-- Historical dependency graph.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:history:0493o0','BUILDS_ON','milestone:history:0493j','B','O0 establishes clean SRC references after the conservative resident closure cycle'),
('milestone:history:0493o1','BUILDS_ON','milestone:history:0493o0','A','target-driven support repair is introduced against the clean O0 reference'),
('milestone:history:0493o1-fix2','FIXES','milestone:history:0493o1','A','makes the CUDA split-only path authoritative and suppresses unsafe CPU fallthrough'),
('milestone:history:0493o2-fix1','EXTENDS','milestone:history:0493o1-fix2','A','adds controlled mono/dual-species TG runner support without inventing a base O2 milestone'),
('milestone:history:0493o3','OPTIMIZES','milestone:history:0493o1-fix2','A','early exit when no cell/species pair requires support repair'),
('milestone:history:0493o4','QUALIFIES','milestone:history:0493o3','A','restores paired segmented-Darcy support-repair qualification'),
('milestone:history:0493w0','BUILDS_ON','milestone:history:0493o4','B','re-audits the application case by varying the SRC kinetic regime before further repair physics'),
('milestone:history:0493w1','CALIBRATES','milestone:history:0493w0','A','replaces theoretical regime estimates with measured SRC transport properties'),
('milestone:history:0493w2','BUILDS_ON','milestone:history:0493w1','A','uses the calibrated constitutive fluid in the segmented-Darcy reference'),
('milestone:history:0493w3','FIXES','milestone:history:0493w2','B','repairs partial-cell segmented inlet injection exposed by the calibrated reference'),
('milestone:history:0493w4','BUILDS_ON','milestone:history:0493w3','B','normalizes the multi-species injection runners used by the following Q6 work'),
('milestone:history:0493w4','BUILDS_ON','milestone:history:0492','A','retains the normalized run_ok/checker contract'),
('milestone:history:0493w5','EXTENDS','milestone:history:0491c','A','adds a structurally independent masked species-Q6 operator to the resident Q6 path'),
('milestone:history:0493w5','BUILDS_ON','milestone:history:0493w4','B','uses the normalized liquid/gas species semantics and runner contract'),
('milestone:history:0493w6','DIAGNOSES','milestone:history:0493w5','A','separates projected face-flux divergence from post-application cell divergence'),
('milestone:history:0493w7','EXTENDS','milestone:history:0493w5','A','removes the periodic-only restriction while preserving the independent operator'),
('milestone:history:0493w7','BUILDS_ON','milestone:history:0493w6','A','keeps the W6 post-application diagnostic contract on the extended BC matrix'),
('milestone:history:0493w8','QUALIFIES','milestone:history:0493w7','A','TG mono/dual-identical equivalence closes the independent-masked Q6 cycle');

DROP TABLE _cur_0493ow;
