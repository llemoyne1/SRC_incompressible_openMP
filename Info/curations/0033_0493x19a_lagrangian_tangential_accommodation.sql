-- V4.33: x19a first tangential accommodation on persistent Lagrangian walls (2026-09-16)
PRAGMA foreign_keys=ON;

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x19a','MILESTONE','x19a','curation:0033_0493x19a_lagrangian_tangential_accommodation');
INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x19a','0493x19a','x19a','0493x19a','solides mobiles / FSI',
  'Première accommodation tangentielle de la frontière lagrangienne',
  'Étend chiKineticBoundaryMode avec bounceback dans le repère local de la paroi x17. Le mode specular historique reste inchangé. Le nouveau mode inverse les composantes normale et tangentielle de la vitesse relative et restitue exactement la réaction au point d’impact.',
  'CODE','FSI','PENDING_LOCAL_CUDA_BUILD_AND_QUALIFICATION','A','2026-09-16',NULL,NULL,
  'Premier jalon volontairement sans VP lagrangiennes: il isole la transmission tangentielle d’impact. Qualification prévue par Couette plan avec plaque lagrangienne prescrite; le chantier suivant devra décider si des agrégats VP de cellules coupées sont nécessaires pour fermer le no-slip MPCD quantitatif.',
  'Info/curations/0033_0493x19a_lagrangian_tangential_accommodation.sql',NULL
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x19a','BUILDS_ON','milestone:0493x17b','A','x19a conserve le contour lagrangien persistant et son action-réaction qualifiée.');
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x19a','EXTENDS','milestone:0493x18a','A','x19a complète la loi cinétique de paroi utilisée par les solides FSI sans modifier le modèle mécanique du volet.');
