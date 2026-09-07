-- Current 2026-09-07 segmented x/y open-boundary milestone.
-- The key is namespaced because bare numeric labels such as 0414 are historically reused.

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:20260907-0414-segmented-xy','MILESTONE','0414','migration:0001');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,notes,source_file
) VALUES(
  'milestone:20260907-0414-segmented-xy',
  '20260907-0414-segmented-xy','0414','20260907-0414-segmented-xy',
  'Post-x14 / conditions limites ouvertes',
  'Extension quadriface des open boundaries segmentées',
  'Généralise les entrées/sorties segmentées aux axes x et y sur le chemin CUDA résident; crossing multi-axes chronologique, x8r quadriface, x8t généralisé, x8s séparable 1-D/2-D, gardes de coins/réservoirs et diagnostic low-face corrigé.',
  'CODE','OPEN_BOUNDARY','QUALIFIED','A','2026-09-07',
  'Qualification Q1-Q7 et ablation x8s 2-D consolidées.',
  'SRC_GPU_SURF_0414_final_segmented_xy_cuda_resident.patch'
);

-- Runner placeholder when rebuilding from a snapshot that predates the runner.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('artifact:scripts/run_0414_segmented_xy_neumann_qualification.sh','ARTIFACT','scripts/run_0414_segmented_xy_neumann_qualification.sh','migration:0001');
INSERT OR IGNORE INTO artifacts(object_id,path,basename,kind,language,status,milestone_hint,description,sha256)
VALUES(
  'artifact:scripts/run_0414_segmented_xy_neumann_qualification.sh',
  'scripts/run_0414_segmented_xy_neumann_qualification.sh','run_0414_segmented_xy_neumann_qualification.sh',
  'RUNNER','bash','qualified/current-worktree','','Q1-Q7 segmented x/y Neumann qualification runner',''
);
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES(
  'artifact:scripts/run_0414_segmented_xy_neumann_qualification.sh','QUALIFIES',
  'milestone:20260907-0414-segmented-xy','A','0414 consolidated qualification runner'
);

-- Exact links to the x8 concepts generalized by the current milestone.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:20260907-0414-segmented-xy','EXTENDS',object_id,'A','0414 qualified extension'
FROM milestones WHERE milestone_id IN ('x8k','x8r','x8s','x8t');

-- Source files modified by 0414.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:20260907-0414-segmented-xy','MODIFIES',object_id,'A','0414 final patch'
FROM artifacts
WHERE path IN (
  'include/simulation_params.h','src/params_io_base.cpp',
  'src/cuda_classic_src_io_resident_0263.cu','src/cuda_q6_resident_0400.cu'
);

-- Runtime x8s ablation switch introduced after the 04/09 inventory snapshot.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('symbol:param:q6PressureOutletDeflationEnable','SYMBOL','q6PressureOutletDeflationEnable','migration:0001');
INSERT OR IGNORE INTO symbols(
  object_id,namespace,canonical_name,category,status,expected_type,default_value,constraints_text,effect_role,remarks,source_inventory
) VALUES(
  'symbol:param:q6PressureOutletDeflationEnable','PARAM','q6PressureOutletDeflationEnable',
  'Q6-G-F — pressure outlet conditioning','ajout 0414d; actif par défaut','booléen','true','true/false',
  'Active/désactive uniquement la déflation exacte x8s des modes lents des pressure outlets compatibles, sans changer x8r/x8t.',
  'Switch d’ablation runtime; géométrie partielle non séparable désactive automatiquement la déflation spécialisée.',
  'curated_0414'
);
INSERT OR IGNORE INTO symbol_names(symbol_object_id,name,name_kind,is_canonical,source_file,source_row)
VALUES('symbol:param:q6PressureOutletDeflationEnable','q6PressureOutletDeflationEnable','PARAM_KEY',1,'SRC_GPU_SURF_0414_final_segmented_xy_cuda_resident.patch',0);
INSERT OR IGNORE INTO symbol_names(symbol_object_id,name,name_kind,is_canonical,source_file,source_row)
VALUES('symbol:param:q6PressureOutletDeflationEnable','pressureOutletDeflationEnable','PARAM_ALIAS',0,'SRC_GPU_SURF_0414_final_segmented_xy_cuda_resident.patch',0);
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:20260907-0414-segmented-xy','INTRODUCES_OR_EXTENDS','symbol:param:q6PressureOutletDeflationEnable','A','0414d');

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('symbol:env:Q6_PRESSURE_OUTLET_DEFLATION_ENABLE','SYMBOL','Q6_PRESSURE_OUTLET_DEFLATION_ENABLE','migration:0001');
INSERT OR IGNORE INTO symbols(
  object_id,namespace,canonical_name,category,status,expected_type,default_value,constraints_text,effect_role,remarks,source_inventory
) VALUES(
  'symbol:env:Q6_PRESSURE_OUTLET_DEFLATION_ENABLE','ENV','Q6_PRESSURE_OUTLET_DEFLATION_ENABLE',
  'Runner 0414 / x8s ablation','ajout 0414d','booléen','true','true/false',
  'Runner alias writing q6PressureOutletDeflationEnable.','Qualification conditioning-only ablation.','curated_0414'
);
INSERT OR IGNORE INTO symbol_names(symbol_object_id,name,name_kind,is_canonical,source_file,source_row)
VALUES(
  'symbol:env:Q6_PRESSURE_OUTLET_DEFLATION_ENABLE','Q6_PRESSURE_OUTLET_DEFLATION_ENABLE','ENV_FLAG',1,
  'scripts/run_0414_segmented_xy_neumann_qualification.sh',0
);
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('symbol:env:Q6_PRESSURE_OUTLET_DEFLATION_ENABLE','SETS_PARAMETER','symbol:param:q6PressureOutletDeflationEnable','A','runner 0414d');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES(
  'symbol:env:Q6_PRESSURE_OUTLET_DEFLATION_ENABLE','DEFINED_OR_USED_IN',
  'artifact:scripts/run_0414_segmented_xy_neumann_qualification.sh','A','runner 0414d'
);
