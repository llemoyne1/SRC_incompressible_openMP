-- V4.16: close x8 with x8u and reconstruct the first coherent capillary block x9a..x9h.
-- Accelerated packaging, without collapsing identities:
--   x8u  runner-level reintegration of validated x8t Neumann closure into x8m lineage
--   x9a  passive curvature scaffold on physical x6c alpha
--   x9b  passive binomial+Scharr curvature candidate / resident LiveVis
--   x9c  passive smoothing-support sweep selecting p3 for production
--   x9d  first active Laplace pressure jump in Q6-g-f
--   x9e  static-drop pressure/velocity diagnostics
--   x9f  true interface-band and ellipse relaxation diagnostics
--   x9g  phase-pair A/B abstraction
--   x9h  passive wall geometry provider; no contact-angle physics yet
-- x9i and later wetting prototypes are deliberately deferred.

-- New canonical identities absent from the raw reference.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from) VALUES
('milestone:0493x8u','MILESTONE','x8u','curation:0017_0493x8u_x9a_x9h_capillary_scaffold'),
('milestone:0493x9a','MILESTONE','x9a','curation:0017_0493x8u_x9a_x9h_capillary_scaffold'),
('milestone:0493x9b','MILESTONE','x9b','curation:0017_0493x8u_x9a_x9h_capillary_scaffold'),
('milestone:0493x9c','MILESTONE','x9c','curation:0017_0493x8u_x9a_x9h_capillary_scaffold');

INSERT OR REPLACE INTO milestones(object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row) VALUES
('milestone:0493x8u','0493x8u','x8u','0493x8u','x8 : conditions limites ouvertes et benchmark von Karman','Réalignement du runner Zovatto sur la fermeture x8t','Met à jour le runner restartable x8m pour utiliser explicitement la fermeture Neumann cinétique-pression validée x8q-x8t, autoriser RUN_MODES et activer par défaut le bruit thermique de l''inlet. Aucun C++/CUDA ni opérateur physique n''est introduit.','INFRA','OPEN_BOUNDARY','Réintégration production de la fermeture x8t dans la lignée x8m; clôture documentaire du cycle x8','A',NULL,NULL,NULL,'Updater runner-only. Il remplace les métadonnées passive_x8l par kinetic_pressure_x8t et passe inletThermalNoise de 0 à une valeur paramétrable par défaut 1.0.','update_0493x8u_zovatto_runner.py',NULL),
('milestone:0493x9a','0493x9a','x9a','0493x9a','x9 : tension superficielle, courbure et mouillage','Premier scaffold passif de courbure résident','Construit à partir du champ physique alpha x6c une normale sortante et une courbure cellulaires résidentes, puis audite la courbure aux crossings alpha=0.5, sans sigma, sans modification de phiGamma/RHS/B1 et sans kick particulaire.','DIAGNOSTIC','SURFACE_TENSION','Scaffold passif historique; géométrie seulement, sans tension superficielle active','A',NULL,NULL,NULL,'x9a représente le coût et le contrat géométrique initial de la future capillarité tout en garantissant un no-op physique.','README_0493X9A.md',NULL),
('milestone:0493x9b','0493x9b','x9b','0493x9b','x9 : tension superficielle, courbure et mouillage','Courbure passive binomiale + Scharr et LiveVis résident','Ajoute un champ alphaK réservé à la courbure : une passe binomiale 3x3 sur alpha_x6c, gradient Scharr, normale sortante puis divergence Scharr. L''interface physique reste celle de x6c alpha=0.5; le champ est visualisable directement depuis CUDA.','DIAGNOSTIC','SURFACE_TENSION','Estimateur passif p1 conservé comme baseline; aucune physique capillaire active','A',NULL,NULL,NULL,'Le candidat Hessien direct n''est pas retenu car il amplifie le bruit du champ alpha quantifié. x9b-audit2 reste une sous-révision diagnostique et non un jalon autonome.','README_0493X9B_PASSIVE_CURVATURE_LIVEVIS.md',NULL),
('milestone:0493x9c','0493x9c','x9c','0493x9c','x9 : tension superficielle, courbure et mouillage','Qualification du support de lissage de courbure','Compare passivement, avec le même opérateur Scharr, une, deux et trois passes binomiales 3x3 du champ alphaK sur une matrice gamma/rayon. La production retient ensuite p3, soit trois passes, comme compromis de courbure utilisé par x9d.','QUALIFICATION','SURFACE_TENSION','Qualification passive; sélectionne p3 pour la courbure de production, sans déplacer l''interface x6c','A',NULL,NULL,NULL,'Le sweep ne modifie ni alpha physique ni phiGamma et n''impose pas de seuil PASS universel; il établit le compromis bruit/biais et la résolution de courbure.','README_0493X9C_SMOOTHING_SWEEP.md',NULL);

