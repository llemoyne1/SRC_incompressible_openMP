-- V4.9: consolidate 0493x6a..x6g and add the missing x6f2 geometry fix.
--
-- The original consolidated reference already contains x6a..x6g in compact form.
-- This curation replaces those retrospective summaries with definitions grounded in
-- their dedicated READMEs/runners.  x6f2 was absent from the canonical reference even
-- though it is an explicit historical fix with a dedicated README and Git label, so it
-- is added as a new milestone.

-- x6a: diagnostic-only gas EOS pressure potential; no Q6 physics change yet.
UPDATE milestones
SET group_name='x6a-x6g : séparation support/interface et pression gazeuse',
    name='Diagnostic EOS de pression gazeuse interfaciale',
    summary='Reconstruit, sans modifier l''opérateur Q6, la pression idéale du gaz p_g=N_g kBT/A_cell et le potentiel phi_g=dt*p_g/rho_l,ref sur les faces liquide/non-liquide du support free_surface_masked. Le champ est audité mais n''est pas consommé par la projection; pGamma reste nul.',
    nature='DIAGNOSTIC',
    domain='Q6_GF',
    status='Diagnostic EOS préparatoire; aucune rétroaction sur le solveur',
    confidence='A',
    notes='Agrège les espèces phaseFamily=gas dans chaque cellule. Le diagnostic mesure l''EOS idéale, pas encore le tenseur de contrainte MPCD complet. Introduit le buffer de potentiel gazeux réutilisé physiquement par x6g.',
    source_file='README_0493X6A_Q6_PHASE_PRESSURE_DIAGNOSTIC.md',
    source_row=NULL
WHERE object_id='milestone:0493x6a';

-- x6b: sparse diagnostic showing that support and physical alpha=0.5 interface differ.
UPDATE milestones
SET group_name='x6a-x6g : séparation support/interface et pression gazeuse',
    name='Diagnostic géométrique support Q6 / interface alpha=0.5',
    summary='Reconstruit à cadence sparse un remplissage de phase à partir des masses cellule-espèce et audite support numérique, crossing alpha=0.5, distances sous-maille et normales, sans créer de champ géométrique résident ni modifier l''opérateur. Cette étape formalise la différence entre le carrier Q6 et l''interface physique.',
    nature='DIAGNOSTIC',
    domain='Q6_GF',
    status='Diagnostic géométrique; prépare la matérialisation résidente x6c',
    confidence='A',
    notes='Une seule passe CUDA O(Ncells) aux pas d''audit; aucune passe particulaire et aucun champ O(Ncells) permanent. x6a est volontairement désactivé dans le runner de référence afin d''isoler le coût géométrique.',
    source_file='README_0493X6B_PHASE_GEOMETRY_DIAGNOSTIC.md',
    source_row=NULL
WHERE object_id='milestone:0493x6b';

-- x6c: materialize raw occupancy and a filtered alpha field resident on CUDA.
UPDATE milestones
SET group_name='x6a-x6g : séparation support/interface et pression gazeuse',
    name='Infrastructure résidente du champ de phase alpha',
    summary='Matérialise sur GPU, à chaque solve Q6 free_surface_masked, un champ rawFill issu des masses liquides puis un champ alpha filtré par un stencil cinq points conservatif avec lambda=0.125. À son introduction ces champs sont construits mais non consommés par la projection; ils deviennent ensuite la géométrie commune de x6d/x6e/x6f/x6g.',
    nature='INFRA',
    domain='Q6_GF',
    status='Infrastructure géométrique résidente; base des stencils d''interface ultérieurs',
    confidence='A',
    notes='Deux passes CUDA O(Ncells) par solve. Le lambda=0.125 est fixé dans le code à ce stade. x6f2 corrigera plus tard la source géométrique en bornant rawFill avant filtrage tout en conservant rawFill comme diagnostic non borné.',
    source_file='README_0493X6C_PHASE_GEOMETRY_RESIDENT.md',
    source_row=NULL
WHERE object_id='milestone:0493x6c';

