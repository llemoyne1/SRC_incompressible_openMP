-- V4.8: consolidate 0493x5a / x5a2 / x5b, the first free-surface-masked sequence.
--
-- The three milestones already exist in the consolidated reference.  This curation
-- replaces the short retrospective descriptions with definitions grounded in the
-- dedicated READMEs/runners and records the conceptual transition from a numerical
-- liquid support boundary to a dynamic liquid/vacuum interface and then to an explicit
-- compressible gas.  No new canonical milestone is created.

-- x5a: first free_surface_masked Q6-g operator on a horizontally partial liquid.
UPDATE milestones
SET group_name='x5a-x5b : surface libre masquée, dam-break vide et gaz explicite',
    name='Q6-g free_surface_masked — premier liquide partiellement rempli',
    summary='Conserve le séquençage prestream_single_fused de x4b et introduit speciesQ6Mode=free_surface_masked pour une unique espèce liquide projetée. Le support de pression est construit à partir du remplissage absolu mass/referenceCellMass; une face active/inactive impose encore une pression de jauge nulle à demi-maille, avec le facteur deux correspondant dans le Laplacien et la correction de vitesse.',
    nature='CODE',
    domain='Q6_GF',
    status='Première fermeture liquide-vide; support numérique encore assimilé à l''interface',
    confidence='A',
    notes='Cas initial volontairement étroit : liquide horizontal partiel dans une boîte fermée statique, gaz absent, resampling/Darcy/virial/open/immersed OFF. Le runner historique utilise typiquement speciesQ6MinOccupancyFraction=0.25 comme seuil de support brut.',
    source_file='README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md',
    source_row=NULL
WHERE object_id='milestone:0493x5a';

-- x5a2: dynamic liquid/vacuum dam-break qualification.  The operator is unchanged;
-- the important historical result is that the post-impact behaviour exposes the
-- difference between the numerical support boundary and a physical phase interface.
UPDATE milestones
SET group_name='x5a-x5b : surface libre masquée, dam-break vide et gaz explicite',
    name='Qualification dam-break liquide-vide du free_surface_masked',
    summary='Soumet l''opérateur x5a inchangé à une interface fortement déformable : une colonne liquide est libérée dans une boîte fermée autrement vide. Le générateur ajoute le profil empty-outside-column et les diagnostics suivent géométrie, support et solveur. La campagne est robuste avant impact mais la fragmentation post-impact montre que le bord du support numérique ne peut pas être identifié à l''interface physique.',
    nature='QUALIFICATION',
    domain='Q6_GF',
    status='Qualification discriminante; motive la séparation support/interface de x6',
    confidence='A',
    notes='Aucun changement Q6/force/collision/thermostat/BC dans ce jalon. Cas historique : liquid-vacuum, free_surface_masked, prestream_single_fused, gaz absent.',
    source_file='README_0493X5A2_DYNAMIC_FREE_SURFACE_DAM_BREAK.md',
    source_row=NULL
WHERE object_id='milestone:0493x5a2';

-- x5b: first explicit compressible-gas dynamic qualification.  The README explicitly
-- states that the CUDA operator is unchanged, so this is a qualification milestone,
-- not a new CODE operator milestone.
UPDATE milestones
SET group_name='x5a-x5b : surface libre masquée, dam-break vide et gaz explicite',
    name='Qualification liquide-gaz : Q6-g liquide et gaz compressible explicite',
    summary='Ajoute la première qualification dynamique bi-espèces au-dessus de x5a/x5a2 sans modifier l''opérateur CUDA. Le liquide seul est projeté par free_surface_masked; le gaz est enregistré avec q6StrengthDeclared=0, reçoit la force et participe aux collisions SRC multi-espèces mais reste compressible et ne reçoit aucune correction Q6 directe. À ce stade la pression gazeuse n''est pas injectée dans la condition de pression Q6.',
    nature='QUALIFICATION',
    domain='Q6_GF',
    status='Première qualification bi-espèces; couplage gaz-liquide encore collisionnel côté pression',
    confidence='A',
    notes='Le cas historique utilise dix particules/cellule dans les deux phases et un rapport de masses 1000. Il constitue un stress-test de gaz fortement stratifié, pas un modèle quantitatif de l''air; il mène au diagnostic EOS gaz x6a.',
    source_file='README_0493X5B_LIQUID_GAS_FREE_SURFACE.md',
    source_row=NULL
