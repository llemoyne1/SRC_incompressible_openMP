-- V4.15: reconstruct the x8k..x8t segmented Poiseuille / passive Neumann cycle.
-- Evidence-driven identities:
--   x8k        local segmented Poiseuille inlet (existing canonical, consolidated)
--   x8l        first passive Q6-G-F Neumann face extrapolation (new canonical)
--   x8m        Zovatto-Pedrizzetti Re_H=280 production benchmark lineage (new)
--   x8n        upstream volume/mass-flux diagnostic (new)
--   x8q        particle kinetic continuation; final local-bath form (consolidated)
--   x8r        pressure outlet phi_out=0 (consolidated)
--   x8s        exact low-mode CG deflation (consolidated)
--   x8t        mean-free density-relaxation target with pressure outlet (consolidated)
--
-- x8o/x8p are deliberately NOT invented: no autonomous evidence was found.
-- x8q-fix1..fix4 are implementation sub-revisions of x8q, not separate milestones.
-- The aggregate Git label x8q-x8t remains a candidate, not a composite canonical stage.
-- x8u is deferred: it aligns the restartable x8m runner to the already validated x8t BCs.

-- ---------------------------------------------------------------------------
-- New canonical identities x8l/x8m/x8n.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from) VALUES
('milestone:0493x8l','MILESTONE','x8l','curation:0016_0493x8k_x8t_open_boundary'),
('milestone:0493x8m','MILESTONE','x8m','curation:0016_0493x8k_x8t_open_boundary'),
('milestone:0493x8n','MILESTONE','x8n','curation:0016_0493x8k_x8t_open_boundary');

INSERT OR REPLACE INTO milestones(object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row) VALUES
('milestone:0493x8l','0493x8l','x8l','0493x8l','x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression','Première extrapolation Neumann passive de la vitesse de sortie','Pour un outlet droit segmenté en mode neumann sur le chemin Q6-g-f, remplace la cible nominale UOUT par la vitesse normale de la cellule de bord afin d''imposer au prédicteur une extrapolation discrète à gradient normal nul. Cette étape ne fournit pas encore la condition de pression correcte, réparée ensuite par x8r.','CODE','OPEN_BOUNDARY','Étape intermédiaire conservée : extrapolation de vitesse retenue comme base par x8r, mais sémantique de projection x8l seule supersédée','A',NULL,NULL,NULL,'x8l établit u*_out=u*_cell. Utiliser ensuite cette même valeur comme cible de projection crée un ratchet de vitesse; x8r conserve l''extrapolation prédicteur mais remplace la condition elliptique par phi_out=0.','apply_0493x8l_zovatto_passive_neumann.py',NULL),
('milestone:0493x8m','0493x8m','x8m','0493x8m','x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression','Benchmark de production Zovatto-Pedrizzetti Re_H=280','Matérialise le cas cylindre confiné Q6-g-f dimensionné sur Zovatto-Pedrizzetti : profil de Poiseuille local pleine hauteur, H/D=5, Re_H cible 280, enregistrement des champs et restart. La lignée x8m passe du domaine de développement réduit au domaine bibliographique 15D amont + 40D aval; son outlet initial est x8l et sera réaligné sur x8t par x8u.','BENCHMARK','OPEN_BOUNDARY','Benchmark de production/restart Zovatto; première lignée sous x8l, ensuite réalignée sur la fermeture x8t','A',NULL,NULL,NULL,'Le même label x8m couvre la lignée du cas de production, y compris le passage du domaine réduit de développement au domaine bibliographique complet. x8u n''est pas fusionné ici : il constitue l''alignement ultérieur du runner restartable sur les BC finales.','run_0493x8m_zovatto_re280.sh',NULL),
('milestone:0493x8n','0493x8n','x8n','0493x8n','x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression','Diagnostic de conservation amont du débit et du flux massique','Analyse hors ligne les enregistrements rho/ux du benchmark x8m et reconstruit par section Ub, Qv, rhoBar, Mrho, Jrho et Urho afin de distinguer accommodation de l''inlet, variation de densité et véritable dérive du flux massique. Aucun état physique n''est modifié.','ANALYZER','OPEN_BOUNDARY','Diagnostic hors ligne du conditionnement et de la conservation amont; aucune modification du solveur','A',NULL,NULL,NULL,'Jrho est un flux macroscopique reconstruit depuis les champs coarse-grainés du recorder, pas un audit particulaire microscopique. Les rapports entre sections restent le test pertinent de cohérence spatiale.','analyze_vk_flux_rho_0493x8n.m',NULL);

