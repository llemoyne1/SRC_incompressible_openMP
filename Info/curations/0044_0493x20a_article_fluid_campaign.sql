-- V4.44: x20a JCP article bulk-fluid characterization master campaign
-- (2026-09-18). Runner/analysis orchestration only; no solver physics change.
PRAGMA foreign_keys=ON;

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x20a','MILESTONE','x20a article fluid campaign','curation:0044_0493x20a_article_fluid_campaign');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x20a','0493x20a','x20a','0493x20a','bulk fluid characterization',
  'Campagne JCP de caractérisation SRC / Q6-G-F',
  'Runner maître unique réutilisant le calibrateur standalone 0493w1 pour une matrice appariée SRC/Q6-G-F. Douze configurations physiques uniques autour du point nominal gamma=8, alpha_SRC=120 deg, lambdaMean/h=0.72; trois réalisations Taylor-Green et MSD par modèle, trois répétitions acoustiques SRC, soit 180 appels solveur. Les points croisés/collapse sont volontairement différés après examen des tendances.',
  'QUALIFICATION','BULK_FLUID','READY_FOR_LOCAL_CAMPAIGN','A','2026-09-18',NULL,NULL,
  'No solver physics modification. Campaign-level restart uses existing .complete realization markers and SKIP_EXISTING=1. LiveVis defaults off because all calibrations are short and small-grid; it remains explicitly available without modifying ./livevis_control.kv.',
  'Info/curations/0044_0493x20a_article_fluid_campaign.sql',NULL
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x20a','RUNNER',
  'scripts/run_0493x20a_article_fluid_campaign.sh','A',
  'Single campaign runner; writes matrix, manifest, status, aggregated transport table, realization table and paired SRC/Q6-G-F transport ratios.'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES(
  'milestone:0493x20a','BUILDS_ON','milestone:0493x13h','A',
  'Campaign point selection and nominal bulk-fluid parameters build on the x13 constitutive/transport qualification family while using the canonical 0493w1 standalone Taylor-Green/MSD/sound metrology.'
);
