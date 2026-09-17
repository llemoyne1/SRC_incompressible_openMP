-- V4.38: x19b-fix2 every-step wall torque + bulk SRC angular-momentum audit
-- (2026-09-17). Diagnostic-only patch; no change to collision physics.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET notes = COALESCE(notes,'') ||
  ' x19b-fix1 short restart separated normal/tangential wall torque. On additional steps 209..2999: total Tin=-25.2921586, Tout=14.8634893; normal Tin=4.12830613, Tout=0.446839249; tangential Tin=-29.4204648, Tout=14.4166501, tangential closure=0.509979. The normal contamination is secondary (|normal/tangential|=0.140321 inner and 0.0309947 outer), while block SEM remains very large (13.8189 inner, 30.5184 outer). x19b-fix2 therefore samples wall torque every solver step and measures the exact real-fluid angular-momentum increment caused by the bulk SRC rotation kernel.'
WHERE object_id='milestone:0493x19b';

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x19b-fix2','MILESTONE','x19b-fix2','curation:0038_0493x19b_fix2_angular_balance');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x19b-fix2','0493x19b-fix2','x19b-fix2','0493x19b-fix2','solides mobiles / FSI',
  'Bilan angulaire paroi/SRC du Couette cylindrique x19b',
  'Diagnostic court sans modification physique: force SUMMARY_EVERY=1 pour conserver tous les impacts x17 et ajoute une réduction CUDA du moment angulaire réel du fluide juste avant/après la rotation SRC. Le bilan compare la réaction de paroi au delta-L SRC et laisse explicitement Q6/thermostat comme opérateurs aval non instrumentés.',
  'QUALIFICATION','FSI','PENDING_LOCAL_CUDA_BUILD_AND_SHORT_RESTART_DIAGNOSTIC','A','2026-09-17',NULL,NULL,
  'Runner prévu sur bounceback seulement, restart d un état Couette déjà établi, 1500 pas supplémentaires par défaut. LiveVis est conservé mais décimé à every=10 car il s agit d un diagnostic court visant à limiter le coût. Aucun specular n est relancé.',
  'Info/curations/0038_0493x19b_fix2_angular_balance.sql',NULL
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x19b-fix2','BUILDS_ON','milestone:0493x19b-fix1','A','Every-step wall torque and direct bulk-SRC angular-momentum diagnostic; physical operators unchanged.');