-- ---------------------------------------------------------------------------
-- Consolidate existing canonical entries x8k and x8q-x8t from primary sources.
-- ---------------------------------------------------------------------------
UPDATE milestones
SET group_name='x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression',
    name='Inlet segmenté à profil de Poiseuille local',
    summary='Définit pour chaque segment une coordonnée tangentielle locale eta=(s-sMin)/(sMax-sMin) et impose u_n=4 Umax eta(1-eta) de façon cohérente dans l''injection particulaire et la cible Q6-g-f; la population hard_cell_density reste uniforme.',
    nature='CODE', domain='OPEN_BOUNDARY',
    status='Actif; sémantique de profil local retenue dans le benchmark Zovatto',
    confidence='A',
    notes='Le runner x8k utilise volontairement un segment partiel [0.20,0.80] pour rendre la localité observable. Son outlet UOUT=Umean n''est qu''un pont temporaire de bilan de flux et n''est pas la fermeture Neumann finale.',
    source_file='run_0493x8k_segmented_local_poiseuille.sh',
    source_row=NULL
WHERE object_id='milestone:0493x8k';

UPDATE milestones
SET group_name='x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression',
    name='Continuation cinétique locale de l''outlet Neumann',
    summary='Complète la sortie Neumann au niveau particulaire : les sortants sont supprimés et la demi-distribution entrante est reconstruite dans la forme finale x8q-fix4 par un bain maxwellien local issu des moments pré-stream des deux couches intérieures, avec échantillonnage pondéré par le flux normal.',
    nature='CODE', domain='OPEN_BOUNDARY',
    status='Actif pour outlet Neumann; forme finale local-bath après les sous-révisions x8q-fix1..fix4',
    confidence='A',
    notes='La première implémentation x8q miroir/copie puis le sampler particule-à-particule de fix3 étaient des étapes internes. fix4 supprime la rétroaction auto-excitante et définit la fermeture cinétique retenue; les suffixes fix ne sont pas promus comme jalons autonomes.',
    source_file='apply_0493x8q_fix4_local_bath.py',
    source_row=NULL
WHERE object_id='milestone:0493x8q';

UPDATE milestones
SET group_name='x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression',
    name='Outlet de pression Neumann Q6-g-f',
    summary='Conserve u*_out=u*_cell comme extrapolation de vitesse prédicteur, mais cesse de la réimposer comme cible physique : la projection impose phi_out=0 à la face ouverte et laisse la correction normale finale être déterminée par la continuité.',
    nature='CODE', domain='OPEN_BOUNDARY',
    status='Actif; sémantique pression passive du mode openBoundaryOutletMode=neumann',
    confidence='A',
    notes='x8r corrige le ratchet de vitesse de x8l tout en conservant son extrapolation de base. L''inlet reste prescrit et le bain cinétique x8q reste inchangé.',
    source_file='apply_0493x8r_neumann_pressure_outlet.py',
    source_row=NULL
WHERE object_id='milestone:0493x8r';

UPDATE milestones
SET group_name='x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression',
    name='Déflation exacte des modes longitudinaux lents du CG',
    summary='Pour le domaine rectangulaire complet avec condition de correction de pression Neumann côté inlet et outlet droit x8r phi=0, résout analytiquement les trois modes longitudinaux de pression les plus lents à l''initialisation du CG puis démarre sur un résidu orthogonal, sans modifier l''équation ni la tolérance.',
    nature='PERF', domain='OPEN_BOUNDARY',
    status='Actif uniquement dans la géométrie x8r pleine hauteur applicable; physique inchangée',
    confidence='A',
    notes='Sur 1200x400, le CG résident x7j et le fallback host atteignaient le même résidu légèrement supérieur à 1e-5 après 2500 itérations; x8s traite le conditionnement, pas la physique de sortie.',
    source_file='apply_0493x8s_pressure_outlet_lowmode_deflation.py',
    source_row=NULL
