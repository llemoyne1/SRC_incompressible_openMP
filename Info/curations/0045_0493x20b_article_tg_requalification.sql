-- V4.45: x20b long TG requalification for the JCP bulk-fluid campaign
-- (2026-09-19). Runner/analysis orchestration only; no solver physics change.
PRAGMA foreign_keys=ON;

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x20b','MILESTONE','x20b long TG requalification','curation:0045_0493x20b_article_tg_requalification');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x20b','0493x20b','x20b','0493x20b','bulk fluid characterization',
  'Requalification longue Taylor-Green SRC / Q6-G-F pour article JCP',
  'Reprise TG-only des douze points x20a sur domaine 128x128, durees physiques adaptees au temps de decroissance mesure lors du pilote, six seeds communes par modele et point. Les MSD et acoustiques x20a ne sont pas rejoues. Les ratios de viscosite produits par le runner sont status-aware et incluent des ratios apparies seed par seed.',
  'QUALIFICATION','BULK_FLUID','READY_FOR_LOCAL_CAMPAIGN','A','2026-09-19',NULL,NULL,
  'No solver/source modification. Uses canonical standalone 0493w1 calibrator with CALIBRATION_EXPERIMENTS=tg only. Campaign restart uses .complete markers/SKIP_EXISTING. Q6-G-F production closure contract unchanged from x20a.',
  'Info/curations/0045_0493x20b_article_tg_requalification.sql',NULL
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x20b','RUNNER',
  'scripts/run_0493x20b_article_tg_requalification.sh','A',
  'Long TG-only article requalification runner; 12 paired physical points, 6 common seeds, adaptive durations, 128x128 domain, status-aware aggregate and paired SRC/Q6-G-F ratios.'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES(
  'milestone:0493x20b','BUILDS_ON','milestone:0493x20a','A',
  'x20b requalifies the Taylor-Green viscosity measurements whose x20a pilot showed REVIEW/INVALID ensemble quality or incomplete gamma=4 SRC coverage, while retaining the already qualified x20a MSD and acoustic measurements.'
);
