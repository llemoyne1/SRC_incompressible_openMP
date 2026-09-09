-- V4.13: reconstruct the repair sequence opened by x7n and closed by x7q.
-- Canonical chain:
--   x7n -> x7d-v2 -> x7d-v2-fix2 -> x7d-v2-signed1 -> x7o/x7p -> x7q
--
-- Two historical sub-fixes are deliberately NOT promoted:
-- * x7d-v2-fix1 only completes call sites left unwritten after the original
--   x7d-v2 patcher aborted part-way through application;
-- * x7d-v2-fix2a only removes an erroneous dependency on the legacy
--   projectionMomentumCorrectionEnable gate from the already-defined fix2.
-- Their primary patchers are preserved as evidence of the canonical stages.

-- ---------------------------------------------------------------------------
-- Missing intermediate physical stages.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7d-v2','MILESTONE','x7d-v2','curation:0014_0493x7d_v2_x7q_repairs');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7d-v2','0493x7d-v2','x7d-v2','0493x7d-v2',
  'x7d-v2-x7q : restauration signée, symétrie et fermeture de moment Q6-g-f',
  'Gate cohérent de compression pour la restauration de densité',
  'Remplace, lorsque le gate est activé, la restauration x7d appliquée à chaque fluctuation locale par une admission des défauts positifs cohérents : la cellule et au moins un voisin de face doivent dépasser le même seuil. Après admission, le défaut complet rawFill-1 est conservé dans la cible de divergence; le seuil n''est pas soustrait.',
  'CODE','Q6_GF','Actif dans le profil Q6-g-f qualifié; gate désactivé = comportement x7d historique','A',
  '2026-08-11','1d6eae3b0e6c8c698557207435a7893043f21042',NULL,
  'Motivé par x7n, qui sépare compression structurée et bruit d''occupation. Le patch initial part du checkpoint c47f49f; son patcher a avorté après avoir écrit une partie des fichiers et x7d-v2-fix1 ne fait que terminer ces call-sites. Ce fix1 d''installation n''est donc pas un jalon canonique. Profil final documenté : gate=true, seuil positif 3/gamma.',
  'patch_0493x7d_v2_compression_gate.py',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7d-v2-fix2','MILESTONE','x7d-v2-fix2','curation:0014_0493x7d_v2_x7q_repairs');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7d-v2-fix2','0493x7d-v2-fix2','x7d-v2-fix2','0493x7d-v2-fix2',
  'x7d-v2-x7q : restauration signée, symétrie et fermeture de moment Q6-g-f',
  'Première fermeture du moment périodique B1 au niveau cellule',
  'Dans le chemin monophase fullDomain avec B1 et direction périodique, accumule la correction Q6 massiquement au niveau cellule puis retire son mode uniforme k=0 lors de l''application B1. Les directions non périodiques et les domaines partiels avec traction interfaciale restent inchangés.',
  'FIX','Q6_GF','Correctif intermédiaire actif historiquement; fermeture k=0 centrée cellule ensuite rendue exacte au niveau particulaire par x7q','A',
  '2026-08-11','1d6eae3b0e6c8c698557207435a7893043f21042',NULL,
  'La correction est physique : un gradient de pression interne ne doit pas changer le moment total de l''espèce projetée dans une direction périodique. Le sous-fix fix2a enlève seulement une dépendance indue à projectionMomentumCorrectionEnable et est conservé comme preuve attachée, pas comme jalon séparé.',
  '0493x7d_v2_fix2_periodic_momentum_closure.patch',NULL
);

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x7d-v2-signed1','MILESTONE','x7d-v2-signed1','curation:0014_0493x7d_v2_x7q_repairs');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
VALUES(
  'milestone:0493x7d-v2-signed1','0493x7d-v2-signed1','x7d-v2-signed1','0493x7d-v2-signed1',
  'x7d-v2-x7q : restauration signée, symétrie et fermeture de moment Q6-g-f',
  'Restauration de densité signée à gates cohérents',
  'Conserve la branche positive cohérente de x7d-v2 et ajoute une branche négative de traction/déplétion : un défaut négatif n''est admis que si la cellule et au moins un voisin de face franchissent le seuil négatif; le défaut complet est alors multiplié par q6DensityRelaxationTractionGain. Gain nul est un no-op exact.',
  'CODE','Q6_GF','Actif dans le profil final signé; qualifié avec la chaîne x7q','A',
  '2026-08-11','1d6eae3b0e6c8c698557207435a7893043f21042',NULL,
  'Le patcher signed1 exige explicitement un état x7d-v2/fix2a déjà qualifié, ce qui fixe son ordre historique après la première fermeture de moment. Profil final documenté : seuil positif 3/gamma, seuil négatif 6/gamma, tractionGain=1.0, tau_rho=0.25.',
  '0493x7d_v2_signed1_traction_branch.patch',NULL
);