WHERE object_id='milestone:0493x8s';

UPDATE milestones
SET group_name='x8k-x8t : inlet Poiseuille segmenté et sortie Neumann cinétique-pression',
    name='Cible de relaxation de densité sans mode moyen à outlet pression',
    summary='Lorsque la relaxation de densité x7d signée, le domaine de pression complet et l''outlet de pression x8r sont simultanément actifs, retire seulement la moyenne spatiale de la cible de divergence de densité avant la projection afin d''éviter une source volumique globale non intentionnelle.',
    nature='CODE', domain='OPEN_BOUNDARY',
    status='Actif dans le couplage fullDomain + x8r + relaxation densité; autres topologies inchangées',
    confidence='A',
    notes='Le mode constant était éliminé par compatibilité dans l''ancien problème purement Neumann mais devient solvable avec l''outlet de pression x8r. x8t conserve toute la redistribution locale signée et soustrait uniquement <d_rho>.',
    source_file='apply_0493x8t_pressure_outlet_density_meanfree.py',
    source_row=NULL
WHERE object_id='milestone:0493x8t';

-- ---------------------------------------------------------------------------
-- Primary evidence archive. Exact original bytes are retained in the nested ZIP;
-- the sibling files are directly readable copies.
-- ---------------------------------------------------------------------------
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8k','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x8k_segmented_local_poiseuille.sh',NULL,'A','Primary x8k qualification runner proving local segment coordinate and temporary outlet bridge'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8k' AND path='Info/inputs/historical/run_0493x8k_segmented_local_poiseuille.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8l','HISTORICAL_SOURCE','Info/inputs/historical/apply_0493x8l_zovatto_passive_neumann.py',NULL,'A','Primary x8l patcher: right segmented Neumann face uses local boundary-cell normal velocity'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8l' AND path='Info/inputs/historical/apply_0493x8l_zovatto_passive_neumann.py');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8m','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x8m_zovatto_re280.sh',NULL,'A','Primary x8m Zovatto Re_H=280 production/restart benchmark runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8m' AND path='Info/inputs/historical/run_0493x8m_zovatto_re280.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8n','HISTORICAL_SOURCE','Info/inputs/historical/analyze_vk_flux_rho_0493x8n.m',NULL,'A','Primary x8n upstream volume/density-weighted flux analyzer'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8n' AND path='Info/inputs/historical/analyze_vk_flux_rho_0493x8n.m');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8q','HISTORICAL_SOURCE','Info/inputs/historical/apply_0493x8q_neumann_kinetic_continuation.py',NULL,'A','Initial x8q kinetic half-space continuation implementation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8q' AND path='Info/inputs/historical/apply_0493x8q_neumann_kinetic_continuation.py');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8q','HISTORICAL_SOURCE','Info/inputs/historical/apply_0493x8q_fix4_local_bath.py',NULL,'A','Final x8q local Maxwellian bath closure replacing self-exciting particle-to-particle sampling'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8q' AND path='Info/inputs/historical/apply_0493x8q_fix4_local_bath.py');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8r','HISTORICAL_SOURCE','Info/inputs/historical/apply_0493x8r_neumann_pressure_outlet.py',NULL,'A','Primary x8r passive pressure-outlet patcher'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8r' AND path='Info/inputs/historical/apply_0493x8r_neumann_pressure_outlet.py');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8s','HISTORICAL_SOURCE','Info/inputs/historical/apply_0493x8s_pressure_outlet_lowmode_deflation.py',NULL,'A','Primary x8s exact low-mode deflation patcher'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8s' AND path='Info/inputs/historical/apply_0493x8s_pressure_outlet_lowmode_deflation.py');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x8t','HISTORICAL_SOURCE','Info/inputs/historical/apply_0493x8t_pressure_outlet_density_meanfree.py',NULL,'A','Primary x8t mean-free density-target patcher'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x8t' AND path='Info/inputs/historical/apply_0493x8t_pressure_outlet_density_meanfree.py');