-- Consolidate raw-reference x9d..x9h from primary historical documentation.
UPDATE milestones SET
 group_name='x9 : tension superficielle, courbure et mouillage',
 name='Premier saut de Laplace actif dans Q6-g-f',
 summary='Ajoute surfaceTensionSigma et utilise la courbure p3 qualifiée par x9c pour imposer aux crossings physiques x6f phiGamma_cap=(dt/rhoA_ref)*sigma*kappaGamma, composé avec la pression extérieure x6g. Aucun terme CSF volumique ni kick capillaire particulaire n''est ajouté.',
 nature='CODE',domain='SURFACE_TENSION',status='Coeur actif de la capillarité bulk; sigma=0 est un no-op exact',confidence='A',
 notes='Le champ alpha_x6c et la position alpha=0.5 restent inchangés; seul le potentiel de Dirichlet interfacial reçoit le saut de Laplace. En 2D, la cible circulaire est sigma/R.',
 source_file='README_0493X9D_ACTIVE_LAPLACE.md',source_row=NULL
WHERE object_id='milestone:0493x9d';

UPDATE milestones SET
 group_name='x9 : tension superficielle, courbure et mouillage',
 name='Qualification diagnostique de goutte statique',
 summary='Ajoute à cadence de résumé des réductions CUDA strictement observationnelles : aire/Reff, pression Q6 cohérente avec la jauge x6g, saut de pression, sigma/Reff, courbure d''interface, résultante capillaire et vitesses liquides/spurious currents.',
 nature='DIAGNOSTIC',domain='SURFACE_TENSION',status='Diagnostic/qualification au-dessus de x9d; physique inchangée',confidence='A',
 notes='La pression rapportée est la pression de projection Q6 dans la même jauge que x6g/x9d, pas une pression thermodynamique absolue reconstruite indépendamment.',
 source_file='README_0493X9E_STATIC_DROP_DIAGNOSTICS.md',source_row=NULL
WHERE object_id='milestone:0493x9e';

UPDATE milestones SET
 group_name='x9 : tension superficielle, courbure et mouillage',
 name='Diagnostic de bande interfaciale vraie et relaxation elliptique',
 summary='Remplace la bande diagnostique alpha 0.1-0.9 par le critère discret de crossing alpha=0.5 et suit COM particulaire, tenseur de moments, rayons principaux, ellipticité et rayons des crossings pour qualifier la relaxation capillaire d''une ellipse vers une goutte circulaire.',
 nature='DIAGNOSTIC',domain='SURFACE_TENSION',status='Diagnostic de forme/relaxation au-dessus de x9e; aucune modification de la capillarité',confidence='A',
 notes='Corrige l''ancienne description trop étroite « quadrupole signé » : les observables primaires sont notamment les rayons de moments et le COM réel, avec extrema de crossings comme diagnostics secondaires.',
 source_file='README_0493X9F_ELLIPSE_DIAGNOSTICS.md',source_row=NULL
WHERE object_id='milestone:0493x9f';

