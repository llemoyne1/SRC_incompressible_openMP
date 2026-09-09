-- 0493 resident multi-species resampling / physics series prior to the later o/w/x cycles.
-- Canonical rows are admitted from three evidence classes: dedicated README/Git labels,
-- explicit implementation comments, and qualification/runtime artifacts. Missing letters are
-- never synthesized; only labels explicitly evidenced below are curated.

CREATE TEMP TABLE _cur_0493(
  milestone_id TEXT PRIMARY KEY,
  milestone_key TEXT NOT NULL,
  name TEXT NOT NULL,
  summary TEXT NOT NULL,
  nature TEXT NOT NULL,
  status TEXT NOT NULL,
  source_file TEXT NOT NULL,
  evidence_type TEXT NOT NULL,
  evidence_confidence TEXT NOT NULL,
  milestone_confidence TEXT NOT NULL
);

INSERT INTO _cur_0493 VALUES
('0493A','history:0493a','Routage universel du resampling multi-espèces résident',
 'Étend la chaîne résidente 0490M/N/P à toutes les familles de frontières supportées, supprime le routage topology-only et garde Q6, Darcy, thermostat et règles de split/merge physiquement inchangés.',
 'INFRA','Jalon historique documenté','README_0493A_UNIVERSAL_SPECIES_RESIDENT.md','MILESTONE_README','A','A'),
('0493B','history:0493b','Resampling CUDA résident activable par espèce',
 'Ajoute une politique de mutation par espèce tout en conservant toutes les espèces dans SRC, Q6, Darcy, frontières et dépôts barycentriques; la production reste zéro-CPU pour les décisions cellule/espèce.',
 'CODE','Jalon historique documenté','README_0493B_UNIVERSAL_RESIDENT_PER_SPECIES.md','MILESTONE_README','A','A'),
('0493C','history:0493c','Qualification du resampling multi-espèces résident',
 'Qualifie le chemin résident sur une matrice périodique, frontières segmentées et Darcy/chi, avec activité effective, intégrité du pool, conservation de masse par espèce et absence de mutation des espèces désactivées.',
 'QUALIFICATION','Qualification historique','README_0493C_RESIDENT_QUALIFICATION.md','MILESTONE_README','A','A'),
('0493C-fix3','history:0493c-fix3','Alignement du population guard medium sur gamma',
 'Corrige la qualification medium de 0493C afin que les seuils de population restent cohérents avec gamma et ne créent pas un faux régime de garde.',
 'FIX','Correctif historique attesté par Git','git:1a705cb','GIT_COMMIT','A','A'),
('0493D','history:0493d','Sélection parallèle déterministe des transferts résidents',
 'Remplace la recherche sérielle plan×particules par une sélection parallèle par groupes indépendants donneur/type, tout en reconstruisant l''ordre global historique des opérations.',
 'PERF','Jalon d''optimisation attesté par le code','src/cuda_species_resampling_fast_path_0490m.cu','IMPLEMENTATION_SOURCE','A','B'),
('0493D-fix1','history:0493d-fix1','Rejeu déterministe du state-update après sélection parallèle',
 'Conserve la sélection parallèle de 0493D mais rejoue mutations et réductions diagnostiques dans l''ordre historique pour préserver exactement l''arithmétique et la déterminisme du chemin 0490M.',
 'FIX','Correctif historique attesté par Git','git:95f408a','GIT_COMMIT','A','A'),
('0493E','history:0493e','Qualification physique mono-espèce du resampling',
 'Teste le resampling résident mono-espèce sur un état contrôlé avec conservation masse/impulsion/énergie, activité split/merge et invariants de pool.',
 'QUALIFICATION','Qualification physique historique','README_0493E_MONOSPECIES_RESAMPLING_PHYSICS.md','MILESTONE_README','A','A'),
('0493F','history:0493f','Qualification physique à deux espèces du resampling',
 'Étend la qualification physique à deux espèces et aux activations sélectives, afin de contrôler séparément conservation globale et conservation par espèce pendant les mutations résidentes.',
 'QUALIFICATION','Qualification physique historique','README_0493F_TWO_SPECIES_RESAMPLING_PHYSICS.md','MILESTONE_README','A','A'),