-- ---------------------------------------------------------------------------
-- Causal structure. x8m/x8n form a benchmark/diagnostic branch from x8l;
-- x8q-x8t form the boundary-closure repair branch. x8u will rejoin them later.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:0493x8k','BUILDS_ON','milestone:0493x8j','A','x8k starts the next open-boundary semantic cycle after the first VK analysis campaign'),
('milestone:0493x8l','BUILDS_ON','milestone:0493x8k','A','passive outlet semantics are introduced after local segmented inlet semantics'),
('milestone:0493x8m','BUILDS_ON','milestone:0493x8l','A','the initial Zovatto production runner explicitly uses the passive x8l right Neumann outlet'),
('milestone:0493x8n','BUILDS_ON','milestone:0493x8m','A','flux/density analyzer is explicitly designed for x8m Zovatto recordings'),
('milestone:0493x8q','BUILDS_ON','milestone:0493x8l','A','x8q supplies the missing particle-level kinetic counterpart of the x8l Q6 face extrapolation'),
('milestone:0493x8r','BUILDS_ON','milestone:0493x8q','A','pressure-outlet correction preserves the x8q kinetic bath'),
('milestone:0493x8r','FIXES','milestone:0493x8l','A','x8r removes the x8l projection-target ratchet while retaining x8l predictor extrapolation'),
('milestone:0493x8s','BUILDS_ON','milestone:0493x8r','A','low-mode deflation addresses the conditioning of the mixed operator created by x8r'),
('milestone:0493x8t','BUILDS_ON','milestone:0493x8s','A','density-target compatibility correction is applied on the x8r/x8s pressure-outlet solve'),
('milestone:0493x8t','REFERENCES','milestone:0493x7d-v2-signed1','A','x8t centers the signed x7d density-relaxation target only in the pressure-outlet coupling');

-- Candidate reconciliation for explicit X labels, when they exist in the real
-- multi-ref Git audit. The aggregate x8q-x8t candidate is deliberately excluded.
UPDATE git_milestone_candidates
SET status='LINKED', linked_milestone_object_id='milestone:0493' || label
WHERE label IN ('x8k','x8l','x8m','x8n','x8q','x8r','x8s','x8t')
  AND EXISTS (SELECT 1 FROM milestones m WHERE m.object_id='milestone:0493' || git_milestone_candidates.label);

-- Current-tree artifact relations, when those artifacts are present on the
-- audited ref. Archive-only evidence above remains sufficient otherwise.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8k','QUALIFIED_BY',object_id,'A','segmented local-Poiseuille qualification runner' FROM artifacts WHERE path='scripts/run_0493x8k_segmented_local_poiseuille.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8m','QUALIFIED_BY',object_id,'A','Zovatto Re_H=280 production benchmark runner' FROM artifacts WHERE path='scripts/run_0493x8m_zovatto_re280.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8n','ANALYZED_BY',object_id,'A','upstream flux/rho analyzer' FROM artifacts WHERE path='matlab/analyze_vk_flux_rho_0493x8n.m';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8l','IMPLEMENTED_IN',object_id,'A','Q6-G-F segmented Neumann predictor extrapolation' FROM artifacts WHERE path='src/cuda_q6_resident_0400.cu';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8q','IMPLEMENTED_IN',object_id,'A','resident particle-level kinetic outlet bath' FROM artifacts WHERE path='src/cuda_classic_src_io_resident_0263.cu';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8r','IMPLEMENTED_IN',object_id,'A','Q6-G-F pressure outlet phi=0 condition' FROM artifacts WHERE path='src/cuda_q6_resident_0400.cu';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8s','IMPLEMENTED_IN',object_id,'A','pressure-outlet low-mode CG deflation' FROM artifacts WHERE path='src/cuda_q6_resident_0400.cu';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x8t','IMPLEMENTED_IN',object_id,'A','mean-free density target for pressure outlet' FROM artifacts WHERE path='src/cuda_q6_resident_0400.cu';
