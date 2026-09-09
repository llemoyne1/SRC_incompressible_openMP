-- 0491 historical species-aware Q6 series.
-- A,D-H,H-fix1 are directly Git-attested in the surviving tree. B/C are restored in
-- V4.4 because the archived 0491 design and the later consolidated technical report
-- explicitly describe them as development gates that were actually traversed.
-- Absence of a numeric Git candidate is therefore not interpreted as absence of a
-- documented historical milestone.

CREATE TEMP TABLE _cur_0491(
  milestone_id TEXT PRIMARY KEY,
  milestone_key TEXT NOT NULL,
  name TEXT NOT NULL,
  summary TEXT NOT NULL,
  nature TEXT NOT NULL,
  status TEXT NOT NULL,
  source_file TEXT NOT NULL,
  evidence_type TEXT NOT NULL,
  evidence_confidence TEXT NOT NULL,
  milestone_confidence TEXT NOT NULL
);

INSERT INTO _cur_0491 VALUES
('0491A','history:0491a','Contrat Q6 sensible à l''espèce',
 'Formalise la distribution de correction Q6 par espèce et fournit un référentiel CPU analytique pour vérifier pondérations, conservation barycentrique et modes de repli.',
 'INFRA','Jalon historique documenté','README_0491A_SPECIES_Q6_CONTRACT.md','MILESTONE_README','A','A'),
('0491B','history:0491b','Dépôt partagé et shadow CUDA species-Q6',
 'Calcule sur GPU les poids et résidus species-Q6 à partir du dépôt cellule-espèce 0490H, en mode shadow sans application dynamique, afin de comparer le calcul CUDA à la référence CPU 0491A.',
 'CODE','Jalon historique attesté par documentation technique','Info/inputs/historical/conception_q6_multiespeces_cuda_resident_0491.tex','HISTORICAL_TECHNICAL_DOCUMENT','A','B'),
('0491C','history:0491c','Application CUDA opt-in du Q6 par espèce',
 'Introduit l''application pondérée par type dans le chemin Q6 CUDA résident, en remplaçant uniquement l''application particulaire de la correction tout en conservant le dépôt barycentrique, le solveur, les conditions limites et les diagnostics historiques.',
 'CODE','Jalon historique attesté par documentation technique','Info/inputs/historical/rapport_mpcd_incompressible_complete_0493w1_calibration_q6_multiespeces.tex','HISTORICAL_TECHNICAL_DOCUMENT','A','B'),
('0491D','history:0491d','Matrice des chemins species-Q6',
 'Qualifie l''activation du Q6 sensible à l''espèce sur les chemins src, src-resampling, src-q6 et src-q6-resampling avec contrôle des résidus et de la configuration résidente.',
 'QUALIFICATION','Qualification historique','scripts/run_0491d_species_q6_path_matrix.sh','QUALIFICATION_RUNNER','A','A'),
('0491E','history:0491e','Audit strict du Q6 résident par espèce',
 'Vérifie le contrat strictement résident du species-Q6 : exécution device-resident, absence de tableaux cellule-espèce hôte, de transfert de poids H2D, de téléchargement complet d''état et de fallback CPU.',
 'QUALIFICATION','Qualification historique','scripts/run_0491e_species_q6_strict_resident_audit.sh','QUALIFICATION_RUNNER','A','A'),
('0491F','history:0491f','Validation énergie et thermostat du species-Q6',
 'Compare les modes Q6 commun et pondéré avec et sans thermostat, en contrôlant résidu Q6, conservation de masse, dérive de vitesse moyenne et comportement thermique.',
 'QUALIFICATION','Qualification historique','scripts/run_0491f_species_q6_energy_validation.sh','QUALIFICATION_RUNNER','A','A'),
('0491G','history:0491g','Qualification frontières ouvertes et Darcy du species-Q6',
 'Vérifie la compatibilité du chemin Q6 par espèce avec les familles de frontières ouvertes et Darcy-Brinkman tout en maintenant les garanties de résidence GPU et l''absence de fallback CPU.',
 'QUALIFICATION','Qualification historique','scripts/run_0491g_species_q6_boundary_darcy_matrix.sh','QUALIFICATION_RUNNER','A','A'),
('0491H','history:0491h','Campagne consolidée de validation species-Q6',
 'Consolide les validations de chemins, résidence stricte, énergie, frontières/Darcy, cas personnalisés et runs longs, avec contrôles de masse par espèce, résidu Q6, allocations et coûts par nombre d''espèces.',
 'QUALIFICATION','Qualification historique consolidée','scripts/run_0491h_species_q6_software_validation.sh','QUALIFICATION_RUNNER','A','A'),
