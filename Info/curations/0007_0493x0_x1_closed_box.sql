-- V4.6: consolidate the historical 0493x0/x1 transition.
--
-- x0 was absent from the original consolidated reference even though its README,
-- generator, runner and checker were introduced together with the x1 closed-box
-- support. x1 existed only as a confidence-C placeholder. This curation creates x0
-- and replaces the x1 placeholder with the history now directly attested by Git/code.

-- 0493x0: qualitative two-species dam-break demonstration of independent_masked Q6.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x0','MILESTONE','0493x0','curation:0007_0493x0_x1_closed_box');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x0','0493x0','x0','0493x0',
  'x0-x1 : dam-break bi-espèces et boîte fermée CUDA résidente',
  'Démonstration dam-break bi-espèces du Q6 independent_masked',
  'Introduit une démonstration qualitative d''une colonne liquide dense entourée d''un gaz compressible, avec speciesQ6Mode=independent_masked, q6Strength liquide=1 et gaz=0. Le cas sert d''intégration/visualisation du Q6 multi-espèces et non de benchmark surface libre calibré.',
  'VISUALIZATION','SPECIES_Q6','Démonstration historique d''intégration','A',
  NULL,NULL,NULL,
  'Le runner a d''abord utilisé un petit vent segmented pour le gaz; x1 remplace ensuite cette topologie par une boîte réellement fermée afin d''éliminer l''injection continue et le panache artificiel.',
  'README_0493X0_DAM_BREAK_DEMO.md',NULL
);

-- 0493x1: replace the original confidence-C placeholder by the now-attested closed-box path.
UPDATE milestones
SET group_name='x0-x1 : dam-break bi-espèces et boîte fermée CUDA résidente',
    name='Chemin de frontières closed-box CUDA résident',
    summary='Étend le chemin parois CUDA résident à une boîte rectangulaire statique non périodique sur les quatre faces. Le premier sous-ensemble accepte solid/specular, sans segment ouvert, obstacle immergé, domaine mobile ni resampling; Q6 independent_masked est exécuté de façon résidente avec boundaryFamily=closed_box.',
    nature='CODE',
    domain='BOUNDARY',
    status='Étape historique qualifiée pour la démonstration dam-break',
    confidence='A',
    notes='Introduit pour supprimer le vent gazeux de x0, qui provoquait une injection continue et un panache artificiel. Le support est opt-in via MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1.',
    source_file='README_0493X1_CLOSED_BOX_CUDA_RESIDENT.md',
    source_row=NULL
WHERE object_id='milestone:0493x1';

-- Primary documentary evidence.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x0','MILESTONE_README','README_0493X0_DAM_BREAK_DEMO.md','A',
       'README dedicated to the two-species dam-break integration demonstration'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x0' AND evidence_type='MILESTONE_README'
    AND path='README_0493X0_DAM_BREAK_DEMO.md'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x1','MILESTONE_README','README_0493X1_CLOSED_BOX_CUDA_RESIDENT.md','A',
       'README dedicated to the static closed-box CUDA-resident boundary path'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x1' AND evidence_type='MILESTONE_README'
    AND path='README_0493X1_CLOSED_BOX_CUDA_RESIDENT.md'
);

-- x0 directly demonstrates the already-qualified independent-masked Q6 chain.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x0','BUILDS_ON','milestone:history:0493w8','A',
       'x0 uses the qualified mono/dual independent_masked Q6 operator from W8'
WHERE EXISTS (SELECT 1 FROM objects WHERE object_id='milestone:history:0493w8');

-- x1 extends the non-periodic boundary coverage established during W7.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x1','EXTENDS','milestone:history:0493w7','A',
       'x1 adds the closed_box family to the resident independent_masked boundary path'
WHERE EXISTS (SELECT 1 FROM objects WHERE object_id='milestone:history:0493w7');

-- x0 is the integration demonstration that consumes the x1 closed-box capability.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x0','DEMONSTRATES','milestone:0493x1','A',
       'the x0 dam-break runner is updated to use the x1 closed-box topology');

-- Surviving repository artifacts.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x0','GENERATED_BY',object_id,'A','x0 initial two-species dam-break state generator'
FROM artifacts WHERE path='scripts/generate_0493x0_dam_break_state.py';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x0','QUALIFIED_BY',object_id,'A','x0 qualitative integration runner/checker'
FROM artifacts WHERE path IN ('scripts/run_0493x0_dam_break_demo.sh','scripts/check_0493x0_dam_break_demo.py');

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x1','QUALIFIED_BY',object_id,'A','x1 compact closed-box SRC/src-q6 smoke matrix'
FROM artifacts WHERE path='scripts/run_0493x1_closed_box_smoke.sh';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x1','IMPLEMENTED_IN',object_id,'A','x1 four-face static streaming/reflection support'
FROM artifacts WHERE path IN (
  'include/cuda_streaming_wall_simple_0246.h',
  'src/cuda_streaming_wall_simple_0246.cu',
  'src/cuda_q6_resident_0400.cu'
);
