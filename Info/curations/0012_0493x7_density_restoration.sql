-- V4.11: split the retrospective x7a/x7b aggregate, add missing x7c, and
-- consolidate x7d/x7e from their preserved historical patches.
--
-- The raw reference row x7a/x7b is intentionally preserved in raw_milestone_rows.
-- Only the canonical aggregate object is removed and replaced with the three actual
-- development stages evidenced by dedicated historical patches/READMEs.

-- Remove the retrospective aggregate. ON DELETE CASCADE removes its inferred relation
-- and imported evidence; the original raw source row remains untouched.
DELETE FROM objects WHERE object_id='milestone:reference:x7a/x7b';

-- x7a: first CUDA-resident explicit virial density-restoring kick.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7a','MILESTONE','x7a','curation:0012_0493x7_density_restoration');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7a','0493x7a','x7a','0493x7a',
  'x7a-x7e : restauration de densité dans Q6-g-f',
  'Kick viriel de densité CUDA résident',
  'Porte sur le chemin free_surface_masked Q6-g-f le mécanisme historique de restauration de densité sous forme d''un kick explicite post-projection : Pvir/rhoRef=kVirial*(rawFill-1), puis duVir=-betaEOS*dt*grad(Pvir/rhoRef). Le kick est limité au bulk liquide, avec correction uniforme optionnelle du moment net, et est fusionné dans le redépôt final des moments cellule.',
  'CODE','Q6_GF','Expérience de restauration explicite; abandonnée au profit de la cible de divergence x7c/x7d','A',
  NULL,NULL,NULL,
  'Chemin initial étroit : exactement une phase liquide et une espèce liquide projetée, x6c+x6f+B1, pas de couplage viriel gaz/interface. virialDensityKickEnable=false reste le défaut. Le mécanisme est ensuite clarifié sémantiquement par x7b puis rendu mutuellement exclusif avec x7c.',
  'README_0493X7A_CUDA_RESIDENT_VIRIAL.md',NULL
);

-- x7b: semantic/diagnostic consolidation of x7a after K32 qualification.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7b','MILESTONE','x7b','curation:0012_0493x7_density_restoration');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7b','0493x7b','x7b','0493x7b',
  'x7a-x7e : restauration de densité dans Q6-g-f',
  'Sémantique continue et diagnostic de grille du viriel',
  'Fixe la convention continue du mécanisme x7a sans modifier son update numérique lorsque kVirial et betaEOS sont explicites : kVirial porte des unités de vitesse au carré et ne se redimensionne pas avec dx/dy; la résolution temporelle est suivie séparément par cVir=sqrt(betaEOS*kVirial) et les nombres de Courant viriels. Le candidat K32 qualifié devient le défaut lorsque le viriel est activé.',
  'DIAGNOSTIC','Q6_GF','Consolidation sémantique de l''ablation virielle; stratégie ensuite remplacée par x7c','A',
  NULL,NULL,NULL,
  'Le patch se déclare explicitement semantic/diagnostic. Il conserve virialDensityKickEnable=false par défaut et retient kVirial=0.10666666666666667, betaEOS=0.05 comme calibration continue K32 après qualification trois seeds.',
  'README_0493X7B_CONTINUUM_VIRIAL_GRID_SEMANTICS.md',NULL
);

-- x7c: move density restoration inside the Q6 projection constraint.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7c','MILESTONE','x7c','curation:0012_0493x7_density_restoration');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7c','0493x7c','x7c','0493x7c',
  'x7a-x7e : restauration de densité dans Q6-g-f',
  'Restauration de densité intégrée au RHS Q6',
  'Remplace le kick viriel explicite post-projection par une contrainte de divergence directement dans le solve Q6 : dans le bulk liquide, div(u_proj)=beta_rho*(rawFill-1)/dt. Les cellules sur la bande d''interface conservent le traitement de pression x6f/x6g; beta=0 est un no-op exact.',
  'CODE','Q6_GF','Mécanisme RHS retenu conceptuellement; paramétrage physique raffiné par x7d','A',
  NULL,NULL,NULL,
  'q6DensityRelaxationBeta est sans dimension et défini par pas. Le chemin est limité au sous-ensemble x6c+x6f, force fusionnée, B1, une espèce liquide projetée. x7c et le kick viriel explicite x7a/x7b sont mutuellement exclusifs.',
  'README_0493X7C_Q6_DENSITY_RELAXATION_RHS.md',NULL
);

-- x7d: physical relaxation time and paired grid-refinement semantics.
UPDATE milestones
SET group_name='x7a-x7e : restauration de densité dans Q6-g-f',
    name='Constante de temps physique de restauration de densité',
    summary='Consolide l''opérateur x7c sans en changer le kernel : l''entrée physique préférée devient q6DensityRelaxationTime=tau_rho, avec div(u_proj)=(rawFill-1)/tau_rho et betaParPas=dt/tau_rho. Le beta par pas x7c reste disponible pour compatibilité mais est mutuellement exclusif avec tau_rho positif. Une campagne coarse/fine à temps physique égal vérifie la sémantique de l''opérateur sous raffinement.',
    nature='CODE',
    domain='Q6_GF',
    status='Paramétrage physique retenu; tau_rho=0.25 dans la chaîne qualifiée',
    confidence='A',
    notes='Qualification historique : 300x150 dt=0.005 beta=0.02 correspond à tau_rho=0.25; à 600x300 dt=0.0025, le même tau donne betaParPas=0.01. Le test est un diagnostic de scaling de l''opérateur, pas une preuve complète de convergence continue MPCD.',
    source_file='README_0493X7D_DENSITY_RELAXATION_TIME_GRID_REFINEMENT.md',
    source_row=NULL
WHERE object_id='milestone:0493x7d';

