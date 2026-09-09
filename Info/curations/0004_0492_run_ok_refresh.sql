-- 0492 historical run_ok refresh / semantic validation milestone.
-- The Git history explicitly exposes one umbrella milestone, 0492.  Internal markers
-- 0492a (resident-mode helper/compatibility alias) and 0492b (injection species checker)
-- remain supporting artifacts rather than standalone canonical milestones.

CREATE TEMP TABLE _cur_0492(
  milestone_id TEXT PRIMARY KEY,
  milestone_key TEXT NOT NULL,
  name TEXT NOT NULL,
  summary TEXT NOT NULL,
  nature TEXT NOT NULL,
  status TEXT NOT NULL,
  source_file TEXT NOT NULL
);

INSERT INTO _cur_0492 VALUES
('0492','history:0492','Refresh et contrat des run_ok',
 'Consolide les runners run_ok autour d''une base commune, d''un preflight homogène et du contrat LiveVis, tout en intégrant la chaîne multi-espèces résidente issue de 0490/0491. Les sous-révisions internes 0492a et 0492b portent respectivement la résolution du mode résident et les contrôles sémantiques des injections multi-espèces.',
 'INFRA','Infrastructure runner historique qualifiée','README_0492_RUN_OK_REFRESH.md');

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
SELECT 'milestone:' || milestone_key,'MILESTONE',milestone_id,'curation:0004_0492'
FROM _cur_0492;

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,
  confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row
)
SELECT
  'milestone:' || milestone_key,milestone_key,milestone_id,milestone_key,
  '0492 : refresh des run_ok et validation sémantique multi-espèces',
  name,summary,nature,'RUN_OK_INFRA',status,
  'A',NULL,NULL,NULL,
  'Curation historique de l''umbrella 0492. Les marqueurs 0492a/0492b restent des sous-révisions techniques et ne sont pas promus comme jalons canoniques autonomes.',
  source_file,NULL
FROM _cur_0492;

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
SELECT 'milestone:' || milestone_key,'MILESTONE_README',source_file,'A',
       'README dédié au refresh 0492 des run_ok.'
FROM _cur_0492;

-- Primary documentary and validation artifacts.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0492','DOCUMENTED_BY',object_id,'A','dedicated 0492 refresh README'
FROM artifacts
WHERE basename='README_0492_RUN_OK_REFRESH.md';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0492','QUALIFIED_BY',object_id,'A','0492 static/preflight checker for the public run_ok suite'
FROM artifacts
WHERE path='scripts/check_run_ok_0492.sh';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0492','IMPLEMENTED_IN',object_id,'A','0492 common run_ok contract and preflight helpers'
FROM artifacts
WHERE path='scripts/src_mpcd_run_ok_common.sh';

-- 0492b is a semantic checker sub-revision, deliberately not a standalone milestone.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0492','QUALIFIED_BY',object_id,'A','0492b semantic validation of injection species state/runtime contracts; supporting sub-revision, not a standalone milestone'
FROM artifacts
WHERE path='scripts/check_injection_species_0492b.py';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0492','QUALIFIED_BY',object_id,'B','0492b injection scenario exercising liquid type 1 into type 2 background'
FROM artifacts
WHERE path='scripts/run_ok_injection_type1_into_type2.sh';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:history:0492','QUALIFIED_BY',object_id,'B','0492b empty-domain injection scenario'
FROM artifacts
WHERE path='scripts/run_ok_injection_type1_into_type2_empty.sh';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:history:0492','BUILDS_ON','milestone:history:0491h-fix1','A','run_ok refresh follows the deep-qualified species-Q6 contract'),
('milestone:history:0492','BUILDS_ON','milestone:history:0490p','A','run_ok species-resident policy reuses the zero-CPU device cell policy finalized in 0490P');

DROP TABLE _cur_0492;
