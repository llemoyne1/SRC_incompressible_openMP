-- V4.47: documentary repair of the already-attested 0493x19d source milestone.
-- Source-only curation. No solver, runner, physical parameter or generated file is modified here.
-- V4.43 documented x19d by attaching its PERFORMANCE_EVIDENCE to x19b-fix3,
-- but did not create milestone:0493x19d itself.
PRAGMA foreign_keys=ON;

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES(
  'milestone:0493x19d','MILESTONE','x19d hot-path diagnostic cleanup',
  'curation:0047_0493x19d_milestone_repair'
);

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x19d','0493x19d','x19d','0493x19d','runtime / diagnostics',
  'Nettoyage du hot path des diagnostics désactivés',
  'Optimisation performance-only du timestep générique: le diagnostic angulaire complet x19b-fix3 devient sans allocation lorsqu il est désactivé, et les profileurs CUDA résidents retournent avant de construire/copier leur état diagnostique lorsque le profiling est OFF. Le comportement des diagnostics explicitement activés et les opérateurs physiques/FSI restent inchangés.',
  'OPTIMIZATION','CORE','INTEGRATED_SOURCE_NO_TIMING_CLAIM','A','2026-09-18',NULL,NULL,
  'Le patch primaire x19d et le snapshot du dépôt du 2026-09-20 contiennent exactement le même src/src_mpcd_base.cpp (SHA256 4e3b345f437d010f8296ccea569480bb84aefadb31e6fb28b0ef44941660f4d1), la même curation V4.43 et la même note V4.43. La vérification V4.43 est statique/syntaxique; aucun facteur d accélération CUDA n est revendiqué faute de benchmark dédié. L audit de frontière confirmé par le snapshot et par la recherche indépendante du dépôt ne trouve aucun patch x19 postérieur à x19d: la séquence passe ensuite à x20a.',
  'Info/curations/0047_0493x19d_milestone_repair.sql',NULL
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x19d','PERFORMANCE_EVIDENCE',
  'Info/docs/CURATION_0493X19D_HOTPATH_DIAGNOSTIC_CLEANUP_V4_43.md','A',
  'Source primaire V4.43: nettoyage du hot path sans modification de physique; vérification syntaxique et audit statique; benchmark CUDA quantitatif explicitement non revendiqué.'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x19d','CURATION_AUDIT',
  'Info/docs/CURATION_0493X19D_MILESTONE_REPAIR_V4_47.md','A',
  'Réconciliation du patch x19d avec le snapshot 2026-09-20 et réparation de son absence comme jalon autonome dans les vues générées.'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT
  'milestone:0493x19d','OPTIMIZES','milestone:0493x19b-fix3','A',
  'x19d rend allocation-free le chemin désactivé du diagnostic angulaire complet x19b-fix3; son second volet optimise aussi les profileurs CUDA résidents génériques.'
WHERE EXISTS(SELECT 1 FROM objects WHERE object_id='milestone:0493x19b-fix3');
