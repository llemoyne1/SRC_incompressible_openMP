-- 0490A-P historical multi-species/resident-resampling series.
-- Curated from the dedicated milestone READMEs and Git candidate evidence.
-- Numeric labels are namespaced internally; the post-Git reconciliation pass links
-- each row only when its numeric Git candidate is unique.  This deliberately avoids
-- the unsafe behaviour seen for reused labels such as 0414.

CREATE TEMP TABLE _cur_0490(
  milestone_id TEXT PRIMARY KEY,
  milestone_key TEXT NOT NULL,
  name TEXT NOT NULL,
  summary TEXT NOT NULL,
  nature TEXT NOT NULL,
  status TEXT NOT NULL,
  source_file TEXT NOT NULL
);

INSERT INTO _cur_0490 VALUES
('0490A','history:0490a','Registre des espèces',
 'Introduit le registre multi-espèces et son échafaudage de diagnostics, base nécessaire aux traitements par espèce ultérieurs.',
 'INFRA','Jalon historique documenté','README_0490A_SPECIES_REGISTRY_SCAFFOLD.md'),
('0490B','history:0490b','Dépôt cellule–espèce',
 'Ajoute le dépôt des populations par cellule et par espèce afin de disposer des grandeurs locales nécessaires au resampling multi-espèces.',
 'CODE','Jalon historique documenté','README_0490B_SPECIES_CELL_DEPOSIT.md'),
('0490C','history:0490c','Resampling conservatif par espèce',
 'Introduit le resampling multi-espèces avec conservation explicite des bilans associés aux espèces.',
 'CODE','Jalon historique documenté','README_0490C_SPECIES_CONSERVATIVE_RESAMPLING.md'),
('0490D','history:0490d','Fermeture de masse sensible à la phase',
 'Rend la fermeture de masse du resampling consciente de la phase afin de préserver les bilans dans les cellules multi-espèces.',
 'CODE','Jalon historique documenté','README_0490D_PHASE_AWARE_MASS_CLOSURE.md'),
('0490E','history:0490e','Garde de population par espèce',
 'Ajoute une garde de population par espèce pour empêcher les états locaux non admissibles lors des opérations de resampling.',
 'CODE','Jalon historique documenté','README_0490E_SPECIES_POPULATION_GUARD.md'),
('0490F','history:0490f','Refill d''espèces mixtes',
 'Étend le refill aux cellules contenant plusieurs espèces tout en conservant l''identité des populations.',
 'CODE','Jalon historique documenté','README_0490F_MIXED_SPECIES_REFILL.md'),
('0490G','history:0490g','Transferts donneur–receveur par espèce',
 'Introduit les transferts donneur–receveur spécifiques aux espèces dans la chaîne de resampling.',
 'CODE','Jalon historique documenté','README_0490G_SPECIES_DONOR_RECEIVER_TRANSFERS.md'),
('0490H','history:0490h','Dépôt cellule–espèce CUDA',
 'Porte sur CUDA le dépôt cellule–espèce requis par la chaîne multi-espèces.',
 'CODE','Jalon historique documenté','README_0490H_CUDA_SPECIES_CELL_DEPOSIT.md'),
('0490I','history:0490i','Fermeture de masse multi-espèces CUDA',
 'Porte sur CUDA la fermeture de masse par espèce de la chaîne de resampling.',
 'CODE','Jalon historique documenté','README_0490I_CUDA_SPECIES_MASS_CLOSURE.md'),
('0490J','history:0490j','Garde de population multi-espèces CUDA',
 'Porte sur CUDA la garde de population par espèce.',
 'CODE','Jalon historique documenté','README_0490J_CUDA_SPECIES_POPULATION_GUARD.md'),
('0490K','history:0490k','Plan de transferts multi-espèces CUDA',
 'Construit côté CUDA le plan de transferts donneur–receveur utilisé par le resampling multi-espèces.',
 'CODE','Jalon historique documenté','README_0490K_CUDA_SPECIES_TRANSFER_PLAN.md'),
('0490L','history:0490l','Validation du resampling résident multi-espèces',
 'Valide l''enchaînement CUDA résident des opérations de resampling multi-espèces avant activation du chemin rapide.',
 'QUALIFICATION','Qualification historique','README_0490L_CUDA_SPECIES_RESIDENT_VALIDATION.md'),
('0490M','history:0490m','Chemin rapide résident multi-espèces',
 'Introduit le fast path CUDA résident pour le resampling multi-espèces afin de réduire les passages par le CPU.',
 'PERF','Optimisation historique','README_0490M_CUDA_SPECIES_RESIDENT_FAST_PATH.md'),
('0490M-fix2','history:0490m-fix2','Fermeture conservative multi-espèces',
 'Correctif de fermeture conservative du chemin résident multi-espèces, appliqué après le jalon 0490M.',
 'FIX','Correctif historique','README_0490M_FIX2_SPECIES_CONSERVATIVE_CLOSURE.md'),
('0490N','history:0490n','Maintenance résidente multi-espèces',
 'Ajoute les opérations de maintenance résidente nécessaires à la continuité du resampling multi-espèces sur GPU.',
 'CODE','Jalon historique documenté','README_0490N_CUDA_SPECIES_RESIDENT_MAINTENANCE.md'),
('0490N-fix1','history:0490n-fix1','Télémétrie résidente par espèce',
 'Ajoute la télémétrie de contrôle des populations et bilans par espèce sur le chemin résident.',
 'DIAGNOSTIC','Diagnostic historique','README_0490N_FIX1_RESIDENT_SPECIES_TELEMETRY.md'),
('0490N-fix2','history:0490n-fix2','Matérialisation des transferts multiples',
 'Correctif de matérialisation de plusieurs transferts par cellule dans la maintenance résidente multi-espèces.',
 'FIX','Correctif historique','README_0490N_FIX2_MULTI_TRANSFER_MATERIALIZER.md'),
('0490P','history:0490p','Politique cellule sur device / zéro CPU',
 'Finalise la politique de cellule côté device afin que la chaîne de décision du resampling résident ne dépende plus d''une décision CPU.',
 'PERF','Architecture historique','README_0490P_DEVICE_CELL_POLICY_ZERO_CPU.md');

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
SELECT 'milestone:' || milestone_key,'MILESTONE',milestone_id,'curation:0002_0490'
FROM _cur_0490;

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row
)
SELECT
  'milestone:' || milestone_key,milestone_key,milestone_id,milestone_key,
  '0490 : resampling conservatif multi-espèces et chemin CUDA résident',
  name,summary,nature,'MULTISPECIES_RESAMPLING',status,
  'A',NULL,NULL,NULL,
  'Curation historique fondée sur le README dédié; date et commit sont réconciliés après import Git uniquement si le candidat numérique est unique.',
  source_file,NULL
FROM _cur_0490;

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:' || milestone_key,'MILESTONE_README',source_file,'A',
       'README dédié au jalon 0490; chemin courant résolu par basename quand présent dans le dépôt.'
FROM _cur_0490;

-- Relate the current repository copy of each README when it is present under doc/ or docs/.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:' || c.milestone_key,'DOCUMENTED_BY',a.object_id,'A','dedicated 0490 milestone README'
FROM _cur_0490 c
JOIN artifacts a ON lower(a.basename)=lower(c.source_file);

DROP TABLE _cur_0490;
