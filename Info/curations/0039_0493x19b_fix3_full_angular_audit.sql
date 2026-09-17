-- V4.39: x19b-fix3 complete operator-by-operator angular-momentum audit
-- (2026-09-17). Diagnostic-only patch; no physical operator is modified.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET notes = COALESCE(notes,'') ||
  ' x19b-fix2 short restart (steps 100..1500, 1401 rows) measured wall reaction total=-9.3164897, tangential=-11.6141197 (inner=-10.99058 outer=-0.623539747), normal=2.29763003, while bulk SRC delta-L/dt=0.950671599. The partial fluid-wall+SRC residual is 10.2671613 (normalized 1.10204), so SRC alone does not account for the angular-momentum budget. x19b-fix3 replaces sequential hypothesis testing by a complete read-only stage audit of mass, linear momentum, angular momentum, kinetic energy, polar mass moment, radial momentum and tangential momentum across every top-level mutating operator, plus an independent x17 wall-reaction cross-check.'
WHERE object_id='milestone:0493x19b';

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x19b-fix3','MILESTONE','x19b-fix3','curation:0039_0493x19b_fix3_full_angular_audit');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x19b-fix3','0493x19b-fix3','x19b-fix3','0493x19b-fix3','solides mobiles / FSI',
  'Audit angulaire complet par opérateur du Couette cylindrique x19b',
  'Instrumentation diagnostique complète et opt-in. Mesure le même état fluide global avant/après prestream, frontière x17, streaming, frontières externes, immersed, diagnostic de pénétration, SRC, Q6, capacité fermée, thermostat, keep-mean-flow, Darcy, dynamique solide et gardes de resampling. Chaque snapshot contient masse, Px, Py, Lz, énergie cinétique, moment polaire, moment radial et tangentiel. Le runner court écrit aussi rho/ux/uy sur une grille 48x48 à chaque pas pour une inspection indépendante de dumps réduits consécutifs.',
  'QUALIFICATION','FSI','PENDING_LOCAL_CUDA_BUILD_AND_SHORT_RESTART_DIAGNOSTIC','A','2026-09-17',NULL,NULL,
  'Aucune physique modifiée. Runner bounceback seul, restart d un état Couette établi, 400 pas supplémentaires par défaut. L audit est activé seulement par MPCD_X19B_FIX3_FULL_ANGULAR_AUDIT=1.',
  'Info/curations/0039_0493x19b_fix3_full_angular_audit.sql',NULL
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x19b-fix3','BUILDS_ON','milestone:0493x19b-fix2','A','Complete stage-resolved angular-momentum audit after x19b-fix2 showed that bulk SRC alone does not close the wall torque budget.');