-- x7e: qualification-only composition of gas pressure and density RHS.
UPDATE milestones
SET group_name='x7a-x7e : restauration de densité dans Q6-g-f',
    name='Qualification combinée pression gaz x6g + restauration de densité x7d',
    summary='Valide sans modifier l''opérateur CUDA l''assemblage additif, dans un même RHS et un même solve CG, de la condition de pression interfaciale x6g et de la cible de divergence bulk x7d. La qualification réutilise la suite d''invariants x6g et le raffinement coarse/fine x7d avec tau_rho=0.25 et B1 actif.',
    nature='QUALIFICATION',
    domain='Q6_GF',
    status='Qualification de composition Q6-g-f; kick viriel explicite désactivé',
    confidence='A',
    notes='RHS = -div(u*) + contribution Dirichlet x6g(p_g-p_ref) + cible bulk x7d. x6g agit aux faces alpha=0.5, x7d dans le bulk liquide, tous deux réutilisent pressureMask/stencil x6f et B1 pour l''application particulaire.',
    source_file='README_0493X7E_X6G_X7D_COMBINATION.md',
    source_row=NULL
WHERE object_id='milestone:0493x7e';

-- Preserve the old retrospective row as evidence on both real virial stages.
INSERT INTO evidence(object_id,evidence_type,path,line_hint,confidence,notes)
SELECT 'milestone:0493x7a','REFERENCE_TEX','Info/inputs/snapshots/referentiel_jalons_SRC_GPU_SURF_20260905.tex','66','B',
       'Original retrospective x7a/x7b aggregate row, split by V4.11'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7a' AND evidence_type='REFERENCE_TEX' AND line_hint='66');
INSERT INTO evidence(object_id,evidence_type,path,line_hint,confidence,notes)
SELECT 'milestone:0493x7b','REFERENCE_TEX','Info/inputs/snapshots/referentiel_jalons_SRC_GPU_SURF_20260905.tex','66','B',
       'Original retrospective x7a/x7b aggregate row, split by V4.11'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7b' AND evidence_type='REFERENCE_TEX' AND line_hint='66');

-- Primary historical patches archived in Info.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7a','HISTORICAL_PATCH','Info/inputs/historical/0493x7a_cuda_resident_virial_density_kick.patch','A','Original CUDA-resident virial density kick patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7a' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7b','HISTORICAL_PATCH','Info/inputs/historical/0493x7b_continuum_virial_grid_semantics.patch','A','Original continuum virial semantics patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7b' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7c','HISTORICAL_PATCH','Info/inputs/historical/0493x7c_q6_density_relaxation_rhs.patch','A','Original Q6 density-relaxation RHS patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7c' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7d','HISTORICAL_PATCH','Info/inputs/historical/0493x7d_density_relaxation_time_and_grid_refinement.patch','A','Original physical relaxation-time and grid-refinement patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7d' AND evidence_type='HISTORICAL_PATCH');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7e','HISTORICAL_PATCH','Info/inputs/historical/0493x7e_x6g_x7d_combined_qualification.patch','A','Original combined x6g+x7d qualification patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7e' AND evidence_type='HISTORICAL_PATCH');

-- Causal chain.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7a','BUILDS_ON','milestone:0493x6h-b1','A','x7a adds density restoration after the qualified x6h B1 face-to-particle path');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7b','BUILDS_ON','milestone:0493x7a','A','x7b fixes the continuum/grid semantics of the unchanged x7a virial mechanism');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7c','BUILDS_ON','milestone:0493x7b','A','x7c replaces the explicit post-projection virial strategy by a divergence target inside Q6');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7a','SUPERSEDED_BY','milestone:0493x7c','A','production density restoration moves from explicit virial kick to the Q6 RHS');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7b','SUPERSEDED_BY','milestone:0493x7c','A','the clarified virial ablation remains useful historically but is not the retained Q6-g-f density closure');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7d','BUILDS_ON','milestone:0493x7c','A','x7d reparameterizes the same RHS operator with a physical relaxation time');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7e','BUILDS_ON','milestone:0493x7d','A','x7e qualifies density relaxation together with the gas-pressure path');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7e','BUILDS_ON','milestone:0493x6g','A','x7e composes x6g interface pressure with x7d bulk density relaxation');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7e','QUALIFIES','milestone:0493x7d','A','combined invariant and coarse/fine qualification with tau_rho=0.25');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7e','QUALIFIES','milestone:0493x6g','A','qualification of x6g gas-pressure Dirichlet contribution in the same RHS as density relaxation');

-- Surviving implementation and qualification artifacts, when present in the scanned repo.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','density-restoration implementation in resident CUDA Q6'
FROM milestones m JOIN artifacts a ON a.path='src/cuda_q6_resident_0400.cu'
WHERE m.object_id IN ('milestone:0493x7a','milestone:0493x7b','milestone:0493x7c','milestone:0493x7d');

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7a','ANALYZED_BY',object_id,'A','virial density audit analyzer'
FROM artifacts WHERE path='scripts/analyze_0493x7a_virial_density.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7b','QUALIFIED_BY',object_id,'A','continuum virial grid-scaling checker'
FROM artifacts WHERE path='scripts/check_0493x7b_virial_grid_scaling.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7c','ANALYZED_BY',object_id,'A','density-RHS analyzer'
FROM artifacts WHERE path='scripts/analyze_0493x7c_density_rhs.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7d','QUALIFIED_BY',object_id,'A','paired grid-refinement runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x7d_density_rhs_grid_refinement.sh','scripts/analyze_0493x7d_density_rhs_grid_refinement.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7e','QUALIFIED_BY',object_id,'A','combined x6g+x7d qualification runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x7e_x6g_x7d_validation.sh','scripts/analyze_0493x7e_x6g_x7d_combination.py');