-- ---------------------------------------------------------------------------
-- Existing retrospective x7o/x7p/x7q rows: replace summaries with primary
-- patch semantics and confidence A.  source_row is cleared so the complete
-- V4.13 sequence publishes together rather than being split by the old table.
-- ---------------------------------------------------------------------------
UPDATE milestones
SET group_name='x7d-v2-x7q : restauration signée, symétrie et fermeture de moment Q6-g-f',
    name='Symétrisation par réflexion du Q6 independent_masked',
    summary='Supprime dans le chemin fullDomain le raccourci directionnel qui assimilait la valeur cellule à la face est/nord. Les vitesses de face deviennent des moyennes FV centrées équivariantes par réflexion et la correction cellule est reconstruite à partir des deux faces opposées, comme dans le chemin masqué.',
    nature='CODE', domain='Q6_GF', status='Actif; corrige le biais est/nord du fullDomain independent_masked', confidence='A',
    introduced_date='2026-08-11', introduced_commit='1d6eae3b0e6c8c698557207435a7893043f21042',
    notes='Le changement vise la discrétisation monophase fullDomain. Les sémantiques de masque/interface des domaines partiels restent celles de x6f; les diagnostics sont alignés sur la même convention de faces centrées.',
    source_file='0493x7o_q6_full_domain_reflection_symmetry.patch', source_row=NULL
WHERE object_id='milestone:0493x7o';

UPDATE milestones
SET group_name='x7d-v2-x7q : restauration signée, symétrie et fermeture de moment Q6-g-f',
    name='Symétrisation par réflexion du Q6 commun',
    summary='Applique au chemin Q6 commun la convention FV centrée validée par x7o : une face intérieure porte la moyenne arithmétique des cellules adjacentes, les corrections sont d''abord construites sur les faces puis la correction cellule réellement appliquée est reconstruite par moyenne des faces opposées.',
    nature='CODE', domain='Q6_GF', status='Actif; enlève l''orientation backward-difference historique du Q6 commun', confidence='A',
    introduced_date='2026-08-11', introduced_commit='1d6eae3b0e6c8c698557207435a7893043f21042',
    notes='x7p est l''analogue common-Q6 de x7o. Il ne remplace pas la condition interfaciale x6f du chemin free_surface_masked.',
    source_file='0493x7p_q6_common_reflection_symmetry.patch', source_row=NULL
WHERE object_id='milestone:0493x7p';