('0493F-fix2','history:0493f-fix2','Cas deux-espèces physiquement neutre',
 'Remplace le checkerboard initial par un état où les champs de masse, impulsion et énergie par espèce sont uniformes malgré les variations de population, afin que le smoke mesure la mutation numérique sans forçage physique parasite.',
 'FIX','Correctif de qualification historique','README_0493F_FIX2_PHYSICALLY_NEUTRAL.md','MILESTONE_README','A','A'),
('0493G','history:0493g','Restauration locale des moments par espèce',
 'Restaure indépendamment les moments thermodynamiques de chaque espèce mutable autour de son propre barycentre; évite l''échange artificiel de quantité de mouvement et d''énergie créé par la restauration sur barycentre de mélange.',
 'CODE','Correction physique historique','README_0493G_SPECIES_LOCAL_MOMENT_RESTORE.md','MILESTONE_README','A','A'),
('0493H','history:0493h','Diagnostic physique par onde de cisaillement périodique',
 'Compare SRC et SRC+resampling sur une onde de cisaillement périodique. Le jalon vérifie décroissance/viscosité et intégrité mais met aussi en évidence les dérives de masse, impulsion et énergie du chemin resampling avant les fermetures I/J.',
 'QUALIFICATION','Diagnostic physique historique','README_0493H_PERIODIC_SHEAR_WAVE_PHYSICS.md','MILESTONE_README','A','A'),
('0493I','history:0493i','Fermeture conservative mono-espèce sur le chemin résident',
 'Étend la balance conservative masse/impulsion de 0490I au cas d''une seule espèce enregistrée; supprime la dérive d''impulsion introduite par l''ancien branchement mass-only lorsque speciesCount=1.',
 'FIX','Correctif physique attesté par le code','src/cuda_species_mass_closure_0490i.cu','IMPLEMENTATION_SOURCE','A','B'),
('0493J','history:0493j','Fermeture conservative de l''énergie cinétique par espèce',
 'Ajoute à la fermeture résidente la conservation de l''énergie cinétique relative par espèce, avec diagnostics de faisabilité et résidu; cette fermeture devient un invariant contrôlé dans les qualifications de transport ultérieures.',
 'CODE','Jalon historique documenté','README_0493J_SPECIES_KINETIC_CLOSURE.md','MILESTONE_README','A','A');

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
SELECT 'milestone:'||milestone_key,'MILESTONE',milestone_id,'curation:0005_0493' FROM _cur_0493;

INSERT OR REPLACE INTO milestones(
 object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
 confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row)
SELECT 'milestone:'||milestone_key,milestone_key,milestone_id,milestone_key,
 '0493 : resampling multi-espèces résident — universalisation, performance et qualification physique',
 name,summary,nature,'MULTISPECIES_RESAMPLING',status,milestone_confidence,NULL,NULL,NULL,
 CASE WHEN evidence_type IN ('IMPLEMENTATION_SOURCE','GIT_COMMIT')
      THEN 'Jalon sans README dédié survivant; conservé car explicitement attesté par le code et/ou le graphe Git. Aucun jalon manquant n''est synthétisé.'
      ELSE 'Jalon historique 0493 documenté par README et/ou qualification dédiée.' END,
 source_file,NULL
FROM _cur_0493;

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:'||milestone_key,evidence_type,source_file,evidence_confidence,
 CASE evidence_type
  WHEN 'MILESTONE_README' THEN 'README dédié du jalon 0493.'
  WHEN 'GIT_COMMIT' THEN 'Commit Git explicitement nommé pour ce correctif 0493.'
  WHEN 'IMPLEMENTATION_SOURCE' THEN 'Source conservant explicitement la sémantique/étiquette 0493 dans le chemin de production.'
  ELSE 'Preuve primaire 0493.' END
FROM _cur_0493;

