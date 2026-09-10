-- V4.23: 0493x9d-fix1-neumann resident-workspace optimization of the post-x14av Neumann path.
-- Documentary curation only. Physics is explicitly marked x9c_unchanged by the runtime source.
-- The short B/O/B timing triplet is not sufficient to claim a qualified speedup.

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x9d-fix1-neumann','MILESTONE','x9d-fix1-neumann','curation:0024_0493x9d_fix1_neumann_resident_opt');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x9d-fix1-neumann',
  '0493x9d-fix1-neumann','x9d-fix1-neumann','0493x9d-fix1-neumann',
  'post-x14av : optimisation Neumann multiphasique',
  'Workspace résident et comptages exacts pour la continuation Neumann',
  'Optimise l''implémentation x9c-outlet/x9b-neumann sans changer la physique: compteurs et tail-pool persistants, métadonnées espèce mises à jour seulement sur changement, synchronisation pré-candidats supprimée, comptages candidats/inactifs exacts et géométrie de lancement ajustée au compte exact.',
  'PERF','OPEN_BOUNDARY_MULTIPHASE',
  'Optimisation structurelle attestée et smoke physique court cohérent avec x9c-outlet; gain de performance NON QUALIFIE car le triplet baseline/optimisé/baseline présente une dispersion murale supérieure à l''effet mesuré.',
  'A','2026-09-09',NULL,NULL,
  'Le marqueur runtime est explicite: mode=resident_workspace_exact_counts, physics=x9c_unchanged, counters=persistent, tailPool=persistent_exact, speciesMetadata=change_only, preCandidateSync=elided, candidateCount=host_exact, inactiveCount=host_exact, launchGeometry=exact, candidateBuffer=preserved, fallback=legacy_exact. Les trois runs de 250 pas donnent 92.53 s (baseline x9c), 61.10 s (x9d-fix1) et 49.73 s (baseline x9c répétée): cette dispersion interdit de convertir le premier ratio en qualification de vitesse.',
  'Info/inputs/historical/0493x9d_fix1_neumann_resident_opt_runtime_250steps_20260909.txt',NULL
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes) VALUES(
  'milestone:0493x9d-fix1-neumann','RUNTIME_MARKER',
  'Info/inputs/historical/0493x9d_fix1_neumann_resident_opt_runtime_250steps_20260909.txt','A',
  'Runtime marker explicitly states physics=x9c_unchanged and enumerates the persistent-workspace/exact-count implementation changes.'
);
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes) VALUES(
  'milestone:0493x9d-fix1-neumann','PHYSICS_NONREGRESSION',
  'Info/inputs/historical/0493x9d_fix1_neumann_resident_opt_runtime_250steps_20260909.txt','A',
  '250-step x9d-fix1 run remains close to the two x9c baselines: final Nliq=8578 versus 8542/8577 and x99=0.308004 versus 0.309473/0.311155; no independent physical qualification is inferred.'
);
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes) VALUES(
  'milestone:0493x9d-fix1-neumann','PERFORMANCE_EVIDENCE',
  'Info/inputs/historical/0493x9d_fix1_neumann_resident_opt_runtime_250steps_20260909.txt','A',
  'Wall times baseline/optimized/baseline are 92.53/61.10/49.73 s. Because the repeated baseline is faster than the optimized run, this evidence supports implementation testing but not a qualified speedup.'
);
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes) VALUES(
  'milestone:0493x9d-fix1-neumann','PROVENANCE_ARCHIVE',
  'Info/inputs/historical/0493x9d_fix1_neumann_resident_opt_original_sources.zip','A',
  'Archive preserves the supplied runtime transcript byte-for-byte with SHA-256 manifest.'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x9d-fix1-neumann','BUILDS_ON','milestone:0493x9c-outlet','A','runtime explicitly keeps x9c phase-support continuation active');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x9d-fix1-neumann','OPTIMIZES','milestone:0493x9c-outlet','A','resident workspace/exact counts optimize implementation while marker states physics=x9c_unchanged');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x9d-fix1-neumann','REFERENCES','milestone:0493x14av','A','tested in the x14av air-assisted atomizer 200x400 demonstration');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9d-fix1-neumann','DOCUMENTED_BY',object_id,'A','V4.23 exact runtime transcript'
FROM artifacts WHERE path='Info/inputs/historical/0493x9d_fix1_neumann_resident_opt_runtime_250steps_20260909.txt';

-- No git_milestone_candidates reassignment: historical x9d is already the capillary milestone.
-- The explicit -fix1-neumann suffix is retained to avoid collision and because it is attested by the runtime marker.