UPDATE milestones
SET group_name='x7d-v2-x7q : restauration signée, symétrie et fermeture de moment Q6-g-f',
    name='Fermeture exacte du moment périodique au niveau particulaire B1/RT0',
    summary='Mesure la correction RT0 réellement échantillonnée aux positions des particules dans le chemin monophase fullDomain périodique, réduit son moment sur GPU puis retire dans un second passage résident le résidu uniforme k=0 laissé par l''estimation centrée cellule de x7d-v2-fix2.',
    nature='CODE', domain='Q6_GF', status='Actif automatiquement pour B1 + fullDomain + direction périodique; chemin partiel/dam-break historique inchangé', confidence='A',
    introduced_date='2026-08-12', introduced_commit='9c76fbb64232065dfe082d0332310b7c9c070a9d',
    notes='Le terme affine RT0 contient un moment lié au barycentre particulaire instantané, qui ne s''annule pas exactement pour un échantillon MPCD fini. x7q ferme ce résidu au niveau où il est réellement créé sans appliquer la correction globale legacy aux espèces compressibles.',
    source_file='0493x7q_exact_particle_periodic_b1_momentum_closure.patch', source_row=NULL
WHERE object_id='milestone:0493x7q';

-- ---------------------------------------------------------------------------
-- Primary historical evidence.  Non-canonical fix1/fix2a are attached to the
-- physical stage they complete/refine.
-- ---------------------------------------------------------------------------
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7d-v2','HISTORICAL_PATCH','Info/inputs/historical/patch_0493x7d_v2_compression_gate.py','A','Primary x7d-v2 coherent positive-compression gate patcher'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7d-v2' AND path='Info/inputs/historical/patch_0493x7d_v2_compression_gate.py');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7d-v2','HISTORICAL_PATCH','Info/inputs/historical/patch_0493x7d_v2_fix1_complete_call_sites.py','A','Non-canonical x7d-v2-fix1: completes call sites left unwritten when the first patcher aborted'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7d-v2' AND path='Info/inputs/historical/patch_0493x7d_v2_fix1_complete_call_sites.py');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7d-v2-fix2','HISTORICAL_PATCH','Info/inputs/historical/0493x7d_v2_fix2_periodic_momentum_closure.patch','A','Primary cell-centred periodic B1 momentum closure patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7d-v2-fix2' AND path='Info/inputs/historical/0493x7d_v2_fix2_periodic_momentum_closure.patch');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7d-v2-fix2','HISTORICAL_PATCH','Info/inputs/historical/patch_0493x7d_v2_fix2a_enable_periodic_momentum_closure.py','A','Non-canonical fix2a: removes dependency on legacy projectionMomentumCorrectionEnable from the fix2 guard'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7d-v2-fix2' AND path='Info/inputs/historical/patch_0493x7d_v2_fix2a_enable_periodic_momentum_closure.py');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7d-v2-signed1','HISTORICAL_PATCH','Info/inputs/historical/patch_0493x7d_v2_signed1_traction_branch.py','A','Primary signed1 patcher; declares required pre-state x7d-v2/fix2a'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7d-v2-signed1' AND path='Info/inputs/historical/patch_0493x7d_v2_signed1_traction_branch.py');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7d-v2-signed1','HISTORICAL_PATCH','Info/inputs/historical/0493x7d_v2_signed1_traction_branch.patch','A','Materialized signed1 diff adding coherent negative traction/depletion branch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7d-v2-signed1' AND path='Info/inputs/historical/0493x7d_v2_signed1_traction_branch.patch');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7o','HISTORICAL_PATCH','Info/inputs/historical/0493x7o_q6_full_domain_reflection_symmetry.patch','A','Primary x7o reflection-equivariant independent_masked patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7o' AND path='Info/inputs/historical/0493x7o_q6_full_domain_reflection_symmetry.patch');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7p','HISTORICAL_PATCH','Info/inputs/historical/0493x7p_q6_common_reflection_symmetry.patch','A','Primary x7p common-Q6 reflection symmetry patch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7p' AND path='Info/inputs/historical/0493x7p_q6_common_reflection_symmetry.patch');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7q','HISTORICAL_PATCH','Info/inputs/historical/0493x7q_exact_particle_periodic_b1_momentum_closure.patch','A','Primary x7q exact particle-level periodic B1 momentum closure diff'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7q' AND path='Info/inputs/historical/0493x7q_exact_particle_periodic_b1_momentum_closure.patch');
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:0493x7q','HISTORICAL_PATCH','Info/inputs/historical/patch_0493x7q_exact_particle_periodic_b1_momentum_closure.py','A','Fail-fast x7q patcher documenting scope and preservation of the historical partial-domain B1 launch'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x7q' AND path='Info/inputs/historical/patch_0493x7q_exact_particle_periodic_b1_momentum_closure.py');

