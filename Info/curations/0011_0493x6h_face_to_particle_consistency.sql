-- V4.10: consolidate 0493x6h-A / B0 / B1 from their preserved historical patches.
--
-- These three milestones already existed in the initial retrospective reference, but
-- only as compact confidence-B summaries.  The original patches make the causal chain
-- explicit: A restores missing west/south low-boundary face corrections; B0 localizes
-- the divergence that remains after face corrections are applied to particles and
-- redeposited; B1 replaces the cell-constant particle increment by an affine
-- face-compatible RT0/MAC reconstruction.  No new milestone is created here.

UPDATE milestones
SET group_name='x6h : cohérence correction de face -> particules',
    name='Correctif des corrections de faces physiques basses',
    summary='Corrige l''asymétrie du stockage east/north des corrections Q6 : sur une frontière physique basse non périodique, aucune cellule propriétaire west/south n''existe pour fournir la correction de face. x6h-A reconstruit alors cette correction avec la même convention target-before que les faces hautes, sous contrôle du pressureMask, afin de ne pas injecter de kick dans les seules cellules de carrier.',
    nature='FIX',
    domain='Q6_GF',
    status='Correctif de reconstruction des faces basses actif dans Q6-g-f',
    confidence='A',
    notes='Le correctif agit dans la reconstruction face-vers-cellule après le solve FV et ne change ni la matrice CG ni la définition de l''interface. Il fournit aussi les faces west/south cohérentes dont B1 a besoin pour reconstruire un champ particulaire affine.',
    source_file='Info/inputs/historical/0493x6h_patchA_low_wall_face_reconstruction.patch',
    source_row=NULL
WHERE object_id='milestone:0493x6h-a';

UPDATE milestones
SET group_name='x6h : cohérence correction de face -> particules',
    name='Diagnostic régional de divergence après application aux particules',
    summary='Ajoute, uniquement à cadence d''audit, un redépôt post-application et localise la divergence résiduelle par régions bulk, interface, paroi, paroi-interface, coin et coin-interface. Le diagnostic montre où la correction FV projetée perd sa cohérence lorsqu''elle est convertie en incréments particulaires puis redéposée.',
    nature='DIAGNOSTIC',
    domain='Q6_GF',
    status='Diagnostic sparse OFF en production; motive la reconstruction B1',
    confidence='A',
    notes='Le buffer d''accumulation est alloué paresseusement et la passe supplémentaire n''existe pas lorsque MPCD_Q6_POSTAPPLY_REGION_DIAGNOSTICS_0493X6H_B0 est désactivé. Ce jalon ne modifie aucune vitesse ni aucun opérateur Q6.',
    source_file='Info/inputs/historical/0493x6h_b0_postapply_region_diagnostic.patch',
    source_row=NULL
WHERE object_id='milestone:0493x6h-b0';

UPDATE milestones
SET group_name='x6h : cohérence correction de face -> particules',
    name='Reconstruction affine RT0/MAC des corrections face-vers-particule',
    summary='Remplace, dans le chemin free_surface_masked force+Q6 fusionné, l''application d''un incrément constant par cellule par une reconstruction affine aux positions particulaires entre les corrections des faces opposées. Les faces west/south sont déduites des moyennes cellulaires et des faces east/north, avec x6h-A pour les frontières basses; la divergence discrète du champ reconstruit est ainsi celle du champ FV projeté.',
    nature='CODE',
    domain='Q6_GF',
    status='Reconstruction face-particule active dans le profil Q6-g-f qualifié',
    confidence='A',
    notes='Le premier chemin B1 est volontairement limité à exactement une espèce Q6 projetée et réutilise les buffers east/north existants; il n''ajoute ni stockage de faces persistant par espèce ni seconde passe particulaire. Les extensions périodiques ultérieures, notamment x7q, ferment ensuite exactement le mode k=0 réellement appliqué.',
    source_file='Info/inputs/historical/0493x6h_b1_rt0_face_to_particle.patch',
    source_row=NULL
WHERE object_id='milestone:0493x6h-b1';

-- Preserve the original stage patches as primary evidence inside Info itself.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6h-a','HISTORICAL_PATCH','Info/inputs/historical/0493x6h_patchA_low_wall_face_reconstruction.patch','A','Original low-wall face reconstruction patch'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x6h-a' AND evidence_type='HISTORICAL_PATCH'
    AND path='Info/inputs/historical/0493x6h_patchA_low_wall_face_reconstruction.patch'
);
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6h-b0','HISTORICAL_PATCH','Info/inputs/historical/0493x6h_b0_postapply_region_diagnostic.patch','A','Original post-apply regional divergence diagnostic patch'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x6h-b0' AND evidence_type='HISTORICAL_PATCH'
    AND path='Info/inputs/historical/0493x6h_b0_postapply_region_diagnostic.patch'
);
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6h-b1','HISTORICAL_PATCH','Info/inputs/historical/0493x6h_b1_rt0_face_to_particle.patch','A','Original RT0/MAC face-to-particle reconstruction patch'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x6h-b1' AND evidence_type='HISTORICAL_PATCH'
    AND path='Info/inputs/historical/0493x6h_b1_rt0_face_to_particle.patch'
);

-- Causal chain from the x6 physical-interface solver to the particle application.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6h-a','BUILDS_ON','milestone:0493x6g','A','x6h-A repairs the low physical faces of the x6f/x6g face-correction path');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6h-a','FIXES','milestone:0493x6f','A','east/north ownership left west/south low-domain corrections unavailable during face-to-cell reconstruction');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6h-b0','BUILDS_ON','milestone:0493x6h-a','A','after low-wall reconstruction, B0 audits the field after application to particles and redeposition');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6h-b0','DIAGNOSES','milestone:0493x6h-a','A','B0 localizes the residual divergence left by the cell-constant face-to-particle application in the corrected x6h-A path');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6h-b1','BUILDS_ON','milestone:0493x6h-b0','A','B1 is the production response to the post-apply localization performed by B0');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6h-b1','EXTENDS','milestone:0493x6h-a','A','B1 consumes the low-wall-consistent opposite face corrections supplied by x6h-A');

-- Current repository implementation and surviving diagnostic artifact.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','x6h face-to-particle consistency implementation in resident CUDA Q6'
FROM milestones AS m
JOIN artifacts AS a ON a.path='src/cuda_q6_resident_0400.cu'
WHERE m.object_id IN ('milestone:0493x6h-a','milestone:0493x6h-b0','milestone:0493x6h-b1');

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6h-b0','ANALYZED_BY',object_id,'A','regional post-apply divergence analyzer'
FROM artifacts WHERE path='scripts/analyze_0493x6h_b0_postapply_regions.py';