-- x6d: first active consumer, but tied to the carrier boundary and later rejected.
UPDATE milestones
SET group_name='x6a-x6g : séparation support/interface et pression gazeuse',
    name='Expérience cut-face 1/theta sur le bord du carrier',
    summary='Premier consommateur actif du champ alpha résident : sur une face active/inactive du carrier qui encadre alpha=0.5, remplace le facteur demi-maille par la distance sous-maille theta et utilise 1/theta dans l''opérateur/correction; les petits theta gardent le facteur 2 de stabilisation. La pression interfaciale reste pGamma=0.',
    nature='CODE',
    domain='Q6_GF',
    status='Expérience active historique; architecture abandonnée au profit de x6f',
    confidence='A',
    notes='x6d suppose encore carrier boundary == physical interface. x6e montre que cette identification est fausse dans les géométries déformées. x6d reste un chemin de comparaison, mutuellement exclusif avec x6f.',
    source_file='README_0493X6D_GUARDED_CUTFACE_ZERO_PRESSURE.md',
    source_row=NULL
WHERE object_id='milestone:0493x6d';

-- x6e: classify every physical alpha=0.5 crossing independently of the carrier.
UPDATE milestones
SET group_name='x6a-x6g : séparation support/interface et pression gazeuse',
    name='Audit topologique de l''interface physique alpha=0.5',
    summary='Scanne toutes les faces de grille traversant alpha=0.5 indépendamment du carrier Q6 et classe les crossings active-active, active-inactive et inactive-inactive. Le diagnostic démontre que l''interface physique traverse fréquemment des paires de cellules encore toutes deux dans le carrier et invalide l''architecture cut-face x6d.',
    nature='DIAGNOSTIC',
    domain='Q6_GF',
    status='Diagnostic architectural décisif; motive pressureMask séparé de x6f',
    confidence='A',
    notes='Le scan est fusionné dans l''audit sparse x6c et n''ajoute ni champ ni passe de production. Les crossings active-inactive sont séparés selon le côté liquide/externe afin de mesurer exactement la couverture du chemin x6d.',
    source_file='README_0493X6E_PHASE_INTERFACE_TOPOLOGY.md',
    source_row=NULL
WHERE object_id='milestone:0493x6e';

-- x6f: final topology architecture before gas pressure: pressureMask != carrierMask.
UPDATE milestones
SET group_name='x6a-x6g : séparation support/interface et pression gazeuse',
    name='Stencil résident de pression sur l''interface physique alpha=0.5',
    summary='Sépare le carrier de particules du domaine de pression : pressureMask=carrierMask AND alpha>=0.5. Une passe CUDA prépare une fois par solve les coefficients east/north des faces (1 intérieur, 1/theta crossing physique, 2 small-theta, 0 sans couplage), ensuite réutilisés à chaque itération CG. Le pGamma reste nul dans cette étape.',
    nature='CODE',
    domain='Q6_GF',
    status='Architecture d''interface retenue; géométrie bornée par x6f2 avant x6g',
    confidence='A',
    notes='x6f supprime l''identification carrier boundary == pressure boundary réfutée par x6e. Les pertes de carrier sans crossing physique ne deviennent pas des surfaces p=0 artificielles. External BC et Darcy/chi restent gérés par leurs chemins existants.',
    source_file='README_0493X6F_PHASE_INTERFACE_STENCIL.md',
    source_row=NULL
WHERE object_id='milestone:0493x6f';

-- x6f2: missing canonical fix.  Raw occupancy may exceed one, but geometry may not.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x6f2','MILESTONE','x6f2','curation:0010_0493x6_phase_interface_architecture');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x6f2','0493x6f2','x6f2','0493x6f2',
  'x6a-x6g : séparation support/interface et pression gazeuse',
  'Correction : géométrie de phase bornée avant filtrage',
  'Sépare l''occupation liquide brute, volontairement non bornée, de la géométrie d''interface : le filtre x6c consomme désormais geom0=clamp(rawFill,0,1), puis alpha=geom0+lambda*sum(geom0_nb-geom0). Cette correction empêche une forte sur-occupation voisine de créer artificiellement alpha>0.5 dans une cellule vide.',
  'FIX','Q6_GF','Correctif géométrique actif de la chaîne x6f/x6g','A',
  NULL,NULL,NULL,
  'Aucun champ résident ni passe CUDA supplémentaire. rawFill reste disponible comme diagnostic d''occupation non bornée; seule sa réinterprétation comme source géométrique est corrigée. Avec lambda=0.125, le filtre de geom0 borné reste une combinaison convexe et alpha demeure dans [0,1].',
  'README_0493X6F2_BOUNDED_PHASE_GEOMETRY.md',NULL
);