WHERE object_id='milestone:0493x5b';

-- Dedicated documentary evidence.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x5a','MILESTONE_README','README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md','A',
       'README defining free_surface_masked and the first partial-liquid pressure condition'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x5a' AND evidence_type='MILESTONE_README'
    AND path='README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x5a2','MILESTONE_README','README_0493X5A2_DYNAMIC_FREE_SURFACE_DAM_BREAK.md','A',
       'README defining the dynamic liquid-vacuum dam-break qualification'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x5a2' AND evidence_type='MILESTONE_README'
    AND path='README_0493X5A2_DYNAMIC_FREE_SURFACE_DAM_BREAK.md'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x5b','MILESTONE_README','README_0493X5B_LIQUID_GAS_FREE_SURFACE.md','A',
       'README defining the first explicit compressible-gas free-surface qualification'
WHERE NOT EXISTS (
  SELECT 1 FROM evidence WHERE object_id='milestone:0493x5b' AND evidence_type='MILESTONE_README'
    AND path='README_0493X5B_LIQUID_GAS_FREE_SURFACE.md'
);

-- Historical chain and interpretation.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x5a','BUILDS_ON','milestone:0493x4b','A','x5a keeps the x4b fused force-aware ordering and adds free_surface_masked support');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x5a2','BUILDS_ON','milestone:0493x5a','A','x5a2 exercises the unchanged x5a operator on a dynamic liquid-vacuum interface');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x5a2','QUALIFIES','milestone:0493x5a','A','dynamic dam-break qualification of free_surface_masked');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x5a2','DIAGNOSES','milestone:0493x5a','A','post-impact fragmentation exposes that numerical support boundary is not the physical interface');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x5b','BUILDS_ON','milestone:0493x5a2','A','x5b adds explicit compressible gas after the liquid-vacuum dynamic qualification');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x5b','EXTENDS','milestone:0493x5a','A','same free_surface_masked liquid operator with an explicit unprojected gas species');

-- Surviving runner/analyzer/generator artifacts when present in the scanned repository.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x5a','QUALIFIED_BY',object_id,'A','x5a partial-liquid free-surface qualification'
FROM artifacts WHERE path IN (
  'scripts/run_0493x5a_partial_liquid_free_surface.sh',
  'scripts/analyze_0493x5a_partial_liquid.py',
  'scripts/run_0493x5a_nonregression.sh'
);
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x5a','GENERATED_BY',object_id,'A','partial-liquid profile from the extended x0 state generator'
FROM artifacts WHERE path='scripts/generate_0493x0_dam_break_state.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x5a','IMPLEMENTED_IN',object_id,'A','free_surface_masked mode, masked stencil and fused liquid application'
FROM artifacts WHERE path IN (
  'include/q6_species_distribution_0491a.h',
  'include/simulation_params.h',
  'src/q6_species_distribution_0491a.cpp',
  'src/params_io_base.cpp',
  'src/cuda_q6_resident_0400.cu'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x5a2','QUALIFIED_BY',object_id,'A','dynamic liquid-vacuum dam-break qualification and non-regression'
FROM artifacts WHERE path IN (
  'scripts/run_0493x5a2_dynamic_free_surface_dam_break.sh',
  'scripts/analyze_0493x5a2_dynamic_free_surface.py',
  'scripts/check_0493x5a2_generator_profiles.py',
  'scripts/run_0493x5a2_nonregression.sh'
);
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x5a2','GENERATED_BY',object_id,'A','empty-outside-column profile from the x0 state generator'
FROM artifacts WHERE path='scripts/generate_0493x0_dam_break_state.py';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x5b','QUALIFIED_BY',object_id,'A','explicit liquid-gas free-surface qualification'
FROM artifacts WHERE path IN (
  'scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh',
  'scripts/analyze_0493x5b_liquid_gas_free_surface.py',
  'scripts/run_0493x5b_nonregression.sh'
);
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x5b','GENERATED_BY',object_id,'A','two-species dam-break initial state from the x0 state generator'
FROM artifacts WHERE path='scripts/generate_0493x0_dam_break_state.py';