-- Commit-level provenance for the bundled 11-August repair and explicit x7q commit.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT m.object_id,'GIT_COMMIT',NULL,'A','1d6eae3b0e6c8c698557207435a7893043f21042 — q6 symetry restored Poiseuille low Mach validated q6-g-f'
FROM milestones m
WHERE m.object_id IN ('milestone:0493x7d-v2','milestone:0493x7d-v2-fix2','milestone:0493x7d-v2-signed1','milestone:0493x7o','milestone:0493x7p')
  AND NOT EXISTS (SELECT 1 FROM evidence e WHERE e.object_id=m.object_id AND e.evidence_type='GIT_COMMIT' AND e.notes LIKE '1d6eae3%');
UPDATE evidence
SET confidence='A', notes='9c76fbb64232065dfe082d0332310b7c9c070a9d — reparation momentum residuel x7q pour k=0'
WHERE object_id='milestone:0493x7q' AND evidence_type='GIT_COMMIT';

-- ---------------------------------------------------------------------------
-- Causal/semantic relations.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7d-v2','BUILDS_ON','milestone:0493x7n','A','x7n isolates coherent compression versus occupancy noise and motivates the gate');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7d-v2','REFERENCES','milestone:0493x7d','A','x7d-v2 gates the x7d density-restoration target without changing its accepted-defect amplitude');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7d-v2-fix2','FIXES','milestone:0493x7d-v2','A','first periodic k=0 momentum closure developed within the x7d-v2 repair campaign');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7d-v2-signed1','BUILDS_ON','milestone:0493x7d-v2-fix2','A','signed1 patcher explicitly requires the qualified x7d-v2/fix2a state');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7d-v2-signed1','REFERENCES','milestone:0493x7d-v2','A','retains positive coherent gate and adds negative coherent branch');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7o','BUILDS_ON','milestone:0493x7d-v2-signed1','A','reflection-symmetry repair is applied on the signed Q6-g-f state');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7p','BUILDS_ON','milestone:0493x7o','A','x7p applies the x7o reflection-equivariant face convention to common Q6');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7q','BUILDS_ON','milestone:0493x7o','A','x7q acts on the reflection-symmetric independent_masked/fullDomain B1 path');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7q','FIXES','milestone:0493x7d-v2-fix2','A','x7q removes the particle-level RT0 residual left by the cell-centred fix2 estimate');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x7q','REFERENCES','milestone:0493x7p','C','same repair commit family also leaves common-Q6 in the x7p reflection-equivariant convention');

-- Commit objects are already imported from the audited Git refs.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'EVIDENCED_BY_COMMIT','git:1d6eae3b0e6c8c698557207435a7893043f21042','A','bundled 11-August repair commit: q6 symmetry restored; low-Mach Poiseuille validated'
FROM milestones m
WHERE m.object_id IN ('milestone:0493x7d-v2','milestone:0493x7d-v2-fix2','milestone:0493x7d-v2-signed1','milestone:0493x7o','milestone:0493x7p')
  AND EXISTS (SELECT 1 FROM objects WHERE object_id='git:1d6eae3b0e6c8c698557207435a7893043f21042');
UPDATE relations
SET confidence='A', evidence_text='explicit x7q commit: reparation momentum residuel x7q pour k=0'
WHERE source_object_id='milestone:0493x7q' AND relation_type='EVIDENCED_BY_COMMIT'
  AND target_object_id='git:9c76fbb64232065dfe082d0332310b7c9c070a9d';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7q','EVIDENCED_BY_COMMIT','git:887181b9fd42e972f7f7281fabcf6e91c15739d6','A','final physical qualification commit: TG, Poiseuille, io_box and bend-pipe passed'