UPDATE milestones SET
 group_name='x9 : tension superficielle, courbure et mouillage',
 name='Généralisation de l''interface aux paires de phases A/B',
 summary='Remplace dans la chaîne de production x6c/x6f/x6g/x9d l''hypothèse Liquid/Gas codée en dur par deux sélecteurs A/B. A est le côté alpha-high projeté et fournit masse/référence; B est le côté extérieur et peut sélectionner famille, type explicite ou vacuum. Le chemin historique liquid/gas reste byte-for-byte équivalent dans la qualification.',
 nature='CODE',domain='SURFACE_TENSION',status='Actif; abstraction de paire sans prétendre fournir un solveur immiscible symétrique général',confidence='A',
 introduced_date='2026-08-17',introduced_commit='240c2e6e0f267f9314aab1634799629ce07f66ab',
 notes='B=wall est accepté par la grammaire mais volontairement rejeté dans x9g faute de provider géométrique; x9h active ensuite ce cas. Les contraintes x7b/x7c et B1 mono-projeté ne sont pas généralisées ici.',
 source_file='README_0493X9G_PHASE_PAIR_GENERALIZATION.md',source_row=NULL
WHERE object_id='milestone:0493x9g';

UPDATE milestones SET
 group_name='x9 : tension superficielle, courbure et mouillage',
 name='Provider géométrique résident de paroi',
 summary='Active B=wall comme troisième objet géométrique indépendant des phases particulaires : combine parois de domaine et, sur opt-in wallVP, géométrie chi avec S=1-chi; fournit fraction solide et normale murale résidentes sans modifier alpha libre ni imposer encore angle de contact ou saut capillaire liquide/solide.',
 nature='CODE',domain='SURFACE_TENSION',status='Géométrie-only qualifiée; capillarité/mouillage avec B=wall encore interdits à cette étape',confidence='A',
 introduced_date='2026-08-17',introduced_commit='3c78e280e85b7f220c8b932cad0da04857edfe57',
 notes='La normale de mur emploie la même famille Scharr que x9b/x9c. Les BC Q6 de paroi restent autoritaires; x9h ne convertit pas le mur en côté Dirichlet x6f et prépare seulement les étapes de contact-angle x9i+.',
 source_file='README_0493X9H_WALL_GEOMETRY_PROVIDER.md',source_row=NULL
WHERE object_id='milestone:0493x9h';

-- Primary historical evidence.
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8u','HISTORICAL_SOURCE','Info/inputs/historical/update_0493x8u_zovatto_runner.py',NULL,'A','Primary x8u runner updater aligning x8m restartable production with x8t BCs'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8u' AND path='Info/inputs/historical/update_0493x8u_zovatto_runner.py');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9a','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9A.md',NULL,'A','Primary x9a passive-curvature scaffold documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9a' AND path='Info/inputs/historical/README_0493X9A.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9b','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9B_PASSIVE_CURVATURE_LIVEVIS.md',NULL,'A','Primary x9b binomial+Scharr passive curvature documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9b' AND path='Info/inputs/historical/README_0493X9B_PASSIVE_CURVATURE_LIVEVIS.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9c','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9C_SMOOTHING_SWEEP.md',NULL,'A','Primary x9c curvature support sweep documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9c' AND path='Info/inputs/historical/README_0493X9C_SMOOTHING_SWEEP.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9d','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9D_ACTIVE_LAPLACE.md',NULL,'A','Primary x9d active Laplace pressure-jump documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9d' AND path='Info/inputs/historical/README_0493X9D_ACTIVE_LAPLACE.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9e','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9E_STATIC_DROP_DIAGNOSTICS.md',NULL,'A','Primary x9e static-drop diagnostic documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9e' AND path='Info/inputs/historical/README_0493X9E_STATIC_DROP_DIAGNOSTICS.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9f','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9F_ELLIPSE_DIAGNOSTICS.md',NULL,'A','Primary x9f ellipse/true-interface-band diagnostics documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9f' AND path='Info/inputs/historical/README_0493X9F_ELLIPSE_DIAGNOSTICS.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9g','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9G_PHASE_PAIR_GENERALIZATION.md',NULL,'A','Primary x9g phase-pair abstraction documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9g' AND path='Info/inputs/historical/README_0493X9G_PHASE_PAIR_GENERALIZATION.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9h','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9H_WALL_GEOMETRY_PROVIDER.md',NULL,'A','Primary x9h wall-geometry provider documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9h' AND path='Info/inputs/historical/README_0493X9H_WALL_GEOMETRY_PROVIDER.md');