-- x6g: first physical gas-pressure boundary condition on the prepared interface.
UPDATE milestones
SET group_name='x6a-x6g : séparation support/interface et pression gazeuse',
    name='Condition de pression gazeuse sur l''interface physique',
    summary='Réutilise le stencil x6f/x6f2 pour imposer p_l|Gamma=p_g. Sur chaque face alpha=0.5, construit phiGamma=dt*(p_g-p_ref)/rho_l,ref à partir du gaz côté alpha<0.5 (EOS ou pression constante), l''injecte dans le RHS et la correction de face sans modifier la matrice CG. Cette face deviendra ensuite le point d''insertion de p_g+sigma*kappa.',
    nature='CODE',
    domain='Q6_GF',
    status='Couplage pression gaz actif sur interface résidente; base du futur terme capillaire',
    confidence='A',
    notes='Requiert x6f et la géométrie x6c corrigée par x6f2. Le mode EOS exige au moins une espèce gas. La trace EOS est évaluée dans la cellule côté gaz afin d''éviter une dilution par le liquide d''une cellule mixte.',
    source_file='README_0493X6G_PHASE_GAS_PRESSURE.md',
    source_row=NULL
WHERE object_id='milestone:0493x6g';

-- Dedicated documentary evidence.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6a','MILESTONE_README','README_0493X6A_Q6_PHASE_PRESSURE_DIAGNOSTIC.md','A','Diagnostic-only gas EOS pressure scaffold'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x6a' AND evidence_type='MILESTONE_README' AND path='README_0493X6A_Q6_PHASE_PRESSURE_DIAGNOSTIC.md');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6b','MILESTONE_README','README_0493X6B_PHASE_GEOMETRY_DIAGNOSTIC.md','A','Sparse support/interface geometry diagnostic'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x6b' AND evidence_type='MILESTONE_README' AND path='README_0493X6B_PHASE_GEOMETRY_DIAGNOSTIC.md');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6c','MILESTONE_README','README_0493X6C_PHASE_GEOMETRY_RESIDENT.md','A','Resident raw-fill and filtered-alpha geometry infrastructure'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x6c' AND evidence_type='MILESTONE_README' AND path='README_0493X6C_PHASE_GEOMETRY_RESIDENT.md');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6d','MILESTONE_README','README_0493X6D_GUARDED_CUTFACE_ZERO_PRESSURE.md','A','Guarded cut-face geometry experiment at zero gauge pressure'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x6d' AND evidence_type='MILESTONE_README' AND path='README_0493X6D_GUARDED_CUTFACE_ZERO_PRESSURE.md');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6e','MILESTONE_README','README_0493X6E_PHASE_INTERFACE_TOPOLOGY.md','A','Topology audit independent of the carrier boundary'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x6e' AND evidence_type='MILESTONE_README' AND path='README_0493X6E_PHASE_INTERFACE_TOPOLOGY.md');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6f','MILESTONE_README','README_0493X6F_PHASE_INTERFACE_STENCIL.md','A','Prepared alpha=0.5 pressure-interface stencil'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x6f' AND evidence_type='MILESTONE_README' AND path='README_0493X6F_PHASE_INTERFACE_STENCIL.md');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6f2','MILESTONE_README','README_0493X6F2_BOUNDED_PHASE_GEOMETRY.md','A','Bounded geometry-source correction before alpha filtering'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x6f2' AND evidence_type='MILESTONE_README' AND path='README_0493X6F2_BOUNDED_PHASE_GEOMETRY.md');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x6g','MILESTONE_README','README_0493X6G_PHASE_GAS_PRESSURE.md','A','Physical gas-pressure Dirichlet coupling on the alpha=0.5 interface'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x6g' AND evidence_type='MILESTONE_README' AND path='README_0493X6G_PHASE_GAS_PRESSURE.md');

