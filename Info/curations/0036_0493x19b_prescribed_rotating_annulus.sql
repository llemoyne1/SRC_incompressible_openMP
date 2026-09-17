-- V4.36: x19b prescribed rotating inner cylinder / concentric annulus
-- (2026-09-17).  Status remains pending local CUDA build and qualification.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET notes = COALESCE(notes,'') ||
  ' Late-window x19a result reported on 2026-09-16 over 11 dumps, steps 5000..15000: bounceback relative RMSE=0.0379074 and shape R2=0.984009; specular relative RMSE=0.598073. This is accepted as the planar tangential-transfer gate for opening the curved-wall x19b qualification, not as a general curved-wall/torque qualification.'
WHERE object_id='milestone:0493x19a';

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x19b','MILESTONE','x19b','curation:0036_0493x19b_prescribed_rotating_annulus');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x19b','0493x19b','x19b','0493x19b','solides mobiles / FSI',
  'Couette cylindrique avec cylindre intérieur tournant prescrit',
  'Ajoute à la frontière lagrangienne x17 une cinématique matérielle tangentielle prescrite pour la branche intérieure d’un anneau concentrique. La géométrie reste stationnaire; le cylindre intérieur porte u_w=Omega ez x r projeté tangentiellement sur la facette locale, tandis que la branche extérieure reste fixe. Mesure séparément profil azimutal et couples d’impact intérieur/extérieur.',
  'QUALIFICATION','FSI','PENDING_LOCAL_CUDA_BUILD_AND_QUALIFICATION','A','2026-09-17',NULL,NULL,
  'Premier cas courbe après x19a. Le garde runtime exige deux branches bien séparées et approximativement concentriques. Le profil u_theta(r) est comparé à la solution exacte de Couette cylindrique. Le couple est enregistré directement par action-réaction x17. La fermeture Tin+Tout et la viscosité déduite du couple sont explicitement traitées comme audit du comportement de moment angulaire du SRC courant; aucune conservation du moment angulaire bulk n’est supposée a priori. Aucun DOF solide dynamique n’est encore activé.',
  'Info/curations/0036_0493x19b_prescribed_rotating_annulus.sql',NULL
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x19b','BUILDS_ON','milestone:0493x19a','A','x19b réutilise sans changement la réponse specular/bounceback x19a et étend uniquement la cinématique prescrite à une rotation locale courbe.'
WHERE EXISTS(SELECT 1 FROM objects WHERE object_id='milestone:0493x19a');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x19b','BUILDS_ON','milestone:0493x17b','A','La géométrie reste le contour lagrangien persistant x17; aucune reconstruction chi(t) ni remapping dynamique n’est réintroduit.');