-- Link primary repository artifacts when present.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:'||c.milestone_key,
 CASE c.evidence_type WHEN 'MILESTONE_README' THEN 'DOCUMENTED_BY' WHEN 'IMPLEMENTATION_SOURCE' THEN 'IMPLEMENTED_IN' ELSE 'EVIDENCED_BY' END,
 a.object_id,c.evidence_confidence,'0493 curated primary evidence'
FROM _cur_0493 c JOIN artifacts a
 ON lower(a.path)=lower(c.source_file) OR lower(a.basename)=lower(c.source_file);

-- Qualification/implementation artifacts that make the functional role directly inspectable.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493a','QUALIFIED_BY',object_id,'A','0493A universal resident routing checker'
FROM artifacts WHERE path='scripts/check_0493a_universal_species_resident.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493b','QUALIFIED_BY',object_id,'A','0493B universal per-species matrix/checker'
FROM artifacts WHERE path IN ('scripts/check_0493b_universal_species_resampling.sh','scripts/run_0493b_universal_species_resampling_matrix.sh');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493c','QUALIFIED_BY',object_id,'A','0493C resident qualification suite'
FROM artifacts WHERE path IN ('scripts/run_0493c_medium_qualification.sh','scripts/run_0493c_species_resampling_qualification.sh','scripts/analyze_0493c_resident_qualification.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493e','QUALIFIED_BY',object_id,'A','0493E mono-species physics smoke/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493e_monospecies_resampling_physics_smoke.sh','scripts/analyze_0493e_monospecies_resampling_physics.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493f','QUALIFIED_BY',object_id,'A','0493F two-species physics smoke/analyzer'
FROM artifacts WHERE path IN ('scripts/run_0493f_two_species_resampling_physics_smoke.sh','scripts/analyze_0493f_two_species_resampling_physics.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493g','QUALIFIED_BY',object_id,'A','0493G two-species local-moment restore qualification'
FROM artifacts WHERE path IN ('scripts/run_0493g_two_species_moment_restore.sh','scripts/analyze_0493g_two_species_moment_restore.py');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0493h','QUALIFIED_BY',object_id,'A','0493H periodic shear-wave physical diagnostic'
FROM artifacts WHERE path IN ('scripts/run_0493h_periodic_shear_wave_physics.sh','scripts/analyze_0493h_periodic_shear_wave_physics.py');

-- Historical dependency chain.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:history:0493a','BUILDS_ON','milestone:history:0492','A','universal resident routing follows the normalized run_ok/resident contract'),
('milestone:history:0493a','BUILDS_ON','milestone:history:0490p','A','reuses the finalized zero-CPU resident species chain'),
('milestone:history:0493b','EXTENDS','milestone:history:0493a','A','adds per-species mutation policy to universal resident routing'),
('milestone:history:0493c','QUALIFIES','milestone:history:0493b','A','resident boundary/Darcy qualification'),
('milestone:history:0493c-fix3','FIXES','milestone:history:0493c','A','gamma-consistent medium population guard'),
('milestone:history:0493d','OPTIMIZES','milestone:history:0493b','A','parallel deterministic transfer selection'),
('milestone:history:0493d-fix1','FIXES','milestone:history:0493d','A','preserves historical arithmetic/order after parallel selection'),
('milestone:history:0493e','QUALIFIES','milestone:history:0493d-fix1','A','mono-species physical qualification'),
('milestone:history:0493f','QUALIFIES','milestone:history:0493d-fix1','A','two-species physical qualification'),
('milestone:history:0493f-fix2','FIXES','milestone:history:0493f','A','physically neutral two-species reference state'),
('milestone:history:0493g','FIXES','milestone:history:0493f-fix2','A','per-species local moment restoration removes mixture-barycentre exchange'),
('milestone:history:0493h','QUALIFIES','milestone:history:0493g','A','shear-wave diagnostic exposes remaining global closure drift'),
('milestone:history:0493i','FIXES','milestone:history:0493h','B','mono-species conservative mass/momentum branch removes one identified drift source'),
('milestone:history:0493j','EXTENDS','milestone:history:0493i','A','adds species kinetic-energy conservative closure and residual/f feasibility diagnostics');

DROP TABLE _cur_0493;