-- Architectural chain.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6a','BUILDS_ON','milestone:0493x5b','A','x6a diagnoses the gas pressure missing from the x5b pressure boundary');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6b','BUILDS_ON','milestone:0493x6a','A','after pressure diagnostics, x6b isolates the missing phase geometry without changing physics');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6c','BUILDS_ON','milestone:0493x6b','A','x6c materializes the phase geometry that x6b reconstructed only at audit cadence');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6d','BUILDS_ON','milestone:0493x6c','A','x6d is the first active consumer of the resident alpha field');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6e','BUILDS_ON','milestone:0493x6c','A','x6e scans the resident alpha field independently of the carrier');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6e','DIAGNOSES','milestone:0493x6d','A','x6e proves that the carrier boundary used by x6d is not the full physical alpha=0.5 interface');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6d','SUPERSEDED_BY','milestone:0493x6f','A','x6f replaces carrier-boundary cut faces by a pressure domain defined from the physical alpha interface');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6f','BUILDS_ON','milestone:0493x6e','A','x6f implements the architecture required by the complete x6e crossing topology');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6f2','BUILDS_ON','milestone:0493x6f','A','x6f2 corrects the geometry source used by the active x6f stencil');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6f2','FIXES','milestone:0493x6f','A','bounded phase geometry prevents false alpha=0.5 interfaces caused by over-occupied raw cells');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6f2','FIXES','milestone:0493x6c','A','the x6c filter source is changed from unbounded raw occupancy to clamp(raw,0,1)');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6g','BUILDS_ON','milestone:0493x6f2','A','x6g consumes the prepared physical interface after the bounded-geometry correction');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x6g','EXTENDS','milestone:0493x6a','A','x6g turns the x6a diagnostic gas-pressure potential into a physical Dirichlet boundary value');

-- Repository artifacts, conditional on their presence in the scanned worktree.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6a','QUALIFIED_BY',object_id,'A','x6a gas-pressure diagnostic runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x6a_phase_pressure_diagnostic.sh','scripts/analyze_0493x6a_phase_pressure.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6b','QUALIFIED_BY',object_id,'A','x6b phase-geometry diagnostic runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x6b_phase_geometry_diagnostic.sh','scripts/analyze_0493x6b_phase_geometry.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6c','QUALIFIED_BY',object_id,'A','x6c resident geometry runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x6c_phase_geometry_resident.sh','scripts/analyze_0493x6c_phase_geometry_resident.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6d','QUALIFIED_BY',object_id,'A','x6d guarded cut-face geometry runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x6d_cutface_geometry_zero_pressure.sh','scripts/analyze_0493x6d_cutface_geometry.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6e','QUALIFIED_BY',object_id,'A','x6e full alpha=0.5 topology runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x6e_phase_interface_topology.sh','scripts/analyze_0493x6e_phase_interface_topology.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6f','QUALIFIED_BY',object_id,'A','x6f prepared interface-stencil runner/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493x6f_phase_interface_stencil.sh','scripts/analyze_0493x6f_phase_interface_stencil.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6f2','QUALIFIED_BY',object_id,'A','x6f runner after bounded-geometry correction'
FROM artifacts WHERE path='scripts/run_0493x6f_phase_interface_stencil.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x6g','QUALIFIED_BY',object_id,'A','x6g gas-pressure interface qualification/validation'
FROM artifacts WHERE path IN ('scripts/run_0493x6g_phase_gas_pressure.sh','scripts/analyze_0493x6g_phase_gas_pressure.py','scripts/run_0493x6g_validation.sh');

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','x6 phase/interface implementation in resident CUDA Q6'
FROM milestones AS m
JOIN artifacts AS a ON a.path='src/cuda_q6_resident_0400.cu'
WHERE m.object_id IN ('milestone:0493x6a','milestone:0493x6b','milestone:0493x6c','milestone:0493x6d','milestone:0493x6e','milestone:0493x6f','milestone:0493x6f2','milestone:0493x6g');