-- Explicit Git-introduction evidence already present in the imported full audit.
UPDATE evidence SET confidence='A' WHERE object_id IN ('milestone:0493x9g','milestone:0493x9h') AND evidence_type='GIT_COMMIT';
UPDATE relations SET confidence='A' WHERE source_object_id IN ('milestone:0493x9g','milestone:0493x9h') AND relation_type='EVIDENCED_BY_COMMIT';

-- Causal/dependency structure.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:0493x8u','BUILDS_ON','milestone:0493x8t','A','x8u explicitly updates the restartable Zovatto runner to the validated x8t kinetic-pressure outlet'),
('milestone:0493x8u','REFERENCES','milestone:0493x8m','A','x8u modifies the x8m restartable production lineage'),
('milestone:0493x9a','BUILDS_ON','milestone:0493x6c','A','x9a builds passive curvature from the qualified physical alpha_x6c field'),
('milestone:0493x9b','BUILDS_ON','milestone:0493x9a','A','x9b introduces the selected binomial+Scharr candidate while retaining x9a as baseline'),
('milestone:0493x9c','BUILDS_ON','milestone:0493x9b','A','x9c sweeps smoothing support with the x9b Scharr operator fixed'),
('milestone:0493x9d','BUILDS_ON','milestone:0493x9c','A','x9d activates sigma*kappa using the p3 curvature selected by x9c'),
('milestone:0493x9d','REFERENCES','milestone:0493x6g','A','x9d composes capillary phiGamma with the existing exterior-pressure provider'),
('milestone:0493x9e','BUILDS_ON','milestone:0493x9d','A','x9e observes the active static-drop physics without changing it'),
('milestone:0493x9f','BUILDS_ON','milestone:0493x9e','A','x9f extends diagnostics to true crossing bands and ellipse-shape observables'),
('milestone:0493x9g','BUILDS_ON','milestone:0493x9f','A','x9g generalizes the already-qualified liquid/gas production chain to an A/B selector contract'),
('milestone:0493x9h','BUILDS_ON','milestone:0493x9g','A','x9h activates the reserved B=wall selector as geometry only');

-- Candidate reconciliation: x9a-x9c are promoted from B candidates to linked canonical identities.
-- x9d-x9h are already linked in the historical audit, but this is idempotent.
UPDATE git_milestone_candidates
SET status='LINKED', linked_milestone_object_id='milestone:0493' || label
WHERE label IN ('x8u','x9a','x9b','x9c','x9d','x9e','x9f','x9g','x9h')
  AND EXISTS (SELECT 1 FROM milestones m WHERE m.object_id='milestone:0493' || git_milestone_candidates.label);

-- Current-tree artifact links when present.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9a','QUALIFIED_BY',object_id,'A','x9a curvature qualification runner' FROM artifacts WHERE path='scripts/run_0493x9a_ellipse_curvature.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9b','QUALIFIED_BY',object_id,'A','x9b passive curvature qualification runner' FROM artifacts WHERE path='scripts/run_0493x9b_ellipse_curvature.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9c','QUALIFIED_BY',object_id,'A','x9c smoothing support sweep' FROM artifacts WHERE path='scripts/run_0493x9c_curvature_sweep.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9d','QUALIFIED_BY',object_id,'A','x9d first active static-drop runner' FROM artifacts WHERE path='scripts/run_0493x9d_static_drop.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9e','ANALYZED_BY',object_id,'A','x9e static-drop diagnostic analyzer' FROM artifacts WHERE path='scripts/analyze_0493x9e_static_drop.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9g','QUALIFIED_BY',object_id,'A','x9g phase-pair equivalence runner' FROM artifacts WHERE path='scripts/run_0493x9g_phase_pair_equivalence.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9h','QUALIFIED_BY',object_id,'A','x9h wall geometry provider qualification runner' FROM artifacts WHERE path='scripts/run_0493x9h_wall_geometry_provider.sh';