('0491H-fix1','history:0491h-fix1','Correctif final et qualification approfondie species-Q6',
 'Consolide le correctif final du chemin Q6 sensible aux espèces par une qualification approfondie : longueurs exactes, équivalence d''état, thermostat, interface, espèce trace, runs fermés longs et politique cellule device issue de 0490P.',
 'FIX','Correctif historique qualifié','README_0491H_FIX1_DEEP_QUALIFICATION.md','MILESTONE_README','A','A');

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
SELECT 'milestone:' || milestone_key,'MILESTONE',milestone_id,'curation:0003_0491'
FROM _cur_0491;

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row
)
SELECT
  'milestone:' || milestone_key,milestone_key,milestone_id,milestone_key,
  '0491 : Q6 multi-espèces — contrat, intégration CUDA et qualification',
  name,summary,nature,'SPECIES_Q6',status,
  milestone_confidence,NULL,NULL,NULL,
  CASE WHEN milestone_id IN ('0491B','0491C')
       THEN 'V4.4 : jalon restauré à partir des archives techniques 0491 et du rapport rétrospectif 0493w1. Aucun SHA n''est forcé en l''absence de candidat Git numérique sûr.'
       ELSE 'Curation historique fondée sur les sources/runners 0491; date et commit sont réconciliés après import Git uniquement lorsque l''ancrage numérique est non ambigu.' END,
  source_file,NULL
FROM _cur_0491;

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:' || milestone_key,evidence_type,source_file,evidence_confidence,
       CASE evidence_type
         WHEN 'MILESTONE_README' THEN 'README dédié au jalon 0491.'
         WHEN 'QUALIFICATION_RUNNER' THEN 'Runner de qualification portant explicitement le jalon 0491.'
         WHEN 'HISTORICAL_TECHNICAL_DOCUMENT' THEN 'Archive technique versionnée sous Info/ attestant explicitement ce jalon malgré l''absence de candidat Git numérique survivant.'
         ELSE 'Source représentative du jalon 0491.'
       END
FROM _cur_0491;

-- Current implementation traces for the two documentation-attested gates.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0491b','IMPLEMENTED_IN',object_id,'B','0491B shadow/deposit machinery was subsequently folded into the resident Q6/species path'
FROM artifacts
WHERE path IN ('src/cuda_q6_resident_0400.cu','include/cuda_q6_resident_0400.h');

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0491c','IMPLEMENTED_IN',object_id,'A','current source explicitly preserves the 0491C CUDA-resident species-Q6 application contract'
FROM artifacts
WHERE path IN ('src/cuda_q6_resident_0400.cu','include/cuda_q6_resident_0400.h','src/q6_projection_adapter.cpp');

-- Link representative current artifacts for Git-attested rows.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:' || c.milestone_key,
       CASE c.evidence_type
         WHEN 'MILESTONE_README' THEN 'DOCUMENTED_BY'
         WHEN 'QUALIFICATION_RUNNER' THEN 'QUALIFIED_BY'
         ELSE 'DOCUMENTED_BY'
       END,
       a.object_id,c.evidence_confidence,'0491 curated primary evidence'
FROM _cur_0491 c
JOIN artifacts a ON lower(a.path)=lower(c.source_file) OR lower(a.basename)=lower(c.source_file);

-- Historical dependency chain.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:history:0491a','BUILDS_ON','milestone:history:0490p','A','species-Q6 follows the completed resident multi-species cell policy'),
('milestone:history:0491b','EXTENDS','milestone:history:0491a','A','GPU shadow implementation of the 0491A contract'),
('milestone:history:0491c','EXTENDS','milestone:history:0491b','A','opt-in CUDA-resident species-weighted application'),
('milestone:history:0491d','QUALIFIES','milestone:history:0491c','A','path matrix validates the implemented species-Q6 path'),
('milestone:history:0491e','QUALIFIES','milestone:history:0491c','A','strict resident audit validates the implemented species-Q6 path'),
('milestone:history:0491f','QUALIFIES','milestone:history:0491c','A','energy/thermostat validation'),
('milestone:history:0491g','QUALIFIES','milestone:history:0491c','A','boundary/Darcy validation'),
('milestone:history:0491h','CONSOLIDATES','milestone:history:0491d','A','full species-Q6 campaign'),
('milestone:history:0491h','CONSOLIDATES','milestone:history:0491e','A','full species-Q6 campaign'),
('milestone:history:0491h','CONSOLIDATES','milestone:history:0491f','A','full species-Q6 campaign'),
('milestone:history:0491h','CONSOLIDATES','milestone:history:0491g','A','full species-Q6 campaign'),
('milestone:history:0491h-fix1','FIXES','milestone:history:0491h','A','final deep-qualified correction');

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0491h','QUALIFIED_BY',object_id,'A','0491H consolidated campaign artifact'
FROM artifacts
WHERE path IN ('scripts/run_0491h_species_q6_full_campaign.sh','scripts/summarize_0491h_species_q6_software_validation.py');

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0491h','DOCUMENTED_BY',object_id,'A','0491H run_ok / LiveVis validation record'
FROM artifacts WHERE basename='README_0491H_RUN_OK_LIVEVIS_VALIDATION.md';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0491h-fix1','QUALIFIED_BY',object_id,'A','0491H-fix1 deep qualification artifact'
FROM artifacts
WHERE path IN ('scripts/run_0491h_fix1_deep_qualification.sh','scripts/summarize_0491h_fix1_deep_qualification.py');

DROP TABLE _cur_0491;
