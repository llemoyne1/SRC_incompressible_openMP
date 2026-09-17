-- V4.37: x19b-fix1 split normal/tangential wall-reaction torque diagnostic
-- (2026-09-17). Diagnostic-only patch; no change to collision physics.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET notes = COALESCE(notes,'') ||
  ' First x19b late-window run: bounceback profile relative RMSE=0.0890368, profile R2=0.889773, shape R2=0.901643, mean |ur|/Ui=0.0600813. Total wall-reaction torques were Tin=-2.09049837 and Tout=-31.8989012; paired subtraction from specular still gave same-sign differential torques (dTin=-3.37097707, dTout=-34.6532198, closure=1.09727746). Therefore x19b-fix1 adds diagnostic decomposition of each impact reaction into local facet-normal and local tangential torque before any interpretation as bulk angular-momentum failure.'
WHERE object_id='milestone:0493x19b';

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x19b-fix1','MILESTONE','x19b-fix1','curation:0037_0493x19b_fix1_torque_split');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x19b-fix1','0493x19b-fix1','x19b-fix1','0493x19b-fix1','solides mobiles / FSI',
  'Décomposition couple normal/tangentiel du Couette cylindrique x19b',
  'Ajoute quatre accumulateurs diagnostiques séparant, pour chaque impact x17 de l anneau prescrit, le couple de la réaction parallèle à la normale de facette et celui de la réaction tangentielle complémentaire. Aucun changement de trajectoire, bounceback, Q6, thermostat ou géométrie.',
  'QUALIFICATION','FSI','PENDING_LOCAL_CUDA_BUILD_AND_SHORT_RESTART_DIAGNOSTIC','A','2026-09-17',NULL,NULL,
  'Qualification courte prévue uniquement sur bounceback: restart du dernier dump x19b établi et 3000 pas supplémentaires. Le but est de déterminer si le mauvais bilan de couple total provient d une contamination normale liée à la facettisation ou persiste dans le couple tangentiel lui-même.',
  'Info/curations/0037_0493x19b_fix1_torque_split.sql',NULL
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x19b-fix1','BUILDS_ON','milestone:0493x19b','A','Diagnostic-only refinement of x19b wall torque; physics unchanged.');