WHERE EXISTS (SELECT 1 FROM objects WHERE object_id='git:887181b9fd42e972f7f7281fabcf6e91c15739d6');

-- ---------------------------------------------------------------------------
-- Implementation / analysis / final qualification artifacts from current tree.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','resident CUDA implementation of x7d-v2 through x7q repair stages'
FROM milestones m JOIN artifacts a ON a.path='src/cuda_q6_resident_0400.cu'
WHERE m.object_id IN ('milestone:0493x7d-v2','milestone:0493x7d-v2-fix2','milestone:0493x7d-v2-signed1','milestone:0493x7o','milestone:0493x7p','milestone:0493x7q');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','parameter declarations for coherent signed density restoration'
FROM milestones m JOIN artifacts a ON a.path='include/simulation_params.h'
WHERE m.object_id IN ('milestone:0493x7d-v2','milestone:0493x7d-v2-signed1');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','parameter parsing/validation for coherent signed density restoration'
FROM milestones m JOIN artifacts a ON a.path='src/params_io_base.cpp'
WHERE m.object_id IN ('milestone:0493x7d-v2','milestone:0493x7d-v2-signed1');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'IMPLEMENTED_IN',a.object_id,'A','Q6-g-f runner controls for coherent signed density restoration'
FROM milestones m JOIN artifacts a ON a.path='scripts/src_mpcd_run_common_0434.sh'
WHERE m.object_id IN ('milestone:0493x7d-v2','milestone:0493x7d-v2-signed1');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x7d-v2-signed1','ANALYZED_BY',a.object_id,'A','signed traction/depletion scan analyzer'
FROM artifacts a WHERE a.path='scripts/analyze_0493x7d_signed_traction_scan.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT m.object_id,'QUALIFIED_BY',a.object_id,'A','x7q production-profile multi-case physical qualification runner'
FROM milestones m JOIN artifacts a ON a.path='scripts/run_0493x7i_q6_g_f_physical_qualification_x7q.sh'
WHERE m.object_id IN ('milestone:0493x7d-v2-signed1','milestone:0493x7o','milestone:0493x7p','milestone:0493x7q');

-- ---------------------------------------------------------------------------
-- Direct parameter/runner-symbol provenance for milestones inserted after the
-- automatic symbol-link inference pass.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:param:q6DensityRelaxationCompressionGateEnable','ASSOCIATED_WITH','milestone:0493x7d-v2','A','parameter introduced by x7d-v2 coherent compression gate');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:param:q6DensityRelaxationCompressionThresholdFill','ASSOCIATED_WITH','milestone:0493x7d-v2','A','positive coherent compression threshold introduced by x7d-v2');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:param:q6DensityRelaxationTractionThresholdFill','ASSOCIATED_WITH','milestone:0493x7d-v2-signed1','A','negative coherent traction/depletion threshold introduced by signed1');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:param:q6DensityRelaxationTractionGain','ASSOCIATED_WITH','milestone:0493x7d-v2-signed1','A','negative coherent branch gain introduced by signed1');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:env:Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE','ASSOCIATED_WITH','milestone:0493x7d-v2','B','runner alias selecting coherent positive gate');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:env:Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES','ASSOCIATED_WITH','milestone:0493x7d-v2','B','runner threshold in particles converted to fill by division by gamma');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:env:Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES','ASSOCIATED_WITH','milestone:0493x7d-v2-signed1','B','runner negative threshold in particles converted to fill by division by gamma');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:env:Q6_GF_DENSITY_TRACTION_GAIN','ASSOCIATED_WITH','milestone:0493x7d-v2-signed1','B','runner alias for signed negative-branch gain');
