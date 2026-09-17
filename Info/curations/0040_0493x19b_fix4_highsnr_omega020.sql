-- V4.40: x19b-fix4 high-SNR prescribed annular Couette qualification
-- (2026-09-17). Run/analyzer layer only; no C++/CUDA physics change.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET notes = COALESCE(notes,'') ||
  ' x19b-fix3 closed the complete operator angular-momentum audit at telescoping relRMS=1.804e-16 and independently reproduced the x17 wall torque at relRMS=4.022e-14. On steps 20..400 the antisymmetric tangential torque estimator was T_C=8.97153647 with sample SEM 21.553472, while the common half-sum was 1.57951063 with sample SEM 20.9297974; the remaining limitation is therefore torque SNR rather than a hidden angular-momentum channel. A matched four-seed src-q6 TG calibration (gamma=12, dt=0.006, kBT=0.05, alpha=pi/2, h=1/256, mode 2,2, lambda=0.25) gives nu=2.3313138152e-4, std=1.0569841665e-5, SEM=5.2849208326e-6, CV=0.045339; all four fits PASS with R2 about 0.9981. x19b-fix4 therefore raises prescribed Omega from 0.05 to 0.20 (Ui=0.04) and measures T_C=(T_outer,t-T_inner,t)/2 against the matched TG torque reference.'
WHERE object_id='milestone:0493x19b';

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x19b-fix4','MILESTONE','x19b-fix4','curation:0040_0493x19b_fix4_highsnr_omega020');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x19b-fix4','0493x19b-fix4','x19b-fix4','0493x19b-fix4','solides mobiles / FSI',
  'Couette cylindrique x19b haute SNR à Omega=0.20',
  'Qualification de couple à haute SNR sans modification de la physique. Le runner repart d un état bounceback établi à Omega=0.05, ajoute uniquement l incrément de vitesse moyenne Couette exact jusqu à Omega=0.20 en conservant les vitesses thermiques particulières, puis exécute 5000 pas avec diagnostics de couple à chaque pas. L analyseur utilise le couple tangentiel antisymétrique T_C=(T_outer-T_inner)/2, le demi-somme comme contrôle de stationnarité, les rayons x17 effectifs et la viscosité TG appariée.',
  'QUALIFICATION','FSI','PENDING_LOCAL_HIGH_SNR_RUN','A','2026-09-17',NULL,NULL,
  'Reference TG: nu=2.3313138152e-4, SEM=5.2849208326e-6, n=4. Target Omega=0.20, nominal Ui=0.04. Nominal expected torque magnitude about 27.37 before replacing nominal radii/density by measured values.',
  'Info/curations/0040_0493x19b_fix4_highsnr_omega020.sql',NULL
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x19b-fix4','BUILDS_ON','milestone:0493x19b-fix3','A','High-SNR torque qualification after the complete operator audit closed and showed no unresolved angular-momentum channel.');
