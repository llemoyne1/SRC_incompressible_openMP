-- V4.32: hinged-plate FSI subcycling and open-boundary finalization x18e/x18f (2026-09-15)
-- Source-only documentary curation. No x18f-fix1 population lock is promoted.
PRAGMA foreign_keys=ON;

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x18e','MILESTONE','x18e','curation:0032_0493x18e_x18f_hinged_fsi_open_boundaries');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x18e','0493x18e','x18e','0493x18e','solides mobiles / FSI',
  'Sous-cyclage FSI local du volet articulé',
  'Sous-cycle localement collisions particule--volet et ODE rigide tout en conservant le pas global SRC/Q6; ajoute des critères angulaires/géométriques et des gardes anti-hang sur le broad-phase.',
  'FIX','FSI',
  'VALIDATED/FUNCTIONAL: compilation CUDA locale et runs réussis; pas global testé jusqu’à 20x la limite pratique précédente sans reproduire le hang. Pas de revendication de stabilité inconditionnelle ni de speedup wall-time 20x.',
  'A','2026-09-15',NULL,NULL,
  'Le chemin normal reste le sous-cyclage local; le mode qualification conserve la trajectoire historique mono-pas avec gardes. Six paramètres chiSolidHingedFsi*/Max* sont introduits.',
  'Info/docs/CURATION_0493X18E_X18F_HINGED_FSI_V4_32.md',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x18f','MILESTONE','x18f','curation:0032_0493x18e_x18f_hinged_fsi_open_boundaries');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x18f','0493x18f','x18f','0493x18f','solides mobiles / FSI',
  'Frontières ouvertes et initialisation finale du volet',
  'Finalise les runners: x18a inlet uniforme gauche + outlet Neumann droit, x18b double-Neumann outlet-only, top/bottom solides, intégration permanente de x18a-fix2 et pool inactif pour la fermeture cinétique Neumann.',
  'CODE','FSI',
  'MIXED: x18a inlet_neumann VALIDATED/FUNCTIONAL; x18b double_neumann fonctionnel qualitativement mais non qualifié quantitativement en bilan de masse.',
  'A','2026-09-15',NULL,NULL,
  'L’extension outlet-only est limitée au chemin Q6 résident + Neumann; le legacy SRC-classic n’est pas élargi. x18f-fix1 de verrouillage global de population n’a pas été appliqué et n’est pas canonique.',
  'Info/docs/CURATION_0493X18E_X18F_HINGED_FSI_V4_32.md',NULL
);

UPDATE milestones
SET status='VALIDATED/FUNCTIONAL: volet 1-DOF avec sous-cyclage x18e et runner x18f inlet_neumann validé localement sur 200 pas à dt=0.006, FLOW_UX=0.352; terminaison COMPLETE.',
    notes='Configuration de référence pour le futur sweep U->theta: inlet uniforme gauche, outlet Neumann droit, haut/bas solides. Le correctif d’initialisation x18a-fix2 est intégré directement au runner x18f.'
WHERE object_id='milestone:0493x18a';

UPDATE milestones
SET status='INTEGRATED: correctif d’initialisation conservé et câblé durablement dans x18f.',
    notes='HINGED_INITIAL_FLUID_GEOMETRY=auto appelle prepare_0493x18a_initial_fluid.py pour tout angle initial non nul; plus besoin de réappliquer le script x18a-fix2 après un build.'
WHERE object_id='milestone:0493x18a-fix2';

UPDATE milestones
SET status='FUNCTIONAL/QUALITATIVE: chute double-Neumann 2000 pas COMPLETE à FLUID_DENSITY_FACTOR=0.10, sans damping mécanique; non qualifié pour mesure quantitative longue du damping ou bilan stationnaire de masse.',
    notes='Double-Neumann outlet-only: à rho factor 0.01, dérive positive forte (+71338 particules cumulées à ~110 pas) et épuisement du pool; à 0.10, Nfluid 1087414 -> 1053894 (-3.0825%), Nmin=1037481, Nmax=1087891 et dérive tardive ~-25 à -29 particules/pas après ~800 pas. Démonstrateur qualitatif seulement.'
WHERE object_id='milestone:0493x18b';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x18e','BUILDS_ON','milestone:0493x18d','A','x18e conserve le fast path global x18d et sous-cycle seulement le couplage local du volet.');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x18e','FIXES','milestone:0493x18a','A','x18e traite le hang/coût explosif du couplage explicite du volet sous forte excitation.');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x18f','BUILDS_ON','milestone:0493x18e','A','x18f finalise les runners sur la dynamique sous-cyclée x18e.');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x18f','BUILDS_ON','milestone:0493x18a-fix2','A','x18f intègre durablement la géométrie initiale fluide cohérente avec l’angle du volet.');

-- Explicit symbol provenance/usage for the new x18e solver parameters.
INSERT OR REPLACE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x18e','A','V4.32: paramètre solveur introduit par le sous-cyclage FSI x18e'
FROM symbols WHERE canonical_name IN (
  'chiSolidHingedFsiSubcyclingEnable','chiSolidHingedFsiMinSubsteps','chiSolidHingedFsiMaxSubsteps',
  'chiSolidHingedMaxAngularIncrement','chiSolidHingedMaxTipDisplacementCells','chiSolidHingedMaxParticleSpanCells'
);

-- New/clarified runner controls associated with x18f.
INSERT OR REPLACE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x18f','A','V4.32: contrôle runner documenté/finalisé par x18f'
FROM symbols WHERE canonical_name IN (
  'HINGED_X_BOUNDARY_MODE','SOLID_QUALIFICATION_DIAGNOSTICS','INACTIVE_SLOTS_CELL_FRACTION'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES('milestone:0493x18e','SOURCE_ARCHIVE','Info/inputs/historical/0493x18e_x18f_hinged_fsi_20260915_original_sources.zip','A','Archive exacte des packages x18e/x18f avec manifest SHA-256 et validation opérateur.');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES('milestone:0493x18e','OPERATOR_VALIDATION','Info/docs/CURATION_0493X18E_X18F_HINGED_FSI_V4_32.md','A','Compilation CUDA locale et runs réussis; dt global testé jusqu’à 20x la limite pratique précédente sans reproduire le hang.');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES('milestone:0493x18f','SOURCE_ARCHIVE','Info/inputs/historical/0493x18e_x18f_hinged_fsi_20260915_original_sources.zip','A','Archive exacte du package x18f et relevé des runs x18a/x18b.');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES('milestone:0493x18f','OPERATOR_VALIDATION','Info/docs/CURATION_0493X18E_X18F_HINGED_FSI_V4_32.md','A','x18a inlet_neumann validé fonctionnel; x18b double_neumann qualifié seulement comme démonstrateur qualitatif en raison du drift de population dépendant du régime.');

UPDATE git_milestone_candidates
SET status='LINKED', linked_milestone_object_id='milestone:0493' || label
WHERE candidate_family='X' AND label IN ('x18e','x18f')
  AND EXISTS (SELECT 1 FROM milestones m WHERE m.object_id='milestone:0493' || git_milestone_candidates.label);
