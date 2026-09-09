-- V4.7: consolidate the 0493x2 -> 0493x4b force-aware Q6 ordering sequence.
--
-- These four milestones already existed in the imported consolidated reference.  This
-- curation does not create new milestone objects; it replaces the concise retrospective
-- descriptions by definitions grounded in the surviving runners/READMEs and records the
-- causal chain from the gravity diagnostic to the fused one-solve Q6-g ordering.

-- x2: causal diagnostic in a fully occupied liquid closed box under gravity.
UPDATE milestones
SET group_name='x2-x4b : diagnostic gravitaire et séquençage Q6-g force-aware',
    name='Diagnostic liquide plein : force appliquée avant une projection Q6 trop tardive',
    summary='Isole un liquide mono-espèce entièrement rempli dans la boîte fermée sous gravité. Le Q6 common maintient une faible divergence post-collision, mais le kick-and-drift historique déplace les particules avant cette projection; le déplacement déterministe d''ordre g*dt^2 s''accumule au mur inférieur et explique la lente sédimentation observée.',
    nature='DIAGNOSTIC',
    domain='Q6_GF',
    status='Diagnostic causal; mène directement à x3',
    confidence='A',
    notes='Le profil liquid-only est ajouté au générateur x0. Cas de référence utilisé ensuite par x3/x4a/x4b : boîte fermée, resampling OFF, gravité gY=-0.5 et dt=0.005 dans la campagne historique.',
    source_file='scripts/run_0493x2_liquid_only_q6_common.sh',
    source_row=NULL
WHERE object_id='milestone:0493x2';

-- x3: Q6-g proof of concept with a pre-stream force-aware projection and the legacy
-- post-collision projection retained as a second solve.
UPDATE milestones
SET group_name='x2-x4b : diagnostic gravitaire et séquençage Q6-g force-aware',
    name='Q6-g force-aware — preuve de concept prestream à deux solves',
    summary='Introduit q6ForceProjectionMode=prestream : la force est appliquée à la vitesse résidente, cette vitesse tentative est projetée par Q6 avant le streaming, puis le solve Q6 post-collision historique est conservé. Le chemin démontre que la vitesse de transport, et non seulement la vitesse post-collision, doit satisfaire la contrainte incompressible.',
    nature='CODE',
    domain='Q6_GF',
    status='Preuve de concept validant la cause; supplantée par x4a',
    confidence='A',
    notes='Mode opt-in limité historiquement au CUDA Q6, périodique ou closed-box statique, sans resampling/open/Darcy/immersed/capacity. Le contrôle TG à force nulle impose la neutralité et le liquide fermé vérifie la suppression de la sédimentation g*dt^2.',
    source_file='README_0493X3_Q6_FORCE_PRESTREAM_TEST.md',
    source_row=NULL
WHERE object_id='milestone:0493x3';

-- x4a: single pre-stream solve. Collision and relative thermostat do not transport
-- particles, therefore post-collision projection can be deferred to the next pre-stream.
UPDATE milestones
SET group_name='x2-x4b : diagnostic gravitaire et séquençage Q6-g force-aware',
    name='Q6-g prestream_single — un solve Q6 par pas forcé',
    summary='Ajoute q6ForceProjectionMode=prestream_single. Après force -> Q6 -> streaming, collision SRC et thermostat relatif ne déplacent pas les particules; le solve post-collision est donc omis et la vitesse issue de collision est projetée au début du pas suivant avant tout nouveau transport.',
    nature='CODE',
    domain='Q6_GF',
    status='Référence mono-solve; supplantée par la fusion x4b',
    confidence='A',
    notes='Conserve le mode x3 à deux solves comme référence. La campagne liquide fermée historique réduit le coût d''environ 142.9 s à 95.5 s sur 1000 pas sans réintroduire la dérive gravitaire.',
    source_file='README_0493X4A_Q6_FORCE_SINGLE_SOLVE.md',
    source_row=NULL
WHERE object_id='milestone:0493x4a';

-- x4b: remove the dedicated force-kick particle pass by depositing tentative momentum
-- and applying physical force + Q6 correction in the same CUDA particle kernel.
UPDATE milestones
SET group_name='x2-x4b : diagnostic gravitaire et séquençage Q6-g force-aware',
    name='Q6-g prestream_single_fused — fusion CUDA force + projection',
    summary='Ajoute q6ForceProjectionMode=prestream_single_fused : le dépôt CUDA construit directement le moment tentative m(v+a dt), le solveur Q6 projette ce champ, puis un même passage particulaire applique la force physique et la correction Q6 avant streaming. Le momentum apporté par la force reste distinct de la correction de momentum Q6.',
    nature='PERF',
    domain='Q6_GF',
    status='Séquençage temporel Q6-g de référence pour la suite de 0493x',
    confidence='A',
    notes='Supprime le dernier passage particulaire dédié au kick tout en gardant x4a comme référence physique/numérique. En contrôle historique, environ 91.9 s/1000 pas et stabilité sur 5000 pas.',
    source_file='README_0493X4B_Q6_FORCE_CUDA_FUSION.md',
    source_row=NULL
WHERE object_id='milestone:0493x4b';

-- Primary evidence. x2 has no dedicated README in the surviving lineage; its dedicated
-- runner plus the liquid-only generator extension are the primary source.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x2','MILESTONE_RUNNER','scripts/run_0493x2_liquid_only_q6_common.sh','A',
       'Dedicated common-Q6 liquid-only gravity diagnostic runner'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x2' AND evidence_type='MILESTONE_RUNNER'
    AND path='scripts/run_0493x2_liquid_only_q6_common.sh'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x3','MILESTONE_README','README_0493X3_Q6_FORCE_PRESTREAM_TEST.md','A',
       'README defining the two-solve force-aware prestream proof of concept'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x3' AND evidence_type='MILESTONE_README'
    AND path='README_0493X3_Q6_FORCE_PRESTREAM_TEST.md'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x4a','MILESTONE_README','README_0493X4A_Q6_FORCE_SINGLE_SOLVE.md','A',
       'README defining the one-solve prestream_single ordering'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x4a' AND evidence_type='MILESTONE_README'
    AND path='README_0493X4A_Q6_FORCE_SINGLE_SOLVE.md'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x4b','MILESTONE_README','README_0493X4B_Q6_FORCE_CUDA_FUSION.md','A',
       'README defining the fused tentative-force CUDA ordering'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x4b' AND evidence_type='MILESTONE_README'
    AND path='README_0493X4B_Q6_FORCE_CUDA_FUSION.md'
);

-- Causal and supersession chain.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x2','BUILDS_ON','milestone:0493x1','A','x2 reuses the x1 closed-box resident boundary path');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x3','BUILDS_ON','milestone:0493x2','A','x3 is the ordering experiment motivated by the x2 gravity diagnostic');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x3','SUPERSEDED_BY','milestone:0493x4a','A','x4a removes the redundant post-collision Q6 solve');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x4a','BUILDS_ON','milestone:0493x3','A','x4a keeps the force-aware prestream physics with one solve');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x4a','SUPERSEDED_BY','milestone:0493x4b','A','x4b fuses the standalone force kick into the resident Q6 data path');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x4b','BUILDS_ON','milestone:0493x4a','A','x4b preserves the x4a one-solve ordering while removing a particle pass');

-- Promote pre-existing inferred supersession links from confidence C to curated A.
UPDATE relations
SET confidence='A', evidence_text='curated x3 -> x4a one-solve supersession'
WHERE source_object_id='milestone:0493x3' AND relation_type='SUPERSEDED_BY'
  AND target_object_id='milestone:0493x4a';
UPDATE relations
SET confidence='A', evidence_text='curated x4a -> x4b fused-path supersession'
WHERE source_object_id='milestone:0493x4a' AND relation_type='SUPERSEDED_BY'
  AND target_object_id='milestone:0493x4b';

-- Link the abstract Q6-g reference to its concrete introduction when present.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x3','IMPLEMENTS','milestone:reference:Q6-g','A','x3 is the first concrete force-aware Q6-g ordering'
WHERE EXISTS (SELECT 1 FROM objects WHERE object_id='milestone:reference:Q6-g');

-- Surviving runner/analyzer artifacts.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x2','QUALIFIED_BY',object_id,'A','x2 liquid-only gravity diagnostic runner'
FROM artifacts WHERE path IN (
  'scripts/run_0493x2_liquid_only_q6.sh',
  'scripts/run_0493x2_liquid_only_q6_common.sh'
);
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x2','GENERATED_BY',object_id,'A','x2 liquid-only profile is generated by the extended x0 state generator'
FROM artifacts WHERE path='scripts/generate_0493x0_dam_break_state.py';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x3','QUALIFIED_BY',object_id,'A','x3 TG and closed-liquid force-ordering qualification'
FROM artifacts WHERE path IN (
  'scripts/run_0493x3_q6_force_projection_tg.sh',
  'scripts/analyze_0493x3_q6_force_projection_tg.py',
  'scripts/run_0493x3_liquid_only_q6_force_prestream.sh'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x4a','QUALIFIED_BY',object_id,'A','x4a one-solve TG / closed-liquid qualification'
FROM artifacts WHERE path IN (
  'scripts/run_0493x4a_q6_force_single_tg.sh',
  'scripts/analyze_0493x4a_q6_force_single_tg.py',
  'scripts/run_0493x4a_liquid_only_q6_force_single.sh'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x4b','QUALIFIED_BY',object_id,'A','x4b fused-vs-separate TG and liquid-only qualification'
FROM artifacts WHERE path IN (
  'scripts/run_0493x4b_q6_force_fusion_tg.sh',
  'scripts/analyze_0493x4b_q6_force_fusion_tg.py',
  'scripts/run_0493x4b_liquid_only_q6_force_fused.sh'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x3','IMPLEMENTED_IN',object_id,'A','force-aware prestream ordering and CUDA force kick/Q6 path'
FROM artifacts WHERE path IN ('src/src_mpcd_base.cpp','src/cuda_q6_resident_0400.cu','include/cuda_q6_resident_0400.h');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x4a','IMPLEMENTED_IN',object_id,'A','single-solve scheduling in the main step/Q6 resident path'
FROM artifacts WHERE path IN ('src/src_mpcd_base.cpp','src/cuda_q6_resident_0400.cu');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x4b','IMPLEMENTED_IN',object_id,'A','tentative-force deposit and fused force+Q6 particle application'
FROM artifacts WHERE path IN ('src/src_mpcd_base.cpp','src/cuda_q6_resident_0400.cu');
